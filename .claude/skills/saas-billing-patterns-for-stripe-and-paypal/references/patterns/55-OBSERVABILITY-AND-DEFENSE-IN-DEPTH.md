# Bundle B55 — Observability & Defense-in-Depth

> **Where this comes from.** § 78a.4–§ 78a.10 of the source guide. Plus § 78a.11 forward-looking patterns.

This bundle is the "we already have the basic billing system; how do we make it production-grade observable + defense-in-depth?" layer. Most of these are NOT in the original source-guide architecture but are forward-looking additions flagged by the security audit + world-class SaaS practice.

Skip this bundle in T1/T2 (pre-launch / early-stage); essential by T3 (growth) and non-optional by T4 (scale).

---

## § 78a.4 — Webhook observability metrics + Prometheus alerts

### Metrics to emit

```
webhook_received_total{provider, event_type}              counter
webhook_signature_fail_total{provider}                    counter
webhook_duplicate_total{provider}                         counter   ← idempotency working as designed
webhook_processing_duration_seconds{provider, event_type} histogram
webhook_processing_error_total{provider, event_type}     counter   ← needs reconciliation
webhook_replay_blocked_total{provider, reason}            counter   ← from §16/SA-22 stale-event gate
```

The duplicate counter is signal-positive — you WANT some duplicates (it proves dedup works; it proves provider retried legitimately). Watch its RATE; sudden spike means provider is having delivery issues.

### Alert rules

```yaml
- alert: WebhookSignatureFailureSpike
  expr: rate(webhook_signature_fail_total[5m]) > 5
  for: 1m
  severity: P1
  description: "Webhook signature failures spiking — possible forgery attack"

- alert: WebhookProcessingSlow
  expr: histogram_quantile(0.99, rate(webhook_processing_duration_seconds_bucket[5m])) > 10
  for: 5m
  severity: P2
  description: "Webhook p99 >10s — reconciliation lag, possible attack load"

- alert: WebhookProcessingErrorRate
  expr: rate(webhook_processing_error_total[5m]) / rate(webhook_received_total[5m]) > 0.01
  for: 5m
  severity: P1
  description: "Webhook error rate above 1% — investigate handler bug or provider outage"

- alert: WebhookReplayBlockedSpike
  expr: rate(webhook_replay_blocked_total[10m]) > 10
  for: 5m
  severity: P0
  description: "Replay-blocked spike — likely bookkeeping bug AND/OR active replay attack"
```

These complement the in-code alarms (`§48` webhook-staleness, `§52` email failsafe). Today most projects have `logger.info`/`warn`/`error` calls in the right places; aggregating into Prometheus + alerting closes the observation loop.

### How to instrument

```ts
// src/lib/observability/webhook-metrics.ts
import { Counter, Histogram } from 'prom-client';

export const webhookReceivedTotal = new Counter({
  name: 'webhook_received_total',
  help: 'Webhook events received after signature verification',
  labelNames: ['provider', 'event_type'],
});

export const webhookSignatureFailTotal = new Counter({
  name: 'webhook_signature_fail_total',
  help: 'Webhook signature verification failures',
  labelNames: ['provider'],
});

export const webhookDuplicateTotal = new Counter({
  name: 'webhook_duplicate_total',
  help: 'Webhook events that hit dedup (skipped_idempotent path)',
  labelNames: ['provider'],
});

export const webhookProcessingDurationSeconds = new Histogram({
  name: 'webhook_processing_duration_seconds',
  help: 'Time from recordWebhookEvent to markEventProcessed',
  labelNames: ['provider', 'event_type'],
  buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60],
});

export const webhookProcessingErrorTotal = new Counter({
  name: 'webhook_processing_error_total',
  help: 'Webhook handlers that threw after recordWebhookEvent succeeded',
  labelNames: ['provider', 'event_type'],
});

export const webhookReplayBlockedTotal = new Counter({
  name: 'webhook_replay_blocked_total',
  help: 'UPDATE attempts blocked by last_event_at staleness gate',
  labelNames: ['provider', 'reason'],
});
```

Wire into the webhook handler at the appropriate points (after sig verify; after recordWebhookEvent dedup decision; around handler dispatch; in the staleness-gate code).

For Vercel deployments without a Prometheus scraper, push metrics to a hosted aggregator (Grafana Cloud, Honeycomb, Axiom, Better Stack) via their Vercel integration.

---

## § 78a.5 — CSP for Stripe Elements / Checkout / Radar

The Content-Security-Policy header for any page that embeds Stripe must allow the Stripe domains. Without these, Stripe Elements / Checkout / Radar fail silently in production.

```
Content-Security-Policy:
  default-src 'self';
  script-src 'self' https://js.stripe.com https://m.stripe.network;
  connect-src 'self' https://api.stripe.com https://m.stripe.network
              https://*.supabase.co wss://*.supabase.co;
  frame-src https://checkout.stripe.com https://js.stripe.com
            https://hooks.stripe.com https://m.stripe.network;
  frame-ancestors 'none';
  form-action 'self';
  base-uri 'self';
  object-src 'none';
```

