# Coverage Matrix

The matrix is the contract between Phase 1 (archaeology) and Phase 4 (planning). It must be machine-greppable, idempotent across runs, and honest about partial coverage.

---

## Generation

`scripts/generate-coverage-matrix.mjs` walks `references/patterns/` and emits one row per pattern with status fields blank. The agent (or the `coverage-mapper.md` subagent) fills the rows from Phase 1 findings.

```bash
./scripts/generate-coverage-matrix.mjs > .billing_workspace/phase2_coverage_matrix.md
```

---

## Schema

```markdown
| Pattern | Status | Evidence | Operator | Notes |
|---------|--------|----------|----------|-------|
| 00-NORTH-STAR § Provider-as-source-of-truth | present | docs/architecture.md:14 | ⊙ | Documented; verified by `getCurrentMrrSnapshot` provenance |
| 10-SCHEMA § payment_events UNIQUE(provider, event_id) | present | supabase/migrations/2025...sql:18 | 🔒 | constraint name payment_events_unique |
| 10-SCHEMA § subscriptions.last_event_at | missing | — | ⏱ | Column doesn't exist; UPDATEs use updatedAt |
| 40-WEBHOOKS § recordWebhookEvent dedup | present | src/lib/webhooks/inbound.ts:42 | 🔒 | Uses 23505 + message check |
| 40-WEBHOOKS § 200-on-error after recordWebhookEvent | partial | src/app/api/stripe/webhook/route.ts:88 | ⤴ | Stripe handler ✓; PayPal handler returns 500 inside catch |
| 50-SECURITY § validatePayPalUserId | missing | — | ⌖ | metadata.user_id trusted directly |
| 50-SECURITY § subscription_id WHERE on team UPDATEs | partial | src/lib/services/team-billing.ts:412 | ⌖ | activated handler ✓; cancelled handler missing the predicate |
| 50-SECURITY § replay-staleness gate | missing | — | ⏱ | No last_event_at column; can't enforce |
| 60-STATE § paused_for_org enum value | n/a | — | — | No team plans planned in this product |
| 70-DUNNING § DUNNING_STAGES { 0, 7, 14, 21 } | partial | src/lib/services/dunning.ts:8 | 🔁 | Stages defined but `wasEmailDeliveredSince` not implemented |
| 90-RELIABILITY § cron pg_try_advisory_lock | missing | — | ⊞ | Crons rely on Vercel single-isolate assumption (not safe) |
| 100-ANALYTICS § canonical exclusions module | missing | — | ⛓ | Each cron / publisher has its own filter; drift risk |
| 110-OPERATIONS § secret-custody matrix | missing | — | 🔐 | No documented inventory; rotation cadence unclear |
| ... | ... | ... | ... | ... |
```

The order of rows mirrors `references/patterns/`: 00 → 10 → 20 → ... → 110.

---

## Status semantics (precise)

### `present`

The pattern exists AND satisfies every Polish Bar dimension that applies to it. `present` is the strictest status; it means a fresh-eyes reviewer would not flag it.

Examples:
- `recordWebhookEvent` exists, includes the 23505 + message check, returns boolean correctly, has a regression test for replay → `present`.
- `last_event_at` column exists AND every UPDATE on subscriptions/orgs includes the WHERE clause AND there's a drift-guard test → `present`.

### `partial`

The pattern exists but fails at least one Polish Bar dimension. The Notes column must explain *which dimension* fails.

Examples:
- `recordWebhookEvent` exists but doesn't check the 23505 message variant → `partial` (driver-shape edge case unhandled).
- `last_event_at` column exists, most UPDATEs include the WHERE, but the team handler doesn't → `partial` (incomplete coverage).
- `validatePayPalUserId` exists but the cross-provider switch branch (`cus_` prefix) is missing → `partial`.

### `missing`

The pattern doesn't exist at all.

Examples:
- No `payment_events` table → `missing`.
- No exclusions module — each consumer hand-rolls a filter → `missing`.

### `n/a`

The pattern doesn't apply to this project, with a written justification.

Examples:
- `paused_for_org` enum: no team plans → `n/a, no team plans in product roadmap`.
- PayPal-specific patterns: Stripe-only product → `n/a, single-provider`.
- SCA / 3DS routing: business-customer-only B2B SaaS in non-EU markets → `n/a, low-SCA exposure`. (Reconsider if you expand to EU.)

`n/a` requires a justification because future-you reads this matrix and assumes silence = `missing`.

---

## How Phase 3 reads the matrix

The risk scorer:
1. Skips `present` and `n/a` rows.
2. For each `partial` and `missing` row, scores 1–9 using [RISK-SCORING.md](RISK-SCORING.md).
3. Joins to the source-pattern file to know what the fix looks like (so the executive summary can name it).

Rule: every gap must trace to a pattern row. If a Phase 1 finding has no pattern row, that's a *signal that the pattern library is incomplete* — file an issue against this skill.

---

## How Phase 4 reads the matrix

The planner:
1. For every score ≥3 gap, creates a task.
2. Resolves task ordering via the bundle dependencies in [PHASES.md § Phase 4 dependency rules](PHASES.md).
3. Bundles tasks per implementer (one implementer per bundle in Phase 5).

Rule: every task references the pattern row it closes. The matrix is updated to `present` only when Phase 5/6/7/8 confirm the dimension passes.

---

## Idempotency across runs

Resuming a run: re-generate the skeleton, then **merge** with the prior matrix (don't blow away). The merger logic:
- New rows (added since last run) → start blank.
- Existing rows with status `present` → carry forward IF the cited file:line still exists; otherwise re-evaluate.
- Existing rows with status `partial`/`missing` → carry forward UNTIL Phase 5/8 marks them `present`.
- Rows with status `n/a` → carry forward UNLESS the project state changed (e.g., team plans were added).

`scripts/merge-coverage-matrix.mjs` (TODO if needed; for now, agents do this manually with a diff-and-eyeball pass).

---

## Common matrix mistakes

- **Marking `present` on hope.** "The function exists" → at most `partial`. The Polish Bar is the bar.
- **`n/a` without justification.** Future-you will assume the row never applied; you'll re-discover it the hard way.
- **No file:line on `present`.** If you can't cite it, you didn't verify it.
- **Skipping rows because "this project doesn't do that yet."** Mark `n/a` with the reason; don't omit.
- **Scoring during Phase 2.** Phase 2 is classification only; Phase 3 does scoring.
