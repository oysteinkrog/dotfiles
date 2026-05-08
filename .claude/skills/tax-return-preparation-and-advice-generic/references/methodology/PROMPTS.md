# Tax Return Preparation Template Prompts

Standardized prompts for each phase of AI-assisted tax return preparation. All prompts use [BRACKET PLACEHOLDERS] for taxpayer-specific data. Replace placeholders with actual values before executing.

---

## Phase 1: Data Gathering and Prior Year Analysis

### First-Year Analysis Prompt (New Taxpayer)

```
I am preparing a [TAX_YEAR] federal and [STATE] state tax return for a new taxpayer.

Filing status: [SINGLE / MFJ / MFS / HOH / QSS]
State(s) of residence: [STATE(S)], with any part-year or multi-state situations: [DETAILS]
Dependents: [NUMBER_AND_AGES]

No prior year return is available for comparison. Begin with the Document Checklist and confirm which categories apply:

1. Employment income (W-2): [YES/NO, HOW MANY EMPLOYERS]
2. Self-employment income (1099-NEC/K): [YES/NO, WHAT BUSINESS]
3. Investment income (dividends, interest, capital gains): [YES/NO]
4. Rental property income: [YES/NO, HOW MANY PROPERTIES]
5. Cryptocurrency transactions: [YES/NO]
6. Pass-through entities (K-1s): [YES/NO, HOW MANY]
7. Retirement distributions: [YES/NO]
8. Social Security: [YES/NO]
9. Any life events this year: [MARRIAGE / DIVORCE / CHILD / HOME_PURCHASE / HOME_SALE / JOB_CHANGE / BUSINESS_START / RETIREMENT / OTHER]

For each applicable category, I will provide documents. Begin processing when documents are provided.
```

### Subsequent-Year Analysis Prompt (Returning Taxpayer)

```
I am preparing the [TAX_YEAR] federal and [STATE] state tax return. Prior year ([PRIOR_YEAR]) return is attached/provided.

PRIOR YEAR KEY FIGURES:
- AGI: $[AMOUNT]
- Total tax: $[AMOUNT]
- Effective rate: [RATE]%
- Filing status: [STATUS]
- Estimated taxes paid (current year): Q1 $[AMT], Q2 $[AMT], Q3 $[AMT], Q4 $[AMT]
- Withholding (current year W-2s): $[AMOUNT]

CARRYFORWARDS FROM PRIOR YEAR:
- Capital loss carryforward: $[AMOUNT] or NONE
- Net operating loss: $[AMOUNT] or NONE
- Passive activity loss: $[AMOUNT] per activity or NONE
- Home office carryforward: $[AMOUNT] or NONE
- Charitable contribution carryforward: $[AMOUNT] or NONE
- Business credit carryforward: $[AMOUNT] or NONE
- AMT credit carryforward: $[AMOUNT] or NONE
- Foreign tax credit carryforward: $[AMOUNT] or NONE
- Section 179 carryforward: $[AMOUNT] or NONE

CHANGES FROM PRIOR YEAR:
[LIST ALL CHANGES: new income sources, lost income sources, new dependents, address change, entity changes, new properties, sold properties, etc.]

Begin Phase 1: Process all [TAX_YEAR] documents and flag any significant variances from prior year (>10% change in any major line item).
```

### Part-by-Part Document Processing Prompt

```
Process the following [DOCUMENT_TYPE] for [TAX_YEAR]:

Document: [FORM_NUMBER — e.g., W-2, 1099-NEC, 1099-B, K-1]
From: [ISSUER_NAME]
Key figures: [PASTE OR DESCRIBE KEY BOXES/AMOUNTS]

Extract:
1. Gross amount and tax category (ordinary income, LTCG, STCG, qualified dividend, etc.)
2. Any withholding (federal, state, local)
3. Any special codes or adjustments (W-2 Box 12 codes, K-1 special allocations)
4. Cross-reference with prior year same document — flag variances
5. Identify any follow-up questions or missing information

Format output as structured data for return assembly.
```

### Income Reconciliation Prompt

