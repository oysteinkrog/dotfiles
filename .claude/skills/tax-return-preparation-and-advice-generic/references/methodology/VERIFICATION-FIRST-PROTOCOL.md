# Verification-First Protocol

A systematic verification protocol designed to prevent the errors documented in COMMON-ERRORS-AND-CORRECTIONS.md. Every step in this protocol was motivated by an actual error that cost real dollars.

---

## The Core Principle

**Before computing any optimization, before running any calculation, before giving any filing recommendation -- VERIFY the source data.**

The most expensive tax errors come from optimizing incorrect inputs, not from suboptimal strategy. A perfectly optimized return built on wrong numbers is worse than a conservatively prepared return built on verified data.

---

## Step 1: Document Inventory

Before touching any calculation, create a complete checklist of every source document expected for the taxpayer. Cross-reference against prior year to identify any missing items.

### Document Inventory Checklist

**Employment Income:**
- [ ] W-2 from each employer (verify count against prior year)
- [ ] W-2 Box 12 codes reviewed (retirement contributions, health insurance, etc.)
- [ ] Final pay stub for December (to reconcile against W-2)

**Investment Income:**
- [ ] 1099-INT from each bank/credit union
- [ ] 1099-DIV from each brokerage
- [ ] 1099-B from each brokerage (check for supplemental pages with cost basis)
- [ ] 1099-COMP / 1099-NEC from each client (self-employment)
- [ ] K-1 from each partnership/S-Corp
- [ ] 1099-R from retirement distributions (if any)

**Mortgage and Real Estate:**
- [ ] 1098 from each mortgage servicer (check for servicer transfers -- may have 2+)
- [ ] Closing disclosure (if purchase/refinance this year -- check for prepaid interest)
- [ ] Property tax statements from county

**Self-Employment:**
- [ ] Business income records (1099-NEC, invoices, bank deposits)
- [ ] Business expense records (credit card statements, receipts, accounting exports)
- [ ] Home office measurements (square footage of office AND total livable space)
- [ ] Vehicle mileage log (if claiming business mileage)
- [ ] Health insurance premiums (Form 1095-A if marketplace)

**Other:**
- [ ] 1098-T (education)
- [ ] 1098-E (student loan interest)
- [ ] Childcare provider information (name, address, SSN/EIN, amounts paid)
- [ ] Charitable contribution records (cash receipts, non-cash valuations)
- [ ] Estimated tax payment records (dates and amounts for federal and state)
- [ ] Prior-year overpayment applied to current year

**Prior Year:**
- [ ] Prior-year filed federal return (PDF or transcript)
- [ ] Prior-year filed state return(s)
- [ ] Prior-year carryforward amounts identified (capital losses, home office, NOL, AMT credit)

### Missing Document Protocol

For each expected document that is NOT received:
1. Ask the taxpayer explicitly: "Did you receive a [document type] from [expected issuer]?"
2. If yes but lost: request a copy from the issuer or download from their portal
3. If no and unexpected: investigate whether the relationship/account changed
4. If legitimately not applicable this year: document why

**Do NOT proceed to calculations until the document inventory is complete.** Missing a single 1098 from a transferred mortgage can cost $10,000+ in missed deductions.

---

## Step 2: Cross-Document Reconciliation

Once all documents are collected, verify internal consistency. Discrepancies at this stage reveal data problems before they become filing errors.

### Income Reconciliation

| Source A | Source B | Reconciliation Check |
|----------|----------|---------------------|
| W-2 Box 1 (wages) | December pay stub YTD | Should match within $100 |
| W-2 Box 3 (SS wages) | W-2 Box 1 | Box 3 is capped at SS wage base ($176,100 for 2025) |
| W-2 Box 5 (Medicare wages) | W-2 Box 1 | Usually equal; may differ by pre-tax benefits |
| 1099-INT total | Bank year-end summary | Should match exactly |
| 1099-DIV Box 1a | Brokerage year-end summary | Should match exactly |
| 1099-B proceeds | Brokerage transaction history | Should match; verify cost basis separately |
| 1099-NEC amounts | Business invoices/bank deposits | 1099 may understate if some clients did not issue 1099s |
| K-1 amounts | Partnership/S-Corp return | Should match the corresponding K-1 line on the entity return |

### Mortgage Interest Reconciliation

This is the single most important reconciliation. Errors here are extremely common.

1. List ALL 1098s received. If a mortgage was transferred, expect 2+ 1098s for the same loan.
2. For each 1098:
   - Identify the servicer and the period covered
   - Verify the interest amount is reasonable for the period (monthly rate x months)
   - Example: 6.125% on $905K = $4,620/month. A 1098 showing $4,620 is ONE month.
3. If a purchase or refinance occurred:
   - Pull the closing disclosure
   - Find the prepaid interest amount
   - This amount appears on NO 1098 -- add it to the total
4. Sum all sources:
   ```
   Total deductible mortgage interest =
     1098 from Servicer A (months 1-2) .......... $9,240
   + 1098 from Servicer B (months 3-12) ......... $46,200
   + Prepaid interest from closing disclosure .... $3,080
   = Total ....................................... $58,520
   ```

