# Export And Data Portability

Customers eventually leave. Auditors eventually arrive. Engineering eventually wants to migrate. Each is a use-case for "export everything we know about this ticketing system in a machine-readable form." This file is the canonical export pattern.

## Three Audiences, Three Shapes

### Audience 1 — The Customer (GDPR-Style Data Export)

When a customer requests their data:

```ts
async function exportCustomerData(userId: string): Promise<CustomerDataExport> {
  const tickets = await db.query.supportTickets.findMany({
    where: eq(supportTickets.userId, userId),
    with: { messages: true },
  });
  const requests = await db.query.supportRequests.findMany({
    where: eq(supportRequests.userId, userId),
  });
  return {
    exportedAt: new Date().toISOString(),
    userId,
    schemaVersion: 1,
    tickets: tickets.map(t => ({
      id: t.id,
      subject: t.subject,
      description: t.description,
      priority: t.priority,
      status: t.status,
      createdAt: t.createdAt,
      resolvedAt: t.resolvedAt,
      messages: t.messages
        .filter(m => m.senderType !== "internal_note")    // never export internal notes to the customer
        .map(m => ({
          id: m.id,
          fromYou: m.senderType === "customer",
          message: m.message,
          attachments: m.attachments,                     // copied into export or short-lived signed URLs
          createdAt: m.createdAt,
        })),
    })),
    requests: requests.map(r => ({ ... })),
  };
}
```

**Critical filters:**
- Never include internal notes
- Never include admin's `displayName` (the customer doesn't need to know who specifically)
- Don't include audit log (internal)
- Don't include cost data, AI cost, etc.
- Prefer copying permitted attachments into the export ZIP so the package is self-contained. If using signed URLs instead, keep them short-lived (for example, up to 7 days), auth-bound where possible, and regenerable from the export request page.

Format: JSON for engineers + a human-readable HTML version (rendered template) for non-technical customers. Email a download link, not the export ZIP itself.

### Audience 2 — The Admin (CSV Export For Analysis)

For admins running custom analysis (which the system's metrics don't cover yet):

```
Content-Disposition: attachment; filename="tickets-2026-04-27.csv"
```

CSV with one row per ticket, columns including:
- `id, subject, priority, status, category`
- `created_at, resolved_at`
- `sla_status, hours_until_breach, sla_breached`
- `user_email, user_display_name, org_name`
- `assignee, team`
- `message_count, customer_message_count, support_message_count`
- `cost_total_cents, admin_minutes`
- `tags`

CSV is requested with filter (status / priority / date range). Export route is permission-gated (`support.export`) and audited. Escape spreadsheet formulas in every CSV cell (`=`, `+`, `-`, `@` prefixes) so opening the export in Excel/Sheets cannot execute attacker-controlled formulas from ticket text.

```ts
// GET /api/admin/support/tickets/export?from=...&to=...&status=...
export async function GET(request: Request) {
  const auth = await requireAdmin(request);
  if (!auth.success) return auth.response;
  const url = new URL(request.url);
  const reason = url.searchParams.get("reason") ?? "";
  const mutation = await requireAdminMutation(request, { admin: auth.user, permission: "support.export", reason, requireReason: true });
  if (!mutation.success) return mutation.response;

  const tickets = await listFilteredTickets(url.searchParams);
  const csv = ticketsToCsv(tickets);

  await mutation.context.logAction({
    actionType: "support_csv_exported",
    metadata: { rowCount: tickets.length, filterSummary: url.searchParams.toString() },
  });

  return new Response(csv, {
    headers: {
      "Content-Type": "text/csv",
      "Content-Disposition": `attachment; filename="tickets-${new Date().toISOString().split("T")[0]}.csv"`,
    },
  });
}
```

Streaming for large exports:

