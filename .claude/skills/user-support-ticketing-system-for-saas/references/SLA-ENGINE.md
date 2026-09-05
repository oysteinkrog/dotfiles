# SLA Engine

The single source of truth for "is this ticket on time?" Lives in `src/lib/services/support-tickets.ts`. All other layers (admin UI, cron, email) consume the fields it computes.

Lifecycle transitions are specified canonically in
[STATE-MACHINE-CONFORMANCE.md](STATE-MACHINE-CONFORMANCE.md). Treat this file as
the Next.js/Drizzle implementation guide for SLA deadlines and status fields,
not a competing state-machine policy.

## Configuration

```ts
const SLA_CONFIG = {
  enterprise: {
    firstResponse: { p0: 1, p1: 2, p2: 4, p3: 8 },
    resolution:    { p0: 4, p1: 8, p2: 24, p3: 48 },
  },
  individual: {
    firstResponse: { p0: 4, p1: 8, p2: 24, p3: 48 },
    resolution:    { p0: 24, p1: 48, p2: 72, p3: 168 },
  },
} as const;

const DEFAULT_SLA_WARNING_HOURS = 2;  // "at_risk" threshold
```

Tier is derived from the user's subscription state at ticket creation. Re-deriving on each compute would let plan downgrades affect already-created tickets — don't.

## OPEN_TICKET_STATUSES (Exported)

```ts
export const OPEN_TICKET_STATUSES: SupportStatus[] = [
  "open", "acknowledged", "in_progress",
];
```

`awaiting_customer` is intentionally excluded — the SLA clock is paused while we wait on them. `resolved` and `closed` are terminal.

Every "is this ticket SLA-tracked right now?" check imports this constant. Drift is the #1 source of phantom-breach bugs.

## Status Transition Computation

```ts
function computeNextStatusAfterMessage(
  current: SupportStatus,
  senderType: "customer" | "support",
): SupportStatus | null {
  if (current === "resolved" || current === "closed") return null;  // terminal
  if (senderType === "support") {
    return current === "awaiting_customer" ? null : "awaiting_customer";
  }
  // customer reply
  return current === "awaiting_customer" ? "in_progress" : null;
}
```

Returns `null` when no change is needed (so the API can short-circuit the UPDATE).

## Deadline Computation

On ticket create:
```ts
slaDeadline = createdAt + SLA_CONFIG[tier].firstResponse[priority] hours
```

On status → `awaiting_customer`: deadline is **frozen** (we don't reset it; the clock pauses but the budget stays where it was).

On status `awaiting_customer` → `in_progress`: deadline is recomputed using the *remaining* time budget, not a fresh full window. Implementation: store `slaPausedAt`, on resume `slaDeadline += (now - slaPausedAt)`.

On status → `resolved`: clear `slaDeadline`. Keep `slaBreachedAt` if it was set (sticky for reporting).

## SLA Status Computation (For The Cron)

```ts
function computeSlaStatus(
  deadline: Date | null,
  now: Date,
  warningHours: number = DEFAULT_SLA_WARNING_HOURS,
): SlaStatus {
  if (!deadline) return "ok";
  if (now >= deadline) return "breached";
  const msUntil = deadline.getTime() - now.getTime();
  if (msUntil <= warningHours * 3600 * 1000) return "at_risk";
  return "ok";
}
```

The cron writes this back to `slaStatus` every 15-30min. Admin UI reads from the persisted column for fast filtering — never recomputes per-row.

## Breach Stickiness

Once a ticket breaches, `slaBreachedAt` is set and never cleared. If the ticket is later resolved within an extended SLA window, `slaStatus` may go back to `ok`, but `slaBreachedAt` remains for SLA-compliance reporting.

## Edge Cases

- **Ticket created at SLA boundary.** `createdAt + 24h` falls during the night → next morning the cron flags it `at_risk`. Don't try to schedule cron exactly on each deadline; periodic sweep is simpler and reliable.
- **Tier change mid-ticket.** A user upgrades while a ticket is open → keep the original deadline. Mid-ticket SLA acceleration would surprise the team. Tier changes apply to NEW tickets only.
- **Customer disabled.** If a user is deactivated/banned, mark their open tickets as `closed` with `system` reason; don't leave them counting down.
- **Org consolidation / merge.** Tickets keep their original org; don't redirect on merge or tier dynamics break.

## Terminal-State Normalization (`computeStoredSlaFields`)

Whenever `addMessage` or `updateTicket` is about to commit a transition, run the SLA fields through one normalization helper so terminal/paused states never desync from the cron's view:

```ts
function computeStoredSlaFields(
  currentBreachedAt: Date | null | undefined,
  nextStatus: SupportStatus,
  nextDeadline: Date | null,
  now: Date,
): { slaStatus, slaStatusUpdatedAt, slaBreachedAt } {
  const isTerminal       = nextStatus === "resolved" || nextStatus === "closed";
  const isPausedOnCustomer = nextStatus === "awaiting_customer";

  // Terminal: snap to ok or breached based on whether we crossed the deadline.
  // Paused: preserve existing breach record; the queue UI excludes paused
  // tickets by status, so keeping slaStatus="breached" doesn't false-alarm —
  // it just preserves "we were late" for the metrics report.
  const nextSlaStatus = isTerminal
    ? nextDeadline && now.getTime() >= nextDeadline.getTime() ? "breached" : "ok"
    : isPausedOnCustomer
      ? currentBreachedAt || (nextDeadline && now.getTime() >= nextDeadline.getTime()) ? "breached" : "ok"
      : computeSlaStatus(nextDeadline, now, DEFAULT_SLA_WARNING_HOURS);

  return {
    slaStatus: nextSlaStatus,
    slaStatusUpdatedAt: now,
    slaBreachedAt: nextSlaStatus === "breached" ? (currentBreachedAt ?? now) : null,
  };
}
```

Three properties this guarantees and the cron alone cannot:

1. **Resolved-before-deadline → `slaStatus="ok"`, `slaBreachedAt=null`.** Without this, the ticket's last cron-written value sticks even after a clean resolution.
2. **Resolved-after-deadline → `slaStatus="breached"`, `slaBreachedAt` preserved sticky.** Compliance reads the sticky timestamp; clearing it on resolve would erase the breach event.
3. **Paused-on-customer never *clears* an existing breach.** A ticket that was breached, then customer replies on `awaiting_customer`, must stay breached for reporting. The cron skips paused tickets so it can't (and shouldn't) recompute this.

