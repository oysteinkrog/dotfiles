# Provider-Authoritative Truth

> The single most dangerous pattern in SaaS billing code is treating your local database as the source of truth for revenue metrics. Your database is a cache of provider state. Stripe and PayPal are the source of truth.

## The Core Principle

**MRR, subscriber counts, and revenue figures must be derived from what Stripe and PayPal report, not from local mutable columns.**

Your `users.subscriptionStatus` field, your `subscriptions.status` column, your `COUNT(*) WHERE status = 'active'` queries — all of these are *caches* of provider state that can and will drift from reality.

### How Drift Happens

1. **Webhook delivery failures** — a cancellation webhook is lost, your DB still shows `active`
2. **Out-of-order processing** — a renewal webhook arrives before the cancellation webhook
3. **Manual provider-side changes** — an admin cancels/refunds in the Stripe dashboard
4. **Enrichment failures** — event recorded but `user_id` never resolved (silently left as NULL)
5. **Stale denormalized fields** — `users.subscriptionStatus` set once but never kept in sync with subscription table changes

### The Canonical MRR Snapshot Pattern

Build a single function that queries Stripe and PayPal live APIs to produce a canonical snapshot. Every admin surface, every projection, every metric that touches revenue must consume this snapshot — never a raw DB query.

```typescript
interface CanonicalMrrSnapshot {
  totalMrr: number;                    // Sum of all paid subscriptions
  totalPaidAccounts: number;           // Distinct paying users
  byProvider: {
    stripe: { mrr: number; count: number; byStatus: Record<string, number> };
    paypal: { mrr: number; count: number; byStatus: Record<string, number> };
  };
  byBusinessType: {
    individual: { mrr: number; count: number };
    team: { mrr: number; count: number };
  };
  providerHealth: {
    stripe: 'live' | 'degraded' | 'unavailable';
    paypal: 'live' | 'degraded' | 'unavailable';
  };
  computedAt: Date;
}
```

**Key rules for the snapshot:**

1. **One snapshot function, all consumers.** Admin cockpit, revenue page, projections, Monte Carlo, AI insights — all read from the same snapshot.
2. **Provider health tracking.** When a provider API fails, mark it as `degraded`/`unavailable`. Never silently substitute DB estimates for provider truth.
3. **DB fallback is clearly labeled.** If you must fall back to DB estimates when a provider is down, the snapshot must expose this so consumers can decide whether to display it or show "unavailable."
4. **Short cache TTL.** 60 seconds maximum. The DB can handle one aggregation query per minute.

---

## Common Violations (All Found in Production)

### 1. `COUNT(active users) * $20`

```typescript
// WRONG — hardcoded price, ignores org/team pricing, ignores provider truth
const mrr = activeSubscribers * 20;
```

This breaks for:
- Team/org subscriptions at different price points
- Any price change
- Users with non-standard plans
- Provider-side adjustments (prorations, credits)

**Fix:** Derive MRR from the canonical snapshot, which sums actual subscription amounts from live provider data.

### 2. Using `users.subscriptionStatus` as Billing Source of Truth

```typescript
// WRONG — stale denormalized field
const paid = await db.select().from(users)
  .where(eq(users.subscriptionStatus, 'active'));
```

This field drifts because:
- Manual DB fixes update the user row without updating the subscription record
- Reconciliation passes reset it to `none` because there's no underlying entitlement
- Org-based access doesn't propagate to this field
- Webhook failures leave it stale

**Fix:** Use paid-access entitlement semantics — check the `subscriptions` table joined with provider-canonical status, or use the canonical MRR snapshot for aggregates.

### 3. Different MRR Definitions on Different Admin Pages

If your admin cockpit shows `$4,480 MRR` and your revenue page shows `$4,560 MRR`, you have two different definitions of "paid." Found in production:
- Cockpit: `users.subscriptionStatus = 'active'` times `$20`
- Revenue page: `countCurrentPaidSubscribersByProvider()`

**Fix:** One canonical snapshot, consumed everywhere. Different admin pages should render different views of the same data, never compute independently.

### 4. Dropping Cancelled-But-Still-Paid Users

```typescript
// WRONG — drops users who cancelled but haven't reached period end
const mrr = await db.select().from(users)
  .where(eq(users.subscriptionStatus, 'active'));
```

If cancellation webhooks immediately set user status to `cancelled`, your MRR drops before access actually ends. These users are still paid through their period.

**Fix:** MRR counts users with paid entitlement (active OR cancelled-with-remaining-period OR past-due-in-grace), not raw status.

### 5. Mixing Stock and Flow Metrics

```typescript
// WRONG — falling back from net revenue (flow) to MRR (stock)
const netRevenue = paymentData?.netRevenue ?? stats.mrr;
```

MRR is a stock metric (recurring revenue rate). Net revenue is a flow metric (cash collected in a period). When payment data is unavailable, showing MRR as "net revenue" creates confusion.

**Fix:** When a metric is unavailable, show "unavailable" or `--`, never fall back to a different metric type.

### 6. Coercing Unknown to Zero

