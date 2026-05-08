# Audit Defense Playbook

Comprehensive guide to IRS audit prevention, response, and resolution. Generic reference for any US taxpayer.

---

## DIF Score Factors and Audit Selection

### How Returns Are Selected for Audit

The IRS uses the **Discriminant Information Function (DIF)** system, a machine learning model that scores every return for audit potential. Higher DIF scores indicate greater likelihood of yielding additional tax upon examination.

**Key DIF Score Factors:**

| Factor | Why It Triggers | Risk Level |
|--------|-----------------|------------|
| Schedule C loss (especially 3+ years) | Hobby loss suspicion; unreported income | High |
| High deductions relative to income | Deduction-to-income ratios outside norms | High |
| Cash-intensive business | IRS assumes underreported income | High |
| Large Schedule C with no employees | Typical audit target for misclassification | Medium-High |
| Home office deduction | Historically abused; exclusive use requirement | Medium |
| Large charitable deductions (>3% AGI) | Overvaluation of non-cash donations | Medium |
| Rental losses with high W-2 income | Passive activity rule compliance | Medium |
| Round numbers throughout return | Suggests estimation rather than records | Medium |
| Significant 1099-B activity | Complex basis calculations; wash sales | Medium |
| Large unreimbursed employee expenses | Eliminated by TCJA but still filed erroneously | Medium |
| Earned Income Tax Credit | High error rate historically | Medium |
| Foreign income / accounts | FBAR/FATCA compliance | High |
| Cryptocurrency transactions | Rapidly increasing IRS focus | Medium-High |
| Employee Retention Credit (ERC) | IRS moratorium; aggressive promoter claims (see note below) | Very High |

**ERC Moratorium Note:** The IRS moratorium on processing new Employee Retention Credit claims is evolving and requires **live verification** before advising any client. As of early 2025, the IRS has been processing some legitimate claims while maintaining heightened scrutiny on others, particularly those filed through aggressive promoters. The moratorium status, processing timelines, and withdrawal/voluntary disclosure programs change frequently. Always check the current IRS ERC page (IRS.gov/erc) for the latest status before providing guidance on filing, amending, or withdrawing ERC claims.

### Audit Rates by Income Level (Recent IRS Data)

| Income Level | Approximate Audit Rate | Notes |
|-------------|----------------------|-------|
| Under $25,000 | 0.4% - 1.0% | Mainly EITC correspondence audits |
| $25,000 - $100,000 | 0.2% - 0.4% | Lowest audit rates |
| $100,000 - $200,000 | 0.2% - 0.5% | Slightly above average |
| $200,000 - $500,000 | 0.4% - 0.8% | Increasing scrutiny |
| $500,000 - $1,000,000 | 0.6% - 1.2% | Noticeably higher |
| $1,000,000 - $5,000,000 | 1.0% - 2.5% | IRS focus area with new funding |
| $5,000,000 - $10,000,000 | 2.0% - 4.0% | High-wealth compliance initiative |
| Over $10,000,000 | 3.0% - 8.0%+ | Highest audit rates |
| Schedule C (no COGS) > $100K | 1.0% - 2.0% | Self-employment scrutiny |
| Schedule C with loss | 1.5% - 3.0% | Hobby loss / unreported income |
| Partnership/S-Corp returns | 0.2% - 0.5% | But increasing with new IRS funding |

Note: IRS audit rates have increased significantly since the Inflation Reduction Act (2022) provided additional enforcement funding, particularly targeting high-income individuals ($400K+).

### IRS Large Business & International (LB&I) Compliance Campaigns

Beyond traditional DIF scoring, many high-income audits are now driven by **LB&I compliance campaigns** -- issue-focused enforcement initiatives targeting specific areas of non-compliance. These campaigns identify systemic risks across taxpayer populations and direct examination resources accordingly.

**Active campaign areas include (non-exhaustive):**
- Virtual currency / digital assets
- Micro-captive insurance arrangements (Section 831(b))
- Syndicated conservation easements
- Transfer pricing (Section 482)
- Earned Income Tax Credit (EITC) compliance
- Partnership issues (including basis shifting and liability allocations)
- International tax compliance (GILTI, Subpart F, treaty positions)

