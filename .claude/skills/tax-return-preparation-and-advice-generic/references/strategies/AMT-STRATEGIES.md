# AMT STRATEGIES — Alternative Minimum Tax Planning

## Overview

The Alternative Minimum Tax (ss55-59) operates as a parallel tax system designed to ensure that taxpayers with significant deductions or preference items pay at least a minimum amount of tax. While the TCJA dramatically reduced the number of AMT-affected taxpayers (from ~5M to ~200K annually) by raising exemptions and capping SALT, the AMT remains a critical planning consideration for three groups: ISO exercisers, high-income taxpayers in high-SALT states, and holders of private activity bonds.

---

## AMT MECHANICS

### The Calculation

1. Start with regular taxable income
2. ADD BACK AMT preference items and adjustments
3. Subtract AMT exemption amount
4. Apply AMT tax rates (26% / 28%)
5. Result = Tentative Minimum Tax (TMT)
6. If TMT > regular tax liability: pay the DIFFERENCE as AMT (in addition to regular tax)

### AMT Rates (2025)

| AMTI (Alternative Minimum Taxable Income) | Rate |
|---|---|
| Up to $239,100 of AMTI above the exemption ($119,550 if MFS) | 26% |
| Above $239,100 of AMTI above the exemption ($119,550 if MFS) | 28% |

Note: Long-term capital gains and qualified dividends are taxed at regular capital gains rates (0%/15%/20%) for AMT purposes — they do NOT get hit with the 26%/28% rate.

### AMT Exemption Amounts (2025)

| Filing Status | Exemption | Phase-out Begins | Phase-out Ends |
|---|---|---|---|
| MFJ | $137,000 | $1,252,700 | $1,800,700 |
| Single / HoH | $88,100 | $626,350 | $978,750 |
| MFS | $68,500 | $626,350 | $900,350 |

The exemption phases out at 25 cents per dollar of AMTI above the threshold. At the phase-out range, the effective marginal AMT rate is 32.5% (26% + 25% x 26%) or 35% (28% + 25% x 28%).

---

## AMT PREFERENCE ITEMS AND ADJUSTMENTS

### Major Add-Backs

| Item | Regular Tax Treatment | AMT Adjustment | IRC Section |
|---|---|---|---|
| **State and local tax (SALT) deduction** | Schedule A deduction generally capped at $40,000 ($20,000 MFS) for 2025, subject to MAGI-based reduction | ADD BACK the allowed deduction | ss56(b)(1)(A) |
| **ISO exercise spread** | Not taxed at exercise | ADD BACK (FMV - strike price) x shares | ss56(b)(3) |
| **Private activity bond interest** | Tax-exempt | ADD BACK as income | ss57(a)(5) |
| **Standard deduction** | Reduces taxable income | ADD BACK (if used) | ss56(b)(1)(E) |
| **Medical expenses** | Deductible > 7.5% AGI | Deductible > 7.5% AGI (same since TCJA) | ss56(b)(1)(B) |
| **Depreciation (pre-TCJA property)** | MACRS (200% DB, 150% DB) | ADS or 150% DB for some property | ss56(a)(1) |
| **Net operating loss** | Full deduction | Limited to 90% of AMTI | ss56(d) |
| **Tax-exempt interest on certain bonds** | Excluded from income | ADD BACK for private activity bonds | ss57(a)(5) |

### SALT Is Still Important, But the Exemption Usually Dominates

For 2025, the personal Schedule A SALT deduction is generally capped at $40,000 ($20,000 MFS), subject to a MAGI-based reduction that cannot reduce the cap below $10,000 ($5,000 MFS). AMT adds back whatever SALT deduction was actually allowed on Schedule A. For taxpayers in high-SALT states (CA, NY, NJ, CT) who itemize:
- Regular tax SALT deduction may be as high as $40,000
- AMT add-back equals that allowed deduction
- Gross AMT sensitivity can therefore be materially larger than under the old $10,000-cap regime

However, the higher 2025 AMT exemption still shields many taxpayers. In practice, post-2025 AMT remains driven primarily by ISO exercise spreads and other large preference items rather than SALT alone.

---

## ISO EXERCISE PLANNING — THE PRIMARY AMT BATTLEGROUND

### The ISO AMT Trap

When an employee exercises Incentive Stock Options (ISOs), there is NO regular tax at exercise (ss422). However, the "bargain element" (FMV at exercise minus strike price) is an AMT preference item. For employees at fast-growing tech companies, this spread can be enormous.

### Calculating Maximum ISO Exercise Without AMT

