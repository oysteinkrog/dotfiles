# Outbound Webhooks (Customer-Subscribable Events)

Enterprise customers want their own automation hooks: "When my ticket changes status, POST to our internal slack/jira/CRM." Outbound webhooks turn the support system into an event source other systems can subscribe to. The pattern is the inverse of [INBOUND-WEBHOOK-INGESTION.md](INBOUND-WEBHOOK-INGESTION.md) — same concerns, different direction.

## Schema

```ts
export const outboundWebhookEndpoints = pgTable("outbound_webhook_endpoints", {
  id: uuid().primaryKey().defaultRandom(),
  ownerId: uuid().references(() => users.id).notNull(),     // who owns the endpoint (admin)
  orgId:   uuid().references(() => organizations.id),        // optional: scoped to an org
  url: text().notNull(),                                     // https://customer.example.com/webhook
  description: text(),                                       // human-readable
  secret: text().notNull(),                                  // HMAC signing secret (random, 64 bytes hex)
  subscribedEvents: jsonb().$type<string[]>().notNull(),     // ['ticket.created', 'ticket.resolved']
  active: boolean().default(true).notNull(),
  failureCount: integer().default(0).notNull(),
  lastDeliveredAt: timestamp({ withTimezone: true }),
  lastFailureAt: timestamp({ withTimezone: true }),
  createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
}, t => [
  index("outbound_webhook_org_idx").on(t.orgId),
  index("outbound_webhook_active_idx").on(t.active),
]);

export const outboundWebhookDeliveries = pgTable("outbound_webhook_deliveries", {
  id: uuid().primaryKey().defaultRandom(),
  endpointId: uuid().references(() => outboundWebhookEndpoints.id, { onDelete: "cascade" }).notNull(),
  eventId: uuid().notNull(),                                 // unique per delivery
  eventType: text().notNull(),
  payload: jsonb().notNull(),
  attemptCount: integer().default(0).notNull(),
  status: text().notNull(),                                  // 'pending' | 'delivered' | 'failed' | 'abandoned'
  responseStatus: integer(),
  responseBody: text(),
  enqueuedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  deliveredAt: timestamp({ withTimezone: true }),
  abandonedAt: timestamp({ withTimezone: true }),
}, t => [
  index("outbound_delivery_endpoint_idx").on(t.endpointId, t.status),
  index("outbound_delivery_pending_idx").on(t.status, t.enqueuedAt),
]);
```

## Event Catalog

Define the public catalog of events. Customers subscribe to a subset:

```ts
const PUBLIC_WEBHOOK_EVENTS = [
  "ticket.created",
  "ticket.status_changed",
  "ticket.resolved",
  "ticket.message_added",       // public messages only — never internal notes
  "ticket.sla_breached",
  "ticket.linked_to_incident",
] as const;
```

Internal-only events (`internal_note_added`, `audit_*`, `cost_*`) are NOT in the catalog. **Whitelist is the safety boundary.**

## Subscription UI

Customer-admin (someone who owns an org with API access) creates endpoints via UI:

```
SUBSCRIPTIONS

+ New endpoint
  URL: https://acme.example.com/support-events
  Events: [✓] ticket.created  [✓] ticket.resolved  [ ] ticket.message_added
  Secret: hwk_abc123...                 [Reveal] [Rotate]
  [Test] [Save]
```

`Test` sends a `ping` event to verify connectivity before enabling.

## Event Emission

When the service layer commits a state change, fan out to subscribed endpoints:

```ts
async function emitWebhookEvent(event: { type: string; data: Record<string, unknown>; orgId?: string }) {
  const endpoints = await db.query.outboundWebhookEndpoints.findMany({
    where: and(
      eq(outboundWebhookEndpoints.active, true),
      sql`${outboundWebhookEndpoints.subscribedEvents} @> ${JSON.stringify([event.type])}::jsonb`,
      event.orgId ? eq(outboundWebhookEndpoints.orgId, event.orgId) : undefined,
    ),
  });

  for (const endpoint of endpoints) {
    await db.insert(outboundWebhookDeliveries).values({
      endpointId: endpoint.id,
      eventId: randomUUID(),
      eventType: event.type,
      payload: event.data,
      status: "pending",
    });
  }
  // Worker picks up pending deliveries
}
```

