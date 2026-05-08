# Verification Cookbook

Scripts, sampling strategies, and reconciliation procedures for proving your extraction is complete and correct.

## The Verification Philosophy

Never trust tool output alone. Verify at every stage boundary:
- **After export:** Is the ZIP structurally valid? Does it contain expected data?
- **After enrichment:** Were all files downloaded? Are emails populated?
- **After transform:** Does JSONL have correct counts? Is it well-formed?
- **After packaging:** Does the ZIP structure match what Mattermost expects?

## Stage 1: Export Verification

### Verify Export ZIP Structure
```bash
# Check ZIP integrity
unzip -t slack_export.zip | tail -5

# List top-level contents
unzip -l slack_export.zip | head -30

# Verify required files exist
for f in users.json channels.json; do
  unzip -l slack_export.zip | grep -q "$f" \
    && echo "OK: $f found" \
    || echo "MISSING: $f"
done

# Count channels in export
unzip -p slack_export.zip channels.json | jq 'length'

# Count users in export
unzip -p slack_export.zip users.json | jq 'length'

# Count total message files
unzip -l slack_export.zip | grep '\.json$' | grep -v 'channels\|users\|groups\|dms\|mpims\|integration' | wc -l
```

### Verify Against Channel Audit CSV
The channel audit CSV is available from the same Slack admin export page (Business+/Enterprise). It contains channel name, ID, member count, message count, creation date, and last activity -- making it the authoritative cross-reference for verifying export completeness.

**How to get it:** Slack Admin > Tools & Settings > Workspace Settings > Import/Export Data > same page as the data export. Look for "Download channel audit report" or similar.

```bash
# Compare channel counts
csv_channels=$(tail -n +2 channel_audit.csv | wc -l)
export_channels=$(unzip -p slack_export.zip channels.json | jq 'length')
echo "Audit CSV: $csv_channels channels"
echo "Export ZIP: $export_channels channels"

# Compare specific channels -- find any in CSV but missing from export
python3 -c "
import csv, json, zipfile, sys

# Load channels from export
with zipfile.ZipFile('slack_export.zip') as z:
    channels_export = {c['name'] for c in json.loads(z.read('channels.json'))}

# Load channels from audit CSV
channels_csv = set()
with open('channel_audit.csv') as f:
    for row in csv.DictReader(f):
        name = row.get('name', row.get('Channel Name', ''))
        if name: channels_csv.add(name)

missing = channels_csv - channels_export
extra = channels_export - channels_csv
if missing:
    print(f'MISSING from export ({len(missing)}): {sorted(missing)[:10]}')
if extra:
    print(f'Extra in export ({len(extra)}): {sorted(extra)[:10]}')
if not missing and not extra:
    print('OK: Channel lists match')
"

# Compare member counts per channel (deeper verification)
python3 -c "
import csv, json, zipfile
with zipfile.ZipFile('slack_export.zip') as z:
    export_channels = {c['name']: len(c.get('members', [])) for c in json.loads(z.read('channels.json'))}
with open('channel_audit.csv') as f:
    for row in csv.DictReader(f):
        name = row.get('name', '')
        csv_members = int(row.get('num_members', row.get('Members', 0)))
        export_members = export_channels.get(name, -1)
        if export_members >= 0 and abs(csv_members - export_members) > 2:
            print(f'  MISMATCH #{name}: CSV={csv_members} Export={export_members}')
"
```

### Verify Date Range Coverage
```bash
# Find oldest and newest messages
unzip -l slack_export.zip | grep -oP '\d{4}-\d{2}-\d{2}' | sort | head -1  # Oldest
unzip -l slack_export.zip | grep -oP '\d{4}-\d{2}-\d{2}' | sort | tail -1  # Newest
```

## Stage 2: Enrichment Verification

### Email Population Check
```bash
# Count users with and without emails
unzip -p export-with-emails.zip users.json | python3 -c "
import json, sys
users = json.load(sys.stdin)
with_email = sum(1 for u in users if u.get('profile', {}).get('email'))
without_email = sum(1 for u in users if not u.get('profile', {}).get('email'))
total = len(users)
bots = sum(1 for u in users if u.get('is_bot'))
print(f'Total users: {total}')
print(f'With email: {with_email} ({100*with_email//total}%)')
print(f'Without email: {without_email}')
print(f'Bots (no email expected): {bots}')
print(f'Human users without email: {without_email - bots}')
"
```
**Target:** > 95% of non-bot users should have emails after enrichment.

### File Attachment Completeness
```bash
# Count file references in messages
total_refs=$(unzip -p export-with-files.zip '*/????-??-??.json' 2>/dev/null \
  | jq -r '.. | .url_private? // empty' 2>/dev/null | grep -c 'https://')

# Count downloaded files
downloaded=$(unzip -l export-with-files.zip | grep '__uploads/' | grep -v '/$' | wc -l)

echo "File references in messages: $total_refs"
echo "Files actually downloaded: $downloaded"
echo "Coverage: $((downloaded * 100 / (total_refs + 1)))%"
```

### Emoji Verification
```bash
# Count emoji downloaded
emoji_count=$(ls workdir/emoji/*.{png,gif,jpg,jpeg} 2>/dev/null | wc -l)

# Count emoji from API
api_count=$(curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/emoji.list" | jq '.emoji | length')

echo "Downloaded: $emoji_count"
echo "API reports: $api_count"
# api_count includes aliases; downloaded should be less
```

## Stage 3: Transform Verification

