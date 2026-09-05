# Bundle B25 — Customer Support Integration

> **Where this comes from.** Cross-reference with `/user-support-triage-for-saas-and-open-source-projects` and `/user-support-ticketing-system-for-saas`. Plus the operational reality that 80% of billing incidents reach engineering through customer support, not alarms.

A billing system without a customer-support integration is a system that gets discovered by complaints. This bundle is the connective tissue between support tickets and engineering response.

Skip in T1 (no customers); essential by T2 (first paying customer); non-optional by T3.

---

## The 12 most common billing support ticket classes

Before you can triage, you need to recognize the class. These are the recurring shapes:

| # | Ticket symptom | Likely class | First check |
|---|----------------|--------------|-------------|
| 1 | "I was charged twice" | Triple-charge / cross-provider duplicate | `select * from subscriptions where user_id = X order by created_at` |
| 2 | "I was charged but my account doesn't show premium" | Webhook silent loss; verify-as-write missed | `select * from payment_events where user_id = X order by created_at desc` |
| 3 | "I cancelled but you charged me again" | Cancellation not propagated; reconciliation lag | Check provider Dashboard for actual sub state |
| 4 | "I refunded but I still have access" | Synchronous cache invalidation missing | Check `users.subscription_status` denorm; check cache TTL |
| 5 | "I never authorized this charge" | Possible hijack OR forgotten subscription | Check `payment_events.payload` for full event; check IP / user agent |
| 6 | "Your reminder email is wrong; I already paid" | `wasEmailDeliveredSince` checking queued instead of sent | Check email_jobs status + sent_at |
| 7 | "I see a charge for $X but I'm on the $Y plan" | Plan mid-cycle change; presentment vs integration currency; tax surcharge | Check Stripe invoice.lines |
| 8 | "Why did my team plan price change?" | Adaptive Pricing; seat count change; tax | Check stripe.subscriptions.retrieve(id) + invoice |
| 9 | "I need a receipt / invoice for accounting" | Customer Portal access | Mint customer-portal-deep-link |
| 10 | "Can I get a refund?" | Policy decision; not automated | Queue for human; gather: reason, days since charge, prior refund history |
| 11 | "My card got declined; can you retry?" | Manual retry path | Check past_due status; offer Customer Portal link |
| 12 | "How do I cancel?" | Customer Portal flow | Mint subscription_cancel deep-link |

Each maps to a copy-paste response template + an investigation runbook.

---

## Pattern 1 — The triage flow

```
┌─────────────────────────────────────────────────────────────┐
│ Support agent receives ticket                                │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ Triage form: classify ticket into one of the 12 classes     │
│  (or "none of these — escalate to engineering")             │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ For each class, the agent has:                               │
│  - Investigation queries (read-only DB / Stripe / PayPal)   │
│  - Decision tree (what's normal vs. needs engineering)      │
│  - Customer-facing copy template                             │
│  - Internal escalation contacts                              │
└──────────────────┬──────────────────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        ▼                     ▼
   [Resolvable]        [Needs engineering]
        │                     │
        ▼                     ▼
   Send response         File incident bead OR
   Close ticket          Slack #billing-incidents
```

---

## Pattern 2 — Read-only support agent role

Support agents need DB read access for billing queries, BUT NOT write access (refunds + cancellations require engineering or admin UI).

```sql
-- Postgres role
CREATE ROLE support_agent;
GRANT CONNECT ON DATABASE app TO support_agent;
GRANT USAGE ON SCHEMA public TO support_agent;
GRANT SELECT ON
  users, subscriptions, organizations, payment_events,
  email_jobs, compliance_events, abuse_signals
TO support_agent;
-- NO INSERT / UPDATE / DELETE
-- NO access to payment_events.payload (PII risk; use a sanitized view)
REVOKE SELECT (payload) ON payment_events FROM support_agent;

-- Sanitized view for support agents (excludes PII)
CREATE VIEW payment_events_for_support AS
SELECT id, provider, event_id, event_type, processed_at, retry_count, last_error, created_at, user_id
FROM payment_events;
GRANT SELECT ON payment_events_for_support TO support_agent;
```

For Supabase: implement the same via RLS — see B50 § Supabase RLS, with a `support_agent` role identified by JWT claim.

