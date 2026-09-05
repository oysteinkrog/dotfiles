# Bundle B60 — Subscription State & Lifecycle

> **Where this comes from.** § 24, § 25, § 26, § 27, § 30, § 31 of the source guide.

The subscription state machine is small but adversarial. Most projects get it wrong by collapsing the state model (treating `paused_for_org` as cancelled), by using the local clock for grace period (which fails at midnight UTC), or by not separating refund decisions from refund mirroring.

---

## The state model + aggregate projection

Five `subscription_status` values:

| Status | Meaning | Granted access? |
|--------|---------|-----------------|
| `none` | No active relationship (post-refund, pre-checkout, expired-and-not-renewed) | No |
| `active` | Paying, in good standing | Yes |
| `past_due` | Payment failed; in grace period | Yes (until grace expires) |
| `cancelled` | Cancelled but `current_period_end` may be in future | Yes (until period end) |
| `paused_for_org` | Individual sub paused because user joined a team plan | No (team plan grants access instead) |

### Multiple subscription rows per user

A user can have N rows in `subscriptions`:
- One Stripe row + one PayPal row (after a provider switch)
- Multiple cancelled rows from prior failed attempts (kept for audit)
- One `gratis` row for comp accounts

The "current" sub is computed by `pickBestSubscription`:

```ts
// src/lib/services/subscription.ts
export function pickBestSubscription(
  subs: Subscription[],
  preferredProvider?: SubscriptionProvider,
): Subscription | null {
  // Precedence: active > past_due (in grace) > paused_for_org > cancelled-but-period-not-ended > cancelled > none
  const tier = (s: Subscription) => {
    if (s.status === 'active') return 5;
    if (s.status === 'past_due' && stillInGrace(s)) return 4;
    if (s.status === 'paused_for_org') return 3;
    if (s.status === 'cancelled' && s.currentPeriodEnd && s.currentPeriodEnd > new Date()) return 2;
    if (s.status === 'cancelled') return 1;
    return 0;
  };
  const sorted = [...subs].sort((a, b) => {
    const ta = tier(a), tb = tier(b);
    if (ta !== tb) return tb - ta;
    // Tiebreak: preferred provider, then most recent
    if (preferredProvider && a.provider !== b.provider) {
      if (a.provider === preferredProvider) return -1;
      if (b.provider === preferredProvider) return 1;
    }
    return (b.updatedAt.getTime() ?? 0) - (a.updatedAt.getTime() ?? 0);
  });
  return sorted[0] ?? null;
}
```

### `deriveAggregateBillingProjection`

Recomputes `users.subscription_status` (the cache) from the underlying subscription rows + org memberships:

```ts
export async function deriveAggregateBillingProjection(
  userId: string,
  tx?: TxLike,
): Promise<{ status: SubscriptionStatus; provider: SubscriptionProvider | null }> {
  const db = tx ?? globalDb;

  // Read all subscriptions
  const subs = await db.query.subscriptions.findMany({ where: eq(subscriptions.userId, userId) });

  // Read team memberships with active org subscription
  const orgMemberships = await db.query.organizationMembers.findMany({
    where: eq(organizationMembers.userId, userId),
    with: { organization: true },
  });
  const activeOrgSub = orgMemberships.find(m =>
    m.organization.subscriptionStatus === 'active' || m.organization.subscriptionStatus === 'past_due'
  );

  // Team coverage trumps individual: if user has an active org sub, individual is paused
  if (activeOrgSub) {
    // Pause any individual subs (intent-then-act in B80)
    return { status: 'active', provider: 'gratis' };  // 'gratis' = "covered by team"
  }

  const best = pickBestSubscription(subs);
  if (!best) return { status: 'none', provider: null };
  return { status: best.status, provider: best.provider };
}
```

The denormalized `users.subscription_status` is rebuilt by this function every time a subscription row changes (in `updateSubscriptionStatus`).

---

## `paused_for_org` (§ 25)

When an individual user joins a team plan, their personal sub should be paused — not cancelled. Reasons:

1. **They might leave the team.** A cancellation would force them to create a new sub from scratch, losing customer history.
2. **Refund accounting needs to know it's still "their sub."** A cancellation breaks the refund window.
3. **Resume should be one click.** The intent-then-act in B80 makes this clean.

