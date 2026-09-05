# Bundle B125 — Dispute Defense

> **Where this comes from.** § 78a.9 (chargeback abuse process) + cross-reference with B25 (customer support) + B45 (admin operations) + Stripe Radar docs.

When a customer (or attacker) files a chargeback, the bank reverses the charge and Stripe / PayPal expects you to either (a) accept the loss or (b) submit evidence and fight. Dispute defense is the process around (b).

This bundle is the systems + process for proactive dispute prevention + reactive dispute response.

---

## Pattern 1 — Dispute lifecycle

```
T0:    Customer files chargeback with their bank
T+1d:  Stripe / PayPal receives the dispute
       - Funds debited from your account immediately
       - charge.dispute.created webhook fires
       - 7-21 days to respond (depends on card network)

T+1d to deadline: Submit evidence
T+30-90d: Bank decides
       - You win → funds returned (charge.dispute.funds_reinstated)
       - You lose → funds stay debited (charge.dispute.funds_withdrawn)
       - You lose → you pay dispute fee ($15 typical)
```

The faster you respond, the better. Automation matters.

---

## Pattern 2 — Dispute reasons taxonomy

| Reason code | Customer says | Defense difficulty |
|-------------|---------------|---------------------|
| `fraudulent` | "I didn't authorize this charge" | HARD; need to prove customer used the service |
| `duplicate` | "I was charged twice" | MEDIUM; show the two charges are different products / dates |
| `subscription_canceled` | "I cancelled but you charged me" | MEDIUM; show cancellation timestamp + last paid period |
| `product_not_received` | "I didn't get what I paid for" | MEDIUM; show usage / login activity post-charge |
| `product_unacceptable` | "Product was defective" | HARD; subjective |
| `credit_not_processed` | "Refund promised but never received" | EASY; show refund issued OR show no refund authorized |
| `general` | (catch-all) | Varies |

For SaaS subscriptions, `subscription_canceled` and `fraudulent` dominate. Both are usually defensible with proper evidence.

---

## Pattern 3 — Dispute table schema

```sql
CREATE TABLE disputes (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid REFERENCES users(id),
  provider              subscription_provider NOT NULL,
  provider_dispute_id   text NOT NULL UNIQUE,
  charge_id             text NOT NULL,
  amount                numeric(20, 4) NOT NULL,
  currency              text NOT NULL,
  reason                text NOT NULL,
  status                text NOT NULL,           -- 'needs_response' | 'under_review' | 'won' | 'lost' | 'warning_needs_response' | 'warning_under_review' | 'warning_closed' | 'charge_refunded'
  evidence_due_by       timestamptz,
  responded_at          timestamptz,
  outcome_decided_at    timestamptz,
  evidence_submitted    jsonb,                    -- whatever evidence package we submitted
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX disputes_status_idx ON disputes (status, evidence_due_by);
CREATE INDEX disputes_user_idx ON disputes (user_id);
```

---

## Pattern 4 — Dispute received → triage

```ts
// In Stripe webhook handler:
async function handleStripeDispute(event: Stripe.Event.ChargeDisputeCreated) {
  const dispute = event.data.object;
  const charge = await stripe.charges.retrieve(dispute.charge as string);
  const userId = await resolveUserFromCharge(charge);

  // Insert dispute row
  await db.insert(disputes).values({
    userId,
    provider: 'stripe',
    providerDisputeId: dispute.id,
    chargeId: charge.id,
    amount: dispute.amount / 100,
    currency: dispute.currency,
    reason: dispute.reason,
    status: dispute.status,
    evidenceDueBy: dispute.evidence_details?.due_by ? new Date(dispute.evidence_details.due_by * 1000) : null,
  });

  // Lock the user (per B55 § 78a.9)
  if (userId) {
    await db.update(users)
      .set({ disputedAt: new Date() })
      .where(eq(users.id, userId));
    await db.update(users).set({ chargebackCount: sql`${users.chargebackCount} + 1` })
      .where(eq(users.id, userId));
  }

  // Critical alert
  await createEmailJob({
    type: 'billing_critical_alert',
    recipient: env.ADMIN_EMAIL,
    payload: {
      subject: `[CHARGEBACK] User ${userId}; dispute ${dispute.id}; amount $${dispute.amount / 100}`,
      reason: dispute.reason,
      due_by: dispute.evidence_details?.due_by,
    },
    priority: 5,
  });

  // Auto-gather evidence (Pattern 5)
  await scheduleEvidenceGathering(dispute.id);
}
```

