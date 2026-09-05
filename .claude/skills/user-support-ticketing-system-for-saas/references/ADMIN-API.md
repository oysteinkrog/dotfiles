# Admin API Contract

All routes guarded by `requireAdmin` + a permission key. All mutations require a `reason` and write to `auditLog`. Pattern: `src/app/api/admin/support/...`.

## GET /api/admin/support/tickets

Permission: `support.read`

```ts
const querySchema = z.object({
  status:        z.enum(STATUSES).optional(),
  priority:      z.enum(PRIORITIES).optional(),
  assignee:      z.string().optional(),
  slaBreachHours: z.coerce.number().min(0).max(168).optional(),  // urgency mode
  limit:         z.coerce.number().int().min(1).max(100).default(50),
  offset:        z.coerce.number().int().min(0).default(0),
});
```

Two modes:

**Standard:** filters → service `listAllTickets()` → enrich with users + orgs (batch via `inArray`, never N+1) → counts by status + priority → response.

**SLA-focused** (`slaBreachHours` set): merge `getTicketsApproachingSla(slaBreachHours)` + `getTicketsBreachedSla()`, sort by deadline, paginate.

Response always includes:
- `tickets[]` with computed `slaBreached` and `hoursUntilBreach`
- `counts` keyed by status
- `priorityStats` keyed by priority
- `approachingBreachCount` (within 2hr by default)
- `pagination: { limit, offset, total }`

## PATCH /api/admin/support/tickets

Permission: `support.resolve`. Always carries `reason`. Always writes audit.

```ts
const updateSchema = z.object({
  ticketId: z.string().uuid(),
  status:   z.enum(STATUSES).optional(),
  priority: z.enum(PRIORITIES).optional(),
  assignee: z.string().trim().max(100).nullable().optional(),
  reason:   adminReasonSchema.optional(),
});
```

Flow:

1. Validate JSON + zod.
2. At least one of `status/priority/assignee` must change.
3. `requireAdminMutation(... permission: "support.resolve", reason, requireReason: true)` — fails if reason missing.
4. Service `updateTicket()` applies the change (including status/priority SLA recomputation where allowed).
5. Audit log entry — `before`/`after` state + changed fields list.
6. Response: full enriched ticket.

`updateTicket` is the single mutation surface. Direct UPDATEs from handlers are forbidden.

## GET /api/admin/support/tickets/[id]/messages

Permission: `support.read`. Returns all messages with sender info hydrated:

```json
{
  "messages": [
    {
      "id": "...",
      "senderType": "customer" | "support" | "system",
      "sender": { "displayName": "...", "email": "..." } | null,
      "message": "...",
      "createdAt": "..."
    }
  ]
}
```

## POST /api/admin/support/tickets/[id]/messages

Permission: `support.assign`.

**This is the email-trigger endpoint.** Posting a message:
1. Validates `{ message: string, max: 5000 }`.
2. Inserts a `supportMessages` row with `senderType: "support"`, `senderId: <admin user id>`.
3. Calls `computeNextStatusAfterMessage(currentStatus, "support")` — usually flips to `awaiting_customer` (pauses SLA).
4. Schedules `sendTicketResponseEmail(...)` through the background hook / queue / outbox helper so the response isn't blocked.
5. Writes audit.
6. Returns the created message + new ticket status.

Integration test must verify the email actually fires.

## GET /api/admin/support/sla-metrics

Permission: `support.read`. Returns:

```json
{
  "open_count": 17,
  "breached_count": 2,
  "at_risk_count": 4,
  "by_priority": { "p0": 0, "p1": 2, "p2": 12, "p3": 3 },
  "median_first_response_hours": 6.4,
  "median_resolution_hours": 38.1,
  "computed_at": "..."
}
```

Computed fresh per request — never serve stale snapshots from a cache that doesn't invalidate on ticket updates.

## Error Envelope

Use the project's existing error helpers. In the default TypeScript shape those are typically `validationError`, `notFound`, `internalError`, and `invalidJson` from an API-error module. Match the host project.

## Audit Event Taxonomy (Add To Project)

```
support_ticket_created      — ticket id; metadata: priority, category, source
support_ticket_updated      — ticket id; before/after; changedFields
support_ticket_message_posted — ticket id; sender_type; message_id; emailSent
support_ticket_resolved     — ticket id; resolution_reason
support.sla_breached        — ticket id; userId: null (system event); priority; deadline; detectedAt
```