```ts
const stream = new ReadableStream({
  async start(controller) {
    controller.enqueue(encoder.encode(headerLine));
    let cursor: Date | null = null;
    while (true) {
      const batch = await getNextBatch(cursor, 500);
      if (batch.length === 0) break;
      for (const ticket of batch) {
        controller.enqueue(encoder.encode(toCsvLine(ticket) + "\n"));
      }
      cursor = batch.at(-1)!.createdAt;
    }
    controller.close();
  },
});
return new Response(stream, { headers: { ... } });
```

Browser starts downloading immediately; even 100k-row exports don't OOM the server.

### Audience 3 — The Provider Migration

When migrating off this system to another (or vice versa), bulk export in JSONL — one ticket per line, full nested shape:

```jsonl
{"id":"abc","subject":"...","messages":[{...}],"audit":[{...}]}
{"id":"def","subject":"...","messages":[{...}],"audit":[{...}]}
```

JSONL is streamable, parses without holding the whole dataset in memory, and round-trips cleanly. Include:
- Full ticket fields (including all timestamps)
- All messages (including internal notes, since the destination team owns the data)
- Audit log entries scoped to the ticket
- Attachment storage keys (the destination provider needs to fetch from the storage bucket separately)

```ts
async function* streamMigrationExport(): AsyncIterable<string> {
  let cursor: Date | null = null;
  while (true) {
    const batch = await getNextBatch(cursor, 100);
    if (batch.length === 0) return;
    for (const ticket of batch) {
      const messages = await getMessagesFor(ticket.id);
      const audit = await getAuditFor(ticket.id);
      yield JSON.stringify({ ticket, messages, audit }) + "\n";
    }
    cursor = batch.at(-1)!.createdAt;
  }
}
```

For large exports, batch-load messages and audit rows by the batch's ticket IDs
instead of issuing per-ticket queries. The JSONL shape is one ticket per line;
the database access does not have to be N+1.

## Schema Versioning

Every export embeds a `schemaVersion`:

```json
{ "schemaVersion": 2, "exportedAt": "2026-04-27T...", ... }
```

When the schema changes, bump the version. Document migration paths in [MIGRATION-PER-PROVIDER.md](MIGRATION-PER-PROVIDER.md). A consumer sees `schemaVersion: 2`, looks up the migration table, applies field renames/coercions to upgrade an older export to the latest shape.

## Export Audit

Every export — customer-data, admin-CSV, provider-migration — is audited:

```json
{
  "actionType": "support_data_exported",
  "userId": "<admin id, or null for system>",
  "metadata": {
    "audience": "customer" | "admin" | "migration",
    "scope": { "userId": "...", "from": "...", "to": "..." },
    "rowCount": 1247,
    "schemaVersion": 2,
    "exportFormatHash": "sha256:..."   // detect if format drifted between exports
  }
}
```

Useful when the customer asks 6 months later "did you export my data on date X?" — the audit row answers.

## Customer-Side Self-Serve Export

`/account/data-export` — a customer-facing surface where they can request their own data. Generates the export, emails them a download link with 7-day expiry. Standard GDPR-compliance UX.

```ts
// POST /api/account/data-export
export async function POST(req) {
  const auth = await requireUser(req);
  if (!auth.success) return auth.response;
  // Rate-limit to 1 per 24h per user — don't let people DOS the system with exports
  if (await hasRecentExport(auth.user.userId, 24)) {
    return validationError({ rate: "Already exported in last 24h; check your email" });
  }
  await enqueueExport(auth.user.userId);
  return NextResponse.json({ status: "queued", estimatedSeconds: 60 });
}
```

Background worker generates the export, stores in a 7-day-expiring bucket, emails the customer a signed URL. They click → download.

## Import (Reverse Direction)

When migrating IN from another provider:

