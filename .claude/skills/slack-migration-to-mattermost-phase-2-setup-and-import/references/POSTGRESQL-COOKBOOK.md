# PostgreSQL Cookbook

## Installation

```bash
# Ubuntu 24.04 ships PostgreSQL 16. Install it:
apt update && apt install -y postgresql postgresql-contrib

systemctl enable postgresql
systemctl status postgresql
psql --version
```

## Create Mattermost User and Database

```bash
sudo -u postgres psql << 'SQL'
CREATE USER mmuser WITH PASSWORD 'CHANGE_THIS_STRONG_PASSWORD';
CREATE DATABASE mattermost OWNER mmuser;
GRANT ALL PRIVILEGES ON DATABASE mattermost TO mmuser;
\q
SQL

# Verify connection
psql -U mmuser -h 127.0.0.1 -d mattermost -c "SELECT version();"
```

If `psql` prompts for password and you want local connections to use password auth, ensure `/etc/postgresql/16/main/pg_hba.conf` has:

```
# TYPE  DATABASE    USER    ADDRESS       METHOD
local   mattermost  mmuser                scram-sha-256
host    mattermost  mmuser  127.0.0.1/32  scram-sha-256
```

Then reload:

```bash
systemctl reload postgresql
```

## Performance Tuning (64GB RAM / ~1000 Users)

Edit `/etc/postgresql/16/main/postgresql.conf`:

```ini
# --- Memory ---
shared_buffers = 16GB                  # 25% of RAM
effective_cache_size = 48GB            # 75% of RAM (OS cache + shared_buffers)
work_mem = 64MB                        # per-sort/hash operation; conservative
maintenance_work_mem = 2GB             # for VACUUM, CREATE INDEX
huge_pages = try                       # use if kernel supports it

# --- Connections ---
max_connections = 200                  # Mattermost default pool is ~20; leave headroom
superuser_reserved_connections = 3

# --- WAL ---
wal_buffers = 64MB                     # 1/256 of shared_buffers, capped at 64MB
min_wal_size = 1GB
max_wal_size = 4GB
checkpoint_completion_target = 0.9     # spread checkpoint writes
checkpoint_timeout = 15min

# --- Query Planner ---
random_page_cost = 1.1                 # NVMe is nearly sequential speed
effective_io_concurrency = 200         # NVMe can handle many concurrent reads
default_statistics_target = 200        # better query plans

# --- Parallel Queries ---
max_worker_processes = 8
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
max_parallel_maintenance_workers = 4

# --- Logging ---
log_min_duration_statement = 1000      # log queries > 1 second
log_checkpoints = on
log_lock_waits = on
log_temp_files = 0                     # log all temp file usage

# --- Autovacuum ---
autovacuum_max_workers = 4
autovacuum_vacuum_scale_factor = 0.05  # vacuum at 5% dead tuples (default 20%)
autovacuum_analyze_scale_factor = 0.02
```

Restart after changes:

```bash
systemctl restart postgresql
```

### Enable Huge Pages (Optional, Recommended)

```bash
# Calculate required huge pages (shared_buffers = 16GB, huge page = 2MB)
echo "vm.nr_hugepages = 8400" >> /etc/sysctl.d/99-hugepages.conf
sysctl -p /etc/sysctl.d/99-hugepages.conf

# Verify
grep -i hugepages /proc/meminfo
```

## Backup Strategy

### Daily pg_dump (Simple)

```bash
mkdir -p /backups/postgresql
chown postgres:postgres /backups/postgresql

cat > /etc/cron.d/mattermost-backup << 'EOF'
# Daily backup at 03:00 UTC, keep 14 days
0 3 * * * postgres pg_dump -Fc -Z6 mattermost > /backups/postgresql/mattermost_$(date +\%Y\%m\%d_\%H\%M).dump 2>> /var/log/mattermost-backup.log
# Prune old backups
30 3 * * * postgres find /backups/postgresql -name "mattermost_*.dump" -mtime +14 -delete
EOF
```

Verify backup is valid:

```bash
# List contents without restoring
pg_restore -l /backups/postgresql/mattermost_YYYYMMDD_0300.dump | head -20

# Test restore to a scratch database
sudo -u postgres createdb mattermost_restore_test
pg_restore -d mattermost_restore_test /backups/postgresql/mattermost_YYYYMMDD_0300.dump
sudo -u postgres dropdb mattermost_restore_test
```

### WAL Archiving (Point-in-Time Recovery)

Add to `postgresql.conf`:

```ini
archive_mode = on
archive_command = 'test ! -f /backups/postgresql/wal/%f && cp %p /backups/postgresql/wal/%f'
```

```bash
mkdir -p /backups/postgresql/wal
chown postgres:postgres /backups/postgresql/wal
systemctl restart postgresql
```

### Point-in-Time Recovery

