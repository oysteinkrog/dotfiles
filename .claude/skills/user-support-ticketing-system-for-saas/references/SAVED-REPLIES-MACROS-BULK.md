# Saved Replies, Macros, And Bulk Actions

The operator productivity layer. A support agent's perceived speed is determined less by how fast they can type and more by how few clicks separate "I know the answer" from "the customer has the answer." This file is the patterns for collapsing those clicks while preserving every safety invariant from the rest of the skill.

## Saved Replies (Templates)

A saved reply is a parameterized template with named slots:

```ts
interface SavedReply {
  id: string;
  ownerId: string;            // who created it
  scope: "global" | "team" | "personal";
  title: string;              // "Refund issued"
  category?: SupportCategory; // suggest contextually
  bodyTemplate: string;       // "Hi {{customer_first_name}}, ..."
  variables: VariableDef[];   // declared slots
  usageCount: number;         // popularity ranking
  lastUsedAt: Date | null;
  createdAt: Date;
}

interface VariableDef {
  name: string;                                // e.g. 'customer_first_name'
  type: "string" | "currency" | "date" | "url";
  source?: "ticket" | "user" | "org" | "manual";
  // 'ticket'/'user'/'org' = auto-populate from context
  required: boolean;
}
```

### Auto-Population

When an admin selects a saved reply, the system pre-fills every `source: "ticket" | "user" | "org"` variable from the current ticket's context:

```ts
async function renderSavedReply(reply: SavedReply, ticketId: string): Promise<{ body: string; manualSlots: VariableDef[] }> {
  const ctx = await loadTicketContext(ticketId);   // ticket + user + org

  let body = reply.bodyTemplate;
  const manualSlots: VariableDef[] = [];
  for (const v of reply.variables) {
    const value = v.source === "ticket" ? ctx.ticket[v.name]
                : v.source === "user"   ? ctx.user[v.name]
                : v.source === "org"    ? ctx.org?.[v.name]
                : null;
    if (value !== null && value !== undefined) {
      body = body.replaceAll(`{{${v.name}}}`, formatVar(value, v.type));
    } else {
      manualSlots.push(v);
    }
  }
  return { body, manualSlots };
}
```

