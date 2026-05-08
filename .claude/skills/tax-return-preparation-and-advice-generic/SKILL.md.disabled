---
name: tax-return-preparation-and-advice-generic
description: >-
  Verification-first AI-assisted tax return preparation for U.S. individual
  returns. Use when preparing tax returns, detecting multi-year filing errors,
  optimizing deductions across entity structures, or navigating state/local
  tax rules. Handles all filing statuses, income/entity structures, profession
  overlays, life events, and 50-state routing with optional browser automation
  and Aiwyn MCP calculation.
---

<!-- TOC: Kernel | Interactive Intake | Phase 1-6 | Aiwyn | State Router | Profession Router | Life Events | Anti-Patterns | References -->

# Universal Tax Return Preparation and Advice

> **Core Insight:** Tax optimization is highest EV when it combines **multi-year return
> analysis + source-document reconciliation + current-law verification + deterministic
> calculation software**. LLMs are useful for pattern recognition, cross-year auditing,
> and strategy search, but they must not be treated as authoritative on raw math,
> current tax-year thresholds, vendor product coverage, or filing mechanics without
> verification.

> **The compression leverage:** Converting opaque PDF returns into LLM-optimized markdown
> analyses creates a 10-20x compression. Three years of returns fit one context window.
> Cross-year analysis at that scale finds errors and optimization opportunities that no
> single-year review — human or AI — can detect.

> **Universal design:** This skill is designed to handle any U.S. individual
> taxpayer profile — single filers, married couples, heads of household, common
> pass-through entities, any profession, and any combination of income sources.
> The intake flow determines which reference files and strategies apply, while
> current-year law, state/local overlays, and software/tool coverage are verified
> live before any filing recommendation is finalized.

---

## THE TAX OPTIMIZATION KERNEL (Universal Axioms)

<!-- TAX_KERNEL_START v2.0 -->

Every tax analysis must assume these axioms. They are load-bearing — skipping one
means missing entire classes of savings or creating audit exposure.

**Axiom 0 — Verify current law before giving filing advice.**
Tax law, IRS instructions, state guidance, filing-product coverage, and phaseouts change
annually. For any live filing recommendation, confirm the current-year rule from official
IRS, state, or city guidance before asserting it. This is mandatory for SALT provisions,
depreciation, credits, contribution limits, and filing mechanics. Never hard-code tax
law from memory — always verify.

**Axiom 1 — Every dollar of income has a jurisdiction stack.**
Federal + State + City (if applicable) + SE tax + NIIT + AMT. A dollar of W-2 income
in New York City has a combined marginal rate approaching 50%. In Texas, the same dollar
faces only Federal tax. Optimization means attacking every layer of the stack independently.
What reduces Federal may not reduce state. What reduces income tax may increase AMT.

**Axiom 2 — Entity structure is the master lever.**
An LLC taxed as a sole proprietorship vs. an S-Corp vs. a C-Corp produces wildly
different tax outcomes on identical revenue. The entity election is not a one-time
decision — it should be re-evaluated annually as income changes. SE tax savings alone
from an S-Corp election can exceed $10,000/year on $150K+ self-employment income.

**Axiom 3 — Timing is a first-class tax strategy.**
Income recognition, expense acceleration, estimated payments, entity elections, retirement
contributions — each has hard deadlines that, once missed, may not be recoverable. Form 2553
filing windows, PTET election deadlines, estimated payments, year-end loss harvesting, and
owner-only retirement-plan adoption / elective-deferral timing must be verified against the
taxpayer's entity type and the current IRS rules. Never assume a generic "December 31" rule
without checking the exact plan and fact pattern.

**Axiom 4 — The SALT cap has workarounds.**
The Federal SALT deduction cap is painful for high-tax-state residents. For TY 2025, the
personal cap is generally $40,000 ($20,000 MFS), subject to income-based reduction at higher
MAGI levels. Pass-Through Entity Tax (PTET) elections available in many states can move some
state tax to the entity level, where it may be deductible federally outside the personal SALT
cap. Whether this matters depends on the user's state, income level, entity structure, and
whether local taxes are also in play.

**Axiom 5 — Depreciation is the most powerful non-cash deduction.**
Cost segregation reclassifies building components into shorter-lived asset classes (5, 7,
15 years vs. 27.5/39), front-loading depreciation. Combined with bonus depreciation
(100% under OBBBA for property acquired after Jan 19, 2025) and Real Estate Professional
status, these losses can offset W-2 and business income without limitation.

**Axiom 6 — Cross-year consistency is both a quality signal and an audit shield.**
The IRS DIF scoring system flags returns that deviate from prior years or from statistical
norms for your income bracket. Identical percentages across different properties,
Schedule C profit that zeroes out precisely, and dramatic year-over-year swings are
red flags. Consistency should be *natural*, not *manufactured*.

**Axiom 7 — Capital losses are a depreciating asset.**
Capital loss carryforwards lose real value every year they go unused (only $3,000
offsets ordinary income annually). Actively generating capital gains to harvest against
carryforward losses is a legitimate strategy.

**Axiom 8 — Multi-model triangulation catches what single-model review misses.**
Run critical analyses through multiple AI models independently. Where they agree,
confidence is high. Where they disagree, that disagreement is the finding that deserves
the most scrutiny. This is especially critical for aggressive positions.

**Axiom 9 — Software is a calculator, not a strategy engine.**
CPAs, TurboTax, FreeTaxUSA, and other prep software are valuable for form mechanics and
math, but they will not reliably surface the highest-EV elections, carryforward errors,
or cross-year inconsistencies on their own. Use software to compute; use multi-year review
and primary-source verification to decide what should be computed.

**Axiom 10 — Documentation is the difference between avoidance and evasion.**
Every aggressive position requires contemporaneous documentation. Home office logs, RE
professional hour tracking, business purpose memos for expenses, mileage logs, cost
segregation studies — if it's not documented at the time, it didn't happen for audit
purposes. The AI can generate documentation templates; the user must fill them out.

<!-- TAX_KERNEL_END v2.0 -->

