# Investment Tax Strategies

## Overview

Investment income is taxed through multiple regimes: short-term capital gains (ordinary rates), long-term capital gains (preferential rates), qualified dividends (preferential rates), interest income (ordinary rates), and potentially the 3.8% Net Investment Income Tax. Understanding these distinctions and planning accordingly can save substantial tax dollars.

All figures are for the 2025 tax year.

---

## Capital Gains Rates

### Long-Term Capital Gains (Assets Held Over 1 Year)

| Filing Status | 0% Rate | 15% Rate | 20% Rate |
|---|---|---|---|
| Single | Taxable income up to $48,350 | $48,351 - $533,400 | Over $533,400 |
| MFJ | Taxable income up to $96,700 | $96,701 - $600,050 | Over $600,050 |
| MFS | Taxable income up to $48,350 | $48,351 - $300,025 | Over $300,025 |
| HoH | Taxable income up to $64,750 | $64,751 - $566,700 | Over $566,700 |

### Short-Term Capital Gains (Assets Held 1 Year or Less)

Taxed at ordinary income rates (10% to 37%).

### Net Investment Income Tax (NIIT)

Additional 3.8% tax on the lesser of net investment income or MAGI exceeding:
- $200,000 (Single)
- $250,000 (MFJ)
- $125,000 (MFS)

**Effective top rate on long-term capital gains:** 20% + 3.8% = 23.8%

### Strategies to Manage Capital Gains

1. **Hold investments over 1 year** to qualify for long-term rates (15% vs. up to 37%)
2. **Harvest losses** to offset gains (see below)
3. **Time sales** across tax years to stay in lower brackets
4. **Use the 0% bracket** -- retirees or low-income years can realize gains tax-free
5. **Donate appreciated stock** to charity instead of selling
6. **Installment sales** to spread gain over multiple years
7. **1031 exchanges** for real estate

---

## Tax-Loss Harvesting

### Mechanics

1. Identify investments held at a loss in taxable accounts
2. Sell the investment to realize the loss
3. Use the loss to offset capital gains (short-term losses offset short-term gains first, then long-term; vice versa)
4. Net capital losses offset up to $3,000 of ordinary income per year ($1,500 MFS)
5. Excess losses carry forward indefinitely
6. Reinvest in a similar (but not substantially identical) investment to maintain market exposure

### Wash Sale Rule (Section 1091)

The loss is disallowed if you purchase "substantially identical" securities within 30 days before or after the sale.

**30-day window:**
```
|----30 days before sale----|SALE|----30 days after sale----|
         Wash sale period              Wash sale period
```

**What is "substantially identical"?**
- Same stock or bond: yes
- Same mutual fund (e.g., sell Vanguard S&P 500 and buy Vanguard S&P 500): yes
- Different funds tracking the same index from different providers (e.g., sell Vanguard S&P 500, buy Fidelity S&P 500): gray area -- IRS has not ruled definitively, but risk exists
- Different index entirely (e.g., sell S&P 500 fund, buy Total Market fund): generally not substantially identical
- Same company's stock purchased via DRIP during the wash sale window: yes
- Options on the same stock: potentially yes

**Cross-account application:**
- Wash sale rules apply across ALL accounts, including IRAs and spouse's accounts (per IRS guidance)
- Buying the same security in an IRA within 30 days of selling at a loss in a taxable account triggers the wash sale -- AND the disallowed loss cannot be added to the IRA basis (permanently lost)

### Year-End Harvesting Checklist

1. Review all positions in taxable accounts in November
2. Identify positions with unrealized losses
3. Determine if losses will offset realized gains from the current year
4. Sell losing positions on or before December 31
5. Wait 31 days before buying back substantially identical securities (or buy a similar alternative immediately)
6. Document all transactions and cost basis adjustments
7. If using specific identification, designate which lots are being sold at the time of sale

---

## Qualified Dividends vs. Ordinary Dividends

### Qualified Dividends

Taxed at the same preferential rates as long-term capital gains (0%/15%/20%).

**Requirements:**
- Paid by a US corporation or a qualified foreign corporation
- Holding period: must hold the stock for more than 60 days during the 121-day period beginning 60 days before the ex-dividend date (90 days / 181-day period for preferred stock)
- Not specifically excluded (e.g., dividends from REITs, money market funds, tax-exempt organizations)

### Ordinary Dividends

Taxed at ordinary income rates. Includes:
- REIT dividends (though some qualify for the 20% QBI deduction under Section 199A)
- Money market fund dividends
- Dividends that fail the holding period test
- Short-term capital gain distributions from mutual funds

### Dividend Capture Strategies and the Holding Period Trap

The 61-day holding period requirement for qualified dividend treatment is a genuine trap for active traders and dividend capture strategies.

