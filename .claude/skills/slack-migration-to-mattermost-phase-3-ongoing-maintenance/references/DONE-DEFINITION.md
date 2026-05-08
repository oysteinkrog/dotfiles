# Phase 3 Done Definition

Phase 3 is a rolling "done" — each stage has its own pass criteria. Phase 3
as a whole is never done while the server is running.

## Required Gates (per stage)

### `health`

- `workdir-phase3/reports/latest-health.json.overall` is `ok` or `yellow`
- no red check without a logged mitigation
- report written and archived

### `update-os`

- `apt-get update` returned 0
- `unattended-upgrade -v` reported zero errors (or `apt-get upgrade -y` for `all` policy)
- `/var/run/reboot-required` probed and the flag persisted to report
- `latest-update-os.json.status` is `success`

### `schedule-reboot`

- `at` queue has exactly one entry for the computed window
- entry appears in `workdir-phase3/reboot-history.json`
- `latest-schedule-reboot.json.status` is `scheduled` (or `skipped` if no reboot required)

### `update-mattermost`

- `MATTERMOST_TARGET_VERSION` is pinned (no "latest")
- pre-upgrade `pg_dump` exists at `BACKUP_PATH/pre-upgrade-<ts>.sql.gz`
- post-upgrade `/api/v4/system/ping` returns 200 within 3 minutes
- `/api/v4/config/client?format=old` reports the target version
- `latest-update-mattermost.json.status` is `success` (or `failed_rolled_back` with evidence)

### `backup`

- `pg_dump` exits 0
- SHA-256 recorded in `latest-backup.json.sha256`
- off-site upload succeeded (or explicitly skipped with operator note)
- off-site hash matches local hash
- rotation completed (old dumps deleted per `BACKUP_RETENTION_*`)

### `db-health`

- all metrics collected (no `skip` entries for core checks)
- `latest-db-health.json.overall` is `ok` or `yellow`
- if `red`: note written, plan to remediate attached

### `restore-drill`

- `pg_restore` exits 0
- observed row counts ≥ `RESTORE_MIN_*`
- `latest-restore-drill.json.status` is `ok`
- scratch DB is recreated cleanly (no residue from previous drill)

### `rotate-credentials`

- old credential revoked (verified by 403 on old token / lock-out on old key)
- new credential verified working (ping + PAT check)
- `config.env` updated to reference the new credential
- audit trail written with named approver from `ROLLBACK_OWNER`

### `disaster-recovery`

- new host serves the same URL
- latest-backup restored into new host; row counts verified
- DNS swapped; Cloudflare proxy re-enabled
- `verify-live` green against new host
- post-mortem skeleton written (timeline, root cause, data lost, lessons)

## Required Outputs (rolling)

Phase 3 accumulates these over time; operators can audit back 90 days on demand.

- Per-stage `<stage>-<ts>.json` + `latest-<stage>.json` symlink
- `reboot-history.json` (cumulative)
- `restore-drill-history.json` (cumulative)
- `rotate-credentials-audit.json` (cumulative)
- DR post-mortems under `workdir-phase3/reports/dr/` if any occurred

## Required Operational Outcomes

- Over any 30-day window, at least 28 daily backups with `verify_status=ok`
- Over any 90-day window, at least 1 passing restore-drill
- Over any 365-day window, at least 1 full DR drill against a fresh host
- Over any 90-day window, at least 1 successful `rotate-credentials` for PAT
- Zero stale security patches > 30 days old
- Zero Mattermost versions > 2 patch releases behind for > 14 days

## Not Done If

- a `restore-drill` failed and was not followed up
- a reboot was required but never scheduled
- a PAT is >120 days old
- a backup run silently failed (no report, no alert)
- a security-flagged Mattermost release is >30 days unapplied
- the team cannot say when the last DR drill was
