# Net Operating Loss (NOL) Reference (Tax Year 2025)

## Overview

A Net Operating Loss occurs when a taxpayer's allowable deductions exceed their gross income in a given tax year. NOLs most commonly arise from business losses (Schedule C, partnership, S-Corp) that exceed all other income sources. Post-TCJA, NOLs have unlimited carryforward but generally cannot be carried back, and the deduction is limited to 80% of taxable income. Proper NOL computation, tracking, and strategic deployment can save thousands in taxes across multiple years.

## Section 172 -- NOL Rules Post-TCJA

### Current Law (Tax Years 2021+)
- **Carryforward**: unlimited -- no time limit on how long an NOL can be carried forward
- **Carryback**: generally NO carryback allowed (exception: farming losses -- see below)
- **80% limitation**: NOL deduction is limited to 80% of taxable income (before the NOL deduction) in the carryforward year
- The 80% limitation means a taxpayer with an NOL carryforward will ALWAYS have at least 20% of their income subject to tax (they can never fully zero out their income with NOL alone)

### Pre-2018 NOLs
- NOLs generated before 2018 are NOT subject to the 80% limitation
- They can offset 100% of taxable income
- They had a 20-year carryforward period (now effectively unlimited since any remaining pre-2018 NOLs have been carried forward under current rules)
- **Ordering rule**: pre-2018 NOLs are applied FIRST (before post-2017 NOLs), which is beneficial because they are not subject to the 80% cap

### How the 80% Limitation Works

```
Example:
  Taxable income before NOL deduction: $100,000
  NOL carryforward from 2023: $200,000

  Maximum NOL deduction: $100,000 x 80% = $80,000
  Taxable income after NOL: $100,000 - $80,000 = $20,000
  Remaining NOL carryforward: $200,000 - $80,000 = $120,000

  Result: taxpayer pays tax on $20,000 even though they have
  $120,000 of unused NOL remaining
```

## How NOL Arises

### Common Sources
1. **Schedule C business loss**: business expenses exceed business income
2. **Partnership / S-Corp loss**: K-1 losses passed through to individual return
3. **Rental activity loss**: only if the taxpayer qualifies as a real estate professional (otherwise limited by passive activity rules first)
4. **Farm loss**: Schedule F losses
5. **Casualty and theft losses**: from a federally declared disaster
6. **Employee business expenses**: largely eliminated under TCJA (2018-2025), but impairment-related work expenses survive

### What Does NOT Create an NOL
- Capital losses in excess of capital gains (limited to $3,000/year -- this limit applies BEFORE NOL computation)
- Personal deductions (standard deduction or itemized deductions) in excess of nonbusiness income
- NOL deductions from prior years
- Section 199A QBI deduction

## NOL Computation -- Form 1045, Schedule A

Computing the actual NOL is more complex than simply looking at the negative number on Form 1040. Several modifications are required:

### Modifications to Taxable Income

Start with the negative taxable income figure, then make these adjustments:

1. **Remove the NOL deduction itself**: if you're computing a current-year NOL, exclude any NOL carryforward deductions used in the current year
2. **Remove the Section 199A QBI deduction**: QBI deduction does not factor into the NOL computation
3. **Capital losses**: limited to capital gains (the $3,000 excess capital loss deduction is added back for NOL purposes)
4. **Nonbusiness deductions**: limited to nonbusiness income
   - Personal deductions (standard deduction, itemized deductions except for casualty losses) can only offset nonbusiness income (wages, interest, dividends, capital gains)
   - If nonbusiness deductions exceed nonbusiness income: the excess is added back
5. **Personal exemption**: add back (largely irrelevant 2018-2025 since personal exemption is $0, but relevant for pre-2018 NOLs still being tracked)
6. **Domestic production activities deduction**: add back (Section 199 -- repealed by TCJA but relevant for pre-2018 NOLs)

### Simplified NOL Computation Framework

