# Red Flag Checklist — Audit Trigger Identification and Risk Scoring

Master checklist of IRS audit triggers, aggressive position classification, documentation
shields, and multi-model validation protocols. Use this checklist during return preparation
to identify, score, and mitigate audit risk before filing.

---

## Risk Scoring System

Each position is scored on a 1-5 scale:

| Score | Risk Level | IRS Action Likelihood | Description |
|-------|-----------|----------------------|-------------|
| 1 | Minimal | <5% | Routine position with clear authority |
| 2 | Low | 5-15% | Supportable position, minor flags |
| 3 | Moderate | 15-30% | May trigger correspondence audit |
| 4 | High | 30-50% | Likely to trigger examination |
| 5 | Very High | >50% | Almost certain audit trigger |

---

## Schedule C (Self-Employment) Red Flags

| Red Flag | Risk Score | Trigger Threshold | Documentation Shield |
|----------|-----------|-------------------|---------------------|
| Net loss 3+ of 5 years | 4 | §183 hobby loss presumption inverts | Written business plan, profit trajectory, time log, professional consultation records |
| Revenue exactly matches deductions (zero net) | 4 | Suggests backward calculation | Independent expense calculation, bank reconciliation |
| 100% business use of vehicle | 5 | Almost no taxpayer has zero personal use | Mileage log (app-based: MileIQ, Stride), second personal vehicle evidence, odometer readings |
| Revenue under $25K with $20K+ expenses | 3 | High expense-to-revenue ratio | Detailed receipts, business purpose documentation, growth plan |
| Cash business with low gross receipts | 4 | Bank deposit analysis mismatch | POS records, daily sales summaries, bank deposit reconciliation |
| Meals exceeding 15% of gross revenue | 3 | Disproportionate meals expense | Per-meal documentation: date, location, attendees, business purpose |
| Large "Other Expenses" line | 3 | Suggests miscategorized or unsupported expenses | Break down into specific categories with receipts |
| No cost of goods sold for product business | 3 | Missing inventory accounting | Inventory records, supplier invoices, purchase orders |
| Revenue reported to the dollar ($50,000 exactly) | 2 | Suggests estimation | Bank statements proving actual amount |
| Home office + Schedule C loss = large refund | 5 | Classic audit pattern | Home office calculation, floor plan, photos, independent expense tracking |

## Schedule E (Rental Property) Red Flags

| Red Flag | Risk Score | Trigger Threshold | Documentation Shield |
|----------|-----------|-------------------|---------------------|
| Rental losses claimed without REP status (AGI >$150K) | 3 | §469 passive activity limits exceeded | Passive loss carryforward tracking, AGI documentation |
| Real Estate Professional status claimed | 4 | 750 hours + material participation = high bar | Contemporaneous time log (not reconstructed), calendar entries, detailed hour tracking by property |
| Rental loss offsetting W-2 income >$25K | 2 | Active participation exception capped at $25K ($150K AGI phaseout) | Active participation evidence (tenant selection, repairs, management decisions) |
| Repairs exceeding 25% of rental income | 3 | May be capital improvements misclassified | Before/after photos, contractor invoices, descriptions proving repair vs. improvement |
| Personal use of rental property | 4 | §280A(d) limits: >14 days or >10% of rental days | Calendar of rental days, personal use days, vacancy days |
| Depreciation on land | 5 | Land is never depreciable | Property tax assessment showing land/building allocation, qualified appraisal |
| Cost segregation without engineering study | 3 | Must be based on actual asset analysis | Formal cost segregation study from qualified engineer/firm |

## Capital Gains Red Flags

| Red Flag | Risk Score | Trigger Threshold | Documentation Shield |
|----------|-----------|-------------------|---------------------|
| 1099-B with $0 or unreported cost basis | 4 | IRS sees full proceeds as gain | Basis documentation from original purchase, W-2 reconciliation for RSUs |
| Wash sale violations across accounts | 3 | 30-day window spans all accounts including IRAs | Cross-account transaction log, 31-day waiting evidence |
| Large LTCG in every year (>$500K) | 2 | Not inherently suspicious but increases DIF score | Complete transaction records with holding period evidence |
| Cryptocurrency gains without Form 8949 detail | 4 | IRS blockchain analytics (Chainalysis, CipherTrace) | Exchange records, wallet transaction history, cost basis tracking (CoinTracker, Koinly) |
| §1031 exchange with boot not recognized | 4 | Any cash or non-like-kind property received = taxable boot | Exchange agreement, qualified intermediary records, settlement statements |
| Day trading reported as LTCG | 5 | Holding period clearly less than 1 year | Brokerage statements showing trade dates |
| Installment sale without interest income | 3 | §483/§1274 imputed interest rules | Promissory note with AFR-compliant interest rate |
| Claiming §1202 QSBS exclusion | 3 | High-value exclusion attracts scrutiny | C-Corp incorporation documents, gross assets certification, qualified trade or business evidence, 5-year holding proof |
| Virtual currency staking rewards unreported or misreported | 4 | Staking rewards taxable per Rev. Rul. 2023-14 when taxpayer has dominion and control; distinct from trading gains | Exchange staking reports, wallet transaction history, FMV at receipt, consistent reporting method documentation |

