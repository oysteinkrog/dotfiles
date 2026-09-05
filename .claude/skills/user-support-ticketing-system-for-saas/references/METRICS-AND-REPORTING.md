# Metrics And Reporting

The single most-read artifact a support system produces is its SLA report. Most reports lie in some way. This file documents the report shape, the safety floors, and the wiring that makes the report match reality.

## The `getSlaMetrics` Contract

A pure function over a date range and optional org filter that returns:

```ts
interface SlaMetrics {
  totalTickets: number;            // tickets created in [periodStart, periodEnd]
  breachedTickets: number;         // count where slaStatus === "breached"
  breachRate: number;              // 0–100, rounded to 2 decimals
  atRiskTickets: number;
  okTickets: number;
  medianResponseHours: number | null;  // null if no resolved tickets
  avgResponseHours: number | null;
  p95ResponseHours: number | null;     // null if n < 20 (sample-size floor)
  byPriority: Array<{ priority: TicketPriority; total: number; breached: number; breachRate: number; }>;
  periodStart: string;             // ISO
  periodEnd: string;               // ISO
}
```

## Period Window: UTC, Inclusive Day Boundaries

Use a helper like `buildUtcInclusiveDayWindow(daysBack, endDate)` that returns `{ startDate, endDate }` snapped to UTC day boundaries. Default 30 days back from `now`.

**Why UTC, not local time:** support is a global team. A "yesterday" report scoped to PT excludes part of the customer's actual yesterday.

**Why inclusive day boundaries:** stable, comparable buckets. A report run at 09:00 PT is otherwise different from a run at 10:00 PT for the same date.

## Reading From Persisted `slaStatus`

The metric counts read from the `slaStatus` column the cron and service layer maintain — not a re-derivation from `slaDeadline` and `now`.

**Why:** the column is the single source of truth. Re-deriving in metric code would diverge from the queue UI's truth and from internal alert truth.

**Implication:** if `slaStatus` is wrong (e.g. cron crashed), the metrics are wrong. The fix is to repair the cron — *not* to re-derive in the report. Centralized truth with loud failure beats decentralized "best-effort" reads.

## Response Time Stats — Floor Enforcement

```ts
const responseTimes = resolvedTickets.flatMap((t) => {
  const created  = coerceTimestamp(t.createdAt);
  const resolved = coerceTimestamp(t.resolvedAt);
  if (!created || !resolved) return [];
  const hrs = (resolved.getTime() - created.getTime()) / 3_600_000;
  if (!Number.isFinite(hrs) || hrs < 0) return [];   // skip negative/invalid
  return [hrs];
}).sort((a, b) => a - b);

let median = null, avg = null, p95 = null;
if (responseTimes.length > 0) {
  const mid = Math.floor(responseTimes.length / 2);
  median = responseTimes.length % 2
    ? responseTimes[mid]
    : (responseTimes[mid - 1] + responseTimes[mid]) / 2;
  avg = responseTimes.reduce((a, b) => a + b, 0) / responseTimes.length;
  if (responseTimes.length >= 20) {
    const idx = Math.ceil(responseTimes.length * 0.95) - 1;
    p95 = responseTimes[idx];
  }
}
```

Rounding: median/avg/p95 are rounded to 2 decimals before return. `breachRate` to 2 decimals. `hoursUntilBreach` (queue UI, not metrics) to 1 decimal.

## Why P95 Has a Sample-Size Floor

P95 with 4 samples is the 4th sample. With 19, it's somewhere between the 18th and 19th — but a single outlier in a 19-sample period rewrites the metric. **20 is the practical minimum** for percentile stability that survives a slow ticket.

Better approach for reports across small periods (e.g. weekly metrics for a small customer):
- Surface `null` and have the dashboard render `—` with a tooltip "Need ≥ 20 resolved tickets in window."
- Offer a *rolling* P95 over the trailing 90 days as the always-available companion.

## Negative Response-Time Filtering

