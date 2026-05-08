# Config Reference

Every `config.env` variable, grouped by purpose. Marked `[R]` = required,
`[O]` = optional (sensible default), `[S]` = stage-specific (only needed for
certain stages).

## Workspace & working directory

| Var | Purpose | Default | Example |
|-----|---------|---------|---------|
| `WORKSPACE_NAME` [R] | Short tag used in report filenames | — | `acme-mattermost` |
| `PHASE3_WORKSPACE_ROOT` [O] | Where reports land | `./workdir-phase3` | `~/mattermost-ops/phase3` |

## Mattermost admin

| Var | Purpose | Default | Example |
|-----|---------|---------|---------|
| `MATTERMOST_URL` [R] | Live Mattermost URL | — | `https://chat.acme.com` |
| `MATTERMOST_ADMIN_TOKEN` [R] | Admin PAT | — | `abc...xyz` |
| `MATTERMOST_ADMIN_USER` [O] | Fallback for mmctl auth | — | `admin` |
| `MATTERMOST_ADMIN_PASS` [O] | Fallback for mmctl auth | — | `<strong>` |
| `MATTERMOST_TEAM_NAME` [O] | Scoped checks | — | `acme` |

## SSH

| Var | Purpose | Default | Example |
|-----|---------|---------|---------|
| `TARGET_HOST` [R] | Hostname or IP of Mattermost server | — | `chat.acme.com` |
| `TARGET_SSH_USER` [R] | SSH user (Phase 2 creates `deploy`) | `deploy` | `deploy` |
| `TARGET_SSH_KEY` [O] | Path to private key if non-default | — | `~/.ssh/id_ed25519` |
| `TARGET_SSH_OPTS` [O] | Extra ssh options | `-o BatchMode=yes -o ServerAliveInterval=30 -o ConnectTimeout=10` | — |

## PostgreSQL

| Var | Purpose | Default | Example |
|-----|---------|---------|---------|
| `POSTGRES_DSN` [R] | Live MM DB | — | `postgres://mmuser:<pw>@localhost:5432/mattermost?sslmode=disable` |
| `POSTGRES_REACH` [O] | `ssh` = reachable only from target; `direct` = from workstation | `ssh` | `ssh` |

## Backup

| Var | Purpose | Default | Example |
|-----|---------|---------|---------|
| `BACKUP_PATH` [R] | On-host dump directory | `/var/backups/mattermost` | same |
| `BACKUP_RETENTION_DAILY_DAYS` [O] | Rotate daily dumps | `30` | `30` |
| `BACKUP_RETENTION_WEEKLY_WEEKS` [O] | Rotate weeklies | `12` | `12` |
| `BACKUP_RETENTION_MONTHLY_MONTHS` [O] | Rotate monthlies | `12` | `12` |
| `OFFSITE_REMOTE` [O] | rclone remote for off-site | — | `r2:mm-backups-acme` |
| `OFFSITE_RCLONE_OPTS` [O] | Extra rclone flags | — | `--transfers 4 --bwlimit 50M` |

## Restore drill

| Var | Purpose | Default | Example |
|-----|---------|---------|---------|
| `SCRATCH_DB_URL` [S] | Scratch DB for restore-drill | — | `postgres://mmuser:<pw>@localhost:5432/mm_restore_drill?sslmode=disable` |
| `RESTORE_MIN_USERS` [O] | Row-count threshold | `0` | `337` |
| `RESTORE_MIN_CHANNELS` [O] | Row-count threshold | `0` | `142` |
| `RESTORE_MIN_POSTS` [O] | Row-count threshold | `0` | `1280000` |

## OS patch policy

| Var | Purpose | Default | Example |
|-----|---------|---------|---------|
| `OS_UPDATE_POLICY` [O] | `security` / `all` / `none` | `security` | `security` |

## Reboot window (UTC)

| Var | Purpose | Default | Example |
|-----|---------|---------|---------|
| `REBOOT_WINDOW_DAY` [O] | 3-letter day abbrev | `Sun` | `Sun` |
| `REBOOT_WINDOW_HOUR_START` [O] | 24h UTC, inclusive | `3` | `3` |
| `REBOOT_WINDOW_HOUR_END` [O] | 24h UTC, exclusive | `5` | `5` |
| `REBOOT_WINDOW_MAX_WAIT_HOURS` [O] | Block if next window > N hours out | `168` | `168` |

## Mattermost upgrade policy

| Var | Purpose | Default | Example |
|-----|---------|---------|---------|
| `MATTERMOST_TARGET_VERSION` [S] | Pin for `update-mattermost` | — | `10.11.3` |
| `MATTERMOST_UPGRADE_ROLLBACK` [O] | `auto` / `manual` | `auto` | `auto` |

## Health thresholds

| Var | Purpose | Default |
|-----|---------|---------|
| `HEALTH_DISK_PCT_RED` | Disk % → red | `85` |
| `HEALTH_DISK_PCT_YELLOW` | Disk % → yellow | `75` |
| `HEALTH_PG_CONN_PCT_RED` | PG connections % → red | `80` |
| `HEALTH_PG_CONN_PCT_YELLOW` | PG connections % → yellow | `60` |
| `HEALTH_LOG_ERR_PER_MIN_RED` | `level=error` lines/min → red | `10` |
| `HEALTH_LOG_ERR_PER_MIN_YELLOW` | `level=error` lines/min → yellow | `3` |

## Alerting

| Var | Purpose | Default | Example |
|-----|---------|---------|---------|
| `ALERT_WEBHOOK_URL` [O] | Incoming-webhook URL (Slack / Mattermost / Discord all work) | — | `https://chat.acme.com/hooks/abc...` |
| `ALERT_EMAIL` [O] | cc for alerts (requires SMTP from Phase 2) | — | `ops@acme.com` |

## Rollback / DR

| Var | Purpose | Default | Example |
|-----|---------|---------|---------|
| `ROLLBACK_OWNER` [R for destructive stages] | Named human for go/no-go | — | `Jane Admin <jane@acme.com>` |

## What's intentionally NOT configurable

- The health-score banner format (matches phase-1/phase-2 convention).
- The `latest-*.json` symlink convention.
- The `workdir-phase3/reports/` layout.
- The SHA-256 hash algorithm (hard-coded; don't change).

## Loading config from a non-default path

Set `PHASE3_CONFIG=/path/to/config.env` before running any script or
`./maintain.sh`. Every script respects that env var.
