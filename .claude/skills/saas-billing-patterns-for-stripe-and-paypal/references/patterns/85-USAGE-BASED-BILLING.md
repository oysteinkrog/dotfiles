# Bundle B85 — Usage-Based Billing

> **Where this comes from.** Cross-reference with B100 settlement ledger + B70 dunning + Stripe's metered billing docs. The source guide focuses on flat-rate subscriptions; this bundle adds the metered / usage-based dimension that many SaaS products need.

Usage-based billing (metered billing, pay-per-call, consumption-based, hybrid subscription+usage) is its own pattern family. Don't bolt it onto a flat-rate system; design for it from the start if it's the business model, or as a major feature if added later.

---

## Pattern 1 — Three usage-billing shapes

| Shape | Example | Stripe term | Complexity |
|-------|---------|-------------|------------|
| **Pure usage** | $0.001 per API call | `usage_type: 'metered'` price | Medium |
| **Tiered usage** | First 10K free, then $0.001/call up to 100K, $0.0008 thereafter | `tiers_mode: 'graduated'` or `'volume'` | High |
| **Hybrid subscription+usage** | $19/mo includes 1K calls, then $0.001/call overage | Two prices in the subscription | High |

This bundle covers all three.

---

## Pattern 2 — Schema additions

```sql
-- Usage records: every billable event the user produces
CREATE TABLE usage_records (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users(id),
  org_id          uuid REFERENCES organizations(id),
  subscription_id uuid REFERENCES subscriptions(id),
  metric          text NOT NULL,           -- 'api_call' | 'storage_gb_hour' | 'compute_seconds' | etc.
  quantity        numeric(20, 6) NOT NULL,  -- support fractional units
  unit            text NOT NULL,            -- 'calls' | 'gb_hours' | 'seconds'
  occurred_at     timestamptz NOT NULL,    -- when the user actually used it
  reported_at     timestamptz,              -- when we reported to Stripe (NULL = pending)
  stripe_usage_record_id text,              -- Stripe's response after reporting
  metadata        jsonb,                    -- e.g., endpoint name, request_id
  recorded_at     timestamptz NOT NULL DEFAULT now()
);

-- Critical indexes
CREATE INDEX usage_records_pending_idx ON usage_records (occurred_at)
  WHERE reported_at IS NULL;
CREATE INDEX usage_records_user_period_idx ON usage_records (user_id, occurred_at);
CREATE INDEX usage_records_metric_period_idx ON usage_records (metric, occurred_at);

-- Aggregated usage for fast querying (snapshot of period totals)
CREATE TABLE usage_period_aggregates (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users(id),
  subscription_id uuid REFERENCES subscriptions(id),
  metric          text NOT NULL,
  period_start    timestamptz NOT NULL,
  period_end      timestamptz NOT NULL,
  total_quantity  numeric(20, 6) NOT NULL,
  computed_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, metric, period_start)
);
```

The two-table design: raw events in `usage_records`, aggregates for fast reads.

---

## Pattern 3 — Recording usage (the write path)

The application writes a `usage_records` row whenever the user does the metered thing:

```ts
// Wherever the metered action happens (API endpoint, file upload, compute job):
await recordUsage({
  userId: user.id,
  metric: 'api_call',
  quantity: 1,
  occurredAt: new Date(),
  metadata: { endpoint: req.path, requestId: req.headers['x-request-id'] },
});

// recordUsage is fire-and-forget for performance; uses an in-process queue
// + periodic batch flush to DB. NOT a synchronous DB write per call.
```

The fire-and-forget pattern is critical: a metered API endpoint that does a synchronous DB INSERT per call adds 5-10ms per request. The buffered approach:

```ts
// src/lib/usage/buffer.ts
const buffer: UsageRecord[] = [];
const FLUSH_INTERVAL_MS = 1000;
const FLUSH_BATCH_SIZE = 1000;

export function recordUsage(record: UsageRecord) {
  buffer.push(record);
  if (buffer.length >= FLUSH_BATCH_SIZE) {
    setImmediate(flushBuffer);  // don't block
  }
}

async function flushBuffer() {
  const batch = buffer.splice(0, FLUSH_BATCH_SIZE);
  if (batch.length === 0) return;
  try {
    await db.insert(usageRecords).values(batch);
  } catch (err) {
    // Push back into buffer; retry next flush
    buffer.unshift(...batch);
    logger.error({ err, count: batch.length }, 'Usage flush failed');
  }
}

setInterval(flushBuffer, FLUSH_INTERVAL_MS);
```