The IRS publishes the list of active LB&I campaigns on its website (IRS.gov > News > Compliance Campaigns). **High-income taxpayers and their advisors should review the active campaign list and assess whether any positions taken on the return overlap with a current campaign.** Overlap does not guarantee an audit, but it significantly increases the probability of examination and signals that the IRS has developed specialized expertise and training for that specific issue.

---

## Common Audit Risk Patterns

### Pattern 1: Home Office "Zeroing"
**What it looks like:** Net Schedule C income is reduced to exactly zero (or a small amount) by the home office deduction.
**Why it flags:** Suggests working backward from a target rather than calculating actual expenses.
**Defense:** Maintain independent calculation showing square footage, actual expenses, and the fact that the result happens to approach zero.

### Pattern 2: Identical Percentages Year-Over-Year
**What it looks like:** Business use of home is exactly 25.00% for 5 consecutive years. Vehicle business use is exactly 75.00% every year.
**Defense:** Actual measurements may legitimately produce similar results. Document the measurement each year independently with dated notes, floor plans, and mileage logs.

### Pattern 3: Round Numbers
**What it looks like:** Office supplies: $500. Travel: $3,000. Meals: $2,000.
**Why it flags:** Real expenses are rarely exactly round numbers.
**Defense:** Always use actual figures. If expenses are estimated (Cohan rule), explain why records are unavailable and show a reasonable basis for the estimate.

### Pattern 4: High Meal and Entertainment
**What it looks like:** Meal expenses exceeding 10-15% of gross revenue.
**Defense:** Each meal must have: date, location, amount, business purpose, who attended, business relationship. No business purpose = no deduction.

### Pattern 5: Schedule C Losses in Hobby Activities
**What it looks like:** Photography, horse breeding, farming, art, writing -- activities that look like hobbies reporting losses year after year.
**Defense:** IRC Section 183 nine-factor test. Document profit motive: business plan, time invested, expert consultation, changes to improve profitability. Safe harbor: profit in 3 of 5 consecutive years (2 of 7 for horse activities).

### Pattern 6: Cash Business with Low Gross Receipts
**What it looks like:** Cash-intensive business (restaurant, retail, personal services) with deposits that don't match reported revenue.
**Defense:** Maintain meticulous records. Reconcile bank deposits to reported income. Document non-income deposits (loans, transfers, gifts). The IRS uses bank deposit analysis as its primary method for cash businesses.

### Pattern 7: Large Non-Cash Charitable Donations
**What it looks like:** $25,000 of clothing donated to Goodwill; $50,000 of art donated to a museum.
**Defense:** Non-cash donations > $500 require Form 8283. Donations > $5,000 require a qualified appraisal by a qualified appraiser. Clothing and household items must be in "good or better" condition.

### Pattern 8: Crypto Reporting Gaps
**What it looks like:** Taxpayer checks "Yes" on the digital asset question but reports no transactions; or exchange-reported 1099-B amounts don't match Schedule D.
**Defense:** Complete transaction history from all exchanges and wallets. Consistent cost basis methodology. Report every taxable event including swaps, DeFi transactions, and staking rewards.

---

## Types of IRS Contact

### 1. Correspondence Audit (Mail Audit)

**What:** IRS sends a letter (CP2000, CP2501, or Letter 566/525) requesting documentation for specific items.
**Volume:** ~75-80% of all audits
**Common Issues:** Missing 1099 income, math errors, EITC verification, charitable deduction substantiation
**Response Timeline:** Usually 30-60 days from notice date

**Strategy:**
- Respond by the deadline (request extension if needed -- call the number on the notice)
- Address ONLY the specific items requested -- do not volunteer additional information
- Send copies of supporting documents, never originals
- Send via certified mail, return receipt requested
- Keep a complete copy of everything sent
- If you agree with the adjustment, sign and return the form with payment
- If you disagree, respond with documentation and a written explanation

### 2. Office Audit (In-Person at IRS Office)

**What:** Taxpayer (or representative) meets with an IRS examiner at a local IRS office.
**Volume:** ~10-15% of audits
**Common Issues:** Home office, business expenses, rental property, employee vs. contractor
**Scope:** Usually limited to specific issues listed in the appointment letter

