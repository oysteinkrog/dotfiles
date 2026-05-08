# Anti-Patterns & Failure Modes

> Every anti-pattern here was discovered the hard way. Learn from the mistakes so you don't repeat them.

## Data Integrity Anti-Patterns

### 1. Calculating Fees from Mutable Subscriptions Table

**Wrong:**
```typescript
// Counts current subscriptions, applies fee rate
const subs = await db.select().from(subscriptions).where(eq(status, 'active'));
const fees = subs.length * estimatedFeePerTransaction;
```

**Why it fails:** The subscriptions table tracks *current state*. Users who subscribed and cancelled within the period are invisible. Actual payment amounts may differ from subscription price (prorations, refunds).

**Right:** Query the immutable `paymentEvents` ledger for `invoice.payment_succeeded` and `PAYMENT.SALE.COMPLETED` events. These record what *actually happened*.

### 2. Including Test Data in Analytics

**Wrong:** Computing MRR, churn, or conversion rates without filtering test accounts.

**Why it fails:** Even one test account that creates/cancels subscriptions repeatedly will massively inflate churn rate and skew MRR.

**Right:** Filter at EVERY query:
- Individual: `email NOT LIKE '%@test.yourdomain.com'`
- Organizations: `name NOT LIKE 'E2E Team%'`
- Subscriptions: `external_id NOT LIKE 'sub_test_%'`

### 3. Treating past_due as Churned

**Wrong:**
```typescript
const churned = await db.select().from(subscriptions)
  .where(or(eq(status, 'cancelled'), eq(status, 'past_due')));
```

**Why it fails:** `past_due` means the payment failed but the subscriber is in a grace period. Many will recover. Counting them as churned inflates your churn rate and triggers false alarms.

**Right:** Count `past_due` as active for MRR purposes. Monitor separately as a payment stress signal in the behavioral scoring model.

### 4. Not Handling Event Ordering

**Wrong:** Blindly applying webhook updates to subscription status.

**Why it fails:** Webhooks arrive out of order. A `subscription.deleted` event may arrive before a `subscription.updated` event from the same second. Applying them in arrival order produces incorrect state.

**Right:** Use a `last_event_at` column and only apply updates where the new event is newer:
```sql
UPDATE subscriptions SET status = $1, last_event_at = $2
WHERE id = $3 AND (last_event_at IS NULL OR last_event_at < $2);
```

---

## Modeling Anti-Patterns

### 5. Single-Point Revenue Projections

**Wrong:** "Your MRR will be $5,000 in 12 months."

**Why it fails:** Compound growth/decay amplifies small input errors. A 1% error in churn rate becomes 12% at month 12. The single number gives false confidence.

**Right:** Monte Carlo simulation with P10/P50/P90 ranges. "Your MRR will likely be between $3,200 and $7,100, with $4,800 being the most likely outcome."

### 6. Using ML/AI for Insight Generation

**Wrong:** Training a neural network to detect revenue anomalies.

**Why it fails:** For early-stage SaaS (< 10,000 subscribers), you don't have enough data for ML. Rule-based heuristics + Z-score statistics are:
- Easier to debug ("why did it alert?")
- Faster to implement
- More transparent to stakeholders
- Sufficient for the data volumes involved

**Right:** Start with deterministic rules. Graduate to ML only when you have 12+ months of data AND the rules are demonstrably insufficient.

### 7. Ignoring Contribution Margin in Break-Even

**Wrong:** `breakEvenSubs = fixedCosts / subscriptionPrice`

**Why it fails:** Each subscriber costs you payment processing fees. If your subscription is $5/month and fees are $0.79/transaction, your contribution margin is only $4.21. Break-even requires more subscribers than the naive calculation suggests.

**Right:** `breakEvenSubs = fixedCosts / (subscriptionPrice - avgPaymentFee)`

And check: if `contributionMargin <= 0`, break-even is **mathematically unreachable** through subscriber growth alone. Surface this as a critical insight.

### 8. Predicting Churn from Billing Events Only

**Wrong:** "User's payment failed twice → high churn risk."