Backfilled `resolvedAt` values older than `createdAt` exist in some migrations. Drop them, don't crash. They'd otherwise produce negative response times that nuke the average.

## Per-Priority Breakdown

Always emit a row per priority *even when zero*:

```ts
const priorities: TicketPriority[] = ["p0", "p1", "p2", "p3"];
const byPriority = priorities.map((priority) => {
  const inP = tickets.filter(t => t.priority === priority);
  const breached = inP.filter(t => t.slaStatus === "breached").length;
  return {
    priority,
    total: inP.length,
    breached,
    breachRate: inP.length ? (breached / inP.length) * 100 : 0,
  };
});
```

Why fixed-shape rows: the dashboard renders a 4-row table whether you have P0 tickets or not. Missing rows make the UI flicker as data populates.

## Surfaces That Read Metrics

1. **`/admin/support/sla` page** — full report, period selector, per-priority table.
2. **`/admin/operations` cockpit** — top-line breach rate, approaching count, link out.
3. **`/admin/command-center`** — alerts surface, breach rate trend.
4. **Weekly-summary email to leadership** — top-line numbers + comparison to prior week.
5. **`/admin/support/sla-metrics` API** — JSON for external dashboards (Looker, Tableau).

When metrics change, **invalidate all five** (TanStack `invalidateQueries` for the in-app cockpits; cache header / max-age for the API).

## Trend Reporting (Beyond `getSlaMetrics`)

For "is the team improving?" questions, periodic reports are necessary:

- **Day-over-day breach rate** — sparkline on the cockpit. 7-day rolling.
- **Time-to-first-response distribution** — histogram (1h / 4h / 24h / 72h / >72h buckets). Reveals tail before percentiles do.
- **Reopen rate** — `tickets_reopened_within_7_days / tickets_resolved`. If > 5%, the team is closing prematurely.
- **First-touch resolution rate** — `resolved_with_zero_support_replies / total_resolved`. Real KB deflection signal.
- **Escalation rate by priority** — manual-bumped P2 → P0 within ticket lifetime. High rate means initial triage misses.

Each gets its own `compute<Metric>` function in `src/lib/services/support-tickets.ts`, each tested independently, each cached with appropriate TTL.

## CSAT / NPS / Cancellation Survey

Customer satisfaction is its own metric family — see [CUSTOMER-SATISFACTION.md](CUSTOMER-SATISFACTION.md). Wire CSAT scores back into the ticket record (`csatScore`, `csatComment`) so the report can correlate scores with priority, assignee, and breach status.

## Org-Scoped Reports

Enterprise customers want their own SLA report. Use `getSlaMetrics({ orgId })`. Cache per org. Surface as `/admin/orgs/[orgId]/support` and as a customer-facing `/account/support/sla` (read-only) for transparency.

## Reporting Anti-Patterns

| ✗ | Why |
|---|---|
| Recomputing `slaStatus` in the report | Diverges from queue/cron truth |
| Reporting P95 on 5 samples | Misleading; one slow ticket is the metric |
| Local-time period bounds | "Yesterday" depends on the reader's timezone |
| Missing zero-priority rows | Dashboard flicker as data populates |
| Counting in-app reopen as a new ticket | Inflates "ticket volume," hides reopen rate |
| Not invalidating adjacent cockpits on mutation | Operations summary lies for 30 seconds after a status change |
| Reporting without a date range | A single number averaged over all time hides the trend |

## Test Fixtures

```
1. Empty period: 0 tickets, period start/end set, all numerics 0 or null.
2. 1 resolved, 0 breached: breachRate=0, median/avg = the one value, p95=null (n<20).
3. 19 resolved: median/avg defined, p95=null.
4. 20 resolved with one slow outlier: p95 = the outlier (correct, by design).
5. 100 resolved with 10 breached: breachRate=10.00, breached priority breakdown matches.
6. Backfilled negative response time: filtered, doesn't crash.
7. Org-scoped: same period, only one org's tickets included.
8. Period straddling DST: bucketing remains UTC-stable.
```
