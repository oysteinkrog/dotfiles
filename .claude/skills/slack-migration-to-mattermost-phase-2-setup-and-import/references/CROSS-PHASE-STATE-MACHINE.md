# Cross-Phase State Machine

Phase 2 should treat the migration as a continuation of the Phase 1 lifecycle, not a separate manual.

## Incoming States

- `handoff-emitted`
- `phase2-intake-validated`
- `staging-imported`
- `staging-approved`
- `cutover-frozen`

## Outgoing States

- `production-imported`
- `activation-open`
- `cutover-complete`
- `rolled-back`
- `closed`

## Gate Rule

Every state transition must have a report or artifact proving why the transition was allowed.
