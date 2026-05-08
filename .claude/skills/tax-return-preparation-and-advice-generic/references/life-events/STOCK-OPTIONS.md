# Stock Options and Equity Compensation Tax Reference (Tax Year 2025)

## Overview

Equity compensation -- including Incentive Stock Options (ISOs), Non-Qualified Stock Options (NSOs/NQSOs), Restricted Stock Units (RSUs), Employee Stock Purchase Plans (ESPPs), and restricted stock with Section 83(b) elections -- is a significant component of total compensation at many companies. Each type has fundamentally different tax treatment. Mistakes in timing, elections, and reporting can cost thousands or tens of thousands in unnecessary taxes.

## Incentive Stock Options (ISOs) — Deep Dive

### IRC §422 Requirements
For options to qualify as ISOs, ALL of the following must be met:
1. **10-year exercise window**: options must be exercised within 10 years of the grant date
2. **Exercise price**: must be at or above 100% of FMV at the date of grant (110% if the
   employee owns >10% of the company's voting stock)
3. **$100,000 annual limit**: the aggregate FMV (at grant date) of stock for which ISOs
   first become exercisable in any calendar year cannot exceed $100,000. Options exceeding
   this limit are automatically treated as NSOs. (Example: granted ISOs on stock worth $150K
   at grant, all vesting in the same year — $100K qualifies as ISO, $50K treated as NSO.)
4. **Employee status**: must be an employee at the time of grant and continuously until
   3 months before exercise (12 months for disability)
5. **Written plan**: must be under a written plan approved by shareholders within 12 months
6. **Transferability**: cannot be transferred except at death

### Tax Treatment at Exercise
- **No ordinary income at exercise** (for regular income tax purposes)
- The spread (FMV at exercise minus exercise price) IS an **AMT preference item** (IRC §56(b)(3))
- AMT adjustment reported on Form 6251, Line 2i
- Example: exercise 1,000 shares at $10 strike when FMV is $50; the $40,000 spread is an
  AMT preference item (may or may not trigger actual AMT depending on total AMT computation)

### AMT Preference Item Calculation
```
AMT preference = (FMV at exercise - exercise price) x number of shares
AMT rate = 26% on first $239,100 of AMTI above exemption; 28% above that (2025)

Example:
Exercise 5,000 shares at $10 strike; FMV = $60
Spread per share: $50
Total AMT preference: $50 x 5,000 = $250,000

If this pushes AMTI above the AMT exemption ($88,100 single, $137,000 MFJ):
Potential AMT = $250,000 x 26-28% = $65,000-$70,000 additional tax

BUT: AMT is the EXCESS of tentative minimum tax over regular tax.
If regular tax is already high, AMT may be minimal or zero.
```

### AMT Credit Recovery — Form 8801
- AMT paid due to ISO exercise creates a **Minimum Tax Credit (MTC)**
- The MTC carries forward indefinitely and can offset regular tax in future years
  (to the extent regular tax exceeds tentative minimum tax)
- File Form 8801 each subsequent year to claim the credit
- **Recovery timeline**: typically takes 3-7 years to fully recover AMT paid on ISOs,
  depending on income trajectory and whether shares are eventually sold
- If you sell the shares in a **disqualifying disposition** in the same year as exercise:
  the AMT preference is eliminated for that year, and any prior AMT credit may be accelerated

### ISO Exercise Planning: Maximum Shares Without Triggering AMT
```
Strategy: calculate the maximum spread that keeps tentative minimum tax ≤ regular tax

1. Compute regular tax liability for the year (without ISO exercise)
2. Compute AMT exemption amount ($88,100 single / $137,000 MFJ for 2025)
3. Maximum ISO spread ≈ (regular tax - AMT on other items) / AMT rate
   (simplified; actual calculation is iterative)

Example: regular tax = $50,000, AMT exemption covers existing income
Maximum ISO spread before AMT kicks in: ~$192,000 ($50,000 / 0.26)
At $50/share spread: exercise up to ~3,840 shares with zero AMT
```

### Qualifying Disposition (Must Meet BOTH)
1. Hold shares for at least **1 year after the exercise date**
2. Hold shares for at least **2 years after the grant date**

**Tax result**: entire gain (sale price minus exercise price) taxed as **long-term capital gains** (0%/15%/20%)

Example:
- Granted at $10 on Jan 1, 2023
- Exercised at $10 when FMV is $50 on July 1, 2024
- Sold at $80 on August 1, 2025 (1+ year from exercise, 2+ years from grant)
- LTCG = $80 - $10 = $70 per share (all capital gain, no ordinary income)

### Disqualifying Disposition
If you sell BEFORE meeting both holding periods:
- The **spread at exercise** (or gain at sale, whichever is LESS) is taxed as **ordinary income**
  (reported on W-2 by employer)
- Any additional gain above the exercise-date FMV is capital gain (short-term or long-term
  depending on holding period from exercise to sale)
- The ordinary income portion is subject to income tax but NOT Social Security/Medicare tax
  (unique to ISO disqualifying dispositions — not true for NSOs)
- A disqualifying disposition in the same year as exercise **eliminates the AMT preference item**
  for those shares (may generate an AMT credit to use in future years)

### Cashless Exercise Tax Trap
- **Cashless exercise**: broker sells enough shares immediately to cover the exercise cost
  and withholding. Common when employees cannot afford to pay the exercise price out of pocket.
- For ISOs: a cashless exercise is a **same-day sale** = automatic disqualifying disposition.
  The spread becomes ordinary income. You lose the ISO's LTCG benefit entirely.
- **If you want qualifying disposition treatment**: you must pay the exercise price with cash
  (or existing shares) and hold for the required periods. The cost of capital is the price
  of the ISO benefit.

### Post-Termination Exercise Window
- After leaving the company: ISOs must be exercised within **90 days** of termination
- After 90 days: unexercised ISOs automatically convert to NSOs (lose ISO tax treatment)
- Exception: disability (12 months), death (estate may have longer per plan terms)
- **Planning for departure**: if you have substantial ISOs, exercise within 90 days of leaving.
  Model the AMT impact before deciding how many shares to exercise.

## Non-Qualified Stock Options (NSOs) — Deep Dive

### Tax Treatment at Exercise (IRC §83)
- **Ordinary income at exercise**: spread (FMV at exercise minus exercise price) is taxed as
  W-2 wages (or 1099-NEC for non-employee consultants)
- Subject to federal income tax, Social Security (up to wage base $176,100), AND Medicare taxes
  (including the 0.9% additional Medicare above $200K/$250K)
- Employer withholds taxes; reported on W-2 Box 1 (also Box 12, Code V)
- **Employer gets a matching deduction** (IRC §83(h)) — the employer deducts the same amount
  the employee recognizes as income. This is why many companies prefer NSOs over ISOs.
- Basis in the shares = FMV at exercise

### Tax Treatment at Sale
- Gain/loss above FMV at exercise is capital gain/loss
- **Short-term**: if sold within 1 year of exercise date
- **Long-term**: if held more than 1 year after exercise date
- Loss below FMV at exercise is also capital (subject to capital loss limitations)

### Social Security and Medicare Withholding
- The spread is subject to FICA withholding:
  - Social Security: 6.2% (employee) + 6.2% (employer) up to wage base ($176,100 combined
    with other W-2 wages for the year)
  - Medicare: 1.45% (employee) + 1.45% (employer) on all amounts
  - Additional Medicare: 0.9% on amounts above $200K single / $250K MFJ
- If your regular W-2 wages already exceed the SS wage base: no additional SS tax on the
  NSO exercise (only Medicare applies)

### NSO Planning
- Exercise and sell immediately ("cashless exercise"): all gain is ordinary income; no market
  risk; simplest. No additional tax complexity.
- Exercise and hold: ordinary income at exercise; hope for additional appreciation taxed as
  LTCG; market risk during holding period. Must pay tax on the spread even without selling.
- NSOs have **no AMT implications** (already taxed at exercise as ordinary income)
- Consider timing exercises to lower-income years to reduce marginal rate

## Restricted Stock Units (RSUs) — Deep Dive

### Tax Treatment at Vesting (IRC §83)
- **Taxed as ordinary income at vesting**: FMV of shares on the vesting date is W-2 income
- Subject to federal income tax, Social Security, and Medicare taxes
- No choice about timing — tax is triggered automatically at vesting

### Sell-to-Cover Withholding — The Underpayment Problem
- Employer typically withholds by selling a portion of shares ("sell to cover")
- **Supplemental withholding rate**: 22% federal (37% on amounts exceeding $1M in
  supplemental wages for the year)
- **22% is almost always insufficient for high earners**: a single filer in the 35% or 37%
  bracket (income above $243,725 / $609,350) will owe 13-15% more at filing
- Plus state tax withholding may also be insufficient
- Plus NIIT (3.8%) if applicable

**Example of withholding shortfall**:
```
RSU vesting: $100,000 of stock vests
Federal withholding (22%):              $22,000
State withholding (CA 10.23%):          $10,230
Total withheld:                         $32,230

Actual tax liability (37% fed + 13.3% CA + 3.8% NIIT):
Federal: $37,000
State:   $13,300
NIIT:     $3,800
Total:   $54,100

SHORTFALL: $54,100 - $32,230 = $21,870 owed at filing
```

- **Solution**: make estimated payments in the quarter of vesting, or submit a new W-4
  requesting additional withholding

### Broker 1099-B $0 Basis Trap (Form 8949 Adjustment)
- When RSU shares are sold, the broker's 1099-B often reports **$0 cost basis** or the
  basis may not be reported to the IRS (Box B or Box D on 1099-B)
- The ACTUAL basis is the FMV at vesting (the amount already included in W-2 income)
- If you report the 1099-B as-is without adjusting basis: you pay tax TWICE on the same
  income (once as W-2 income at vesting, again as capital gain at sale)
- **Fix**: on Form 8949, report the 1099-B proceeds, then add an adjustment in Column (g)
  equal to the correct basis. Use adjustment code "B" (basis reported to IRS is incorrect)
  in Column (f).
- This is one of the MOST COMMON tax errors for equity compensation recipients.

### Key Points
- No §83(b) election available for RSUs (they are not "property" until vesting; they are merely
  a promise to deliver shares)
- RSUs cannot have a disqualifying disposition (not applicable)
- Dividend equivalents paid during vesting: taxed as ordinary compensation (W-2), not qualified dividends

## Employee Stock Purchase Plan (ESPP) — Deep Dive

### Qualified ESPP (IRC §423 Plan Requirements)
- Must be approved by shareholders
- Only employees of the company (or subsidiaries) are eligible
- Cannot discriminate in favor of highly compensated employees (though some exclusions are permitted)
- **Maximum discount**: 15% below FMV
- **Maximum contribution**: $25,000 of stock per year (based on FMV at the start of the offering period)
- Typical structure: 6-month offering period; purchase at 85% of the **lower of** FMV at the
  start or end of the offering period ("lookback" provision)
- The lookback provision means the effective discount can far exceed 15% if the stock rises
  during the offering period

### Qualifying Disposition
Requirements (must meet BOTH holding periods):
- Hold for at least **2 years from the offering date** AND
- Hold for at least **1 year from the purchase date**

Tax result:
- **Ordinary income**: the LESSER of:
  - (a) the actual gain on sale, OR
  - (b) the discount at the offering date (typically 15% of FMV at start of offering period)
- **Remaining gain**: long-term capital gains
- If the stock declined below the purchase price: you may still have ordinary income on the
  discount portion, offset by a capital loss

**Example**:
```
Offering date FMV: $100/share
Purchase date FMV: $120/share
Purchase price: 85% of lower = 85% of $100 = $85/share
Sale price (2+ years later): $150/share

Ordinary income: lesser of ($150-$85=$65) or (15% x $100=$15) = $15/share
LTCG: $150 - $85 - $0 = $65 total gain minus $15 ordinary = $50/share LTCG
Total gain: $15 ordinary + $50 LTCG = $65/share
```

### Disqualifying Disposition
- Selling before meeting the holding periods
- **Ordinary income**: spread at purchase (FMV on purchase date minus actual purchase price)
- The ordinary income is the FULL spread at purchase, not just the 15% discount
- Additional gain/loss: capital (short-term or long-term depending on holding period from purchase)
- Reported on W-2 by employer

**Example (disqualifying)**:
```
Same facts but sold 6 months after purchase (before 1-year holding period):
Ordinary income: $120 - $85 = $35/share (full spread at purchase)
Short-term capital gain: $150 - $120 = $30/share
Total: $35 ordinary + $30 STCG = $65/share
```

Compare: qualifying disposition = $15 ordinary + $50 LTCG (much lower effective rate)

### ESPP Planning
- **Almost always participate** if offered: the 15% discount is essentially a guaranteed return;
  even selling immediately is advantageous (disqualifying disposition, but 15%+ return in 6 months)
- For qualifying disposition: hold for the required periods if you believe in the stock AND
  can tolerate the concentration risk
- Maximum contribution: $25,000/year. Fund through payroll deductions (typically 1-15% of salary).
- Consider selling immediately to diversify if the stock represents a large portion of net worth

## Section 83(b) Election — Restricted Stock

### When It Applies
- Applies to **restricted stock** (NOT RSUs) — shares that are issued and transferred to
  the employee but subject to a substantial risk of forfeiture (vesting schedule)
- Without 83(b): taxed as ordinary income at EACH vesting date (FMV at vesting minus amount paid)
- With 83(b): elect to be taxed on the value at GRANT date instead of at each vesting date

### Why File 83(b)
- If you believe the stock will appreciate significantly: pay tax on a small amount now
  (grant date value) rather than a large amount later (vesting date value)
- All appreciation after the election is taxed as capital gain (long-term if held 1+ year from grant)

**Example**:
```
Receive 100,000 shares of restricted stock at $0.10/share (early-stage startup)
Total value at grant: $10,000

Without 83(b): if stock is worth $50/share at vesting (4-year vest):
  Year 1: 25,000 shares x $50 = $1,250,000 ordinary income
  Year 2-4: additional vesting = more ordinary income
  Total ordinary income: potentially $5,000,000

With 83(b): pay tax on $10,000 at grant (tax ≈ $3,700 at 37%)
  All future appreciation is LTCG (20% + 3.8% NIIT = 23.8%)
  Tax on $5M gain: $1,190,000 (LTCG) vs. $1,850,000+ (ordinary income)
  Savings: $660,000+
```

### Early Exercise + §83(b) Strategy for Startups
- Some startup stock option plans allow **early exercise** (exercising unvested options)
- The shares received are still subject to vesting (company can repurchase unvested shares
  at exercise price if you leave)
- File 83(b) within 30 days of early exercise
- If the stock is nearly worthless (common stock of a pre-revenue startup with a low 409A
  valuation), the tax on the 83(b) election is minimal or zero
- All future appreciation is LTCG (if held 1+ year from exercise)
- **Combine with QSBS (§1202)**: if the stock qualifies (C-corp, $50M asset limit at issuance,
  held 5+ years), up to $10M or 10x basis of gain may be excluded entirely
- **Risk**: if you file 83(b) and the stock later becomes worthless or you leave before vesting,
  you get NO refund of the tax paid. Your loss is limited to the amount you paid for the stock.

### Critical Rules for 83(b) Filing
- **Must file within 30 days of the stock grant** — NO exceptions, NO extensions, NO late filings
- File with: (1) the IRS service center where you file your return, (2) your employer
- Attach a copy to your tax return for that year
- The election is **irrevocable**
- Keep proof of mailing (certified mail/return receipt) — the filing deadline is absolute
  and you need evidence of timely filing

## Section 83(i) — Qualified Equity Grants (IRC §83(i))

### 5-Year Deferral Election
- Available for employees of **private companies** (not publicly traded)
- Must be a **broad-based** equity grant (at least 80% of employees receive options/RSUs
  under the same terms)
- Employee can elect to defer income recognition for up to **5 years** after the exercise
  of stock options or settlement of RSUs
- The election must be made within 30 days of the taxable event (exercise/vesting)

### Requirements
- Company must be a corporation (not partnership/LLC)
- Stock must not be readily tradable on an established market
- Company must have a written plan and provide adequate notice to employees
- Excludes: 1% owners, current/former CEO/CFO, family members of the above, the 4 highest
  compensated officers

### Practical Limitations
- Tax is merely DEFERRED, not eliminated — the income is still ordinary when recognized
- The deferral period ends at the EARLIEST of: 5 years, the date the stock becomes transferable
  or publicly traded, or the date employment terminates
- Employer must withhold at the maximum individual rate (37%) at the end of the deferral
- Limited adoption in practice; complex compliance requirements

## Required Forms

| Form | Purpose |
|------|---------|
| Form 3921 | ISO exercise information (from employer) |
| Form 3922 | ESPP share transfer information (from employer) |
| Form 6251 | Alternative Minimum Tax (ISO AMT preference) |
| Form 8801 | Minimum Tax Credit (to recover AMT from ISO exercise) |
| Form 8949 / Schedule D | Capital gains/losses on sale of shares |
| W-2 | Ordinary income from NSO exercise, RSU vesting, disqualifying dispositions |
| 83(b) election letter | Filed with IRS within 30 days of restricted stock grant |

## Optimization Strategies

1. **ISOs: model AMT before exercising** — exercise incrementally to stay below AMT threshold;
   use Form 8801 to recover AMT credit in future years. Spreadsheet or tax software is essential.
2. **ISOs: calculate maximum shares per year** — determine the number of shares you can exercise
   each year without triggering AMT, then exercise that many annually over several years
3. **NSOs: exercise in low-income years** — if you have a sabbatical, job change, or retirement,
   exercise NSOs when marginal rate is lower
4. **RSUs: plan for withholding shortfall** — 22% supplemental rate is often insufficient;
   make estimated payments or adjust W-4. At $200K+ income, expect to owe 10-15%+ more.
5. **RSUs: adjust 1099-B basis** — ALWAYS check the 1099-B cost basis against your W-2.
   If 1099-B shows $0 basis, you MUST adjust on Form 8949 or you'll be double-taxed.
6. **ESPP: always participate** — the 15% discount is a guaranteed return; hold for qualifying
   disposition if possible, but even immediate sale is profitable
7. **83(b): file for startup stock** — if stock is nearly worthless at grant, the tax cost is
   minimal and the upside is enormous (especially combined with QSBS under §1202)
8. **QSBS (Section 1202)**: if your stock qualifies (C-corp, under $50M assets, held 5+ years),
   you may exclude $10M+ of gain. Worth structuring around.
9. **Charitable giving**: donate appreciated shares after meeting holding periods to avoid
   capital gains and get FMV deduction
10. **Tax-loss harvesting**: if stock declines after vesting/exercise, selling at a loss can
    offset other gains (watch wash sale rules)
11. **10b5-1 trading plans**: establish a preset selling plan to manage concentrated stock
    positions while complying with insider trading rules
12. **ISO + disqualifying disposition in same year**: if you exercise ISOs and sell in the same
    calendar year (disqualifying disposition), you eliminate the AMT preference entirely.
    Useful when AMT would be large and the stock has already appreciated significantly.

## Worked Examples

### ISO Exercise and Qualifying Sale
```
Grant: 10,000 ISOs at $10/share on Jan 1, 2022
Exercise: all 10,000 on Jan 15, 2024 (FMV = $40/share)
Sale: all 10,000 on Feb 1, 2025 (FMV = $60/share)

At exercise (2024):
  AMT preference: ($40-$10) x 10,000 = $300,000
  Regular tax: $0 (no ordinary income)
  AMT: depends on other income; if substantial, could be $50K-$80K+
  AMT credit created: equal to AMT actually paid

At sale (2025 — qualifying disposition):
  LTCG: ($60-$10) x 10,000 = $500,000
  Federal tax (20% + 3.8% NIIT): $119,000
  Minus AMT credit recovery (Form 8801): reduces regular tax

Net benefit vs. NSO treatment:
  If NSO: $300K ordinary income at exercise (37% = $111K) + $200K LTCG at sale ($47.6K) = $158.6K
  ISO route: $119K LTCG tax - AMT credit recovery ≈ $100-110K effective
  ISO savings: $50K-$60K
```

### RSU Vesting and Sale
```
100 RSUs vest when stock = $200/share
W-2 income: 100 x $200 = $20,000
Sell-to-cover: employer sells 22 shares at $200 = $4,400 (22% federal)
Net shares received: 78 shares

Sell all 78 shares 2 months later at $220/share:
  Proceeds: 78 x $220 = $17,160
  Basis: 78 x $200 = $15,600
  Short-term capital gain: $1,560

Form 8949: if broker reports $0 basis → shows $17,160 gain (WRONG)
Must adjust: report $15,600 basis, code "B" → correct gain = $1,560
```

### ESPP Qualifying vs. Disqualifying
```
Offering date: Jan 1, 2023 (FMV = $100)
Purchase date: Jun 30, 2023 (FMV = $130)
Purchase price: 85% of min($100, $130) = $85

Qualifying disposition (sold Jul 1, 2025 at $160):
  Ordinary income: min($160-$85, 15% x $100) = min($75, $15) = $15/share
  LTCG: $160 - $85 - $15 = $60/share (wait: total gain = $75; ordinary = $15; LTCG = $60)
  Tax on $15 ordinary (37%): $5.55/share
  Tax on $60 LTCG (23.8%): $14.28/share
  Total tax: $19.83/share

Disqualifying disposition (sold Dec 31, 2023 at $160):
  Ordinary income: $130 - $85 = $45/share
  STCG: $160 - $130 = $30/share
  Tax on $45 ordinary (37%): $16.65/share
  Tax on $30 STCG (37%): $11.10/share
  Total tax: $27.75/share

Savings from qualifying disposition: $7.92/share
On 1,000 shares: $7,920 saved by holding
```

## Common Mistakes

1. **Missing the 30-day 83(b) deadline** — absolutely no exceptions; failure is permanent
2. **Not tracking cost basis per equity type** — basis for ISOs (exercise price), NSOs (FMV at exercise), RSUs (FMV at vesting) is different for each type
3. **Double-counting income on RSUs** — the W-2 already includes the vesting income; if you also report the full sale proceeds on Form 8949 without adjusting basis, you pay tax twice
4. **Exercising ISOs without modeling AMT** — large exercises can trigger tens of thousands in AMT. Always model before exercising.
5. **Selling ESPP shares in a disqualifying disposition unnecessarily** — the tax difference between qualifying and disqualifying can be $5-$10+ per share
6. **Holding concentrated stock positions too long** — tax optimization should not override diversification; a 50% stock decline costs more than the tax saved
7. **Not withholding enough on RSU vesting** — 22% supplemental rate leaves high earners underwithheld by $10K-$50K+ per year
8. **Confusing RSUs with restricted stock** — RSUs cannot have an 83(b) election; they are fundamentally different (promise vs. issued property)
9. **Cashless ISO exercise** — results in automatic disqualifying disposition, eliminating the ISO tax benefit entirely. If you want qualifying treatment, pay cash to exercise.
10. **Not filing Form 8801 to recover AMT credit** — AMT paid on ISO exercise creates a credit that carries forward. Many taxpayers forget to claim it in subsequent years.
11. **Ignoring the $100K ISO annual limit** — options vesting above the $100K FMV threshold in a single year automatically become NSOs. Plan vesting schedules accordingly.

## State Considerations

- **California**: taxes all equity compensation as ordinary income at state level (no LTCG preference); sources equity income based on where services were performed during the vesting/service period. CA has its own AMT that may be triggered by ISO exercises.
- **Multi-state allocation**: if you moved states during the vesting period, each state may claim a portion of the income based on the ratio of service days in that state during the allocation period (grant to vest for RSUs; grant to exercise for options)
- **New York**: sources equity compensation to NY based on days worked in NY during the allocation period. The convenience-of-employer rule may affect sourcing for remote workers.
- **No-income-tax states**: timing exercise/vesting for after a move to FL, TX, NV, etc. can eliminate state tax on the income entirely. But be cautious: CA in particular will allocate income back to CA for the portion of the vesting period you worked in CA, even if you exercise/vest after moving.
- **State AMT**: CA has its own AMT that may be triggered by ISO exercises; most other states do not have a separate AMT
- **ESPP multi-state**: the ordinary income portion is allocated based on where you worked during the offering period; the capital gain portion is sourced to your state of residence at sale