**The 121-day window:** Begins 60 days before the ex-dividend date and ends 60 days after. The stock must be held for MORE than 60 days within this window. Days of reduced risk (hedged positions, put options, short positions in substantially similar stock) do NOT count.

**Example of a failed dividend capture:**
```
Stock XYZ ex-dividend date: March 15
Dividend: $2.00/share (qualified if holding period met)
Investor buys 10,000 shares on February 20 (23 days before ex-date)
Investor sells on April 10 (26 days after ex-date)
Total holding: 49 days -> FAILS the 61-day test

Dividend received: $20,000
Tax at qualified rate (20%): $4,000
Tax at ordinary rate (37%): $7,400
Difference: $3,400 in additional tax

The investor thought they were getting a preferential rate but owes ordinary income tax.
```

**Planning:** Any systematic dividend capture strategy must hold positions for at least 61 days within the 121-day window to receive qualified treatment. For high-value positions, this is essential to verify before selling.

---

## Section 1256 Contracts -- 60/40 Treatment

### What They Are

Section 1256 contracts receive special tax treatment: gains and losses are treated as 60% long-term and 40% short-term, REGARDLESS of the actual holding period. Additionally, they are marked to market at year-end.

### Qualifying Contracts

1. **Regulated futures contracts (RFC):** Contracts traded on a domestic board of trade (CME, CBOT, NYMEX, etc.)
2. **Foreign currency contracts:** Certain interbank-traded forward contracts
3. **Non-equity options:** Options on broad-based stock indexes (S&P 500, Nasdaq 100, Russell 2000), but NOT options on individual stocks or narrow-based indexes
4. **Dealer equity options:** Options granted or acquired by a dealer in the normal course of dealing
5. **Dealer securities futures contracts**

### Tax Treatment

```
Blended rate calculation:
  60% long-term at 20% = 12.0%
  40% short-term at 37% = 14.8%
  Blended rate: 26.8% (vs. 37% if all short-term)

For a trader with $100,000 in Section 1256 gains:
  Tax at blended rate: $26,800
  Tax if all short-term: $37,000
  Savings: $10,200
```

### Mark-to-Market at Year-End

All open Section 1256 contracts are treated as if sold at FMV on the last business day of the tax year. Gains and losses are recognized even if the position is not closed. In the next year, the contract's basis is adjusted to the year-end FMV.

### Three-Year Carryback of Losses

Under Section 1256(d), net Section 1256 contract losses can be carried back 3 years and applied against Section 1256 gains in those prior years. This is unique -- ordinary capital losses cannot be carried back at all. The carryback is applied to the earliest year first.

### Common Section 1256 Planning

- **Day traders of index options (SPX, NDX):** Receive 60/40 treatment on all gains, even positions held for minutes
- **Futures traders:** All regulated futures get 60/40 automatically
- **Mixed straddle complications:** If a Section 1256 contract is part of a straddle with non-Section-1256 property, special rules apply (see Straddle Rules below)

---

## Constructive Sales (Section 1259)

### What It Is

Section 1259 treats certain hedging transactions as constructive sales, triggering capital gain recognition even though the taxpayer has not actually sold the appreciated position.

### Transactions That Trigger Constructive Sales

1. **Short against the box:** Holding an appreciated long position and selling short the same security (or substantially identical property)
2. **Entering a forward contract to deliver the appreciated position**
3. **Entering an equity swap:** Swapping the return on the appreciated position for a fixed or floating return
4. **Entering one or more transactions that have substantially the same effect** as any of the above

### How It Works

When a constructive sale occurs:
1. The taxpayer recognizes gain as if the appreciated position were sold at FMV on the date of the constructive sale
2. The holding period for the position restarts
3. The basis in the appreciated position is increased by the gain recognized

### Exception: 30-Day Closing

A constructive sale does NOT occur if:
- The transaction is closed within 30 days after the end of the tax year AND
- The underlying appreciated position is held without hedging for at least 60 days after closing

### Worked Example

```
Taxpayer holds 10,000 shares of AAPL with a basis of $50 and FMV of $200.
Unrealized gain: $150/share x 10,000 = $1,500,000

Taxpayer enters an equity swap: agrees to pay the return on 10,000 AAPL shares
and receive a fixed 5% return for 3 years.

This is a constructive sale under Section 1259.
  Gain recognized: $1,500,000
  New basis: $200/share
  Holding period restarts

The taxpayer has effectively locked in the gain economically but
must now pay tax on $1,500,000 even though no shares were sold.
```

### Planning Around Section 1259