**Why it fails:** Payment failure is a lagging indicator. By the time payments fail, the user may have already mentally churned weeks ago. You're detecting involuntary churn but missing voluntary churn entirely.

**Right:** Behavioral signals predict churn 2-4 weeks earlier:
- Days since last activity (recency)
- Declining usage trend (engagement)
- Narrow feature adoption (breadth)
- Never activated (activation)

Payment signals are one of FIVE categories in the behavioral model, not the only one.

---

## Architecture Anti-Patterns

### 9. Failing the Whole Dashboard on One Bad Query

**Wrong:**
```typescript
const [mrr, churn, fees, health] = await Promise.all([
  calculateMrr(),
  calculateChurn(),
  calculateFees(),
  calculateHealth(),
]);
```

**Why it fails:** If ANY of these throws, the entire `Promise.all` rejects. Admin sees a blank page.

**Right:**
```typescript
const [mrr, churn, fees, health] = await Promise.allSettled([...]);
// Each metric is independent — show what you have, mark what failed
```

### 10. Aggressive Caching of Subscriber Counts

**Wrong:** Caching MRR for 1 hour to reduce DB load.

**Why it fails:** If a subscriber joins or churns, the admin dashboard shows stale MRR for up to an hour. For an early-stage SaaS where each subscriber matters, this creates confusion ("I just signed up a user but MRR didn't change").

**Right:** 60-second TTL for the summary widget. The DB can handle one aggregation query per minute. Use TanStack Query's `staleTime` to prevent excessive client-side refetching.

### 11. Not Rate-Limiting Compute-Heavy Endpoints

**Wrong:** Letting admins run Monte Carlo simulations with 10,000 iterations without throttling.

**Why it fails:** Monte Carlo is CPU-bound with no I/O yields. It blocks the Node.js event loop for hundreds of milliseconds. Multiple concurrent requests = server brownout.

**Right:** Rate-limit to 1 request per 5 seconds per admin. Cap iterations at 10,000. Cap months at 120.

### 12. Storing Analytics in the Same DB Transaction as Webhooks

**Wrong:**
```typescript
await db.transaction(async (tx) => {
  await tx.insert(paymentEvents).values(event);
  await tx.update(subscriptions).set({ status: 'active' });
  await updateDailyAnalytics(tx);  // Expensive aggregation
});
```

**Why it fails:** The analytics computation holds the transaction open. If it's slow, the webhook handler times out. Stripe/PayPal retry. You get duplicate processing attempts.

**Right:** Insert the event and update subscription status in one fast transaction. Run analytics as a separate post-processing step (or via cron).

---

## Behavioral Scoring Anti-Patterns

### 13. Scoring Users with No Usage Data

**Wrong:** Computing health scores for users who signed up but have zero usage events.

**Why it fails:** A user who signed up yesterday with no events is in a completely different state than a user who's been subscribed for 30 days with no events. The former needs activation nudging; the latter is a critical churn risk.

**Right:** Gate health scoring on `subscriptionAgeDays > 3`. For users < 3 days old, use a separate "activation tracking" path instead of the full behavioral model.

### 14. Equal Weighting of All Behavioral Factors

**Wrong:** Treating a payment failure the same as a slightly below-average engagement day.

**Why it fails:** Not all signals are equal predictors. Recency of last activity is the strongest single predictor of churn. Payment failures are a strong secondary signal. Event volume is useful but noisy.

**Right:** Use the weighted driver model with empirically calibrated weights. The 19-driver model assigns impact weights from -0.2 (protective) to +0.35 (high risk) based on predictive power.

### 15. Not Accounting for Usage Trend Direction

**Wrong:** "User had 10 events in the last 30 days → medium engagement."

**Why it fails:** 10 events that were all in the first week (declining) is very different from 10 events that were all in the last week (improving). Same number, opposite trajectory.

**Right:** Compare `events14` vs `eventsPrev14` (usage trend ratio). A ratio < 0.5 = declining, > 1.5 = improving. This directional signal is more predictive than absolute volume.

---