**Strategy:**
- Bring ONLY documents related to the issues listed -- nothing extra
- Organize documents by issue with a clear index
- Representative (CPA, EA, attorney) can attend instead of taxpayer (Form 2848 Power of Attorney)
- Taxpayer should generally NOT attend if represented -- the examiner may ask leading questions
- Be polite, factual, and concise -- do not volunteer information
- If asked about issues not in the appointment letter, state "That issue was not included in the examination scope"

### 3. Field Audit (IRS Comes to You)

**What:** Revenue agent visits the taxpayer's business or home.
**Volume:** ~5-10% of audits; typically for businesses and high-income taxpayers
**Common Issues:** Large businesses, complex returns, high-income individuals
**Scope:** Can be broad; agent may expand scope if issues are found

**Strategy:**
- NEVER allow the audit at home unless the home office is at issue (then it may be unavoidable)
- Request the audit be conducted at the representative's office
- Have an attorney or CPA present
- Control the environment -- do not leave files, computers, or records accessible
- Prepare a "day one" package: organized documents for each issue
- Brief all employees who may interact with the agent
- Know your rights: you can record the interview (with notice in most jurisdictions)

---

## Response Strategy by Issue Type

### Home Office (Form 8829)

**IRS Focus Areas:**
- Exclusive and regular use (no dual-purpose rooms)
- Principal place of business test (or meeting clients test)
- Percentage calculation accuracy
- Gross income limitation compliance

**Documentation to Prepare:**
- Floor plan with measurements (to scale, dated)
- Photographs of the office space showing exclusive business use
- Description of how the space is used (no personal items visible)
- Calculation worksheet showing square footage method
- Prior year consistency (if percentage changed, explain why)
- Utility bills, rent/mortgage statements for expense verification

**Key Legal Authority:**
- IRC Section 280A
- *Soliman v. Commissioner* (1993) -- principal place of business
- *Hamacher v. Commissioner* -- exclusive use requirement

### Schedule C Business Expenses

**IRS Focus Areas:**
- Reasonableness and business purpose of each expense
- Substantiation of travel, meals, entertainment
- Personal vs. business allocation
- Income completeness (bank deposit analysis)

**Documentation to Prepare:**
- Complete P&L with supporting receipts organized by category
- Bank statements reconciled to reported income
- Mileage log (if applicable)
- For each questioned expense: receipt, business purpose, relationship to business

**Key Legal Authority:**
- IRC Section 162 (ordinary and necessary business expenses)
- IRC Section 274 (substantiation requirements for travel, meals)
- *Cohan v. Commissioner* (1930) -- reasonable estimate when records lost (but NOT for travel/entertainment)

### Capital Gains and Basis

**IRS Focus Areas:**
- Cost basis accuracy (especially for inherited, gifted, or ESPP/ISO stock)
- Holding period classification (LTCG vs. STCG)
- Wash sale rule compliance
- Installment sale calculations
- 1031 exchange compliance

**Documentation to Prepare:**
- Purchase confirmations with dates and prices
- Brokerage 1099-B with supplemental schedules
- Basis step-up documentation for inherited assets (FMV at date of death)
- For 1031: exchange agreement, identification letter, closing documents
- Wash sale adjustment spreadsheet showing all accounts

**Key Legal Authority:**
- IRC Section 1001 (realization and recognition)
- IRC Section 1012 (basis)
- IRC Section 1014 (basis of inherited property)
- IRC Section 1031 (like-kind exchanges)
- IRC Section 1091 (wash sales)

### Rental Property (Schedule E)

**IRS Focus Areas:**
- Personal use days vs. rental days (Section 280A)
- Passive activity loss limitations
- Real estate professional status qualification
- Depreciation accuracy (correct life, method, convention)
- Repair vs. capitalization (improvement)

**Documentation to Prepare:**
- Rental agreements / lease documents
- Rent receipts or bank deposit records
- Calendar showing rental days, personal use days, and vacant days
- Expense receipts organized by property
- Depreciation schedules with placed-in-service dates
- Time log if claiming REP status (750 hours + material participation)
- For each repair: description, invoice, and explanation of why it is not a capital improvement

**Key Legal Authority:**
- IRC Section 469 (passive activity rules)
- IRC Section 280A (personal use limitations)
- Treasury Reg. 1.263(a)-3 (repair vs. improvement regulations)
- *Toups v. Commissioner* -- REP hour documentation

### Employee vs. Independent Contractor

