# Post-Cutover Operations

## First Week After Migration

### Day 1: Monitor Everything

```bash
# Check Mattermost is healthy
mmctl system status
curl -sf https://chat.yourdomain.com/api/v4/system/ping | python3 -m json.tool

# Watch error logs in real time
sudo tail -f /opt/mattermost/logs/mattermost.log | grep -i error

# Monitor active users (are people actually logging in?)
sudo -u postgres psql -d mattermost -c "
SELECT count(DISTINCT userid) as active_users_today
FROM status
WHERE lastactivityat > extract(epoch from now() - interval '24 hours') * 1000;
"
```

### Day 1-3: Common Support Tickets

| Ticket | Solution |
|--------|----------|
| "I can't log in" | Check email matches Slack email. Reset password: `mmctl user reset-password user@email.com NewPass123!` |
| "My DMs are missing" | DMs import to the direct messages sidebar. User may need to click "More..." in the DM list. |
| "Old files won't load" | Check R2/S3 migration completed. Verify file paths in `fileinfo` table. |
| "Channel history incomplete" | Check Phase 1 export date range. May need re-import with wider range. |
| "Wrong username" | `mmctl user update username --username old_name --new-username new_name` |
| "Notifications are broken" | User needs to configure notification preferences in Settings > Notifications |
| "Can't find a channel" | Channel may have imported as archived. Check: `mmctl channel list --all \| grep channel-name` |

### Day 3-7: Activation Tracking

```bash
# Users who have logged in at least once since migration
sudo -u postgres psql -d mattermost -c "
SELECT
  count(*) FILTER (WHERE lastactivityat > 0) as activated,
  count(*) FILTER (WHERE lastactivityat = 0 OR lastactivityat IS NULL) as never_logged_in,
  count(*) as total
FROM users
WHERE deleteat = 0 AND roles NOT LIKE '%bot%';
"

# List users who have NOT activated (for follow-up nudges)
sudo -u postgres psql -d mattermost -c "
SELECT username, email
FROM users
WHERE deleteat = 0
  AND roles NOT LIKE '%bot%'
  AND (lastactivityat = 0 OR lastactivityat IS NULL)
ORDER BY username;
"
```

Send reminder emails to users who have not logged in after 3 days.

## Routine Maintenance

### Mattermost Updates

#### APT-Based Updates (Recommended)

If installed via the official APT repository:

```bash
# Check current version
mmctl system version

# Update
sudo apt update
sudo apt upgrade mattermost -y

# Mattermost restarts automatically after APT upgrade
# Verify it came back healthy
sleep 10
mmctl system status
```

#### Manual Updates

If installed from tarball:

```bash
# Check latest version at https://mattermost.com/download/
# Download new version
wget https://releases.mattermost.com/X.Y.Z/mattermost-X.Y.Z-linux-amd64.tar.gz

# Stop service
sudo systemctl stop mattermost

# Backup current installation
sudo cp -a /opt/mattermost /opt/mattermost-backup-$(date +%F)

# Extract new version (preserves config and data)
cd /opt
sudo tar -xzf /path/to/mattermost-X.Y.Z-linux-amd64.tar.gz --transform='s,^mattermost/,mattermost/,'

# Restore ownership
sudo chown -R mattermost:mattermost /opt/mattermost

# Start service
sudo systemctl start mattermost
mmctl system status
```

**Version policy**: Stay on the latest stable release. Mattermost releases monthly.
Extended Support Releases (ESR) exist but are only necessary if you need a slower
update cadence for compliance reasons.

### SSL Certificate Management

#### Cloudflare Origin CA (Recommended)

If you followed CLOUDFLARE-COOKBOOK.md and use Cloudflare Origin CA:

- **Certificate validity**: 15 years
- **No rotation needed** for the foreseeable future
- **Verification**:

```bash
sudo openssl x509 -in /etc/ssl/cloudflare/origin.pem -noout -dates
# notAfter=Dec 31 2039 (or similar far-future date)
```

#### Let's Encrypt (If Not Using Cloudflare Proxy)

```bash
# Install certbot if not present
sudo apt install certbot python3-certbot-nginx

# Initial certificate
sudo certbot --nginx -d chat.yourdomain.com

# Auto-renewal is set up by certbot automatically
# Verify the timer is active
sudo systemctl list-timers | grep certbot

# Test renewal
sudo certbot renew --dry-run
```

### Plugin Management

```bash
# List installed plugins
mmctl plugin list

# Check marketplace for updates (via Mattermost UI)
# System Console > Plugin Management > Marketplace

# Install a plugin from marketplace
mmctl plugin marketplace install <plugin-id>

# Enable/disable plugins
mmctl plugin enable <plugin-id>
mmctl plugin disable <plugin-id>
```

Check for plugin updates monthly. Critical security updates should be applied immediately.

### Database Maintenance

#### Weekly: VACUUM

