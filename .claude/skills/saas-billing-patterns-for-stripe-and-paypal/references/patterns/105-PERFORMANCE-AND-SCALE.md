# Bundle B105 — Performance & Scale

> **Where this comes from.** Cross-reference with `/extreme-software-optimization`, `/profiling-software-performance`, `/deadlock-finder-and-fixer`. Plus operational reality: billing tables become hot paths as customer count grows.

Billing systems are READ-HEAVY (every page load checks subscription status) and WRITE-HEAVY in bursts (webhook storms, cron sweeps). Performance choices made early matter most.

Skip in T1 (premature optimization). Useful in T2 (catch quadratic bugs early). Essential by T3 (10K+ customers; query plans matter). Non-optional by T4 (50K+ customers; partitioning may apply).

---

## Pattern 1 — The 5 hot-path queries

These run on every (or most) page loads. Optimize first; benchmark continuously.

| Query | Table | Index needed |
|-------|-------|--------------|
| "Does user X have access?" | users + subscriptions | users.id PK; subscriptions(user_id, status) composite |
| "What's user X's current plan?" | users (denormalized) | users.id PK + denormalized status |
| "List recent payment events for user X" | payment_events | payment_events(user_id, created_at DESC) |
| "Has user X been billed in the last 24h?" | settlement_ledger | settlement_ledger(user_id, occurred_at DESC) |
| "Webhook reconciliation: pending events" | payment_events | payment_events(created_at) WHERE processed_at IS NULL ← partial index |

**The denormalized `users.subscription_status` is what makes #1 + #2 O(1).** Don't deprecate it for "purity"; it's load-bearing.

---

## Pattern 2 — Indexes the source guide already prescribes

From B10 / source guide:

```sql
-- Hot reconciliation path
CREATE INDEX payment_events_unprocessed_idx
  ON payment_events (created_at)
  WHERE processed_at IS NULL;

-- Per-user payment events
CREATE INDEX payment_events_user_created_idx
  ON payment_events (user_id, created_at DESC);

-- Subscription lookup by external id (webhook handler)
CREATE UNIQUE INDEX subscriptions_provider_external_id_idx
  ON subscriptions (provider, external_id);

-- User-subscription relationship
CREATE INDEX subscriptions_user_status_idx
  ON subscriptions (user_id, status)
  WHERE status IN ('active', 'past_due', 'cancelled');

-- Email queue priority
CREATE INDEX email_jobs_priority_queue_idx
  ON email_jobs (priority, next_retry_at, created_at)
  WHERE status = 'queued';

-- Pending checkout session uniqueness
CREATE UNIQUE INDEX users_pending_checkout_session_idx
  ON users (pending_checkout_session_id)
  WHERE pending_checkout_session_id IS NOT NULL;

-- Orphan-cancel queue scan
CREATE INDEX organizations_pending_individual_sub_cancel_active_idx
  ON organizations (pending_individual_sub_cancel_retry_count)
  WHERE pending_individual_sub_cancel_id IS NOT NULL
    AND pending_individual_sub_cancel_retry_count < 5;

-- Settlement ledger by user
CREATE INDEX settlement_ledger_user_id_idx
  ON settlement_ledger (user_id, occurred_at);
```

These are baseline; verify EXPLAIN ANALYZE shows index usage on production query plans.

---

## Pattern 3 — N+1 query detection

The most common scale bug: query inside a loop.

```ts
// BAD — N+1
for (const sub of subscriptions) {
  const user = await db.query.users.findFirst({ where: eq(users.id, sub.userId) });
  // ... do something with user
}

// GOOD — single batch query
const userIds = [...new Set(subscriptions.map(s => s.userId))];
const users = await db.query.users.findMany({ where: inArray(users.id, userIds) });
const userById = new Map(users.map(u => [u.id, u]));
for (const sub of subscriptions) {
  const user = userById.get(sub.userId);
  // ...
}
```

### Detection script

```bash
# scripts/detect-n-plus-one.sh
# Greps billing code for `for (...) { await db... }` patterns
rg -l --type ts 'for \([^)]+\) \{[^}]*await db\.' src/ | while read f; do
  echo "POTENTIAL N+1: $f"
  rg -A 3 'for \([^)]+\) \{[^}]*await db\.' "$f"
done
```

