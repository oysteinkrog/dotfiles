# Software Engineer -- Tax Reference Guide (TY 2025)

## 1. Overview

Software engineers span the spectrum from W-2 employees at large tech companies to independent
contractors and startup founders. The profession's tax landscape is dominated by equity
compensation (RSUs, ISOs, ESPP), high W-2 income in expensive metro areas, and increasing
remote-work home office considerations. Many engineers also earn side income from open-source
sponsorships, SaaS products, freelance consulting, or content creation.

## 2. Common Income Types

- **W-2 salary and bonuses** -- The primary income source for most engineers. Supplemental wages
  (bonuses, RSU vesting) are often withheld at the flat 37% federal supplemental rate.
- **RSUs (Restricted Stock Units)** -- Taxed as ordinary income at vesting (FMV on vest date).
  Reported on W-2 Box 1. Subsequent sale creates capital gain/loss from vest-date basis.
- **ISOs (Incentive Stock Options)** -- No regular tax at exercise if held. AMT adjustment equals
  spread (FMV minus exercise price) at exercise. Qualifying disposition (hold 2 years from
  grant, 1 year from exercise) converts to long-term capital gain.
- **ESPP (Employee Stock Purchase Plan)** -- Discount up to 15%. Qualifying disposition: discount
  portion is ordinary income; remainder is capital gain. Disqualifying disposition: entire
  spread at purchase is ordinary income.
- **1099-NEC / 1099-K** -- Side consulting, freelance projects, SaaS revenue, sponsorships.
- **1099-MISC royalties** -- Open-source sponsorships, book royalties, course revenue.
- **Cryptocurrency** -- Mining, staking rewards, airdrops, DeFi yield (all taxable events).

## 3. RSU Basis Reconciliation -- Critical Detail

### The Problem

When RSUs vest, the income appears on the W-2 (Box 1). When the shares are later sold, the
broker issues a 1099-B. **The broker's 1099-B frequently shows $0 cost basis** (or reports basis
in a supplemental document, not on the 1099-B itself). If the taxpayer reports the sale using
the $0 basis from the 1099-B without adjusting, they are **taxed twice** on the same income:
once as W-2 wages at vesting and again as capital gains at sale.

### How to Fix It

On **Form 8949**, use:
- **Column (a):** Description of property (e.g., "100 shares AAPL")
- **Column (b):** Date acquired (vest date)
- **Column (c):** Date sold
- **Column (d):** Proceeds (from 1099-B)
- **Column (e):** Cost basis -- **USE THE ADJUSTED BASIS** (FMV at vest date x shares), NOT the $0 from the 1099-B
- **Column (f):** Code "B" (basis was NOT reported to the IRS) -- this tells the IRS you are reporting a different basis than what appears on the 1099-B
- **Column (g):** Adjustment amount -- the difference between the correct basis and the reported basis

### Worked Example

```
100 RSUs vest on March 15, 2025 at $200/share
W-2 income: 100 x $200 = $20,000 (already taxed as ordinary income)

Sell 100 shares on August 20, 2025 at $220/share
1099-B shows: Proceeds = $22,000, Cost basis = $0 (or "see supplemental")

WRONG (double taxation):
  Proceeds: $22,000
  Basis: $0
  Reported gain: $22,000 <-- WRONG, already paid tax on $20,000

CORRECT (Form 8949 adjustment):
  Proceeds: $22,000
  Adjusted basis: $20,000 (FMV at vest date)
  Column (e) adjustment: +$20,000
  Actual gain: $2,000 (short-term, since held < 1 year from vest date)
```

### Where to Find the Correct Basis

- **Supplemental information** on the 1099-B (often a separate page or section labeled "For informational purposes")
- **Equity compensation portal** (E*Trade, Schwab, Morgan Stanley at Work, Fidelity Stock Plan Services)
- **W-2 breakdown:** Some employers provide a separate equity compensation summary showing vest dates, shares, and FMV
- **Calculate manually:** Number of shares vested x FMV on vest date = correct basis

### ESPP Basis Reconciliation