## YEAR-SPECIFIC OVERLAY DISCIPLINE

Separate evergreen methodology from volatile tax-year facts.

- **Evergreen:** intake method, cross-year reconciliation, carryforward tracking, entity
  arbitrage, audit-risk review, documentation standards.
- **Year-specific:** brackets, standard deductions, SALT amounts, CTC/ACTC, HSA limits,
  retirement-plan limits, Social Security wage base, 1099-K thresholds, bonus depreciation
  timing, product pricing, software form coverage.
- **Tool-specific:** Aiwyn supported jurisdictions / namespaces, consumer-software form
  support, browser-automation viability, e-file availability.

Before giving a live filing recommendation, explicitly verify all year-specific and tool-specific
assumptions from primary sources or the live tool surface.

---

## COGNITIVE OPERATORS (Tax Thinking Moves)

These are composable mental moves for finding tax savings. Apply them to any
aspect of a return. Each has triggers, failure modes, and a prompt module.
See [OPERATORS.md](references/methodology/OPERATORS.md) for the full card library.

### $ Stack-Decompose — "What's the full tax on this dollar?"
Break every income/deduction item into its full jurisdiction stack
(Federal + State + City + SE + NIIT + AMT) to find the true marginal rate and
identify which layer is most attackable. The stack varies enormously by state —
a dollar in California faces 13.3% state tax; the same dollar in Florida faces 0%.

### ⟳ Entity-Arbitrage — "What entity should hold this income?"
For every income stream, evaluate whether personal, LLC (disregarded),
LLC (S-Corp), or LLC (C-Corp) treatment produces the lowest total tax across all
jurisdiction layers. See [ENTITY-STRATEGIES.md](references/strategies/ENTITY-STRATEGIES.md).

### ⌂ Space-Split — "What percentage of this space is business?"
Allocate shared spaces (home, utilities, internet, insurance) between
personal and business use with defensible measurements and contemporaneous records.
See [HOME-OFFICE.md](references/strategies/HOME-OFFICE.md).

### ↻ Carryforward-Harvest — "What's sitting unused from prior years?"
Identify all carryforward items (capital losses, passive losses, NOLs,
QBI losses, AMT credits) and engineer current-year transactions to utilize them.

### 🏗 Depreciation-Accelerate — "Can I reclassify this asset's useful life?"
Apply cost segregation and Section 179 to reclassify building components and
maximize first-year deductions. See [REAL-ESTATE.md](references/strategies/REAL-ESTATE.md).

### ⏱ Deadline-Gate — "What irreversible deadline is approaching?"
Map all hard deadlines for elections, contributions, and filings that
cannot be recovered once passed. See [DEADLINES.md](references/methodology/DEADLINES.md).

### 🔀 Income-Shift — "Can this income be recognized at a better time?"
Move income recognition or deduction timing to optimize across tax years.

### 🛡 Audit-Shield — "How would this look to an IRS examiner?"
For every aggressive position, evaluate audit probability, documentation quality,
and worst-case exposure. See [AUDIT-DEFENSE.md](references/methodology/AUDIT-DEFENSE.md).

### 🔗 Strategy-Chain — "What other strategies does this unlock?"
Map the interaction effects between tax strategies. Some are prerequisites for
others; some conflict.

### 💰 Credit-Optimize — "What credits am I leaving on the table?"
Systematically scan all available federal and state tax credits. Credits reduce tax
dollar-for-dollar and are higher-value than deductions. For each: check qualification,
compute amount, verify phase-out status. See [OPERATORS.md](references/methodology/OPERATORS.md).

### 🏦 Retirement-Optimize — "Am I maximizing tax-deferred shelter?"
Compare all available retirement vehicles (401(k), IRA, Roth, backdoor Roth, SEP,
SIMPLE, Solo 401(k), Defined Benefit/Cash Balance) at the taxpayer's marginal rate.
The optimal Traditional vs. Roth split depends on current vs. expected retirement rate.
See [OPERATORS.md](references/methodology/OPERATORS.md) and
[DEFINED-BENEFIT-PLANS.md](references/strategies/DEFINED-BENEFIT-PLANS.md).

---

## INTERACTIVE INTAKE FLOW

**This is the heart of the universal skill.** Before any analysis or preparation can
begin, the agent must gather comprehensive information about the user's tax situation
through a structured conversational intake. Ask questions one category at a time,
in plain language — never dump the entire questionnaire at once.

See [INTAKE-QUESTIONNAIRE.md](references/intake/INTAKE-QUESTIONNAIRE.md) for the
complete question set organized by category.

### Intake Phase 1: Identity and Filing Basics

Ask these first — everything else depends on them:

```
1. What tax year are we preparing? (default: most recent)
2. What is your filing status?
   - Single
   - Married Filing Jointly (MFJ)
   - Married Filing Separately (MFS)
   - Head of Household (HOH)
   - Qualifying Surviving Spouse (QSS)
3. What state do you live in? Did you move states during the tax year?
4. Do you live in a city with its own income tax? (NYC, Philadelphia,
   Detroit, St. Louis, Baltimore, Columbus, Cincinnati, Cleveland, etc.)
5. What is your approximate total household income? (rough range is fine
   for now — helps me determine which strategies and phase-outs apply)
```

**After filing status and state are known:** Load the appropriate state reference
file from `references/states/{STATE_ABBREV}.md` and adjust all subsequent questions
and analysis for that state's rules.

### Intake Phase 2: Personal Information

```
6. Full legal names (taxpayer + spouse if MFJ/MFS)
7. Dates of birth
8. Social Security Numbers (for filing; handle with care)
9. Current mailing address
10. Do you have dependents? For each:
    - Name, DOB, SSN
    - Relationship (child, parent, sibling, other)
    - Did they live with you all year?
    - Do they have any income?
    - Are they a full-time student?
    - Do they have a disability?
```

### Intake Phase 3: Income Sources

Ask about each category. For each "yes," drill down for details:

