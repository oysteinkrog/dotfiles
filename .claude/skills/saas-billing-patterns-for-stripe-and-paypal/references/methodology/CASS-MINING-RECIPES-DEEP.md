# CASS Mining Recipes — Per-Failure-Class Deep Dive

> **Where this comes from.** Extension of `CASS-MINING.md`. The base file has reusable billing-mining recipes; this file has class-specific recipes for each of the 38 failure modes from B145.

For each known failure class, a calibrated cass query that surfaces prior project history relevant to that class. Use during Phase 1 archaeology + during incident response.

---

## How to use

1. Identify the suspected failure class (per B145).
2. Find the matching recipe below.
3. Run the cass searches.
4. Append findings to `.billing_workspace/phase0_cass_mining_class_<NN>.md`.
5. Use findings to inform your fix / archaeology / risk-scoring.

---

## F1.1 — Triple-charge / cross-provider duplicate

```bash
cass search "duplicate charge" --robot --days 365 --limit 30
cass search "Tom Hunter" --robot --days 365 --limit 10
cass search "cross-provider probe" --robot --days 365 --limit 20
cass search "customer reuse stripe" --robot --days 365 --limit 20
cass search "bd-1m86f" --robot --days 365 --limit 20
cass search "triple charge" --robot --days 365 --limit 20
cass search "integrity audit" --robot --days 365 --limit 20
```

Look for: prior incidents in similar code paths; prior fixes that may have reverted; team-internal jargon for this class.

---

## F1.2 — Marco Fanti silent webhook loss

```bash
cass search "silent webhook loss" --robot --days 365 --limit 20
cass search "Marco Fanti" --robot --days 365 --limit 10
cass search "provider reconciliation" --robot --days 365 --limit 20
cass search "webhook never arrived" --robot --days 365 --limit 20
cass search "bd-1ug5i" --robot --days 365 --limit 20
cass search "stripe webhook delivery" --robot --days 365 --limit 20
```

---

## F1.3 — `incomplete` checkout marked active

```bash
cass search "mapStripeStatus" --robot --days 365 --limit 30
cass search "incomplete subscription" --robot --days 365 --limit 30
cass search "stripe checkout incomplete" --robot --days 365 --limit 20
cass search "3DS payment incomplete" --robot --days 365 --limit 20
```

---

## F1.4 — Webhook 200-on-error missing

```bash
cass search "webhook 500 retry storm" --robot --days 365 --limit 30
cass search "stripe retry storm" --robot --days 365 --limit 20
cass search "200 on error webhook" --robot --days 365 --limit 30
cass search "bd-1zzos" --robot --days 365 --limit 20
cass search "duplicate side effect" --robot --days 365 --limit 20
```

---

## F1.5 — Per-event retry counter shared

```bash
cass search "retry_count shared" --robot --days 365 --limit 20
cass search "BILLING.PLAN.UPDATED noise" --robot --days 365 --limit 20
cass search "MAX_RETRY_COUNT" --robot --days 365 --limit 30
```

---

## F1.6 — Cross-provider webhook payload confusion

```bash
cass search "stripe payload paypal endpoint" --robot --days 365 --limit 20
cass search "BL-42 webhook confusion" --robot --days 365 --limit 20
cass search "generic webhook endpoint" --robot --days 365 --limit 20
```

---

## F2.1 — PayPal individual hijack

```bash
cass search "validatePayPalUserId" --robot --days 365 --limit 30
cass search "paypal custom_id hijack" --robot --days 365 --limit 30
cass search "bd-2gxws" --robot --days 365 --limit 20
cass search "paypal payer_id mismatch" --robot --days 365 --limit 20
cass search "cross-provider switch paypal" --robot --days 365 --limit 20
```

---

## F2.2 — PayPal team hijack

```bash
cass search "paypal team hijack" --robot --days 365 --limit 30
cass search "subscription_id WHERE clause" --robot --days 365 --limit 30
cass search "SA-01" --robot --days 365 --limit 20
cass search "bd-08xvg.1" --robot --days 365 --limit 20
cass search "team subscription update WHERE" --robot --days 365 --limit 20
```

