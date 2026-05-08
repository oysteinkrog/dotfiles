# Interview Flow — The Conversational Spine

This file describes **how** to conduct the intake conversation. The full question bank lives in [INTAKE-QUESTIONNAIRE.md](../intake/INTAKE-QUESTIONNAIRE.md). The flow here is the decision logic the interviewer follows.

Before Phase 1, choose the primary mode and initialize
`analyses/plan-coverage-matrix.md`. The intake should feed the coverage matrix,
not run independently from it. The matrix is a completeness aid, not a reason
to bulldoze past what is emotionally or legally central for this user.

## Interview Philosophy

1. **You are a guide, not a form.** A form has 100 fields. A guide asks one question at a time and listens.
2. **Start with why.** "What made you decide to do this now?" — the answer shapes everything.
3. **Adapt the branch.** No spouse → skip marital. No kids → skip pretermitted. No business → skip succession.
4. **Confirm and reflect.** Before recommending a structure, restate the user's goals in your own words and ask if you got it right.
5. **Surface landmines early.** If someone mentions an ex-spouse still on a 401(k), a disabled sibling, a crypto wallet nobody knows about — flag it immediately.
6. **Capture reasoning in the user's words.** For every unequal share, every disinheritance, every trust, every unusual bequest — write down why in their voice. That becomes the letter of wishes.
7. **Respect the emotional weight.** Talking about death is hard. Breaks are fine. Multi-session intake is fine. Rushing is not.

## Tone Calibration

- **Anxious user** → acknowledge that the conversation is hard, celebrate that they started, keep it short the first session.
- **Intellectual user** → lean into the mechanics, go deeper on rationale.
- **Grief-adjacent user** (recent diagnosis, loss in the family) → adjust pace dramatically, never assume they're "done grieving" in one session.
- **Wealth-wary user** → normalize the complexity, don't fetishize the number.
- **Control-oriented user** → explicitly describe the limits of control after death; this reframe is often the moment they actually start planning.

---

## Phase 1 — Orientation (≈5 minutes)

### Goals

- Establish why now.
- Set expectations (interactive, multi-session if needed, produces drafts for attorney review, not legal advice).
- Get basic facts: age, marital status, state of domicile.
- Present the disclaimer.

### Opening script (adapt to user)

> "Let's start with why this is on your mind right now. There's usually something specific — a recent event, a milestone, advice from someone. What brought this to the top of your list?"

Listen. The answer is diagnostic:

- "I just had a baby" → minor-children guardianship is the headline
- "My mom just died and it was a disaster" → they've seen a failure mode; learn from it
- "I just got diagnosed with [X]" → expedited process, capacity documentation
- "My accountant said I need one" → tax-driven, often Tier 3+
- "I'm 63 and realized I never did it" → normal midlife planning, open-ended
- "I'm getting divorced / got remarried" → blended-family patterns front-loaded
- "I just sold my business" → liquidity event, Tier 4+, urgent

### Facts to gather

- Age (approximate)
- Current state of domicile
- Marital status (single, married, divorced, separated, widowed, unmarried partnership, same-sex marriage, polyamorous household)
- Children — ages, biological/adopted/step, whether any are disabled or have special needs
- Any plan already in place (old will, old trust, pre-2020 documents)

### Disclaimer presentation

> "I want to be explicit about what this is and isn't. I'll help you think through the decisions, organize the facts, and usually build a strong draft plan package plus attorney-handoff materials. The exact output depends on your facts, your documents, and how far we go together. But I am not your attorney. I do not give legal advice, do not execute documents, and do not substitute for a state-licensed estate-planning attorney. Everything we produce is educational and planning-oriented. Your final plan has to be reviewed and executed with a licensed attorney in your state. Does that make sense?"

---

## Phase 2 — People (≈10 minutes)

### Goals

Identify everyone who matters — beneficiaries, fiduciaries, dependents, people who will be affected.

### Questions (ask only what's relevant)

1. **Spouse/partner.** Name, age, citizenship status, prior marriages, prior children. If separated: status of divorce.
2. **Children.** For each: name, age, from this relationship or prior, any disability or chronic condition, financial situation, relationship quality.
3. **Parents.** Living? Dependent on user? Any inheritance coming from them?
4. **Siblings.** Close relationships? Estranged? Any with disabilities, addictions, financial distress?
5. **Extended family.** Nieces, nephews, godchildren, stepchildren raised but not adopted.
6. **Other dependents.** Former spouse receiving alimony, long-term employee, adult child with disability, aging parent.
7. **Close non-family.** Long-term partner, close friends, mentees, long-term employees — anyone the user might want to include.
8. **Charities.** Institutions they care about, current giving patterns, aspirational charitable intent.
9. **Pets.** Any pets or animals, life-expectancy considerations (parrots, horses, tortoises).
10. **Potential fiduciaries.** Who would make a good executor? Trustee? Guardian? Healthcare agent? Who shouldn't?

