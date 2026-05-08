# Job Change Tax Reference (Tax Year 2025)

## Overview

Changing jobs -- whether voluntary or involuntary -- creates multiple tax events and planning opportunities. Multiple W-2s, retirement plan rollovers, HSA transitions, severance payments, and unemployment compensation all require careful handling. Understanding these issues prevents over-withholding, penalty traps, and missed opportunities.

## Tax Implications

### Multiple W-2s in One Year
- Each employer withholds based on their wages alone (does not know about other employer income)
- Common result: under-withholding because each employer uses lower bracket withholding rates
- Example: two jobs each paying $60,000 will each withhold as if total income is $60,000, not $120,000
- **Solution**: use IRS Tax Withholding Estimator at new job to increase withholding (W-4 Step 4(c) for additional amount per pay period)
- Alternative: make an estimated tax payment (Form 1040-ES) to cover the shortfall

### Social Security Over-Withholding -- Detailed Mechanics

**2025 Social Security wage base**: $176,100. Each employer independently withholds 6.2% on wages up to $176,100.

**The problem**: If combined wages from multiple employers exceed $176,100, excess Social Security tax was withheld because each employer treats its wages independently.

**Worked example**:
- Job 1 (Jan-June): $110,000 in wages. SS withheld: $110,000 x 6.2% = $6,820
- Job 2 (July-Dec): $95,000 in wages. SS withheld: $95,000 x 6.2% = $5,890
- Total wages: $205,000. Total SS withheld: $12,710
- Maximum SS tax: $176,100 x 6.2% = $10,918.20
- **Excess withheld**: $12,710 - $10,918.20 = $1,791.80

**How to claim**: Report the excess as a credit on Form 1040, line 26 (for TY 2025). The refundable credit appears on your return. You must claim it yourself -- it is NOT automatic.

**Note**: Medicare tax (1.45%) has no wage base limit and there is no refund for Medicare over-withholding. The 0.9% Additional Medicare Tax ($200K single / $250K MFJ) is reconciled on Form 8959.

**Employer cannot adjust**: even if you tell Employer 2 about Employer 1's withholding, they are legally required to withhold on their wages independently. The refund mechanism on Form 1040 is the only remedy.

