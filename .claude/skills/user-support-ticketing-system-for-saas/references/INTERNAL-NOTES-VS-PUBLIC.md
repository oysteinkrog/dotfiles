# Internal Notes vs Public Replies

The single most common class of accidental privacy leak in support systems: an internal note posted as a public reply. This file is the architectural defense.

## The Failure Mode

Engineer A is investigating a customer complaint. They want to add context for Engineer B who'll handle the next response: "this customer's account is in churn-risk; tread carefully" or worse, "the actual bug is in our billing rounding code, but we shouldn't tell them that yet."

If the reply UI has a single textarea with a checkbox marked "Internal note (not sent to customer)" — and the checkbox starts *unchecked* — Engineer A's note ships to the customer. Trust crater.

This pattern keeps appearing because the *ergonomic* shape (one form, one toggle) is naturally a single-form. The defense forces a different shape.

## Architectural Defense: Two APIs, Two UI Affordances

Public replies and internal notes are **different APIs**. Different UI buttons. Different colors. Different confirmation copy.

### Schema Addition

Extend `senderType`:
```ts
export const ticketSenderTypeEnum = pgEnum("ticket_sender_type", [
  "customer",        // customer reply
  "support",         // support agent reply, customer-visible
  "system",          // automated event (status change, sla breach detection)
  "internal_note",   // admin internal note, NOT customer-visible
]);
```

`internal_note` rows live in `supportMessages` alongside the public messages so the conversation thread is auditable, but they are **filtered out of all customer-visible endpoints**.

### Two Routes

```
POST /api/admin/support/tickets/[id]/messages         # PUBLIC reply, emails customer
POST /api/admin/support/tickets/[id]/notes            # INTERNAL note, no customer email
```

The two share validation but have different downstream side effects:

```ts
// /messages — public path
await addMessage({ ticketId, senderId, senderType: "support", message, attachments });
// triggers sendTicketResponseEmail
// (status flips to awaiting_customer if currently active)

// /notes — internal path
await addInternalNote({ ticketId, senderId, message });
// NO email
// NO status flip
// audit logged with `actionType: "support_internal_note_added"`
```

### Separate UI Forms

The admin ticket detail page has TWO buttons, never combined:

```tsx
{/* Tab-style switcher; mutually exclusive */}
<div className="flex gap-2 border-b">
  <button data-mode="reply"    className={mode === "reply" ? "active" : ""}>
    💬 Reply to Customer
  </button>
  <button data-mode="internal" className={mode === "internal" ? "active" : ""}>
    🔒 Internal Note (Team Only)
  </button>
</div>

{mode === "reply" && (
  <ReplyForm ticketId={ticketId} />   /* posts to /messages */
)}
{mode === "internal" && (
  <InternalNoteForm ticketId={ticketId} />  /* posts to /notes */
)}
```

**Visual differentiation:**
- Reply form: light background, primary-colored "Send Reply" button
- Internal note form: amber/yellow background, gray "Save Internal Note" button
- Internal note form *header* explicitly says: "🔒 Only visible to your team. Not sent to the customer."

### Confirmation Modal On Reply (Not On Note)

The customer-facing reply triggers a confirmation:

```
You're about to send this message to:
  customer@example.com

Subject: Re: <ticket subject>

[Cancel]  [Send to Customer]
```

The internal note does NOT have this modal — it's faster (people add notes constantly while investigating). The asymmetric friction encodes "the public reply is the high-stakes action; the internal note is the cheap one."

### Conversation Thread Rendering

In the admin ticket detail UI, internal notes are interleaved with public messages chronologically but visually distinct:

```
┌─────────────────────────────────────────────────┐
│ Customer · 2h ago                                │
│ When I export, I get an error.                   │
└─────────────────────────────────────────────────┘

┌─🔒 INTERNAL NOTE ─────────────────────────────── │
│ Engineer A · 1.5h ago                            │
│ This is the rounding bug from #5421. Don't       │
│ mention the workaround until eng confirms.       │
└─ visible only to team ────────────────────────── │

┌─────────────────────────────────────────────────┐
│ Acme Support (Engineer B) · 1h ago               │
│ Thanks for the report — we're investigating.     │
└─────────────────────────────────────────────────┘
```

Internal notes have:
- A 🔒 lock icon
- Amber background (or whatever your "internal" color is)
- "Visible only to team" footer text
- Different border/shadow

### Customer-Side Detail Endpoint Filters Internal Notes

```ts
// GET /api/support/tickets/[id]
const messages = await db.select(...)
  .from(supportMessages)
  .where(and(
    eq(supportMessages.ticketId, ticketId),
    inArray(supportMessages.senderType, ["customer", "support", "system"]),  // NEVER internal_note
  ))
  .orderBy(asc(supportMessages.createdAt));
```

The `inArray` whitelist is the canonical defense — if a new sender type is added, it explicitly must be reviewed against the customer-side filter. Whitelist > blacklist.

