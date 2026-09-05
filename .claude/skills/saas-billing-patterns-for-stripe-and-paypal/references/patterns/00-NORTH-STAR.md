# Bundle B00 — North-Star Principles

> **Where this comes from.** § 1, § 2 of the source guide. Every pattern in every other bundle is a corollary of these.

This bundle has no code. Its job is to give you the three sentences you should mentally repeat before reading any other bundle, plus the architecture diagram everyone should be able to draw on a whiteboard.

---

## The 16 north-star principles (in priority order)

<!-- BILLING_KERNEL_START v1.0 -->

1. **Provider is source of truth.** Stripe / PayPal are authoritative. Our DB is a *fast cache* of provider state. When they disagree, the provider wins. Corollary: every cache value carries `provenance: live | fallback | unavailable`. Every reader checks provenance before rendering a number.

2. **Webhooks are best-effort.** Treat every webhook as "may arrive, may be late, may never come, may be duplicated, may be replayed by an attacker." Build for all five.

3. **Layered defenses, not single guards.** Three write paths (live webhook, verify-as-write, reconciliation cron) and three alarm paths (per-event admin alert, stale-pipeline alarm, email failsafe escalation) so any single failure mode is caught by the next layer — never by a customer support ticket.

4. **Idempotency at every write boundary.** Provider-side idempotency keys + DB-side `payment_events` dedup + partial-UNIQUE indexes (one OPEN intent per (user, sub); one pending checkout session ID globally) + status-set `WHERE` guards on UPDATEs + `WHERE last_event_at < new_event_at` for ordering.

5. **Always return 200 to the provider after authenticated event ingestion** — even on processing errors. Missing/invalid signatures and malformed JSON can still fail at the protocol boundary. Once a trusted provider event has a `payment_events` row, returning 500 just causes 3-day retry storms with partial-success duplicates. The reconciliation cron retries cleanly off our own `payment_events` rows.

6. **Refund decisions belong to humans.** No automated refund or auto-cancel of a suspicious subscription. Detect, alert, queue for triage.

7. **Synthetic test fixtures must be excluded from every read** (analytics, dunning, alerts, integrity audits, MRR, weekly digests). One canonical `exclusions` module. A drift-guard test pins the audit list so a new cron added without exclusions is caught in CI.

8. **Every cron uses a database advisory lock** to prevent overlap across isolates. Bounded scans, bounded retries, terminal-stuck digests so unbounded retry queues don't spam forever. **Reserved DB connection** for the lock — don't hand it back to the pool while the lock is held.

9. **Slow provider calls happen OUTSIDE the DB transaction.** The intent row is the durable record; reconciliation closes any divergence. The lock + intent insert + commit takes ~50ms; the provider call can take 80s–3min during slowdowns. Holding a pool connection for 3 minutes under bursts is how you exhaust the pool.

10. **Verify-as-write.** The `/api/checkout/verify` endpoint can ALSO write subscription state if the webhook hasn't landed yet. The webhook is a backup, not the primary writer.

11. **Secrets are part of the billing boundary.** Stripe secret/restricted keys, Stripe webhook secrets, PayPal client secrets, Supabase secret/service-role keys, cron secrets, and ops alert tokens are not "deployment details." They are capabilities that can create charges, grant access, read provider payloads, or bypass RLS. Track custody, scope, rotation, and audit evidence with the same seriousness as webhook code.

12. **`last_event_at` is the only correct ordering primitive.** Don't use `updatedAt` (reconciliation discovers drift long after the customer event). Don't use the local clock (webhooks arrive out of order). The provider's own event timestamp is the single ground truth — and it must be on the row, not the audit table.

13. **Centralize every constant** that touches money or state semantics: pricing, API version + client, routes, error codes, feature flags. Hard-coded duplicates rot.

14. **Type-derive against the SDK, never hard-code SDK strings.** Pin the Stripe API version using a type derived from `ConstructorParameters<typeof Stripe>[1]['apiVersion']` so a future bump Stripe doesn't recognize fails to compile. The version constant is the only string in the entire codebase.

15. **Exclude analytics-excluded users from EVERY publisher and EVERY read.** The activity feed and the metric counters MUST agree. A "new subscriber!" event for a test signup that doesn't show up in the MRR card is a customer support ticket waiting to happen.

16. **For every billing-touching DB write, add a regression test that pins the contract.** The test name should map to the bead/incident ID. When you delete or rename the test, that's how the next person knows what they just gave up.

<!-- BILLING_KERNEL_END v1.0 -->

---

## The architecture diagram (everyone should be able to draw this from memory)