---

## Pattern 5 — Auto-gather evidence

For each dispute reason, gather the relevant evidence automatically:

```ts
async function gatherEvidenceForDispute(disputeId: string) {
  const dispute = await db.query.disputes.findFirst({ where: eq(disputes.id, disputeId) });
  const user = await db.query.users.findFirst({ where: eq(users.id, dispute.userId) });

  const evidence: Record<string, unknown> = {};

  // 1. Customer activity log (proof of usage)
  evidence.customerActivity = await db.execute(sql`
    SELECT date_trunc('day', occurred_at) as day, count(*) as actions
    FROM activity_log
    WHERE user_id = ${dispute.userId}
      AND occurred_at >= ${new Date(charge.created * 1000)}
    GROUP BY day ORDER BY day
  `);

  // 2. Login history
  evidence.loginHistory = await db.execute(sql`
    SELECT logged_in_at, ip_address, user_agent
    FROM auth_log
    WHERE user_id = ${dispute.userId}
      AND logged_in_at >= ${new Date(charge.created * 1000)}
    ORDER BY logged_in_at DESC LIMIT 20
  `);

  // 3. Subscription state at time of charge
  evidence.subscriptionAtChargeTime = await db.query.subscriptions.findFirst({
    where: and(
      eq(subscriptions.userId, dispute.userId),
      eq(subscriptions.provider, 'stripe'),
    ),
  });

  // 4. TOS acceptance timestamp
  evidence.tosAcceptedAt = user.tosAcceptedAt;

  // 5. Email communications
  evidence.recentEmailsToCustomer = await db.query.emailJobs.findMany({
    where: and(
      eq(emailJobs.recipient, user.email),
      gt(emailJobs.sentAt, new Date(charge.created * 1000)),
      eq(emailJobs.status, 'sent'),
    ),
    orderBy: desc(emailJobs.sentAt),
  });

  // 6. Customer-facing receipt
  evidence.receiptUrl = await getStripeReceiptUrl(dispute.chargeId);

  // 7. Customer signature / acknowledgment (if applicable)
  evidence.acceptanceRecord = await getAcceptanceRecord(user.id);

  // Stash for human review
  await db.update(disputes)
    .set({ evidenceSubmitted: evidence, updatedAt: new Date() })
    .where(eq(disputes.id, disputeId));

  // Notify ops to review + submit
  await createEmailJob({
    type: 'dispute_evidence_ready',
    recipient: env.ADMIN_EMAIL,
    payload: { disputeId, dueBy: dispute.evidenceDueBy, evidence: Object.keys(evidence) },
    priority: 20,
  });
}
```

---

## Pattern 6 — Submit evidence to Stripe

```ts
async function submitDisputeEvidence(disputeId: string, narrative: string) {
  const dispute = await db.query.disputes.findFirst({ where: eq(disputes.id, disputeId) });
  const evidence = dispute.evidenceSubmitted as EvidencePackage;

  await stripe.disputes.update(dispute.providerDisputeId, {
    evidence: {
      // Stripe's evidence schema — fill the relevant fields
      product_description: 'SaaS subscription to ProductName',
      service_date: dispute.created_at.toISOString().slice(0, 10),
      receipt: evidence.receiptUrl,  // URL to receipt
      customer_communication: evidence.recentEmailsToCustomer.map(e => `${e.sent_at}: ${e.type}`).join('\n'),
      customer_signature: evidence.acceptanceRecord ? 'Acceptance recorded; see customer_purchase_ip' : null,
      customer_purchase_ip: evidence.signupIp,
      customer_email_address: user.email,
      customer_name: user.name,
      access_activity_log: JSON.stringify(evidence.customerActivity),
      uncategorized_text: narrative,
      // For subscription disputes specifically:
      cancellation_policy: 'https://example.com/terms#cancellation',
      cancellation_policy_disclosure: 'Customer agreed to cancellation policy at signup',
      cancellation_rebuttal: narrative,
      refund_policy: 'https://example.com/terms#refund',
      refund_policy_disclosure: 'Refund policy displayed at signup',
      // ...
    },
    submit: true,  // SUBMIT (not just stage)
  });

  await db.update(disputes)
    .set({ status: 'under_review', respondedAt: new Date() })
    .where(eq(disputes.id, disputeId));
}
```

