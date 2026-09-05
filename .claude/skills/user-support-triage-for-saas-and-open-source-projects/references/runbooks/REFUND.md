# Runbook: REFUND

When a customer requests a refund. The cost of getting this wrong is high (chargebacks, churn, regulator complaints), so this runbook is more rigid than the others. **Owner approval required before issuing.**

Use [COMPENSATION-CALCULUS.md](../COMPENSATION-CALCULUS.md) through the `🎁 GOODWILL` operator when the question is not "is money owed?" but "what remedy best fits the harm?" The calculus recommends a shape; this runbook still controls evidence collection, execution, and audit.

## Trigger Conditions

The customer message contains:
- "refund", "money back", "cancel and refund", "I was charged"
- A dispute via Stripe Dashboard / PayPal Resolution Center (chargeback shape)
- A subscription cancel + "I was charged for the next period"
- "I'd like a refund within the [X-day] window"

## Evidence To Collect (Before Drafting)

```bash
# 1. Verify customer state in your DB
ADMIN_KEY=$(grep ADMIN_API_KEY <project>/.env | cut -d= -f2)
BASE="https://<project-domain>"

curl -s "$BASE/api/admin/users?email=$EMAIL" \
  -H "Authorization: Bearer $ADMIN_KEY" | python3 -m json.tool

# 2. Pull payment history from the provider (which one paid?)
stripe customers list --email "$EMAIL"
stripe subscriptions list --customer "<cus_id>"
stripe charges list --customer "<cus_id>" --limit 5

# OR PayPal:
paypal subscriptions list --email "$EMAIL"   # (or via web dashboard)

# 3. Read recent payment_events for stuck/unprocessed
curl -s "$BASE/api/admin/payments/events?email=$EMAIL" \
  -H "Authorization: Bearer $ADMIN_KEY"

# 4. Look at the user's actual product usage in the period
# (light usage = good-faith refund; heavy usage = harder call)
```

## Decision Tree

First split owed-money from goodwill:

- **Owed money**: duplicate charge, statutory refund, provider error, contractual SLA credit, or product not delivered. This is not "generosity"; execute correctly after owner/policy approval.
- **Goodwill**: the customer got the core product but suffered time, trust, launch, outage, or support-handling harm. Use the four dials from [COMPENSATION-CALCULUS.md](../COMPENSATION-CALCULUS.md) and surface the recommendation to the owner.

```
Customer requests refund within first 14 days?
├─ Yes → STANDARD-REFUND-WINDOW path (most lenient)
│        Issue refund + cancel sub. Owner approval still required.
│
├─ No, but within 30 days, light usage, first complaint?
│   → DISCRETION path: surface to owner with usage data and recommendation.
│
├─ No, > 30 days, OR heavy usage, OR repeat refund-seeker?
│   → DECLINE path: draft polite decline + offer alternative (cancel-only).
│   → If user pushes back hard → escalate to owner.
│
├─ Customer started a chargeback before contacting us?
│   → CHARGEBACK path: Stripe/PayPal will hold our funds; respond to dispute
│     within 7 days; offer voluntary refund + ask them to drop the dispute.
│     (Voluntary refund > losing the chargeback fee + reputation hit.)
│
└─ Customer alleges "I was charged but never used the service"?
    → INVESTIGATE: pull usage logs. If actually unused, refund + apology.
                   If used, gather evidence + go to DISCRETION.
```

## Jurisdiction Considerations

| Region | Legal floor |
|---|---|
| **EU/UK** | 14-day right of withdrawal for digital content unless user explicitly waived after performance started (UK CRA 2015, EU CRD 2011/83 Art. 16(m)). Stripe Checkout consent checkbox covers this if implemented. |
| **US** | No federal SaaS refund law; FTC enforces stated policy. Chargeback rights via card networks (Reg E/Z). |
| **California** | Auto-renewal disclosures (CA Auto-Renewal Law); cancel within 30 days of first charge → most likely full refund expected. |
| **Australia** | ACL guarantees: refund mandatory if "not as described" or "not fit for purpose". |
| **Canada** | Provincial: Ontario CPA 30-day cooling-off for online; Quebec consumer protection. |

