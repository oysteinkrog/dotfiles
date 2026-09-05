# The Polish Bar

A "production-grade billing system" is not "the happy path works." Every billing-touching change must pass these checks. The bar is *binary per dimension*: green or red, no half-credit. If a dimension is `n/a` for the bundle, document why.

The Polish Bar is what coverage matrix `present` rows have to satisfy. It's also the gate Phase 7 fresh-eyes uses to decide if a finding is real.

---

## How to use this file

1. After a Phase 5 bundle implementation, walk every dimension below for that bundle.
2. For each dimension, run the **verification query** (a grep, a test, or a manual file check).
3. If green, mark the bundle's row in the coverage matrix `present`.
4. If red, the bundle's not done. Either fix it now (a few-line change), or file as a Phase 4 task and continue.

---

## Dimension 1 — Provider-Authority

**Statement.** When the provider's state and our DB's state disagree, the provider wins. Renderers display provider-state (or visibly degrade) rather than confidently rendering stale DB-state.

**Verification.**
- For every entitlement check (paywall, feature flag, plan-tier read), confirm there's a `verify-as-write` fallback when the DB shows `none` but a recent checkout session exists.
- Cache reads return `provenance: live | fallback | unavailable`. The renderer checks provenance.
- The integrity-audit cron (`§50` of source guide) detects DB-vs-provider divergence and alerts.

**Verification grep:**
```bash
rg "subscription_status|hasActiveSubscription|checkUserPlan" -t ts | rg -v "test|mock"
# For each hit, confirm provider-fallback path exists.
```

**Source.** `00-NORTH-STAR §1`, `60-STATE-AND-LIFECYCLE §verify-as-write`, `100-ANALYTICS §MRR snapshot`.

---

## Dimension 2 — Layered-Defense

**Statement.** Three write paths (live webhook, verify-as-write, reconciliation cron) and three alarm paths (per-event admin alert, stale-pipeline alarm, email failsafe) cover every entitlement-affecting event. A single failure mode is caught by the next layer.

**Verification.**
- For every entitlement-affecting event type (subscription.created, .updated, .deleted, invoice.paid, charge.refunded, etc.), confirm:
  - A live webhook handler.
  - A verify-as-write code path that also writes if DB shows no subscription yet.
  - A reconciliation cron that drains unprocessed `payment_events` rows.
- For every webhook stuck > N minutes, confirm an alarm fires.
- For every email-DLQ entry > 30min, confirm a failsafe escalation path.

**Verification queries:**
```bash
# Confirm the three crons exist
ls src/app/api/cron/ | rg "webhook-reconciliation|webhook-staleness|email-queue"

# Confirm verify-as-write writer exists
rg "reconcilePendingCheckoutForUser|verifyAsWrite|/api/checkout/verify" -t ts

# Confirm OPS_FAILSAFE_EMAIL is wired
rg "OPS_FAILSAFE_EMAIL" -t ts
```

**Source.** `00-NORTH-STAR §3`, `90-RELIABILITY`.

---

## Dimension 3 — Idempotent-Writes (provider + DB + WHERE-guard)

**Statement.** Every billing write is safe to repeat. Three layers of dedup:
- Provider idempotency key (Stripe `Idempotency-Key`; PayPal `PayPal-Request-Id`).
- DB-side UNIQUE constraint or partial UNIQUE index.
- Status-set `WHERE` guard on every UPDATE.

**Verification.**
- Every Stripe SDK call that creates / mutates resources passes `idempotencyKey`.
- Every PayPal API request includes `PayPal-Request-Id` header.
- `payment_events` has `UNIQUE (provider, event_id)`.
- `users.pending_checkout_session_id` has a partial UNIQUE index (one open intent per user; one global session id).
- Every UPDATE on `subscriptions` / `organizations` includes:
  - Stable address (`user_id` / `org_id`)
  - Provider-side cross-check (`subscription_id` / `customer_id`) where applicable
  - `WHERE last_event_at < new_event_at`
  - Status-set guard where state transitions matter (e.g., `WHERE status IN ('active', 'past_due')`)

**Verification queries:**
```bash
# Find UPDATEs missing the cross-check
rg "db\.update\(subscriptions\)" -A 8 -t ts | rg -v "last_event_at"

# Find Stripe API calls without idempotency key
rg "stripe\.(?:subscriptions|customers|invoices|paymentIntents)\.create\(" -A 10 -t ts | rg -v "idempotencyKey"
```

**Source.** `00-NORTH-STAR §4`, `40-WEBHOOKS §recordWebhookEvent`, `30-CHECKOUT §idempotency`.