Manual slots (variables the system can't auto-fill) are surfaced in the UI as labeled inputs. The admin fills them, hits "Insert," and the rendered body lands in the reply textarea — still pre-de-slopify, still pre-send.

### `/de-slopify` Still Runs

A saved reply is *also* customer-visible text. It still passes through `/de-slopify` before send. The template author's voice gets calibrated on every send (not at template-author time) so the latest voice rules apply.

### Slash-Command Insertion

Type `/refund` in the reply textarea → fuzzy match against saved-reply titles → enter selects → variables populate → admin reviews and sends.

```tsx
function ReplyTextarea({ ticketId }) {
  const [value, setValue] = useState("");
  const [showCommandMenu, setShowCommandMenu] = useState(false);
  const [commandQuery, setCommandQuery] = useState("");

  function onChange(v: string) {
    setValue(v);
    const match = v.match(/\/(\w*)$/);
    if (match) {
      setCommandQuery(match[1]);
      setShowCommandMenu(true);
    } else {
      setShowCommandMenu(false);
    }
  }

  async function selectReply(reply: SavedReply) {
    const { body, manualSlots } = await renderSavedReply(reply, ticketId);
    if (manualSlots.length > 0) {
      // open variable-fill modal
      const filled = await fillVariableModal(manualSlots);
      const finalBody = applyManualVariables(body, filled);
      setValue(finalBody);
    } else {
      setValue(body);
    }
    setShowCommandMenu(false);
  }
  // ...
}
```

### Saved Reply Library UI

Surface a sidebar with:
- Recently used (top 5)
- Suggested for this category (auto-filtered)
- Personal library
- Team library
- Global library
- "Create from this reply" — convert the current draft into a saved reply

Track `usageCount` and `lastUsedAt`; a saved reply with 0 uses in 6 months is ripe for archival.

---

## Macros (Multi-Action)

A macro is a saved-reply *plus* a state mutation: reply + status change + tag + assignee in one click.

```ts
interface Macro {
  id: string;
  scope: "global" | "team" | "personal";
  title: string;                   // "Resolve as duplicate"
  actions: MacroAction[];
  requireReason: boolean;          // honor the audit invariant
  permissionRequired: PermissionKey;
}

type MacroAction =
  | { type: "insert_reply"; savedReplyId: string }
  | { type: "set_status"; status: TicketStatus }
  | { type: "set_priority"; priority: TicketPriority }
  | { type: "set_assignee"; assignee: string | null }
  | { type: "add_tag"; tag: string }
  | { type: "link_ticket"; relationKind: "duplicate_of" }   // requires picker
  | { type: "send_internal_note"; noteTemplate: string };
```

Example: "Resolve as duplicate" macro has actions:
1. Pick a target ticket (the canonical one)
2. Insert a reply: "Hi {{first_name}}, this is a duplicate of an existing ticket we're already tracking. We'll follow up on the canonical thread."
3. Add tag `duplicate`
4. Link to target ticket (relationKind=duplicate_of)
5. Set status to `closed`
6. Audit reason: "Closed as duplicate of {{target_id}}"

The macro execution honors all the original invariants:
- `/de-slopify` runs on the reply body
- `requireReason` makes the modal ask for confirmation/free-text reason
- Email send, audit log, status normalization, all standard
- Single transaction wraps the multi-write actions

### Macro Execution Audit

Audit logs as a single `support_macro_executed` event with metadata listing every sub-action performed:

```json
{
  "actionType": "support_macro_executed",
  "entityId": "ticketId",
  "metadata": {
    "macroId": "resolve-as-duplicate-1",
    "macroTitle": "Resolve as duplicate",
    "subActions": ["set_status", "add_tag", "link_ticket", "insert_reply"],
    "linkedTicketId": "target-ticket-uuid"
  },
  "reason": "Closed as duplicate of <target>"
}
```

This collapses what would otherwise be 4-5 separate audit rows into one comprehensible event.

### Permission Inheritance

A macro's `permissionRequired` is the union of permissions its actions need. The "Resolve as duplicate" macro requires `support.resolve` (because it sets status=closed). UI hides the macro from admins lacking the needed permissions.

---

## Bulk Actions

A bulk action applies to N selected tickets at once. The risks: N+1 query patterns, partial-failure semantics, audit volume, customer-email storms.

### UI: Selection + Action Bar

```tsx
const [selected, setSelected] = useState<Set<string>>(new Set());

return (
  <>
    <SelectAllCheckbox onToggle={...} />
    {tickets.map(t => (
      <Row ticket={t} selected={selected.has(t.id)} onSelect={...} />
    ))}
    {selected.size > 0 && (
      <BulkActionBar
        count={selected.size}
        actions={[
          { label: "Assign", onClick: () => openAssignModal(selected) },
          { label: "Set Priority", onClick: () => openPriorityModal(selected) },
          { label: "Add Tag", onClick: () => openTagModal(selected) },
          { label: "Close as duplicate", onClick: () => openMacroModal(selected, "resolve-as-duplicate") },
          { label: "Export CSV", onClick: () => exportSelectedCsv(selected) },
        ]}
      />
    )}
  </>
);
```

### Bulk Service Function

A bulk action is *not* implemented as a `for` loop over `updateTicket`. Use a dedicated function:

```ts
async function bulkUpdateTickets(params: {
  ticketIds: string[];
  update: Partial<{ status: TicketStatus; priority: TicketPriority; assignee: string | null }>;
  reason: string;
  adminUserId: string;
}): Promise<{
  succeeded: string[];
  failed: Array<{ ticketId: string; error: string }>;
}> {
  const { ticketIds, update, reason, adminUserId } = params;
  const now = new Date();
  const succeeded: string[] = [];
  const failed: Array<{ ticketId: string; error: string }> = [];

  // Load all in one query
  const existing = await db.query.supportTickets.findMany({
    where: inArray(supportTickets.id, ticketIds),
  });
  const existingMap = new Map(existing.map(t => [t.id, t]));

  // Compute updates per ticket (for SLA recomputation, status normalization)
  const updates: Array<{ ticketId: string; computed: Partial<typeof supportTickets.$inferInsert> }> = [];
  const auditEvents: Array<typeof auditLog.$inferInsert> = [];

  for (const id of ticketIds) {
    const t = existingMap.get(id);
    if (!t) { failed.push({ ticketId: id, error: "not_found" }); continue; }
    try {
      const computed = computeUpdateFor(t, update, now);  // pure function
      updates.push({ ticketId: id, computed });
      auditEvents.push({
        userId: adminUserId,
        eventType: "support_ticket_updated_bulk",
        entityType: "support_ticket",
        entityId: id,
        eventData: { beforeState: t, afterState: { ...t, ...computed }, reason, bulkBatchId: ... },
      });
    } catch (err) {
      failed.push({ ticketId: id, error: err.message });
    }
  }

  // Single transaction: bulk update + bulk audit insert
  await db.transaction(async (tx) => {
    for (const { ticketId, computed } of updates) {
      await tx.update(supportTickets).set(computed).where(eq(supportTickets.id, ticketId));
    }
    if (auditEvents.length > 0) {
      await tx.insert(auditLog).values(auditEvents);
    }
  });

  // Side effects (emails) queued OFFLINE — don't fan out inline
  for (const id of updates.map(u => u.ticketId)) {
    await enqueueBulkSideEffect({ kind: "ticket_resolved_email", ticketId: id });
  }

  succeeded.push(...updates.map(u => u.ticketId));
  return { succeeded, failed };
}
```

**Key choices:**
- One `findMany` to load all targets.
- Per-ticket computation in JS (no DB round trip per ticket).
- Bulk insert of audit rows.
- Single transaction wraps state changes.
- Side effects queued for async processing — don't block the UI on N email sends.
- Per-ticket failures returned in `failed[]`; the bulk action partial-succeeds.

### Bulk-Side-Effect Queue

Email sends from a bulk action go through a queue, not inline `after()`:

```ts
async function processBulkSideEffectQueue() {
  const maxPerWindow = EMAIL_PROVIDER_LIMITS.supportBulk.maxPerWindow;
  const windowMs = EMAIL_PROVIDER_LIMITS.supportBulk.windowMs;
  const batches = chunk(items, maxPerWindow);
  for (const batch of batches) {
    await Promise.all(batch.map(item => sendForItem(item)));
    await sleep(windowMs);
  }
}
```

Without provider-aware pacing, a 200-ticket bulk-resolve can fire 200 emails in
100ms; many providers reject or defer a large fraction; failures become noisy or
silent depending on the provider. Always pace through the same email abstraction
used by normal ticket replies.

### Bulk Email Suppression Switch

Some bulk actions shouldn't email at all. When a admin closes 50 abandoned tickets that the customer never saw a reply to, sending 50 "your ticket has been resolved" emails is anti-pattern: the customer doesn't remember filing.

Add `suppressCustomerEmails: boolean | "ask"` to bulk-action config:

```tsx
<Modal>
  <h2>Bulk close 47 tickets</h2>
  <Checkbox label="Notify customers (send 'resolved' email)" checked={notify} onChange={setNotify} />
  <p className="muted">When unchecked, no emails are sent. Useful for cleanup of abandoned tickets.</p>
</Modal>
```

Default the checkbox based on action type, but never suppress customer-visible
messages when the customer was promised a reply, the action changes their
account/access/money, or the duplicate/canonical-ticket pattern requires a
redirect:
- "Resolve as duplicate" → notify (customer should know where to find the canonical ticket)
- "Close stale" → ask or suppress only for abandoned/manual-cleanup tickets with no customer-visible commitment
- "Reassign" → suppress (customers don't see assignee)

### Confirmation Threshold

Bulk actions affecting > 10 tickets require an extra confirmation:

```
You're about to close 47 tickets.
Type "47" to confirm:  [    ]
[Cancel]  [Close 47 Tickets]
```

The number-input requires the admin to read the count, preventing fat-fingered clicks on a stale selection.

### Audit Batch Identifier

Every audit row from a single bulk action shares a `bulkBatchId` (random UUID). This makes investigating "what happened in that bulk close last Tuesday" a single query.

### Bulk Action Pause/Resume

For bulk actions affecting > 100 tickets, build with checkpoint resume:

```ts
const batchSize = 50;
const total = ticketIds.length;
let processed = 0;
const batchId = randomUUID();

await persistBatchProgress({ batchId, total, processed });
for (const chunk of chunkArray(ticketIds, batchSize)) {
  await processChunk(chunk);
  processed += chunk.length;
  await updateBatchProgress({ batchId, processed });
}
await markBatchComplete(batchId);
```

If the process crashes mid-bulk, an admin can resume from the last checkpoint instead of redoing or partially-redoing.

---

## CSV Export

The admin queue's "Export selected" button generates a CSV of the selected tickets:

```ts
function ticketsToCsv(tickets: AdminTicketView[]): string {
  const headers = ["id", "subject", "priority", "status", "category", "created_at", "sla_status", "hours_until_breach", "user_email", "org_name"];
  const lines = [headers.join(",")];
  for (const t of tickets) {
    lines.push([
      t.id,
      csvEscape(t.subject),
      t.priority,
      t.status,
      t.category,
      t.createdAt,
      t.slaStatus,
      t.hoursUntilBreach ?? "",
      csvEscape(t.user.email ?? ""),
      csvEscape(t.organization?.name ?? ""),
    ].join(","));
  }
  return lines.join("\n");
}

function csvEscape(s: string): string {
  if (/[,"\n]/.test(s)) return `"${s.replaceAll('"', '""')}"`;
  return s;
}
```

`Content-Disposition: attachment; filename="tickets-YYYY-MM-DD.csv"` — date-stamped.

**Privacy gate:** CSV export records to audit (`actionType: "support_csv_exported"`, metadata.row_count, metadata.filter_summary). Exporting customer data is a privileged action.

---

## Anti-Patterns

| ✗ | Why |
|---|---|
| Looping `await updateTicket(t)` across N tickets | N×3 queries; long transaction; pool-saturating |
| Skipping `/de-slopify` on saved reply bodies | Saved replies with stale slop ship the slop verbatim every time |
| Bulk email send without provider-aware rate limit | Provider rejects or delays messages; admins think actions worked |
| No confirmation threshold above 10 tickets | Fat-finger close 200 real tickets, irrecoverable |
| Bulk audit as N rows without `bulkBatchId` | Investigating bulk events requires reconstructing batches manually |
| Macros that bypass `requireReason` | Audit gap; loses the reasoning trail |
| Saved replies without auto-population | Same parameters typed every time; opportunity to drift |
| Slash-command insertion that injects raw template (no variable filling) | Customer sees `{{first_name}}` literally — disaster |
| Personal saved-reply leakage to other admins | Privacy concern if reply contains internal commentary |
| Macro that emails on suppressCustomerEmails=undefined | Default to "ask"; never silently fan-out |

---

## Wire Points Checklist

- [ ] `savedReplies` table with scope, owner, template, variables, usage stats
- [ ] `macros` table with action chain, permission requirement, reason policy
- [ ] Slash-command UI in reply textarea with fuzzy match
- [ ] Variable auto-population from ticket/user/org context
- [ ] Manual-slot fill-in modal
- [ ] `/de-slopify` runs after template render before send
- [ ] Macro execution wraps actions in single transaction
- [ ] Bulk action service (not per-row loop)
- [ ] Bulk audit with `bulkBatchId`
- [ ] Bulk side effects queued and rate-limited
- [ ] Bulk action confirmation modal above 10-ticket threshold
- [ ] Bulk customer-email suppression toggle
- [ ] CSV export endpoint with audit
- [ ] Export `Content-Disposition` filename includes date
- [ ] Permission inheritance on macros (action-set permission union)
- [ ] Saved reply usage tracking + 6-month staleness flag