```
Reconcile all [TAX_YEAR] income documents against bank deposits and records:

Total W-2 wages: $[AMOUNT] across [NUMBER] employers
Total 1099-NEC: $[AMOUNT] across [NUMBER] payers
Total 1099-K: $[AMOUNT] across [NUMBER] platforms
Total K-1 income: $[AMOUNT] across [NUMBER] entities
Total investment income: $[AMOUNT] (interest $[AMT] + dividends $[AMT] + capital gains $[AMT])
Total rental income: $[AMOUNT] across [NUMBER] properties
Total other income: $[AMOUNT] — [DESCRIBE]

Bank deposit total for year: $[AMOUNT]
Known non-income deposits: $[AMOUNT] — [DESCRIBE: transfers, loans, gifts, reimbursements]

Flag any unexplained gap between reported income and bank deposits exceeding $[THRESHOLD].
Identify any 1099s that may not have been received (e.g., cash payments > $600 from a single payer).
```

---

## Phase 2: Cross-Year Error Detection

### Error Detection Prompt

```
Perform cross-year error detection comparing [TAX_YEAR] return draft with [PRIOR_YEAR] return.

Check the following categories for errors, inconsistencies, or missed opportunities:

1. INCOME CONSISTENCY
   - Did any W-2 employer disappear without explanation?
   - Did any 1099 payer disappear without explanation?
   - Did rental income change by more than [X]% without a documented reason?
   - Are all K-1s from prior year accounted for (or disposition documented)?

2. DEDUCTION CONSISTENCY
   - Is the home office percentage the same? If changed, is the change documented?
   - Is the vehicle business use percentage the same? If changed, is the change documented?
   - Did charitable giving change dramatically? (Flag for bunching strategy review)
   - Are all depreciation schedules continuing correctly from prior year?
   - Did any asset disposition occur requiring depreciation recapture?

3. CARRYFORWARD ACCURACY
   - Does the capital loss carryforward from [PRIOR_YEAR] match Schedule D Line 21?
   - Do passive loss carryforwards match Form 8582 worksheets?
   - Does the NOL carryforward match the NOL computation worksheet?
   - Are all charitable carryforwards properly tracked by year of origin?
   - Is the AMT credit carryforward properly reflected on Form 8801?

4. CALCULATION VERIFICATION
   - Does QBI deduction use the correct W-2 wages and UBIA figures from K-1s?
   - Is self-employment tax calculated on 92.35% of net SE income?
   - Is the SE health insurance deduction limited to net SE income?
   - Is the home office deduction limited by gross income?
   - Are estimated tax payments credited to the correct year?

5. ELECTIONS AND FORMS
   - Is Form 8606 filed (for any nondeductible IRA contribution or Roth conversion)?
   - Is Form 8829 consistent with prior year?
   - Is de minimis safe harbor election made if assets under threshold were expensed?
   - Are all required foreign reporting forms filed (FBAR, 8938)?

List all findings as: [SEVERITY: Critical/Warning/Info] [CATEGORY] [DESCRIPTION] [RECOMMENDED_ACTION]
```

---

## Phase 3: Optimization Strategy

### Comprehensive Optimization Prompt

