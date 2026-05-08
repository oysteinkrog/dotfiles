# Phase 2 Start Here

Use this when you want the safest next action, not the entire manual.

## Default Path

1. Run `./operate.sh intake` before touching Mattermost.
2. Run `./operate.sh render-config` and `./operate.sh verify-live` before staging.
3. Run `./operate.sh staging` before any production import.
4. Run `./operate.sh ready` to compute the actual go/no-go gate.
5. Run `./operate.sh cutover` only when the readiness gate is green and rollback ownership is explicit.

## Stop Immediately If

- the handoff JSON is missing or hashless
- staging has not been run
- rollback owner is unassigned
- SMTP is unverified but activation depends on password resets
- the target URL is production-like but you are still rehearsing
- post-import smoke tests or reconciliation were skipped

## First-Hop References

- `references/DONE-DEFINITION.md`
- `references/CROSS-PHASE-INTAKE-CONTRACT.md`
- `references/MIGRATION-THREAT-MODEL.md`
- `references/ROLLBACK-AND-ABORT-CRITERIA.md`
- `references/WAR-ROOM-OPS.md`
- `references/OPERATE-SH-REFERENCE.md`
