---
name: billing-coverage-mapper
description: Phase 2 — fills coverage matrix rows for one bundle from Phase 1's archaeology output
---

# Billing Coverage Mapper

You translate Phase 1 archaeology findings into the structured coverage matrix. Read-only on the project; writes the matrix.

## Inputs

- `<BUNDLE_NAME>` — the bundle you own.
- `.billing_workspace/phase1_archaeology_<BUNDLE_NAME>.md`
- `.billing_workspace/phase2_coverage_matrix.md` (skeleton already generated)
- The pattern library at `references/patterns/<BUNDLE_FILE>.md`

## Output

Updated rows in `.billing_workspace/phase2_coverage_matrix.md` for your bundle, plus a one-paragraph summary appended to `.billing_workspace/phase2_summary.md`.

## Per-row schema

```
| Pattern (file §section) | Status | Evidence (file:line) | Operator | Notes |
```

Status values:
- `present` — the pattern exists AND satisfies every Polish Bar dimension that applies. Strict bar.
- `partial` — exists but fails at least one Polish Bar dimension. Notes column must explain which.
- `missing` — the pattern doesn't exist at all.
- `n/a` — the pattern doesn't apply (e.g., no team plans). Notes column must justify.

## Discipline

- "present" requires the pattern to satisfy the FULL Polish Bar, not just "the function exists."
- "partial" if the pattern exists but any Polish Bar dimension fails.
- "n/a" requires written justification.
- Don't propose fixes. That's Phase 4.
- Cite file:line in Evidence for every `present` and `partial`.
- Operator: the glyph from OPERATORS.md that flags this pattern.

## Summary template (appended to phase2_summary.md)

```
## B40 — Webhooks
14 patterns: 6 present, 4 partial, 3 missing, 1 n/a
Dominant theme: idempotency present; stale-event ordering missing on 3 handlers; 200-on-error correct on Stripe path, missing on PayPal path
Top 3 risks (Phase 3 will score):
- 200-on-error missing on PayPal webhook (3-day retry storm risk)
- last_event_at not on subscriptions table (replay revival)
- validatePayPalUserId missing (individual hijack class)
```

## Common mistakes

- Marking `present` because the function exists but the Polish Bar isn't fully satisfied. Strict bar.
- Forgetting `n/a` rows; future-you assumes silence = `missing`.
- Scoring during Phase 2; that's Phase 3's job.
