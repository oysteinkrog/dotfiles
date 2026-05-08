# Self-Employed Taxpayer Reference (Tax Year 2025)

## Overview

Self-employed individuals file Schedule C (Form 1040) to report business income and expenses. This includes sole proprietors, independent contractors (1099-NEC recipients), gig economy workers, and single-member LLC owners who have not elected corporate taxation. Self-employment triggers additional tax obligations beyond those of W-2 employees, including self-employment tax and quarterly estimated payments.

## Self-Employment Tax — Detailed Computation (Schedule SE, IRC §1402)

### The 92.35% Factor
- SE tax rate: 15.3% (12.4% Social Security + 2.9% Medicare)
- Applied to **92.35%** of net earnings, not the full amount
- The 92.35% factor (100% - 7.65%) simulates the employer-half deduction that W-2 employees
  receive (employer pays 7.65%, and that portion is not taxable to the employee)
- Net SE earnings = Schedule C net profit x 0.9235

### Step-by-Step Computation
```
1. Schedule C net profit:                           $180,000
2. Multiply by 92.35%:                              $166,230
3. Social Security tax (12.4% on first $176,100):   $20,613 (full amount, since $166,230 < $176,100)
4. Medicare tax (2.9% on all):                       $4,821
5. Additional Medicare (0.9% on amount > $200K single / $250K MFJ):  $0
   (Note: threshold applies to COMBINED wages + SE income)
6. Total SE tax:                                     $25,434
7. 50% deduction (above-the-line):                   $12,717
```

### Interaction with W-2 Wages
- If the taxpayer also has W-2 wages, the Social Security wage base ($176,100) is reduced by
  the W-2 wages. Only the remainder is subject to the 12.4% SS portion of SE tax.
- Example: $80K in W-2 wages + $120K Schedule C. SS tax on SE income applies only to
  $176,100 - $80,000 = $96,100 of the SE income (at 12.4%).
- The 2.9% Medicare portion has NO cap — applies to all SE income.
- Additional 0.9% Medicare: applies when COMBINED W-2 wages + SE income exceeds $200K (single)
  or $250K (MFJ). The W-2 employer does not withhold the additional Medicare on SE income,
  so the self-employed person pays it through Schedule SE.

## Estimated Tax Payments — Traps and Mechanics

### Due Dates and Safe Harbors (IRC §6654)
- Due quarterly: April 15, June 15, September 15, January 15 (of following year)
- **Safe harbor #1**: Pay 100% of prior year tax liability (110% if AGI > $150,000)
- **Safe harbor #2**: Pay 90% of current year tax
- Meet EITHER to avoid underpayment penalty

### Penalty Calculation
- Penalty rate: federal short-term rate + 3 percentage points (~8% for 2025)
- Computed PER QUARTER: each quarter's underpayment accrues interest separately from its
  due date until the earlier of: (1) payment date, or (2) April 15 of the following year
- Use Form 2210 to compute penalty or request waiver
- **No waiver for ignorance** — penalty is automatic and not subject to reasonable cause waiver
  (except for casualty, disaster, or retirement after age 62)

### Annualized Income Installment Method (Form 2210, Schedule AI)
- For self-employed individuals with uneven income (e.g., seasonal business, large Q4 project)
- Calculates required payment based on income ACTUALLY EARNED through each quarter
- Periods: 1/1-3/31, 1/1-5/31, 1/1-8/31, 1/1-12/31 (note: not standard quarter ends)
- Prevents penalty when income is back-loaded even if annual estimated payments seem insufficient
- Must complete Schedule AI with Form 2210; complex but valuable for variable-income businesses

### First-Year Estimated Payment Trap
- If you had no prior-year tax liability (true startup): the prior-year safe harbor is $0,
  but you must still pay 90% of current-year tax. Estimate conservatively.
- If transitioning from W-2: your prior-year safe harbor is based on your W-2 year's tax.
  You must pay 100%/110% of that amount even if self-employment income is lower.
- W-2 withholding from earlier in the year counts toward the required amount.

## Health Insurance Deduction — Circular Calculation with PTC

### Basic Rules (IRC §162(l))
- Self-employed health insurance deduction: above-the-line deduction for premiums paid for
  self, spouse, and dependents
- Cannot exceed net SE income from the business under which the plan is established
- Cannot claim if eligible for employer-subsidized coverage (including through spouse)
- Includes medical, dental, vision, and qualified long-term care premiums (age-based limits)
- Does NOT reduce SE tax — only income tax

