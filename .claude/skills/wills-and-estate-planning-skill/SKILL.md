---
name: wills-and-estate-planning-skill
description: >-
  U.S. estate planning: wills, audits, executor workflows. Use when
  creating/reviewing a plan, life-event updates, urgent signing, beneficiary
  or succession changes, or estate administration.
---

<!-- TOC: Kernel | Operators | Wealth-Tier Triage | Interactive Intake | Output Deliverables | Anti-Patterns | References -->

# Wills and Estate Planning — Interactive Life Planning

> **Core Insight:** Estate planning is not "writing a will." It is coordinating a **will + beneficiary designations + titling + trust structure + incapacity docs + digital assets + communication plan** so that **one coherent story** is told by every document on the day you die or become incapacitated. A beautifully drafted will can be functionally irrelevant if the 401(k) still names an ex-spouse, the house is titled joint tenancy with the wrong sibling, or nobody can find the crypto seed phrase.

> **Scope:** U.S. federal + state estate/gift/GST law as of **2026**, under the **One Big Beautiful Bill Act (OBBBA)** with a **$15M per-person** federal basic exclusion and a **roughly doubled married-couple shelter only to the extent both spouses' exclusion capacity is actually preserved and available**. Because estate-planning law is volatile and state-specific, recommendations that rely on current law must be verified against live primary sources before they are treated as final.

> **Mandatory framing:** This skill produces **educational output and drafts for review by a licensed estate-planning attorney** in the user's state. It never signs, witnesses, files, records, or executes a legal document. Every deliverable ends with an attorney handoff packet. See [DISCLAIMER.md](assets/DISCLAIMER.md).

---

## QUICK START

1. From this skill directory, run `./scripts/intake-session.sh <project-dir>` to scaffold a dedicated project directory.
2. Select a **primary mode** using [OPERATING-MODES](references/methodology/OPERATING-MODES.md).
3. Resolve the required overlays using [OVERLAY-RESOLVER](references/methodology/OVERLAY-RESOLVER.md) and produce:
   - `analyses/plan-coverage-matrix.md`
4. Branch by mode instead of reflexively running a greenfield workflow:
   - `new-plan` / weak baseline: start with intake + document inventory, then usually build `analyses/current-document-audit.md`, `analyses/document-quality-triage.md`, `analyses/beneficiary-form-audit.md`, `analyses/red-flag-triage.md`, `analyses/document-acquisition-plan.md`, and `analyses/evidence-confidence-map.md`
   - `existing-plan-audit` / `life-event-delta`: start with `analyses/current-document-audit.md`, `analyses/prior-plan-gap-analysis.md` when applicable, `analyses/coherence-audit.md`, and a targeted beneficiary / titling review only where the triggering facts make it relevant
   - `urgent-bedside-signing` / `executor-activation`: triage execution, deadlines, access, and authority first; only backfill deeper audits when they could change the immediate recommendation
5. Load state and execution references before making state-sensitive recommendations.
6. For the active mode, build the relevant plan, implementation, litigation, confidence, and handoff layers. Common finishers include:
   - `deliverables/plan-report.md`
   - `deliverables/implementation-ledger.md`
   - `deliverables/signing-readiness-checklist.md`
   - `analyses/litigation-risk-memo.md`
   - `analyses/recommendation-confidence-register.md`
   - `deliverables/attorney-engagement-brief.md`

The plan is not complete when the drafting logic looks good. It is complete when the
controlling documents, beneficiary forms, titling, signing logistics, and implementation
queue all tell the same story.

---

## MODE ROUTER

Pick the primary mode first. Do not force every user through the same workflow.

| Mode | Use when | Must finish with |
|------|----------|------------------|
| `new-plan` | Building from weak or no prior plan | full design + implementation + attorney handoff |
| `existing-plan-audit` | User already has documents and wants to know if they still work | gap analysis + coherence + risk memo |
| `life-event-delta` | Marriage, divorce, birth, move, retirement, sale, inheritance | targeted repair list + updated beneficiary / title cleanup |
| `urgent-bedside-signing` | Capacity / health / travel pressure makes execution fragile | signing-readiness + litigation-defense + attorney escalation |
| `executor-activation` | Decedent has died; user is executing the plan | updated executor checklist + deadline sections + contact matrix |
| `business-owner-succession` | An operating business must survive death or incapacity | business continuity plan + implementation / control routing |
| `uhnw-restructure` | Transfer-tax / control / dynasty / liquidity architecture dominates | tax / basis / control comparison + implementation queue |
| `maintenance-review` | Annual or post-signing upkeep | drift repair + refreshed review schedule |
| `finalize-and-cleanse` | User is done and wants the contemporaneous paper trail removed from their folder after saving + emailing the final package | interactive save-and-email confirmation + curated `deliverables/final/` + audited deletion of intake, analyses, decisions, drafts, session logs |

Fast-start reference: [OPERATING-MODES](references/methodology/OPERATING-MODES.md)

Archetype accelerator: [ARCHETYPE-START-PACKS](references/intake/ARCHETYPE-START-PACKS.md)

---

## COVERAGE DISCIPLINE

Do not claim the skill "considered everything relevant" unless the workspace can show how it got there.

- Build `analyses/plan-coverage-matrix.md` early.
- Resolve state, family, asset, profession, life-event, and risk overlays explicitly.
- Record which references were loaded, which outputs are required, and which issues remain blocked.
- Treat the coverage matrix as a live completeness check and memory aid, not a substitute for judgment.

Use:

- [OVERLAY-RESOLVER](references/methodology/OVERLAY-RESOLVER.md)
- [DOCUMENT-INGESTION](references/methodology/DOCUMENT-INGESTION.md)
- [CONFIDENCE-SCORING](references/methodology/CONFIDENCE-SCORING.md)
- [FIDUCIARY-SCORING](references/methodology/FIDUCIARY-SCORING.md)
- [IMPLEMENTATION-OPS](references/methodology/IMPLEMENTATION-OPS.md)
- [LITIGATION-DEFENSE](references/methodology/LITIGATION-DEFENSE.md)
- [ATTORNEY-HANDOFF-RUBRIC](references/methodology/ATTORNEY-HANDOFF-RUBRIC.md)

---

## THE ESTATE-PLANNING KERNEL (Universal Axioms)

<!-- ESTATE_KERNEL_START v1.0 -->

Almost every serious plan, from a 24-year-old renter to a $400M industrialist, should be stress-tested against these axioms. They are default truths, not mindless scripts: if an edge case seems to break one, explain why before treating it as an exception.

**Axiom 0 — The will does not control the whole estate.**
Retirement accounts, life insurance, annuities, TOD/POD accounts, survivorship-titled real estate, trust-owned assets, and property subject to buy-sell agreements pass by **contract or title**, not by will. A will that says "everything to my children equally" does nothing if the 401(k) still names an ex-spouse. **Every plan starts and ends with a beneficiary/titling audit.**

**Axiom 1 — One coherent story must be told by every document.**
Will + revocable trust + beneficiary forms + deeds + POAs + healthcare directives + letter of instruction + digital inventory must point at the same people, in the same shares, under the same contingencies, under the same state's law. Silos produce the deepest failures.

**Axiom 2 — Plan for incapacity first, death second.**
Incapacity (dementia, stroke, coma, severe mental illness) often lasts longer and damages more wealth than death. For most adults, the default incapacity package is durable financial POA + healthcare POA + living will + HIPAA authorization, with a funded revocable trust added whenever probate avoidance, multi-state assets, privacy, or management continuity justify it. Death planning without incapacity planning is often only half a plan.

**Axiom 3 — Beneficiary designations override wills and trusts.**
ERISA retirement plans in particular are governed by federal law, and the plan administrator will usually follow the beneficiary designation on file unless a federal overlay such as spousal-consent rules changes the result. Update them personally after every life event — marriage, divorce, birth, death, move, adoption, remarriage.

**Axiom 4 — Fair process matters more than fair outcome.**
Heirs accept unequal inheritances when they feel heard. Heirs fight equal inheritances when they feel ambushed. The family meeting, the letter of wishes, and the explanation-while-alive prevent more litigation than any no-contest clause.