---

## F2.3 — Stripe Connect / org event account-mismatch

```bash
cass search "STRIPE_ACCOUNT_ID" --robot --days 365 --limit 20
cass search "stripe connect account verification" --robot --days 365 --limit 20
cass search "event.account check" --robot --days 365 --limit 20
cass search "webhook event rejected wrong account" --robot --days 365 --limit 20
```

---

## F2.4 — Email-fallback hijack

```bash
cass search "email fallback hijack" --robot --days 365 --limit 20
cass search "updateSubscriptionStatus email lookup" --robot --days 365 --limit 20
cass search "bd-2zb9z" --robot --days 365 --limit 20
```

---

## F2.5 — Reconcile-cancelled-orgs revival

```bash
cass search "reconcile cancelled orgs" --robot --days 365 --limit 30
cass search "SA-03" --robot --days 365 --limit 20
cass search "bd-08xvg.3" --robot --days 365 --limit 20
cass search "PAYMENT.SALE.COMPLETED revival" --robot --days 365 --limit 20
cass search "cancelled org guard" --robot --days 365 --limit 20
```

---

## F3.1 — Stale event replay revival

```bash
cass search "stale event replay" --robot --days 365 --limit 30
cass search "last_event_at WHERE" --robot --days 365 --limit 30
cass search "subscription revival" --robot --days 365 --limit 20
cass search "d5cb6549" --robot --days 365 --limit 20
cass search "PAYMENT.SALE.DENIED race" --robot --days 365 --limit 20
```

---

## F3.2 — `paused_for_org` treated as cancelled

```bash
cass search "paused_for_org" --robot --days 365 --limit 30
cass search "double bill team leave" --robot --days 365 --limit 20
cass search "individual subscription pause" --robot --days 365 --limit 20
```

---

## F3.3 — Grace period off-by-one

```bash
cass search "grace period boundary" --robot --days 365 --limit 30
cass search "isWithinGracePeriod" --robot --days 365 --limit 20
cass search "bd-5zyz6" --robot --days 365 --limit 20
cass search "GRACE_PERIOD_DAYS off by one" --robot --days 365 --limit 20
```

---

## F3.4 — Stale-checkout race

```bash
cass search "detectStaleCheckoutRace" --robot --days 365 --limit 20
cass search "stale checkout" --robot --days 365 --limit 30
cass search "bd-bfwcy.4" --robot --days 365 --limit 20
cass search "BILLING-M2" --robot --days 365 --limit 20
cass search "pending checkout session race" --robot --days 365 --limit 20
```

---

## F4.1 — Synchronous cache invalidation missing

```bash
cass search "synchronous cache invalidation" --robot --days 365 --limit 30
cass search "SA-02" --robot --days 365 --limit 20
cass search "refund cache stale" --robot --days 365 --limit 20
cass search "revokeAccessOnRefund" --robot --days 365 --limit 20
cass search "Promise.race timeout" --robot --days 365 --limit 20
```

---

## F4.2 — PayPal partial refund

```bash
cass search "paypal partial refund" --robot --days 365 --limit 30
cass search "Billing-H2" --robot --days 365 --limit 20
cass search "bd-hbfat" --robot --days 365 --limit 20
cass search "isPayPalSalePartialRefund" --robot --days 365 --limit 20
cass search "fetchParentPayment" --robot --days 365 --limit 20
```

---

## F4.3 — Refund webhook unscoped revoke

```bash
cass search "refund without subscription_id" --robot --days 365 --limit 20
cass search "ambiguous refund" --robot --days 365 --limit 20
cass search "stripped two subs" --robot --days 365 --limit 20
```

---

## F4.4 — Auto-refund on duplicate (rejected pattern)

```bash
cass search "auto-refund duplicate" --robot --days 365 --limit 20
cass search "auto refund rejected" --robot --days 365 --limit 20
```

---

## F5.1 — Per-row dunning email cycle bug

```bash
cass search "wasEmailDeliveredSince" --robot --days 365 --limit 30
cass search "dunning email duplicate" --robot --days 365 --limit 20
cass search "queued vs sent dedup" --robot --days 365 --limit 20
```