- **Variable prepaid forward contracts** with sufficient downside exposure may avoid constructive sale treatment (see *Anschutz v. Commissioner*), but this is highly fact-specific
- **Options collars** (buying puts and selling calls) are generally NOT constructive sales unless the collar is too tight (the spread between the put strike and call strike is de minimis)
- **Exchange funds (Section 721):** Contributing appreciated stock to a diversified partnership can defer gain without triggering Section 1259, but Section 721(c) rules apply for related parties

---

## Straddle Rules (Section 1092)

### What Is a Straddle?

A straddle exists when a taxpayer holds offsetting positions in actively traded personal property. If a loss position is closed while the offsetting gain position remains open, the loss is deferred to the extent of the unrecognized gain in the offsetting position.

### Loss Deferral Rule

```
Taxpayer holds:
  Long position in Stock A: unrealized gain of $50,000
  Short position in Stock A (or puts on A): unrealized loss of $30,000

Taxpayer closes the short position, realizing a $30,000 loss.
Long position still open with $50,000 unrealized gain.

Under Section 1092: The $30,000 loss is DEFERRED (not currently deductible)
because there is $50,000 of unrecognized gain in the offsetting position.

The deferred loss is recognized when the offsetting position is closed.
```

### Mixed Straddle Rules

A mixed straddle involves a Section 1256 contract (60/40 treatment) offsetting a non-Section-1256 position. Special elections are available:

1. **Identified straddle election (Section 1092(b)(2)):** The taxpayer identifies the straddle positions and offsets gains and losses. Loss deferral applies but the character of gains/losses is preserved.

2. **Mixed straddle account election (Reg. 1.1092(b)-4T):** All positions in a designated class of property go into an account. Gains and losses are netted periodically. Net gains are treated as 50% long-term and 50% short-term. Net losses are treated as 60% long-term and 40% short-term.

3. **Section 1256(d) election:** Treat the Section 1256 contract in a mixed straddle as NOT a Section 1256 contract, so it loses the 60/40 treatment but avoids the complex mixed straddle rules.

### Holding Period Suspension

If a straddle exists, the holding period of the losing position is suspended (or eliminated) while the straddle is in effect. This can prevent a position from ever qualifying as long-term.

---

## UBTI in Retirement Accounts

### What Is UBTI?

Unrelated Business Taxable Income (UBTI) is income generated by a tax-exempt entity (including IRAs, 401(k)s, HSAs) from an unrelated trade or business. When UBTI exceeds $1,000 in a tax year, the IRA or retirement account must file Form 990-T and pay tax at trust tax rates.

### Common Sources of UBTI in Retirement Accounts

1. **Debt-financed income (Section 514):** If an IRA invests in a partnership that uses leverage (mortgage) to acquire property, the portion of income attributable to the debt is UBTI. This is called Unrelated Debt-Financed Income (UDFI).

2. **Master Limited Partnerships (MLPs) in IRAs:** MLPs typically pass through operating income from an active business (pipeline operations, energy production). This operating income is UBTI to the IRA. Additionally, MLPs often use leverage, generating UDFI.

3. **Partnership interests with active business income:** Any K-1 from a partnership conducting an active trade or business generates UBTI to a retirement account.

4. **Real estate partnerships with leverage:** Even if the underlying activity is rental (not normally UBTI for a direct IRA investment), the use of debt makes a portion of the income UBTI under the debt-financed income rules.

### The $1,000 Threshold

- UBTI below $1,000 is exempt. A specific deduction of $1,000 applies.
- UBTI above $1,000 is taxed at trust income tax rates (which reach 37% at only $15,650 of taxable income for 2025)
- The tax is paid FROM the retirement account, reducing the account balance
- If the IRA custodian fails to file Form 990-T, the IRS can assess penalties

### Worked Example -- MLP in IRA

```
IRA invests $100,000 in an MLP (XYZ Pipeline Partners).
K-1 reports:
  Ordinary business income: $8,000
  Section 179 deduction: ($2,000)
  Depreciation: ($3,000)
  Net UBTI before deduction: $3,000
  Less $1,000 specific deduction: ($1,000)
  Taxable UBTI: $2,000

Tax (at trust rates): ~$220 (10% on first $3,150)

This tax is paid from the IRA.
Over time, MLPs can generate cumulative UBTI that results in
meaningful tax drag inside the tax-advantaged account.
```

### Planning

- **Hold MLPs in taxable accounts** where the K-1 deductions (depreciation, depletion) reduce taxable income and can be offset against the taxpayer's other income
- **Use C-Corp MLP alternatives** (some ETFs hold MLPs inside a C-Corp structure, paying corporate tax internally but issuing a 1099 instead of K-1 -- no UBTI to the IRA)
- **Monitor UBTI annually** for any partnership K-1 received by a retirement account
- **Leveraged real estate funds in IRAs:** Be aware that the debt-financed income portion is UBTI, even if the fund's overall strategy is passive real estate

