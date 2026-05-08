# Staging Workflow for Mattermost Migration

## Why Stage First

Mattermost explicitly recommends importing to a staging environment before production.
Large migrations typically require 2-5 iterations to get right. Issues you will catch
in staging:

- Missing or malformed channel mappings
- User email conflicts with existing accounts
- Thread parent/reply integrity problems
- File attachment path mismatches
- Custom emoji that failed to upload
- DM conversations that mapped to the wrong users
- Bot messages that lost attribution
- Unicode/encoding edge cases in message text

**Rule: Never import directly to production on the first attempt.**

## Option A: Quick Staging with Docker

Fastest way to get a throwaway Mattermost instance for testing imports.

### Prerequisites

```bash
# Docker must be installed
docker --version

# Pull the preview image (includes PostgreSQL built-in)
docker pull mattermost/mattermost-preview
```

### Start Staging Instance

```bash
docker run -d \
  --name mattermost-staging \
  -p 8065:8065 \
  -v mattermost-staging-data:/mm/mattermost-data \
  -v mattermost-staging-config:/mm/mattermost-config \
  -v mattermost-staging-logs:/mm/mattermost-logs \
  mattermost/mattermost-preview

# Wait for startup (takes ~30 seconds)
echo "Waiting for Mattermost to start..."
until curl -sf http://localhost:8065/api/v4/system/ping > /dev/null 2>&1; do
  sleep 2
done
echo "Mattermost staging is ready at http://localhost:8065"
```

### First-Time Setup

1. Open `http://localhost:8065` in browser
2. Create admin account (use a test email, not your real one)
3. Skip team creation (teams come from the import)

### Copy Import File into Container

```bash
# From your local machine, copy the bulk import zip
docker cp /path/to/mattermost-bulk-import.zip mattermost-staging:/mm/mattermost-data/import/

# Shell into the container
docker exec -it mattermost-staging bash

# Inside the container:
cd /mm/mattermost
bin/mmctl auth login http://localhost:8065 --name local --username admin --password yourpassword

# Upload and process the import
bin/mmctl import upload /mm/mattermost-data/import/mattermost-bulk-import.zip
bin/mmctl import list available
bin/mmctl import process <import-filename-from-list>
bin/mmctl import job list
```

### Tear Down and Rebuild (For Iteration)

```bash
# Completely destroy staging to start fresh
docker stop mattermost-staging
docker rm mattermost-staging
docker volume rm mattermost-staging-data mattermost-staging-config mattermost-staging-logs

# Re-create with the same docker run command above
# This gives you a clean slate for each import attempt
```

## Option B: Full Staging on a Second Server or VM

For production-identical testing, spin up a second server that mirrors production.

### Provision Staging Server

Use the same provider as production (e.g., Hetzner, DigitalOcean):
- Same OS (Ubuntu 24.04)
- Same or smaller specs (4 GB RAM minimum, 2 vCPU)
- Install PostgreSQL, Nginx, Mattermost -- same versions as production
- Follow the same steps from SERVER-PROVISIONING.md

### Transfer Import File to Staging

```bash
# From your local machine
scp /path/to/mattermost-bulk-import.zip user@staging-server:/opt/mattermost/data/import/

# Or from the production server (if import was built there)
rsync -avP /opt/mattermost/data/import/mattermost-bulk-import.zip \
  user@staging-server:/opt/mattermost/data/import/
```

### Run Import on Staging

```bash
# On the staging server
mmctl import upload /opt/mattermost/data/import/mattermost-bulk-import.zip
mmctl import list available
mmctl import process <import-filename>

# Monitor the import job
watch -n 5 'mmctl import job list --json 2>/dev/null | python3 -m json.tool | tail -20'
```

## Verification Checklist

After each import, run through every item. Do not skip any.

### Channel Verification

```bash
# Count channels in Mattermost
mmctl channel list --all --json 2>/dev/null | python3 -c "
import json, sys
channels = json.load(sys.stdin)
print(f'Total channels: {len(channels)}')
by_type = {}
for c in channels:
    t = c.get('type', 'unknown')
    by_type[t] = by_type.get(t, 0) + 1
for t, count in sorted(by_type.items()):
    print(f'  {t}: {count}')
"
```