```ts
// In updateSubscriptionStatus, when org membership becomes active:
await tx.update(subscriptions)
  .set({ status: 'paused_for_org' })
  .where(and(
    eq(subscriptions.userId, userId),
    inArray(subscriptions.status, ['active', 'past_due']),
    or(isNull(subscriptions.lastEventAt), lt(subscriptions.lastEventAt, eventAt)),
  ));

// AND THEN (outside the tx — see B80 Intent-Then-Act):
//   provider call to actually pause Stripe / PayPal subscription
```

The provider-side pause happens via the intent table, not inside the DB transaction. See B80.

---

## Pause/resume intent ledger — `paused_for_org` is a *durable contract*, not just a state

The `paused_for_org` state above is the user-visible side of a multi-step coordination problem. Switching an individual sub from `active` to `paused_for_org` requires two writes that *cannot* both happen in a single transaction:

1. **DB write**: flip `subscriptions.status` to `paused_for_org` (fast, ms-scale, transactional)
2. **Provider write**: cancel the individual sub at the provider (slow, 200ms-3s, network) — for `paused_for_org` the provider call is a *cancel*, not a pause, because once a user is on a team plan there is no scenario where their old individual sub resumes (a future re-subscribe creates a fresh sub). The same intent-ledger pattern carries genuine `pause` intents (Billing-H4 / `bd-yu9g9`) where the resume *does* reuse the original sub.

Combining them in one transaction means the slow provider call holds a DB connection for 3s under bursts → connection pool exhaustion. Splitting them naively means a crash between (1) and (2) leaves a sub that *says* it's paused-or-cancelled in our DB but is still actively charging the customer at the provider. The fix is the **intent ledger**: durably record the *intent* in (1), let an idempotent reconciliation cron eventually carry out (2).

