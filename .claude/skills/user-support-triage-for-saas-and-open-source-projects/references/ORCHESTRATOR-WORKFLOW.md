# Orchestrator Workflow — Composing Operators Into Real Triage

The operator library (`OPERATOR-LIBRARY.md`) defines the registered triage operators. This file shows how to **chain them** into actual end-to-end triage flows for the cases that recur most. Use this as the cookbook the orchestrator (you, the agent) consults when picking the next operator to invoke.

## The Six-Phase Backbone

Every ticket flows through six phases, regardless of category. Skipping one is the most common mistake:

```
1. GROUND TRUTH    Who/when/what tier; pull the actual artifacts
2. INVESTIGATE     Repro / version-pin / correlate
3. DRAFT           Decide → draft reply → match voice
4. OWNER REVIEW    Confirm → bundle → owner sign-off
5. ACT + VERIFY    Send → status update → verify resolution → bead the followup
6. OUTCOME         Tag themes, capture learning, propose compounding fixes
```

Operators slot into phases:

| Phase | Required operators | Optional |
|---|---|---|
| 1 | ★ ORIENT, ⊞ MULTI-CHANNEL | 📐 EISENHOWER, 🔮 PREDICT |
| 2 | 🔍 REPRO, ✓ VERSION-PIN, ⊕ CORRELATE | 🔭 ANOMALY, 🪞 SECOND-OPINION |
| 3 | ⚖ DECIDE, ✉ DRAFT, 🎙 VOICE-MATCH | 🛡 ESCALATE, 🚦 PAUSE-SLA, 🌐 TRANSLATE, 🪄 EMPATHIZE, 🪜 LADDER, 🎁 GOODWILL |
| 4 | ✓ CONFIRM | 🪞 SECOND-OPINION |
| 5 | 📤 SEND, 🔁 VERIFY, 🐞 BEAD | — |
| 6 | 🏷 TAG-CONSISTENCY, 📈 OUTCOME | 📚 KB-SUGGEST, 🪧 BROADCAST, 🩹 PROACTIVE, 💎 KEEPER, 🔁 LOOPBACK, 🧬 EVOLVE |

The required operators are non-negotiable. The optional ones fire on conditions described in their cards.

## Standard Pipelines

### Pipeline A: Routine Bug Report (Tier-Free / Individual)

```
★ ORIENT
  → ⊞ MULTI-CHANNEL (already in queue, single source)
  → 🔍 REPRO (try locally; succeed/fail)
  → ✓ VERSION-PIN (note user's vs current vs deploy)
  → ⊕ CORRELATE (siblings? recent commits?)
  → ⚖ DECIDE (known vs new; fix-now vs backlog)
  → ✉ DRAFT
  → 🎙 VOICE-MATCH
  → ✓ CONFIRM (routine batch-review — included in owner bundle)
  → 📤 SEND
  → 🐞 BEAD (if backlog)
  → 🔁 VERIFY (within 48h)
```

Time budget: 20-40 min start to send. Routine path; should compose smoothly.

### Pipeline B: Refund Request (≤ $X policy threshold)

```
★ ORIENT
  → ⊞ MULTI-CHANNEL
  → 🔍 REPRO (only if claim involves a defect)
  → 🚦 PAUSE-SLA (probably not; refund tickets stay active)
  → ⊕ CORRELATE (subscription status? recent transactions?)
  → ⚖ DECIDE (within statutory window? within tier policy?)
  → ✉ DRAFT (use refund-grant or refund-decline template)
  → 🎙 VOICE-MATCH
  → ✓ CONFIRM (HOLD for owner if amount > policy threshold)
  → [owner reviews → approves]
  → 📤 SEND (if granted: also issue refund via Stripe/PayPal first, THEN send confirmation)
  → 🔁 VERIFY (refund settled? customer acknowledged?)
  → 🐞 BEAD (refund metric for monthly review)
```

Critical sequencing: refund the money before saying you refunded it. Customer who reads "we refunded you" but checks their statement and sees nothing → second ticket, far angrier.

### Pipeline C: Refund Request (> $X — high-stakes)

