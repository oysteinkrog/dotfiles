# Performance Budgets

The support cockpit is admin-facing infrastructure that must stay fast even under SLA-scare load (5 admins refreshing the queue while 200 tickets flow in). Slow queues turn into stale queues turn into missed breaches. This file defines explicit budgets per surface and the techniques to stay within them.

## Per-Surface Budgets

| Surface | Total budget | DB queries | Bundle size | Notes |
|---|---|---|---|---|
| Admin queue list | 800ms | ≤ 8 | — | Most-used surface; tightest budget |
| Admin ticket detail | 600ms | ≤ 6 | — | Fewer rows; faster |
| Admin SLA metrics | 1200ms | ≤ 4 | — | Aggregate; cache-friendly |
| User-side ticket list | 500ms | ≤ 4 | — | Short timeout; user-facing |
| User-side ticket detail | 400ms | ≤ 3 | — | Single ticket + messages |
| Customer journey panel | 800ms | ≤ 6 | — | Multiple sources; parallel |
| Cron run (per cycle) | 30s | unlimited | — | Bounded by next cron firing |
| Slack/internal alert post | 10s | — | — | `AbortSignal.timeout(10_000)` |
| New-ticket form deflection | 300ms | ≤ 3 | — | Has to feel instant |
| Floating widget initial render | 100ms (FCP) | — | ≤ 25KB JS | Loaded site-wide |

These are P50 targets. P95 should be within 2× (admin queue P95 ≤ 1600ms). P99 within 4× (≤ 3200ms).

## Query-Count Budget Enforcement

Wrap the test DB to count queries:

```ts
function wrapDbForCounting(realDb: typeof db): { db: typeof db; counts: { select: number; insert: number; update: number; transaction: number } } {
  const counts = { select: 0, insert: 0, update: 0, transaction: 0 };
  const wrapped = new Proxy(realDb, {
    get(target, prop) {
      if (prop === "select") { counts.select++; return target.select.bind(target); }
      if (prop === "insert") { counts.insert++; return target.insert.bind(target); }
      if (prop === "update") { counts.update++; return target.update.bind(target); }
      if (prop === "transaction") { counts.transaction++; return target.transaction.bind(target); }
      return Reflect.get(target, prop);
    },
  });
  return { db: wrapped, counts };
}

test("admin list endpoint stays within query budget", async () => {
  const { db: countingDb, counts } = wrapDbForCounting(realDb);
  await getAdminTicketsList.call({ db: countingDb }, makeAdminReq("?limit=50"));
  expect(counts.select + counts.update).toBeLessThanOrEqual(8);
});
```

CI fails if a regression brings the count above budget.

## Latency Budget Enforcement

Per-route timing in production:

```ts
export async function GET(request: Request) {
  const start = performance.now();
  try {
    // ... handler logic
    return response;
  } finally {
    const elapsed = performance.now() - start;
    metrics.histogram("support.admin.list.latency_ms", elapsed, { route: "tickets-list" });
    if (elapsed > 800) {
      logger.warn({ elapsed, route: "tickets-list" }, "Latency budget exceeded");
    }
  }
}
```

Wire to your observability stack (Datadog, Honeycomb, OpenTelemetry). Alert when P95 exceeds budget for 5 consecutive minutes.

## DB Index Coverage

The admin list endpoint joins/filters on:
- `status` (filter)
- `priority` (filter)
- `assignee` (filter)
- `slaDeadline` (sort)
- `slaStatus` (filter)
- `createdAt` (sort)

Each gets its own index. Composite indexes for hot filter combinations:

```ts
index("support_tickets_status_priority_idx").on(t.status, t.priority),
index("support_tickets_status_sla_deadline_idx").on(t.status, t.slaDeadline),
```

Use `EXPLAIN ANALYZE` on the actual query the admin list executes. Plan should use Index Scan, not Seq Scan, even for low-cardinality filter values.

## Pagination Performance

Offset-based pagination (`OFFSET 5000 LIMIT 50`) gets slower as offset grows because Postgres has to count and skip rows. For admin queue (typically offset < 500), it's fine. For deep history queries (offset > 5000), use cursor-based:

```ts
// Cursor-based: next page = "tickets created before <cursor>"
const cursorRaw = new URL(request.url).searchParams.get("cursor");
const cursorDate = cursorRaw ? new Date(cursorRaw) : null;
const where = cursorDate ? lt(supportTickets.createdAt, cursorDate) : undefined;
const tickets = await db.select(...).from(supportTickets).where(where).orderBy(desc(supportTickets.createdAt)).limit(50);
const nextCursor = tickets.at(-1)?.createdAt.toISOString();
return { tickets, nextCursor };
```

Cursor scales to millions of rows without degradation.

## TanStack Query Cache Sizing

Aggressive cache reduces redundant fetches:

```ts
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,                          // 30s default
      gcTime: 5 * 60_000,                         // 5 min before garbage-collected
      retry: (failureCount, error) => failureCount < 2 && !is4xx(error),
      refetchOnWindowFocus: false,                 // admin tabs flip frequently; don't refetch on each
    },
  },
});
```

Per-query overrides:
- Ticket list: `staleTime: 30_000`
- Ticket detail: `staleTime: 15_000` (messages may arrive)
- SLA metrics: `staleTime: 5 * 60_000`

## Server-Side Cache Layer