## Dashboard Anti-Patterns

### 16. Showing Raw Numbers Without Context

**Wrong:** "MRR: $1,200"

**Why it fails:** Is $1,200 good or bad? Up or down? The number alone doesn't inform decisions.

**Right:** "MRR: $1,200 (+8.1% MoM)" with a sparkline showing the 30-day trend and a trend indicator (green up arrow).

### 17. Alert Fatigue from Non-Dismissible Insights

**Wrong:** Showing the same "Conversion rate is low" insight every page load forever.

**Why it fails:** Admin learns to ignore all insights. Critical alerts get buried.

**Right:** Implement dismissal (7-day snooze). Track dismissals in DB with expiry. Auto-expire stale insights. Use severity levels so critical alerts stand out.

### 18. Monte Carlo Fan Charts Without Explanation

**Wrong:** Showing P10/P50/P90 bands without explaining what they mean.

**Why it fails:** Most people don't intuitively understand probability distributions. They'll focus on P90 (best case) and be disappointed.

**Right:** Label bands clearly: "Pessimistic (10th percentile)", "Most likely (median)", "Optimistic (90th percentile)". Add a survival probability number: "78% chance of surviving 12 months."

---

## Provider-Authoritative Anti-Patterns

> These patterns were discovered in production audits where admin analytics showed wrong revenue, wrong subscriber counts, and wrong churn rates — all because the code treated local database state as truth instead of the payment provider.

### 19. Hardcoding Subscription Price in MRR Calculations

**Wrong:**
```typescript
const mrr = activeSubscribers * 20;  // Assumes $20/mo flat
```

**Why it fails:** Breaks for team/org subscriptions at different price points, any price change, prorated amounts, or multi-plan setups. Monte Carlo simulations that hardcode `$20` per subscriber produce garbage projections for any non-homogeneous subscriber base.

**Right:** Derive MRR from the canonical provider-authoritative snapshot. Use actual ARPA (Average Revenue Per Account) from live provider data:
```typescript
const arpa = snapshot.totalMrr / snapshot.totalPaidAccounts;
```

### 20. Ignoring Stripe Line-Item Quantities for Team Subscriptions

**Wrong:**
```typescript
const lineItemMrr = item.price.unit_amount / 100;
```

**Why it fails:** A 5-seat team subscription at $100/seat is $500 MRR, not $100. Ignoring `quantity` systematically undercounts team/org revenue.

**Right:**
```typescript
const lineItemMrr = (item.price.unit_amount * (item.quantity ?? 1)) / 100;
```

### 21. Using Stale Denormalized `users.subscriptionStatus` as Billing Truth

**Wrong:**
```typescript
const paidUsers = await db.select().from(users)
  .where(eq(users.subscriptionStatus, 'active'));
```

**Why it fails:** This denormalized field drifts from reality due to: webhook delivery failures, manual DB fixes that don't update subscriptions, org-based access not propagating to the user row, and reconciliation passes resetting it to `none`. Found in production: 10+ admin surfaces using this field produced 3 different subscriber counts.

**Right:** Use paid-access entitlement semantics — check the `subscriptions` table joined with provider status, or consume the canonical MRR snapshot.

### 22. Record-First-Enrich-Later Without Ensuring Enrichment Completes

**Wrong:**
```typescript
await recordWebhookEvent(event);  // Stores raw event with user_id = NULL
// ... later, enrichment silently fails to resolve user
await markAsProcessed(event.id);  // Marked "done" with user_id still NULL
```

**Why it fails:** The event is stored but never linked to a user. It gets marked as "processed" despite enrichment failure. Over time, you accumulate hundreds of unlinked payment events (found: 433 unlinked vs 296 linked in 30 days). Analytics that rely on `user_id` linkage silently undercount.

**Right:** If enrichment fails to resolve a user/subscription, either retry with backoff or flag for manual review — never silently mark as processed with `user_id = NULL` and `processed_at` set.

### 23. Stripe Invoice Subscription ID: Only Checking Top-Level Field

**Wrong:**
```typescript
const subId = invoice.subscription;  // Only works with legacy Stripe API versions
```