## Entity and Business Structure Red Flags

| Red Flag | Risk Score | Trigger Threshold | Documentation Shield |
|----------|-----------|-------------------|---------------------|
| S-Corp officer with $0 or below-market salary | 5 | IRS actively audits for reasonable compensation | Compensation study, industry benchmarks, time analysis, corporate minutes documenting salary |
| S-Corp distributions >> salary | 4 | Ratio > 3:1 distributions-to-salary is aggressive | Reasonable compensation analysis, prior W-2 history, industry data |
| Single-member LLC reporting large losses | 3 | Disregarded entity losses flow to Schedule C | Business substance documentation, separate bank account, business purpose |
| Related party transactions | 4 | §267 loss disallowance, §482 arm's length standard | Written agreements at fair market value, independent valuation, third-party comparable terms |
| Multiple LLCs with losses offsetting W-2 income | 4 | Passive activity loss stacking | Material participation logs for each entity, time records by activity |
| Partnership with special allocations | 3 | §704(b) substantial economic effect test | Partnership agreement with liquidation provisions, capital account maintenance |

## Charitable Contribution Red Flags

| Red Flag | Risk Score | Trigger Threshold | Documentation Shield |
|----------|-----------|-------------------|---------------------|
| Cash donations > 5% of AGI | 3 | Well above national average (~3%) | Bank statements, canceled checks, written acknowledgment from charity |
| Large alimony deductions (pre-2019 divorce) | 3 | IRS cross-references recipient's reporting; pre-2019 divorce agreements only | Divorce decree/separation agreement dated before 1/1/2019, proof of payments, recipient's SSN on return, confirmation amounts match recipient's reporting |
| Non-cash donations > $5,000 without qualified appraisal | 5 | Required by law — failure = automatic disallowance | Qualified appraisal by qualified appraiser, Form 8283 Section B |
| Non-cash donations > $500 without Form 8283 | 4 | Required — IRS matches 8283 to return | Form 8283 Section A with all fields completed |
| Conservation easement (syndicated) | 5 | IRS listed transaction (Notice 2017-10) | Independent appraisal (not promoter-provided), economic substance analysis |
| Vehicle/boat donation > $500 | 2 | Substantiation requirements apply | Form 1098-C from charity, written acknowledgment with sale price |
| Clothing and household goods "round number" | 3 | $5,000 of clothes to Goodwill without detail | Itemized list with condition and thrift-store pricing, photographs |
| Charitable deduction = exact % of AGI limit | 2 | Suggests backward calculation | Independent documentation showing actual donations |

## Foreign Account and International Red Flags

| Red Flag | Risk Score | Trigger Threshold | Documentation Shield |
|----------|-----------|-------------------|---------------------|
| Missing FBAR (accounts > $10,000 aggregate) | 5 | Severe penalties, criminal exposure | File immediately via BSA E-Filing, reasonable cause statement |
| Missing Form 8938 (above thresholds) | 4 | $10K penalty + 40% accuracy penalty | File with return, gather all foreign account statements |
| Foreign income without Form 2555 or FTC | 4 | IRS sees foreign income on W-2/1099 but no credit/exclusion | Form 2555 (FEIE) or Form 1116 (FTC) with supporting documentation |
| CFC without Form 5471 | 5 | $10,000 per form per year penalty | Complete Form 5471 with all required schedules and financial statements |
| Foreign trust distributions without Form 3520 | 5 | 35% penalty on distribution amount | Form 3520 filed timely with trust accountings |
| PFIC holdings without Form 8621 | 4 | Punitive excess distribution tax applies by default | QEF or mark-to-market election, Form 8621 for each PFIC |

## Income Reporting Red Flags

