# Bundle B145 — Extended Failure-Mode Catalog (38 incidents)

> **Where this comes from.** Full expansion of source guide § 72 (failure-mode catalog). The headline guide summarized 18; this is the full 38 plus catalog organization.

The failure-mode catalog is the OPERATIONAL HISTORY of a battle-tested billing system. Each entry is a real incident class. Knowing them is what separates "we wrote a billing system" from "we operated a billing system."

Use as: pre-incident reading (recognition), during-incident reference (matching), post-incident contribution (extension).

---

## Catalog organization

The 38 failure modes group into 8 themes:

| Theme | Failure count | Primary bundle |
|-------|---------------|----------------|
| Webhook ingestion | 6 | B40 |
| Hijack / security | 5 | B50 |
| State + lifecycle | 4 | B60 |
| Refund + dispute | 4 | B125 |
| Dunning + email | 3 | B70 |
| Cron + reliability | 5 | B90 |
| Reporting + analytics | 4 | B100 |
| Operations + admin | 7 | B45 / B110 |

---

## Theme 1 — Webhook ingestion (6 failures)

### F1.1 — Triple-charge (Tom Hunter — bd-1m86f)

| Field | Value |
|-------|-------|
| Symptom | Customer charged 3x for one subscription |
| Root cause | Webhook 3h late + DB-only checkout guard + customer ID drift |
| Fix layer | Cross-provider probe + customer reuse + idempotency bucket + integrity audit |
| Caught by | Customer support ticket |
| Detection latency | 18 hours |
| Customer impact | $57 over-charge to one customer; identical class for 2 others recovered post-discovery |
| Pattern | B30 § Cross-provider duplicate-sub guard |
| Regression test | `tests/integration/billing/cross-provider-duplicate-guard.test.ts` |

### F1.2 — Marco Fanti silent webhook loss (bd-1ug5i)

| Field | Value |
|-------|-------|
| Symptom | Paid customer never activated; complained 3 weeks after payment |
| Root cause | PayPal webhook silently dropped at provider edge |
| Fix layer | Webhook-staleness alarm tightened; provider-reconciliation cron added |
| Caught by | Customer support ticket |
| Detection latency | 21 days |
| Customer impact | One customer; $19 refund + apology |
| Pattern | B90 § Provider-authoritative reconciliation sweep |
| Regression test | `tests/integration/billing/provider-reconciliation-detects-silent-loss.test.ts` |

### F1.3 — Stripe `incomplete` checkout incorrectly marked active

| Field | Value |
|-------|-------|
| Symptom | Customer activated despite payment failing 3DS |
| Root cause | `mapStripeStatus` fallthrough mapped `incomplete` to `active` |
| Fix layer | Block `incomplete` at checkout entry + explicit mapping |
| Caught by | Multi-agent code review (`bd-1m86f` related) |
| Detection latency | Pre-production (caught in code review) |
| Pattern | B40 § canonical writer + B30 § checkout |
| Regression test | `tests/unit/payment/map-stripe-status.test.ts` |

### F1.4 — Webhook 200-on-error missing → retry storm

| Field | Value |
|-------|-------|
| Symptom | Stripe retried failing handler for 3 days; partial side effects fired N times |
| Root cause | `try/catch` with `throw` after `recordWebhookEvent` succeeded (`bd-1zzos`) |
| Fix layer | Always 200 after dedup; reconciliation cron handles retries |
| Caught by | Production log noise + duplicated welcome emails |
| Detection latency | 2 days |
| Customer impact | 12 customers received duplicate welcome emails |
| Pattern | B40 § 200-on-error |
| Regression test | `tests/integration/billing/webhook-200-on-error.test.ts` |

### F1.5 — Per-event retry counter shared across event types

| Field | Value |
|-------|-------|
| Symptom | High-failure-rate event type (BILLING.PLAN.UPDATED noise) maxed counter for entire class |
| Root cause | `retry_count` shared across event types |
| Fix layer | Per-event-type retry caps at handler level |
| Caught by | Reconciliation cron stalled; on-call investigation |
| Pattern | B40 § per-event-type retry caps |