```typescript
// WRONG — provider API failed, but dashboard shows $0
const payoutBalance = stripeBalance ?? 0;
```

Showing `$0` when the real answer is "we couldn't reach Stripe" creates false certainty. An operator might see `$0 available` and think there's a billing emergency when it's just a transient API failure.

**Fix:** Make the value nullable. Render `--` or "unavailable" in the UI, never `$0`.

---

## Stripe-Specific Provider Truth

### MRR Must Be Quantity-Aware and Interval-Normalized

```typescript
// WRONG — flat unit price, ignores quantity and annual plans
const mrr = item.price.unit_amount / 100;

// RIGHT — accounts for seats AND normalizes annual to monthly
const intervalFactor = item.price.recurring?.interval === 'year' ? 1/12 : 1;
const mrr = (item.price.unit_amount * (item.quantity ?? 1) * intervalFactor) / 100;
```

### Scheduled Cancellation Tracking

Subscriptions with `cancel_at_period_end = true` or a future `cancel_at` date are still "active" but will churn at period end. Track their total MRR separately as "scheduled cancellation exposure" — this is revenue at risk.

```typescript
const scheduledCancellationMrr = subscriptions
  .filter(s => s.cancel_at_period_end || (s.cancel_at && s.cancel_at > Date.now()))
  .reduce((sum, s) => sum + s.mrr, 0);
```

### Team vs. Individual Detection via Metadata

Use subscription metadata to distinguish business types:
```typescript
function isTeamSubscription(sub: Stripe.Subscription): boolean {
  return sub.metadata?.type === 'team' || !!sub.metadata?.org_id
    || KNOWN_TEAM_PRICE_IDS.includes(sub.items.data[0]?.price?.id);
}
```

Store `type` and `org_id` in metadata at creation time. Fall back to price ID matching for legacy subscriptions.

### Team/Org Subscriptions: Multiply `unit_amount * quantity`

```typescript
// WRONG — ignores seat count
const lineItemMrr = item.price.unit_amount / 100;

// RIGHT — accounts for team seats
const lineItemMrr = (item.price.unit_amount * (item.quantity ?? 1)) / 100;
```

A 5-seat team subscription at $100/seat is $500 MRR, not $100.

### Nested Invoice Subscription ID

Modern Stripe API versions store the subscription ID in a nested path:

```typescript
// Check both locations — Stripe API versions differ
function getInvoiceSubscriptionId(invoice: Stripe.Invoice): string | null {
  // Legacy: top-level field
  if (typeof invoice.subscription === 'string') return invoice.subscription;

  // Modern: nested in line items
  const lineItem = invoice.lines?.data?.[0];
  const nested = lineItem?.parent?.subscription_item_details?.subscription;
  if (typeof nested === 'string') return nested;

  return null;
}
```

If you only check the top-level field, modern Stripe payloads silently fail to resolve the subscription, and the event gets marked as "processed" with `user_id = NULL`.

---

## PayPal-Specific Provider Truth

### Missing `plan_id` in Subscription List API

PayPal's subscription list API (`GET /v1/billing/subscriptions`) often omits `plan_id` for live subscriptions. If your MRR calculation depends on `plan_id` to look up pricing, subscriptions without it land in "uncategorized" with `$0` MRR.

**Fix:** When `plan_id` is missing, hydrate from the per-subscription detail endpoint (`GET /v1/billing/subscriptions/{id}`). If plan metadata is still absent, fall back to the last billed amount.

### Deprecated `auto_renewal` Field

PayPal's `auto_renewal` field is deprecated. It only indicates whether billing continues after finite billing cycles, NOT whether a subscription is scheduled to cancel at period end. If you use `auto_renewal: false` to infer scheduled cancellation, every PayPal subscriber gets falsely flagged.

**Fix:** Never use `auto_renewal` for cancellation inference. Use explicit cancellation status from the subscription record.

### Provider "Configured" Check

Both `PAYPAL_CLIENT_ID` and `PAYPAL_CLIENT_SECRET` are required for PayPal to function. Checking only `PAYPAL_CLIENT_ID` makes the system think PayPal is configured when it's actually broken, suppressing real operator warnings.

**Fix:** Require ALL necessary environment variables for each provider:
- Stripe: `STRIPE_SECRET_KEY` + `STRIPE_WEBHOOK_SECRET`
- PayPal: `PAYPAL_CLIENT_ID` + `PAYPAL_CLIENT_SECRET`
- GA4: `GA4_PROPERTY_ID` + `GA4_CLIENT_EMAIL` + `GA4_PRIVATE_KEY`

---

## Provider-Authoritative Reconciliation

Your reconciliation job must list subscriptions FROM the provider first, then reconcile local state against that list.

```
WRONG (DB-led):
  For each subscription in our DB:
    Check if it exists in the provider
    → Subscriptions that exist in the provider but not in our DB are invisible

RIGHT (Provider-led):
  List all subscriptions from Stripe API / PayPal API
  For each provider subscription:
    Does it exist in our DB? If not → flag as drift
    Does our DB status match provider status? If not → reconcile
  For each DB subscription not seen in provider listing:
    Flag as orphaned
```