---

## Dimension 4 — Hijack defense

**Statement.** Every WHERE clause that addresses a row by an attacker-controllable identifier (`metadata.user_id`, PayPal `custom_id`) cross-checks against an attacker-not-controllable identifier we already trust (stored `payer_id`, our own `customer_id`).

**Verification.**
- `validatePayPalUserId` (or equivalent) runs on EVERY PayPal individual handler before any state mutation.
- Every team-org UPDATE includes `subscription_id` (or `paypal_subscription_id`) in the WHERE clause.
- For Stripe Connect / org event endpoints: `event.account` / context check before processing.
- 0-row UPDATE on rejection path is silent + safe; emit `webhook_event_rejected` security event + `trackAbuseSignal`.

**Verification queries:**
```bash
# PayPal handlers without validatePayPalUserId
rg "paypal" -t ts -l | xargs rg "metadata\.user_id|custom_id" -l | xargs -I{} sh -c 'rg "validatePayPalUserId" {} || echo MISSING: {}'

# Team-org UPDATEs without subscription_id cross-check
rg "db\.update\(organizations\)" -A 10 -t ts | rg -v "subscription_id|paypal_subscription_id"
```

**Source.** `50-SECURITY §validatePayPalUserId`, §`subscription_id WHERE`, §account-mismatch (78a.1). Bead trail: `bd-2gxws`, `bd-08xvg.1`, SA-01.

---

## Dimension 5 — Stale-event ordering

**Statement.** Every UPDATE on a status / period / cancelled-at field includes `WHERE last_event_at < new_event_at`. `last_event_at` lives on the row, not the audit table.

**Verification.**
- `subscriptions` and `organizations` (and any equivalent table) have a `last_event_at timestamptz` column.
- Every UPDATE that mutates state includes the WHERE clause.
- The clause uses provider-side `event.created`, NOT local `now()` or `updated_at`.

**Verification query:**
```bash
# Updates missing the staleness guard
rg "set\([^)]*status:" -A 5 -t ts | rg -v "last_event_at"
```

**Source.** `00-NORTH-STAR §12`, `50-SECURITY §replay-staleness`.

---

## Dimension 6 — 200-on-error after recordWebhookEvent

**Statement.** Webhook handlers always return 200 once `recordWebhookEvent` has succeeded, even on processing error. Reconciliation cron retries off our own `payment_events` rows.

**Verification.**
- Top-level `try / catch` in webhook routes wraps the handler dispatch.
- The catch logs `eventId` and returns 200 with `outcome: "error_acknowledged"`.
- The route returns 4xx ONLY for: missing signature, invalid signature, malformed JSON before `recordWebhookEvent` runs.

**Verification query:**
```bash
# 500 returns from webhook routes after processing
rg "stripe/webhook|paypal/webhook" -A 30 -t ts -l | xargs rg -A 2 "status: 500"
```

**Source.** `00-NORTH-STAR §5`, `40-WEBHOOKS §10`. Bead trail: `bd-1zzos`.

---

## Dimension 7 — Synchronous cache invalidation on refund

**Statement.** When a refund is processed, the user's denormalized `subscription_status` cache and any per-user CDN cache must be invalidated *synchronously* before the 200 returns to the provider, with a 2s `Promise.race` cap so a slow invalidation doesn't block.

**Verification.**
- Refund handler explicitly invalidates per-user caches (Vercel `revalidateTag`, Redis `DEL`, etc.).
- Invalidation is wrapped in `Promise.race([invalidate(), sleep(2000)])`.
- Failure of invalidation is logged but does NOT throw.

**Verification query:**
```bash
rg "revokeAccessOnRefund|charge\.refunded|REFUND" -A 30 -t ts | rg "revalidateTag|cache\.invalidate|redis\.del|Promise\.race"
```

**Source.** `60-STATE §refunds`, `78a.2 (SA-02)` of source guide. Bead trail: SA-02.

---

## Dimension 8 — Analytics exclusions

**Statement.** A single canonical `exclusions.ts` (or equivalent) is imported by every cron, every analytics read, every admin event publisher, every dunning select. A drift-guard test pins the import list.

**Verification.**
- One file owns the synthetic-fixture predicates.
- Every cron / publisher / analytics read imports from there.
- Drift-guard test (e.g., `cronsThatMustExclude`) lists every cron and asserts the import.
- Activity feed and metric counters AGREE on test signups (both filter, or neither does).