| Directive | Why |
|-----------|-----|
| `script-src https://js.stripe.com` | Stripe.js initializes Elements |
| `script-src https://m.stripe.network` | Stripe Radar (fraud detection) loads from this domain |
| `frame-src https://checkout.stripe.com` | Stripe-hosted checkout redirect target |
| `frame-src https://js.stripe.com` | Stripe Elements iframe |
| `frame-src https://hooks.stripe.com` | 3-D Secure challenge iframe |
| `frame-src https://m.stripe.network` | Radar's cross-origin iframe |
| `connect-src https://api.stripe.com` | Stripe.js → Stripe API direct |
| `frame-ancestors 'none'` | Anti-clickjacking — billing pages must NOT be embeddable |
| `form-action 'self'` | Prevents your forms from POSTing to attacker-controlled domains |

### PayPal CSP

Simpler ONLY when the app uses a pure server-created approval URL and redirects the buyer away from your page. If the app renders the PayPal JavaScript SDK (Smart Buttons, marks, messages, card fields), CSP must explicitly allow:
- `https://www.paypal.com/sdk/js`
- `paypalobjects.com` (PayPal-owned frame/script origin)

Treat "no PayPal CSP additions" as a **redirect-only claim**, not a general PayPal integration rule. Audit your specific implementation.

### Verifying CSP

```bash
curl -sI https://<your-domain>/checkout | grep -i content-security-policy
```

For Next.js: set in `next.config.js` under `headers()` or in middleware. For Vercel: also configurable via dashboard for project-wide headers.

Add a CSP-coverage drift-guard test that asserts the response header on `/checkout` contains the expected Stripe + (if applicable) PayPal directives.

---

## § 78a.6 — Credential rotation cadence

| Credential | Rotation cadence | Trigger event |
|------------|------------------|---------------|
| Stripe secret key (`sk_live_...`) | 90 days | Any team member with prod access leaves |
| Stripe webhook secret (`whsec_...`) | 180 days | Webhook endpoint URL change |
| PayPal client secret | 180 days | Any team member with prod access leaves |
| PayPal webhook ID | (rare) | PayPal-driven only |
| `STRIPE_PRICE_ID` family | Never (rotate plans, not IDs) | New pricing tier — create new price; deprecate old |
| `SUPABASE_SERVICE_ROLE_KEY` | 365 days OR on team change | Any team member with prod access leaves |
| `CRON_SECRET` | 90 days | Any deploy integration compromise; team member with deploy access leaves |
| `RESEND_API_KEY` | 365 days | Resend account compromise; team member access change |

### Rotation without downtime

Most providers allow multiple active keys simultaneously:

```
Step 1: Add NEW key in provider dashboard.
Step 2: Deploy app with NEW key in env vars.
Step 3: Verify webhooks still work with NEW key (Stripe CLI test, PayPal sandbox sim).
Step 4: Keep old endpoint secret active during dashboard-roll overlap window
        (Stripe supports up to 24h) so all deployed instances pick up new secret.
Step 5: Revoke OLD key in provider dashboard.
Step 6: Audit dashboard for unusual activity during exposure window.
```

For Stripe webhook secrets specifically: the overlap window is about deploy propagation, not the entire webhook retry period. Stripe generates the timestamp + signature each time it sends an event; while both endpoint secrets are active, Stripe includes signatures for both. After old secret expires, later retries are signed with the remaining active secret. If your code supports `STRIPE_WEBHOOK_SECRET_PREVIOUS`, keep it ONLY long enough to cover propagation, then remove it deliberately.

### Rotation log

Maintain `phase10_secret_custody.md` rotation log section:

```markdown
| Secret | Rotation date | Reason | Rotated by | Verified by | Old key revoked at |
|--------|---------------|--------|------------|-------------|---------------------|
| STRIPE_SECRET_KEY | 2026-04-15 | Quarterly cadence | <name> | <name> | 2026-04-16 09:00 UTC |
| STRIPE_WEBHOOK_SECRET | 2026-01-12 | Annual + endpoint URL change | <name> | <name> | 2026-01-13 18:00 UTC |
| ... | ... | ... | ... | ... | ... |
```

Drift-guard: a test that fails if any secret's `last_rotated` field is past its cadence.

---

## § 78a.7 — Webhook timestamp tolerance window (defense-in-depth)

Defense in depth on top of `last_event_at` ordering: track event AGE, but do NOT reject normal provider webhooks solely because `event.created` is old. That would drop legitimate late Stripe retries and the exact webhook-delivery-gap incidents this guide is trying to survive.

**Stripe's signature libraries already enforce a separate delivery-signature timestamp tolerance.** That timestamp is generated each time Stripe sends the event and is NOT the same as the event object's `created` time.

```ts
const WEBHOOK_EVENT_AGE_OBSERVABILITY_SECONDS = 300;  // 5 min

// After signature verification, before recordWebhookEvent:
const eventTimestampMs = event.created * 1000;
const ageSeconds = (Date.now() - eventTimestampMs) / 1000;

if (ageSeconds > WEBHOOK_EVENT_AGE_OBSERVABILITY_SECONDS) {
  // Do NOT reject ordinary billing events here. Old event.created can mean a
  // legitimate provider retry, dashboard resend, or delayed delivery. Log it
  // as observability/security signal and let per-event idempotency plus
  // last_event_at ordering decide whether it is safe to apply.
  logSecurityEvent({
    type: "webhook_event_age_exceeded",
    severity: "warn",
    actor: { authSource: "stripe_webhook" },
    target: { type: "stripe_event", id: event.id },
    details: { reason: "event_created_older_than_observability_window", ageSeconds },
  });
}
```

