---
name: billing-policy-portability-auditor
description: Verifies trial / discount / deal / annual / multi-currency policy is consistently expressed across BUSINESS constants, provider state, and reporting
---

# Policy Portability Auditor

For when the SaaS supports trials / discounts / deals / annual / multi-currency. Verifies the policy matrix from `references/methodology/BUSINESS-MODEL-PORTABILITY.md` is consistently expressed.

## Inputs

- `BUSINESS` constants (the declared policy).
- Live Stripe + PayPal state.
- Local schema (deals table, settlement_ledger, etc.).
- Recent reporting outputs (MRR, ARR, churn breakdowns).

## Output

`.billing_workspace/policy_portability_audit.md`:

```markdown
# Policy Portability Audit

## Declared policy (from BUSINESS)
- TRIAL_DAYS: <N>
- ALLOW_PROMO_CODES: <bool>
- ALLOWED_CURRENCIES: <list>
- ALLOWED_INTERVALS: <list>
- ALLOWED_DEAL_FAMILIES: <list>
- TAX_MODE: <stripe_tax | mor | manual>

## Provider state (live)
- Stripe coupons active: <count> (expected: <count>; matches: ✓/✗)
- Stripe promotion codes: <count>
- Stripe Payment Links recurring: <count>
- Stripe Subscription discounts active: <count>
- Stripe trial cycles in active subs: <count>
- Stripe Customer Portal `subscription_update`: <enabled/disabled>
- Stripe Customer Portal `promotion_codes`: <enabled/disabled>
- PayPal plans with TRIAL cycles: <count>
- PayPal plans non-USD: <count>

## Local schema
- `subscriptions.trial_*` columns present: <yes/no>
- `subscriptions.contract_*` columns present: <yes/no>
- `deals` table exists: <yes/no>
- `deal_redemptions` table exists: <yes/no>
- `settlement_ledger` table exists: <yes/no>

## Reporting consistency
- MRR includes trial subs as $0: <yes/no>
- MRR excludes gratis subs: <yes/no>
- ARR reported separately for annual subs: <yes/no>
- Churn distinguishes trial-expired / paid-cancelled / payment-failed: <yes/no>
- Per-currency MRR breakdown: <yes/no>
- Discount realization tracked at invoice level: <yes/no>

## Drift findings
[per-row: declared vs. actual; severity; suggested fix]

## Abuse controls (if discounts enabled)
- Promotion-code rate limit: <yes/no>
- Self-referral block: <yes/no>
- Coupon-stacking alert: <yes/no>
- Expired-code acceptance alert: <yes/no>
```

## Procedure

1. Read BUSINESS constants.
2. Use provider-catalog-auditor outputs (or run independently) for live provider state.
3. Inspect schema (Drizzle / Prisma / equivalent).
4. Read recent reporting code outputs.
5. Compare; emit drift findings with severity.

## Discipline

- Counts-only redaction.
- "Declared no trials" + "active trial cycles found" = Critical drift.
- Even if your project is "no trial / no discount", run this auditor periodically — Dashboard clicks can violate the policy.

## Integration

- Phase 1 / Phase 7 (verifies declared policy is enforced).
- Compliance-pass mode (evidence file in pack).
- Triggered after any Dashboard change.
- Used by add-feature mode when adding trials / discounts / annual / multi-currency.
