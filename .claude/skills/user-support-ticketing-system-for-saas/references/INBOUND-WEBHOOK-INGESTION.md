# Inbound Webhook Ingestion

The support system isn't an island. Stripe, GitHub, status pages, KB systems, observability tools, CRM platforms — all push events that should change ticket state or create new tickets. This file is the pattern for consuming those events safely.

## The Common Shape

Every inbound webhook handler shares structural concerns:

1. **Authenticate** — verify the sender (HMAC, JWT, mTLS)
2. **Idempotency** — same event replayed produces no duplicate side effects
3. **Rate-limit** — flood protection
4. **Dispatch** — route to the right handler
5. **Audit** — every accepted event recorded
6. **Async work** — heavy work goes to a queue, not the request handler

Wrap all of that in a single `withWebhookGuards(...)` helper:

```ts
async function withWebhookGuards<T>(opts: {
  request: Request;
  source: WebhookSource;
  verify: (rawBody: string, headers: Headers) => boolean;
  parse: (rawBody: string) => T & { eventId: string; eventType: string };
  handle: (event: T & { eventId: string; eventType: string }) => Promise<void>;
}): Promise<Response> {
  const rawBody = await opts.request.text();
  if (!opts.verify(rawBody, opts.request.headers)) {
    return new Response("Invalid signature", { status: 401 });
  }
  const event = opts.parse(rawBody);

  // Idempotency: have we seen this eventId from this source before?
  const seen = await db.query.webhookEventLog.findFirst({
    where: and(eq(webhookEventLog.source, opts.source), eq(webhookEventLog.eventId, event.eventId)),
  });
  if (seen) {
    logger.info({ source: opts.source, eventId: event.eventId }, "Webhook duplicate ignored");
    return new Response("OK", { status: 200 });
  }

  // Persist BEFORE handling so a crash mid-handler doesn't leak duplicates
  await db.insert(webhookEventLog).values({
    source: opts.source,
    eventId: event.eventId,
    eventType: event.eventType,
    rawBody,
    receivedAt: new Date(),
  });

  // Handle async if heavy; sync if light
  await opts.handle(event);

  return new Response("OK", { status: 200 });
}
```

## `webhookEventLog` Schema

```ts
export const webhookEventLog = pgTable("webhook_event_log", {
  id: uuid().primaryKey().defaultRandom(),
  source: text().notNull(),                   // 'stripe' | 'github' | 'statuspage' | ...
  eventId: text().notNull(),                  // sender-supplied
  eventType: text().notNull(),
  rawBody: text().notNull(),                  // for replay
  receivedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  processedAt: timestamp({ withTimezone: true }),
  processError: text(),
}, t => [
  unique("webhook_event_unique").on(t.source, t.eventId),     // dedup constraint
  index("webhook_event_received_idx").on(t.receivedAt),
]);
```

The `unique(source, eventId)` constraint is the **defense-in-depth** for idempotency — even if the application logic fails, the DB rejects duplicates.

## Source: Stripe

Customer-billing webhooks are the highest-stakes inbound source. Failed-payment events drive support-ticket triage; refund events update audit trails.

```ts
// /api/webhooks/stripe
export async function POST(request: Request) {
  return withWebhookGuards({
    request,
    source: "stripe",
    verify: (body, headers) => {
      try {
        stripe.webhooks.constructEvent(body, headers.get("stripe-signature")!, env.STRIPE_WEBHOOK_SECRET);
        return true;
      } catch { return false; }
    },
    parse: (body) => {
      const e = JSON.parse(body);
      return { eventId: e.id, eventType: e.type, data: e.data };
    },
    handle: async (event) => {
      switch (event.eventType) {
        case "invoice.payment_failed": return handlePaymentFailed(event.data.object);
        case "charge.refunded":        return handleRefundExternal(event.data.object);
        case "customer.subscription.deleted": return handleSubscriptionDeleted(event.data.object);
      }
    },
  });
}
```

### `invoice.payment_failed` → Auto-Triage

A payment failure often produces a customer ticket within 24h. Pre-position:

```ts
async function handlePaymentFailed(invoice: Stripe.Invoice) {
  const userId = await mapStripeCustomerToUserId(invoice.customer as string);
  if (!userId) return;
  // Create or update a billing-context tag for upcoming tickets
  await upsertCustomerContextNote({
    userId,
    kind: "billing_dunning",
    message: `Payment failed on invoice ${invoice.number}; amount ${invoice.amount_due / 100} ${invoice.currency.toUpperCase()}`,
    expiresAt: addDays(new Date(), 30),
  });
  // If they file a ticket, the admin queue will surface this in the journey panel
}
```

We don't auto-create a ticket (the customer might resolve it themselves). We pre-load context so when they file, the agent has it.

### `charge.refunded` (External-Originated)

If someone issues a refund via Stripe Dashboard (bypassing the support system), reflect it as an audit row:

```ts
async function handleRefundExternal(charge: Stripe.Charge) {
  const userId = await mapStripeCustomerToUserId(charge.customer as string);
  await db.insert(auditLog).values({
    userId: null,                                          // system-attributed
    actionType: "refund_issued_external",
    entityType: "user",
    entityId: userId,
    metadata: {
      stripeChargeId: charge.id,
      stripeRefundId: charge.refunds?.data[0]?.id,
      amountCents: charge.amount_refunded,
    },
  });
  // If a ticket is open about this charge, link it
  const linkedTickets = await findTicketsMentioningCharge(userId, charge.id);
  for (const t of linkedTickets) {
    await addInternalNote({ ticketId: t.id, message: `Refund issued externally via Stripe: ${charge.id}` });
  }
}
```

Every refund — internal or external — appears in the audit log. No bypass.

## Source: GitHub / Linear / Jira (Engineering Trackers)

When linked engineering issues update, sync to support tickets via webhook:

```ts
// /api/webhooks/github
export async function POST(request: Request) {
  return withWebhookGuards({
    request,
    source: "github",
    verify: (body, headers) => verifyGithubHmac(body, headers.get("x-hub-signature-256")!, env.GITHUB_WEBHOOK_SECRET),
    parse: (body) => {
      const e = JSON.parse(body);
      const eventType = request.headers.get("x-github-event")!;
      const eventId = request.headers.get("x-github-delivery")!;
      return { eventId, eventType, ...e };
    },
    handle: async (event) => {
      if (event.eventType === "issues" && event.action === "closed") {
        await onEngineeringIssueResolved({
          externalRefKind: "github",
          externalRefId: `gh:${event.repository.full_name}#${event.issue.number}`,
          resolutionTitle: event.issue.title,
        });
      }
    },
  });
}
```

`onEngineeringIssueResolved` follows the pattern in [TICKET-LINKING-AND-RELATIONSHIPS.md](TICKET-LINKING-AND-RELATIONSHIPS.md) — adds an internal system note to all linked tickets; admins verify with customers before closing.

## Source: Status Page

See [STATUS-PAGE-INTEGRATION.md](STATUS-PAGE-INTEGRATION.md). Inbound webhook drives `incidents` table updates and triggers ticket fan-out on resolution.

## Source: Email-To-Ticket

Customers email `support@yourdomain.com`; an inbound-email service (Resend, Postmark, SendGrid Inbound Parse) POSTs to your endpoint:

```ts
// /api/webhooks/inbound-email
export async function POST(request: Request) {
  return withWebhookGuards({
    request,
    source: "inbound_email",
    verify: (body, headers) => verifyInboundEmailSignature(body, headers),
    parse: (body) => {
      const email = parseInboundEmail(body);
      return { eventId: email.messageId, eventType: "email_received", email };
    },
    handle: async (event) => {
      const userId = await findUserByEmail(event.email.from);
      if (!userId) {
        // Anonymous email — create a `support_request` (legacy table)
        await createAnonymousSupportRequest({
          email: event.email.from,
          subject: event.email.subject,
          body: event.email.text,
        });
        return;
      }
      // Check if this is a reply to an existing ticket (In-Reply-To header)
      const ticketId = await findTicketByEmailThread(event.email.inReplyTo, userId);
      if (ticketId) {
        await addMessage({
          ticketId, senderId: userId, senderType: "customer",
          message: event.email.text, attachments: extractAttachments(event.email),
        });
      } else {
        await createTicket({
          userId, subject: event.email.subject,
          description: event.email.text, source: "inbound_email",
        });
      }
    },
  });
}
```

### Email Threading

`In-Reply-To` and `References` headers carry parent message IDs. Persist your outbound email's `Message-ID` (Resend returns it); on inbound, look up the corresponding ticket. This makes email-side replies thread correctly into the in-app conversation.

### Quoted-Text Stripping

Email replies typically include the original message quoted with `>` prefixes or "On Tue, Jan 1, ... wrote:" headers. Strip before persisting:

```ts
function stripQuotedReplies(text: string): string {
  return text
    .split("\n")
    .filter(line => !line.startsWith(">"))
    .join("\n")
    .replace(/^On\s+\w+,\s+.+wrote:\s*$/m, "")
    .trim();
}
```

Imperfect; document the limitation; offer a "show full email" toggle in admin UI.

## Source: Slack / Discord (Slash Commands)

Admins use chat shortcuts to interact with tickets without leaving the chat:

```
/support tickets-mine
/support ticket-show ABC12345
/support reply ABC12345 We're looking into this and will follow up.
```

Each is a webhook from Slack/Discord to your endpoint:

```ts
// /api/webhooks/slack/slash-commands
export async function POST(request: Request) {
  return withWebhookGuards({
    request,
    source: "slack",
    verify: (body, headers) => verifySlackSignature(body, headers.get("x-slack-signature")!, headers.get("x-slack-request-timestamp")!, env.SLACK_SIGNING_SECRET),
    parse: ...,
    handle: async (event) => {
      const adminUserId = await mapSlackUserToAdminId(event.user_id);
      if (!adminUserId) return respondWithError("Not a support admin");
      const [, command, ...args] = event.text.match(/^(\S+)(?:\s+(.+))?$/) ?? [];
      switch (command) {
        case "tickets-mine": return respondWithMyTickets(adminUserId);
        case "ticket-show":  return respondWithTicket(args[0]);
        case "reply":        return respondWithReplyConfirmation(args[0], args.slice(1).join(" "), adminUserId);
      }
    },
  });
}
```

**Reply confirmation**: Slack's interactive message UI asks the admin to confirm before sending. Slack sees the reply; the customer sees an email. Audit captures both.

## Source: CRM (HubSpot, Salesforce)

CRM events drive customer-segment changes that affect support priority:

```ts
// CRM event: deal_stage_changed → "Closed Won"
// Effect: customer's tier flips to enterprise (their next ticket inherits enterprise SLA)
async function handleCrmDealClosedWon(dealId: string) {
  const userId = await mapCrmDealToUserId(dealId);
  await updateUserTier(userId, "enterprise");
  // Note: existing tickets keep their tier (per IMPLEMENTATION-PATTERNS.md #13)
}
```

## Source: Status Probes (Uptime Robot, Pingdom)

Probe alerts fire when an endpoint is degraded. Auto-create internal incident (if your team triages from the support system):

```ts
async function handleProbeAlert(probe: ProbeAlertEvent) {
  if (probe.severity !== "critical") return;
  // Internal-only ticket so the team triages it
  await createInternalTicket({
    title: `🚨 Probe failure: ${probe.endpoint}`,
    body: `${probe.endpoint} returned ${probe.statusCode} starting ${probe.timestamp}`,
    senderType: "system",
    routeToTeam: "engineering_escalation",
    priority: "p0",
  });
}
```

## Replay And Recovery

Webhook events sometimes need replay (e.g. handler bug fixed; reprocess all events from yesterday):

```ts
// /api/admin/webhooks/replay
async function replayWebhookEvents(opts: {
  source: WebhookSource;
  since: Date;
  until: Date;
  dryRun: boolean;
}): Promise<{ replayed: number; failed: number }> {
  const events = await db.query.webhookEventLog.findMany({
    where: and(
      eq(webhookEventLog.source, opts.source),
      gte(webhookEventLog.receivedAt, opts.since),
      lte(webhookEventLog.receivedAt, opts.until),
    ),
    orderBy: asc(webhookEventLog.receivedAt),
  });
  let replayed = 0, failed = 0;
  for (const e of events) {
    try {
      if (!opts.dryRun) await dispatchEvent(opts.source, JSON.parse(e.rawBody));
      replayed++;
    } catch (err) {
      failed++;
      logger.error({ err, eventId: e.eventId }, "Replay failed");
    }
  }
  return { replayed, failed };
}
```

The `unique(source, eventId)` constraint means re-running an event that was already processed doesn't double-process — but the **handler logic must be idempotent on its own side effects** (database upserts, not blind inserts).

## Replay Audit

Every replay run is owner-tier audited:

```ts
{
  actionType: "webhook_replay",
  metadata: { source: "stripe", since, until, replayed, failed, dryRun, reason: "..." }
}
```

## Anti-Patterns

| ✗ | Why |
|---|---|
| No HMAC verification | Anyone fakes events into your system |
| No idempotency log | Replays double-fan-out |
| Heavy work in the webhook handler | Provider times out and retries; thundering herd |
| Reading-then-writing without `unique` constraint | Race condition on simultaneous deliveries |
| Logging full webhook bodies at INFO with PII | Subpoena risk; log-export risk |
| Webhook handler that throws on unknown event type | Provider sees 500; retries forever |
| No "dry-run" replay mode | First replay either does nothing useful or breaks production |
| Email parsing without quoted-reply stripping | Conversation thread becomes nested copies |
| Email threading without `Message-ID` persistence | Reply-by-email creates a new ticket every time |
| Slash-command handlers without admin-permission check | Slack workspace member could mutate tickets |

## Wire Points Checklist

- [ ] `withWebhookGuards` helper centralizes auth + idempotency + audit + dispatch
- [ ] `webhook_event_log` table with `unique(source, eventId)` constraint
- [ ] HMAC verification per source (Stripe, GitHub, Slack, etc.)
- [ ] Heavy work queued; webhook handler responds < 1s
- [ ] Provider retries handled idempotently
- [ ] Stripe `invoice.payment_failed` pre-loads billing context
- [ ] Stripe `charge.refunded` (external) recorded as system audit
- [ ] GitHub/Linear/Jira issue-resolved → linked-ticket internal note
- [ ] Status page resolution → linked-ticket fan-out
- [ ] Inbound email parsed, threaded, attachments extracted
- [ ] Quoted-reply stripping on email
- [ ] `Message-ID` persisted on outbound email for threading
- [ ] Slack slash-command admin-permission check
- [ ] Slack reply confirmation before sending to customer
- [ ] CRM events drive tier updates (NEW tickets only, per immutable-tier rule)
- [ ] Probe alerts auto-create internal tickets (P0 routed to on-call)
- [ ] Replay endpoint with dry-run mode and owner audit
- [ ] Failed-event quarantine (after N retries, move to "needs review" surface)
