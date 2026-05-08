# Starting a Business Tax Reference (Tax Year 2025)

## Overview

Starting a business triggers numerous tax obligations and planning opportunities. Key decisions made in the first year -- entity type, accounting method, retirement plan selection, and expense elections -- have long-lasting tax consequences. Understanding startup cost treatment, estimated payment requirements, and record-keeping obligations from day one prevents costly mistakes.

## Entity Selection Decision Tree

### Primary Decision Factors
1. **Expected net income level**: S-Corp SE tax savings meaningful above ~$50K-$60K net
2. **Liability protection needs**: LLC/Corp vs. sole proprietorship
3. **Number of owners**: single-member LLC vs. partnership vs. multi-member LLC
4. **Exit plan**: plan to sell the business? C-Corp + QSBS exclusion may save millions
5. **Investor compatibility**: VCs require C-Corp (preferably DE-incorporated); SBA loans work with any structure
6. **State-specific costs**: CA $800 minimum tax, NY UBT, etc. affect the calculation

### Entity Comparison

| Entity | Tax Treatment | SE Tax | Liability | Complexity | Best For |
|--------|--------------|--------|-----------|------------|----------|
| Sole Proprietorship | Schedule C | Yes, on all net income | Unlimited | Lowest | Testing a business idea, very low income |
| Single-Member LLC | Default: Schedule C | Yes, on all net income | Limited | Low | Most startups before S-Corp threshold |
| Partnership / Multi-Member LLC | Form 1065; K-1 to partners | Yes, for general partners | Limited for LLC members | Moderate | Multiple founders |
| S-Corporation | Form 1120-S; K-1 to shareholders | Only on reasonable salary | Limited | Higher | Established businesses $60K+ net |
| C-Corporation | Form 1120; 21% flat | No SE (but payroll on salary) | Limited | Highest | VC-funded, QSBS strategy, high-retention |

### Decision Logic
```
Net income < $40K? → Sole proprietorship (or LLC for liability protection)
Net income $40K-$60K? → LLC, evaluate S-Corp annually
Net income > $60K, one owner? → LLC with S-Corp election
Multiple owners, no investors? → Multi-member LLC (taxed as partnership or S-Corp)
Seeking VC investment? → C-Corporation (Delaware)
Want QSBS exclusion on sale? → C-Corporation (must be C-Corp from issuance, §1202)
```

## State-by-State Formation Considerations

### Delaware Incorporation
- **Advantages**: highly developed business law (Court of Chancery), predictable legal outcomes, privacy (no public disclosure of officers/directors on annual report), flexible corporate statute
- **Disadvantages**: annual franchise tax ($300 min for LLCs, $400+ for Corps based on shares), must register as foreign entity in your home state (additional fees), need a registered agent in DE ($100-$300/year)
- **Best for**: C-Corps seeking investors, businesses planning to go public, businesses wanting the most developed body of corporate case law

### Wyoming / Nevada
- **Advantages**: no state income tax, no franchise tax, strong privacy protections (WY does not require disclosure of members/managers publicly), low filing fees
- **Disadvantages**: still must register and pay taxes in the state where you actually operate
- **Best for**: businesses operated from no-income-tax states that want formation in the same state; online businesses with no physical presence

### Home State Formation
- **Simplest approach**: form in the state where you physically operate
- Avoids double registration fees (home state + formation state)
- Avoids annual registered agent fees in a foreign state
- **Best for**: most small businesses, service businesses, local operations

### State Formation Cost Comparison (Approximate)
| State | LLC Filing Fee | Annual Fee/Tax | Corp Filing Fee | Annual Fee/Tax |
|-------|---------------|----------------|-----------------|----------------|
| Delaware | $90 | $300 | $89 | $400+ (franchise tax) |
| Wyoming | $100 | $60 | $100 | $60 |
| Nevada | $75 + $150 bus lic | $350 bus license | $75 | $500 bus license |
| California | $70 | $800 min tax | $100 | $800 min tax |
| New York | $200 | $25 (filing) + publication $300-$1,500+ | $125 | $25 filing |
| Texas | $300 | $0 (under $2.47M) | $300 | $0 (under $2.47M) |
| Florida | $125 | $138.75 | $70 | $150 |

