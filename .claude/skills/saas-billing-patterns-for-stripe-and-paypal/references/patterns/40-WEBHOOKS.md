# Bundle B40 — Webhooks

> **Where this comes from.** § 5, § 10, § 12, § 16, § 27 of the source guide.

The 5-step webhook ingestion contract is the single most-reused pattern in the entire system. Every webhook handler — Stripe and PayPal — follows this skeleton. Diverging from it is how bugs get in.

---

## The 5-step ingestion contract (Stripe shown; PayPal is symmetric)

```ts
// src/app/api/stripe/webhook/route.ts
export async function POST(request: Request) {
  // Step 1: verify signature (4xx on failure — protocol error)
  const body = await request.text();
  const signature = request.headers.get('stripe-signature');
  if (!signature) {
    await trackAbuseSignal({ signal: 'webhook_signature_failed', source: 'system', request });
    return NextResponse.json(
      { error: 'missing_signature', code: WebhookErrorCodes.STRIPE.SIGNATURE_MISSING },
      { status: 400 }
    );
  }
  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(body, signature, env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    await trackAbuseSignal({ signal: 'webhook_signature_failed', source: 'system', request });
    return NextResponse.json(
      { error: 'invalid_signature', code: WebhookErrorCodes.STRIPE.SIGNATURE_INVALID },
      { status: 401 }
    );
  }

  // (Step 1.5: optional account/context check for Stripe Connect / org event endpoints)
  if (env.STRIPE_ACCOUNT_ID && event.account && event.account !== env.STRIPE_ACCOUNT_ID) {
    await trackAbuseSignal({
      signal: 'webhook_event_rejected',
      source: 'system',
      request,
      route: '/api/stripe/webhook',
      metadata: { provider: 'stripe', reason: 'wrong_account', received_account: event.account },
    });
    logSecurityEvent({
      type: 'webhook_event_rejected',
      severity: 'critical',
      target: { type: 'stripe_event', id: event.id, secondaryId: event.account },
      details: { reason: 'account_mismatch' },
    });
    // Return 200 — signature was valid; this is policy rejection, not protocol error.
    return NextResponse.json({ received: true, outcome: 'rejected_wrong_account' });
  }

  // Step 2: idempotency via payment_events row INSERT
  const isNewEvent = await recordWebhookEvent({
    provider: 'stripe',
    eventId: event.id,
    eventType: event.type,
    payload: event,
  });
  if (!isNewEvent) {
    return NextResponse.json({ received: true, outcome: 'skipped_idempotent' });
  }

  // Step 3 + 4: process — wrapped to never throw out
  try {
    await handleStripeEvent(event);
    await markEventProcessed('stripe', event.id);
    return NextResponse.json({ received: true, outcome: 'processed' });
  } catch (err) {
    // Step 5: ALWAYS return 200 even on processing error.
    //   - 500 = Stripe retries for 3 days = duplicate-charge risk
    //   - Event row is recorded but processed_at stays NULL
    //   - Reconciliation cron picks it up
    logger.error({ err, eventId: event.id }, 'Webhook processing failed; reconciliation will retry');
    return NextResponse.json({ received: true, outcome: 'error_acknowledged' });
  }
}
```

PayPal is identical except step 1 verifies via PayPal's `/v1/notifications/verify-webhook-signature` API call (no local crypto), and the `paypal-transmission-id` header is the equivalent of `stripe-signature`.

---

## `recordWebhookEvent` — the only correct dedup

```ts
// src/lib/webhooks/inbound.ts
export async function recordWebhookEvent(event: WebhookEvent): Promise<boolean> {
  try {
    await db.insert(paymentEvents).values({
      provider: event.provider,
      eventId: event.eventId,
      eventType: event.eventType,
      payload: event.payload as object,
    });
    return true;  // freshly inserted
  } catch (error) {
    const isUniqueViolation =
      (error as any)?.code === '23505' ||
      (error as any)?.nativeError?.code === '23505' ||
      (error as Error).message.includes('duplicate key value violates unique constraint');

    if (isUniqueViolation) {
      // Already recorded; let caller bail to skipped_idempotent.
      // (We don't care if the prior row is processed yet — reconciliation handles it.)
      return false;
    }
    throw error;  // anything else is a real bug
  }
}
```

**Why both `code === '23505'` AND a message check:** drivers differ in error shape (`pg` vs Supabase serverless vs node-postgres direct). Belt-and-suspenders.

---

## `markEventProcessed` — the second write

```ts
export async function markEventProcessed(
  provider: SubscriptionProvider,
  eventId: string,
): Promise<void> {
  await db.update(paymentEvents)
    .set({ processedAt: new Date() })
    .where(and(
      eq(paymentEvents.provider, provider),
      eq(paymentEvents.eventId, eventId),
    ));
}
```