```bash
# Add to crontab for the postgres user
sudo crontab -u postgres -e
```

```cron
# Weekly VACUUM on Sunday at 3 AM
0 3 * * 0 psql -d mattermost -c "VACUUM VERBOSE;" >> /var/log/postgresql/vacuum.log 2>&1
```

#### Monthly: ANALYZE

```cron
# Monthly ANALYZE on the 1st at 4 AM
0 4 1 * * psql -d mattermost -c "ANALYZE VERBOSE;" >> /var/log/postgresql/analyze.log 2>&1
```

#### Quarterly: REINDEX

```cron
# Quarterly REINDEX (Jan, Apr, Jul, Oct) at 2 AM on the 1st
0 2 1 1,4,7,10 * psql -d mattermost -c "REINDEX DATABASE mattermost;" >> /var/log/postgresql/reindex.log 2>&1
```

#### Check Database Size Growth

```bash
sudo -u postgres psql -d mattermost -c "
SELECT pg_size_pretty(pg_database_size('mattermost')) as db_size;
"

# Size by table
sudo -u postgres psql -d mattermost -c "
SELECT relname as table_name,
       pg_size_pretty(pg_total_relation_size(relid)) as total_size
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 10;
"
```

### Log Rotation

#### Mattermost Logs

In `config.json` under `LogSettings`:

```json
{
  "LogSettings": {
    "EnableFile": true,
    "FileLocation": "/opt/mattermost/logs",
    "FileLevel": "INFO",
    "EnableLogRotation": true,
    "MaxLogRotationSizeMb": 100,
    "MaxLogAge": 30
  }
}
```

#### Nginx Logs

Create `/etc/logrotate.d/nginx-mattermost` (usually exists by default):

```
/var/log/nginx/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 $(cat /var/run/nginx.pid)
    endscript
}
```

### Disk Monitoring

```bash
# One-time check
df -h /opt/mattermost /var/lib/postgresql

# Set up alert script at /usr/local/bin/disk-alert.sh
cat > /tmp/disk-alert.sh << 'SCRIPT'
#!/bin/bash
THRESHOLD=80
ALERT_EMAIL="admin@yourdomain.com"

usage=$(df /opt/mattermost --output=pcent | tail -1 | tr -d ' %')
if [ "$usage" -gt "$THRESHOLD" ]; then
    echo "ALERT: Mattermost disk usage at ${usage}% on $(hostname)" | \
      mail -s "Disk Alert: $(hostname)" "$ALERT_EMAIL"
fi

pg_usage=$(df /var/lib/postgresql --output=pcent | tail -1 | tr -d ' %')
if [ "$pg_usage" -gt "$THRESHOLD" ]; then
    echo "ALERT: PostgreSQL disk usage at ${pg_usage}% on $(hostname)" | \
      mail -s "Disk Alert: $(hostname)" "$ALERT_EMAIL"
fi
SCRIPT

sudo mv /tmp/disk-alert.sh /usr/local/bin/disk-alert.sh
sudo chmod +x /usr/local/bin/disk-alert.sh
```

```cron
# Check disk every 6 hours
0 */6 * * * /usr/local/bin/disk-alert.sh
```

### Performance Review (Monthly)

```bash
# Connection pool usage
sudo -u postgres psql -c "
SELECT count(*) as total_connections,
       count(*) FILTER (WHERE state = 'active') as active,
       count(*) FILTER (WHERE state = 'idle') as idle,
       count(*) FILTER (WHERE state = 'idle in transaction') as idle_in_tx
FROM pg_stat_activity
WHERE datname = 'mattermost';
"

# Slow queries (if pg_stat_statements is enabled)
sudo -u postgres psql -d mattermost -c "
SELECT calls, mean_exec_time::numeric(10,2) as avg_ms,
       total_exec_time::numeric(10,2) as total_ms,
       left(query, 80) as query_preview
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = 'mattermost')
ORDER BY mean_exec_time DESC
LIMIT 10;
"

# Mattermost response time (from Nginx logs)
awk '{print $NF}' /var/log/nginx/access.log | sort -n | awk '
  {a[NR]=$1}
  END {
    print "p50:", a[int(NR*0.5)], "ms"
    print "p95:", a[int(NR*0.95)], "ms"
    print "p99:", a[int(NR*0.99)], "ms"
  }
'

# Active users over the past 30 days
sudo -u postgres psql -d mattermost -c "
SELECT count(DISTINCT userid) as monthly_active_users
FROM status
WHERE lastactivityat > extract(epoch from now() - interval '30 days') * 1000;
"
```

## Annual Operations

### PostgreSQL Major Version Upgrades

