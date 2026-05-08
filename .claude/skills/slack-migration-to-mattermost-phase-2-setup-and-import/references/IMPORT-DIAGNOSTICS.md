# Import Diagnostics

## Job Monitoring

### Check Import Job Status

```bash
# List all import jobs (most recent first)
mmctl import job list --json 2>/dev/null | python3 -m json.tool

# Watch import progress in real time
watch -n 10 'mmctl import job list --json 2>/dev/null | python3 -c "
import json, sys
jobs = json.load(sys.stdin)
for j in jobs[:3]:
    status = j.get(\"status\", \"unknown\")
    progress = j.get(\"progress\", 0)
    job_id = j.get(\"id\", \"?\")[:12]
    data = j.get(\"data\", {})
    err = data.get(\"error\", \"\")
    line = data.get(\"line_number\", \"\")
    print(f\"{job_id}  status={status}  progress={progress}  error={err}  line={line}\")
"'
```

### Parse Job Details

```bash
# Get full details of the most recent import job
mmctl import job list --json 2>/dev/null | python3 -c "
import json, sys
jobs = json.load(sys.stdin)
if not jobs:
    print('No import jobs found')
    sys.exit(0)
j = jobs[0]
print(f'Job ID:      {j.get(\"id\")}')
print(f'Status:      {j.get(\"status\")}')
print(f'Progress:    {j.get(\"progress\")}')
print(f'Create at:   {j.get(\"create_at\")}')
print(f'Start at:    {j.get(\"start_at\")}')
print(f'Last act at: {j.get(\"last_activity_at\")}')
data = j.get('data', {})
for k, v in data.items():
    print(f'  data.{k}: {v}')
"
```

## Common Import Failures

### 1. Job Stuck in `in_progress`

**Symptoms**: Job shows `in_progress` for hours with no progress change.

**Diagnosis**:

```bash
# Check if Mattermost process is alive and consuming CPU
ps aux | grep mattermost | grep -v grep
top -bn1 | grep mattermost

# Check server logs for errors
sudo tail -200 /opt/mattermost/logs/mattermost.log | grep -i -E "error|panic|fatal"

# Docker variant
docker logs mattermost --tail 200 2>&1 | grep -i -E "error|panic|fatal"

# Check disk space (imports expand significantly)
df -h /opt/mattermost
df -h /tmp

# Check available memory
free -h

# Check PostgreSQL connections
sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_activity WHERE datname = 'mattermost';"
```

**Fixes**:
- If disk full: free space (see section below), restart Mattermost, re-import
- If OOM killed: increase server RAM or tune PostgreSQL (see section below)
- If truly stuck: restart Mattermost (`sudo systemctl restart mattermost`), the job will fail and you can retry

### 2. "could not count users" / Email Conflicts

**Symptoms**: Import fails with `BulkImport: could not count users` or similar user-related error.

**Diagnosis**:

```bash
# Check for duplicate emails in the import JSONL
# (Run this against the unzipped import directory)
grep '"type":"user"' data/import.jsonl | python3 -c "
import json, sys
from collections import Counter
emails = []
for line in sys.stdin:
    obj = json.loads(line)
    if 'user' in obj:
        emails.append(obj['user'].get('email', ''))
dupes = {e: c for e, c in Counter(emails).items() if c > 1}
if dupes:
    print('DUPLICATE EMAILS:')
    for e, c in dupes.items():
        print(f'  {e}: {c} times')
else:
    print('No duplicate emails found')
"

# Check if imported emails conflict with existing Mattermost users
mmctl user list --all --json 2>/dev/null | python3 -c "
import json, sys
users = json.load(sys.stdin)
for u in users:
    print(u.get('email', ''))
" | sort > /tmp/existing_emails.txt

grep '"type":"user"' data/import.jsonl | python3 -c "
import json, sys
for line in sys.stdin:
    obj = json.loads(line)
    if 'user' in obj:
        print(obj['user'].get('email', ''))
" | sort > /tmp/import_emails.txt

comm -12 /tmp/existing_emails.txt /tmp/import_emails.txt
# Any output = conflicting emails
```

**Fixes**:
- Remove duplicate emails in the Phase 1 transform
- For conflicts with existing users: the import will merge if `username` matches, otherwise fail
- Pre-create users with matching emails before import, or deactivate conflicting accounts

### 3. "User roles not consistent" / Guest Role Conflicts

**Symptoms**: Import fails mentioning role validation.

**Diagnosis**:

```bash
# Find users with guest roles in the import
grep '"type":"user"' data/import.jsonl | python3 -c "
import json, sys
for line in sys.stdin:
    obj = json.loads(line)
    if 'user' in obj:
        roles = obj['user'].get('roles', '')
        if 'guest' in roles.lower():
            print(f'{obj[\"user\"].get(\"username\")}: {roles}')
"
```

