# Backup Failure Response

`./maintain.sh backup` or `./maintain.sh restore-drill` reported red.
This is a production-incident-adjacent situation; the server is still up,
but your ability to recover from a disaster just degraded.

## Triage checklist

1. What exactly failed?
   - `backup`: which step? `pg_dump`, local disk write, SHA computation,
     off-site upload, or upload-hash verify?
   - `restore-drill`: pg_restore exit code, or row counts below minimum, or
     scratch-DB unreachable?
2. Is the previous successful backup still on disk (local) and off-site?
   ```bash
   ssh deploy@$TARGET ls -la /var/backups/mattermost/ | tail
   rclone ls "$OFFSITE_REMOTE/" | tail
   ```
   If yes: you have a fallback; the immediate risk is bounded to the
   window since that backup.
3. Is the Mattermost service still healthy? `./maintain.sh health`. If
   health is red too, handle the incident first (`playbooks/INCIDENT-RESPONSE.md`).

## Common failure modes and fixes

### pg_dump fails

- **Connection refused** → Postgres not running. `ssh target sudo systemctl
  status postgresql` + restart.
- **Authentication failed** → `POSTGRES_DSN` password wrong or role
  revoked. Verify with `psql "$POSTGRES_DSN" -c 'SELECT 1'`.
- **"canceling statement due to lock timeout"** → unusual on pg_dump
  (which uses ACCESS SHARE). Check for a long-running `VACUUM FULL` or
  `ALTER TABLE` that's holding a conflicting lock.

### Local disk write fails

- **No space** → `ssh target df -h /var/backups/mattermost`. Rotation may
  be stuck. Manually delete oldest files and re-run backup.
- **Permission denied** → `BACKUP_PATH` ownership changed.
  `ssh target sudo chown -R postgres:postgres /var/backups/mattermost`.

### Off-site upload fails

- **Auth error in rclone** → token rotated or revoked. Check `rclone
  config show $OFFSITE_REMOTE`; regenerate at provider if needed.
- **Network intermittent** → `rclone` retries 3 times by default. Pass
  `OFFSITE_RCLONE_OPTS="--retries 10"` and re-run.
- **Destination full** (e.g. Hetzner Storage Box hit quota) → rotate
  off-site retention manually, then re-run.

### Upload-hash mismatch

- **Extremely rare** (usually a provider-side bug or in-flight
  corruption). Re-upload:
  ```bash
  rclone copy "$BACKUP_PATH/mm_<ts>.sql.gz" "$OFFSITE_REMOTE/"
  rclone copy "$BACKUP_PATH/mm_<ts>.sql.gz.sha256" "$OFFSITE_REMOTE/"
  rclone cat "$OFFSITE_REMOTE/mm_<ts>.sql.gz.sha256"   # verify
  ```
- **If recurring**: switch `OFFSITE_REMOTE` to a different provider.

### Restore-drill row count mismatch

- **`RESTORE_MIN_*` is stale** → the workspace grew, minimums weren't
  updated. Compare against `./maintain.sh db-health` current counts;
  update `RESTORE_MIN_*` in `config.env` to the new floor.
- **Backup truncated** → check the SHA-256 against what was recorded when
  the backup was taken (look at `latest-backup.json`). If mismatch, the
  backup on disk is corrupt; use an older backup.
- **Scratch DB pg_restore errors** → PG major version mismatch. Scratch
  DB must be >= the source DB's major version.

## Escalation criteria

Escalate (see [../comms/ESCALATION-LADDER.md](../comms/ESCALATION-LADDER.md)) if:

- Three consecutive nightly backups failed (7+ day gap in restorable
  state approaching).
- Last restore-drill pass is older than 90 days AND a pending upgrade is
  required.
- Any sign of data integrity concern on the live DB (corruption, partial
  transaction blocks).

## After stabilizing

1. Write a short incident note: what failed, what you did, what you'll
   change. Stored under `workdir-phase3/reports/incidents/<ts>-backup.md`.
2. If the failure is an infrastructure pattern (e.g. "Hetzner Storage Box
   is flaky"), file a durable fix: switch provider, add a second `OFFSITE_REMOTE_2`,
   shorten retention, etc.
3. Re-run a successful `./maintain.sh backup` and `./maintain.sh restore-drill`
   before closing the incident.
