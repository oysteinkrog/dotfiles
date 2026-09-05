---
name: billing-harmonizer
description: Phase 6 — cross-bundle consistency for one theme (idempotency, env, exclusions, provenance, error codes, secrets, types)
---

# Billing Harmonizer

Phase 5 implementers worked in parallel; harmonization makes the seams clean.

## Inputs

- Your assigned theme (one of: idempotency, env-and-constants, exclusions, provenance, error-codes, secret-custody, types)
- All Phase 5 commits on this branch (`git log --oneline main..HEAD`)
- The pattern library

## Outputs

- A `harmonize: <theme>` commit (or commits)
- Append a one-section summary to `.billing_workspace/phase6_harmonization_diff.md`

## Theme rules

### Idempotency
- Every UPDATE WHERE clause includes the right ordering + ownership guards (`last_event_at`, `subscription_id`, status-set guard).
- Every Stripe SDK call passes `idempotencyKey`; every PayPal API call includes `PayPal-Request-Id`.
- DB-side UNIQUE constraints + partial UNIQUEs match the documented schema.

### Env / constants
- Single source of truth for `STRIPE_API_VERSION`, `BUSINESS`, `WebhookErrorCodes`, `ROUTES`.
- No literal API version strings outside `stripe-config.ts`.
- No plan-ID literals outside `BUSINESS`.
- All env reads go through validated `env`, not `process.env` directly.

### Exclusions
- Every cron / publisher / reader imports from one canonical `exclusions.ts`.
- Drift-guard list (`cronsThatMustExclude`) is up to date.
- Activity feed and metric counters AGREE on test signups.

### Provenance
- Every cache value carries `live | fallback | unavailable`.
- Renderers visibly degrade when not `live`; never render `unavailable` as a number.

### Error codes
- Every error path uses a registered code from `WebhookErrorCodes` / `PaymentErrorCodes`.
- No inline error strings.
- Drift-guard test pins completeness.

### Secret custody
- No `NEXT_PUBLIC_*` for any billing secret.
- All secrets in production-only env, marked sensitive.
- `OPS_FAILSAFE_EMAIL` is a different inbox from `ADMIN_EMAIL`.

### Types
- No `any` in billing code.
- Status enums match across bundles.
- Drizzle / Prisma schema matches Postgres exactly.

## Coordination

Reserve files via Agent Mail BEFORE editing — multiple harmonizers may touch the same file (especially `env.ts`, `schema.ts`, `WebhookErrorCodes`).

```
file_reservation_paths(project_key, agent_name, paths=["src/env.ts"], ttl_seconds=1800, exclusive=true, reason="harmonize-env")
```

## Discipline

- Don't widen function contracts to make things "consistent." Some asymmetries are real (the team subscription handlers' Activated-vs-Cancelled WHERE clauses are asymmetric on purpose). Read the source pattern's "Why" section before flattening.
- Run `tsc --noEmit` and tests after every commit.
- If your theme requires no changes, write the summary line: "<theme>: no changes needed; per-bundle implementations already consistent."

## Common mistakes

- Consolidating by widening a function's contract. Don't make `updateSubscriptionStatus` accept arbitrary metadata.
- Breaking a per-bundle nuance for "consistency." Some asymmetries are intentional.
- Forgetting to update the drift-guard list when adding new patterns.
- Editing without an Agent Mail reservation → merge conflicts.
