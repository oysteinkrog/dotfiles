# Runbook: BILLING-DISCREPANCY (Deep)

The most common high-stakes ticket category for SaaS. Mishandling = chargebacks, churn, or charging the wrong customer. Most billing tickets reduce to a small number of root causes — this runbook indexes them.

## Trigger Conditions

- "I paid but I'm not subscribed"
- "I cancelled but I'm still being charged"
- "Charged twice this month"
- "Says past_due but I paid"
- "Wrong plan / wrong amount"
- "Refund processed but still has access" (or vice versa)
- "My team / org subscription stopped working"
- A Stripe / PayPal dispute opened (chargeback path — see [REFUND.md](REFUND.md))
- "Invoice doesn't match what I'm seeing"

## Symptom-To-Root-Cause Map

| Symptom | Likely root cause | First thing to check |
|---|---|---|
| "I paid but I'm not subscribed" | Webhook handler didn't fire / silently failed (PayPal `BILLING.SUBSCRIPTION.ACTIVATED` missing `payer_id`) | `payment_events` for `processedAt IS NULL` |
| "Charged twice" | Idempotency key missing on retry; or genuine double-charge from provider | Stripe charges list; check `created` timestamps |
| "Past_due despite paying" | `currentPeriodEnd` not updated; `PAYMENT.SALE.COMPLETED` didn't route | `users.currentPeriodEnd` vs provider's billing period |
| "Cancelled but still charged" | Provider cross-match: started Stripe, switched to PayPal — old sub never cancelled | `users.customerId` prefix (`cus_*` Stripe, numeric PayPal) |
| "Wrong plan after upgrade" | Cache invalidation timeout > webhook timeout → entitlement stale | Redis health; user's last entitlement-refresh timestamp |
| "Team sub stuck" | Team-handler routing: `PAYMENT.SALE.COMPLETED` only routed to individual handler | Org's `subscription_status` vs `currentPeriodEnd` |
| "Refund happened but still has access" | `handleSaleRefunded` couldn't match user; `customerId` was cleared | `users.customerId` not null + matches provider record |
| "Account access lost mid-period" | Reconciliation cron flipped status incorrectly; or webhook ordering issue | Audit log for status changes; webhook event order |
| "Says I'm on a plan I never picked" | Plan promo or trial conversion failed silently | `subscription_history`; trial conversion events |

## Investigation Procedure

```bash
PROJECT="<project-path>"
ADMIN_KEY=$(grep ADMIN_API_KEY "$PROJECT/.env" | cut -d= -f2)
BASE="https://<project-domain>"
EMAIL="<customer email>"

# 1. Check our DB state
curl -s "$BASE/api/admin/users?email=$EMAIL" \
  -H "Authorization: Bearer $ADMIN_KEY" | python3 -m json.tool
# Note: subscription_status, currentPeriodEnd, customerId, plan_tier

# 2. Check payment_events for stuck/late processing
curl -s "$BASE/api/admin/payments/events?email=$EMAIL" \
  -H "Authorization: Bearer $ADMIN_KEY" | python3 -c "
import sys, json
events = json.load(sys.stdin).get('events', [])
for e in events:
    status = 'STUCK' if not e.get('processedAt') else 'OK'
    print(f'{status}  {e[\"eventType\"]}  {e[\"provider\"]}  {e.get(\"createdAt\",\"\")}')
"

# 3. Pull from provider directly
stripe customers list --email "$EMAIL"
stripe subscriptions list --customer "<cus_id>"
stripe charges list --customer "<cus_id>" --limit 10
stripe invoices list --customer "<cus_id>" --limit 10

# 4. PayPal (if applicable)
# Web dashboard: https://www.paypal.com/billing/subscriptions
# Or API: GET /v1/billing/subscriptions

# 5. Check webhook health
curl -s "$BASE/api/admin/payment-health" -H "Authorization: Bearer $ADMIN_KEY"
# Look for: webhook delivery failure rate, last successful event per provider

# 6. Find the user's payment timeline in audit_log
# Order: created → activated → period_end_extension → ...
```

## PayPal-Specific: Silently Dropped Events

PayPal dispatches many event types. The handler MUST switch on each:

| Handled (per JSM SKILL) | Silently Dropped (debug-only log) |
|---|---|
| `BILLING.SUBSCRIPTION.CREATED` | `BILLING.SUBSCRIPTION.UPDATED` (plan changes!) |
| `.ACTIVATED` | `.EXPIRED` |
| `.CANCELLED` | `.PAYMENT_FAILED` |
| `.SUSPENDED` | `.RE-ACTIVATED` |
| `PAYMENT.SALE.COMPLETED` | `PAYMENT.SALE.PENDING` |
| `.DENIED` | `BILLING.PLAN.UPDATED` |
| `.REFUNDED` | |
| `.REVERSED` | |
| `CUSTOMER.DISPUTE.CREATED` | |