The strict ordering — *insert first, run handler, then mark processed* — is what makes the reconciliation cron correct: any handler that throws leaves `processed_at NULL`, guaranteeing the row will be retried.

---

## `updateSubscriptionStatus` — the canonical writer

Every subscription-state mutation flows through this single function. The contract:

```ts
// src/lib/webhooks/inbound.ts
export async function updateSubscriptionStatus(params: {
  provider: SubscriptionProvider;
  externalSubscriptionId: string;
  customerId: string;
  userId?: string;                 // preferred — direct caller
  email?: string;                  // fallback — for first-time PayPal links (gated)
  status: SubscriptionStatus;
  currentPeriodStart?: Date;
  currentPeriodEnd?: Date;
  cancelledAt?: Date;
  eventId?: string;                // payment_events.event_id for userId enrichment
  eventAt?: Date;                  // PROVIDER's authoritative timestamp
}): Promise<UpdateSubscriptionResult>;

export interface UpdateSubscriptionResult {
  userId: string;
  previousStatus: SubscriptionStatus | null;   // for transition decisions
  currentStatus: SubscriptionStatus;
  isNew: boolean;                              // first row created?
}
```

### What it actually does, in order

1. **Resolve user** — `userId` if provided; else look up by `customerId`; else look up by `email` (PayPal-only first-time-link, gated). On unresolved → throw with `WebhookErrorCodes.STRIPE.USER_NOT_RESOLVABLE`.
2. **Stale-event guard** — if `subscriptions.last_event_at` exists and is newer than the incoming `eventAt`, drop the update. This is the single most important defense against late-replayed webhooks reviving cancelled state.
3. **Inside a single transaction:**
   - Snapshot the previous row (or detect `isNew`).
   - Insert or update the `subscriptions` row with new status + period dates.
   - Recompute `users.subscription_status` and `users.subscription_provider` by calling `deriveAggregateBillingProjection()` over ALL of the user's remaining subscription rows + org memberships.
   - **For cancellations**, only touch `users.customer_id` if the cancelled sub's customer matches AND there's no other live sub. (Tom Hunter defense — `bd-1m86f` Layer 4.)
4. **Enrich `payment_events.user_id`** if `eventId` was provided and the event row didn't have a user attached at recording time. Enables per-user payment analytics.
5. **Invalidate caches synchronously** with a 2s timeout (`Promise.race`). See B100 — SA-02 made this synchronous.
6. **Return** the `UpdateSubscriptionResult` so callers can decide whether to publish admin events (using `previousStatus` to gate "was this a real cancellation").

### The `LIVE_SUBSCRIPTION_STATUSES` Tom-Hunter defense

```ts
const LIVE_SUBSCRIPTION_STATUSES: ReadonlySet<SubscriptionStatus> =
  new Set<SubscriptionStatus>(['active', 'past_due']);

export function allSubscriptionsAfterUpdateHasBillable(
  subs: Array<{ status: SubscriptionStatus; externalId: string }>,
  justUpdatedExternalId: string,
): boolean {
  return subs.some(
    (s) => s.externalId !== justUpdatedExternalId && LIVE_SUBSCRIPTION_STATUSES.has(s.status),
  );
}
```

When a cancellation webhook arrives, this check decides whether to update `users.customer_id`. If the user has ANY OTHER live sub, leave `customer_id` alone — pointing it at the cancelled sub's customer would break Stripe portal deep-links and could cause future webhook race conditions (Tom Hunter Layer 4).

### The email-fallback hijack defense

Pre-fix (`bd-2zb9z`): `updateSubscriptionStatus` would look up the user by email if `customerId` wasn't found. An attacker who knows a victim's email could craft a PayPal subscription with that email as the subscriber and hijack the row. Fix: email fallback is now gated on `customerId` being non-null on the user (i.e., we already know this user is a PayPal customer of ours). First-time PayPal linking is OK because the user has no existing PayPal customer relationship to override.

---

## Replay-staleness gating with `last_event_at` (the core ⏱ STALE-EVENT-GATE pattern)

Every UPDATE on `subscriptions` includes:

```ts
await tx.update(subscriptions)
  .set({ status: newStatus, lastEventAt: eventAt, updatedAt: new Date(), ... })
  .where(and(
    eq(subscriptions.userId, userId),
    eq(subscriptions.provider, provider),
    eq(subscriptions.externalId, externalSubscriptionId),
    or(
      isNull(subscriptions.lastEventAt),
      lt(subscriptions.lastEventAt, eventAt),     // ← the gate
    ),
  ));
```

If the WHERE clause matches 0 rows, the UPDATE is a silent no-op AND the function returns `{ rowsAffected: 0 }` so the caller can log + emit `payment_event_replay_blocked`.

For PayPal, the equivalent column is `paypal_last_event_at` on `organizations` (team subs) and `last_event_at` on `subscriptions` (individual subs).

### `<=` vs `<` — first-write-wins is load-bearing