**The goal**: Determine how many shares can be exercised in a given year without the AMT exceeding the regular tax.

**Formula**:
1. Calculate regular tax liability (known from other income)
2. Calculate AMT exemption remaining after other AMTI
3. Available AMT "headroom" = Regular tax - (26% x (AMTI excluding ISO + ISO spread - AMT exemption))
4. Solve for the ISO spread that makes TMT = regular tax
5. Divide by per-share spread to get maximum shares

### Worked Example — ISO Exercise Planning

**Facts**:
- Employee, Single filer
- W-2 income: $300,000
- ISO: 50,000 shares, $5 strike price, current FMV $25/share
- Per-share spread: $20
- Total potential spread: $1,000,000

**Regular tax calculation**:
- Taxable income: ~$284,250 (after $15,750 standard deduction)
- Regular tax: ~$69,000

**AMT calculation if ALL 50,000 shares exercised**:
- AMTI: $284,250 taxable income + $15,750 standard deduction add-back + $1,000,000 ISO spread = **$1,300,000**
- AMT exemption: fully phased out at this AMTI level
- TMT: $239,100 x 26% + ($1,300,000 - $239,100) x 28% = $62,166 + $297,052 = **$359,218**
- AMT owed: $359,218 - $69,239 = **~$289,979**
- Cash needed: $250,000 (exercise cost) + ~$289,979 (AMT) = **~$539,979** — for stock that may decline

**Optimal exercise**: Find the number of shares where TMT = regular tax:
- Base AMTI before ISO spread: ~$300,000
- Base TMT before ISO spread: ~$55,094
- Remaining TMT headroom before matching regular tax: ~$14,145
- ISO spread allowed while still in the 26% band: ~$54,400
- Shares to exercise: ~$54,400 / $20 = **~2,720 shares** — with effectively ZERO incremental AMT

**Multi-year strategy**: Exercise ~2,720 shares per year over many years? Usually still impractical if the option has a 10-year term. Better: exercise enough each year to manage AMT deliberately and recover the resulting credit within a reasonable 2-3 year window.

### The ISO Tax Trap Scenario

The devastating scenario: Employee exercises ISOs when stock is at $100, generating $4.75M in AMT spread. Pays ~$1.3M in AMT. Stock drops to $10 before year-end (or before the employee can sell in the next year after the disqualifying disposition holding period). The AMT is owed on phantom income that no longer exists.

**Mitigation strategies**:
1. **Same-day sale (disqualifying disposition)**: Sell ISO shares in the same year as exercise. The spread becomes ordinary income (not AMT preference). The AMT problem disappears, but you lose the ISO capital gains benefit.
2. **Partial exercise**: Exercise only enough shares to stay within AMT headroom
3. **Section 83(b) election**: Not applicable to ISOs (ISOs have their own rules under ss422)
4. **Sell in January**: If exercised in December, selling in January of the following year creates a disqualifying disposition — but the AMT for the exercise year has already been triggered. This does NOT help.

---

## AMT CREDIT (ss53) — RECOVERING YOUR AMT

### How the Credit Works

AMT paid due to "timing" differences (items that will eventually be taxed under regular tax, like ISO spreads) generates an AMT credit that can be carried forward indefinitely.

**AMT credit = AMT paid in prior years (attributable to deferral preferences)**

The credit is usable in any future year where the regular tax exceeds the tentative minimum tax:
- **Credit allowed** = Regular tax - TMT (for the credit year)
- If regular tax is $80,000 and TMT is $50,000: up to $30,000 of AMT credit can be used

### Deferral vs Exclusion Preferences

| Deferral Preferences (Generate AMT Credit) | Exclusion Preferences (Do NOT Generate Credit) |
|---|---|
| ISO exercise spread | State/local tax deduction |
| Depreciation timing differences | Private activity bond interest |
| Installment sale adjustments | Standard deduction |
| Long-term contract adjustments | Percentage depletion |

The ISO spread is a deferral preference because when the stock is eventually sold, the gain is recognized for regular tax (but not AMT, since it was already included). This timing difference generates the credit.

### Worked Example — AMT Credit Recovery

**Year 1**: Exercise ISOs, pay $100,000 in AMT (all from ISO spread — deferral preference)
- AMT credit generated: $100,000

**Year 2**: Sell the ISO shares (disqualifying disposition or after holding period)
- Regular tax on the sale: High (ordinary income on spread portion)
- TMT: Lower (ISO spread was already included in AMTI in Year 1)
- Regular tax exceeds TMT by $60,000
- AMT credit used: $60,000
- Remaining credit: $40,000

