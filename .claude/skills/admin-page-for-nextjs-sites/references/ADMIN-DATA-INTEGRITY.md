# Admin Data Integrity

> Admin dashboards that show wrong numbers are worse than no dashboard at all. Wrong numbers create false confidence, trigger incorrect interventions, and erode operator trust. Every pattern here was discovered by finding real production bugs.

## 1. KPI Card Hydration

### The Bug
Admin KPI cards (Today's Revenue, Today's Signups, Active Users) initialize from hardcoded `0` defaults and update via client-side SSE events. But if SSE events are never published, or if the page loads without an active SSE connection, the cards show zeros forever — even when the database has real data.

### The Rule
**KPI cards must hydrate from database-backed API values on initial load.** SSE/WebSocket updates are a supplement for real-time deltas, never the sole data source.

```typescript
// WRONG — client-only state, relies on SSE
const [revenue, setRevenue] = useState(0);
useEffect(() => {
  const es = new EventSource('/api/admin/events');
  es.onmessage = (e) => setRevenue(JSON.parse(e.data).revenue);
}, []);

// RIGHT — hydrate from API, then layer real-time updates
const { data } = useQuery({ queryKey: ['admin-stats'], queryFn: fetchAdminStats });
// SSE updates are additive deltas on top of API-backed initial values
```

---

## 2. Never Coerce Unknown to Zero

### The Bug
When provider APIs (Stripe, PayPal) have transient failures, dashboard widgets show `$0` instead of "unavailable." An operator sees `$0 available balance` and thinks there's a billing emergency.

### The Rule
**When a value is unknown/unavailable, render it as `--` or "unavailable", never as `$0` or `0`.**

```typescript
// WRONG
const revenue = todayRevenue ?? 0;
return <KPICard value={`$${revenue}`} />;

// RIGHT
if (todayRevenue === null || todayRevenue === undefined) {
  return <KPICard value="--" subtitle="unavailable" />;
}
return <KPICard value={`$${todayRevenue}`} />;
```

Special case: `0` is a valid value (e.g., zero signups today). The distinction is between "we know the answer is zero" and "we don't know the answer."

---

## 3. Per-Provider Graceful Degradation

### The Bug
The admin stats endpoint fans out to live Stripe and PayPal APIs. If either provider API has a transient failure, the entire endpoint returns a 500 — even though most of the response is DB-backed and would be correct.

### The Rule
**Each provider call must fail independently.** Use `Promise.allSettled()` for provider fanout. DB-backed metrics still return; provider-backed metrics become "unavailable" for the failed provider.

```typescript
const [stripeResult, paypalResult, dbStats] = await Promise.allSettled([
  fetchStripeData(),
  fetchPaypalData(),
  fetchDbStats(),  // Always works if DB is up
]);

return {
  ...unwrapSettled(dbStats),
  stripe: stripeResult.status === 'fulfilled' ? stripeResult.value : { status: 'unavailable' },
  paypal: paypalResult.status === 'fulfilled' ? paypalResult.value : { status: 'unavailable' },
};
```

### Provider Health Per-Provider, Not Global

```typescript
// WRONG — one healthy provider masks a dead one
const lastWebhook = await getLastWebhookTimestamp(); // Returns newest across ALL providers
if (minutesSince(lastWebhook) > 60) warn("webhooks stale");

// RIGHT — check each provider independently
const stripeLastEvent = await getLastWebhookTimestamp('stripe');
const paypalLastEvent = await getLastWebhookTimestamp('paypal');
if (minutesSince(stripeLastEvent) > 60) warn("Stripe webhooks stale");
if (minutesSince(paypalLastEvent) > 60) warn("PayPal webhooks stale");
```

---

## 4. Don't Mix Metric Types

### The Bug
When payment data is unavailable, the "Net Revenue" card falls back to showing MRR. MRR is a stock metric (recurring rate). Net Revenue is a flow metric (cash collected in a period). Mixing them creates nonsensical displays.