```
Perform tax optimization analysis for [TAX_YEAR] return:

CURRENT RETURN SUMMARY:
- Filing status: [STATUS]
- AGI: $[AMOUNT]
- Taxable income: $[AMOUNT]
- Total tax: $[AMOUNT]
- Effective rate: [RATE]%
- Marginal federal bracket: [BRACKET]%
- State marginal rate: [RATE]%

APPLY ALL COGNITIVE OPERATORS:

1. $ STACK-DECOMPOSE: Build the full tax stack for this taxpayer. What is the true marginal rate on the next dollar of: (a) ordinary income, (b) SE income, (c) LTCG, (d) qualified dividends?

2. ⟳ ENTITY-ARBITRAGE: If self-employed, compare current structure vs. S-Corp. Calculate SE tax savings net of payroll costs. If already S-Corp, evaluate reasonable salary level.

3. ⌂ SPACE-SPLIT: Review home office (simplified vs. regular), vehicle (mileage vs. actual), and any mixed-use assets. Which method produces the larger deduction?

4. ↻ CARRYFORWARD-HARVEST: List all carryforwards. Can any be used this year? Should income be recognized to absorb capital losses? Should a passive activity be disposed to release suspended losses?

5. 🏗 DEPRECIATION-ACCELERATE: Review all depreciable assets. Can any be reclassified? Should cost segregation be pursued? Is Section 179 or bonus depreciation being maximized?

6. ⏱ DEADLINE-GATE: What deadlines remain for [TAX_YEAR] (if pre-filing) or upcoming [NEXT_YEAR] strategies? Flag any irrecoverable deadlines within 90 days.

7. 🔀 INCOME-SHIFT: Can income be shifted to a lower-bracket year? Should Roth conversion be done? Can income be split with family members?

8. 🛡 AUDIT-SHIELD: Score each aggressive position. Is documentation sufficient? Any positions requiring Form 8275 disclosure?

9. 🔗 STRATEGY-CHAIN: Map interactions between all proposed strategies. Identify conflicts. Calculate the net combined benefit (not just sum of individual benefits).

OUTPUT FORMAT:
For each strategy, provide:
- Description of the strategy
- Estimated tax savings (federal + state + SE/FICA)
- Implementation steps
- Risk level (1-5)
- Documentation requirements
- Deadline for implementation
- Conflicts with other strategies

TOTAL ESTIMATED SAVINGS: $[AMOUNT]
RANKED STRATEGIES (by savings-to-risk ratio): [LIST]
```

### Retirement Contribution Optimization Prompt

```
Optimize retirement contributions for [TAX_YEAR]:

CURRENT SITUATION:
- Taxpayer age: [AGE] (catch-up eligible if 50+)
- Spouse age: [AGE]
- Total earned income (taxpayer): $[AMOUNT]
- Total earned income (spouse): $[AMOUNT]
- Self-employment net income: $[AMOUNT] or N/A
- W-2 income: $[AMOUNT]
- Employer 401(k) available: [YES/NO], employer match: [DETAILS]
- Current IRA balance (traditional): $[AMOUNT]
- Current IRA balance (Roth): $[AMOUNT]
- Marginal tax rate: [RATE]%
- Expected retirement tax rate: [ESTIMATED_RATE]%

EVALUATE ALL VEHICLES:
1. 401(k)/403(b): Employee limit $23,000 ($30,500 if 50+); employer match
2. Solo 401(k): Employee $23,000 + Employer 25% of comp (20% of SE net)
3. SEP-IRA: 25% of W-2 or 20% of SE net, up to $69,000 (2024)
4. SIMPLE IRA: $16,000 ($19,500 if 50+) + employer match/contribution
5. Traditional IRA: $7,000 ($8,000 if 50+) — deductibility depends on plan coverage and income
6. Roth IRA: $7,000 ($8,000 if 50+) — income limits; backdoor if over limit
7. HSA: $4,150/$8,300 (2024) — triple tax advantage if HDHP enrolled
8. Defined Benefit Plan: Actuarially determined; can be $100K+ if older

QUESTIONS:
- Does a backdoor Roth make sense? (Check pro-rata rule -- traditional IRA balance)
- Does mega-backdoor Roth apply? (After-tax 401k contributions + in-plan conversion)
- Traditional vs. Roth: given current vs. expected future rate, which wins?
- Can SEP-IRA and Solo 401(k) be combined? (Generally not with same employer)
- Total maximum across all vehicles: $[CALCULATE]
```

---

## Phase 4: Tax Software Walkthrough

### Software Entry Prompt

