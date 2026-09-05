---
name: billing-marketplace-implementer
description: Implements Stripe Connect / marketplace patterns per B115 — connected accounts, fee splits, dispute handling
---

# Billing Marketplace Implementer

For projects building marketplaces (sellers + buyers) or processing payments on behalf of sub-merchants.

## Inputs

- B115 — Marketplace & Connect patterns.
- B125 — Dispute Defense (Connect-aware variant).
- Stripe Connect configuration (Standard / Express / Custom decision).

## Output

- `connected_accounts` schema.
- `marketplace_transactions` schema.
- Connect webhook endpoint (separate from platform webhook).
- Onboarding flow (Express by default).
- Charging on behalf of (Direct / Destination / On Connected Account — pick + document).
- Capability monitoring cron.
- Dispute handling for Connect transactions.
- 1099-K configuration (US sellers).

## Procedure

1. **Account-type decision** — Standard / Express / Custom. Default Express.
2. **Onboarding flow** — collect basic info; redirect to Stripe AccountLinks; handle return.
3. **Connect webhook endpoint** — separate route; separate signing secret.
4. **Account-mismatch check** — every Connect event has `event.account`; verify against `connected_accounts` table.
5. **Charge model** — Direct vs Destination vs On Connected Account; document.
6. **Refund flow** — `reverse_transfer` + `refund_application_fee`.
7. **Capability monitoring** — daily cron checks each account's `charges_enabled` + `payouts_enabled`.
8. **Dispute liability** — document who pays.
9. **1099-K** — enable in Stripe Connect Dashboard.

## Discipline

- Connect webhook endpoint MUST be separate from platform.
- Account-mismatch check on EVERY Connect event.
- Fee math includes Connect overhead.
- Seller dispute-rate monitoring + ban policy.
- Marketplace transaction has explicit fee/seller/platform breakdown stored.

## Common pitfalls

- Using platform webhook for Connect events (per § 78a.1 attack vector).
- Refund without `reverse_transfer` (seller keeps money).
- No capability monitoring (sellers' accounts go inactive silently).
- Fee calc ignores Connect overhead.
- No 1099-K (US compliance).

## Integration

- Phase 5 implementation when marketplace feature added.
- Phase 7 fresh-eyes critical here (security implications high).
- Coordinates with B125 for Connect-specific dispute defense.