### Carryforward Reconciliation

For EACH carryforward item, verify the amount and character from the prior-year return:

| Carryforward Type | Prior Year Source | Line Reference |
|-------------------|-------------------|---------------|
| Short-term capital loss | Schedule D + Carryover Worksheet | Lines 7, 21, Worksheet Line 8 |
| Long-term capital loss | Schedule D + Carryover Worksheet | Lines 15, 21, Worksheet Line 13 |
| Home office expenses | Form 8829 | Lines 43 (casualty), 44 (operating) |
| Net Operating Loss | Form 1045 or manual calculation | Varies |
| AMT credit | Form 8801 | Line 25 |
| Charitable contribution | Schedule A | 5-year carryforward of excess contributions |

**Character tracking is critical for capital losses.** Short-term and long-term carryforwards must be tracked separately. See COMMON-ERRORS-AND-CORRECTIONS.md for the full explanation of why.

---

## Step 3: Rate and Threshold Verification

Tax law changes annually. AI models frequently cite outdated rates. Before using ANY rate, threshold, or dollar amount in a calculation, verify it.

### Current Year Rates Verification Checklist (2025)

| Item | Correct 2025 Value | Source | Verified? |
|------|-------------------|--------|-----------|
| MFJ standard deduction | $31,500 (OBBBA) | IRS Form 1040 instructions | [ ] |
| Single standard deduction | $15,750 (OBBBA) | IRS Form 1040 instructions | [ ] |
| SALT cap (MFJ) | $40,000 (OBBBA), phase-down >$500K | OBBBA text | [ ] |
| CTC per child | $2,200 (OBBBA) | Schedule 8812 instructions | [ ] |
| Business mileage rate | $0.70/mile | IRS Notice (annual) | [ ] |
| Medical mileage rate | $0.22/mile | IRS Notice (annual) | [ ] |
| Charitable mileage rate | $0.14/mile | IRC 170(i) | [ ] |
| SS wage base | $176,100 | SSA announcement | [ ] |
| SE tax rate | 15.3% (up to SS base), 2.9% (above) | Schedule SE instructions | [ ] |
| SE income factor | 92.35% (0.9235) | Schedule SE instructions | [ ] |
| SEP-IRA rate (self-employed) | 20% effective (not 25%) | IRS Publication 560 | [ ] |
| Additional Medicare Tax threshold | $250,000 MFJ | Form 8959 instructions | [ ] |
| NIIT threshold | $250,000 MAGI (MFJ) | Form 8960 instructions | [ ] |
| Bonus depreciation (post-Jan 19 2025) | 100% (OBBBA) | OBBBA text | [ ] |
| Bonus depreciation (pre-Jan 20 2025) | 40% (TCJA phasedown) | IRC 168(k) | [ ] |
| De minimis safe harbor | $2,500/item | Reg. 1.263(a)-1(f)(1)(ii) | [ ] |
| QBI deduction phase-out (MFJ) | $394,600-$494,600 | IRS Rev. Proc. | [ ] |

### Verification Protocol

For each rate/threshold:
1. Check the current-year IRS form instructions (primary source)
2. Cross-reference with IRS.gov or a second authoritative source
3. If using an AI model's cited rate, verify independently -- do NOT trust the model's number
4. Document the verified rate with its source citation in workpapers

---

## Step 4: Calculation Verification

### Rule: AI Models Do NOT Do Arithmetic

AI models (Claude, GPT, Gemini) should be used for:
- Identifying applicable tax rules and forms
- Recommending optimization strategies
- Reviewing for completeness and missed deductions
- Explaining tax concepts and implications

AI models should NOT be used for:
- Final arithmetic on any line item
- Complex multi-step calculations (especially those with circular references like SEP-IRA)
- Tax liability computation
- Penalty and interest calculations

### Deterministic Calculation Sources

Use these for all arithmetic:
1. **Aiwyn MCP tools** -- `calculate_tax` for federal and state computation
2. **Tax preparation software** -- FreeTaxUSA, TurboTax, TaxAct (built-in calculators)
3. **Spreadsheet formulas** -- For custom calculations not handled by the above
4. **IRS worksheets** -- From the form instructions (manually computed but deterministic)

### Cross-Validation Protocol

For every return:
1. Run the calculation through Aiwyn
2. Enter the same data into FreeTaxUSA (or other e-filing software)
3. Compare key totals:
   - Adjusted Gross Income
   - Taxable Income
   - Total Tax (federal)
   - Self-Employment Tax
   - Total Payments/Withholding
   - Refund or Amount Due
   - State tax
4. Investigate ANY discrepancy, no matter how small
5. A $1 rounding difference is acceptable; a $100+ difference means something is wrong

---

## Step 5: Multi-Model Review for Aggressive Positions

An "aggressive position" is any deduction, credit, or filing position that is:
- At the boundary of IRS rules (could be argued either way)
- Unusually large relative to income
- Based on a less-common provision
- Different from what was claimed in prior years