### F1.6 — Cross-provider webhook payload confusion (BL-42 / § 78a.8)

| Field | Value |
|-------|-------|
| Symptom | Stripe-formatted payload sent to PayPal endpoint (or vice versa); handler errored confusingly |
| Root cause | Missing per-provider header validation |
| Fix layer | Each provider's route validates `stripe-signature` / `paypal-transmission-id` BEFORE field access |
| Pattern | B55 § cross-provider webhook confusion |
| Regression test | `tests/integration/billing/wrong-provider-payload.test.ts` |

---

## Theme 2 — Hijack / security (5 failures)

### F2.1 — PayPal individual hijack (bd-2gxws)

| Field | Value |
|-------|-------|
| Symptom | Attacker upgraded victim's account by crafting PayPal subscription with `custom_id = victim_uuid` |
| Root cause | Trusted `custom_id` UUID without cross-check |
| Fix layer | `validatePayPalUserId()` cross-checks `payerId` against stored `customerId` |
| Caught by | Security code review |
| Detection latency | Pre-production |
| Pattern | B50 § validatePayPalUserId |
| Regression test | `tests/integration/security/paypal-individual-hijack.test.ts` (6 scenarios) |

### F2.2 — PayPal team hijack (SA-01 / bd-08xvg.1)

| Field | Value |
|-------|-------|
| Symptom | Attacker mutated arbitrary org's status by replaying a `subscription.id` they owned |
| Root cause | Team-org UPDATEs lacked `subscription_id` cross-check in WHERE clause |
| Fix layer | `paypal_subscription_id = $sub_id` in every team-org UPDATE WHERE |
| Caught by | Security audit (SA-01) |
| Detection latency | Pre-production |
| Pattern | B50 § subscription_id cross-check |
| Regression test | `tests/integration/security/sa17-paypal-team-hijack-e2e.test.ts` |

### F2.3 — Stripe Connect / org event account-mismatch

| Field | Value |
|-------|-------|
| Symptom | (theoretical) Attacker's Connect account fires events at platform → entitlement granted |
| Root cause | Missing `event.account` validation on Connect endpoint |
| Fix layer | `STRIPE_ACCOUNT_ID` env + check at top of handler; 200 + `webhook_event_rejected` |
| Caught by | Security audit (§ 78a.1) |
| Pattern | B50 § Stripe account verification |

### F2.4 — Email-fallback hijack (bd-2zb9z)

| Field | Value |
|-------|-------|
| Symptom | Attacker hijacks victim's row by crafting PayPal sub with victim's email |
| Root cause | `updateSubscriptionStatus` looked up user by email if `customerId` not found |
| Fix layer | Email fallback gated on `customerId IS NOT NULL` |
| Pattern | B40 § canonical writer email-fallback hijack pitfall |

### F2.5 — Reconcile-cancelled-orgs revival (SA-03 / bd-08xvg.3)

| Field | Value |
|-------|-------|
| Symptom | Cancelled team org revived to `past_due` by late `PAYMENT.SALE.DENIED` replay |
| Root cause | Reconcile branch missing `cancelled` status guard |
| Fix layer | `!== "cancelled"` in BOTH if-branch AND SQL `notInArray()` |
| Caught by | Security audit (SA-03) |
| Pattern | B50 § Reconcile cancelled-orgs guard |

---

## Theme 3 — State + lifecycle (4 failures)

### F3.1 — Stale event replay revival

| Field | Value |
|-------|-------|
| Symptom | Cancelled subscription re-activated by late webhook replay (`d5cb6549`) |
| Root cause | UPDATE without `last_event_at` ordering guard |
| Fix layer | `WHERE last_event_at < new_event_at` on every status UPDATE |
| Pattern | B40 § replay-staleness gating |

### F3.2 — `paused_for_org` treated as cancelled (early bug)

| Field | Value |
|-------|-------|
| Symptom | Org-pause user double-billed when leaving team plan |
| Root cause | Treating `paused_for_org` as semantically equivalent to `cancelled` |
| Fix layer | `paused_for_org` enum value + dedicated handlers |
| Pattern | B60 § paused_for_org |

