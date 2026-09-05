---
name: user-support-triage-for-saas-and-open-source-projects
description: >-
  Triage support across any project (DB tickets, GitHub issues, Zendesk,
  Intercom). Use when reviewing tickets, SLA breaches, refunds, hostile users,
  GDPR/CCPA, or onboarding agent-driven support.
---

# User Support Triage — SaaS & Open-Source Projects

## Table of Contents

- [Quick Start (Cold-Start Agent, Read This First)](#quick-start-cold-start-agent-read-this-first)
- [Two Modes (Onboard Once, Triage Forever)](#two-modes-onboard-once-triage-forever)
- [When To Use](#when-to-use)
- [The Confirmation Rule (Non-Negotiable)](#the-confirmation-rule-non-negotiable)
- [Onboarding Phase (Run Once Per Project)](#onboarding-phase-run-once-per-project)
- [Triage Phase (Every Session — 6 Phases + Operators)](#triage-phase-every-session--6-phases--operators)
- [Operator Library (Cognitive Moves For Triage)](#operator-library-cognitive-moves-for-triage)
- [Live Escalation (User Waiting In Real Time)](#live-escalation-user-waiting-in-real-time)
- [Risk-Tier Runbooks (One Click Away)](#risk-tier-runbooks-one-click-away)
- [Operationalization Quality Gates](#operationalization-quality-gates)
- [Anti-Patterns (Hard-Won, Generalized From Real Incidents)](#anti-patterns-hard-won-generalized-from-real-incidents)
- [Companion Skills](#companion-skills)
- [References](#references)
- [When NOT to Use This Skill](#when-not-to-use-this-skill)
- [Self-Test](#self-test)

## Quick Start (Cold-Start Agent, Read This First)

If you're triaging right now and this project has never been onboarded, **stop and onboard first** — triage without the map produces hallucinated APIs and wrong policies. Otherwise:

```bash
# 1. Confirm the support-triage map exists. If not, run onboarding (see Phase 0-4 below).
test -f <project>/.claude/support-triage/README.md \
  && test -f <project>/.claude/support-triage/01-architecture.md \
  || echo "MISSING: run onboarding first"

# 2. Bootstrap helper skills (idempotent — skips already-installed).
./scripts/check-skills.sh <project>/.claude/support-triage/.workspace
./scripts/install-referenced-skills.sh <project>/.claude/support-triage/.workspace

# 3. Start one full cycle workspace. It fetches ground truth and creates the
#    owner-review draft bundle; it never sends customer messages.
./scripts/triage-cycle.sh <project>

# Optional: validate a project adapter or fire-drill fixture before triage.
python3 ./scripts/validate-adapter-output.py /tmp/open-items.json

# Optional: validate the whole project support map after onboarding.
python3 ./scripts/validate-support-map.py <project>/.claude/support-triage
```

Pick the pipeline by signal (full table in [ORCHESTRATOR-WORKFLOW.md](references/ORCHESTRATOR-WORKFLOW.md)):
- "I get error X when I do Y" → Pipeline A (routine bug)
- "Refund please" → Pipeline B/C (small / >$200)
- "I found a vulnerability" → Pipeline D (security; ESCALATE first, draft later)
- 3+ tickets same fingerprint in 1h → Pipeline E (outage; ONE comms thread, not N replies)
- "GDPR" / "Article 15/17/20" → Pipeline F (DSAR; identity-verify FIRST)
- Insults / "lawsuit" / "regulator" → Pipeline G (hostile; do not mirror tone)
- "Can you add X?" → Pipeline H (feature request; 5–10 min budget)
- "I'm locked out" → Pipeline J (account recovery; identity-verify FIRST)
- "Webhook stopped working" → Pipeline K (integration failure)
- App-store/marketplace review, order dispute, or platform complaint → 🧭 DOMAIN-ADAPT first, then money/public-reply runbooks
- Employee/internal ops request → 🧭 DOMAIN-ADAPT; treat privacy/audit seriously even without external customers
- Healthcare/finance/education/minors/safety-regulated support → regulated mode; no agent-freelanced advice; counsel/compliance owner required
- OSS PR backlog, hostile contributor, or maintainer burnout → Pipeline N/O (OSS-specific; protect contributor time and maintainer bandwidth)
- NPS detractor, cancellation reason, repeated theme, or public mention → Pipeline V/R (VoC mining; turn support evidence into product intelligence)
- 3+ repeated how-to tickets or avoidable confusion → 📚 KB-SUGGEST + deflection loop
- Launch/pricing/migration likely to spike tickets → 🔮 PREDICT + pre-stage templates/comms
- Journalist / press contact → Pipeline T (counsel + comms-led; never agent-freelanced)
- Regulator / formal compliance inquiry → Pipeline U + ⛓ EVIDENCE-CHAIN (legal-hold mode)
- DPA, security questionnaire, custom MSA, enterprise SLA credit → [ENTERPRISE-PLAYBOOKS.md](references/ENTERPRISE-PLAYBOOKS.md); route to legal/security/account owner
- Feature/API/plan/product deprecation or shutdown → [DEPRECATION-AND-SUNSET-COMMS.md](references/DEPRECATION-AND-SUNSET-COMMS.md); account-level impact + migration path
- Customer named harm; refund/credit/upgrade decision → 🎁 GOODWILL (four-dial calculus, not gut feel)
- Stage 3+ rage cycle / repeated ignored-feeling / identity threat → 🪄 EMPATHIZE → 🪜 LADDER (see [CUSTOMER-PSYCHOLOGY.md](references/CUSTOMER-PSYCHOLOGY.md))
- Accessibility barrier, screen-reader issue, low-bandwidth support, or complex formatting → [ACCESSIBILITY-IN-SUPPORT.md](references/ACCESSIBILITY-IN-SUPPORT.md)
- Fraud/ATO/refund-abuse signals → [FRAUD-AND-ABUSE-DETECTION.md](references/FRAUD-AND-ABUSE-DETECTION.md) before any account or money action
- Self-harm, abuse, stalking, violence, or minors-at-risk disclosure → [TRAUMA-INFORMED-SUPPORT.md](references/TRAUMA-INFORMED-SUPPORT.md); stop routine triage
- Deceased user, executor, succession, or family access request → [DECEASED-USER-AND-SUCCESSION.md](references/DECEASED-USER-AND-SUCCESSION.md); verify authority before data/account action

**Hard floor before any send**: `✓ CONFIRM` operator (owner approval) + `🧹 DE-SLOPIFY` pass via the canonical [`/de-slopify`](references/DE-SLOPIFY-INTEGRATION.md) skill on the reply body. Both non-negotiable. Skipping either is the #1 trust-destroyer in real triage sessions.

**Auto-install of `/de-slopify`**: `de-slopify` is marked **REQUIRED** in `scripts/check-skills.sh`. Step 2 of bootstrap (`install-referenced-skills.sh`) installs it FIRST via `jsm install de-slopify` before any optional skill. If `jsm` is missing or unauthenticated, the bootstrap script prints the installer URL and continues — every customer-facing draft must then use the inline AI-tell remover fallback ([VOICE-CALIBRATION.md](references/VOICE-CALIBRATION.md) + [DE-SLOPIFY-INTEGRATION.md](references/DE-SLOPIFY-INTEGRATION.md)) until `jsm install de-slopify` succeeds. The same auto-install path covers every other referenced skill (codebase-archaeology, multi-model-triangulation, idea-wizard, etc.) on a best-effort basis; only `de-slopify` carries the REQUIRED-fail loud-warning.

---

# User Support Triage (SaaS + OSS + Product Support)

> **Core Insight:** User reports are hints, not facts. Triage is verification, not stenography. The first time a project is touched, the skill produces a durable map of *where support lives* — so every later session can dive straight into triage with no rediscovery. Every customer-facing message goes through the **Confirmation Gate** before sending.

---

## Two Modes (Onboard Once, Triage Forever)

```
┌─────────────────────────────────────────────────────────────┐
│  ONBOARDING (one-time per project)                          │
│  ─────────────────────────────                              │
│  Codebase-archaeology + codebase-report applied to the      │
│  *support surface*. Outputs durable docs into the target    │
│  project at  .claude/support-triage/  so future sessions    │
│  load instantly. Ends with a policy-elicitation handshake   │
│  with the owner so refunds/SLAs/voice are codified.         │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  TRIAGE (every session after)                               │
│  ────────────────────────────                               │
│  Read the onboarding map → fetch open items → classify →    │
│  apply operators (★ ORIENT, 🔍 REPRO, ⊕ CORRELATE, ⚖ DECIDE,│
│  ✉ DRAFT, ✓ CONFIRM, 📤 SEND, 🔁 VERIFY) → ask owner for    │
│  approval on every customer-facing send → act → file beads  │
│  → write an outcome record so the map improves next time.   │
└─────────────────────────────────────────────────────────────┘
```

Re-run onboarding only when the support surface changes materially (new ticketing system, new SLA tier, new business policy, new payment provider, new third-party support tool).

---

## When To Use

- "Triage open tickets for `<project>`."
- "Review GitHub issues + PRs on `owner/repo`."
- "Onboard `<project>` to agent-driven support."
- "Map support for a marketplace, mobile app, community, internal tool, agency/client service, or regulated product."
- "User is escalating live and someone needs to investigate before responding."
- "SLA breach alert fired."
- "Refund / billing dispute landed."
- "Security report came in via DM."
- "GDPR/DSAR request received."
- "Hostile / harassing user — what now?"

If the project hasn't been onboarded yet, **always run the onboarding phase first.** Triage without the map produces hallucinated APIs, mis-routed escalations, and wrong response templates.

---

## The Confirmation Rule (Non-Negotiable)

**Never send a customer-facing message without explicit owner approval.** Drafting, classifying, status updates, internal notes, beads — all fine without approval. *Sending* requires `Y/n`.

```
Draft → Show owner all drafts together → Owner edits/approves → Then send.
```

Why: a single confidently-wrong reply destroys more trust than a slow honest one. Confidence-without-evidence is the #1 cited anti-pattern from real triage sessions ([ANTI-PATTERNS.md §10](references/ANTI-PATTERNS.md)).

**Exception**: status-only acknowledgements that stop a SLA clock without sending email *are* OK without approval, because they're not customer-facing. Anything with email-out, public-comment, refund-execution, ban-action, or DM-reply requires approval.

---

## Onboarding Phase (Run Once Per Project)

The onboarding output is `<project>/.claude/support-triage/` — a folder of agent-intuitive markdown that future triage sessions load directly. Template: [assets/ONBOARDING-TEMPLATE.md](assets/ONBOARDING-TEMPLATE.md).

### Phase 0 — Skill Bootstrap (Install Helper Skills via jsm)

This skill composes other skills (codebase-archaeology, codebase-report, github, admin-page-for-nextjs-sites, supabase, stripe-checkout, ga4, saas-customer-analytics, idea-wizard, user-support-ticketing-system-for-saas, e2e-testing-for-webapps, security-audit-for-saas, multi-model-triangulation). Before fan-out:

```bash
./scripts/check-skills.sh /path/to/project/.claude/support-triage/.workspace
```

Writes `skill_inventory.json` with present/missing per skill. If `jsm` is installed + authenticated and the user has an active jeffreys-skills.md subscription:

```bash
./scripts/install-referenced-skills.sh /path/to/project/.claude/support-triage/.workspace
```

If `jsm` is missing, walk the user through install (see [SKILL-INSTALLATION.md](references/SKILL-INSTALLATION.md)). If they don't want a paid subscription, **everything has an inline fallback** — none of the helper skills are prerequisites. The skill always runs end-to-end with just `gh` + `curl` + your existing project tooling.

### Phase 1 — Detect Support Surface

```bash
./scripts/detect-support-surface.sh /path/to/project
# → writes <project>/.claude/support-triage/_detection.json
```

Classifies the project into one or more of:

| Surface | Signal | Playbook |
|---|---|---|
| **github-only** | OSS repo (LICENSE, public visibility), no SaaS deployment | [GITHUB-FORK.md](references/GITHUB-FORK.md) |
| **saas-custom** | Has `support_tickets` / `tickets` / `issues` table or admin support routes | [SAAS-CUSTOM.md](references/SAAS-CUSTOM.md) |
| **saas-third-party** | `ZENDESK_*` / `INTERCOM_*` / `HELPSCOUT_*` / `FRESHDESK_*` / `CRISP_*` / `PLAIN_*` / `LINEAR_*` / `FRONT_*` / `GORGIAS_*` / `HUBSPOT_*` / `SALESFORCE_*` / `JSM_*` / `ZOHO_DESK_*` / `PYLON_*` env vars | [SAAS-THIRD-PARTY.md](references/SAAS-THIRD-PARTY.md) |
| **email** | `SUPPORT_EMAIL` / `support@` / contact form without adapter | [SUPPORT-INTAKE-ROUTER.md](references/SUPPORT-INTAKE-ROUTER.md) + manual-channel cadence |
| **community-manual** | Discord, Slack, forums, Reddit, X/LinkedIn, HN, community spaces | [SUPPORT-INTAKE-ROUTER.md](references/SUPPORT-INTAKE-ROUTER.md) + public/private boundary |
| **marketplace-or-app-store** | Shopify/ecommerce, app stores, marketplace reviews/orders | [SUPPORT-INTAKE-ROUTER.md](references/SUPPORT-INTAKE-ROUTER.md) + platform/order evidence |
| **internal-ops** | employee or operations support rather than external customers | [SUPPORT-INTAKE-ROUTER.md](references/SUPPORT-INTAKE-ROUTER.md) + identity/audit owner |
| **none-yet** | Product has support demand but no durable queue/adapter yet | Offer to scaffold via [`/user-support-ticketing-system-for-saas`](../user-support-ticketing-system-for-saas/SKILL.md). **If owner says yes**: run [`scripts/scaffold-ticketing.sh`](scripts/scaffold-ticketing.sh) — it jsm-installs the ticketing skill plus co-deps (`supabase`, `admin-page-for-nextjs-sites`, `stripe-checkout`), writes a project-context handoff file, and emits `TICKETING-SKILL-STATUS present\|missing` so the agent knows whether to invoke `/user-support-ticketing-system-for-saas` (status=`present`) or fall back to the inline ticketing-design template (status=`missing`). **If no**: document a manual-only cadence and continue triage on whatever surface exists. |

Most non-trivial projects hit multiple surfaces. Run each branch and merge findings into one onboarding doc.

### Phase 2 — Map The Support Surface (codebase-archaeology applied narrowly)

For each detected surface, run the relevant playbook. Each produces a section of the onboarding doc:

```
.claude/support-triage/
├── README.md              ← orientation; what this folder is + how future agents load it
├── 00-intake.md           ← complexity band, routers, owner/source decisions
├── 01-architecture.md     ← codebase-archaeology output focused on support code paths
├── 02-channels.md         ← every place a user can ask for help (multi-channel intake)
├── 03-decision-matrix.md  ← issue-type → action → template (project-specific)
├── 04-templates/          ← response templates customized to brand voice
├── 05-policies.md         ← refund SOP, escalation paths, SLA tiers, business rules
├── 06-recurring-issues.md ← known issues + diagnostic shortcuts
├── 07-secrets.md          ← which env vars to read, which API keys to ask for (NOT the keys)
├── 08-voice.md            ← brand voice: register, sample phrases, do-say/don't-say
├── 09-knowledge-base.md   ← canonical answers; KB articles to link
├── 10-metrics.md          ← FRT/MTTR/CSAT targets and dashboards
├── 11-runbooks/           ← copy-paste runbooks per high-risk category (refund, security, GDPR)
├── 12-gap-dispositions.md ← explicit manual-only / blocked / policy-gap list
├── vocabularies/          ← controlled tags for themes/personas/outcomes when VoC is active
├── artifacts/             ← high-risk evidence, drafts, approvals, sends, verification
├── handoffs/              ← live escalation / migration machine-readable handoffs
└── _detection.json        ← machine-readable surface fingerprint
```

Section templates: [assets/ONBOARDING-TEMPLATE.md](assets/ONBOARDING-TEMPLATE.md). Voice analysis details: [VOICE-CALIBRATION.md](references/VOICE-CALIBRATION.md).

Every surface should eventually expose the universal adapter from
[ADAPTER-CONTRACT.md](references/ADAPTER-CONTRACT.md). The adapter is the
contract that lets this skill triage GitHub, custom DB tickets, and third-party
support tools through one read-only input shape.

### Phase 3 — Resolve Ambiguity With The Owner

Onboarding always finds gaps. Surface them in a single batched prompt — never pester one-at-a-time:

```
🤔 ONBOARDING — POLICY DECISIONS NEEDED

We mapped your support surface but found ambiguity. Pick one for each:

1. SLA on P2 first response — current behavior is "no SLA tracked".
2. Refunds within 14 days — currently handled case-by-case.
3. Feature requests — currently get "thanks, logged" with no follow-up.
4. Hostile user posture — lock-and-block / owner-reviews / soft-decline?
5. Security-disclosure ack template — do you have one?
6. GDPR/DSAR contact and SLA?

Once you choose, we'll write these into 05-policies.md so the next session
can apply them automatically.
```

Full elicitation script: [POLICY-ELICITATION.md](references/POLICY-ELICITATION.md).

### Phase 4 — Wire Outbound Email (If Missing)

If the project sends customer email but `RESEND_API_KEY` (or equivalent) is missing, walk the owner through Resend setup ([RESEND-SETUP.md](references/RESEND-SETUP.md)). Same for Zendesk / Intercom / Help Scout API tokens — ask once, store via the project's existing secrets mechanism, document the *names* (not values) in `07-secrets.md`.

### Onboarding Acceptance

- [ ] `_detection.json` lists every surface
- [ ] `00-intake.md` records complexity band, lifecycle mode, audience segments, routers used, and source anchors for owner answers
- [ ] `02-channels.md` enumerates every place users can ask for help (don't miss email bounces, community/social, app-store/marketplace reviews, sales/customer-success handoffs, or internal ops queues)
- [ ] `03-decision-matrix.md` covers ≥80% of historical ticket categories
- [ ] `05-policies.md` answers: who gets refunded, who gets escalated, what's the SLA, who handles security/legal
- [ ] `07-secrets.md` lists every env var name with a one-line purpose (NEVER the values)
- [ ] `08-voice.md` has 5+ historical reply samples + voice analysis
- [ ] `11-runbooks/` has at least: REFUND, SECURITY-DISCLOSURE, GDPR-DSAR, HOSTILE-USER, OUTAGE-COMMS
- [ ] If the project wants product feedback loops, `vocabularies/themes.md` exists with owner-approved theme tags and a slow-growth policy
- [ ] At least one templated reply per category in `04-templates/`
- [ ] Owner approved the policy decisions from Phase 3
- [ ] `scripts/list-open.sh` returns `support-adapter-v1` JSON or clearly documents why a manual channel remains outside automation
- [ ] `python3 <skill>/scripts/validate-adapter-output.py <open-items.json>` passes for the project adapter
- [ ] At least one routine fire drill and one high-risk fire drill pass with no customer-visible sends
- [ ] `05-policies.md` high-risk rules cite evidence anchors or `TBD-OWNER`
- [ ] `12-gap-dispositions.md` gives every known gap one disposition: confirmed, not-applicable, manual-only, blocked-by-access, provider-gap, policy-gap, evidence-gap, deferred, or unknown
- [ ] High-risk runbooks point to the artifact contract for evidence, draft, approval, send, and verification records
- [ ] `python3 <skill>/scripts/validate-support-map.py <project>/.claude/support-triage` passes, or blockers are recorded with owners

---

## Triage Phase (Every Session — 6 Phases + Operators)

Once onboarded, every triage session follows the 6-phase loop, applying operators within each phase. **Always run in order** — you can't draft without ground truth, can't act without drafts, and the skill does not improve unless outcomes are recorded.

| Phase | Goal | Operators | Output |
|---|---|---|---|
| **1. Ground Truth** | Fetch open items across ALL channels; never trust counts from memory | ★ ORIENT, ⊞ MULTI-CHANNEL | Open-items list + SLA breach list |
| **2. Investigate** | Reproduce each issue against production; verify admin notes still accurate | 🔍 REPRO, ⊕ CORRELATE, ✓ VERSION-PIN | Per-ticket classification + root cause |
| **3. Draft** | Apply decision matrix → templates → batch all drafts together | ⚖ DECIDE, ✉ DRAFT, 🎙 VOICE-MATCH | Draft bundle for owner review |
| **4. Owner Review** | Show every draft. Owner edits or approves. Bulk-acknowledge SLA breaches without messaging | ✓ CONFIRM | Approved drafts |
| **5. Act + Verify** | Send → update status → fix code → file beads → re-fetch to verify completeness | 📤 SEND, 🔁 VERIFY, 🐞 BEAD | Closed loop |
| **6. Outcome** | Capture what changed, what failed, and what should improve | 📈 OUTCOME, 🧬 EVOLVE | Outcome record + bounded improvement proposals |

Full per-phase playbook with surface-specific commands: [TRIAGE-WORKFLOW.md](references/TRIAGE-WORKFLOW.md). Operator library: [OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md).

### Accretive Support Flywheel

The session is not done when the last reply is sent. Phase 6 must route each
meaningful support artifact to one value loop:

| Evidence | Loop | Output |
|---|---|---|
| Repeated how-to / confusion | docs and self-service | KB suggestion, docs issue, in-app copy gap |
| Repeated defect signature | product quality | bug bead with repro and affected cohort |
| Repeated onboarding blocker | activation/retention | onboarding friction note and cohort query |
| Repeated expensive handwork | automation | adapter/script/operator proposal |
| Praise, public quote, high-signal verbatim | positioning/community | keeper record with consent status |
| Hostile/abuse cluster | safety/admin wellbeing | abuse rule, moderation posture, escalation owner |

If no loop applies, record `not-accretive-this-session` in the outcome. Do not
let support evidence disappear into a closed ticket.

### What To Surface vs Just Handle

| Surface to owner (judgment required) | Just handle (mechanical) |
|---|---|
| Refund decisions | SLA breach acknowledgement (status only) |
| Feature scope decisions | Status transitions on confirmed bugs |
| Ambiguous customer demands | Stale-issue closure (pre-cutoff GitHub issues) |
| Anything legal/security-flavored | Duplicates, ack-and-merge |
| Hostile-user lock/ban | Bead creation, internal notes |
| Plan-tier override / comp credit | Internal Slack pings |
| Any *outbound message* | Internal-only audit notes |

---

## Operator Library (Cognitive Moves For Triage)

Adapted from `/operationalizing-expertise` Track A. Each operator has triggers, failure modes, and a copy-paste prompt module. Drop them into your working context per ticket. Full cards: [OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md).

| Symbol | Operator | When |
|---|---|---|
| **🧭 DOMAIN-ADAPT** | Translate the universal loop into the project's support archetype | Before onboarding non-default surfaces or ambiguous project types |
| **★ ORIENT** | Frame the ticket: who, what, urgency, channel, customer tier | Phase 1, every ticket |
| **⊞ MULTI-CHANNEL** | Pull from every channel before responding to any | Phase 1, session start |
| **🔍 REPRO** | Reproduce the user's exact path against production, not a proxy | Phase 2, suspected bugs |
| **⊕ CORRELATE** | Cluster reports by hypothesis before classifying individually | Phase 2, ≥2 open items |
| **✓ VERSION-PIN** | Map user's CLI/app/browser version to the exact fix commit | Phase 2, version-sensitive bugs |
| **⚖ DECIDE** | Apply decision matrix; surface owner-judgment items | Phase 3, every classified item |
| **✉ DRAFT** | Customize template; insert specific evidence | Phase 3, every reply |
| **🎙 VOICE-MATCH** | Match the brand's voice from `08-voice.md` | Phase 3, after drafting |
| **🧹 DE-SLOPIFY** | Run `/de-slopify` (auto-installed via jsm) on every customer-facing draft to remove AI-tells; fall back to inline AI-tell list if skill missing | Phase 3, after VOICE-MATCH; **mandatory non-bypassable** for every send |
| **🪄 EMPATHIZE** | Use mirror/label moves for emotionally loaded tickets; never routine overhead | Stage-3+ rage cycle, refund pain, identity threat |
| **🪜 LADDER** | De-escalate hostile or identity-threatened users before facts/declines | Hostile, public, repeated ignored-feeling cases |
| **🎁 GOODWILL** | Apply compensation dials and owner policy before refund/credit/upgrade offers | Refund, outage, paid-user harm, public apology cases |
| **✓ CONFIRM** | Show all drafts to owner; obtain explicit Y/n | Phase 4, before any send |
| **📤 SEND** | Execute approved replies via the surface's API | Phase 5, after approval |
| **🔁 VERIFY** | Re-fetch open list; confirm nothing missed | Phase 5, end of session |
| **🐞 BEAD** | File a tracking issue for follow-up bugs | Phase 5, confirmed bugs |
| **🛡 ESCALATE** | Move out of the public channel into private/legal | When: security report, legal threat, hostile abuse |
| **🚦 PAUSE-SLA** | Set status `awaiting_customer` to legitimately pause clock | When: question to user, or clarification needed |
| **🔭 ANOMALY** | "Why is this ticket different from the 50 in the same category?" | When: classification matches but instinct says no |
| **📐 EISENHOWER** | Allocate effort by urgency × consequence, not queue order | Large queue, tail-risk signals, owner priority decisions |
| **🔮 PREDICT** | Forecast support demand/capacity before queues breach | Launches, migrations, pricing changes, growing backlog |
| **📚 KB-SUGGEST** | Convert repeated avoidable tickets into docs/in-app/status improvements | Phase 6, repeated how-to/confusion themes |
| **🪧 BROADCAST** | One coordinated incident/status update instead of N conflicting replies | Outages, mass events, provider degradation |
| **🩹 PROACTIVE** | Reach affected silent cohorts before they write in | Known blast radius, churn risk, activation failure |
| **🌐 TRANSLATE** | Route non-English replies through translation; show original | When: customer's language ≠ your voice's language |
| **🪞 SECOND-OPINION** | Run hard cases through `/multi-model-triangulation` (Codex + Gemini + Grok) | When: high-stakes ambiguous; refund > $X; security-flavored |
| **🧪 FIRE-DRILL** | Rehearse routine and high-risk fixtures with no-send guarantees | Onboarding acceptance; after runbook/operator changes |
| **🏷 TAG-CONSISTENCY** | Apply owner-approved theme/persona/outcome vocabulary before close | Phase 6, any project using VoC |
| **💎 KEEPER** | Preserve consented praise/verbatims as product/marketing evidence | Promoter NPS, public praise, unusually good support quotes |
| **🔁 LOOPBACK** | Notify affected reporters when a theme, bug, or docs gap is fixed | Feature shipped, bug fixed, KB article published |
| **📈 OUTCOME** | Write a structured result record after sends/verification | Phase 6, every session |
| **🧬 EVOLVE** | Promote repeated evidence into project docs or operator proposals | After 3+ repeated outcomes or one high-risk failure |

---

## Live Escalation (User Waiting In Real Time)

Stakes are higher when an owner is relaying live customer chat. Different rules:

- **Inventory the working tree** — note overlapping edits before hotfixing, preserve unrelated work, and avoid touching peer-owned files; only overlapping dirty files should change the emergency plan.
- **Relay verbatim quotes** — paraphrased "Too Many Requests" loses the signal that says rate-limit-tier-bug.
- **Assume the first fix surfaces another bug.** Don't send "all fixed!" until the user confirms end-to-end.
- **Schedule a fresh-eyes audit the next day** — hotfixes-under-pressure miss things.

Full protocol: [LIVE-ESCALATION.md](references/LIVE-ESCALATION.md).

---

## Risk-Tier Runbooks (One Click Away)

These are the categories that *must* have a runbook because the cost of getting them wrong is high:

| Runbook | When | Where |
|---|---|---|
| **REFUND** | User requests refund / chargeback risk | [runbooks/REFUND.md](references/runbooks/REFUND.md) |
| **SECURITY-DISCLOSURE** | Vuln report (DM, email, GitHub) | [runbooks/SECURITY-DISCLOSURE.md](references/runbooks/SECURITY-DISCLOSURE.md) |
| **GDPR-DSAR** | Right of access / erasure / portability | [runbooks/GDPR-DSAR.md](references/runbooks/GDPR-DSAR.md) |
| **CCPA** | California / state-level US privacy request | [runbooks/CCPA.md](references/runbooks/CCPA.md) |
| **HOSTILE-USER** | Abuse, harassment, threats | [runbooks/HOSTILE-USER.md](references/runbooks/HOSTILE-USER.md) |
| **OUTAGE-COMMS** | Public incident; status page + customer comms | [runbooks/OUTAGE-COMMS.md](references/runbooks/OUTAGE-COMMS.md) |
| **BILLING-DISCREPANCY** | "I paid but no access" / "still being charged" | [runbooks/BILLING-DEEP.md](references/runbooks/BILLING-DEEP.md) |
| **DATA-LOSS** | Customer reports lost data / corruption | [runbooks/DATA-LOSS.md](references/runbooks/DATA-LOSS.md) |

Each runbook has: trigger conditions, evidence to collect, decision tree, drafts, escalation path, audit-trail template.

---

## Operationalization Quality Gates

Borrowed from `/operationalizing-expertise`: this skill is useful only if future agents can verify where every rule came from and can run the workflow without rediscovering context.

Before declaring a project onboarded:

1. **Evidence anchors exist.** Every non-obvious policy or recurring issue in `05-policies.md` / `06-recurring-issues.md` cites its source: owner answer, code path, ticket id, issue URL, commit SHA, or provider doc URL + access date.
2. **Operator contract is executable.** `scripts/list-open.sh` works for every channel in `02-channels.md`; `scripts/post-reply.sh` is either implemented with the confirmation gate or intentionally exits with a clear "manual send only" message.
3. **Kernel is concise.** `README.md` + `03-decision-matrix.md` should be enough for a cold agent to triage one routine ticket. Deep details live in runbooks and references.
4. **Policy gaps are explicit.** Unknowns are marked `TBD-OWNER`, batched into a single owner prompt, and never silently filled with guesses.
5. **Counter-example tested.** Run at least one routine ticket and one high-risk ticket (refund/security/GDPR/hostile) through the map. If the map does not route both cleanly, onboarding is not done.
6. **Adapter contract validates.** `list-open.sh` output passes [ADAPTER-CONTRACT.md](references/ADAPTER-CONTRACT.md)'s validator, or the channel is documented as manual-only.
7. **Fire drill passes.** New runbooks/operators are rehearsed with [FIRE-DRILL-HARNESS.md](references/FIRE-DRILL-HARNESS.md) before being trusted in live support.
8. **Outcome loop exists.** Every live triage session writes the Phase 6 record from [POST-SEND-OUTCOME.md](references/POST-SEND-OUTCOME.md).
9. **Support map validates.** The project map passes `scripts/validate-support-map.py`, including intake, gap dispositions, artifacts, handoffs, runbooks, adapter capabilities, and dispatch scripts.
10. **Audience and lifecycle are explicit.** Drafts and escalation choices name the audience/persona and lifecycle mode, not just the ticket category.
11. **Pattern probes are used.** Phase 2 investigations check the symptom against the issue-pattern library before accepting a narrow explanation.

When the skill itself is expanded, use the same rule: add operators, validation, or sharper failure modes. Do not add doctrine that gives agents more to read but nothing new to do.

---

## Anti-Patterns (Hard-Won, Generalized From Real Incidents)

These mistakes cost real time and trust. Each maps to a specific failure mode from the corpus.

1. **Trusting reported counts.** "I think there are two tickets" → there were three. Always re-fetch.
2. **Declaring a fix without end-to-end repro.** Individual `curl`s pass; the chained user flow still fails.
3. **First fix is rarely the last.** Plan for iteration; don't close the loop unilaterally.
4. **Failing to correlate before responding.** Two "different" reports often share one root cause.
5. **Quoting stale admin notes.** Old notes reference shipped fixes that didn't actually ship.
6. **Deploy blockers compound under pressure.** Keep workspace + CI green so hotfixes ship instantly.
7. **Tier-blind rate limiting.** Paid users hitting 429s = ticket factory.
8. **Infra problems without a tracking ticket.** "Noted" ≠ resolved.
9. **Internal notes ≠ user notification.** Verify the message actually reaches the user.
10. **Confidence without evidence.** "Yes, this works" with no production reproduction destroys trust irreparably.
11. **Reopen-on-reply for `closed` tickets.** Customer's tangential reply re-opens; SLA "breaches" immediately.
12. **`Math.random()` for ticket IDs.** Real bug: collisions; predictable IDs.
13. **TTY-detection disabling headless fallback.** VPS users locked out of OAuth.
14. **Cron with missing `CRON_SECRET`.** Silent 403s; SLAs untracked.
15. **Auto-deploy disabled in `vercel.json`.** Fix committed, never shipped.
16. **DSAR erasure that leaves audit-log emails.** Incomplete erasure → re-DSAR + complaint.
17. **Public reply to a security report.** Embargo blown; CVE assignment compromised.
18. **Security.txt missing.** Researchers find no responsible-disclosure path; vulns get posted publicly instead.
19. **Public roadmap voting captured by 5 power users.** Misaligns priorities.
20. **Status page "all green" while support queue is 6h backed up.** Monitoring measures uptime not response time.

Full case studies + how to recognize each early: [ANTI-PATTERNS.md](references/ANTI-PATTERNS.md).

---

## Companion Skills

- `/user-support-ticketing-system-for-saas` — scaffold a production-grade in-app ticketing system into a SaaS app that has none. Next.js is the default example; the handoff and adapter contracts are portable.
- `/admin-page-for-nextjs-sites` — broader admin cockpit; ticket triage UI is one slice.
- `/saas-customer-analytics` — churn / segment data informs triage prioritization.
- `/codebase-archaeology` + `/codebase-report` — used inside Onboarding Phase 2.
- `/gh-cli` (`gh`) — used inside the GitHub fork.
- `/multi-model-triangulation` — used by 🪞 SECOND-OPINION operator on hard cases.
- `/security-audit-for-saas` — referenced by SECURITY-DISCLOSURE runbook.
- `/e2e-testing-for-webapps` — used to write regression tests after fixing user-reported bugs.
- `/idea-wizard` — used for FEATURE-REQUEST replies that need a "smaller version we can ship".
- `/cass` — mine prior triage sessions for working patterns.

If a companion skill is not installed, every workflow has an **inline fallback** in this skill's references.

---

## References

### Core
| Need | File |
|---|---|
| Skill bootstrap + jsm install + subscription | [SKILL-INSTALLATION.md](references/SKILL-INSTALLATION.md) |
| Detection + missing-skill matrix | [BOOTSTRAP.md](references/BOOTSTRAP.md) |
| Onboarding doc template | [assets/ONBOARDING-TEMPLATE.md](assets/ONBOARDING-TEMPLATE.md) |
| Universal support adapter contract | [ADAPTER-CONTRACT.md](references/ADAPTER-CONTRACT.md) |
| Support intake router (complexity bands, routers, source discipline) | [SUPPORT-INTAKE-ROUTER.md](references/SUPPORT-INTAKE-ROUTER.md) |
| Evidence packs, handoffs, and gap dispositions | [SUPPORT-EVIDENCE-ARTIFACTS.md](references/SUPPORT-EVIDENCE-ARTIFACTS.md) |
| Triage 6-phase workflow | [TRIAGE-WORKFLOW.md](references/TRIAGE-WORKFLOW.md) |
| Operator library (cognitive moves) | [OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md) |

### Surface forks
| Need | File |
|---|---|
| GitHub issues + PRs via `gh` | [GITHUB-FORK.md](references/GITHUB-FORK.md) |
| SaaS custom DB ticketing | [SAAS-CUSTOM.md](references/SAAS-CUSTOM.md) |
| SaaS third-party (Zendesk/Intercom/Help Scout/Freshdesk/Crisp/Plain/Linear/Front/Gorgias/Pylon) | [SAAS-THIRD-PARTY.md](references/SAAS-THIRD-PARTY.md) |
| Email/community/marketplace/internal/manual channels | [SUPPORT-INTAKE-ROUTER.md](references/SUPPORT-INTAKE-ROUTER.md) + [ADAPTER-CONTRACT.md](references/ADAPTER-CONTRACT.md) |

### Decision support
| Need | File |
|---|---|
| Generic decision matrix | [DECISION-MATRIX.md](references/DECISION-MATRIX.md) |
| Generic response templates | [RESPONSE-TEMPLATES.md](references/RESPONSE-TEMPLATES.md) |
| Owner policy elicitation | [POLICY-ELICITATION.md](references/POLICY-ELICITATION.md) |
| Voice calibration (matching brand voice) | [VOICE-CALIBRATION.md](references/VOICE-CALIBRATION.md) |
| Failure-mode catalog (40+) | [FAILURE-MODES.md](references/FAILURE-MODES.md) |
| Anti-patterns (case studies) | [ANTI-PATTERNS.md](references/ANTI-PATTERNS.md) |
| Support issue pattern probes | [SUPPORT-ISSUE-PATTERN-LIBRARY.md](references/SUPPORT-ISSUE-PATTERN-LIBRARY.md) |
| Live escalation protocol | [LIVE-ESCALATION.md](references/LIVE-ESCALATION.md) |
| Multi-model triangulation for hard cases | [MULTI-MODEL.md](references/MULTI-MODEL.md) |
| Resend / outbound-email setup | [RESEND-SETUP.md](references/RESEND-SETUP.md) |
| AI auto-response governance and action tiers | [AI-AUTO-RESPONSE-GOVERNANCE.md](references/AI-AUTO-RESPONSE-GOVERNANCE.md) |
| `/de-slopify` integration: REQUIRED auto-install + mandatory pre-send pass | [DE-SLOPIFY-INTEGRATION.md](references/DE-SLOPIFY-INTEGRATION.md) |
| Customer psychology and rage-cycle mechanics | [CUSTOMER-PSYCHOLOGY.md](references/CUSTOMER-PSYCHOLOGY.md) |
| Tactical empathy moves for loaded conversations | [TACTICAL-EMPATHY.md](references/TACTICAL-EMPATHY.md) |
| Compensation/refund/credit/upgrade calculus | [COMPENSATION-CALCULUS.md](references/COMPENSATION-CALCULUS.md) |
| Crisis comms when support becomes public | [CRISIS-COMMS.md](references/CRISIS-COMMS.md) |
| Deprecation and sunset communications | [DEPRECATION-AND-SUNSET-COMMS.md](references/DEPRECATION-AND-SUNSET-COMMS.md) |
| Deflection and self-service economics | [DEFLECTION-AND-SELF-SERVICE.md](references/DEFLECTION-AND-SELF-SERVICE.md) |
| Pareto/head-vs-tail triage strategy | [PARETO-AND-LONG-TAIL.md](references/PARETO-AND-LONG-TAIL.md) |
| Proactive support and silent-cohort outreach | [PROACTIVE-SUPPORT.md](references/PROACTIVE-SUPPORT.md) |
| Support forecasting and capacity planning | [SUPPORT-FORECASTING.md](references/SUPPORT-FORECASTING.md) |
| OSS maintainer/contributor sustainability | [OSS-MAINTAINER-PROTECTION.md](references/OSS-MAINTAINER-PROTECTION.md) |
| Evidence chain-of-custody for legal/regulator/press cases | [EVIDENCE-CHAIN-OF-CUSTODY.md](references/EVIDENCE-CHAIN-OF-CUSTODY.md) |
| Enterprise support: DPA, security questionnaires, MSAs, custom SLAs | [ENTERPRISE-PLAYBOOKS.md](references/ENTERPRISE-PLAYBOOKS.md) |
| Accessibility-aware support formatting and channels | [ACCESSIBILITY-IN-SUPPORT.md](references/ACCESSIBILITY-IN-SUPPORT.md) |
| Fraud, account-takeover, refund abuse, and support-channel attacks | [FRAUD-AND-ABUSE-DETECTION.md](references/FRAUD-AND-ABUSE-DETECTION.md) |
| Internationalization, locale, and cultural calibration | [INTERNATIONALIZATION-AND-LOCALE.md](references/INTERNATIONALIZATION-AND-LOCALE.md) |
| Multi-tier support organizations: L1/L2/L3, swarming, follow-the-sun | [MULTI-TIER-SUPPORT-ORG.md](references/MULTI-TIER-SUPPORT-ORG.md) |
| QA shadow review for support quality and coaching | [QA-SHADOW-REVIEW.md](references/QA-SHADOW-REVIEW.md) |
| Observability-driven triage: errors, logs, traces, silent cohorts | [OBSERVABILITY-DRIVEN-TRIAGE.md](references/OBSERVABILITY-DRIVEN-TRIAGE.md) |
| Ticket lifecycle states beyond open/closed | [TICKET-LIFECYCLE-STATES.md](references/TICKET-LIFECYCLE-STATES.md) |
| Trauma-informed crisis support | [TRAUMA-INFORMED-SUPPORT.md](references/TRAUMA-INFORMED-SUPPORT.md) |
| Triage scoreboard: metrics that improve support instead of gaming it | [TRIAGE-SCOREBOARD.md](references/TRIAGE-SCOREBOARD.md) |

### Risk-tier runbooks
| Need | File |
|---|---|
| Refund execution + drafts | [runbooks/REFUND.md](references/runbooks/REFUND.md) |
| Security disclosure | [runbooks/SECURITY-DISCLOSURE.md](references/runbooks/SECURITY-DISCLOSURE.md) |
| GDPR / DSAR | [runbooks/GDPR-DSAR.md](references/runbooks/GDPR-DSAR.md) |
| CCPA / state privacy | [runbooks/CCPA.md](references/runbooks/CCPA.md) |
| Hostile user / harassment | [runbooks/HOSTILE-USER.md](references/runbooks/HOSTILE-USER.md) |
| Outage communication | [runbooks/OUTAGE-COMMS.md](references/runbooks/OUTAGE-COMMS.md) |
| Billing discrepancy / chargeback | [runbooks/BILLING-DEEP.md](references/runbooks/BILLING-DEEP.md) |
| Data loss / corruption | [runbooks/DATA-LOSS.md](references/runbooks/DATA-LOSS.md) |

### Lifecycle
| Need | File |
|---|---|
| Knowledge-base integration | [KNOWLEDGE-BASE.md](references/KNOWLEDGE-BASE.md) |
| Metrics + dashboards (FRT/MTTR/CSAT/NPS) | [METRICS-AND-DASHBOARDS.md](references/METRICS-AND-DASHBOARDS.md) |
| Audience, lifecycle, and support feedback loops | [AUDIENCE-LIFECYCLE-FEEDBACK.md](references/AUDIENCE-LIFECYCLE-FEEDBACK.md) |
| Post-incident retros | [POST-INCIDENT-RETRO.md](references/POST-INCIDENT-RETRO.md) |
| Knowledge-base feedback loop | [KB-FEEDBACK-LOOP.md](references/KB-FEEDBACK-LOOP.md) |
| Status page integration | [STATUS-PAGE.md](references/STATUS-PAGE.md) |
| Voice-of-customer loop from support to roadmap | [VOICE-OF-CUSTOMER-LOOP.md](references/VOICE-OF-CUSTOMER-LOOP.md) |
| Replayable fire-drill harness | [FIRE-DRILL-HARNESS.md](references/FIRE-DRILL-HARNESS.md) |
| Post-send outcome loop | [POST-SEND-OUTCOME.md](references/POST-SEND-OUTCOME.md) |
| Operator evolution from evidence | [OPERATOR-EVOLUTION.md](references/OPERATOR-EVOLUTION.md) |
| Dueling-wizards improvement synthesis | [DUELING-WIZARDS-REPORT.md](references/DUELING-WIZARDS-REPORT.md) |

### Composition / Craft
| Need | File |
|---|---|
| Operator-chaining cookbook (11 named pipelines) | [ORCHESTRATOR-WORKFLOW.md](references/ORCHESTRATOR-WORKFLOW.md) |
| Communication craft (apology / decline / uncertainty) | [COMMUNICATION-CRAFT.md](references/COMMUNICATION-CRAFT.md) |
| Beads (br) integration for triage backlog | [BEADS-INTEGRATION.md](references/BEADS-INTEGRATION.md) |
| Account recovery / lost-access runbook | [runbooks/ACCOUNT-RECOVERY.md](references/runbooks/ACCOUNT-RECOVERY.md) |
| Integration-failure runbook (webhook / SDK / OAuth) | [runbooks/INTEGRATION-FAILURE.md](references/runbooks/INTEGRATION-FAILURE.md) |
| Deceased user and account succession protocol | [DECEASED-USER-AND-SUCCESSION.md](references/DECEASED-USER-AND-SUCCESSION.md) |

## Scripts

| Script | Purpose |
|---|---|
| `scripts/check-skills.sh <workspace>` | Inventory referenced helper skills + jsm + subscription |
| `scripts/install-referenced-skills.sh <workspace>` | Bulk `jsm install` missing skills |
| `scripts/detect-support-surface.sh <project>` | Classify project surface; emit `_detection.json` |
| `scripts/scaffold-onboarding.sh <project>` | Create `<project>/.claude/support-triage/` skeleton |
| `scripts/list-open-items.sh <project>` | Dispatch to surface-specific listing (gh / curl admin / Zendesk API) |
| `scripts/triage-cycle.sh <project>` | Start a triage session workspace: ground-truth fetch + draft bundle skeleton; no customer sends |
| `scripts/validate-adapter-output.py <open-items.json>` | Validate `support-adapter-v1` output or fire-drill fixtures |
| `scripts/validate-support-map.py <project>/.claude/support-triage` | Validate onboarding map files, runbooks, artifacts, handoffs, gaps, and adapter capabilities |

## Subagents

| Subagent | Purpose |
|---|---|
| `subagents/onboarding-cartographer.md` | Phase 2 of onboarding: maps a single surface and writes the section |
| `subagents/voice-analyst.md` | Reads 5+ historical replies; extracts voice signature into `08-voice.md` |
| `subagents/correlator.md` | Phase 2 of triage: clusters open tickets by hypothesis |
| `subagents/draft-bundler.md` | Phase 3: produces the owner-review draft bundle |

## When NOT to Use This Skill

| Symptom | Use this instead |
|---|---|
| User wants the system *built* (DB schema, SLA engine, admin UI, outbound-email wiring) | `/user-support-ticketing-system-for-saas` — that skill *creates* the queue this skill *operates* |
| Specific to one project's policies / runbooks | The project's own `<project>/.claude/support-triage/` — this skill *populates* that folder during onboarding |
| Generic GitHub issue/PR triage on OSS without customer context | `/gh-triage-ru` — leaner, no customer-comms layer |
| Removing AI-tells from drafts | `/de-slopify` — invoke directly on the draft body |
| Polishing the team's voice signature offline | `/readme-writing` — has a parallel voice-section pattern |
| Cross-project pattern extraction across many projects | `/codebase-pattern-extraction` — meta-level, runs above triage |
| Mining session history for "what did I ask?" | `/cass` — read-only, no triage actions |

The skill is appropriate when there is (a) a real user inbound, (b) a project owner who can approve sends, and (c) a need to ship action plus reply within an SLA. If any are missing, route accordingly.

## Self-Test

Should activate this skill:
- "Triage open tickets for my SaaS"
- "Onboard this project to agent-driven support"
- "Review GitHub issues on owner/repo"
- "User just reported they can't log in — investigate"
- "SLA breach alert; what do I do"
- "Customer is asking for a refund — walk me through it"
- "Someone DM'd a vulnerability — handle it"
- "We got a GDPR DSAR; respond"
- "Hostile user is spamming our Discord; what's the playbook"
- "Map support for our app-store reviews and marketplace order complaints"
- "Triage employee support requests for an internal ops tool"

Should NOT activate this skill (route accordingly):
- "Build the ticketing system / SLA engine / admin queue from scratch" → `/user-support-ticketing-system-for-saas`
- "Polish this draft for tone before sending" → `/de-slopify` (this skill calls `/de-slopify`; doesn't replace it)
- "OSS-only GitHub triage with no customer-comms layer" → `/gh-triage-ru`
- "Mine prior triage sessions for what I asked" → `/cass`
- "Pattern extraction across many projects" → `/codebase-pattern-extraction`
- "Generic README polish on the project's voice section" → `/readme-writing`

Pre-flight smoke (every triage session):

```bash
# Map exists? If not, the next call should be onboarding, not triage.
ls <project>/.claude/support-triage/01-architecture.md 2>/dev/null \
  && echo "ONBOARDED — proceed to Phase 1 of triage" \
  || echo "NOT ONBOARDED — run scripts/detect-support-surface.sh and onboarding first"

# Bootstrap helpers (idempotent)
./scripts/check-skills.sh <project>/.claude/support-triage/.workspace
```

If the map is missing, **stop and onboard first**. Triage without the map produces hallucinated APIs, wrong policies, and mis-routed escalations.
