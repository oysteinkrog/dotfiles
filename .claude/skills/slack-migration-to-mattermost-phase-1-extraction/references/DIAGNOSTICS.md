# Diagnostics Scripts & Health Checks

Copy-paste diagnostic commands for every failure scenario. Organized by pipeline stage.

## Pre-Flight Diagnostics

### System Readiness
```bash
# Check all dependencies
for cmd in curl jq zip unzip tar python3; do
  command -v "$cmd" &>/dev/null \
    && echo "OK: $cmd ($(command -v $cmd))" \
    || echo "MISSING: $cmd -- install with: sudo apt-get install -y $cmd"
done

# Disk space (need 3x export size)
df -h . | tail -1 | awk '{print "Available disk:", $4}'

# Check ulimits (important for large exports)
echo "Open files limit: $(ulimit -n)"
[[ $(ulimit -n) -lt 4096 ]] && echo "WARNING: Consider raising ulimit -n to 4096+"
```

### Token Validation
```bash
# Verify Slack token
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/auth.test" | jq '{ok, user, team, url}'

# Check token scopes
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/auth.test" -D - 2>/dev/null \
  | grep -i 'x-oauth-scopes'
```

### Mattermost Server Reachability
```bash
# Check server is up
curl -s "${MATTERMOST_URL}/api/v4/system/ping" | jq '.'
# Should return: {"status":"OK"}

# Check mmctl auth
mmctl auth login "${MATTERMOST_URL}" \
  --name migration \
  --username "${MATTERMOST_ADMIN_USER}" \
  --password "${MATTERMOST_ADMIN_PASS}"
mmctl system version
```

## Export Diagnostics

### Slackdump Health
```bash
# Version check
./tools/slackdump version

# Auth test
./tools/slackdump auth test

# List channels (smoke test)
./tools/slackdump list 2>&1 | head -20
```

### Export ZIP Integrity
```bash
# Test ZIP isn't corrupt
unzip -t slack_export.zip 2>&1 | tail -3

# Check size is reasonable
ls -lh slack_export.zip

# Peek at contents
unzip -l slack_export.zip | wc -l   # Total entries
unzip -l slack_export.zip | grep 'users.json'
unzip -l slack_export.zip | grep 'channels.json'

# Quick user count
unzip -p slack_export.zip users.json | jq 'length'

# Quick channel count
unzip -p slack_export.zip channels.json | jq 'length'
```

### Export Completeness Fingerprint
```bash
# Generate a fingerprint of the export for comparison
echo "=== EXPORT FINGERPRINT ==="
echo "SHA256: $(sha256sum slack_export.zip | cut -d' ' -f1)"
echo "Size: $(stat --format=%s slack_export.zip) bytes"
echo "Users: $(unzip -p slack_export.zip users.json | jq 'length')"
echo "Channels: $(unzip -p slack_export.zip channels.json | jq 'length')"
echo "Private groups: $(unzip -p slack_export.zip groups.json 2>/dev/null | jq 'length' 2>/dev/null || echo 0)"
echo "DMs: $(unzip -p slack_export.zip dms.json 2>/dev/null | jq 'length' 2>/dev/null || echo 0)"
echo "Group DMs: $(unzip -p slack_export.zip mpims.json 2>/dev/null | jq 'length' 2>/dev/null || echo 0)"
echo "Date files: $(unzip -l slack_export.zip | grep -cP '\d{4}-\d{2}-\d{2}\.json')"
echo "========================="
```

## Enrichment Diagnostics

### slack-advanced-exporter Status
```bash
# Check if emails were added
diff <(unzip -p raw-export.zip users.json | jq -r '.[].profile.email // "EMPTY"' | sort) \
     <(unzip -p export-with-emails.zip users.json | jq -r '.[].profile.email // "EMPTY"' | sort) \
  | head -20

# Count new emails added
before=$(unzip -p raw-export.zip users.json | jq '[.[] | select(.profile.email != null and .profile.email != "")] | length')
after=$(unzip -p export-with-emails.zip users.json | jq '[.[] | select(.profile.email != null and .profile.email != "")] | length')
echo "Emails before: $before, after: $after, added: $((after - before))"
```

### File Download Diagnostics
```bash
# Check for failed downloads (0-byte files)
find workdir/ -name "*.pdf" -o -name "*.png" -o -name "*.jpg" -o -name "*.gif" 2>/dev/null \
  | while read f; do
    [[ ! -s "$f" ]] && echo "EMPTY FILE: $f"
  done

# Count files by type
echo "Files by extension:"
find workdir/__uploads/ -type f 2>/dev/null | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -10
```

### Emoji Download Diagnostics
```bash
# Verify emoji files aren't HTML error pages
for f in workdir/emoji/*.{png,gif,jpg,jpeg} 2>/dev/null; do
  [[ ! -f "$f" ]] && continue
  mime=$(file -b --mime-type "$f")
  case "$mime" in
    image/*) ;;  # Good
    text/html) echo "BAD (HTML error page): $f" ;;
    *) echo "UNEXPECTED ($mime): $f" ;;
  esac
done
```

## Transform Diagnostics