### The Rule
**Stock metrics (MRR, ARR, subscriber count) and flow metrics (net revenue, fees collected, refunds issued) must never substitute for each other.**

| Metric Type | Examples | On Unavailable |
|-------------|----------|---------------|
| Stock | MRR, ARR, active subscribers | Show "unavailable" |
| Flow | Net revenue, fees, refunds | Show "unavailable" |
| Trend | MRR change %, growth rate | Show "unavailable" |

When a metric is unavailable, show `--`, not a different metric type.

Also: A subscriber growth percentage is not a dollar delta. Label precisely.

---

## 5. Canonical Data Source for Admin Surfaces

### The Bug
Admin cockpit MRR: `COUNT(users WHERE subscriptionStatus = 'active') * $20 = $4,480`.
Revenue page MRR: `countCurrentPaidSubscribersByProvider() = $4,560`.
Projections MRR: `COUNT(DISTINCT subscriptions.userId WHERE status = 'active') * $20 = $4,600`.
Three different numbers on three different admin pages.

### The Rule
**One canonical snapshot, all consumers.** Build a single `getCurrentMrrSnapshot()` function that queries live provider data. Every admin surface reads this snapshot. Different pages may render different *views* of the same data, but they must never compute revenue independently.

When the canonical snapshot uses DB fallback for a degraded provider, the fallback must be *clearly labeled*, not mixed with provider-authoritative data. Create a `toCanonicalCurrentMrrSnapshot()` adapter that strips any DB fallback contribution — fallback providers contribute zero to admin totals rather than masquerading as provider truth.

---

## 6. Test User Exclusion

### The Bug
Test/admin/E2E accounts were included in subscriber counts, MRR, churn, MAU, conversion, funnel, health, and anomaly metrics across 10+ admin surfaces. Production showed `totalUsers=483` and `mrr=$4,600` when corrected values were `totalUsers=323` and `mrr=$4,460`.

### The Rule
**Create a shared exclusion function and apply it in EVERY analytics query.** Ad-hoc filtering leads to inconsistency.

```typescript
// Shared exclusion — one function, all queries
function excludeTestUsers(query: QueryBuilder): QueryBuilder {
  return query
    .where(not(like(users.email, '%@test.yourdomain.com')))
    .where(eq(users.isAdmin, false))
    .where(not(like(users.email, 'owner@yourdomain.com')));
}
```

Test exclusion must apply to BOTH sides of ratio metrics:
```typescript
// WRONG — exclude from numerator but not denominator
const rate = paidUsers / totalUsers;  // totalUsers includes test accounts

// RIGHT — exclude from both
const rate = paidUsersExcludingTest / totalUsersExcludingTest;
```

---

## 7. Concurrency: In-Flight Deduplication

### The Bug (appeared in 6+ files)
Multiple admin services used a self-referential in-flight promise cache:
```typescript
let cachedPromise;
cachedPromise = (async () => {
  // ... cachedPromise referenced inside its own initializer
  cachedPromise = result;
})();
```

This is both a TypeScript error and a concurrency correctness bug.

### The Rule
**Separate the cache write from the promise initializer:**

```typescript
let inFlight: Promise<Result> | null = null;
let cached: { value: Result; at: number } | null = null;

async function getCached(forceRefresh = false): Promise<Result> {
  if (cached && !forceRefresh && Date.now() - cached.at < TTL_MS) {
    return cached.value;
  }
  if (inFlight && !forceRefresh) {
    return inFlight;
  }
  inFlight = computeExpensive();
  try {
    const result = await inFlight;
    cached = { value: result, at: Date.now() };
    return result;
  } finally {
    inFlight = null;
  }
}
```

### Force-Refresh Must Supersede Stale In-Flight

```typescript
// WRONG — refresh=true silently gets stale data
if (inFlight) return inFlight;  // Even when forceRefresh is true

// RIGHT — track whether in-flight work is forced
let inFlightForced = false;
if (inFlight && !forceRefresh) return inFlight;
if (forceRefresh || !inFlight) {
  inFlightForced = forceRefresh;
  inFlight = computeExpensive();
}
```