**IRS Focus Areas:**
- Behavioral control (who controls how work is done)
- Financial control (unreimbursed expenses, investment, profit/loss opportunity)
- Relationship type (permanency, benefits, written contracts)

**Documentation to Prepare:**
- Written contract specifying independent contractor relationship
- Evidence of contractor's control over methods and schedule
- Evidence contractor serves multiple clients
- Invoice/payment records (not timesheets)
- Evidence contractor provides own tools/equipment
- 1099-NEC filing records

**Key Legal Authority:**
- IRC Section 530 (safe harbor for worker classification)
- Revenue Ruling 87-41 (20-factor test, now simplified to 3 categories)
- IRS Form SS-8 determination

---

## Penalty Mitigation

### IRC Section 6662 -- Accuracy-Related Penalty (20%)

**Applies When:**
- Negligence or disregard of rules
- Substantial understatement of income tax (>$5,000 or >10% of correct tax)
- Substantial valuation misstatement
- Transaction lacking economic substance

**Defenses:**

| Defense | Standard | How to Prove |
|---------|----------|-------------|
| **Reasonable cause and good faith** | Taxpayer exercised ordinary care and prudence | Reliance on professional advice, complexity of issue, taxpayer's knowledge and experience |
| **Substantial authority** | ~40% likelihood of prevailing | Cite IRC, regulations, rulings, court cases supporting position |
| **Adequate disclosure** | Form 8275/8275-R | Disclosed the position; reduces standard to reasonable basis (20%) |
| **Reliance on professional** | Reasonable reliance on qualified tax advisor | Must provide full and accurate information to advisor; advisor must be competent |

### First-Time Penalty Abatement (FTA)

**Eligibility:**
1. No penalties for the 3 prior tax years (same penalty type)
2. All required returns filed (or valid extensions)
3. All tax due has been paid (or is in an installment agreement)

**How to Request:**
- Call IRS at number on notice and request FTA verbally
- Or write a letter citing IRM 20.1.1.3.2
- Can be requested on Form 843 (Claim for Refund)
- **Important:** FTA only abates the penalty, not interest
- **Strategy tip:** If eligible for both reasonable cause and FTA, use FTA first (it is easier and preserves reasonable cause for future use)

### Estimated Tax Penalty (Section 6654)

**Exceptions (No Penalty If):**
- Total tax due is less than $1,000
- Withholding + estimated payments are at least 90% of current year tax
- Withholding + estimated payments are at least 100% of prior year tax (110% if AGI > $150K)
- Annualized income installment method shows no underpayment for each quarter
- Tax withheld from W-2 (treated as paid evenly throughout the year)

**Waiver:**
- Casualty, disaster, or unusual circumstances
- Recently retired (age 62+) or became disabled during the year
- Request waiver using Form 2210

---

## Statute of Limitations

### Federal

| Situation | Period | Authority |
|-----------|--------|-----------|
| Normal assessment period | 3 years from filing (or due date, whichever is later) | IRC 6501(a) |
| Omission of >25% of gross income | 6 years | IRC 6501(e) |
| Fraud or willful evasion | **No limit** | IRC 6501(c)(1) |
| Failure to file | **No limit** | IRC 6501(c)(3) |
| Return filed early | 3 years from due date (not early filing date) | IRC 6501(b) |
| Amended return filed | Does not restart the clock (with exceptions) | |
| Claim for refund | 3 years from filing or 2 years from payment, whichever is later | IRC 6511 |
| FBAR penalty | 6 years from due date | 31 USC 5321 |
| Omission of foreign financial assets >$5,000 | 6 years | IRC 6501(e)(1)(A)(ii) |
| State returns | Varies: typically 3-4 years (CA: 4 years; NY: 3 years) | State law |

**Critical Rules:**
- Filing an extension does NOT extend the statute -- it runs from the actual filing date (or original due date if filed before)
- The IRS can request consent to extend the statute (Form 872) -- taxpayers can refuse, but this often triggers immediate assessment
- Keep records for at least 7 years (covers the 6-year substantial omission period + 1 year buffer)
- Keep records of property basis indefinitely (until property is disposed of + 3 years)
- Keep copies of all filed returns indefinitely

