---
name: user-support-ticketing-system-for-saas
description: >-
  Build production-grade support ticketing: schema, SLA engine, APIs, queues,
  admin/user UI, email, cron. Use when adding tickets or SLA tracking.
---

# User Support Ticketing System

## Table of Contents

- [Quick Start (Cold-Start Agent, Read This First)](#quick-start-cold-start-agent-read-this-first)
- [Use When](#use-when)
- [When NOT to Use This Skill](#when-not-to-use-this-skill)
- [The Exact Prompts](#the-exact-prompts)
- [Hard Invariants](#hard-invariants)
- [Architecture (One-Page)](#architecture-one-page)
- [Schema (Drizzle Sketch — Adapt To Project Naming)](#schema-drizzle-sketch--adapt-to-project-naming)
- [SLA Tiers (Defaults — Override Per Project)](#sla-tiers-defaults--override-per-project)
- [Phased Rollout](#phased-rollout)
- [Policy And Handoff Contract](#policy-and-handoff-contract)
- [Deliverables](#deliverables)
- [Anti-Patterns](#anti-patterns)
- [Companion Skills](#companion-skills)
- [References](#references)
- [Scripts](#scripts)
- [Self-Test](#self-test)

## Quick Start (Cold-Start Agent, Read This First)

If you've just been asked to "build a support ticketing system" or "expand `/admin/support`" in a SaaS app, product, internal tool, community, or marketplace, run the picker below first - picking the wrong starting prompt wastes a phase or two of work. The default examples are Next.js + Drizzle + Resend; the invariant set is portable.

| Signal in the request | Run |
|---|---|
| Greenfield ticketing on top of a clean app close to the default Next.js + Drizzle shape | [Exact Prompt 1](#1-build-from-scratch) |
| Existing tables / partial admin queue / "are we missing anything?" | [Exact Prompt 2](#2-expand-an-existing-system) — uses [`AUDIT-PROMPT.md`](references/AUDIT-PROMPT.md) |
| Shipped basic SLAs, now need 4hr-response enterprise tier | [Exact Prompt 3](#3-add-enterprise-tier-slas) — uses [`ENTERPRISE-TIER.md`](references/ENTERPRISE-TIER.md) |
| Non-SaaS, internal, marketplace, mobile-app, community, agency/client-service, or regulated support | [Exact Prompt 4](#4-design-for-a-non-default-support-archetype) — uses [`ROUTER-AND-COMPLEXITY-MODES.md`](references/ROUTER-AND-COMPLEXITY-MODES.md) |
| Migrating off Zendesk / Intercom / Help Scout / Freshdesk / Plain / Linear / JSM / HubSpot Service Hub / Salesforce Service Cloud / Front / Gorgias / Zoho Desk | Run Prompt 1 first, then [`MIGRATION-PER-PROVIDER.md`](references/MIGRATION-PER-PROVIDER.md) (12 providers covered) |
| Unsure how much system to build, or nonstandard business/support model | Start with [`ROUTER-AND-COMPLEXITY-MODES.md`](references/ROUTER-AND-COMPLEXITY-MODES.md) |
| Money/access/privacy/security/legal/customer-visible side effects are in scope | Run [`SUPPORT-SYSTEM-THREAT-MODEL.md`](references/SUPPORT-SYSTEM-THREAT-MODEL.md) before implementation |
| Screenshots/log uploads, hostile inbound, bulk actions, multiple support teams, or linked tickets are in scope | Add the relevant hardening module before launch: attachments, abuse, saved replies/macros, multi-team routing, and ticket relationships |
| Support should feed roadmap, docs, retention, or product quality | Add support-intelligence fields plus journey reconstruction, cost-of-support, customer satisfaction, proactive support, and the triage VoC loop |
| Unsure where to start | Open [`PHASED-ROLL-OUT.md`](references/PHASED-ROLL-OUT.md), pick the lowest unmet phase, run Prompt 1 scoped to that phase |

Cold-start sanity check before writing any code — run [`scripts/doctor.sh`](scripts/doctor.sh):

```bash
./scripts/doctor.sh                 # human-readable; exits 0 only when prerequisites are green
./scripts/doctor.sh --json | jq .   # machine-readable for piping into a planner
./scripts/doctor.sh --portable      # non-default stacks: validates project root, reports default-stack gaps as routing hints
```

**Bootstrap the companion skills before doctor runs.** This skill calls into `/de-slopify` (Hard Invariant: every customer-visible reply must run through it) and several other companion skills. The bootstrap inventories what's installed and installs missing ones via `jsm`:

```bash
./scripts/check-companion-skills.sh                # non-mutating inventory; writes skill_inventory.json
./scripts/install-companion-skills.sh              # jsm install <name> for each missing companion
```

`/de-slopify` is **required** — if it can't be installed, do not proceed; the Hard Invariant cannot be met without it. All other companions are optional with degradation paths. Full guide (jsm install, login flow, headless, subscription, search paths): [SKILL-INSTALLATION.md](references/SKILL-INSTALLATION.md).

The doctor wraps the default-stack checks (Drizzle config / service layer / admin API tree / Resend SDK + key) plus an "is `support-tickets.ts` already there?" hint that decides between Prompt 1 (build) and Prompt 2 (audit/expand). Use default mode when the host project is meant to be close to the Next.js/Drizzle/Resend path. Use `--portable` when the project has another stack or support archetype; in that mode, default-stack gaps become routing hints instead of hard blockers. If default-mode checks fail because the project is still missing basic SaaS plumbing, fix the host project first. If the project uses a different stack, use [FRAMEWORK-PORTABILITY.md](references/FRAMEWORK-PORTABILITY.md) plus [PROVIDER-PORTABILITY.md](references/PROVIDER-PORTABILITY.md) instead of forcing Next.js / Drizzle / Resend names into the codebase. The companion `/supabase`, `/vercel`, and `/admin-page-for-nextjs-sites` skills cover the default path.

Before schema work, run the policy preflight in [POLICIES-PER-CATEGORY.md](references/POLICIES-PER-CATEGORY.md): SLA tier defaults, refund authority, security disclosure owner, hostile-user escalation, privacy retention, and support-channel scope. The database model should encode policy decisions, not guess them after launch.

Before implementation planning, declare the mode from
[ROUTER-AND-COMPLEXITY-MODES.md](references/ROUTER-AND-COMPLEXITY-MODES.md)
and record the high-risk boundaries from
[SUPPORT-SYSTEM-THREAT-MODEL.md](references/SUPPORT-SYSTEM-THREAT-MODEL.md).
The goal is to avoid building the default Next.js support queue when the project
actually needs a minimal contact replacement, a regulated audit trail, an
enterprise escalation lane, or a provider migration.

For non-Next.js projects, keep the invariant set and port the implementation
shape using [FRAMEWORK-PORTABILITY.md](references/FRAMEWORK-PORTABILITY.md).
For provider swaps, use [PROVIDER-PORTABILITY.md](references/PROVIDER-PORTABILITY.md).

For the **38 hard-won implementation patterns** that distinguish a
production-grade ticketing system from a tutorial — pause-duration anchoring,
terminal-state SLA normalization, billable-seat access gates, two-phase cron,
batch-fetch enrichment, runtime payload validators, form fallback to legacy
contact, and 31 others — see
[IMPLEMENTATION-PATTERNS.md](references/IMPLEMENTATION-PATTERNS.md). For the
same patterns operationalized into trigger / action / why / failure-mode
**operator cards** that an agent can match against a situation and fire, see
[OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md). For the **SLA metrics
report contract** (`getSlaMetrics`, percentile sample-size floors, period
bounds, trend reports), see
[METRICS-AND-REPORTING.md](references/METRICS-AND-REPORTING.md). For
**forward-looking innovations** unlocked by the foundation (refund autopilot,
auto-brief, customer-facing live SLA, ticket-driven product insights, plus
eleven more), see [CREATIVITY-AND-INNOVATION.md](references/CREATIVITY-AND-INNOVATION.md).
When the project needs a richer cockpit, layer in the modular references rather
than bloating the first implementation pass: [ATTACHMENTS-AND-FILE-UPLOAD.md](references/ATTACHMENTS-AND-FILE-UPLOAD.md),
[SAVED-REPLIES-MACROS-BULK.md](references/SAVED-REPLIES-MACROS-BULK.md),
[TICKET-LINKING-AND-RELATIONSHIPS.md](references/TICKET-LINKING-AND-RELATIONSHIPS.md),
[MULTI-TEAM-ROUTING.md](references/MULTI-TEAM-ROUTING.md), and
[SPAM-ABUSE-HOSTILE-USERS.md](references/SPAM-ABUSE-HOSTILE-USERS.md). Those
modules are not optional when their threat surface exists; they are staged
extensions of the same invariants.
For global, incident-heavy, AI-assisted, or high-volume teams, add the matching
advanced modules before launch: [INTERNATIONALIZATION-AND-LOCALIZATION.md](references/INTERNATIONALIZATION-AND-LOCALIZATION.md),
[STATUS-PAGE-INTEGRATION.md](references/STATUS-PAGE-INTEGRATION.md),
[WAR-ROOM-INCIDENT-MODE.md](references/WAR-ROOM-INCIDENT-MODE.md), and
[ADVANCED-AI-FEATURES.md](references/ADVANCED-AI-FEATURES.md).
For support systems that should become accretive product intelligence instead
of just a queue, also wire the VoC fields from the triage skill's
[VOICE-OF-CUSTOMER-LOOP.md](../user-support-triage-for-saas-and-open-source-projects/references/VOICE-OF-CUSTOMER-LOOP.md):
theme tags, persona/register tags, source stream, keeper consent, and loopback
state. These can be columns, JSON fields, or analytics events; the invariant is
that future triage agents can export them without rereading every thread.

## Use When
- Building a brand-new support ticketing system into a SaaS app or product with recurring user support.
- A SaaS, marketplace, mobile app, internal tool, community, or agency/client-service project has a contact form but no SLA / threading / status / admin queue.
- The triage skill (`/user-support-triage-for-saas-and-open-source-projects`) detected `surfaces: ["none-yet"]` and the owner wants to roll their own (vs Zendesk/Intercom).
- Migrating off a third-party ticketing tool back to in-app.

This skill is the **build** counterpart to the triage skill. Once installed, the triage skill onboards against the new system in minutes because the adapter, handoff, policy, and validation contracts are shared.

## When NOT to Use This Skill

Pick the right tool — building when you should be triaging (or vice versa) wastes hours.

| Symptom | Use this skill instead |
|---|---|
| Tickets already exist; you want to *handle the queue right now* | `/user-support-triage-for-saas-and-open-source-projects` |
| Customer support runs on GitHub Issues only (OSS project) | `/gh-triage-ru` + triage skill's `GITHUB-FORK.md` |
| You need to polish an admin reply for tone before sending | `/de-slopify` (this skill wires `/de-slopify` in; doesn't replace it) |
| Building any non-support admin surface (users, billing, content moderation) | `/admin-page-for-nextjs-sites` |
| Stripe/PayPal subscription wiring (so `tier` resolution works) | `/stripe-checkout` first, then this skill |
| Supabase / Drizzle pooler / RLS setup not done yet | `/supabase` first |
| Final integration tests on real DB (no mocks) | `/testing-real-service-e2e-no-mocks` |
| Pre-launch security sweep on the new admin surface | `/security-audit-for-saas` |
| You want a knowledge-base only (no tickets) | `KNOWLEDGE-BASE.md` here is the wire-up; the *content* belongs in your docs site (`/documentation-website-for-software-project`) |

## THE EXACT PROMPTS

### 1) Build From Scratch
<a id="1-build-from-scratch"></a>
```text
Design and implement an in-app support ticketing system for this SaaS app.
Use the default Next.js / Drizzle / Resend shapes only where they match the host
project; otherwise port the same invariants through FRAMEWORK-PORTABILITY.md and
PROVIDER-PORTABILITY.md. Match the Hard Invariants in this skill. Output:

1. Drizzle schema additions or equivalent migrations (support_tickets, support_messages, support_requests
   if needed, supportCategoryEnum, supportStatusEnum, slaStatusEnum,
   ticketPriorityEnum) — with indexes
2. Service layer at src/lib/services/support-tickets.ts — SLA computation,
   status transitions (awaiting_customer pause/resume), createTicket,
   addMessage, listAllTickets, updateTicket, getTicketsApproachingSla,
   getTicketsBreachedSla
3. Admin REST API:
   - GET    /api/admin/support/tickets               (list + filters + counts)
   - PATCH  /api/admin/support/tickets               (status/priority/assignee
                                                      + reason + audit)
   - GET    /api/admin/support/tickets/[id]/messages
   - POST   /api/admin/support/tickets/[id]/messages (triggers customer email)
   - POST   /api/admin/support/tickets/[id]/notes    (internal-only; no email)
   - GET    /api/admin/support/sla-metrics
4. User-facing API:
   - POST   /api/support/tickets             (create)
   - GET    /api/support/tickets             (mine)
   - GET    /api/support/tickets/[id]        (detail)
   - POST   /api/support/tickets/[id]/messages
5. Admin UI at src/app/admin/support/tickets/page.tsx — TanStack Query, filter
   bar (status/priority/assignee/SLA-bucket), count pills, action queue
6. User UI: SupportWidget + NewTicketForm + TicketList components
7. Email pipeline (src/lib/email/support.ts or project equivalent):
   sendTicketCreatedEmail, sendTicketResponseEmail, sendTicketResolvedEmail.
   Resend is the default provider; keep the provider boundary swappable.
8. Cron at /api/cron/sla-alerts (every 15-30 min) — flags at_risk and
   breached, posts internal-note alert (webhook/provider optional)
9. Permission keys (support.read, support.assign, support.resolve), audit
   pipeline integration, rate-limit tier-aware on user routes
10. Integration tests for: ticket creation triggers email, status transitions
    pause/resume SLA, breach cron flips slaStatus, admin reply emails customer
11. Handoff artifacts for `/user-support-triage-for-saas-and-open-source-projects`:
    detection output, 02-channels.md, 05-policies.md, 08-voice.md, and a
    working `.claude/support-triage/scripts/list-open.sh`
12. State-machine conformance fixtures from
    `references/STATE-MACHINE-CONFORMANCE.md` pass against the service layer
13. `.claude/support-triage/scripts/list-open.sh` returns `support-adapter-v1`
    JSON that passes the triage skill's `validate-adapter-output.py`
14. Threat model and validation record: support boundaries, dangerous side
    effects, idempotency points, and gates from `references/VALIDATION-GATES.md`
15. Machine-readable handoff from `references/HANDOFF-ARTIFACT-CONTRACT.md`
    including route map, permission keys, env var names, adapter scripts, known
    gaps, and owner-approval-required actions
16. Support-intelligence fields/events for theme tags, persona/register,
    customer effort, compensation band/approval, keeper verbatims, and
    loopback-needed/sent state, so the triage skill can run its VoC loop later
17. If attachments are in scope: two-step signed upload, scanner/quarantine,
    per-request signed reads, retention policy, forged-key tests, and EXIF
    stripping from `references/ATTACHMENTS-AND-FILE-UPLOAD.md`
18. If queues are shared across teams or high volume: saved replies/macros,
    bulk action safety, ticket relationships, multi-team routing, and
    spam/abuse protections from the hardening references
19. If support is meant to improve product strategy: customer journey
    reconstruction, cost-of-support, customer satisfaction, proactive support,
    and VoC fields are queryable and included in handoff/export
```

### 2) Expand An Existing System
<a id="2-expand-an-existing-system"></a>
Use `references/AUDIT-PROMPT.md` — checks each Hard Invariant and lists gaps.

### 3) Add Enterprise-Tier SLAs
<a id="3-add-enterprise-tier-slas"></a>
Use `references/ENTERPRISE-TIER.md` — adds 4hr first-response config and per-org overrides.

### 4) Design For A Non-Default Support Archetype
<a id="4-design-for-a-non-default-support-archetype"></a>
```text
Design the smallest production-grade support system for this project's actual
support archetype. Start from ROUTER-AND-COMPLEXITY-MODES.md and do not force
the default Next.js / Drizzle / Resend shape unless it matches the host project.

Output:

1. Mode declaration naming support archetype(s), requester identity source,
   public/private boundary, policy owners, and side effects needing approval
2. Equivalent service boundary, state machine, audit log, permission vocabulary,
   notification provider, scheduler/job runner, and adapter script for the host
   stack
3. Minimal ticket/request/message model that preserves the Hard Invariants
   without overbuilding enterprise features the archetype does not need
4. Channel-specific proof plan: app-store/marketplace ids, community thread
   public/private rules, internal employee identity, client contract/SOW, or
   regulated evidence pack as applicable
5. Handoff artifacts for the triage skill, including support-handoff.json,
   adapter-capabilities.json, list-open.sh, and validation-gate record
```

## Hard Invariants

These are non-negotiable. Each is wired to a real failure mode — see [ANTI-PATTERNS.md](references/ANTI-PATTERNS.md).

### Universal Implementation Kernel

For any stack or archetype, first map these seven things before writing routes
or UI:

| Kernel piece | Question it answers | Default-stack example |
|---|---|---|
| Request record | What is the durable unit of support work? | `supportTickets` |
| Conversation record | What is customer-visible vs internal-only text? | `supportMessages` + internal notes |
| State machine | Which statuses are legal, terminal, paused, or active? | `STATE-MACHINE-CONFORMANCE.md` |
| Side-effect boundary | What can email, refund, lock, publish, or notify? | service-layer send/outbox helpers |
| Permission/audit boundary | Who can mutate support state and why? | `support.read/assign/resolve` + audit log |
| Evidence/export boundary | How can triage prove what happened later? | adapter + handoff artifacts |
| Improvement loop | How does support evidence improve docs/product/ops? | VoC fields, KB suggestions, cost metrics |

If a proposed design cannot answer those seven questions, it is not ready for
code even if the schema looks plausible.

- **One service layer.** All ticket mutations route through `src/lib/services/support-tickets.ts`. No direct table writes from API handlers.
- **One SLA engine.** `computeSlaStatus` lives in the service layer; admin UI / cron / email all consume the same fields (`slaStatus`, `slaDeadline`, `slaBreachedAt`).
- **Status transitions are computed, not free-form.** Customer reply on `awaiting_customer` → `in_progress`. Support reply on active ticket → `awaiting_customer` (pauses SLA). Terminal states (`resolved` / `closed`) reject reopen via reply.
- **State machine is canonical and tested.** The transition table in [STATE-MACHINE-CONFORMANCE.md](references/STATE-MACHINE-CONFORMANCE.md) is the portable source of truth; Drizzle/Next.js code is one implementation, not a second policy.
- **`OPEN_TICKET_STATUSES` is exported and shared.** Every "is the SLA clock running?" check imports the same set. `awaiting_customer` is intentionally excluded (clock paused).
- **Permission keys, never inline checks.** `support.read`, `support.assign`, `support.resolve` are the only authorization surface. `requireAdminPermission(...)` at every privileged route.
- **Reason + audit on every mutation.** All admin status/priority/assignee changes carry a `reason` string and write to `auditLog` via the shared mutation helper.
- **Outbound email on every reply.** Admin replies via `POST /api/admin/support/tickets/[id]/messages` MUST trigger `sendTicketResponseEmail`. No silent admin-notes path that doesn't notify the user. Verified by integration test.
- **Internal notes are a separate route and sender type.** `POST /api/admin/support/tickets/[id]/notes` never emails the customer, never flips ticket status, and customer-facing APIs/emails whitelist only customer-visible sender types.
- **Rate-limit is tier-aware on user routes.** Authenticated paying users do not share buckets with anonymous visitors. Resolve identity *before* the limit check.
- **Cron alerter only flags, never auto-resolves.** It writes `slaStatus = breached` and posts an internal alert. It does NOT close, reassign, or message the customer.
- **N+1 forbidden in list endpoints.** Use bulk `WHERE IN` / `inArray(...)` batch fetches for users/orgs in admin list routes; see [ADMIN-API.md](references/ADMIN-API.md) and [IMPLEMENTATION-PATTERNS.md](references/IMPLEMENTATION-PATTERNS.md) for the portable shape.
- **Every customer-facing reply body runs through `/de-slopify` before send.** Admin/AI reply API, system templates (created/resolved emails), AI-generated suggestions, saved replies / macros after render, bot turns in chat — all of them. Customers can spot LLM defaults; one shipped slop-reply destroys trust we can't get back. The skill assumes `/de-slopify` is installed (the bootstrap auto-installs via `jsm install de-slopify`); if missing, `doctor.sh` blocks the EXACT PROMPTS and `install-companion-skills.sh` exits non-zero. See [SKILL-INSTALLATION.md](references/SKILL-INSTALLATION.md) for the install/auth/subscription flow, [EMAIL.md](references/EMAIL.md) and [AI-ASSIST.md](references/AI-ASSIST.md) for wire points, and [VOICE-CALIBRATION.md from the triage skill](../user-support-triage-for-saas-and-open-source-projects/references/VOICE-CALIBRATION.md) for the AI-tell catalog.
- **External side effects are idempotent and observable.** Email sends, refunds, webhook ingestion, cron alerts, and provider syncs record provider ids or idempotency keys and support read-after-write verification.
- **Ticket content is untrusted input.** AI assist may summarize or suggest, but ticket text never overrides system policy, tool instructions, permission checks, or the owner confirmation gate.
- **Support readiness includes handoff readiness.** The build must produce the triage handoff artifacts, adapter scripts, and validation record; compiling routes is not enough.
- **Support intelligence is structured, not buried in prose.** Theme tags, persona/register, CSAT/NPS/cancel verbatims, compensation decisions, keeper consent, and loopback state must be queryable/exportable so support evidence can improve product/docs/roadmap.

## Architecture (One-Page)

```
USER FLOW                                ADMIN FLOW
─────────                                ──────────
SupportWidget  ─POST /api/support/...    /admin/support/tickets (TanStack)
   │                                          │
   ▼                                          ▼
[supportTickets]  ◄──── service layer ──►  GET   /api/admin/support/tickets
[supportMessages]    (sla, transitions)    PATCH /api/admin/support/tickets
                          │                POST  .../[id]/messages  ──┐
                          ▼                                            │
                    sendTicketCreatedEmail  sendTicketResponseEmail ◄──┘
                          │                                            │
                          ▼                                            ▼
                    Email provider ──────────────────────────►  customer mailbox

Cron: /api/cron/sla-alerts every 15-30min
    └─► getTicketsApproachingSla(2)  → flags at_risk
        getTicketsBreachedSla()      → flags breached + internal alert (optional)
```

## Schema (Drizzle Sketch — Adapt To Project Naming)

```ts
export const supportCategoryEnum = pgEnum("support_category",
  ["auth", "billing", "access", "bug", "content_moderation", "other"]);
export const supportStatusEnum = pgEnum("support_status",
  ["open", "acknowledged", "in_progress", "awaiting_customer", "resolved", "closed"]);
export const slaStatusEnum = pgEnum("sla_status", ["ok", "at_risk", "breached"]);
export const ticketPriorityEnum = pgEnum("ticket_priority", ["p0", "p1", "p2", "p3"]);

export const supportTickets = pgTable("support_tickets", {
  id:                    uuid().primaryKey().defaultRandom(),
  orgId:                 uuid().references(() => organizations.id, { onDelete: "cascade" }),
  userId:                uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
  subject:               text().notNull(),
  description:           text().notNull(),
  priority:              ticketPriorityEnum().default("p2").notNull(),
  status:                supportStatusEnum().default("open").notNull(),
  slaDeadline:           timestamp({ withTimezone: true }),
  slaStatus:             slaStatusEnum().default("ok").notNull(),
  slaStatusUpdatedAt:    timestamp({ withTimezone: true }),
  slaBreachedAt:         timestamp({ withTimezone: true }),
  assignee:              text(),               // support agent identifier
  resolvedAt:            timestamp({ withTimezone: true }),
  createdAt:             timestamp({ withTimezone: true }).defaultNow().notNull(),
  updatedAt:             timestamp({ withTimezone: true }).defaultNow().notNull(),
}, t => [
  index("support_tickets_user_idx").on(t.userId),
  index("support_tickets_org_idx").on(t.orgId),
  index("support_tickets_status_idx").on(t.status),
  index("support_tickets_priority_idx").on(t.priority),
  index("support_tickets_sla_idx").on(t.slaDeadline),
  index("support_tickets_sla_status_idx").on(t.slaStatus),
  index("support_tickets_assignee_idx").on(t.assignee),
  index("support_tickets_created_idx").on(t.createdAt),
]);

export const supportMessages = pgTable("support_messages", {
  id:           uuid().primaryKey().defaultRandom(),
  ticketId:     uuid().notNull().references(() => supportTickets.id, { onDelete: "cascade" }),
  senderId:     uuid().references(() => users.id),       // null for system / support_agent
  senderType:   text().notNull(),                        // 'customer' | 'support' | 'system'
  message:      text().notNull(),
  createdAt:    timestamp({ withTimezone: true }).defaultNow().notNull(),
}, t => [
  index("support_messages_ticket_idx").on(t.ticketId),
  index("support_messages_created_idx").on(t.createdAt),
]);
```

### Support Intelligence Fields (Portable Shape)

The exact storage shape should match the host project. Keep these semantics
available somewhere queryable, even if the implementation uses JSONB or analytics
events instead of columns:

| Field | Suggested location | Why |
|---|---|---|
| `category` | `supportTickets` | Routing and volume metrics |
| `themeTags[]` | `supportTickets` or `supportOutcomes` | VoC trend mining |
| `personaTag` | `supportTickets` or `supportOutcomes` | Register/voice selection |
| `sourceStream` | tickets, surveys, public mentions | Distinguishes support/NPS/cancel/sales/public evidence |
| `customerEffortCount` | `supportOutcomes` | Reply-cycle and ask-count friction |
| `compensationBand` / `compensationApprovedBy` | `supportOutcomes` or audit log | Refund/credit consistency and proof |
| `keeperConsent` | `supportVerbatims` | Whether quotes can be used publicly |
| `loopbackNeeded` / `loopbackSentAt` | `supportOutcomes` or theme table | Close the loop when a fix ships |

Do not make the AI assistant the source of truth for these fields. It can
suggest tags; service code or the support agent records the accepted value.

Full schema (with `support_requests` legacy + `enterprise_leads`): [SCHEMA.md](references/SCHEMA.md).

## SLA Tiers (Defaults — Override Per Project)

| Tier        | P0 first response | P0 resolve | P2 first response | P2 resolve |
|-------------|-------------------|------------|-------------------|------------|
| Enterprise  | 1h                | 4h         | 4h                | 24h        |
| Individual  | 4h                | 24h        | 24h               | 72h        |
| Free        | 48h               | 168h       | 96h               | 168h       |

The service layer derives tier from the user/org subscription when the ticket is created, computes the SLA deadline, and then treats that deadline as historical fact. Do not recompute existing-ticket SLA deadlines just because the customer later upgrades or downgrades. If you store the resolved tier for audit/debugging, it is a snapshot, not the source of truth for future tickets.

## Phased Rollout

| Phase | Includes | Acceptance |
|---|---|---|
| 1 — Foundation  | Schema + service layer + permission keys + audit hook | Unit tests on `computeSlaStatus`, `computeNextStatusAfterMessage`, and state-machine conformance pass |
| 2 — User path   | `POST /api/support/tickets` + `SupportWidget` + create-confirmation email | E2E: a user creates a ticket and gets the email |
| 3 — Admin path  | Admin list/patch APIs + admin/support/tickets page + filters | E2E: admin sees the ticket and changes status with reason |
| 4 — Threading   | Messages API both sides + reply emails | E2E: admin reply emails customer; customer reply via UI flips status to `in_progress` |
| 5 — SLA cron    | `/api/cron/sla-alerts` + slaStatus enum populated + at_risk/breached transitions | E2E: cron flips slaStatus when deadline passes |
| 6 — Enterprise  | Per-org tier override + 4hr response config | E2E: an org tagged `enterprise` gets the tighter deadlines |
| 7 — Hardening   | Rate-limit tier-aware, audit on every mutation, integration tests for high-risk flows | All Hard Invariants pass `references/CHECKLIST.md` |
| 8 — Handoff     | Threat model, support-handoff.json, adapter scripts, support-map validation, routine + high-risk fire drills | `references/VALIDATION-GATES.md` G8-G10 pass or blockers have owners |

Detail: [PHASED-ROLL-OUT.md](references/PHASED-ROLL-OUT.md).

## Policy And Handoff Contract

This skill builds the queue; the triage skill operates it. Treat the handoff as part of done.

| Contract | Acceptance |
|---|---|
| Policy decisions | `references/POLICIES-PER-CATEGORY.md` adapted into project docs; owner signed off on refund, escalation, SLA, privacy, security, hostile-user handling |
| Channel map | New system appears in `<project>/.claude/support-triage/02-channels.md` with user/admin routes and email behavior |
| List-open adapter | `<project>/.claude/support-triage/scripts/list-open.sh` returns `support-adapter-v1` JSON without sending anything |
| Adapter validation | Triage skill's `scripts/validate-adapter-output.py` passes on the new system's open-item output |
| Voice | `08-voice.md` exists or explicitly says "no samples yet"; generated replies still go through `/de-slopify` |
| Theme vocabulary / VoC | `vocabularies/themes.md` exists when product feedback loops are in scope; tickets/export include theme tags and source stream |
| Compensation policy | Refund/credit/upgrade actions record owner approval and enough dials/evidence for the triage `🎁 GOODWILL` operator |
| Owner approval | No API route, cron, or admin bulk action sends customer-facing messages without an explicit support-agent action |
| Provider migration | Third-party cutover has a rollback path and preserves external ids for idempotency |
| Threat model | `references/SUPPORT-SYSTEM-THREAT-MODEL.md` reviewed; dangerous side effects have auth, audit, idempotency, and verification |
| Machine-readable handoff | `handoffs/support-handoff.json` follows `references/HANDOFF-ARTIFACT-CONTRACT.md` |
| Validation gates | `references/VALIDATION-GATES.md` record exists with status/evidence for each required gate |

If any row is missing, the system can exist technically but is not support-ready.

## Deliverables

- Migration files (auto-generated by Drizzle)
- Service-layer module + tests
- 6 admin routes + 4 user routes (handlers + tests)
- Internal-note route + customer-visibility filters
- Admin UI page (TanStack Query + filter bar + count pills + action queue)
- User UI: `SupportWidget`, `NewTicketForm`, `TicketList` components
- Email module + transactional templates
- Cron handler at `/api/cron/sla-alerts`
- Permission registry update (3 new keys)
- Audit-event taxonomy entry
- README/AGENTS.md blurb
- Support-triage handoff docs + `scripts/list-open.sh`
- Optional-but-required-when-triggered hardening modules: attachments, saved
  replies/macros/bulk actions, ticket relationships, multi-team routing,
  spam/abuse handling, business-hours calendars, and journey/cost/proactive
  intelligence

## Anti-Patterns

| ✗ | Why |
|---|---|
| Direct table writes from route handlers | Bypasses SLA / status logic — drift is silent |
| Reopen-on-customer-reply for `closed` tickets | Resurrects work the team thought was done; surprises support |
| `awaiting_customer` SLA clock still running | Defeats the pause; alarms fire when the customer is actually the blocker |
| Admin notes without email-out | The user gets diagnosed, never told; trust collapses |
| Cron auto-resolving "old" tickets | Hides work; never auto-mutate without an explicit rule |
| Permission keys mixed with role checks | Two authorization surfaces is one too many |
| Ad-hoc rate-limit tiers per route | Tier mismatch bugs proliferate |
| `customerId` reused as ticket-thread join key | Tickets shouldn't depend on payment-provider IDs |
| Synchronous `sendEmail` in the request path | Slow paths under provider degradation; use a background hook, queue, or outbox |
| Adding a column for every priority subtype | The 4-level enum is enough; resist drift |

Full case studies: [ANTI-PATTERNS.md](references/ANTI-PATTERNS.md).

## Companion Skills

- `/user-support-triage-for-saas-and-open-source-projects` — operates this system once installed.
- `/admin-page-for-nextjs-sites` — broader admin cockpit; ticket queue is one slice.
- `/supabase` + `/stripe-checkout` + `/vercel` — environment plumbing.
- `/e2e-testing-for-webapps` — wiring the integration tests for ticket flows.
- `/security-audit-for-saas` — pre-launch sweep on the new admin endpoints.

## References

| Need | File |
|---|---|
| Bootstrap companion skills via jsm (de-slopify and friends) | [SKILL-INSTALLATION.md](references/SKILL-INSTALLATION.md) |
| Full Drizzle schema (incl. legacy support_requests) | [SCHEMA.md](references/SCHEMA.md) |
| Admin API contract + Zod schemas | [ADMIN-API.md](references/ADMIN-API.md) |
| User API contract | [USER-API.md](references/USER-API.md) |
| SLA engine: deadlines, transitions, edge cases | [SLA-ENGINE.md](references/SLA-ENGINE.md) |
| SLA as contract: service credits, compliance reports, commercial commitments | [SLA-AS-CONTRACT.md](references/SLA-AS-CONTRACT.md) |
| Portable state machine + conformance fixtures | [STATE-MACHINE-CONFORMANCE.md](references/STATE-MACHINE-CONFORMANCE.md) |
| Email pipeline (Resend) + templates | [EMAIL.md](references/EMAIL.md) |
| Internal notes vs public replies privacy defense | [INTERNAL-NOTES-VS-PUBLIC.md](references/INTERNAL-NOTES-VS-PUBLIC.md) |
| Admin UI patterns (TanStack Query) | [ADMIN-UI.md](references/ADMIN-UI.md) |
| User-facing widget + ticket detail | [USER-UI.md](references/USER-UI.md) |
| Permissions, audit, rate-limit tier | [SECURITY.md](references/SECURITY.md) |
| Cron + alerting provider | [CRON-AND-ALERTS.md](references/CRON-AND-ALERTS.md) |
| Business-hours calendars and operating-window SLAs | [BUSINESS-HOURS-AND-CALENDARS.md](references/BUSINESS-HOURS-AND-CALENDARS.md) |
| Enterprise tier overrides | [ENTERPRISE-TIER.md](references/ENTERPRISE-TIER.md) |
| Integration test plan | [TEST-PLAN.md](references/TEST-PLAN.md) |
| Ticketing-specific testing cookbook | [TESTING-COOKBOOK.md](references/TESTING-COOKBOOK.md) |
| Build/review checklist | [CHECKLIST.md](references/CHECKLIST.md) |
| Audit prompt for existing systems | [AUDIT-PROMPT.md](references/AUDIT-PROMPT.md) |
| Production implementation patterns and subtle failure modes | [IMPLEMENTATION-PATTERNS.md](references/IMPLEMENTATION-PATTERNS.md) |
| Incident pattern catalog and audit signals | [INCIDENT-PATTERNS.md](references/INCIDENT-PATTERNS.md) |
| Category-specific behavior matrix | [CATEGORY-AWARE-BEHAVIORS.md](references/CATEGORY-AWARE-BEHAVIORS.md) |
| Attachments, signed URLs, scanning, and retention | [ATTACHMENTS-AND-FILE-UPLOAD.md](references/ATTACHMENTS-AND-FILE-UPLOAD.md) |
| Saved replies, macros, bulk actions, and CSV export | [SAVED-REPLIES-MACROS-BULK.md](references/SAVED-REPLIES-MACROS-BULK.md) |
| Ticket graph: duplicates, incidents, engineering links, follow-ups | [TICKET-LINKING-AND-RELATIONSHIPS.md](references/TICKET-LINKING-AND-RELATIONSHIPS.md) |
| Multi-team routing, on-call lanes, and handoff hygiene | [MULTI-TEAM-ROUTING.md](references/MULTI-TEAM-ROUTING.md) |
| Spam, abuse, hostile users, ATO, and admin wellbeing | [SPAM-ABUSE-HOSTILE-USERS.md](references/SPAM-ABUSE-HOSTILE-USERS.md) |
| Ticketing operator cards for implementation and audit | [OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md) |
| SLA metrics and reporting contract | [METRICS-AND-REPORTING.md](references/METRICS-AND-REPORTING.md) |
| Customer journey reconstruction for faster diagnosis | [CUSTOMER-JOURNEY-RECONSTRUCTION.md](references/CUSTOMER-JOURNEY-RECONSTRUCTION.md) |
| Cost-of-support economics and ROI loops | [COST-OF-SUPPORT.md](references/COST-OF-SUPPORT.md) |
| Evidence anchoring guide for local verification | [EVIDENCE-CORPUS.md](references/EVIDENCE-CORPUS.md) |
| Proactive and predictive support layers | [PROACTIVE-AND-PREDICTIVE-SUPPORT.md](references/PROACTIVE-AND-PREDICTIVE-SUPPORT.md) |
| Future product and platform ideas after the foundation is real | [CREATIVITY-AND-INNOVATION.md](references/CREATIVITY-AND-INNOVATION.md) |
| Triage VoC loop and theme instrumentation | [VOICE-OF-CUSTOMER-LOOP.md](../user-support-triage-for-saas-and-open-source-projects/references/VOICE-OF-CUSTOMER-LOOP.md) |
| Voice-of-customer extraction into product/marketing/leadership outputs | [VOICE-OF-CUSTOMER-EXTRACTION.md](references/VOICE-OF-CUSTOMER-EXTRACTION.md) |
| Triage compensation calculus for refund/credit/upgrade actions | [COMPENSATION-CALCULUS.md](../user-support-triage-for-saas-and-open-source-projects/references/COMPENSATION-CALCULUS.md) |
| Triage tactical-empathy and customer-psychology operators | [TACTICAL-EMPATHY.md](../user-support-triage-for-saas-and-open-source-projects/references/TACTICAL-EMPATHY.md) |
| Failure modes / case studies | [ANTI-PATTERNS.md](references/ANTI-PATTERNS.md) |
| Phased rollout | [PHASED-ROLL-OUT.md](references/PHASED-ROLL-OUT.md) |
| KB integration (deflection + agent suggestions) | [KNOWLEDGE-BASE.md](references/KNOWLEDGE-BASE.md) |
| AI-assisted features (categorize / suggest / dedup) | [AI-ASSIST.md](references/AI-ASSIST.md) |
| Migration scripts per provider (Zendesk/Intercom/Help Scout/Freshdesk/Plain/Linear/JSM/HubSpot/Salesforce/Front/Gorgias/Zoho Desk) | [MIGRATION-PER-PROVIDER.md](references/MIGRATION-PER-PROVIDER.md) |
| Accessibility (WCAG 2.2 AA) | [ACCESSIBILITY.md](references/ACCESSIBILITY.md) |
| Observability — logs, metrics, traces, alerts | [OBSERVABILITY.md](references/OBSERVABILITY.md) |
| Customer satisfaction (CSAT/NPS/cancellation surveys) | [CUSTOMER-SATISFACTION.md](references/CUSTOMER-SATISFACTION.md) |
| Policies — refund, escalation, SLA, security, hostile | [POLICIES-PER-CATEGORY.md](references/POLICIES-PER-CATEGORY.md) |
| Diagnostics — symptom-keyed troubleshooting for live systems | [DIAGNOSTICS.md](references/DIAGNOSTICS.md) |
| Framework portability beyond Next.js | [FRAMEWORK-PORTABILITY.md](references/FRAMEWORK-PORTABILITY.md) |
| Provider portability for email/observability/AI | [PROVIDER-PORTABILITY.md](references/PROVIDER-PORTABILITY.md) |
| Router and complexity modes | [ROUTER-AND-COMPLEXITY-MODES.md](references/ROUTER-AND-COMPLEXITY-MODES.md) |
| Support system threat model | [SUPPORT-SYSTEM-THREAT-MODEL.md](references/SUPPORT-SYSTEM-THREAT-MODEL.md) |
| Handoff artifact contract | [HANDOFF-ARTIFACT-CONTRACT.md](references/HANDOFF-ARTIFACT-CONTRACT.md) |
| Validation gates and proof record | [VALIDATION-GATES.md](references/VALIDATION-GATES.md) |
| Real-world failure modes — 35 named incidents with defenses | [INCIDENT-PATTERNS.md](references/INCIDENT-PATTERNS.md) |
| Testing cookbook — Drizzle chain mocks, lifecycle fixtures, integration recipes | [TESTING-COOKBOOK.md](references/TESTING-COOKBOOK.md) |
| Per-category behaviors — auth/billing/access/bug/content_moderation/other | [CATEGORY-AWARE-BEHAVIORS.md](references/CATEGORY-AWARE-BEHAVIORS.md) |
| Internal notes vs public replies — accidental-leak defenses | [INTERNAL-NOTES-VS-PUBLIC.md](references/INTERNAL-NOTES-VS-PUBLIC.md) |
| Attachments and file upload — signed URLs, virus scan, retention, EXIF | [ATTACHMENTS-AND-FILE-UPLOAD.md](references/ATTACHMENTS-AND-FILE-UPLOAD.md) |
| Business hours and calendars — wallclock vs business-hours SLA | [BUSINESS-HOURS-AND-CALENDARS.md](references/BUSINESS-HOURS-AND-CALENDARS.md) |
| Saved replies, macros, bulk actions — operator productivity layer | [SAVED-REPLIES-MACROS-BULK.md](references/SAVED-REPLIES-MACROS-BULK.md) |
| Proactive and predictive support — clusters, repeat filers, deflection, churn | [PROACTIVE-AND-PREDICTIVE-SUPPORT.md](references/PROACTIVE-AND-PREDICTIVE-SUPPORT.md) |
| Cost of support — per-ticket / per-customer / per-tier economics | [COST-OF-SUPPORT.md](references/COST-OF-SUPPORT.md) |
| Spam, abuse, and hostile users — layered defense | [SPAM-ABUSE-HOSTILE-USERS.md](references/SPAM-ABUSE-HOSTILE-USERS.md) |
| Customer journey reconstruction — analytics + errors + flags + history | [CUSTOMER-JOURNEY-RECONSTRUCTION.md](references/CUSTOMER-JOURNEY-RECONSTRUCTION.md) |
| Ticket linking and relationships — duplicates, blocks, engineering, incident | [TICKET-LINKING-AND-RELATIONSHIPS.md](references/TICKET-LINKING-AND-RELATIONSHIPS.md) |
| Cross-product linking — roadmap, changelog, releases, KB, flags, CRM, community | [CROSS-PRODUCT-LINKING.md](references/CROSS-PRODUCT-LINKING.md) |
| Multi-team routing — per-team SLAs, on-call, re-routing | [MULTI-TEAM-ROUTING.md](references/MULTI-TEAM-ROUTING.md) |
| Performance budgets — query, latency, bundle, cache | [PERFORMANCE-BUDGETS.md](references/PERFORMANCE-BUDGETS.md) |
| Real-time presence and updates — polling, SSE, optimistic, presence | [REAL-TIME-PRESENCE-AND-UPDATES.md](references/REAL-TIME-PRESENCE-AND-UPDATES.md) |
| Chatbot and in-product messaging — real-time chat on the ticket substrate | [CHATBOT-AND-IN-PRODUCT-MESSAGING.md](references/CHATBOT-AND-IN-PRODUCT-MESSAGING.md) |
| Export and data portability — GDPR, CSV, migration JSONL, scheduled exports | [EXPORT-AND-DATA-PORTABILITY.md](references/EXPORT-AND-DATA-PORTABILITY.md) |
| Offboarding and account deletion — cancellation, erasure, holds, termination | [OFFBOARDING-AND-ACCOUNT-DELETION.md](references/OFFBOARDING-AND-ACCOUNT-DELETION.md) |
| Internationalization and localization — locale, language, cultural calibration | [INTERNATIONALIZATION-AND-LOCALIZATION.md](references/INTERNATIONALIZATION-AND-LOCALIZATION.md) |
| Mobile responsive support surfaces — widget/forms/conversation on phones | [MOBILE-RESPONSIVE-PATTERNS.md](references/MOBILE-RESPONSIVE-PATTERNS.md) |
| Status page integration — ticket clusters and public incident truth | [STATUS-PAGE-INTEGRATION.md](references/STATUS-PAGE-INTEGRATION.md) |
| War-room incident mode — explicit major-incident operating mode | [WAR-ROOM-INCIDENT-MODE.md](references/WAR-ROOM-INCIDENT-MODE.md) |
| Forensics and litigation holds — evidence preservation, subpoena response, hold lifecycle | [FORENSICS-AND-LITIGATION-HOLDS.md](references/FORENSICS-AND-LITIGATION-HOLDS.md) |
| Inbound webhooks — authenticated/idempotent support event ingestion | [INBOUND-WEBHOOK-INGESTION.md](references/INBOUND-WEBHOOK-INGESTION.md) |
| Outbound customer webhooks — customer-subscribable ticket events | [OUTBOUND-WEBHOOKS-FOR-CUSTOMERS.md](references/OUTBOUND-WEBHOOKS-FOR-CUSTOMERS.md) |
| Advanced AI feature hardening — prompt-injection, validation, cost, privacy | [ADVANCED-AI-FEATURES.md](references/ADVANCED-AI-FEATURES.md) |
| Tone and empathy patterns — positive craft layer above `/de-slopify` | [TONE-AND-EMPATHY-PATTERNS.md](references/TONE-AND-EMPATHY-PATTERNS.md) |
| Marketplace and disputes — buyer/seller dispute schema, evidence, neutrality, fraud detection | [MARKETPLACE-AND-DISPUTES.md](references/MARKETPLACE-AND-DISPUTES.md) |
| Postmortem and learning loops — support-specific incident learning | [POSTMORTEM-AND-LEARNING-LOOPS.md](references/POSTMORTEM-AND-LEARNING-LOOPS.md) |
| Regression detection from tickets — velocity sentinel, deploy correlation, surface severity | [REGRESSION-DETECTION-FROM-TICKETS.md](references/REGRESSION-DETECTION-FROM-TICKETS.md) |
| Documentation feedback loop — turning ticket signal into docs improvements | [DOCUMENTATION-FEEDBACK-LOOP.md](references/DOCUMENTATION-FEEDBACK-LOOP.md) |
| Customer lifecycle integration — stage enum, SLA multiplier, expansion/at-risk/renewal hooks | [CUSTOMER-LIFECYCLE-INTEGRATION.md](references/CUSTOMER-LIFECYCLE-INTEGRATION.md) |
| Support product integration — `?` bubbles, contextual KB, in-app banners, ticket-create context capture | [SUPPORT-PRODUCT-INTEGRATION.md](references/SUPPORT-PRODUCT-INTEGRATION.md) |

## Scripts

| Script | Purpose |
|---|---|
| [`scripts/doctor.sh`](scripts/doctor.sh) | Green/red readiness check; required + informational; `--json` and `--strict` modes; flags missing `/de-slopify` as a required failure |
| [`scripts/check-companion-skills.sh`](scripts/check-companion-skills.sh) | Non-mutating inventory of companion skills + jsm state; writes `skill_inventory.json` |
| [`scripts/install-companion-skills.sh`](scripts/install-companion-skills.sh) | Runs `jsm install <name>` for each missing companion; exits non-zero if `/de-slopify` can't be installed |

## Self-Test

Should activate this skill:
- "Build a support ticketing system into our Next.js SaaS"
- "Add SLA tracking to /admin/support"
- "Migrate us off Zendesk back to in-app tickets"
- "Wire Resend so admin replies email the customer"
- "Add a 4hr first-response tier for enterprise"
- "Audit the existing support code for missing invariants"
- "Design a support queue for our internal ops tool"
- "Build support around marketplace order disputes and app-store reviews"

Should NOT activate this skill (route accordingly):
- "I have an open ticket queue and need to handle it right now" → `/user-support-triage-for-saas-and-open-source-projects`
- "Polish this admin reply for tone before sending" → `/de-slopify`
- "Add a refund button" without ticketing scaffolding → `/admin-page-for-nextjs-sites`
- "Set up Stripe so we can compute tier" → `/stripe-checkout` first
- "Drizzle pooler / Auth / RLS not done" → `/supabase` first
- "Just write integration tests for an existing system" → `/testing-real-service-e2e-no-mocks`

Pre-flight smoke (run before invoking any EXACT PROMPT):

```bash
./scripts/doctor.sh    # exits 0 only when host project meets prerequisites
```

If `doctor.sh` exits non-zero, the listed failure tells you which companion skill to run first.