```
EMPLOYMENT:
11. Do you have W-2 wage income? (How many W-2s? From which employers?)
12. Did you change jobs during the year?
13. Do you receive stock options, RSUs, or ESPP benefits?

SELF-EMPLOYMENT / BUSINESS:
14. Do you have any self-employment or freelance income (1099-NEC/1099-MISC)?
15. Do you own a business? (LLC, S-Corp, C-Corp, sole proprietorship?)
    - What type of business? What industry?
    - Approximate gross revenue and expenses?
16. Do you receive income from gig platforms (Uber, DoorDash, Etsy, etc.)?

INVESTMENTS:
17. Did you sell any stocks, bonds, mutual funds, or ETFs?
18. Did you sell, trade, or receive any cryptocurrency?
19. Do you have interest income (savings, CDs, bonds)?
20. Do you have dividend income?
21. Do you have capital loss carryforwards from prior years?

RENTAL PROPERTY:
22. Do you own rental property? (How many? Residential or commercial?)
    - Gross rental income?
    - Short-term (Airbnb) or long-term leases?
23. Did you purchase or sell any rental property this year?

PARTNERSHIPS / S-CORPS:
24. Do you receive K-1s from partnerships, S-Corps, or trusts?

RETIREMENT:
25. Did you receive retirement distributions (IRA, 401k, pension, Social Security)?
26. Did you do a Roth conversion?

OTHER:
27. Any alimony received (pre-2019 divorce agreements)?
28. Gambling winnings?
29. Cancellation of debt income?
30. Foreign income or foreign bank accounts?
31. State/local tax refund from prior year?
```

### Intake Phase 4: Deductions and Credits

```
HOUSING:
32. Do you own your home? (Mortgage interest, property taxes)
33. Did you buy or sell a home this year?
34. Do you pay rent? (some states allow renter credits)
35. Do you work from home? (Home office deduction potential)

TAXES PAID:
36. Estimated tax payments made? (Federal and state, dates and amounts)
37. Prior year state refund or balance due?

CHARITABLE:
38. Did you make charitable donations? (Cash, property, stock, DAF)
    - Total approximate amount?
    - Any single donation over $250?
    - Any non-cash donation over $500?

MEDICAL:
39. Do you have significant medical expenses? (Over ~7.5% of income)
40. Do you have a Health Savings Account (HSA)?
41. Are you self-employed and pay your own health insurance?

EDUCATION:
42. Did you or a dependent attend college/university?
43. Did you pay student loan interest?
44. Did you contribute to a 529 plan?
45. Did you pay for work-related education?

CHILDCARE:
46. Did you pay for childcare or dependent care?
    - Provider name, address, EIN/SSN?
    - Total amount paid?

RETIREMENT CONTRIBUTIONS:
47. Did you contribute to an IRA (Traditional or Roth)?
48. Did you contribute to a SEP-IRA, SIMPLE IRA, or Solo 401(k)?
49. Does your employer offer a retirement plan? Did you max it out?

BUSINESS EXPENSES (if self-employed):
50. What are your major business expense categories?
    - Software/subscriptions?
    - Equipment?
    - Vehicle/mileage?
    - Travel?
    - Meals?
    - Professional services?
    - Insurance?
    - Advertising?
```

### Intake Phase 5: Life Events and Special Situations

```
51. Did any of these happen this year?
    - Got married or divorced
    - Had or adopted a child
    - Bought or sold a home
    - Started or closed a business
    - Changed jobs
    - Moved to a different state
    - Retired or became disabled
    - Received an inheritance
    - Exercised stock options
    - Converted a traditional IRA to Roth
    - Had significant crypto activity
    - Sold rental property
    - Were affected by a natural disaster
    - Served in military/combat zone
    - Received foreign income
    - Had a child start or finish college
```

**For each "yes" to a life event:** Load the appropriate reference file from
`references/life-events/` and ask targeted follow-up questions.

### Intake Phase 6: Prior Year Context

```
52. Do you have copies of your prior year tax returns (ideally 2-3 years)?
    - If so, share the PDFs or key numbers
53. Were there any issues with prior returns?
    - Amended returns?
    - IRS notices or audits?
    - Known errors or missed deductions?
54. Do you have carryforward items from prior years?
    - Capital losses?
    - Passive activity losses?
    - QBI losses?
    - NOL?
    - AMT credit?
    - Home office expense carryover?
```

### Intake Router — What Happens After Intake

Based on the intake answers, the agent should:

1. **Load relevant state file(s):** `references/states/{STATE}.md`
2. **Load profession file (if applicable):** `references/professions/{PROFESSION}.md`
3. **Load relevant strategy files** based on income types and situations
4. **Load relevant life-event files** for any triggered events
5. **Determine applicable forms** and complexity level
6. **Build a tax situation summary** documenting all gathered information
7. **Proceed to Phase 1** (or Phase 2 if prior-year analyses already exist)

**Complexity Assessment:**
```
SIMPLE (1040 only, standard deduction):
  - W-2 income only, standard deduction, basic credits
  - Estimated preparation: 30 minutes

MODERATE (additional schedules):
  - W-2 + investment income + itemized deductions
  - Estimated preparation: 1-2 hours

COMPLEX (multiple business/rental activities):
  - Self-employment + rental property + entity structure
  - Estimated preparation: 3-6 hours

VERY COMPLEX (multi-jurisdiction, advanced strategies):
  - Multiple businesses + rental properties + multi-state
  - Entity optimization + cost segregation + RE Professional
  - Estimated preparation: 6-12+ hours
```

---

## The Analysis Files — The Core Asset

The entire methodology revolves around structured markdown analyses of each year's
complete tax return. These are LLM-optimized — 10-20x smaller than the original PDF,
uniform in structure across years, and designed for cross-year comparison within a
single context window.

**When this skill is invoked**, first check if analysis files already exist. If they do,
read them ALL before doing anything else — they contain the accumulated context that makes
cross-year analysis possible.