```
Step 1: Start with negative taxable income from Form 1040
Step 2: Add back NOL deduction from prior years (if any used this year)
Step 3: Add back QBI deduction (Section 199A)
Step 4: Add back excess nonbusiness deductions over nonbusiness income
Step 5: Add back excess capital loss deduction (amount over $3,000 limit
         is already limited, but verify capital losses don't exceed
         capital gains for NOL purposes)
Step 6: Result = Net Operating Loss for the year
```

### Worked Example: Computing the NOL

```
Taxpayer (single) has:
  Schedule C loss:           ($120,000)
  W-2 wages:                  $40,000
  Interest income:             $2,000
  Standard deduction:        ($15,750)
  QBI deduction:                  $0  (no QBI because loss year)

Form 1040 taxable income:    ($93,750)

NOL Computation:
  Start with:                ($93,000)
  Add back QBI deduction:         $0
  Add back excess nonbusiness deductions:
    Nonbusiness income = $40,000 + $2,000 = $42,000
    Nonbusiness deductions = $15,750 (standard deduction)
    Excess = $0 ($15,750 < $42,000, so no add-back)

  NOL = ($93,750)

  Note: If the standard deduction had exceeded nonbusiness
  income, we would add back the excess.

Alternative scenario -- no W-2 income:
  Schedule C loss:           ($120,000)
  Interest income:             $2,000
  Standard deduction:        ($15,750)

  Taxable income:           ($133,750)

  NOL Computation:
    Start with:             ($133,000)
    Add back excess nonbusiness deductions:
      Nonbusiness income = $2,000
      Nonbusiness deductions = $15,750
      Excess = $13,750 (add back)
    NOL = ($133,750) + $13,750 = ($120,000)

  The NOL equals the Schedule C loss -- the standard deduction
  cannot create or increase the NOL beyond the business loss.
```

## Section 461(l) -- Excess Business Loss Limitation

### The Rule (Applies to Non-Corporate Taxpayers)
- Effective for tax years 2021-2028 (extended by various legislation)
- Business losses are limited to a threshold amount:
  - **2025**: $305,000 (single) / $610,000 (MFJ) -- indexed for inflation (verify current amounts)
- Losses exceeding the threshold become an NOL carryforward (treated as a deduction attributable to a trade or business in the next year)

### How It Works

```
Step 1: Calculate total business income and total business losses
  (aggregate all Schedule C, partnerships, S-Corps, farms)

Step 2: Net business income/loss = total business income - total business losses

Step 3: If net business LOSS exceeds the threshold:
  Excess = Net business loss - threshold amount
  The excess is NOT deductible in the current year
  Instead, it becomes an NOL carryforward

Step 4: The taxpayer can deduct business losses UP TO the threshold
  against any income (business or nonbusiness)
```

### Interaction with Other Limitations
- Section 461(l) applies AFTER:
  - Basis limitations (Section 704(d) for partnerships, Section 1366(d) for S-Corps)
  - At-risk limitations (Section 465)
  - Passive activity limitations (Section 469)
- Losses that survive basis, at-risk, and passive activity rules then face the Section 461(l) limitation
- Any excess business loss under 461(l) becomes an NOL carryforward

### Worked Example

```
MFJ taxpayer, 2025:
  Schedule C income:         $100,000
  S-Corp K-1 loss:          ($900,000)  (passed basis/at-risk/passive tests)

  Net business loss: ($900,000) + $100,000 = ($800,000)
  Threshold (MFJ 2025): $610,000

  Deductible business loss: $610,000
  Excess business loss: $800,000 - $610,000 = $190,000

  The $190,000 excess becomes an NOL carryforward to 2026
  (treated as a business deduction in 2026, subject to 80% limitation)

  In 2025: the $610,000 business loss offsets all other income
  (wages, investment income, etc.)
```

## Farming Exception -- Section 172(b)(1)(B)

### 2-Year Carryback for Farm NOLs
- NOLs from farming businesses can be carried back **2 years**
- This is the only remaining general NOL carryback provision
- The farming NOL is NOT subject to the 80% limitation when carried back (it can offset 100% of prior-year income)
- Election: can elect to waive the carryback and only carry forward (but why would you? -- the carryback gives an immediate refund)