### F3.3 — Grace period off-by-one (bd-5zyz6)

| Field | Value |
|-------|-------|
| Symptom | `isWithinGracePeriod` returned true on Day 21; cron suspended same day; race |
| Root cause | `<=` instead of `<` |
| Fix layer | Boundary fix + millisecond arithmetic + `now` parameter for consistency |
| Pattern | B60 § grace period correctness |

### F3.4 — Stale-checkout race (bd-bfwcy.4 / BILLING-M2)

| Field | Value |
|-------|-------|
| Symptom | User started 2nd checkout; 1st webhook arrived after; stale activation |
| Root cause | `checkout.session.completed` for old session activated without check |
| Fix layer | `detectStaleCheckoutRace` + alert + no-activation on stale |
| Pattern | B30 + B60 § stale-checkout race guard |

---

## Theme 4 — Refund + dispute (4 failures)

### F4.1 — Synchronous cache invalidation missing on refund (SA-02)

| Field | Value |
|-------|-------|
| Symptom | Refunded user retained access for hours (cache TTL) |
| Root cause | Cache invalidation scheduled via `after()` (best-effort post-response) |
| Fix layer | Synchronous invalidation with 2s `Promise.race` cap |
| Pattern | B60 § refunds + B100 § synchronous cache invalidation |

### F4.2 — PayPal partial refund stripped access (Billing-H2 / bd-hbfat)