The pre-flight READ that decides "is this event stale?" must use `<=` (less-than-or-equal), not `<`:

```ts
// In the canonical writer's stale-event guard (READ form)
if (
  sequencingEventAt &&
  existingSubscription.lastEventAt &&
  sequencingEventAt <= existingSubscription.lastEventAt   // ← <= not <
) {
  logger.debug({
    subscriptionId: externalSubscriptionId,
    eventAt: sequencingEventAt.toISOString(),
    lastEventAt: existingSubscription.lastEventAt.toISOString(),
    staleStatus: status,
  }, "Skipping stale webhook event — already processed a newer-or-equal event");
  return { currentStatus: existingSubscription.status, isNew: false, /* ... */ };
}
```

**Why the equality matters:** Stripe's `event.created` is integer seconds (no millisecond resolution). Two distinct events emitted in the same second are common during invoice → payment_intent → subscription cascades. The READ guard and the WRITE WHERE clause encode the *same predicate from opposite sides*:

- READ: skip when `incoming <= persisted` → equivalently, apply only when `incoming > persisted`.
- WRITE: apply only when `persisted < incoming` (`lt(lastEventAt, eventAt)`) → identical predicate.

Both implement **first-write-wins** on same-second ties: the first event to commit sets `last_event_at = T`, and any subsequent event whose `event_at` is also `T` fails the strict-less-than check on the WRITE WHERE and silently no-ops.

So why have BOTH the READ and the WRITE check? Three reasons:

1. **The READ is an early-exit optimization** — a stale event short-circuits before the transaction even opens, saving a connection and a wasted UPDATE round-trip.
2. **The READ feeds the structured log** — the no-op write would silently succeed; the explicit READ-side check produces the `"Skipping stale webhook event"` log line that powers the `payment_event_replay_blocked` security signal.
3. **The WRITE is the durable enforcement** — even if a future refactor accidentally drops the READ guard, the WHERE clause keeps correctness.

PayPal events have millisecond timestamps (`event_time` is ISO-8601 with `Z`), so same-instant ties are rarer there — but the same `<=` rule applies because clock skew between PayPal nodes and your DB has surfaced same-millisecond ties at scale.

### Why on the row, not in `payment_events`

The `payment_events` table records what arrived; the `subscriptions` row records the authoritative state. Joining these on every read is too slow for hot paths. The `last_event_at` column is the cached "highest event time we've applied," and it's local to the row whose state it gates.

---

## Verify-as-write (paired with the live webhook)

```ts
// src/app/api/checkout/verify/route.ts
export async function POST(request: Request) {
  const userId = await requireUserId(request);
  const sessionId = request.nextUrl.searchParams.get('session_id');
  if (!sessionId) return NextResponse.json({ error: 'missing_session' }, { status: 400 });

  // 1. Try the DB first
  const sub = await db.query.subscriptions.findFirst({
    where: and(eq(subscriptions.userId, userId), eq(subscriptions.status, 'active')),
  });
  if (sub) return NextResponse.json({ ok: true, source: 'db' });

  // 2. DB shows none. Fetch the session from Stripe.
  const session = await stripe.checkout.sessions.retrieve(sessionId);
  if (session.payment_status !== 'paid' && session.status !== 'complete') {
    return NextResponse.json({ ok: false, status: session.status }, { status: 202 });
  }

  // 3. Reconcile via the same canonical writer
  const subResult = await reconcilePendingCheckoutForUser({
    provider: 'stripe',
    userId,
    sessionId,
    session,
  });

  return NextResponse.json({ ok: true, source: 'verify_write_path', ...subResult });
}
```

The `reconcilePendingCheckoutForUser` helper calls into `updateSubscriptionStatus` with the data extracted from the freshly-read Stripe session. The webhook becomes a backup; the user clicking "I just paid, please activate" produces the same state with no race against the webhook.

The current source-guide HEAD has feature flags (`verify_write_path`, `verify_write_path_shadow_mode`) — when off, Stripe falls back to legacy read-only paid-but-pending verification, and PayPal still has its older inline direct-write fallback.

---

## Bidirectional event coverage

Every webhook handler must subscribe to the events it wants AND only handle events it subscribed to.