**Fix**: Mattermost guest accounts require the Guest feature to be enabled. Either:
- Enable Guest Access: `mmctl config set GuestAccountsSettings.Enable true`
- Or change guest roles to `system_user` in the Phase 1 transform

### 4. Disk Full During Import

**Symptoms**: Import fails, `df -h` shows 95%+ usage.

**How much space do you need?**

| Export ZIP Size | Required Free Space | Why |
|----------------|-------------------|-----|
| 1 GB | 4 GB | ZIP extraction + DB temp tables + WAL |
| 5 GB | 15-20 GB | Same, scaled up |
| 20 GB | 60-80 GB | PostgreSQL needs significant temp space |

**Emergency cleanup**:

```bash
# Check what's consuming space
du -sh /opt/mattermost/data/*
du -sh /opt/mattermost/logs/*
du -sh /var/lib/postgresql/

# Clear old Mattermost logs
sudo truncate -s 0 /opt/mattermost/logs/mattermost.log

# Remove previous import uploads (if retrying)
ls -la /opt/mattermost/data/import/
rm -f /opt/mattermost/data/import/old-import-*.zip

# Clear PostgreSQL WAL if it has grown (careful!)
sudo -u postgres psql -c "SELECT pg_size_pretty(sum(size)) FROM pg_ls_waldir();"

# Expand disk if on cloud (DigitalOcean, Hetzner, etc.)
# This is often faster than trying to free space
```

### 5. Out of Memory (OOM)

**Symptoms**: Mattermost process killed, `dmesg | grep -i oom` shows OOM killer activity.

**Diagnosis**:

```bash
dmesg | grep -i "out of memory" | tail -5
dmesg | grep -i "killed process" | tail -5
journalctl -u mattermost --since "1 hour ago" | grep -i -E "killed|signal|oom"
```

**Fixes**:

```bash
# Increase PostgreSQL shared_buffers and work_mem for large imports
sudo -u postgres psql -c "SHOW shared_buffers;"
sudo -u postgres psql -c "SHOW work_mem;"

# For 1000+ user imports, recommended minimums:
# shared_buffers = 2GB (in postgresql.conf)
# work_mem = 256MB
# maintenance_work_mem = 512MB
# effective_cache_size = 4GB

# Edit /etc/postgresql/16/main/postgresql.conf, then:
sudo systemctl restart postgresql

# Also consider adding swap if not present:
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
```

**Server sizing for imports:**

| Users | Messages | Minimum RAM | Recommended RAM |
|-------|----------|-------------|-----------------|
| < 100 | < 100K | 4 GB | 4 GB |
| 100-500 | 100K-1M | 4 GB | 8 GB |
| 500-1000 | 1M-5M | 8 GB | 16 GB |
| 1000+ | 5M+ | 16 GB | 32 GB |

### 6. Import Timeout / Takes Forever

**Symptoms**: Import running for hours with slow progress.

**Context**: Large imports (>500K messages) routinely take 2-8 hours. This may be normal.

**Diagnosis**:

```bash
# Check if progress is actually advancing (run twice, 5 minutes apart)
mmctl import job list --json 2>/dev/null | python3 -c "
import json, sys
j = json.load(sys.stdin)[0]
print(f'Progress: {j.get(\"progress\")} Last activity: {j.get(\"last_activity_at\")}')
"

# Check PostgreSQL activity during import
sudo -u postgres psql -d mattermost -c "
SELECT pid, state, wait_event_type, wait_event,
       left(query, 80) as query_preview
FROM pg_stat_activity
WHERE datname = 'mattermost' AND state != 'idle'
ORDER BY backend_start;
"
```

**Optimizations for faster imports**:
- Use SSD storage (not HDD)
- Increase `maintenance_work_mem` to 1GB during import
- Disable full-text search indexing during import, re-enable after
- Use R2/S3 for file storage (parallel uploads)
- If possible, run import during off-hours to avoid resource contention

## Log Locations

```bash
# Bare metal / APT install
/opt/mattermost/logs/mattermost.log
/opt/mattermost/logs/notification.log

# Docker
docker logs mattermost 2>&1
docker logs mattermost 2>&1 | tail -500

# Docker Compose
docker compose logs mattermost --tail 500

# Nginx (if relevant)
/var/log/nginx/access.log
/var/log/nginx/error.log

# PostgreSQL
/var/log/postgresql/postgresql-16-main.log

# systemd journal
journalctl -u mattermost --since "2 hours ago" --no-pager
```

### Filtering Logs for Import Issues