| Field | Value |
|-------|-------|
| Symptom | Customer received partial refund; full access revoked |
| Root cause | Trusted `sale.state` hint instead of fetching parent payment |
| Fix layer | Fetch parent payment + cumulative refund math + fall-back-safe (don't revoke on fetch failure) |
| Pattern | B60 § PayPal partial-refund detection |

### F4.3 — Refund webhook with no sub_id stripped 2 subs

| Field | Value |
|-------|-------|
| Symptom | Refund event without `subscription_id` revoked all the user's active subs |
| Root cause | Unscoped revoke logic |
| Fix layer | Throw on ambiguity; queue for cron retry with manual disambiguation |
| Pattern | B60 § refund disambiguation |

### F4.4 — Auto-refund on duplicate detection (REJECTED)

| Field | Value |
|-------|-------|
| Symptom | Tried briefly during bd-1m86f triage; reverted within 24h |
| Root cause | Real customers occasionally have legitimate duplicates (gift sub then real sub) |
| Fix layer | Detection + alert + human triage; never auto-refund |
| Pattern | B00 § north-star principle 6; B125 § dispute defense |

---

## Theme 5 — Dunning + email (3 failures)

### F5.1 — Per-row dunning email cycle bug

| Field | Value |
|-------|-------|
| Symptom | Customer who fixed payment got duplicate "your payment failed" email |
| Root cause | `wasEmailDeliveredSince` keyed on `status='queued'` instead of `status='sent' AND sent_at` |
| Fix layer | Check delivery, not queueing |
| Pattern | B70 § wasEmailDeliveredSince |

### F5.2 — Newsletter delayed refund alert (bd-bfwcy.5 / BILLING-M3)

| Field | Value |
|-------|-------|
| Symptom | Refund alert email sat behind 5K newsletter blast for hours |
| Root cause | FIFO email queue, no priority |
| Fix layer | `email_jobs.priority` smallint + index |
| Pattern | B10 § email_jobs + B90 § email queue priority |

### F5.3 — Card-expiry warning off-by-one

| Field | Value |
|-------|-------|
| Symptom | Card expiring 3-1 month away didn't get warning |
| Root cause | Days rounded DOWN instead of UP |
| Fix layer | Round UP |
| Pattern | B70 § card-expiry pre-warning |

---

## Theme 6 — Cron + reliability (5 failures)

### F6.1 — Webhook reconciliation overlap

| Field | Value |
|-------|-------|
| Symptom | Two concurrent cron isolates processed same `payment_events` row → double side-effect |
| Root cause | No advisory lock |
| Fix layer | `pg_try_advisory_lock` per cron |
| Pattern | B90 § cron-defenses |

### F6.2 — Cron pool exhaustion via held-connection

| Field | Value |
|-------|-------|
| Symptom | "Too many connections" errors after cron ran for 5min |
| Root cause | `pgClient.reserve()` without `finally { release() }` |
| Fix layer | Always release in finally |
| Pattern | B90 § failure-mode #8 |

### F6.3 — Pause/resume pool exhaustion (Billing-H4 / bd-yu9g9)

| Field | Value |
|-------|-------|
| Symptom | Stripe API call inside DB tx held connection for 80s-3min during slowdowns |
| Root cause | Provider call inside transaction |
| Fix layer | Intent-then-act; provider call OUTSIDE tx |
| Pattern | B80 § pause/resume intent-then-act |

### F6.4 — GDPR delete left ghost Stripe sub (bd-bfwcy.6 / BILLING-M5)

| Field | Value |
|-------|-------|
| Symptom | Deleted user kept getting charged for 3 months |
| Root cause | Provider cancel called AFTER user delete tx; failure left orphan |
| Fix layer | Insert orphan-cancel row INSIDE delete tx; retry cron drains |
| Pattern | B90 § orphan-cancel queue |

### F6.5 — Refund alert lost when Resend down (Billing-H1 / bd-ja8c0)

| Field | Value |
|-------|-------|
| Symptom | Refund happened; admin never alerted; customer complained next day |
| Root cause | Direct `sendEmail()` for alerts; Resend outage = lost alerts |
| Fix layer | Email-queue failsafe + OPS_FAILSAFE_EMAIL (different inbox, direct send bypass) |
| Pattern | B90 § email queue failsafe escalation |

---

## Theme 7 — Reporting + analytics (4 failures)

### F7.1 — Revenue tile showed stale 0 during outage

| Field | Value |
|-------|-------|
| Symptom | Admin saw "MRR: $0" during 30-min Stripe outage; panicked |
| Root cause | Cache returned stale on fail; no provenance |
| Fix layer | `provenance: live | fallback | unavailable` propagation |
| Pattern | B100 § MRR snapshot |

### F7.2 — Synthetic fixtures spamming alerts

| Field | Value |
|-------|-------|
| Symptom | Customer-facing dunning email sent to `you@example.test`; real customer copied on it; trust break |
| Root cause | New cron added without analytics-exclusion import |
| Fix layer | Canonical exclusions module + drift-guard test pinning every cron |
| Pattern | B90 § analytics exclusions + B110 § drift-guards |

### F7.3 — Activity feed shows test signups as new subscribers

| Field | Value |
|-------|-------|
| Symptom | Leadership panic at "+50 new subscribers!"; all were test signups |
| Root cause | Admin event publisher bypassed analytics-exclusion |
| Fix layer | Two-gate publisher (previousStatus + exclusion) |
| Pattern | B90 § admin events |

### F7.4 — MRR computed from SQL view that joined live tables (REJECTED)

| Field | Value |
|-------|-------|
| Symptom | Cache invalidation impossible; MRR drifted under burst |
| Root cause | View aggregated subscriptions live |
| Fix layer | Snapshot function + cache + invalidation hooks on every sub mutation |
| Pattern | B100 § MRR snapshot |

---

## Theme 8 — Operations + admin (7 failures)

### F8.1 — Migration that doesn't update schema.ts

| Field | Value |
|-------|-------|
| Symptom | Drizzle queries fail at runtime with "column doesn't exist" |
| Root cause | DBA ran migration directly; engineer's `schema.ts` not updated |
| Fix layer | AGENTS.md rule: schema.ts and migration in same commit; drift-guard |
| Pattern | B110 § migration discipline |

### F8.2 — `STRIPE_API_VERSION` hardcoded in 13 places (bd-vifc1)

| Field | Value |
|-------|-------|
| Symptom | API version upgrade rolled one place; 12 others drift; intermittent failures |
| Root cause | No single-source-of-truth |
| Fix layer | Centralize in `stripe-config.ts`; type-derive; drift-guard |
| Pattern | B20 § STRIPE_API_VERSION |

### F8.3 — Polluting `abuse_detected` for system alerts (REJECTED)

| Field | Value |
|-------|-------|
| Symptom | Dashboards showed huge `abuse_detected` count; customers thought we were under attack |
| Root cause | Reused customer-actor signal type for system self-alerts |
| Fix layer | Dedicated `system_alert_dedupe` event type |
| Pattern | B50 § security event taxonomy |

### F8.4 — One-shared `maybeFireTerminalStuckDigest` helper across crons (REJECTED)

| Field | Value |
|-------|-------|
| Symptom | DRY refactor coupled different schemas; god-function risk |
| Root cause | `orphan_subscription_cancels` and `pending_individual_sub_cancel_*` are different tables |
| Fix layer | Copy-and-adapt; not shared helper |
| Pattern | B90 § cron-defenses |

### F8.5 — Storing partial event payloads (REJECTED)

| Field | Value |
|-------|-------|
| Symptom | Future handler change needed re-fetch from provider OR backfill |
| Root cause | Stored only parsed subset to save disk |
| Fix layer | `payment_events.payload jsonb NOT NULL` — store full event |
| Pattern | B10 § payment_events |

### F8.6 — Admin retry without age cutoff (SA-13 / bd-08xvg.13)

| Field | Value |
|-------|-------|
| Symptom | Admin replayed months-old event; reactivated cancelled customer |
| Root cause | No age cutoff on admin replay |
| Fix layer | 7-day cutoff + override + staleness check + safe vs dangerous classification |
| Pattern | B50 § admin retry path |

### F8.7 — Auto-replay after bookkeeping failure (SA-22 / bd-08xvg.22)

| Field | Value |
|-------|-------|
| Symptom | Reconciliation cron re-ran side effects after bookkeeping failed |
| Root cause | No suppression after partial-success |
| Fix layer | `payment_event_suppressed` event + `processed_at` set + lastError preserved |
| Pattern | B50 § suppress automatic replay |

---

## How to use this catalog

### During incident response

1. The on-call engineer sees the symptom.
2. Greps this catalog for matching symptom.
3. Finds the class; reads root cause + fix layer.
4. Applies the runbook for that bundle.
5. Files postmortem; if novel, ADDS to catalog.

### During code review

1. Reviewer reads new code.
2. Mentally checks against the 38 classes.
3. Flags if any pattern is missing or weakened.

### During onboarding

1. New engineer reads this catalog.
2. Recognizes that "billing is hard, BUT, the hard parts are KNOWN."
3. Confidence calibration: knows what to be paranoid about.

---

## Catalog extension protocol

When YOUR project encounters a NEW failure class not in this catalog:

1. Write the postmortem (per `assets/postmortem-template.md`).
2. Add a new entry to your project-local catalog (`docs/billing/failure-catalog.md`).
3. If the class is generally applicable: PR back to this skill's `145-EXTENDED-FAILURE-CATALOG.md`.

The catalog grows; the value compounds.

---

## Polish Bar checks for B145

- [ ] All 38 classes documented with: symptom, root cause, fix, regression test, pattern reference.
- [ ] Project-local catalog at `docs/billing/failure-catalog.md` mirrors + extends.
- [ ] On-call engineers have read the catalog at least once.
- [ ] New engineers read during onboarding.
- [ ] Each new incident: catalog updated within 1 week.
- [ ] Quarterly review: count of recurrences per class; drives systemic-fix priorities.

---

## Common B145 mistakes

- **Catalog written but never read.** Operators don't recognize a recurrence. Fix: include in onboarding.
- **Catalog has one author.** Single-perspective bias. Multi-author + reviews.
- **Catalog grows unboundedly.** When > 100 entries, group + cross-reference; consider per-bundle sub-catalogs.
- **No postmortem-to-catalog flow.** Postmortems written; catalog stale.
- **Project-local catalog forks from this skill's catalog.** Drift; future agents confused. Periodically merge upstream.
- **Symptom field too vague.** "Billing problems" is not a symptom. Be specific: "Customer received duplicate welcome email after one-time charge."