```bash
# Check current version
psql --version

# Install new PostgreSQL version alongside current
sudo apt install postgresql-17

# Use pg_upgrade for in-place upgrade
sudo systemctl stop mattermost
sudo systemctl stop postgresql

sudo -u postgres /usr/lib/postgresql/17/bin/pg_upgrade \
  --old-datadir=/var/lib/postgresql/16/main \
  --new-datadir=/var/lib/postgresql/17/main \
  --old-bindir=/usr/lib/postgresql/16/bin \
  --new-bindir=/usr/lib/postgresql/17/bin

# Update postgresql.conf port if needed
sudo systemctl start postgresql
sudo systemctl start mattermost

# Verify
mmctl system status
```

### Mattermost Major Version Upgrades

Follow the official upgrade guide for the specific version. Major version upgrades
(e.g., v9 to v10) may include breaking changes or required database migrations.

```bash
# Always backup before major upgrades
sudo -u postgres pg_dump mattermost > /backups/pre-upgrade-$(date +%F).sql
sudo cp -a /opt/mattermost/config /backups/config-backup-$(date +%F)
```

### Annual Backup Restore Test

```bash
# Restore a backup to a test database and verify
sudo -u postgres createdb mattermost_restore_test
sudo -u postgres psql mattermost_restore_test < /backups/latest-backup.sql

# Verify data integrity
sudo -u postgres psql -d mattermost_restore_test -c "
SELECT 'Users' as t, count(*) FROM users
UNION ALL SELECT 'Posts', count(*) FROM posts
UNION ALL SELECT 'Channels', count(*) FROM channels;
"

# Clean up test database
sudo -u postgres dropdb mattermost_restore_test
```

### Security Audit

- [ ] Review Cloudflare Access policies (remove departed employees)
- [ ] Rotate R2 API tokens
- [ ] Review Mattermost system admin accounts
- [ ] Check for disabled/deprecated plugins
- [ ] Review Nginx configuration against current best practices
- [ ] Verify backup automation is working (restore test above)
- [ ] Check PostgreSQL `pg_hba.conf` for unnecessary access rules
- [ ] Review UFW rules (`sudo ufw status verbose`)

## Decommissioning Slack

After confirming the Mattermost migration is stable (recommend waiting 30+ days):

### 1. Revoke Migration Tokens

```bash
# In Slack admin: https://api.slack.com/apps
# Find the migration app you created in Phase 1
# Click "Revoke All Tokens" or delete the app entirely
```

### 2. Delete the Migration App

1. Go to https://api.slack.com/apps
2. Select the migration app
3. Scroll to **Delete App** > Confirm

### 3. Export Final Audit Report

Before canceling Slack:

```bash
# Request a Corporate Export (if on Business+ or Enterprise Grid)
# Slack Admin > Settings > Import/Export Data > Export
# This is your permanent legal/compliance archive

# For Standard/Pro plans, do a regular Workspace Export:
# Slack Admin > Settings > Import/Export Data > Export
# This only includes public channels
```

Save the export to long-term storage (R2, Backblaze B2, or local archive).

### 4. Notify Users

Send a final message in Slack:

> This Slack workspace will be deactivated on [DATE]. All history has been migrated
> to Mattermost at https://chat.yourdomain.com. Please ensure you can log in to
> Mattermost before this date. Contact admin@yourdomain.com with any issues.

### 5. Cancel Slack Subscription

1. Slack Admin > Billing > Manage plan
2. Downgrade to Free (data retained for a while) or cancel entirely
3. Save confirmation/receipt for records

### 6. DNS Cleanup (Optional)

If you had custom DNS for Slack Connect or similar:

```bash
# Remove any Slack-related DNS records from Cloudflare
# Dashboard > DNS > find and delete records related to Slack
```

## Complete Crontab Summary

All maintenance cron entries in one place. Add via `sudo crontab -e`:

```cron
# === Mattermost Post-Migration Maintenance ===

# Database: Weekly VACUUM (Sunday 3 AM)
0 3 * * 0 sudo -u postgres psql -d mattermost -c "VACUUM VERBOSE;" >> /var/log/postgresql/vacuum.log 2>&1

# Database: Monthly ANALYZE (1st of month, 4 AM)
0 4 1 * * sudo -u postgres psql -d mattermost -c "ANALYZE VERBOSE;" >> /var/log/postgresql/analyze.log 2>&1

# Database: Quarterly REINDEX (Jan/Apr/Jul/Oct 1st, 2 AM)
0 2 1 1,4,7,10 * sudo -u postgres psql -d mattermost -c "REINDEX DATABASE mattermost;" >> /var/log/postgresql/reindex.log 2>&1

# Disk monitoring: Every 6 hours
0 */6 * * * /usr/local/bin/disk-alert.sh

# Database backup: Daily at 2 AM (see BACKUPS.md for the script)
0 2 * * * /usr/local/bin/mattermost-backup.sh >> /var/log/mattermost-backup.log 2>&1

# Let's Encrypt renewal check: Twice daily (only if using Let's Encrypt)
0 0,12 * * * certbot renew --quiet --deploy-hook "systemctl reload nginx"
```
