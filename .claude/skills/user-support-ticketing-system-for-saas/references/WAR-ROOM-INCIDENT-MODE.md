# War-Room / Incident Mode

When a major outage hits, regular ticket triage breaks down: 50 tickets in 10 minutes, all about the same thing, the team is investigating root cause, customers are panicking. "War room" is the explicit *operating mode shift* that adapts the support system to incident response.

This file is the architectural pattern for entering, operating in, and exiting war-room mode.

## What Triggers War-Room Mode

Pre-defined triggers (no judgment-call ambiguity at 3 AM):

- Status-page incident at "major" or "critical" impact
- Cluster detection finds 10+ tickets in 30 min on same root cause
- P0 enterprise SLA breach actively unfolding
- Manual activation by support lead or on-call engineer

Activation is **explicit** — someone clicks "Enter War Room" or invokes a slash command. No silent mode-shift.

## The State Change

When war room enters, the support system shifts behavior in 8 specific ways:

### 1. Inbound Tickets Auto-Tag

All tickets created during war-room window auto-tag with the active incident:

```ts
async function createTicket(input) {
  const ticket = await db.insert(...).returning();
  const activeWar = await getActiveWarRoom();
  if (activeWar && (await similarityToIncident(ticket, activeWar)) > 0.6) {
    await createTicketLink({
      fromTicketId: ticket.id,
      externalRefKind: "incident",
      externalRefId: activeWar.incidentId,
      kind: "linked_to_incident",
      reason: "Auto-tagged during war room",
    });
  }
  return ticket;
}
```

Lower similarity threshold (0.6 vs normal 0.8) — broader catch radius during incident.

### 2. Auto-Acknowledge Reply

Customers filing during war-room get an auto-reply within 60 seconds. This is the rare exception to "no auto-customer-replies" — owner-pre-approved during war-room activation:

```
Thank you for reaching out.

We're aware of an issue affecting [component] and are actively
investigating. Status updates: status.example.com/incidents/abc

We've logged your report and will follow up directly when there's
news. Your ticket #[id] is in our queue.
```

The owner-tier approval at war-room start covers all auto-replies during the window. Audit captures the approval-id on each.

### 3. Cluster Auto-Resolution On Incident Close

When the underlying incident resolves, the fan-out (per [TICKET-LINKING-AND-RELATIONSHIPS.md](TICKET-LINKING-AND-RELATIONSHIPS.md)) sends each linked ticket the resolution message and flips status to `awaiting_customer`. Customers confirm or reopen.

### 4. Admin UI Pivots To "Triage Mode"

Admin queue switches default sort to "war-room first," shows a banner, exposes bulk-tag actions:

```
🚨 WAR ROOM ACTIVE: API latency (33 minutes in)
   Linked tickets: 47    Auto-tagged: 38    Manual: 9
   [Override sort] [Bulk reply] [Exit war room]
```

A dedicated "war room queue" lists only ticket-linked-to-incident, sortable by customer-tier (enterprise first).

### 5. Aggressive Internal Notifications

P0 enterprise tickets during war-room → on-call engineer paged via PagerDuty *immediately* (not just Slack). Higher noise floor accepted; missed-page risk drops.

### 6. Status Updates Pushed To Linked Tickets

Periodic incident updates (every 15-30 min) auto-post as system messages on linked tickets:

```
─── system · 15 min ago ───────────────────────
Update: We've identified the cause and are deploying a fix.
ETA to resolution: 20-30 minutes.
View status: status.example.com/incidents/abc
─────────────────────────────────────────────────
```

Owner-pre-approved at war-room start; admin can pause/customize later.

### 7. Coordinator Role Designated

One person owns coordination; engineers report status to them; they post to status page; they trigger fan-out updates. Single source of truth prevents conflicting updates.

### 8. SLA Pause (Optional)

For tickets explicitly linked to the incident, SLA can be paused while war-room is active — the team isn't "breaching" if the underlying system is broken, the customer knows it, and a status-page acknowledgment is up. Per [BUSINESS-HOURS-AND-CALENDARS.md](BUSINESS-HOURS-AND-CALENDARS.md), this is configurable; document the choice.

## Schema

```ts
export const warRooms = pgTable("war_rooms", {
  id: uuid().primaryKey().defaultRandom(),
  incidentId: uuid().references(() => incidents.id),
  triggeredBy: uuid().references(() => users.id).notNull(),
  triggerKind: text().notNull(),                          // 'cluster' | 'incident' | 'manual'
  startedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  endedAt: timestamp({ withTimezone: true }),
  coordinatorUserId: uuid().references(() => users.id),
  autoReplyTemplate: text().notNull(),                    // captured at start
  autoReplyApprovalId: uuid().notNull(),                  // owner approval reference
  ticketsLinked: integer().default(0).notNull(),
  metadata: jsonb(),
}, t => [
  index("war_rooms_active_idx").on(t.endedAt),            // null = active
]);
```

## Activation Flow

```
1. Trigger detected (cluster / incident / manual)
2. UI prompts: "Enter war-room mode for incident X?"
3. Owner reviews:
     - Auto-reply template (edit if needed)
     - Coordinator (default: trigger-er)
     - SLA-pause toggle
4. Owner approves → war-room ACTIVE
5. System:
     - Inserts war_rooms row
     - Captures owner-approval id on autoReplyApprovalId
     - Posts to support team Slack: "🚨 War room active: <title>"
     - Audit row written
```

## During War Room

### Coordinator Dashboard