---

## Pattern 3 — Investigation query library

For each ticket class, a standard query the agent runs FIRST:

```sql
-- "I was charged twice" — class 1
-- Find duplicate live subs for an email
SELECT u.email, s.id, s.provider, s.external_id, s.status, s.current_period_start, s.current_period_end
FROM users u
JOIN subscriptions s ON s.user_id = u.id
WHERE u.email = $1
  AND s.status IN ('active', 'past_due')
ORDER BY s.created_at;

-- "I was charged but no premium" — class 2
-- Find recent payment events for a user
SELECT pe.event_id, pe.event_type, pe.processed_at, pe.last_error, pe.created_at,
       s.status as sub_status
FROM payment_events pe
LEFT JOIN subscriptions s ON s.external_id = pe.payload->'data'->'object'->>'subscription'
WHERE pe.payload->'data'->'object'->>'customer' = $1  -- Stripe customer ID
   OR pe.payload->'resource'->>'custom_id' = $2       -- PayPal user ID
ORDER BY pe.created_at DESC
LIMIT 20;

-- "I cancelled but charged again" — class 3
-- Verify cancellation is in DB and provider
SELECT s.*, u.email
FROM subscriptions s
JOIN users u ON u.id = s.user_id
WHERE u.email = $1
ORDER BY s.created_at DESC;
-- Then cross-check Stripe Dashboard / PayPal Dashboard for actual provider state.

-- "Refunded but still have access" — class 4
-- Find recent refunds + check denormalized cache
SELECT u.email, u.subscription_status, u.subscription_provider,
       (SELECT count(*) FROM payment_events pe
        WHERE pe.payload->'type' ? 'refund'
          AND pe.created_at > now() - interval '7 days'
          AND pe.payload->'data'->'object'->>'customer' = u.customer_id) as recent_refunds
FROM users u
WHERE u.email = $1;
```

Each query goes in `<project>/docs/support/queries/<class-name>.sql`. Agent copy-pastes; runs against read-only DB.

---

## Pattern 4 — Customer-facing copy templates

For each class, a vetted customer response template (legal + tone reviewed):

```markdown
### Class 4 — "Refunded but still have access"

Subject: Re: Refund processed; access updated shortly

Hi [Customer name],

Thanks for reaching out. I've confirmed your refund was processed on [DATE]
for [AMOUNT]. The funds will appear on your statement within 5-10 business
days, depending on your bank.

Your premium access has been removed from your account as of [TIMESTAMP].
If you're still seeing premium features, please log out and back in — our
caching can take up to 5 minutes to update.

If you continue to see premium features after a fresh login, reply to this
email and I'll escalate immediately.

Best,
[Agent name]
```

