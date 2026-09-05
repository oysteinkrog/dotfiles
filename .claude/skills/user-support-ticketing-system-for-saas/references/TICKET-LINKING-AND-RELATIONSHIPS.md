# Ticket Linking And Relationships

Real customer issues rarely come as standalone tickets. They split, merge, recur, follow up, and reference one another. Modeling those relationships first-class transforms the queue from "list of unrelated items" into "graph of customer experience" — and unlocks bulk operations, deflection metrics, and engineering-bug correlation.

## The Relationship Types

```ts
export const ticketRelationKindEnum = pgEnum("ticket_relation_kind", [
  "duplicate_of",      // this ticket is a duplicate of another (merge target)
  "related_to",        // similar topic, not a duplicate
  "parent_of",         // this is the canonical, others below are duplicates pointing here
  "child_of",          // this is a duplicate; the parent is the canonical
  "follows_up",        // a new ticket continuing a previous resolved one
  "blocks",            // this ticket can't resolve until target resolves
  "blocked_by",        // inverse of blocks
  "merged_into",       // historical: this ticket was merged into another
  "split_from",        // historical: this ticket was split off from another
  "followed_by",       // inverse of follows_up
  "linked_to_engineering",  // links to an engineering tracker issue
  "linked_to_incident",     // links to a status-page incident
]);
```

Most relationships are **bidirectional pairs** (`duplicate_of` ↔ `parent_of`, `blocks` ↔ `blocked_by`). The schema stores one direction; the API returns both.

## Schema

```ts
export const ticketRelations = pgTable("ticket_relations", {
  id: uuid().primaryKey().defaultRandom(),
  fromTicketId: uuid().references(() => supportTickets.id, { onDelete: "cascade" }).notNull(),
  toTicketId:   uuid().references(() => supportTickets.id, { onDelete: "cascade" }),
  kind: ticketRelationKindEnum().notNull(),
  // For external links (engineering, incident), `toTicketId` may be NULL and an external pointer is used:
  externalRefKind: text(),                                  // 'github', 'linear', 'jira', 'incident'
  externalRefId:   text(),                                  // 'gh:owner/repo#123' or similar
  createdById: uuid().references(() => users.id),
  reason: text(),                                           // why this link exists
  createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
}, t => [
  index("ticket_relations_from_idx").on(t.fromTicketId, t.kind),
  index("ticket_relations_to_idx").on(t.toTicketId, t.kind),
  unique("ticket_relations_internal_unique").on(t.fromTicketId, t.toTicketId, t.kind),
  unique("ticket_relations_external_unique").on(t.fromTicketId, t.externalRefKind, t.externalRefId, t.kind),
]);
```

Either `toTicketId` is set (internal link) or `externalRefKind` + `externalRefId` are set (external link). One or the other, never both.
Enforce that with a database check constraint; don't rely on route validation
alone.

## Bidirectional Mirroring

When admin creates a `duplicate_of` link from ticket A to ticket B, the system inserts BOTH:
- `(A → B, duplicate_of)`
- `(B → A, parent_of)`

This denormalization makes "find all duplicates of ticket X" a single query against `to=X, kind=parent_of` instead of a recursive search.

```ts
async function createTicketLink(params: {
  fromTicketId: string;
  toTicketId?: string;
  externalRefKind?: "github" | "linear" | "jira" | "incident";
  externalRefId?: string;
  kind: TicketRelationKind;
  reason?: string;
  createdById: string;
}) {
  const isInternal = Boolean(params.toTicketId);
  const isExternal = Boolean(params.externalRefKind && params.externalRefId);
  if (isInternal === isExternal) {
    throw new Error("Set exactly one of toTicketId or externalRefKind/externalRefId");
  }
  const inverseKind = INVERSE_KINDS[params.kind];   // e.g. duplicate_of → parent_of
  await db.transaction(async (tx) => {
    await tx.insert(ticketRelations).values({
      fromTicketId: params.fromTicketId,
      toTicketId: params.toTicketId ?? null,
      externalRefKind: params.externalRefKind ?? null,
      externalRefId: params.externalRefId ?? null,
      kind: params.kind,
      reason: params.reason,
      createdById: params.createdById,
    });
    if (inverseKind && params.toTicketId) {
      await tx.insert(ticketRelations).values({
        fromTicketId: params.toTicketId,
        toTicketId: params.fromTicketId,
        kind: inverseKind,
        reason: params.reason,
        createdById: params.createdById,
      });
    }
  });
}

const INVERSE_KINDS: Partial<Record<TicketRelationKind, TicketRelationKind>> = {
  duplicate_of: "parent_of",
  parent_of: "duplicate_of",
  child_of: "parent_of",
  blocks: "blocked_by",
  blocked_by: "blocks",
  merged_into: "split_from",
  split_from: "merged_into",
  related_to: "related_to",   // symmetric
  follows_up: "followed_by",
  followed_by: "follows_up",
};
```