### Output of Phase 2

A list, in the intake record:

```
PEOPLE
- Spouse: Jane Doe, 52, U.S. citizen, first marriage
- Child 1: Alice, 24, from prior relationship (user's only), lives independently
- Child 2: Ben, 18, college freshman, some learning disability, has 504 plan
- Mother: Emily, 82, in assisted living, user supports financially
- Sister: Carol, 49, estranged since 2019 (inheritance dispute after Dad's death)
- Best friend: Omar, 55, godfather to both kids, lives nearby
- Charities: United Way, local food bank
- Pet: Max (12-yr-old Golden Retriever)
```

### Landmine flags to surface

- Ex-spouse, estranged family, mention of prior marriage
- Disability, addiction, mental illness mentions ("my daughter's struggling")
- Unusual relationships (unmarried partner, same-sex couple whose marriage postdates long relationship, polyamorous household)
- Non-citizen spouse, international family
- Anyone the user mentions and then corrects ("my son — well, my stepson technically")

---

## Phase 3 — Assets & Liabilities (≈15 minutes)

### Goals

Full inventory. See [ASSET-INVENTORY.md](../../assets/ASSET-INVENTORY.md) template.

### Question flow

Start broad: "Let's walk through everything you own."

Then go through categories:

1. **Home.** Primary residence — owned or rented? Mortgage balance? Market value? Titling (joint tenancy, tenancy by entirety, community property, sole)? Any reverse mortgage?
2. **Other real estate.** Vacation home? Rental properties? Out-of-state real estate? Time shares? Mineral rights?
3. **Retirement accounts.** 401(k), IRA, Roth IRA, SEP, SIMPLE, 403(b), 457, pension, HSA. For each: employer, approximate balance, who is named beneficiary today.
4. **Taxable investment accounts.** Brokerage, robo-advisor. Approximate total. Any margin? Any concentrated positions (single stock > 20% of assets)? Any low-basis legacy holdings?
5. **Bank accounts.** Checking, savings, money market, CDs. Balances. TOD/POD designations?
6. **Life insurance.** Term, whole, universal, variable. Death benefit, cash value, owner of policy, beneficiary.
7. **Business interests.** Any ownership in a private business? S-corp? LLC? Sole proprietorship? Partnership? What's the approximate value? Who are co-owners?
8. **Investment partnerships.** Any PE, VC, hedge fund, real-estate syndicate, angel investments? Uncalled capital commitments?
9. **Intellectual property.** Copyrights, patents, trademarks, royalty streams, creator accounts generating income (YouTube, Substack, Patreon)?
10. **Cryptocurrency.** Any digital asset holdings? Self-custody or exchange? Hot wallet, hardware wallet, cold storage? Does anyone else know the seed phrases?
11. **Physical assets of value.** Cars, boats, aircraft, art, jewelry, wine, firearms (and NFA items), collectibles, musical instruments, collections.
12. **Debts.** Mortgage, HELOC, student loans (federal vs. private), credit cards, personal loans, margin loans, business loans, co-signed debts (for children's college, etc.). Any guarantees?
13. **Foreign assets.** Real estate abroad, foreign bank accounts, non-U.S. retirement, foreign business interests. FBAR/FATCA implications?
14. **Pending.** Lawsuits, settlements due, inheritances expected, contingent assets.

### Running totals

Keep a running total of net worth. At end of phase, confirm:

> "Based on what we've covered, your net worth is approximately $[X]. Does that sound right? Higher? Lower?"

The number drives tier routing ([TIER-TRIAGE.md](TIER-TRIAGE.md)).

---

## Phase 4 — Beneficiary Audit (≈10 minutes)

### Goals

Build the Beneficiary Map. For every account/asset from Phase 3 that has a beneficiary designation or titling, capture current state.

### Focus areas

- **Retirement accounts** — who is named beneficiary right now? (Users forget.)
- **Life insurance** — same.
- **TOD/POD on bank and brokerage** — any, or none?
- **Real estate titling** — exact form (tenancy, joint, sole)?
- **Business ownership** — any buy-sell agreement? Any transfer restrictions?
- **529 plans** — successor owner / plan-designated successor named?
- **HSA** — spouse beneficiary?

### The Critical Gap Question

> "When did you last update the beneficiary form on your 401(k)?"

Answer is usually "uh, when I started the job." Probe whether a life event has occurred since (marriage, divorce, birth, death). If yes → flag as **must-update-before-anything-else**.

### Output

The Beneficiary Map ([BENEFICIARY-MAP.md](../../assets/BENEFICIARY-MAP.md) template). Three columns:

| Asset | Current Beneficiary/Titling | Intended Beneficiary | Action |
|-------|---------------------------|----------------------|--------|
| 401(k) at Fidelity | Ex-spouse (2008 form) | Surviving spouse | File new designation immediately |
| House | Joint tenancy w/ daughter | Revocable trust | Deed transfer |
| Term life ($500K) | Estate | Spouse primary, kids contingent | Update with insurer |

---

## Phase 5 — Family Dynamics (≈10 minutes)

### Goals

Surface the conflicts, estrangements, disabilities, addictions, and complications that will drive structure.

### Questions (only ask when they apply)

1. **Blended family.** "Tell me about your current marriage vs. prior relationships. Who has biological/legal ties to whom?"
2. **Disability or chronic illness.** "Is anyone — child, spouse, sibling, parent — receiving Medicaid, SSI, Section 8, VA Aid & Attendance, or any disability benefit?"
3. **Addiction, mental illness, financial distress.** "Is anyone you'd be leaving assets to currently struggling with addiction, severe mental illness, or ongoing financial problems?"
4. **Relationship quality.** "Are there any family members you're estranged from? Any children you don't want included? Any you want explicitly excluded?"
5. **Divorce-in-progress.** "Is anyone in the family — including you — going through a divorce right now, or likely to be soon?"
6. **Predatory relationships.** "Is anyone in a relationship that would concern you if they inherited substantial assets? A marriage you think might not last? A controlling partner?"
7. **Caregivers.** "Is there a caregiver, assistant, or close recent companion you want to recognize? Or one you're concerned might assert undue influence?"
8. **Dynamics between children.** "How do your children get along? Are there rivalries, resentments, or protective dynamics we should plan around?"

### Key listens

- "Well, she's been clean for three years but..." → spendthrift/discretionary trust
- "He's always been bad with money" → staged distributions + trustee discretion
- "My second wife and my kids don't really get along" → QTIP or similar spouse-versus-children tension planning likely deserves a serious look
- "My daughter's husband is... we don't love him" → preserve separate-property character for daughter's share
- "My brother hasn't spoken to me since Dad's funeral" → specify disinheritance explicitly, don't leave ambiguity

### Output

Narrative in the intake record, flagged by issue type. These flags drive which family-structure reference files get pulled in at [ROUTING](../../SKILL.md#routing-table).

---

## Phase 6 — Goals & Values (≈15 minutes)

### Goals

Before recommending structure, understand what the user wants. This is the foundation of the Letter of Wishes and Ethical Will.

### The central question

> "Imagine it's 30 years after you die. What do you hope is still true because of decisions you made in this plan?"

Listen carefully. The answer will be one of:

- "My kids are doing well and not fighting."
- "The farm is still in the family."
- "My grandkids went to college."
- "My spouse was taken care of."
- "[Charity] has been able to do X."
- "Our family values continued."

Each drives different structure.

### Secondary questions

1. **Equal vs. equitable.** "If you had to choose between leaving everything exactly equally to your children vs. leaving more to the one who needs it, what would you do?"
2. **Charitable intent.** "Are there causes or institutions that matter to you? Would you want to leave a portion of the estate to them? A specific amount or a percentage?"
3. **Business/legacy asset.** "If you own a business or a meaningful asset — the family farm, a vacation home — do you want it to stay in the family or be sold and divided?"
4. **Control after death.** "How much control do you want to exercise after you're gone? Are you comfortable trusting your heirs to make decisions with the assets, or do you want strong trust structures?"
5. **Unequal shares.** "If you think about unequal shares, what would your reasoning be? Let's capture that in your words."
6. **What you want them to know.** "Is there anything specific you want each of your children (or other heirs) to know — messages, stories, life lessons?" → seed the ethical will.

### Output

Narrative captured in user's own words. Feeds directly into:

- The Letter of Wishes template
- The Ethical Will
- Unequal-share justifications in the plan report
- Charitable-vehicle recommendations

---

## Phase 7 — Incapacity Scenarios (≈10 minutes)

### Goals

Complete the incapacity package: POA, healthcare proxy, living will, HIPAA, Ulysses/dementia directive if indicated.

### Questions

1. **Financial agent.** "If you were in a coma tomorrow, who would you want paying your bills, managing investments, dealing with insurance? Who is your backup?"
2. **Healthcare agent.** "If you couldn't speak for yourself in the hospital, who would you want making medical decisions? Is that the same person as the financial agent or someone different?"
3. **End-of-life preferences.** Working through a living will with specific scenarios:
   - Terminal illness, no chance of recovery — ventilator? Feeding tube? CPR?
   - Permanent unconsciousness — same questions
   - Severe dementia, physically healthy — continue aggressive treatment? Antibiotics for infections? Hand-feeding?
4. **Organ donation.** "Are you a registered organ donor? Do you want to be?"
5. **Psychiatric history.** "Have you ever been hospitalized for a mental-health episode? Had a significant period of mania, severe depression, or psychosis?" → Ulysses clause candidate
6. **Substance use history.** "Have you ever had a substance-use problem, or is there a risk you would in the future? Would you want a mechanism to protect your financial accounts during relapse?"
7. **Firearms.** "Do you own firearms? If you were in a mental-health crisis, would you want to pre-authorize a friend or family member to temporarily hold them?" — voluntary surrender directive
8. **Cognitive decline planning.** "If you started showing signs of dementia, who would you want to have the conversation with you? Who would you want to step in financially?"

### Output

- POA agent primary + successor
- Healthcare agent primary + successor
- Living will preferences, including dementia-specific scenarios if indicated
- HIPAA authorization consent
- POLST / MOLST evaluation when serious illness or advanced frailty makes current bedside medical orders useful
- Psychiatric advance directive if indicated
- Firearm surrender directive if relevant

---

## Phase 8 — Jurisdiction (≈5 minutes)

### Goals

Confirm domicile, out-of-state property, and cross-border issues.

### Questions

1. **Primary domicile.** "What state do you consider your home? Driver's license, voter registration, homestead declaration — all in that state?"
2. **Secondary residence.** "Do you spend significant time in another state? How many days per year?"
3. **Out-of-state real property.** "Do you own real estate in any state other than your domicile?"
4. **Cross-border.** "Do you own assets abroad? Do you hold dual citizenship? Is any beneficiary not a U.S. citizen or resident?"
5. **Recent moves or planned moves.** "Have you relocated in the last 5 years? Planning to?"

### Output

- Primary state of domicile
- List of states with real property
- International exposures (FBAR/FATCA, foreign real estate, forced heirship concerns)
- Relocation planning flags

---

## Phase 9 — Wealth-Tier Routing (≈5 minutes)

### Goals

Based on Phases 3 (assets), 5 (complexity), and 8 (jurisdiction), determine the tier and which reference files to load.

### Calculation

- Primary tier = wealth tier from [TIER-TRIAGE.md](TIER-TRIAGE.md)
- Complexity overlays = from Phase 5 landmines + Phase 8 jurisdiction
- State-specific adjustments = from Phase 8

### Next steps announcement

> "Based on what we've covered, I'd put your situation at roughly Tier [N] in complexity, with these specific overlays: [list]. That means we'll focus on [key focus areas]. We'll draft [list of deliverables]. Next, I'll begin producing the plan documents. We may need a follow-up session to work through [specific complex item]. Sound good?"

---

## Session Management

### One-session vs. multi-session

- **Tier 1, no complications** → often one shorter session that can cover all 9 phases
- **Tier 2, moderate complications** → often two sessions, with early intake in the first and decision-heavy work in the second
- **Tier 3+** → often three or more sessions, with attorney involvement by session 2
- **Tier 4-5** → weeks-to-months engagement, multi-advisor, often family meetings before final decisions

### Pausing and resuming

- Save after each phase into `intake/intake-record.md`
- If the user needs to pause, capture exactly where in the flow ("we stopped at Phase 5, you were telling me about your daughter")
- When resuming, read back the prior phases' summaries before diving into new questions

### Difficult moments

- User breaks down discussing a dying parent or a traumatic family history → acknowledge, offer to pause, never force through
- User is clearly in denial about a family problem → don't bulldoze, return to the topic gently later in the session
- User and spouse disagree (if both in the session) → note the disagreement, don't force consensus in the moment, suggest separate follow-ups with each
- User wants to rush through because "this is taking too long" → gently remind them that rushed estate planning is how families end up in litigation; propose finishing in a second session

---

## End-of-Session State Preservation

At the end of each meaningful intake session, write the durable state the next session will actually need:

1. `intake/intake-record.md` — updated with everything captured this session
2. `analyses/plan-coverage-matrix.md` — refreshed if the mode, overlays, or required outputs changed
3. Session summary when continuity matters — what we covered, what remains uncertain, and what comes next
4. Pending items only when something is blocked — specific questions or documents the user still needs to gather
5. Immediate user action items only when there are true near-term fixes or retrieval tasks

This preserves state across sessions and ensures no detail is lost to memory or compaction.