```ts
// The handled set:
const HANDLED_STRIPE_EVENTS = new Set<Stripe.Event.Type>([
  'customer.subscription.created',
  'customer.subscription.updated',
  'customer.subscription.deleted',
  'customer.subscription.paused',
  'customer.subscription.resumed',
  'customer.subscription.trial_will_end',
  'invoice.paid',
  'invoice.payment_succeeded',
  'invoice.payment_failed',
  'invoice.payment_action_required',  // SCA / 3DS
  'invoice.upcoming',                  // pre-charge notification
  'invoice.finalized',
  'invoice.marked_uncollectible',
  'invoice.overdue',
  'invoice.voided',
  'charge.refunded',
  'charge.refund.updated',
  'refund.created',
  'refund.updated',
  'charge.dispute.created',
  'charge.dispute.updated',
  'charge.dispute.closed',
  'checkout.session.completed',
  'checkout.session.async_payment_succeeded',
  'checkout.session.async_payment_failed',
  'payment_method.attached',
  'payment_method.detached',
  'payment_method.updated',
  // (add more per your business needs)
]);

async function handleStripeEvent(event: Stripe.Event) {
  if (!HANDLED_STRIPE_EVENTS.has(event.type)) {
    // Recorded for analytics / debugging, but no behavior.
    logger.debug({ type: event.type, id: event.id }, 'Unhandled Stripe event type');
    return;
  }

  switch (event.type) {
    case 'customer.subscription.created':
    case 'customer.subscription.updated':
      return handleSubscriptionChanged(event);
    case 'customer.subscription.deleted':
      return handleSubscriptionDeleted(event);
    case 'invoice.paid':
    case 'invoice.payment_succeeded':
      return handleInvoicePaid(event);
    case 'invoice.payment_failed':
      return handleInvoicePaymentFailed(event);
    case 'invoice.payment_action_required':
      return handleSCA(event);
    case 'charge.refunded':
    case 'charge.refund.updated':
    case 'refund.created':
    case 'refund.updated':
      return handleRefund(event);
    case 'charge.dispute.created':
      return handleDispute(event);
    // ...
    default:
      // Listed in HANDLED but no case branch → bug.
      logger.error({ type: event.type }, 'HANDLED set claims event but no case branch');
  }
}
```

Coverage audit (B110): compare the live Stripe Dashboard's webhook endpoint enabled-events list to `HANDLED_STRIPE_EVENTS`. Drift in either direction is a bug.

---

## PayPal specifics

```ts
// Step 1 verification — PayPal requires an API call (no local crypto)
async function verifyPayPalWebhook(headers: Headers, body: string): Promise<boolean> {
  const verifyResponse = await fetch(
    `${env.PAYPAL_API_BASE}/v1/notifications/verify-webhook-signature`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${await getPayPalAccessToken()}`,
      },
      body: JSON.stringify({
        auth_algo: headers.get('paypal-auth-algo'),
        cert_url: headers.get('paypal-cert-url'),
        transmission_id: headers.get('paypal-transmission-id'),
        transmission_sig: headers.get('paypal-transmission-sig'),
        transmission_time: headers.get('paypal-transmission-time'),
        webhook_id: env.PAYPAL_WEBHOOK_ID,
        webhook_event: JSON.parse(body),
      }),
    },
  );
  if (!verifyResponse.ok) return false;
  const result = await verifyResponse.json();
  return result.verification_status === 'SUCCESS';
}
```

The PayPal verify endpoint is a network call — meaning step 1 itself can fail in ways Stripe can't. Cache the OAuth access token (it's valid for ~9 hours); if the verify call fails, return 503 (NOT 200) so PayPal retries.

PayPal events to handle:

```ts
const HANDLED_PAYPAL_EVENTS = new Set([
  'BILLING.SUBSCRIPTION.CREATED',
  'BILLING.SUBSCRIPTION.ACTIVATED',
  'BILLING.SUBSCRIPTION.UPDATED',
  'BILLING.SUBSCRIPTION.CANCELLED',
  'BILLING.SUBSCRIPTION.SUSPENDED',
  'BILLING.SUBSCRIPTION.EXPIRED',
  'BILLING.SUBSCRIPTION.PAYMENT.FAILED',
  'PAYMENT.SALE.COMPLETED',
  'PAYMENT.SALE.DENIED',
  'PAYMENT.SALE.REFUNDED',
  'PAYMENT.SALE.REVERSED',
  // (NOT 'BILLING.PLAN.UPDATED' — that's a plan-level config event, not entitlement)
]);
```

---

## `validatePaymentEventIntegrity` — never trust the event's contents

`updateSubscriptionStatus` trusts the **identity** in the event (signature-verified, account-checked); it does NOT trust the **contents** (line items, prices, discounts, livemode, customer match). Before activating a subscription from a `checkout.session.completed`, run a structured payload validator:

```ts
// src/lib/billing/payment-event-integrity.ts
type IntegrityViolation = {
  code:
    | "amount_mismatch"
    | "discount_applied"
    | "wrong_price_id"
    | "trial_period_present"
    | "test_mode_in_prod"
    | "client_reference_user_mismatch"
    | "subscription_not_active"
    | "expand_failed";
  severity: "critical" | "warn" | "info";
  details?: Record<string, unknown>;
};

export type IntegrityResult = {
  valid: boolean;             // false iff at least one critical violation
  violations: IntegrityViolation[];
  warnings: IntegrityViolation[];
  notes: IntegrityViolation[];
};