---

## F5.2 — Newsletter delayed refund alert

```bash
cass search "newsletter delays refund" --robot --days 365 --limit 20
cass search "email_jobs priority" --robot --days 365 --limit 30
cass search "BILLING-M3" --robot --days 365 --limit 20
cass search "bd-bfwcy.5" --robot --days 365 --limit 20
cass search "inferEmailJobPriority" --robot --days 365 --limit 20
```

---

## F5.3 — Card-expiry off-by-one

```bash
cass search "card expiry off by one" --robot --days 365 --limit 20
cass search "card expiring round up" --robot --days 365 --limit 20
cass search "card_expiry_warning cron" --robot --days 365 --limit 20
```

---

## F6.1 — Webhook reconciliation overlap

```bash
cass search "reconciliation overlap" --robot --days 365 --limit 30
cass search "pg_try_advisory_lock cron" --robot --days 365 --limit 30
cass search "double-process payment_event" --robot --days 365 --limit 20
```

---

## F6.2 — Cron pool exhaustion

```bash
cass search "pool exhaustion" --robot --days 365 --limit 30
cass search "finally release connection" --robot --days 365 --limit 20
cass search "pgClient.reserve" --robot --days 365 --limit 20
cass search "too many connections" --robot --days 365 --limit 20
```

---

## F6.3 — Pause/resume pool exhaustion

```bash
cass search "pause resume pool exhaustion" --robot --days 365 --limit 30
cass search "Billing-H4" --robot --days 365 --limit 20
cass search "bd-yu9g9" --robot --days 365 --limit 20
cass search "stripe call inside transaction" --robot --days 365 --limit 20
cass search "intent then act" --robot --days 365 --limit 20
```

---

## F6.4 — GDPR delete left ghost sub

```bash
cass search "ghost subscription user delete" --robot --days 365 --limit 30
cass search "BILLING-M5" --robot --days 365 --limit 20
cass search "bd-bfwcy.6" --robot --days 365 --limit 20
cass search "orphan_subscription_cancels" --robot --days 365 --limit 20
cass search "GDPR delete cancel" --robot --days 365 --limit 20
```

---

## F6.5 — Refund alert lost when Resend down

```bash
cass search "Resend outage refund alert" --robot --days 365 --limit 20
cass search "Billing-H1" --robot --days 365 --limit 20
cass search "bd-ja8c0" --robot --days 365 --limit 20
cass search "OPS_FAILSAFE_EMAIL" --robot --days 365 --limit 20
cass search "email failsafe sweep" --robot --days 365 --limit 20
```

---

## F7.1 — Revenue tile stale 0

```bash
cass search "MRR snapshot stale" --robot --days 365 --limit 20
cass search "provenance unavailable" --robot --days 365 --limit 30
cass search "MRR cache failure" --robot --days 365 --limit 20
```

---

## F7.2 — Synthetic fixtures spamming alerts

```bash
cass search "test signup new subscriber" --robot --days 365 --limit 20
cass search "analytics exclusions cron" --robot --days 365 --limit 30
cass search "you@example.test customer" --robot --days 365 --limit 20
cass search "drift-guard cronsThatMustExclude" --robot --days 365 --limit 20
```

---

## F7.3 — Activity feed shows test signups

```bash
cass search "admin event publisher analytics" --robot --days 365 --limit 20
cass search "test signup activity feed" --robot --days 365 --limit 20
cass search "two-gate publisher" --robot --days 365 --limit 20
```

---

## F7.4 — MRR from SQL view

```bash
cass search "MRR from SQL view" --robot --days 365 --limit 20
cass search "getCurrentMrrSnapshot" --robot --days 365 --limit 20
cass search "cache invalidation MRR" --robot --days 365 --limit 20
```

---

## F8.1 — Migration without schema.ts update

```bash
cass search "migration schema.ts" --robot --days 365 --limit 20
cass search "drizzle migration discipline" --robot --days 365 --limit 20
cass search "column doesn't exist runtime" --robot --days 365 --limit 20
```

---

## F8.2 — STRIPE_API_VERSION drift