Same problem exists for ESPP shares. The broker 1099-B typically shows the actual purchase price as basis, but the W-2 includes the discount as ordinary income. If this is not reconciled:

**Qualifying disposition (held >2 years from offering, >1 year from purchase):**
- Ordinary income: lesser of (1) actual discount at purchase or (2) gain at sale
- Capital gain: remaining gain above the ordinary income portion
- Basis = purchase price + ordinary income recognized

**Disqualifying disposition (sold before holding periods met):**
- Ordinary income: FMV at purchase minus purchase price (the full spread, even if stock declined)
- This ordinary income is on the W-2
- Capital gain/loss: sale price minus (purchase price + ordinary income)

---

## 4. ISO Exercise Strategy by AMT Bracket

### The AMT Trap

When ISOs are exercised and the stock is held (not sold same day), the spread (FMV - exercise
price) is an AMT adjustment on Form 6251. This does not affect regular tax, but if the AMT
liability exceeds regular tax, the taxpayer owes the difference as AMT.

### Strategic Exercise Planning

The goal: exercise the maximum number of ISOs per year WITHOUT triggering AMT (or triggering
only a small, manageable AMT amount).

**Step-by-step calculation:**
1. Calculate regular tax liability (without any ISO exercises)
2. Calculate AMT exemption amount ($88,100 single / $137,000 MFJ for 2025)
3. Determine AMT exemption phase-out (begins at AMTI of $609,350 single / $1,218,700 MFJ)
4. Calculate AMTI without ISO exercises (regular taxable income + add-back items)
5. Determine "AMT cushion" = the amount of additional AMTI before AMT exceeds regular tax
6. Divide the AMT cushion by the per-share ISO spread to get maximum shares to exercise

**Worked example:**
```
Single filer, $200,000 W-2 income, no other adjustments
Regular tax (approx): $42,000
AMTI without ISOs: $210,000 (assume same as taxable income)
AMT exemption: $88,100
AMT taxable: $210,000 - $88,100 = $121,900
AMT: $121,900 x 26% = $31,694
Regular tax exceeds AMT by: $42,000 - $31,694 = $10,306

AMT cushion: $10,306 / 26% = ~$39,638 of additional AMTI
ISO spread per share: $150 (FMV $200 - exercise price $50)
Max shares to exercise without AMT: $39,638 / $150 = ~264 shares

Exercise 264 ISOs: no AMT owed
Exercise 265+ ISOs: AMT begins to apply
```

### AMT Credit Recovery

If AMT is paid in Year 1 due to ISO exercises, the AMT amount becomes a **credit carryforward**
(Form 8801, Credit for Prior Year Minimum Tax). In future years when regular tax exceeds AMT
(typically after the ISO shares are sold), the credit reduces the regular tax liability.

**Key:** The AMT credit is recoverable -- it is not a permanent additional tax. It is timing. But
it can take several years to fully recover, and the credit does not earn interest.

### Section 83(i) Qualified Equity Grant Deferral

For employees of private companies (not publicly traded), IRC 83(i) allows deferral of tax on
equity compensation for up to 5 years after vesting. Requirements:
- The company must be a "eligible corporation" (not publicly traded)
- The equity must be "qualified stock" received in connection with services
- The election must be made within 30 days of the taxable event (vesting/exercise)
- The company must offer equity to at least 80% of US employees (with some exclusions for officers, 1% owners, etc.)
- The deferred amount is subject to income tax (including SE tax, if applicable) when the deferral period ends or upon certain triggering events (sale of stock, IPO, etc.)

**Practical use:** An engineer at a late-stage private startup receives RSUs that vest. The RSUs
are taxable at vesting, but the stock is illiquid (no public market). Under 83(i), the engineer
can defer the tax for up to 5 years, hoping the company goes public or is acquired, providing
liquidity to pay the tax.

---

## 5. ESPP Strategy -- Detailed

### How ESPP Works

- Employee contributes up to $25,000/year (measured by FMV at offering date, not purchase date)
- Purchase price: typically 85% of the LOWER of (FMV at offering date, FMV at purchase date)
- Offering period: usually 6 months or 24 months (with interim purchase dates)
- The 15% discount is the minimum guaranteed benefit (can be more if stock drops during offering)