### Interaction with Premium Tax Credit (PTC)
- If you buy insurance through the ACA marketplace and receive PTC, a circular dependency arises:
  1. The SE health insurance deduction reduces your AGI
  2. Lower AGI increases your PTC (or maintains eligibility)
  3. Higher PTC reduces the net premium you pay
  4. Lower net premium reduces the SE health insurance deduction
  5. Which raises AGI... and the cycle repeats
- IRS provides an iterative calculation method in **Publication 974**
- Tax software handles this automatically, but manual filers must iterate until the numbers converge
- **Common mistake**: claiming the full gross premium as the deduction when PTC reduces the
  out-of-pocket amount. The deduction is limited to the NET premium after PTC.

## QBI Deduction for Schedule C Filers (IRC §199A)

### Mechanics
- Up to 20% of qualified business income
- Schedule C net income is QBI (after reducing for 50% of SE tax and SE health insurance deduction)
- QBI deduction is taken on Form 1040, NOT on Schedule C (does not reduce SE income)

### SSTB vs. Non-SSTB
- **SSTB (Specified Service Trade or Business)**: health, law, accounting, consulting, financial
  services, performing arts, athletics, brokerage. Principal asset is reputation/skill of employees.
- Below threshold ($197,300 single / $394,600 MFJ): full 20% deduction regardless of business type
- Phase-out for SSTB: $197,300-$247,300 (single), $394,600-$494,600 (MFJ). Above = $0.
- Non-SSTB above threshold: limited to greater of 50% of W-2 wages OR 25% of W-2 + 2.5% of UBIA