---

## Net Unrealized Appreciation (NUA)

### What It Is

Net Unrealized Appreciation is a strategy for taxpayers who hold employer stock (company stock) in a 401(k) or other employer-sponsored retirement plan. Instead of rolling the stock into an IRA (where all future distributions are taxed as ordinary income), the taxpayer takes a "lump-sum distribution" and receives the employer stock in kind (transferred to a taxable brokerage account).

### How It Works

1. **At distribution:** The taxpayer pays ordinary income tax ONLY on the cost basis of the employer stock inside the plan (typically the original purchase price or the value when contributed)
2. **The appreciation (NUA):** The difference between the stock's FMV at distribution and the cost basis is NOT taxed at distribution
3. **At sale:** When the stock is eventually sold, the NUA portion is taxed as LONG-TERM capital gain (regardless of holding period after distribution). Any additional appreciation after the distribution date is taxed as short-term or long-term capital gain based on the actual holding period.

### Requirements

The distribution must be a **lump-sum distribution** from the plan, which requires ALL of the following:
- Distribution of the ENTIRE balance in the plan (all employer-sponsored plans of the same type)
- Triggered by one of these events: separation from service, reaching age 59.5, death, or disability (for self-employed only)
- The entire balance is distributed within ONE tax year

### Worked Example -- $200K+ in Tax Savings

```
Employee retires at age 62 with $1,000,000 in her 401(k):
  Employer stock: $800,000 FMV, cost basis $100,000 (NUA = $700,000)
  Other investments (bonds, mutual funds): $200,000

Option A: Roll everything into an IRA
  Future distributions taxed at ordinary rates (up to 37%)
  Tax on $1,000,000 if withdrawn: $370,000 (at 37%)

Option B: NUA Strategy
  Step 1: Roll the $200,000 non-stock assets into an IRA (tax-free rollover)
  Step 2: Distribute the $800,000 of employer stock IN KIND to a taxable brokerage
    - Ordinary tax on cost basis: $100,000 x 37% = $37,000
    - NO tax on the $700,000 NUA at distribution
  Step 3: Sell the stock immediately (or hold for further appreciation)
    - $700,000 NUA taxed at LTCG rate: $700,000 x 20% = $140,000
    - Plus NIIT (3.8%): $700,000 x 3.8% = $26,600

  Total tax: $37,000 + $140,000 + $26,600 = $203,600

Tax savings: $370,000 - $203,600 = $166,400

If the stock is held and appreciates further to $1,200,000:
  Additional $400,000 gain taxed at LTCG rates = $80,000 + $15,200 NIIT
  vs. IRA distribution at ordinary rates = $148,000
  Additional savings on the growth: $52,800

Total potential savings: $219,200+
```

### When NUA Makes Sense

- **Large percentage of employer stock** in the 401(k) with a LOW cost basis
- **High ordinary income tax bracket** (the spread between ordinary rates and LTCG rates is the savings)
- **Immediate or near-term need for the funds** (NUA avoids the 10% early withdrawal penalty on the NUA portion, though the cost basis portion is still subject to penalty if under 59.5)
- **Concentrated stock position is acceptable** (NUA requires holding the actual stock, not diversified assets)

### When NUA Does NOT Make Sense

- **Cost basis is close to FMV** (little NUA, so little benefit)
- **Taxpayer is in a low tax bracket** (the spread between ordinary and LTCG rates is small)
- **Taxpayer wants diversification** immediately (must hold the specific employer stock)
- **Taxpayer plans to leave the IRA to heirs** (the step-up in basis at death for IRA assets distributed as ordinary income may be more favorable than the NUA treatment)

---

## Section 1244 Small Business Stock

### What It Is

Section 1244 allows losses on "small business stock" to be treated as ORDINARY losses rather than capital losses. This is dramatically more valuable because:
- Capital losses are limited to offsetting capital gains plus $3,000/year of ordinary income
- Ordinary losses are fully deductible against all types of income with no annual cap (subject to Section 1244 limits)

### Annual Loss Limits

- **$50,000** per year for single filers
- **$100,000** per year for married filing jointly
- Losses exceeding these amounts are treated as capital losses (subject to the $3,000 limitation)

### Requirements