### Tax Treatment by Disposition Type

**Qualifying Disposition (held >2 years from offering date AND >1 year from purchase date):**
```
Offering date FMV: $100
Purchase date FMV: $120
Purchase price: $85 (85% of $100 offering date FMV, since $100 < $120)
Sale price: $150

Ordinary income: lesser of:
  (a) Actual gain: $150 - $85 = $65
  (b) Offering date discount: $100 - $85 = $15
  Ordinary income = $15

Capital gain (long-term): $150 - $85 - $15 = $50
  (Or equivalently: $150 - $100 = $50)

Total tax: $15 at ordinary rates + $50 at LTCG rates
```

**Disqualifying Disposition (sold before both holding periods met):**
```
Same facts, but sold after 8 months (less than 1 year from purchase)

Ordinary income: FMV at purchase minus purchase price = $120 - $85 = $35
Capital gain (short-term): $150 - $120 = $30

Total tax: $35 at ordinary rates + $30 at STCG rates (ordinary)
```

### ESPP Strategy

- **Always participate** if the plan offers a discount -- even if you sell immediately, the 15% discount is guaranteed income
- **For qualifying disposition treatment:** Hold shares >2 years from offering AND >1 year from purchase
- **Risk management:** If the stock is volatile, selling immediately (disqualifying disposition) locks in the discount and eliminates stock price risk. The tax difference between qualifying and disqualifying dispositions is the difference between LTCG and ordinary rates on the discount portion.
- **Max contribution:** $25,000/year at offering date FMV. If the stock price is $100 at offering, you can purchase up to 250 shares ($25,000 / $100). At 15% discount, guaranteed profit = $3,750/year.

---

## 6. Startup Founder Tax Path

### The Optimal Sequence

**Step 1: 83(b) Election within 30 days of receiving restricted stock**
- File within 30 days of the stock grant (not vesting). This is an ABSOLUTE deadline -- no extensions, no late filing.
- Pay tax on the current (low) value of the stock. If the company is just starting (pre-revenue), the stock may be worth pennies.
- All future appreciation is capital gain (not ordinary income)
- If the stock never vests (forfeiture), the tax paid is lost (no refund)
- Send by certified mail to the IRS; keep a copy. Also provide a copy to the company.

**Step 2: Section 1202 QSBS (Qualified Small Business Stock)**
- Must be a C-Corporation (not S-Corp, LLC, or partnership)
- Stock must be acquired at original issuance (directly from the company, not secondary market)
- Corporation must have gross assets of $50M or less at time of issuance and immediately after
- Corporation must be an active business (not holding company, financial services, etc.)
- If held for 5+ years: **exclude up to $10M or 10x basis** from capital gains (100% exclusion for stock acquired after September 27, 2010)
- This is potentially the most valuable tax benefit available to founders

**Step 3: Section 1244 Small Business Stock (for potential loss)**
- If the startup fails, up to $50,000 ($100,000 MFJ) of loss on 1244 stock is treated as **ordinary loss** (not capital loss)
- Ordinary loss is deductible against ordinary income (no $3,000 annual capital loss limit)
- Requirements: stock must be issued for money or property (not services), corporation must have aggregate paid-in capital of $1M or less

**Step 4: Section 351 for IP Contribution**
- If the founder contributes intellectual property (code, patents, trade secrets) to the corporation in exchange for stock, IRC 351 allows the contribution to be non-taxable (no gain recognized) provided the contributor receives at least 80% control of the corporation
- This is how founders avoid immediate taxation when incorporating and transferring their work product

### Founder Equity Timeline

```
Day 0: Incorporate C-Corp
Day 1: Issue founder shares (e.g., 10M shares at $0.001/share = $10,000)
Day 1: File 83(b) election (tax: $10,000 x 37% = $3,700)
Day 1: Contribute IP under Section 351 (no tax)
Years 1-5: Build company, no tax on appreciation
Year 5+: Sell stock, exclude up to $10M under QSBS
         If $50M exit: $10M excluded, $40M at 20% LTCG = $8M tax
         Without QSBS: $50M at 20% LTCG = $10M tax
         With QSBS: savings = $2M

If startup fails:
  Section 1244 loss: $10,000 as ordinary loss (fully deductible against W-2 income)
```