For high-volume systems, replace with Kafka / Redis Streams / SQS. But the principle is the same: don't block the request path on usage tracking.

---

## Pattern 4 — Reporting usage to Stripe

Stripe's metered billing requires reporting via `subscription_items.createUsageRecord(...)`:

```ts
// /api/cron/report-usage-to-stripe (every 5 min)
async function reportUsageToStripe() {
  await acquireAdvisoryLock('report_usage_to_stripe', async () => {
    // Find pending usage records (not yet reported)
    const pending = await db.query.usageRecords.findMany({
      where: and(
        isNull(usageRecords.reportedAt),
        lt(usageRecords.occurredAt, new Date(Date.now() - 60_000)),  // > 1 min old
      ),
      orderBy: asc(usageRecords.occurredAt),
      limit: 1000,
    });

    // Group by (subscription_id, metric)
    const groups = groupBy(pending, r => `${r.subscriptionId}__${r.metric}`);

    for (const [key, records] of Object.entries(groups)) {
      const [subId, metric] = key.split('__');
      const totalQuantity = records.reduce((sum, r) => sum + Number(r.quantity), 0);
      const sub = await db.query.subscriptions.findFirst({ where: eq(subscriptions.id, subId) });

      // Find the right subscription_item for this metric
      const stripeSubItem = await findStripeSubItemForMetric(sub.externalId, metric);
      if (!stripeSubItem) {
        await logSecurityEvent({
          type: 'usage_report_no_sub_item',
          target: { type: 'subscription', id: subId },
          details: { metric, totalQuantity },
        });
        continue;
      }

      // Report to Stripe with idempotency key
      const idempotencyKey = `usage-${subId}-${metric}-${records[0].occurredAt.toISOString()}`;
      const usageRecord = await stripe.subscriptionItems.createUsageRecord(
        stripeSubItem.id,
        {
          quantity: Math.ceil(totalQuantity),  // Stripe takes integers; ceil for fractional
          timestamp: Math.floor(records[0].occurredAt.getTime() / 1000),
          action: 'increment',  // OR 'set' if you're reporting cumulative
        },
        { idempotencyKey },
      );

      // Mark as reported
      await db.update(usageRecords)
        .set({ reportedAt: new Date(), stripeUsageRecordId: usageRecord.id })
        .where(inArray(usageRecords.id, records.map(r => r.id)));
    }
  });
}
```

### Critical idempotency

The idempotency key (`usage-${subId}-${metric}-${timestamp}`) prevents double-reporting under retries. Without it, a transient Stripe error → retry → double-report → customer charged 2x for the usage.

### `action: 'increment'` vs `'set'`

- `increment` — adds to existing usage in the period.
- `set` — replaces total usage for the period.

Use `increment` for streaming usage (most cases). Use `set` when reporting cumulative totals at end-of-period.

---

## Pattern 5 — Aggregates cron

For fast dashboard reads, periodically aggregate `usage_records` into `usage_period_aggregates`:

```ts
// /api/cron/aggregate-usage (daily)
async function aggregateUsage() {
  await acquireAdvisoryLock('aggregate_usage', async () => {
    // For each user with usage in last 24h, compute period totals
    const periodStart = startOfMonth(new Date());
    const periodEnd = endOfMonth(new Date());

    const aggregates = await db.execute(sql`
      INSERT INTO usage_period_aggregates (user_id, subscription_id, metric, period_start, period_end, total_quantity)
      SELECT
        user_id,
        subscription_id,
        metric,
        ${periodStart} as period_start,
        ${periodEnd} as period_end,
        SUM(quantity) as total_quantity
      FROM usage_records
      WHERE occurred_at >= ${periodStart} AND occurred_at < ${periodEnd}
      GROUP BY user_id, subscription_id, metric
      ON CONFLICT (user_id, metric, period_start) DO UPDATE
        SET total_quantity = EXCLUDED.total_quantity,
            computed_at = now();
    `);
  });
}
```

