# Backup Diagnostics

Things that go wrong during `./maintain.sh backup` and `./maintain.sh restore-drill`.

## pg_dump fails

| Error | Cause | Fix |
|-------|-------|-----|
| `FATAL: password authentication failed` | `POSTGRES_DSN` wrong / role revoked | Verify: `psql "$POSTGRES_DSN" -c 'SELECT 1'` |
| `could not connect: Connection refused` | Postgres down | `ssh $TARGET sudo systemctl status postgresql` + restart |
| `canceling statement due to lock timeout` | Long-held exclusive lock | Check for running VACUUM FULL or ALTER TABLE; wait or kill |
| `out of memory` | `work_mem` too low for dump of a large table | Add `-Z 1` (lighter compression) or raise server memory |

## Disk write fails

| Error | Fix |
|-------|-----|
| `No space left on device` | `df -h $BACKUP_PATH`; rotation stuck. Manually delete oldest dumps, re-run |
| `Permission denied` | `ssh $TARGET sudo chown -R postgres:postgres $BACKUP_PATH` |

## SHA-256 computation fails

Shouldn't happen; `sha256sum` is in coreutils. If it does: check the
target's PATH / coreutils installation.

## Off-site upload fails

| rclone error | Cause | Fix |
|--------------|-------|-----|
| `Failed to copy: 401/403` | Token rotated / revoked | Regenerate at provider; update rclone config |
| `dial tcp: lookup ...: no such host` | DNS fail or remote offline | Wait, retry with `--retries 10` |
| `quota exceeded` | Storage quota hit | Manually delete oldest off-site backups, or raise quota |
| `TLS handshake timeout` | Network flaky | Retry with `--low-level-retries 20` |

## Upload-hash mismatch

Very rare. Re-upload:
```
rclone copy "$BACKUP_PATH/mm_<ts>.sql.gz" "$OFFSITE_REMOTE/" \
  --checksum --retries 5
rclone cat "$OFFSITE_REMOTE/mm_<ts>.sql.gz.sha256"
```

If the mismatch recurs after several attempts: the provider or network
is corrupting bytes. Switch `OFFSITE_REMOTE`.

## Restore-drill: pg_restore errors

| Error | Cause | Fix |
|-------|-------|-----|
| `pg_restore: error: unsupported version` | Scratch DB's PG < source DB's PG | Upgrade scratch DB to match source major |
| `schema "public" already exists` | Scratch DB wasn't recreated | `DROP DATABASE` + `CREATE DATABASE` before restore |
| `relation "..." already exists` | Same as above | same |
| `could not open file "/var/backups/..."` | Pass through is wrong; rclone cat didn't stream | Use `rclone cat ... | gunzip | psql` |

## Restore-drill: row counts below minimum

| Table | Below threshold means |
|-------|------------------------|
| `users` | Backup captured before user import, or a new cohort was added and `RESTORE_MIN_USERS` is stale |
| `channels` | Similar; also check channel-deletion events in between |
| `posts` | Most common; `RESTORE_MIN_POSTS` is usually outpaced by workspace growth |

Fix approach:
1. Compare `db-health` current counts vs `RESTORE_MIN_*`.
2. If db-health counts are much higher: minimums are stale. Update
   `RESTORE_MIN_*` to the current floor.
3. If db-health counts are similar or lower: the backup actually didn't
   capture everything. Investigate the failing backup run; previous
   backups should have restored fine.

## Restore-drill: scratch DB unreachable

Same diagnostics as live DB: password, connectivity, Postgres running.

## Too-old backup

If `./maintain.sh restore-drill` picks a backup from 30+ days ago
because more recent ones failed silently: the real failure is the failing
backup chain. Work
[../playbooks/BACKUP-FAILURE-RESPONSE.md](../playbooks/BACKUP-FAILURE-RESPONSE.md)
first, then re-run the drill against a fresh backup.

## Persistent drill failures

If the drill fails 2 quarters in a row despite backups passing: there's
a gap between "backup passed" and "backup restores." Either:
- The backup script is silently skipping content.
- The scratch DB environment is subtly different from production (PG
  version, extensions, locale).
- The RESTORE_MIN_* are outright wrong.

Escalate to L2 (DBA review) per [../comms/ESCALATION-LADDER.md](../comms/ESCALATION-LADDER.md).