---

## 7. Key Deductions

### W-2 Employees (limited post-TCJA)
- **State and local taxes (SALT)** -- Capped at $10,000 ($5,000 MFS). Critical in CA, NY. WA
  has no income tax but high property tax.
- **Mortgage interest** -- On up to $750,000 acquisition debt.
- **Charitable contributions** -- Stock donations of appreciated shares avoid capital gains tax.

### Self-Employed / Side Business (Schedule C)
- **Home office** -- Regular and exclusive use. Simplified method: $5/sq ft up to 300 sq ft ($1,500 max).
  Actual method: proportionate share of rent/mortgage interest, utilities, insurance, depreciation.
- **Equipment** -- Computers, monitors, peripherals, standing desks. Section 179 or bonus depreciation
  for items used >50% for business.
- **Software and subscriptions** -- IDE licenses, cloud hosting (AWS/GCP/Azure), SaaS tools, domains.
- **AI/ML infrastructure** -- GPU costs (local or cloud), cloud compute (AWS/GCP/Azure), API
  subscriptions (OpenAI, Anthropic, Google AI), AI coding tools (Cursor, GitHub Copilot, Tabnine,
  Codeium) -- 100% deductible on Schedule C if used for business.
- **Professional development** -- Conference registration, travel, online courses, books, certifications.
- **Internet and phone** -- Business-use percentage of home internet and cell phone.
- **Health insurance** -- Self-employed health insurance deduction (above-the-line) if no employer plan.

### Conference and Travel Deductions
- **Registration fees:** 100% deductible if conference is directly related to the business
- **Airfare:** 100% deductible (coach class; business/first class may be scrutinized)
- **Hotel:** 100% deductible for nights the conference is in session (plus reasonable travel days)
- **Meals during travel:** 50% deductible (the 100% restaurant exception expired after 2022)
- **Incidental expenses:** Tips, transportation to/from airport, internet fees -- 100% deductible
- **Must be directly related to business:** A JavaScript developer attending a JavaScript conference is clearly related. A JavaScript developer attending a real estate conference is not (unless they have a real estate business).

### Home Lab / Server Equipment
- **Section 179 immediate expensing:** Equipment used for business (servers, networking gear, UPS
  systems, NAS devices) can be fully expensed in the year of purchase under Section 179
- **Listed property rules:** If the equipment is used LESS than 100% for business, it is "listed
  property" subject to special rules. Must use MACRS depreciation (not Section 179) if business
  use is 50% or less. Must document business vs. personal use percentage.
- **Examples:** A home lab server used 80% for freelance development and 20% for personal media
  streaming: 80% of cost is deductible via Section 179. Must maintain a usage log.

### Open Source and Side Project Income

All income from side projects is self-employment income reported on Schedule C:
- **GitHub Sponsors:** 1099-K from GitHub (or payment processor) if over reporting threshold
- **App store revenue:** Apple/Google issue 1099-K for app sales
- **SaaS subscription income:** Stripe/PayPal issue 1099-K
- **Patreon/Ko-fi:** 1099-K from the platform
- **Book royalties and course revenue:** 1099-MISC (royalties) or 1099-NEC (if structured as service)

All subject to SE tax (15.3% on first $176,100, then 2.9% Medicare above that, plus 0.9%
Additional Medicare Tax above $200K single / $250K MFJ).

---

## 8. Recommended Entity Structure

- **Side income under ~$50K** -- Report on Schedule C as sole proprietor. Simple, low overhead.
- **Side income $50K-$100K+** -- Consider single-member LLC taxed as S-Corp. Pay yourself
  reasonable W-2 salary to save SE tax on distributions. Break-even typically around $40K-$60K
  net profit after accounting for additional payroll costs (~$2K-$3K/year for payroll service).
- **Startup founders** -- C-Corp for venture-funded startups (required for institutional investors,
  enables QSBS exclusion under IRC 1202). S-Corp for bootstrapped lifestyle businesses.