```
★ ORIENT
  → ⊞ MULTI-CHANNEL
  → ⊕ CORRELATE (full payment history; cross-provider check per BILLING-DEEP)
  → ⚖ DECIDE
  → 🪞 SECOND-OPINION (multi-model; cost ~$0.10)
  → ✉ DRAFT
  → 🎙 VOICE-MATCH
  → ✓ CONFIRM (owner sign-off mandatory)
  → 📤 SEND
  → 🔁 VERIFY
  → 🐞 BEAD (postmortem if pattern; per POST-INCIDENT-RETRO if > $500)
```

### Pipeline D: Security Disclosure

```
★ ORIENT
  → ⊞ MULTI-CHANNEL (security@ vs in-app vs Twitter — confirm no leak)
  → 🛡 ESCALATE (immediately to owner; security goes off-band)
  → 🚦 PAUSE-SLA (security has its own SLA — see runbook)
  → 🔍 REPRO (carefully, in isolated environment)
  → ⊕ CORRELATE (CVE database? prior disclosure?)
  → 🪞 SECOND-OPINION (if severity unclear, multi-model on the PoC)
  → ⚖ DECIDE (severity / fix path / disclosure timeline)
  → ✉ DRAFT (security ack template; do NOT discuss specifics in unencrypted email)
  → 🎙 VOICE-MATCH (formal register, not warm-casual)
  → ✓ CONFIRM (owner)
  → 📤 SEND (encrypted channel preferred)
  → 🐞 BEAD (CVE assignment, fix tracking, disclosure timeline)
  → 🔁 VERIFY (fix shipped? reporter confirmed?)
```

Skipping the ESCALATE early is the #1 security-handling mistake. Owner needs to know within hours, not at the end of triage.

### Pipeline E: Outage (Multiple Customer Reports)

```
[trigger: 3+ reports same fingerprint within 1h]
  → 🔭 ANOMALY (confirm spike vs noise)
  → 🛡 ESCALATE (immediate; status page + owner + on-call)
  → ★ ORIENT (treat as ONE incident, not N tickets)
  → ⊕ CORRELATE (root cause across reports; recent deploy?)
  → ⚖ DECIDE (rollback / forward fix / monitoring-only)
  → ✉ DRAFT (status-page update + customer email template)
  → ✓ CONFIRM (owner)
  → 📤 SEND (status page first, then individual ticket replies linking to it)
  → 🔁 VERIFY (incident resolved across all affected)
  → 🐞 BEAD (postmortem — mandatory)
```

Per-ticket triage during an outage is the wrong default — bundle all into one comms thread.

### Pipeline F: GDPR DSAR

```
★ ORIENT
  → ⊞ MULTI-CHANNEL (single source; ack receipt)
  → 🚦 PAUSE-SLA (has its own 30-day clock — set the clock explicitly)
  → ⚖ DECIDE (verify identity first per GDPR runbook)
  → ✉ DRAFT (verification request template)
  → ✓ CONFIRM
  → 📤 SEND (initial: identity-verify request)
  → [wait for user to verify]
  → ⚖ DECIDE (which Article — 15 / 17 / 20 — full scope)
  → 🔍 REPRO → here it's "execute the export/erasure script"
  → ✉ DRAFT (deliverable + receipt)
  → ✓ CONFIRM (legal hold check — owner)
  → 📤 SEND (encrypted attachment; data only via authenticated portal)
  → 🐞 BEAD (compliance log entry; 7-year retention)
  → 🔁 VERIFY (within 30-day deadline; user acknowledged)
```

### Pipeline G: Hostile User

```
★ ORIENT (assess severity per HOSTILE-USER L0-L6 scale)
  → 🛡 ESCALATE (any L3+ → owner immediately, do not engage)
  → 🚦 PAUSE-SLA (only after L4+; otherwise standard SLAs apply)
  → ⊕ CORRELATE (account history; prior tickets; ToS history)
  → ⚖ DECIDE (de-escalation level; suspension warranted?)
  → ✉ DRAFT (formal, factual, do NOT mirror tone — see HOSTILE-USER drafts)
  → 🎙 VOICE-MATCH (mode-shift to formal-de-escalation per VOICE-CALIBRATION)
  → ✓ CONFIRM (owner mandatory at L3+)
  → 📤 SEND
  → 🐞 BEAD (preserve evidence; document for legal record)
  → 🔁 VERIFY (response? escalation? quiet?)
```

### Pipeline H: Feature Request

