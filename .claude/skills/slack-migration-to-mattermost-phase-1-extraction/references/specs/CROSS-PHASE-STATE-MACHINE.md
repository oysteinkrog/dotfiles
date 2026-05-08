# Cross-Phase State Machine

This is the canonical migration lifecycle across both skills.

## States

1. `plan-approved`
2. `raw-acquired`
3. `enrichment-complete`
4. `transform-complete`
5. `package-validated`
6. `handoff-emitted`
7. `phase2-intake-validated`
8. `staging-imported`
9. `staging-approved`
10. `cutover-frozen`
11. `production-imported`
12. `activation-open`
13. `cutover-complete`
14. `closed`

## Abort / Rollback Branches

- from `phase2-intake-validated` back to `handoff-emitted` if intake validation fails
- from `staging-imported` back to `transform-complete` if counts, mappings, or files are wrong
- from `production-imported` back to `cutover-frozen` if smoke tests fail before activation

## Rule

No stage may advance unless the previous stage has a manifest, a report, or a gate artifact proving it.