1. The stock must be issued by a domestic **small business corporation** -- aggregate money and property received by the corporation for stock, as contributions to capital, and as paid-in surplus does not exceed $1,000,000 at the time the stock is issued
2. The stock must be issued for **money or property** (not for services, other stock, or securities)
3. The corporation must have derived more than 50% of its aggregate gross receipts from active business operations (not passive income like rents, royalties, dividends, interest, etc.) during the 5 most recent tax years (or the corporation's entire life if less than 5 years)
4. The stock must be **common stock** (not preferred)
5. Must be original issue stock (purchased directly from the corporation, not on a secondary market)

### Worked Example

```
Taxpayer invests $200,000 in a qualifying small business corporation.
The business fails and the stock becomes worthless.

Without Section 1244:
  Capital loss: $200,000
  Deductible against capital gains: $0 (no gains this year)
  Deductible against ordinary income: $3,000/year
  Time to fully deduct: 66+ years

With Section 1244 (MFJ):
  Year 1: Ordinary loss deduction: $100,000 (fully deductible against W-2, business income, etc.)
  Year 2: Ordinary loss deduction: $100,000
  Fully deducted in 2 years

Tax benefit at 37% rate: $200,000 x 37% = $74,000
vs. capital loss benefit over 66 years (discounted): negligible

Section 1244 turns a financial catastrophe into a meaningful tax benefit.
```

### Documentation

- The corporation should adopt a Section 1244 plan at the time of stock issuance (board resolution)
- Track the amount of money/property received for stock to ensure the $1M aggregate limit
- Maintain records of the corporation's gross receipts to verify the active business test
- The shareholder (not the corporation) claims the Section 1244 loss on their return

---

## Qualified Opportunity Fund (QOF) Multi-Strategy

### Beyond Single Investments

A Qualified Opportunity Fund offers three distinct tax benefits that can be layered:

1. **Deferral:** Capital gains from ANY source (stock sales, real estate, business sales, crypto) can be invested in a QOF within 180 days, deferring the gain recognition
2. **10-year hold basis step-up:** If the QOF investment is held for 10+ years, the basis in the QOF investment is stepped up to FMV -- meaning ALL appreciation in the QOF is tax-free
3. **Underlying asset appreciation:** The QOF invests in Qualified Opportunity Zone Property, which can appreciate significantly in high-growth areas

### Multi-Strategy Approach

```
Taxpayer sells concentrated stock position: $2,000,000 gain

Strategy: Invest $2,000,000 in a diversified QOF that invests in:
  QOZ Business A (tech startup in designated zone): $600,000
  QOZ Real Estate B (multifamily development): $800,000
  QOZ Real Estate C (mixed-use commercial): $600,000

Tax deferral: $2,000,000 gain deferred (recognized by Dec 31, 2026 or sale, whichever is earlier)

If QOF appreciates to $4,000,000 after 10 years:
  Appreciation: $2,000,000
  Tax on appreciation: $0 (10-year step-up to FMV)
  Tax savings on appreciation: $2,000,000 x 23.8% = $476,000

Total benefit:
  Time-value of deferral (gain recognized later) + $476,000 exclusion on growth
```

### Current Timing Considerations (2025)

- The original gain deferral ends December 31, 2026 for most investors -- meaning the deferred gain will be recognized regardless
- New investments made NOW primarily benefit from the 10-year exclusion of appreciation
- The 180-day investment window starts from the date of the gain event (not year-end)
- For partnership gains, the 180-day window can start from either the date of the gain event OR the last day of the partnership's tax year (taxpayer's election)

---

## Municipal Bonds

### Federal Tax Treatment

- Interest from municipal bonds is generally exempt from Federal income tax
- Interest is also exempt from the 3.8% NIIT
- However, municipal bond interest IS included in MAGI for:
  - ACA Premium Tax Credit calculations
  - Social Security benefit taxation
  - Various AGI-based phase-outs

### State Tax Treatment

- Interest from bonds issued by your state of residence: generally exempt from state income tax
- Interest from bonds issued by other states: generally taxable at the state level
- Some states exempt all municipal bond interest regardless of issuer

### Tax-Equivalent Yield

```
Tax-equivalent yield = Municipal yield / (1 - marginal tax rate)

Example: 3.5% municipal yield, 37% Federal + 3.8% NIIT + 8% state = 48.8% combined rate
Tax-equivalent yield = 3.5% / (1 - 0.488) = 6.84%
```

### When Municipal Bonds Make Sense

- High marginal tax rate (32%+ Federal)
- High-income state (NY, CA, NJ, etc.)
- Taxable account (no benefit in IRA/401(k))
- NIIT applies (MAGI > $250K MFJ)

---

## Bond Premium Amortization (Section 171)

### What It Is

When a bond is purchased at a premium (above par value), the premium can be amortized over the remaining life of the bond and used to offset the bond's interest income each year.

### How It Works

- **Taxable bonds:** The premium amortization is deductible as an offset to interest income (not as a separate deduction)
- The taxpayer can elect to amortize bond premium under Section 171
- Once elected, applies to all taxable bonds owned and subsequently acquired
- Amortization reduces the bond's basis each year

