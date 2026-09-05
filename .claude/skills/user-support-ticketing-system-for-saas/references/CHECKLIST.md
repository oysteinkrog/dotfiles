# Build / Review Checklist

Walk this list before opening a PR. Every item maps to a Hard Invariant or a real failure mode.

## Schema

- [ ] All four enums created: `supportCategoryEnum`, `supportStatusEnum`, `slaStatusEnum`, `ticketPriorityEnum`
- [ ] `supportTickets` has all 8 indexes (user, org, status, priority, slaDeadline, slaStatus, assignee, createdAt)
- [ ] `supportMessages` has 2 indexes (ticket, createdAt)
- [ ] FKs use `onDelete: "cascade"` so user / org deletion doesn't orphan rows
- [ ] Migration runs as one transaction; rollback tested

## Service Layer

- [ ] `OPEN_TICKET_STATUSES` is exported and the only definition
- [ ] All ticket mutations route through `src/lib/services/support-tickets.ts`
- [ ] `computeSlaStatus` and `computeNextStatusAfterMessage` have unit tests
- [ ] State-machine conformance fixtures from `STATE-MACHINE-CONFORMANCE.md` pass
- [ ] `awaiting_customer` paused-clock logic has a test
- [ ] Tier resolution happens once at create, not on every read
- [ ] Extension states, if any, map to `running`, `paused`, or `terminal`

## Admin API

- [ ] All routes use `requireAdmin` + permission key
- [ ] PATCH requires `reason`; rejects 400 without it
- [ ] PATCH writes audit log with before/after
- [ ] List endpoint batches user/org lookups (no N+1)
- [ ] List endpoint returns counts + priorityStats + approachingBreachCount
- [ ] POST messages route triggers `sendTicketResponseEmail` through a background hook / queue / outbox helper

## User API