If a billing ticket matches a "silently dropped" type, the handler is the bug. Fix the handler, then process the missed event by hand.

## Provider Cross-Match Trap

The most subtle bug:

```
1. User pays via PayPal in March → users.customerId = "I-PAYPAL-ID"
2. User upgrades via Stripe in June → users.customerId = "cus_STRIPE_ID" (overwrite)
3. PayPal sub still active → PayPal still tries to charge in July
4. PayPal `PAYMENT.SALE.COMPLETED` arrives → handler looks for users.customerId
   matching the PayPal payer_id → no match → handler returns early
5. Customer charged but DB unchanged.
```

Fix: maintain a `payment_provider_history` table that tracks every customerId the user has had with each provider, never overwrite.

## Investigating "Charged Twice"

Both possibilities:

- **Real double-charge**: Stripe / PayPal failed to dedupe an idempotency-keyed retry. Refund the duplicate immediately + apologize.
- **Apparent double-charge**: prorated invoice for plan upgrade + standard period charge in the same week. Customer sees both, panics. Explain the prorate, no refund needed (but offer one if relationship is at risk).

```bash
# Distinguish:
stripe charges list --customer "cus_id" --limit 10
# Real double: two charges, same amount, < 5 minutes apart, similar idempotency
# Prorated: amounts differ, descriptions differ ("subscription_proration" vs "subscription_cycle")
```

## Drafts

### BILLING-FIXED-AND-EXPLAINED

```
Thanks for flagging this. Here's what happened and what we did:

Diagnosis: <one-line root cause, e.g., "a PayPal webhook for your plan
upgrade got dropped due to a missing handler — that's our bug">

Fix: <one-line, e.g., "we processed your payment manually and updated
your subscription status. You should now see the correct plan reflected
on your account.">

Verification: <one-line, e.g., "you can confirm by visiting /billing —
let me know if anything still looks off">

Preventing recurrence: <one-line, e.g., "we've added the missing
webhook handler so this can't recur">.

Sorry for the friction.
```

### BILLING-CHARGED-TWICE-REFUND

```
Confirmed — you were charged twice on <date>. The duplicate has been
refunded ($<amt>). It'll appear in 5-10 business days on your card.

Root cause: <one-line, e.g., "an idempotency-key bug in our retry
logic. Fixed.">

If you see anything else off, just reply.
```

### BILLING-PRORATED-NOT-A-DOUBLE-CHARGE

```
I see why this looks like a double charge — there's a $<X> proration
plus the regular $<Y> for your new plan. Here's the breakdown:

- $<X> on <date>: prorated charge for the upgrade (covers <num> days
  remaining on your old plan at the new rate)
- $<Y> on <date>: regular monthly charge starting your new billing
  cycle

Net: you paid for the upgrade portion + the new cycle, not double.

That said, if this came as a surprise, we can credit the proration. Let
me know.
```

### BILLING-PROVIDER-CROSSMATCH

```
Found it — you originally subscribed via PayPal, then upgraded via
Stripe. We had a bug where the upgrade link broke the PayPal
cancellation, so PayPal kept charging.

We've:
- Cancelled the PayPal subscription (effective immediately)
- Refunded $<X> for the duplicate charge
- Verified your Stripe subscription is active and on the correct plan

Sorry for the headache.
```

## Hard-Won Lessons

1. **Auto-deploy disabled** = fix in `main` doesn't reach production. Always check Vercel deploy timestamp before claiming "fixed".
2. **Tier resolved before authentication** = paid users get 429 / get classified as anonymous on the request that just paid. Move identity resolution before rate-limit + entitlement checks.
3. **`Math.random()` for ticket IDs** in real-world code (cass-confirmed). Always `crypto.randomUUID()`.
4. **Webhook secret rotated, old in env** = silent 500s on every webhook; verify-signature returns false. Check Sentry for spike in webhook 500s after any ops change.
5. **Cache invalidation timeout > webhook timeout** under Redis degradation: webhook responds late, Stripe retries, retry storm. Move cache-invalidation to async + idempotent.

## Audit Trail (Required)

```yaml
ticket_id: <id>
customer_email: <email>
diagnosis_class: <one-of: silent-webhook-drop, provider-crossmatch, idempotency-failure, cache-timeout, plan-upgrade-prorate, ...>
investigation:
  db_state_before: <snapshot>
  provider_state_before: <stripe / paypal snapshot>
  events_processed_manually: [<event_id>, ...]
fix_applied:
  what: <description>
  who_authorized: <owner-handle>
  refund_id: <if any>
verification: <link / curl output>
```

## Companion Refs

- [REFUND.md](REFUND.md) — refund execution mechanics
- [DATA-LOSS.md](DATA-LOSS.md) — when billing data was actually corrupted
- [OUTAGE-COMMS.md](OUTAGE-COMMS.md) — when many billing tickets share one root cause
