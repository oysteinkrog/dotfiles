# Observability — Logs, Metrics, Traces, Alerts

A support system without observability is a black box: tickets vanish, SLAs silently breach, agents triage without visibility. This file covers what to log, what to alert on, and how to wire it.

## What To Instrument

### Application Metrics (Prometheus / Grafana / Vercel)

| Metric | Type | Labels |
|---|---|---|
| `support_ticket_created_total` | counter | category, priority, tier |
| `support_ticket_resolved_total` | counter | category, priority, tier |
| `support_ticket_open` | gauge | status |
| `support_ticket_sla_breached_total` | counter | tier |
| `support_ticket_first_response_seconds` | histogram | tier |
| `support_ticket_resolve_seconds` | histogram | tier, priority |
| `support_message_sent_total` | counter | senderType |
| `support_email_sent_total` | counter | template, status (sent/failed) |
| `support_admin_action_total` | counter | action (status_change/priority_change/assign), agent |
| `support_cron_run_total` | counter | result (success/error) |
| `support_kb_search_total` | counter | result_count_bucket |
| `support_kb_deflection_total` | counter | article_id |

### Logs (Structured JSON)

Every state-changing action:

```ts
log.info({
  event: "support.ticket.status_changed",
  ticket_id,
  user_id,
  from: "in_progress",
  to: "awaiting_customer",
  agent: agentEmail,
  reason: "Asked for repro steps",
  ts: new Date().toISOString(),
});
```

Required event vocabulary:
- `support.ticket.created`
- `support.ticket.status_changed`
- `support.ticket.priority_changed`
- `support.ticket.assigned`
- `support.ticket.resolved`
- `support.ticket.closed`
- `support.ticket.reopened`
- `support.message.received`
- `support.message.sent`
- `support.email.sent`
- `support.email.failed`
- `support.sla.breached`
- `support.sla.at_risk`
- `support.cron.sla_alerts.completed`
- `support.kb.searched`
- `support.kb.cited`

Don't log raw message bodies in plain text (PII risk). Use:
- `subject_prefix: subject.slice(0, 50)` instead of full subject
- `body_length: body.length` instead of full body
- `ticket_id` to look up the body if needed

### Traces (OpenTelemetry)

Wrap every API handler and service-layer method:

```ts
import { trace } from "@opentelemetry/api";
const tracer = trace.getTracer("support");

export async function createTicket(input: TicketInput) {
  return await tracer.startActiveSpan("support.createTicket", async span => {
    span.setAttributes({
      "support.user_tier": input.tier,
      "support.category": input.category,
    });

    try {
      const ticket = await db.transaction(async tx => { ... });

      span.setAttribute("support.ticket_id", ticket.id);
      span.setStatus({ code: SpanStatusCode.OK });
      return ticket;
    } catch (e) {
      span.recordException(e);
      span.setStatus({ code: SpanStatusCode.ERROR });
      throw e;
    } finally {
      span.end();
    }
  });
}
```

This gives you flame graphs per ticket-create call, with SLA-engine, DB, and email-send spans nested.

## Alerts

Alert thresholds, with named owners:

| Alert | Condition | Severity | Owner | Channel |
|---|---|---|---|---|
| **SLA breach rate spike** | `breach_rate > 5%` for 30 min | P1 | Owner | PagerDuty |
| **Cron failed** | `cron_run_total{result=error}` increases | P1 | Owner | PagerDuty |
| **Email send failures** | `email_failed > 5%` for 15 min | P1 | Owner | PagerDuty |
| **Open ticket count surging** | `support_ticket_open` > 2x 7-day avg | P2 | On-call | Slack |
| **No tickets created in 1h** | (during business hours) | P2 | Owner | Slack — could be a signup bug |
| **Admin route error rate** | `5xx > 1%` for 10 min | P1 | Owner | PagerDuty |
| **DB query timeout** | p99 latency > 5s | P2 | Eng | Slack |
| **Hostile-flag spike** | `hostile_tickets > 3 in 1h` | P2 | Owner | Slack — possible coordinated attack |

### PromQL Examples

```promql
# Breach rate over the last 30 min — breaches divided by created tickets in
# the same window. Don't `rate()` the gauge `support_ticket_open`; rates only
# apply to monotonically increasing counters.
sum(rate(support_ticket_sla_breached_total[30m]))
  /
sum(rate(support_ticket_created_total[30m]))
> 0.05

# FRT P90 by tier (histogram_quantile requires the `le` label preserved
# through the aggregation — sum-by-le is the canonical pattern)
histogram_quantile(
  0.9,
  sum by (le, tier) (
    rate(support_ticket_first_response_seconds_bucket[30m])
  )
)

# Email send failure rate
sum(rate(support_email_sent_total{status="failed"}[15m]))
  /
sum(rate(support_email_sent_total[15m]))
```

## Dashboards

### Production Health

```
┌────────────────────────────────────────────┐
│ Open tickets by status                     │
│ [stacked area chart, last 24h]             │
├────────────────────────────────────────────┤
│ FRT P50/P90 by tier      Resolve P50/P90  │
│ [line chart]              [line chart]    │
├────────────────────────────────────────────┤
│ SLA breach count                           │
│ [bar chart, last 7 days]                   │
├────────────────────────────────────────────┤
│ Inbound by hour     Resolve by hour       │
│ [heatmap]            [heatmap]            │
├────────────────────────────────────────────┤
│ Cron success rate                          │
│ [line, last 7 days, target = 100%]         │
└────────────────────────────────────────────┘
```

### Operator Dashboard