```ts
async function importMigrationStream(stream: AsyncIterable<string>): Promise<{ imported: number; failed: ImportFailure[] }> {
  const failures: ImportFailure[] = [];
  let imported = 0;
  for await (const line of stream) {
    try {
      const parsed = JSON.parse(line);
      const upgraded = upgradeSchema(parsed, parsed.schemaVersion);  // bring up to current schema
      const insertable = mapToInsertable(upgraded);
      if (await alreadyImported(insertable.metadata.original_id)) {
        continue;
      }
      await db.transaction(async (tx) => {
        const [ticket] = await tx.insert(supportTickets).values(insertable.ticket).returning();
        if (insertable.messages.length) await tx.insert(supportMessages).values(insertable.messages.map(m => ({ ...m, ticketId: ticket.id })));
      });
      imported++;
    } catch (err) {
      failures.push({ line: line.slice(0, 200), error: err.message });
    }
  }
  return { imported, failures };
}
```

**Critical:** preserve the original ticket ID via a `metadata.original_id` field. Lets you resolve cross-references and run the migration idempotently (skip already-imported tickets).

## Selective Export For Customer-Communication Verification

A specific compliance use-case: customer disputes "you never told me X." Auditor asks for "every customer-visible communication this customer received from your system, with timestamps."

Different from the customer-data export above; this excludes the customer's own messages, focuses on outbound:

```ts
async function exportOutboundCommunication(userId: string): Promise<OutboundExport> {
  const messages = await db.query.supportMessages.findMany({
    where: and(
      sql`${supportMessages.ticketId} IN (SELECT id FROM support_tickets WHERE user_id = ${userId})`,
      eq(supportMessages.senderType, "support"),
    ),
    orderBy: asc(supportMessages.createdAt),
  });
  const emails = await db.query.emailLog.findMany({
    where: eq(emailLog.recipientUserId, userId),
    orderBy: asc(emailLog.sentAt),
  });
  return { messages, emails, generatedAt: new Date(), forUserId: userId };
}
```

The `emailLog` table records every transactional email sent (subject, type,
sentAt, provider message id). Useful here.

## Scheduled Exports

For enterprise customers who want monthly data dumps:

```ts
const SCHEDULED_EXPORTS = await db.select().from(scheduledExports);
// runs nightly:
for (const exp of SCHEDULED_EXPORTS) {
  if (shouldRunNow(exp)) {
    const data = await exportForOrg(exp.orgId, exp.windowSpec);
    await uploadToCustomerBucket(data, exp.destination);   // S3 bucket they own
    await markExportCompleted(exp.id);
  }
}
```

Customer specifies an S3 bucket they own; the system writes to it. They handle ingestion. Saves the customer the manual export step every month. Use a customer-owned write-only credential or pre-signed destination, encrypt at rest, record the object hash, and audit each scheduled delivery.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Including internal notes in customer data export | GDPR violation; team's candor preserved by separation |
| Exporting all-tickets without permission gate | Privacy of customers in the export depends on requester being authorized |
| No schema version on export | Downstream can't detect drift; breaks integrations silently |
| Synchronous export of 1M+ rows | OOM the server; client times out |
| Permanent signed URLs in export attachments | Defeats short-expiry attachment security |
| Exporting without audit | Subpoena response is "we don't know" |
| Customer self-serve export without rate limit | DOS surface |
| CSV export including PII without admin reason | Privacy regression |
| CSV cells not formula-escaped | Spreadsheet injection from customer-controlled ticket text |
| Importing without preserving original IDs | Cross-references break; can't resume on failure |

## Wire Points Checklist

- [ ] Customer-side export endpoint with internal-note filter, attachment signed URLs (7d)
- [ ] Admin CSV export with permission + reason + audit
- [ ] CSV formula-injection defense for all customer-controlled fields
- [ ] CSV export streamed (no full-buffer)
- [ ] Migration JSONL export including audit and original IDs
- [ ] Schema version embedded in every export
- [ ] Migration upgrade table for older schema versions
- [ ] `support_data_exported` audit event with audience + scope + row count
- [ ] Customer self-serve export rate-limited (1 per 24h)
- [ ] Email log table populated by `sendEmail` for outbound-comm export
- [ ] Outbound-communication export endpoint (compliance / legal)
- [ ] Scheduled-export infrastructure for enterprise contracts
- [ ] Import path preserves `metadata.original_id` for idempotent re-imports