**Axiom 5 — Under the 2026 $15M exemption, basis often dominates tax.**
For estates below the exemption, **maximizing step-up in basis** at death typically produces more family wealth than removing assets from the estate. For estates above the exemption, **removing appreciation** from the taxable estate dominates. Crossover is around the federal exemption, but for married couples you should model the combined shelter that will actually be available rather than assuming two full exclusions; state estate tax shifts the line further.

**Axiom 6 — State law controls more than federal law for most families.**
State estate tax (NY, MA, OR, IL, CT, DC, HI, ME, MN, RI, VT, WA + MD), state inheritance tax (KY, NE, NJ, PA + MD), elective-share rules, homestead protection, community property regime, Medicaid lookback, TOD deed availability, and trust situs rules vary enormously. Verify the user's **domicile state** and every state where they own real estate.

**Axiom 7 — Titling of real estate and major assets governs transfer at death.**
Joint tenancy, tenancy by the entirety, community property with right of survivorship, TOD deeds, trust ownership — each produces a different post-death path with different tax and probate consequences. A will cannot override titling.

**Axiom 8 — Irrevocable choices must clear an intent-plus-cost test.**
Irrevocable trusts, Medicaid transfers, large gifts, ILIT premium funding, GRAT execution — these are hard to unwind cleanly. Pressure-test them by asking: (a) is the intent likely to persist, (b) does the tax/creditor benefit justify the loss of control and possible basis cost, and (c) what flexibility hooks exist if facts change?

**Axiom 9 — Illiquidity at death is the silent killer.**
Estate tax is due in cash 9 months after death. Family businesses, farms, real estate, and private fund interests are illiquid. Without life insurance, §6166 deferral, or planned liquidity, families can get pushed into bad sales or rushed borrowing.

**Axiom 10 — Communication is the actual work.**
Legal documents are the deliverable. Family conversations are the plan. Surprise at the reading of the will is one of the fastest ways to turn a workable plan into litigation.

