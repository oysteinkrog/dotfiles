# Status Page Integration

The status page is the *public-facing* truth of system health. The support ticketing system is the *private-facing* source of customer pain. Connecting them creates a feedback loop where each amplifies the other: status updates pre-empt tickets; ticket clusters trigger status investigations.

This file is the architectural pattern.

## Two Status-Page Topologies

### Topology A — Internal Status Page (You Own It)

You run a status page on your own infra (a `/status` route or a dedicated subdomain). You can read/write programmatically.

### Topology B — External (Statuspage, Better Uptime, Instatus)

Third-party status page (Atlassian Statuspage, Better Stack, Instatus, etc.). Integration is via webhook + API.

The pattern below works for both; the difference is where the API calls go.

## Schema Addition

```ts
export const incidents = pgTable("incidents", {
  id: uuid().primaryKey().defaultRandom(),
  externalId: text(),                                    // statuspage incident id
  title: text().notNull(),
  status: text().notNull(),                              // investigating | identified | monitoring | resolved
  impact: text().notNull(),                              // none | minor | major | critical
  startedAt: timestamp({ withTimezone: true }).notNull(),
  resolvedAt: timestamp({ withTimezone: true }),
  affectedComponents: jsonb().$type<string[]>(),         // ['api', 'auth']
  createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
}, t => [
  index("incidents_status_idx").on(t.status),
  index("incidents_started_idx").on(t.startedAt),
]);
```

## Five Integration Loops

### Loop 1 — Cluster Detection → Status Page

When ticket-cluster detection (see [PROACTIVE-AND-PREDICTIVE-SUPPORT.md](PROACTIVE-AND-PREDICTIVE-SUPPORT.md)) finds 5+ tickets with similar text in 30 minutes, prompt admin to escalate to status page:

```
🔥 Cluster detected (8 tickets in 30min)
   "Cannot upload files"
   First: 12 minutes ago
   Suggested action: Create status page incident
   [Investigate cluster] [Create incident...] [Dismiss]
```

Click "Create incident" → admin reviews title + initial message → owner-tier confirmation → `POST /api/admin/incidents/create` → status page updated.

The mode-switch from "ticket triage" to "incident response" is the key value.

### Loop 2 — New Incident → Auto-Tag Recent Tickets

When an incident is created, sweep tickets filed during the incident window with similar topic:

```ts
async function tagTicketsWithIncident(incident: Incident) {
  const tickets = await listTicketsCreatedBetween(incident.startedAt, new Date());
  const incidentEmbedding = await embedText(`${incident.title}\n${incident.affectedComponents.join(" ")}`);
  for (const ticket of tickets) {
    const ticketEmb = await embedText(`${ticket.subject}\n${ticket.description.slice(0, 1000)}`);
    if (cosineSimilarity(ticketEmb, incidentEmbedding) > 0.80) {
      await createTicketLink({
        fromTicketId: ticket.id,
        externalRefKind: "incident",
        externalRefId: incident.id,
        kind: "linked_to_incident",
        reason: "Auto-tagged via similarity match during incident window",
      });
    }
  }
}
```

Threshold tuned per project (start at 0.80). Admins can manually link/unlink.

### Loop 3 — Active Incident → Widget Banner

When `incident.status !== "resolved"` and `incident.impact !== "none"`, the support widget renders a banner:

```tsx
function SupportWidget() {
  const { data: activeIncident } = useActiveIncident();
  return (
    <div className="floating-widget">
      {activeIncident && (
        <div className="bg-amber-50 border-l-4 border-amber-500 p-3 text-sm">
          <p className="font-medium">⚠ Known issue: {activeIncident.title}</p>
          <p className="text-muted">Status: {activeIncident.status}. Updates: <a href={statusPageUrl(activeIncident.id)}>status page</a></p>
        </div>
      )}
      {/* ... rest of widget ... */}
    </div>
  );
}
```

Reduces inbound-ticket volume during outages. Customers self-deflect when they see the banner.

### Loop 4 — Active Incident → Pre-Filing Form Hint

In the create-ticket form, if the customer's draft text overlaps with an active incident, surface inline:

```tsx
function NewTicketForm() {
  const [description, setDescription] = useState("");
  const debouncedText = useDebounce(description, 500);
  const { data: matchedIncident } = useIncidentMatch(debouncedText);

  return (
    <form>
      <textarea value={description} onChange={...} />
      {matchedIncident && (
        <div className="bg-amber-50 p-3 text-sm">
          <p>📍 We're already investigating: <strong>{matchedIncident.title}</strong></p>
          <p>Updates at <a href={...}>status page</a>. You can still file a ticket if your issue is different.</p>
        </div>
      )}
      <button>Create Ticket Anyway</button>
    </form>
  );
}
```

Combines proactive deflection with the customer's right to file — the button always wins.

### Loop 5 — Incident Resolution → Fan-Out To Linked Tickets

When the incident is marked resolved, all `linked_to_incident` tickets get a system message + their status auto-flipped to `awaiting_customer` (so the customer can confirm or report still-broken):

```ts
async function onIncidentResolved(incident: Incident) {
  const linkedTickets = await db.select().from(ticketRelations)
    .where(and(
      eq(ticketRelations.kind, "linked_to_incident"),
      eq(ticketRelations.externalRefId, incident.id),
    ));

  const resolutionMessage = `Good news — the issue you reported was related to a recent incident:\n\n${incident.title}\n\nWe've identified and resolved the problem. Could you confirm whether things are working for you now?\n\nIf you're still seeing issues, just reply to this message.`;

  for (const link of linkedTickets) {
    await scheduleSupportSideEffect(
      () => addApprovedCustomerMessage({
        ticketId: link.fromTicketId,
        senderType: "support",
        message: resolutionMessage,
        approvalId: incident.resolutionApprovalId,
      }),
      { ticketId: link.fromTicketId, incidentId: incident.id },
      "Incident resolution fan-out scheduled outside request",
    );
    await updateTicket({ ticketId: link.fromTicketId, status: "awaiting_customer" });
  }
}
```