### What Qualifies as a Farming Loss
- Losses from the trade or business of farming (Schedule F)
- Includes: crop losses, livestock losses, farm operating losses
- Does NOT include: losses from processing or marketing activities (unless directly part of the farming operation)

### How to Claim
- File **Form 1045** (Application for Tentative Refund) within 12 months of the close of the NOL year for a quick refund
- Or file **Form 1040-X** for each carryback year
- Form 1045 is faster (IRS must process within 90 days)

## Interaction with QBI Loss

### Separate Tracking
- NOL carryforward and QBI loss carryforward are **separate items** -- they are tracked independently
- A QBI loss in one year carries forward as a **QBI carryover loss** to the next year and reduces QBI in the next year (reducing the Section 199A deduction)
- An NOL carryforward reduces taxable income but does NOT directly affect QBI computation

### The Ordering
1. Current-year QBI is computed first (net income or loss from qualified businesses)
2. If current-year QBI is a loss: carries forward as a QBI loss (reduces future QBI)
3. If current-year QBI is income: the Section 199A deduction is computed (20% of QBI, subject to limitations)
4. NOL from prior years reduces taxable income (but NOT QBI itself)
5. QBI loss carryforward reduces current-year QBI before computing the Section 199A deduction

### Why This Matters
- A taxpayer with a prior-year QBI loss AND a prior-year NOL has BOTH reducing their current-year numbers
- The QBI loss reduces the QBI available for the 199A deduction
- The NOL reduces taxable income (the other component of the 199A deduction limitation)
- Track both separately on the workpapers

## Interaction with Passive Activity Loss

### Ordering of Limitations
Passive losses are limited BEFORE the NOL computation:

```
1. Basis limitation (partnerships/S-Corps)
2. At-risk limitation (Section 465)
3. Passive activity limitation (Section 469)
   -- only losses that PASS the passive activity rules flow to the NOL computation
4. Excess business loss limitation (Section 461(l))
5. NOL computation
```

- Suspended passive losses do NOT contribute to the NOL
- Only losses that are currently deductible (after surviving all limitation layers) can create an NOL
- Example: $200,000 rental loss, $25,000 active participation exception applies, remaining $175,000 suspended. Only the $25,000 flows through to potentially contribute to the NOL.

## NOL Application Ordering

### When Using NOL Carryforwards
- Apply NOLs from the **earliest year first** (FIFO ordering)
- Pre-2018 NOLs: applied first, can offset 100% of taxable income
- Post-2017 NOLs: applied after pre-2018 NOLs, subject to 80% limitation
- Within the same vintage: applied in chronological order

### Interaction with Other Deductions
- NOL deduction is taken AFTER computing AGI but as part of taxable income
- It does NOT affect AGI (unlike above-the-line deductions)
- This means NOL usage does NOT affect AGI-dependent items (medical expense 7.5% floor, miscellaneous deductions, etc.)
- However, NOL does reduce taxable income, which affects the tax computation

## State NOL Rules

### Key Differences from Federal
- Many states have **different carryforward periods** (some limit to 10-20 years)
- Some states have different **percentage limitations** (some use 80%, some use 100%, some use lower percentages)
- Some states do NOT conform to federal NOL rules at all (compute state NOL independently)
- **California**: 2024 legislation (check current status) may limit or suspend NOL deductions for large taxpayers
- **New York**: generally follows federal with modifications
- **New Jersey**: has historically suspended NOL deductions during budget crises
- **Illinois**: follows federal 80% limitation

### State NOL Must Be Tracked Separately
- Federal NOL and state NOL can differ because of state-specific income additions and subtractions
- Example: if a state does not conform to bonus depreciation, the state NOL will be different from federal
- Maintain separate NOL schedules for each state

## Strategic Use of NOL

### Don't Waste NOL in Low-Income Years
- If income is already low (e.g., in the 10% or 12% bracket): the NOL deduction saves only 10-12 cents per dollar
- Consider whether other deductions can reduce tax first (standard deduction, itemized deductions, IRA contributions)
- The NOL carries forward indefinitely -- saving it for a high-income year saves 22-37 cents per dollar

