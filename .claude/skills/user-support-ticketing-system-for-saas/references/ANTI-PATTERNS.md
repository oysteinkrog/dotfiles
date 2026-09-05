# Anti-Patterns (Build-Side, With Case Notes)

These are real bugs the JSM build went through. Each maps to a Hard Invariant violation.

## 1. Direct Table Writes From Handlers

**Symptom:** Status transition logic copied into 3 different routes; over time the copies drift. New `awaiting_customer` rule lands in one route, not the others.

**Fix:** All mutations through `service/support-tickets.ts:updateTicket(...)`. Handlers are thin: validate → call service → format response.

## 2. Reopen-On-Reply For Closed Tickets

**Symptom:** A user replies to a year-old closed ticket asking an unrelated question; it reopens, looks like an SLA breach immediately, ops scrambles.

**Fix:** `computeNextStatusAfterMessage` returns `null` for `closed` and (per project policy) `resolved`. Customer reply on closed gets a polite "this ticket is closed; please open a new one" instead of mutating it.

## 3. SLA Clock Running During `awaiting_customer`

**Symptom:** Cron pages the team about a "breach" while the ticket is genuinely waiting on the customer to respond. Confidence in alerts erodes.

**Fix:** `OPEN_TICKET_STATUSES` excludes `awaiting_customer`. Every SLA query filters by it, including the cron's `getTicketsBreachedSla()`.

## 4. Admin Notes Without Customer Email

**Symptom:** `support_requests` had an `adminNotes` field. Admin filled it in to resolve; user was never told. User opens a duplicate ticket a week later asking what happened.

**Fix:** PATCH on `support_requests` calls `sendSupportRequestResponseEmail`. Integration test asserts the email is sent. **This was the worst trust hit on JSM history.**

## 5. Cron Auto-Resolving "Old" Tickets

**Symptom:** A team adds a "close after 30 days no activity" rule. It silently closes a P0 the customer was about to escalate.

**Fix:** Cron flags only. Closing requires a human.

## 6. Permission Keys Mixed With Inline Role Checks

**Symptom:** `if (user.role === "admin")` scattered through 14 files. New role tier ("support_agent") is added; rolling it out is a multi-day audit because every check is a separate edit.

**Fix:** Single permission registry. `requireAdminPermission("support.assign")`. New role just needs the key list updated centrally.

## 7. Ad-Hoc Rate-Limit Tiers Per Route

**Symptom:** `/api/support/tickets` has its own limit, `/api/support/tickets/[id]/messages` has another, neither tier-aware. Paid users hit caps the team didn't realize they had.

**Fix:** One `enforceRateLimit(req, user)` helper. Tiers resolved consistently. Per-route limits are tunable but go through the same path.

## 8. `customerId` As Ticket Join Key

**Symptom:** A team uses `customerId` (a Stripe-format `cus_...` field) as the ticket's user reference. When a user switches from Stripe to PayPal mid-relationship, all their tickets become un-findable.

**Fix:** Tickets reference `users.id` (UUID). Payment provider IDs are subscription concerns, not support concerns.

## 9. Synchronous `sendEmail` In The Request Path

**Symptom:** Resend is degraded; ticket-create requests time out at 10s because the response is blocked on the email send.

**Fix:** Use `next/server`'s `after()` to enqueue the email. The HTTP response returns immediately; the email fires after.

## 10. Adding Columns For Every Priority Subtype

**Symptom:** Someone proposes `severity`, `urgency`, `customer_impact` on top of `priority`. Now there are 4 ways to express "how bad is this", and they conflict.

**Fix:** Resist. The 4-level enum (P0/P1/P2/P3) is enough. If you need product-area routing, add `category` not new priority dimensions.

## 11. `slaBreachedAt` Cleared On Resolve

**Symptom:** SLA-compliance reporting shows 0 breaches because resolved tickets clear the breach timestamp. Quarterly numbers look great, ops knows it's wrong.

**Fix:** `slaBreachedAt` is sticky. Set on first breach; never cleared. `slaStatus` may go back to `ok` on resolve, but `slaBreachedAt` retains the historical fact.

## 12. Duplicate `OPEN_TICKET_STATUSES` Definitions

**Symptom:** One file says `["open", "acknowledged", "in_progress"]`; another adds `awaiting_customer` for "the SLA list". Reports diverge by which file is being imported.

**Fix:** Export it once from the service. Every consumer imports the same constant. Lint rule (or grep check in CI) flags any new local definition.

## 13. UI Hydration From Client State Only

**Symptom:** Admin counts cards show `0 / 0 / 0` for a few seconds on every page load while WebSocket connects. Operators think the queue is empty and close their tabs.

**Fix:** Hydrate from REST on mount; treat WebSocket as a *supplement* for live updates, never the primary data source. (Ref: admin-page-for-nextjs-sites.)

## 14. Cron Secret Header Mismatch

**Symptom:** Cron deploys, runs every 15min, returns 403 silently because Vercel sends the secret under `x-vercel-cron-secret`, not `x-cron-secret`. SLAs go untracked for weeks.

**Fix:** Wire a smoke test that pings the cron endpoint at deploy time and asserts non-403. Fail the deploy if it 403s.