**Each analysis must contain** (in this exact section order):
1. Filing Information (status, names, SSNs, address, dependents, preparer)
2. Income Summary (total income, AGI, taxable income — with YoY comparison)
3. Income Sources (wages, interest, dividends, cap gains, Schedule E, other — every dollar)
4. Business Operations (each Schedule C with all line items, COGS, expenses)
5. Foreign Tax Credit (Form 1116)
6. Alternative Minimum Tax
7. Additional Taxes (Additional Medicare Form 8959, NIIT Form 8960)
8. Qualified Business Income Deduction (Form 8995 with carryforward tracking)
9. State Tax Return (state form, state tax, local tax if any, credits, payments, refund)
10. Depreciation Analysis (all assets, methods, Section 179)
11. **Carryovers to Next Year** (CRITICAL — capital losses ST/LT with computation,
    QBI carryforward, passive losses, home office expense carryover, investment interest,
    foreign tax credit, AMT credit, NOL)
12. Estimated Tax Payments (what was scheduled/paid)
13. Tax Strategy Observations (what the return reveals about strategy)
14. Considerations for Future Planning

**The carryovers section is the most important** — it is the bridge between years and the
source of truth for loss carryforward amounts.

---

## Phase 1: Document Ingestion — PDF to Structured Analysis

### Prerequisites

```bash
# Recommended project directory structure:
# ~/tax-prep/
#   returns/                  ← PDF returns (current + prior years)
#   returns_markdown/         ← markdown conversions of returns
#   analyses/                 ← analysis files live HERE (the core asset)
#   source_documents/         ← W-2s, 1099s, K-1s, closing docs, etc.
#   documentation/            ← contemporaneous logs and templates
#   my_tax_situation.md       ← comprehensive current-year situation document
```

**Required tools:**
- Claude Code with Opus model (1M context handles most returns without splitting)
- **Aiwyn Tax Engine (MCP server)** — deterministic calculations + PDF generation when the
  target year, jurisdiction, and namespace set are supported
  (see [AIWYN-INTEGRATION.md](references/tools/AIWYN-INTEGRATION.md))
- **For filing:** a verified consumer tax product, direct-file / fillable-forms path, paper
  filing, or preparer workflow selected only after confirming current-year coverage
- All source tax documents organized in the project directory

### Step 0: Check for Existing Analyses (ALWAYS DO THIS FIRST)

```
Look for files matching *analysis*.md or *claude_analysis*.md in the project directory.

If they exist, read ALL of them. These are the accumulated multi-year
context that powers cross-year error detection and optimization.

Also read my_tax_situation.md if it exists — this is the comprehensive
current-year situation document.

Before giving any filing recommendation, also build a source-of-truth ledger from:
- current-year 1098 / 1099 / K-1 / brokerage / crypto / closing docs
- prior-year filed return carryforwards
- business ledgers and expense exports
- residency and move-date evidence

Never optimize from narrative notes alone if primary documents are available.
```

### THE PROMPT — First Year Analysis

```
Read the PDF at [PATH_TO_RETURN].

This is my [YEAR] tax return ([FILING_STATUS], [STATE] resident).
[DEPENDENT_INFO]

My income sources and business activities:
[INCOME_SUMMARY_FROM_INTAKE]

Our situation for [TARGET_YEAR] is similar except:
[KEY_CHANGES_FROM_INTAKE]

Go through EVERY part of this return and produce a comprehensive structured
analysis covering ALL of the following with EXACT dollar amounts:

1. Filing status, exemptions, dependents (SSNs, DOBs)
2. W-2 income (each employer, gross, withholding, retirement contributions)
3. Self-employment income per Schedule C (gross revenue, every expense
   category, net profit, SE tax calculation)
4. Business Use of Home (Form 8829) — square footage, percentage, expenses
5. Rental property (Schedule E) — gross rents, each expense, depreciation
   method/basis/life, net income/loss
6. Capital gains/losses (Schedule D + Form 8949) — each transaction, wash
   sales, carryforward amounts with character (ST vs LT)
7. Partnership/S-Corp income (Schedule E page 2 from K-1s) — each entity,
   ordinary income, guaranteed payments, separately stated items
8. Interest and dividend income (Schedule B) — each source and amount
9. Deductions (Schedule A or standard) — SALT, mortgage interest, charitable,
   medical, other
10. Tax credits — Child Tax Credit, Dependent Care, education, energy,
    foreign tax credit
11. Additional Medicare Tax (Form 8959) and NIIT (Form 8960)
12. AMT calculation (Form 6251) if applicable
13. Qualified Business Income deduction (Form 8995) — QBI amount, limitations,
    carryforward
14. Estimated tax payments made (dates and amounts)
15. State return summary — forms, state tax, local tax, credits, payments, refund
16. All elections made (depreciation methods, accounting methods, etc.)
17. All carryforward items to next year
18. Any attached statements, schedules, or addenda

Flag anything unusual, potentially incorrect, or audit-risky.
Write the analysis to [OUTPUT_PATH]/analysis_[YEAR].md
```

### THE PROMPT — Subsequent Years (with context accumulation)

```
Read the PDF at [PATH_TO_NEXT_YEAR_RETURN].
Also read [PATH]/analysis_[PRIOR_YEAR].md for context.

This is my [YEAR] tax return. Produce the same comprehensive analysis using
the IDENTICAL structure and section headings as the prior year.

Additionally, for each section, note:
- Year-over-year changes and whether they make sense
- Carryforward items that SHOULD appear from prior year — verify they do
- Any inconsistencies with prior year that seem incorrect
- Elections that should be consistent — verify they are

Write to [OUTPUT_PATH]/analysis_[YEAR].md using the SAME format.
```

### For returns over ~80 pages: split and process sequentially

```bash
# Chrome: Print to PDF, pages 1-30, 31-60, 61+
# Save as [YEAR]_return_part1.pdf, part2.pdf, part3.pdf
```

Process each part, then merge. See [PROMPTS.md](references/methodology/PROMPTS.md) for
part-by-part prompts.

### Format Standardization (Critical Step — Do Not Skip)

```
Read all analysis files. Identify which has the best structure and detail level.
Rewrite the others to match that format EXACTLY — same sections, same ordering,
same granularity. Do NOT lose any information or dollar amounts.
```

---

## Phase 2: Cross-Year Error Detection