### Worked Example

```
Bond purchased for $10,500 (face value $10,000, 5% coupon, 10 years to maturity)
Premium: $500
Annual amortization (simplified straight-line): $500 / 10 = $50/year

Annual interest income reported on 1099-INT: $500
Premium amortization offset: ($50)
Net taxable interest: $450

Without election: $500/year taxable interest, then $500 capital loss at maturity
With election: $450/year taxable interest, $0 gain/loss at maturity

The election smooths the tax benefit and may reduce current-year ordinary income
instead of creating a future capital loss (limited to $3K/year offset).
```

### Tax-Exempt Bond Premium

For tax-exempt municipal bonds, premium amortization is REQUIRED (not elective) under Section 171(a)(2). The premium reduces the bond's basis but does NOT create a deductible amount (since the interest is already tax-exempt). This prevents the taxpayer from claiming a capital loss at maturity on a tax-exempt bond purchased at a premium.

---

## Market Discount Bonds (Section 1276)

### What It Is

A market discount bond is a bond acquired in the secondary market at a price below its stated redemption price at maturity (below par, or below the adjusted issue price for an OID bond). The discount represents income that accrues over the holding period.

### Default Treatment (Section 1276)

- When a market discount bond is sold or redeemed, gain is treated as **ordinary income** to the extent of the accrued market discount
- Only the gain in EXCESS of accrued market discount is treated as capital gain
- This is worse than capital gain treatment (37% vs. 20%)

### De Minimis Exception

If the market discount is less than 0.25% of the stated redemption price multiplied by the number of complete years to maturity, the discount is treated as zero (no ordinary income recharacterization).

```
Bond: $10,000 face value, 8 years to maturity
De minimis threshold: $10,000 x 0.25% x 8 = $200
If purchased for $9,850 (discount = $150 < $200): de minimis applies, all gain is capital
If purchased for $9,700 (discount = $300 > $200): market discount rules apply
```

### Section 1278(b) Election to Accrue Market Discount Annually

Instead of recognizing all accrued market discount as ordinary income at disposition, the taxpayer can elect to include market discount in income currently (as it accrues each year).

**Advantages of the annual accrual election:**
- Converts the character from a lump-sum ordinary income recognition at sale to annual ordinary income recognition
- Allows the taxpayer to increase basis annually, potentially creating a capital loss (or smaller gain) at sale
- Interest expense on debt incurred to purchase the bond is currently deductible (without the election, interest deductions attributable to market discount bonds are deferred)

**The election is made on the return for the first year it applies and is binding for all subsequent market discount bonds.**

---

## Payments in Lieu (PILs) from Securities Lending

### What They Are

When a broker lends out your shares (common in margin accounts), you may receive "payments in lieu of dividends" instead of actual dividends.

### Tax Impact

- PILs are taxed as **ordinary income**, NOT qualified dividends
- This eliminates the preferential rate (0%/15%/20%) on what would have been qualified dividends
- PILs do NOT qualify for the foreign tax credit (if the underlying dividend would have)
- Reported on Form 1099-MISC (not 1099-DIV)

### How to Avoid

- Opt out of securities lending programs (if your broker allows)
- Use a cash account (not margin) -- lending typically requires margin authorization
- Check broker statements for PILs and request shares not be lent

### Recall Shares Before Record Date

If you receive PILs despite holding dividend-paying stocks in a margin account, contact your broker to **recall the shares** before the dividend record date. Once the shares are recalled (returned from the borrower), you receive the actual dividend (qualified treatment) rather than a PIL.

**Timing:** You must recall shares before the record date, not the ex-dividend date. The record date is typically 1-2 business days after the ex-date. Some brokers automate this for large positions if you request it.

---

## Short Sale Rules

### Holding Period for Short Sales

When a taxpayer sells stock short (borrowing and selling shares with the intent to buy back later at a lower price):

- If the taxpayer holds substantially identical property on the date of the short sale, the holding period for that property resets to zero (Section 1233(b))
- This means a long-term gain can be converted to short-term
- Gain on closing a short sale is short-term unless the short sale was open for more than one year AND the taxpayer did not hold substantially identical property

### Substantially Identical Property

For short sale purposes, "substantially identical" has the same meaning as for wash sales:
- Same stock or security
- Convertible bonds or preferred stock convertible into the stock
- Options to acquire the stock

### Example

```
January 1: Taxpayer holds 1,000 shares of XYZ (purchased 2 years ago, LTCG holding)
January 15: Taxpayer sells short 1,000 shares of XYZ at $100
March 1: Taxpayer closes the short by delivering the long-held shares

Result: The gain on the delivered shares is SHORT-TERM (the 2-year holding period
was reset when the short position was opened on January 15).

This is the "short against the box" rule -- it prevents taxpayers from
locking in gains through short sales while maintaining long-term character.
```

