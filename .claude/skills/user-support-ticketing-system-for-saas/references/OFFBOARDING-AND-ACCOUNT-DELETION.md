# Offboarding And Account Deletion

When a customer leaves — voluntarily, involuntarily, or via GDPR data-deletion request — their support data needs careful handling. The naive answer ("just delete everything") breaks compliance, audit trails, and ongoing investigations. The careful answer requires understanding what to retain, what to delete, and what to anonymize.

## Six Departure Modes

| Mode | Triggered by | Data treatment |
|---|---|---|
| **Voluntary cancellation** | Customer self-serve cancel | Standard retention; account dormant |
| **Subscription expiration** | Payment failure cascade | Soft-suspend; standard retention |
| **GDPR right-to-erasure** | Customer / DPA request | Hard delete with legal-hold exceptions |
| **Account termination** | Hostile-user policy violation | Account locked; audit retained; PII redacted |
| **Death of customer** | Notified by family / probate | Soft-delete; legal-hold; family contact |
| **Legal hold / litigation** | Subpoena / preservation order | Retain everything; freeze deletion |

Each has distinct data handling. Conflating them ("deletion = deletion") loses important nuance.

## What's In The "Customer Data" Bucket

For any customer, support-related data spans:

- `supportTickets` (their tickets)
- `supportMessages` (their messages on tickets they own + their messages on tickets they don't own)
- `supportRequests` (legacy contact form)
- `supportAttachments` (files they uploaded)
- Their `auditLog` rows (actions they took)
- Their `auditLog` rows from system events about them (`userId: null` events)
- VoC tags / quotes / field notes about them
- `aiCostLog` rows tied to their tickets
- `webhookEventLog` rows about their account events
- Linked engineering tracker issues (cross-reference, not data)

Map every category to a deletion / retention rule.

## Voluntary Cancellation — The Default

Customer cancels subscription. Account becomes dormant but not deleted:

- Support tickets stay (customer might come back)
- Customer can still log in to view their tickets and history
- Outbound webhooks marked inactive (no automation against dormant account)
- Subsequent tickets stay possible (some support after cancellation is common — billing questions, data export)

Optional: after 24 months of dormancy, prompt customer with: "Do you want to keep your account, or should we close and delete?" Default action if no response is *retain* (deletion is the destructive option).

## Subscription Expiration — The Soft Path

Payment failures cascade through dunning. Eventually the subscription expires. Treat almost identically to voluntary cancellation, with one difference: support is *more* likely to be the path back. Don't gate "create ticket" on subscription state — locked-out customers often need to file a billing ticket to fix the lock-out.

## GDPR Right-To-Erasure — The Careful Path

Customer (or their DPO) submits an erasure request. Workflow:

1. **Verify identity** — confirm the requester is the customer (or authorized representative). Standard channels: signed-in account + email confirmation; or DPO with notarized authorization for B2B.
2. **Check legal holds** — if there's an open dispute, lawsuit, or regulatory matter, deletion may be partially deferred. Document the legal basis.
3. **Generate an export** — per [EXPORT-AND-DATA-PORTABILITY.md](EXPORT-AND-DATA-PORTABILITY.md). Customer keeps a copy.
4. **Redact (don't delete) audit trail** — `auditLog` rows replace `userId` with `[deleted-user]` token; audit-row content stays for compliance.
5. **Hard delete or anonymize** the support data:
   - `supportTickets`: anonymize (retain ticket for audit; replace personal info with `[redacted]`)
   - `supportMessages`: redact message content of customer-authored rows; admin-authored rows about them keep only ticket-id reference
   - `supportAttachments`: hard delete from storage; row preserved with `deleted_at`
   - `supportRequests` (legacy): same as tickets
6. **Tombstone** — leave a record that this user existed (uuid + deleted_at) so referential integrity holds across the rest of the system
7. **Confirmation email** to the customer-supplied email, then forget the email itself
8. **Audit** the deletion event with the legal basis and date

```ts
async function executeRightToErasure(opts: {
  userId: string;
  requestedById: string;
  legalBasis: string;
  ticketIdsOnLegalHold?: string[];
}): Promise<{ deleted: number; redacted: number; preservedForLegalHold: number }> {
  // Pre-flight: hold check
  const heldTickets = opts.ticketIdsOnLegalHold ?? await getTicketsOnLegalHoldFor(opts.userId);
  // Generate export first (customer keeps a copy)
  const exportRef = await generateAndDeliverExport(opts.userId);

  // Redact messages
  const redactedCount = await db.update(supportMessages)
    .set({ message: "[redacted per right-to-erasure]", senderId: TOMBSTONE_USER_ID })
    .where(and(
      eq(supportMessages.senderId, opts.userId),
      sql`ticket_id NOT IN (${heldTickets.length > 0 ? sql.join(heldTickets.map(t => sql`${t}`), sql`, `) : sql`SELECT NULL WHERE FALSE`})`,
    ))
    .returning({ id: supportMessages.id });

  // Anonymize ticket subjects/descriptions
  await db.update(supportTickets).set({
    subject: "[redacted]",
    description: "[redacted per right-to-erasure]",
  }).where(eq(supportTickets.userId, opts.userId));

  // Hard delete attachments (file blobs)
  const attachments = await listAttachmentsForUser(opts.userId);
  for (const a of attachments) {
    if (heldTickets.includes(a.ticketId)) continue;
    await deleteFromStorage(a.storageKey);
    await db.update(supportAttachments).set({ deletedAt: new Date(), storageKey: null }).where(eq(supportAttachments.id, a.id));
  }

  // Tombstone the user
  await db.update(users).set({
    email: `[deleted-${opts.userId}]@example.invalid`,
    displayName: "[deleted user]",
    isDeleted: true,
    deletedAt: new Date(),
  }).where(eq(users.id, opts.userId));

  // Audit (this audit row itself is exempt from deletion — legal-basis = legitimate interest in audit retention)
  await db.insert(auditLog).values({
    actionType: "user_data_erasure",
    userId: opts.requestedById,
    entityType: "user",
    entityId: opts.userId,
    metadata: {
      legalBasis: opts.legalBasis,
      preservedForLegalHold: heldTickets.length,
      exportRef,
    },
  });

  return { deleted: attachments.length - heldTickets.length, redacted: redactedCount.length, preservedForLegalHold: heldTickets.length };
}
```

### Why Tombstone Instead Of Hard-Delete

Hard-deleting the user row breaks:
- Foreign keys on tickets (cascading delete loses audit rows you need)
- References from other entities (the customer's interactions with co-customers)
- Statistical accuracy (ticket counts, retention curves)

The tombstone preserves the *fact that they existed* without preserving identifying data.

### Legal Hold Exception

Tickets under legal hold (open dispute, litigation, regulatory matter) don't get redacted. Document the legal basis:

```ts
{
  actionType: "user_data_erasure",
  metadata: {
    legalBasis: "GDPR Article 17(3)(e) - establishment, exercise or defense of legal claims",
    preservedTicketIds: ["abc-123", "def-456"],
    legalHoldDocumentRef: "<link>",
  }
}
```

## Account Termination — Hostile-User Policy

Per [SPAM-ABUSE-HOSTILE-USERS.md](SPAM-ABUSE-HOSTILE-USERS.md), repeated TOS violations → termination. Distinct from GDPR erasure:

- Account is **locked** (no login, no new tickets) but data preserved (potential litigation; team awareness for similar future patterns)
- PII partially redacted in *visible* surfaces (admin queue shows "[terminated user]") but remains in audit-only views
- Customer notified of termination with policy citation

If terminated customer later submits GDPR erasure request, the standard erasure path runs (legal hold may apply; document).

## Death Of Customer

Family or probate notifies the team that a customer has died. Sensitive handling:

1. **Verify** — request death certificate or probate documentation. Be patient.
2. **Soft-delete** account (no further charges) — pause subscription
3. **Honor data export** to estate if requested
4. **Don't auto-respond** to any further pings on the account
5. **Audit** the soft-delete with the documentation reference

For B2B accounts where the deceased was the sole admin: work with the estate to transition admin rights or wind down per their instructions.

## Legal Hold / Litigation

Subpoena or preservation order arrives. Until released:

- **Freeze deletion** of relevant tickets — tag with `legal_hold: true`
- **Snapshot current state** — full export of tickets + audit + messages, hashed and timestamped
- **No further admin mutations** without legal approval — admins see a "🔒 Legal hold" banner on those tickets
- **Audit** every read

```ts
export const legalHolds = pgTable("legal_holds", {
  id: uuid().primaryKey().defaultRandom(),
  triggeredAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  triggeredBy: uuid().references(() => users.id).notNull(),
  legalReference: text().notNull(),                          // case number / subpoena number
  scope: jsonb().notNull(),                                  // { userIds, ticketIds, orgIds, dateRange }
  expectedReleaseDate: timestamp({ withTimezone: true }),
  releasedAt: timestamp({ withTimezone: true }),
  metadata: jsonb(),
});
```

UI: "Legal hold active on this ticket" banner with reference number; reads audited; mutations blocked except with `support.legal_hold_override` permission.

## Outbound Effects On Departure

When customer leaves (any mode), update downstream:

- **Outbound webhooks**: their endpoints disabled
- **Email subscriptions**: respect their deletion-time preference (most: hard unsubscribe)
- **AI training**: any model fine-tuned on their data must be retrained without it (if applicable)
- **Vector embedding stores**: delete embeddings of their content
- **Analytics**: anonymize past events; preserve aggregate metrics
- **CRM**: mark contact deleted/inactive

Each downstream needs its own deletion handler. Wire centrally:

```ts
const DELETION_HANDLERS = [
  deleteFromOutboundWebhookEndpoints,
  deleteFromEmailSubscriptions,
  deleteFromVectorEmbeddingStore,
  anonymizeAnalytics,
  notifyCrmIntegration,
  // ... add new ones as new downstreams are introduced
];

async function processCustomerDeletion(userId: string) {
  for (const handler of DELETION_HANDLERS) {
    try {
      await handler(userId);
    } catch (err) {
      logger.error({ err, handler: handler.name, userId }, "Deletion handler failed");
      // Don't abort; partial deletion better than zero
    }
  }
}
```

Each handler idempotent — retry-safe.

## Re-Activation

Customer changed their mind; comes back:

- Voluntary cancellation: reactivate is one-click; data intact; subscription rebilled
- GDPR erasure: cannot un-delete; new account starts fresh; old tickets gone (admin can mention "we previously had a account; per request we deleted everything; this is a fresh start")
- Account termination: requires owner-tier review; not automatic
- Death: cannot reactivate

## Audit-Log Of Audit-Logs

The audit log of erasure events itself never gets deleted (legitimate interest exception). After 7-10 years (jurisdiction-dependent), summarize and purge raw events; retain summary for legal compliance.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Treating GDPR as cascading hard-delete | Loses referential integrity; breaks foreign keys; loses audit rights |
| Deleting audit rows when user is deleted | Audit-of-audit gone; impossible to prove handling later |
| Hard-deleting hostile-user accounts | Loses pattern recognition for similar future cases |
| No legal-hold mechanism | Subpoena arrives; deletions in flight; spoliation of evidence; legal exposure |
| Auto-deleting after N months without prompting customer | Surprises retentive customers; reactivation impossible |
| Conflating cancellation with deletion | Customer expects to be able to log back in |
| GDPR-deletion of account but preserving content as "valuable" | Direct violation of erasure right |
| No tombstone | Foreign-key cascade can corrupt cross-references |
| Inconsistent partial deletion across downstreams | Customer's data persists in vector store / CRM / etc. for months |
| No reactivation workflow | Customer regrets cancellation; no path back |
| No audit on deletion events | Can't prove compliance later |
| Confirmation email surviving the deletion | "Your data has been deleted" email needs to be sendable then *the email record deleted* |

## Wire Points Checklist

- [ ] Six departure modes documented with distinct handling
- [ ] `executeRightToErasure` service function with legal-hold awareness
- [ ] Tombstone strategy: preserve uuid + deleted_at, redact PII
- [ ] Audit row on every erasure with legal basis
- [ ] `legalHolds` table; banner + mutation-block in admin UI
- [ ] Pre-erasure export delivered to customer
- [ ] Downstream deletion handlers (webhooks, email subs, vector store, analytics, CRM)
- [ ] Idempotent handlers; partial failures don't block remaining
- [ ] Account termination distinct from GDPR erasure
- [ ] Death-of-customer workflow with documentation requirement
- [ ] Reactivation paths documented (cancellation vs erasure vs termination)
- [ ] Confirmation email sent then own record deleted
- [ ] Audit log of erasures retained (legitimate interest)
- [ ] Test: erase user; verify FKs intact, audit retained, attachments deleted from storage
- [ ] Test: legal hold blocks erasure of in-scope tickets but allows out-of-scope
- [ ] Documentation: customer-facing privacy policy describes the process