**This is where the analysis files pay off.** Load ALL of them into one context:

### THE PROMPT — Find CPA/Self-Prep Mistakes

```
You have just read [N] consecutive years of detailed tax return analyses.

Scrutinize each return individually AND across years. Check:

CALCULATION ERRORS:
- Math mistakes in any schedule
- Incorrect phase-out calculations (child tax credit, QBI, etc.)
- Wrong tax bracket application
- Depreciation calculation errors (method, basis, useful life)
- SE tax computation errors

CROSS-YEAR INCONSISTENCIES:
- Home office percentage: is it identical across different residences?
  (RED FLAG if always the same % across different-sized homes)
- Schedule C profit: does it suspiciously zero out every year?
- Capital loss carryforwards: do they reconcile properly year-to-year?
- Passive activity suspended losses: proper carryforward tracking?
- QBI carryforward: does it track correctly?
- Depreciation schedules: consistent methods and continuing basis?

AUDIT RED FLAGS (IRS DIF Score Triggers):
- Round number deductions (suggests estimation, not records)
- Schedule C losses in 3+ of 5 years (hobby loss rules IRC §183)
- Home office deduction >25% of gross Schedule C income
- Charitable contributions >5% of AGI
- Unreported income (1099s that should appear but might be missing)
- Cash-heavy business with low reported income
- Dramatic year-over-year swings without explanation

MISSED OPPORTUNITIES:
- Credits not claimed that likely qualify
- Deductions not taken
- Better entity structure options
- Retirement contribution optimization

For each finding:
- Severity: CRITICAL / MODERATE / LOW
- Year(s) affected
- Specific evidence from analyses (quote exact numbers)
- Recommended action
- Estimated tax impact
- Risk of IRS challenge

Write to [PATH]/error_detection_report.md
```

---

## Phase 3: Tax Optimization Strategy

### THE PROMPT — Comprehensive Optimization

```
Read ALL analysis files and the error detection report.

Based on the full multi-year picture plus these current-year facts:
[INSERT: current year income, entities, property details, life changes from intake]

Identify EVERY legal tax reduction strategy organized as:

TIER 1 — IMMEDIATE (current year filing):
Entity structure optimization, deduction maximization, credit claims,
carryforward utilization, filing status optimization.

TIER 2 — STRUCTURAL (requires setup, high long-term value):
S-Corp election, retirement plans (Solo 401(k), SEP-IRA, Defined Benefit),
cost segregation, RE Professional status, state PTET election, SALT workarounds.

TIER 3 — FORWARD-LOOKING (next year and beyond):
Roth conversions, income timing, charitable vehicles (DAF, QCD),
estate planning, entity restructuring.

For each strategy provide:
- Prerequisites and qualification requirements
- Specific IRS forms and tax code sections
- Estimated annual tax savings (show the math)
- Implementation complexity (simple/moderate/complex)
- Audit risk level (conservative/moderate/aggressive)
- Hard deadlines
- Interaction effects with other strategies
- State-specific implications for [USER'S STATE]

Write to [PATH]/optimization_strategies.md
```

See strategy reference files:
- [ENTITY-STRATEGIES.md](references/strategies/ENTITY-STRATEGIES.md)
- [REAL-ESTATE.md](references/strategies/REAL-ESTATE.md)
- [HOME-OFFICE.md](references/strategies/HOME-OFFICE.md)
- [RETIREMENT-PLANS.md](references/strategies/RETIREMENT-PLANS.md)
- [BUSINESS-OPTIMIZATION.md](references/strategies/BUSINESS-OPTIMIZATION.md)
- [ADVANCED-STRATEGIES.md](references/strategies/ADVANCED-STRATEGIES.md)
- [CHARITABLE-GIVING.md](references/strategies/CHARITABLE-GIVING.md)
- [INVESTMENT-TAX-STRATEGIES.md](references/strategies/INVESTMENT-TAX-STRATEGIES.md)
- [CRYPTO-DIGITAL-ASSETS.md](references/strategies/CRYPTO-DIGITAL-ASSETS.md)
- [SALT-WORKAROUNDS.md](references/strategies/SALT-WORKAROUNDS.md)
- [EDUCATION-TAX-BENEFITS.md](references/strategies/EDUCATION-TAX-BENEFITS.md)
- [HEALTH-SAVINGS.md](references/strategies/HEALTH-SAVINGS.md)

---

## Phase 4: Return Preparation

### Default workflow: choose the filing path only after verification

Before committing to any software path, verify:
- target tax year support,
- federal + state + local form coverage,
- treatment of part-year residency, city tax, and international overlays,
- whether browser automation is actually viable for the chosen product.

### Option A: consumer tax software with optional browser automation

FreeTaxUSA is one battle-tested profile for many individual returns, but it is not a universal
default. FreeTaxUSA, TurboTax, TaxSlayer, IRS Direct File / Fillable Forms, or paper filing may
each be correct depending on form complexity, state coverage, local-tax needs, and budget.

If browser automation is used:
1. user logs in manually,
2. agent uses a data-entry guide built from source documents + chosen strategy,
3. agent enters data section-by-section,
4. agent verifies intermediate totals and clears validation errors,
5. user reviews and authorizes submission.

See [BROWSER-AUTOMATION-FREETAXUSA.md](references/tools/BROWSER-AUTOMATION-FREETAXUSA.md)
for the FreeTaxUSA-specific playbook and battle-tested gotchas.

### Option B: Aiwyn Tax Engine (deterministic calculation + validation)

Use Aiwyn when the live tool surface confirms that the tax year, jurisdiction, and needed
namespaces are supported. Aiwyn is strongest as a deterministic calculator, validation layer, and
PDF generator. It is not a blanket substitute for software coverage discovery, local-tax review,
or e-file transmission.

See [AIWYN-INTEGRATION.md](references/tools/AIWYN-INTEGRATION.md) for the live workflow.

### Option C: Manual or guided software entry