**Axiom 11 — Plans atrophy on contact with life.**
Review every 3–5 years or after any life event (marriage, divorce, birth, death, inheritance, business sale, interstate move, change in tax law, change in a named agent's circumstances). A 2014 plan written under a $5M exemption for a family that has since divorced and moved from NY to FL can be actively dangerous if nobody has rechecked it.

<!-- ESTATE_KERNEL_END v1.0 -->

---

## VERIFICATION-FIRST OVERLAY

This skill follows a **verification-first** model for any point that can drift with inflation adjustments, legislative changes, agency guidance, or state-specific execution rules.

- **Evergreen methodology** comes from the kernel, operators, tier routing, and the guide corpus.
- **Volatile law** must be checked from live primary sources before finalizing a recommendation, calculation, or attorney handoff packet.
- **Primary sources first:** IRS, state tax department, state legislature, state judiciary, secretary of state, health department, or equivalent official materials.
- **Audit trail required:** every live-law check belongs in `analyses/official-source-log.md`.

Use [VERIFICATION-FIRST](references/methodology/VERIFICATION-FIRST.md) as the operating protocol and [SOURCE-COVERAGE-MAP](references/methodology/SOURCE-COVERAGE-MAP.md) to confirm the skill still covers the full `multi_agent_wills_guide.md` source corpus.

Mandatory verification triggers include:

- Federal transfer-tax thresholds, annual exclusions, portability, QDOT, GST allocation rules, and filing deadlines
- State estate / inheritance tax thresholds, rates, portability, cliffs, and lookback rules
- State will-execution formalities, self-proving affidavit practice, notarization, witness rules, and holographic-will treatment
- Elective share, community property, TOD deed, Lady Bird deed, homestead, and Medicaid rules
- POLST / MOLST naming, healthcare-directive forms, and state-specific incapacity forms
- NFA firearms transfer rules, trust-situs issues, foreign-heir constraints, and any cross-border tax issue

---

## COGNITIVE OPERATORS (Estate-Planning Thinking Moves)

Composable moves. Apply them to any asset, beneficiary, or objective. See [OPERATORS.md](references/methodology/OPERATORS.md) for the full card library with triggers, failure modes, and prompt modules.

- **§ Probate-Bypass** — "Does this asset avoid probate? Should it?" (titling, TOD/POD, trust funding, survivorship)
- **⚖ Spousal-Rights Check** — "Would the elective share, community property, or ERISA default override this clause?"
- **⧉ Beneficiary-Title Coherence** — "If the owner died tonight, which document controls this asset — will, beneficiary form, or title — and do they all tell the same story?"
- **$↑ Step-Up-vs-Transfer Tradeoff** — "Does gifting this out of the estate save more transfer tax than it costs in lost basis step-up?"
- **⧗ Liquidity-at-Death** — "On Day 270 after death, where does the cash come from to pay the tax bill, the mortgage, the margin loan, the capital call?"
- **⧒ Incapacity-Transition** — "Who takes over financial and medical decisions at the first sign of cognitive decline, and how is that trigger defined?"
- **⌂ Lumpy-Asset Division** — "Can this single asset be split fairly among multiple heirs, or does forced co-ownership make a partition fight likely?"
- **⟳ Cross-State Domicile** — "Which state's law, tax regime, elective share, and homestead rule governs? Which state taxes what assets at death?"
- **⩚ Vulnerable-Beneficiary Filter** — "Would an outright distribution disqualify this person from means-tested benefits, fund an addiction, or be seized by a creditor?"
- **∵ Tax-Apportionment** — "Who bears the estate tax? Residuary? Specific-bequest recipients? Non-probate takers? Has the will told the executor explicitly?"
- **⚑ Blended-Family QTIP** — "Is 'to my spouse, remainder to my kids' actually enforceable, or can the survivor rewrite their will and disinherit the first marriage's children?"
- **☍ Disclaimer Window** — "Within 9 months of death, can a qualified disclaimer redirect a bequest to a better-positioned beneficiary (lower-bracket heir, generation-skip, asset-protection trust)?"
- **☖ Trust-Situs Selection** — "For long-term trusts, does a state situs (SD, NV, DE, WY, AK, TN) produce better tax, creditor, and duration outcomes than the home state?"
- **⇢ Basis-Consistency** — "Has the date-of-death valuation been captured for every asset, and has Form 8971 been filed if required?"

---

## WEALTH-TIER TRIAGE (Route to the Right Depth)

Estate planning is not one-size-fits-all. Route the user to the tier matching their net worth **and** complexity. See [TIER-TRIAGE.md](references/methodology/TIER-TRIAGE.md) for full routing logic.

| Tier | Net Worth | Typical Profile | Primary Goals | Core Docs |
|------|-----------|-----------------|---------------|-----------|
| **1 — Modest** | < $500K | Renter, early-career, young family, no business | Guardianship, basic will, beneficiary forms, life insurance | Will, POA, healthcare directive, beneficiary audit |
| **2 — Middle-Class** | $500K – $3M | Home + 401(k) + kids, small biz maybe | Probate avoidance, minor-child trust, disability, simple tax | + Revocable trust, TOD deed, pour-over will, 529 continuity review |
| **3 — High Net Worth** | $3M – $15M | Home + investments + business + state-tax exposure | State estate tax, blended family, business succession, basis step-up | + QTIP/CST, ILIT, buy-sell, domicile planning |
| **4 — Ultra-High Net Worth** | $15M – $100M | Multi-asset, often multi-state, significant business/partnerships | Federal estate tax, GST, asset protection, liquidity | + GRAT, IDGT sale, SLAT, dynasty trust, §6166, FLP |
| **5 — Industrialist / Dynasty** | $100M+ | Operating empire, multiple generations, philanthropy | Multi-generation wealth transfer, family governance, foundation, cross-border | + Family office, private foundation, CLT/CRT, offshore, family constitution, trust situs arbitrage |

**Complexity overlay** (bumps tier up regardless of net worth):

- Blended family → +1 tier complexity
- Non-citizen spouse → +1 (adds QDOT / treaty / portability analysis)
- Privately held business / partnership interests → +1
- Disabled or vulnerable heir requiring SNT → +1
- Assets in multiple states or countries → +1
- Firearms (NFA items) → specialty: NFA gun trust
- Significant crypto / self-custody → specialty: digital-asset handoff
- Active creative / IP royalty portfolio → specialty: IP succession
- Pre-IPO stock / large RSU / concentrated position → specialty: concentration + GRAT
- Known capacity/cognition risk, psychiatric history, addiction → specialty: incapacity + Ulysses + incentive trust

---

## INTERACTIVE INTAKE (The Conversational Spine)

This is the heart of the skill. Do **not** ask the user a 100-question survey up front. Instead, conduct an **adaptive interview**: start broad, branch based on answers, and only ask what the user's situation makes relevant.

See [INTERVIEW-FLOW.md](references/methodology/INTERVIEW-FLOW.md) for the adaptive interview map and [INTAKE-QUESTIONNAIRE.md](references/intake/INTAKE-QUESTIONNAIRE.md) for the full question bank. If you use `scripts/intake-session.sh`, treat it as a helper, not as a substitute for judgment.

### The 9 Intake Phases

```
Phase 1 — Orientation           (5 min)  "Why are you doing this now? What triggered it?"
Phase 2 — People                (10 min) Who exists in your life? Spouse, partners, kids, parents, siblings, friends, charities, dependents?
Phase 3 — Assets & Liabilities  (15 min) What do you own, where is it, how is it titled, what are the liabilities against it?
Phase 4 — Beneficiary Audit     (10 min) What does every beneficiary form, deed, and contract currently say?
Phase 5 — Family Dynamics       (10 min) Blended family? Estrangement? Disability? Addiction? Divorce in progress? Second marriage?
Phase 6 — Goals & Values        (15 min) Who matters? What do you want your legacy to be? Equal vs. equitable? Charitable intent?
Phase 7 — Incapacity Scenarios  (10 min) Who decides if you can't? What do you want done? End-of-life wishes?
Phase 8 — Jurisdiction          (5 min)  Where are you domiciled? Where do you own property? Where do heirs live?
Phase 9 — Wealth-Tier Routing   (5 min)  Based on totals, route to the right depth
```

At each phase, **update the running intake record** (save to the user's project directory as `intake/intake-record.md`) and cross-check Axiom 1: does the emerging plan still tell one coherent story?

### Interview Principles

1. **Plain English first.** Never lead with "QTIP" or "GST exemption." Lead with "what happens to the house?" and "who raises the kids?"
2. **One topic at a time.** Don't bundle 6 questions in one message. Ask, listen, follow up, move on.
3. **Adapt the branch.** If they say "no spouse," skip marital deduction, QDOT, spousal rollover. If they say "no kids," skip pretermitted-heir logic. If they say "blended family," go deep on QTIP.
4. **Surface landmines early.** If a user mentions an ex-spouse still on a 401(k), a crypto wallet nobody knows about, a child with addiction, or a vacation home in a second state — flag it immediately, not at the end.
5. **Document the why.** For every meaningful choice (disinheritance, unequal shares, trustee selection, charitable bequest), capture the user's reasoning in their own words for the letter of wishes.
6. **Confirm before recommending.** Before suggesting a QTIP or an ILIT, restate the user's goals and confirm the recommendation actually serves those goals.
7. **Respect cognition and age.** Elderly or ill users may need shorter sessions, larger text, contemporaneous capacity notes, and (ultimately) signing ceremonies the attorney can videotape.

---

## THE 9-STEP WORKFLOW (End-to-End)

Before Step 1, select the mode and build `analyses/plan-coverage-matrix.md`.

```
┌────────────────────────────────────────────────────────────────────────┐
│  STEP 1 — ORIENT                                                       │
│     Ask why-now, intake Phase 1, set expectations, present the         │
│     disclaimer. Confirm user understands this is not legal advice.     │
│                                                                        │
│  STEP 2 — INVENTORY                                                    │
│     Drive Phases 2–4 (people, assets, beneficiary audit). Produce      │
│     the Asset Inventory, Beneficiary Map, and Evidence Confidence Map. │
│     FIRST DELIVERABLE LAYER.                                           │
│                                                                        │
│  STEP 3 — SURFACE COMPLICATIONS                                        │
│     Phase 5 (family dynamics). Flag blended family, disability,        │
│     addiction, disinheritance, foreign beneficiaries, concentrated     │
│     positions, illiquidity, domicile ambiguity. Produce Red Flag       │
│     Triage.                                                            │
│                                                                        │
│  STEP 4 — CLARIFY GOALS                                                │
│     Phase 6. Equal vs. equitable. Charitable intent. Business          │
│     succession. Family values. Write these in the user's own words.    │
│                                                                        │
│  STEP 5 — DESIGN STRUCTURE                                             │
│     Apply Kernel + Operators + Tier. Choose will / trust / POA         │
│     architecture. Name executor, trustee, guardian, agents.            │
│     Coordinate beneficiary designations. Handle lumpy assets.          │
│                                                                        │
│  STEP 6 — INCAPACITY & END-OF-LIFE                                     │
│     Phase 7. Durable POA, healthcare proxy, living will, HIPAA,        │
│     dementia directive, POLST if appropriate, disposition of remains.  │
│                                                                        │
│  STEP 7 — TAX & DOMICILE                                               │
│     Phase 8 + 9. Federal exemption, state estate/inheritance tax,      │
│     portability, step-up planning, GST for dynasty, charitable         │
│     vehicles. Domicile audit if multi-state. Load execution-formality  │
│     references when state signing rules could affect outcome.          │
│                                                                        │
│  STEP 8 — COMMUNICATION & LEGACY                                       │
│     Family meeting agenda. Letter of wishes. Ethical will.             │
│     Digital-asset inventory. Conflict-prevention plan. "If I die       │
│     tomorrow" package.                                                 │
│                                                                        │
│  STEP 9 — ATTORNEY HANDOFF                                             │
│     Produce the Comprehensive Plan Report with every decision,         │
│     rationale, stress test, and draft. Attorney Interview Question     │
│     list. Execution checklist. Implementation ledger. Review cadence.  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## OUTPUT CONTRACT (What the User Walks Away With)

Every serious session should leave a structured project directory, not just a loose pile of files. But the required subset is **mode-dependent**: do not generate files just to satisfy a template. Use `analyses/plan-coverage-matrix.md` to record which outputs were required, intentionally skipped, or deferred.

### `intake/`

1. **`intake/intake-record.md`** — Full interview transcript and user-confirmed facts
2. **`intake/session-*-summary.md`** — Session continuity notes for longer multi-session projects

### `analyses/`

1. **`analyses/current-document-audit.md`** — What documents already exist, their apparent governing law, and gaps
2. **`analyses/beneficiary-form-audit.md`** — Every beneficiary form and every mismatch
3. **`analyses/titling-audit.md`** — Every asset's current titling and what controls at death
4. **`analyses/coherence-audit.md`** — Cross-document contradictions and required cleanup
5. **`analyses/tax-exposure-analysis.md`** — Federal + state estate / inheritance tax analysis
6. **`analyses/liquidity-analysis.md`** — Day-270 liquidity test and forced-sale risk
7. **`analyses/prior-plan-gap-analysis.md`** — What is stale or broken in an existing plan
8. **`analyses/decision-ledger.md`** — Why each major planning choice was made
9. **`analyses/official-source-log.md`** — Live-law verification log with source URLs and dates
10. **`analyses/red-flag-triage.md`** — Critical / high / medium / cleanup planning issues
11. **`analyses/document-acquisition-plan.md`** — Missing-document retrieval queue
12. **`analyses/evidence-confidence-map.md`** — Confidence grading for key facts and assets
13. **`analyses/stress-test-scenarios.md`** — Death, incapacity, conflict, and execution failure tests
14. **`analyses/plan-coverage-matrix.md`** — Proof of which overlays, references, and outputs were required
15. **`analyses/document-quality-triage.md`** — Document-authority and legibility triage
16. **`analyses/recommendation-confidence-register.md`** — Confidence scoring by recommendation
17. **`analyses/fiduciary-bench-scorecard.md`** — Comparison of executor / trustee / guardian / agent candidates
18. **`analyses/litigation-risk-memo.md`** — Contest-risk and execution-defense memo
19. **`analyses/attorney-handoff-readiness.md`** — Readiness rubric for efficient counsel engagement
20. **`analyses/foreign-and-conflict-of-laws-review.md`** — Cross-border and multi-jurisdiction review when triggered

### `deliverables/`

1. **`deliverables/asset-inventory.md`** — Assets, liabilities, titling, location, approximate values
2. **`deliverables/beneficiary-map.md`** — Every account/asset, who it goes to today, who it should go to, and the delta
3. **`deliverables/plan-report.md`** — The comprehensive plan
4. **`deliverables/implementation-ledger.md`** — Trust-funding and institution-update queue
5. **`deliverables/letter-of-instruction.md`** — Where documents are, who to contact, funeral wishes, passwords pointer
6. **`deliverables/digital-inventory.md`** — Accounts, wallets, seed-location references, legacy contacts, crypto custody diagram
7. **`deliverables/personal-property-memorandum.md`** — State-specific list of tangible items referenced by the will
8. **`deliverables/letter-of-wishes.md`** — Non-binding guidance for trustees on discretionary distributions
9. **`deliverables/ethical-will.md`** — Values, stories, messages
10. **`deliverables/family-meeting-agenda.md`** — Talking points for the family conversation
11. **`deliverables/conflict-prevention-plan.md`** — Flashpoints, explanation strategy, governance fixes
12. **`deliverables/if-i-die-tomorrow.md`** — One-page quickstart package for spouse/executor
13. **`deliverables/disposition-of-remains.md`** — Funeral, burial, cremation, organ donation wishes
14. **`deliverables/executor-checklist.md`** — Timeline-based post-death playbook
15. **`deliverables/attorney-interview-questions.md`** — Questions for hiring counsel
16. **`deliverables/attorney-engagement-brief.md`** — Condensed handoff brief for counsel
17. **`deliverables/document-package-index.md`** — Index of supporting documents supplied to counsel
18. **`deliverables/review-schedule.md`** — Triggers and cadence for plan updates
19. **`deliverables/signing-readiness-checklist.md`** — Ceremony logistics and execution safeguards
20. **`deliverables/funding-proof-log.md`** — Evidence that beneficiary / titling / funding steps were completed
21. **`deliverables/institution-contact-matrix.md`** — Institution-by-institution implementation map
22. **`deliverables/beneficiary-change-packet.md`** — Ordered packet for beneficiary-form cleanup
23. **`deliverables/business-continuity-activation.md`** — Monday-morning operations plan when a business is material

All templates live under [assets/](assets/). The plan report references each deliverable by relative path.

---

## ROUTING TABLE (Which Reference to Read Next)

| Situation | Read |
|-----------|------|
| Need to choose the right primary workflow | [methodology/OPERATING-MODES.md](references/methodology/OPERATING-MODES.md) |
| Need disciplined overlay routing | [methodology/OVERLAY-RESOLVER.md](references/methodology/OVERLAY-RESOLVER.md) |
| Want a fast profile-specific starting point | [intake/ARCHETYPE-START-PACKS.md](references/intake/ARCHETYPE-START-PACKS.md) |
| Need messy-document / stale-document triage | [methodology/DOCUMENT-INGESTION.md](references/methodology/DOCUMENT-INGESTION.md) |
| Need implementation / funding / institution ops | [methodology/IMPLEMENTATION-OPS.md](references/methodology/IMPLEMENTATION-OPS.md) |
| Need litigation / contest hardening | [methodology/LITIGATION-DEFENSE.md](references/methodology/LITIGATION-DEFENSE.md) |
| Need recommendation confidence scoring | [methodology/CONFIDENCE-SCORING.md](references/methodology/CONFIDENCE-SCORING.md) |
| Need fiduciary candidate scoring | [methodology/FIDUCIARY-SCORING.md](references/methodology/FIDUCIARY-SCORING.md) |
| Need attorney handoff scoring | [methodology/ATTORNEY-HANDOFF-RUBRIC.md](references/methodology/ATTORNEY-HANDOFF-RUBRIC.md) |
| Need cross-border escalation logic | [methodology/CROSS-BORDER-ESCALATION.md](references/methodology/CROSS-BORDER-ESCALATION.md) |
| Unsure where to start | [methodology/INTERVIEW-FLOW.md](references/methodology/INTERVIEW-FLOW.md) |
| Need a triage / severity framework | [methodology/RED-FLAG-CHECKLIST.md](references/methodology/RED-FLAG-CHECKLIST.md) |
| Need a missing-doc / evidence workflow | [methodology/DOCUMENT-CHECKLIST.md](references/methodology/DOCUMENT-CHECKLIST.md) |
| Need to compare planning tradeoffs | [methodology/STRATEGY-INTERACTION-MATRIX.md](references/methodology/STRATEGY-INTERACTION-MATRIX.md) |
| Need maintenance / annual refresh logic | [methodology/PLAN-MAINTENANCE-OS.md](references/methodology/PLAN-MAINTENANCE-OS.md) |
| Need to break the plan with scenarios | [methodology/STRESS-TEST-SCENARIOS.md](references/methodology/STRESS-TEST-SCENARIOS.md) |
| Need the full intake question bank | [intake/INTAKE-QUESTIONNAIRE.md](references/intake/INTAKE-QUESTIONNAIRE.md) |
| Net worth < $500K | [tiers/TIER-1-MODEST-ESTATE.md](references/tiers/TIER-1-MODEST-ESTATE.md) |
| $500K – $3M | [tiers/TIER-2-MIDDLE-CLASS.md](references/tiers/TIER-2-MIDDLE-CLASS.md) |
| $3M – $15M | [tiers/TIER-3-HNW.md](references/tiers/TIER-3-HNW.md) |
| $15M – $100M | [tiers/TIER-4-UHNW.md](references/tiers/TIER-4-UHNW.md) |
| $100M+ / industrialist | [tiers/TIER-5-INDUSTRIALIST.md](references/tiers/TIER-5-INDUSTRIALIST.md) |
| Blended family, stepchildren, second marriage | [family-structures/BLENDED-FAMILY.md](references/family-structures/BLENDED-FAMILY.md) |
| Unmarried partner | [family-structures/UNMARRIED-PARTNERS.md](references/family-structures/UNMARRIED-PARTNERS.md) |
| Same-sex married couple / LGBTQ family dynamics | [situations/SAME-SEX-MARRIED-COUPLE.md](references/situations/SAME-SEX-MARRIED-COUPLE.md), [situations/LGBTQ-PLANNING.md](references/situations/LGBTQ-PLANNING.md) |
| Polyamorous or unconventional family | [situations/POLYAMOROUS-OR-UNCONVENTIONAL-FAMILY.md](references/situations/POLYAMOROUS-OR-UNCONVENTIONAL-FAMILY.md) |
| Non-U.S.-citizen spouse | [family-structures/NON-CITIZEN-SPOUSE.md](references/family-structures/NON-CITIZEN-SPOUSE.md) |
| Single, no kids | [family-structures/SINGLE-NO-KIDS.md](references/family-structures/SINGLE-NO-KIDS.md) |
| Aging alone / no obvious family fiduciary | [situations/AGING-ALONE.md](references/situations/AGING-ALONE.md) |
| Minor children | [family-structures/MINOR-CHILDREN.md](references/family-structures/MINOR-CHILDREN.md) |
| Heir with disability / on SSI/Medicaid / addiction / creditor risk | [family-structures/VULNERABLE-HEIRS.md](references/family-structures/VULNERABLE-HEIRS.md) |
| Disinheriting a child or sibling | [family-structures/DISINHERITANCE.md](references/family-structures/DISINHERITANCE.md) |
| Divorced or currently separated | [family-structures/DIVORCED-OR-SEPARATED.md](references/family-structures/DIVORCED-OR-SEPARATED.md) |
| Foreign heirs or foreign assets | [family-structures/INCARCERATED-OR-FOREIGN-HEIRS.md](references/family-structures/INCARCERATED-OR-FOREIGN-HEIRS.md) |
| Caregiver-child dynamics | [situations/CAREGIVER-FOR-PARENT.md](references/situations/CAREGIVER-FOR-PARENT.md), [life-events/BECOMING-CAREGIVER.md](references/life-events/BECOMING-CAREGIVER.md) |
| Estranged family / no-contact issues | [situations/ESTRANGED-FAMILY.md](references/situations/ESTRANGED-FAMILY.md) |
| Frozen embryos / posthumous reproduction / assisted reproduction | [family-structures/POSTHUMOUS-REPRODUCTION-CHILDREN.md](references/family-structures/POSTHUMOUS-REPRODUCTION-CHILDREN.md) |
| Home, reverse mortgage, vacation home | [assets/PRIMARY-RESIDENCE.md](references/assets/PRIMARY-RESIDENCE.md), [REVERSE-MORTGAGES.md](references/assets/REVERSE-MORTGAGES.md), [VACATION-HOMES.md](references/assets/VACATION-HOMES.md) |
| Retirement / IRA / 401(k) / HSA / pension | [assets/RETIREMENT-ACCOUNTS.md](references/assets/RETIREMENT-ACCOUNTS.md) |
| Taxable brokerage, margin loan, concentrated stock, RSU | [assets/INVESTMENT-ACCOUNTS-MARGIN.md](references/assets/INVESTMENT-ACCOUNTS-MARGIN.md) |
| Life insurance, ILIT | [assets/LIFE-INSURANCE.md](references/assets/LIFE-INSURANCE.md), [advanced-planning/ILIT.md](references/advanced-planning/ILIT.md) |
| Crypto / wallets / digital accounts | [assets/CRYPTO-AND-DIGITAL.md](references/assets/CRYPTO-AND-DIGITAL.md) |
| Firearms, NFA items | [assets/FIREARMS-NFA.md](references/assets/FIREARMS-NFA.md) |
| Closely held business, S-corp, family business | [assets/PRIVATE-BUSINESS.md](references/assets/PRIVATE-BUSINESS.md) |
| Private fund, PE, hedge fund, real-estate syndicate interest | [assets/INVESTMENT-PARTNERSHIPS.md](references/assets/INVESTMENT-PARTNERSHIPS.md) |
| Need institution / plan-administrator operations details | [assets/INSTITUTIONAL-OPERATIONS.md](references/assets/INSTITUTIONAL-OPERATIONS.md) |
| Royalties, IP, copyright, patents, creator-economy | [assets/INTELLECTUAL-PROPERTY.md](references/assets/INTELLECTUAL-PROPERTY.md) |
| Farmland, ranch, mineral rights, water rights, timber | [assets/FARMLAND-MINERAL-RIGHTS.md](references/assets/FARMLAND-MINERAL-RIGHTS.md) |
| Art, cars, wine, jewelry, collectibles | [assets/ART-COLLECTIONS-PERSONAL-PROPERTY.md](references/assets/ART-COLLECTIONS-PERSONAL-PROPERTY.md) |
| Pets (dogs, cats, horses, exotic pets) | [assets/PETS-AND-ANIMALS.md](references/assets/PETS-AND-ANIMALS.md) |
| Foreign real estate / forced heirship / FBAR-FATCA | [assets/FOREIGN-ASSETS.md](references/assets/FOREIGN-ASSETS.md) |
| Operating-business continuity after death/incapacity | [assets/BUSINESS-CONTINUITY.md](references/assets/BUSINESS-CONTINUITY.md) |
| Dementia / cognitive decline planning | [incapacity/HEALTHCARE-AND-DIRECTIVES.md](references/incapacity/HEALTHCARE-AND-DIRECTIVES.md) |
| Mental health history, Ulysses clause | [incapacity/MENTAL-HEALTH-DIRECTIVES.md](references/incapacity/MENTAL-HEALTH-DIRECTIVES.md) |
| Long-term care, nursing home, Medicaid | [incapacity/LONG-TERM-CARE.md](references/incapacity/LONG-TERM-CARE.md), [MEDICAID-PLANNING.md](references/incapacity/MEDICAID-PLANNING.md) |
| Need execution / signing / e-will / TOD routing | [execution-formalities/README.md](references/execution-formalities/README.md) |
| Revocable trust design | [advanced-planning/REVOCABLE-LIVING-TRUST.md](references/advanced-planning/REVOCABLE-LIVING-TRUST.md) |
| QTIP, credit shelter | [advanced-planning/CREDIT-SHELTER-QTIP.md](references/advanced-planning/CREDIT-SHELTER-QTIP.md) |
| GRAT, IDGT sale | [advanced-planning/GRAT-IDGT.md](references/advanced-planning/GRAT-IDGT.md) |
| SLAT, QPRT | [advanced-planning/SLAT-QPRT.md](references/advanced-planning/SLAT-QPRT.md) |
| Dynasty trust, GST | [advanced-planning/DYNASTY-GST-PLANNING.md](references/advanced-planning/DYNASTY-GST-PLANNING.md) |
| Charitable (DAF, CRT, CLT, private foundation) | [advanced-planning/CHARITABLE-PLANNING.md](references/advanced-planning/CHARITABLE-PLANNING.md) |
| Asset protection (DAPT, offshore) | [advanced-planning/ASSET-PROTECTION.md](references/advanced-planning/ASSET-PROTECTION.md) |
| Basis step-up strategy | [advanced-planning/STEP-UP-BASIS-PLANNING.md](references/advanced-planning/STEP-UP-BASIS-PLANNING.md) |
| Trust situs (SD, NV, DE, WY) | [advanced-planning/TRUST-SITUS.md](references/advanced-planning/TRUST-SITUS.md) |
| Executor duties post-death | [post-death/EXECUTOR-PLAYBOOK.md](references/post-death/EXECUTOR-PLAYBOOK.md) |
| Disclaim an inheritance | [post-death/DISCLAIMERS.md](references/post-death/DISCLAIMERS.md) |
| Receiving an inheritance | [post-death/HEIR-PLAYBOOK.md](references/post-death/HEIR-PLAYBOOK.md) |
| Funeral, disposition, organ donation | [legacy-and-logistics/FUNERAL-AND-DISPOSITION.md](references/legacy-and-logistics/FUNERAL-AND-DISPOSITION.md) |
| Digital legacy, social media, email | [legacy-and-logistics/DIGITAL-LEGACY.md](references/legacy-and-logistics/DIGITAL-LEGACY.md) |
| Ethical will, legacy letter | [legacy-and-logistics/ETHICAL-WILL.md](references/legacy-and-logistics/ETHICAL-WILL.md) |
| Family meeting, talking to heirs | [legacy-and-logistics/FAMILY-COMMUNICATION.md](references/legacy-and-logistics/FAMILY-COMMUNICATION.md) |
| Need profession-specific overlay | [professions/README.md](references/professions/README.md) |
| Need situation-specific overlay | [situations/README.md](references/situations/README.md) |
| Need life-event-specific review | [life-events/README.md](references/life-events/README.md) |
| Probate, intestacy | [foundations/PROBATE-AND-INTESTACY.md](references/foundations/PROBATE-AND-INTESTACY.md) |
| Federal estate/gift/GST tax (2026) | [foundations/FEDERAL-TRANSFER-TAX.md](references/foundations/FEDERAL-TRANSFER-TAX.md) |
| State estate / inheritance tax | [foundations/STATE-ESTATE-TAX.md](references/foundations/STATE-ESTATE-TAX.md) |
| Domicile, residency, relocation | [foundations/DOMICILE.md](references/foundations/DOMICILE.md) |
| Core documents overview | [foundations/CORE-DOCUMENTS.md](references/foundations/CORE-DOCUMENTS.md) |
| Full anti-pattern catalog | [anti-patterns/ANTI-PATTERNS.md](references/anti-patterns/ANTI-PATTERNS.md) |

---

## ANTI-PATTERNS (Shortlist — full list in references)

- **Treating the will as the plan.** For many households, a large share of the balance sheet passes outside probate by contract and title. A will alone is not the plan.
- **Naming minors directly as beneficiaries.** Usually pushes money into court-supervised property management or an outright handoff at the applicable release age. Use a trust or other deliberate structure.
- **"Everything to spouse, trust the spouse to take care of my kids" in a blended family.** That can fail badly if there is no protected-remainder structure. Use a QTIP or similar design when the first-marriage children's protection really matters.
- **Leaving a vacation home to "all my kids equally."** Often sets up deadlock and partition risk. Use governance, buyout terms, or a sale plan instead.
- **Putting seed phrases or passwords in the will.** Will becomes public record at probate.
- **Setting up an ILIT when the estate is well below the relevant federal and state transfer-tax thresholds and there is no separate liquidity, control, or family-structure reason.** Often adds irrevocability and administration without enough payoff.
- **Aggressive lifetime gifting of appreciated assets below the exemption.** Often trades step-up basis for transfer-tax savings that the estate was unlikely to need after federal and state modeling.
- **Naming the estate (not a person or trust) as the life-insurance or retirement-account beneficiary without a specific reason.** Forces probate; and for retirement accounts often accelerates taxable payout.
- **Springing POA that requires physician certification.** Fails in practice. Banks reject. Use immediate POA with a trusted agent.
- **Co-executors or co-trustees in a conflicted family.** Guarantees gridlock.
- **Handwritten ("holographic") wills in states that barely recognize them.** Litigation magnet.
- **Updating documents a week before death under pressure from a new caregiver.** Classic undue-influence setup.
- **Ignoring the $60,000 NRA exemption trap for non-resident-alien spouses owning U.S. assets.**
- **Failing to file Form 706 for portability after the first spouse's death.** Leaves the DSUE on the table — often millions in future exemption.
- **Funding a revocable trust on paper but never re-titling assets into it.** A paper trust alone does very little for major assets left outside it, and the pour-over cleanup can still leave those assets in probate.

Full catalog: [anti-patterns/ANTI-PATTERNS.md](references/anti-patterns/ANTI-PATTERNS.md).

---

## VALIDATION (Before Declaring the Plan Complete)

- [ ] Every named agent (executor, trustee, guardian, POA agent, healthcare agent) has a primary AND at least one successor
- [ ] Every asset on the inventory is matched to a controlling document (will, trust, beneficiary form, or title)
- [ ] Beneficiary map reconciles with the will and trust — no contradictions
- [ ] Incapacity package is complete (financial POA + healthcare POA + living will + HIPAA + dementia directive if indicated)
- [ ] Digital-asset inventory exists; location of seed phrases / password-manager master is documented separately from the will
- [ ] Liquidity test: can the estate pay taxes, mortgages, and administration expenses on Day 270 without forced sales?
- [ ] Domicile confirmed; out-of-state real estate has a verified state-specific transfer strategy
- [ ] State estate tax projection run if net worth ≥ applicable state exemption
- [ ] `analyses/official-source-log.md` exists and records every current-law verification the plan depends on
- [ ] `analyses/plan-coverage-matrix.md` exists and proves which overlays and deliverables were required
- [ ] `analyses/document-quality-triage.md` distinguishes authoritative documents from weak evidence
- [ ] `analyses/red-flag-triage.md` exists and distinguishes critical issues from cleanup
- [ ] `analyses/evidence-confidence-map.md` identifies any material facts still based on weak evidence
- [ ] `analyses/recommendation-confidence-register.md` makes conditional recommendations explicit
- [ ] `analyses/fiduciary-bench-scorecard.md` compares realistic primary and backup fiduciaries
- [ ] `analyses/stress-test-scenarios.md` has been completed for at least death tonight, incapacity, fiduciary failure, and digital lockout
- [ ] `analyses/litigation-risk-memo.md` addresses contest, capacity, undue-influence, and fiduciary-conflict risks where applicable
- [ ] Blended-family test: if survivor remarried, would the first-marriage children still be protected?
- [ ] Vulnerable-heir test: would any distribution disqualify a beneficiary from means-tested benefits?
- [ ] Letter of instruction exists, names known to executor, location known
- [ ] Family meeting held OR scheduled (or explicit reason for declining documented)
- [ ] Attorney handoff packet generated: plan report + inventory + draft wishes + interview questions
- [ ] `deliverables/implementation-ledger.md` exists and shows what still must be retitled / updated
- [ ] `deliverables/signing-readiness-checklist.md` exists when signing / execution logistics are part of the active mode or implementation path
- [ ] `deliverables/institution-contact-matrix.md` and `deliverables/beneficiary-change-packet.md` exist when institution-specific implementation work is required
- [ ] `deliverables/funding-proof-log.md` exists or the workspace explicitly states no funding / titling proof is required
- [ ] `analyses/attorney-handoff-readiness.md` scores whether counsel can draft efficiently from this packet
- [ ] Review cadence set (3–5 years + life-event triggers)

Run `./scripts/plan-validator.py <project-dir>` as a backstop for structural misses and untouched starter outputs. It is not a substitute for legal reasoning, source verification, or adaptive judgment.

---

## DISCLAIMER (Present Every Session)

This skill produces **educational drafts for review by a licensed attorney** in the user's state. It does not:

- Constitute legal, tax, or financial advice
- Create an attorney-client relationship
- Replace a licensed estate-planning attorney, CPA, or financial advisor
- Execute, witness, notarize, file, or record any document
- Substitute for state-specific analysis — state laws vary substantially

For anyone with more than a trivial estate, minor children, a blended family, a business, disability in the family, or unusual circumstances: **hire a qualified attorney.** Full disclaimer: [assets/DISCLAIMER.md](assets/DISCLAIMER.md).

---

## Reference Index

**Methodology:** [OPERATING-MODES](references/methodology/OPERATING-MODES.md) · [OVERLAY-RESOLVER](references/methodology/OVERLAY-RESOLVER.md) · [KERNEL](references/methodology/KERNEL.md) · [OPERATORS](references/methodology/OPERATORS.md) · [TIER-TRIAGE](references/methodology/TIER-TRIAGE.md) · [INTERVIEW-FLOW](references/methodology/INTERVIEW-FLOW.md) · [RED-FLAG-CHECKLIST](references/methodology/RED-FLAG-CHECKLIST.md) · [DOCUMENT-CHECKLIST](references/methodology/DOCUMENT-CHECKLIST.md) · [DOCUMENT-INGESTION](references/methodology/DOCUMENT-INGESTION.md) · [CONFIDENCE-SCORING](references/methodology/CONFIDENCE-SCORING.md) · [FIDUCIARY-SCORING](references/methodology/FIDUCIARY-SCORING.md) · [IMPLEMENTATION-OPS](references/methodology/IMPLEMENTATION-OPS.md) · [LITIGATION-DEFENSE](references/methodology/LITIGATION-DEFENSE.md) · [CROSS-BORDER-ESCALATION](references/methodology/CROSS-BORDER-ESCALATION.md) · [ATTORNEY-HANDOFF-RUBRIC](references/methodology/ATTORNEY-HANDOFF-RUBRIC.md) · [STRATEGY-INTERACTION-MATRIX](references/methodology/STRATEGY-INTERACTION-MATRIX.md) · [PLAN-MAINTENANCE-OS](references/methodology/PLAN-MAINTENANCE-OS.md) · [STRESS-TEST-SCENARIOS](references/methodology/STRESS-TEST-SCENARIOS.md) · [VERIFICATION-FIRST](references/methodology/VERIFICATION-FIRST.md) · [SOURCE-COVERAGE-MAP](references/methodology/SOURCE-COVERAGE-MAP.md)

**Intake:** [INTAKE-QUESTIONNAIRE](references/intake/INTAKE-QUESTIONNAIRE.md) · [ARCHETYPE-START-PACKS](references/intake/ARCHETYPE-START-PACKS.md)

**Foundations:** [CORE-DOCUMENTS](references/foundations/CORE-DOCUMENTS.md) · [PROBATE-AND-INTESTACY](references/foundations/PROBATE-AND-INTESTACY.md) · [FEDERAL-TRANSFER-TAX](references/foundations/FEDERAL-TRANSFER-TAX.md) · [STATE-ESTATE-TAX](references/foundations/STATE-ESTATE-TAX.md) · [DOMICILE](references/foundations/DOMICILE.md) · [BENEFICIARY-COORDINATION](references/foundations/BENEFICIARY-COORDINATION.md)

**Family Structures:** see routing table above.

**Assets:** see routing table above, including [INSTITUTIONAL-OPERATIONS](references/assets/INSTITUTIONAL-OPERATIONS.md) and [BUSINESS-CONTINUITY](references/assets/BUSINESS-CONTINUITY.md).

**Incapacity:** [DURABLE-POA](references/incapacity/DURABLE-POA.md) · [HEALTHCARE-AND-DIRECTIVES](references/incapacity/HEALTHCARE-AND-DIRECTIVES.md) · [POLST-MOLST](references/incapacity/POLST-MOLST.md) · [MENTAL-HEALTH-DIRECTIVES](references/incapacity/MENTAL-HEALTH-DIRECTIVES.md) · [LONG-TERM-CARE](references/incapacity/LONG-TERM-CARE.md) · [MEDICAID-PLANNING](references/incapacity/MEDICAID-PLANNING.md)

**Advanced Planning:** see routing table above.

**Tiers:** see routing table above.

**Post-Death:** [EXECUTOR-PLAYBOOK](references/post-death/EXECUTOR-PLAYBOOK.md) · [HEIR-PLAYBOOK](references/post-death/HEIR-PLAYBOOK.md) · [DISCLAIMERS](references/post-death/DISCLAIMERS.md)

**Legacy & Logistics:** [FUNERAL-AND-DISPOSITION](references/legacy-and-logistics/FUNERAL-AND-DISPOSITION.md) · [DIGITAL-LEGACY](references/legacy-and-logistics/DIGITAL-LEGACY.md) · [ETHICAL-WILL](references/legacy-and-logistics/ETHICAL-WILL.md) · [FAMILY-COMMUNICATION](references/legacy-and-logistics/FAMILY-COMMUNICATION.md)

**Anti-Patterns:** [ANTI-PATTERNS](references/anti-patterns/ANTI-PATTERNS.md)

**Assets (Templates):** [ASSET-INVENTORY](assets/ASSET-INVENTORY.md) · [BENEFICIARY-MAP](assets/BENEFICIARY-MAP.md) · [CURRENT-DOCUMENT-AUDIT](assets/CURRENT-DOCUMENT-AUDIT.md) · [BENEFICIARY-FORM-AUDIT](assets/BENEFICIARY-FORM-AUDIT.md) · [TITLING-AUDIT](assets/TITLING-AUDIT.md) · [COHERENCE-AUDIT](assets/COHERENCE-AUDIT.md) · [TAX-EXPOSURE-ANALYSIS](assets/TAX-EXPOSURE-ANALYSIS.md) · [LIQUIDITY-ANALYSIS](assets/LIQUIDITY-ANALYSIS.md) · [PRIOR-PLAN-GAP-ANALYSIS](assets/PRIOR-PLAN-GAP-ANALYSIS.md) · [DECISION-LEDGER](assets/DECISION-LEDGER.md) · [OFFICIAL-SOURCE-LOG](assets/OFFICIAL-SOURCE-LOG.md) · [PLAN-COVERAGE-MATRIX](assets/PLAN-COVERAGE-MATRIX.md) · [DOCUMENT-QUALITY-TRIAGE](assets/DOCUMENT-QUALITY-TRIAGE.md) · [RED-FLAG-TRIAGE](assets/RED-FLAG-TRIAGE.md) · [DOCUMENT-ACQUISITION-PLAN](assets/DOCUMENT-ACQUISITION-PLAN.md) · [EVIDENCE-CONFIDENCE-MAP](assets/EVIDENCE-CONFIDENCE-MAP.md) · [RECOMMENDATION-CONFIDENCE-REGISTER](assets/RECOMMENDATION-CONFIDENCE-REGISTER.md) · [FIDUCIARY-BENCH-SCORECARD](assets/FIDUCIARY-BENCH-SCORECARD.md) · [LITIGATION-RISK-MEMO](assets/LITIGATION-RISK-MEMO.md) · [STRESS-TEST-SCENARIOS](assets/STRESS-TEST-SCENARIOS.md) · [IMPLEMENTATION-LEDGER](assets/IMPLEMENTATION-LEDGER.md) · [SIGNING-READINESS-CHECKLIST](assets/SIGNING-READINESS-CHECKLIST.md) · [FUNDING-PROOF-LOG](assets/FUNDING-PROOF-LOG.md) · [INSTITUTION-CONTACT-MATRIX](assets/INSTITUTION-CONTACT-MATRIX.md) · [BENEFICIARY-CHANGE-PACKET](assets/BENEFICIARY-CHANGE-PACKET.md) · [LETTER-OF-INSTRUCTION](assets/LETTER-OF-INSTRUCTION.md) · [DIGITAL-INVENTORY](assets/DIGITAL-INVENTORY.md) · [PERSONAL-PROPERTY-MEMORANDUM](assets/PERSONAL-PROPERTY-MEMORANDUM.md) · [LETTER-OF-WISHES](assets/LETTER-OF-WISHES.md) · [ETHICAL-WILL-TEMPLATE](assets/ETHICAL-WILL-TEMPLATE.md) · [FAMILY-MEETING-AGENDA](assets/FAMILY-MEETING-AGENDA.md) · [CONFLICT-PREVENTION-PLAN](assets/CONFLICT-PREVENTION-PLAN.md) · [IF-I-DIE-TOMORROW](assets/IF-I-DIE-TOMORROW.md) · [EXECUTOR-CHECKLIST](assets/EXECUTOR-CHECKLIST.md) · [BUSINESS-CONTINUITY-ACTIVATION](assets/BUSINESS-CONTINUITY-ACTIVATION.md) · [FOREIGN-AND-CONFLICT-OF-LAWS-REVIEW](assets/FOREIGN-AND-CONFLICT-OF-LAWS-REVIEW.md) · [ATTORNEY-HANDOFF-READINESS](assets/ATTORNEY-HANDOFF-READINESS.md) · [DISPOSITION-OF-REMAINS](assets/DISPOSITION-OF-REMAINS.md) · [ATTORNEY-INTERVIEW](assets/ATTORNEY-INTERVIEW.md) · [ATTORNEY-ENGAGEMENT-BRIEF](assets/ATTORNEY-ENGAGEMENT-BRIEF.md) · [DOCUMENT-PACKAGE-INDEX](assets/DOCUMENT-PACKAGE-INDEX.md) · [REVIEW-SCHEDULE](assets/REVIEW-SCHEDULE.md) · [COMPREHENSIVE-PLAN-REPORT](assets/COMPREHENSIVE-PLAN-REPORT.md) · [DISCLAIMER](assets/DISCLAIMER.md)

**Scripts:** `scripts/intake-session.sh` · `scripts/plan-validator.py`

**State-Specific:** [states/README](references/states/README.md) · [execution-formalities/README](references/execution-formalities/README.md) · [CALIFORNIA](references/states/CALIFORNIA.md) · [NEW-YORK](references/states/NEW-YORK.md) · [MASSACHUSETTS](references/states/MASSACHUSETTS.md) · [FLORIDA](references/states/FLORIDA.md) · [TEXAS](references/states/TEXAS.md) · [WASHINGTON](references/states/WASHINGTON.md) · [OTHER-ESTATE-TAX-STATES](references/states/OTHER-ESTATE-TAX-STATES.md)

**Profession Overlays:** [professions/README](references/professions/README.md) · [PHYSICIAN](references/professions/PHYSICIAN.md) · [EXECUTIVE](references/professions/EXECUTIVE.md) · [FOUNDER](references/professions/FOUNDER.md) · [ATTORNEY](references/professions/ATTORNEY.md) · [REAL-ESTATE-INVESTOR](references/professions/REAL-ESTATE-INVESTOR.md) · [SOFTWARE-ENGINEER](references/professions/SOFTWARE-ENGINEER.md) · [BUSINESS-OWNER](references/professions/BUSINESS-OWNER.md) · [ARTIST-CREATIVE](references/professions/ARTIST-CREATIVE.md) · [ATHLETE-ENTERTAINER](references/professions/ATHLETE-ENTERTAINER.md) · [MILITARY](references/professions/MILITARY.md) · [ACADEMIC](references/professions/ACADEMIC.md) · [PUBLIC-EMPLOYEE](references/professions/PUBLIC-EMPLOYEE.md)

**Life Event Triggers:** [life-events/README](references/life-events/README.md) · [MARRIAGE](references/life-events/MARRIAGE.md) · [DIVORCE](references/life-events/DIVORCE.md) · [CHILD-BIRTH-ADOPTION](references/life-events/CHILD-BIRTH-ADOPTION.md) · [MOVING-STATES](references/life-events/MOVING-STATES.md) · [INHERITANCE-RECEIVED](references/life-events/INHERITANCE-RECEIVED.md) · [BUSINESS-SALE-OR-IPO](references/life-events/BUSINESS-SALE-OR-IPO.md) · [RETIREMENT](references/life-events/RETIREMENT.md) · [DIAGNOSIS-SERIOUS-ILLNESS](references/life-events/DIAGNOSIS-SERIOUS-ILLNESS.md) · [BECOMING-CAREGIVER](references/life-events/BECOMING-CAREGIVER.md) · [DEATH-OF-FAMILY-MEMBER](references/life-events/DEATH-OF-FAMILY-MEMBER.md) · [STARTING-BUSINESS](references/life-events/STARTING-BUSINESS.md) · [NEW-PROPERTY-PURCHASE](references/life-events/NEW-PROPERTY-PURCHASE.md)

**Situation Profiles:** [situations/README](references/situations/README.md) · [AGING-ALONE](references/situations/AGING-ALONE.md) · [CAREGIVER-FOR-PARENT](references/situations/CAREGIVER-FOR-PARENT.md) · [EXPATRIATE-ABROAD](references/situations/EXPATRIATE-ABROAD.md) · [IMMIGRANT-NEW-TO-US](references/situations/IMMIGRANT-NEW-TO-US.md) · [LGBTQ-PLANNING](references/situations/LGBTQ-PLANNING.md) · [SAME-SEX-MARRIED-COUPLE](references/situations/SAME-SEX-MARRIED-COUPLE.md) · [POLYAMOROUS-OR-UNCONVENTIONAL-FAMILY](references/situations/POLYAMOROUS-OR-UNCONVENTIONAL-FAMILY.md) · [RELIGIOUS-MINORITY](references/situations/RELIGIOUS-MINORITY.md) · [GRANDPARENT-RAISING-GRANDCHILD](references/situations/GRANDPARENT-RAISING-GRANDCHILD.md) · [ESTRANGED-FAMILY](references/situations/ESTRANGED-FAMILY.md) · [FAMILY-BUSINESS-OWNER](references/situations/FAMILY-BUSINESS-OWNER.md) · [DEBT-HEAVY](references/situations/DEBT-HEAVY.md) · [RECOVERY-FROM-ADDICTION](references/situations/RECOVERY-FROM-ADDICTION.md)

**Subagents:** [subagents/README](subagents/README.md) · [intake-conductor](subagents/intake-conductor.md) · [document-organizer](subagents/document-organizer.md) · [asset-discovery-auditor](subagents/asset-discovery-auditor.md) · [beneficiary-audit](subagents/beneficiary-audit.md) · [anti-pattern-scanner](subagents/anti-pattern-scanner.md) · [tax-analyzer](subagents/tax-analyzer.md) · [execution-formalities-router](subagents/execution-formalities-router.md) · [state-law-verifier](subagents/state-law-verifier.md) · [overlay-resolver](subagents/overlay-resolver.md) · [fiduciary-bench-builder](subagents/fiduciary-bench-builder.md) · [implementation-ops-planner](subagents/implementation-ops-planner.md) · [funding-checklist-generator](subagents/funding-checklist-generator.md) · [conflict-prevention-planner](subagents/conflict-prevention-planner.md) · [litigation-defense-reviewer](subagents/litigation-defense-reviewer.md) · [multi-model-validator](subagents/multi-model-validator.md) · [deliverables-generator](subagents/deliverables-generator.md)

---

## PROJECT DIRECTORY WORKFLOW

**Strongly recommended:** run this skill inside a dedicated project directory that holds the user's financial documents, prior wills, insurance policies, tax returns, and deliverables. This mirrors the pattern used by `tax-return-preparation-and-advice-generic`.

Use [PROJECT-SETUP.md](assets/PROJECT-SETUP.md) as the blueprint. Typical structure:

```
my-estate-plan/
├── intake/                  # intake record + session summaries
├── current-documents/       # existing will, trust, POAs, beneficiary forms
├── financial-documents/     # account statements, tax returns, life insurance policies, deeds
├── analyses/                # audit outputs, tax analysis, coherence review, source log
├── deliverables/            # plan report, asset inventory, beneficiary map, handoff packet
├── correspondence/          # attorney/family communication
├── identity-documents/      # IDs, marriage/divorce/naturalization records
├── beneficiary-information/ # info on named beneficiaries and fiduciaries
└── digital-vault/           # recovery-process references, never seed phrases or master passwords
```

The skill reads from `current-documents/` and `financial-documents/`, writes to `intake/`, `analyses/`, and `deliverables/`.

---

## PRIVILEGE, CONFIDENTIALITY, AND THE `finalize-and-cleanse` MODE

AI chat transcripts and this skill's intake architecture (intake record, decision ledger, letter of wishes, iteration drafts) accumulate a detailed contemporaneous record of the testator's thinking. Recent case law — including at least one New York decision — has held that consumer-grade AI conversations do not carry attorney-client privilege, and that discussing otherwise-privileged legal matters with a chatbot can forfeit the privilege in a later conversation with a real lawyer on the same subject. For HNW/UHNW testators who anticipate their estate may be contested, that record is exactly what a contest lawyer wants to see.

The `finalize-and-cleanse` mode addresses this by giving the user a deliberate, audited way to remove the intermediate paper trail on files they own, at their direction, at a time when no litigation is pending. It is **not** spoliation of evidence, and it is **not** a substitute for legal advice.

### When to offer `finalize-and-cleanse`

Offer it at the end of any session where the user has produced a final deliverable and confirmed they are done iterating. Use the [`finalize-and-cleanse-subagent`](subagents/finalize-and-cleanse-subagent.md) to walk them through the flow.

### When NOT to offer it (hard rules)

- **Bedside / deathbed drafting.** These require a human attorney as drafter and witness. Tell the user and do not offer cleanup.
- **Active or anticipated litigation.** If the user mentions a probate dispute, pending challenge, or ongoing legal matter connected to this plan, refer them to their attorney. Deleting records during pending litigation is spoliation.
- **Professional fiduciary handling someone else's estate.** Cleanup is for the testator's own files, not records held in a fiduciary capacity.
- **Business records with external retention obligations.** SEC, FINRA, healthcare, or other regulated-records duties override this cleanup; refer to counsel.

### The flow (summary)

1. Confirm the user is fully done iterating.
2. Have the user curate `deliverables/final/` — the subset they want preserved locally.
3. Instruct the user to save the final package to durable storage AND email a copy to at least one address not on the same laptop (themselves at a different provider, their attorney, their spouse, or their executor).
4. User creates `FINAL_PACKAGE_SAVED.txt` by hand, documenting where they saved and whom they emailed. The script refuses to run if this file is missing or lacks `@`, `EMAILED`/`SENT`, and `SAVED`/`STORED`.
5. User is shown exactly what will be deleted and preserved, in plain language.
6. User types the literal confirmation string `YES I SAVED AND EMAILED THE FINAL PACKAGE` at the terminal. Anything else aborts.
7. [`scripts/finalize-and-cleanse.sh`](scripts/finalize-and-cleanse.sh) wipes intermediate directories (`intake/`, `analyses/`, `decisions/`, `drafts/`, `session-logs/`, `working/`, `tmp/`, plus the non-`final/` portion of `deliverables/`) and pattern-matched files (`*.tmp`, `*.scratch.*`, `DRAFT_*`, `SCRATCH_*`, `*.draft.md`) and writes `CLEANED.md` with a summary.

### What is preserved

`FINAL_PACKAGE_SAVED.txt`, `CLEANED.md`, `deliverables/final/` (user's curated subset), `user-provided/` (original uploads), any path listed in `intake-inputs.txt`, and anything outside the swept directories and patterns.

### Containment guardrails

The script refuses to run on `/`, the user's `$HOME`, or any path shallower than three directory levels from root. It uses `realpath`-style resolution on every target to defend against symlinks pointing outside the working folder. These are belt-and-suspenders; the primary safety is the three-gate consent flow (flag + marker file + typed confirmation).