```
Guide me through entering this return in [SOFTWARE_NAME: TurboTax / FreeTaxUSA / H&R Block / TaxAct / Drake / ProSeries / Lacerte]:

RETURN OVERVIEW:
- Filing status: [STATUS]
- Dependents: [NUMBER]
- Income types: [LIST: W-2, 1099-NEC, 1099-B, K-1, Schedule E, etc.]
- Deduction method: [STANDARD / ITEMIZED]
- Special forms needed: [LIST: 8829, 4562, 8606, 8582, etc.]

Walk me through step by step:
1. Personal information and filing status entry
2. Income entry (in the order the software expects it)
3. Adjustments to income (above-the-line deductions)
4. Deductions (standard vs. itemized; Schedule A details)
5. Credits (child, education, energy, etc.)
6. Other taxes (SE tax, AMT, etc.)
7. Payments and estimated taxes
8. State return entry
9. Review and error check

For each step, specify:
- Where to navigate in the software
- What values to enter and in which fields
- Common mistakes to avoid at that step
- How to verify the entry is correct (what should the running total show)

Flag any entries where the software default may not be optimal (e.g., depreciation method, basis reporting, state allocation).
```

---

## Phase 5: Draft Validation

### Pre-Filing Validation Prompt

```
Validate the draft [TAX_YEAR] return before filing:

DRAFT RETURN FIGURES:
- Total income (Line 9): $[AMOUNT]
- AGI (Line 11): $[AMOUNT]
- Standard/itemized deduction: $[AMOUNT]
- QBI deduction: $[AMOUNT]
- Taxable income: $[AMOUNT]
- Total tax (Line 24): $[AMOUNT]
- Total payments (Line 33): $[AMOUNT]
- Refund or Amount due: $[AMOUNT]
- Effective tax rate: [RATE]%

VALIDATION CHECKS:

1. REASONABLENESS
   - Is the effective rate consistent with the income level and filing status?
   - How does this compare to [PRIOR_YEAR] effective rate? Variance explained?
   - Is the refund/balance due consistent with withholding and estimated payments?

2. MATHEMATICAL VERIFICATION
   - Does Line 9 equal sum of all income lines?
   - Does Line 11 equal Line 9 minus adjustments?
   - Is the standard deduction amount correct for filing status and age?
   - Does the QBI deduction calculation follow Section 199A correctly?
   - Is SE tax calculated on 92.35% of net SE income?
   - Is Additional Medicare Tax calculated correctly on excess wages?

3. FORM CROSS-REFERENCES
   - Does Schedule SE match Schedule C net income?
   - Does Form 8829 (home office) match Schedule C Line 30?
   - Does Form 4562 (depreciation) match all relevant schedules?
   - Do all K-1 amounts flow correctly to their respective schedules?
   - Does Form 8606 track basis in nondeductible IRA contributions?
   - Does Form 8582 correctly limit passive losses?

4. STATE RETURN VALIDATION
   - Does state AGI reconcile from federal AGI with proper adjustments?
   - Are state-specific deductions and credits claimed?
   - Does the state return reflect PTET credit if applicable?
   - Is the correct resident/nonresident/part-year form being used?

5. PRIOR YEAR COMPARISON
   - Line-by-line comparison of key figures to [PRIOR_YEAR]
   - Every variance > 10% flagged with explanation
   - Carryforward amounts verified against prior year ending balances

6. PAYMENT STRATEGY
   - If balance due: can it be paid in full, or is an installment agreement needed?
   - If large refund: should estimated payments be reduced next year?
   - Safe harbor analysis for next year's estimated taxes

List all findings with severity levels and recommended corrections before filing.
```

---

## Scenario Modeling Prompts

### Tax Scenario Comparison Prompt

```
Model the following [NUMBER] tax scenarios for [TAX_YEAR] and compare outcomes:

BASE CASE: [DESCRIBE CURRENT SITUATION]

SCENARIO A: [DESCRIBE CHANGE — e.g., "Elect S-Corp status, pay $80K reasonable salary"]
SCENARIO B: [DESCRIBE CHANGE — e.g., "Maximize Solo 401k contributions"]
SCENARIO C: [DESCRIBE CHANGE — e.g., "Perform $50K Roth conversion"]
SCENARIO D: [DESCRIBE CHANGE — e.g., "Purchase $30K equipment for Section 179"]
SCENARIO AB: [COMBINE SCENARIOS A + B]
SCENARIO ABCD: [COMBINE ALL]

For each scenario, calculate:
1. Federal tax liability
2. State tax liability
3. Self-employment tax
4. Total tax liability
5. Effective tax rate
6. Tax savings vs. base case
7. Implementation cost (compliance, fees, etc.)
8. Net benefit after implementation cost
9. Risk score (1-5)
10. Downstream effects on future years

Produce a comparison table and recommend the optimal combination.
```

