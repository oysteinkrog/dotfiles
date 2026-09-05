# Bundle B100 — Analytics & Reporting

> **Where this comes from.** § 55–§ 64 of the source guide.

The reporting backend is what turns billing data into business decisions. The patterns here are about *honesty under partial outage*: never lie with a stale number, always show provenance, exclude noise (test fixtures, replacement subs that aren't real churn), single-flight cache to prevent stampedes, and forecast with explicit uncertainty bands.

---

## MRR snapshot — multi-layer cache + provenance — § 55

```ts
// src/lib/services/financial-projections.ts
export interface ProvenancedValue<T> {
  value: T | null;
  provenance: 'live' | 'fallback' | 'unavailable';
  computedAt: Date | null;
  cachedUntil: Date | null;
  staleness?: 'fresh' | 'soft_expired' | 'hard_expired';
}

export async function getCurrentMrrSnapshot(opts?: { forceRefresh?: boolean }): Promise<ProvenancedValue<MrrSnapshot>> {
  const cacheKey = 'mrr:current';
  const ttl = 5 * 60 * 1000;  // 5 minutes

  if (!opts?.forceRefresh) {
    const cached = await redis.getJson<MrrSnapshotCacheEntry>(cacheKey);
    if (cached && Date.now() - cached.computedAt < ttl) {
      return { value: cached.snapshot, provenance: 'live', computedAt: new Date(cached.computedAt), cachedUntil: new Date(cached.computedAt + ttl), staleness: 'fresh' };
    }
  }

  // Compute fresh under single-flight (§ 57)
  return await singleFlight(cacheKey, async () => {
    try {
      const snapshot = await computeMrrSnapshot();
      await redis.setJson(cacheKey, { snapshot, computedAt: Date.now() }, { ex: ttl / 1000 });
      return { value: snapshot, provenance: 'live', computedAt: new Date(), cachedUntil: new Date(Date.now() + ttl), staleness: 'fresh' };
    } catch (err) {
      // Fall back to last-known-good if available
      const lastGood = await redis.getJson<MrrSnapshotCacheEntry>(cacheKey);
      if (lastGood) {
        return { value: lastGood.snapshot, provenance: 'fallback', computedAt: new Date(lastGood.computedAt), cachedUntil: null, staleness: 'soft_expired' };
      }
      return { value: null, provenance: 'unavailable', computedAt: null, cachedUntil: null };
    }
  });
}
```

### How the renderer uses provenance

```tsx
function MrrCard() {
  const { data } = useSwr('/api/admin/mrr', getCurrentMrrSnapshotJson);
  if (!data || data.provenance === 'unavailable') {
    return <div className="text-amber-600">MRR data unavailable. <RefreshButton /></div>;
  }
  return (
    <div>
      <div className="text-3xl">${data.value.totalMrr.toFixed(2)}</div>
      <div className="text-sm text-muted">
        {data.provenance === 'live' ? '✓ Live' : '⚠ Fallback (last update ' + relativeTime(data.computedAt) + ')'}
      </div>
    </div>
  );
}
```

**The renderer NEVER renders `unavailable` as a number.** This is the Polish Bar dimension.

---

## Canonical-only MRR — exclude fallback providers — § 56

If your project has a "fallback" provider (e.g., gratis comp accounts, manual invoicing, free trials), exclude them from authoritative MRR totals. They're not paying customers in the financial sense.

```ts
async function computeMrrSnapshot(): Promise<MrrSnapshot> {
  const subs = await db.query.subscriptions.findMany({
    where: and(
      inArray(subscriptions.status, ['active', 'past_due']),
      // ⚠ EXCLUDE gratis from authoritative MRR
      ne(subscriptions.provider, 'gratis'),
    ),
    with: { user: true },
  });

  // Then exclude analytics-excluded users
  const billable = subs.filter(s => !analyticsExclusions.isExcluded(s.user.email));

  // Sum monthly amounts (handle yearly subs as monthly equivalent)
  const totalMrr = billable.reduce((sum, s) => sum + getMonthlyAmount(s), 0);

  return {
    totalMrr,
    activeCount: billable.filter(s => s.status === 'active').length,
    pastDueCount: billable.filter(s => s.status === 'past_due').length,
    byProvider: groupBy(billable, 'provider').map(([p, subs]) => ({ provider: p, mrr: subs.reduce(...) })),
  };
}
```

---

## Single-flight cache stampede protection — § 57

When the cache expires, 1000 concurrent reads all see the cache miss and all try to compute. Without single-flight, you've ddosed your own DB.

```ts
// src/lib/cache/single-flight.ts
const inflight = new Map<string, Promise<any>>();

export async function singleFlight<T>(key: string, fn: () => Promise<T>): Promise<T> {
  if (inflight.has(key)) return inflight.get(key)!;

  const promise = fn().finally(() => {
    setTimeout(() => inflight.delete(key), 1000);  // brief hold to absorb the stampede tail
  });
  inflight.set(key, promise);
  return promise;
}
```

For multi-isolate (Vercel serverless) deployments where the in-process map doesn't help across isolates, use Redis SETNX as a distributed single-flight:

```ts
const lockKey = `single_flight_lock:${key}`;
const acquired = await redis.set(lockKey, '1', { ex: 30, nx: true });
if (!acquired) {
  // Another isolate is computing; wait briefly then re-read cache
  for (let i = 0; i < 30; i++) {
    await sleep(100);
    const cached = await redis.getJson<T>(key);
    if (cached) return cached;
  }
  // Fall through and compute ourselves; the lock-holder must have crashed
}
```

---

## Canonical churn timestamp — § 58

The naive churn calc is `WHERE status = 'cancelled' AND updated_at IN <last 30 days>`. Wrong because `updated_at` gets bumped by reconciliation, replacement subs, etc.

The canonical churn timestamp:

```sql
COALESCE(
  cancelled_at,
  subscription_status_changed_at,  -- on the orgs/users denorm
  updated_at
) as canonical_cancellation_time
```

And exclude **replacement coverage** — subs that were "cancelled" because the user got a better one (e.g., individual → team upgrade):

```ts
async function getChurnedInPeriod(start: Date, end: Date) {
  const churned = await db.query.subscriptions.findMany({
    where: and(
      eq(subscriptions.status, 'cancelled'),
      gte(subscriptions.cancelledAt, start),
      lt(subscriptions.cancelledAt, end),
    ),
    with: { user: { with: { organizationMemberships: true } } },
  });

  return churned.filter(s => {
    // Exclude if user joined a team plan (covered, not churned)
    const hasTeamCoverage = s.user.organizationMemberships.some(m => m.organization.subscriptionStatus === 'active');
    if (hasTeamCoverage) return false;
    // Exclude if user replaced this with a new sub (provider switch)
    const hasReplacementSub = /* check for sub created shortly after cancel */;
    if (hasReplacementSub) return false;
    return true;
  });
}
```

---

## Payment fees — blended effective rate — § 59

Stripe and PayPal charge differently (Stripe ~2.9% + 30¢; PayPal ~3.49% + fixed). For accurate revenue reporting, compute the blended effective rate from real settlement data.

```ts
async function computeBlendedFeeRate(period: { start: Date; end: Date }) {
  // Stripe: Balance Transactions API
  const stripeBalanceTxns = await stripe.balanceTransactions.list({
    type: 'charge',
    created: { gte: Math.floor(period.start.getTime() / 1000), lt: Math.floor(period.end.getTime() / 1000) },
    limit: 100,
    // ... paginate
  });
  const stripeFees = stripeBalanceTxns.data.reduce((sum, t) => sum + t.fee, 0);
  const stripeGross = stripeBalanceTxns.data.reduce((sum, t) => sum + t.amount, 0);

  // PayPal: Transaction Search API
  const paypalTxns = await fetchPayPalTransactionsForPeriod(period);
  const paypalFees = paypalTxns.reduce((sum, t) => sum + t.fee, 0);
  const paypalGross = paypalTxns.reduce((sum, t) => sum + t.amount, 0);

  const totalGross = stripeGross + paypalGross;
  const totalFees = stripeFees + paypalFees;
  return {
    blendedRate: totalFees / totalGross,
    stripeRate: stripeFees / stripeGross,
    paypalRate: paypalFees / paypalGross,
    period,
    provenance: { stripeTxnCount: stripeBalanceTxns.data.length, paypalTxnCount: paypalTxns.length },
  };
}
```

Persist the result to a `payment_fees` snapshot table; recompute monthly. Don't compute on every dashboard load.

---

## Net revenue + fee telemetry snapshot — § 60

Snapshot table:

```sql
CREATE TABLE financial_snapshots (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_start  date NOT NULL,
  period_end    date NOT NULL,
  gross_revenue numeric NOT NULL,
  total_fees    numeric NOT NULL,
  net_revenue   numeric NOT NULL,
  blended_fee_rate numeric NOT NULL,
  provider_breakdown jsonb NOT NULL,
  computed_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (period_start, period_end)
);
```

Snapshots are immutable once written; corrections write a new snapshot with the correction reason in `provider_breakdown.metadata`.

---

## Customer health scoring — composite 0-100 — § 61

```ts
async function computeCustomerHealth(userId: string): Promise<CustomerHealthScore> {
  const user = await db.query.users.findFirst({ where: eq(users.id, userId), with: { subscriptions: true, organizationMemberships: true } });

  const components = {
    payment_history: scorePaymentHistory(user.subscriptions),       // 0-30
    feature_engagement: await scoreFeatureUsage(userId),             // 0-30
    tenure: scoreTenure(user.createdAt),                            // 0-15
    provider_signals: await scoreProviderSignals(user.subscriptions),// 0-15
    support_signals: await scoreSupportTickets(userId),              // 0-10
  };
  const total = Object.values(components).reduce((s, v) => s + v, 0);

  return {
    score: total,
    band: total >= 80 ? 'healthy' : total >= 60 ? 'at-risk' : total >= 40 ? 'concerning' : 'critical',
    components,
    provenance: 'live',
    computedAt: new Date(),
  };
}
```

Recompute weekly; persist for trend analysis.

---

## Behavioral forecasting — driver-attributed churn probability — § 62

Per-user churn probability with attribution:

```ts
export interface ChurnPrediction {
  userId: string;
  churnProbability: number;            // 0-1
  daysUntilLikelyChurn: number | null; // null if low probability
  drivers: Array<{ driver: string; weight: number; explanation: string }>;
  recommendedIntervention: 'none' | 'check_in' | 'discount' | 'concierge';
  provenance: ProvenancedValue<unknown>['provenance'];
}
```

Drivers (each contributes a weight):
- `payment_failure_recent` — past 30 days saw a failed payment
- `feature_usage_decline` — usage dropped > 50% vs baseline
- `support_ticket_recent` — opened a ticket in past 14 days
- `card_expiring_no_update` — card expires in < 30 days, not updated
- `team_plan_underutilized` — team plan with > 50% of seats unused
- `tenure_critical_milestone` — approaching the typical churn point for their tenure

The point of attribution is to drive *intervention*: a `payment_failure_recent` driver suggests the dunning ladder; an `underutilized_team_plan` driver suggests a downgrade-conversation.

---

## Monte Carlo runway projection — § 63

Project cash runway under uncertainty:

```ts
export async function monteCarloRunway(opts: {
  startingCash: number;
  monthlyBurn: number;
  iterations?: number;       // default 10000
}): Promise<RunwayProjection> {
  // Pull recent actuals to seed the distribution
  const lastSnapshots = await db.query.financialSnapshots.findMany({
    where: gte(financialSnapshots.periodStart, addMonths(new Date(), -6)),
    orderBy: asc(financialSnapshots.periodStart),
  });
  const monthlyNetRevenues = lastSnapshots.map(s => Number(s.netRevenue));
  const meanRevenue = mean(monthlyNetRevenues);
  const stddevRevenue = stddev(monthlyNetRevenues);

  const iterations = opts.iterations ?? 10000;
  const monthsToBankruptcy: number[] = [];

  for (let i = 0; i < iterations; i++) {
    let cash = opts.startingCash;
    let months = 0;
    while (cash > 0 && months < 36) {
      const sampledRevenue = Math.max(0, sampleNormal(meanRevenue, stddevRevenue));
      cash += sampledRevenue - opts.monthlyBurn;
      months++;
    }
    monthsToBankruptcy.push(months);
  }

  return {
    p10: percentile(monthsToBankruptcy, 10),
    p50: percentile(monthsToBankruptcy, 50),
    p90: percentile(monthsToBankruptcy, 90),
    iterations,
    seed: { meanRevenue, stddevRevenue, sampleCount: monthlyNetRevenues.length },
    computedAt: new Date(),
    provenance: 'live',
  };
}
```

Return p10/p50/p90 percentiles, NOT a single number. "Runway is 8.7 months" is dishonest; "p10 = 4 months, p50 = 9 months, p90 = 18 months" tells the operator the actual uncertainty.

---

## Reconciliation freshness telemetry — § 64 / MOR-22B

Track HOW FRESH the reconciliation pipeline is. Stale freshness means the live numbers are derived from increasingly stale snapshots.

```ts
export async function reconciliationFreshnessMetrics(): Promise<FreshnessMetrics> {
  const lastReconciled = await db.query.paymentEvents.findFirst({
    where: not(isNull(paymentEvents.reconciledAt)),
    orderBy: desc(paymentEvents.reconciledAt),
  });
  const lastIntegrityAudit = await db.query.complianceEvents.findFirst({
    where: eq(complianceEvents.eventType, 'integrity_audit_completed'),
    orderBy: desc(complianceEvents.createdAt),
  });
  const lastProviderSweep = await db.query.complianceEvents.findFirst({
    where: eq(complianceEvents.eventType, 'provider_reconciliation_completed'),
    orderBy: desc(complianceEvents.createdAt),
  });

  return {
    last_reconciliation_at: lastReconciled?.reconciledAt,
    last_reconciliation_lag_seconds: lastReconciled ? (Date.now() - lastReconciled.reconciledAt.getTime()) / 1000 : null,
    last_integrity_audit_at: lastIntegrityAudit?.createdAt,
    last_provider_sweep_at: lastProviderSweep?.createdAt,
    is_fresh: this.isFresh({ last_reconciliation_lag_seconds, last_integrity_audit_at, last_provider_sweep_at }),
  };
}
```

Expose to operators as a chip in the admin UI: green when fresh, amber when soft-stale (e.g., reconciliation > 30min), red when hard-stale (> 4h).

---

## Polish Bar checks for B100

- [ ] `getCurrentMrrSnapshot` returns `ProvenancedValue<MrrSnapshot>` with `provenance` and `computedAt`.
- [ ] Renderer never displays `provenance === 'unavailable'` as a number.
- [ ] MRR computation excludes `gratis` provider AND analytics-excluded users.
- [ ] `singleFlight` wraps every cache-recompute path.
- [ ] Distributed single-flight via Redis SETNX for multi-isolate deployments.
- [ ] Canonical churn timestamp uses `COALESCE(cancelled_at, subscription_status_changed_at, updated_at)`.
- [ ] Replacement-coverage exclusion in churn calc.
- [ ] Payment fees computed from real settlement data (Balance Transactions / Transaction Search).
- [ ] `financial_snapshots` table; immutable; corrections via new snapshot.
- [ ] Customer health scoring: composite of 4-6 components; tracked weekly.
- [ ] Forecasting: per-user with driver attribution; recommended intervention.
- [ ] Monte Carlo: p10/p50/p90, not single number; seeded from recent actuals.
- [ ] Reconciliation freshness exposed in admin UI with green/amber/red chip.
- [ ] Regression test: MRR snapshot returns provenance=fallback when fresh compute fails.
- [ ] Regression test: churn calc excludes replacement coverage.
- [ ] Regression test: single-flight collapses concurrent reads to one compute.

---

## Common B100 mistakes

- **Cache returns stale value silently on compute failure.** Renderer shows confidently-stale number. Wrap in provenance.
- **`unavailable` rendered as `$0`.** Looks like the company died. Show the chip; never the zero.
- **`gratis` subs included in MRR.** Inflates the number; investor decisions on bad data.
- **Test users in MRR.** Same.
- **Single-flight in-process only on Vercel.** Each isolate stampedes independently. Use Redis.
- **Churn includes replacement coverage.** Overstates churn; obscures the real signal.
- **Fees computed from sub price.** Wrong; some plans have promotions, currency conversion, etc. Use settlement data.
- **Health score is a single number with no attribution.** Operator can't act on "user is at-risk" without knowing why.
- **Forecasting returns single point estimate.** Hides uncertainty. Use percentiles.
- **Snapshot computed on every dashboard load.** N+1 across providers; rate-limited; slow. Snapshot monthly + cache.
