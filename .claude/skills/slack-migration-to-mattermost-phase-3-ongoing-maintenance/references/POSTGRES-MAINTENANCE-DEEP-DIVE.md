# PostgreSQL Maintenance Deep Dive

Mattermost's Postgres needs exactly the normal care any Postgres gets;
the distinctive parts are which tables matter most and which queries are
hot.

## Hot tables (read often)

- `Posts` — every message. Largest by row count.
- `ChannelMembers` — membership per user per channel. Grows with users × channels.
- `Sessions` — active user sessions; short-lived.
- `Users` — one per account; read on every auth.

## Hot tables (write often)

- `Posts` (insert-heavy at peak post volume).
- `ChannelMembers.LastViewedAt` (update on every read-receipt).
- `Sessions.LastActivityAt` (update on every API call).
- `Status` — user presence; very high update rate.

## Indexes to watch

Mattermost creates its own indexes; they're generally well-placed. Watch:

- `Posts` indexes on `(ChannelId, CreateAt)` — used for channel scroll.
- `Posts` indexes on `RootId` — used for thread fetch.
- `ChannelMembers` PK on `(ChannelId, UserId)`.

At scale, `REINDEX CONCURRENTLY` quarterly on `Posts` indexes prevents
index bloat.

## Autovacuum

Mattermost's defaults are fine for workspaces up to ~10K users. Signs of
trouble:
- `n_dead_tup` > 20% of `n_live_tup` for > 1 week
- autovacuum starts but is constantly canceled (lock contention)

Remediation (per table):

```sql
-- Make autovacuum more aggressive
ALTER TABLE "Posts" SET (
  autovacuum_vacuum_scale_factor = 0.05,  -- default 0.2
  autovacuum_analyze_scale_factor = 0.05
);
```

Or manual, off-hours:

```sql
VACUUM (VERBOSE, ANALYZE) "Posts";
```

Note: plain `VACUUM` does NOT take an exclusive lock; `VACUUM FULL` does.
Never `VACUUM FULL` during business hours.

## pg_repack for bloat

When bloat estimate is > 30% and you can't afford downtime:

```bash
# On target, as postgres user
sudo -u postgres pg_repack -d mattermost -t Posts
```

`pg_repack` copies the table into a new file and swaps, without holding
a long lock. Install via `apt install postgresql-XX-pg-repack` matching
your PG version.

## Tuning

Mattermost's recommended Postgres settings (in `postgresql.conf`) for a
64 GB RAM server:

```conf
shared_buffers = 16GB               # 25% of RAM
effective_cache_size = 48GB         # ~75% of RAM
work_mem = 64MB                     # per sort / hash
maintenance_work_mem = 2GB          # for VACUUM / CREATE INDEX
max_connections = 300               # raise from default 100-200
wal_buffers = 16MB
random_page_cost = 1.1              # for NVMe (default 4 assumes HDD)
effective_io_concurrency = 200      # for NVMe
```

Requires Postgres restart.

## Backup strategy (refresher)

- Logical: `pg_dump --format=custom --compress=1` (what `db-backup.sh` does)
- Physical: `pg_basebackup` + WAL archive (out of scope; consider for HA)
- Streaming replication: hot standby with `pg_basebackup` + `replication`
  user (out of scope; consider for near-zero RPO)

## Restore considerations

- `pg_restore` into an empty DB created with `createdb` (not dropdb; keep
  ownership correct).
- `pg_restore --jobs=4` for parallel restore on multi-core hosts.
- Match Postgres major version between dump source and restore target.

## Locking incidents

Symptoms: Mattermost UI hangs on certain channels, `/api/v4/system/ping`
slow, `pg_stat_activity` shows `wait_event_type='Lock'`.

Diagnose:
```sql
SELECT pid, usename, query_start, state, wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE wait_event_type IS NOT NULL
ORDER BY query_start;
```

Common: a migration or long ALTER TABLE blocking other queries. Either
wait or `pg_terminate_backend(pid)` on the offender.

## Long-running queries

```sql
SELECT pid, now()-query_start AS runtime, query
FROM pg_stat_activity
WHERE state='active' AND now()-query_start > interval '5 minutes';
```

Investigate; sometimes a plugin generates pathological queries. Terminate
with `pg_terminate_backend(pid)` if disrupting service.

## Extensions

- `pg_stat_statements` — recommended. Enables query-profile visibility
  for `db-bloat-auditor`. Enable via `shared_preload_libraries = 'pg_stat_statements'`
  + restart + `CREATE EXTENSION pg_stat_statements;`.
- `pgstattuple` — for precise bloat measurement. Optional.
- `pg_repack` — for bloat remediation. Recommended install.

## Major upgrades

See [diagnostics/UPGRADE-DIAGNOSTICS.md](diagnostics/UPGRADE-DIAGNOSTICS.md)
"Upgrade touched Postgres major version." Postgres major upgrades are
significant events; plan a separate window.
