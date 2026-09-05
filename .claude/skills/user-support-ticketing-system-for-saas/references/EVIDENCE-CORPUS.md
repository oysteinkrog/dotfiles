# Evidence Anchoring Guide

## Reference Index

- Example File Map: default-stack source map shape.
- Example Anchor Index By Pattern: how patterns map to files/functions.
- Lifecycle Test Cases: fixtures every port should preserve.
- Verification Workflow: how to create target-project anchors.
- Why This File Exists: drift and hallucination failure modes.

Use evidence anchors so an agent can verify a support-system pattern against real local code before recommending or porting it. Following the operationalizing-expertise principle: **every non-obvious rule cites an anchor**.

The paths below are an example source map from a reviewed default-stack SaaS implementation. They are not universal and may not exist in the user's repository. When operating in a target project, create the same kind of local source map in the support handoff and cite the target project's real files, tickets, commits, provider docs, or owner decisions.

## Example File Map

| Concern | Example path |
|---|---|
| Service layer (SLA, transitions, lifecycle) | `src/lib/services/support-tickets.ts` |
| Service-layer SLA tests (lifecycle conformance) | `src/lib/services/__tests__/support-ticket-sla-lifecycle.test.ts` |
| Service-layer general tests | `src/lib/services/__tests__/support-tickets.test.ts` |
| Subscription / billable seat coverage | `src/lib/services/subscription.ts` (`organizationProvidesBillableSeatCoverage`, `hasLiveStripeSubscriptionId`) |
| Email pipeline (Resend) | `src/lib/email/support.ts`, `src/lib/email/resend-client.ts`, `src/lib/email/render-transactional.ts`, `src/lib/email/tokens.ts` |
| Validation schemas (Zod) | `src/lib/validation/support.ts` (categories, summary, optional URL refinement) |
| TanStack Query hooks + runtime validators | `src/lib/query/support-tickets-hooks.ts` |
| Operations cockpit normalizer | `src/lib/admin/operations-support-sla.ts` |
| Admin reason / mutation contracts | `src/lib/admin/contracts.ts`, `src/lib/admin/mutations.ts` |
| Admin support tickets — list & PATCH | `src/app/api/admin/support/tickets/route.ts` |
| Admin support tickets — message reply | `src/app/api/admin/support/tickets/[id]/messages/route.ts` |
| Admin SLA metrics endpoint | `src/app/api/admin/support/sla-metrics/route.ts` |
| User support tickets — create + list | `src/app/api/support/tickets/route.ts` |
| User ticket detail | `src/app/api/support/tickets/[id]/route.ts` |
| User add message | `src/app/api/support/tickets/[id]/messages/route.ts` |
| Legacy contact (fallback target) | `src/app/api/support/route.ts` |
| Admin queue UI | `src/app/admin/support/tickets/page.tsx` |
| Admin SLA dashboard | `src/app/admin/support/sla/page.tsx` |
| Floating widget | `src/components/support/SupportWidget.tsx` |
| New ticket form (with fallback) | `src/components/support/NewTicketForm.tsx` |
| Ticket list (user-facing) | `src/components/support/TicketList.tsx` |
| User ticket detail page | `src/app/support/[ticketId]/page.tsx`, `.../TicketDetailClient.tsx` |
| Drizzle schema | `src/lib/db/schema.ts` |
| Coercion helpers | `src/lib/db/coerce.ts` |
| API error helpers | `src/lib/api-error.ts` |
| Cache headers helper | `src/lib/cache/headers.ts` |
| Date-range helper | `src/lib/admin/date-range.ts` |
| Routes constants | `src/lib/routes.ts` |
| Logger (pino-style) | `src/lib/logger.ts` |
| Rate limit | `src/lib/rate-limit.ts` |

## Example Anchor Index By Pattern