**Verification query:**
```bash
# Crons without the exclusions import
ls src/app/api/cron/ | xargs -I{} sh -c 'rg "from.*analytics/exclusions" src/app/api/cron/{}/route.ts || echo MISSING: {}'
```

**Source.** `100-ANALYTICS §exclusions`, `110-OPERATIONS §drift-guard`.

---

## Dimension 9 — Provenance everywhere

**Statement.** Every cached billing value carries `live | fallback | unavailable`. Renderers refuse to render `unavailable` as a number; they show the chip.

**Verification.**
- `getCurrentMrrSnapshot` (or equivalent) returns `{ value, provenance }`, never just `value`.
- Cache wrapper (e.g., `singleFlightCache`) propagates provenance.
- Renderers / API responses include provenance and use it.

**Verification query:**
```bash
rg "cache\.get|getCurrentMrr|getCurrentChurn" -A 5 -t ts | rg -v "provenance"
```

**Source.** `00-NORTH-STAR §1`, `100-ANALYTICS §MRR snapshot, §single-flight, §reconciliation-freshness`.

---

## Dimension 10 — Cron defenses

**Statement.** Every cron uses `pg_try_advisory_lock` (or platform equivalent), bounded scans, bounded retries, `finally { conn.release() }`, and a terminal-stuck digest for rows past the retry cap.

**Verification.**
- Every cron route handler starts with a try-lock; bails out 200 if not acquired.
- The reserved DB connection is released in `finally`.
- The SELECT has `LIMIT N` matching the per-run wall-time budget.
- Per-row retry cap exists; rows past the cap fire a digest, not retried forever.

**Verification queries:**
```bash
# Crons without pg_try_advisory_lock
ls src/app/api/cron/ | xargs -I{} sh -c 'rg "pg_try_advisory_lock" src/app/api/cron/{}/route.ts || echo MISSING: {}'

# Crons without finally release
rg "pgClient\.reserve\(\)" -A 30 -t ts | rg -v "finally"
```

**Source.** `00-NORTH-STAR §8`, `90-RELIABILITY §cron-defenses`. Failure mode catalog: source `§78` item 8.

---

## Dimension 11 — Secret custody

**Statement.** Every Stripe / PayPal / Supabase / cron / alert credential is in production-only env, marked sensitive, environment-isolated, rotation-tracked. No `NEXT_PUBLIC_*` for any billing-secret credential.

**Verification.**
- `.env.production` and Vercel project env are the ONLY places live secrets exist.
- Vercel sensitive flag is set on every billing secret.
- Preview / Development env contains test-mode keys ONLY.
- No `NEXT_PUBLIC_STRIPE_SECRET_KEY` etc. (publishable keys are OK in NEXT_PUBLIC; secret keys are not).
- A secret-custody matrix exists at `phase10_secret_custody.md`.
- Rotation cadence is documented; last rotation timestamp is recorded.

**Verification queries:**
```bash
# Public env vars that should be secret
rg "NEXT_PUBLIC_" -t ts | rg -i "secret|key|token" | rg -v "publishable|test_pk_"

# Secrets accidentally in client bundle (after build)
./scripts/audit-bundle-leakage.sh
```

**Source.** `00-NORTH-STAR §11`, `20-CONSTANTS-AND-ENV §env`, `78a.6b` of source guide.

---

## Dimension 12 — Pin-the-contract regression test

**Statement.** Every fix has a regression test named after the bead/incident it pins, so future-you knows what they're giving up if they delete it.

**Verification.**
- For every fix in this bundle, a test exists with naming pattern `bd-<id>__<short_description>` or `<incident>__<contract>.test.ts`.
- The test covers the adversarial case, not just the happy path.
- Drift-guard tests pin invariants that have no obvious code line (cronsThatMustExclude, WebhookErrorCodesCompleteness, etc.).

**Verification query:**
```bash
rg "describe\(|test\(|it\(" -t ts | rg "bd-|sa-|billing-h|billing-m" | wc -l
# Should be > 0 in any bundle that's had real fixes.
```

**Source.** `00-NORTH-STAR §15`, `110-OPERATIONS §integration-tests`.

---

## Dimension 13 — Type-derive, not hard-code

**Statement.** SDK strings (Stripe API version, plan IDs, event types, status enums) are typed constants in one place. Future SDK upgrades fail to compile, not at runtime.

**Verification.**
- `STRIPE_API_VERSION` is one constant in one file, derived from `ConstructorParameters<typeof Stripe>[1]['apiVersion']`.
- No literal API version string anywhere else.
- Plan IDs are in `BUSINESS` (or equivalent constants module).
- Event type literals are in a registry, not inline strings.