### Multi-Model Review Protocol

1. Present the fact pattern to at least 2 AI models independently
2. Do NOT show one model the other's work
3. Compare their recommendations
4. **Disagreements are the highest-value findings** -- investigate every disagreement by going to the primary source (statute, regulation, IRS publication)
5. Document the resolution

### Real-World Examples from Practice

In the 2025 filing season, multi-model cross-validation caught:

| Error | Found By | Missed By | Source Resolution |
|-------|----------|-----------|-------------------|
| SEP-IRA 25% vs 20% rate | Codex (GPT) | Claude | IRS Pub 560 confirms 20% |
| Outdated mileage rate ($0.67) | Codex (GPT) | Claude | IRS Notice confirms $0.70 |
| Outdated standard deduction | Claude | GPT | OBBBA text confirms $31,500 |
| Zero-basis crypto election | Codex (GPT) | Both initially | Valid per Reg. 1.1012-1 |
| Home office % calculation | Gemini | Claude, GPT | Pub 587 confirms livable sq ft |

---

## Step 6: Pre-Filing Audit Checklist

Before finalizing any return, run through this checklist.

### Line Item Verification

- [ ] Every income line has a source document (W-2, 1099, K-1, etc.)
- [ ] Every deduction line has a source document or calculation supporting it
- [ ] All carryforward amounts verified against prior-year return
- [ ] All rates and thresholds verified against current-year IRS guidance

### Reasonableness Checks

- [ ] AGI is within expected range based on prior year and known changes
- [ ] Total tax is reasonable for the income level and filing status
- [ ] Effective tax rate makes sense (compare against standard rate tables)
- [ ] Self-employment tax is correct (check SS wage base interaction)
- [ ] State tax is reasonable for the state and income level

### Red Flag Review

- [ ] No round numbers on deduction lines (e.g., $5,000 exactly for charitable is suspicious)
- [ ] No identical percentages across different properties or businesses
- [ ] Schedule C does not zero out perfectly after deductions
- [ ] Home office percentage is reasonable for the home size
- [ ] Business expenses are not disproportionately large relative to business income
- [ ] Capital gains/losses are properly characterized (ST vs LT)

### Cross-Year Comparison

- [ ] Compare current year against prior year for major line items
- [ ] Identify and explain any significant changes (>20% swing)
- [ ] Common legitimate changes: new job, new home, new business, investment gains/losses
- [ ] Unexplained changes = possible data error, investigate before filing

### Carryforward Ledger Update

- [ ] Current-year carryforward amounts computed and documented
- [ ] Capital loss carryforward computed separately for ST and LT characters
- [ ] Home office carryforward from Form 8829 Lines 43/44 recorded
- [ ] NOL carryforward computed if applicable
- [ ] AMT credit carryforward computed if applicable
- [ ] Charitable contribution carryforward computed if applicable
- [ ] Ledger saved in a durable location for next year's preparer

### Documentation Package

- [ ] Final return PDF saved
- [ ] Draft analysis document created (using same format as prior years for consistency)
- [ ] Source documents organized and stored
- [ ] Carryforward ledger updated
- [ ] Any aggressive positions documented with supporting authority
- [ ] Multi-model review notes retained (which models, what they found)

---

## Quick Reference: Verification Order of Operations

For a new return, follow this sequence strictly:

```
1. COLLECT    Gather all source documents (Step 1)
2. RECONCILE  Cross-check documents against each other (Step 2)
3. VERIFY     Confirm all rates/thresholds are current year (Step 3)
4. CALCULATE  Run through Aiwyn + tax software (Step 4)
5. REVIEW     Multi-model check on aggressive positions (Step 5)
6. AUDIT      Pre-filing checklist (Step 6)
7. ENTER      Input into e-filing software
8. COMPARE    Verify e-filing totals match calculation
9. FILE       Submit only when everything matches
```

Do NOT skip to step 4 (calculate) before completing steps 1-3. The temptation to "just start calculating" is the root cause of most expensive errors.

---

## When to STOP and Escalate

Stop the preparation process and escalate to a CPA or tax attorney when:

- **Aiwyn returns a disqualification** -- Do not attempt to work around it
- **Multi-model review produces irreconcilable disagreement** on a material position -- The position needs human professional judgment
- **Source documents are contradictory** -- e.g., W-2 and pay stubs do not reconcile, and the taxpayer cannot explain the discrepancy
- **Unusual transactions** -- Cryptocurrency with complex DeFi interactions, international transfers above reporting thresholds, estate/trust distributions, partnership dissolution
- **Audit notice received** -- All preparation work stops; representation requires authorization (Form 2848)
- **Suspected fraud or unreported income** -- The preparer has due diligence obligations under Circular 230

---

*Last updated: 2026-04-13. This protocol is a living document. Each error caught in practice should generate a new entry in COMMON-ERRORS-AND-CORRECTIONS.md and a corresponding verification step here.*
