# Template Prompts (Copy-Paste Ready)

These prompts are battle-tested for use with this skill. Copy them, fill in the brackets, and paste into a new conversation in your project directory.

## Phase -1 — Mode Selection and Coverage Mapping

### THE PROMPT — Choose the mode and build the coverage matrix

```
Before doing substantive estate-planning work, classify this matter using
references/methodology/OPERATING-MODES.md and
references/methodology/OVERLAY-RESOLVER.md.

1. Select the single best primary mode
2. Identify any secondary tags or overlays
3. Determine the required references, analyses, deliverables, and subagents
4. Generate `analyses/plan-coverage-matrix.md` using the
   assets/PLAN-COVERAGE-MATRIX.md template

Be explicit about negative decisions too: if an overlay might have applied but
does not, say why.
```

## Mode Prompt — Existing Plan Audit

```
This is an `existing-plan-audit`, not a greenfield build.

Please:

1. Read all documents in `current-documents/`
2. Read all relevant account, deed, insurance, and beneficiary records in `financial-documents/`
3. Build `analyses/plan-coverage-matrix.md`
4. Generate:
   - `analyses/document-quality-triage.md`
   - `analyses/current-document-audit.md`
   - `analyses/prior-plan-gap-analysis.md`
   - `analyses/coherence-audit.md`
   - `analyses/red-flag-triage.md`
   - `analyses/litigation-risk-memo.md`

Rank findings by:
- dangerous now
- should fix before next signing
- cleanup later

Do not default to recommending a full redraft unless the audit actually supports it.
```

## Mode Prompt — Life-Event Delta

```
This is a `life-event-delta` review.

The triggering event is: [marriage / divorce / birth / move / inheritance / retirement / business event]

Please:

1. Read the existing `deliverables/` and `analyses/` files
2. Identify which assumptions the event changed
3. Refresh `analyses/plan-coverage-matrix.md`
4. Generate a delta memo covering:
   - what is now broken
   - what remains valid
   - what beneficiary / titling / fiduciary updates are now required
   - what can wait for the next full review

Update:
- `deliverables/beneficiary-map.md`
- `deliverables/implementation-ledger.md`
- `deliverables/review-schedule.md`
- `analyses/official-source-log.md` if the event changes state-law or tax-law dependencies
```

## Mode Prompt — Urgent Bedside Signing

```
This is an `urgent-bedside-signing` situation.

Please optimize for:
- what absolutely must be done now
- execution validity
- litigation defense
- state-specific signing mechanics

Generate:
- `analyses/plan-coverage-matrix.md`
- `analyses/litigation-risk-memo.md`
- `deliverables/signing-readiness-checklist.md`
- updates to `analyses/official-source-log.md`

Be explicit about:
- what can be signed now
- what should wait for counsel
- what facts make capacity / undue influence / ceremony defects more dangerous
```

## Mode Prompt — Business Owner Succession

```
This is a `business-owner-succession` review.

Please read:
- `financial-documents/business-documents/`
- `current-documents/` for any trusts / wills / buy-sell agreements
- `deliverables/asset-inventory.md` if it exists

Then generate:
- `analyses/plan-coverage-matrix.md`
- `deliverables/business-continuity-activation.md`
- updates to `deliverables/implementation-ledger.md`
- updates to `analyses/litigation-risk-memo.md`

Focus on the Monday-morning problem:
- payroll
- banking authority
- customer / vendor continuity
- ownership transfer restrictions
- buy-sell and valuation mechanics
```

## Phase 0 — Document Intake and Audit

### THE PROMPT — Read all current documents and audit