## Use Cases

### Duplicate Resolution (merge)

Macro: "Mark as duplicate" (see [SAVED-REPLIES-MACROS-BULK.md](SAVED-REPLIES-MACROS-BULK.md))

1. Admin selects a duplicate ticket
2. Clicks "Mark as duplicate of..."
3. Picks the canonical ticket from a search dropdown
4. Confirms with reason
5. System:
   - Creates `duplicate_of` link bidirectionally (`parent_of` mirror)
   - Posts a customer-facing reply on the duplicate: "We're already tracking this issue on a canonical ticket; we'll respond there."
   - Sets duplicate's status to `closed`
   - Audit row records the merge

The canonical ticket sees the duplicate's customer mentioned in the relationships sidebar. The agent replying on the canonical decides whether to email all duplicate-customer accounts (typically yes — see "fan-out reply" below).

### Fan-Out Reply From Canonical

When the canonical ticket is resolved, fan out the already owner-approved
resolution reply to all duplicate tickets too. Do not generate new copy and do
not bypass `/de-slopify` or the same customer-facing send path:

```ts
async function publishCanonicalResolutionToDuplicates(canonicalTicketId: string, approvedResolutionMessage: string, approvalId: string) {
  const duplicates = await db.select()
    .from(ticketRelations)
    .where(and(
      eq(ticketRelations.toTicketId, canonicalTicketId),
      eq(ticketRelations.kind, "parent_of"),
    ));

  for (const link of duplicates) {
    await addApprovedCustomerMessage({
      ticketId: link.fromTicketId,
      senderId: SUPPORT_BOT_USER_ID,
      senderType: "support",
      message: `(Resolution from canonical ticket #${canonicalTicketId.slice(0, 8)}:)\n\n${approvedResolutionMessage}`,
      approvalId,
    });
    await updateTicket({ ticketId: link.fromTicketId, status: "resolved" });
  }
}
```

Saves the team from manually replying to 20 duplicate tickets when a single bug
is fixed. Audit captures the fan-out, the approval id, and the canonical source
ticket.

### Engineering Tracker Link

When admin escalates a bug ticket to engineering, the link is recorded:

```ts
await createTicketLink({
  fromTicketId,
  externalRefKind: "linear",
  externalRefId: "ENG-1234",
  kind: "linked_to_engineering",
  reason: "Engineering tracking the underlying export pipeline bug",
  createdById: adminId,
});
```

When the engineering issue is resolved (via webhook), all linked support tickets
get an internal system note and are surfaced in a "ready to verify" view. The
customer-facing update still requires admin verification and approval:

```ts
async function onEngineeringIssueResolved(externalRefId: string) {
  const linkedTickets = await db.select()
    .from(ticketRelations)
    .where(and(
      eq(ticketRelations.externalRefId, externalRefId),
      eq(ticketRelations.kind, "linked_to_engineering"),
    ));

  for (const link of linkedTickets) {
    await addMessage({
      ticketId: link.fromTicketId,
      senderId: SUPPORT_BOT_USER_ID,
      senderType: "internal_note",
      message: `Engineering resolved ${externalRefId}; verify against the customer report before sending a customer-facing update.`,
    });
    // Don't auto-resolve; admin verifies with the customer first.
  }
}
```

Webhooks from Linear/GitHub/Jira are signed; verify the signature before processing (see [SECURITY.md](SECURITY.md) "Webhook Security").

### Incident Link

When status-page incident is created, tickets filed during the incident window can be auto-linked:

```ts
async function tagTicketsWithIncident(incidentId: string, since: Date, until: Date) {
  // Use AI similarity to match ticket text against incident description; auto-link high-confidence matches
  const recentTickets = await listTicketsCreatedBetween(since, until);
  for (const ticket of recentTickets) {
    const sim = await similarity(ticket.description, incident.description);
    if (sim > 0.85) {
      await createTicketLink({
        fromTicketId: ticket.id,
        externalRefKind: "incident",
        externalRefId: incidentId,
        kind: "linked_to_incident",
        reason: "Auto-tagged via similarity match during incident window",
        createdById: SYSTEM_USER_ID,
      });
    }
  }
}
```

When the incident resolves, fan-out resolution to all linked tickets (same pattern as engineering).

### Follow-Up Detection

When a customer files a new ticket within 30 days of a previous resolved ticket, with similar text, suggest:

```
🔗 This looks like a follow-up to:
   #ABC12345 "Export Skills issue" (resolved 12d ago)
   [View previous] [Mark as follow-up]
