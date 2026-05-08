# Backup & Disaster Recovery

Complete backup strategy for a self-hosted Mattermost instance with PostgreSQL.

## What to Back Up

| Component | Location | Method |
|-----------|----------|--------|
| PostgreSQL database | localhost:5432 `mattermost` DB | pg_dump + WAL archiving |
| Mattermost config | `/opt/mattermost/config/` | File copy |
| File attachments (local) | `/opt/mattermost/data/` | rsync |
| File attachments (S3/R2) | Cloud bucket | Already durable; replicate if needed |
| Custom emoji | Stored in DB + `/opt/mattermost/data/emoji/` | Included in DB dump + data rsync |
| TLS certificates | `/etc/nginx/ssl/` | File copy |
| Nginx config | `/etc/nginx/sites-available/` | File copy |

## Daily pg_dump with Retention

### Backup Script

```bash
#!/usr/bin/env bash
# /opt/backups/scripts/backup-mattermost.sh
set -euo pipefail

BACKUP_DIR="/opt/backups/mattermost"
RETENTION_DAYS=30
DATE=$(date +%Y%m%d_%H%M%S)
LOG="/var/log/mattermost-backup.log"

mkdir -p "$BACKUP_DIR"/{db,config,data}

echo "[$(date)] Starting backup" >> "$LOG"

# 1. Database dump (custom format for parallel restore)
pg_dump -U mmuser -Fc mattermost > "$BACKUP_DIR/db/mattermost_${DATE}.dump"
echo "[$(date)] Database dump complete: $(du -h "$BACKUP_DIR/db/mattermost_${DATE}.dump" | cut -f1)" >> "$LOG"

# 2. Config directory
tar czf "$BACKUP_DIR/config/config_${DATE}.tar.gz" -C /opt/mattermost config/
echo "[$(date)] Config backup complete" >> "$LOG"

# 3. File attachments (local storage only)
if [ -d /opt/mattermost/data ]; then
    rsync -a --delete /opt/mattermost/data/ "$BACKUP_DIR/data/"
    echo "[$(date)] File storage rsync complete" >> "$LOG"
fi

# 4. Nginx + TLS certs
tar czf "$BACKUP_DIR/config/nginx_${DATE}.tar.gz" \
    /etc/nginx/sites-available/ \
    /etc/nginx/ssl/ 2>/dev/null || true
echo "[$(date)] Nginx config backup complete" >> "$LOG"

# 5. Prune old backups
find "$BACKUP_DIR/db" -name "*.dump" -mtime +${RETENTION_DAYS} -delete
find "$BACKUP_DIR/config" -name "*.tar.gz" -mtime +${RETENTION_DAYS} -delete
echo "[$(date)] Pruned backups older than ${RETENTION_DAYS} days" >> "$LOG"

echo "[$(date)] Backup finished" >> "$LOG"
```

Make it executable:
```bash
chmod +x /opt/backups/scripts/backup-mattermost.sh
```

### Cron Entry

```bash
# Run daily at 03:00 UTC as the postgres-capable user
sudo crontab -e
# Add:
0 3 * * * /opt/backups/scripts/backup-mattermost.sh 2>&1 | tee -a /var/log/mattermost-backup.log
```

Verify cron is running:
```bash
sudo systemctl status cron
grep "backup" /var/log/syslog | tail -5
```

## WAL Archiving for Point-in-Time Recovery

WAL archiving lets you restore to any point in time, not just the last daily dump. Essential if you need sub-day RPO.

### Enable WAL Archiving in PostgreSQL

Edit `/etc/postgresql/16/main/postgresql.conf`:
```
wal_level = replica
archive_mode = on
archive_command = 'test ! -f /opt/backups/mattermost/wal/%f && cp %p /opt/backups/mattermost/wal/%f'
```

Create the WAL directory and restart:
```bash
sudo mkdir -p /opt/backups/mattermost/wal
sudo chown postgres:postgres /opt/backups/mattermost/wal
sudo systemctl restart postgresql
```

### Take a Base Backup (Required for PITR)

```bash
sudo -u postgres pg_basebackup \
    -D /opt/backups/mattermost/basebackup \
    -Ft -z -Xs -P
```

Retake the base backup weekly (add to cron):
```bash
0 4 * * 0 sudo -u postgres pg_basebackup -D /opt/backups/mattermost/basebackup_$(date +\%Y\%m\%d) -Ft -z -Xs -P 2>&1 | tee -a /var/log/mattermost-backup.log
```

### Restore to a Specific Point in Time

```bash
# 1. Stop Mattermost and PostgreSQL
sudo systemctl stop mattermost postgresql

# 2. Move the current data directory
sudo mv /var/lib/postgresql/16/main /var/lib/postgresql/16/main.old

# 3. Extract the base backup
sudo -u postgres mkdir /var/lib/postgresql/16/main
sudo -u postgres tar xzf /opt/backups/mattermost/basebackup/base.tar.gz \
    -C /var/lib/postgresql/16/main

# 4. Create recovery signal and config
sudo -u postgres bash -c 'cat > /var/lib/postgresql/16/main/recovery.signal <<EOF
EOF'
sudo -u postgres bash -c "cat >> /var/lib/postgresql/16/main/postgresql.auto.conf <<EOF
restore_command = 'cp /opt/backups/mattermost/wal/%f %p'
recovery_target_time = '2026-04-15 14:30:00 UTC'
recovery_target_action = 'promote'
EOF"

# 5. Start PostgreSQL -- it will replay WAL to the target time
sudo systemctl start postgresql

# 6. Verify, then start Mattermost
sudo -u postgres psql -c "SELECT count(*) FROM posts;" mattermost
sudo systemctl start mattermost
```