### Multi-Year Projection Prompt

```
Project tax liability over [NUMBER] years under the following assumptions:

CURRENT YEAR ([TAX_YEAR]):
- Income: $[AMOUNT] ([GROWTH_RATE]% annual growth)
- Self-employment income: $[AMOUNT] ([GROWTH_RATE]% annual growth)
- Investment income: $[AMOUNT] ([GROWTH_RATE]% annual growth)
- Deductions: $[AMOUNT]
- Retirement contributions: $[AMOUNT]

ASSUMPTIONS:
- Tax law: [CURRENT_LAW / SCHEDULED_CHANGES — e.g., TCJA expiration 2026]
- State: [STATE] (any planned moves?)
- Filing status: [STATUS] (any changes expected?)
- Life events: [EXPECTED_EVENTS — retirement, sale of business, etc.]

MODEL:
Year 1 through Year [N]:
- Projected income (all sources)
- Projected deductions
- Projected tax liability
- Cumulative tax over period
- NPV of tax liability at [DISCOUNT_RATE]%

COMPARE:
- Strategy 1: [DESCRIBE — e.g., "Continue current approach"]
- Strategy 2: [DESCRIBE — e.g., "Convert $X to Roth per year for 5 years"]
- Strategy 3: [DESCRIBE — e.g., "Switch to S-Corp in Year 2"]

Total NPV tax difference between strategies: $[CALCULATE]
```

---

## Audit Defense Prompts

### Audit Response Prompt

```
An IRS [CORRESPONDENCE / OFFICE / FIELD] audit has been initiated for [TAX_YEAR].

NOTICE: [CP_NUMBER or LETTER_NUMBER]
ISSUES UNDER EXAMINATION:
[LIST EACH ISSUE — e.g., "Schedule C expenses", "Home office deduction", "Capital gains reporting"]

DUE DATE FOR RESPONSE: [DATE]

For each issue:
1. What is the IRS's likely position?
2. What documentation do we have? [LIST]
3. What documentation is missing? Can it be reconstructed?
4. What is the legal authority supporting our position? [CITE IRC sections, Treasury Regulations, Revenue Rulings, Tax Court cases]
5. What is the probability of prevailing? [HIGH / MEDIUM / LOW]
6. If we lose this issue, what is the tax impact? $[AMOUNT] + penalties + interest
7. What is the negotiation strategy? (Full concession, partial concession, appeals)

RESPONSE PLAN:
- Deadline management (extend if possible: 30-day letter response)
- Document organization (what to send, what NOT to send voluntarily)
- Representation strategy (CPA, EA, attorney)
- Settlement authority (what amount would we accept in a closing agreement)

Draft the response letter addressing each issue with supporting documentation references.
```

### Documentation Generation Prompt

```
Generate audit-ready documentation for the following position:

POSITION: [DESCRIBE — e.g., "Home office deduction of $X for Y sq ft office"]
TAX YEAR: [YEAR]
AMOUNT: $[AMOUNT]

Create:
1. Written narrative explaining the business purpose and factual basis
2. Calculation worksheet showing how the amount was determined
3. List of supporting documents with descriptions
4. Legal authority memo citing:
   - IRC section
   - Treasury Regulation
   - IRS Publication
   - Relevant Revenue Ruling or Tax Court case
5. Timeline of key events (dates of use, measurements, purchases)
6. Contemporaneous log template (if ongoing activity like mileage or home office use)
7. Third-party verification (if available — e.g., Google Timeline for mileage, utility bills for home office)

Ensure all documentation meets the substantiation requirements of IRC Section 274 (where applicable) and the Cohan rule limitations.
```

### Penalty Abatement Request Prompt