```bash
# All import-related log lines
grep -i "import" /opt/mattermost/logs/mattermost.log | tail -100

# Errors only
grep -i "error" /opt/mattermost/logs/mattermost.log | grep -i "import" | tail -50

# Bulk import specific
grep -i "bulkimport" /opt/mattermost/logs/mattermost.log | tail -50
```

## Database-Level Diagnostics

### Check Table Counts After Import

```bash
sudo -u postgres psql -d mattermost -c "
SELECT 'Users' as table_name, count(*) as row_count FROM users
UNION ALL SELECT 'Channels', count(*) FROM channels
UNION ALL SELECT 'Posts', count(*) FROM posts
UNION ALL SELECT 'ChannelMembers', count(*) FROM channelmembers
UNION ALL SELECT 'TeamMembers', count(*) FROM teammembers
UNION ALL SELECT 'Reactions', count(*) FROM reactions
UNION ALL SELECT 'FileInfo', count(*) FROM fileinfo
UNION ALL SELECT 'Emoji', count(*) FROM emoji
ORDER BY table_name;
"
```

### Verify Specific Data

```bash
# Check if a specific user was imported
sudo -u postgres psql -d mattermost -c "
SELECT id, username, email, roles, deleteat
FROM users WHERE email = 'someone@company.com';
"

# Check channel message counts
sudo -u postgres psql -d mattermost -c "
SELECT c.name, c.displayname, c.type, count(p.id) as post_count
FROM channels c
LEFT JOIN posts p ON p.channelid = c.id
GROUP BY c.id, c.name, c.displayname, c.type
ORDER BY post_count DESC
LIMIT 20;
"

# Check for orphaned posts (posts without valid channels)
sudo -u postgres psql -d mattermost -c "
SELECT count(*) as orphaned_posts
FROM posts p
LEFT JOIN channels c ON p.channelid = c.id
WHERE c.id IS NULL;
"
```

## JSONL Validation (Pre-Import)

Validate the import file before uploading to catch obvious errors:

```bash
# Check JSONL is valid JSON on every line
python3 -c "
import json, sys
errors = []
with open('data/import.jsonl') as f:
    for i, line in enumerate(f, 1):
        try:
            json.loads(line)
        except json.JSONDecodeError as e:
            errors.append(f'Line {i}: {e}')
            if len(errors) > 20:
                break
if errors:
    print(f'Found {len(errors)} JSON errors:')
    for e in errors:
        print(f'  {e}')
else:
    print('All lines are valid JSON')
"

# Check record type distribution
python3 -c "
import json
from collections import Counter
types = Counter()
with open('data/import.jsonl') as f:
    for line in f:
        obj = json.loads(line)
        types[obj.get('type', 'unknown')] += 1
for t, c in types.most_common():
    print(f'  {t}: {c}')
"

# Verify required ordering (version > scheme > team > channel > user > post)
python3 -c "
import json

ORDER = ['version', 'scheme', 'team', 'channel', 'user', 'post', 'direct_channel', 'direct_post', 'emoji']
last_idx = -1
violations = []

with open('data/import.jsonl') as f:
    for line_num, line in enumerate(f, 1):
        obj = json.loads(line)
        t = obj.get('type', '')
        if t in ORDER:
            idx = ORDER.index(t)
            if idx < last_idx:
                violations.append(f'Line {line_num}: {t} appears after {ORDER[last_idx]}')
                if len(violations) > 10:
                    break
            last_idx = max(last_idx, idx)

if violations:
    print('ORDERING VIOLATIONS (import may fail):')
    for v in violations:
        print(f'  {v}')
else:
    print('Record ordering is correct')
"
```

## Import Retry Strategy

Mattermost bulk import is **idempotent** -- it is safe to retry:

- Existing users with matching emails/usernames are updated, not duplicated
- Existing channels with matching names are updated
- Existing posts are matched by timestamp + user + channel (usually)
- File attachments already uploaded are skipped

```bash
# Simply re-run the same import
mmctl import process <same-import-filename>

# Monitor the new job
mmctl import job list
```

**When to retry vs. fix and re-import:**
- Network timeout / server restart mid-import: **retry** the same file
- Data error (bad JSON, missing user, role conflict): **fix** Phase 1 output, re-export, re-upload, re-import

## Pre-Import Validation Checklist

Run through before every import attempt:

- [ ] JSONL passes validation (valid JSON, correct ordering)
- [ ] No duplicate emails in user records
- [ ] All post authors exist in user records
- [ ] All post channels exist in channel records
- [ ] Disk space is 3x the ZIP size
- [ ] PostgreSQL has adequate RAM (see sizing table above)
- [ ] Mattermost service is running and healthy (`mmctl system status`)
- [ ] No other import jobs currently running
- [ ] Server logs are not showing pre-existing errors
- [ ] Backup of existing database taken (if importing to non-empty instance)