```
★ ORIENT
  → ⚖ DECIDE (yes-now / yes-later / no — is it on roadmap?)
  → ✉ DRAFT (acknowledge + redirect; do NOT promise unless owner pre-cleared)
  → 🎙 VOICE-MATCH
  → ✓ CONFIRM (routine batch-review only if "no, here's why" / "noted, will track")
  → 📤 SEND
  → 🐞 BEAD (product backlog with feature-request label)
```

Time budget: 5-10 min. Don't over-invest. If you need /idea-wizard, that's a sign the request deserves owner attention.

### Pipeline I: Pre-Sales / Eval Question

```
★ ORIENT (pricing / fit / competitor question)
  → ⚖ DECIDE (in-scope for support? or route to sales?)
  → ✉ DRAFT (factual product info; do NOT push)
  → ✓ CONFIRM
  → 📤 SEND
  → 🐞 BEAD (pre-sales lead tag for sales attention)
```

Don't soft-pitch. The customer asked a question; answer it.

### Pipeline J: Account Recovery / Lost Access

```
★ ORIENT
  → ⊕ CORRELATE (audit log: when did access fail? deploy? auth migration?)
  → ⚖ DECIDE (verify identity per recovery policy)
  → ✉ DRAFT (verification step — magic link to email of record)
  → 📤 SEND
  → [wait for verify]
  → ⚖ DECIDE (root cause — password reset / SSO breakage / suspension / etc.)
  → ✉ DRAFT (resolution + steps + verify)
  → ✓ CONFIRM
  → 📤 SEND
  → 🔁 VERIFY (user signed in? confirmed in reply?)
```

Identity-verify FIRST. Skipping this is how account-takeover incidents start.

### Pipeline K: Integration Failure (Third-Party)

```
★ ORIENT
  → 🔍 REPRO
  → ✓ VERSION-PIN (their integration version; our API version)
  → ⊕ CORRELATE (recent API changes? webhook format change? rate-limit change?)
  → ⚖ DECIDE (their bug / our bug / mutual misunderstanding)
  → ✉ DRAFT (cite specific endpoint / payload / timestamp)
  → 🎙 VOICE-MATCH (terse-technical for dev-tools)
  → ✓ CONFIRM
  → 📤 SEND
  → 🔁 VERIFY (integration restored?)
```

### Pipeline L: Forecast / Mass-Event Preparedness

```
[trigger: launch, pricing change, migration, or queue trend]
  → 🔮 PREDICT (last 90d counts + event bump + capacity)
  → 📐 EISENHOWER (reserve head/tail/compounding capacity)
  → 📚 KB-SUGGEST (pre-stage top confusion docs/templates)
  → 🪧 BROADCAST (stage status/product-banner copy if event-risk is high)
  → ✓ CONFIRM (owner approves launch-support plan)
  → 📈 OUTCOME (forecast vs actual after event)
```

### Pipeline N: OSS PR Review / Maintainer Protection

```
★ ORIENT (issue/PR type, contributor history, policy fit)
  → 📐 EISENHOWER (drive-by/head vs consequential/tail)
  → ⚖ DECIDE (accept, request changes, redirect, close, or fork guidance)
  → ✉ DRAFT (use OSS-MAINTAINER-PROTECTION.md templates)
  → 🎙 VOICE-MATCH (maintainer voice; direct, warm, bounded)
  → ✓ CONFIRM (owner/maintainer if policy-sensitive)
  → 📤 SEND (gh comment/close/label)
  → 🏷 TAG-CONSISTENCY + 📈 OUTCOME (policy or docs friction)
```

### Pipeline O: Drive-By Hostile Contributor

```
★ ORIENT (is this issue/PR conflict, behavior issue, or legal/security?)
  → 🪜 LADDER (only if L0-L2 and still solvable)
  → 🛡 ESCALATE (L3+ harassment, legal, CoC, trademark, threat)
  → ⚖ DECIDE (policy citation; contribution decision separate from behavior)
  → ✉ DRAFT (short, factual, no thread debate)
  → ✓ CONFIRM (maintainer/owner)
  → 📤 SEND
  → 📈 OUTCOME (maintainer-protection policy gap if any)
```

### Pipeline P: Proactive Customer Outreach