## Pause-Resume Deadline Extension

When status flips from `awaiting_customer` back to `in_progress`, the deadline is extended by the duration of the pause. **Anchor the pause start to the last *support* message timestamp, not `updatedAt`** — `updatedAt` is touched by cron, normalizations, and attachment writes; the support-message timestamp is the actual moment the customer was put on the clock.

```ts
function extendDeadlineByPausedDuration(
  currentDeadline: Date | string | null,
  pauseStartedAt:  Date | string | null,  // last support message createdAt
  now: Date,
): Date | null {
  const deadline   = coerceTimestamp(currentDeadline);
  const pauseStart = coerceTimestamp(pauseStartedAt);
  if (!deadline || !pauseStart) return deadline;
  const pausedMs = Math.max(0, now.getTime() - pauseStart.getTime());
  return new Date(deadline.getTime() + pausedMs);
}
```

`Math.max(0, ...)` defends against clock skew producing a negative pause.

## Priority Change → Recompute Deadline (Gated)

When admin changes priority on a non-finished ticket, recompute `slaDeadline` from `createdAt` (the customer's wait is the customer's wait), with the *new* priority's hours. **Skip** the deadline write if either the existing or next status is `resolved`/`closed`.

```ts
const wasFinished    = existing.status === "resolved" || existing.status === "closed";
const willBeFinished = nextStatus === "resolved" || nextStatus === "closed";
if (priorityChanged && !wasFinished && !willBeFinished) {
  const { isEnterprise } = await isEnterpriseUser(existing.userId);
  nextDeadline = computeSlaDeadline(priority, isEnterprise, "firstResponse", existing.createdAt);
}
```

Recomputing from `now` would let admins game the SLA. Recomputing on a finished ticket would retroactively change compliance history.

## Cron Phase Boundary

The SLA refresh runs in two distinct functions:

- `updateSlaStatuses(thresholdHours)` — pure-DB. Scans open tickets, computes next status, writes status updates and the corresponding breach audit events **inside one transaction** so a crash between the two does not produce audit gaps.
- `sendSlaBreachAlerts(thresholdHours, _deps?)` — invokes phase 1 (DI'd for tests), enriches with org names, posts a structured severity alert through the configured provider with a hard timeout.

The `_deps?: { updateSlaStatuses }` parameter on phase 2 is the seam for testing without real DB fixtures.

## Coercing Timestamps

ORMs and database drivers may return timestamps as `Date` instances, ISO strings, numeric epochs, or nullable values depending on configuration and migration history. Wrap arithmetic with:

```ts
function coerceTimestamp(v: Date | string | null | undefined): Date | null {
  if (v == null) return null;
  if (v instanceof Date) return Number.isFinite(v.getTime()) ? v : null;
  const d = new Date(v);
  return Number.isFinite(d.getTime()) ? d : null;
}
```

Without this, `deadline.getTime()` on a string throws; the catch silently flips the user to non-enterprise (or skips the SLA flag), and weeks pass before anyone notices.

## Test Fixtures

Unit-test these specifically:

```
1. P2 individual ticket, no replies, deadline at +24h.
   At t=22h:    slaStatus = at_risk
   At t=24h:    slaStatus = breached, slaBreachedAt = 24h
   At t=24h+1h: still breached (sticky)

2. Same ticket, support replies at t=12h → awaiting_customer.
   At t=22h: slaStatus = ok (clock paused)
   Customer replies at t=30h → in_progress, deadline += 18h (the pause).
   At t=42h: slaStatus = at_risk again

3. Ticket created → resolved within 1h.
   slaDeadline cleared, slaBreachedAt null, slaStatus = ok.

4. P0 enterprise ticket, support replies.
   awaiting_customer status set, but if the customer doesn't reply,
   the cron does NOT flag it (clock paused — but project policy may
   want a separate "abandoned ticket" cron).
```