### Replay Must Match Live Handler

After fixing a live webhook handler (e.g., "refresh active subscriptions on PayPal renewal"), the reconciliation replay path must also be updated. Otherwise, the reconciliation job replays events using the old broken logic, and the fix is incomplete.

**Rule:** Every change to a live webhook handler must be mirrored in the reconciliation replay path. Test both paths.

---

## Projections Must Use Provider-Authoritative Inputs

Every financial projection function must take its inputs from the canonical MRR snapshot:

| Function | Wrong Input | Right Input |
|----------|-------------|-------------|
| `calculateBreakEven()` | `COUNT(active subs) * $20` | `snapshot.totalMrr` |
| `calculateLTV()` | `$20 / churnRate` | `snapshot.totalMrr / snapshot.totalPaidAccounts / churnRate` |
| `calculateRunway()` | `activeSubs * $20 - costs` | `snapshot.totalMrr - costs` |
| `runScenario()` | `subscribers * $20` | `snapshot.totalMrr` |
| Monte Carlo | `$20 per subscriber` | `snapshot.totalMrr / snapshot.totalPaidAccounts` (actual ARPA) |

If any projection function hardcodes a price or counts raw subscription rows, it will produce wrong results for any subscription mix that includes teams, orgs, or non-standard plans.

---

## Subscription Provider Filtering

When counting paid subscribers, always filter by `provider IN ('stripe', 'paypal')` to exclude gratis/test/manually-provisioned subscriptions:

```typescript
const PAID_SUBSCRIPTION_PROVIDERS = ['stripe', 'paypal'] as const;

const paidSubs = await db.select().from(subscriptions)
  .where(and(
    inArray(subscriptions.provider, PAID_SUBSCRIPTION_PROVIDERS),
    eq(subscriptions.status, 'active'),
    excludeTestUsers()
  ));
```

Never use `status = 'active'` alone as a proxy for "paying customer." A subscription can be `active` with a `manual` or `gratis` provider.

---

## Date Boundary Hardening

All time-windowed analytics queries must have explicit start AND end bounds:

```sql
-- WRONG — no upper bound, can include future-dated records
WHERE created_at >= $thirtyDaysAgo

-- RIGHT — explicit bounds, midnight-aligned
WHERE created_at >= $thirtyDaysAgoMidnightUTC
  AND created_at <= $nowUTC
```

Always normalize date boundaries to midnight UTC (`setUTCHours(0, 0, 0, 0)`) to prevent partial-day double-counting.

---

## MRR History Reconstruction via Delta Inversion

When you have current-state truth but no historical snapshots, reconstruct approximate MRR history by inverting daily deltas:

```typescript
// Walk backwards from today's known MRR
let mrr = currentMrr;
for (let day = today; day >= startDate; day--) {
  const newMrr = sumNewSubscriptionsOn(day);
  const churnedMrr = sumCancellationsOn(day);
  history.unshift({ date: day, mrr });
  mrr = mrr - newMrr + churnedMrr; // Invert: undo today's changes to get yesterday
}
```

This is far more useful than flat-line placeholders or hardcoded sparkline data.

---

## Refund: Multi-Table Access Revocation

When subscription state is split across a `users` table (quick-access `subscription_status`) and a `subscriptions` table (canonical billing data), refund processing must update both atomically:

```typescript
await db.transaction(async (tx) => {
  // 1. Revoke subscription record
  await tx.update(subscriptions).set({
    status: 'none',
    cancelledAt: new Date(),
    currentPeriodEnd: new Date(), // Immediate, not period end
  }).where(eq(subscriptions.id, subId));

  // 2. Revoke user-level flag
  await tx.update(users).set({
    subscriptionStatus: 'none',
  }).where(eq(users.id, userId));
});
```

Updating only one table creates a state where the user appears subscribed in one view and unsubscribed in another. For refunds specifically, `currentPeriodEnd` must be set to NOW (immediate revocation), not left at the original period end.

### `cancel_at` vs Immediate Cancellation

A Stripe subscription can have `cancel_at` set to a future date (scheduled cancellation at period end) yet still be `status: "active"`. For a refund, you must call `DELETE /v1/subscriptions/{id}` (immediate cancel), not rely on the existing `cancel_at` — the subscription would continue granting access until period end otherwise.

---

## ORM Type Coercion (Drizzle/TypeORM/Prisma)

**`sql<number>` type annotations are TypeScript-only and do NOT coerce at runtime.** Postgres returns raw strings for aggregates:
- `COUNT(*)` returns `"140"` (string, not number)
- `AVG()` returns `"4.2"` (string, not number)
- `MAX(timestamp)` returns `"2026-03-25 05:01:14.533+00"` (string, not Date)

Using `+` on an uncoerced "number" string does silent string concatenation (`"4.2" + 1` becomes `"4.21"`).

**Fix:** Always apply explicit coercion:
- Add `::int` or `::numeric` to SQL aggregates
- Use runtime coercion helpers (`Number()`, `new Date()`) on query results
- In test mocks, use raw Postgres string values, not typed JavaScript objects (to catch coercion bugs)