**Year 3**: Normal income year
- Regular tax exceeds TMT by $40,000
- AMT credit used: $40,000
- Remaining credit: $0 — fully recovered

### Recovery Timeline

For large ISO exercises, full AMT credit recovery typically takes 2-5 years. The recovery is faster when:
- The stock is sold (creates a regular tax liability that was already counted for AMT)
- Other income is high (more regular tax headroom above TMT)
- SALT deductions are low (reduces AMTI, lowering TMT)

---

## TIMING STRATEGIES

### Income Shifting Between Years

**Accelerate income into the current year** if you are NOT in AMT this year but expect to be next year — income taxed at regular rates now is cheaper than AMT rates later.

**Defer income to next year** if you ARE in AMT this year but won't be next year — income deferred avoids the AMT surcharge.

### SALT Timing (Still Limited Utility for Most Filers)

Pre-TCJA, prepaying state taxes in December was a classic AMT trigger. For 2025, the personal SALT deduction cap is generally much higher than it was under TCJA, but AMT still adds back the allowed deduction and the exemption often determines the actual outcome. However:
- **PTET (Pass-Through Entity Tax)**: PTET payments are generally deducted at the entity level rather than as a personal Schedule A SALT item, so they bypass the personal SALT cap and usually do not create the same AMT preference problem.
- **Charitable contributions**: Large charitable donations in a single year can push a taxpayer into AMT by reducing regular tax below TMT. Consider spreading large gifts or using a Donor Advised Fund.

### Depreciation Method Selection

For property placed in service where depreciation is an AMT preference:
- Electing ADS (Alternative Depreciation System) for regular tax eliminates the AMT depreciation adjustment entirely
- Trade-off: slower depreciation for regular tax, but no AMT add-back
- Generally not worthwhile unless the taxpayer is in AMT for multiple years and the depreciation amount is large

Note: Under TCJA, most tangible personal property placed in service after 2017 uses 200% DB for both regular tax and AMT (the adjustment was largely eliminated). The depreciation AMT preference primarily affects pre-2018 property and certain real property.

---

## PRIVATE ACTIVITY BONDS AND AMT

### The Issue

Interest on private activity bonds (issued for purposes like hospitals, airports, housing, and industrial development) is tax-exempt for regular tax purposes but IS an AMT preference item under ss57(a)(5).

### Impact on Municipal Bond Selection

For AMT-affected investors:
- **General obligation bonds**: Interest is tax-exempt for BOTH regular and AMT — no AMT issue
- **Essential function bonds**: Same — no AMT issue
- **Private activity bonds**: Interest is an AMT preference item — may trigger or increase AMT

**Planning**: Check the bond's CUSIP or prospectus for AMT status. If you are at risk of AMT, avoid private activity bonds or ensure the yield premium over non-AMT munis (typically 10-30 bps) compensates for the AMT cost.

### Quantifying the PAB AMT Cost

For a taxpayer in the 28% AMT bracket holding $500,000 of private activity bonds yielding 4%:
- Annual interest: $20,000
- AMT on the interest: $20,000 x 28% = $5,600
- After-tax yield: ($20,000 - $5,600) / $500,000 = 2.88% — NOT the 4% tax-free yield expected
- If a non-AMT muni yields 3.5%: the non-AMT muni is better after considering AMT

---

## STATE AMT

### States with Their Own AMT

| State | AMT Rate | Exemption | Notes |
|---|---|---|---|
| California | 7% | $95,222 (MFJ) | Very different from federal — uses CA adjustments |
| Colorado | 3.5% (minimum) | N/A | Alternative minimum tax based on federal AMTI |
| Connecticut | 19% of CT tax | N/A | AMT is 19% of regular CT tax liability |
| Iowa | Repealed (2023+) | N/A | No longer applicable |
| Minnesota | 6.75% | $129,580 (MFJ) | Based on MN-specific preferences |
| Wisconsin | Varies | Varies | Based on WI-specific adjustments |

### California AMT — Double Exposure

California has its own AMT that uses California-specific adjustments. An employee exercising ISOs in California faces:
- Federal AMT: Up to 28% on the spread
- California AMT: Up to 7% on the spread (with CA adjustments)
- **Combined AMT rate: up to 35%** on the ISO spread

For a $1M ISO spread in California:
- Federal AMT: ~$280,000
- California AMT: ~$70,000
- **Total AMT: ~$350,000** — on stock that may decline before it can be sold