The schema lives on the parent table (the org's row carries the pending cancel for the individual sub it just absorbed):

```sql
ALTER TABLE organizations
  ADD COLUMN pending_individual_sub_cancel_id          text,
  ADD COLUMN pending_individual_sub_cancel_user_id     uuid,
  ADD COLUMN pending_individual_sub_cancel_provider    subscription_provider,
  ADD COLUMN pending_individual_sub_cancel_enqueued_at timestamptz,
  ADD COLUMN pending_individual_sub_cancel_retry_count int NOT NULL DEFAULT 0,
  ADD COLUMN pending_individual_sub_cancel_last_retry_at timestamptz,
  ADD COLUMN pending_individual_sub_cancel_last_error  text;
```

Step 1 (the `paused_for_org` flip) writes the intent in the same transaction:

```ts
await tx.update(organizations).set({
  pendingIndividualSubCancelId: subscription.externalId,
  pendingIndividualSubCancelUserId: subscription.userId,
  pendingIndividualSubCancelProvider: subscription.provider,
  pendingIndividualSubCancelEnqueuedAt: new Date(),
  pendingIndividualSubCancelRetryCount: 0,
}).where(eq(organizations.id, orgId));

await tx.update(subscriptions).set({ status: "paused_for_org" })
  .where(and(eq(subscriptions.id, subscription.id), /* last_event_at gate */));
```

Step 2 happens in `/api/cron/retry-individual-sub-cancels` (every 5 min):

```ts
// src/app/api/cron/retry-individual-sub-cancels/route.ts
const MAX_RETRY_COUNT = 5;

function clearedPendingCancelValues() {
  return {
    pendingIndividualSubCancelId: null,
    pendingIndividualSubCancelUserId: null,
    pendingIndividualSubCancelProvider: null,
    pendingIndividualSubCancelEnqueuedAt: null,
    pendingIndividualSubCancelRetryCount: 0,
    pendingIndividualSubCancelLastRetryAt: null,
    pendingIndividualSubCancelLastError: null,
  };
}

// Drain — bounded by retry_count cap
const pending = await db.select(/* ... */).from(organizations)
  .where(and(
    isNotNull(organizations.pendingIndividualSubCancelId),
    lt(organizations.pendingIndividualSubCancelRetryCount, MAX_RETRY_COUNT),
  ));

for (const row of pending) {
  const result = await tryCancelOrPauseAtProvider(
    row.pendingIndividualSubCancelProvider!,
    row.pendingIndividualSubCancelId!,
  );

  if (result.ok || result.alreadyMissing) {
    // Success or "Stripe says it's already gone" — clear the intent
    await db.update(organizations)
      .set(clearedPendingCancelValues())
      .where(eq(organizations.id, row.id));
  } else {
    // Failed — bump retry counter; stays in the queue
    await db.update(organizations).set({
      pendingIndividualSubCancelRetryCount: row.pendingIndividualSubCancelRetryCount + 1,
      pendingIndividualSubCancelLastRetryAt: new Date(),
      pendingIndividualSubCancelLastError: result.error,
    }).where(eq(organizations.id, row.id));
  }
}
```

When `retry_count` hits `MAX_RETRY_COUNT`, the row STAYS in the queue but the cron skips it — the **terminal-stuck digest** (run daily) summarizes all stuck intents in one email so on-call can investigate manually:

```ts
// /api/cron/billing-stuck-digest (daily at 9am UTC)
const stuck = await db.select(/* ... */).from(organizations)
  .where(and(
    isNotNull(organizations.pendingIndividualSubCancelId),
    gte(organizations.pendingIndividualSubCancelRetryCount, MAX_RETRY_COUNT),
  ));

if (stuck.length > 0) {
  // esc() is the HTML-escape helper from B40 §"HTML-escape admin notifications".
  await sendEmail({
    to: env.ADMIN_EMAIL,
    subject: `[billing] ${stuck.length} stuck individual-sub-cancel intent(s)`,
    html: stuck.map(s => `<li>${esc(s.id)} — ${esc(s.pendingIndividualSubCancelLastError ?? "(no error)")}</li>`).join("\n"),
  });
}
```

The same pattern carries `/api/cron/retry-orphan-sub-cancels` (the GDPR-delete safety net from B10's `orphan_subscription_cancels` table). Both crons share three invariants:

1. **Bounded retry** (`MAX_RETRY_COUNT = 5`) — never burn provider API quota in an infinite loop on a permanently broken sub.
2. **`alreadyMissing` is success** — Stripe says "no such subscription"? Treat as done; don't retry forever.
3. **Terminal stuck stays in the queue** — clearing on max-retry would lose the audit trail.

**Why this is in B60 and not B70 (dunning):** dunning is about *collecting money*; this is about *honoring the user's intent regardless of provider availability*. Different concerns, different SLAs (dunning's day-7 cadence vs this cron's 5-min cadence).

**Reference:** jeffreys-skills.md `src/app/api/cron/retry-individual-sub-cancels/route.ts:67-117, 160-250` and `src/app/api/cron/retry-orphan-sub-cancels/route.ts:63-256`.

---

## Grace period — Edge-compatible single source (§ 26)

```ts
// src/lib/services/grace-period.ts
// MUST be Edge-runtime compatible — used in middleware on every request.

const GRACE_PERIOD_DAYS = 21;

/**
 * Returns true if a past_due subscription is still within its grace window.
 * The "grace window" starts at the most recent failed payment attempt
 * (current_period_end if no specific failure timestamp is recorded).
 */
export function stillInGrace(sub: Pick<Subscription, 'status' | 'currentPeriodEnd' | 'lastEventAt'>): boolean {
  if (sub.status !== 'past_due') return sub.status === 'active' || sub.status === 'cancelled';

  // The clock is the provider event timestamp, not local time
  const reference = sub.lastEventAt ?? sub.currentPeriodEnd;
  if (!reference) return false;

  const graceEnd = new Date(reference.getTime() + GRACE_PERIOD_DAYS * 24 * 60 * 60 * 1000);
  return Date.now() < graceEnd.getTime();
}
```

### Why Edge-compatible

This function runs in middleware on every request to decide if a `past_due` user still gets access. Middleware in Next.js runs in the Edge runtime — no Node APIs. Keep dependencies to zero (no `node:crypto`, no DB calls).

### Why a single source

`GRACE_PERIOD_DAYS` is also referenced by:
- The dunning ladder cron (B70).
- The integrity-audit cron (B90).
- Customer-portal templating ("you have 12 days to update your card").

If three places had three constants, they'd drift. One file owns the value.

---

## Verify-as-write (already shown in B40, summarized here)

The `/api/checkout/verify` endpoint can ALSO write subscription state if the webhook hasn't landed yet. The webhook is a backup, not the primary writer.

The shared helper `reconcilePendingCheckoutForUser()` is the unified entry point for Stripe and PayPal verify-as-write paths. Behind feature flags (`verify_write_path`, `verify_write_path_shadow_mode`):
- When the write flag is off, Stripe falls back to legacy read-only paid-but-pending verification.
- PayPal still has its older inline direct-write fallback.

The planned recent-checkout cron and self-service "I paid, please activate" button should reuse the same helper rather than inventing separate activation semantics.

---

## Stale-checkout race guard (§ 28 / `bd-bfwcy.4 / BILLING-M2`)

Detail in B30 (checkout side). The B60 side: when a webhook for an OLD session arrives, recognize it and queue the operator alert:

```ts
// In handleStripeCheckoutCompleted:
async function handleStripeCheckoutCompleted(event: Stripe.Event) {
  const session = event.data.object as Stripe.Checkout.Session;
  const userId = session.metadata?.userId;
  const user = await db.query.users.findFirst({ where: eq(users.id, userId) });

  if (user.pendingCheckoutSessionId && user.pendingCheckoutSessionId !== session.id) {
    // The user has moved on to a NEWER session; this completed one is stale.
    await queueStaleCheckoutAlert({
      user,
      staleSessionId: session.id,
      currentPendingSessionId: user.pendingCheckoutSessionId,
    });
    // Do NOT activate; the user paid a stale session — operator needs to refund or attach.
    return;
  }

  // Normal path
  await reconcilePendingCheckoutForUser({ provider: 'stripe', userId, sessionId: session.id, session });
}
```

---

## Refunds — the asymmetric strict path

### The contract

When a refund event arrives:
1. **Confirm the parent payment is fully refunded** (or partial — see § 31).
2. **Revoke access in OUR DB synchronously** (don't wait for the next webhook tick).
3. **Synchronously invalidate caches** (B100 — SA-02 made this synchronous, 2s timeout).
4. **Emit refund-bookkeeping event** (separate from access-revocation; book-kept lazily by cron).
5. **Return 200** (the provider already issued the refund; nothing for us to retry).

```ts
// src/lib/webhooks/inbound.ts
export async function revokeAccessOnRefund(params: {
  provider: SubscriptionProvider;
  externalSubscriptionId: string;
  refundEventId: string;
  refundAmount: number;
  parentChargeId: string;
}): Promise<void> {
  // 1. For PayPal partial refunds, fetch parent payment to compute cumulative
  //    refunded amount; only revoke if cumulative >= total charged.
  if (params.provider === 'paypal') {
    const parent = await getPayPalParentPayment(params.parentChargeId);
    const totalRefunded = parent.refunds.reduce((sum, r) => sum + r.amount, 0);
    if (totalRefunded < parent.total) {
      logger.info({ refundEventId: params.refundEventId, totalRefunded, total: parent.total },
        'Partial refund — access not revoked yet');
      return;
    }
  }

  // 2. Revoke
  await db.transaction(async (tx) => {
    await tx.update(subscriptions)
      .set({ status: 'none', cancelledAt: new Date(), updatedAt: new Date() })
      .where(and(
        eq(subscriptions.provider, params.provider),
        eq(subscriptions.externalId, params.externalSubscriptionId),
        // No last_event_at gate here — refund is terminal; even a stale event
        // shouldn't revive a refunded subscription
      ));
    await deriveAggregateBillingProjection(/* user from sub */);
  });

  // 3. Synchronously invalidate caches (2s race cap)
  await Promise.race([
    invalidateUserCaches(userId),
    sleep(2000).then(() => logger.warn({ userId }, 'Cache invalidation timed out; rendering may be stale')),
  ]);

  // 4. Emit refund-bookkeeping event (B100 picks it up)
  await emitRefundBookkeepingEvent({ refundEventId: params.refundEventId, refundAmount: params.refundAmount });
}
```

---

## PayPal partial-refund detection (§ 31 / Billing-H2)

The naive PayPal handler reads `sale.state` to decide if a refund is full or partial — but `sale.state` is sometimes `partially_refunded` even when the customer was fully refunded across multiple refund events.

```ts
// CORRECT — fetch parent payment, sum all refund amounts, compare to total
async function handlePayPalRefund(event: PayPalWebhookEvent) {
  const parentPaymentId = event.resource.parent_payment;
  const parent = await getPayPalParentPayment(parentPaymentId);
  // parent.transactions[0].related_resources contains all sales + refunds
  const totalCharged = parent.transactions[0].amount.total;
  const refunds = parent.transactions[0].related_resources
    .filter(r => r.refund)
    .map(r => parseFloat(r.refund.amount.total));
  const cumulativeRefunded = refunds.reduce((sum, amt) => sum + amt, 0);

  const fullyRefunded = Math.abs(cumulativeRefunded - parseFloat(totalCharged)) < 0.005;  // float tolerance
  if (fullyRefunded) {
    await revokeAccessOnRefund({ ...refund details... });
  } else {
    // Partial — log it, emit a partial-refund event, but don't revoke.
    await logComplianceEvent({ eventType: 'partial_refund_no_revoke', target, metadata: { cumulativeRefunded, totalCharged } });
  }
}
```

If `getPayPalParentPayment` fails (PayPal API outage), fall back safe: do NOT revoke, log a `paypal_parent_payment_unavailable` security event, queue retry. The refund will be re-evaluated on next webhook tick or by the reconciliation cron.

---

## Refund & cancellation policy guardrails (§ 65)

The system should NOT auto-refund. Detection / queueing is automated; the actual refund is a human click in the Stripe Dashboard.

The customer-facing policy lives in your Terms of Service. The implementation guardrail:

```ts
// ❌ NEVER do this:
async function autoRefundDuplicateCharge(charge: Stripe.Charge) {
  await stripe.refunds.create({ charge: charge.id });  // No.
}

// ✓ Instead:
async function detectAndQueueDuplicateCharge(charge: Stripe.Charge) {
  await queueRefundReviewItem({
    customerId: charge.customer,
    chargeId: charge.id,
    suspectedDuplicate: true,
    detectedAt: new Date(),
  });
  await createEmailJob({
    type: 'admin_ops_alert',
    recipient: env.ADMIN_EMAIL,
    payload: { subject: 'Suspected duplicate charge', chargeId: charge.id, amount: charge.amount },
    priority: 30,
  });
}
```

### The refund window

A configured `BUSINESS.REFUND_WINDOW_DAYS` (default 14) lets the admin UI know which subs are still eligible for refund (often required by jurisdiction). Outside the window, the admin UI can still issue refunds via the Stripe Dashboard, but the in-app workflow is gated.

---

## Polish Bar checks for B60

- [ ] Five-status enum is the single source of truth for subscription state.
- [ ] `pickBestSubscription` returns the correct row for users with multiple subs.
- [ ] `deriveAggregateBillingProjection` recomputes `users.subscription_status` after every subscription mutation.
- [ ] Org-membership precedence over individual subs is correct.
- [ ] `paused_for_org` enum value is used when user joins team (NOT `cancelled`).
- [ ] **Pause/resume intent ledger** — `pendingIndividualSubCancel*` columns on `organizations`; provider call NEVER inside the DB transaction.
- [ ] `retry-individual-sub-cancels` cron has `MAX_RETRY_COUNT = 5` cap, treats `alreadyMissing` as success, leaves max-retried rows in queue (not cleared).
- [ ] `retry-orphan-sub-cancels` cron mirrors the same invariants for the GDPR-delete safety net.
- [ ] **Terminal-stuck digest** runs daily; one summary email instead of per-row pages.
- [ ] `stillInGrace` is Edge-runtime compatible (no DB, no Node APIs).
- [ ] `GRACE_PERIOD_DAYS` is one constant; referenced by middleware + dunning + portal.
- [ ] Verify-as-write helper shared between Stripe + PayPal.
- [ ] Stale-checkout race guard fires `queueStaleCheckoutAlert` (not silent activation).
- [ ] Refund handler revokes access synchronously inside a tx.
- [ ] Synchronous cache invalidation with 2s race cap.
- [ ] PayPal partial-refund detection fetches parent payment + sums cumulative.
- [ ] PayPal partial fallback: do not revoke if parent unavailable; log + retry.
- [ ] No auto-refund anywhere; detection queues for human triage.
- [ ] `BUSINESS.REFUND_WINDOW_DAYS` gates the in-app refund workflow.
- [ ] Regression test pinning the multiple-subs `pickBestSubscription` edge cases.
- [ ] Regression test pinning grace-period boundaries (entry to grace, exit at day 21, exit at provider event).
- [ ] Regression test pinning PayPal partial refund (cumulative < total → don't revoke).

---

## Common B60 mistakes

- **Treating `paused_for_org` as `cancelled`.** Doubles the user when they leave the team.
- **`stillInGrace` uses `Date.now()` only.** Fine on a normal request; broken when the test uses a fixed-clock and breaks midnight UTC. Always reference `sub.lastEventAt`.
- **`pickBestSubscription` doesn't handle the `cancelled but period-not-ended` case.** A user who cancelled but is still inside their paid period gets shown the wrong UI.
- **Refund handler doesn't sync-invalidate caches.** SA-02. The user's denormalized status is stale; they keep seeing premium features for hours.
- **PayPal partial refund handler revokes on the FIRST refund event.** Customer requested half-refund; access pulled. Outrage.
- **Verify-as-write writes a NEW subscription row instead of using the canonical writer.** Two rows for the same external_id; UNIQUE constraint catches it but late, and `pickBestSubscription` picks wrong.
- **Refund handler retries on `getPayPalParentPayment` failure.** Storms PayPal API. Fall back safe + queue.
