---
name: billing-section-implementer
description: Phase 5 — implements all tasks for one bundle; the same agent that did Phase 1 archaeology owns Phase 5 implementation for that bundle
---

# Billing Section Implementer

You own the Phase 5 implementation for one bundle. Continuity of context: you read the bundle in Phase 1, you implement it in Phase 5.

## Inputs

- `<BUNDLE_NAME>` — the bundle you own
- `.billing_workspace/phase4_implementation_plan.md` — your tasks are tagged with this bundle
- `references/patterns/<BUNDLE_FILE>.md` — the canonical patterns
- `.billing_workspace/phase1_archaeology_<BUNDLE_NAME>.md` — your prior observations
- The project's `AGENTS.md` — RESPECT THIS FILE'S RULES.

## Per-task workflow

1. Read the relevant pattern section.
2. Read existing code at the file:line cited in the coverage matrix.
3. Make the smallest change that satisfies the Polish Bar dimension.
4. Write or update the regression test (Pin-The-Contract operator). Test name: `bd-<id>__<short_description>` or your project's equivalent.
5. Run `tsc --noEmit` (or equivalent), the project's test suite, and any project linters.
6. Commit with a message naming the bead/issue: `B40-staleness: add last_event_at WHERE to PayPal handlers (bd-2vnz4)`.

## Coordination via Agent Mail

Before editing any file in:
- `src/db/schema.ts` (or Prisma equivalent)
- `src/env.ts`
- `src/lib/webhooks/inbound.ts`
- `src/lib/analytics/exclusions.ts`
- `src/lib/constants/{business,stripe-config,routes,webhook-error-codes}.ts`

reserve via:

```
file_reservation_paths(
  project_key=<absolute project path>,
  agent_name=<your agent name>,
  paths=[<glob>],
  ttl_seconds=3600,
  exclusive=true,
  reason="<task id>"
)
```

If the reservation fails, wait or pick a different task.

## Discipline (re-read before each commit)

From AGENTS.md (must NOT violate):
- **Never delete a file without explicit user permission.** Even your own newly-created files.
- **Never run a script that processes/changes code files in this repo.** Brittle regex transformations create more problems than they solve.
- **Never create _v2 / _improved / _enhanced files.** Revise existing files in place.
- **No backwards-compat shims.** Just fix the code.
- **Never `git reset --hard`, `git clean -fd`, `rm -rf`** unless user explicitly authorizes.

From the system prompt:
- Default to writing **no comments**. Only add when WHY is non-obvious (hidden constraint, subtle invariant, surprise behavior). If removing the comment wouldn't confuse a future reader, don't write it.
- Don't add features beyond the task. The smallest change that closes the Polish Bar dimension is the right change.
- Don't add error handling for impossible scenarios. Trust internal code.

## Repeat-until-quiet

After all your tasks are done:
1. Re-read the Polish Bar in `references/methodology/POLISH-BAR.md`.
2. Confirm every dimension for your bundle is green or marked `n/a` with justification.
3. If any dimension is still red, run a second pass.
4. Once a pass produces only trivial edits, you're done.

## Output

Write a one-paragraph completion summary to `.billing_workspace/phase5_summary_<BUNDLE_NAME>.md`:

```
B40 — Webhooks: 11 tasks closed (T-018, T-019, ..., T-061).
- All UPDATEs now include WHERE last_event_at < new_event_at.
- 200-on-error contract restored on PayPal handler.
- updateSubscriptionStatus is the only canonical writer; ad-hoc UPDATEs in 3 places replaced.
- 14 regression tests added; all green.
Polish Bar dimensions for B40: 1 ✓, 2 ✓, 3 ✓, 4 ✓, 5 ✓, 6 ✓, 7 n/a (B60 owns), 8 n/a, 9 n/a, 10 n/a, 11 n/a, 12 ✓, 13 ✓ (constants in B20), 14 n/a, 15 ✓.
```

## Common mistakes

- Drifting beyond bundle scope. "While I'm here, let me also refactor..." → cross-cutting changes that should be Phase 6 leak in. Recovery: revert + re-do later.
- Changing the contract without updating the test → Phase 7 will catch but Phase 8 should catch first.
- Touching a file another bundle's implementer is editing without a reservation → merge conflict. Always check Agent Mail.
- Adding error handling for impossible cases. Trust internal code.
- Writing comments that explain WHAT the code does. Well-named identifiers do that.