```
[trigger: known affected cohort or churn/activation signal]
  → 🩹 PROACTIVE (cohort, ethics check, channel, help offer)
  → 🎁 GOODWILL (if harm/incident compensation may be appropriate)
  → ✉ DRAFT
  → 🎙 VOICE-MATCH
  → ✓ CONFIRM
  → 📤 SEND
  → 🔁 VERIFY (delivery + replies routed)
  → 📈 OUTCOME (reach rate / reverse-CSAT / retention signal)
```

### Pipeline Q: High-Consequence Tail Ticket

```
★ ORIENT (long-tail signals: ARR, press, regulator, public, data loss, identity threat)
  → 📐 EISENHOWER (promote out of head strategy)
  → 🪞 SECOND-OPINION (what are we missing?)
  → 🔍 REPRO / ⊕ CORRELATE (deep evidence pack)
  → 🎁 GOODWILL (if relationship repair is needed)
  → ✉ DRAFT + 🪄 EMPATHIZE / 🪜 LADDER as appropriate
  → ✓ CONFIRM (owner directly involved)
  → 📤 SEND
  → 🔁 VERIFY + 📈 OUTCOME + 🧬 EVOLVE
```

### Pipeline R: NPS / CSAT Detractor

```
★ ORIENT (score, verbatim, account tier, recent tickets, churn risk)
  → 🏷 TAG-CONSISTENCY (theme + persona)
  → 🎁 GOODWILL (only if harm/fault warrants outreach/credit)
  → 🩹 PROACTIVE (owner-led follow-up)
  → ✉ DRAFT (short, personal, quotes their words)
  → ✓ CONFIRM
  → 📤 SEND
  → 💎 KEEPER (verbatim internal-only unless consent)
  → 📈 OUTCOME
```

### Pipeline T: Press / Journalist Inquiry

```
★ ORIENT (deadline, topic, outlet, public/private facts)
  → 🛡 ESCALATE (owner + comms/counsel; Tier 4)
  → ⚖ DECIDE (ack only vs substantive response; agent does not freelance)
  → ✉ DRAFT (optional holding-statement starting point)
  → ✓ CONFIRM (human-led)
  → 📤 SEND only if explicitly approved by owner/comms
  → 📈 OUTCOME (audit trail)
```

### Pipeline U: Regulator / Legal / Compliance Inquiry

```
★ ORIENT (verbatim inquiry, sender identity, deadline, jurisdiction)
  → 🛡 ESCALATE (counsel-led immediately)
  → SUPPORT-EVIDENCE-ARTIFACTS.md evidence pack
  → no customer/public drafting until cleared
  → ✓ CONFIRM for every written acknowledgement
  → 📈 OUTCOME (restricted-access summary, no legal analysis beyond counsel)
```

### Pipeline V: Voice-of-Customer Mining

```
[trigger: weekly/monthly synthesis or repeated themes]
  → 🏷 TAG-CONSISTENCY (normalize ticket/NPS/cancel/public tags)
  → 📚 KB-SUGGEST (docs/in-app/status surface candidates)
  → 💎 KEEPER (verbatims worth preserving)
  → 🧬 EVOLVE (theme → product/docs/runbook/operator proposal)
  → 🔁 LOOPBACK (when shipped fixes are ready)
  → 📈 OUTCOME (or monthly VoC synthesis)
```

### Pipeline W: Crisis / Safety Inbound

```
[trigger: ⛔ RED-FLAGS detect self-harm / abuse / threats /
child-endangerment / acute mental-health crisis disclosure]
  → 🛟 RESCUE (recognize + halt standard pipeline)
  → 🛡 ESCALATE (owner + specialist; out-of-band notification)
  → 🎚 LIFECYCLE-STATE (set crisis-hold; suspend automation)
  → For self-harm/suicide signals SPECIFICALLY:
       send owner-pre-approved crisis-resource pointer
       within project's crisis-SLA (often <1h);
       NEVER agent-generated text
  → ⛓ EVIDENCE-CHAIN (privileged retention of disclosure;
       not in clear-text ticket history)
  → 🚦 PAUSE-SLA (clock paused; no automated nudges)
  → If mandatory-reporting category (CSAM, imminent threat to
       identifiable person, child endangerment): qualified owner/counsel
       decides and files where legally required; agent flags only
  → After clearance: 🪜 LADDER tone for any returning ticket-substance work;
       compensation calculus via 🎁 GOODWILL with grief / trauma multiplier
  → 📈 OUTCOME (with disclosure detail in privileged store; not the
       standard outcome record)
```