---

## Carried Interest (Section 1061)

### What It Is

Section 1061 requires a 3-year holding period (instead of 1 year) for capital gains allocated to holders of "applicable partnership interests" (carried interest) to qualify for long-term capital gain treatment.

### Who It Affects

- Private equity fund managers
- Venture capital fund managers
- Hedge fund managers
- Real estate fund managers
- Any person who receives a partnership interest in exchange for services (the "profits interest" or "carried interest")

### How It Works

- Capital gains from the sale of assets held by the partnership for 1-3 years that are allocated to the carried interest holder are recharacterized as **short-term capital gain** (ordinary rates)
- Only capital gains from assets held MORE THAN 3 YEARS qualify for LTCG treatment
- The 3-year requirement applies to the partnership's holding period of the underlying asset, not the manager's holding period of the carried interest

### Exceptions

The 3-year holding period does NOT apply to:
1. **Capital interests:** Gains attributable to the manager's actual capital contribution (as opposed to the carried interest portion) retain the normal 1-year holding period
2. **Section 1231 gains:** Gains from Section 1231 assets (real property, depreciable business property) are not subject to Section 1061
3. **Certain partnership interests:** Interests in partnerships that invest substantially all assets in real estate, not providing services to the partnership

### Planning

- Fund managers should separately track gains attributable to their capital interest vs. carried interest
- Structure investments to hold underlying assets for 3+ years
- Real estate fund managers may benefit from the Section 1231 exception
- The distinction between capital interest and profits interest is critical for tax reporting

---

## Installment Sale to Related Party (Section 453(e))

### The Related Party Resale Rule

When a taxpayer sells property to a related party on the installment method, and the related party resells the property within 2 years, the deferred gain is accelerated.

### How It Works

1. Taxpayer sells appreciated property to a related party (spouse, child, controlled entity, etc.) on installment terms
2. The related party resells the property within 2 years of the original sale
3. On the date of the resale, the original seller must recognize gain equal to the amount realized by the related party on the resale (minus payments already received from the related party)

### Purpose

Congress enacted this rule to prevent taxpayers from doing an end-run around gain recognition:
- Sell to a related party on installment terms (defer gain)
- Related party immediately sells for cash (gets the money)
- Related party funnels money back to the original seller through the installment payments

### Exceptions

The 2-year resale rule does NOT apply to:
1. **Involuntary conversions** of the property by the related party
2. **Transactions where it is established that tax avoidance was NOT a principal purpose** (very hard to prove)
3. **Marketable securities** (these are already excluded from installment sale treatment under Section 453(k))

### Worked Example

```
Father sells rental property to Son on January 1, 2025:
  Sale price: $500,000, Basis: $200,000, Gain: $300,000
  Terms: $100,000 down, $100,000/year for 4 years (no interest for simplicity)
  Gross profit ratio: 60%

Father's gain recognition on $100,000 down payment: $60,000

June 1, 2025: Son resells the property to unrelated buyer for $550,000 (cash).

Under Section 453(e):
  Father must recognize gain as if he received the full $550,000 immediately.
  Amount realized by Son: $550,000
  Less: payments Father already received: $100,000
  Acceleration amount: $450,000
  But Father's remaining deferred gain is only: $300,000 - $60,000 = $240,000
  Father recognizes $240,000 of gain in 2025 (in addition to the $60,000 already recognized)

Result: Father's installment deferral is completely unwound.
```

---

## Options Taxation

### Incentive Stock Options (ISOs)

- **Exercise:** No regular income tax at exercise (but the spread IS an AMT preference item)
- **Sale (qualifying disposition):** If held 2+ years from grant and 1+ year from exercise, all gain is long-term capital gain
- **Sale (disqualifying disposition):** If holding periods not met, spread at exercise is ordinary income; remaining gain is capital gain
- **AMT trap:** The spread at exercise can trigger significant AMT in the exercise year; plan accordingly

### Non-Qualified Stock Options (NSOs/NQSOs)

- **Exercise:** Spread (FMV - exercise price) is ordinary income, subject to withholding and FICA
- **Sale:** Gain/loss above FMV at exercise is capital gain/loss (short-term or long-term based on holding period from exercise date)
- **No AMT implications** at exercise (the income is already recognized for regular tax)

### Employee Stock Purchase Plan (ESPP)

- Typically allows purchase at 15% discount to lower of grant-date or purchase-date price
- **Qualifying disposition** (2+ years from offering date, 1+ year from purchase): discount taxed as ordinary income; additional gain is LTCG
- **Disqualifying disposition:** Discount at purchase taxed as ordinary income; remaining gain/loss is capital gain/loss

