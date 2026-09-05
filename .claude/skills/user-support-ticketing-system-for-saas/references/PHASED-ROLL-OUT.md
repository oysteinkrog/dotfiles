# Phased Rollout

8 phases, each shippable independently. Each gate has acceptance criteria; don't move on until they're green.

## Phase 0 — Policy + Surface Decisions (Before Code)

**Scope:** Decide what the system is allowed to do, who can approve risky actions, and how triage agents will operate it.

- [ ] Refund policy, escalation paths, security disclosure owner, hostile-user handling, and privacy retention captured from [POLICIES-PER-CATEGORY.md](POLICIES-PER-CATEGORY.md)
- [ ] Support channels chosen: in-app widget, email, GitHub issues, Discord/Slack, third-party migration cutover
- [ ] SLA tier defaults approved by owner
- [ ] Outbound voice source identified (5+ historical replies, or "no samples yet")
- [ ] Handoff target chosen: `<project>/.claude/support-triage/`

**Gate:** Owner signs off on the policy decisions; no schema work starts from guessed refund/SLA/security behavior.

## Phase 1 — Foundation (Day 1–2)

**Scope:** Schema + service layer + permission keys + audit hook.

- [ ] Drizzle schema + migration applied (locally + staging)
- [ ] `support-tickets.ts` exposes: `createTicket`, `addMessage`, `updateTicket`, `listAllTickets`, `getTicketsApproachingSla`, `getTicketsBreachedSla`
- [ ] Unit tests on `computeSlaStatus`, `computeNextStatusAfterMessage`, deadline math
- [ ] Permission keys added to registry (no UI yet)
- [ ] `OPEN_TICKET_STATUSES` exported from one place

**Gate:** `bun test src/lib/services/support-tickets.test.ts` green.

## Phase 2 — User Path (Day 3)

**Scope:** Create-ticket route + SupportWidget + confirmation email.

- [ ] `POST /api/support/tickets` accepts valid input, persists, emails user
- [ ] `SupportWidget` opens, submits, shows shortId in confirmation
- [ ] User receives confirmation email with the ticket link
- [ ] Rate-limit tier-aware (paid users distinct buckets)

**Gate:** E2E: a free user creates a ticket and gets the email in < 30s. A paid user does the same and is not throttled by anon limits.

## Phase 3 — Admin Path (Day 4–5)

**Scope:** Admin GET/PATCH + admin UI + audit log.

- [ ] `GET /api/admin/support/tickets` with filters + counts + priorityStats
- [ ] `PATCH /api/admin/support/tickets` with `reason` requirement + audit
- [ ] Admin page renders the list, sorted by `slaDeadline ASC`
- [ ] Filter bar works for status/priority/assignee/SLA
- [ ] Permission gating hides actions per role

**Gate:** Admin can change a ticket from `open` → `acknowledged` with a reason, and the audit row exists.

## Phase 4 — Threading (Day 6)

**Scope:** Messages API + admin reply emails customer + customer reply resumes SLA.

- [ ] `GET /api/admin/support/tickets/[id]/messages`
- [ ] `POST /api/admin/support/tickets/[id]/messages` triggers `sendTicketResponseEmail`
- [ ] User-side `POST /api/support/tickets/[id]/messages` flips `awaiting_customer` → `in_progress`
- [ ] Closed tickets reject reply

**Gate:** Admin replies; customer's email arrives; customer replies in-app; status flips correctly.

## Phase 5 — SLA Cron (Day 7)

**Scope:** /api/cron/sla-alerts + slaStatus persistence + Slack webhook (optional).

- [ ] Cron route accepts `CRON_SECRET`, returns 403 without
- [ ] At-risk + breach detection wires
- [ ] Idempotency tested (run twice, no double-fire)
- [ ] Vercel Cron schedule configured
- [ ] Slack webhook posts when present (silent if not)

**Gate:** Force a ticket past its deadline; cron flips slaStatus, posts Slack ping, doesn't double-post on next run.

## Phase 6 — Enterprise Tier (Optional, Day 8)

**Scope:** Per-org SLA overrides for enterprise customers.

- [ ] `slaOverride` column on `organizations`
- [ ] Service-layer reads override before falling back to tier defaults
- [ ] Admin UI shows ENTERPRISE badge + custom-SLA tag
- [ ] SLA-compliance report query for org-level reporting

**Gate:** An enterprise org's tickets get tighter deadlines; reporting query produces a compliance summary.

## Phase 7 — Hardening (Day 9–10)

**Scope:** Tests, audit, security review, smoke tests.

- [ ] All TEST-PLAN.md cases green
- [ ] Rate-limit tier-aware in production
- [ ] Audit on every privileged mutation
- [ ] Webhook signatures verified
- [ ] Production smoke test passes (file → email → reply → resolved)
- [ ] AGENTS.md / docs blurb added
- [ ] Triage skill (companion) onboards cleanly against the new system
- [ ] `<project>/.claude/support-triage/scripts/list-open.sh` returns open tickets and SLA fields

**Gate:** All Hard Invariants in [CHECKLIST.md](CHECKLIST.md) pass. PR can merge to main.

## Don't Skip Phases

Tempting shortcuts:
- "Skip the audit log; it's just for compliance" → comes back to bite you in 6 months when an action mystery surfaces
- "Skip Phase 5; we'll add SLA later" → operators don't know what to triage; queues drift
- "Skip user UI; admin can create tickets manually" → you've built half a system; the rest never lands

Each phase shipped solo is value. The full set is the product.

## Migrating Off A Third-Party Tool

If migrating off Zendesk / Intercom / etc, add a Phase 0:

- [ ] Export ticket history from the legacy tool
- [ ] Decide what to migrate (open tickets only? last 90 days? all history?)
- [ ] Map fields to your schema (their categories → yours, etc)
- [ ] Run a one-shot import script; mark migrated tickets with `source = "imported_zendesk"`
- [ ] Cutover plan: dual-running for a week, then redirect inbound to the new system

The triage skill's SAAS-THIRD-PARTY.md has provider-specific export notes.