```bash
cass search "STRIPE_API_VERSION" --robot --days 365 --limit 30
cass search "centralize stripe api version" --robot --days 365 --limit 20
cass search "bd-vifc1" --robot --days 365 --limit 20
cass search "13 instances stripe client" --robot --days 365 --limit 20
```

---

## F8.3 — `abuse_detected` polluted

```bash
cass search "abuse_detected pollution" --robot --days 365 --limit 20
cass search "system_alert_dedupe" --robot --days 365 --limit 20
cass search "BILLING-M1" --robot --days 365 --limit 20
cass search "bd-bfwcy.3" --robot --days 365 --limit 20
```

---

## F8.4 — Shared terminal-stuck digest helper (rejected)

```bash
cass search "shared maybeFireTerminalStuckDigest" --robot --days 365 --limit 20
cass search "DRY god function" --robot --days 365 --limit 20
cass search "copy and adapt" --robot --days 365 --limit 20
```

---

## F8.5 — Storing partial event payloads (rejected)

```bash
cass search "partial event payload" --robot --days 365 --limit 20
cass search "payment_events.payload jsonb" --robot --days 365 --limit 20
```

---

## F8.6 — Admin retry without age cutoff

```bash
cass search "admin retry age cutoff" --robot --days 365 --limit 20
cass search "SA-13" --robot --days 365 --limit 20
cass search "bd-08xvg.13" --robot --days 365 --limit 20
cass search "STORED_EVENT_MAX_AGE" --robot --days 365 --limit 20
```

---

## F8.7 — Auto-replay after bookkeeping failure

```bash
cass search "SA-22" --robot --days 365 --limit 20
cass search "bd-08xvg.22" --robot --days 365 --limit 20
cass search "payment_event_suppressed" --robot --days 365 --limit 20
cass search "suppressAutomaticReplayAfterBookkeepingFailure" --robot --days 365 --limit 20
```

---

## Cross-class recipes

### Find all billing incidents in a time window

```bash
cass search "billing incident" --robot --days 90 --limit 50
cass search "P0 billing" --robot --days 90 --limit 50
cass search "P1 billing" --robot --days 90 --limit 50
cass search "postmortem billing" --robot --days 365 --limit 50
```

### Find all decisions about billing patterns

```bash
cass search "we decided not to" --robot --days 365 --limit 30
cass search "explicit policy" --robot --days 365 --limit 30
cass search "BUSINESS constants" --robot --days 365 --limit 30
```

### Find all attempts at a refactor that didn't work

```bash
cass search "tried but reverted" --robot --days 365 --limit 30
cass search "rejected pattern" --robot --days 365 --limit 30
cass search "rolled back" --robot --days 365 --limit 30
```

---

## Output template per class

For each class searched, append to `.billing_workspace/phase0_cass_mining_class_<NN>.md`:

```markdown
## Class F<NN>: <name>

### Sessions found
- Session 1 (2025-XX-XX): <summary>
- Session 2 (2025-YY-YY): <summary>

### Decisions captured
- "<verbatim user voice>" (per session ZZZ)

### Recurrences
- N occurrences in last 365 days
- Pattern: <recurring trigger / recurring fix>

### Reusable prompts found
- "<prompt>" — from session AAAAA; reuse for <bundle> implementer

### Open questions
- <thing the cass results don't answer>
```

Pass these per-class artifacts to the bundle archaeologists in Phase 1.

---

## Discipline

- Quote user voice exactly when the user made a policy commitment.
- Cross-reference cass findings against current code (cass may be stale).
- Don't search for secrets; redact in your output if you find any.
- Stop at 30 results per query; deeper exploration via narrower searches.

---

## Integration with the Phase loop

| Phase | Use these recipes for |
|-------|------------------------|
| Phase 0 | Pre-archaeology context per class |
| Phase 1 | Per-bundle archaeology (specific to class found) |
| Phase 3 | Risk-scoring (recurrences = higher severity) |
| Phase 4 | Reuse prior decisions in plan |
| Phase 7 | Fresh-eyes (search for "we tried this; here's why it failed") |
| Phase 10 | Runbook authoring (prior incidents per class become runbook content) |
