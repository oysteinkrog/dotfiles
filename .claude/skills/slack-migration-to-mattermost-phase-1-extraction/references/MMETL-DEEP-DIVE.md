# mmetl Deep Dive

Mattermost's official ETL (Extract-Transform-Load) tool for converting Slack exports into Mattermost bulk-import format. This is the critical transformation step.

GitHub: `github.com/mattermost/mmetl`

## Installation

```bash
# Auto-installed by migrate.sh setup
# Manual:
curl -sL "https://api.github.com/repos/mattermost/mmetl/releases/latest" \
  | jq -r '.assets[] | select(.name | test("linux.*amd64")) | .browser_download_url' \
  | head -1 | xargs curl -sL -o mmetl.tar.gz
tar -xzf mmetl.tar.gz
chmod +x mmetl
```

**Platform:** Linux and macOS only. mmetl is NOT supported on Windows.

## Command Reference

### Check (Validate Slack Export)
```bash
./mmetl check slack --file slack_export.zip
```
Validates the ZIP structure, checks for required files (users.json, channels.json), and reports issues.

**Exit codes:** 0 = valid, non-zero = issues found (may still be transformable).

### Transform (The Main Command)
```bash
./mmetl transform slack \
  --team myteam \
  --file slack_export.zip \
  --output mattermost_import.jsonl \
  --attachments-dir ./bulk-export-attachments
```

### All Transform Flags

| Flag | Required | Description |
|------|----------|-------------|
| `--team NAME` | yes | Target team name (must exist on MM server before import) |
| `--file PATH` | yes | Path to Slack export ZIP |
| `--output PATH` | yes | Output JSONL file path |
| `--attachments-dir PATH` | no | Directory for extracted attachments |
| `--default-email-domain DOMAIN` | no | Fallback domain for users missing emails (e.g., `company.com` → `username@company.com`) |
| `--skip-empty-emails` | no | Skip users with no email instead of failing |
| `--discard-invalid-props` | no | Drop message properties mmetl can't parse instead of failing |
| `--allow-download` | no | Allow mmetl to download files from Slack URLs during transform |

### Grid Transform (Enterprise Grid)
```bash
./mmetl grid-transform --file enterprise_grid_export.zip
```
Splits an Enterprise Grid export into separate per-workspace export ZIPs. Run `transform` on each individual workspace ZIP afterwards.

## What mmetl Transforms

### Input (Slack Format)
```
slack_export.zip
├── channels.json, groups.json, dms.json, mpims.json, users.json
├── #channel-name/YYYY-MM-DD.json (messages)
└── __uploads/ (if files included)
```

### Output (Mattermost Format)
```
mattermost_import.jsonl     # One JSON object per line
data/
└── bulk-export-attachments/ # File attachments organized by ID
    ├── file1.pdf
    ├── image2.png
    └── ...
```

## JSONL Output Structure

mmetl generates objects in this order:

1. **Version** -- `{"type":"version","version":1}`
2. **Teams** -- `{"type":"team","team":{...}}`
3. **Channels** -- `{"type":"channel","channel":{...}}`
4. **Users** -- `{"type":"user","user":{...}}`
5. **Posts** -- `{"type":"post","post":{...}}` (with replies, reactions, attachments)
6. **Direct Channels** -- `{"type":"direct_channel","direct_channel":{...}}`
7. **Direct Posts** -- `{"type":"direct_post","direct_post":{...}}`

**Ordering matters.** Teams must come before channels. Channels before posts. Users before posts that reference them.

## Transform Gotchas

### Guest User Role Conflict
mmetl sometimes generates users with both `system_user` and `system_guest` roles, which Mattermost rejects. The migrate.sh script patches this automatically:
```python
if 'guest' in roles and 'system_user' in roles:
    user['roles'] = roles.replace('system_user', '').strip()
```

### Unicode Channel Names
Non-ASCII channel names (e.g., Japanese, emoji) may be transformed into hex IDs (e.g., `c3afdb16`). No automated fix exists. Rename in Slack before exporting, or rename in Mattermost after import.

### Message Length
Slack: up to 40,000 chars per message. Mattermost default: 4,000 chars (configurable to 16,383 max).

**Before importing:** Increase `MaxPostSize` to 16383 in System Console > General > Restrictions. Messages exceeding the limit are silently truncated.