**Why it fails:** Modern Stripe API versions store the subscription ID under `lines.data[0].parent.subscription_item_details.subscription`. If you only check the top-level field, 100% of modern invoice events fail to resolve their subscription.

**Right:**
```typescript
function getInvoiceSubscriptionId(invoice: Stripe.Invoice): string | null {
  if (typeof invoice.subscription === 'string') return invoice.subscription;
  const nested = invoice.lines?.data?.[0]?.parent
    ?.subscription_item_details?.subscription;
  return typeof nested === 'string' ? nested : null;
}
```

### 24. PayPal: Using Deprecated `auto_renewal` for Cancellation Inference

**Wrong:**
```typescript
if (!subscription.auto_renewal) {
  markAsScheduledCancellation(subscription);
}
```

**Why it fails:** `auto_renewal` is deprecated. It indicates whether billing continues after finite cycles, NOT whether a subscription is scheduled to cancel. Every PayPal subscriber gets falsely flagged as cancelling.

**Right:** Use explicit cancellation status from the subscription record. Never use `auto_renewal`.

### 25. PayPal: Only Reactivating past_due on PAYMENT.SALE.COMPLETED

**Wrong:**
```typescript
if (subscription.status === 'past_due') {
  reactivateSubscription(subscription);
}
// Active subscriptions silently ignored — period timestamps never refreshed
```

**Why it fails:** PayPal renewal payments on already-active subscriptions don't refresh `current_period_end` or `updated_at`. Over months, subscription records' period timestamps progressively fall behind reality, creating billing-state drift.

**Right:** Refresh `current_period_end` and `updated_at` on EVERY successful payment, regardless of current subscription status.

### 26. DB-Led Reconciliation Instead of Provider-Led

**Wrong:**
```typescript
// Only checks subscriptions we already know about
for (const sub of await db.select().from(subscriptions)) {
  const providerSub = await stripe.subscriptions.retrieve(sub.externalId);
  // Subscriptions that exist in Stripe but not in our DB are invisible
}
```

**Why it fails:** Any subscription created in the provider but never recorded in your DB (webhook lost, handler crash) is completely invisible to reconciliation.

**Right:** List subscriptions FROM the provider first, then reconcile against your DB. Flag provider subscriptions not found in your DB as drift.

### 27. Reconciliation Replay Not Matching Live Handler

**Wrong:** Fixing the live webhook handler but leaving the reconciliation replay path with old logic.

**Why it fails:** The reconciliation job replays unprocessed events using the old broken handler logic. Your fix works for new events but fails for retried ones.

**Right:** Every change to a live webhook handler MUST be mirrored in the reconciliation replay path. Test both paths.

---

## Counting & Aggregation Anti-Patterns

### 28. Counting Subscription Rows Instead of Distinct Users

**Wrong:**
```typescript
const mrr = await db.select({ count: count() }).from(subscriptions)
  .where(eq(status, 'active'));
// User with two active subscription rows gets double-counted
```

**Why it fails:** Duplicate active subscription rows (data quality issue) inflate MRR. Common with multi-provider setups where a user has both Stripe and PayPal records.

**Right:** Count `DISTINCT` on user IDs:
```typescript
const mrr = await db.select({ count: countDistinct(subscriptions.userId) })
  .from(subscriptions).where(eq(status, 'active'));
```

### 29. Revenue Comparison Using Only One Event Type

**Wrong:**
```typescript
// Only counts Stripe payment_intent.succeeded, misses invoice.payment_succeeded
// Misses ALL PayPal revenue entirely
const revenue = await sumStripePaymentIntents(period);
```

**Why it fails:** Stripe renewal payments come as `invoice.payment_succeeded`, not `payment_intent.succeeded`. PayPal revenue arrives as `PAYMENT.SALE.COMPLETED`. Missing any event type systematically undercounts.

**Right:** Sum across ALL revenue-bearing event types from ALL providers:
- Stripe: `invoice.payment_succeeded`
- PayPal: `PAYMENT.SALE.COMPLETED`
- Then subtract: refunds, disputes, chargebacks

