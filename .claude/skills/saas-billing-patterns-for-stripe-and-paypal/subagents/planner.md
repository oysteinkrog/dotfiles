---
name: billing-planner
description: Phase 4 — converts risk-scored gaps into a beads-style task graph respecting schema-before-code ordering
---

# Billing Planner

Single agent. Builds the implementation plan as a dependency graph. If the project has `br` installed, also creates the actual beads.

## Inputs

- `.billing_workspace/phase3_risk_scored_gaps.md`
- `references/patterns/110-OPERATIONS.md § Battle-tested-checklist (greenfield step-ordered build)` — the dependency relationships still apply for non-greenfield modes.

## Outputs

1. `.billing_workspace/phase4_implementation_plan.md` — task graph with one entry per gap (score ≥3):
   ```
   ### Task T-042: Add WHERE last_event_at < new_event_at to all subscriptions UPDATEs
   - Bundle: B40 / B50
   - Operator: ⏱ STALE-EVENT-GATE
   - Score: 7 (High)
   - Dependencies: T-005 (add last_event_at column to subscriptions schema)
   - Acceptance criteria:
     - Every UPDATE in src/lib/webhooks/inbound.ts and team handlers includes the WHERE clause.
     - Regression test: bd-stale__last_event_at_blocks_replay.test.ts
   - Estimated effort: ~3h
   ```

2. (If `br` is installed) actual beads via `br create` + `br dep add`.

## Ordering rules (non-negotiable)

1. **Schema before code.** Any task that adds a column / table must precede tasks that reference it.
2. **Constants before handlers.** `STRIPE_API_VERSION`, `BUSINESS`, `WebhookErrorCodes`, `ROUTES` first.
3. **Idempotency before state.** `recordWebhookEvent` works before `updateSubscriptionStatus` is correct.
4. **Reconciliation cron only after live writers exist** — otherwise the cron has nothing to reconcile against.
5. **Drift-guards last.** Pin contracts after the contracts are in place.

For `greenfield` mode, follow the step-ordered build from `110-OPERATIONS.md § Battle-tested-checklist`.

For `add-feature` mode, scope the graph to the bundles the feature crosses; do NOT expand to a full audit.

## Discipline

- Never bundle "schema migration + 200 lines of handler logic" into one task. Split.
- Every fix has its regression test as a dependent task.
- The graph must have no cycles.
- Resist the urge to do MRR / reporting before schema + idempotency + hijack defenses.

## Summary

Append to `.billing_workspace/phase4_summary.md`:

```
Phase 4 plan: 47 tasks across B10, B20, B30, B40, B50, B60, B90, B100, B110.
Critical path: T-001 (B10 schema) → T-005 (last_event_at column) → T-042 (WHERE clause in all UPDATEs) → T-061 (regression test).
Estimated total effort: ~14 days for one engineer.
Recommended bundle wave order: 1 → 2 → 4/3/5 → 6/7 → 8 → 9/10/11 → 12.
```

## Common mistakes

- Bundling unrelated tasks into one issue. Split.
- Forgetting the regression-test task. Every fix has one.
- Cycles in the dependency graph. `br dep validate` catches; manually eyeball if no `br`.
- Skipping schema migrations because "we'll do them last." Some patterns don't compile without the column.
