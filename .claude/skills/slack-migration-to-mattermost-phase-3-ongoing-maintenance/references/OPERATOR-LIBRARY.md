# Operator Library — Phase 3 Maintenance

Per-stage operator cards: trigger, inputs, outputs, failure modes, prompt modules.

## HEALTH — live health probe

**Trigger**: weekly, or whenever you suspect something is off (user reports of slow Mattermost, disk alerts from your hoster, UFW email).

**Inputs**: live MATTERMOST_URL + SSH to TARGET_HOST. No writes anywhere.

**Outputs**: `latest-health.json` with per-check status, overall `ok|yellow|red`.

**Failure modes**:
- `mattermost_ping=red` → Mattermost is down. Check systemd on target: `sudo systemctl status mattermost`. Likely causes: OOM, corrupted config.json, port 8065 collision after reboot.
- `websocket_upgrade=red` → Nginx lost the Upgrade headers. Re-run Phase 2 `render-config` + `deploy` or edit `/etc/nginx/sites-enabled/mattermost.conf` directly.
- `smtp_tcp=red` → SMTP provider blocked or creds rotated. Paste the Phase 2 SMTP walkthrough prompt to the agent.
- `disk_root=red` → usually `/var/log/` or `/opt/mattermost/data/` blowup. `du -shx /*` to find it.
- `pg_connections=red` → connection leak or burst load. `SELECT * FROM pg_stat_activity WHERE state='idle in transaction';` and terminate stale ones.
- `mattermost_errors=red` → tail `/opt/mattermost/logs/mattermost.log` for the last 500 lines and look for a repeating error.

**Prompt**: see [prompts/health.md](../prompts/health.md).

## UPDATE-OS — OS patches

**Trigger**: weekly for `security` policy, monthly for `all`. Always before a Mattermost upgrade.

**Inputs**: SSH to TARGET_HOST, `sudo` non-interactive, `OS_UPDATE_POLICY`.

**Outputs**: `latest-update-os.json` with counts of upgradable and security packages before the run, plus `reboot_required` flag.

**Failure modes**:
- `apt-get update` fails → Ubuntu archive is down or the target has no internet. Retry in 10 minutes; if persistent, check `sudo ufw status` and `resolvectl status`.
- Kernel was upgraded → `reboot_required=yes`. Do NOT `apt-get autoremove` with `--purge` without confirming you've still got the running kernel.
- Disk full mid-upgrade → `apt-get clean`, then re-run. Chronic disk pressure should surface in health checks.

**Prompt**: see [prompts/update-os.md](../prompts/update-os.md).

## UPDATE-MM — Mattermost version upgrade

**Trigger**: on release cadence (minor: quarterly; patch: within a week of ship if security-critical).

**Inputs**: `MATTERMOST_TARGET_VERSION`, pre-upgrade backup, approval from `ROLLBACK_OWNER` for major version.

**Outputs**: `latest-update-mattermost.json` with before/after versions, pre-upgrade dump path, status.

**Failure modes**:
- APT fails to find the version → Mattermost repo hasn't published it yet, or the version string is wrong. `apt-cache madison mattermost` on the target to see candidates.
- Migration hangs → the upgrade includes a long DDL migration. Wait; check `/opt/mattermost/logs/mattermost.log`. For very large DBs (>100 GB), some migrations take an hour.
- Post-upgrade ping fails → auto-rollback kicks in (if `MATTERMOST_UPGRADE_ROLLBACK=auto`). You're back on the previous version; investigate the new version's release notes before retrying.

**Prompt**: see [prompts/update-mattermost.md](../prompts/update-mattermost.md).

## BACKUP — pg_dump + off-site

**Trigger**: daily via scheduled run; also before every `update-mattermost` and before `cutover`-style operations.

**Inputs**: SSH to target, PG superuser `postgres` (for `pg_dump`), `OFFSITE_REMOTE` + rclone.

**Outputs**: `latest-backup.json` with path, hash, upload status, verify status.

**Failure modes**:
- `pg_dump: connection refused` → Postgres not running. Check `sudo systemctl status postgresql`.
- Disk space under `BACKUP_PATH` exhausted → rotation didn't keep up. Check retention settings; manually delete the oldest files and re-run.
- Off-site upload fails → check `rclone config show` on the target, and the auth token or key for the remote. Retry with `--retries 5`.
- Hash mismatch after upload → data corruption in transit (rare). Re-upload; if it recurs, the rclone remote may be flaking.

**Prompt**: see [prompts/backup.md](../prompts/backup.md).

## DB-HEALTH — Postgres snapshot

**Trigger**: weekly as part of sweep, or after any unusual DB-adjacent incident.

**Inputs**: SSH, PG superuser for `pg_stat_*` queries.

**Outputs**: `latest-db-health.json` with sizing, connections, vacuum status, lock waits.

**Failure modes**: rarely fails outright; it's a read-only snapshot. Red overall means you have a real DB problem the agent has already summarized.

**Prompt**: see [prompts/db-health.md](../prompts/db-health.md).

## RESTORE — restore-drill

**Trigger**: quarterly. This is the canary that proves backups work; do NOT skip.

**Inputs**: `SCRATCH_DB_URL` (a throwaway DB), latest backup (off-site or local), `RESTORE_MIN_*` thresholds.

**Outputs**: `latest-restore-drill.json` with source backup, observed row counts vs minimums, status.

**Failure modes**:
- `SCRATCH_DB_URL` points at an unreachable DB → fix in `config.env`; can't restore into nothing.
- `pg_restore` errors → backup file is corrupt, or the scratch DB's PG version is older than the source. Use matching major version.
- Row count below minimum → either the minimum is stale (workspace grew, never update) or a recent backup accidentally captured an empty DB. Investigate.

**Prompt**: see [prompts/restore-drill.md](../prompts/restore-drill.md).

## REBOOT — scheduled reboot

**Trigger**: after `update-os` reports `reboot_required=yes`.

**Inputs**: `at` daemon on target, `REBOOT_WINDOW_*` config.

**Outputs**: `latest-schedule-reboot.json` with next-window timestamp; entry in `workdir-phase3/reboot-history.json`.

**Failure modes**:
- `at` not installed → the script auto-installs it; fails if target has no internet.
- Next window > `REBOOT_WINDOW_MAX_WAIT_HOURS` → blocked; surface to human. Don't auto-widen the window.
- Reboot doesn't return → server didn't come back. Escalate to Hetzner support; check `robot.hetzner.com` for hardware alerts.

**Prompt**: see [prompts/schedule-reboot.md](../prompts/schedule-reboot.md).

## DR — disaster recovery

**Trigger**: catastrophic host failure. Full playbook in [DISASTER-RECOVERY.md](DISASTER-RECOVERY.md).

**Inputs**: new host, latest backup, Phase 2 skill, approval from `ROLLBACK_OWNER`.

**Outputs**: rebuilt Mattermost at the same URL; post-mortem skeleton.

**Failure modes**: each phase has its own fallbacks; see the playbook.

**Prompt**: see [prompts/disaster-recovery.md](../prompts/disaster-recovery.md).