export function validatePaymentEventIntegrity(input: {
  provider: "stripe" | "paypal";
  session: Stripe.Checkout.Session & { subscription?: Stripe.Subscription | null };
  // For single-tier SaaS, `expectedPriceIds` is `[STRIPE_PRICE_ID]`. For
  // multi-product projects, pass the full allowlist of legitimate price IDs.
  context: { expectLiveMode: boolean; expectedPriceIds: ReadonlySet<string>; expectedUserId: string };
}): IntegrityResult {
  const all: IntegrityViolation[] = [];

  // Critical — refuse the write
  if (input.context.expectLiveMode && input.session.livemode === false) {
    all.push({ code: "test_mode_in_prod", severity: "critical" });
  }
  if (input.session.client_reference_id !== input.context.expectedUserId) {
    all.push({
      code: "client_reference_user_mismatch",
      severity: "critical",
      details: { expected: input.context.expectedUserId, got: input.session.client_reference_id },
    });
  }
  const lineItems = input.session.line_items?.data ?? [];
  for (const li of lineItems) {
    if (li.price?.id && !input.context.expectedPriceIds.has(li.price.id)) {
      all.push({
        code: "wrong_price_id",
        severity: "critical",
        details: { expected: [...input.context.expectedPriceIds], got: li.price.id },
      });
    }
  }
  if ((input.session.total_details?.amount_discount ?? 0) > 0) {
    all.push({ code: "discount_applied", severity: "critical" });
  }
  if (input.session.subscription?.trial_end != null) {
    // No-trial policy: the canonical writer must refuse a session that
    // somehow acquired a trial period (misconfigured plan, attacker-tampered).
    all.push({
      code: "trial_period_present",
      severity: "critical",
      details: { trial_end: input.session.subscription.trial_end },
    });
  }

  // Info — proceed but log; common for SCA-required sessions
  if (input.session.subscription && input.session.subscription.status !== "active") {
    all.push({
      code: "subscription_not_active",
      severity: "info",
      details: { actual_status: input.session.subscription.status },
    });
  }

  return {
    valid:      !all.some((v) => v.severity === "critical"),
    violations: all.filter((v) => v.severity === "critical"),
    warnings:   all.filter((v) => v.severity === "warn"),
    notes:      all.filter((v) => v.severity === "info"),
  };
}
```

Call site (Stripe `checkout.session.completed` handler):

```ts
const integrity = validatePaymentEventIntegrity({
  provider: "stripe",
  session: { ...session, subscription },
  context: {
    expectLiveMode: isProductionLikeEnv(),
    expectedPriceIds: new Set([env.STRIPE_PRICE_ID]),  // single-tier; expand for multi-product
    expectedUserId: userId,
  },
});

if (!integrity.valid) {
  logger.error({
    sessionId: session.id,
    userId,
    violations: integrity.violations,
  }, "Stripe checkout session failed payment integrity validation");
  // recordVerifyEvent + VERIFY_EVENT_TAGS are defined in B10 §"verify_endpoint_events".
  recordVerifyEvent({ tag: VERIFY_EVENT_TAGS.PAYLOAD_INTEGRITY_VIOLATION, provider: "stripe" });
  throw new Error("Stripe checkout session failed payment integrity validation");
}
if (integrity.notes.length > 0) {
  logger.info({ notes: integrity.notes }, "Payment integrity notes (non-blocking)");
}
```

The validator never throws and never reaches outside the function — this keeps it pure and trivially unit-testable. The caller decides whether `valid: false` aborts (production) or just logs (shadow mode).

**Why it exists:** webhook signature verification proves the event came from Stripe; it does NOT prove the event's *body* matches what your business expects. A misconfigured Stripe Dashboard (test-mode price ID copy-pasted into prod), a stale checkout session from before a price increase, an attacker who somehow got a session with a 100%-off promo coupon attached, a Connect/account leak — all pass signature verification and all are caught here.

**Reference:** jeffreys-skills.md `src/lib/billing/payment-event-integrity.ts:110-311, 505-512` and call site in Stripe webhook handler.

---

## Owner-mismatch detection — the `webhook_hijack_attempt` security event

When a webhook arrives for a subscription that already exists in our DB, the *persisted* owner of that row must match the *resolved* user from the event. Mismatch = hijack attempt, regardless of how the resolution happened (customer ID lookup, email fallback, metadata.userId).

```ts
// In updateSubscriptionStatus, after resolving the user:
if (existingSubscription) {
  if (
    typeof existingSubscription.userId === "string" &&
    existingSubscription.userId !== resolvedUser.id
  ) {
    logger.error({
      subscriptionId: externalSubscriptionId,
      linkedUserId: existingSubscription.userId,
      resolvedUserId: resolvedUser.id,
      suppliedUserId: userId,
    }, "SECURITY: Refusing subscription update for mismatched existing owner");

    logSecurityEvent({
      type: "webhook_hijack_attempt",
      severity: "critical",
      actor: { authSource: "webhook", userId: resolvedUser.id },
      target: { type: "subscription", id: externalSubscriptionId },
      details: {
        linkedUserId: existingSubscription.userId,
        resolvedUserId: resolvedUser.id,
        provider,
      },
    });

    throw new SubscriptionOwnerMismatchError({
      externalSubscriptionId,
      persistedUserId: existingSubscription.userId,
      resolvedUserId: resolvedUser.id,
    });
  }
}
```

`SubscriptionOwnerMismatchError` lives next to the other typed errors in B110 §"`PaymentError` taxonomy" — it carries the persisted vs resolved user IDs in its `details` so the handler's catch block can include them in the security log line.

This is paired with PayPal's `validatePayPalUserId` (B50): both are different lenses on the same threat. `validatePayPalUserId` catches the `custom_id` spoof at lookup time; the owner-mismatch check catches all other paths (email fallback hijack, customer-id reuse, manual admin edits gone wrong).

The `SubscriptionOwnerMismatchError` is caught at the handler level and returns 200 (per the 5-step contract); the security event in `complianceEvents` is the durable signal for the on-call admin alert.

**Reference:** jeffreys-skills.md `src/lib/webhooks/inbound.ts:774-815`.

---

## Refund chain resolution: charge → invoice → subscription

`charge.refunded` events carry a charge but not directly a subscription. Naive code resolves "what to revoke" by `customer_id`, then iterates all subs for that customer. This is wrong: a customer with two active subscriptions (e.g., a base plan and a usage-based add-on) loses BOTH on a single-line refund.

The fix: resolve the chain `charge.invoice → invoice.subscription` and revoke only that exact sub:

```ts
// In handleStripeRefund:
const chargeInvoice = (charge as Stripe.Charge & { invoice?: string | { id?: unknown } }).invoice;
let externalSubscriptionId: string | undefined;
const invoiceRef = typeof chargeInvoice === "string" ? chargeInvoice : chargeInvoice?.id;