---

## Pattern 6 — Customer-facing usage display

Show users their usage in real-time:

```tsx
function UsageWidget({ userId }: Props) {
  const { data } = useSwr(`/api/billing/usage?userId=${userId}`, fetcher);
  if (!data) return <Skeleton />;

  return (
    <Card>
      <h3>Usage this period</h3>
      <ProgressBar value={data.used} max={data.included} label={`${data.used} / ${data.included} ${data.unit}`} />
      {data.used > data.included && (
        <Notice>You've used {(data.used - data.included)} {data.unit} over your included quota. Overage charge: ${data.overageEstimate.toFixed(2)}</Notice>
      )}
      <Link href="/billing/usage">View detailed usage →</Link>
    </Card>
  );
}
```

Critical: **show OVERAGE estimates BEFORE the bill arrives.** Surprises = chargebacks.

---

## Pattern 7 — Hard caps + soft limits

For products where unbounded usage = unbounded cost:

- **Soft limit (warning)**: at 80% of expected usage, send "you've used 80%; expect overage" email.
- **Hard cap (block)**: at 200% of expected, OPTIONALLY block further usage.

```ts
async function checkUsageBeforeAction(userId: string, metric: string, quantity: number) {
  const aggregate = await db.query.usagePeriodAggregates.findFirst({
    where: and(
      eq(usagePeriodAggregates.userId, userId),
      eq(usagePeriodAggregates.metric, metric),
      gte(usagePeriodAggregates.periodStart, startOfMonth(new Date())),
    ),
  });
  const usedSoFar = Number(aggregate?.totalQuantity ?? 0);
  const newTotal = usedSoFar + quantity;

  const user = await getUserWithBillingPolicy(userId);
  const includedQuota = user.billingPolicy.includedQuota[metric];
  const hardCap = user.billingPolicy.hardCap[metric];

  // Soft limit warning (idempotent per period)
  if (usedSoFar < includedQuota * 0.8 && newTotal >= includedQuota * 0.8) {
    await createEmailJob({
      type: 'usage_soft_limit_warning',
      recipient: user.email,
      payload: { metric, used: newTotal, included: includedQuota },
      priority: 60,
    });
  }

  // Hard cap (block if configured)
  if (hardCap && newTotal > hardCap) {
    return { allowed: false, reason: 'hard_cap_exceeded' };
  }

  return { allowed: true };
}
```

The hard-cap pattern is contentious — some businesses want it, some don't. Make it explicit policy.

---

## Pattern 8 — Refund / credit math for usage

Refunding a metered customer is harder:

- A monthly subscription refund = pro-rata cash back.
- A metered subscription refund = which usage records do you "uncharge"?

The pattern: store a `usage_credits` table.

```sql
CREATE TABLE usage_credits (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users(id),
  metric          text NOT NULL,
  credit_quantity numeric(20, 6) NOT NULL,
  reason          text NOT NULL,
  applied_to_period_start timestamptz,
  applied_to_period_end   timestamptz,
  applied_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);
```

When reporting usage to Stripe, subtract applied credits:

```ts
const totalQuantity = records.reduce((sum, r) => sum + Number(r.quantity), 0);
const credits = await db.query.usageCredits.findMany({
  where: and(
    eq(usageCredits.userId, userId),
    eq(usageCredits.metric, metric),
    isNull(usageCredits.appliedAt),
    or(isNull(usageCredits.appliedToPeriodStart), eq(usageCredits.appliedToPeriodStart, period.start)),
  ),
});
const totalCredits = credits.reduce((sum, c) => sum + Number(c.creditQuantity), 0);
const netQuantity = Math.max(0, totalQuantity - totalCredits);

await stripe.subscriptionItems.createUsageRecord(itemId, { quantity: Math.ceil(netQuantity), ... });

// Mark credits applied
await db.update(usageCredits).set({ appliedAt: new Date() })
  .where(inArray(usageCredits.id, credits.map(c => c.id)));
```

---

## Pattern 9 — Fraud / abuse detection

Usage-based pricing has a unique fraud vector: a single attacker can run up massive overage charges before they're caught.