For each class, the template has:
- The verified facts the agent looked up (so no false claims).
- The expected timeline (so customer knows when to follow up).
- The escalation path (so agent isn't blocked on edge cases).

Templates live in `<project>/docs/support/templates/<class-name>.md`.

---

## Pattern 5 — Escalation taxonomy

When the agent can't resolve, escalation paths are explicit:

| Severity | Definition | Escalation |
|----------|------------|------------|
| P0 | Money-related; multiple customers; visible at scale | Page on-call engineering immediately; create incident |
| P1 | Money-related; single customer; novel | Slack #billing; assign engineer within 4h |
| P2 | Customer confused but no money lost | Defer to engineering; respond in < 24h |
| P3 | Feature request / how-to | Defer to product / docs team |

Each tier has a documented escalation channel (Slack, PagerDuty, etc.).

---

## Pattern 6 — Support → engineering bead/issue creation

When escalating, the agent creates a structured issue (not just "customer X has a problem"):

```markdown
# [P1] Refund processed but access not revoked

## Customer
- Email: [redacted]
- User ID: [uuid]
- Subscription provider: stripe
- External sub ID: sub_xxx

## What happened (per customer)
[Customer's words]

## What I checked
- Refund issued: ✓ (Stripe Dashboard, charge ch_xxx, refund re_yyy, $19.00, 2026-05-04)
- DB subscription status: still 'active' (?)
- Recent payment_events: refund event present, processed_at NULL
- Cache check: cache key `user:billing:[uuid]` shows old data

## Suspected class
SA-02 cache invalidation — refund event arrived but cache was not invalidated.

## What I told the customer
"I've escalated to engineering; they'll respond within 4 hours."

## Engineering action needed
1. Confirm the bug (re-run the cache invalidation manually).
2. Investigate why the synchronous invalidation didn't fire (timeout? logger.error?).
3. Restore correct state for this customer.
4. File postmortem if recurring.

## Files attached
- payment_events row export (sanitized)
- Stripe Dashboard screenshot (refund + sub state)
```

The structured format means engineering can act in 5 minutes instead of 30 minutes of back-and-forth.

---

## Pattern 7 — Customer impact ledger

Every customer-affecting incident generates a row in `incident_customer_impact` (per B140 Pattern 8). Support uses this to:
- Avoid double-remediating the same customer.
- Confirm everyone affected got remediated.
- Track refund / credit policy compliance.

```sql
-- Has this customer already been remediated?
SELECT i.incident_id, i.impact_type, i.impact_value, i.remediation, i.remediation_at
FROM incident_customer_impact i
WHERE i.user_id = $1
ORDER BY i.recorded_at DESC;
```

---

## Pattern 8 — Proactive customer comms during incidents

When an incident affects > N customers, support proactively reaches out BEFORE customers complain:

1. Engineering identifies the customer impact set (with help from `incident_customer_impact`).
2. Support drafts proactive email (legal review).
3. Support sends to affected customers via the durable email queue (priority 30).
4. Support monitors response queue for follow-up needs.

Proactive comms turn a P0 incident from "customer support nightmare" into "customers thank you for the transparency."

---

## Pattern 9 — Refund decision policy + button

Per `00-NORTH-STAR § 6` (refund decisions belong to humans), the support → engineering refund process:

1. Agent gathers facts: reason, days since charge, prior refund history, amount.
2. Agent applies policy: within `BUSINESS.REFUND_WINDOW_DAYS`? prior refund < 1? amount under $X auto-approval threshold?
3. Within auto-approval: agent uses admin UI's "Issue Refund" button (logged via B50 admin-action audit).
4. Outside: escalate to manager with policy reasoning.
5. Manager approves: admin UI button.
6. Issued via `incidentRefund(...)` helper (B140 Pattern 1) — synchronous cache invalidation + audit log.

The button is in the admin UI (B45). The decision is human. The execution is automated.

---

## Pattern 10 — Customer-facing self-service

Reduce ticket volume by routing common questions to self-service:

- **"How do I cancel?"** → Customer Portal `subscription_cancel` deep-link in account UI.
- **"How do I update my card?"** → `payment_method_update` deep-link.
- **"Where's my receipt?"** → Customer Portal invoice list.
- **"How do I change plans?"** → `subscription_update` deep-link (if portal config allows).

Track which questions still arrive despite self-service; surface as friction signal to product.

---

## Polish Bar checks for B25

- [ ] Read-only `support_agent` DB role + sanitized views.
- [ ] Investigation query library committed to `docs/support/queries/`.
- [ ] Customer-facing copy templates committed to `docs/support/templates/`.
- [ ] Escalation taxonomy + channel matrix documented.
- [ ] Structured issue template for support → engineering escalation.
- [ ] `incident_customer_impact` queryable by support.
- [ ] Refund decision policy + auto-approval threshold + manager-escalation flow.
- [ ] Customer-facing self-service Portal deep-links wired.
- [ ] Proactive comms playbook for incidents.
- [ ] Quarterly review of ticket class distribution → flag systemic issues for engineering.

---

## Common B25 mistakes

- **Support has write DB access.** Agent typoes a query; data corruption.
- **Support has admin-UI access without rate limit.** Insider threat amplified.
- **No escalation taxonomy.** Everything is P1; on-call burns out; real P0s missed.
- **Support refunds without bead/audit log.** Compliance auditor finds untraced money movement.
- **Self-service deep-links broken.** Customer files ticket because Portal returns 404; doubles ticket volume.
- **Customer-facing templates not legal-reviewed.** Apologetic phrasing implies liability the company didn't intend.
- **No proactive comms playbook.** Customers find out about incident via Twitter; trust crater.
- **`incident_customer_impact` not queryable by support.** Same customer remediated 3 times; another customer missed entirely.