Twenty tickets resolved by one approval. Audit captures incident-id + approval-id on each.

## Webhook Integration (External Status Pages)

Statuspage / Better Stack push events via webhook on incident state changes. Wire:

```ts
// /api/webhooks/statuspage
export async function POST(request: Request) {
  const signature = request.headers.get("x-webhook-signature");
  const body = await request.text();
  if (!verifyHmac(body, signature, env.STATUSPAGE_WEBHOOK_SECRET)) {
    return new Response("Invalid signature", { status: 401 });
  }
  const event = JSON.parse(body);
  switch (event.type) {
    case "incident.created":  return handleIncidentCreated(event.data);
    case "incident.updated":  return handleIncidentUpdated(event.data);
    case "incident.resolved": return handleIncidentResolved(event.data);
  }
  return new Response("OK");
}
```

Every webhook handler is idempotent — replays of the same event don't double-fan-out. Use `event.id` deduplication.

## Public RSS / JSON Feed

Status pages should expose a feed:

```
GET /api/status/feed.json
{
  "currentStatus": "operational" | "minor" | "major",
  "activeIncidents": [
    { "id", "title", "impact", "startedAt", "components" }
  ],
  "scheduledMaintenance": [...],
}
```

Same content as the status page UI; lets external monitors and dashboards consume programmatically.

## Internal "Maintenance Mode" Coordination

Scheduled maintenance windows pre-announce. Wire:

1. Admin schedules: `POST /api/admin/maintenance` with title, start, end, components
2. 24h before: customers in affected segments get an email
3. T-15min: status page banner activates
4. During: ticket creation form shows banner; new tickets auto-tagged
5. End: status page resolves; tagged tickets get a "thanks for your patience" message (owner-approved boilerplate)

The audit trail captures every announcement send for compliance.

## Component-Level Granularity

Status pages have *components* (api, auth, billing, dashboard). Tickets have *categories*. Map them:

```ts
const COMPONENT_TO_CATEGORY: Record<string, SupportCategory[]> = {
  api: ["bug", "access"],
  auth: ["auth"],
  billing: ["billing"],
  dashboard: ["bug", "access"],
};
```

Affected-component → category map drives auto-tagging precision. A "billing" component incident auto-tags only `billing` tickets in the window, not `bug` tickets.

## Cross-Reference In Conversation Thread

When a ticket gets `linked_to_incident`, show the link in the customer-facing conversation:

```
─── system · 5 min ago ─────────────────────────────────
This ticket is linked to an active incident:
📍 API latency (status: investigating)
View updates: status.example.com/incidents/abc
────────────────────────────────────────────────────────
```

Customer sees they're not alone; expectations re-set.

## Internal-Only Component Health View

Admin dashboard surfaces a unified component-health view:

```
COMPONENT HEALTH (last 7d)
─────────────────────────────
api          🟢 99.9% uptime, 0 incidents
auth         🟡 99.2% uptime, 1 minor incident, 12 linked tickets
billing      🟢 100% uptime, 3 unrelated tickets
dashboard    🔴 ACTIVE INCIDENT (47 min in)
```

Live-aggregated from incidents + tickets + uptime probes (Pingdom, Uptime Robot, etc).

## Anti-Patterns

| ✗ | Why |
|---|---|
| Status page that lags ticket signal | Customers tweet before you announce; reputation suffers |
| Auto-creating status page incidents from cluster detection without owner review | Public communication should be deliberate, not algorithmic |
| Status page that contradicts ticket reality | "All systems operational" while 50 customers report outage = trust collapse |
| Linking every ticket to the active incident regardless of similarity | Pollutes the analysis; obscures unrelated bugs |
| Resolving incident without sweeping linked tickets | Customers stay unanswered after the underlying fix |
| Status page lacking RSS/JSON feed | Customers/integrators can't monitor programmatically |
| Component naming that doesn't match support categories | Mapping requires manual inference per incident |
| Maintenance windows without 24h notice | Customer surprise = filed-tickets surge |
| Webhooks not signature-verified | Anyone POSTs fake incidents into your system |
| Webhook idempotency missing | Replay storms double-fan-out |

## Wire Points Checklist

- [ ] `incidents` table or external API integration
- [ ] Webhook receiver with HMAC verification + idempotency dedup
- [ ] Cluster-detection → "Create incident" admin prompt with owner gate
- [ ] Auto-tag tickets to incident on creation (similarity-based)
- [ ] Widget banner active during open incidents
- [ ] Pre-filing form match against active incidents
- [ ] Incident resolution fan-out to linked tickets (owner-approved boilerplate)
- [ ] System message in linked-ticket conversation thread
- [ ] Public RSS/JSON status feed
- [ ] Maintenance mode flow (schedule → announce → activate → resolve)
- [ ] Component → category mapping config
- [ ] Component health dashboard for admins
- [ ] Audit on every incident state change (created, updated, resolved)
- [ ] Test: webhook replay produces no duplicate side effects
- [ ] Test: incident resolution with 20 linked tickets sends 20 fan-outs in one bulk operation