**Verification queries:**
```bash
# Hardcoded API version literals
rg '"20\d{2}-\d{2}-\d{2}\.[a-z]+"' -t ts | rg -v "STRIPE_API_VERSION ="

# Inline event type literals
rg '"customer\.subscription|invoice\.payment|charge\.refunded"' -t ts | rg -v "EVENT_TYPES|StripeEventType ="
```

**Source.** `00-NORTH-STAR §13`, `20-CONSTANTS-AND-ENV §STRIPE_API_VERSION`. Bead trail: `bd-vifc1`.

---

## Dimension 14 — Priority-aware queue

**Statement.** Every email / notification / alert type has an explicit priority branch in the central `inferEmailJobPriority` (or equivalent). Refund / dispute / past-due > customer-facing transactional > admin ops > digests > newsletter.

**Verification.**
- `inferEmailJobPriority` has a branch for every `metadata.type` the system creates.
- The queue's processing order respects priority via `(priority, next_retry_at, created_at)` index.
- DLQ failsafe sweeps don't squash priority on the recovery summary.

**Verification queries:**
```bash
# Email types created without priority
rg "createEmailJob\(" -A 5 -t ts | rg -v "priority|inferEmailJobPriority"
```

**Source.** `90-RELIABILITY §email-queue priority`. Bead trail: `bd-bfwcy.5 / BILLING-M3`.

---

## Dimension 15 — Bidirectional event coverage

**Statement.** The set of events subscribed in the provider's webhook endpoint config equals the set of events handled in code.

**Verification.**
- A coverage report compares the live provider config (Stripe Dashboard, PayPal app config) to the in-code handler set.
- Subscribed-but-unhandled events are explicitly OK only if a one-line `// intentionally ignored` documents why.
- Handled-but-unsubscribed events are flagged as dead code.

**Verification queries:**
```bash
# In-code handler set
rg 'case "([^"]+)"' src/app/api/stripe/webhook/handler.ts | sed 's/.*case "\([^"]*\)".*/\1/' | sort -u

# Compare against Stripe Dashboard webhook endpoint config (manual or via Stripe CLI):
stripe webhook_endpoints retrieve we_xxx | jq '.enabled_events[]' | sort -u
```

**Source.** `40-WEBHOOKS §coverage`, `78a.3` of source guide.

---

## Per-bundle Polish Bar checklist

Run this at the end of each Phase 5 bundle implementation. Each row should be ✓ or `n/a (justified)`.

| Dimension | B10 Schema | B20 Constants | B30 Checkout | B40 Webhooks | B50 Security | B60 State | B70 Dunning | B80 Teams | B90 Reliability | B100 Analytics | B110 Ops |
|-----------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 1 Provider-Authority | n/a | — | — | ✓ | — | ✓ | — | — | — | ✓ | — |
| 2 Layered-Defense | n/a | — | ✓ | ✓ | — | ✓ | — | ✓ | ✓ | — | — |
| 3 Idempotent-Writes | ✓ | — | ✓ | ✓ | — | ✓ | ✓ | ✓ | ✓ | — | — |
| 4 Hijack defense | — | — | ✓ | ✓ | ✓ | — | — | ✓ | — | — | — |
| 5 Stale-event ordering | ✓ | — | — | ✓ | ✓ | ✓ | — | ✓ | — | — | — |
| 6 200-on-error | — | — | — | ✓ | — | — | — | — | — | — | — |
| 7 Synchronous refund invalidation | — | — | — | — | — | ✓ | — | — | — | ✓ | — |
| 8 Analytics exclusions | — | — | — | — | — | — | ✓ | — | ✓ | ✓ | ✓ |
| 9 Provenance | — | — | — | — | — | — | — | — | — | ✓ | — |
| 10 Cron defenses | — | — | — | — | — | — | ✓ | — | ✓ | — | ✓ |
| 11 Secret custody | — | ✓ | — | — | ✓ | — | — | — | — | — | ✓ |
| 12 Pin-the-contract | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 13 Type-derive | — | ✓ | — | — | — | — | — | — | — | — | — |
| 14 Priority-aware queue | — | — | — | — | — | — | ✓ | — | ✓ | — | — |
| 15 Bidirectional coverage | — | — | — | ✓ | — | — | — | — | — | — | ✓ |

`✓` = dimension applies; must be green. `—` = dimension doesn't apply to this bundle. `n/a` = dimension only applies in derived form (e.g., schema doesn't enforce provider-authority directly, but supports it).

This matrix is the de-facto exit gate for Phase 5/6.