### 30. Gross Revenue Without Refund/Dispute Subtraction

**Wrong:**
```typescript
const periodRevenue = grossCharges;  // Refunds and disputes never subtracted
```

**Why it fails:** Revenue is always overstated. A customer who paid $20 and got a $20 refund shows as $20 revenue, not $0.

**Right:** Net revenue = gross charges - refunds - disputes - chargebacks. Always.

### 31. Conversion Rate Requiring Subscriptions to Still Be Active

**Wrong:**
```typescript
// Only counts currently-active subscriptions as "converted"
const converted = await db.select().from(subscriptions)
  .where(eq(status, 'active'));
```

**Why it fails:** Users who converted and later cancelled are invisible. Historical conversion rate is understated.

**Right:** Count ALL paid-provider subscription records (any status) for historical conversion metrics. Only use current status for "currently paying" metrics.

### 32. Funnel Stages Not Monotonically Decreasing

**Wrong:** Computing each funnel stage independently, allowing `retained > activated > subscribed`.

**Why it fails:** Displays impossible flows in the admin funnel visualization. Operators lose trust in the data.

**Right:** Clamp each stage: `retain = Math.min(retain, activate)`. Each funnel stage must be <= the previous stage.

### 33. Churn Query Using Inconsistent Cancellation Timestamp

**Wrong:**
```typescript
// Some queries use cancelledAt, others use COALESCE(cancelledAt, updatedAt)
const churned = await db.select().from(subscriptions)
  .where(and(eq(status, 'cancelled'), gte(cancelledAt, startDate)));
// Rows missing cancelledAt are invisible to this query
```

**Why it fails:** Not all cancellation records have `cancelledAt` populated. Using raw `cancelledAt` undercounts churn for rows where only `updatedAt` was set.

**Right:** Use `COALESCE(cancelledAt, updatedAt)` consistently across all churn queries.

---

## Silent Error Anti-Patterns

### 34. Degrading to Fake Zeros on Analytics Error

**Wrong:**
```typescript
try {
  return await computeRealMetrics();
} catch {
  return { totalInvocations: 0, skillsUsed: 0, timeSaved: 0 };
}
```

**Why it fails:** The zero payload is indistinguishable from "no activity." A SQL error, a permission failure, a schema change — all produce the same "everything is zero" response. The underlying bug is invisible indefinitely because the UI renders normally.

**Right:** Mark degraded responses so the UI can show "analytics unavailable" instead of fake zeros:
```typescript
try {
  return { ...await computeRealMetrics(), degraded: false };
} catch {
  return { totalInvocations: 0, degraded: true, error: 'analytics_unavailable' };
}
```

### 35. PayPal MRR Undercounting: Missing plan_id

**Wrong:**
```typescript
const mrr = subscriptions
  .filter(s => s.plan_id)
  .reduce((sum, s) => sum + getPlanPrice(s.plan_id), 0);
// Subscriptions without plan_id contribute $0
```

**Why it fails:** PayPal's subscription list API often omits `plan_id` for live subscriptions. Those subscriptions land in "uncategorized" at $0 MRR.

**Right:** When `plan_id` is missing, hydrate from the per-subscription detail endpoint. If plan metadata is still absent, fall back to the last billed amount.

### 36. PayPal "Configured" Check Too Permissive

**Wrong:**
```typescript
const paypalConfigured = !!process.env.PAYPAL_CLIENT_ID;
```

**Why it fails:** PayPal requires BOTH `PAYPAL_CLIENT_ID` AND `PAYPAL_CLIENT_SECRET`. Checking only one makes the system think PayPal is configured when API calls will actually fail, suppressing real operator warnings.

**Right:** Require ALL necessary env vars per provider:
```typescript
const paypalConfigured = !!(process.env.PAYPAL_CLIENT_ID && process.env.PAYPAL_CLIENT_SECRET);
const stripeConfigured = !!(process.env.STRIPE_SECRET_KEY && process.env.STRIPE_WEBHOOK_SECRET);
```
