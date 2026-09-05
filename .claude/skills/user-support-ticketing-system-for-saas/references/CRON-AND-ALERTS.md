# Cron + Alerting

## /api/cron/sla-alerts

Runs every 15-30 min via Vercel Cron / GitHub Actions / your scheduler. Auth via `CRON_SECRET` header check.

```ts
export async function POST(req: Request) {
  if (req.headers.get("x-cron-secret") !== process.env.CRON_SECRET) {
    return new Response("forbidden", { status: 403 });
  }

  const breached    = await getTicketsBreachedSla();
  const atRisk      = await getTicketsApproachingSla(2);  // within 2h

  // Persist new states
  for (const t of breached) {
    if (t.slaStatus !== "breached") {
      await markBreached(t.id);   // sets slaStatus, slaBreachedAt, slaStatusUpdatedAt
      await notifyInternal({ type: "breach", ticket: t });
    }
  }
  for (const t of atRisk) {
    if (t.slaStatus === "ok") {
      await markAtRisk(t.id);
      await notifyInternal({ type: "at_risk", ticket: t });
    }
  }

  return Response.json({ breached: breached.length, at_risk: atRisk.length });
}
```

## Internal Alert Surface (Webhook Example)

Optional but recommended. Set a support-alert webhook URL and:

```ts
async function notifyInternal({ type, ticket }) {
  if (!process.env.SUPPORT_ALERT_SLACK_WEBHOOK_URL) return;
  const emoji = type === "breach" ? ":rotating_light:" : ":warning:";
  await fetch(process.env.SUPPORT_ALERT_SLACK_WEBHOOK_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      text: `${emoji} ${type === "breach" ? "SLA BREACHED" : "Approaching SLA"} — ` +
            `${ticket.priority.toUpperCase()} <${baseUrl}/admin/support/tickets|${ticket.id.slice(0,8)}>: ${ticket.subject}`,
    }),
  });
}
```

The cron NEVER messages the customer. Customer-facing email comes from admin replies only.

## Idempotency

The cron is idempotent: running it twice in quick succession should not double-alert. Guarded by:
- `slaStatus !== "breached"` check before transitioning
- `slaBreachedAt` is sticky, so re-runs see the same breach time

## Scheduling

Vercel:
```json
// vercel.json
{
  "crons": [
    { "path": "/api/cron/sla-alerts", "schedule": "*/15 * * * *" }
  ]
}
```

GitHub Actions equivalent in a `.github/workflows/cron-sla.yml` posts to the URL with the secret.

## Don't Auto-Resolve

The most common cron-related bug we've seen is "auto-close tickets older than N days". Don't. Closing tickets is a customer-facing action; it should require a human decision. The cron flags; the operator resolves.

## Optional Cron: Daily SLA Report

A second cron at `/api/cron/sla-daily-report` aggregates the last 24h and posts to a Slack channel. Useful for weekly retros without being noisy.

## Cron Secret Hygiene

`CRON_SECRET` is generated once and rotated quarterly. If you forget to set it before deploy, the cron returns 403 and SLAs go untracked silently — wire a smoke test that pings the cron endpoint at deploy time and asserts non-403.

## Two-Phase Architecture (Production Pattern)

Split the cron into two pure functions:

```ts
// Phase 1: pure DB. Returns categorized tickets + audit-event payloads.
export async function updateSlaStatuses(hoursUntilBreach = 2): Promise<{
  breached: Ticket[]; atRisk: Ticket[]; ok: Ticket[];
  updatedCount: number; breachLogCount: number;
}> { ... }

// Phase 2: invokes phase 1 (DI'd for tests), enriches, posts alert.
export async function sendSlaBreachAlerts(
  hoursUntilBreach = 2,
  _deps?: { updateSlaStatuses?: typeof updateSlaStatuses },
): Promise<{ sent: boolean; ticketCount: number; ... }> { ... }
```

The `_deps?: { updateSlaStatuses }` parameter is the test seam — phase-2 tests pass a deterministic phase 1 instead of fixturing the DB.

Why two phases:
- Phase 1 is idempotent and testable without alert-provider credentials.
- Phase 2's I/O failure (provider outage, network) doesn't break DB state-keeping.
- They fail independently; observability gets cleaner failure signals.

## Transactional Status Update + Audit (No Gaps)

Phase 1 wraps the status updates **and** breach audit-log inserts in a single transaction:

```ts
await db.transaction(async (tx) => {
  await Promise.all(updates.map((u) =>
    tx.update(supportTickets).set({
      slaStatus: u.status,
      slaStatusUpdatedAt: now,
      slaBreachedAt: u.setBreachedAt ? now : undefined,
      updatedAt: now,
    }).where(eq(supportTickets.id, u.ticketId))
  ));
  if (breachAuditEvents.length > 0) {
    await tx.insert(auditLog).values(breachAuditEvents);
  }
});
```

A crash between status writes and audit inserts would leave compliance with "ticket says breached but no audit row" (or vice versa) — both states worse than either being wrong alone.

## System-Attributed Audit (`userId: null`)

Every breach event is **system-attributed**, not customer-attributed:

```ts
breachAuditEvents.push({
  userId: null,                                    // system event
  eventType: "support.sla_breached",
  eventData: { ticketId, orgId, priority, slaDeadline, detectedAt },
});
```

Attributing breach detection to the customer ("user X breached their own ticket") is wrong — the customer didn't breach; the team did. Wrong attribution also poisons abuse-pattern analytics ("this customer keeps breaching SLAs" — no, the team keeps missing them).

## Structured Severity Alert

Build the alert payload sectioned by severity. Slack Block Kit is one concrete format; PagerDuty, Discord, Mattermost, Teams, email, or incident tooling should preserve the same hierarchy:

```
Header  :rotating_light: SLA Alert: {N} tickets at risk or breached
Divider
:fire: BREACHED ({n}):
  *{subject}*
  :fire: BREACHED | Ticket: `{id}` | Org: {org} | Assignee: {a or *UNASSIGNED*}
Divider
:red_circle: P0 CRITICAL ({n}):
  *{subject}*
  :clock1: {h}h left  | Ticket | Org | Assignee
Divider
:large_orange_circle: P1 HIGH ({n}):
  ...
Divider
Context: :large_yellow_circle: {n} additional P2/P3 tickets approaching SLA
Divider
Context: View all tickets at /admin/support/tickets
```

Why severity-sectioned: an engineer paged at 3 AM by "5 tickets at risk" scrolls past it. A clear "1 breached, 2 P0 critical, 1 P1 high" block surfaces the action without opening the dashboard.

The unstructured `text` fallback (or provider equivalent) summarizes counts so notifications and clients without rich-block support still get useful information.

## Webhook Timeout (Required)

```ts
const response = await fetch(webhookUrl, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(payload),
  signal: AbortSignal.timeout(10000),   // 10 seconds
});
```

Without it, a slow alert endpoint stalls the cron worker. Next cron run starts overlapping; within an hour the worker pool saturates and SLA detection stops entirely. Webhook failing fast is dramatically better than cron failing slowly.

## Org-Name Enrichment Before Alert

Phase 2 enriches tickets with org names *before* building the payload:

```ts
const enrichedAtRisk    = await enrichTicketsWithOrgName(atRisk);
const enrichedBreached  = await enrichTicketsWithOrgName(breached);
```

`enrichTicketsWithOrgName` does a single batched `inArray(organizations.id, orgIds)` query. The alert then surfaces `Org: {name}` instead of `Org: {uuid}` — engineers can match the alert to the customer instantly.
