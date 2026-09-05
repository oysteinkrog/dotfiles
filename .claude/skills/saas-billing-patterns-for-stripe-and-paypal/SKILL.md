---
name: saas-billing-patterns-for-stripe-and-paypal
description: >-
  Audit, harden, or implement SaaS subscription billing with Stripe/PayPal.
  Use when fixing webhooks, duplicate charges, billing security, dunning,
  MRR, migrations, or Next.js billing.
---

<!-- TOC: One Rule | Inputs | Scope Governor | Mode Router | Skill Bootstrap | Phase Loop | Operators | Polish Bar | Anti-Patterns | Project-Type Defaults | Verification-First | Scope Triage | Source Corpus | Reference Index | Scripts | Subagents | Assets | Self-Test -->

# SaaS Billing Patterns — Stripe + PayPal

> **The One Rule.** The provider is the source of truth, your DB is a *fast cache* of provider state, and every other pattern in this skill is a corollary of that fact. When the DB and provider disagree, the provider wins; when they agree but the user's experience is wrong, your projection is wrong; when they agree and the user is happy, you have not yet been attacked.

> **What this skill produces.** Either (a) a thorough audit + multi-pass refactor of an existing SaaS project's billing code so every activated/in-scope pattern in this skill's pattern library is verifiably present or explicitly marked `n/a`, or (b) a from-scratch billing system built in the canonical step-ordered build sequence. Output deliverables include a coverage matrix, a risk-scored gap list, a beads-style implementation plan, the actual code changes, real-DB integration tests, drift-guard tests, runbooks, and a secret-custody inventory.

---

## What This Skill Is For

You point this skill at a SaaS project (Next.js by default; works on other frameworks with translated patterns) and ask one of these:

1. *"Audit my billing code and tell me what's broken or missing."*
2. *"Implement Stripe + PayPal subscriptions in this project from scratch."*
3. *"Harden the webhook layer — we had a duplicate charge incident."*
4. *"Add team plans / pause-resume / dunning / MRR reporting / refund handling."*
5. *"Migrate from one provider's billing to dual-provider with proper isolation."*

The skill answers each by routing through the same kernel (north-star principles), the same operator library (cognitive moves), and the same phase loop (research → coverage → risk → plan → implement → polish → audit → test → ship → handoff).

The pattern library is mined from `COMPREHENSIVE_GUIDE_TO_SAAS_BILLING_PATTERNS_WITH_STRIPE_AND_PAYPAL.md` — 78 sections, ~700 billing-touching commits, 339 closed billing beads, and the seven security-audit findings (SA-01, SA-02, SA-03, SA-06, SA-13, SA-17, SA-22) that shaped them. Every pattern in this skill traces back to a real customer incident or a verified attack class.

---

## Inputs

- **Target project path** (default: cwd) — absolute path to a SaaS repo, OR a git URL we should clone into `/tmp/`.
- **Mode** (auto-detected from project state, user-overridable; see Mode Router).
- **Provider scope** — `stripe-only` | `paypal-only` | `both` (default: `both` — the patterns are explicitly designed for the dual-provider, asymmetric case).
- **Stack hints** (auto-detected by `scripts/discover-stack.sh`) — framework (Next.js / Remix / SvelteKit / Express / Fastify / FastAPI / Django / Rails / Phoenix), ORM (Drizzle / Prisma / Sequelize / SQLAlchemy / Ecto / ActiveRecord), DB (Postgres / MySQL / SQLite), cron host (Vercel / Cloud Run / Render / Fly / self-hosted), email provider (Resend / Postmark / SES).
- **Risk appetite** — `production-paying-customers` (most patterns mandatory) | `pre-launch-pilot` (security mandatory, reporting deferrable) | `internal-tool` (skip dunning + reporting; keep schema + idempotency + hijack defenses).

## Scope Governor

This skill is a billing-system skill. It can use adjacent process tools, but it must not become a general NTM, git, CI, support, or operations manual.

Before Phase 1, write `.billing_workspace/phase0_scope_decision.md` with:

- mode, tier, provider scope, and risk appetite;
- required bundles for this run;
- conditional bundles explicitly included with the trigger that activated each one;
- conditional bundles explicitly skipped with `n/a` rationale;
- a short **not doing** list for adjacent work the user did not ask for.

Default to the smallest mode that fully covers the user request. A one-capability request stays in `add-feature` unless it crosses a shared billing primitive: schema, webhook handler set, cron/reconciliation, provider migration, compliance evidence, incident response, or live provider catalog drift.

Use progressive disclosure:

1. Always read `SKILL.md`, [SCOPE-TRIAGE.md](references/methodology/SCOPE-TRIAGE.md), [OPERATING-MODES.md](references/methodology/OPERATING-MODES.md), [POLISH-BAR.md](references/methodology/POLISH-BAR.md), and only the pattern bundles that the scope decision activates.
2. Read [CASS-MINING.md](references/methodology/CASS-MINING.md) only when prior billing sessions, incidents, migrations, or decisions could change the plan.
3. Read [NTM-SWARM-ORCHESTRATION.md](references/methodology/NTM-SWARM-ORCHESTRATION.md) only for T4+ billing swarms or P0 incidents with multiple parallel bundle owners.
4. Read hooks, git, compliance, marketplace, migration, tax, usage, and internationalization references only when their activation criteria fire.

If a helper reference is not activated, document it as skipped; do not silently import its practices into the run.

---

## Up-Front Confirmations (Ask Before Starting)

Use the intake template at `assets/intake-prompt.md` verbatim. The summary:

1. **Project path?** Confirm the absolute path. If a git URL, ask whether to clone to `/tmp/<basename>` and operate on the worktree.
2. **Mode?** Show the auto-detected mode and let the user override (see Mode Router below).
3. **Scope tier?** Auto-detect from customer count + ARR + complexity overlay (see [SCOPE-TRIAGE.md](references/methodology/SCOPE-TRIAGE.md)); confirm the tier and corresponding required-bundle list.
4. **Scope decision artifact?** Confirm the proposed `.billing_workspace/phase0_scope_decision.md`: included bundles, skipped bundles, and adjacent work explicitly out of scope.
5. **Provider scope + risk appetite?** These determine which pattern bundles are mandatory vs. optional.
6. **Branch strategy?** Default: create a new branch `billing-hardening-<YYYYMMDD>` and commit each phase separately so the user can review per-phase diffs.
7. **Real-DB tests OK?** Ask whether the user has a disposable Postgres branch (Supabase / Neon / local Docker). Mock-only tests are explicitly rejected for billing code (`§69` of source guide); we will refuse to mark Phase 8 complete without a real DB.
8. **Stripe + PayPal sandbox creds available?** For Phase 9 staging drills. If not, walk the user through generating restricted Stripe API keys + PayPal sandbox app creds.
9. **Resuming a prior run?** If `.billing_workspace/` already exists, offer to re-enter the phase loop where it left off (idempotent) or treat as a fresh run.
10. **CASS available?** If `/cass` is installed and indexed, run `subagents/cass-miner.md` BEFORE Phase 1 only when prior billing context could change scope, risk, or implementation ordering.