Wire from service layer:

```ts
async function updateTicket(...) {
  // ... existing logic ...
  if (statusChanged) {
    await emitWebhookEvent({
      type: "ticket.status_changed",
      data: { ticketId, before: existing.status, after: nextStatus, at: now.toISOString() },
      orgId: existing.orgId,
    });
  }
}
```

## Worker — Delivery With Retry

A separate worker (cron or always-on) picks up `pending` deliveries:

```ts
async function deliverPendingWebhooks() {
  const pending = await db.query.outboundWebhookDeliveries.findMany({
    where: and(
      eq(outboundWebhookDeliveries.status, "pending"),
      lte(outboundWebhookDeliveries.attemptCount, MAX_ATTEMPTS),
    ),
    orderBy: asc(outboundWebhookDeliveries.enqueuedAt),
    limit: 100,
  });

  for (const delivery of pending) {
    const endpoint = await getEndpoint(delivery.endpointId);
    if (!endpoint || !endpoint.active) continue;

    const body = JSON.stringify({
      id: delivery.eventId,
      type: delivery.eventType,
      data: delivery.payload,
      timestamp: delivery.enqueuedAt.toISOString(),
    });
    const signature = hmacSha256(endpoint.secret, body);

    try {
      const res = await fetch(endpoint.url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Webhook-Signature": signature,
          "X-Webhook-Event-Id": delivery.eventId,
          "X-Webhook-Event-Type": delivery.eventType,
          "User-Agent": "Acme-Support-Webhooks/1.0",
        },
        body,
        signal: AbortSignal.timeout(10_000),
      });
      if (res.status >= 200 && res.status < 300) {
        await markDelivered(delivery.id, res.status);
        await resetEndpointFailureCount(endpoint.id);
      } else {
        await scheduleRetry(delivery.id, res.status, await res.text().catch(() => ""));
        await incrementEndpointFailureCount(endpoint.id);
      }
    } catch (err) {
      await scheduleRetry(delivery.id, null, err.message);
    }
  }
}
```

## Retry Strategy

Exponential backoff with jitter. Drop after N failures:

```ts
const RETRY_DELAYS_SEC = [60, 300, 900, 3600, 21600];  // 1min, 5min, 15min, 1h, 6h
const MAX_ATTEMPTS = RETRY_DELAYS_SEC.length;

async function scheduleRetry(deliveryId: string, status: number | null, body: string) {
  const delivery = await getDelivery(deliveryId);
  const nextAttempt = delivery.attemptCount + 1;
  if (nextAttempt > MAX_ATTEMPTS) {
    await db.update(outboundWebhookDeliveries).set({
      status: "abandoned",
      abandonedAt: new Date(),
      responseStatus: status,
      responseBody: body.slice(0, 1000),
    }).where(eq(outboundWebhookDeliveries.id, deliveryId));
    return;
  }
  const delaySec = RETRY_DELAYS_SEC[nextAttempt - 1] + Math.random() * 30;
  // Mark for retry; worker re-picks based on enqueuedAt
  await db.update(outboundWebhookDeliveries).set({
    attemptCount: nextAttempt,
    enqueuedAt: new Date(Date.now() + delaySec * 1000),
    responseStatus: status,
    responseBody: body.slice(0, 1000),
  }).where(eq(outboundWebhookDeliveries.id, deliveryId));
}
```

## Endpoint Auto-Disable

After 50 consecutive failures, disable the endpoint and alert the owner:

```ts
async function incrementEndpointFailureCount(endpointId: string) {
  const ep = await db.query.outboundWebhookEndpoints.findFirst({ where: eq(outboundWebhookEndpoints.id, endpointId) });
  if (!ep) return;
  const newCount = ep.failureCount + 1;
  if (newCount >= 50) {
    await db.update(outboundWebhookEndpoints).set({ active: false, failureCount: newCount, lastFailureAt: new Date() }).where(eq(outboundWebhookEndpoints.id, endpointId));
    await sendEndpointDisabledEmail(ep.ownerId, ep);
  } else {
    await db.update(outboundWebhookEndpoints).set({ failureCount: newCount, lastFailureAt: new Date() }).where(eq(outboundWebhookEndpoints.id, endpointId));
  }
}
```