## Startup Costs (IRC §195) — Detailed

### What Qualifies as Startup Costs
- Costs incurred BEFORE the business begins active trade or business operations
- Must be costs that WOULD be deductible as ordinary business expenses if the business were already operating
- **Examples**: market research, pre-opening advertising, travel to scope out business locations, training employees before opening, consultant fees, pre-opening rent, pre-opening wages for staff training

### Investigation vs. Active Trade Expenses
- **Investigation costs** (before committing to a specific business): exploring a general field, analyzing market conditions, researching potential locations
- **Active trade expenses** (after committing but before operations begin): hiring staff, setting up accounting, lease negotiations for a specific location
- Both are §195 startup costs, but the distinction matters if the business is never started (see below)

### Tax Treatment
- **First $5,000**: immediately deductible in the year the business begins
- **Phase-out**: the $5,000 deduction is reduced dollar-for-dollar by startup costs exceeding $50,000
- At $55,000+ in startup costs: $0 immediate deduction; all 180-month amortization
- **Remaining costs**: amortized over 180 months (15 years) beginning in the month the business starts

### Worked Example
```
Startup costs incurred: $62,000

$5,000 immediate deduction: REDUCED by ($62,000 - $50,000) = $12,000
Immediate deduction: $5,000 - $12,000 = $0 (cannot be negative)

Entire $62,000 amortized over 180 months = $344.44/month
If business started in March: 10 months of amortization in year 1 = $3,444.44
```

### Business That Never Starts
- If you investigate a business and decide NOT to proceed: costs are personal and NOT deductible
- Exception: if investigation costs relate to a business in the same field you already operate, they may be currently deductible as expansion costs (not startup costs under §195)
- If you start and later abandon: unamortized startup costs deductible as a loss in the year of abandonment (ordinary loss under §165)

## Organizational Costs (IRC §248 for Corps, §709 for Partnerships)

- Costs of creating the legal entity: state filing fees, legal fees for articles of incorporation/organization, partnership agreement drafting, accounting fees for setting up initial books
- **Same treatment as startup costs**: first $5,000 deductible + amortize the rest over 180 months. Phase-out above $50,000.
- Only applies to partnerships and corporations; sole proprietors have no organizational costs
- **NOT organizational costs** (but may be deductible elsewhere): costs of issuing stock or partnership interests, costs of transferring assets to the entity, syndication costs (partnerships — must be capitalized, never deductible)

## EIN (Employer Identification Number)

- **Required for**: partnerships, corporations, S-Corps, multi-member LLCs, single-member LLCs with employees, trust, estate, and most bank account openings
- Obtain free from IRS at IRS.gov (Form SS-4 online application; immediate issuance during business hours)
- Sole proprietors without employees CAN use SSN but EIN is recommended for identity protection
- **One EIN per entity**: do not reuse EINs across entities. If entity structure changes (e.g., sole prop becomes partnership), a new EIN is required.
- **Responsible party**: the Form SS-4 requires a responsible party (individual, not entity). This is the person who controls, manages, or directs the entity. Update within 60 days of any change (Form 8822-B).

## First-Year Estimated Tax Payments

### The First-Year Problem
- Self-employed individuals must make quarterly estimated payments if they expect to owe $1,000+ in tax
- Due dates: April 15, June 15, September 15, January 15 (of the following year)

### No Prior-Year Safe Harbor Trap
- **Standard safe harbor**: pay 100% of prior year tax liability (110% if AGI > $150,000)
- **First-year business from a W-2 job**: your prior-year tax liability reflects the W-2 job.
  You must pay 100%/110% of THAT amount even if business income is lower. This protects you
  from penalty but may result in overpayment.
- **True first-year taxpayer (no prior return)**: no prior-year safe harbor exists. Must estimate
  current-year tax at 90% accuracy or face underpayment penalty.
