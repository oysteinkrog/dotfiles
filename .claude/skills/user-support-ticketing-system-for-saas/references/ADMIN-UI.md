# Admin UI Patterns

`src/app/admin/support/tickets/page.tsx` — TanStack Query, filter bar, count pills, action queue.

## Hard Rules (Inherited From admin-page-for-nextjs-sites)

- One `AdminShell` (single nav + context).
- Central query keys (`admin.support.*`) via TanStack hook factory.
- KPI cards hydrate from API on first load — never client-only state.
- "Unavailable" is rendered as `--`, never `0`.
- Force-refresh via `refresh=true` query param supersedes in-flight stale.

## Filter Bar (Required)

```
[ Status ▾ ]  [ Priority ▾ ]  [ Assignee ▾ ]  [ SLA bucket ▾ ]  [ Search ]
   ⏱ Show only breached   ⚡ Approaching breach (≤2h)
```

Default: status=open, sort by `slaDeadline ASC` so most-urgent is at the top. The list is an *action queue*, not a catalog.

## Count Pills

Pull from `counts` and `priorityStats` in the GET response:

```
Open 12   Acknowledged 4   In Progress 7   Awaiting Customer 3   Resolved 28
P0 0     P1 2             P2 18           P3 6
SLA: ⚠ 2 breached • 4 at risk
```

Click a pill → applies that filter.

## Row Surface

| Column | Notes |
|---|---|
| Subject | `{shortId} {priority-badge} {subject}` — bold if breached |
| User | displayName + email tooltip |
| Status | colored pill — clickable for inline transition |
| SLA | `2.4h` green / `0.5h` amber / `breached 4h ago` red |
| Last activity | relative time |
| Assignee | dropdown for inline reassign |
| Actions | View / Reply / Resolve |

## Action Queue Pattern (Not Charts)

Charts go on `/admin/support/sla-metrics`, not on the tickets page. The tickets page is **what to do next**. Resist the urge to add graphs — operators want triage.

## Reply Modal

- Big textarea (use `cmd+enter` to submit).
- Always asks for `reason` if the action also changes status (e.g., reply + resolve).
- Pre-fills templates if the project has saved replies in the DB.
- Shows the customer's last 3 messages inline so the operator doesn't context-switch.

## Optimistic Updates

For status / assignee changes:
- Optimistically update query cache.
- On error, revert + toast.
- Refetch the whole filtered list after success (counts + ordering may change).

## Permission Gates

Every action button checks the permission key:
```tsx
{can("support.assign") && <ReassignButton />}
{can("support.resolve") && <ResolveButton />}
```

Hide, don't disable. Disabled buttons that no one in the role has access to is dead UI.

## SLA Label Rules — Read Persisted, Not Recomputed

The "Met / Missed / Paused" labels read from the *persisted* `slaStatus` column. They are not recomputed in the UI from `slaDeadline` and `now`:

```ts
function formatSlaStatus(ticket: SupportTicket) {
  if (!ticket.slaDeadline) return null;

  // Terminal states: read historical slaStatus so a ticket resolved past
  // its deadline shows "Missed", not "Met".
  if (ticket.status === "resolved" || ticket.status === "closed") {
    return ticket.slaStatus === "breached"
      ? { label: "Missed", color: "text-red-400" }
      : { label: "Met",    color: "text-green-400" };
  }

  // Paused states: clock is stopped, but surface historical breach if any.
  if (ticket.status === "awaiting_customer") {
    return ticket.slaStatus === "breached"
      ? { label: "Paused (past SLA)",         color: "text-amber-400" }
      : { label: "Paused — awaiting customer", color: "text-slate-400" };
  }

  // Active: live countdown.
  if (ticket.slaBreached) return { label: "Breached", color: "text-red-400" };
  const h = sanitizeCount(ticket.hoursUntilBreach);
  if (h !== null && h <= 2) return { label: `${h}h left`, color: "text-orange-400" };
  if (h !== null)            return { label: `${h}h left`, color: "text-green-400" };
  return null;
}
```

UI recomputation re-introduces drift between the cron's view and the user's view. The persisted column is the contract — if it's wrong, fix the cron, not the UI.