```
I'm preparing my [YEAR] tax return in [SOFTWARE NAME].

Based on our analyses and chosen optimization strategies, walk me through
EVERY section with exact navigation:

For each entry tell me:
- Exact screen/section name and navigation path
- What to enter and where (exact dollar amounts where known)
- Which IRS forms this populates behind the scenes
- Non-obvious choices, elections, or checkboxes
- When to use "Other" or manual entry vs. guided interview

Start with Personal Info, then Income, then Deductions, then Credits, then
State Returns. I'll confirm each section before proceeding.
```

### E-Filing Strategy

The IRS requires e-filed returns use MeF XML via an authorized transmitter.
Aiwyn generates PDFs but cannot e-file.

**Filing-path selection criteria:**
- verified form coverage for the actual return,
- verified state and local coverage,
- ease of review against the source-document ledger,
- cost,
- whether the user wants automation or manual review.

**Typical options:**

| Path | Federal | State | Total | Notes |
|------|---------|-------|-------|-------|
| FreeTaxUSA | Verify live | Verify live | Verify live | Strong profile for many returns; not universal |
| IRS Direct File / Fillable Forms | Verify live | Verify live | Verify live | Coverage and state integration vary |
| TaxSlayer / TurboTax / H&R Block / other consumer software | Verify live | Verify live | Verify live | Choose only after confirming current-year support |
| Paper file | postage | postage | postage | Slowest; useful as fallback when software support is weak |

---

## Phase 5: Draft Validation — The Flywheel Closes

Once tax software or Aiwyn produces a draft return, create the next analysis file.
This is the flywheel — each year's analysis becomes next year's context.

```
Read the draft [YEAR] return (PDF export or markdown conversion).

Create analysis_[YEAR].md using the IDENTICAL structure as prior year analyses.
Every section, every heading, same level of detail. Include year-over-year
comparisons against the most recent prior year.

Pay CRITICAL attention to:
- Carryovers section (capital losses, QBI, passive, home office, NOL)
- Verify carryforward inputs match prior year analysis outputs
- Flag any carryovers that were NOT properly carried forward

Write to [PATH]/analysis_[YEAR].md
```

Then load ALL analyses and run cross-year validation:

```
Read ALL analysis files ([FIRST_YEAR] through [CURRENT_YEAR] draft).

Compare the draft against the full multi-year trajectory:
1. Does the draft correctly implement every chosen strategy?
2. Are ALL carryforward items properly carried from prior year?
3. Does the effective tax rate match projections?
4. Cross-year consistency: do patterns look natural?
5. Anything that would trigger a DIF score flag?
6. Did we leave money on the table?

Write validation report to [PATH]/draft_validation.md
```

### Multi-Model Triangulation (Required for aggressive positions)

```
Export the draft analysis and cross-validate with GPT and Gemini.
Focus on: S-Corp reasonable salary, home office allocation, RE Pro hours,
cost segregation allocations, PTET computation, any position where tax
savings exceed $5,000 and audit risk is moderate or higher.
Disagreements between models = findings that need the most scrutiny.
```

---

## Phase 6: Filing, Documentation, and Next-Year Setup

### Post-Filing Checklist

- [ ] E-file Federal and State returns (or mail if paper filing)
- [ ] Save all analyses to project directory for next year's Phase 0
- [ ] Archive all source documents (W-2s, 1099s, K-1s)
- [ ] Set calendar reminders for next year's deadlines
  (see [DEADLINES.md](references/methodology/DEADLINES.md))
- [ ] Begin documentation logs for next year (home office, mileage, RE hours)
- [ ] Review estimated tax payments needed for next year
- [ ] Evaluate entity structure changes needed before next year's deadlines
- [ ] If applicable: begin RE Professional hour logging
- [ ] Review owner-only retirement-plan adoption and contribution deadlines based on entity type

### Documentation Templates

```
Generate contemporaneous documentation templates for:
1. Home office usage log (monthly sign-off)
2. Real estate professional activity log (daily hours) — if pursuing RE Pro
3. Business expense substantiation (purpose, amount, attendees for meals)
4. Vehicle mileage log (business vs personal)
5. Rental property management activity log — if applicable
6. Carryforward ledger (running totals across years)
7. Cost segregation study summary memo — if applicable
```

---

## State Tax Router

Based on the user's state of residence, load the appropriate reference file
from `references/states/`. Each state file contains:

- Income tax rates and brackets (all filing statuses)
- Standard deduction / personal exemption
- Key state-specific credits and deductions
- Filing requirements and forms
- Estimated tax payment rules
- Pass-Through Entity Tax (PTET) availability and rules
- Local/city income taxes (if applicable)
- Special features and gotchas

**No income tax states (9):** Alaska, Florida, Nevada, New Hampshire (dividends/interest
only), South Dakota, Tennessee, Texas, Washington, Wyoming — still have state files
for property tax, sales tax, and other relevant information.

**States with PTET elections (30+):** See individual state files for election deadlines,
rates, and mechanics.

**High-tax states requiring special attention:** California, New York, New Jersey,
Connecticut, Hawaii, Oregon, Minnesota, Vermont, Iowa, Wisconsin — SALT workarounds
and entity-level elections are most valuable here.

**Local-tax overlay:** If the facts touch NYC, Yonkers, Philadelphia, Ohio municipal / RITA
cities, PA locals, school-district taxes, WA capital gains, or other city / county regimes, do
not stop at the state guide. Pull the local rules directly into the analysis and verify sourcing
and residency dates.

---

## Profession Router

Based on the user's profession, load the appropriate reference file from
`references/professions/`. Each profession file contains:

- Common deductions specific to that profession
- Industry-specific tax rules and elections
- Typical entity structure recommendations
- Common audit triggers for that profession
- Profession-specific retirement plan options
- Continuing education deduction guidance

**Available profession guides:**
- Software Engineer / Tech Worker
- Physician / Dentist
- Healthcare Worker
- Attorney / Legal Professional
- Real Estate Agent / Broker
- Freelancer / Consultant
- Small Business Owner
- Gig Economy Worker (Uber, DoorDash, Etsy, etc.)
- Military / Veteran
- Teacher / Educator
- Creative Professional (Artist, Musician, Writer)
- Truck Driver / Transportation
- Construction / Skilled Trades
- Clergy / Religious Worker
- Farmer / Rancher
- Financial Professional / Day Trader
- Salesperson / Commission-Based Worker
- Startup Founder
- Executive / C-Suite
- Athlete / Entertainer
- Influencer / Content Creator