```
I have set up an estate-planning project directory at the path I'm in.
Please:

1. Read every document in `current-documents/` (existing wills, trusts, POAs, healthcare directives, prenups, divorce decrees, buy-sell agreements)
2. Read every document in `financial-documents/` (tax returns, brokerage statements, retirement statements, deeds, insurance policies, business documents, beneficiary forms)
3. Read `identity-documents/` for citizenship, marriage, divorce status

Then generate the mode-relevant analyses below, writing each to `analyses/`. If a file is not justified yet, say so in `analyses/plan-coverage-matrix.md` instead of creating filler.

A. `document-quality-triage.md` — classify documents as authoritative, probative, context-only, or unusable. Flag unsigned drafts, blurry scans, stale statements, and anything too weak to treat as settled.

B. `current-document-audit.md` — every existing document, when executed, key terms, what state's law it was drafted under, named agents and beneficiaries, what assets it covers, freshness assessment, gaps

C. `beneficiary-form-audit.md` — every beneficiary form: account, institution, primary beneficiary, contingent, date last updated, any spousal-consent issues. Flag ex-spouses, deceased people, minor children, "estate" designations.

D. `titling-audit.md` — every real estate parcel and major asset: how titled today, who survives at death, any concerning patterns (joint tenancy with one child to exclusion of others, out-of-state real estate without trust ownership, etc.)

E. `prior-plan-gap-analysis.md` — what is stale, what needs updating, in priority order. Categorize as URGENT (file change today), HIGH (within 30 days), MEDIUM (within 90 days), LOW (next review).

F. `red-flag-triage.md` — classify issues into CRITICAL, HIGH, MEDIUM, CLEANUP. Do not let optimization items bury structural failures.

G. `document-acquisition-plan.md` — identify every missing controlling document, why it matters, who likely has it, and what planning decision is blocked without it.

H. `evidence-confidence-map.md` — grade key facts as A/B/C/D evidence quality and identify weak points still based on memory.

I. `official-source-log.md` — if any recommendation or observation depends on current law, execution formalities, thresholds, rates, portability, lookback periods, or state-specific procedural rules, log the official source, URL, jurisdiction, and verification date.

Be precise about dollar amounts, dates, and named people. Quote only short excerpts when necessary; otherwise extract and synthesize faithfully. If a conclusion depends on current law rather than what the document itself says, verify it from official sources before treating it as settled.
```

## Phase 1 — Intake Conversation

### THE PROMPT — Begin the structured intake

```
I'm ready to begin the structured intake interview. Use the 9-phase flow from
references/methodology/INTERVIEW-FLOW.md. Ask one phase at a time, one major
question at a time. Adapt based on my answers — don't ask irrelevant questions.

After each phase, save the answers to `intake/intake-record.md` so we don't
lose progress if the session ends.

Begin with Phase 1: Orientation.
```

### THE PROMPT — Resume intake from prior session

```
I had a prior intake session. Please:

1. Read `intake/intake-record.md` to see what we already covered
2. Read all session summaries in `intake/`
3. Identify which phase we stopped at
4. Resume from the next phase

If anything in my situation has changed since the last session, ask me about
those changes first before continuing.
```

## Phase 2 — Tier Routing and Plan Design

### THE PROMPT — Generate the comprehensive plan

```
You have my complete intake record and document analyses. Now design the
estate plan.

1. Read `intake/intake-record.md` and all `analyses/` files
2. Determine my wealth tier (1-5) per references/methodology/TIER-TRIAGE.md
3. Determine all complexity overlays that apply
4. Pull the relevant tier file from references/tiers/
5. Pull every relevant family-structure, asset, and advanced-planning file
6. Build or refresh `analyses/plan-coverage-matrix.md`
7. For every recommendation that depends on current law, verify it from primary sources and append the citation trail to `analyses/official-source-log.md`
8. Generate `deliverables/plan-report.md` following the
   assets/COMPREHENSIVE-PLAN-REPORT.md template

For each recommendation, show:
- The Axiom or Operator that drives it
- Specific dollar impact (where calculable)
- Implementation cost and complexity
- Timeline and deadlines
- Open questions for attorney

Also generate the coverage-matrix-approved subset of:
- `deliverables/beneficiary-map.md` (every account, current/intended designation, action)
- `deliverables/asset-inventory.md` (complete inventory)
- `deliverables/implementation-ledger.md` (what must actually be retitled or updated)
- `analyses/recommendation-confidence-register.md` (which recommendations are solid vs conditional)
- `analyses/fiduciary-bench-scorecard.md` (executor/trustee/guardian/agent comparison)
- `deliverables/attorney-interview-questions.md` (specific questions for hiring counsel)
- `analyses/stress-test-scenarios.md` (death / incapacity / fiduciary-failure / digital-lockout checks)
```

