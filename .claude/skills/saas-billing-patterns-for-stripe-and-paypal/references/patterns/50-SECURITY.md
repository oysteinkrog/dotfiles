# Bundle B50 — Security

> **Where this comes from.** § 13–§ 23, § 78a of the source guide. SA-01, SA-02, SA-03, SA-06, SA-13, SA-17, SA-22 all live here.

Webhook signatures are necessary but not sufficient. The PayPal `custom_id` is attacker-controllable; PayPal will sign an attacker-created subscription that names the victim's UUID. This bundle is the cross-checks that close that gap.

---

## The hijack class

**The attack.** An attacker with a PayPal business account creates a subscription naming `custom_id = victim_uuid` (or `subscription.id = some_team_id`). PayPal signs the webhook with the legitimate signature. Without further cross-check, the handler updates the victim's row.

**The defense (three layers).**

1. **`validatePayPalUserId`** — every PayPal individual handler cross-checks `custom_id` against `users.customer_id` (the stored payer ID).
2. **`subscription_id` cross-check on every team UPDATE WHERE clause** — an attacker-named org_id alone can't mutate.
3. **Replay-staleness gating** — late events can't revive cancelled state.

---

## Layer 1 — `validatePayPalUserId` (individual hijack)

```ts
// src/lib/paypal/validation.ts
export async function validatePayPalUserId(
  customId: string | undefined,    // attacker-set
  payerId: string,                 // attacker-set BUT must match real PayPal account
  subscriptionId: string,
): Promise<string | undefined> {
  if (!customId) return undefined;

  const user = await db.query.users.findFirst({
    where: eq(users.id, customId),
    columns: { id: true, customerId: true },
  });
  if (!user) return undefined;

  // First-time linking: user has no PayPal customerId yet — allow.
  if (!user.customerId) return customId;

  // Existing PayPal customer: payerId must match what we have stored.
  if (user.customerId === payerId) return customId;

  // Cross-provider switch (Stripe → PayPal): allow only if no other PayPal
  // sub already grants this user current access.
  if (user.customerId.startsWith('cus_')) {
    const existingPaypalSubs = await db.query.subscriptions.findMany({
      where: and(
        eq(subscriptions.userId, customId),
        eq(subscriptions.provider, 'paypal'),
        ne(subscriptions.externalId, subscriptionId),
      ),
    });
    const currentPaypalSub = pickBestSubscription(existingPaypalSubs, 'paypal');
    if (currentPaypalSub) {
      logger.error({ customId, payerId, subscriptionId }, 'PayPal cross-provider switch rejected — potential hijack');
      await trackAbuseSignal({
        signal: 'paypal_user_id_mismatch',
        source: 'system',
        target: { type: 'user', id: customId },
        metadata: { reason: 'cross_provider_with_existing_paypal_sub' },
      });
      return undefined;
    }
    return customId;
  }

  // PayPal customerId mismatch — explicit hijack signal.
  logger.error({ customId, payerId, storedCustomerId: user.customerId, subscriptionId }, 'PayPal user_id validation failed');
  await trackAbuseSignal({
    signal: 'paypal_user_id_mismatch',
    source: 'system',
    target: { type: 'user', id: customId },
    metadata: { reason: 'payer_id_mismatch', received_payer_id: payerId },
  });
  return undefined;
}
```

### The decision matrix

| `customId` | User exists | `user.customerId` | `payerId` matches | Decision |
|-----------|-------------|-------------------|-------------------|----------|
| missing   | n/a         | n/a               | n/a               | return `undefined` (skip) |
| present   | NO          | n/a               | n/a               | return `undefined`, log warn |
| present   | YES         | NULL              | n/a               | accept (first-time link) |
| present   | YES         | matches `payerId` | yes               | accept (existing customer) |
| present   | YES         | starts with `cus_` (Stripe) | n/a       | accept IF no other PayPal sub grants access; else REJECT |
| present   | YES         | mismatch          | no                | REJECT, log error, fire `paypal_user_id_mismatch` abuse signal |

The cross-provider switch branch is not theoretical: legitimate users do switch providers. The defense-in-depth is checking for an EXISTING PayPal sub on the user — if they're switching cleanly, there's no other PayPal sub. If there IS one, the incoming webhook is suspicious.