`support.sla_breached` is **always system-attributed** (`userId: null`). Attributing breach detection to the customer is a fundamental mis-attribution that pollutes abuse-pattern detection.

## Route-Level Directives (Next.js)

```ts
export const dynamic = "force-dynamic";   // never cache admin queue responses
export const maxDuration = 30;            // generous; SLA-focused merge can run long
```

`force-dynamic` is non-negotiable; the admin queue must reflect database truth on every request.

## Standard Mode — N+1 Elimination

The list path enriches with user + org names via batched `inArray` lookups, never per-row joins:

```ts
const userIds = [...new Set(result.tickets.map((t) => t.userId))];
const orgIds  = [...new Set(result.tickets.map((t) => t.orgId).filter(Boolean))] as string[];

const [users, orgs] = await Promise.all([
  userIds.length ? db.query.users.findMany({
    where: inArray(users.id, userIds),
    columns: { id: true, displayName: true, email: true },
  }) : [],
  orgIds.length ? db.query.organizations.findMany({
    where: inArray(organizations.id, orgIds),
    columns: { id: true, name: true },
  }) : [],
]);
const userMap = new Map(users.map((u) => [u.id, u]));
const orgMap  = new Map(orgs.map((o) => [o.id, o]));
```

Two queries serve any page size up to the configured `limit` (50). `Map.get(id)` is O(1); never replace with `.find()`.

The `slaBreached` boolean returned per ticket is computed at response time:

```ts
const isBreached = slaDeadline && now > slaDeadline && SLA_ACTIVE_STATUSES.has(ticket.status);
```

`SLA_ACTIVE_STATUSES` is `new Set(OPEN_TICKET_STATUSES)` — imported from the service layer, never re-declared per route.

## Status & Priority Counts (Single GroupBy Per Dimension)

Counts are computed via two `GROUP BY` queries, not by counting in JS:

```ts
const statusCounts = await db.select({
  status: supportTickets.status,
  count: sql<number>`count(*)::int`,
}).from(supportTickets)
  .where(countWhereClause)        // priority/assignee filters, not status
  .groupBy(supportTickets.status);
```

A separate `priorityStats` groupBy uses status/assignee filters but excludes the priority filter — so changing one filter dimension doesn't zero out the others' pills.

## PATCH — No-Op Rejection + Audit Shape

Reject updates that would change nothing:

```ts
const statusChanged   = status !== undefined && status !== existing.status;
const priorityChanged = priority !== undefined && priority !== existing.priority;
const assigneeChanged = normalizedAssignee !== undefined && normalizedAssignee !== (existing.assignee ?? null);
if (!statusChanged && !priorityChanged && !assigneeChanged) {
  return validationError({ update: ["Update payload does not change any fields"] }, "Validation failed");
}
```

Audit log payload after the update succeeds:

```ts
await mutation.context.logAction({
  actionType: "support_ticket_updated",
  entityType: "support_ticket",
  entityId: ticketId,
  beforeState: { status: existing.status, priority: existing.priority, assignee: existing.assignee, resolvedAt: existing.resolvedAt ?? null },
  afterState:  { status: updated.status,  priority: updated.priority,  assignee: updated.assignee,  resolvedAt: updated.resolvedAt ?? null  },
  metadata: {
    update: {
      status:   statusChanged   ? status            : null,
      priority: priorityChanged ? priority          : null,
      assignee: assigneeChanged ? (normalizedAssignee ?? null) : null,
    },
    changedFields: [
      ...(statusChanged   ? ["status"]   : []),
      ...(priorityChanged ? ["priority"] : []),
      ...(assigneeChanged ? ["assignee"] : []),
    ],
  },
});
```

`changedFields` is the index admins query against ("show me every assignee change last week"). Without it, the audit log is unqueryable noise.

## Operations-Cockpit Compatibility

Some adjacent cockpits (operations summary, command center) consume `/api/admin/support/tickets?slaBreachHours=N` directly. Their normalizer (`src/lib/admin/operations-support-sla.ts`) accepts both `snake_case` and `camelCase` keys:

```ts
{
  thresholdHours: payload.threshold_hours ?? payload.thresholdHours ?? defaultThresholdHours,
  total:           payload.total            ?? payload.tickets.length,
  breachedCount:   payload.breached_count   ?? payload.breachedCount   ?? null,
  approachingCount: payload.approaching_count ?? payload.approachingCount ?? null,
}
```

When extending the response, either update all consumers in lock-step or deliberately support both response shapes as a documented contract. Do not add quiet compatibility shims without naming the consumers and removal condition.