```
┌────────────────────────────────────────────┐
│ Open: 17  Acknowledged: 4  In progress: 7 │
│ Awaiting customer: 3                       │
├────────────────────────────────────────────┤
│ ⚠ SLA: 2 breached, 4 at-risk (within 2h)  │
├────────────────────────────────────────────┤
│ By category                                │
│ billing: 5  auth: 4  bug: 3  other: 5     │
├────────────────────────────────────────────┤
│ Tickets per agent today                    │
│ Maria: 7  John: 5  Aisha: 4                │
└────────────────────────────────────────────┘
```

This is what the agent sees when they open `/admin/support`.

## Sentry / Error Tracking

Wrap the route handlers and the cron:

```ts
import * as Sentry from "@sentry/nextjs";

export async function POST(req: Request) {
  return Sentry.startSpan({ name: "POST /api/admin/support/tickets" }, async () => {
    try {
      // ...
    } catch (e) {
      Sentry.captureException(e, {
        tags: { feature: "support" },
        extra: { ticket_id: params.id },
      });
      throw e;
    }
  });
}
```

Sentry alerts on:
- Unhandled exceptions (default)
- Slow transactions (> 5s for the create path)
- Specific error fingerprints (e.g., "Resend rate limit hit")

## Audit Log

Separate from logs — durable, queryable, never auto-deleted.

```ts
// in supportTickets service:
async function changeStatus(id, newStatus, agent, reason) {
  await db.transaction(async tx => {
    const before = await tx.query.supportTickets.findFirst({ where: eq(...id) });
    await tx.update(supportTickets).set({ status: newStatus }).where(eq(supportTickets.id, id));
    await tx.insert(auditLog).values({
      entity: "support_ticket",
      entityId: id,
      action: "status_change",
      actor: agent.email,
      before: { status: before.status },
      after: { status: newStatus },
      reason,
      ts: new Date(),
      ip: agent.ip,
      userAgent: agent.ua,
    });
  });
}
```

Queries the audit log answers:
- "Who changed this ticket's status?"
- "What did the agent see at the time of decision?"
- "Did we follow our policy (every change has a reason)?"

The audit log is also legal-grade evidence in disputes.

## DB Query Observability

Drizzle's `logger` interface only sees the query text + bind params, not duration. To capture latency, wrap your service-layer calls with a timer (or use OpenTelemetry spans, see below).

```ts
const db = drizzle(pool, {
  schema,
  logger: {
    logQuery(q, params) {
      log.debug({ event: "db.query", q, params });
    },
  },
});

// For per-operation latency, time the call site:
async function timed<T>(name: string, fn: () => Promise<T>): Promise<T> {
  const start = performance.now();
  try {
    return await fn();
  } finally {
    const dur = performance.now() - start;
    log.debug({ event: "db.timing", name, dur_ms: dur });
    if (dur > 500) {
      log.warn({ event: "db.timing.slow", name, dur_ms: dur });
    }
  }
}

// Usage in the service layer. `.returning()` resolves to T[], so destructure
// to get the single inserted row.
const [ticket] = await timed("createTicket", () =>
  db.insert(supportTickets).values({ ... }).returning()
);
```

The OTel span wrapper shown above (`tracer.startActiveSpan`) gives you the same data plus distributed-trace context — prefer that pattern in production code, and use the simple `timed()` only for ad-hoc diagnostics.

Slow queries above the support-tickets path → file a perf bead.

## Customer-Side Observability

What the customer sees during outages:
- Status page (see triage skill `STATUS-PAGE.md`)
- In-app banner pulled from `/api/status`
- Email notification for major incidents

## Privacy / Compliance

- **PII redaction**: scrub emails, phones, full names from logs.
- **Retention**: 90 days for application logs; 7 years for audit log.
- **Access control**: log access is itself audited.
- **GDPR DSAR**: when a user requests deletion, the audit log is retained (legitimate-interest exception) but PII is replaced with `[redacted-2026-04-27]`.

## Tooling Stack (Default)

| Concern | Tool |
|---|---|
| Logs | Vercel logs / Datadog / Axiom |
| Metrics | Prometheus + Grafana, or Datadog |
| Traces | Sentry / Datadog APM / Honeycomb |
| Errors | Sentry |
| Audit log | Postgres table (long retention) |
| Status page | Statuspage / BetterStack / custom |
| Dashboards | Grafana / Mixpanel / native admin |

For solo / early-stage: Vercel logs + Sentry + a custom Grafana board against your Postgres metrics export. ~$0 for the first 6 months, scales to ~$50-100/month at 10k tickets/month.

## Validation

In a working system, you should be able to answer:

```
□ How many tickets did we get yesterday?  (metrics)
□ What was the FRT P90 last week by tier?  (metrics)
□ Why did ticket #abc123 get marked as P1?  (audit log)
□ Did the cron actually run last night?  (logs/metrics)
□ Are we breaching enterprise SLAs more this week than last?  (metrics)
□ What's the slowest API path right now?  (traces)
□ Did anyone manually change a customer's plan in the last hour?  (audit log)
```

If any of these takes > 5 minutes to answer, instrument more.

## Companion Refs

- [SCHEMA.md](SCHEMA.md) — audit log table
- [CRON-AND-ALERTS.md](CRON-AND-ALERTS.md) — Slack webhook for breach alerts
- [SECURITY.md](SECURITY.md) — audit log access control
- `/saas-customer-analytics` — broader analytics framework
- `/user-support-triage-for-saas-and-open-source-projects` — METRICS-AND-DASHBOARDS.md