if (invoiceRef) {
  try {
    const invoice = await stripe.invoices.retrieve(invoiceRef);
    const subRef = (invoice as Stripe.Invoice & { subscription?: unknown }).subscription;
    if (typeof subRef === "string") {
      externalSubscriptionId = subRef;
    } else if (subRef && typeof subRef === "object" && "id" in subRef) {
      const maybeId = (subRef as { id?: unknown }).id;
      if (typeof maybeId === "string") externalSubscriptionId = maybeId;
    }
  } catch (err) {
    // Invoice may have been purged or the API call may have failed. Fall back
    // to customer-scoped revoke, but log loudly — this is not the happy path.
    logger.warn({
      err,
      chargeId: charge.id,
      invoiceId: invoiceRef,
    }, "Refund handler: failed to resolve invoice → subscription; falling back to customer-scoped revoke");
  }
}
```

When `externalSubscriptionId` resolves, pass it to `revokeAccessOnRefund({ ..., externalSubscriptionId })`; the revoke function uses it as a `WHERE` clause to scope the access change to that one row.

**Reference:** jeffreys-skills.md `src/app/api/stripe/webhook/handler.ts:909-942`.

---

## Full-vs-partial refund distinction

Partial refunds are goodwill (the customer keeps access). Full refunds revoke. Decide deterministically:

```ts
const isFullRefund = charge.amount_refunded >= charge.amount && charge.amount > 0;

logger.info({
  chargeId: charge.id,
  amount: charge.amount,
  amountRefunded: charge.amount_refunded,
  isFullRefund,
}, isFullRefund
  ? "Charge fully refunded — revoking access on the specific subscription"
  : "Charge partially refunded — access retained");

let revocationResult: { revoked: boolean } = { revoked: false };
if (isFullRefund && customerId) {
  try {
    revocationResult = await revokeAccessOnRefund({
      provider: "stripe",
      customerId,
      externalSubscriptionId,    // from chain resolution above
      eventAt,
    });
  } catch (err) {
    logger.error({ err, chargeId: charge.id }, "Failed to revoke access on refund — MANUAL INTERVENTION REQUIRED");
    // Do NOT re-throw — webhook returns 200; admin alert via critical-alert path
  }
}
```

The `charge.amount > 0` guard handles a Stripe edge case where `amount_refunded === amount === 0` (a $0 trial charge that was nominally "refunded"); without it, every test-mode trial event triggers a revoke.

PayPal's equivalent is in `PAYMENT.SALE.REFUNDED`: compare `resource.amount.total` to the parent payment's gross. PayPal partial refunds (Billing-H2) require fetching the parent payment's full refund history because individual events arrive with one refund's amount, not the cumulative.

**Reference:** jeffreys-skills.md `src/app/api/stripe/webhook/handler.ts:909-976`.

---

## Stale checkout race detection + durable critical alert

`checkout.session.completed` can arrive after the user has already moved on (cleared their pending checkout, started a new provider, or the cron has already activated a sibling sub). Activating naively in this window creates duplicate billable subscriptions.

The detection:

```ts
// src/lib/services/stale-checkout.ts
type StaleCheckoutResult = {
  stale: boolean;
  reason?: "duplicate_active_sub" | "session_id_mismatch";
  pendingCheckoutSessionId?: string | null;
  existingSubscriptionId?: string | null;
};