```

Marking creates a `follows_up` link. Useful for "did our fix not actually fix it?" detection — measure follow-up rate by category.

### Block / Blocked-By

Two tickets reference dependent issues. "I can't pay until login is fixed" → block. The admin queue UI shows blocked tickets with a 🔗 indicator and shows the blocker's status. When the blocker resolves, blocked tickets surface in the "ready to look at" view.

```sql
SELECT t.*
FROM support_tickets t
JOIN ticket_relations r ON r.from_ticket_id = t.id
JOIN support_tickets blocker ON blocker.id = r.to_ticket_id
WHERE r.kind = 'blocked_by'
  AND blocker.status IN ('resolved', 'closed')
  AND t.status NOT IN ('resolved', 'closed')
ORDER BY blocker.resolved_at DESC;
```

## UI: Relationships Sidebar

```
┌────── Relationships ──────────────────────┐
│                                            │
│ 🔗 Duplicates of this (3)                  │
│   • #DUP1 "Cannot export" (Jane)          │
│   • #DUP2 "Export broken" (Bob)           │
│   • #DUP3 "Skills won't download" (Sue)   │
│   [Fan-out reply when resolved]           │
│                                            │
│ 🚧 Blocked by                              │
│   • #ABC1 "Login redirect" (in_progress)  │
│                                            │
│ 🔧 Linked to engineering                   │
│   • Linear ENG-1234 (in review)           │
│                                            │
│ 📍 Linked to incident                      │
│   • status.example.com/i/3 (resolved)     │
│                                            │
│ 🔄 Previous tickets                        │
│   • #PREV1 "Login issue" (32d ago)        │
│                                            │
│ [+ Add link]                               │
└────────────────────────────────────────────┘
```

Click any relation → navigate to the linked ticket. "Add link" opens a search dropdown.

## Customer-Visible Relationships

Most relationships are admin-internal. Surface only:
- `linked_to_incident` (when public-status-page incident exists) → "We've identified this as part of a known incident: [link to status page]"
- `duplicate_of` resolution fan-out (the customer sees the resolution reply they wouldn't have gotten otherwise)

Never expose: `blocks`, `parent_of`, `linked_to_engineering` (internal tracker IDs are private).

## Search-And-Suggest

When admin types in "add link" search, suggest:
1. Top semantic matches (embedding similarity > 0.75)
2. Same-customer recent tickets (last 90d)
3. Open tickets in the same category created within 24h
4. Recent admin queries (autocomplete history)

Each suggestion shows ticket id, subject, status, age. Click adds the link.

## Cycle Detection

`blocks` / `blocked_by` graphs can develop cycles (A blocks B, B blocks C, C blocks A). The UI must detect and prevent:

```ts
async function wouldCreateCycle(fromId: string, toId: string, kind: "blocks" | "blocked_by"): Promise<boolean> {
  if (kind !== "blocks") return false;
  // BFS from `to` along outgoing `blocks`; if we reach `from`, it's a cycle
  const visited = new Set<string>();
  const queue = [toId];
  while (queue.length) {
    const id = queue.shift()!;
    if (id === fromId) return true;
    if (visited.has(id)) continue;
    visited.add(id);
    const next = await db.select({ to: ticketRelations.toTicketId })
      .from(ticketRelations)
      .where(and(eq(ticketRelations.fromTicketId, id), eq(ticketRelations.kind, "blocks")));
    queue.push(...next.map(n => n.to));
  }
  return false;
}
```

UI rejects cycle-forming links with explanation.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Single-direction relations (no inverse) | Every "find related" becomes a recursive query |
| Auto-resolving duplicates without a reply on each | Customer thinks ticket was ignored |
| Letting customers see engineering-tracker IDs | Internal information leak; reveals stack |
| Auto-linking by similarity without confidence threshold | False positives create noise; admin loses trust in suggestions |
| Allowing cycle in `blocks` graph | Infinite loops in "ready to look at" computation |
| Not deduplicating same-pair links | Same `(A, B, duplicate_of)` inserted twice creates orphan rows |
| Including links in customer email body verbatim | Internal IDs / status leak |
| Skipping audit on link create/delete | Linking is a privileged action |

## Wire Points Checklist

- [ ] `ticketRelationKindEnum` defined with all relation types
- [ ] `ticketRelations` table with bidirectional unique constraint
- [ ] `createTicketLink` mirrors inverse direction in single transaction
- [ ] Macro: "Mark as duplicate" creates link + closes + posts redirect reply
- [ ] Fan-out resolution from canonical to duplicates
- [ ] Engineering-tracker link with webhook to fan-out resolution
- [ ] Incident link via auto-similarity match during incident window
- [ ] `blocks` / `blocked_by` cycle detection
- [ ] UI: relationships sidebar on ticket detail
- [ ] UI: search-and-suggest for adding links
- [ ] Permission: `support.create_link` (typically tier-2)
- [ ] Audit on every link create/delete
- [ ] Customer-side filtering: only `linked_to_incident` (public) surfaces