Critical rule: zero agent-generated substantive replies on crisis content.
Out-of-scope ticket business is paused, not rushed, until qualified owner
or specialist clearance returns the conversation to ordinary support scope.

### Pipeline X: Fraud / ATO Investigation

```
[trigger: 🕵 FRAUD-CHECK score ≥ 4, or any ATO-shape recovery /
refund-abuse signal]
  → 🕵 FRAUD-CHECK (compute multi-signal risk score; document)
  → 🎚 LIFECYCLE-STATE (freeze account if ≥ 6; investigating otherwise)
  → ⊕ CORRELATE (account history; payment-method linkage; device
       fingerprint; multi-account clustering)
  → ⛓ EVIDENCE-CHAIN (preserve evidence in case of chargeback dispute)
  → ⚖ DECIDE (friendly-fraud vs intentional-fraud; cite signals)
  → For ATO-shape: NEVER change auth factors solely on possession;
       require independent-channel verification on a factor that
       EXISTED BEFORE the request
  → For refund-abuse: present evidence calmly; do not capitulate
       to chargeback threats; do not accuse
  → ✉ DRAFT (calibrated; per FRAUD-AND-ABUSE-DETECTION.md patterns)
  → 🪞 SECOND-OPINION (high-stakes; especially marginal cases)
  → ✓ CONFIRM (owner; mandatory for freeze / decline / counter-claim)
  → 📤 SEND (or refer to chargeback dispute process)
  → 🔁 VERIFY (account state correct; future-attempt detection in place)
  → 🐞 BEAD (pattern; aggregate to monthly fraud review)
```

Aggregate calls in monthly review: were thresholds too tight (lost legit
users) or too loose (over-paid in refunds)? Tune `05-policies.md`.

### Pipeline Y: Plan Transition / Pricing Migration

```
[trigger: customer requests plan change, OR project is migrating
plans, OR prorated billing dispute]
  → ★ ORIENT (current plan; usage; billing cycle; reason for change)
  → 🩻 X-RAY (what underlying need is the plan change addressing?)
  → ⚖ DECIDE (clean transition vs requires policy override)
  → 🎁 GOODWILL (if transition is project-driven, not customer-fault,
       compensation calibrated upward)
  → ⏳ Track timing: prorated charges, mid-cycle credit math
  → ✉ DRAFT (specific: their account; their cycle; their numbers;
       per-locale currency formatting per 🌍 LOCALE-AWARE)
  → ✓ CONFIRM (owner; mandatory for non-routine pricing change)
  → 📤 SEND (and execute: update plan; issue prorated credit/charge;
       confirm in account UI)
  → 🔁 VERIFY (next billing cycle accurate; customer notified of
       all line items)
  → 🐞 BEAD (if pattern across customers, project may need pricing
       UX clarity improvement)
```

### Pipeline Z: Deprecation / EOL Customer Inbound

```
[trigger: customer affected by an announced or imminent deprecation;
or post-removal "this used to work"]
  → ★ ORIENT (which deprecation; their specific impact)
  → ☠ EOL (recall lead time, migration path, recovery options)
  → For pre-deadline:
       → ✉ DRAFT (specific to their account: what's at risk,
            what they need to do, when, with timeline for help)
       → 🩹 PROACTIVE (if they're representative of a silent cohort,
            consider broader outreach)
  → For post-deadline (missed migration):
       → Recovery path per DEPRECATION-AND-SUNSET-COMMS.md
       → 🎁 GOODWILL (per project policy; often grace period extension)
       → Help them migrate even though deadline passed
  → For enterprise-affected:
       → 🏛 ENTERPRISE (contract review; counsel-led if breach risk)
  → ✓ CONFIRM (owner; especially for grace-period / contract-bend cases)
  → 📤 SEND
  → 🐞 BEAD (track post-deadline cases; may signal lead time too short)
```

### Pipeline AA: Enterprise — DPA / Security Questionnaire / MSA