### Bot Messages
Slack bot messages have `subtype: "bot_message"` and may lack a `user` field. mmetl maps these to a "System" user. Enable `Enable Integrations to Override Usernames` in Mattermost before importing if you want bot names preserved.

### Empty Emails
Users without email addresses fail the import (Mattermost requires emails). Use:
- `--default-email-domain company.com` to auto-generate `username@company.com`
- `--skip-empty-emails` to exclude them entirely
- Pre-enrich with `slack-advanced-exporter fetch-emails` (preferred)

### File Attachment Paths
mmetl places files in `--attachments-dir` and references them in the JSONL as relative paths. The final ZIP must maintain this path structure:
```
mattermost-bulk-import.zip
├── mattermost_import.jsonl
└── data/
    └── bulk-export-attachments/
        ├── file1.pdf
        └── ...
```

### Nil Pointer Panics
mmetl is a Go binary. Unexpected JSON structures can cause nil pointer dereferences:
- **Cause:** Corrupted ZIP, hand-modified JSON, or unsupported Slack features
- **Fix:** Don't unzip/rezip the Slack export. Use a fresh export. Update mmetl.

## Debugging Transform Failures

### Step 1: Validate Input
```bash
./mmetl check slack --file export.zip 2>&1
unzip -l export.zip | head -20   # Check ZIP structure
```

### Step 2: Examine Users
```bash
# Check for empty emails
unzip -p export.zip users.json | jq '[.[] | select(.profile.email == "" or .profile.email == null)] | length'

# Check for guest users
unzip -p export.zip users.json | jq '[.[] | select(.is_restricted or .is_ultra_restricted)] | length'
```

### Step 3: Check Message Count
```bash
# Count total messages across all channels
unzip -p export.zip '*/????-??-??.json' | jq -s 'map(length) | add'
```

### Step 4: Try With Relaxed Flags
```bash
./mmetl transform slack \
  --team myteam \
  --file export.zip \
  --output output.jsonl \
  --default-email-domain company.com \
  --skip-empty-emails \
  --discard-invalid-props \
  2>&1 | tee mmetl_debug.log
```

### Step 5: Validate Output
```bash
# Count output objects
wc -l output.jsonl
grep -c '"type":"user"' output.jsonl
grep -c '"type":"channel"' output.jsonl
grep -c '"type":"post"' output.jsonl

# Check for malformed JSON
python3 -c "
import json, sys
for i, line in enumerate(open('output.jsonl'), 1):
    try: json.loads(line)
    except: print(f'Line {i}: {line[:100]}')
"
```

## Post-Transform Patching

After mmetl produces the JSONL, you may need to patch it:

### Inject Custom Emoji
Emoji objects must appear AFTER version and BEFORE team objects:
```bash
# Create emoji JSONL entries
for f in emoji/*.png; do
  name=$(basename "$f" .png | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/_/g')
  echo "{\"type\":\"emoji\",\"emoji\":{\"name\":\"$name\",\"image\":\"data/emoji/$name.png\"}}"
done > emoji_lines.jsonl

# Insert after version line (line 1)
head -1 mattermost_import.jsonl > patched.jsonl
cat emoji_lines.jsonl >> patched.jsonl
tail -n +2 mattermost_import.jsonl >> patched.jsonl
mv patched.jsonl mattermost_import.jsonl
```

### Create Archive Channels for Slack-Native Artifacts
```bash
# Add a channel for canvas archives
echo '{"type":"channel","channel":{"team":"myteam","name":"slack-canvases-archive","display_name":"Slack Canvases Archive","type":"P","header":"Archived Slack canvases"}}' >> mattermost_import.jsonl
```

### Truncate Oversized Messages
```bash
python3 -c "
import json, sys
max_len = 16383
for line in open(sys.argv[1]):
    obj = json.loads(line.strip())
    if obj.get('type') in ('post', 'direct_post'):
        key = 'post' if obj['type'] == 'post' else 'direct_post'
        msg = obj[key].get('message', '')
        if len(msg) > max_len:
            obj[key]['message'] = msg[:max_len-50] + '\n\n[Message truncated from ' + str(len(msg)) + ' chars]'
    print(json.dumps(obj))
" mattermost_import.jsonl > truncated.jsonl
mv truncated.jsonl mattermost_import.jsonl
```