```
WAR ROOM: API latency
Started 33 min ago by @alice
Coordinator: @alice  [reassign]

LINKED TICKETS  47    UNRESOLVED 38    NEW IN LAST 5MIN  3
ENTERPRISE          12    INDIVIDUAL  35

[Pause auto-reply] [Push status update] [End war room]

ACTIVITY
  10:00 War room started; auto-reply enabled
  10:05 Status update pushed to 47 tickets
  10:18 Bulk reply sent to 12 enterprise customers (custom message)
  10:25 Engineering deployed fix
  10:33 Verifying...
```

### Bulk Reply Action

The coordinator can send a customer-visible bulk reply to all linked tickets in the war-room:

```ts
async function bulkReplyDuringWarRoom(opts: {
  warRoomId: string;
  message: string;
  approvalId: string;
}) {
  const linkedTickets = await getWarRoomLinkedTickets(opts.warRoomId);
  const cleanedMessage = await deslopify(opts.message);
  for (const ticket of linkedTickets) {
    await scheduleSupportSideEffect(
      () => addApprovedCustomerMessage({
        ticketId: ticket.id,
        senderType: "support",
        message: cleanedMessage,
        approvalId: opts.approvalId,
      }),
      { ticketId: ticket.id, warRoomId: opts.warRoomId },
      "Bulk reply scheduled outside request",
    );
  }
}
```

Owner-confirmation (separate from war-room activation approval) for *each* bulk reply. The war-room activation pre-approves auto-replies and status updates; ad-hoc bulk replies need their own approval.

### Adding A Manually-Filed Ticket To War Room

Admin discovers a ticket that's about the war-room incident but didn't auto-tag (similarity below threshold):

```
[ Add to War Room: API latency ]
```

Click → creates the link → ticket gets auto-reply (if not yet replied) → enters the war-room queue.

### Excluding A Ticket From War Room

Sometimes a ticket auto-tagged is unrelated. One click to remove the link; ticket returns to normal queue; auto-reply already sent stays.

## Status Page Sync

War-room activation can simultaneously update the status page:

```ts
async function activateWarRoom(opts: { incidentId: string; ... }) {
  // Update or create status-page incident
  if (!opts.incidentId) {
    const newIncident = await statusPage.createIncident({
      title: opts.title,
      impact: "major",
      message: opts.publicMessage,
    });
    opts.incidentId = newIncident.id;
  }
  // Create war-room
  await db.insert(warRooms).values({...});
  // Notify
  await notifyTeam("war_room_activated", {...});
}
```

The status-page incident and war-room are conceptually separate but typically created together. UI checkbox: "Also create status-page incident" → defaults checked.

## Exit Flow

```
1. Incident resolves (status page → resolved)
2. Coordinator confirms war-room exit
3. System:
     - Sends final fan-out to linked tickets ("issue resolved; please confirm")
     - Sets war_rooms.endedAt
     - Pauses auto-reply
     - Resumes normal SLA computation on linked tickets
     - Posts "war room exited" to team Slack with stats
4. Postmortem auto-scheduled within 48h (per [POSTMORTEM-AND-LEARNING-LOOPS.md](POSTMORTEM-AND-LEARNING-LOOPS.md))
```

## During-War-Room Audit

Every action during war-room captures:
- `metadata.warRoomId` for cross-referencing
- The owner-approval-id pre-approved at activation

Aggregate audit query for postmortem:

```sql
SELECT action_type, COUNT(*), MIN(timestamp), MAX(timestamp)
FROM audit_log
WHERE metadata->>'warRoomId' = '<id>'
GROUP BY action_type
ORDER BY MIN(timestamp);
```

## Anti-Patterns

| ✗ | Why |
|---|---|
| Implicit war-room mode (just behavior changes when stuff is busy) | No audit trail; mode-state ambiguous; impossible to reason about |
| Auto-reply without owner approval | Customer-visible bulk send is the highest-stakes operation |
| Coordinator role unassigned | Multiple uncoordinated updates contradict each other |
| Engineers post to status page directly during war-room | Bypasses coordination; conflicting messages |
| Linked-ticket fan-out without de-slopify on the bulk message | Slop blast — orders of magnitude more damaging than slop reply |
| Exit war-room before incident resolves | Linked tickets stuck in tagged state |
| War-room state has no end-of-incident audit | Postmortem reconstruction harder |
| Auto-reply identical regardless of customer-tier | Enterprise expects different tone than free |
| SLA pause applied universally instead of just linked tickets | Phantom-pass for unrelated breaches |
| War-room queue not prioritized by tier | Enterprise customers buried |

## Wire Points Checklist

- [ ] `warRooms` table with active / ended / coordinator / approval-id
- [ ] Triggers documented (cluster / incident / manual)
- [ ] Owner-approval gate at activation
- [ ] Auto-reply template captured per war-room
- [ ] Auto-tag inbound tickets during war-room (similarity threshold lowered)
- [ ] Banner in admin UI surfacing active war-room
- [ ] War-room queue sortable by customer-tier
- [ ] Coordinator dashboard with stats + actions
- [ ] Bulk-reply with separate owner approval per send
- [ ] "Add to war room" / "Remove from war room" admin actions
- [ ] Status update fan-out (15-30 min cadence; configurable)
- [ ] PagerDuty integration for P0 enterprise during war-room
- [ ] Optional SLA pause for linked tickets
- [ ] Exit flow: final fan-out, end timestamp, stats post, postmortem auto-scheduled
- [ ] Every audit row during war-room carries `metadata.warRoomId`
- [ ] Test: war-room with 50 linked tickets bulk-replies in one operation under budget
- [ ] Test: exit war-room flips linked tickets to `awaiting_customer` correctly