## Phase 3 — Coherence Audit (Find Contradictions)

### THE PROMPT — Cross-document coherence check

```
Run the Beneficiary-Title Coherence operator across all documents.

For each asset/account in `deliverables/asset-inventory.md`, identify:
1. What document/title/contract controls disposition at death
2. Who currently receives it under that controlling instrument
3. What my will/trust says SHOULD happen
4. Whether they match
5. If not — which controls and what action is needed

Output: `analyses/coherence-audit.md` with a delta table for every asset.

Pay special attention to:
- ERISA retirement plans where state divorce-revocation doesn't preempt
- Joint tenancy that contradicts will provisions
- Ex-spouses still on any form
- "Estate" as beneficiary on retirement / life insurance
- Minor children as direct beneficiaries
- Out-of-state real estate without trust ownership
```

## Phase 3B — Litigation Defense Review

### THE PROMPT — Review the plan with adversarial eyes

```
Read:
- `intake/intake-record.md`
- `deliverables/plan-report.md`
- `deliverables/conflict-prevention-plan.md` if present
- `analyses/coherence-audit.md`

Then run the litigation-defense review using
references/methodology/LITIGATION-DEFENSE.md.

Generate `analyses/litigation-risk-memo.md` using the
assets/LITIGATION-RISK-MEMO.md template.

Explicitly address:
- capacity
- undue influence
- execution defect risk
- ambiguity / contradiction
- fiduciary conflict
- surprise / family backlash

If any issue would materially change signing logistics, also update
`deliverables/signing-readiness-checklist.md`.
```

## Phase 3C — Fiduciary Bench

### THE PROMPT — Score executor, trustee, guardian, and agent candidates

```
Using references/methodology/FIDUCIARY-SCORING.md, compare the realistic
candidates for:
- executor
- successor trustee
- guardian
- financial POA agent
- healthcare agent

Generate `analyses/fiduciary-bench-scorecard.md` using the
assets/FIDUCIARY-BENCH-SCORECARD.md template.

Do not default to family hierarchy or sentiment. Explain the actual tradeoffs.
```

## Phase 4 — Liquidity Test

### THE PROMPT — Day-270 cash flow analysis

```
Run the Liquidity-at-Death operator.

Build a Day-270 (9-months-after-death) cash projection:

OBLIGATIONS:
- Federal estate tax (if applicable per current $15M exemption)
- State estate tax (per my domicile + states with my real property)
- Mortgage continuing payments (per my real estate + amortization)
- Margin / pledged-asset line interest and any margin-call exposure
- Capital calls on private fund commitments
- Funeral and administration expenses ($10K-$50K)
- Specific cash bequests in my will
- Ongoing alimony / child support if applicable

LIQUID ASSETS AVAILABLE:
- Cash, checking, money market
- Liquid taxable brokerage (excluding margined positions)
- Life insurance proceeds expected within 60 days
- Retirement accounts (with tax acceleration cost)

NET LIQUIDITY GAP:
- Compute the gap
- Recommend solutions: ILIT-funded life insurance, §6166 deferral,
  §303 redemption, planned liquidity reserve, pre-death debt paydown

Output: `analyses/liquidity-analysis.md`
```

## Phase 5 — State Tax Exposure

### THE PROMPT — Comprehensive state tax projection

```
Compute my full state estate / inheritance tax exposure:

1. My state of domicile: [STATE]
2. States where I own real property: [LIST]
3. States where my heirs reside (for inheritance tax purposes): [LIST]

Read the state files for each from references/states/.

Before finalizing any threshold, rate, portability claim, cliff treatment,
lookback period, or filing deadline, verify it from official state or IRS
sources and append the result to `analyses/official-source-log.md`.

For each state, compute:
- Whether estate tax applies
- Threshold and my exposure above it
- Whether portability is available
- Whether the state has a "cliff" rule (NY, etc.)
- Whether out-of-state real estate is exposed
- Any inheritance tax exposure for non-spouse heirs (PA, NJ, KY, NE, MD)

If meaningful state tax exposure exists, recommend:
- Credit-shelter trust at first death (preserves both state exemptions)
- ILIT-funded liquidity for state tax
- Domicile-change analysis (savings vs. clean-break complexity)

Output: `analyses/tax-exposure-analysis.md`
```