- **Starting mid-year**: for the remaining quarters, calculate what's needed to meet the safe
  harbor. W-2 withholding from the employed portion of the year counts toward the total.

### State Estimated Payments
- Most states with income tax also require quarterly estimated payments
- Thresholds and due dates vary by state
- Some states have different safe harbor rules than federal (e.g., some states require 90% of current year with no prior-year option)

## Key First-Year Deductions

### Section 179 Expense Election
- Immediately expense qualifying business assets up to $2,500,000 (2025)
- Phase-out: begins at $4,000,000 of total assets placed in service
- Qualifying: tangible personal property (equipment, furniture, computers, vehicles), certain improvements, off-the-shelf software
- Must be used more than 50% for business
- Section 179 is limited to the business's net taxable income (cannot create a loss)

### Bonus Depreciation
- 40% first-year bonus depreciation for 2025 (phasing down from 100% in 2022: 80% in 2023, 60% in 2024, 40% in 2025, 20% in 2026, 0% in 2027)
- Applies to new AND used property with a recovery period of 20 years or less
- No business income limitation (unlike Section 179 — bonus depreciation CAN create a loss)

### Home Office from Day One
- If you use a portion of your home regularly and exclusively for business
- Particularly valuable for new businesses without a commercial lease
- Establishes the home as the "principal place of business" — makes ALL business travel
  from home deductible (eliminates commuting exclusion)
- **Simplified method**: $5/sq ft, max 300 sq ft ($1,500)
- **Regular method**: actual expenses proportional to business-use percentage (Form 8829)
- Start documenting from the first day of business: photos, measurements, floor plan

### Vehicle Expenses
- Standard mileage rate (2025): $0.70/mile for business use
- OR actual expenses (gas, insurance, depreciation, repairs) prorated by business-use percentage
- **Must choose standard mileage in the first year** the vehicle is used for business (to preserve the option going forward). If you claim actual in year 1, you are locked into actual for that vehicle's entire business life.
- Keep a contemporaneous mileage log from day one (date, destination, business purpose, miles)