Auto-disable prevents zombie endpoints from generating ongoing failed-delivery noise.

## Signature Verification (For The Receiver)

The customer's receiver verifies your signature:

```ts
// Customer-side code (documented in your developer docs)
import crypto from "node:crypto";
const signature = req.headers["x-webhook-signature"];
const body = await req.text();
const computed = crypto.createHmac("sha256", WEBHOOK_SECRET).update(body).digest("hex");
if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(computed))) {
  return res.status(401).end();
}
```

Document this snippet in your public developer docs. Most security regressions on the customer side come from naive signature checks.

## Replay Endpoint

Customers can replay events they missed (after restoring their service from a backup, etc.):

```
POST /api/customer/webhooks/{endpointId}/replay
{
  "since": "2026-04-25T00:00:00Z",
  "until": "2026-04-26T00:00:00Z",
  "eventTypes": ["ticket.resolved"]
}
```

Replays come from the deliveries table — no new event-type-aware code needed. Rate-limit replays (1 per endpoint per hour).

## Privacy Filters On Payload

The event payload includes ticket data. Apply the same filters as the customer-data export:

```ts
function buildTicketEventPayload(ticket: SupportTicket): Record<string, unknown> {
  return {
    id: ticket.id,
    subject: ticket.subject,
    description: ticket.description,        // customer's own input
    priority: ticket.priority,
    status: ticket.status,
    category: ticket.category,
    createdAt: ticket.createdAt.toISOString(),
    resolvedAt: ticket.resolvedAt?.toISOString() ?? null,
    // NEVER include:
    //   - assignee (admin's name)
    //   - internal notes
    //   - audit log
    //   - cost data
    //   - AI scores
  };
}
```

## Test Webhook UI

In the subscription UI, "Test" button sends a synthetic event:

```ts
const testEventPayload = {
  id: "test-evt-" + randomUUID(),
  type: "ping",
  data: { message: "Hello from Acme Support webhooks", timestamp: new Date().toISOString() },
};
```

Receiver should reply 2xx; the UI shows green checkmark + response body. Catches misconfiguration before a real event fires.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Synchronous emit in the API request handler | Slow customer endpoints stall ticket creation |
| Including internal notes / audit data in event payload | Privacy regression; leaks team internals |
| No HMAC signing | Endpoint can't verify the sender; spoofing risk |
| No retry policy | A 500 from the customer endpoint loses the event |
| Infinite retries | Zombie endpoints generate forever-load |
| Same payload shape across event types | Customer parsers brittle; document each event type's schema |
| No replay mechanism | Customers with downtime miss data permanently |
| Customer-visible secret stored as plaintext in admin UI | Showing once-only at create + offering rotate is the standard |
| Webhook URL not validated (can target localhost / internal IPs) | SSRF risk; validate URL is reachable + non-private |
| No dead-letter visibility for abandoned deliveries | Customers don't know they're missing events |
| No rate-limit on retries | Customer endpoint flooded |

## Wire Points Checklist

- [ ] `outbound_webhook_endpoints` table with HMAC secret
- [ ] `outbound_webhook_deliveries` table with attempt count + status
- [ ] Public event catalog (whitelist; no internal events)
- [ ] Subscription UI: create / test / rotate-secret / disable
- [ ] SSRF protection on URL validation (no localhost / private IPs)
- [ ] Async emission (queue, not inline)
- [ ] Worker picks up `pending` deliveries with attempt-count gating
- [ ] HMAC-SHA256 signing with `X-Webhook-Signature` header
- [ ] Idempotency header (`X-Webhook-Event-Id`)
- [ ] Timeout per delivery (10s)
- [ ] Retry schedule: 1min, 5min, 15min, 1h, 6h
- [ ] Auto-disable after 50 consecutive failures + owner email
- [ ] Replay endpoint with rate limit
- [ ] Privacy filter on payload (no admin names, no internal notes)
- [ ] Test-webhook button in UI
- [ ] Public developer docs with verification snippet
- [ ] Dead-letter view in admin UI for abandoned deliveries
- [ ] Audit on subscription create/delete/secret-rotate