```
[trigger: enterprise inbound: DPA request, security questionnaire,
custom MSA redlines, SOC2/ISO certification ask, or sub-processor change]
  → 🏛 ENTERPRISE (recognize; switch register and process)
  → 🛡 ESCALATE (counsel + AE/CSM; never agent-led)
  → ⛓ EVIDENCE-CHAIN (every legal/contract exchange to per-customer
       evidence repo)
  → For DPA: standard version OR counsel review of customer's DPA;
       redline non-standard clauses; do NOT countersign without counsel
  → For security questionnaire: route to security lead; map from
       master answer set if available; honest-not-aspirational answers
  → For MSA redlines: counsel + AE; flag deal-blocking clauses to AE
       within 24h
  → For SOC2 ask: report under NDA if held; honest "in progress" with
       compensating controls if not; never claim certification you
       don't have
  → For sub-processor change: per-customer notification per DPA;
       track acknowledgement / objection
  → ⚡ SWARM if multi-domain (legal + security + product)
  → ✓ CONFIRM (counsel + AE + owner; multi-sign-off for substantive)
  → 📤 SEND (per channel customer specified; never freelance)
  → 🐞 BEAD (deal-blocking item tracking; renewal-prep input)
  → 📈 OUTCOME (compounding: master DPA, master security answers grow)
```

### Pipeline AB: Estate / Deceased User / Account Succession

```
[trigger: family member, executor, or business co-owner notifies of
account-holder death]
  → 🪦 SUCCESSION (recognize inbound class)
  → 🎚 LIFECYCLE-STATE (suspend automation on the account; pause
       any reminders / nudges / billing-prompts to the deceased)
  → 🪜 LADDER tone (heavy-end of apology spectrum; grief-modulated;
       no marketing footer; no "rate this support")
  → 🕵 FRAUD-CHECK (verify documents; social-engineering vector exists)
  → ⛓ EVIDENCE-CHAIN (death certificate + court documents go to
       privileged retention; hashes only in ticket history)
  → ⚖ DECIDE (verification tier A/B/C/D per
       DECEASED-USER-AND-SUCCESSION.md)
  → For Tier A (subscription cancel/refund): operational; quick
  → For Tier B (data export): documents + cool-down period;
       social-engineering pattern check
  → For Tier C (ownership transfer): counsel review; rare; often
       closure + new account is correct path
  → For Tier D (memorialisation): lock account; flag account
  → If pre-stated wishes exist: those supersede family request
  → ✉ DRAFT (grief-calibrated; specific path forward; no rush)
  → ✓ CONFIRM (owner mandatory for Tier B+)
  → 📤 SEND (no auto-reminders; human follow-up only)
  → 📈 OUTCOME (privileged-retention; standard outcome record minimal)
```

## The Orchestrator's Decision Tree

When picking the next operator:

```
Have you done ★ ORIENT? ────────────────► no → start there
                                              yes ↓

Have you confirmed channels (⊞)? ───────► no → confirm no leak / no dup
                                              yes ↓

Is this a pattern (3+ siblings in 1h)? ─► yes → switch to Pipeline E (outage)
                                              no ↓

Is severity flagged at intake? ─────────► yes → 🛡 ESCALATE first
   (security / hostile / data-loss / legal)    no ↓

Have you investigated (🔍 / ✓ / ⊕)? ────► no → run those next
                                              yes ↓

Have you decided (⚖)? ──────────────────► no → DECIDE; cite policy
                                              yes ↓

Is the decision high-stakes? ───────────► yes → 🪞 SECOND-OPINION before draft
                                              no ↓

Have you drafted? ──────────────────────► no → ✉ DRAFT
                                              yes ↓

Has voice been matched? ────────────────► no → 🎙 VOICE-MATCH
                                              yes ↓

Has owner approved? ────────────────────► no → ✓ CONFIRM (bundle if many)
                                              yes ↓

→ 📤 SEND → 🔁 VERIFY → 🐞 BEAD
                                              ↓
                                      🏷 TAG-CONSISTENCY → 📈 OUTCOME
```

Memorize the decision tree; the orchestrator's job is to traverse it correctly.

## Time Budgets (Per-Pipeline)

These are targets, not contracts:

