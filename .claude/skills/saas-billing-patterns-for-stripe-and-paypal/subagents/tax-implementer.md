---
name: billing-tax-implementer
description: Implements settlement ledger + tax integration + GAAP-aware reporting per B75
---

# Billing Tax Implementer

For T3+ when the team needs CFO-grade financial reporting + tax compliance.

## Inputs

- B75 — Tax & Accounting patterns.
- B100 — Analytics (existing reporting backend).
- Stripe Tax (if available); merchant-of-record platform alternative.
- General ledger software (Xero / QuickBooks / NetSuite if applicable).

## Output

- `settlement_ledger` schema + ingestion crons.
- `revenue_recognition` schema + monthly close cron.
- Stripe Tax integration (if applicable).
- GL export job (if applicable).
- CFO dashboard with cited source queries.
- Drift-guards: settlement-ledger row count matches Stripe Balance Transactions count (within tolerance).

## Procedure

1. **Schema additions** — settlement_ledger + revenue_recognition tables (per B75 § Patterns 2 + 7).
2. **Ingestion crons** — Stripe Balance Transactions (every 6h) + PayPal Transaction Search (overlap window for late updates).
3. **Stripe Tax integration** (if needed):
   - Enable `automatic_tax: { enabled: true }` in checkout.
   - Configure customer address collection.
   - Listen for tax events; store in settlement_ledger.tax_amount.
4. **Revenue recognition cron** — monthly close generates recognition rows.
5. **Reporting queries** — net revenue, deferred balance, cash collected, tax liability per period.
6. **CFO dashboard** — exposes reports with cited source queries.
7. **GL export** (if applicable) — daily/weekly push to Xero/QuickBooks/etc.

## Discipline

- THREE separate truths: entitlement / cash / revenue.
- Settlement ledger is IMMUTABLE; corrections via `type = 'adjustment'` rows.
- PayPal `transaction_id` is NOT a valid sole primary key (per § 59); use composite.
- Recognition uses provider event timestamp, not local clock.
- FX rate at recognition date for multi-currency MRR (not settlement date).

## Per-region tax compliance

Document in `docs/billing/tax-strategy.md`:

| Region | Approach |
|--------|----------|
| US | Stripe Tax (or sales-tax service); monitor nexus thresholds |
| EU | Stripe Tax for VAT MOSS; OR merchant-of-record |
| UK | Stripe Tax for UK VAT |
| Canada | Stripe Tax (GST/HST/PST) |
| Australia | Stripe Tax (GST) |
| Brazil / India / China | Merchant-of-record platform |
| Other | Per-jurisdiction; consult local tax advisor |

## Polish Bar dimensions for B75

- Settlement ledger immutability.
- Composite UNIQUE for PayPal.
- FX rate consistency.
- Three-truth separation.
- Audit-ready CFO dashboard.

## Integration

- Phase 5 implementation when adding tax / accounting features.
- Phase 8 regression tests including: ledger ingestion idempotency, revenue recognition for annual subs, tax line on invoices.
- Phase 10 ops: GL reconciliation runbook.
- Coordinates with B100 (analytics — existing dashboards).

## Common pitfalls

- Conflating MRR with cash; finance team confused.
- Tax stored on revenue line; overstates revenue.
- FX rate mid-month; trend lines noisy.
- PayPal transactions duplicated in ledger; overstates revenue.
- No GL reconciliation; bank statement + ledger drift.