This catches simple cases. Subtle ones (Promise.all over async fns that each query) need profiler.

---

## Pattern 4 — Profile the slow queries

Use Postgres `auto_explain`:

```sql
-- In postgresql.conf or per-session
SET auto_explain.log_min_duration = '100ms';
SET auto_explain.log_analyze = true;
SET auto_explain.log_buffers = true;
```

Or per-query EXPLAIN ANALYZE in a benchmark script:

```ts
// scripts/bench-billing-queries.ts
import { db } from '@/lib/db';
import { performance } from 'node:perf_hooks';

const queries = [
  { name: 'mrr_snapshot', query: () => computeMrrSnapshot() },
  { name: 'churn_30d', query: () => computeChurn30Days() },
  { name: 'customer_health', query: () => computeAllCustomerHealth() },
  { name: 'reconciliation_pending_count', query: () => countPendingPaymentEvents() },
];

for (const { name, query } of queries) {
  const start = performance.now();
  await query();
  const duration = performance.now() - start;
  console.log(`${name}: ${duration.toFixed(1)}ms`);
}
```

Run in CI nightly against a production-shaped DB. Alert on regression.

---

## Pattern 5 — Partial indexes save space + time

Per § 3.1 / source guide: `WHERE processed_at IS NULL` partial index. Why:

- Without partial: index has 1 row per `payment_events` row (millions over time).
- With partial: index has 1 row per UNPROCESSED event (typically tens to hundreds).
- Reconciliation cron's scan: O(unprocessed_count) instead of O(total_count).

Use partial indexes for any "scan filtered by transient state" pattern:

```sql
CREATE INDEX subs_past_due_idx ON subscriptions (current_period_end)
  WHERE status = 'past_due';

CREATE INDEX users_pending_checkout_active_idx ON users (pending_checkout_expires_at)
  WHERE pending_checkout_session_id IS NOT NULL
    AND pending_checkout_expires_at > now();  -- not valid; use cron-side filter

CREATE INDEX email_jobs_dlq_recent_idx ON email_dlq (inserted_at)
  WHERE failsafe_alerted_at IS NULL;
```