### Single-Flight Must Not Evict Active Requests

```typescript
// WRONG — 30-second timeout evicts active work, allows duplicate computation
setTimeout(() => { inFlightMap.delete(key); }, 30_000);

// RIGHT — warn but keep active work joinable
if (elapsed > 30_000) {
  logger.warn({ key, elapsed }, 'Long-running request');
  // Do NOT delete from map — late joiners should still get the result
}
```

### Cache Invalidation Must Prevent Stale Overwrites

When cache is invalidated (e.g., new data written), an older in-flight recomputation must not repopulate the cache with pre-invalidation data.

```typescript
let cacheGeneration = 0;

function invalidateCache() {
  cached = null;
  cacheGeneration++;
}

async function getCached(): Promise<Result> {
  const startGeneration = cacheGeneration;
  const result = await computeExpensive();
  // Only write to cache if nobody invalidated since we started
  if (cacheGeneration === startGeneration) {
    cached = { value: result, at: Date.now() };
  }
  return result;
}
```

---

## 8. `cachedAt` Timestamps

### The Bug
Cached responses stamp `meta.cachedAt` with "right now" on every cache hit, hiding the actual age of cached data. An operator thinks they're seeing fresh data when it's actually 5 minutes old.

### The Rule
**`cachedAt` must reflect the moment the data was computed, not the moment it was read.** Store the timestamp at write time.

```typescript
// WRONG
return { data: cached.value, meta: { cachedAt: new Date() } };

// RIGHT
return { data: cached.value, meta: { cachedAt: cached.computedAt } };
```

---

## 9. Geographic Revenue Apportionment

### The Bug
Revenue-by-country was apportioned from individual subscriber counts only, silently dropping all org/team MRR. And per-country values were rounded independently, so country totals drifted away from canonical overall totals (leaking or inventing dollars).

### The Rules
1. **Include org/team MRR** in geographic apportionment, not just individual subscribers.
2. **Use largest-remainder allocation** to prevent rounding drift:

```typescript
function apportionByCountry(
  totalMrr: number,
  countryShares: { country: string; share: number }[]
): { country: string; mrr: number }[] {
  const rawAllocations = countryShares.map(c => ({
    country: c.country,
    raw: totalMrr * c.share,
    floor: Math.floor(totalMrr * c.share * 100) / 100,
  }));

  let remainder = totalMrr - rawAllocations.reduce((s, a) => s + a.floor, 0);
  const sorted = [...rawAllocations].sort((a, b) =>
    (b.raw - b.floor) - (a.raw - a.floor)
  );

  return sorted.map((a, i) => ({
    country: a.country,
    mrr: a.floor + (i < Math.round(remainder * 100) ? 0.01 : 0),
  }));
}
```

---

## 10. Insight and Alert Scoping

### Fee-Drift Insights Must Be Multi-Provider
A "fee drift" insight labeled as business-wide but computed from only one provider (e.g., Stripe) is misleading. Compute the expected baseline from the blended payment mix across all active providers.

### Churn Alerts Must Be Business-Wide
Churn-spike detection that counts only individual subscription cancellations and ignores org/team churn undercounts real churn. Count distinct cancelled users across all business types, exclude test entities.

### Insight Category Filtering Should Be Applied Early
If the request only asks for `categories=churn`, don't execute all insight generators then filter. Only execute the requested generators — it's faster and prevents false interactions between categories.

### Payment Webhook Staleness Must Be Per-Provider
A single global "last webhook received" check means one healthy provider can mask a completely dead one. Check each provider independently.

---

## 11. Admin Payments Event Display

### The Bug
Admin payment event rows show `$0` for amounts because the code only checks a flat `payload.amount` path. Real Stripe/PayPal webhook bodies store money in nested provider-specific paths.

### The Rule
**Parse amounts from the correct nested provider paths:**

