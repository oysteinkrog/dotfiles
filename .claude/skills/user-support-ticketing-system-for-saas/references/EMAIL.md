# Email Pipeline (Resend)

## Reference Index

- Core email functions and wire points.
- `/de-slopify` requirement for every customer-visible body.
- Background hook / queue / outbox scheduling.
- Ticket display IDs, footer preference links, and template discriminators.

`src/lib/email/support.ts` exposes three functions; each is the *only* path for that lifecycle event.

```ts
sendTicketCreatedEmail({ ticketId, userId, subject, priority, slaHours })   // confirms creation
sendTicketResponseEmail({ ticketId, userId, subject, responseMessage })     // admin reply notify
sendTicketResolvedEmail({ ticketId, userId, subject })                      // status → resolved
```

Optional, only if `support_requests` table exists:
```ts
sendSupportRequestResponseEmail({ requestId, userId, summary, adminNotes }) // legacy contact form
```

## Hard Rules

- Each function looks up the user, fails closed if email missing, and **always returns** `{ sent, messageId? }` — never throws upstream.
- Logging on both success and failure paths.
- Metadata tags every send: `{ type, ticketId, userId }` for delivery analytics + idempotency.
- Use the background hook / queue / outbox helper to schedule sends. In the default Next.js path that helper uses `next/server` `after()`; admin reply API mustn't block on email-out.
- Templates live in `src/emails/templates/transactional/`. Render via React Email or HTML-with-text fallback.
- Footer always includes `preferencesUrl` + `unsubscribeUrl` (even for transactional — generates trust). `supportUrl` for self-service.

## Wire Points

| Caller | Calls |
|---|---|
| `createTicket()` (service) | `sendTicketCreatedEmail` |
| `POST /api/admin/support/tickets/[id]/messages` | `sendTicketResponseEmail` |
| `updateTicket(... status: "resolved")` | `sendTicketResolvedEmail` |
| `PATCH /api/admin/support` (legacy resolve) | `sendSupportRequestResponseEmail` |

Integration tests must verify each wire point: not "the function exists" but "the function is *invoked* in the request lifecycle".

## Subject Line Pattern

```
[Acme] Re: <subject>          # admin reply
[Acme] Ticket #ABC12345 created
[Acme] Your ticket has been resolved
```

`ticketId.slice(0, 8).toUpperCase()` is the user-friendly short ID. Never expose the full UUID in subject lines or templates — looks ugly and leaks DB internals.

## Config Required

```
RESEND_API_KEY=re_xxx
RESEND_FROM_EMAIL=support@yourdomain.com
RESEND_FROM_NAME=Acme Support
NEXT_PUBLIC_URL=https://yourdomain.com
```

See the triage skill's RESEND-SETUP.md for the owner walkthrough when these env vars are missing.

## All Customer-Facing Reply Bodies Run Through `/de-slopify`

The `responseMessage` parameter to `sendTicketResponseEmail` carries an agent's draft straight to the customer's inbox. Anything that smells of LLM defaults — "I'd be happy to help", "Unfortunately,", em-dashes for emphasis, sentence-rhythm uniformity, "delve / robust / kindly" — torches trust the moment the customer reads it. **Run every `responseMessage` through `/de-slopify` before calling the send function.**

Wire it as the last step of the admin reply pipeline:

```ts
// POST /api/admin/support/tickets/[id]/messages
const draftMessage = req.body.message;
const cleanMessage = await deslopify(draftMessage);  // calls /de-slopify
// ...persist `cleanMessage` to supportMessages, then:
await sendTicketResponseEmail({ ticketId, userId, subject, responseMessage: cleanMessage });
```

This applies equally to system-generated bodies (created/resolved templates). When you change a template, run the new copy through `/de-slopify` once at authoring time and lock the result. The triage skill's `references/VOICE-CALIBRATION.md` documents the AI-tells `/de-slopify` catches and why each one erodes trust.

## `scheduleSupportSideEffect` — Background Hook With Fallback

Every email send goes through one helper so request-scoped scheduling, fallback execution for tests/cron/scripts, error logging, and observability all live in a single place. In the default Next.js path the scheduling hook is `after()`; in other stacks use the queue/outbox/background-task primitive:

```ts
function scheduleSupportSideEffect(
  task: () => Promise<void>,
  logContext: Record<string, unknown>,
  fallbackMessage: string,
) {
  const wrappedTask = async () => {
    try { await task(); }
    catch (err) { logger.error({ err, ...logContext }, "Support side effect failed"); }
  };
  try { after(wrappedTask); }
  catch (err) {
    logger.warn({ err, ...logContext }, fallbackMessage);
    void wrappedTask();    // outside request scope (test, cron, CLI) — run inline
  }
}
```

Use it for *every* support email, not just `sendTicketCreatedEmail`. The `logContext` keys (e.g. `{ ticketId, userId }`) appear on both success and failure log lines so SREs can tie failures back to a ticket without re-querying.

## Ticket-ID Display Convention

Don't expose the full UUID in customer-visible places. Slice the first 8 characters and uppercase:

```ts
const displayId = ticketId.slice(0, 8).toUpperCase();
// "Ticket #ABC12345 created"
```

The full UUID stays in the URL (where uniqueness matters); the display form is what humans read and quote.

## Footer Links — Tokenized Preference URL

The footer's preferences/unsubscribe URL is a *signed, time-limited token* generated per recipient, not a static URL:

```ts
function getFooterLinks(userId: string): TransactionalFooterLinks {
  const preferenceUrl = generatePreferenceUrl(userId);     // signed token
  return {
    preferencesUrl: preferenceUrl,
    unsubscribeUrl: preferenceUrl,                          // same target — fewer steps for the user
    supportUrl: `${BASE_URL}${ROUTES.SUPPORT.ROOT}`,
  };
}
```

The same token serves preferences and unsubscribe — anti-pattern is making the user click "unsubscribe → log in → find prefs page → toggle." Compliance only requires *a* working unsubscribe; UX wants it to be the fastest path possible.

## Template `kind` Discriminator

When the same template (e.g. `renderTicketResponseEmail`) renders for two different domain objects (ticket vs legacy support_request), pass a `kind: "ticket" | "request"`:

```ts
const rendered = await renderTicketResponseEmail({
  // ...common fields...
  kind: "request",   // template uses this to pick CTA label/preview/subject
});
```

Inside the template:
- `kind === "request"` → CTA "View response", preview "Response to your support request", subject "[Acme] Response to your support request"
- `kind === "ticket"` (default) → CTA "View conversation", preview "New response on ticket", subject "[Acme] Re: <subject>"

A request has no conversation thread; pretending it does in the email confuses the customer when the link lands on a flat admin-notes view.
