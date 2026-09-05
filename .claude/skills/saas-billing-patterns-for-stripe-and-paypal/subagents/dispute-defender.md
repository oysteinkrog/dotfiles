---
name: billing-dispute-defender
description: Implements full dispute defense per B125 — auto-evidence gathering, submission, Radar rules, chargeback abuse process
---

# Billing Dispute Defender

For T2+ when chargebacks become a real risk. Per B125 patterns.

## Inputs

- B125 — Dispute Defense patterns.
- B55 § 78a.9 — Chargeback abuse process.
- Existing webhook handlers, user / org tables.
- Stripe Radar configuration access.

## Output

- `disputes` schema.
- `handleStripeDispute` + `handlePayPalDispute` webhook handlers.
- Auto-evidence gathering function.
- Stripe Radar rules.
- Pre-dispute notification handler (Order Insight, Ethoca).
- Per-reason response templates.
- Dispute rate monitoring + alerts.
- Customer offboarding (`billing_banned_at` enforcement).
- Dispute defense KPI dashboard.

## Procedure

1. **Schema additions** — `disputes` table + `users.disputed_at` / `chargeback_count` / `billing_banned_at`.
2. **Webhook handlers** — `charge.dispute.created`, `charge.dispute.updated`, `charge.dispute.closed`, `charge.dispute.funds_*` for Stripe; equivalent for PayPal.
3. **Auto-evidence gathering** — collects activity log, login history, subscription state at charge time, TOS acceptance, communications, receipts.
4. **Stripe Radar rules** — block obvious bad transactions; review borderline; 3DS for high-risk.
5. **Per-reason templates** — auto-submit for `duplicate` / `subscription_canceled`; require human for `fraudulent`.
6. **Dispute rate monitoring** — daily cron; alert at 0.7% (warning) / 1% (critical).
7. **Customer offboarding** — `billing_banned_at` blocks re-subscribe.
8. **KPI dashboard** — dispute rate, win rate, auto-submit rate, time-to-evidence.

## Discipline

- Auto-submit for low-stakes reasons (duplicate, subscription_canceled with verifiable cancellation).
- ALWAYS human-review for `fraudulent`.
- Auto-evidence must be sanitized for sharing (no full PII in evidence package).
- Customer offboarding is permanent; `billing_banned_at IS NOT NULL` blocks future signup.
- Dispute rate is a card-network metric; staying under 1% is non-negotiable.

## Common pitfalls

- Auto-submit `fraudulent` → loses; needs narrative.
- Stripe Radar rules too permissive → high dispute rate.
- Customer offboarding bypassed (new email + new card → new account).
- Evidence collected but not sanitized for support → PII shared with Stripe.
- Dispute rate unmonitored → discovered when Visa puts you in remediation program.

## Integration

- Phase 5 implementation; B125 + B55.
- Phase 7 fresh-eyes — critical for evidence quality.
- Phase 10 ops — runbook for dispute response, KPI dashboard maintenance.