## Empty / Unknown Sentinels (Never `0`)

Counts have an explicit "unknown" sentinel (`null`) and a `formatCount(value)` helper that renders `—`:

```ts
const EMPTY_COUNT_METRICS = { open: null, acknowledged: null, in_progress: null,
                              awaiting_customer: null, resolved: null, closed: null };

function sanitizeCount(v: number | null | undefined): number | null {
  return typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : null;
}
function formatCount(v: number | null | undefined): string {
  const safe = sanitizeCount(v);
  return safe === null ? "—" : safe.toLocaleString();
}
```

`0` is ambiguous — is it really zero, or did the API fail to return it? An em-dash tells the admin "we don't know" — and that's a different action than "we know it's zero."

## Cascading Query Invalidation

Mutation `onSuccess` invalidates the queues that surface ticket counts beyond just the support page. Adjacent cockpits stay coherent:

```ts
onSuccess: (ticket) => {
  setActionError(null);
  queryClient.invalidateQueries({ queryKey: queryKeys.admin.support.ticketsAll });
  queryClient.invalidateQueries({ queryKey: ["admin", "support", "tickets", "approaching-sla"] });
  queryClient.invalidateQueries({ queryKey: queryKeys.admin.support.slaMetricsAll });
  queryClient.invalidateQueries({ queryKey: ["admin", "operations", "summary"] });
  queryClient.invalidateQueries({ queryKey: ["admin", "command-center"] });
}
```

Without the cascade, an admin who changes a ticket status sees the support page update but the operations cockpit lag by 30 seconds — incoherent across surfaces.

## Runtime Payload Validators

Every fetch boundary uses a runtime type guard:

```ts
function isSupportTicket(value: unknown): value is SupportTicket { /* exhaustive checks */ }
function isTicketListResponse(value: unknown): value is TicketListResponse { /* ... */ }

const data = await readValidatedJsonResponse(response, "Failed to fetch support tickets", isTicketListResponse);
```

A schema migration on the server (someone renames `slaDeadline` → `dueAt`) silently corrupts the UI until a bug report says "I don't see SLA labels anymore." Runtime validators turn that into a loud, recoverable error at the network boundary.

## Reason-Required Mutation Flow (Prompt Dialog)

For status / priority / assignee changes, the UI prompts for a reason via `usePromptDialog` before sending:

```ts
const { prompt, dialogProps } = usePromptDialog();
const getActionReason = async (label: string) =>
  prompt({ title: label, description: "Provide a reason for this change (min 8 characters).", confirmLabel: "Submit" });

// On click:
const reason = await getActionReason("Resolve ticket");
if (!reason) return;
updateTicket(ticketId, { status: "resolved", reason });
```

The server enforces `reason: adminReasonSchema` (min 8 chars). Catching it at the UI is the difference between "frustrating round trip" and "smooth flow."

## Pagination — Defensive Math

The pagination total can be `null` under failure modes; the UI must not crash or render "Page 1 of 0":

```ts
const safePaginationTotal  = data ? sanitizeCount(pagination.total) : 0;
const lastPageOffset = (safePaginationTotal === null || safePaginationTotal === 0)
  ? 0
  : Math.floor((safePaginationTotal - 1) / PAGE_SIZE) * PAGE_SIZE;
const fallbackOffset = safePaginationTotal === null
  ? Math.max(0, offset)
  : Math.min(Math.max(0, offset), lastPageOffset);
```

`Math.min(Math.max(0, offset), lastPageOffset)` clamps the user's offset into the valid range so a refetch with stale counts doesn't show "Page 47 of 5."

## Sticky Top Header With Filter Bar

The filter bar lives in a `position: sticky; top: 0; z-50` header so it stays visible during scroll. Backdrop-blur for elegance:

```tsx
<header className="border-border/40 bg-background/95 supports-[backdrop-filter]:bg-background/60 sticky top-0 z-50 mb-6 border-b backdrop-blur">
```

Triage is fast scrolling through 50+ tickets; losing the filter bar to scroll forces context-restoration every few seconds.