**6-Year Statute for Foreign Financial Assets:** Under Section 6501(e)(1)(A)(ii), the statute of limitations extends to **6 years** when the taxpayer omits from gross income an amount of foreign financial assets that exceeds **$5,000**. This is distinct from the FBAR penalty statute (31 USC 5321), which has its own 6-year window running from the date of the BSA violation. Both statutes can run in parallel -- a taxpayer with unreported foreign financial asset income may face a 6-year assessment window for the income tax AND a 6-year FBAR penalty window, potentially with different start dates.

### State Statutes

| State | Normal Period | Notes |
|-------|--------------|-------|
| California | 4 years from filing | Extended to 8 years for >25% omission |
| New York | 3 years from filing | Extended to 6 years for >25% omission |
| Texas | No income tax | Franchise tax: 4 years |
| Florida | No income tax | 3 years for sales/use tax |
| Most other states | 3-4 years | Often tied to federal statute |

---

## Emergency Response Checklist

When an IRS notice or audit letter arrives, follow these steps immediately:

### Day 1: Triage
- [ ] Read the entire notice carefully
- [ ] Identify the notice type (CP number or Letter number)
- [ ] Note the response deadline (typically 30-60 days from notice date)
- [ ] Determine the issue(s) under examination
- [ ] Determine the proposed adjustment amount (tax, penalty, interest)
- [ ] DO NOT PANIC -- most notices are routine and resolvable
- [ ] DO NOT IGNORE -- ignoring makes everything worse

### Day 2-3: Assessment
- [ ] Pull the return for the year in question
- [ ] Review the specific items at issue
- [ ] Gather supporting documentation
- [ ] Assess whether the IRS position is correct, partially correct, or incorrect
- [ ] Determine if professional representation is needed (CPA, EA, attorney)
- [ ] If representation needed, engage professional immediately (deadline pressure)

### Day 4-14: Preparation
- [ ] Organize documentation by issue
- [ ] Create a written response addressing each issue
- [ ] Include only requested documentation -- do not volunteer extra information
- [ ] If requesting additional time, call the phone number on the notice
- [ ] If the notice is correct, sign the agreement and pay (or set up installment plan)
- [ ] If disputing, prepare a clear, factual response with supporting documents

### Day 15-30: Response
- [ ] Send response via certified mail, return receipt requested (or use IRS online tools if available)
- [ ] Keep a complete copy of everything sent
- [ ] Note the date sent and expected IRS processing time (typically 4-8 weeks)
- [ ] Calendar a follow-up date if no response received
- [ ] If calling, note the date, time, agent name, and badge number

### Post-Response
- [ ] Monitor for IRS acknowledgment
- [ ] If the IRS agrees with your response, verify the account is adjusted
- [ ] If the IRS disagrees, evaluate whether to:
  - Accept the adjustment
  - Request an informal conference with the examiner's manager
  - File a protest to IRS Appeals (30-day letter)
  - Petition the US Tax Court (90-day letter)
- [ ] Address any penalties (First-Time Abatement or Reasonable Cause)
- [ ] Verify state tax implications of any federal adjustment

---

## Proactive Audit Prevention Strategies

### Documentation Discipline
1. **Maintain contemporaneous records.** The single most important audit defense is real-time documentation. Reconstructed records are inherently weaker.
2. **Separate business and personal accounts.** Commingling is the fastest way to lose deductions in an audit.
3. **Use accounting software.** QuickBooks, Xero, Wave, FreshBooks -- anything that creates a systematic record is better than a shoebox.
4. **Photograph receipts.** Paper fades; digital records do not.
5. **Mileage apps.** MileIQ, Stride, Everlance -- automatic tracking is more credible than a handwritten log.

### Return Preparation Practices
1. **Avoid round numbers.** $2,347 is more credible than $2,500.
2. **Avoid zeroing out Schedule C.** If the home office deduction coincidentally makes Schedule C net income exactly zero, document the calculation clearly.
3. **Be consistent year-over-year.** Dramatic swings in deduction amounts trigger DIF scoring.
4. **Report all income.** The IRS matches 1099s and W-2s. If a 1099 is wrong, report the income and back it out with an explanation -- do not simply omit it.
5. **Attach explanations.** For unusual items, attach a statement. Examiners reviewing returns appreciate clarity.
6. **File electronically.** E-filed returns have lower error rates and are processed faster.