### mmetl Debug Output
```bash
# Run transform with verbose output
./tools/mmetl transform slack \
  --team "${MATTERMOST_TEAM_NAME}" \
  --file export-with-files.zip \
  --output mattermost_import.jsonl \
  --default-email-domain "${DEFAULT_DOMAIN:-company.com}" \
  --skip-empty-emails \
  --discard-invalid-props \
  2>&1 | tee mmetl_debug.log

# Check for errors in the log
grep -i "error\|panic\|fatal\|warning" mmetl_debug.log
```

### JSONL Structural Validation
```bash
python3 << 'VALIDATE'
import json, sys

errors = []
types_order = ['version', 'emoji', 'team', 'channel', 'user', 'post', 'direct_channel', 'direct_post']
last_type_idx = -1
line_count = 0

with open("mattermost_import.jsonl") as f:
    for i, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            continue
        line_count += 1
        try:
            obj = json.loads(line)
            t = obj.get('type', '')
            if t in types_order:
                idx = types_order.index(t)
                # Allow same type, warn on backward
                if idx < last_type_idx:
                    errors.append(f"Line {i}: {t} appears after {types_order[last_type_idx]} (ordering violation)")
                last_type_idx = max(last_type_idx, idx)
            else:
                errors.append(f"Line {i}: Unknown type '{t}'")
        except json.JSONDecodeError as e:
            errors.append(f"Line {i}: JSON parse error: {e}")

if errors:
    print(f"ERRORS ({len(errors)}):")
    for e in errors[:20]:
        print(f"  {e}")
else:
    print(f"OK: {line_count} lines, no structural errors")
VALIDATE
```

### Guest Role Audit
```bash
python3 -c "
import json
guests = []
for line in open('mattermost_import.jsonl'):
    obj = json.loads(line.strip())
    if obj.get('type') != 'user': continue
    u = obj['user']
    roles = u.get('roles', '')
    if 'guest' in roles:
        conflict = 'system_user' in roles
        guests.append((u['username'], roles, conflict))

print(f'Guest users: {len(guests)}')
conflicts = [g for g in guests if g[2]]
if conflicts:
    print(f'CONFLICT (guest + system_user): {len(conflicts)}')
    for g in conflicts[:5]:
        print(f'  {g[0]}: {g[1]}')
else:
    print('OK: No role conflicts')
"
```

### Long Message Audit
```bash
python3 -c "
import json
long = []
for line in open('mattermost_import.jsonl'):
    obj = json.loads(line.strip())
    for key in ('post', 'direct_post'):
        if obj.get('type') == key.replace('_', '_'):
            msg = obj.get(key, {}).get('message', '')
            if len(msg) > 16383:
                ch = obj.get(key, {}).get('channel', 'DM')
                long.append((ch, len(msg)))

if long:
    print(f'Messages exceeding 16383 chars: {len(long)}')
    for ch, l in sorted(long, key=lambda x: -x[1])[:10]:
        print(f'  #{ch}: {l} chars')
    print('ACTION: Increase MaxPostSize to 16383 in Mattermost System Console')
else:
    print('OK: No messages exceed 16383 chars')
"
```

## Package Diagnostics

### Import ZIP Structure
```bash
# Verify exact expected structure
echo "=== ZIP STRUCTURE CHECK ==="
unzip -l mattermost-bulk-import.zip | grep 'mattermost_import.jsonl' && echo "OK: JSONL present" || echo "FAIL: No JSONL"
unzip -l mattermost-bulk-import.zip | grep 'data/' && echo "OK: data/ present" || echo "INFO: No data/ dir"

# Check for common packaging errors
unzip -l mattermost-bulk-import.zip | grep -q 'workdir/' && echo "WARNING: workdir/ prefix in paths -- may cause import errors"
unzip -l mattermost-bulk-import.zip | grep -q '__MACOSX' && echo "WARNING: macOS resource fork files in ZIP"
```

## One-Shot Full Diagnostic
```bash
#!/bin/bash
# Run this to get a complete health snapshot
echo "=== FULL MIGRATION DIAGNOSTIC ==="
echo "Time: $(date -Iseconds)"
echo ""

echo "--- TOOLS ---"
for tool in slackdump mmetl mmctl; do
  [[ -x "tools/$tool" ]] && echo "OK: $tool" || echo "MISSING: $tool"
done

echo ""
echo "--- FILES ---"
for f in config.env workdir/slack_export.zip workdir/mattermost_import.jsonl workdir/mattermost-bulk-import.zip; do
  [[ -f "$f" ]] && echo "OK: $f ($(du -sh "$f" | cut -f1))" || echo "NOT YET: $f"
done

echo ""
echo "--- TOKENS ---"
[[ -n "$SLACK_TOKEN" ]] && echo "OK: SLACK_TOKEN set" || echo "NOT SET: SLACK_TOKEN"
[[ -n "$SLACK_COOKIE" ]] && echo "OK: SLACK_COOKIE set" || echo "NOT SET: SLACK_COOKIE"

echo ""
echo "--- DISK ---"
df -h . | tail -1 | awk '{print "Available:", $4, "Used:", $3}'

echo ""
echo "=== END DIAGNOSTIC ==="
```