```typescript
function extractAmount(provider: string, payload: any): number | null {
  if (provider === 'stripe') {
    return (payload?.data?.object?.amount_paid
         ?? payload?.data?.object?.amount
         ?? payload?.data?.object?.total) / 100 ?? null;
  }
  if (provider === 'paypal') {
    return parseFloat(
      payload?.resource?.amount?.total
      ?? payload?.resource?.amount?.value
      ?? '0'
    ) || null;
  }
  return null;
}
```

---

## 12. Edge Cases in Value Display

### `runwayMonths = 0` Is Not Null
A runway of 0 months means "cash runs out this month" — a critical signal. Treating `0` the same as `null` hides this.

```typescript
// WRONG
const display = runwayMonths ? `${runwayMonths} mo` : 'N/A';

// RIGHT
const display = runwayMonths !== null && runwayMonths !== undefined
  ? `${runwayMonths.toFixed(1)} mo`
  : 'N/A';
```

### Negative Net Revenue Is Valid
After refunds and disputes, today's net revenue can be negative. Don't clamp to zero — show the real number with appropriate styling (red for negative).

---

## 13. CDN/Download Proxying Through Your Own Domain

### The Bug
Raw CDN hostnames (`*.r2.dev`, `*.s3.amazonaws.com`) get sinkholed by consumer DNS resolvers, corporate firewalls, and ad-blockers. CLI installers and self-update that hardcode these URLs break silently for a subset of users.

### The Rule
**Proxy all customer-facing downloads through a route on your own domain.** Your domain is already trusted by DNS resolvers and firewalls. The CDN/object-store is a backend detail.

```typescript
// /api/v1/downloads/[...path]/route.ts
export async function GET(req: Request, { params }: { params: { path: string[] } }) {
  // Validate path segments (reject '..' and non-alphanumeric)
  for (const seg of params.path) {
    if (!/^[A-Za-z0-9._-]+$/.test(seg)) return new Response('Invalid path', { status: 400 });
  }
  const upstream = await fetch(`${BUCKET_URL}/${params.path.join('/')}`);
  // Forward only cache/range/content headers, return controlled 502 on failure
}
```

---

## 14. Build Hygiene: Exclude Scratch Files

### The Bug
Developer scratch files (`temp_debug.ts`, `temp_test/`) committed or present during CI cause production build failures from unrelated type errors.

### The Rule
**Proactively exclude temp/scratch patterns in `tsconfig.json`:**
```json
{ "exclude": ["node_modules", "temp*.ts", "temp_test/", "*.tmp.ts"] }
```

---

## 15. Design Components for 3 Auth States

### The Bug
Interactive feature buttons (Save, Follow, Like) are hidden for non-authenticated users instead of showing contextual CTAs, leaving the browse surface without engagement affordances.

### The Rule
**Design every interactive component with three states from the start:**
1. Authenticated + authorized → full interaction
2. Authenticated + unauthorized (free tier) → "Subscribe to [action]" CTA
3. Unauthenticated → "Sign in to [action]" CTA

Never just hide the button. A hidden affordance can't convert.

---

## 16. Schema Changes Require Same-Commit Migrations

### The Bug
`schema.ts` changes without a corresponding new migration file in `supabase/migrations/`. Code deploys expecting columns that don't exist in production. Auth, billing, and webhook flows break silently.

### The Rule
**Every schema change must include its migration file in the same commit.** If `schema.ts` changes and there is no new file in `supabase/migrations/`, the task is incomplete. Treat this as a site-breaking, revenue-threatening failure.

The `last_event_at` column for out-of-order webhook safety is a critical example: the entire webhook protection mechanism silently degrades to zero protection if this migration hasn't been applied.

---

## 17. Cron Endpoint Authentication

### The Rule
**Every cron, reconciliation, and internal API endpoint must authenticate the caller** via a shared secret in the `Authorization: Bearer ${CRON_SECRET}` header — never in query parameters (which leak in logs).

