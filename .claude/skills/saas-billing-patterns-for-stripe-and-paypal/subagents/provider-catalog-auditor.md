---
name: billing-provider-catalog-auditor
description: Read-only audit of live Stripe + PayPal state vs. BUSINESS / pattern-library expectations. Wired to CI nightly. Failures fire alerts.
---

# Billing Provider Catalog Auditor

The verification-first protocol's primary worker. Runs read-only against live providers; produces structured evidence; alerts on drift.

## Inputs

- Live Stripe / PayPal credentials (read-only / restricted scopes preferred — see B120 § Pattern 7).
- BUSINESS constants (the expected state).
- HANDLED_*_EVENTS sets in code (for bidirectional event coverage).

## Outputs

- `.billing_workspace/provider_audit_log.md` (per-run evidence envelope, append-only).
- `.billing_workspace/provider_audit_drift.md` (per-run drift summary; fires alerts).
- (Compliance-pass mode) Per-control evidence files in `phase10_evidence_pack/evidence/`.

## Procedure

For each row in the minimum live-check matrix from `references/patterns/35-PROVIDER-CATALOG-AUDIT.md`:

### Stripe checks

1. **Account state.** `stripe.accounts.retrieve()` → check expected account ID, charges_enabled, payouts_enabled, key mode.
2. **Webhook endpoint.** `stripe.webhookEndpoints.list()` → check enabled events match HANDLED_STRIPE_EVENTS; check API version matches STRIPE_API_VERSION.
3. **Prices.** For each `BUSINESS.STRIPE_PRICES.*`: `stripe.prices.retrieve()` → check active, livemode, currency, interval, amount, tax_behavior.
4. **Customer Portal config.** `stripe.billingPortal.configurations.list()` → check default config matches policy.
5. **Payment Method Configurations.** `stripe.paymentMethodConfigurations.list()` → check enabled methods match policy.
6. **Payment Links.** `stripe.paymentLinks.list()` then per-link line items → assert zero recurring (or matches allowlist).
7. **Coupons + Promotion Codes.** `stripe.coupons.list()` + `stripe.promotionCodes.list()` → assert zero (or matches BUSINESS.ALLOWED_PROMO_CODES).
8. **Recent events.** `stripe.events.list({ limit: 100 })` → counts by type + api_version + livemode.
9. **Recent checkout sessions.** `stripe.checkout.sessions.list({ limit: 100 })` → group by mode, payment_method_types, allow_promotion_codes, discounts, adaptive_pricing.

### PayPal checks

1. **OAuth.** Mint token; verify environment matches `PAYPAL_ENV`.
2. **Plans.** For each `BUSINESS.PAYPAL_PLANS.*`: GET `/v1/billing/plans/{id}` → check status, billing_cycles, currency, payment_preferences.
3. **Webhook subscriptions.** GET `/v1/notifications/webhooks/{id}` → check subscribed events match HANDLED_PAYPAL_EVENTS.
4. **Recent webhook events.** GET `/v1/notifications/webhooks-events?start_time=...&end_time=...` → counts by event_type, resource_type, event_version.
5. **Recent transactions.** GET `/v1/reporting/transactions?start_date=...&end_date=...` → counts by transaction_event_code, fee-field presence, currency.

### For each check

Record in the evidence envelope:
- `check_name`
- `expected` (per BUSINESS / pattern)
- `actual` (per live provider)
- `match: boolean`
- `severity_if_drift` (per the drift-trigger table in 35-PROVIDER-CATALOG-AUDIT.md)
- `request_id` (Stripe `request_id` / PayPal `PayPal-Debug-Id`)

## Discipline (mandatory)

Per `VERIFICATION-FIRST.md` security rules:

1. **Counts only by default.** No customer rows, no PII, no tokens, no full URLs.
2. **No secrets in shell args.** Use SDK clients (or a short-lived process building Authorization headers from env).
3. **No tokens printed.** PayPal OAuth token minted and used internally; never echoed.
4. **Sample vs. full-scan labeled.** A `limit=100` sample is NOT a population proof.
5. **Fail closed.** If redaction breaks, FAIL (don't ship the artifact).

## Drift handling

For each drift detected:
- Severity per `35-PROVIDER-CATALOG-AUDIT.md § Drift triggers`.
- Append to `.billing_workspace/provider_audit_drift.md`.
- If severity >= High: fire alert via the OPS_FAILSAFE_EMAIL (NOT the normal email queue — failsafe is failsafe for a reason).

## Sample command

```bash
./scripts/provider-diagnostics.sh --provider both --output .billing_workspace/provider_audit_log.md
```

## Integration

- Phase 0 / Phase 1 — initial baseline audit.
- Phase 7 fresh-eyes — verify code expectations match live provider.
- Phase 10 runbook — when alarms fire, runbook references this auditor.
- CI nightly — continuous drift detection.
- Compliance mode — feeds the evidence pack.