The narrative is human-written; the evidence package is automatic.

---

## Pattern 7 — Stripe Radar (proactive prevention)

Stripe Radar uses ML to score transactions for fraud before they're charged. Configure rules:

```
# Stripe Dashboard → Radar → Rules
Allow if: customer_email ends with one of [trusted_domains]
Block if: cvc_check = 'fail' and address_zip_check = 'fail'
Review if: card_issuer_country differs from billing_address_country
3DS if: amount > 100 and card_country = 'US'
```

For SaaS:
- Block if multiple recent declines from same IP.
- Review if disposable email domain.
- 3DS if first transaction from this customer.
- Allow if customer_id exists in your loyal-customer list.

Radar reduces chargeback rate by 20-50% for typical SaaS.

---

## Pattern 8 — Pre-dispute notifications

Some networks (Visa Order Insight, Mastercard Ethoca) send "alerts" BEFORE the chargeback files. You can:
- Refund proactively (avoids chargeback fee + loss).
- Reach out to customer with refund offer.

Stripe surfaces these via webhook events; configure in Dashboard.

---

## Pattern 9 — Dispute response automation per reason

Different reasons need different defenses; templatize:

```ts
const DISPUTE_TEMPLATES: Record<string, DisputeResponseTemplate> = {
  fraudulent: {
    autoSubmit: false,  // requires human review
    evidenceFields: ['accessActivityLog', 'loginHistory', 'customerSignature', 'serviceDate'],
    narrativeTemplate: `The customer authorized this charge on ${signupDate}. Their account was used to access ${actionsCount} times after the charge, including ${recentLogins} logins. ...`,
  },
  duplicate: {
    autoSubmit: true,
    evidenceFields: ['receipt', 'serviceDate', 'productDescription'],
    narrativeTemplate: `This charge is for ${productDescription} on ${serviceDate}. The customer's other charge was for ${otherProduct} on ${otherDate}; they are distinct transactions.`,
  },
  subscription_canceled: {
    autoSubmit: true,  // if subscription is verifiably active at charge time
    evidenceFields: ['subscriptionAtChargeTime', 'cancellationPolicy', 'recentEmailsToCustomer'],
    narrativeTemplate: `Customer's subscription was active at the time of this charge (subscription created ${subStart}, current period ${periodStart} to ${periodEnd}). They had not requested cancellation prior to this charge. ...`,
  },
  // ...
};
```

For `autoSubmit: true` cases, the system can submit without human review. For `autoSubmit: false`, queue for ops.

---

## Pattern 10 — Dispute rate monitoring + circuit breaker

Track your dispute rate; alert if it spikes:

```sql
-- Monthly dispute rate
SELECT
  date_trunc('month', d.created_at) as month,
  count(*) as disputes,
  count(*) filter (where status = 'lost') as lost,
  (SELECT count(*) FROM settlement_ledger
   WHERE type = 'charge'
     AND occurred_at >= date_trunc('month', d.created_at)
     AND occurred_at < date_trunc('month', d.created_at) + interval '1 month') as charges_in_month,
  (count(*) * 1.0 / nullif((SELECT ...), 0))::numeric(5,4) as dispute_rate