```typescript
export async function GET(request: NextRequest) {
  const auth = request.headers.get('authorization');
  if (auth !== `Bearer ${process.env.CRON_SECRET}`) {
    return new Response('Unauthorized', { status: 401 });
  }
  // ... cron logic
}
```

---

## 18. Support Ticket SLA Alerting

### The Bug
The system tracked SLA deadlines and breach timestamps in the database, but tickets sat in "breached" status for days with no automated escalation. SLA tracking without proactive alerts is passive bookkeeping.

### The Rule
**SLA tracking must include automated escalation:**
- Email/Slack notification when a ticket approaches SLA deadline (e.g., 75% of time elapsed)
- Immediate notification on SLA breach
- Dashboard prominence changes (breached tickets float to top, change color)
- Periodic digest of breached tickets to admin

---

## 19. E2E Test Port Isolation

### The Bug
Playwright was configured to use port 3000 with `reuseExistingServer: true`. Another project's dev server was already on 3000, so Playwright silently ran all tests against the wrong application.

### The Rule
**E2E test configs must use a non-standard port and reject reuse:**
```typescript
webServer: {
  command: 'npm run dev -- --port 3100',
  port: 3100,
  reuseExistingServer: false,
}
```
- Use a non-standard port (not 3000/8080)
- Set `reuseExistingServer: false`
- Detect and ignore legacy env values pointing to the default dev port
- Pass `--port` explicitly to the dev server command

---

## 20. Test Mock Isolation

### The Bug
Database connection mocks (simulating advisory locks with stateful resolve chains) were shared at module scope. `vi.clearAllMocks()` clears call history but preserves `mockResolvedValueOnce` queues, causing cross-test leakage.

### The Rule
**Database connection mocks with stateful resolve chains must be recreated in `beforeEach`, not shared at module scope.** This is especially critical for advisory lock mocks where `mockResolvedValueOnce` chains carry ordering semantics.

---

## 21. Migration Deployment Gating

### The Bug
Three migration files sat in git for 4 days without being applied to production. Code deployed expecting columns that didn't exist, causing 500 errors on auth endpoints.

### The Rule
**Gate deployments on migration parity.** Options:
1. Automated migration-on-deploy step
2. CI check comparing pending migrations against production schema
3. Pre-deploy checklist that verifies migration state

When running dual migration systems (ORM + raw SQL), changes must be reflected in both simultaneously.

---

## 22. Validator-DB Constraint Parity

### The Bug
The application validator required `description.min(10).max(500)`, but the DB column was nullable text with no constraints. Records created through admin inserts, legacy syncs, or manual creation accumulated invalid data (single-dash placeholders, empty descriptions).

### The Rule
**DB constraints must mirror critical validation rules.** If the app enforces `NOT NULL`, `MIN(10)`, `MAX(500)`, or `UNIQUE`, the database should enforce the same. Code-only validation is bypassed by direct DB access, migration scripts, admin tools, and sync pipelines.

---

## 23. Structural Token Validation

### The Bug
Token verification uses `as UnsubscribeTokenPayload` type assertion after `JSON.parse()` — zero runtime validation. A crafted token with extra/missing fields passes silently.

### The Rule
**Use runtime type-guard functions on untrusted token payloads:**
- Validate the token has exactly the expected number of dot-separated parts
- Type-guard functions check field types and value domains
- Distinguish between "malformed token" and "expired token" for logging
- Cross-token type prevention: unsubscribe tokens must NOT have fields from preference tokens
- `getSigningSecret()` must trim whitespace and throw on empty string

---

## 19. Billing E2E Tests Must Test the Repair Path

### The Rule
Billing E2E tests should not just test the happy path. The most valuable tests deliberately corrupt local state and verify reconciliation repairs it:

1. Create a real provider subscription (Stripe test mode)
2. Send signed webhooks to activate
3. Deliberately corrupt the DB row (`status = 'past_due'`, `currentPeriodEnd` in the past)
4. Trigger the reconciliation cron
5. Assert the row is repaired to the correct state
6. Clean up provider-side resources in a `finally` block