Compare against your Slack export:
- [ ] Public channel count matches (O = open in Mattermost)
- [ ] Private channel count matches (P = private in Mattermost)
- [ ] Channel names are correct (no weird transliterations)
- [ ] Channel purposes/headers preserved

### User Verification

```bash
# Count users
mmctl user list --all --json 2>/dev/null | python3 -c "
import json, sys
users = json.load(sys.stdin)
active = [u for u in users if u.get('delete_at', 0) == 0]
deactivated = [u for u in users if u.get('delete_at', 0) > 0]
print(f'Total users: {len(users)}')
print(f'Active: {len(active)}')
print(f'Deactivated: {len(deactivated)}')
"
```

- [ ] User count matches expected count from Slack
- [ ] Email addresses are correct
- [ ] Usernames are reasonable (no mangled names)
- [ ] Deactivated Slack users are deactivated in Mattermost

### Message Sampling

Spot-check at least 5 channels:

- [ ] Oldest messages are present (scroll to beginning of channel)
- [ ] Most recent messages are present
- [ ] Message timestamps are correct (not shifted by timezone)
- [ ] Code blocks render properly
- [ ] Links are clickable
- [ ] Mentions (@user) resolve to the correct user
- [ ] Message edit history is preserved (if applicable)

### Thread Integrity

- [ ] Threaded replies appear under the correct parent message
- [ ] Reply counts match (visible in thread view)
- [ ] Thread participants are correct

### File Attachments

- [ ] Images display inline (not broken image icons)
- [ ] PDFs and documents are downloadable
- [ ] File names are preserved
- [ ] Files in threads are accessible

### Other Data

- [ ] Custom emoji appear in the emoji picker
- [ ] Reactions on messages are preserved (correct emoji, correct users)
- [ ] DM conversations are between the correct pairs of users
- [ ] Group DMs have the correct participants
- [ ] Pinned messages are pinned
- [ ] Bot messages show the correct bot name/icon

## Iterating After Finding Issues

The typical workflow:

1. Import to staging
2. Run verification checklist
3. Find issues (there will be issues)
4. Fix the Phase 1 transform scripts
5. Re-export / re-transform
6. **Destroy staging completely** (Docker: remove container+volumes; VM: re-provision or truncate DB tables)
7. Re-import to clean staging
8. Run verification checklist again
9. Repeat until clean

**Do not import on top of a previous import** -- this causes duplicate data and
makes verification impossible. Always start from a clean Mattermost instance.

### Truncating Staging Database (Alternative to Full Rebuild)

If re-provisioning is too slow:

```sql
-- Connect to PostgreSQL on staging
-- WARNING: This deletes ALL Mattermost data. Only do this on staging.
TRUNCATE TABLE posts CASCADE;
TRUNCATE TABLE channels CASCADE;
TRUNCATE TABLE channelmembers CASCADE;
TRUNCATE TABLE users CASCADE;
TRUNCATE TABLE teams CASCADE;
TRUNCATE TABLE teammembers CASCADE;
TRUNCATE TABLE reactions CASCADE;
TRUNCATE TABLE fileinfo CASCADE;
TRUNCATE TABLE emoji CASCADE;
-- Re-create the initial admin user through the Mattermost setup wizard
```

## Performance Observations

- Docker preview imports are slower than bare-metal (expect 2-3x slower)
- S3-compatible storage (R2) imports faster than local/NFS for file attachments
- PostgreSQL with 4+ GB `shared_buffers` imports noticeably faster
- Large imports (>100K messages) can take 1-4 hours -- do not interrupt
- Monitor disk space during import: plan for 3x the export ZIP size

## Sharing Staging with Stakeholders

Before cutting over, let key stakeholders verify the import:

```bash
# If using Docker on your local machine, expose via ngrok or similar:
ngrok http 8065

# If using a staging server, it already has a public IP
# Create test accounts for stakeholders:
mmctl user create --email stakeholder@company.com --username stakeholder --password TempPass123!
mmctl team add <team-name> stakeholder@company.com
```

Ask stakeholders to verify:
- Their DMs are present and correct
- Key channels have expected history
- File attachments they care about are accessible
- Overall "feel" is acceptable

Get explicit sign-off before proceeding to production import.