### W-2/UBIA Limitation for Schedule C
- Schedule C sole proprietors typically have $0 in W-2 wages (they don't pay themselves W-2)
- If you have employees, their wages count toward the W-2 limitation
- UBIA = unadjusted basis of depreciable property used in the business (computers, equipment, vehicles)
- **S-Corp strategy**: paying yourself W-2 wages through an S-Corp creates W-2 wages that
  increase the QBI limitation. Particularly valuable for non-SSTB businesses above the threshold.

## Home Office — Principal Place of Business

### Legal Standard (Commissioner v. Soliman, 506 U.S. 168 (1993))
- The Supreme Court established a two-part test:
  1. **Relative importance**: where the most important/essential functions of the business are performed
  2. **Time**: comparative amount of time spent at each location
- Congress subsequently amended IRC §280A(c)(1) to clarify that a home office qualifies as
  the principal place of business if it is used for **administrative or management activities**
  and there is **no other fixed location** where such activities are substantially conducted.
- For most self-employed individuals working from home: the home office qualifies as the
  principal place of business even if services are delivered at client locations.

### Deduction Methods
- **Simplified method**: $5/sq ft, max 300 sq ft = $1,500 max deduction
- **Regular method (Form 8829)**: actual expenses proportional to business-use percentage
  - Direct expenses: 100% deductible (e.g., painting the office)
  - Indirect expenses: proportional (mortgage interest, rent, utilities, insurance, repairs, depreciation)
- Home office deduction limited to gross income from the business (carryforward allowed)
- Employees working from home: NOT deductible under TCJA (2018-2025) unless specific exceptions

### Travel Deduction Bonus
- With a qualified home office, ALL travel from home to business locations is deductible
  (Rev. Rul. 99-7). Without a home office, travel from home to first/last work location
  is nondeductible commuting.

## Business vs. Hobby — Section 183

### The 9-Factor Test (Reg. §1.183-2)
No single factor is determinative; IRS and courts weigh all factors together:
1. **Manner carried on**: businesslike records, separate accounts, business plan
2. **Expertise**: taxpayer's knowledge or use of advisors
3. **Time and effort**: devoted to the activity
4. **Expectation of appreciation**: business assets may increase in value
5. **Success in similar activities**: prior profitable ventures in similar field
6. **History of income or losses**: pattern of losses raises suspicion
7. **Amount of occasional profits**: large occasional profit may indicate profit motive
8. **Financial status**: if taxpayer has other substantial income sources, suggests hobby
9. **Elements of personal pleasure**: enjoyment of the activity (horse breeding, art, travel)

### Presumption of Profit Motive
- Profit in 3 of 5 consecutive years (2 of 7 for horse breeding/racing)
- This is a **presumption**, not a safe harbor — IRS can still challenge
- Taxpayer can elect under §183(e) to postpone the determination until the end of the 5-year
  (or 7-year) period by filing Form 5213. Extends the statute of limitations.

### Consequences of Hobby Classification
- Income still fully taxable (reported on Schedule 1, Line 8j — other income)
- Expenses: NOT deductible at all under TCJA (suspended miscellaneous itemized deductions 2018-2025)
- Pre-TCJA: hobby expenses were deductible as miscellaneous itemized deductions subject to 2% AGI floor
- SE tax does NOT apply to hobby income (small consolation)
- **Key cases**: Groetzinger v. Commissioner (gambling as trade/business); Nickerson v. Commissioner
  (real estate activity conducted like a business despite losses)

## Vehicle Expenses

### Standard Mileage vs. Actual Expenses
- **Standard mileage rate 2025**: $0.70/mile for business use
- **Actual expense method**: gas, insurance, repairs, depreciation, etc. prorated by business-use %

### First-Year Lock-In Rule
- Must choose standard mileage in the FIRST YEAR the vehicle is used for business to preserve
  the option for future years
- If you claim actual expenses in year 1: you can NEVER use standard mileage for that vehicle
- If you use standard mileage in year 1: you CAN switch to actual in later years
- **5-or-more vehicles**: cannot use standard mileage if you operate 5+ vehicles simultaneously
  (fleet operators must use actual method)
- Cannot use standard mileage if you claimed §179 or bonus depreciation on the vehicle

### Substantiation Requirements (IRC §274(d))
- Must maintain a contemporaneous log: date, destination, business purpose, miles driven
- "Contemporaneous" = recorded at or near the time of the trip (not reconstructed at year-end)
- Log must distinguish business from personal miles
- Total business miles must be supportable — IRS frequently disallows vehicle deductions
  for inadequate documentation

## Record-Keeping Requirements

- Retain records for at least 3 years from filing date (6 years if >25% understatement;
  indefinitely if fraud or failure to file)
- Required documentation: receipts, bank/credit card statements, mileage logs, contracts, invoices
- **Separate business bank account**: strongly recommended (not legally required for sole prop
  but practically essential). Commingling personal and business funds weakens deduction
  substantiation and can be used by IRS to impute unreported income.
- Digital records acceptable; no requirement for paper originals
- Meals: record date, amount, business purpose, attendees, relationship to business

## Retirement Plan Comparison for Self-Employed

| Feature | Solo 401(k) | SEP-IRA | SIMPLE IRA | Defined Benefit |
|---------|-------------|---------|------------|-----------------|
| Employee deferral | $23,500 ($31,000 if 50+) | None | $16,500 ($20,000 if 50+) | N/A |
| Employer contribution | 20% of net SE or 25% of W-2 | 20% of net SE or 25% of W-2 | 3% match or 2% nonelective | Actuarially determined |
| Total max | $70,000 + catch-up | $70,000 | ~$32,500 | $280,000+ benefit |
| Roth option | Yes (employee portion) | No | No | No |
| Loan | Yes (up to $50K) | No | No | No |
| Setup deadline | Dec 31 of tax year | Filing deadline (incl. ext.) | Oct 1 of tax year | Filing deadline (incl. ext.) |
| Funding deadline | Employee: Dec 31; Employer: filing | Filing deadline (incl. ext.) | Employee: calendar year; Employer: filing | Filing deadline (incl. ext.) |
| Backdoor Roth impact | None | YES (pro-rata) | None (different rules) | None |
| Admin cost | Low ($0-$300/yr) | Very low | Very low | High ($2K-$10K/yr) |
| Best for | Most self-employed | Last-minute setup | Small income, simplicity | High earners age 40+ |

### Key Decision Points
- **Solo 401(k) vs. SEP**: Solo 401(k) is almost always better (higher contribution at lower
  income due to employee deferral, Roth option, loan, no pro-rata issue for backdoor Roth).
  Only choose SEP if you need to establish and fund AFTER Dec 31 (SEP can be set up through
  filing deadline).
- **Adding a Defined Benefit plan**: for high earners ($300K+), a cash balance DB plan layered
  on top of a 401(k) can shelter $300K+ per year. Requires actuarial administration but
  deduction is substantial. Must commit to funding for multiple years.

## Applicable Forms

| Form | Purpose |
|------|---------|
| Schedule C | Profit or Loss from Business |
| Schedule SE | Self-Employment Tax |
| Form 1040-ES | Estimated Tax Payments |
| Form 8829 | Home Office Deduction (regular method) |
| Form 4562 | Depreciation and Amortization |
| Form 8995/8995-A | QBI Deduction |
| Form 2210 | Underpayment of Estimated Tax |
| 1099-NEC | Nonemployee Compensation received |
| 1099-K | Payment card / third-party network receipts |

## Entity Election Decision

- **Sole Proprietorship / Single-Member LLC**: simplest; all income on Schedule C; full SE tax
- **S-Corporation election (Form 2553)**: pay reasonable salary (subject to payroll tax), take
  remaining profit as distributions (no SE tax). Beneficial when net income consistently
  exceeds ~$50,000-$60,000 after salary
- **S-Corp must file Form 1120-S**; election deadline: March 15 (2 months 15 days into tax year)
  or use late election relief under Rev. Proc. 2013-30
- Consider: additional payroll compliance costs ($1,000-$3,000/yr), state-level entity taxes,
  unemployment insurance obligations

## Section 179 and Bonus Depreciation
- Section 179 limit for 2025: $2,500,000 (phase-out begins at $4,000,000)
- Bonus depreciation: generally 100% for qualified property acquired and placed in service after January 19, 2025; property acquired before January 20, 2025 is generally limited to 40%
- Applies to equipment, vehicles (with limitations), software, qualified improvement property
- Listed property (vehicles) special rules: SUV limit $31,300 for Section 179; luxury auto caps apply

## Common Mistakes

1. **Failing to make estimated payments** — results in underpayment penalties even if you get a refund. Penalty is automatic; no reasonable-cause waiver.
2. **Deducting personal expenses as business** — mixed-use items must be properly allocated.
3. **Not tracking basis in assets** — critical for depreciation and eventual sale/disposition.
4. **Ignoring state obligations** — many states have separate estimated payment requirements, business registration fees, and gross receipts taxes.
5. **Overlooking the QBI deduction** — leaving up to 20% of income on the table.
6. **Claiming home office without meeting exclusive-use test** — a room used partly as a guest bedroom does not qualify.
7. **Misclassifying workers** — treating employees as independent contractors triggers penalties (Section 530 relief may apply).
8. **Not deducting self-employed health insurance** — must be claimed on Schedule 1, not Schedule C. Does not reduce SE tax.
9. **Choosing actual vehicle expenses in year 1** — locks you out of standard mileage for the life of that vehicle.
10. **Ignoring the health insurance / PTC circular calculation** — under- or over-claiming the SE health deduction when receiving marketplace PTC.
11. **Not separating bank accounts** — commingling personal and business funds is the most common audit weakness.
12. **Using a simplistic Solo 401(k) deadline rule** — adoption and contribution timing vary by
    entity type and contribution type. Verify the current IRS rules before concluding the taxpayer
    must fall back to a SEP-IRA.

## Worked Example: Self-Employed Consultant, $120K Net Income

### Facts
- Marketing consultant, single, Schedule C, home office (200 sq ft of 1,500 sq ft home)
- Gross 1099-NEC income: $150,000
- Business expenses: $18,000 (software, subcontractors, marketing, home office)
- Net Schedule C income before retirement: $132,000
- Health insurance premium: $8,400/year (marketplace plan)
- Prior-year tax liability: $22,000

### Computation
```
Schedule C net income:                         $132,000
SE tax (15.3% on $132K x 92.35%):              $18,652
50% SE tax deduction:                          ($9,326)
Self-employed health insurance:                ($8,400)
Solo 401(k) employee deferral:                ($23,500)
Solo 401(k) employer (~20% of $132K net SE):  ($20,537)
  (20% x ($132,000 - $9,326) = $24,535; capped so total ≤ $70K)
QBI deduction: 20% x $132,000 =              ($26,400)
Standard deduction:                           ($15,700)

Taxable income:                                $28,137
Federal income tax:                             $3,197
SE tax:                                        $18,652
Total federal tax:                             $21,849
Effective rate on $132K:                       16.6%
```

### Estimated Payment Strategy
- Prior-year safe harbor: 100% of $22,000 = $22,000
- Quarterly payments: $5,500 x 4 = $22,000
- Actual tax: $21,849 — slight overpayment, applied to next year or refunded

### Without Optimization (No Retirement, No QBI Awareness)
- Taxable income: ~$98,574
- Federal income tax: ~$16,200
- SE tax: $18,652
- Total: ~$34,852
- **Tax savings from optimization: ~$13,003/year**

## State-Specific Notes

- **California**: $800 minimum LLC tax (even for single-member LLCs); additional LLC fee if gross receipts > $250,000
- **Texas**: no income tax but franchise (margin) tax applies to entities with revenue > $2,470,000
- **New York**: requires separate estimated payments; NYC has additional UBT (Unincorporated Business Tax) at ~4%
- **Illinois**: replacement tax on pass-through entities (1.5% for partnerships, S-Corps)
- **Washington**: no income tax but B&O (Business & Occupation) tax on gross receipts
- **Colorado**: requires state estimated payments with different thresholds than federal
- **Oregon**: high income tax (up to 9.9%) but no sales tax; SE income fully taxable at state level
- Many states do not conform to federal QBI deduction (CA, NJ, and others add QBI back)
- State nexus rules vary — selling into other states may create filing obligations
- PTET elections available in 30+ states for S-Corp filers — bypass the personal SALT cap
- Some states have additional SE-like taxes (e.g., NYC UBT at ~4% on net SE income)
