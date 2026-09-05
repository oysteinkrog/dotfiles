# User-Facing API Contract

All routes guarded by `requireUser`. Rate-limit MUST resolve identity *before* applying the limit so paid users don't share buckets with anonymous visitors.

## POST /api/support/tickets

Create a new ticket.

```ts
const createSchema = z.object({
  subject:     z.string().min(3).max(200),
  description: z.string().min(10).max(10000),
  category:    z.enum(CATEGORIES).default("other"),
  priority:    z.enum(PRIORITIES).default("p2"),
  pageUrl:     z.string().url().optional(),
  screenshotUrl: z.string().url().optional(),
});
```

Flow:
1. `requireUser` → identity
2. `enforceRateLimit(req, auth.user)` — keyed to user, not IP
3. Validate body
4. Call `createTicket(...)` from service layer — sets `slaDeadline` based on user's tier
5. Schedule `sendTicketCreatedEmail(...)` through the background hook / queue / outbox helper
6. Return `{ id, status, priority, slaDeadline, createdAt }`

## GET /api/support/tickets

List the authenticated user's tickets (org-scoped if applicable).

```ts
const querySchema = z.object({
  status: z.enum(STATUSES).optional(),
  limit:  z.coerce.number().int().min(1).max(50).default(20),
  offset: z.coerce.number().int().min(0).default(0),
});
```

Returns the user's tickets with computed `hoursUntilBreach`. Do NOT expose admin-only fields (`assignee`, `slaBreachedAt`, `slaStatusUpdatedAt` — keep them admin-only).

## GET /api/support/tickets/[id]

Detail view + messages. Verify the requesting user OR a member of the ticket's org. Return 404 (not 403) on access denial — don't leak existence.

```json
{
  "ticket": { ... },
  "messages": [
    { "id", "senderType", "message", "createdAt", "fromYou": true|false }
  ]
}
```

`fromYou` collapses the customer/support split into a UI-friendly boolean.

## POST /api/support/tickets/[id]/messages

Customer reply.

```ts
const schema = z.object({ message: z.string().min(1).max(5000) });
```

Flow:
1. `requireUser` + ownership check (404 on miss).
2. Reject if ticket status is `closed` (terminal). For `resolved`, the project's policy decides; a common rule is reopen-via-reply only inside a short window such as 7 days.
3. Insert message with `senderType: "customer"`, `senderId: <user>`.
4. Service computes new status: if currently `awaiting_customer` → `in_progress` (resumes SLA clock).
5. Optional: notify support via an internal alert provider (no customer email — they wrote it).
6. Return new message + updated ticket status.

## Rate Limit Tier (Critical)

Rate-limit middleware MUST consult subscription tier *before* deciding the bucket:

```ts
async function enforceRateLimit(req: Request, user: AuthedUser) {
  const tier = user.subscriptionStatus === "active" ? "paid" : "free";
  const limit = LIMITS[tier];                         // 100/min vs 20/min
  return checkLimit(req, { key: `support:${user.id}`, limit });
}
```

Anonymous users use IP keying. Authenticated users use `user.id`. Never key paid users by IP — shared-IP customers (offices, mobile carriers) get squeezed otherwise.

## Edge / Auth

If the project uses Edge runtime for these routes, mind that:
- `requireUser` may be slow on cold starts; favor Node runtime here unless latency is critical
- Rate-limit data store must be available in Edge (Upstash Redis works; Postgres-backed limiters often don't)

## Cache Headers — `private` Only

User-facing list/detail responses ship `Cache-Control: private`:

```ts
return NextResponse.json({...}, { headers: withCacheHeaders("private") });
```

Never `public`. A CDN that caches `public` ticket lists serves user A's tickets to user B — that's the kind of bug companies do not survive.

## Ticket Access Verification (`verifyTicketAccess`)

A user has access to a ticket iff:

1. They created it (`ticket.userId === currentUser.id`), OR
2. They belong to the ticket's `orgId` AND that org has **billable-seat coverage** (active/past_due subscription with a *real* Stripe or PayPal subscription id — `sub_test_*` test ids do not unlock teammate access).

```ts
async function verifyTicketAccess(ticketId, userId): Promise<boolean> {
  const [ticket] = await db.select(...).from(supportTickets).where(eq(supportTickets.id, ticketId)).limit(1);
  if (!ticket) return false;
  if (ticket.userId === userId) return true;
  if (!ticket.orgId) return false;
  const [m] = await db.select({...}).from(organizationMembers).innerJoin(organizations, ...).where(
    and(
      eq(organizationMembers.userId, userId),
      eq(organizationMembers.orgId, ticket.orgId),
      inArray(organizations.subscriptionStatus, ["active", "past_due"]),
    )
  ).limit(1);
  return organizationProvidesBillableSeatCoverage({
    subscriptionStatus: m?.orgSubscriptionStatus,
    stripeSubscriptionId: m?.stripeSubscriptionId,
    paypalSubscriptionId: m?.paypalSubscriptionId,
  });
}
```

This gate runs on every customer-side message-add and detail read. Privacy regressions are silent — a teammate who shouldn't see a ticket reads it for weeks before discovery.

## Compile-Time Block: Customer PATCH Cannot Send `awaiting_customer`

`awaiting_customer` is the auto-flip the service layer sets when *support* replies. The customer-side PATCH must not accept it from the client. Block at compile time **and** in Zod:

```ts
// Client side
export type CustomerUpdatableStatus = Exclude<TicketStatus, "awaiting_customer">;
async function updateTicketStatus(ticketId: string, status: CustomerUpdatableStatus) { ... }

// Server side (Zod)
const customerStatusSchema = z.enum(["open", "acknowledged", "in_progress", "resolved", "closed"]);
```

Compile-time catches honest client mistakes; Zod catches hand-rolled curl.

## Unified Listing — Tickets + Legacy Requests

If the project has both `supportTickets` and `supportRequests` (legacy contact form), `GET /api/support/tickets` returns the **union**, tagged with `kind`:

```ts
const merged = [...ticketsTagged, ...requestsTagged].sort(
  (a, b) => toMillis(b.createdAt) - toMillis(a.createdAt)
);
const sliced = merged.slice(offset, offset + limit);
return { tickets: sliced, total: ticketTotal + requestTotal, limit, offset };
```

Each row carries `kind: "ticket" | "request"`. Tickets have `slaDeadline`; requests expose only customer-safe response fields. Never leak raw admin notes into the user API. The UI uses `kind` to render the right CTA: "View conversation" (ticket) vs "View response" (request).

This pattern is what makes "View conversation" links from old emails work forever — the resolved support_request from 6 months ago still appears on `/support` and the user can find it instead of filing a duplicate.