(Note: index expressions can't reference `now()` directly. Use a fixed cutoff like `WHERE pending_checkout_expires_at > '2024-01-01'` for "recently created" patterns.)

---

## Pattern 6 — Bounded scans (carry from B90)

Already in B90. The performance lens: every cron has a wall-time budget. If it ever runs longer, INVESTIGATE — it's a sign your scan grew faster than the bound expected.

```ts
// Bounded
const candidates = await db.query.paymentEvents.findMany({
  where: ...,
  limit: 50,            // ← the bound
});

// Unbounded — DON'T
const candidates = await db.query.paymentEvents.findMany({ where: ... });
```

Per § 51: dunning `LIMIT 5000`, reconciliation `LIMIT 50`, verify-as-write reconciliation `LIMIT 100`. Wall-time budget per cron is typically Vercel's 300s on Pro plan; SCAN_LIMIT × per-row processing time should fit.

---

## Pattern 7 — Connection pool sizing

For Vercel serverless: each isolate maintains its own pool. Pool size × concurrent isolates = total Postgres connections.

```ts
// src/lib/db.ts
const pool = new Pool({
  connectionString: env.DATABASE_URL,
  max: 5,              // per-isolate; tune based on Postgres connection limit / expected concurrency
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,
});
```

For Supabase pooler: use `?pgbouncer=true` mode and a low `max`. The pooler handles total-connection management.

For self-hosted: estimate concurrent isolates × per-isolate pool size; ensure < 80% of Postgres `max_connections`.

### Connection leak detection

If pool keeps growing or eventually exhausts:
- Add `pool.on('error', ...)` handler.
- Log `pool.totalCount`, `pool.idleCount`, `pool.waitingCount` periodically.
- Look for `await db.transaction(...)` that throws without releasing.
- Look for `pgClient.reserve()` without `finally { release() }` (per B90 § cron-defenses; failure-mode catalog #8).

---

## Pattern 8 — Read replicas for analytics

For T4+ scale: route heavy analytics queries (MRR, churn, health) to a read replica.

```ts
// src/lib/db.ts
const writeDb = drizzle(new Pool({ connectionString: env.DATABASE_URL }));
const readDb = drizzle(new Pool({ connectionString: env.DATABASE_REPLICA_URL ?? env.DATABASE_URL }));

export const db = writeDb;        // default; transactional reads + writes
export const readonlyDb = readDb; // analytics; eventual consistency OK
```

Use `readonlyDb` for:
- MRR snapshot computation.
- Churn calculation.
- Customer health scoring.
- Admin dashboard reads (if seconds-stale is acceptable).

Use `writeDb` for:
- Webhook handlers (need read-after-write).
- Verify-as-write (must read fresh state).
- Cron reconciliation (writes).

---

## Pattern 9 — Caching strategies (with provenance)

Per B100: every cached value carries `provenance: live | fallback | unavailable`. The performance angle:

- **Hot cache (5 min TTL)**: MRR snapshot, churn, customer health.
- **Warm cache (1 hour TTL)**: settlement ledger aggregates per period.
- **Cold cache (24 hour TTL)**: monthly close artifacts.

For Vercel: use Vercel KV (Redis) or Upstash Redis. Both are eventually consistent across regions (don't use for strong-consistency reads).

```ts
// src/lib/cache/billing.ts
const CACHE_TTL_MRR = 5 * 60;  // seconds

export async function getCurrentMrrSnapshot() {
  const cached = await redis.getJson<MrrSnapshotWithProvenance>('mrr:current');
  if (cached && Date.now() - cached.computedAt.getTime() < CACHE_TTL_MRR * 1000) {
    return { ...cached, provenance: 'live' as const };
  }

  return await singleFlight('mrr:current', async () => {
    try {
      const fresh = await computeMrrSnapshot();
      await redis.setJson('mrr:current', fresh, { ex: CACHE_TTL_MRR });
      return { ...fresh, provenance: 'live' as const };
    } catch (err) {
      const fallback = await redis.getJson<MrrSnapshotWithProvenance>('mrr:current');
      if (fallback) return { ...fallback, provenance: 'fallback' as const };
      return { value: null, provenance: 'unavailable' as const };
    }
  });
}
```

---

## Pattern 10 — Table partitioning (T4+ scale)

For tables with > 100M rows (large `payment_events`, large `usage_records`, large `audit_log`), Postgres declarative partitioning by month:

```sql
-- Convert payment_events to partitioned (one-time migration)
CREATE TABLE payment_events_partitioned (
  LIKE payment_events INCLUDING ALL
) PARTITION BY RANGE (created_at);

-- Create monthly partitions
CREATE TABLE payment_events_2026_01 PARTITION OF payment_events_partitioned
  FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE payment_events_2026_02 PARTITION OF payment_events_partitioned
  FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
-- ... etc

-- Cron creates next month's partition each month
```

Benefits:
- Index size per-partition (faster scans).
- Old partitions can be DROPPED (rather than DELETED) for archival.
- Backup can be per-partition (faster restore).

Trade-offs:
- Partition key must be in WHERE clauses for partition pruning.
- Schema migrations more complex.
- Some Postgres features don't work across partitions (e.g., UNIQUE without partition key).

Don't partition unless you have the scale. Premature partitioning is a tax on every query.

---

## Pattern 11 — Background jobs vs synchronous

For operations > 1 second: defer to background.

```ts
// BAD — synchronous in webhook handler
async function handleStripeWebhook(event) {
  // ...
  await sendWelcomeEmail(user);  // 800ms
  await analyticsClient.track(user, 'subscription_created');  // 300ms
  await syncToCRM(user);  // 1500ms
  // Total: 2600ms; webhook timeout risk
  return 200;
}

// GOOD — defer via job queue
async function handleStripeWebhook(event) {
  // ...
  await db.insert(deferredJobs).values([
    { type: 'send_welcome_email', payload: { userId: user.id } },
    { type: 'analytics_track', payload: { userId: user.id, event: 'subscription_created' } },
    { type: 'sync_crm', payload: { userId: user.id } },
  ]);
  // Total: <50ms; cron drains the jobs
  return 200;
}
```

The deferred job processor is its own cron with B90 cron defenses.

---

## Pattern 12 — Performance budget per route

| Route | p50 | p99 | p99.9 |
|-------|-----|-----|-------|
| `/api/auth/check-session` | 20ms | 100ms | 500ms |
| Page load (with paywall check) | 100ms | 500ms | 2000ms |
| `/api/stripe/webhook` | 100ms | 1000ms | 5000ms (recon catches) |
| `/api/checkout/create` | 500ms | 2000ms | 5000ms |
| Admin dashboard page | 500ms | 2000ms | 5000ms |
| MRR snapshot compute | 1000ms (cached) | 30s (uncached) | 120s |

Track per-route latency in Prometheus / Grafana / Datadog. Alert on p99 regression.

---

## Pattern 13 — Pre-warm caches

For latency-sensitive paths, pre-compute caches before users hit them:

```ts
// /api/cron/prewarm-caches (every 5 min)
async function prewarmCaches() {
  await Promise.all([
    getCurrentMrrSnapshot(),
    getCurrentFeeTelemetrySnapshot(),
    getReconciliationFreshnessSnapshot(),
    // Pre-warm per-user caches for active admins
    ...activeAdminIds.map(id => prewarmAdminDashboard(id)),
  ]);
}
```

Pre-warm BEFORE the user hits the page; their request hits a warm cache.

---

## Pattern 14 — Database vacuum + analyze

Postgres needs periodic `VACUUM` + `ANALYZE` to keep query plans accurate. Supabase does this automatically; self-hosted needs a cron:

```bash
# Daily VACUUM ANALYZE on hot tables
psql "$DATABASE_URL" <<'EOF'
VACUUM ANALYZE payment_events;
VACUUM ANALYZE subscriptions;
VACUUM ANALYZE settlement_ledger;
VACUUM ANALYZE usage_records;
VACUUM ANALYZE audit_log;
EOF
```

Without this, query plans drift; nightly EXPLAIN ANALYZE benchmarks would show regression.

---

## Polish Bar checks for B105

- [ ] Hot-path queries identified; indexes in place.
- [ ] N+1 detection script in CI.
- [ ] Performance benchmark script runs nightly; alerts on regression.
- [ ] Partial indexes for transient-state filters.
- [ ] All crons have bounded scans matching wall-time budget.
- [ ] Connection pool sized appropriately; leak detection wired.
- [ ] Read replica for analytics (T4+).
- [ ] Cache strategy with provenance per cache.
- [ ] Table partitioning evaluated (T4+).
- [ ] Background jobs for any operation > 1s in webhook path.
- [ ] Per-route latency budget; Prometheus alerts.
- [ ] Pre-warm caches for latency-sensitive paths.
- [ ] VACUUM ANALYZE cron (or auto-vacuum verified).
- [ ] Query plan stability tested across releases.

---

## Common B105 mistakes

- **N+1 in dunning cron.** Past_due users iterated; per-user query inside loop. 5000 customers → 5000 queries → cron times out.
- **No partial indexes.** Every "find pending X" scan is O(total_X) instead of O(pending_X).
- **Connection pool max=20.** Vercel deploys 30 concurrent isolates → 600 connections → Postgres rejects.
- **Synchronous CRM sync in webhook.** 1500ms added; webhook timeout; reconciliation storm.
- **MRR computed live on every dashboard load.** 30s queries N times per minute; DB hot CPU.
- **Tables partitioned without partition-key in WHERE clauses.** Scans every partition; SLOWER than non-partitioned.
- **Read replica without `read_committed` understanding.** Stale-data bugs in admin dashboard.
- **Caches without provenance.** Stale displayed as live; user confused.
- **Performance benchmarks not in CI.** Regression introduced; discovered in production.
- **Pre-warm cron timing wrong.** Pre-warms 1 minute AFTER cache TTL; pre-warm misses; user request still slow.