| Pipeline | Target | Hard cap |
|---|---|---|
| A — Routine bug | 20-40 min | 60 min |
| B — Refund (small) | 15-30 min | 45 min |
| C — Refund (large) | 1-2h | half day |
| D — Security disclosure | 4h ack | per SLA |
| E — Outage | 30 min to first comms | per SLA |
| F — GDPR DSAR | 1h initial | 30 days total |
| G — Hostile user | 30 min initial; varies | varies |
| H — Feature request | 5-10 min | 20 min |
| I — Pre-sales | 5-10 min | 20 min |
| J — Account recovery | 30 min | 2h |
| K — Integration failure | 30-60 min | 2h |
| L — Forecast / mass-event prep | 30-90 min | before launch |
| N — OSS PR review | 5-30 min | maintainer budget |
| O — Hostile contributor | 30 min | owner decides |
| P — Proactive outreach | 30-90 min | owner decides |
| Q — High-consequence tail | 1-4h | owner decides |
| R — NPS/CSAT detractor | 15-45 min | 24h follow-up |
| T — Press inquiry | 4h acknowledgement | deadline-driven |
| U — Regulator/legal | counsel-led | legal deadline |
| V — VoC mining | 1-2h weekly/monthly | synthesis cadence |

Hitting the hard cap = check in: are you missing context, or is the case genuinely outside-pipeline? Either way, escalate.

## Signal-To-Pipeline Mapping

When a ticket arrives, this is how to pick the pipeline:

| Signal in ticket | Likely pipeline |
|---|---|
| "I get error X when I do Y" | A (routine bug) |
| "Refund please" / "I want my money back" | B or C (small / large) |
| "I found a vulnerability" / CVE / proof-of-concept | D (security) |
| 3+ similar tickets in 60 min | E (outage) |
| "GDPR" / "Article 15/17/20" / "data export" | F (DSAR) |
| Insults / threats / "regulator" / "lawsuit" | G (hostile) |
| "Can you add X?" / "wishlist" | H (feature) |
| "How much" / "vs Competitor X" / pricing | I (pre-sales) |
| "Locked out" / "can't log in" / "password reset" | J (recovery) |
| "Webhook stopped working" / "API returning 4xx/5xx" | K (integration) |
| Launch/pricing/migration coming up | L (forecast/prep) |
| OSS PR/issue contribution decision | N (OSS PR review) |
| Hostile contributor / public OSS argument | O (hostile contributor) |
| Known affected cohort but they have not written in | P (proactive outreach) |
| Enterprise/press/regulator/public-trust tail signal | Q (high-consequence tail) |
| NPS/CSAT detractor or cancellation verbatim | R (detractor follow-up) |
| Journalist / press@ / outlet deadline | T (press) |
| Regulator, lawyer, subpoena, official compliance inquiry | U (legal/compliance) |
| Repeated themes / monthly support synthesis | V (VoC mining) |

When unclear, default to A (routine bug) and re-classify after orientation.

## Multi-Pipeline Tickets

A single ticket may need multiple pipelines:
- "I got an error AND I want a refund" → run A's investigation, then B's decision
- "Can you add X? Otherwise I'm cancelling" → H + cancellation-survey trigger
- "Your bug caused data loss, this is a GDPR issue" → DATA-LOSS runbook + F

When pipelines conflict, the higher-stakes one wins. Never run a refund pipeline first when the underlying issue is a security disclosure.

## Failure Modes

| Failure | Recovery |
|---|---|
| Skipped ORIENT, drafted directly | Stop, restart pipeline; never draft to a misunderstood ticket |
| Skipped CONFIRM, sent directly | Damage control: read what was sent vs what's in policy; if conflict, owner-led correction |
| Wrong pipeline picked | Recoverable; reclassify and re-run from ★ ORIENT |
| Pipeline ran but didn't VERIFY | Add to followup queue; verify within 48h |
| Investigation exceeds budget but no escalation | Auto-escalate at 2x budget |

## Companion Refs

- [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md) — operator cards in detail
- [TRIAGE-WORKFLOW.md](TRIAGE-WORKFLOW.md) — base 6-phase workflow
- [DECISION-MATRIX.md](DECISION-MATRIX.md) — fine-grained decision rules
- [runbooks/](runbooks/) — category-specific runbooks; this file shows how to compose them
- [FAILURE-MODES.md](FAILURE-MODES.md) — what goes wrong when pipelines aren't followed
