# User-Facing UI

Three components: `SupportWidget` (entry point), `NewTicketForm` (modal), `TicketList` (history view).

## SupportWidget

Floating button in `app/layout.tsx` (or page-specific). Click → modal opens with two tabs:
- **New ticket** → `NewTicketForm`
- **Your tickets** → `TicketList`

Auto-fill `pageUrl` from `window.location.href` so the user doesn't have to describe where they were.

## NewTicketForm

Required fields: `subject`, `description`, `category`. Optional: `priority` (default p2), `screenshot` (R2/S3 upload via signed URL).

UX rules:
- Show SLA expectations under the priority selector: "P2: response within 24h"
- After submit, show the short ID and a `/support/tickets/{id}` link — sets expectation "you have a record"
- Send `{ ticketId }` to GA4 / analytics for support funnel measurement

## TicketList

```
[Open: 2]  [Resolved: 7]
─────────────────────────────────
#ABC12345  Can't export skills        in_progress  2h ago  →
#XYZ98765  Billing question           awaiting_customer    →
                                      (Action needed by you)
─────────────────────────────────
```

Click → `/support/tickets/{id}` detail page with thread + reply form.

## Ticket Detail Page

`/support/tickets/[id]/page.tsx` — server component, hydrates from `/api/support/tickets/[id]`.

Layout:
```
{shortId}   {priority}   {status pill}     created 2 days ago
{subject}
{description}

────────── Conversation ──────────
You · 2 days ago         {message}
Acme Support · 1 day ago {reply}
You · 22h ago            {message}
─────────────────────────────────
[ Reply textarea ]                          [Send]

(disabled if status = closed)
```

Status pills with explanation: `awaiting_customer` should literally say "Acme is waiting on a reply from you" not just the enum value. Translate jargon.

## Empty + Loading + Error States

- Empty: "No support tickets yet" + a "Need help?" CTA
- Loading: skeleton rows, not a centered spinner
- Error: keep the rest of the page intact + a small banner; don't blow away the navigation

## SupportWidget — Accessibility + Polish Details

The floating widget is the most-seen support UI; small details add up:

- **Escape dismisses** — register `keydown` listener inside `useEffect` (only when expanded), clean up on collapse/unmount.
- **`useId()` for `aria-controls`** — unique panel id pairs the trigger button with the panel for screen readers.
- **`aria-expanded`** — reflects current state on the trigger button.
- **Open-count badge clamps at "9+"** — `{openCount > 9 ? "9+" : openCount}` keeps the pill geometry stable.
- **SLA pitch in the footer** — if the product has paid SLA tiers, a short tier-specific line doubles as discovery for upgrades.
- **Close button mirrors the trigger** — same icon (X) inside the expanded panel header so the dismiss target is unambiguous.

```tsx
useEffect(() => {
  if (!isExpanded) return;
  const handler = (e: KeyboardEvent) => { if (e.key === "Escape") setIsExpanded(false); };
  document.addEventListener("keydown", handler);
  return () => document.removeEventListener("keydown", handler);
}, [isExpanded]);

// Badge with clamp
{openCount > 0 && (
  <span className="absolute -top-1 -right-1 ...">{openCount > 9 ? "9+" : openCount}</span>
)}
```

## NewTicketForm — Critical Details

### Priority Options With Descriptions

Don't just label P0/P1/P2/P3 — describe what each means in the customer's language:

```ts
const PRIORITY_OPTIONS = [
  { value: "p0", label: "Critical", description: "Site down, data loss, security issue" },
  { value: "p1", label: "High",     description: "Major feature broken, blocking work" },
  { value: "p2", label: "Normal",   description: "Bug or issue affecting workflow" },
  { value: "p3", label: "Low",      description: "Minor issue, question, or suggestion" },
];
// rendered: "<option>Critical - Site down, data loss, security issue</option>"
```

Without descriptions, customers default to P0 to "get faster service" — the team drowns in misclassified urgency.

### SLA Expectation Surfaced Post-Create

After successful create, format the deadline and show it in the success toast:

```ts
function formatSlaExpectation(deadline: string | null): string | null {
  if (!deadline) return null;
  const date = new Date(deadline);
  if (Number.isNaN(date.getTime())) return null;
  const formatted = date.toLocaleString("en-US", {
    month: "short", day: "numeric", hour: "numeric", minute: "2-digit",
  });
  return `Expected response by ${formatted}`;
}
```

The customer's first impression of the system is "I have a record AND I know when to expect a reply." The customer who knows the SLA writes back at the SLA, not 4 hours after waiting.

### Fallback To Legacy Contact On Failure

If the ticket API fails (server error, schema drift), the form silently falls back to `POST /api/support` (the legacy contact-form endpoint), captures a reference id, and tells the customer their request was received:

```ts
try {
  result = await mutation.mutateAsync({ subject, description, priority });
} catch (err) {
  if (err instanceof InvalidCreateTicketResponseError) {
    // Hard error — payload shape failed validation. Don't fall back; surface the bug.
    setToast({ type: "error", message: "Ticket created but the response payload was incomplete. Please refresh." });
    return;
  }
  // Soft fallback — try the contact form path
  const fallback = await submitFallbackSupportRequest({ subject, description, priority });
  setReference(fallback.requestId);
  setToast({ type: "success",
    message: "Ticketing is temporarily unavailable. Your request was sent to support and we will reply by email." });
  // ...reset form, exit
}
```

Distinguishing payload-shape errors from server errors:
- Shape errors → likely a schema regression in the new API; *don't* fall back, surface so the bug gets noticed.
- Other errors → likely transient server fault; the contact form is the safety net.

### Redirect Timer Cleanup

Navigate to the new ticket's detail page after a brief delay (so the success toast is read), but cancel the timer on unmount:

```ts
const redirectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
useEffect(() => () => { if (redirectTimerRef.current) clearTimeout(redirectTimerRef.current); }, []);
// after success:
redirectTimerRef.current = setTimeout(() => {
  redirectTimerRef.current = null;
  router.push(`/support/${ticket.id}`);
}, 1000);
```

Without cleanup, fast-clicking users navigate away then bounce back via the timer — "stale navigation" feels like the app is fighting them.

### Reference ID On Fallback

When the fallback path activates, surface the reference id prominently so the customer can quote it in follow-up email — proves the request was received and gives support a join key:

```tsx
{reference && (
  <div className="bg-muted/40 mt-4 rounded-md px-3 py-2 text-xs">
    Reference ID: <span className="font-semibold">{reference}</span>
  </div>
)}
```