After the user answers, send the matching kickoff prompt from [KICKOFF-PROMPTS.md](references/methodology/KICKOFF-PROMPTS.md) verbatim.

If any helper skill referenced here is missing (`/operationalizing-expertise`, `/codebase-archaeology`, `/codebase-report`, `/security-audit-for-saas`, `/multi-pass-bug-hunting`, `/multi-model-triangulation`, `/saas-customer-analytics`, `/ubs`, `/ru-multi-repo-workflow`, `/agent-mail`, `/beads-br`, `/beads-bv`, `/vercel`, `/supabase`, `/stripe-checkout`, `/e2e-testing-for-webapps`, `/testing-real-service-e2e-no-mocks`, `/testing-real-service-e2e-no-mocks`, `/idea-wizard`, `/cass`, `/cc-hooks`, `/gh-cli`, `/code-review-gemini-swarm-with-ntm`, `/multi-agent-swarm-workflow`): if the user has `jsm` installed and authenticated, offer to `jsm install <name>` for each missing one. Don't block a phase if a polish skill is missing — note it and proceed with the inline fallback in `references/methodology/SKILL-FALLBACKS.md`.

---

## Skill Bootstrap (Phase 0.5 — right after inputs, before partition)

```bash
./scripts/check-skills.sh .billing_workspace
# Prints inventory of helper skills + writes phase0_skill_inventory.json

./scripts/discover-stack.sh <project-path> > .billing_workspace/phase0_stack.json
# Detects framework, ORM, DB, cron host, email provider, payment libraries
```

If skills are missing and `jsm` is installed + authenticated:

```bash
./scripts/install-referenced-skills.sh .billing_workspace
```

If `jsm` isn't installed, offer the official installer (Linux/macOS):

```bash
curl -fsSL https://jeffreys-skills.md/install.sh | bash
```