## Refund Execution (After Owner Approval)

```bash
# Stripe (most common)
stripe refunds create --charge ch_XXX
# Optional: --reason requested_by_customer | duplicate | fraudulent
# Stripe TS SDK union for `reason` is narrow; cast carefully.

# Cancel subscription (no proration, no grace period)
stripe subscriptions cancel sub_XXX --invoice-now=false

# PayPal (if applicable)
paypal payments refund --capture-id <CAPTURE_ID> --amount <AMT>

# Revoke access in your DB
psql -c "UPDATE users SET subscription_status='none', current_period_end=NOW() WHERE email='$EMAIL';"
```

## Drafts

### REFUND-APPROVED

```
Refund processed. Here's what we did:

- Subscription cancelled effective immediately
- Refund of $<AMOUNT> issued to your original payment method
  (typically 5-10 business days to appear)
- Account access has been updated

We're sorry it didn't work out. If there's anything we could have done
differently, we'd genuinely appreciate the feedback.
```

### REFUND-DECLINED-OUT-OF-WINDOW

```
Thanks for reaching out. Our refund policy is <policy-text> — at
<duration> since the charge, this falls outside that window.

I can't issue a refund here, but I'd like to make sure you can get value
going forward. What was the friction that led you to reach out?

If you'd like to cancel future renewals so you're not billed again, I can
do that immediately. Just say the word.
```

### REFUND-DISCRETION-WITH-USAGE

```
Thanks for the note. Looking at your account, I see you've been using
<feature/X> over the past <duration>. We can offer a <pro-rated/partial>
refund of $<AMT> here — does that work?

(Just want to be transparent: full refunds are usually within our 14-day
window; we can stretch a bit for first-time complaints.)
```

### REFUND-CHARGEBACK-OPENED

```
Thanks — I see you've also opened a dispute with your card. We'd much
rather refund directly than fight the dispute, so we're happy to issue
a full refund of $<AMT> right now.

If you can withdraw the dispute on your end (your card-issuer's support
can do that), it saves both of us the back-and-forth. Once you confirm
withdrawal, we'll process the refund.

(If you'd prefer the dispute path, that's fine too — we'll process within
the dispute window. Just slower for you.)
```

## Audit Trail (Required)

After issuing a refund, log:

```yaml
ticket_id: <id>
customer_email: <email>
refund_amount: $<amt>
refund_currency: <ccy>
provider: stripe | paypal
charge_id: <id>
refund_id: <id>
sub_cancelled: <sub_id> | null
reason_internal: <our-classification>
reason_customer: <their-words>
approver: <owner-handle>
runbook_path: REFUND
```

Write to `audit_log` table OR commit to `<workspace>/refunds-<date>.log`.

## Anti-Patterns

| Don't | Why |
|---|---|
| Auto-issue without owner approval | Easy to set a precedent that costs $$$ |
| Decline without explaining | Customers escalate to chargeback; you lose the dispute fee |
| "Send to billing" with no internal context | Multiple agents touching same case → conflicting answers |
| Cancel sub without confirming refund hit | Customer sees "cancelled" but not the money back; opens 2nd ticket |
| Quote a "30-day refund policy" if you don't actually have one | One-off promise becomes implicit policy |
| Refund without revoking access | User keeps using product after refund |
| Stripe `RefundReason` typed cast errors | Stripe TS SDK union is narrow; document the cast or it breaks |

## Repeat Refund-Seekers

If the same customer email has requested >2 refunds in a year:
- Block new sign-ups under that email at the auth layer
- Document in customer record
- Surface to owner before any further refund

## Chargeback Reverse-Math

```
voluntary refund $X with 5-min agent time
  vs
chargeback at $X + $15 dispute fee + 1h evidence collection + ratio impact
```

The voluntary refund is almost always cheaper. Stripe chargeback monitoring fires at 0.65% ratio, which is much closer than people think.