- **QSBS (IRC 1202)** -- Up to $10M or 10x basis exclusion on C-Corp stock held 5+ years.
  Extraordinary benefit for founders. Must be qualified small business (assets under $50M).

## 9. Remote Work Multi-State Complexity

### The Problem

A software engineer who lives in State A but works for an employer in State B may owe taxes to
BOTH states. The rules vary dramatically by state.

### Convenience of the Employer Rule

Several states tax nonresidents who work remotely if the remote work is for the employee's
"convenience" (not the employer's necessity):

| State | Rule |
|---|---|
| **NY** | Taxes nonresident remote workers unless the employer has a bona fide office and the employee works from the NY office regularly. The "convenience test" presumes the work is for the employee's convenience unless proven otherwise. |
| **PA** | Similar convenience rule for nonresidents working remotely for PA employers |
| **NE** | Taxes nonresidents who work remotely for NE employers |
| **AR** | Taxes nonresidents working remotely for AR employers |
| **CT** | Reciprocal agreement with NY -- if NY taxes the income, CT provides a credit |
| **DE** | Convenience rule for nonresidents |
| **MA** | During COVID, MA taxed nonresidents working remotely for MA employers (challenged in court, temporary rule extended) |
| **NJ** | Does NOT follow the convenience rule (NJ taxes based on physical presence only) |

### Practical Impact

```
Example: Engineer lives in NJ, works for NYC employer, works from home 4 days/week

NY claims: 100% of income taxable to NY (convenience rule -- remote work is for employee's convenience)
NJ claims: 100% of income taxable to NJ (resident state)

Result: Double taxation on 80% of income (the 4 days worked from NJ)
NJ provides a credit for taxes paid to NY, but only for income actually earned IN NY (1 day/week)
Net: Engineer pays NY tax on 100% + NJ tax on the 80% portion not credited

Potential annual extra tax on $250K salary: $8,000-$15,000+
```

### Strategies

- **Track days worked in each state meticulously** -- many states use a days-based allocation formula
- **Understand your employer's state presence** -- if the employer has an office in your state, different rules may apply
- **Consider relocation:** Moving to a state with no income tax (FL, TX, WA, NV) eliminates the problem
- **Request a state tax analysis** before accepting a remote position that crosses state lines

---

## 10. Retirement Plan Strategy

- **W-2 employees** -- Max 401(k) at $23,500 (2025). Mega backdoor Roth if plan allows
  after-tax contributions with in-plan conversion (total 415(c) limit $70,000).
  Backdoor Roth IRA: contribute to traditional IRA, convert to Roth (watch pro-rata rule).
- **Self-employed side income** -- Solo 401(k) allows employee ($23,500) + employer (25% of
  net SE income) contributions. Can shelter significant side income.
  Note: The $23,500 elective deferral is shared across ALL employers. If you max out at your
  W-2 job, you can only make employer (profit-sharing) contributions to the Solo 401(k).
- **High earners** -- Roth vs. traditional depends on expected future tax rates and state.
  Engineers in WA/TX (no state tax) may prefer traditional; those in CA/NY may prefer Roth
  if planning to relocate to lower-tax state.

## 11. Common Audit Triggers

- **Large RSU vesting** -- Mismatch between W-2 reported income and 1099-B cost basis.
  Brokers often report $0 basis on RSU sales; taxpayer must adjust to avoid double taxation.
- **Home office for W-2 employees** -- W-2 employees cannot deduct home office post-TCJA
  (2018-2025) even if fully remote. Only self-employed income qualifies.
- **Hobby vs. business** -- Side projects showing losses year after year invite scrutiny.
  Must demonstrate profit motive (3 of 5 years profitable is safe harbor, not requirement).
- **Cryptocurrency reporting** -- IRS actively pursuing crypto compliance. Must report all
  dispositions even if exchange doesn't issue 1099. Check "yes" to digital asset question.
- **Unreported 1099-NEC** -- IRS matching program catches missing Schedule C income.

## 12. Profession-Specific Rules

- **ISO AMT trap** -- Exercising ISOs creates AMT preference item. If stock drops after exercise,
  taxpayer owes AMT on phantom income. Exercise-and-hold strategy requires careful AMT modeling.
  AMT credit carryforward (Form 8801) recovers excess AMT in future years.
- **83(b) election** -- Must be filed within 30 days of restricted stock grant. Elects to pay
  tax on current (low) value rather than future vesting value. Critical for early-stage startups.
  No late filing; IRS strictly enforces deadline.
- **ESPP timing** -- Track qualifying vs. disqualifying dispositions. Holding periods matter
  significantly for tax treatment.
- **Section 199A (QBI)** -- Software consulting may qualify for 20% deduction if under income
  thresholds ($197,300 single / $394,600 MFJ for 2025). Above threshold, "specified service
  trade or business" (SSTB) limitations apply -- consulting is generally SSTB.

## 13. State Considerations

- **California** -- Taxes RSU/ISO income. Does not conform to federal QSBS exclusion (only
  allows 50% exclusion for CA-qualified businesses). High marginal rate (13.3%).
- **Washington** -- No income tax, but 7% capital gains tax on gains over $270,000 (2025).
  Affects large RSU/ISO sales.
- **New York** -- City tax adds 3.078-3.876% on top of state (up to 10.9%). Remote work
  "convenience of employer" rule can tax nonresidents who work remotely for NY employers.
- **Texas, Florida, Nevada** -- No state income tax. Popular relocation destinations for
  engineers. Ensure clean break from prior state to avoid residency audits.
- **Multi-state remote work** -- Work-from-anywhere creates nexus issues. Track days worked
  in each state. Some states have de minimis thresholds (e.g., 30 days).

## 14. Worked Example: Senior Engineer with RSUs, ISOs, and Side Income

### Profile

- **W-2 salary:** $250,000 (at a public tech company in CA)
- **RSU vesting:** 1,000 shares at $200/share = $200,000 (included in W-2)
- **ISO exercise:** 500 shares, exercise price $50, FMV $200 = $75,000 AMT preference
- **Filing status:** Single
- **Side income:** None (purely W-2)

### Income Summary

| Source | Amount | Tax Type |
|---|---|---|
| W-2 salary | $250,000 | Ordinary income |
| RSU vesting (on W-2) | $200,000 | Ordinary income |
| ISO exercise | $0 regular tax / $75,000 AMT preference | AMT only (if stock held) |
| **Total W-2 income** | **$450,000** | |

### Federal Tax Calculation (Approximate)

**Regular Tax:**
```
Gross income:                          $450,000
Standard deduction:                    -$15,700
Taxable income:                        $434,300

Federal income tax (2025 brackets):
  10% on first $11,925:               $1,193
  12% on $11,926 - $48,475:           $4,386
  22% on $48,476 - $103,350:          $12,073
  24% on $103,351 - $197,300:         $22,548
  32% on $197,301 - $250,525:         $17,032
  35% on $250,526 - $434,300:         $64,321
  Regular tax:                         ~$121,553
```

**Additional Medicare Tax:**
```
W-2 wages subject to Additional Medicare Tax: $450,000 - $200,000 = $250,000
Additional Medicare Tax: $250,000 x 0.9% = $2,250
```

**Net Investment Income Tax (NIIT):**
```
MAGI: $450,000
Threshold (single): $200,000
Net investment income: $0 (assuming no investment income beyond RSU/ISO)
NIIT: $0 (no net investment income to tax)

Note: If RSU shares are sold, any capital gain IS net investment income.
If 1,000 RSU shares sold at $220 (gain = $20,000):
  NIIT: $20,000 x 3.8% = $760
```

**AMT Calculation (ISO Exercise):**
```
Regular taxable income:                $434,300
Add: ISO AMT preference:              +$75,000
AMTI:                                  $509,300
AMT exemption (single 2025):          -$88,100
AMT phase-out: ($509,300 - $609,350) = negative, no phase-out
AMT taxable income:                    $421,200
AMT:
  26% on first $239,100:              $62,166
  28% on $421,200 - $239,100:         $50,988
  Total AMT:                          $113,154

Regular tax:                           $121,553
AMT exceeds regular tax?               $112,970 < $121,553 -- NO
AMT owed:                             $0

In this case, the taxpayer's high regular income means AMT is NOT
triggered by the ISO exercise. The regular tax rate already exceeds
the AMT rate. This taxpayer could exercise MORE ISOs without AMT.

AMT cushion: $121,553 - $113,154 = $8,399
Additional ISO spread before AMT: $8,583 / 28% = ~$30,654
Could exercise another ~153 ISOs (at $200 spread) without AMT.
```

**California State Tax:**
```
CA taxable income: ~$434,300 (CA does not allow standard deduction for high earners,
  uses CA standard deduction of $5,540 single)
CA income: $450,000 - $5,540 = $444,460
CA tax (top bracket 13.3% on income over $721,314 -- does not apply here):
  Approximate CA tax: ~$37,000-$40,000

CA also taxes ISO spread if shares are sold in a disqualifying disposition.
CA does NOT have a separate AMT for ISOs (CA conforms to federal AMT with modifications).
```

**Total Estimated Tax Liability:**
```
Federal income tax:                    ~$121,553
Additional Medicare Tax:               $2,250
NIIT:                                  $0 (unless investment income exists)
CA state tax:                          ~$38,000
AMT:                                   $0

Total:                                 ~$161,803 on $450,000 income
Effective rate:                        ~36%
```

### Key Takeaways from the Example

1. At $450K income, the regular tax rate is high enough that moderate ISO exercises do NOT trigger AMT
2. The RSU income is already fully taxed on the W-2 -- do NOT report it again when selling shares
3. The Additional Medicare Tax adds 0.9% on wages above $200K (single)
4. CA state tax at these income levels is approximately 8.5% effective
5. If the engineer contributed $23,500 to 401(k): taxable income drops by $23,500, saving ~$8,225 in federal tax + ~$2,200 in CA tax = ~$10,425 in tax savings
6. Mega backdoor Roth (if employer plan allows): additional $38,500+ in Roth contributions

---

## 15. Common Mistakes

1. **Double-taxing RSUs** -- Not adjusting cost basis on 1099-B when broker reports $0 or
   partial basis. Must add W-2 income amount to basis.
2. **Missing AMT on ISOs** -- Exercising ISOs without modeling AMT impact. Can create
   six-figure surprise tax bills.
3. **Claiming home office as W-2 employee** -- Not deductible federally 2018-2025 even
   if employer requires remote work. Some states (e.g., NY) still allow.
4. **Ignoring estimated taxes on side income** -- Quarterly payments required if expecting
   to owe $1,000+ at filing. Underpayment penalty (currently ~8% annualized) applies.
5. **Failing to track crypto cost basis** -- Must use specific identification or FIFO.
   Not tracking basis means defaulting to $0, paying tax on full proceeds.
6. **ESPP disposition misreporting** -- Using wrong basis amount, double-counting income
   that appears on both W-2 and 1099-B.
7. **Forgetting 83(b) election** -- 30-day deadline is absolute. No extensions, no excuses.
   Send via certified mail; keep proof of filing.
8. **Not filing in former state after relocation** -- Part-year returns required. States
   aggressively audit high-income departures (especially CA, NY).
9. **Overlooking charitable stock donations** -- Donating appreciated RSU shares avoids
   capital gains while providing full FMV deduction. Far more tax-efficient than cash.
10. **Ignoring multi-state taxation for remote work** -- The convenience of employer rule
    can result in double taxation. Must track days in each state and understand state rules.
11. **Not maximizing the mega backdoor Roth** -- Many large tech employer plans support it.
    Leaving $38,500+ of Roth contribution capacity unused annually.
12. **Missing the 83(i) deferral election at private companies** -- If available, can defer
    tax on illiquid equity for up to 5 years.
13. **Failing to claim AMT credit carryforward** -- After paying AMT on ISO exercises, the
    credit (Form 8801) is recoverable in future years. Many taxpayers forget to claim it.
14. **Not exercising ISOs strategically** -- Exercising all at once can trigger massive AMT.
    Spreading exercises over multiple years can keep each year's AMT at zero.