### Health Insurance
- Self-employed health insurance deduction: premiums for self, spouse, and dependents
- Above-the-line deduction (Schedule 1), not on Schedule C
- Cannot exceed net SE income from the business
- Cannot claim if eligible for employer-subsidized health plan (including spouse's employer plan)

## Insurance Requirements for New Businesses

- **General liability insurance**: protects against third-party claims (slip-and-fall, property damage). Essential for any business with a physical location or client interaction.
- **Professional liability (E&O)**: for service businesses. Covers claims of negligence, errors, or omissions in professional services. Premiums are fully deductible.
- **Workers' compensation**: REQUIRED by most states once you have employees (even one). Rates vary by industry and state. Failure to carry workers' comp when required can result in personal liability and criminal penalties.
- **Commercial auto**: if vehicles are titled to the business or used primarily for business
- **Cyber liability**: for businesses handling customer data, credit cards, personal information

## Hiring the First Employee

### Employment Tax Registration
1. **Federal**: already have EIN. Register for EFTPS (Electronic Federal Tax Payment System) for payroll tax deposits.
2. **State**: register with state tax authority for income tax withholding AND state unemployment insurance (SUI). Each state has different registration processes.
3. **Local**: some cities/counties require registration for local payroll taxes

### Required Forms and Actions
- **Form I-9**: verify employment eligibility within 3 business days of hire. Keep on file for 3 years after hire or 1 year after termination (whichever is later).
- **Form W-4**: employee provides withholding elections. Keep on file.
- **State withholding form**: many states have their own version (e.g., CA DE-4, NY IT-2104)
- **Form 941**: Employer's Quarterly Federal Tax Return (or Form 944 if annual liability < $1,000)
- **Payroll deposits**: semi-weekly or monthly depending on lookback period liability. New employers generally deposit monthly. Penalties for late deposits: 2-15% of underpayment.
- **Form 940**: Annual FUTA return ($42 max per employee per year, plus possible state credit)
- **State unemployment returns**: quarterly (rates and forms vary by state)

### New Hire Reporting
- Must report new hires to the state directory within 20 days of hire (for child support enforcement purposes). Most states accept electronic reporting.

## Record-Keeping Systems

### Required Records
- All income received (invoices, bank deposits, payment confirmations)
- All expenses paid (receipts, credit card/bank statements, contracts)
- Mileage log (date, destination, business purpose, miles)
- Asset purchases (invoices, date placed in service, business-use percentage)
- Home office measurements and expense records (if applicable)
- Employee records (I-9, W-4, payroll records, benefits)

### Recommended Practices
- **Separate business bank account**: essential even if not legally required. Many banks offer free business checking.
- **Separate business credit card**: simplifies expense tracking and substantiation
- **Accounting software**: QuickBooks (most popular, ~$30/month), FreshBooks (freelancers), Wave (free), Xero (growing businesses)
- **Receipt management**: digital scanning/photos acceptable; no paper originals required by IRS.
  Apps: Dext (formerly Receipt Bank), Shoeboxed, or simply phone photos organized by month.
- **Accounting method election**: cash basis (most small businesses) or accrual. Must be
  consistent. Cash method available if average gross receipts $30M or less (3 years). The
  method elected on the first return is binding unless you file Form 3115 to change.
- **Retain records**: minimum 3 years from filing (6 years if substantial understatement;
  7 years for bad debt/worthless securities deduction; indefinitely if fraud or no return filed)

## Retirement Plan Establishment

### First-Year Options
| Plan | Setup Deadline | Contribution Deadline | Notes |
|------|---------------|----------------------|-------|
| SEP-IRA | Filing deadline (including extensions) | Filing deadline (including extensions) | Simplest; employer-only contributions |
| Solo 401(k) | Verify based on entity type and contribution type | Employee deferral timing is stricter; employer timing is later | Best for maximizing contributions when structured correctly |
| SIMPLE IRA | October 1 of the tax year | Employee: Jan calendar year; Employer: filing deadline | Lower limits but easiest for small employers |
| Traditional/Roth IRA | April 15 of following year | April 15 of following year | $7,000/$8,000 limit; everyone eligible |

### First-Year Strategy
- Do not rely on a blanket December 31 rule for a Solo 401(k). Adoption timing depends on the
  entity type and whether the contribution is an employee elective deferral or employer
  contribution. Verify the current IRS rules before assuming only a SEP-IRA remains available.
- **Solo 401(k) is usually optimal**: higher contribution at moderate income (due to employee
  deferral), Roth option, loan provision, no pro-rata issue for backdoor Roth
- **SEP-IRA caution**: SEP balances count for pro-rata calculation in backdoor Roth conversions.
  If you plan to do backdoor Roth, avoid SEP-IRA.

## S-Corporation Election Timing

- **Form 2553 deadline**: within 2 months and 15 days of the start of the tax year
  (March 15 for calendar-year entities) OR within 2 months and 15 days of the entity's
  formation date (for new entities)
- **Late election relief (Rev. Proc. 2013-30)**: available if filed within 3 years and 75 days
  of the intended effective date, if: (1) the entity intended S-Corp status, (2) reasonable
  cause for late filing, (3) all shareholders reported income consistent with S-Corp status.
  Write "FILED PURSUANT TO REV. PROC. 2013-30" on Form 2553.
- **Wait before electing**: if year-1 income is low or the business may lose money, S-Corp
  adds compliance costs without savings. Evaluate after the first full year of operations.

## Required Forms

| Form | Purpose |
|------|---------|
| Schedule C | Profit or Loss from Business |
| Schedule SE | Self-Employment Tax |
| Form 1040-ES | Estimated Tax Payment vouchers |
| Form 4562 | Depreciation and Amortization |
| Form 8829 | Home Office (regular method) |
| SS-4 | EIN Application |
| Form 2553 | S-Corporation Election (if applicable) |
| Form 8995/8995-A | QBI Deduction |

## Worked Example: First-Year Service Business

### Facts
- Graphic designer quits W-2 job ($80K salary) on March 31
- Forms single-member LLC on April 1, begins freelancing
- Year 1 freelance revenue: $90,000 (April-December)
- Business expenses: $12,000 (software, computer, home office, marketing)
- Prior-year tax liability: $14,000

### Tax Computation
```
W-2 income (Jan-Mar):                     $20,000
Schedule C revenue (Apr-Dec):              $90,000
Schedule C expenses:                      ($12,000)
Net Schedule C income:                     $78,000

SE tax (15.3% on $78K x 92.35%):           $11,017
50% SE tax deduction:                      ($5,509)
Self-employed health insurance (9 mo):     ($9,000)
Solo 401(k) employee deferral:            ($23,500)
Solo 401(k) employer (~20% of net SE):    ($14,498)
Standard deduction (single):              ($15,700)

Approximate taxable income:                $29,793
Federal income tax:                         $3,365
SE tax:                                    $11,017
Total federal tax:                         $14,382
```

### Estimated Payment Strategy
- Prior-year safe harbor: 100% of $14,000 = $14,000 (AGI < $150K)
- W-2 withholding (Jan-Mar): ~$4,500
- Remaining required estimated payments: $14,000 - $4,500 = $9,500
- Spread across Q2, Q3, Q4: ~$3,167/quarter
- **Result**: safe harbor met with minimal effort; actual tax of $14,382 covered

## Common Mistakes

1. **Not separating business and personal finances** — commingling makes record-keeping difficult and weakens liability protection for LLCs
2. **Missing the S-Corp election deadline** — Form 2553 must be filed within 2 months and 15 days of the start of the tax year (or use late election relief)
3. **Not making estimated payments** — underpayment penalties apply even if you get a refund. First-year businesses have no prior-year safe harbor if they had no prior SE income.
4. **Deducting startup costs improperly** — costs incurred before the business starts are subject to §195 treatment, not immediate deduction (except the first $5K)
5. **Choosing the wrong entity** — an S-Corp adds complexity and compliance costs that may not be justified for a business earning under $50K
6. **Not tracking mileage from day one** — the IRS requires contemporaneous records; reconstructed logs are disfavored. Choose standard mileage in year 1 to preserve flexibility.
7. **Using a simplistic Solo 401(k) deadline rule** — adoption and contribution timing depend on
   the entity type and contribution being claimed; verify before defaulting to a SEP-IRA
8. **Ignoring state obligations** — state registration, sales tax permits, and quarterly estimated payments are easy to overlook. Penalties accrue per-state.
9. **Not establishing home office immediately** — delays in claiming the home office mean lost deductions for rent/mortgage, utilities, and the travel deduction bonus
10. **Hiring employees without proper registration** — must register with state and federal agencies BEFORE the employee's first day. Form I-9 must be completed within 3 days.
11. **Overspending on startup costs past $50K** — the $5K immediate deduction phases out dollar-for-dollar above $50K in total startup costs. Consider timing pre-opening expenses.
12. **Forming in Delaware/Wyoming unnecessarily** — for a single-state business, forming in your home state avoids dual registration fees and foreign qualification requirements.

## State Considerations

- **California**: $800 minimum LLC/S-Corp franchise tax (first-year exemption for new LLCs registered in 2024-2025); additional LLC fee for gross receipts > $250,000
- **Texas**: no income tax but franchise (margin) tax applies to entities with revenue > $2,470,000
- **New York**: annual LLC filing fee ($25); NYC Unincorporated Business Tax (~4%) for sole proprietors/partnerships; LLC publication requirement ($300-$1,500+ depending on county)
- **Delaware**: popular for incorporation due to favorable business law; $300 annual franchise tax minimum for LLCs; $400+ for corporations
- **Nevada**: no income tax, no franchise tax; popular for formation but operating in another state still triggers that state's taxes
- **Florida**: no personal income tax; 5.5% corporate income tax on C-Corps
- **Washington**: no income tax but B&O tax on gross receipts (rates vary by business classification; 0.484% for most services)
- **Sales tax nexus**: if selling goods, understand economic nexus rules (most states: $100K in sales or 200 transactions per South Dakota v. Wayfair)