| Pattern (this skill) | Example anchor |
|---|---|
| `OPEN_TICKET_STATUSES` exported | `support-tickets.ts` — top-of-file `export const OPEN_TICKET_STATUSES` |
| `computeNextStatusAfterMessage` | `support-tickets.ts` — function block |
| `extendDeadlineByPausedDuration` | `support-tickets.ts` — function block |
| `computeStoredSlaFields` (terminal/paused normalization) | `support-tickets.ts` — function block |
| `scheduleSupportSideEffect` (background hook + fallback) | `support-tickets.ts` — function block |
| `verifyTicketAccess` | `support-tickets.ts` — function block |
| `isEnterpriseUser` | `support-tickets.ts` — function block (uses billable-seat coverage) |
| Priority change recomputes deadline | `support-tickets.ts` — `updateTicket` priority branch |
| Two-phase cron (`updateSlaStatuses` + `sendSlaBreachAlerts`) | `support-tickets.ts` |
| Structured severity alert payload | `support-tickets.ts` — alert-payload builder |
| Webhook/client timeout for alerts | `support-tickets.ts` — `sendSlaBreachAlerts` |
| `getSlaMetrics` (median/avg/P95 floor) | `support-tickets.ts` — function block |
| Admin route N+1 batch fetch | `src/app/api/admin/support/tickets/route.ts` — GET handler |
| `requireAdminMutation` + `mutation.context.logAction` | `src/app/api/admin/support/tickets/route.ts` — PATCH handler |
| Customer-side `Cache-Control: private` | `src/app/api/support/tickets/route.ts` — GET response |
| Unified ticket+request listing | `support-tickets.ts` — `listTicketsForUser` |
| Runtime payload validators (`is*`) | `src/lib/query/support-tickets-hooks.ts` |
| `InvalidCreateTicketResponseError` | `support-tickets-hooks.ts` |
| `CustomerUpdatableStatus = Exclude<...>` | `support-tickets-hooks.ts` |
| Form fallback to legacy `/api/support` | `src/components/support/NewTicketForm.tsx` — `submitFallbackSupportRequest` |
| Widget Escape / `useId` / `9+` clamp | `src/components/support/SupportWidget.tsx` |
| Admin queue `formatSlaStatus` (Met/Missed/Paused) | `src/app/admin/support/tickets/page.tsx` |
| Empty-count sentinel + `sanitizeCount` / `formatCount` | `src/app/admin/support/tickets/page.tsx` |
| Email `metadata` tags + footer prefs URL | `src/lib/email/support.ts` |
| Email template `kind: "request"` discriminator | `src/lib/email/support.ts` — `sendSupportRequestResponseEmail` |
| Operations cockpit normalizer (snake_case ↔ camelCase) | `src/lib/admin/operations-support-sla.ts` |

## Lifecycle Test Cases (Conformance)

The default-stack conformance suite defines three cases that should be ported as fixtures into any new implementation:

1. **"normalizes terminal tickets to ok when resolved before the deadline"** — resolved before deadline → `slaStatus = "ok"`, `slaBreachedAt = null`, `resolvedAt` set.
2. **"marks reopened tickets as breached when the deadline has already passed"** — reopen of past-deadline ticket → `slaStatus = "breached"`, `slaBreachedAt` set immediately.
3. **"recomputes stored SLA status when priority changes the deadline"** — priority p2→p0 on enterprise user → deadline tightens, `slaStatus = "at_risk"` if within warning threshold.

## Verification Workflow

When porting a pattern from this skill into a target project:

1. Locate the target project's equivalent file, route, service, provider handler, or test.
2. Read the function or block before recommending a change.
3. Port the *shape* (state-machine semantics, audit, idempotency, confirmation gate), not the project-specific bindings.
4. Translate the test fixture matrix into the target project's test runner.
5. Add a project-local citation note in the handoff or validation record so future reviewers can trace back.

```ts
// Pattern: pause-duration extension on resume from awaiting_customer.
// Local anchor: src/lib/services/support-tickets.ts
//               extendDeadlineByPausedDuration
async function resumeFromAwaitingCustomer(...) { ... }
```

## Why This File Exists

Two failure modes this prevents:

1. **Drift over time.** A pattern documented in a skill diverges from the project implementation because the implementation evolved. Anchored citations let the next agent verify the pattern is still current.
2. **Hallucinated patterns.** An agent invents a "pause-duration extension" with subtly different semantics than the code. The anchor lets the next agent diff against the actual implementation and notice the divergence.

The anchors are pointers, not claims. Verify they exist in the current target-project revision before recommending. Memory is one form of evidence; the file system and live system are more authoritative.