### Entity and Structure Practices
1. **Maintain corporate formalities.** If operating as an S-Corp or LLC, keep minutes, maintain separate accounts, and document transactions.
2. **Reasonable compensation.** S-Corp officer compensation should be defensible with industry data.
3. **Document related-party transactions.** Any transaction between you and an entity you control needs a written agreement at arm's-length terms.

### Specific High-Risk Area Prevention

#### Home Office
- Take dated photographs of the office space annually
- Keep a floor plan with measurements on file
- Maintain the space as exclusively business (no personal items, no guest bed)
- If audited, the IRS may visit -- the space must actually look like an office

#### Vehicle
- Use a mileage tracking app from January 1
- Record total miles for the year (odometer on Jan 1 and Dec 31)
- Keep a log of each business trip (date, destination, purpose, miles)
- If claiming actual expenses, keep every receipt (gas, maintenance, insurance, registration)

#### Charitable Donations
- Get written acknowledgment for donations > $250 BEFORE filing the return
- For non-cash donations > $500, file Form 8283
- For non-cash donations > $5,000, get a qualified appraisal
- Photograph donated items before donating
- Be realistic about used item valuations (IRS has thrift-store pricing guidelines)

#### Business Meals
- Note on every receipt: who was present, what was discussed, business relationship
- Tip: write the business purpose on the back of the receipt immediately
- Keep calendar entries that corroborate the meeting

#### Cash Businesses
- Use a POS system that generates records
- Deposit all cash (do not use cash receipts for expenses)
- Reconcile bank deposits to revenue monthly
- Keep Z-tapes or daily sales summaries

### When to Proactively Engage a Tax Attorney
- Criminal investigation (CI) contact -- immediately retain counsel (5th Amendment protections)
- Assessment of fraud penalty -- counsel needed before any communication
- Very large proposed adjustments (>$100K)
- Offshore account or foreign compliance issues
- Appeals and Tax Court proceedings
- Trust fund recovery penalty (personal liability for payroll taxes)
- When CPA/EA privilege is insufficient (communications with attorneys are more broadly protected)

---

## Appeals and Litigation Path

If you disagree with the IRS examination result:

```
Examination Result
  |
  v
30-Day Letter (proposed adjustments)
  |
  ├── Agree? -> Sign and pay (or installment agreement)
  |
  ├── Disagree? -> File written protest to IRS Appeals
  |                 |
  |                 v
  |              IRS Appeals (independent review)
  |                 |
  |                 ├── Settlement reached? -> Closing agreement
  |                 |
  |                 └── No agreement? -> 90-Day Letter (Statutory Notice of Deficiency)
  |
  └── No response? -> 90-Day Letter issued
                       |
                       v
                    90-Day Letter (DO NOT IGNORE)
                       |
                       ├── File Tax Court petition within 90 days
                       |     |
                       |     ├── Tax Court (no prepayment required)
                       |     |     |
                       |     |     ├── Small case (<$50,000): simplified, no appeal
                       |     |     └── Regular case: formal trial, appealable
                       |     |
                       |     └── Settlement during Tax Court (most cases settle)
                       |
                       ├── Pay tax and file refund claim
                       |     |
                       |     ├── US District Court (jury trial available)
                       |     └── US Court of Federal Claims
                       |
                       └── No action within 90 days?
                             -> Assessment becomes final and legally collectible
                             -> IRS can levy wages, bank accounts, property
```

**Key Timing:**
- 30-Day Letter: 30 days to respond with protest to Appeals
- 90-Day Letter: Exactly 90 days to file Tax Court petition (150 days if addressed to taxpayer outside the US)
- **Missing the 90-day window is nearly always irrecoverable** -- the assessment becomes final

### Appeals Advantages
- Independent from the examination division
- Hazards-of-litigation analysis (considers what would happen in court)
- Can negotiate settlements based on facts, law, and hazards
- No cost to the taxpayer (no court filing fees)
- Typically resolves within 6-12 months
- Most disputes settle at the Appeals level

### Tax Court Advantages
- No prepayment required (unlike District Court or Court of Federal Claims)
- Judges are tax specialists
- Extensive body of precedent
- Small-case procedure for amounts under $50,000 (simple, informal, no attorney required -- but no appeal)
- Most cases settle before trial