| Red Flag | Risk Score | Trigger Threshold | Documentation Shield |
|----------|-----------|-------------------|---------------------|
| Missing 1099-NEC/1099-K income | 5 | IRS automated matching (CP2000) | Report all 1099 income; if 1099 is wrong, report and adjust on return |
| Premium Tax Credit reconciliation discrepancy (Form 8962) | 3 | Over/under-estimation of income for ACA marketplace enrollees; large discrepancies between estimated and actual income trigger scrutiny and can result in significant balance due or refund | Form 1095-A, income documentation, Form 8962 reconciliation showing APTC vs. actual PTC, evidence of income change if applicable |
| Cryptocurrency "Yes" checkbox with no Form 8949 | 4 | Inconsistent answers = perjury risk | Complete crypto transaction history, cost basis records |
| Digital assets question answered "No" when "Yes" | 5 | Perjury trap — checkbox is signed under penalties | Answer truthfully; digital assets include crypto, NFTs, stablecoins |
| Large cash deposits not matching reported income | 4 | Bank deposit analysis method | Document non-income deposits: transfers, loans, gifts, reimbursements |
| Tips/cash income significantly below industry norms | 3 | IRS has industry-specific benchmarks | Tip log, POS records, customer count documentation |
| Barter income not reported | 3 | §61(a)(3) — FMV of goods/services received | Track all barter transactions at FMV when received |

## DIF Score Trigger Summary

### High-DIF-Score Combinations (Worst Case)
These combinations of factors virtually guarantee elevated DIF scores:

1. **Schedule C loss + Home office + Vehicle 100% business** = Score 5
   - The "audit trifecta" — multiple aggressive positions stacked on the same return.
2. **High W-2 income + Large Schedule C loss** = Score 4
   - Tax shelter suspicion — "hobby" masking W-2 income.
3. **Large charitable deductions + Round numbers throughout** = Score 4
   - Estimated, not substantiated.
4. **Cash business + Low gross receipts + High lifestyle indicators** = Score 5
   - Unreported income suspicion (IRS uses indirect methods: net worth, bank deposits).
5. **Multiple rental losses + No REP status + >$150K AGI** = Score 3
   - Passive activity loss rules likely violated.

---

## Aggressive Position Classification

### Conservative (95%+ Chance of Success)
Positions supported by clear statutory language, regulations, and/or case law directly on point:
- Standard deduction vs. itemized deduction choice
- §199A QBI deduction for non-SSTB below income threshold
- §121 home sale exclusion with clear 2-of-5-year ownership and use
- LTCG treatment for assets held >1 year with clear documentation
- Contribution to traditional 401(k) within limits

### Moderate (70-95% Chance of Success)
Positions supported by reasonable interpretation of law but with some ambiguity:
- Real Estate Professional status with documented 750+ hours (may be challenged on facts)
- §1202 QSBS exclusion (complex requirements, all must be met and documented)
- S-Corp reasonable compensation at a specific amount (no bright-line rule)
- Cost segregation study accelerating depreciation on rental property
- Home office deduction with clear exclusive-use documentation
- §199A QBI deduction at or near income thresholds ($191,950 Single / $383,900 MFJ for 2025) — IRS scrutinizes SSTB classification and taxable income manipulation near these thresholds; document business classification and income computations thoroughly

### Aggressive (40-70% Chance of Success)
Positions with some legal support but subject to significant IRS challenge:
- Personal goodwill allocation in C-Corp asset sale (documented but fact-intensive)
- QSBS stacking through multiple trusts (IRS has signaled scrutiny)
- §199A for activities near the SSTB boundary (e.g., consulting with engineering aspects)
- Claiming material participation through management activities alone (no hands-on work)
- Travel deductions for trips mixing significant business and personal purposes

### Reckless (<40% Chance of Success) — DO NOT RECOMMEND
Positions with little or no legal support, likely to result in penalties:
- Conservation easement deductions from syndicated deals (IRS listed transaction)
- Micro-captive insurance arrangements (IRS listed transaction, Notice 2016-66)
- Claiming home office for W-2 employees (not deductible post-TCJA, no exceptions)
- §1031 exchanges of cryptocurrency (not real property after TCJA)
- Deducting personal expenses by routing through a business entity without substance

---

## Round Number Warning System

During return preparation, flag any line item that is a "suspiciously round" number:

| Flag Level | Examples | Action |
|------------|---------|--------|
| No flag | $4,327 / $12,891 / $847 | Specific numbers suggest actual records |
| Minor flag | $4,500 / $12,500 / $850 | May be legitimate but verify source documentation |
| Major flag | $5,000 / $10,000 / $1,000 | Strongly suggests estimation; verify or adjust to actual |
| Critical flag | $25,000 / $50,000 / $100,000 | Almost certainly estimated; IRS examiner will challenge |

**Best practice**: If the actual amount happens to be a round number, attach a note: "Amount
verified per bank statement dated [date]." Having the documentation ready prevents the presumption
of estimation.

---

## Year-Over-Year Consistency Flags

DIF scoring compares the current return to prior years. Flag changes exceeding:

| Line Item | Change Threshold | Action Required |
|-----------|-----------------|-----------------|
| Gross receipts (Sch C) | >25% decrease or >50% increase | Document reason (new client, lost client, market change) |
| Business expenses (total) | >20% increase | Verify no personal expenses included; document new expenses |
| Charitable contributions | >100% increase | Verify documentation for all donations; attach explanation |
| Depreciation | >30% change | Reconcile with asset additions/dispositions |
| Rental income/loss | New loss where prior year showed income | Document vacancies, repairs, market changes |
| State/local tax deduction | >$2,000 change | Reconcile with actual tax payments |

---

## Worker Classification Red Flags

### IRS Targets for 1099 vs. W-2 Misclassification

| Factor | Points Toward Employee (W-2) | Points Toward Contractor (1099) |
|--------|------------------------------|--------------------------------|
| Behavioral control | Company dictates how, when, where work is done | Worker controls methods and schedule |
| Financial control | Company provides tools, bears expenses | Worker invests in own tools, bears risk of loss |
| Relationship | Ongoing, indefinite; benefits provided | Project-based; no benefits |
| Exclusivity | Works only for this company | Works for multiple clients |
| Training | Company trains the worker | Worker has independent expertise |

**Risk score**: 4-5 if the business has 1099 workers who look like employees (full-time, on-site,
company equipment, single client).

**Documentation shield**: Written independent contractor agreement, evidence of multiple clients,
invoices (not timesheets), own equipment, LLC/business entity for the worker.

---

## State Nexus Triggers

| Trigger | Risk Score | States Most Aggressive |
|---------|-----------|----------------------|
| Remote employee working from another state | 3 | NY (convenience rule), CA, NJ, CT, PA |
| Economic nexus from online sales (>$100K/200 txn) | 3 | All states with sales tax (post-Wayfair) |
| Affiliate nexus (marketing affiliates in state) | 2 | NY, CA, IL |
| Employee performing services in multiple states | 3 | All — duty-day allocation required |
| Rental property in another state | 2 | Filing required in property's state |
| K-1 income from multi-state partnership | 2 | Each state where partnership operates |

---

## Multi-Model Validation Protocol

### When to Cross-Validate with Other AI Models
Not every position requires multi-model validation. Use this protocol for:

1. **Any position classified as "aggressive" (40-70% chance of success)**
2. **QSBS exclusion claims over $5M**
3. **Personal goodwill allocations over $1M**
4. **Real Estate Professional status with borderline hours (750-850 documented)**
5. **§199A QBI deductions near the SSTB income phase-out boundary**
6. **International tax positions involving CFC/PFIC/treaty benefits**
7. **Charitable deductions for complex property (conservation easements, art, IP)**
8. **Any position where the taxpayer's aggressive preference conflicts with conservative guidance**

### Validation Process
1. **State the position clearly**: Include IRC section, facts, dollar amounts, and legal authority.
2. **Query multiple models**: Ask each model (GPT, Gemini, Claude) to independently assess:
   - Is this position supportable?
   - What is the risk of successful IRS challenge?
   - What documentation would strengthen the position?
   - Are there any recent cases or rulings that affect this analysis?
3. **Compare results**: If all models agree the position is supportable → proceed with documentation.
   If models disagree → research the specific area of disagreement and err on the conservative side.
4. **Document the validation**: Note that the position was cross-validated, the result, and the
   final decision. This documentation itself supports "reasonable cause and good faith" if the
   position is later challenged. Reg. §1.6662-4(d).

### Positions That Must NEVER Be Cross-Validated (Always Decline)
- Conservation easement syndicated deals (listed transaction)
- Micro-captive insurance (listed transaction)
- Any position the taxpayer cannot independently substantiate with documentation
- "Disappearing income" structures designed solely to eliminate tax
- Positions that depend on non-disclosure to the IRS for effectiveness

---

## Pre-Filing Checklist Summary

Before filing any return, verify:

- [ ] All 1099s and W-2s reconcile to reported income
- [ ] No missing income (check IRS transcript if available via Form 4506-T or IRS Online Account)
- [ ] Digital assets question answered correctly
- [ ] No round numbers without supporting documentation
- [ ] Year-over-year changes are documented and explainable
- [ ] All aggressive positions are documented with legal authority
- [ ] FBAR filed (or confirmed not required) for any foreign accounts
- [ ] Form 8938 filed (or confirmed not required)
- [ ] S-Corp reasonable compensation is defensible
- [ ] Home office meets exclusive use test with photos and measurements
- [ ] Vehicle business use is supported by contemporaneous mileage log
- [ ] Charitable donations have required acknowledgments (before filing)
- [ ] All required 1099s have been issued to contractors
- [ ] Estimated tax payments are current (or safe harbor met)
- [ ] State filing obligations identified for all applicable states
- [ ] Multi-model validation completed for any aggressive positions