**Test it.**
```ts
test("customer-side endpoint excludes internal notes", async () => {
  await addMessage({ ticketId, senderId: customerId, senderType: "customer", message: "x" });
  await addInternalNote({ ticketId, senderId: adminId, message: "secret" });
  await addMessage({ ticketId, senderId: adminId, senderType: "support", message: "reply" });

  const res = await GET(makeReq(), { params: Promise.resolve({ id: ticketId }) });
  const body = await res.json();
  expect(body.ticket.messages.map((m: any) => m.message)).toEqual(["x", "reply"]);
  // "secret" must not appear
  const flat = JSON.stringify(body);
  expect(flat).not.toContain("secret");
});
```

### Email Renderer Filters Internal Notes

The "ticket response" email template fetches recent messages to show context. **Filter to non-internal types** before rendering:

```ts
const recentMessages = allMessages
  .filter(m => m.senderType !== "internal_note")
  .slice(-3);
```

Without this, the email body could include internal notes from the rendered thread context.

### Cron / Webhook Output Filters Internal Notes

Slack alerts that include a "last message preview" must filter:

```ts
const lastCustomerVisible = messages
  .filter(m => m.senderType !== "internal_note")
  .at(-1);
```

A breach alert containing an internal note's content posted in a shared #support Slack channel is itself a leak.

---

## Mention-Style Notification Within Internal Notes

Internal notes can mention teammates with `@username` syntax. Mentions trigger an in-app notification (and optionally email) only to the mentioned admin. Mentions render as visual badges in the note. They never affect customer-visible state.

```ts
const mentions = parseMentions(noteText);  // ["@engineer-b"]
for (const username of mentions) {
  await notifyAdmin(username, {
    type: "support_note_mention",
    ticketId,
    excerpt: noteText.slice(0, 200),
  });
}
```

Mention notifications are how internal notes substitute for the natural "hey did you see this" Slack message. Tighter loop = better collaboration without leaving the ticket UI.

---

## Audit Differences

| Action | Audit Type | Reason Required | Mention Notifications |
|---|---|---|---|
| Public reply | `support_ticket_message_posted` (senderType=support) | Optional | No |
| Internal note | `support_internal_note_added` | No | Yes (parsed from body) |
| Status change with reply | Both above audit events | Yes | If mentions present |

---

## Convert Internal Note → Public Reply (Sometimes)

Sometimes an admin realizes an internal note actually belongs as a public reply. Provide an explicit conversion action — but with strong friction:

```
🔒 Internal Note · Engineer A
"Hey Engineer B, the workaround is to refresh and retry."

[ Send this as a public reply? ]   <-- button
```

Clicking opens the public-reply modal pre-filled with the note text, runs `/de-slopify`, asks for the standard send-confirmation. Audit logs the conversion. Original internal note row is *not* deleted (preserves the team's investigation history).

---

## Mistake Recovery: A Note Was Sent As Reply

If the safeguards fail and a note ships to a customer — what then?

1. **Acknowledge in a follow-up reply.** Don't pretend it didn't happen; the customer received the email already. "Earlier we sent a note that wasn't intended for you — apologies for the confusion."
2. **Audit log records the original event.** Don't try to scrub it; do not delete the message row. Compliance needs the original record.
3. **Add a 'sent_in_error' flag.** Mark the message in the schema; UI can render with a strikethrough "marked as sent in error."
4. **Post-incident review.** Did the safeguards fail? Patch the gap.

---

## Anti-Patterns

| ✗ | Why |
|---|---|
| One textarea, one "internal" checkbox | Default-unchecked ships notes; default-checked ships replies. Either default produces the wrong outcome. |
| Internal notes stored in a separate table with no unified timeline | Loses chronological thread context; if separate storage is required, expose one ordered conversation view |
| Internal notes filtered with blacklist (`senderType !== "internal_note"`) | A new sender type added later silently leaks. Use whitelist. |
| Skipping the confirmation modal on public reply "for speed" | Speed costs trust. The 200ms confirmation is worth it. |
| Same color/font/icon for notes and replies | Visual differentiation is the last line of defense |
| Letting internal notes appear in email "recent context" | Email renderer must filter |
| Allowing customer-side detail endpoint to return all sender types | Single missed filter ships every internal note ever |
| Storing internal-note tone same as customer reply tone | Internal notes can be candid; customer replies must be polished. Different audiences, different writing |

---

## Wire Points Checklist

- [ ] `ticketSenderTypeEnum` includes `internal_note`
- [ ] `POST /api/admin/support/tickets/[id]/notes` route exists and is separate from `/messages`
- [ ] `addInternalNote` service function exists; does NOT call `sendTicketResponseEmail`; does NOT change ticket status
- [ ] Customer-side `GET /api/support/tickets/[id]` filters with whitelist `inArray(senderType, ["customer", "support", "system"])`
- [ ] Email "recent context" renderer filters internal notes
- [ ] Slack alert payload filters internal notes from "last message preview"
- [ ] Admin UI has two distinct buttons + visual differentiation (color, icon, label)
- [ ] Public reply has confirmation modal showing recipient + subject
- [ ] Internal note has no confirmation modal (lower friction)
- [ ] Mention parsing notifies admins; never customer
- [ ] Convert internal-to-public action exists with friction + audit
- [ ] Audit log differentiates `support_ticket_message_posted` vs `support_internal_note_added`
- [ ] Test: internal note never appears in customer-side endpoint output
- [ ] Test: internal note never appears in rendered email body