### AMT Planning for ISOs

- Calculate the AMT impact BEFORE exercising ISOs
- Consider exercising in stages over multiple years to stay below AMT trigger
- Exercise and sell in the same year (same-day sale) to avoid AMT (but all gain is ordinary income)
- AMT credit from ISO exercise can be recovered in future years when regular tax exceeds AMT

---

## Net Investment Income Tax (NIIT) Strategies

### What Counts as Net Investment Income

- Interest, dividends, capital gains, rental income (passive), royalties
- Income from passive business activities
- Gains from sale of partnership/S-Corp interests (passive portion)

### What Does NOT Count

- Wages, self-employment income
- Income from businesses in which you materially participate
- Social Security benefits
- Tax-exempt interest
- Distributions from retirement plans (but these affect MAGI)

### Strategies to Reduce NIIT

1. **Material participation:** Convert passive income to non-passive by meeting material participation tests
2. **RE Professional status:** Can convert rental income to non-passive
3. **Increase deductions:** Retirement contributions, charitable giving reduce MAGI
4. **Tax-loss harvesting:** Reduces net investment income
5. **Municipal bonds:** Interest excluded from net investment income
6. **Timing:** Defer income to years when MAGI may be lower
7. **Installment sales:** Spread gain recognition to stay below thresholds
8. **Roth conversions:** Pay tax now, reduce future investment income and MAGI

---

## Collectibles and Alternative Investments

### Collectibles (28% Rate)

Long-term capital gains on collectibles are taxed at a maximum rate of 28% (not the usual 0/15/20%):
- Art, antiques, gems, stamps, coins
- Precious metals (gold, silver, platinum) -- including ETFs backed by physical metals
- Rugs, wines, baseball cards

### Section 1202 QSBS

Gain on Qualified Small Business Stock held 5+ years may be excluded up to $10M (or 10x basis). See ENTITY-STRATEGIES.md for details.

### Section 1244 Stock

Losses on Section 1244 small business stock (up to $50K single / $100K MFJ per year) are treated as ordinary losses (not capital losses) -- much more valuable for tax purposes. See the dedicated Section 1244 section above for requirements and worked examples.

---

## Asset Location Strategy

### Concept

Place investments in the most tax-efficient account type based on their tax characteristics.

### Optimal Placement

| Investment Type | Best Account Type | Reason |
|---|---|---|
| Taxable bonds / bond funds | Tax-deferred (Traditional IRA/401(k)) | Interest taxed at ordinary rates |
| REITs | Tax-deferred | Dividends taxed at ordinary rates |
| High-turnover active funds | Tax-deferred | Frequent short-term gains |
| MLPs | Taxable account | Avoid UBTI in retirement accounts |
| Tax-efficient index funds | Taxable account | Low turnover, qualified dividends, LTCG |
| Growth stocks (no/low dividends) | Taxable or Roth | Low current tax drag; Roth for highest growth potential |
| Municipal bonds | Taxable account only | Tax benefit lost in tax-deferred accounts |
| Employer stock (ESPP/RSU) | Taxable (by default) | Consider diversification and tax timing |
| Section 1256 contracts | Taxable account | 60/40 treatment only matters in taxable accounts |
| Market discount bonds | Tax-deferred | Avoids ordinary income recharacterization |

### Why This Matters

A portfolio with the same total allocation but poor asset location can pay 0.5-1.0% more in taxes annually. Over decades, this compounds significantly.

---

## Year-End Investment Tax Planning Checklist

1. **Review realized gains and losses** year-to-date
2. **Identify tax-loss harvesting opportunities** in November
3. **Check mutual fund capital gain distribution estimates** (published by fund companies in November)
4. **Consider Roth conversions** if in a low-income year
5. **Donate appreciated stock** to charity or DAF before year-end
6. **Review asset location** and rebalance in tax-efficient manner
7. **Exercise ISOs strategically** with AMT calculation
8. **Realize gains in the 0% bracket** if applicable (retirees, gap years)
9. **Check wash sale exposure** from automated reinvestment (DRIP, automatic investments)
10. **Review payments in lieu** on 1099s and consider opting out of securities lending
11. **Mark-to-market check** for Section 1256 contracts (gains recognized even on open positions)
12. **Review straddle positions** for deferred losses that can be released
13. **Check UBTI** on any partnership K-1s flowing to retirement accounts (file Form 990-T if over $1,000)
14. **Evaluate NUA opportunity** if separating from employer with appreciated company stock in 401(k)
15. **Verify holding periods** for qualified dividend treatment before selling dividend stocks
16. **Review bond premium amortization** and market discount accrual elections
17. **Assess carried interest positions** for the 3-year holding period under Section 1061