### Two clocks for two jobs

1. **Signature timestamp tolerance** — keep Stripe's `constructEvent()` / SDK default tolerance on the `Stripe-Signature` timestamp. That prevents attacker replay of an old signed HTTP request.
2. **Business event ordering** — use provider event time (`event.created`, PayPal `create_time` / `status_update_time`) only inside `last_event_at` / `paypalLastEventAt` compare-and-swap guards. An old provider event can be REAL; ignore it only when it would move state backwards.

Hard-reject by event age ONLY in manually scoped replay tooling where the operator has explicitly chosen a bounded time window. Do NOT put that rejection in the live billing webhook path.

---

## § 78a.8 — Cross-provider webhook confusion (BL-42)

**The class.** A Stripe-formatted webhook payload sent to the PayPal endpoint (or vice versa). If the handler dispatches off `event.event_type` without first validating that the field shape matches the expected provider, malformed input could trigger unexpected code paths.

**Defense.** Each provider's route MUST validate the provider-specific header set BEFORE any field access:

```ts
// /api/stripe/webhook/route.ts:
const signature = request.headers.get("stripe-signature");
if (!signature) return rejectWithSignal("missing_stripe_signature");

// /api/paypal/webhook/route.ts:
const transmissionId = request.headers.get("paypal-transmission-id");
if (!transmissionId) return rejectWithSignal("missing_paypal_transmission_id");
```

Today most projects do this correctly. The drift-guard is to ensure no shared "generic webhook" abstraction creeps in.

**Never add a `/api/webhooks/payments` endpoint that auto-detects provider** — keep routes provider-specific so a Stripe payload to a PayPal endpoint is explicitly rejected at the header check.

A drift-guard test asserts:
- `/api/stripe/webhook` route returns 400 if `stripe-signature` header is absent.
- `/api/paypal/webhook` route returns 400 if `paypal-transmission-id` header is absent.
- No file in `src/app/api/webhooks/` exists (the generic-route honeypot).

---

## § 78a.9 — Chargeback abuse process

When `charge.dispute.created` fires (Stripe) or PayPal dispute event fires:

### Account-lock state

```sql
ALTER TABLE users
  ADD COLUMN disputed_at        timestamptz,
  ADD COLUMN chargeback_count   int NOT NULL DEFAULT 0,
  ADD COLUMN billing_banned_at  timestamptz;
```

### Handler

```ts
async function handleStripeDispute(event: Stripe.Event.ChargeDisputeCreated) {
  const dispute = event.data.object;
  const charge = await stripe.charges.retrieve(dispute.charge as string);
  const userId = await resolveUserFromCharge(charge);
  if (!userId) return;

  await db.transaction(async (tx) => {
    // 1. Lock the account
    await tx.update(users)
      .set({ disputedAt: new Date() })
      .where(eq(users.id, userId));

    // 2. Increment chargeback count
    const updated = await tx.update(users)
      .set({ chargebackCount: sql`${users.chargebackCount} + 1` })
      .where(eq(users.id, userId))
      .returning({ chargebackCount: users.chargebackCount });

    // 3. After threshold (e.g., 2 lifetime), billing-ban the account
    if (updated[0].chargebackCount >= 2) {
      await tx.update(users)
        .set({ billingBannedAt: new Date() })
        .where(eq(users.id, userId));
    }
  });

  // 4. Queue admin alert (priority 5 — critical)
  await createEmailJob({
    type: 'billing_critical_alert',
    recipient: env.ADMIN_EMAIL,
    payload: {
      subject: `[CHARGEBACK] User ${userId}; dispute ${dispute.id}; amount ${dispute.amount / 100}`,
      ...
    },
    priority: 5,
  });
}
```

### Access gating

```ts
// In auth middleware / paywall check:
const user = await getCurrentUser();
if (user.disputedAt !== null) {
  // Disputed — block premium access regardless of subscription status
  return { hasAccess: false, reason: 'disputed' };
}
if (user.billingBannedAt !== null) {
  // Billing-banned — cannot re-subscribe
  return { hasAccess: false, reason: 'billing_banned', canResubscribe: false };
}
```

### Resolution

When the dispute resolves:

- `charge.dispute.funds_reinstated` (we won) → CLEAR `disputedAt`, restore access. KEEP the chargeback count (still a signal).
- `charge.dispute.funds_withdrawn` + `closed` (we lost) → KEEP `disputedAt` set; do NOT restore access. Customer must contact support to be reinstated (and pay the chargeback fee).

### Why a separate `disputed_at` column

The chargeback may resolve months later. The account-lock state needs to survive subscription churn in the meantime. The support-contact-required-to-unlock is a deliberate friction — it screens out card-tester accounts.

### Stripe Connect / multi-account

If using Stripe Connect: the dispute belongs to the Connected account, not the platform. `event.account` tells you which account. Cross-check (per § 78a.1) before mutating user state.

