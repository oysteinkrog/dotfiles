# maintain.sh Reference

The Phase 3 orchestrator. Thin dispatcher over `scripts/*.sh` and `scripts/*.py`.

## Synopsis

```bash
./maintain.sh <stage> [options]
```

## Stages

| Stage | Script | Destructive? | Idempotent? |
|-------|--------|--------------|-------------|
| `health` | `scripts/health-check.sh` | no | yes |
| `update-os` | `scripts/os-update.sh` | no (until reboot) | yes |
| `update-mattermost` | `scripts/mattermost-upgrade.sh` | yes (service restart + migration) | no |
| `backup` | `scripts/db-backup.sh` | no | yes |
| `db-health` | `scripts/db-health.sh` | no | yes |
| `restore-drill` | `scripts/restore-drill.sh` | yes (wipes SCRATCH_DB_URL) | yes |
| `schedule-reboot` | `scripts/schedule-reboot.sh` | yes (queues reboot) | yes-if-same-window |
| `rotate-credentials` | `scripts/rotate-credentials.sh` | yes (revokes old creds) | no |
| `disaster-recovery` | prints `references/DISASTER-RECOVERY.md` | n/a (interactive) | n/a |
| `weekly-sweep` | composite: health → update-os → backup → db-health | aborts on first failure | yes |

## Environment

| Variable | Purpose |
|----------|---------|
| `PHASE3_CONFIG` | Override path to `config.env` (default: `./config.env`) |
| `PHASE3_WORKSPACE_ROOT` | Override report directory (default: `./workdir-phase3`) |
| `PHASE3_STAGE_TIMESTAMP` | Internal — timestamp of current run |
| `PHASE3_STAGE_OUT_JSON` | Internal — path of current stage's JSON output |

## Outputs

Every stage writes:

- `workdir-phase3/reports/<stage>-<timestamp>.json` — the timestamped report
- `workdir-phase3/reports/latest-<stage>.json` — symlink to most recent

Non-zero exit = stage failed. The orchestrator aborts composite stages on
first failure.

## Chaining

```bash
./maintain.sh health       && \
./maintain.sh update-os    && \
./maintain.sh backup       && \
./maintain.sh db-health
```

is equivalent to `./maintain.sh weekly-sweep`. The composite form writes a
single summary report; the chain above writes four.

## Non-interactive use

All stages are safe to run unattended with exceptions:

- `disaster-recovery` is an interactive playbook; running it non-interactively
  just dumps the playbook markdown to stdout.
- `rotate-credentials` prompts for operator confirmation at each rotation
  step; pass `--yes` to skip (not recommended for production).

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Stage complete, all checks passed |
| 1 | Stage failed (red metric, upload verify failure, etc.) |
| 2 | Usage error (missing stage arg, missing config) |
| 3 | Gate blocked (e.g. `update-mattermost` with stale restore-drill) |

## Dry-run

`./scripts/smoke-test-phase3.sh` is the dry-run of all stages. It performs
read-only checks: reachability, config completeness, one SELECT 1 against the
DB, one `apt list --upgradable`. Emits a go/no-go JSON.

## Scheduled use (cron on workstation)

```cron
# Nightly backup at 03:00 UTC
0 3 * * *  cd ~/mattermost-ops && ./maintain.sh backup        >> /var/log/mm-backup.log 2>&1

# Weekly sweep Saturday 02:00 UTC
0 2 * * 6  cd ~/mattermost-ops && ./maintain.sh weekly-sweep  >> /var/log/mm-sweep.log 2>&1

# Quarterly restore-drill: first Saturday of Jan/Apr/Jul/Oct at 04:00 UTC
0 4 1-7 1,4,7,10 6  cd ~/mattermost-ops && ./maintain.sh restore-drill  >> /var/log/mm-drill.log 2>&1
```

See [workflows/WEEKLY-SWEEP-WORKFLOW.md](workflows/WEEKLY-SWEEP-WORKFLOW.md)
for the recommended cadence.