```
Draft a penalty abatement request for:

PENALTY TYPE: [FAILURE_TO_FILE / FAILURE_TO_PAY / ACCURACY_RELATED / ESTIMATED_TAX]
TAX YEAR: [YEAR]
PENALTY AMOUNT: $[AMOUNT]
INTEREST: $[AMOUNT]

GROUNDS FOR ABATEMENT:
1. First-Time Penalty Abatement (FTA):
   - Filing compliance for prior 3 years: [YES/NO]
   - Payment compliance for prior 3 years: [YES/NO]
   - No penalties in prior 3 years: [YES/NO]

2. Reasonable Cause:
   - What was the cause? [DESCRIBE — illness, natural disaster, reliance on professional, fire/casualty, IRS error, etc.]
   - When did the cause begin and end?
   - What steps were taken to comply as soon as possible?
   - Documentation of the cause: [LIST]

3. Statutory Exception:
   - Does an exception apply? [E.g., estimated tax penalty exception for >$1K threshold, 110% safe harbor, etc.]

Draft a formal letter to IRS using the appropriate format (Form 843 or written request), citing:
- IRM 20.1.1.3.2 (First-Time Abatement)
- IRM 20.1.1.3.1 (Reasonable Cause)
- Relevant Tax Court precedents for the penalty type
- Specific facts and supporting documentation
```

---

## Quarterly Planning Prompt

```
Perform quarterly tax planning review for Q[1/2/3/4] [TAX_YEAR]:

YEAR-TO-DATE ACTUAL (through [DATE]):
- W-2 wages earned: $[AMOUNT]
- Self-employment income earned: $[AMOUNT]
- Investment income earned: $[AMOUNT]
- Rental income earned: $[AMOUNT]
- Other income: $[AMOUNT]
- Estimated taxes paid YTD: $[AMOUNT]
- Withholding YTD: $[AMOUNT]

PROJECTED FULL-YEAR:
- Total income: $[AMOUNT]
- Total deductions: $[AMOUNT]
- Projected tax liability: $[AMOUNT]
- Projected payments: $[AMOUNT]
- Projected balance due/refund: $[AMOUNT]

QUESTIONS:
1. Are estimated tax payments on track to meet safe harbor (110% prior year / 90% current year)?
2. Should W-4 withholding be adjusted?
3. What optimization strategies should be executed this quarter?
4. Are any irrecoverable deadlines approaching?
5. What documentation should be gathered now?
6. Are there any legislative changes that affect this year's planning?

Produce a specific action list with deadlines for this quarter.
```

---

## TCJA Expiration Planning Prompt (2026+)

```
The Tax Cuts and Jobs Act provisions are scheduled to expire/change after [YEAR]. Model the impact on this taxpayer:

CURRENT YEAR RETURN FIGURES UNDER TCJA:
- Marginal bracket: [RATE]% (TCJA rates)
- Standard deduction: $[AMOUNT] (TCJA doubled amount)
- SALT deduction: $[AMOUNT] (capped at $10,000)
- QBI deduction: $[AMOUNT]
- Child Tax Credit: $[AMOUNT]
- AMT exemption: $[AMOUNT]

PROJECTED FIGURES IF TCJA EXPIRES (revert to pre-TCJA + inflation):
- Marginal bracket: [PROJECTED_RATE]%
- Standard deduction: $[PROJECTED_AMOUNT]
- SALT deduction: $[PROJECTED_AMOUNT] (uncapped)
- Personal exemptions: $[PROJECTED_AMOUNT] (return)
- QBI deduction: $0 (eliminated)
- Child Tax Credit: $[PROJECTED_AMOUNT] (reduced)
- AMT exemption: $[PROJECTED_AMOUNT] (reduced)

ANALYSIS:
1. Net tax increase/decrease if TCJA expires
2. Should Roth conversions be accelerated before expiration?
3. Should income be accelerated into lower-rate TCJA years?
4. Should deductions be deferred to post-TCJA higher-rate years?
5. Does the entity structure (S-Corp, etc.) need to change without QBI?
6. What proactive steps should be taken now?
```