const BILLABLE_DUPLICATE_CHECKOUT_STATUSES = new Set<SubscriptionStatus>(["active", "past_due"]);

export async function detectStaleCheckoutRace(input: {
  userId: string;
  provider: SubscriptionProvider;        // "stripe" | "paypal"
  incomingSessionId: string;
  incomingSubscriptionId: string;
}): Promise<StaleCheckoutResult> {
  const { userId, provider, incomingSessionId, incomingSubscriptionId } = input;

  const user = await db.query.users.findFirst({ where: eq(users.id, userId) });
  if (!user) return { stale: false };

  // Race A: user already has a billable sub in the SAME provider, different sub ID
  if (
    BILLABLE_DUPLICATE_CHECKOUT_STATUSES.has(user.subscriptionStatus) &&
    user.subscriptionProvider === provider
  ) {
    const existingBillable = await db.query.subscriptions.findFirst({
      where: and(
        eq(subscriptions.userId, userId),
        eq(subscriptions.provider, provider),
        inArray(subscriptions.status, ["active", "past_due"]),
        ne(subscriptions.externalId, incomingSubscriptionId),
      ),
    });
    if (existingBillable) {
      return {
        stale: true,
        reason: "duplicate_active_sub",
        existingSubscriptionId: existingBillable.externalId,
      };
    }
  }

  // Race B: user's current pending checkout points at a DIFFERENT session
  if (user.pendingCheckoutSessionId && user.pendingCheckoutSessionId !== incomingSessionId) {
    return {
      stale: true,
      reason: "session_id_mismatch",
      pendingCheckoutSessionId: user.pendingCheckoutSessionId,
    };
  }

  return { stale: false };
}
```

The handler call:

```ts
const race = await detectStaleCheckoutRace({
  userId,
  provider: "stripe",                            // "paypal" in the PayPal handler
  incomingSessionId: session.id,
  incomingSubscriptionId: subscriptionId,
});
if (race.stale) {
  logger.warn({ ...race, alertQueued: true }, "billing.checkout.stale_completion_detected");
  try {
    await queueStaleCheckoutAlert({
      reason: race.reason,
      userId,
      incomingSessionId: session.id,
      incomingSubscriptionId: subscriptionId,
      existingSubscriptionId: race.existingSubscriptionId,
      pendingSessionId: race.pendingCheckoutSessionId,
      email,
    });
  } catch (alertErr) {
    logger.error({ err: alertErr, userId }, "billing.checkout.stale_alert_queue_failed");
    // CRITICAL: re-throw so the outer handler leaves processed_at NULL.
    // Reconciliation will retry and the alert will eventually queue.
    throw alertErr;
  }
  return; // 200 to Stripe, no state mutation
}
```

The `queueStaleCheckoutAlert` writes to the durable `email_jobs` table with `priority: "critical"`. An ephemeral `sendEmail()` call is wrong here — if Resend is down (the original Billing-H1 incident), you'd lose the only signal that a duplicate was about to happen.

**Reference:** jeffreys-skills.md `src/app/api/stripe/webhook/handler.ts:401-443` and `src/lib/services/stale-checkout.ts:48-178`.

---

## HTML-escape admin notifications — the `esc()` helper

Customer email addresses, subscription IDs, dispute reason strings, refund metadata — all of these flow into admin email bodies as HTML. None of them are trustworthy inputs for HTML rendering. Use a single `esc()` helper for every embedded value:

```ts
function esc(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// Every admin email follows this shape:
await sendEmail({
  to: env.ADMIN_EMAIL,
  subject: `New subscriber: ${email ?? "unknown"}`,
  html: `
<p><strong>New Stripe subscription</strong></p>
<ul>
  <li>Email: ${esc(email ?? "unknown")}</li>
  <li>Customer: ${esc(customerId)}</li>
  <li>Subscription: ${esc(subscriptionId)}</li>
  <li>User ID: ${esc(userId ?? "unknown")}</li>
</ul>`,
});
```

Why subject lines are intentionally NOT escaped: Resend (and most ESPs) treat the subject as plain text, not HTML. Escaping the subject would render `&amp;` literally to admins.

The rule: if the value goes inside an `<element>...${value}...</element>`, escape it. If it goes in `subject`, plain-text only — and use a sanitizer to strip HTML if the value source isn't trustworthy.

A copy of `esc()` lives in both Stripe and PayPal webhook handlers; do NOT factor it into a shared module that imports SDK types — keep the helper local so each handler is fully self-contained.

**Reference:** jeffreys-skills.md `src/app/api/stripe/webhook/handler.ts:52-59` and `src/app/api/paypal/webhook/route.ts:54-60`.

---

## Polish Bar checks for B40

- [ ] Both Stripe and PayPal handlers follow the 5-step contract.
- [ ] Step 1 (signature verification) returns 4xx; everything else returns 200 once `recordWebhookEvent` succeeds.
- [ ] Step 1 invokes `trackAbuseSignal({ signal: 'webhook_signature_failed' })` on both missing and invalid signatures.
- [ ] Stripe Connect / org event endpoints have the account/context check (Step 1.5).
- [ ] `recordWebhookEvent` handles 23505 from both `code` and message-string forms.
- [ ] `markEventProcessed` is the second write; ordering is enforced.
- [ ] `updateSubscriptionStatus` is the only canonical writer; no per-handler ad-hoc UPDATEs.
- [ ] `last_event_at` WHERE clause on every state UPDATE.
- [ ] **READ-side stale-event guard uses `<=`** (not `<`) — first-write-wins on same-second ties.
- [ ] **`validatePaymentEventIntegrity`** runs before activation; critical violations refuse the write.
- [ ] **Owner-mismatch hijack guard** runs in `updateSubscriptionStatus` — refuses + logs `webhook_hijack_attempt`.
- [ ] Email-fallback hijack defense: gated on `customerId IS NOT NULL`.
- [ ] Tom-Hunter defense: `LIVE_SUBSCRIPTION_STATUSES` check before clobbering `users.customer_id`.
- [ ] **Refund chain resolution** (`charge.invoice → invoice.subscription`) — revoke targets the EXACT sub.
- [ ] **Full-vs-partial refund**: `amount_refunded >= amount && amount > 0` is the test for `isFullRefund`.
- [ ] **`detectStaleCheckoutRace`** runs on every `checkout.session.completed`; stale → durable `billing_critical_alert`.
- [ ] Stale-checkout alert queueing failure re-throws so `processed_at` stays NULL and reconciliation retries.
- [ ] **HTML-escape `esc()`** helper used on every customer-supplied value embedded in admin email HTML.
- [ ] Bidirectional event coverage: `HANDLED_*_EVENTS` set matches Dashboard config.
- [ ] PayPal access token cached; verify endpoint failure returns 503 (not 200).
- [ ] Per-event-type retry caps (no shared counter) — see § 29.8 of source.
- [ ] `payment_events.payload` stored in full (not partial subset).
- [ ] Verify-as-write code path (`reconcilePendingCheckoutForUser`) shared between Stripe + PayPal where possible.
- [ ] Regression test pinning the 200-on-error contract per provider.
- [ ] Regression test pinning the dedup contract (replay).
- [ ] Regression test pinning the stale-event ordering with same-second ties.
- [ ] Regression test for `validatePaymentEventIntegrity` violations (test-mode in prod, price not in `expectedPriceIds` allowlist, discount applied, `trial_end` set).
- [ ] Regression test for owner-mismatch (existing sub user_id ≠ resolved user_id throws hijack error).
- [ ] Regression test for refund chain: a customer with two subs, refunding ONE, leaves the other untouched.
- [ ] Regression test for `detectStaleCheckoutRace` (duplicate active sub triggers alert path, no state mutation).

---

## Common B40 mistakes

- **Step 3 throws → 500 returned.** The whole point of the 5-step contract is the error-acknowledged path. Re-read § 5 of the source guide.
- **`recordWebhookEvent` only catches `code === '23505'`** — Supabase serverless's error shape uses `nativeError.code`. Add the message-string fallback.
- **`markEventProcessed` runs even when handler threw.** The cron now thinks the event was processed; the side effect is lost. Use try/catch + only call `markEventProcessed` on success.
- **`updateSubscriptionStatus` skipped for one-off "I just need to set this status"** — every handler does ad-hoc `db.update(subscriptions)`. Three months later the team-org branch doesn't have the WHERE-clause guard. Force every state mutation through the canonical writer.
- **`last_event_at` not updated on insert.** New row created without the column → next replay can't gate. Insert with `lastEventAt: eventAt`.
- **PayPal access token call inside the webhook hot path.** Cache it; the OAuth call is 200ms+ and serializes your handler.
- **PayPal `BILLING.PLAN.UPDATED` handled.** It's a plan-config event, not entitlement; handling it can revive cancelled subs if you're not careful. Either explicitly ignore or remove from subscribed events.
- **Stripe Account ID check that returns 401 instead of 200.** Stripe will retry. The signature was valid; this is a policy rejection. 200 with `outcome: 'rejected_wrong_account'` is correct.