---

## Life Event Router

When the user reports a life event during intake, load the appropriate reference
file from `references/life-events/`. Each file contains:

- Tax implications of the event
- Required forms and documentation
- Common mistakes to avoid
- Optimization opportunities triggered by the event
- State-specific considerations
- Timeline and deadlines

**Available life event guides:**
- Marriage or Divorce
- New Child (birth or adoption)
- Home Purchase or Sale
- Starting a Business
- Job Change or Layoff
- Moving to a Different State
- Retirement
- Inheritance or Estate
- Disability
- Stock Options (ISO, NSO, RSU, ESPP)
- College (starting, attending, graduating)
- Natural Disaster
- Military Deployment
- Death of Spouse
- Business Exit / Sale
- International Move / Foreign Income
- Divorce

---

## Anti-Patterns

| Don't | Do Instead |
|-------|------------|
| Trust LLM raw tax arithmetic | Use Aiwyn or tax software, then reconcile |
| Use a single model for aggressive positions | Cross-validate with 2+ models |
| Claim identical home office % across different homes | Measure each home independently |
| Zero out Schedule C profit precisely with home office | Let natural deductions flow |
| Hard-code current-year tax law from memory | Verify the live rule from IRS/state guidance |
| Assume all states work the same | Load the state-specific reference file |
| Skip the intake questionnaire | Always complete intake before analysis |
| Give advice without knowing filing status and state | These determine everything |
| Assume standard deduction is always simpler | Calculate both; itemize when higher |
| Ignore state/local tax (focus only on Federal) | Stack-Decompose every item |
| Apply every aggressive strategy simultaneously | Phase in over 2-3 years |
| Forget to track carryforwards | Maintain a running carryforward ledger |
| Assume your CPA found everything | Run cross-year analysis yourself |
| Miss entity election deadlines | Calendar all deadlines at year start |
| Skip documentation ("I'll do it later") | Generate templates NOW, fill monthly |
| Guess at numbers the user hasn't provided | ASK — never fabricate values |
| Assume a profession has no special rules | Check the profession reference file |

---

## Workflow Summary

```
INTAKE: Interactive questionnaire (filing status, state, income, deductions,
        life events, prior years) → Load relevant reference files
    ↓
Step 0: Load existing analysis files (if returning user with prior years)
    ↓
Phase 1: Create analysis files for each year's return
    ↓   (PDF/markdown → structured analysis, oldest first, accumulate context)
    ↓
Phase 2: Load ALL analyses into one context → Cross-year error detection
    ↓   (find CPA/self-prep mistakes, carryforward reconciliation, audit risks)
    ↓
Phase 3: Load analyses + current situation → Optimization strategy
    ↓   (aggressive, then filter by risk tolerance and state rules)
    ↓
Phase 4: Return preparation (Aiwyn calculation → tax software → e-file)
    ↓
Phase 5: Create analysis of draft return → cross-year validation
    ↓   (the flywheel closes)
    ↓
Phase 6: File + Document + Set Up Next Year
    ↓
The current year's analysis becomes next year's Phase 0 input (flywheel compounds)
```

**The flywheel effect:** Each year, the analysis files accumulate. By year 3+,
cross-year pattern detection becomes extremely powerful — inconsistencies, missed
carryforwards, suspicious patterns, and optimization opportunities that no single-year
review could find become visible.

---

## References

### Methodology
| Topic | Reference |
|-------|-----------|
| Complete intake questionnaire | [INTAKE-QUESTIONNAIRE.md](references/intake/INTAKE-QUESTIONNAIRE.md) |
| Cognitive operators (full cards) | [OPERATORS.md](references/methodology/OPERATORS.md) |
| Document checklist | [DOCUMENT-CHECKLIST.md](references/methodology/DOCUMENT-CHECKLIST.md) |
| All template prompts | [PROMPTS.md](references/methodology/PROMPTS.md) |
| Deadlines calendar | [DEADLINES.md](references/methodology/DEADLINES.md) |
| Audit defense playbook | [AUDIT-DEFENSE.md](references/methodology/AUDIT-DEFENSE.md) |

### Federal Tax Law
| Topic | Reference |
|-------|-----------|
| Brackets, rates, forms, provisions | [FEDERAL-TAX-PROVISIONS.md](references/federal/FEDERAL-TAX-PROVISIONS.md) |

### State Tax Guides (50 states + DC)
| State | Reference |
|-------|-----------|
| All 50 states + DC | `references/states/{STATE_ABBREV}.md` |

### Tax Strategies
| Topic | Reference |
|-------|-----------|
| Entity selection (LLC, S-Corp, C-Corp) | [ENTITY-STRATEGIES.md](references/strategies/ENTITY-STRATEGIES.md) |
| Retirement plans | [RETIREMENT-PLANS.md](references/strategies/RETIREMENT-PLANS.md) |
| Home office deduction | [HOME-OFFICE.md](references/strategies/HOME-OFFICE.md) |
| Real estate strategies | [REAL-ESTATE.md](references/strategies/REAL-ESTATE.md) |
| Business optimization | [BUSINESS-OPTIMIZATION.md](references/strategies/BUSINESS-OPTIMIZATION.md) |
| Advanced strategies | [ADVANCED-STRATEGIES.md](references/strategies/ADVANCED-STRATEGIES.md) |
| Charitable giving | [CHARITABLE-GIVING.md](references/strategies/CHARITABLE-GIVING.md) |
| Investment tax strategies | [INVESTMENT-TAX-STRATEGIES.md](references/strategies/INVESTMENT-TAX-STRATEGIES.md) |
| Crypto and digital assets | [CRYPTO-DIGITAL-ASSETS.md](references/strategies/CRYPTO-DIGITAL-ASSETS.md) |
| SALT cap workarounds | [SALT-WORKAROUNDS.md](references/strategies/SALT-WORKAROUNDS.md) |
| Education tax benefits | [EDUCATION-TAX-BENEFITS.md](references/strategies/EDUCATION-TAX-BENEFITS.md) |
| Health savings (HSA/HRA/FSA) | [HEALTH-SAVINGS.md](references/strategies/HEALTH-SAVINGS.md) |