- [ ] All routes use `requireUser`
- [ ] Rate-limit is tier-aware (paid users don't share buckets with anon)
- [ ] Customer can't read another user's ticket (404, not 403)
- [ ] Customer reply on `awaiting_customer` flips to `in_progress`
- [ ] Customer reply on `closed` is rejected

## Email

- [ ] Three lifecycle emails wired: created, response, resolved
- [ ] Each is fired from exactly one wire point (not duplicated)
- [ ] Template subject lines use short ID, not full UUID
- [ ] sendEmail handles missing user / missing email without crashing
- [ ] Resend metadata tags every send

## Admin UI

- [ ] List page is sorted by `slaDeadline ASC` (urgency first)
- [ ] Filter bar: status, priority, assignee, SLA bucket
- [ ] Count pills hydrate from API on load (not client-only state)
- [ ] Action buttons hidden if user lacks permission
- [ ] Reply modal asks for reason if also changing status

## User UI

- [ ] `SupportWidget` accessible from any page (or per-area as designed)
- [ ] `NewTicketForm` shows SLA expectation under priority selector
- [ ] `TicketList` separates open vs resolved
- [ ] Detail page translates `awaiting_customer` to "we're waiting on you"
- [ ] Reply form disabled when status = `closed`

## Cron

- [ ] `/api/cron/sla-alerts` requires `CRON_SECRET`; 403 otherwise
- [ ] Idempotent: re-running doesn't double-alert
- [ ] Internal alert webhook/provider optional (project still works without it)
- [ ] Schedule wired into `vercel.json` or equivalent
- [ ] Cron does NOT auto-resolve, auto-close, or message customers

## Security

- [ ] 3 permission keys added: `support.read`, `support.assign`, `support.resolve`
- [ ] Audit pipeline writes for every mutation
- [ ] PII not indexed in search
- [ ] Webhook signatures verified (Resend, etc.)
- [ ] No `support@` exposure in client bundle / source maps
- [ ] Threat model from `SUPPORT-SYSTEM-THREAT-MODEL.md` reviewed and stored with the implementation notes or handoff artifacts
- [ ] Customer ticket text is treated as untrusted input in AI assist, search snippets, logs, and admin UI rendering
- [ ] External side effects that can retry (email, refunds, webhooks, cron alerts) have idempotency keys or provider ids

## Tests

- [ ] All wire points covered (see TEST-PLAN.md)
- [ ] No mocked DB / Resend in integration tests
- [ ] E2E: user creates → admin sees → admin replies → user sees email arrives
- [ ] CI runs the full suite before merge
- [ ] Validation gates from `VALIDATION-GATES.md` have pass/fail/blocked evidence, not just a prose claim

## Deploy

- [ ] All env vars documented in `.env.example` (names only, never values)
- [ ] Owner has set `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `RESEND_FROM_NAME`, `CRON_SECRET`
- [ ] Domain verified in Resend before first send
- [ ] First test send to a Gmail address arrives, not in spam
- [ ] Production smoke test: file ticket → email arrives → admin reply → reply email arrives

## Documentation

- [ ] `AGENTS.md` blurb added explaining the support system
- [ ] Permission registry doc updated
- [ ] `/admin/support/tickets` linked from admin nav
- [ ] Triage skill (`user-support-triage-for-saas-and-open-source-projects`) onboards cleanly against the new system

## Triage Handoff

- [ ] `<project>/.claude/support-triage/_detection.json` includes `saas-custom`
- [ ] `<project>/.claude/support-triage/00-intake.md` declares mode, support owners, audience segments, source anchors, and policy gaps
- [ ] `02-channels.md` documents user/admin routes, support email behavior, and any secondary channels
- [ ] `05-policies.md` includes owner-approved SLA/refund/escalation/security/privacy decisions
- [ ] `08-voice.md` exists, or explicitly says no historical samples exist yet
- [ ] `12-gap-dispositions.md` lists manual-only, blocked-by-access, provider-gap, policy-gap, evidence-gap, deferred, and unknown items as applicable
- [ ] `handoffs/support-handoff.json` follows `HANDOFF-ARTIFACT-CONTRACT.md`
- [ ] `adapter-capabilities.json` marks customer-visible sends, refunds, account locks, privacy actions, and public incident updates as unsafe/approval-required
- [ ] `scripts/list-open.sh` returns `support-adapter-v1` JSON with id, subject, status, priority, SLA, age, customer, evidence, and safe/unsafe actions
- [ ] Triage skill's `scripts/validate-adapter-output.py` passes against `scripts/list-open.sh` output
- [ ] Triage skill's `scripts/validate-support-map.py` passes against `<project>/.claude/support-triage`
- [ ] `scripts/post-reply.sh` either implements the approved-send path or exits with a clear manual-send message
- [ ] At least one routine fire drill and one high-risk fire drill produce a no-send draft bundle

## Portability

- [ ] Framework-specific implementation choices are separated from universal invariants
- [ ] Support archetype(s) declared: SaaS, OSS-hybrid, marketplace/ecommerce, mobile app, community, internal tool, regulated, agency/client, or other with evidence keys
- [ ] Provider failures never mark customer-visible messages as sent
- [ ] Email/observability/AI providers record enough ids for audit and debugging
- [ ] AI suggestions record accepted/edited/rejected outcomes when AI assist is enabled
- [ ] Non-Next.js ports document service layer, migration, route/controller, auth, cron, and test equivalents

## Production Workmanship (from IMPLEMENTATION-PATTERNS.md)

- [ ] `OPEN_TICKET_STATUSES` exported from service layer and re-imported in admin / cron / metrics (no inline arrays)
- [ ] `computeStoredSlaFields` runs inside `addMessage` and `updateTicket` (not cron-only) so terminal/paused states never desync
- [ ] Pause-resume deadline extension anchors to **last support message** timestamp, not `updatedAt`
- [ ] Priority change on a non-finished ticket recomputes deadline from `createdAt` (not `now`); skipped on terminal status
- [ ] Reopening a ticket with a past deadline immediately sets `slaStatus = "breached"` + `slaBreachedAt` (no waiting for cron)
- [ ] Email/alert side effects scheduled via background hook / queue / outbox (or framework equivalent) with fallback for tests/cron/CLI
- [ ] Admin list endpoint batch-fetches users + orgs via `inArray` (no N+1; Map lookup, never `.find`)
- [ ] Admin mutations require `reason` (≥ 8 chars), reject no-op updates, write `beforeState` / `afterState` / `changedFields` audit
- [ ] Customer ticket access gated by `verifyTicketAccess` + `organizationProvidesBillableSeatCoverage` (real Stripe/PayPal id, never `sub_test_*`)
- [ ] `CustomerUpdatableStatus = Exclude<TicketStatus, "awaiting_customer">` enforced in TS *and* server-side Zod
- [ ] User-side responses ship `Cache-Control: private` (never `public`)
- [ ] Unified user-side listing merges `supportTickets` + `supportRequests` with a `kind` discriminator
- [ ] Cron is two-phase: `updateSlaStatuses` (DB+audit txn) → `sendSlaBreachAlerts` (DI'd for tests)
- [ ] Outbound webhook calls use `AbortSignal.timeout(10_000)` (or equivalent)
- [ ] System-attributed audit events use `userId: null` — never the customer
- [ ] SLA-status updates and breach audit inserts wrapped in a single DB transaction
- [ ] Internal alert payload sectioned by severity (BREACHED → P0 → P1 → P2/P3 summary)
- [ ] Admin queue `formatSlaStatus` reads persisted `slaStatus` (Met / Missed / Paused) — never recomputes
- [ ] Empty-state count sentinel is `null` + `formatCount` renders `—` (never `0` for unknown)
- [ ] Mutation `onSuccess` invalidates adjacent cockpits (operations summary, command-center)
- [ ] Email metadata tags `{ type, ticketId, userId }` present on every send; footer uses tokenized signed preference URL
- [ ] `getSlaMetrics` enforces P95 floor at n ≥ 20 resolved in window
- [ ] Customer-visible numbers rounded: 1 decimal for hours, 2 decimals for percent
- [ ] Every external side effect (refund, webhook, AI tool, provider sync) records an idempotency key
- [ ] Ticket text never authoritative for AI tool calls; permission check runs *after* AI step
- [ ] Floating widget: `Escape` dismiss, `useId()` + `aria-controls`, open-count badge clamps at "9+"
- [ ] New ticket form falls back to legacy `/api/support` on non-shape errors and surfaces a Reference ID
- [ ] New ticket form surfaces SLA expectation post-create ("Expected response by ...")

## Mode And Validation Gates

- [ ] Mode declared from `ROUTER-AND-COMPLEXITY-MODES.md`: minimal, standard, enterprise, regulated, migration, OSS-hybrid, internal tool, marketplace/ecommerce, mobile app, community, or agency/client
- [ ] "Do not build yet" branches checked before implementation
- [ ] G0 prerequisite doctor status recorded
- [ ] G1 mode/policy status recorded
- [ ] G2 schema/state-machine status recorded
- [ ] G3 service-layer invariant status recorded
- [ ] G4 API/security status recorded
- [ ] G5 email/side-effect status recorded
- [ ] G6 UI workflow status recorded
- [ ] G7 cron/observability status recorded
- [ ] G8 handoff adapter status recorded
- [ ] G9 fire-drill status recorded
- [ ] G10 production smoke status recorded or explicitly deferred with owner
- [ ] G11 accretive-loop status recorded, including product/docs/ops owner or explicit not-in-scope decision