---

## § 78a.10 — Nested side-effect idempotency

The pattern lets you mark each individual side-effect (admin event publish, welcome email, analytics ping) as already-emitted, so a webhook retry skips the ones that already succeeded but retries the ones that failed.

```sql
CREATE TABLE side_effect_log (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key       text NOT NULL UNIQUE,        -- '<event_id>:<side_effect>'
  emitted_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX side_effect_log_emitted_idx ON side_effect_log (emitted_at);
```

```ts
async function emitSideEffectOnce(
  eventId: string,
  sideEffect: string,
  action: () => Promise<void>,
): Promise<void> {
  const key = `${eventId}:${sideEffect}`;

  // Insert-on-conflict: if the row already exists, this side effect ran.
  const inserted = await db.insert(sideEffectLog)
    .values({ key, emittedAt: new Date() })
    .onConflictDoNothing()
    .returning({ key: sideEffectLog.key });

  if (inserted.length === 0) return;     // already emitted

  try {
    await action();
  } catch (err) {
    // Remove the marker so a retry can attempt again
    await db.delete(sideEffectLog).where(eq(sideEffectLog.key, key));
    throw err;
  }
}

// Usage in updateSubscriptionStatus or similar:
await emitSideEffectOnce(eventId, "publish_subscription_created", async () => {
  await publishSubscriptionCreated(userId, "individual", "stripe");
});
await emitSideEffectOnce(eventId, "send_welcome_email", async () => {
  await createEmailJob({ userId, ..., metadata: { type: "welcome" } });
});
await emitSideEffectOnce(eventId, "analytics_ping_signup", async () => {
  await analyticsClient.track({ userId, event: "subscription_started" });
});
```

### When this becomes load-bearing

Today's "good enough" idempotency is:
- Admin event publishers wrapped in try/catch that swallows errors.
- Welcome email gated by `isNew` returning true from `updateSubscriptionStatus` (atomic upsert).

That works for current event types. It becomes load-bearing when:
- A new side effect is non-idempotent on its own (e.g., posting to Slack channel that creates duplicate visible items).
- The reconciliation cron starts replaying events for non-trivial side effects.

File a bead when adding the first non-idempotent side effect. Until then, pin idempotency-by-construction in tests.

### Drift-guard

Test that asserts: every reconciliation-replay-able side effect uses `emitSideEffectOnce` (or has a documented equivalent guard).

---

## § 78a.11 — Forward-looking world-class patterns

