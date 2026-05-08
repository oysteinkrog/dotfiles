# Phase 3 Start Here

Use this when you want the safest next action, not the entire manual.

## Default Path

1. Run `./scripts/doctor.sh`, `./scripts/doctor.sh --require-remote`, and
   `./scripts/doctor.sh --require-mcp`. All three must be green before any
   stage runs.
2. Run `./maintain.sh health` to get a baseline. Archive the result.
3. Schedule `./maintain.sh weekly-sweep` as a recurring agent run.
4. On the first Saturday of each quarter, run `./maintain.sh restore-drill`.
5. On each Mattermost security release, run `./maintain.sh update-mattermost`
   with a pinned `MATTERMOST_TARGET_VERSION`.
6. Once a year, run a full disaster-recovery rehearsal per
   [workflows/ANNUAL-DR-DRILL-WORKFLOW.md](workflows/ANNUAL-DR-DRILL-WORKFLOW.md).

## Stop Immediately If

- `TARGET_HOST` is unreachable over SSH in `BatchMode=yes`
- `MATTERMOST_URL` returns non-200 on `/api/v4/system/ping` for >60 seconds
- `MATTERMOST_ADMIN_TOKEN` is invalid (403 on `/api/v4/users/me`)
- Last `restore-drill` is older than 90 days and an `update-mattermost` was requested
- `ROLLBACK_OWNER` is unset when a destructive stage was requested
- SSH host-key mismatch since last connection (possible MitM)

## First-Hop References

- [DONE-DEFINITION.md](DONE-DEFINITION.md) — pass criteria per stage
- [CROSS-PHASE-INTAKE-CONTRACT.md](CROSS-PHASE-INTAKE-CONTRACT.md) — what
  Phase 2 hands off to Phase 3
- [MIGRATION-THREAT-MODEL.md](MIGRATION-THREAT-MODEL.md) — assets and
  countermoves
- [playbooks/INCIDENT-RESPONSE.md](playbooks/INCIDENT-RESPONSE.md) — when a
  user reports Mattermost down
- [MAINTAIN-SH-REFERENCE.md](MAINTAIN-SH-REFERENCE.md) — orchestrator CLI
- [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md) — per-stage cards