## Phase 6 — Vulnerable-Heir Routing

### THE PROMPT — Special-needs / vulnerable heir analysis

```
For each beneficiary on my plan, run the Vulnerable-Beneficiary Filter:

For each, identify any of:
- Disability or chronic illness (Medicaid/SSI eligibility)
- Addiction history (substance, gambling)
- Mental illness with hospitalization history
- Pending bankruptcy or creditor exposure
- Predatory marriage concerns
- Financial-immaturity concerns
- Outstanding judgments / restitution
- Incarceration

For any beneficiary triggering ≥1 risk factor, design a protective structure:
- Third-party SNT for benefits-eligibility cases
- Discretionary spendthrift trust for addiction / creditor / divorce cases
- Lifetime trust with HEMS for predatory-marriage concerns
- Staged distribution for immaturity
- Independent or corporate trustee
- Trust protector

Reference references/family-structures/VULNERABLE-HEIRS.md.

Output: structured plan section in `deliverables/plan-report.md` and
`deliverables/letter-of-wishes.md` for each vulnerable heir's trustee.
```

## Phase 7 — Charitable Planning

### THE PROMPT — Tax-optimized charitable planning

```
I have charitable intent. Run charitable optimization:

Read references/advanced-planning/CHARITABLE-PLANNING.md.

Considering:
- My estate's federal tax exposure
- My state's tax treatment of charitable bequests
- My current charitable giving pattern
- My children's bracket vs. mine
- The composition of my assets (IRA vs. taxable vs. real estate)

Recommend:
- Whether to leave traditional IRA to charity (most tax-efficient)
- Whether DAF, private foundation, or both
- Whether CRT or CLT structure would benefit
- Whether QCD is being used optimally
- Specific dollar allocation to each vehicle

Output: charitable section in plan report with EV calculation per option.
```

## Phase 7B — Implementation Ops

### THE PROMPT — Turn the legal plan into an execution queue

```
Read:
- `deliverables/plan-report.md`
- `deliverables/beneficiary-map.md`
- `deliverables/asset-inventory.md`
- `analyses/official-source-log.md`

Then use references/methodology/IMPLEMENTATION-OPS.md to generate:

- `deliverables/signing-readiness-checklist.md`
- `deliverables/funding-proof-log.md`
- `deliverables/institution-contact-matrix.md`
- `deliverables/beneficiary-change-packet.md`

Update `deliverables/implementation-ledger.md` so every legal recommendation that
depends on funding, titling, or institution paperwork has a concrete action path.

If a business is involved, also generate
`deliverables/business-continuity-activation.md`.
```

## Phase 8 — Family Communication Plan

### THE PROMPT — Generate family meeting agenda

```
Based on my plan and intake, generate `deliverables/family-meeting-agenda.md`
following the assets/FAMILY-MEETING-AGENDA.md template.

Customize for:
- My specific family configuration
- The most likely sources of conflict
- The vulnerable heirs needing sensitive treatment
- The specific decisions that may surprise heirs
- Whether I should have separate meetings (spouse + first-marriage kids
  meetings if blended family)

Also generate only the communication / legacy files the coverage matrix and family dynamics make worth creating now:
- `deliverables/letter-of-wishes.md` for each trust beneficiary
- `deliverables/ethical-will.md` outline
- `deliverables/conflict-prevention-plan.md`
- Suggested talking-point script in my own voice

The goal is: when I sit down with my family, I have a complete agenda and
specific language ready.
```

## Phase 8B — Cross-Border / Conflict-of-Laws Escalation

### THE PROMPT — Escalate foreign and multi-jurisdiction issues

```
If the plan involves foreign real estate, foreign heirs, a non-citizen spouse,
an expatriate fact pattern, or multi-state domicile friction, run
references/methodology/CROSS-BORDER-ESCALATION.md.

Generate `analyses/foreign-and-conflict-of-laws-review.md` using the
assets/FOREIGN-AND-CONFLICT-OF-LAWS-REVIEW.md template.

Separate:
- issues that are safe to analyze now
- issues that require local or foreign counsel
- issues that block confident recommendations
```