### JSONL Health Check
```bash
# Count all object types
python3 -c "
import json, sys
from collections import Counter
counts = Counter()
errors = 0
for i, line in enumerate(open(sys.argv[1]), 1):
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        counts[obj.get('type', 'UNKNOWN')] += 1
    except json.JSONDecodeError:
        errors += 1
        if errors <= 5: print(f'  JSON error on line {i}')

print('Object counts:')
for t, c in sorted(counts.items()):
    print(f'  {t}: {c}')
if errors: print(f'  JSON errors: {errors}')
print(f'Total lines: {sum(counts.values())}')
" mattermost_import.jsonl
```

### Cross-Reference Checks
```bash
# Verify all post users exist as user objects
python3 -c "
import json, sys
users = set()
missing_users = set()
for line in open(sys.argv[1]):
    obj = json.loads(line.strip())
    if obj['type'] == 'user':
        users.add(obj['user']['username'])
    elif obj['type'] == 'post':
        u = obj['post'].get('user', '')
        if u and u not in users:
            missing_users.add(u)

if missing_users:
    print(f'WARNING: {len(missing_users)} users referenced in posts but not defined:')
    for u in sorted(missing_users)[:10]:
        print(f'  {u}')
else:
    print('OK: All post users exist as user objects')
" mattermost_import.jsonl

# Verify all post channels exist as channel objects
python3 -c "
import json, sys
channels = set()
missing = set()
for line in open(sys.argv[1]):
    obj = json.loads(line.strip())
    if obj['type'] == 'channel':
        channels.add(obj['channel']['name'])
    elif obj['type'] == 'post':
        ch = obj['post'].get('channel', '')
        if ch and ch not in channels:
            missing.add(ch)

if missing:
    print(f'WARNING: {len(missing)} channels referenced but not defined:')
    for c in sorted(missing)[:10]:
        print(f'  {c}')
else:
    print('OK: All post channels exist as channel objects')
" mattermost_import.jsonl
```

### Message Integrity Sampling
```bash
# Sample 5 random channels, count messages, compare to Slack export
python3 -c "
import json, sys, random, glob

# Count messages per channel in JSONL
jsonl_counts = {}
for line in open(sys.argv[1]):
    obj = json.loads(line.strip())
    if obj['type'] == 'post':
        ch = obj['post']['channel']
        jsonl_counts[ch] = jsonl_counts.get(ch, 0) + 1

# Sample 5 channels
sample = random.sample(list(jsonl_counts.keys()), min(5, len(jsonl_counts)))
print('Channel message count sample:')
for ch in sample:
    print(f'  #{ch}: {jsonl_counts[ch]} posts')
print(f'Total channels with posts: {len(jsonl_counts)}')
print(f'Total posts: {sum(jsonl_counts.values())}')
" mattermost_import.jsonl
```

## Stage 4: Package Verification

### ZIP Structure Check
```bash
# Verify the import ZIP has the right structure
unzip -l mattermost-bulk-import.zip | head -20

# Must contain:
unzip -l mattermost-bulk-import.zip | grep -q 'mattermost_import.jsonl' \
  && echo "OK: JSONL found" || echo "MISSING: mattermost_import.jsonl"

unzip -l mattermost-bulk-import.zip | grep -q 'data/bulk-export-attachments/' \
  && echo "OK: Attachments dir found" || echo "INFO: No attachments directory"

# Count files
echo "Total files in ZIP: $(unzip -l mattermost-bulk-import.zip | grep -c '^\s')"
echo "ZIP size: $(du -sh mattermost-bulk-import.zip | cut -f1)"
```

### mmctl Validate
```bash
mmctl import validate ./mattermost-bulk-import.zip
# Exit code 0 = valid
# Non-zero = check output for specific errors
```

## Reconciliation Report Template

Run this after all stages to produce a summary:

```bash
#!/bin/bash
echo "=== SLACK MIGRATION VERIFICATION REPORT ==="
echo "Date: $(date)"
echo ""
echo "--- SOURCE (Slack) ---"
echo "Export ZIP: $(du -sh slack_export.zip | cut -f1)"
echo "Users: $(unzip -p slack_export.zip users.json | jq 'length')"
echo "Public channels: $(unzip -p slack_export.zip channels.json | jq 'length')"
echo "Private channels: $(unzip -p slack_export.zip groups.json 2>/dev/null | jq 'length' 2>/dev/null || echo 'N/A')"
echo "DMs: $(unzip -p slack_export.zip dms.json 2>/dev/null | jq 'length' 2>/dev/null || echo 'N/A')"
echo ""
echo "--- OUTPUT (Mattermost JSONL) ---"
echo "Users: $(grep -c '"type":"user"' mattermost_import.jsonl)"
echo "Channels: $(grep -c '"type":"channel"' mattermost_import.jsonl)"
echo "Posts: $(grep -c '"type":"post"' mattermost_import.jsonl)"
echo "Direct channels: $(grep -c '"type":"direct_channel"' mattermost_import.jsonl)"
echo "Direct posts: $(grep -c '"type":"direct_post"' mattermost_import.jsonl)"
echo "Emoji: $(grep -c '"type":"emoji"' mattermost_import.jsonl)"
echo ""
echo "--- PACKAGE ---"
echo "Import ZIP: $(du -sh mattermost-bulk-import.zip | cut -f1)"
echo "mmctl validate: $(mmctl import validate ./mattermost-bulk-import.zip 2>&1 | tail -1)"
echo ""
echo "=== END REPORT ==="
```