```
┌─────────────────────────────────────────────────────────────────────┐
│                        WRITE PATHS (3 layers)                        │
├─────────────────────────────────────────────────────────────────────┤
│ L1 LIVE WEBHOOK   →  /api/{stripe,paypal}/webhook                    │
│                       Signature verified, payment_events row INSERT, │
│                       handler dispatches by event type, marks        │
│                       processed_at=now(). 200 on post-ingest errors. │
│                                                                      │
│ L2 VERIFY-AS-WRITE → /api/checkout/verify                            │
│                       User landed on /dashboard with session_id.     │
│                       If DB shows no active sub, fetch session from  │
│                       provider; if "paid", call updateSubscription   │
│                       Status() inline. Webhook becomes a backup.     │
│                                                                      │
│ L3 RECONCILIATION  →  /api/cron/webhook-reconciliation (every 5m)    │
│                       Drains payment_events WHERE processed_at IS    │
│                       NULL AND age > 5m. Bounded retries. Per-event  │
│                       claim lease prevents double-processing.        │
│                                                                      │
│    PROVIDER SWEEP  →  /api/cron/provider-reconciliation (every 6h)   │
│                       Lists all subs from Stripe/PayPal, compares to │
│                       DB, fixes drift. Catches webhooks that were    │
│                       silently dropped at the provider edge.         │
│                                                                      │
│    INTEGRITY AUDIT →  /api/cron/billing-integrity-audit (daily)      │
│                       Backstop. Lists billable subs grouped by       │
│                       email; alerts on any user with >1.             │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                      ALARM PATHS (3 layers)                          │
├─────────────────────────────────────────────────────────────────────┤
│ A1 PER-EVENT       →  payment_events.retry_count >= MAX_RETRY_COUNT  │
│                       fires admin email + complianceEvents row.      │
│                                                                      │
│ A2 STALE PIPELINE  →  /api/cron/webhook-staleness (every 5m)         │
│                       Any payment_events row unprocessed > 10m       │
│                       pages admin. Dedupes within 60m.               │
│                       Terminal-stuck digest re-pages every 24h.      │
│                                                                      │
│ A3 EMAIL FAILSAFE  →  /api/cron/email-queue post-batch sweep         │
│                       Detects billing_*_alert jobs DLQ'd > 30m and   │
│                       sends a SUMMARY email via OPS_FAILSAFE_EMAIL   │
│                       (different inbox than ADMIN_EMAIL — survives a │
│                       Gmail filter eating "[ALERT]" messages).       │
└─────────────────────────────────────────────────────────────────────┘
```

The whole architecture is a deliberate response to a real chain of incidents:

| Incident | What it forced |
|----------|----------------|
| Tom Hunter triple-charge (`bd-1m86f`) | Cross-provider checkout guard, deterministic idempotency, customer-id reuse, webhook-staleness alarm, daily integrity audit |
| Marco Fanti PayPal silent loss (`bd-1ug5i`) | Webhook-staleness alarm, provider-reconciliation cron tightened |
| PayPal team webhook hijack (`bd-08xvg.1`) | `subscription_id` cross-check on every UPDATE WHERE clause |
| PayPal individual hijack (`bd-2gxws`) | `validatePayPalUserId()` cross-checks `custom_id` against stored payer_id |
| Stripe checkout URL encoding (`bd-lp3vu`) | Template-literal `success_url`, lint rule, regression test |
| Pause/resume pool exhaustion (`bd-yu9g9` / Billing-H4) | Intent-then-act, intent table, reconciliation cron behind FF |
| Refund alert lost when Resend down (`bd-ja8c0` / Billing-H1) | Email-queue failsafe, OPS_FAILSAFE_EMAIL |
| Newsletter delaying refund alert (`bd-bfwcy.5` / BILLING-M3) | `email_jobs.priority` smallint + index |
| GDPR delete left ghost Stripe sub (`bd-bfwcy.6` / BILLING-M5) | Orphan-cancel rows INSIDE delete tx, retry cron |
| Cancelled team revived by replay (`bd-08xvg.3` / SA-03) | Cancelled-status guard in reconcile branch |
| Stale Stripe replay revived | `last_event_at` gating on replay |
| PayPal partial refund stripped access (`bd-hbfat` / Billing-H2) | Fetch parent payment, cumulative refund math, fall back safe |

**Read this table when scoping any bundle.** Each row is a real customer-facing failure that the architecture exists to prevent. If your project has the corresponding pattern *missing*, you're vulnerable to the same incident.

---

## The "if you only have an hour" reading list

The source guide is 6800 lines. If you have ≤1 hour and need the most leverage:

1. § 1 (this section, principles)
2. § 2 (architecture diagram)
3. § 3 (schema — what the four load-bearing tables are and why)
4. § 6 (provider-symmetric checkout — the canonical sequence)
5. § 10 (the 5-step webhook ingestion contract)
6. § 13 (webhook hijack defense — three layers)
7. § 28 (failure-mode catalog — 38 incidents)
8. § 29 (patterns that were tried and rejected — 10 anti-patterns)

Everything else expands these.
