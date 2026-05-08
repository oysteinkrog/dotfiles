# Workflow — Quarterly Restore Drill

Prove backups actually work. The single highest-leverage recurring
maintenance task.

## Prerequisites

- `SCRATCH_DB_URL` configured and points to a throwaway DB
- At least one successful backup in the last 7 days
- `./maintain.sh doctor --require-remote` green

## Steps

1. Paste [prompts/restore-drill.md](../../prompts/restore-drill.md).
2. Agent runs `./maintain.sh restore-drill`:
   a. Selects newest backup (off-site preferred, local fallback).
   b. Recreates scratch DB (drops + creates fresh).
   c. Streams backup through `gunzip | psql`.
   d. Counts `users`, `channels`, `posts` in the restored scratch DB.
   e. Compares against `RESTORE_MIN_*` thresholds.
3. Agent reads `latest-restore-drill.json` and reports:
   - which backup was used (source + timestamp + age)
   - observed row counts
   - pass / fail
4. If `RESTORE_MIN_*` look stale (well below current `db-health`
   counts), agent proposes updated values to paste into `config.env`.
5. If fail: agent walks [BACKUP-FAILURE-RESPONSE.md](../playbooks/BACKUP-FAILURE-RESPONSE.md).

## Timing

For a 10 GB Mattermost DB:

- Download from R2: 30-120 sec
- `pg_restore` via `psql`: 5-15 min
- Row-count verification: 10 sec
- **Total**: ~10-20 min wall-clock

Bigger DBs scale linearly: plan for ~2 min per GB.

## What "pass" means

- `pg_restore` exits 0 (no errors logged)
- `users` count ≥ `RESTORE_MIN_USERS`
- `channels` count ≥ `RESTORE_MIN_CHANNELS`
- `posts` count ≥ `RESTORE_MIN_POSTS`
- scratch DB has Mattermost's schema intact (spot-check: `SELECT COUNT(*) FROM teams;`)

## What "fail" means and what to do

- pg_restore errors → see [diagnostics/BACKUP-DIAGNOSTICS.md](../diagnostics/BACKUP-DIAGNOSTICS.md) "pg_restore errors"
- Row counts below minimum → either backup truncated, or minimums stale
- Connection timeout → scratch DB unreachable; see TROUBLESHOOTING.md

## Side effects

- Scratch DB is wiped and recreated. Anything you had in it before is gone.
- ~10 GB of temporary disk used during restore.
- No production impact.

## After passing

- Update `workdir-phase3/restore-drill-history.json` (script does this
  automatically).
- Update `RESTORE_MIN_*` in `config.env` to reflect current production
  counts (so next drill isn't lenient).
- Mark "restore-drill freshness" gate satisfied; `update-mattermost` is
  now unblocked for the next 90 days.

## After failing

- Write an incident note at
  `workdir-phase3/reports/incidents/<ts>-restore-drill.md`.
- Fix the underlying problem (backup chain, scratch DB config, etc.).
- Re-run the drill.
- Do NOT run `update-mattermost` until a drill passes.

## Automation

```cron
# First Sunday of each quarter, 04:00 UTC
0 4 1-7 1,4,7,10 0  cd ~/mattermost-ops && ./maintain.sh restore-drill >> /var/log/mm-drill.log 2>&1
```

Or invoke via `/schedule` skill if the operator prefers agent-driven.

## Why quarterly and not more often

- Restores consume disk + CPU on whichever host holds the scratch DB.
- At quarterly cadence you'll detect a broken backup chain within 90
  days; combined with daily backup reports, a silent failure is caught
  within hours via the nightly run's own status.
- More frequent restore-drills would detect failures faster but at the
  cost of operator attention; quarterly hits the Pareto point for small
  to mid workspaces.

## Why not annual

- One year is too long for a critical capability to go unverified.
- Backup formats, PG versions, and scratch DB configs can drift in 12
  months such that a drill fails not because backups are bad, but
  because the drill environment is.

## Related

- [../playbooks/BACKUP-FAILURE-RESPONSE.md](../playbooks/BACKUP-FAILURE-RESPONSE.md)
- [../BACKUP-STRATEGY.md](../BACKUP-STRATEGY.md)
- [../diagnostics/BACKUP-DIAGNOSTICS.md](../diagnostics/BACKUP-DIAGNOSTICS.md)