Then `jsm login` (browser OAuth). Requires a paid [jeffreys-skills.md](https://jeffreys-skills.md) subscription to install premium skills. The pipeline degrades gracefully without `jsm` — every helper skill has an inline fallback playbook.

Full bootstrap detail (subscription checks, headless OAuth, offline fallback): **[SKILL-FALLBACKS.md](references/methodology/SKILL-FALLBACKS.md)**.

---

## Mode Router

Pick the primary mode first. The phase loop is the same; the **stop conditions and required artifacts** differ.

| Mode | Use when | Must finish with |
|------|----------|------------------|
| `audit-only` | Existing billing code; no commits requested | coverage matrix + risk-scored gap list + beads-style backlog (no code changes) |
| `audit-and-fix` | Existing billing code; user wants the gaps fixed | everything in `audit-only` + per-pattern fixes + drift-guard tests + ≥2 fresh-eyes passes clean |
| `harden-incident` | A real production billing incident just happened | RCA-driven fix-first pass on the relevant pattern bundle, then a full `audit-and-fix` |
| `add-feature` | Adding one bounded billing capability (teams, pause/resume, dunning ladder, refund automation, MRR card, etc.) | scoped to the relevant pattern bundle(s) + cross-cutting harmonization for the touched tables/crons |
| `greenfield` | No existing billing code at all | entire step-ordered implementation from `references/patterns/110-OPERATIONS.md §Battle-tested-checklist` |
| `migration` | Switching from a different billing approach (Lemon Squeezy / Paddle / Chargebee / Recurly) or adding a second provider to a single-provider system | provider-symmetric refactor + cross-provider duplicate-sub guard + migration runbook |
| `compliance-pass` | SOC2 / ISO / annual-review pressure | secret-custody matrix + RLS audit + rate-limiter coverage + security-event taxonomy completeness + log-tampering audit |

Auto-detect heuristics: `scripts/discover-stack.sh` looks for Stripe/PayPal SDK imports, webhook routes, `payment_events` / `subscriptions` tables, Drizzle/Prisma schemas, and recent commits with `stripe|paypal|webhook|subscription|invoice|refund|dunning|mrr` in the message. The detector picks the mode and shows its reasoning; the user can override.

Full mode definitions, exit criteria, and required artifacts: **[OPERATING-MODES.md](references/methodology/OPERATING-MODES.md)**.

**Single-feature guard.** If the user asks for one bounded capability, start in `add-feature` and activate only the directly crossed bundles plus cross-cutting Polish Bar dimensions for touched tables, crons, and handlers. Escalate to `audit-and-fix` only when the feature changes shared billing primitives or exposes evidence of broader drift.

---

## The Phase Loop (Mandatory)

```
Phase 1  ARCHAEOLOGY      framework + ORM + DB + billing surfaces (parallel by subtree)
Phase 2  COVERAGE         every pattern → present | partial | missing | n/a
Phase 3  RISK             score gaps by exploitability × customer-impact × blast-radius
Phase 4  PLAN             beads-style task graph; ordering respects schema-before-code
Phase 5  IMPLEMENT        per-bundle parallel implementers (schema → webhooks → checkout → security → state → dunning → teams → reliability → reporting → ops)
Phase 6  HARMONIZE        cross-cutting consistency: idempotency, error codes, exclusions, provenance, secret custody
Phase 7  FRESH EYES       three review prompts (yourself, fellow-agent, security lens); multi-model triangulation if available
Phase 8  REAL-DB TESTS    integration tests against real Postgres + provider sandboxes; drift-guards
Phase 9  STAGING DRILL    end-to-end webhook drills against Stripe Test mode + PayPal sandbox
Phase 10 OPS HANDOFF      runbooks, secret-custody matrix, alert wiring, on-call doc
```

**Phases 5, 6, 7** are *reapply-until-quiet* — keep spawning passes until an entire pass produces only trivial edits (typo, comment polish). Phase 7's two clean rounds are the explicit termination gate before Phase 8.

**Phase 7 fresh-eyes prompts** (use verbatim — they're calibrated):

1. *"Carefully read over all of the new code you just wrote and other existing code you just modified with 'fresh eyes' looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover."*
2. *"Sort of randomly explore the code files in this project, choosing code files to deeply investigate and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious bugs, problems, errors, silly mistakes. Comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in AGENTS.md."*
3. *"Turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues. Diagnose underlying root causes using first-principle analysis. Don't restrict yourself to the latest commits — cast a wider net and go super deep."*

Repeat until two consecutive rounds come up clean except for trivial changes. Then run `ubs` (if available) and the linters; fix everything.

### Mode variants on the phase loop

| Mode | Phases run | Key omissions / additions |
|------|-----------|---------------------------|
| `audit-only` | 1, 2, 3 (no 4+) | Output is a report only; no code touched |
| `audit-and-fix` | All 10 | Default |
| `harden-incident` | 1 (scoped) → 4 → 5 (scoped) → 7 → 8 → 9 → all phases on touched bundles | Skip parts of 2/3 not in blast radius; expand later |
| `add-feature` | 1 → 4 → 5 → 6 → 7 → 8 (only touched test surfaces) | Scoped to relevant bundles |
| `greenfield` | 4 (using Day-1 → Day-12 in `110-OPERATIONS.md`) → 5 → 6 → 7 → 8 → 9 → 10 | Skip 1/2/3 (no existing code to inventory) |
| `migration` | 1 (both old + new) → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 | Add a *cutover* sub-phase between 9 and 10 |
| `compliance-pass` | 1 → 2 (compliance subset) → 3 → 4 → 5 → 6 → 7 → audit-trail-only | Phase 8 is read-only; no code changes |

Full per-phase playbook with exact prompts: **[PHASES.md](references/methodology/PHASES.md)** and **[AGENT-PROMPTS.md](references/methodology/AGENT-PROMPTS.md)**.

---

## Parallelism Model

The repo's billing surface partitions naturally along the same boundaries as the source guide:

```
┌───────────────────────────────────────────────────────────────┐
│  PARTITION (Phase 1, by main agent)                           │
│  ─> identify which bundles already exist; assign one          │
│     archaeologist + implementer per bundle                    │
└────────────────┬──────────────────────────────────────────────┘
                 │
   ┌─────────────┼──────────────┬──────────────┬───────────────┐
   ▼             ▼              ▼              ▼               ▼
┌───────┐    ┌───────┐      ┌───────┐      ┌───────┐       ┌────────┐
│Schema │    │Webhook│      │Checkout│      │Security│      │Dunning │
│ B10   │    │  B40  │      │  B30   │      │  B50   │      │  B70   │
└───┬───┘    └───┬───┘      └───┬───┘      └───┬───┘        └───┬────┘
    │            │              │              │                │
    └────────────┴──────────────┴──────────────┴────────────────┘
                       │
                       ▼
            ┌──────────────────────┐
            │ Phase 6 HARMONIZE    │  single agent; cross-cutting consistency
            │ (idempotency, env,   │  pulls regression-test gaps for Phase 8
            │  exclusions, ...)    │
            └──────────┬───────────┘
                       ▼
                Phase 7 FRESH-EYES swarm (parallel + multi-model)
```

**Coordination.** Use [MCP Agent Mail](../agent-mail/SKILL.md) file reservations when multiple agents could touch the same file (especially `schema.ts`, `webhooks/inbound.ts`, the analytics-exclusions module, and the env config). Thread id: `billing-<run-id>-<phase>-<bundle>`.

**Orchestration tier** — pick based on repo size:

| Tier | Shape | When |
|------|-------|------|
| Solo | 1 worker, serial phases | Tiny project, single file billing |
| Pair | 2 workers, fan-out only on Phase 5 | Typical Next.js SaaS, single provider |
| Squad | 4–6 workers, parallel by bundle | Dual-provider SaaS with team plans |
| Swarm | 8–12 workers, beads-driven + multi-model triangulation in Phase 7 | Multi-product platform; SOC2 audit pressure |

Triangulation (Claude + Codex + Gemini) is reserved for Phase 7 fresh-eyes and Phase 9 staging-drill verification, where independent reads produce the highest signal. See **[ORCHESTRATION.md](references/methodology/ORCHESTRATION.md)**.

---

## Cognitive Operators (Billing Thinking Moves)

Composable moves. Apply them to any line of billing code, any new pattern, any code review comment. Each operator is a question that, if it fails, names a section to fix. See **[OPERATORS.md](references/methodology/OPERATORS.md)** for the full card library with triggers, failure modes, and prompt modules.

| Glyph | Name | Question | Fix-section |
|-------|------|----------|-------------|
| `⊙` | **Provider-Authority** | "If the provider says X and our DB says Y, do we render X?" | `00-NORTH-STAR` §1, `60-STATE` §verify-as-write |
| `⊕` | **Layered-Defense** | "If this single guard fails, what catches it next?" | `00-NORTH-STAR` §3, `90-RELIABILITY` |
| `🔒` | **Idempotent-Write** | "What stops a replay from doing the work twice?" | `40-WEBHOOKS` §recordWebhookEvent, `30-CHECKOUT` §idempotency |
| `⌖` | **Hijack-Cross-Check** | "What stops an attacker from pointing this UPDATE at a victim?" | `50-SECURITY` §validatePayPalUserId, §subscription_id WHERE |
| `⏱` | **Stale-Event-Gate** | "Does this UPDATE include `WHERE last_event_at < new_event_at`?" | `50-SECURITY` §replay-staleness |
| `⤴` | **200-On-Error** | "If the handler throws AFTER signature verification, do we still return 200?" | `40-WEBHOOKS` §10 |
| `⛓` | **Analytics-Exclusion** | "Are synthetic-fixture users filtered from this read / publisher?" | `100-ANALYTICS` §exclusions, `110-OPERATIONS` §drift-guard |
| `🪟` | **Provenance** | "Does this cache value carry `live | fallback | unavailable` for the renderer?" | `00-NORTH-STAR` §provenance, `100-ANALYTICS` §MRR snapshot |
| `🗄` | **Intent-Then-Act** | "Is the durable intent row written and committed BEFORE the slow provider call?" | `80-TEAMS` §pause/resume |
| `⊞` | **Advisory-Lock** | "Does this cron use `pg_try_advisory_lock` with a `finally` connection-release?" | `90-RELIABILITY` §cron-defenses |
| `🔁` | **Reconciliation-Backstop** | "Which cron catches this if the live webhook never lands?" | `90-RELIABILITY` §reconciliation, §integrity-audit |
| `⚖` | **Human-In-Loop-Refund** | "Is this irreversible action gated on a human, not a heuristic?" | `60-STATE` §refunds, `00-NORTH-STAR` §6 |
| `🔐` | **Secret-Custody** | "Is this credential scoped, sensitive-flagged, environment-isolated, and rotation-tracked?" | `20-CONSTANTS-AND-ENV` §secrets, `110-OPERATIONS` §custody |
| `🧪` | **Pin-The-Contract** | "Is there a regression test mapped to a bead/incident name?" | `110-OPERATIONS` §integration-tests, §drift-guards |
| `📐` | **Type-Derive-Not-Hard-Code** | "Is the SDK string derived from `ConstructorParameters<typeof Stripe>` rather than written by hand?" | `20-CONSTANTS-AND-ENV` §STRIPE_API_VERSION |
| `🎚` | **Priority-Aware-Queue** | "Is the email type's priority set explicitly (refund > ops-alert > newsletter)?" | `90-RELIABILITY` §email-queue |
| `🪞` | **Bidirectional-Coverage** | "Is the set of subscribed events on the provider equal to the set of handled events in code?" | `40-WEBHOOKS` §coverage, `110-OPERATIONS` §provider-catalog-audit |

The operators are deliberately overlapping — a single line of webhook code typically deserves three or four. Application order in Phase 5/6: see [OPERATORS.md § Composition cheat-sheet](references/methodology/OPERATORS.md#composition-cheat-sheet).

---

## The Polish Bar (Non-Negotiable)

A "production-grade billing system" is not "the happy path works in `stripe trigger`." Every billing-touching change must satisfy:

| Dimension | Test |
|-----------|------|
| **Provider-Authority** | DB writes never override what we just read from the provider; cache reads display provider-state, not stale-DB-state, when they disagree. |
| **Layered-Defense** | Three write paths (live webhook, verify-as-write, reconciliation cron) and three alarm paths (per-event admin alert, stale-pipeline alarm, email failsafe) cover every entitlement-affecting event. |
| **Idempotent-Writes** | Provider idempotency key + DB-side `payment_events` dedup (UNIQUE provider, event_id) + partial-UNIQUE indexes (one OPEN intent per (user, sub); one pending checkout session ID globally) + status-set `WHERE` guards on every UPDATE. |
| **Hijack defense** | `validatePayPalUserId` runs on every PayPal individual handler; `subscription_id` is in every team-org UPDATE WHERE clause; account-mismatch (Stripe Connect / org events) returns 200 + `webhook_event_rejected`. |
| **Stale-event ordering** | Every UPDATE includes `WHERE last_event_at < new_event_at`. `last_event_at` lives on the row, not the audit table. |
| **200-on-error** | Webhook handlers ALWAYS return 200 after `recordWebhookEvent` succeeds, even on processing error. Reconciliation cron retries off our own rows. |
| **Synchronous cache invalidation on refund** | 2s `Promise.race` cap; failure logs but does not block the 200-return. |
| **Analytics exclusions** | Single canonical `exclusions.ts`; every cron + every reader + every admin-event publisher uses it; drift-guard test pins the import list. |
| **Provenance everywhere** | Every cached billing value carries `live | fallback | unavailable`; readers refuse to render `unavailable` as a number. |
| **Cron defenses** | `pg_try_advisory_lock` per cron, bounded scans, bounded retries, `finally { conn.release() }`, dry-run mode for the destructive ones. |
| **Secret custody** | Every Stripe / PayPal / Supabase / cron / alert credential lives in production-only env, marked sensitive, rotated, audited; no `NEXT_PUBLIC_*` for any billing key. |
| **Pin-the-contract regression test** | Every fix has a test named after the incident it fixes (`bd-1m86f__triple_charge_cross_provider_guard.test.ts`). |

If a change can't satisfy these, **it fails the bar** — that's a Phase 6 / 7 rework target, not a "ship it and watch."

Full rubric, per-bundle checklists, and verification queries: **[POLISH-BAR.md](references/methodology/POLISH-BAR.md)**.

---

## Project-Type Defaults

Phase 0 stack discovery picks a template. See **[PROJECT-TYPES.md](references/methodology/PROJECT-TYPES.md)** for the per-stack adjustments. Defaults in this skill are calibrated for the *primary* stack (the one the source guide was mined from):

| Stack | Primary | Notes |
|-------|---------|-------|
| **Next.js App Router + Drizzle + Postgres (Supabase) + Vercel Cron + Resend** | ✅ canonical | All patterns apply directly with file-path translations |
| Next.js Pages Router + Prisma | supported | Map App Router routes to `pages/api/`; Prisma migration discipline differs |
| Remix / SvelteKit / Nuxt | supported | Patterns translate; cron must run on a worker (no built-in cron) |
| Express / Fastify / Hono | supported | No bundler-leak risk for env vars; everything else applies |
| FastAPI / Django / Rails / Phoenix | translated | Pattern semantics same; idiomatic-translation tables in PROJECT-TYPES |
| Cloudflare Workers / Edge runtime | partial | Postgres pool pattern doesn't apply; use Hyperdrive or external DB; cron via Cron Triggers |
| Serverless monorepo (Turborepo / Nx) | supported | Single canonical billing package; consumers depend on it; never duplicate the writers |

For non-Postgres stacks: the `payment_events` UNIQUE-on-(provider, event_id) pattern requires a real unique constraint. SQLite is acceptable for early-stage; MySQL works with `ON DUPLICATE KEY UPDATE` adjustments documented in PROJECT-TYPES.

---

## Anti-Patterns (Never Do)

| ✗ | Why | Fix |
|---|-----|-----|
| Return 500 from a webhook after `recordWebhookEvent` succeeded | Provider retries cause duplicate side effects | Always 200 post-ingest; reconciliation cron drains failed rows |
| Trust `metadata.user_id` / `custom_id` as authoritative | Both are attacker-controlled | Cross-check via `validatePayPalUserId` / Stripe account check |
| Auto-refund on duplicate detection | Heuristics get it wrong; destroys customer relationships | Detect → alert → human triage |
| Use `updatedAt` for ordering webhook updates | Reconciliation discovers drift months after the customer event | Use provider's `event.created` → `last_event_at` column |
| One shared retry counter across event types | One bad event type maxes the counter for the whole class | Per-event-type retry caps at the handler level |
| Direct `sendEmail()` for billing alerts | Resend outage = lost alerts | `createEmailJob` (durable, retried) + failsafe sweep |
| Compatibility shims for old Stripe SDK shapes | Tech debt rots; per AGENTS.md "no shims" | Replace with single resolver (`getSubscriptionPeriod(sub)`) used uniformly |
| Build "MRR" from a SQL view that joins live tables | Kills cache invalidation semantics | Snapshot function with cache + invalidation hooks on every sub mutation |
| `NEXT_PUBLIC_STRIPE_*` for anything secret | Bundled into client JS, indexable | Server-only; for publishable keys use the explicit `_PUBLIC_` naming + audit |
| Skip the `paused_for_org` enum value | Treating org-pause as cancelled double-bills users on org-leave | Distinct enum value + projection rules |
| Webhook handler that throws after a partial side effect | Provider retries replay the partial side effect | All side effects inside one transaction; throw before commit |
| Polling Stripe API in a hot loop instead of using the webhook | Quota exhaustion + latency | Webhook-primary, verify-as-write second, reconciliation cron third |
| Mock the DB or Stripe in billing tests | Mocked tests pass while prod fails | Real-DB integration tests + provider sandboxes (`§69`) |
| Single email priority queue (FIFO) | Newsletter delays refund alerts | `email_jobs.priority smallint` + `(priority, next_retry_at, created_at)` index |
| Storing partial event payloads | Future handler changes need re-fetch / backfill | `payment_events.payload jsonb NOT NULL` — store full event |
| Inline destructive `git reset --hard` to "fix" a botched billing migration | Per AGENTS.md, hard reset is forbidden | Use `git revert` of the bad migration commit + a forward-fix migration |

Full anti-pattern catalog with the bead trail for each: **[110-OPERATIONS.md § Patterns rejected](references/patterns/110-OPERATIONS.md#patterns-tried-and-rejected---73)**.

---

## Pre-Flight & End Checklist

- [ ] Project path confirmed; mode auto-detected and confirmed; risk appetite set
- [ ] `.billing_workspace/phase0_scope_decision.md` written and confirmed: included bundles, skipped bundles, and adjacent work not being done
- [ ] Helper skills inventoried; missing ones offered via `jsm install` (non-blocking)
- [ ] Stack discovered and recorded in `phase0_stack.json`
- [ ] Phase 1 produced per-bundle archaeology notes (survives compaction)
- [ ] Phase 2 coverage matrix produced; every pattern marked `present | partial | missing | n/a`
- [ ] Phase 3 risk-scored gap list with explicit exploitability + customer-impact + blast-radius
- [ ] Phase 4 task graph respects schema-before-code ordering
- [ ] Phase 5 implementation passes ran until marginal (≥2 passes per bundle, last one trivial)
- [ ] Phase 6 cross-cutting harmonization done; single canonical exclusions/env/error-codes
- [ ] Phase 7 fresh-eyes ran ≥2 times clean; multi-model triangulation if available
- [ ] Phase 8 real-DB integration tests green; drift-guards in place; `ubs` clean if available
- [ ] Phase 9 staging drills (Stripe Test mode + PayPal sandbox) green; `tsc --noEmit` clean; build clean
- [ ] Phase 10 runbooks committed; secret-custody matrix written; on-call doc handed off

---

## Verification-First (mandatory)

The patterns in this skill are evergreen. Live provider state is volatile. Read **[VERIFICATION-FIRST.md](references/methodology/VERIFICATION-FIRST.md)** before finalizing any recommendation that depends on Stripe / PayPal Dashboard state, current SDK shape, or platform-controllable policy.

Core rule: do not give a live recommendation that depends on a volatile field UNTIL it has been verified read-only against the live provider AND logged in `.billing_workspace/provider_audit_log.md`.

The matching pattern bundle is **[35-PROVIDER-CATALOG-AUDIT.md](references/patterns/35-PROVIDER-CATALOG-AUDIT.md)** with paste-ready audit checks for every Stripe + PayPal surface that can drift.

---

## Scope Triage (route to the right depth)

Pick a tier first; the patterns scale to it. Don't over-build for T1; don't under-build for T4.

| Tier | Customers | ARR | Default mode | Bundles required |
|------|-----------|-----|--------------|------------------|
| **T1 — Pre-launch** | 0 | $0 | greenfield | B00, B10, B20, B30, B40, B50, B60, B90 (minimal), B70 (D0+D21), B100 (canonical MRR), B110 (one runbook/cron) |
| **T2 — Early-stage** | 1–500 | <$100K | audit-and-fix | All of T1 + full B70 + B90 |
| **T3 — Growth** | 500–10K | $100K–$5M | audit-and-fix quarterly + add-feature | All T2 + full B100 + full B110 + B80 if teams |
| **T4 — Scale** | 10K–500K | $5M–$50M | compliance-pass annually + audit-and-fix quarterly + migration as needed | ALL bundles + B35 + B55 + B120 + B140 |
| **T5 — Platform** | 500K+ | $50M+ | continuous everything | All + product-specific extensions |

Complexity overlay (+1 tier per): dual-provider, team plans, multi-currency, annual contracts, trials, discounts, multi-product, marketplace/Connect, usage-based, multi-region compliance.

Full triage logic: **[SCOPE-TRIAGE.md](references/methodology/SCOPE-TRIAGE.md)**.

---

## Source Corpus (Track A from operationalizing-expertise)

This skill IS a Track A artifact:
- **Corpus** — `COMPREHENSIVE_GUIDE_TO_SAAS_BILLING_PATTERNS_WITH_STRIPE_AND_PAYPAL.md` (78 sections, ~700 commits, 339 closed beads); see `references/source/SOURCE-INDEX.md` for the index of which sections feed which patterns.
- **Quote bank** — [SOURCE-CORPUS.md § Quote Bank](references/methodology/SOURCE-CORPUS.md#quote-bank) (48+ tagged anchors).
- **Triangulated kernel** — the 16 north-star principles in [00-NORTH-STAR.md](references/patterns/00-NORTH-STAR.md).
- **Operator library** — 21 operators in [OPERATORS.md](references/methodology/OPERATORS.md).
- **Validators** — 16 audit scripts in `scripts/`.

Section → bundle mapping in **[SOURCE-INDEX.md](references/source/SOURCE-INDEX.md)**. Bead trail in **[BEAD-DICTIONARY.md](references/source/BEAD-DICTIONARY.md)**.

When extending the skill: add the source quote to the quote bank with a `[Q-NNN]` ID, propose a kernel addition (rare), or add a new operator card. See [SOURCE-CORPUS.md § How to extend the corpus](references/methodology/SOURCE-CORPUS.md).

---

## Reference Index

### Methodology
| Need | File |
|------|------|
| Mode definitions + exit criteria | [OPERATING-MODES.md](references/methodology/OPERATING-MODES.md) |
| Per-phase playbook with exit criteria | [PHASES.md](references/methodology/PHASES.md) |
| Exact prompts for each parallel subagent | [AGENT-PROMPTS.md](references/methodology/AGENT-PROMPTS.md) |
| Per-mode kickoff prompts (verbatim) | [KICKOFF-PROMPTS.md](references/methodology/KICKOFF-PROMPTS.md) |
| Operator cards + composition cheat-sheet | [OPERATORS.md](references/methodology/OPERATORS.md) |
| Coverage-matrix template + scoring | [COVERAGE-MATRIX.md](references/methodology/COVERAGE-MATRIX.md) |
| Risk-scoring rubric | [RISK-SCORING.md](references/methodology/RISK-SCORING.md) |
| Polish-bar verification queries | [POLISH-BAR.md](references/methodology/POLISH-BAR.md) |
| Per-stack adjustments | [PROJECT-TYPES.md](references/methodology/PROJECT-TYPES.md) |
| Multi-agent orchestration tiers | [ORCHESTRATION.md](references/methodology/ORCHESTRATION.md) |
| Inline fallbacks for missing skills | [SKILL-FALLBACKS.md](references/methodology/SKILL-FALLBACKS.md) |
| Multi-model triangulation harness | [TRIANGULATION.md](references/methodology/TRIANGULATION.md) |
| **Verification-first protocol** (live provider audit discipline) | [VERIFICATION-FIRST.md](references/methodology/VERIFICATION-FIRST.md) |
| **Scope-tier triage** (T1-T5 routing) | [SCOPE-TRIAGE.md](references/methodology/SCOPE-TRIAGE.md) |
| **Source corpus structure** (Track A: corpus + quote bank + kernel + operators + validators) | [SOURCE-CORPUS.md](references/methodology/SOURCE-CORPUS.md) |
| **CASS mining recipes (general)** (mine prior agent sessions for billing context) | [CASS-MINING.md](references/methodology/CASS-MINING.md) |
| **CASS mining recipes (per failure class)** (38 calibrated queries per known class) | [CASS-MINING-RECIPES-DEEP.md](references/methodology/CASS-MINING-RECIPES-DEEP.md) |
| **Migration cutover playbook** (5-stage with rollback drill) | [MIGRATION-CUTOVER.md](references/methodology/MIGRATION-CUTOVER.md) |
| **Compliance evidence pack** (SOC2 / ISO templates) | [COMPLIANCE-EVIDENCE.md](references/methodology/COMPLIANCE-EVIDENCE.md) |
| **Incident response framework** (5-phase + 5-whys + postmortem template) | [INCIDENT-RESPONSE-PLAYBOOK.md](references/methodology/INCIDENT-RESPONSE-PLAYBOOK.md) |
| **Business-model portability** (trials / discounts / annual / multi-currency) | [BUSINESS-MODEL-PORTABILITY.md](references/methodology/BUSINESS-MODEL-PORTABILITY.md) |
| **Multi-model triangulation prompts** (verbatim for Codex / Gemini / Grok per lens + per failure class) | [MULTI-MODEL-TRIANGULATION-PROMPTS.md](references/methodology/MULTI-MODEL-TRIANGULATION-PROMPTS.md) |
| **NTM swarm orchestration** (optional T4+ billing-swarm guardrails; not a general NTM manual) | [NTM-SWARM-ORCHESTRATION.md](references/methodology/NTM-SWARM-ORCHESTRATION.md) |
| **Onboarding new engineers** (4-week curriculum + trust ladder + buddy system) | [ONBOARDING-NEW-ENGINEERS.md](references/methodology/ONBOARDING-NEW-ENGINEERS.md) |
| **Case studies + quick tier scoping** (compact T1-T5 right-sizing examples and run snapshots) | [CASE-STUDIES.md](references/methodology/CASE-STUDIES.md) |
| **Hooks integration** (optional billing-specific gates; defer to project CI/hook conventions) | [HOOKS-INTEGRATION.md](references/methodology/HOOKS-INTEGRATION.md) |
| **Stripe API reference card** (billing-relevant endpoints, calls, error codes) | [STRIPE-API-REFERENCE-CARD.md](references/methodology/STRIPE-API-REFERENCE-CARD.md) |
| **PayPal API reference card** (billing-relevant endpoints, calls, gotchas) | [PAYPAL-API-REFERENCE-CARD.md](references/methodology/PAYPAL-API-REFERENCE-CARD.md) |
| **Git workflow for billing** (optional billing PR traceability overlay; defer to project git rules) | [GIT-WORKFLOW-FOR-BILLING.md](references/methodology/GIT-WORKFLOW-FOR-BILLING.md) |

### Patterns (mined from the source guide + extensions)
| Need | File |
|------|------|
| North-star principles, layered-defense architecture | [00-NORTH-STAR.md](references/patterns/00-NORTH-STAR.md) |
| Schema design — `payment_events`, `subscriptions`, denorm `users`, supporting tables, migrations, **per-sub advisory locks, refund-terminal `none` absorbing state, `verify_endpoint_events` PII-free counter table with 25-tag namespace** | [10-SCHEMA.md](references/patterns/10-SCHEMA.md) |
| Constants, env validation, secrets, Stripe API version, idempotency keys | [20-CONSTANTS-AND-ENV.md](references/patterns/20-CONSTANTS-AND-ENV.md) |
| **Customer support integration (12 ticket classes, triage flow, read-only DB role, escalation taxonomy, refund policy)** | [25-CUSTOMER-SUPPORT-INTEGRATION.md](references/patterns/25-CUSTOMER-SUPPORT-INTEGRATION.md) |
| Provider-symmetric checkout, race guards, customer reuse, cross-provider probe; **TOCTOU lock + access check inside `.for("update")`, probe interface returning `{existingSub, reusableCustomerId}`, eager PayPal sub-id persistence + rollback, PayPal approval URL allowlisting, oldest-customer reuse + backfill, asymmetric pending TTLs (1h Stripe / 30m PayPal), full PayPal `application_context`** | [30-CHECKOUT.md](references/patterns/30-CHECKOUT.md) |
| **Provider catalog audit (Stripe + PayPal live state, bidirectional event coverage, diagnostic discipline)** | [35-PROVIDER-CATALOG-AUDIT.md](references/patterns/35-PROVIDER-CATALOG-AUDIT.md) |
| Webhook ingestion contract, canonical writer, replay/stale gates; **`<=` first-write-wins ordering primitive, `validatePaymentEventIntegrity` (test-mode/discount/wrong-price/livemode), owner-mismatch hijack guard, refund chain (charge→invoice→sub) resolution, full-vs-partial refund decision, `detectStaleCheckoutRace` + durable `billing_critical_alert`, HTML-escape admin notifications** | [40-WEBHOOKS.md](references/patterns/40-WEBHOOKS.md) |
| **Admin operations surface (refund button, invoice retry, event replay, dashboards, audit log, self-target block, break-glass)** | [45-ADMIN-OPERATIONS-SURFACE.md](references/patterns/45-ADMIN-OPERATIONS-SURFACE.md) |
| Hijack defenses, account-mismatch, abuse signals, rate limiter; **Layer 4 catch-all (owner-mismatch + payload integrity)** | [50-SECURITY.md](references/patterns/50-SECURITY.md) |
| **Observability + defense-in-depth (Prometheus alerts, CSP, credential rotation, event-age tolerance, cross-provider confusion, chargebacks, side-effect idempotency, settlement ledger); verify-endpoint alerts cron with per-tag thresholds + 60min cooldown, SLO snapshots cron with P0–P5 targets pinned to ADR-0010, webhook delivery-health heartbeat (paid-checkout/quiet-hours conditional thresholds), Vercel Skew Protection** | [55-OBSERVABILITY-AND-DEFENSE-IN-DEPTH.md](references/patterns/55-OBSERVABILITY-AND-DEFENSE-IN-DEPTH.md) |
| Subscription state, paused_for_org, grace, verify-as-write, refunds; **pause/resume intent ledger with `MAX_RETRY_COUNT=5` bounded retry, terminal-stuck digest, `alreadyMissing`-as-success** | [60-STATE-AND-LIFECYCLE.md](references/patterns/60-STATE-AND-LIFECYCLE.md) |
| **Test data + fixtures (predictable test users, Stripe Test Clocks, PayPal sandbox, adversarial corpus, mock detection)** | [65-TEST-DATA-AND-FIXTURES.md](references/patterns/65-TEST-DATA-AND-FIXTURES.md) |
| Dunning ladder, manual retry, SCA / 3DS, card expiry, pre-charge, portal, trial/discount/deal policy; **anti-misfire guard for `paid`/`void`/`uncollectible` invoices, full 6-guard `retryLatestStripeInvoice` (status/cap/lead-window/idempotency/race-recovery/SCA-context), SCA email rewrite to `hosted_invoice_url`, day-30 win-back single email** | [70-DUNNING-AND-PROACTIVE.md](references/patterns/70-DUNNING-AND-PROACTIVE.md) |
| **Tax + accounting (settlement ledger, Stripe Tax, GAAP-aware reporting, deferred revenue, GL integration)** | [75-TAX-AND-ACCOUNTING.md](references/patterns/75-TAX-AND-ACCOUNTING.md) |
| Team plans, seats, pause/resume intent, individual→team upgrade | [80-TEAMS.md](references/patterns/80-TEAMS.md) |
| **Usage-based billing (metered, tiered, hybrid; reporting to Stripe, fraud detection, refunds via credits)** | [85-USAGE-BASED-BILLING.md](references/patterns/85-USAGE-BASED-BILLING.md) |
| Orphan-cancel queues, reconciliation crons, integrity audit, cron defenses, email failsafe | [90-RELIABILITY.md](references/patterns/90-RELIABILITY.md) |
| **Internationalization + multi-currency (presentment vs integration, Adaptive Pricing, per-region tax, PSD2/SCA, payment methods)** | [95-INTERNATIONALIZATION.md](references/patterns/95-INTERNATIONALIZATION.md) |
| Analytics exclusions, MRR snapshot, fees, churn, health, forecasting, runway, freshness | [100-ANALYTICS.md](references/patterns/100-ANALYTICS.md) |
| **Performance + scale (N+1 detection, hot-path indexes, partial indexes, connection pool, read replicas, caching, partitioning)** | [105-PERFORMANCE-AND-SCALE.md](references/patterns/105-PERFORMANCE-AND-SCALE.md) |
| Error taxonomy, migration discipline, integration tests, drift-guards, cron schedule, runbooks, failure catalog, rejected patterns, key custody, greenfield step-ordered checklist; **ADR system (`docs/adr/billing/` with template + the 10 load-bearing ADRs that pin SLO numbers, payload-integrity policy, verify-as-write strategy, etc.)** | [110-OPERATIONS.md](references/patterns/110-OPERATIONS.md) |
| **Marketplace + Stripe Connect (connected accounts, fee splits, dispute on-behalf, capability monitoring, 1099-K)** | [115-MARKETPLACE-AND-CONNECT.md](references/patterns/115-MARKETPLACE-AND-CONNECT.md) |
| **Compliance evidence pack patterns (continuous evidence, per-control files, drift-guards as evidence, postmortems linked to controls, read-only audit credentials)** | [120-COMPLIANCE-EVIDENCE.md](references/patterns/120-COMPLIANCE-EVIDENCE.md) |
| **Dispute defense (auto-evidence gathering, Stripe Radar, per-reason templates, dispute rate monitoring, friendly-fraud)** | [125-DISPUTE-DEFENSE.md](references/patterns/125-DISPUTE-DEFENSE.md) |
| **Migration cutover patterns (provider-symmetric writer, dual-run reconciliation, customer-renewal-boundary migration, rollback drill, three-state migration column)** | [130-MIGRATION-CUTOVER.md](references/patterns/130-MIGRATION-CUTOVER.md) |
| **Webhook forensics (smoking-gun query, per-customer event timeline, replay tooling, traffic analysis, hijack forensics)** | [135-WEBHOOK-FORENSICS.md](references/patterns/135-WEBHOOK-FORENSICS.md) |
| **Incident response patterns (containment helpers, kill switches, webhook DLQ, per-row recovery, postmortem-driven test addition, customer-impact tally)** | [140-INCIDENT-RESPONSE.md](references/patterns/140-INCIDENT-RESPONSE.md) |
| **Extended failure-mode catalog (full 38-incident catalog organized by 8 themes; for incident triage + onboarding)** | [145-EXTENDED-FAILURE-CATALOG.md](references/patterns/145-EXTENDED-FAILURE-CATALOG.md) |

### Source corpus (read-only evidence)
| Need | File |
|------|------|
| Master guide (78 sections) | `COMPREHENSIVE_GUIDE_TO_SAAS_BILLING_PATTERNS_WITH_STRIPE_AND_PAYPAL.md` (private corpus, not bundled with this skill) |
| Section index → pattern bundle mapping | [SOURCE-INDEX.md](references/source/SOURCE-INDEX.md) |
| Bead-trail dictionary | [BEAD-DICTIONARY.md](references/source/BEAD-DICTIONARY.md) |

---

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/check-skills.sh` | Detect referenced helper skills + jsm state; write `phase0_skill_inventory.json` |
| `scripts/install-referenced-skills.sh` | Bulk-install missing skills via jsm |
| `scripts/discover-stack.sh` | Detect framework, ORM, DB, cron host, payment libraries; pick a project-type template |
| `scripts/grep-billing-surfaces.sh` | List every file that mentions stripe / paypal / webhook / subscription / refund / dunning / mrr |
| `scripts/generate-coverage-matrix.mjs` | Emit `phase2_coverage_matrix.md` skeleton with one row per pattern |
| `scripts/audit-update-staleness-guards.mjs` | Walk every UPDATE on subscriptions / organizations; report ones missing `last_event_at` clause |
| `scripts/audit-webhook-200-on-error.sh` | Detect webhook handlers that return non-200 after `recordWebhookEvent` succeeds |
| `scripts/audit-cron-locks.sh` | Detect crons missing `pg_try_advisory_lock` / `finally release` |
| `scripts/audit-exclusions-coverage.mjs` | Detect crons / publishers / readers that don't import the canonical exclusions module |
| `scripts/audit-bundle-leakage.sh` | Scan built Next bundle for leaked Stripe / PayPal / Supabase / cron tokens |
| `scripts/audit-stripe-event-coverage.sh` | Compare HANDLED_STRIPE_EVENTS in code vs. live Stripe Dashboard webhook config |
| `scripts/audit-trial-discount-deal.sh` | Verify trial/discount/deal policy enforced at provider level |
| `scripts/audit-csp-headers.sh` | Check CSP headers on checkout pages allow Stripe Elements/Checkout/Radar |
| `scripts/audit-vercel-env.sh` | Audit Vercel env scope + sensitive flag + NEXT_PUBLIC_ leak detection |
| `scripts/audit-rls-policies.sh` | Verify Supabase RLS policies on billing tables; probe as anon + authenticated + service_role |
| `scripts/provider-diagnostics.sh` | Read-only Stripe + PayPal diagnostics with mandatory counts-only redaction |
| `scripts/extract-source-quotes.sh` | Extract triangulated kernel + quote bank from source guide |
| `scripts/verify-source-coverage.sh` | Confirm every § of source guide maps to at least one bundle |
| `scripts/run-staging-drills.sh` | Trigger Stripe Test events + PayPal sandbox webhooks; verify end-to-end state changes |
| `scripts/stripe-test-clock-drill.sh` | Run Stripe Test Clock subscription-lifecycle drills (renewal / failed-payment / cancellation / pause-resume) |
| `scripts/replay-from-dlq.mjs` | Replay webhook DLQ entries against the live handler post-incident |
| `scripts/audit-stripe-payment-method-config.sh` | Audit Stripe Payment Method Configuration; detect Stripe-hosted PayPal drift |
| `scripts/audit-paypal-plan-prefs.sh` | Audit each PayPal plan's payment_preferences (auto_bill, threshold, setup_fee, trial cycles, quantity) |
| `scripts/generate-runbook-skeletons.sh` | Generate runbook skeletons from template for every cron + standard alarm |

Scripts either write their documented phase artifact or emit documented stdout for redirection into `.billing_workspace/`; JSON-only behavior is called out per script.

---

## Subagents

| Subagent | Phase | Purpose |
|----------|-------|---------|
| `subagents/cass-miner.md` | 0 | Mines user's prior cass sessions for billing patterns / decisions / reusable prompts |
| `subagents/archaeologist.md` | 1 | Project archaeology for one bundle subtree |
| `subagents/coverage-mapper.md` | 2 | Builds coverage matrix row(s) for one bundle |
| `subagents/risk-scorer.md` | 3 | Scores gaps by exploitability × customer-impact × blast-radius |
| `subagents/planner.md` | 4 | Creates beads-style task graph; respects schema-before-code |
| `subagents/section-implementer.md` | 5 | Implements one pattern bundle; the same agent owns archaeology + implementation for that bundle |
| `subagents/harmonizer.md` | 6 | Cross-cutting consistency (idempotency, env, exclusions, error codes, secrets) |
| `subagents/security-reviewer.md` | 7 | Adversarial security review focused on hijack + replay + signature classes |
| `subagents/fresh-eyes.md` | 7 | Generic fresh-eyes review using the three calibrated prompts |
| `subagents/triangulator.md` | 7 / 9 | Multi-model verification (Claude + Codex + Gemini) |
| `subagents/integration-test-writer.md` | 8 | Real-DB integration test author (no mocks) |
| `subagents/staging-verifier.md` | 9 | Stripe Test mode + PayPal sandbox drills |
| `subagents/runbook-writer.md` | 10 | Ops handoff: runbooks, secret-custody matrix, on-call doc |
| `subagents/provider-catalog-auditor.md` | 0 / 1 / 7 / nightly CI | Read-only audit of live Stripe + PayPal state vs. BUSINESS / pattern-library expectations |
| `subagents/policy-portability-auditor.md` | 1 / 7 | Verifies trial / discount / deal / annual / multi-currency policy expressed consistently |
| `subagents/rls-auditor.md` | 1 / 7 | Audits Supabase RLS policies; probes anon + authenticated + service_role queries |
| `subagents/observability-alerter.md` | 5 (B55) | Implements webhook + cron metrics + Prometheus alert rules |
| `subagents/csp-auditor.md` | 5 / 9 | Audits CSP headers on checkout pages for Stripe / PayPal allowance |
| `subagents/chargeback-handler.md` | 5 / add-feature | Implements chargeback abuse process (disputed_at + chargeback_count + billing_banned_at + access-gate) |
| `subagents/migration-cutover-coordinator.md` | migration mode | Orchestrates 5-stage cutover playbook with go/no-go gates and rollback drills |
| `subagents/compliance-evidence-collector.md` | compliance-pass mode | Assembles per-control evidence pack from continuous audit artifacts + drift-guards + postmortems |
| `subagents/idea-generator.md` | Phase 11 (post-baseline / explicit ask) | Surfaces billing-only improvement opportunities via /idea-wizard or inline prompts |
| `subagents/red-team-attacker.md` | Phase 7+ (T4+) | Adversarial — actively tries NOVEL attacks (vs security-reviewer's known-class lens) |
| `subagents/support-ticket-triager.md` | B25 / ongoing | Classifies + investigates customer support tickets per the 12 ticket classes |
| `subagents/admin-ui-implementer.md` | Phase 5 / B45 | Implements operator-facing admin UI (refund, retry, replay buttons, audit log viewer) |
| `subagents/test-fixture-author.md` | Phase 8 / B65 | Builds realistic test data + fixture corpus (Stripe Test Clocks, PayPal sandbox, adversarial fixtures) |
| `subagents/tax-implementer.md` | Phase 5 / B75 | Implements settlement ledger + Stripe Tax + GAAP-aware reporting |
| `subagents/performance-auditor.md` | T3+ ongoing / B105 | N+1 detection, query plan analysis, index review, connection pool sizing |
| `subagents/marketplace-implementer.md` | B115 | Implements Stripe Connect / marketplace patterns (connected accounts, fee splits) |
| `subagents/dispute-defender.md` | T2+ / B125 | Implements full dispute defense (auto-evidence, Radar, per-reason templates, KPI dashboard) |
| `subagents/knowledge-transfer.md` | onboarding | 4-week curriculum + trust ladder + buddy system for new engineers |

## Assets

| Asset | Purpose |
|-------|---------|
| `assets/intake-prompt.md` | Use at very start of skill invocation to gather inputs |
| `assets/postmortem-template.md` | Copy to `<project>/docs/postmortems/<date>-<name>.md` |
| `assets/runbook-template.md` | Copy to `<project>/docs/runbooks/<name>.md` |
| `assets/key-custody-template.md` | Copy to `.billing_workspace/phase10_key_custody.md` |
| `assets/evidence-pack-readme-template.md` | Copy to `.billing_workspace/phase10_evidence_pack/README.md` |

---

## Self-Test

Trigger phrases that should activate this skill:

- "Audit my Stripe webhook code for security issues"
- "We had a duplicate-charge incident — help me harden the billing system"
- "Implement Stripe + PayPal subscriptions in this Next.js project from scratch"
- "Add team plans with seat-based pricing and pause/resume to our billing"
- "Build the MRR / churn / cohort reporting backend for our SaaS"
- "Add a dunning ladder with grace period and SCA routing"
- "Migrate from Lemon Squeezy to dual Stripe + PayPal"
- "Why does our PayPal `subscription.cancelled` handler revive cancelled orgs?"
- "Set up a webhook reconciliation cron with advisory locks"
- "We need to pass SOC2 — audit our billing secret custody"
- "The new admin events feed shows test signups as new subscribers — fix the analytics exclusions"
- "Add real-DB integration tests for our billing code (no mocks)"

Trigger-phrase probe + smoke test on a tiny project: [SELF-TEST.md](SELF-TEST.md).