## Off-Site Backup Shipping

### Option A: Hetzner Storage Box (BorgBackup)

```bash
# Install borg
sudo apt install -y borgbackup

# Initialize remote repo (first time only)
borg init --encryption=repokey ssh://uXXXXXX@uXXXXXX.your-storagebox.de:23/./mattermost-backup

# Daily borg backup (add to cron after pg_dump)
borg create --compression zstd \
    ssh://uXXXXXX@uXXXXXX.your-storagebox.de:23/./mattermost-backup::'{now}' \
    /opt/backups/mattermost/db/ \
    /opt/backups/mattermost/config/ \
    /opt/backups/mattermost/data/

# Prune remote
borg prune --keep-daily=7 --keep-weekly=4 --keep-monthly=6 \
    ssh://uXXXXXX@uXXXXXX.your-storagebox.de:23/./mattermost-backup
```

### Option B: Cloudflare R2

```bash
# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Configure R2 remote (interactive)
rclone config
# Type: s3, Provider: Cloudflare, Access Key ID + Secret from R2 dashboard
# Endpoint: https://ACCOUNT_ID.r2.cloudflarestorage.com

# Sync backups to R2
rclone sync /opt/backups/mattermost/ r2:mattermost-backups/ \
    --transfers=4 --progress
```

R2 cron entry:
```bash
30 4 * * * rclone sync /opt/backups/mattermost/ r2:mattermost-backups/ --transfers=4 >> /var/log/mattermost-backup.log 2>&1
```

## Encryption at Rest

Encrypt backups before shipping off-site:

```bash
# Generate an encryption key (store this SECURELY, separate from backups)
openssl rand -base64 32 > /root/.backup-key
chmod 600 /root/.backup-key

# Encrypt a dump before shipping
openssl enc -aes-256-cbc -salt -pbkdf2 \
    -in "$BACKUP_DIR/db/mattermost_${DATE}.dump" \
    -out "$BACKUP_DIR/db/mattermost_${DATE}.dump.enc" \
    -pass file:/root/.backup-key

# Decrypt when restoring
openssl enc -d -aes-256-cbc -pbkdf2 \
    -in mattermost_${DATE}.dump.enc \
    -out mattermost_${DATE}.dump \
    -pass file:/root/.backup-key
```

If using BorgBackup, encryption is built in (`--encryption=repokey`). No need for manual encryption on top.

## Backup Verification (Restore Test)

Run a monthly restore test to a temporary PostgreSQL instance to confirm backups are valid.

```bash
#!/usr/bin/env bash
# /opt/backups/scripts/verify-backup.sh
set -euo pipefail

LATEST_DUMP=$(ls -t /opt/backups/mattermost/db/*.dump | head -1)
TEST_DB="mattermost_restore_test"

echo "Verifying backup: $LATEST_DUMP"

# Create temp database
sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${TEST_DB};"
sudo -u postgres psql -c "CREATE DATABASE ${TEST_DB} OWNER mmuser;"

# Restore into it
pg_restore -U mmuser -d "$TEST_DB" --no-owner "$LATEST_DUMP"

# Validate key tables
USERS=$(sudo -u postgres psql -t -c "SELECT count(*) FROM users;" "$TEST_DB")
POSTS=$(sudo -u postgres psql -t -c "SELECT count(*) FROM posts;" "$TEST_DB")
CHANNELS=$(sudo -u postgres psql -t -c "SELECT count(*) FROM channels;" "$TEST_DB")

echo "Restore verified: ${USERS} users, ${POSTS} posts, ${CHANNELS} channels"

# Clean up
sudo -u postgres psql -c "DROP DATABASE ${TEST_DB};"
echo "Verification complete -- backup is valid"
```

Monthly cron:
```bash
0 5 1 * * /opt/backups/scripts/verify-backup.sh >> /var/log/mattermost-backup.log 2>&1
```

## Full Disaster Recovery Procedure

Complete restore from backup to a fresh server.

```bash
# 1. Provision new Ubuntu server, install PostgreSQL + Mattermost (Stage 1-2 from SKILL.md)
sudo apt install -y postgresql mattermost

# 2. Retrieve backups from off-site
rclone copy r2:mattermost-backups/db/ /tmp/restore/db/
rclone copy r2:mattermost-backups/config/ /tmp/restore/config/

# 3. Restore PostgreSQL
sudo -u postgres psql -c "DROP DATABASE IF EXISTS mattermost;"
sudo -u postgres psql -c "CREATE DATABASE mattermost OWNER mmuser;"
pg_restore -U mmuser -d mattermost --no-owner /tmp/restore/db/mattermost_LATEST.dump

# 4. Restore Mattermost config
sudo tar xzf /tmp/restore/config/config_LATEST.tar.gz -C /opt/mattermost/
sudo chown -R mattermost:mattermost /opt/mattermost/config/

# 5. Restore file attachments (if local storage)
rclone copy r2:mattermost-backups/data/ /opt/mattermost/data/
sudo chown -R mattermost:mattermost /opt/mattermost/data/

# 6. Restore Nginx config + TLS certs
sudo tar xzf /tmp/restore/config/nginx_LATEST.tar.gz -C /
sudo systemctl restart nginx

# 7. Update SiteURL if server IP or domain changed
sudo -u mattermost mmctl config set ServiceSettings.SiteURL "https://chat.yourdomain.com"

# 8. Start services
sudo systemctl start postgresql mattermost nginx

# 9. Verify
curl -s https://chat.yourdomain.com/api/v4/system/ping
mmctl user list --all | wc -l
```

**RTO target:** Under 1 hour with practiced runbook.
**RPO target:** Under 24 hours with daily dumps, under 1 hour with WAL archiving.