Per-user data (mine tickets, my profile) can use browser/private cache headers
(`Cache-Control: private, max-age=60`) but must not be stored in a shared CDN
cache unless the key includes authenticated user identity and authorization
state. Per-org data can be cached server-side keyed on org-id + permission scope
with 60s TTL. Aggregate metrics cached 5-15 min.

```ts
async function getCachedSlaMetrics(orgId: string | null, periodKey: string) {
  const cacheKey = `sla-metrics:${orgId ?? "global"}:${periodKey}`;
  const cached = await edgeCache.get(cacheKey);
  if (cached) return cached;
  const metrics = await getSlaMetrics({ orgId, ...periodFromKey(periodKey) });
  await edgeCache.set(cacheKey, metrics, { ttl: 300 });
  return metrics;
}
```

Invalidate on mutation: every `updateTicket` invalidates the org-scoped key; cron invalidates global.

## Client Bundle Budget

Floating widget loaded on every page; keep under 25KB gzipped:

```bash
bun run build
ls -la .next/static/chunks/ | grep widget
# .next/static/chunks/support-widget-abc123.js   23,847 bytes  ✅
```

Lazy-load the modal contents (form, ticket list) on widget-open:

```tsx
const ModalContent = lazy(() => import("./SupportWidgetModal"));

function SupportWidget() {
  const [expanded, setExpanded] = useState(false);
  return (
    <>
      <button onClick={() => setExpanded(true)}>...</button>
      {expanded && (
        <Suspense fallback={<Loader />}>
          <ModalContent onClose={() => setExpanded(false)} />
        </Suspense>
      )}
    </>
  );
}
```

The 200KB modal code only loads if the user actually opens the widget.

## Cron Per-Cycle Budget

A 30s budget for the SLA cron means:
- Phase 1 (DB scan + transactional update): ≤ 5s
- Phase 2 (alert post, with timeout): ≤ 11s (10s timeout + 1s buffer)
- Org-name enrichment: ≤ 1s
- Other: ≤ 13s

If cron runs over budget, tighten by:
- Limit the scan to recent 7 days (older breached tickets stay flagged)
- Batch the transactional update (10 rows per transaction, parallel)
- Skip the Slack post for non-priority breaches

## Image / Attachment Lazy-Load

Admin ticket detail with 5 image attachments shouldn't fetch all 5 on render. Use `loading="lazy"` on `<img>` and intersection-observer for download:

```tsx
<img src={signedUrl} loading="lazy" decoding="async" alt={attachment.name} />
```

## Streaming / Suspense For Long Loads

Customer journey panel can take 800ms; render the ticket-detail page first (200ms), then stream the journey panel:

```tsx
export default async function TicketDetailPage({ params }) {
  const ticket = await getTicket(params.id);
  return (
    <>
      <TicketHeader ticket={ticket} />
      <TicketConversation ticket={ticket} />
      <Suspense fallback={<JourneySkeleton />}>
        <CustomerJourney userId={ticket.userId} ticketId={ticket.id} />
      </Suspense>
    </>
  );
}
```

The admin sees the conversation immediately; the journey loads in the background.

## Memory Budget

Large in-memory caches grow without bound. Cap with LRU:

```ts
import LRU from "lru-cache";
const cache = new LRU<string, unknown>({ max: 5000, ttl: 60_000 });
```

5000 entries × ~10KB each = 50MB ceiling. Acceptable for a single Node instance; configure based on instance size.

## Profiling In Production

Sentry transaction tracing, OpenTelemetry, Datadog APM — pick one and instrument:

```ts
import { startTransaction } from "@/lib/observability";

export async function GET(request: Request) {
  return await startTransaction("support.admin.list", async (tx) => {
    const url = new URL(request.url);
    tx.setTag("limit", url.searchParams.get("limit") ?? "default");
    return await listTickets(...);
  });
}
```

Surface P50/P95/P99 in dashboards. Page if P95 > budget for 5 min.

## Anti-Patterns

| ✗ | Why |
|---|---|
| One huge SQL query that returns everything | Single slow query worse than 8 fast ones with parallel fetch |
| Adding indexes for every column "just in case" | Write amplification; storage cost; slower inserts |
| Deep offset pagination | Linear scan time at large offsets |
| Recompute SLA on every read instead of using persisted column | Defeats the index; multiplies latency |
| Synchronous cron heavy work blocking the request handler | Request times out; client retries; thundering herd |
| Cache without TTL | Stale data persists indefinitely |
| Cache without invalidation on mutation | Reads see stale data after admin actions |
| Loading the widget JS bundle on every page synchronously | 200KB blocking render of every page |
| No N+1 detection in CI | Regressions slip through |
| Profiling locally only | Prod has different load characteristics |

## Wire Points Checklist

- [ ] Per-route latency histogram in observability
- [ ] Alert when P95 exceeds budget for 5 min
- [ ] CI test for query-count budget on admin list
- [ ] All filter/sort columns indexed individually
- [ ] Composite indexes for hot filter combinations
- [ ] Cursor-based pagination available for deep queries
- [ ] TanStack Query staleTime tuned per surface
- [ ] Edge cache for per-user data with `private, max-age=60`
- [ ] Server-side cache for org/global aggregates with invalidation
- [ ] Widget bundle < 25KB gzipped
- [ ] Modal content lazy-loaded
- [ ] Image attachments use `loading="lazy"`
- [ ] Streaming/Suspense for long-load surfaces
- [ ] LRU cache caps for in-memory data
- [ ] Cron run-time histogram with budget alert