These complement (don't replace) the source-guide design.

### 1. Economic facts come from provider settlement objects

Forecasting can use configured rates, but accounting should eventually read:
- Stripe Balance Transactions (`/v1/balance_transactions`)
- PayPal `seller_receivable_breakdown` / fee fields

Store gross, fee, tax, refund, dispute, and net as IMMUTABLE LEDGER ENTRIES. Then derive MRR and margin snapshots from that ledger.

```sql
CREATE TABLE settlement_ledger (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider        subscription_provider NOT NULL,
  provider_object_id text NOT NULL,
  type            text NOT NULL,           -- 'charge' | 'refund' | 'fee' | 'dispute' | 'tax' | 'payout' | 'adjustment'
  reporting_category text,                  -- Stripe's reporting_category
  gross_amount    numeric NOT NULL,
  fee_amount      numeric NOT NULL DEFAULT 0,
  tax_amount      numeric NOT NULL DEFAULT 0,
  net_amount      numeric NOT NULL,
  currency        text NOT NULL,
  presentment_currency text,
  customer_id     text,
  user_id         uuid,
  invoice_id      text,
  occurred_at     timestamptz NOT NULL,    -- provider's timestamp
  recorded_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT settlement_ledger_unique UNIQUE (provider, provider_object_id, type)
);
```

The ledger is the source of truth for accounting; MRR/churn/health/etc. are derivable views.

### 2. Checkout payload integrity is a first-class invariant

On every entitlement-changing event, validate:
- Provider (matches the route's expected provider).
- Mode (`subscription` for subscription routes; `payment` for one-time).
- `livemode` / environment (production routes only accept live events).
- Price or plan ID (in BUSINESS allowlist).
- Amount (matches expected).
- Currency (in BUSINESS allowed currencies).
- Customer / subscription ownership (cross-checked per hijack defense).
- Expected product (matches plan ID's expected product).

This is the concrete implementation target behind `bd-lp3vu.13`.

```ts
function validateCheckoutPayload(event: Stripe.Event): CheckoutValidationResult {
  const session = event.data.object as Stripe.Checkout.Session;

  // Provider check
  if (event.type !== 'checkout.session.completed') return invalid('wrong_event_type');

  // Mode check
  if (session.mode !== 'subscription') return invalid('mode_not_subscription');

  // livemode check (production-only routes)
  if (env.NODE_ENV === 'production' && !session.livemode) return invalid('not_live');

  // Price ID check
  const expectedPriceIds = Object.values(BUSINESS.STRIPE_PRICES);
  const actualPriceIds = session.line_items?.data.map(li => li.price?.id) ?? [];
  if (!actualPriceIds.every(id => expectedPriceIds.includes(id))) return invalid('unknown_price_id');

  // Amount check (allow ±1 cent for FX)
  // ... etc

  return { valid: true };
}
```

### 3. Test clocks and sandbox replay are regression gates, not demos

Stripe Test Clocks should cover renewal, failure, retry, cancellation, pause, subscription upgrade timelines.

PayPal sandbox coverage should replay duplicate, delayed, missing-payer, cancelled, suspended, refunded events through the real signature-verification route.

Wire as regular tests; run in CI; failures block deploy.

### 4. Billing deploys roll out like infrastructure changes

Any change under checkout / webhook / subscription projection / dunning / provider reconciliation should have:
- Staged rollout (canary → 10% → 50% → 100%).
- Live smoke test after each stage.
- Rollback metric (auto-rollback if smoke test or error rate spikes).

The open `bd-lp3vu.4.2` rolling-release bead is the right shape: path-based deploy routing, hold windows, automatic rollback on verify/webhook health regressions.

### 5. Tax and merchant-of-record boundaries stay explicit

Stripe Tax, PayPal tax fields, or a merchant-of-record platform (Paddle, Lemon Squeezy) can calculate tax. But entitlement code MUST NOT infer "paid" from tax-inclusive totals.

Store:
- Tax jurisdiction evidence (where the customer was billed).
- Invoice tax line.
- Access state (entitlement period).

Three separate facts.

### 6. Secret custody and RLS proof are launch gates

A billing backend with perfect webhook idempotency can still fail open if:
- `sk_live_...` is in a preview environment.
- `SUPABASE_SERVICE_ROLE_KEY` ships to a CLI.
- `.env` was committed once (even later reverted — git history retains).
- `payment_events.payload` is readable through a broad RLS policy.

Treat secret inventory + RLS matrix as PART OF THE BILLING SKILL, not generic DevOps hygiene.

### 7. Product policy is a matrix, not prose

If a SaaS supports trials / coupons / annual contracts / localized prices / Payment Links / negotiated deals: encode those choices as:
- Provider allowlists.
- Local ledger fields.
- Dashboard audits.
- Analytics dimensions.
- Abuse controls.

The "no trials / no discounts / no deals" policy is a valid simplicity strategy. The reusable pattern is **explicit policy + provider proof**, not the absence of those features.

See `BUSINESS-MODEL-PORTABILITY.md` for the per-policy implementation.

---

## Verify-endpoint alerts cron (per-tag thresholds)

The `verify_endpoint_events` table from B10 is the data source. The alerts cron runs every 5 minutes, scans windows defined per tag, and pages admins when thresholds breach. Critical: cooldown via `compliance_events` so a sustained outage doesn't spam alerts.

```ts
// src/app/api/cron/verify-endpoint-alerts/route.ts
type AlertThreshold = {
  windowMinutes: number;     // sliding window
  countAbove: number;        // observed > countAbove → alert
  severity: "info" | "warn" | "error" | "critical";
  description: string;
};

// Partial record so excerpts here can show 5 representative tags;
// production should populate every VERIFY_EVENT_TAGS member or assert
// completeness in a unit test.
const ALERT_THRESHOLDS: Partial<Record<VerifyEventTag, AlertThreshold>> = {
  [VERIFY_EVENT_TAGS.STRIPE_API_FAILED]: {
    windowMinutes: 5,
    countAbove: 0,                 // any failure pages
    severity: "error",
    description: "Stripe SDK threw on checkout-session retrieve.",
  },
  [VERIFY_EVENT_TAGS.PAYLOAD_INTEGRITY_VIOLATION]: {
    windowMinutes: 5,
    countAbove: 0,
    severity: "error",
    description: "validatePaymentEventIntegrity rejected a session.",
  },
  [VERIFY_EVENT_TAGS.UNEXPECTED_DISCOUNT]: {
    windowMinutes: 5,
    countAbove: 0,
    severity: "error",
    description: "Discount on a session — policy violation.",
  },
  [VERIFY_EVENT_TAGS.WRITE_PATH_DB_ERROR]: {
    windowMinutes: 15,
    countAbove: 2,
    severity: "critical",
    description: "Verify endpoint hit a DB error on the write path.",
  },
  [VERIFY_EVENT_TAGS.POLL_EXHAUSTED]: {
    windowMinutes: 60,
    countAbove: 5,
    severity: "warn",
    description: "Verify endpoint exhausted its retry poll budget — webhooks may be silent.",
  },
  // ... (one entry per VERIFY_EVENT_TAGS member)
};

// Cron handler:
const COOLDOWN_MINUTES = 60;

for (const [tag, threshold] of Object.entries(ALERT_THRESHOLDS)) {
  if (!threshold) continue;                          // satisfies the Partial<>
  const windowStart = new Date(Date.now() - threshold.windowMinutes * 60 * 1000);

  const [aggregate] = await db
    .select({ total: sql<number>`coalesce(sum(${verifyEndpointEvents.count}), 0)` })
    .from(verifyEndpointEvents)
    .where(and(
      eq(verifyEndpointEvents.tag, tag),
      gte(verifyEndpointEvents.hourBucket, windowStart),
    ));

  if (aggregate.total > threshold.countAbove) {
    const dedupeKey = `verify-alert:${tag}`;
    const recentAlert = await db.query.complianceEvents.findFirst({
      where: and(
        eq(complianceEvents.eventType, "system_alert_dedupe"),
        eq(complianceEvents.actorId, dedupeKey),
        gte(complianceEvents.createdAt, new Date(Date.now() - COOLDOWN_MINUTES * 60 * 1000)),
      ),
    });
    if (recentAlert) continue;       // still in cooldown

    await dispatchAlert({
      severity: threshold.severity,
      subject: `[verify-alert] ${tag} (${aggregate.total} in ${threshold.windowMinutes}m)`,
      body: threshold.description,
    });
    await db.insert(complianceEvents).values({
      eventType: "system_alert_dedupe",
      actorType: "system",
      actorId: dedupeKey,
      metadata: { tag, observed: aggregate.total, threshold: threshold.countAbove },
    });
  }
}
```

**Why cooldown is critical:** during a Stripe US-EAST outage, `STRIPE_API_FAILED` will fire continuously. Without cooldown, your inbox gets 12 pages per hour for 4 hours — and you stop reading them. The cooldown row in `compliance_events` lets you re-alert every 60 minutes (long enough that a sustained outage stays present in your awareness without spamming).

**Reference:** jeffreys-skills.md `src/app/api/cron/verify-endpoint-alerts/route.ts:63-144`.

---

## SLO snapshots cron (formal P0–P5 targets)

The same `verify_endpoint_events` data feeds an hourly SLO snapshot that gets written to `slo_snapshots` for trending. The targets are pinned in an ADR (B110 §"ADR system"); the cron computes against them and stores `withinTarget: true|false`.

```ts
// src/lib/billing/slo-compute.ts
export type SloValue = {
  sloId: string;            // 'P0', 'P1_p50', 'P1_p95', etc.
  value: number;
  target: number;
  withinTarget: boolean;
  measuredAt: Date;
};

export async function computeAllSlos(windowStart: Date, windowEnd: Date): Promise<SloValue[]> {
  return [
    ...await computeP0FalseFailures(windowStart, windowEnd),
    ...await computeP1ActivationLatency(windowStart, windowEnd),
    ...await computeP2PollExhaustion(windowStart, windowEnd),
    ...await computeP3WebhookSilenceDetection(windowStart, windowEnd),
    ...await computeP4ReconciliationFalseNegatives(windowStart, windowEnd),
    ...await computeP5TestSuitePassRate(windowStart, windowEnd),
  ];
}

async function computeP1ActivationLatency(windowStart: Date, windowEnd: Date): Promise<SloValue[]> {
  // Pass Date objects directly — Drizzle binds them as $1, $2 with the
  // correct type. Avoid `${date.toISOString()}::timestamptz` because the
  // ISO string would be inlined as a quoted parameter, not a literal cast.
  //
  // The latency-per-sub uses the LATEST payment_event for that user that
  // landed within an hour BEFORE the sub became active — this is the
  // triggering event for activation. Without the bounded LATERAL, a user
  // with N historic events would contribute N rows to the percentile
  // input and skew the result.
  const result = await db.execute(sql`
    SELECT
      coalesce(percentile_cont(0.50) WITHIN GROUP (ORDER BY latency_seconds), 0) AS p50_seconds,
      coalesce(percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_seconds), 0) AS p95_seconds,
      coalesce(percentile_cont(0.99) WITHIN GROUP (ORDER BY latency_seconds), 0) AS p99_seconds
    FROM (
      SELECT EXTRACT(EPOCH FROM (s.created_at - pe.created_at)) AS latency_seconds
      FROM subscriptions s
      JOIN LATERAL (
        SELECT pe2.created_at
        FROM payment_events pe2
        WHERE pe2.user_id = s.user_id
          AND pe2.created_at <= s.created_at
          AND pe2.created_at >= s.created_at - INTERVAL '1 hour'
        ORDER BY pe2.created_at DESC
        LIMIT 1
      ) pe ON true
      WHERE s.status IN ('active', 'past_due')
        AND s.created_at >= ${windowStart}
        AND s.created_at <  ${windowEnd}
    ) latencies
  `);
  const row = result.rows[0] as { p50_seconds: number; p95_seconds: number; p99_seconds: number };

  const p50 = Number(row.p50_seconds), p95 = Number(row.p95_seconds), p99 = Number(row.p99_seconds);
  const measuredAt = new Date();
  return [
    { sloId: "P1_p50", value: p50, target: 2,   withinTarget: p50 <= 2,   measuredAt },
    { sloId: "P1_p95", value: p95, target: 30,  withinTarget: p95 <= 30,  measuredAt },
    { sloId: "P1_p99", value: p99, target: 300, withinTarget: p99 <= 300, measuredAt },
  ];
}
```

**The full target table** (mirrors ADR-0010 from the source codebase):

| ID | Statement | Target | Source signal |
|----|-----------|--------|---------------|
| **P0** | A paid customer never sees a "subscription required" failure banner while active | 0/week | `verify.*_violation` + `verify.failed` for users whose `subscription_status` is `active` at moment of event |
| **P1** | Charge → DB activation latency | p50 ≤ 2s, p95 ≤ 30s, p99 ≤ 300s (5min) | `subscriptions.created_at − payment_events.event_at` for new subs |
| **P2** | Verify-endpoint poll exhaustion rate | < 1 per 1000 checkouts | `verify.poll_exhausted` ÷ activation count |
| **P3** | Webhook silence detected within 30 min during business hours | 100% | `webhook-delivery-health` cron + monthly chaos test |
| **P4** | Reconciliation false-negative rate (events with `processed_at IS NOT NULL` but `subscriptions` row diverges from provider) | 0 over rolling 90 days | provider-reconciliation cron output vs `payment_events` |
| **P5** | E2E billing test suite pass rate (no flake) | > 99% | GitHub Actions API |

**Why pinning these in code (not just docs) matters:** the SLO compute function returns `withinTarget` for every measurement. The next layer (an alert rule) can flip from "fire if value > threshold" to "fire if `withinTarget === false`" — same semantics, but driven by ADR-pinned values that don't drift away from the doc.

`slo_snapshots` table:

```sql
CREATE TABLE slo_snapshots (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slo_id       text NOT NULL,
  value        numeric NOT NULL,
  target       numeric NOT NULL,
  within_target boolean NOT NULL,
  window_start timestamptz NOT NULL,
  window_end   timestamptz NOT NULL,
  measured_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX slo_snapshots_id_recent_idx ON slo_snapshots (slo_id, measured_at DESC);
```

The dashboard at `/admin/health/slo` reads the most recent snapshot per `slo_id` for the live view, plus the last 30 days for trending sparklines.

**Reference:** jeffreys-skills.md `src/lib/billing/slo-compute.ts:16-270`, `src/app/api/cron/slo-snapshot/route.ts`, `docs/adr/billing/0010-slo-targets.md`.

---

## Webhook delivery-health heartbeat (gap-since-last-event)

`webhook-staleness` (B90) detects unprocessed `payment_events` rows. `webhook-delivery-health` is a different signal: the gap *since the last signature-verified event arrived*. A long gap means webhooks aren't even reaching us, which `webhook-staleness` cannot detect (an empty queue looks fine to it).

The threshold logic is conditional on time-of-day AND on whether a paid checkout is in flight:

```ts
// src/app/api/cron/webhook-delivery-health/route.ts
const BUSINESS_HOURS_THRESHOLD_MINUTES = 30;
const QUIET_HOURS_THRESHOLD_MINUTES    = 4 * 60;       // 4 hours overnight
const QUIET_HOURS_START_UTC = 1;
const QUIET_HOURS_END_UTC   = 6;
const PAID_CHECKOUT_THRESHOLD_MINUTES = 10;            // tighter when revenue is on the line

type ThresholdInputs = {
  hourUtc: number;
  gapMinutes: number;
  recentPaidCheckouts: number;
};

type ThresholdDecision =
  | { kind: "ok" }
  | { kind: "alert"; reason: "paid_checkout_silent" | "business_hours_gap" | "quiet_hours_gap" };

export function decideThreshold(inputs: ThresholdInputs): ThresholdDecision {
  const inQuietHours = inputs.hourUtc >= QUIET_HOURS_START_UTC && inputs.hourUtc < QUIET_HOURS_END_UTC;

  // Highest priority: a paid checkout in flight with NO recent events is
  // suspicious regardless of time-of-day. Revenue at risk overrides quiet hours.
  if (inputs.recentPaidCheckouts > 0 && inputs.gapMinutes >= PAID_CHECKOUT_THRESHOLD_MINUTES) {
    return { kind: "alert", reason: "paid_checkout_silent" };
  }

  // Mutually exclusive: quiet vs business. Picking the threshold up-front
  // prevents the business-hours branch from firing inside quiet hours
  // (a 35-min gap at 3am should NOT page; quiet hours bound is 4h).
  const threshold = inQuietHours ? QUIET_HOURS_THRESHOLD_MINUTES : BUSINESS_HOURS_THRESHOLD_MINUTES;
  if (inputs.gapMinutes >= threshold) {
    return {
      kind: "alert",
      reason: inQuietHours ? "quiet_hours_gap" : "business_hours_gap",
    };
  }

  return { kind: "ok" };
}
```

**Per-provider tracking:** the cron computes the gap per (provider, livemode) pair. Test-mode events are ignored for production alerting; livemode-only events are what drive the 30-minute threshold. `livemode` is read out of the JSONB payload (Stripe stamps every event with it; PayPal's equivalent is the absence of `_sandbox_` in the webhook id).

**Inputs feeding the threshold:**

```ts
// livemode lives in the stored event payload — no dedicated column needed.
const lastStripeEvent = await db.query.paymentEvents.findFirst({
  where: and(
    eq(paymentEvents.provider, "stripe"),
    sql`payload->>'livemode' = 'true'`,
  ),
  orderBy: desc(paymentEvents.createdAt),
});
const [{ c: recentPaidCheckouts }] = await db
  .select({ c: count() })
  .from(users)
  .where(and(
    isNotNull(users.pendingCheckoutSessionId),
    gte(users.pendingCheckoutExpiresAt, new Date()),
  ));
```

The 10-minute "paid checkout silent" threshold catches the worst case: a customer just paid, the verify-endpoint fallback also failed (so the user sees a frozen "verifying..." screen), AND no webhook arrived. Without this, you find out via support ticket the next morning.

**Reference:** jeffreys-skills.md `src/app/api/cron/webhook-delivery-health/route.ts:55-174`.

---

## Vercel Skew Protection (deploy-time defense)

When a billing-touching deploy goes out, the in-flight requests from the OLD bundle may end up POSTing to the NEW bundle's API routes — and a payload-shape mismatch can corrupt state. The Vercel platform-level fix is Skew Protection: incoming requests carry a `x-deployment-id` header and Vercel routes them back to the deploy that produced their bundle.

```ts
// next.config.ts
export default {
  experimental: { skewProtection: true },         // Vercel routes by deployment id
} satisfies NextConfig;

// In API routes that participate:
import { headers } from "next/headers";
const h = await headers();
const deploymentId = h.get("x-deployment-id");
logger.info({ deploymentId, path: "/api/stripe/create-checkout" }, "request from deployment");
```

The smoke test at deploy time:

```ts
// scripts/smoke-test-skew.ts
const deploymentUrl = process.env.VERCEL_DEPLOYMENT_URL;
const res = await fetch(`${deploymentUrl}/api/stripe/create-checkout/health`);
const headers = res.headers;
if (!headers.get("x-vercel-id")) throw new Error("No x-vercel-id header — Skew Protection misconfigured");
```

**What this defends against in billing specifically:** a 2-minute deploy window for a `customer_id` column rename. Old bundle reads `customerId`, new bundle reads `customer_id_v2`. Without Skew Protection, a webhook that started on old and finished on new gets `undefined` for the customer, falls through to the email-fallback path, and (without the email-fallback hijack defense) writes to the wrong row.

**Reference:** jeffreys-skills.md uses `experimental.skewProtection` and has a smoke test gating CI promotion.

---

## Polish Bar checks for B55

- [ ] Webhook metrics emitted (received, signature_fail, duplicate, processing_duration, processing_error, replay_blocked).
- [ ] Prometheus / equivalent alert rules wired for each metric.
- [ ] CSP headers set on all checkout pages with Stripe directives.
- [ ] PayPal CSP additions if PayPal SDK rendered (NOT pure redirect).
- [ ] CSP drift-guard test asserts response header on /checkout.
- [ ] Credential rotation cadence documented + drift-guard test for past-cadence rotation.
- [ ] Webhook event-age observability log (NOT a hard reject).
- [ ] Cross-provider webhook confusion: per-provider header validation; no generic /api/webhooks/.
- [ ] Chargeback handling: `disputed_at` + `chargeback_count` + `billing_banned_at` + access-gate.
- [ ] Side-effect idempotency: `side_effect_log` table + `emitSideEffectOnce` helper for non-idempotent side effects.
- [ ] Settlement ledger (immutable) for accounting facts.
- [ ] Checkout payload integrity validation function.
- [ ] **`verify-endpoint-alerts` cron** runs every 5min, has per-tag thresholds, uses `compliance_events` cooldown (60min default).
- [ ] **`slo-snapshot` cron** runs hourly, computes P0–P5 with `withinTarget` boolean, writes to `slo_snapshots` table.
- [ ] **SLO targets pinned in an ADR** (B110) and the cron's targets reference that ADR by number.
- [ ] **`webhook-delivery-health` cron** tracks per-provider gap-since-last-event (separate from `webhook-staleness`).
- [ ] Webhook delivery-health threshold is conditional: 30min business hours / 4h quiet hours / 10min when paid checkout in flight.
- [ ] **Vercel Skew Protection** enabled (`experimental.skewProtection`) + smoke test asserts `x-vercel-id` header at deploy time.
- [ ] `/admin/health/checkout-verification` page reads from `verify_endpoint_events`.
- [ ] `/admin/health/slo` page reads from `slo_snapshots`.
- [ ] Stripe Test Clocks tests in CI for renewal / failure / retry / cancellation / pause / upgrade.
- [ ] PayPal sandbox replay tests in CI.
- [ ] Staged rollout for billing-touching deploys.
- [ ] Tax jurisdiction stored separately from entitlement state.

---

## Common B55 mistakes

- **Metrics emitted but no alerts wired.** Dashboards become wallpaper; no one notices the spike.
- **CSP set on the marketing site but not on /checkout.** Stripe Elements renders blank.
- **Hard-rejecting old `event.created` events.** Drops legitimate provider retries; introduces silent failures.
- **Generic `/api/webhooks/payments` endpoint.** Cross-provider confusion class.
- **Chargeback handler doesn't gate access.** Disputed user keeps using premium; we lose the dispute AND lose the future months of entitlement to the deadbeat.
- **Side-effect idempotency table grows unbounded.** Add a TTL cleanup cron.
- **Settlement ledger derived from local invoices instead of provider settlements.** Misses adjustments / disputes that the provider knows about but our invoices don't.
- **Checkout payload integrity check trusts metadata without re-validating amount.** Attacker can craft a session with low amount and metadata pointing at high-value tier.
- **Test Clocks tests only run locally; not in CI.** Regression risk.
- **Staged rollout without auto-rollback.** Deployment glitch ships to all customers; manual rollback is too slow.