## Phase 9 — Attorney Handoff Packet

### THE PROMPT — Generate the attorney handoff

```
I'm ready to engage an estate-planning attorney. Generate the complete
handoff packet:

1. `deliverables/attorney-interview-questions.md` — questions to ask multiple
   attorneys before hiring (per assets/ATTORNEY-INTERVIEW.md)

2. `deliverables/attorney-engagement-brief.md` — a 5-10 page brief the attorney
   can read in 30 minutes containing:
   - My situation summary
   - All decisions I've already made
   - All decisions I need attorney guidance on
   - The complete asset inventory
   - The beneficiary map and required updates
   - The recommended structure with my reasoning
   - Specific draft clauses that need review (disinheritance, vulnerable-heir
     trusts, no-contest, tax apportionment)
   - State-specific issues
   - Open tax questions for the CPA
   - Timeline and priorities

3. `deliverables/document-package-index.md` — list every supporting document
   I'm bringing, organized for easy attorney access

4. Attach or summarize `analyses/official-source-log.md` so the attorney can
   see exactly which state/federal law points were already verified and when

5. Score the packet using references/methodology/ATTORNEY-HANDOFF-RUBRIC.md and
   generate `analyses/attorney-handoff-readiness.md`

The goal: the attorney's engagement is high-leverage technical drafting and
compliance, not basic intake.
```

## Phase 9B — Maintenance Review

### THE PROMPT — Run an annual or life-event maintenance pass

```
Read the existing `deliverables/` and `analyses/` files, then use
references/methodology/OPERATING-MODES.md and
references/methodology/PLAN-MAINTENANCE-OS.md to run a maintenance review.

Update:
- `analyses/plan-coverage-matrix.md`
- `deliverables/review-schedule.md`
- `deliverables/implementation-ledger.md`
- `analyses/official-source-log.md` for any refreshed live-law points

Output a concise maintenance memo:
- what changed
- what drifted
- what needs immediate repair
- what can wait until the next full review
```

## Phase 10 — Post-Death Activation (For Executor)

### THE PROMPT — Activate the executor playbook

```
[The decedent] has passed away. I am the named executor.

Read all documents in `current-documents/`, all `deliverables/`, all
`analyses/`. Then:

1. Generate a 7-day priority list (this week's tasks)
2. Generate a 30-day priority list (this month's tasks)
3. Identify all hard deadlines (9-month estate tax, qualified disclaimer
   window, etc.)
4. Identify required tax filings and engage CPA contact
5. Identify creditor notification process for this state
6. Compile contact list (attorney, CPA, financial advisor, beneficiaries)
7. Compile the Day-1 checklist (death certificate copies, social security,
   credit bureaus, mail forwarding, secure home, pets)

Update `deliverables/executor-checklist.md` with explicit sections for:
- day 1 / first 72 hours
- first 30 days
- months 2-9
- hard deadlines calendar
- contact list / advisors to notify

Also update `deliverables/institution-contact-matrix.md` with the institutions,
advisors, agencies, and beneficiaries who must be contacted, and mirror any
institution or filing tasks into `deliverables/implementation-ledger.md` when
the next action is operational rather than purely explanatory.

Only if the user explicitly wants a live estate-administration workspace rather
than a planning workspace, you may additionally create an
`executor-activation/` directory for temporary working notes. Do not treat that
directory as required output, and mirror all durable guidance back into
`deliverables/executor-checklist.md`.
```

## Multi-Model Triangulation

For any aggressive position or large dollar decision, run the same prompt
through Claude, GPT, and Gemini independently. Where they agree, confidence
is high. Where they disagree, that disagreement IS the finding requiring
attorney attention.

```
Export the relevant analysis from analyses/ or deliverables/.

Send to GPT (model: gpt-5.4-pro or current best) with the same prompt:
"Review this estate plan section. Identify any errors, missed opportunities,
state-specific issues for [STATE], or audit risks. Be specific with dollar
amounts and IRC sections."

Send to Gemini (gemini-3.1-ultra or current best) with the same prompt.

Compile the three responses side-by-side. Where two or more disagree,
escalate to attorney for resolution.
```