```bash
# 1. Stop PostgreSQL
systemctl stop postgresql

# 2. Back up current data directory (safety)
mv /var/lib/postgresql/16/main /var/lib/postgresql/16/main.broken

# 3. Restore base backup
pg_restore -Fc -d mattermost /backups/postgresql/mattermost_YYYYMMDD_0300.dump

# 4. Create recovery signal file
touch /var/lib/postgresql/16/main/recovery.signal

# 5. Set recovery target in postgresql.conf
echo "recovery_target_time = '2026-04-15 12:00:00 UTC'" >> /etc/postgresql/16/main/postgresql.conf
echo "restore_command = 'cp /backups/postgresql/wal/%f %p'" >> /etc/postgresql/16/main/postgresql.conf

# 6. Start PostgreSQL (it replays WAL to target time)
systemctl start postgresql

# 7. After recovery, promote to normal operation
sudo -u postgres psql -c "SELECT pg_wal_replay_resume();"
```

## Monitoring Queries

### Active Connections

```sql
SELECT datname, usename, state, count(*)
FROM pg_stat_activity
GROUP BY datname, usename, state
ORDER BY count DESC;
```

### Database Size

```sql
SELECT pg_database.datname,
       pg_size_pretty(pg_database_size(pg_database.datname)) AS size
FROM pg_database
ORDER BY pg_database_size(pg_database.datname) DESC;
```

### Largest Tables

```sql
SELECT schemaname, relname,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
       n_live_tup AS live_rows,
       n_dead_tup AS dead_rows
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 15;
```

### Slow Queries (if pg_stat_statements enabled)

```bash
# Enable the extension
sudo -u postgres psql -d mattermost -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
```

Add to `postgresql.conf`:

```ini
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all
```

```sql
-- Top 10 slowest queries by mean time
SELECT round(mean_exec_time::numeric, 2) AS mean_ms,
       calls,
       round(total_exec_time::numeric, 2) AS total_ms,
       left(query, 120) AS query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = 'mattermost')
ORDER BY mean_exec_time DESC
LIMIT 10;
```

### Cache Hit Ratio

```sql
SELECT
  sum(heap_blks_hit) / nullif(sum(heap_blks_hit) + sum(heap_blks_read), 0) AS cache_hit_ratio
FROM pg_statio_user_tables;
-- Should be > 0.99 with 16GB shared_buffers
```

### Replication Lag (if using replicas)

```sql
SELECT client_addr, state,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;
```

## Connection Pooling with PgBouncer

For >200 concurrent connections or multi-instance Mattermost:

```bash
apt install -y pgbouncer

cat > /etc/pgbouncer/pgbouncer.ini << 'EOF'
[databases]
mattermost = host=127.0.0.1 port=5432 dbname=mattermost

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 40
min_pool_size = 10
reserve_pool_size = 10
server_idle_timeout = 300
EOF

# Create auth file
echo '"mmuser" "CHANGE_THIS_STRONG_PASSWORD"' > /etc/pgbouncer/userlist.txt
chmod 600 /etc/pgbouncer/userlist.txt
chown postgres:postgres /etc/pgbouncer/userlist.txt

systemctl enable pgbouncer
systemctl start pgbouncer
```

Update Mattermost `config.json` to connect through PgBouncer:

```json
{
  "SqlSettings": {
    "DataSource": "postgres://mmuser:password@127.0.0.1:6432/mattermost?sslmode=disable"
  }
}
```

**Important:** PgBouncer in `transaction` mode does not support prepared statements. Add `?binary_parameters=yes` to the DSN if Mattermost complains, or use `session` mode (reduces pooling efficiency).

## Maintenance

### Manual VACUUM and ANALYZE

```bash
# Full vacuum (reclaims disk space, locks table -- run during maintenance window)
sudo -u postgres vacuumdb --full --analyze mattermost

# Regular vacuum + analyze (non-blocking, safe to run anytime)
sudo -u postgres vacuumdb --analyze mattermost
```

### REINDEX

```bash
# Rebuild all indexes (fixes bloat after heavy import)
sudo -u postgres reindexdb mattermost
# Run after the Mattermost bulk import completes
```

### Check for Bloat

```sql
SELECT schemaname, relname,
       n_dead_tup,
       n_live_tup,
       round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 1) AS dead_pct
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC
LIMIT 10;
-- If dead_pct > 20%, run VACUUM on that table
```

## Post-Import Maintenance

After running `mmctl import process`, the database has ingested a large batch. Run this sequence:

```bash
# 1. Analyze all tables (updates query planner statistics)
sudo -u postgres vacuumdb --analyze mattermost

# 2. Reindex (rebuild indexes after bulk insert)
sudo -u postgres reindexdb mattermost

# 3. Check database size
sudo -u postgres psql -d mattermost -c "SELECT pg_size_pretty(pg_database_size('mattermost'));"

# 4. Verify cache hit ratio is healthy
sudo -u postgres psql -d mattermost -c "
SELECT sum(heap_blks_hit) / nullif(sum(heap_blks_hit) + sum(heap_blks_read), 0)
FROM pg_statio_user_tables;"
```