### Timing Income to Maximize NOL Benefit
- If you have a large NOL: consider accelerating income into the current year (exercise stock options, take retirement distributions, trigger capital gains)
- The NOL will absorb 80% of the income, effectively taxing only 20%
- This is particularly powerful when transitioning from a loss business to a profitable one

### Roth Conversion with NOL
- Large NOL + Roth conversion = convert traditional IRA to Roth while the NOL absorbs the income
- 80% of the conversion is offset by the NOL; only 20% is taxable
- Effectively converts at a fraction of the normal tax cost

## Comprehensive Worked Example

```
2024: Sarah's Schedule C has a net loss of ($80,000)
  W-2 wages: $30,000
  Standard deduction: ($15,750)

  Taxable income: $30,000 - $80,000 - $15,750 = ($65,750)

  NOL Computation:
    Start: ($65,000)
    Add back excess nonbusiness deductions:
      Nonbusiness income: $30,000
      Standard deduction: $15,750
      Excess: $0 ($15,750 < $30,000)
    NOL = $65,750

  (Note: not the full $80,000 business loss -- the $30,000
   of wages already absorbed $30,000 of the loss, and the
   standard deduction used another $15,750 of nonbusiness income)

   Actually, let's recalculate properly:
   Business income/loss: ($80,000)
   Nonbusiness income: $30,000
   Nonbusiness deductions: $15,750

   Modified taxable income for NOL:
   ($80,000) + $30,000 = ($50,000) business portion
   $30,000 - $15,750 = $14,250 nonbusiness portion

   The standard deduction uses $15,750 of the $30,000 nonbusiness income
   Remaining nonbusiness income: $14,250
   This absorbs $14,250 of the business loss
   NOL = $80,000 - $14,250 = $65,750

   Wait -- the simplest way:
   NOL = the negative taxable income + any nonbusiness deductions
   that exceeded nonbusiness income
   = $65,750 + $0 = $65,750 ✓

2025: Sarah's Schedule C has net income of $50,000
  W-2 wages: $40,000
  Standard deduction: ($15,750)
  NOL carryforward: $65,750

  Taxable income before NOL: $50,000 + $40,000 - $15,750 = $74,250
  NOL deduction (80% limit): $74,250 x 80% = $59,400
  But NOL available is only $65,750, so deduction = $59,400

  Taxable income after NOL: $74,250 - $59,400 = $14,850
  Remaining NOL carryforward: $65,750 - $59,400 = $6,350

  Tax on $14,850 (single): approximately $1,544
  Without the NOL: tax on $74,250 would be approximately $11,249
  NOL saved: ~$9,705 in taxes

2026: Sarah deploys remaining $5,000 NOL
  Taxable income before NOL: $80,000
  NOL deduction: min($5,000, $80,000 x 80%) = $5,000
  NOL fully used up.
```

## Required Forms

| Form | Purpose |
|------|---------|
| Form 1045 | Application for Tentative Refund (carryback -- farming only) |
| Form 1045 Schedule A | NOL computation worksheet |
| Form 1040-X | Amended return for carryback claims |
| Form 1040, Line 8 | NOL deduction (via Schedule 1) |
| Schedule 1, Line 8a | NOL deduction entry |

## Common Mistakes

1. **Not computing the NOL correctly** -- using the raw negative taxable income instead of applying the modifications (especially the nonbusiness deduction limitation)
2. **Forgetting to carry forward** -- NOLs from prior years must be tracked and applied; they don't appear automatically on future returns
3. **Applying the 80% limit to pre-2018 NOLs** -- pre-2018 NOLs can offset 100% of income
4. **Not tracking state NOL separately** -- state and federal NOL amounts often differ
5. **Wasting NOL in low-income years** -- consider whether the NOL provides meaningful benefit in a year when income is already minimal
6. **Confusing NOL with excess business loss** -- Section 461(l) excess business loss becomes an NOL, but the computation is different
7. **Double-counting passive losses** -- suspended passive losses do NOT contribute to the NOL; only currently deductible losses count
8. **Missing the farming carryback** -- farm NOLs can be carried back 2 years for an immediate refund