### Professions
| Profession | Reference |
|-----------|-----------|
| 21 profession-specific guides | `references/professions/{PROFESSION}.md` |

### Life Events
| Event | Reference |
|-------|-----------|
| 17 life-event guides | `references/life-events/{EVENT}.md` |

### Situations
| Situation | Reference |
|-----------|-----------|
| Self-employed | [SELF-EMPLOYED.md](references/situations/SELF-EMPLOYED.md) |
| High income | [HIGH-INCOME.md](references/situations/HIGH-INCOME.md) |
| Investor | [INVESTOR.md](references/situations/INVESTOR.md) |
| Rental property owner | [RENTAL-PROPERTY-OWNER.md](references/situations/RENTAL-PROPERTY-OWNER.md) |
| Multi-state | [MULTI-STATE.md](references/situations/MULTI-STATE.md) |
| First-time filer | [FIRST-TIME-FILER.md](references/situations/FIRST-TIME-FILER.md) |
| Expat / foreign income | [EXPAT-FOREIGN-INCOME.md](references/situations/EXPAT-FOREIGN-INCOME.md) |
| Retiree | [RETIREE.md](references/situations/RETIREE.md) |
| Business exit planning | [BUSINESS-EXIT-PLANNING.md](references/situations/BUSINESS-EXIT-PLANNING.md) |
| International tax | [INTERNATIONAL-TAX.md](references/situations/INTERNATIONAL-TAX.md) |
| Divorce tax planning | [DIVORCE-TAX-PLANNING.md](references/situations/DIVORCE-TAX-PLANNING.md) |
| Tax planning by income tier | [TAX-PLANNING-BY-INCOME-TIER.md](references/situations/TAX-PLANNING-BY-INCOME-TIER.md) |

### Battle-Tested Methodology
| Topic | Reference |
|-------|-----------|
| Common errors and corrections | [COMMON-ERRORS-AND-CORRECTIONS.md](references/methodology/COMMON-ERRORS-AND-CORRECTIONS.md) |
| Verification-first protocol | [VERIFICATION-FIRST-PROTOCOL.md](references/methodology/VERIFICATION-FIRST-PROTOCOL.md) |

### Tools
| Tool | Reference |
|------|-----------|
| FreeTaxUSA + Playwright automation | [BROWSER-AUTOMATION-FREETAXUSA.md](references/tools/BROWSER-AUTOMATION-FREETAXUSA.md) |
| Aiwyn Tax Engine (MCP) | [AIWYN-INTEGRATION.md](references/tools/AIWYN-INTEGRATION.md) |

### Advanced Tax Planning
| Topic | Reference |
|-------|-----------|
| Trust taxation | [TRUST-TAXATION.md](references/strategies/TRUST-TAXATION.md) |
| Estate planning | [ESTATE-PLANNING.md](references/strategies/ESTATE-PLANNING.md) |
| Opportunity Zones | [OPPORTUNITY-ZONES.md](references/strategies/OPPORTUNITY-ZONES.md) |
| QSBS Section 1202 | [QSBS-SECTION-1202.md](references/strategies/QSBS-SECTION-1202.md) |
| Short-term rental loophole | [SHORT-TERM-RENTAL-LOOPHOLE.md](references/strategies/SHORT-TERM-RENTAL-LOOPHOLE.md) |
| Deferred compensation | [DEFERRED-COMPENSATION.md](references/strategies/DEFERRED-COMPENSATION.md) |
| Tax-efficient withdrawals | [TAX-EFFICIENT-WITHDRAWAL.md](references/strategies/TAX-EFFICIENT-WITHDRAWAL.md) |
| Social Security optimization | [SOCIAL-SECURITY-OPTIMIZATION.md](references/strategies/SOCIAL-SECURITY-OPTIMIZATION.md) |
| AMT strategies | [AMT-STRATEGIES.md](references/strategies/AMT-STRATEGIES.md) |
| Strategy interactions | [STRATEGY-INTERACTION-MATRIX.md](references/strategies/STRATEGY-INTERACTION-MATRIX.md) |
| Basis tracking | [BASIS-TRACKING.md](references/strategies/BASIS-TRACKING.md) |
| Estimated tax strategies | [ESTIMATED-TAX-STRATEGIES.md](references/strategies/ESTIMATED-TAX-STRATEGIES.md) |
| Divorce tax planning | [DIVORCE-TAX-PLANNING.md](references/situations/DIVORCE-TAX-PLANNING.md) |
| Tax planning by income tier | [TAX-PLANNING-BY-INCOME-TIER.md](references/situations/TAX-PLANNING-BY-INCOME-TIER.md) |
| Carryforward tracking | [CROSS-YEAR-CARRYFORWARD-LEDGER.md](references/methodology/CROSS-YEAR-CARRYFORWARD-LEDGER.md) |
| Red flag checklist | [RED-FLAG-CHECKLIST.md](references/methodology/RED-FLAG-CHECKLIST.md) |
| Private Placement Life Insurance | [PRIVATE-PLACEMENT-LIFE-INSURANCE.md](references/strategies/PRIVATE-PLACEMENT-LIFE-INSURANCE.md) |
| Captive insurance (Section 831(b)) | [CAPTIVE-INSURANCE.md](references/strategies/CAPTIVE-INSURANCE.md) |
| Defined Benefit / Cash Balance Plans | [DEFINED-BENEFIT-PLANS.md](references/strategies/DEFINED-BENEFIT-PLANS.md) |
| Delaware Statutory Trusts (1031) | [DELAWARE-STATUTORY-TRUSTS.md](references/strategies/DELAWARE-STATUTORY-TRUSTS.md) |