### Withholding Strategy for New Job
- Adjust W-4 at new employer to account for:
  - Year-to-date income already earned at prior employer
  - Expected income for the rest of the year at new employer
  - Any other income sources (investments, SE, spouse's income)
- If starting a new job late in the year with significant income already earned: may need substantial additional withholding to avoid underpayment penalty
- Use IRS Tax Withholding Estimator (irs.gov/W4App) for precise calculation

## Retirement Plan Transitions

### 401(k) Rollover Options
When leaving an employer, you have four options for your 401(k):
1. **Roll over to new employer's 401(k)**: direct trustee-to-trustee transfer; no tax consequences; preserves Rule of 55 for the new plan
2. **Roll over to a traditional IRA**: most flexible investment options; no tax consequences on direct rollover; cannot use Rule of 55 or Net Unrealized Appreciation (NUA) strategy after rollover
3. **Leave in former employer's plan**: allowed if balance > $5,000 (most plans); may have limited investment options or higher fees
4. **Cash out (distribution)**: taxable as ordinary income PLUS 10% early withdrawal penalty if under 59.5 (exceptions: Rule of 55, disability, QDRO, etc.)

### Direct vs. Indirect Rollover -- Critical Distinction

**Direct rollover (trustee-to-trustee)**:
- Check made payable to the new custodian (e.g., "Fidelity FBO John Smith")
- No withholding, no tax, no 60-day deadline
- No limit on frequency
- This is ALWAYS the preferred method

**Indirect rollover**:
- Check made payable to YOU
- **20% mandatory federal withholding**: the plan MUST withhold 20% for federal tax, even if you intend to complete the rollover
- You must deposit the FULL original amount (including replacing the 20% from your own funds) into the new account within 60 days
- If you do not replace the 20%, that shortfall is treated as a taxable distribution + potential 10% penalty
- **Once-per-year limit**: only one indirect IRA-to-IRA rollover per 12-month period (per person, not per account). Does NOT apply to direct rollovers or 401(k)-to-IRA rollovers.

**Worked example -- indirect rollover trap**:
- You receive a $100,000 distribution from your 401(k). Plan withholds 20% = $20,000. You get a check for $80,000.
- To complete a tax-free rollover, you must deposit $100,000 (not $80,000) into an IRA within 60 days.
- You need to come up with $20,000 from other funds to complete the full rollover.
- If you only deposit the $80,000: the $20,000 shortfall is a taxable distribution. If under 59.5, also a 10% penalty ($2,000).
- You recover the $20,000 withholding when you file your tax return (as a credit), but you still owe tax + penalty on the $20,000 distribution.

### Rule of 55 (Separation from Service) -- Detailed Rules

**IRC Section 72(t)(2)(A)(v)**: If you separate from service in or after the year you turn 55, you can take penalty-free distributions from THAT employer's 401(k)/403(b).

**Key restrictions**:
- Must be the plan of the employer you separated from at age 55+ (not a prior employer's plan)
- Does NOT apply to IRAs -- only employer plans
- If you roll the 401(k) to an IRA before taking distributions: you LOSE the Rule of 55 access permanently
- The separation must be in the year you turn 55 or later (not earlier with distributions starting at 55)
- SECURE 2.0 enhancement: **Rule of 50** for qualified public safety employees

**Planning**: if you are between 55 and 59.5 and may need access to retirement funds, keep money in the employer plan rather than rolling to IRA.

### Net Unrealized Appreciation (NUA) -- Employer Stock Strategy

If you hold employer stock in your 401(k), NUA provides a powerful tax planning opportunity:

**How it works**:
1. Distribute employer stock in-kind from the 401(k) (not as cash)
2. Pay ordinary income tax ONLY on the cost basis of the stock (what the plan originally paid for it)
3. The NUA (difference between FMV at distribution and cost basis) is taxed at long-term capital gains rates when the stock is eventually sold -- regardless of holding period after distribution
4. Any additional appreciation after distribution follows normal holding period rules (STCG if sold within 1 year, LTCG if held >1 year)

**Requirements**:
- Must distribute the ENTIRE plan balance in a single tax year ("lump-sum distribution")
- Must be triggered by a qualifying event: separation from service, reaching age 59.5, disability, or death
- Can roll non-stock assets to IRA while taking stock in-kind

**Worked example**:
- 401(k) contains 10,000 shares of employer stock. Cost basis in the plan: $100,000. Current FMV: $500,000.
- NUA = $500,000 - $100,000 = $400,000.
- **NUA strategy**: Take stock in-kind. Pay ordinary tax on $100,000 (cost basis). When sold, pay LTCG rate (20%) on $400,000 = $80,000.
- **Rollover strategy**: Roll to IRA. When withdrawn, pay ordinary tax on $500,000 at 37% = $185,000.
- **Tax savings**: $105,000+ in federal tax savings.

**Lost if stock is rolled to an IRA** -- once in an IRA, all distributions are ordinary income. NUA opportunity is permanently lost.

## Employer Benefits Transition Checklist

### Health Insurance
- **COBRA**: continues employer coverage for 18 months (36 months in some cases). Expensive (full premium + 2% admin fee) but same coverage.
- **Marketplace**: losing employer coverage triggers a 60-day Special Enrollment Period. May qualify for Premium Tax Credit.
- **New employer plan**: typically begins on first day or first of the month after start date. Gap coverage may be needed.
- **Gap in coverage**: if there is a gap between old and new employer coverage, consider short-term health insurance or Marketplace plan for the interim.

### Life and Disability Insurance
- Employer-provided life insurance ends on separation. Consider converting to an individual policy (typically within 31 days of termination, no medical exam).
- Short-term and long-term disability coverage ends. Evaluate need for individual disability insurance.

### Dependent Care FSA
- Dependent care FSA funds from the old employer must be used for expenses incurred during the coverage period. Remaining balance is forfeited.
- New employer FSA: can enroll during new-hire enrollment period. Annual election starts fresh.

### Healthcare FSA
- If you leave mid-year, you can only submit claims for expenses incurred during the period you were covered.
- COBRA allows you to continue Healthcare FSA contributions and access the full annual election.
- This can be valuable if you front-loaded medical expenses early in the year.

## HSA Mid-Year Changes

### Changing HDHP Coverage
- If you lose HDHP coverage (new employer offers only traditional plan): HSA contribution limit is prorated by month
- Example: HDHP coverage for 6 months = 6/12 of annual limit
- **Last-month rule exception**: if you have HDHP coverage on December 1, you can contribute the FULL annual amount; but you must maintain HDHP coverage through December 31 of the FOLLOWING year (13-month testing period); failure triggers tax + 10% penalty on the excess

### HSA Portability
- HSA is YOURS -- it does not belong to the employer. You own it permanently.
- Keep your existing HSA or transfer to a new custodian; no tax consequences on trustee-to-trustee transfer
- One rollover (indirect) per 12-month period
- New employer's HSA contributions (if any) count toward the annual limit
- You can continue to use the HSA for qualified medical expenses even if you no longer have HDHP coverage (you just cannot make new contributions)

### HSA Contribution Limits (2025)
- Self-only: $4,300
- Family: $8,550
- Catch-up (55+): additional $1,000
- Prorate if HDHP coverage changes mid-year (unless last-month rule applies)

## Severance Pay

### Tax Treatment
- Severance pay is taxable as ordinary income in the year received
- **Subject to all employment taxes**: federal income tax withholding, Social Security (6.2%), AND Medicare (1.45%)
- Reported on W-2 from the former employer
- May push you into a higher bracket for the year

### Negotiating Timing
- **Defer to next year**: if you expect lower income next year, negotiate to receive severance in January instead of December
- **Accelerate**: if next year's income will be higher (new job starts January), take the severance this year
- **Installment payments**: if employer is willing, spreading over 2 years can reduce bracket impact

### Lump Sum vs. Installments
- Lump sum: all income in one year; higher withholding; potential bracket bump
- Installments: spread income over multiple years; lower bracket impact; BUT risk of employer default on future payments and no FICA wage base benefit if each year's payments are below $176,100
- Tax planning opportunity: if you expect lower income in the following year, installments may be preferable

## COBRA Continuation

- COBRA premiums are NOT deductible for W-2 employees (not self-employed)
- Exception: if you are self-employed (have Schedule C income), COBRA premiums may qualify for the self-employed health insurance deduction (IRC Section 162(l))
- COBRA coverage can last 18 months (36 months in certain situations)
- Alternative: Marketplace plan during Special Enrollment Period (job loss is a qualifying event). May qualify for Premium Tax Credit based on projected annual income.

## Unemployment Compensation

- **Fully taxable** as ordinary income at the federal level
- Report on Form 1099-G; include on Form 1040 Line 7
- Federal tax not withheld by default -- opt into 10% voluntary withholding (Form W-4V) or make estimated payments
- State treatment varies: some states do not tax unemployment benefits (CA, MT, NJ, PA, VA, and others)

## Job Search Expenses

- **NOT deductible** under current law (TCJA suspended miscellaneous itemized deductions through 2025)
- Before TCJA: travel, resume preparation, employment agency fees were deductible as miscellaneous itemized deductions (subject to 2% AGI floor)
- May become deductible again if TCJA provisions expire after 2025

## Relocation/Moving Expenses

- **NOT deductible** for most taxpayers under TCJA (2018-2025)
- **Exception**: active-duty military members moving under military orders can still deduct (Form 3903) per IRC Section 217(g)
- Employer-paid moving reimbursements: taxable as wages (included in W-2 Box 1)
- Exception: military members' employer-paid moving expenses are excludable

## Required Forms

| Form | Purpose |
|------|---------|
| W-2 | From each employer during the year |
| Form 1099-R | Retirement plan distributions |
| Form 5498 | IRA contribution/rollover report |
| Form 1099-G | Unemployment compensation |
| Form W-4 | Employee withholding (update at new employer) |
| Form W-4V | Voluntary withholding on unemployment |
| Schedule 3 | Excess Social Security tax credit |
| Form 8959 | Additional Medicare Tax reconciliation |

## Optimization Strategies

1. **Adjust withholding immediately at new job**: prevent year-end surprise by accounting for income earned at the prior job
2. **Direct rollover of retirement funds**: avoid 20% mandatory withholding and the 60-day scramble
3. **Evaluate NUA strategy before rolling over**: if you hold appreciated employer stock in a 401(k), this is a rare opportunity. Once rolled to an IRA, it is permanently lost.
4. **Preserve Rule of 55 access**: if you are 55-59.5 and may need the funds, do NOT roll to an IRA
5. **Maximize retirement contributions at both employers**: combined employee deferrals cannot exceed $23,500 ($31,000 if 50+), but employer matches are separate
6. **HSA: use the last-month rule strategically**: if you have HDHP coverage on December 1, contribute the full annual amount
7. **Time severance if possible**: negotiate payment timing to minimize bracket impact
8. **Claim excess Social Security tax**: easy to miss when filing; verify total Social Security withheld across all W-2s exceeds $10,918.20
9. **COBRA vs. Marketplace comparison**: losing employer coverage triggers a Special Enrollment Period; Marketplace with PTC may be cheaper than COBRA

## Common Mistakes

1. **Not adjusting W-4 at new employer** -- results in under-withholding and potential underpayment penalty
2. **Forgetting to claim excess Social Security tax** -- if combined wages exceed $176,100, you are owed a refund. It does not happen automatically.
3. **Cashing out 401(k)** -- pays income tax PLUS 10% penalty; loses decades of tax-deferred growth. A $100,000 cashout at age 35 costs ~$45,000 in tax/penalty and ~$600,000 in future retirement value.
4. **Indirect rollover: not replacing the 20% withholding** -- if you deposit less than the full balance, the shortfall is a taxable distribution plus 10% penalty if under 59.5
5. **Rolling employer stock to IRA without evaluating NUA** -- permanently loses the favorable capital gains treatment
6. **Over-contributing to HSA** -- forgetting to prorate for partial-year HDHP coverage
7. **Not reporting unemployment income** -- IRS receives Form 1099-G; failing to report triggers a notice
8. **Missing the 60-day indirect rollover deadline** -- distribution becomes fully taxable with no remedy (except one self-certified hardship waiver per lifetime under Rev. Proc. 2020-46)
9. **Rolling 401(k) to IRA when you need Rule of 55 access** -- the penalty-free distribution option is permanently lost once funds are in an IRA
10. **Not coordinating 401(k) contributions across employers** -- exceeding the $23,500 employee deferral limit triggers tax + penalty on the excess

## Negotiation and Signing Bonus Considerations

### Signing Bonus
- Taxable as ordinary income in the year received
- Subject to supplemental wage withholding rate (22% federal flat rate, or aggregate method)
- If you must repay the signing bonus (e.g., if you leave within a year), you get a deduction in the repayment year
- **Timing strategy**: if offered a choice, consider whether receiving the bonus this year or next is more tax-efficient

### Relocation Packages
- Employer-paid relocation: taxable as wages under TCJA (included in W-2 Box 1) for non-military
- Some employers "gross up" relocation payments to cover the tax
- Employer-provided temporary housing: taxable benefit
- Track all relocation-related expenses even though they are not deductible -- they may be needed for state allocation or if TCJA expires

### Non-Compete Payments
- Taxable as ordinary income
- Subject to FICA (Social Security and Medicare taxes)
- State sourcing: generally sourced to where the former employment was performed, but varies by state
- May need to be reported on the former employer's W-2 or on a 1099-NEC

### Stock Compensation at Job Change
- **Unvested RSUs**: forfeited upon leaving (no tax consequence; you never received them)
- **Vested but unexercised ISOs**: generally must exercise within 90 days of separation or lose them. Exercise triggers AMT preference (spread between exercise price and FMV).
- **Vested but unexercised NQSOs**: check the plan for post-termination exercise period (often 90 days). Exercise triggers ordinary income on the spread.
- **New employer equity**: RSU grants and option grants from new employer have their own vesting schedules. First vesting date triggers income.

## Worked Example -- Complete Job Change Tax Impact

**Scenario**: leave a job paying $150,000 on June 30. Start a new job paying $180,000 on August 1. Receive $15,000 severance and $10,000 signing bonus.

- **W-2 from old employer**: $75,000 wages + $15,000 severance = $90,000 (Box 1)
- **W-2 from new employer**: $75,000 wages + $10,000 signing bonus = $85,000 (Box 1)
- **Total income**: $175,000
- **Social Security check**: Old employer withheld 6.2% on $90,000 = $5,580. New employer withheld 6.2% on $85,000 = $5,270. Total = $10,850. Maximum = $10,918. No excess to claim.
- **Withholding issue**: each employer withheld as if their wages were the only income. Combined income of $175,000 is in the 32% bracket, but each employer likely withheld at the 22-24% bracket rate. Shortfall estimated at $2,000-$4,000.
- **Action**: adjust W-4 at new employer (Step 4(c)) to add ~$300-$400/month additional withholding to cover the gap.

## State Considerations

- **Unemployment taxation**: CA, MT, NJ, PA, VA, and others do not tax unemployment benefits at the state level
- **401(k) rollover**: no state tax consequences on direct rollovers in any state
- **Severance sourcing for multi-state**: generally sourced to where the services were performed; may require allocation if you worked in multiple states for the same employer
- **State withholding**: update state withholding form at new employer; if changing states, may need to file part-year returns in both states
- **Non-compete payments**: taxable as ordinary income; sourced to the state where the former employment was located (varies by state)
- **State retirement plan protections**: some states exempt 401(k)/IRA distributions from state income tax (PA exempts all retirement plan distributions; IL exempts retirement income)
- **Signing bonus sourcing**: if you move states for a new job, the signing bonus is generally sourced to where you will perform services (new state), but this can vary