```ts
async function detectUsageFraud(userId: string, metric: string, recent: UsageRecord[]) {
  // Velocity check: compare to historical baseline
  const baseline = await getHistoricalAvgUsagePerHour(userId, metric);
  const recentRate = recent.length / (1);  // per hour

  if (recentRate > baseline * 100) {  // 100x normal
    await trackAbuseSignal({
      signal: 'usage_velocity_anomaly',
      target: { type: 'user', id: userId },
      metadata: { metric, recentRate, baseline },
    });
    // OPTIONAL: temporarily block further usage; require human approval
    await db.update(users)
      .set({ usageBlocked: true, usageBlockedAt: new Date(), usageBlockedReason: 'velocity_anomaly' })
      .where(eq(users.id, userId));
    await createEmailJob({ type: 'admin_critical_alert', ... });
  }
}
```

Run as a background check after each `recordUsage` flush.

---

## Pattern 10 — Reconciliation between local + Stripe

Per the verify-as-write pattern: don't trust just one source.

```ts
// /api/cron/reconcile-usage-with-stripe (daily)
async function reconcileUsage() {
  // For each subscription with usage in last 30 days:
  //   1. Compute total usage from local usage_records.
  //   2. Fetch Stripe's usage records for the same period via subscriptionItems.listUsageRecordSummaries.
  //   3. Compare; alert on drift > 1%.
}
```

Drift means we either over-reported or under-reported to Stripe. Both are bad. Investigate.

---

## Pattern 11 — Customer Portal for usage

Stripe Customer Portal can show usage. Configure it:

```ts
const portalConfig = await stripe.billingPortal.configurations.create({
  features: {
    invoice_history: { enabled: true },
    payment_method_update: { enabled: true },
    // Stripe Portal does not have a built-in "live usage" widget;
    // for per-metric usage display, link from Portal back to YOUR app's usage page.
  },
});
```

Customer Portal returns invoice history (which shows the usage line on each invoice). For real-time usage, your app's UI handles it.

---

## Pattern 12 — Migration from flat-rate to usage-based

Per B130, but with usage-specific gotchas:

1. **Customers must opt in.** Don't auto-migrate paying flat-rate customers to usage; they'll churn.
2. **Grandfather pricing.** Existing flat-rate customers stay on flat-rate; new sign-ups get usage.
3. **Usage tracking starts from the beginning.** Even if not billed yet, track it for forecasting.
4. **Communicate clearly.** "Starting Jan 1, your bill will include usage above 10K calls. Here's your usage from last month for reference."

---

## Polish Bar checks for B85

- [ ] `usage_records` schema with pending-events partial index.
- [ ] `usage_period_aggregates` for fast reads.
- [ ] Fire-and-forget `recordUsage` with buffered flush.
- [ ] `report-usage-to-stripe` cron with idempotency key.
- [ ] Daily aggregation cron.
- [ ] Customer-facing usage widget shows OVERAGE estimate.
- [ ] Soft-limit + (optional) hard-cap policy explicit.
- [ ] `usage_credits` table for refunds / promotional credits.
- [ ] Fraud detection — velocity-anomaly signal.
- [ ] Reconciliation cron between local + Stripe.
- [ ] Customer Portal links back to app usage page.
- [ ] Migration playbook if moving from flat-rate.

---

## Common B85 mistakes

- **Synchronous DB write per metered action.** Slows the request path; cascading latency.
- **No idempotency on `createUsageRecord`.** Retry storms double-charge.
- **No customer-facing overage display.** Customers shocked by bill; chargebacks.
- **No hard cap → unbounded fraud exposure.** Single attacker runs $50K bill.
- **Reconciliation skipped.** Local + Stripe drift → revenue / customer disputes.
- **Refund without `usage_credits`.** Credit math wrong; double-refund or under-refund.
- **Auto-migrate flat-rate customers to usage.** Churn surge.
- **`action: 'set'` used when reporting incrementally.** Each report overwrites prior; massive under-charge.
- **Aggregates cron skipped.** Dashboard reads are slow; UX suffers.
- **Soft-limit warning without dedup.** Send 100 warnings as user crosses 80% boundary repeatedly.