Pin this contract: `__tests__/paypal-validation.test.ts` covering all 6 rows.

---

## Layer 2 — `subscription_id` cross-check on every team UPDATE (`bd-08xvg.1` / SA-01)

The team subscription handlers must include the **incoming `subscription.id` in every UPDATE WHERE clause** so an UPDATE for an unknown subscription affects 0 rows (silent no-op, attacker can't mutate).

```ts
// CORRECT
await db.update(organizations)
  .set({ subscriptionStatus: 'none', paypalSubscriptionId: null, ... })
  .where(and(
    eq(organizations.id, orgId),                       // attacker-controlled
    eq(organizations.paypalSubscriptionId, subscription.id),  // attacker-controlled
                                                       // BUT must match what we recorded
  ));

// WRONG — pre-fix
await db.update(organizations)
  .set({...})
  .where(eq(organizations.id, orgId));   // attacker mutates any org by UUID
```

### The asymmetric handlers

| Handler | Pre-fix WHERE | Post-fix WHERE |
|---------|---------------|----------------|
| Activated | `id = $orgId` | SELECT FOR UPDATE first; accept if `paypal_sub_id IS NULL AND pending_session_id = $sub_id` (legit first activation) OR `paypal_sub_id = $sub_id` (idempotent replay) |
| Cancelled | `id = $orgId` | `id = $orgId AND paypal_subscription_id = $sub_id` |
| Suspended | `id = $orgId AND status IN ('active', 'past_due')` | `id = $orgId AND paypal_subscription_id = $sub_id AND status IN ('active', 'past_due')` |

A 0-row UPDATE on the rejection paths is the desired outcome — silent no-op that cannot mutate the victim. The Activated path is asymmetric because the WHERE clause alone cannot express "either NULL → match OR equals → match," so it does an explicit SELECT FOR UPDATE + branch.

On rejection: emit `webhook_hijack_attempt` security event + `trackAbuseSignal`. Returns 200 so PayPal doesn't keep retrying.

```ts
async function handleTeamCancelled(event: PayPalWebhookEvent): Promise<void> {
  const subId = event.resource.id;
  const orgId = event.resource.custom_id;  // attacker-controllable

  const result = await db.update(organizations)
    .set({
      subscriptionStatus: 'cancelled',
      paypalSubscriptionId: null,
      subscriptionStatusChangedAt: new Date(event.create_time),
      paypalLastEventAt: new Date(event.create_time),
    })
    .where(and(
      eq(organizations.id, orgId),
      eq(organizations.paypalSubscriptionId, subId),
      or(
        isNull(organizations.paypalLastEventAt),
        lt(organizations.paypalLastEventAt, new Date(event.create_time)),
      ),
    ))
    .returning({ id: organizations.id });

  if (result.length === 0) {
    // Either: stale event (replay), wrong sub_id (hijack attempt), or already cancelled.
    // Emit security event regardless; investigate via the runbook.
    await logSecurityEvent({
      type: 'webhook_hijack_attempt_or_replay',
      severity: 'high',
      target: { type: 'organization', id: orgId },
      details: { subscription_id: subId, event_id: event.id },
    });
  }
}
```

---

## Layer 3 — Replay-staleness gating with `last_event_at` (carries B40 ⏱)

Already detailed in `40-WEBHOOKS.md`; mirrored here because the security review reads this bundle:

```ts
// In any team handler:
if (organization.paypalLastEventAt && event.create_time
    && new Date(event.create_time) < organization.paypalLastEventAt) {
  logger.info({ orgId, eventId: event.id, eventTime: event.create_time }, 'Stale PayPal event ignored');
  await logSecurityEvent({
    type: 'payment_event_replay_blocked',
    severity: 'medium',
    target: { type: 'organization', id: organization.id },
    details: { event_id: event.id, event_time: event.create_time, last_event_at: organization.paypalLastEventAt },
  });
  return;
}
```

---

## Reconcile-cancelled-orgs guard (`bd-08xvg.3` / SA-03)

The `PAYMENT.SALE.COMPLETED` reconcile branch must NOT revive cancelled orgs. Both the application-level if-check AND the SQL `WHERE` clause must include the cancelled-status guard.

```ts
// Pre-fix (vulnerable):
if (org.subscriptionStatus !== 'active') {
  await db.update(organizations).set({ subscriptionStatus: 'past_due' }).where(eq(organizations.id, orgId));
}

// Post-fix:
if (org.subscriptionStatus !== 'active' && org.subscriptionStatus !== 'cancelled' && org.subscriptionStatus !== 'none') {
  await db.update(organizations)
    .set({ subscriptionStatus: 'past_due' })
    .where(and(
      eq(organizations.id, orgId),
      notInArray(organizations.subscriptionStatus, ['cancelled', 'active', 'none']),
      // last_event_at gate also applies
    ));
}
```

A missing `!== "cancelled"` was a real vulnerability, not theoretical.

---

## Layer 4 — owner-mismatch + payload-integrity (the catch-all)

Layers 1-3 catch hijack via known input vectors (PayPal `custom_id`, team `subscription_id`, replay timestamps). Layer 4 catches *everything else* by enforcing two invariants on every state-mutating webhook:

**Invariant A: persisted owner == resolved owner.** If a `subscriptions` row already exists for this `external_subscription_id`, its `user_id` must match the user resolved from the inbound event. Any mismatch is a hijack regardless of how the resolution happened.

```ts
// Inside updateSubscriptionStatus, after user resolution:
if (existingSubscription && typeof existingSubscription.userId === "string"
    && existingSubscription.userId !== resolvedUser.id) {
  logSecurityEvent({
    type: "webhook_hijack_attempt",
    severity: "critical",
    actor: { authSource: "webhook", userId: resolvedUser.id },
    target: { type: "subscription", id: externalSubscriptionId },
    details: { linkedUserId: existingSubscription.userId, resolvedUserId: resolvedUser.id, provider },
  });
  throw new SubscriptionOwnerMismatchError({ /* ... */ });
}
```

**Invariant B: event payload matches expected business shape.** Signature verification proves the event came from the provider; it does NOT prove the line items, prices, discounts, or livemode match what your business contract expects. `validatePaymentEventIntegrity` (defined in B40) is the structured validator that rejects:

- `test_mode_in_prod` — production env receiving a test-mode session
- `client_reference_user_mismatch` — the userId we set in checkout doesn't match the one in the event
- `wrong_price_id` — line items contain a price not in the allowlist (`expectedPriceIds` set)
- `discount_applied` — `total_details.amount_discount > 0` when policy is no-discount
- `trial_period_present` — `subscription.trial_end` set when policy is no-trial

Layer 4 is the catch-all because the prior layers are vector-specific. A new attack vector that bypasses Layers 1-3 still has to forge an event whose persisted owner matches OR whose payload passes integrity — both invariants stand independent of the attack mechanism.

**Reference:** see B40 §"Owner-mismatch detection" and §"`validatePaymentEventIntegrity`" for the full implementations.

---

## Stripe account / context verification (Connect / org events) — § 78a.1

For multi-account Stripe webhook setups (Stripe Connect, organization event destinations), verify the originating account before processing.

```ts
// In env.ts:  STRIPE_ACCOUNT_ID: z.string().startsWith('acct_').optional()
// In handleStripeEvent, BEFORE switch:
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
  return NextResponse.json({ received: true, outcome: 'rejected_wrong_account' });
}
```

**Important scope correction.** For an ordinary single-account Stripe webhook endpoint, a random attacker cannot make their own Stripe account's webhook pass our endpoint-secret verification; Stripe signs each endpoint delivery with that endpoint's signing secret. The account/context check above is for Stripe Connect endpoints, Stripe organization event destinations, or any future shared webhook route intentionally receiving events for more than one Stripe account.

For PayPal: there's no equivalent `event.account` field, but cross-check `event.resource.plan_id` against your allowed PayPal plan IDs (`PAYPAL_PLANS` in `BUSINESS`). An attacker-created PayPal subscription will NOT use one of your plan IDs.

---

## Rate limiter `FAIL_CLOSED_ENDPOINTS` (SA-06) — § 18

Some routes are sensitive enough that if the rate limiter fails (Redis down, etc.), they MUST fail closed (deny the request) rather than fall back to allowing.

```ts
// src/lib/security/rate-limit.ts
const FAIL_CLOSED_ENDPOINTS: ReadonlySet<string> = new Set([
  '/api/auth/login',
  '/api/auth/signup',
  '/api/auth/password-reset',
  '/api/checkout/verify',
  // do NOT include /api/{stripe,paypal}/webhook — Stripe IPs would get banned during retry storms
]);

export async function checkRateLimit(req: Request, key: string): Promise<RateLimitResult> {
  try {
    return await rateLimiter.check(req, key);
  } catch (err) {
    const path = new URL(req.url).pathname;
    if (FAIL_CLOSED_ENDPOINTS.has(path)) {
      logger.error({ path, err }, 'Rate limiter unavailable; failing closed');
      return { allowed: false, reason: 'limiter_unavailable' };
    }
    logger.warn({ path, err }, 'Rate limiter unavailable; failing open (non-sensitive route)');
    return { allowed: true, reason: 'limiter_unavailable_failed_open' };
  }
}
```

The webhook routes are explicitly NOT in the fail-closed set because Stripe's IP would get banned during normal retry storms, breaking reconciliation. Use § 78a.2 instead (skip cooldown for `source === 'system'`).

---

## Admin retry path — age cutoff, regression guard, override audit (SA-13) — § 19

The admin "retry this stuck payment_event" button needs three guards:

```ts
async function adminRetryPaymentEvent(
  adminUserId: string,
  paymentEventId: string,
  override: { reason?: string; force?: boolean } = {},
): Promise<RetryResult> {
  // 1. Age cutoff — events older than 90 days are likely irrelevant
  const event = await db.query.paymentEvents.findFirst({ where: eq(paymentEvents.id, paymentEventId) });
  const ageDays = (Date.now() - event.createdAt.getTime()) / (1000 * 60 * 60 * 24);
  if (ageDays > 90 && !override.force) {
    return { ok: false, reason: 'age_cutoff', ageDays };
  }

  // 2. Regression guard — event has been processed; double-processing risks duplicate side effect
  if (event.processedAt && !override.force) {
    return { ok: false, reason: 'already_processed', processedAt: event.processedAt };
  }

  // 3. Override audit — every override is logged with the admin user, reason, and timestamp
  if (override.force) {
    await logSecurityEvent({
      type: 'admin_retry_override',
      severity: 'high',
      actor: { type: 'user', id: adminUserId },
      target: { type: 'payment_event', id: paymentEventId },
      details: { reason: override.reason ?? 'no_reason_given', age_days: ageDays, was_processed: !!event.processedAt },
    });
  }

  // 4. Execute via the same reconciliation path
  return await reconcilePaymentEvent(event);
}
```

---

## Suppress automatic replay after bookkeeping failure (SA-22) — § 21

If the bookkeeping cron fails to record a refund into the ledger (so dashboards / fees / tax-reports are inaccurate), do NOT automatically replay the refund. The refund already happened at the provider; replaying just emits more `payment_events.refund.created` rows that all collide on UNIQUE.

The right move: surface the bookkeeping failure as a `system_alert_dedupe` event + alert; let the operator manually triage.

```ts
// In refund-bookkeeping cron:
try {
  await recordRefundLedgerEntry(refundEvent);
  await markRefundBookkept(refundEvent.id);
} catch (err) {
  // Don't retry the bookkeeping itself — that's deterministic.
  // Don't replay the refund — that's already done.
  // Surface the failure for human triage.
  await logComplianceEvent({
    eventType: 'refund_bookkeeping_failed',
    target: { type: 'payment_event', id: refundEvent.id },
    metadata: { error: err.message },
  });
  await createEmailJob({
    type: 'admin_ops_alert',
    recipient: env.ADMIN_EMAIL,
    payload: { subject: 'Refund bookkeeping failed', refundId: refundEvent.id, error: err.message },
    priority: 30,
  });
}
```

---

## Security event taxonomy — § 22

Every security event has a stable type from a closed registry. Avoid in-line strings.

```ts
export const SecurityEventTypes = {
  WEBHOOK: {
    SIGNATURE_FAILED: 'webhook_signature_failed',
    EVENT_REJECTED: 'webhook_event_rejected',
    HIJACK_ATTEMPT: 'webhook_hijack_attempt',
    REPLAY_BLOCKED: 'payment_event_replay_blocked',
  },
  PAYPAL: {
    USER_ID_MISMATCH: 'paypal_user_id_mismatch',
    PAYER_ID_MISMATCH: 'paypal_payer_id_mismatch',
    SUBSCRIPTION_ID_MISMATCH: 'paypal_subscription_id_mismatch',
  },
  STRIPE: {
    ACCOUNT_MISMATCH: 'stripe_account_mismatch',
  },
  ADMIN: {
    RETRY_OVERRIDE: 'admin_retry_override',
    SECRET_ROTATED: 'admin_secret_rotated',
  },
  RATE_LIMIT: {
    FAIL_CLOSED: 'rate_limit_fail_closed',
    EXCEEDED: 'rate_limit_exceeded',
  },
} as const;
```

`logSecurityEvent` writes to `compliance_events` (the dedicated audit log) AND fires an admin alert if severity ≥ 'high'. The dashboard groups by event_type; the runbook keys on event_type.

---

## Abuse signal cooldowns — § 23

`abuse_signals` table stores per-IP, per-route, per-signal counters with TTL. Cooldown logic:

```ts
export async function trackAbuseSignal(params: {
  signal: AbuseSignal;
  source: 'user' | 'system';
  request?: Request;
  ...
}): Promise<void> {
  // Step 1: always increment the counter (we want to know this happened)
  await incrementSignalCounter(params.signal, getClientIp(params.request));

  // Step 2: skip cooldown application if source === 'system' (Stripe IP retry storm)
  if (params.source === 'system') return;

  // Step 3: apply cooldown for user-source signals
  const counter = await getSignalCounter(params.signal, getClientIp(params.request));
  const threshold = COOLDOWN_THRESHOLDS[params.signal];
  if (counter > threshold) {
    await applyCooldown(params.signal, getClientIp(params.request), COOLDOWN_DURATION[params.signal]);
  }
}
```

Without the `source === 'system'` skip, a Stripe IP that hits our webhook 1000 times in a minute (legitimate during a retry storm) would trigger an IP-level cooldown that bans Stripe's IP and breaks reconciliation.

---

## Polish Bar checks for B50

- [ ] `validatePayPalUserId` exists and runs on EVERY PayPal individual handler before state mutation.
- [ ] All 6 rows of the decision matrix are pinned by tests.
- [ ] `subscription_id` is in every team-org UPDATE WHERE clause.
- [ ] Activated handler does SELECT FOR UPDATE + branch (asymmetric guard).
- [ ] 0-row UPDATE rejection emits `webhook_hijack_attempt` + abuse signal.
- [ ] Reconcile-cancelled-orgs guard: cancelled-status check in BOTH if-branch AND SQL WHERE.
- [ ] Stripe Connect / org event endpoints have account/context check.
- [ ] PayPal cross-check: `event.resource.plan_id` against `BUSINESS.PAYPAL_PLANS`.
- [ ] Rate limiter `FAIL_CLOSED_ENDPOINTS` includes auth + checkout-verify; explicitly EXCLUDES webhook routes.
- [ ] Admin retry path: age cutoff + already-processed guard + override audit log.
- [ ] Bookkeeping failure path doesn't auto-replay (SA-22).
- [ ] Security event types are in a closed registry; no inline strings.
- [ ] `abuse_signals.source === 'system'` skips cooldowns.
- [ ] Per-incident regression test (every SA-NN finding has a test named after it).
- [ ] Hijack runbook lives at `docs/runbooks/paypal-hijack-attempt.md`.

---

## Common B50 mistakes

- **Cross-provider switch branch missing the EXISTING PayPal sub check.** The defense-in-depth is what catches a hijack on a user who already has a PayPal sub.
- **`subscription_id` cross-check on Cancelled but not Suspended.** All team handlers need the predicate.
- **Reconcile branch revives cancelled orgs.** The `!== "cancelled"` is non-negotiable; SA-03 was a real vulnerability.
- **Rate limiter cooldown applied to Stripe webhook IPs.** Reconciliation breaks during retry storms. Use the source === 'system' skip.
- **Admin retry button with no override audit.** The override is the most dangerous capability in the admin UI; log every use with the admin's identity, reason, and what they overrode.
- **Bookkeeping cron retries on its own failure.** The refund happened; the dashboard is wrong. Surface for human triage; don't replay.
- **Hardcoded security event type strings.** Dashboard breaks when a typo emits a new event type; runbook grep misses. Use the registry.