This makes California ISO exercise planning especially critical. Many CA employees limit annual exercises to very small amounts or immediately do disqualifying dispositions.

---

## AMT PLANNING DECISION TREE

### Step 1: Determine AMT Exposure

Calculate regular tax and TMT for the current year:
- If regular tax > TMT: NO AMT concern — can take deductions and preferences freely
- If TMT > regular tax: IN AMT — every additional preference dollar costs 26-28%

### Step 2: Identify Controllable Preferences

| Controllable | Not Controllable |
|---|---|
| ISO exercise timing and amount | W-2 income amount |
| Private activity bond selection | Prior-year depreciation methods |
| Charitable donation timing | State income tax owed |
| SALT prepayment decisions | Existing NOL carryforwards |
| Depreciation method elections | Prior AMT credit carryforwards |

### Step 3: Optimize

**If NOT in AMT**:
- Exercise ISOs up to the headroom (TMT < regular tax gap)
- Hold private activity bonds if yield is attractive
- Take standard deduction or itemize — whichever gives better regular tax result

**If IN AMT**:
- Limit ISO exercises to generate only as much AMT as can be recovered in 2-3 years via credit
- Avoid additional private activity bond purchases
- Consider disqualifying dispositions of ISOs (converts AMT preference to regular ordinary income)
- PTET for business owners (circumvents SALT AMT interaction)

### Step 4: Track AMT Credit

Maintain a running tally of:
- AMT credit carryforward balance
- Source of credit (ISO, depreciation, etc.)
- Expected recovery timeline
- Impact of planned future income events on credit recovery

---

## WORKED EXAMPLE — COMPREHENSIVE AMT PLANNING

**Taxpayer**: Single, software engineer in San Francisco
- W-2: $350,000
- ISOs: 20,000 shares at $10 strike, FMV $50 (spread = $40/share, total = $800,000)
- Private activity bonds: $200,000 portfolio, 3.8% yield ($7,600/year)
- SALT: $35,000 state income tax + $12,000 property tax = $47,000 (generally capped at $40,000 for 2025)
- Charitable: $15,000

**Without AMT planning (exercise all ISOs)**:
- Regular taxable income: ~$325,000
- AMTI: $325,000 + $800,000 (ISO) + $40,000 (SALT add-back) + $7,600 (PAB interest) = $1,172,600
- AMT exemption: fully phased out at this AMTI level
- TMT: $239,100 x 26% + ($1,172,600 - $239,100) x 28% = $62,166 + $261,380 = **$323,546**
- Regular tax: ~$83,500
- AMT: ~$323,546 - ~$83,500 = **~$240,045**
- Plus CA AMT: ~$56,000
- **Total AMT: ~$301,000** on top of regular tax

**With AMT planning (exercise 2,000 shares only)**:
- ISO spread: 2,000 x $40 = $80,000
- AMTI: $325,000 + $80,000 + $40,000 + $7,600 = $452,600
- AMT exemption: $88,100 (no phase-out, below the threshold)
- AMTI after exemption: $452,600 - $88,100 = $364,500
- TMT: $239,100 x 26% + ($364,500 - $239,100) x 28% = $62,166 + $35,112 = **$97,278**
- Regular tax: ~$83,500
- AMT: ~$97,278 - ~$83,500 = **~$13,777**
- AMT credit generated: ~$18,000 (deferral portion from ISOs)
- Credit recovery: Expected within 1-2 years
- Net long-term cost: **minimal** (credit recovered, small time-value cost)

**Federal savings from AMT planning: roughly $226,000**, plus substantial California AMT savings, by deferring 18,000 shares of ISO exercise to future years

---

## KEY TAKEAWAYS

1. **Post-TCJA, the AMT primarily affects ISO exercisers** — the raised exemption shields most other taxpayers
2. **Calculate ISO exercise headroom annually** — exercise ONLY up to the point where TMT equals regular tax
3. **AMT credit from ISO exercises is recoverable** — but recovery takes 2-5 years. Do not generate more AMT than you can absorb.
4. **Disqualifying disposition is the escape valve** — converts AMT preference to regular ordinary income
5. **California doubles the AMT pain** — state AMT of 7% on top of federal 28%
6. **Private activity bonds** have a hidden AMT cost — check before buying
7. **PTET completely avoids** the SALT/AMT interaction for business owners
8. **The AMT credit is an interest-free loan to the IRS** — minimize the loan amount
9. **Run AMT projections by October** of each year — you need time to act before December 31
10. **Multi-year modeling is essential** — a decision that saves AMT this year may cost more next year