FROM disputes d
GROUP BY 1 ORDER BY 1 DESC;
```

Card networks penalize merchants with dispute rate > 0.9% (Visa) or 1% (Mastercard). At 1.5%+, you're at risk of being put on a remediation program. At 2%+, you're at risk of losing card processing entirely.

Set alerts at 0.7% (warning) and 1% (critical).

---

## Pattern 11 — Customer offboarding for disputers

Per B55 § 78a.9 + B25 § Pattern 9: a customer with disputes is permanently flagged.

```sql
-- Users with chargeback history
SELECT u.email, u.chargeback_count, u.billing_banned_at
FROM users u
WHERE u.chargeback_count > 0
ORDER BY u.chargeback_count DESC;
```

Block re-subscription if `billing_banned_at IS NOT NULL`:

```ts
// In subscription / checkout flow:
if (user.billingBannedAt) {
  return NextResponse.json({
    error: 'billing_banned',
    message: 'Your account is restricted due to prior payment disputes. Please contact support.',
  }, { status: 403 });
}
```

---

## Pattern 12 — Dispute defense KPIs

Track to gauge defense effectiveness:

| KPI | Target |
|-----|--------|
| Dispute rate | < 0.5% |
| Win rate (responded disputes) | > 50% |
| Auto-submit rate (vs needing human) | > 60% |
| Time to evidence submission (median) | < 24 hours |
| Evidence completeness score | > 80% |

Dashboard these for ops review.

---

## Pattern 13 — PayPal disputes

Different mechanics:

- PayPal disputes start as "Disputes" (informal); escalate to "Claims" if customer not satisfied.
- Webhook events: `CUSTOMER.DISPUTE.CREATED`, `CUSTOMER.DISPUTE.UPDATED`, `CUSTOMER.DISPUTE.RESOLVED`.
- Evidence submission via PayPal Dashboard or `/v1/customer/disputes/{id}/provide-evidence` API.
- Time limits: typically 10 days to respond to dispute; longer for claim escalation.

Implement parallel `handlePayPalDispute` handler.

---

## Pattern 14 — Friendly fraud / "first party fraud"

The hardest dispute class: customer used the product, then disputes. Defense:

- Strong activity logs (every login, every action, IP, device).
- Email confirmation for every billing event (proves customer received notice).
- Clear cancellation flow (proves customer DIDN'T cancel).
- Clear refund flow (proves customer didn't request refund).
- Customer signature on TOS (proves they agreed to terms).

Even with all of this, friendly-fraud win rate is < 30%. Some you absorb.

---

## Polish Bar checks for B125

- [ ] `disputes` schema with status + due_by + evidence stored.
- [ ] Dispute received → user lock + alert + evidence-gather scheduled.
- [ ] Auto-gather collects activity log, login history, subscription state, TOS, communications.
- [ ] Submit-evidence flow for dispute response.
- [ ] Stripe Radar rules configured.
- [ ] Pre-dispute notifications (Order Insight, Ethoca) handled.
- [ ] Per-reason templates: auto-submit vs human-review.
- [ ] Dispute rate monitoring + alerts at 0.7% / 1%.
- [ ] Customer offboarding policy: `billing_banned_at` blocks re-subscription.
- [ ] Dispute defense KPIs dashboarded.
- [ ] PayPal dispute handlers parallel.
- [ ] Friendly-fraud defense: activity log + email confirmations + TOS signature.
- [ ] Dispute fee accounting: settlement ledger captures dispute fee separately.

---

## Common B125 mistakes

- **No automated evidence gathering.** Operator manually pulls data; deadline missed.
- **Submit evidence without human review for `fraudulent`.** Auto-submit for fraud often loses; need narrative.
- **No Stripe Radar rules.** Default Radar lets bad transactions through.
- **Customer banned for chargeback but bypass possible (new email, new card).** Check by IP / device fingerprint too.
- **Evidence stored as plain text.** Loses structure; auditor can't verify what was actually submitted.
- **Dispute rate unmonitored.** Discovered when card network sends remediation notice.
- **Friendly-fraud absorbed without analytics.** Don't learn the patterns; same customer's pals try the same.
- **PayPal disputes ignored (different webhook events).** Loses by default.
- **Lock customer access on dispute but no offboarding flow.** Customer keeps trying to use product; support tickets.
- **Refund issued AND evidence submitted.** Stripe sees double-action; processed inconsistently.
