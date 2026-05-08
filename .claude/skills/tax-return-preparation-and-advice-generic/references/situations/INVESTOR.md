# Investor Reference (Tax Year 2025)

## Overview

Investors report investment income and capital gains/losses across multiple forms and schedules. Proper classification of income (ordinary vs. capital, short-term vs. long-term, qualified vs. non-qualified), strategic use of losses, and asset location optimization can significantly reduce tax liability. This reference covers taxable brokerage accounts, not retirement accounts (which are covered under RETIREE.md).

## Key Tax Considerations

### Capital Gains Tax Rates (2025)
- **Short-term capital gains** (held 1 year or less): taxed as ordinary income (10%-37%)
- **Long-term capital gains** (held more than 1 year): preferential rates:
  - 0% rate: taxable income up to $48,350 (single) / $96,700 (MFJ)
  - 15% rate: taxable income up to $533,400 (single) / $600,050 (MFJ)
  - 20% rate: taxable income above those thresholds
- **Collectibles** (art, coins, precious metals, stamps): 28% max rate on long-term gains
- **Section 1250 unrecaptured gain** (depreciation on real estate): 25% max rate
- **Qualified Small Business Stock (Section 1202)**: up to 100% exclusion if requirements met
  (C-corp, $50M asset limit at issuance, 5-year holding period, acquired at original issuance)

### Capital Gains Bracket Optimization
- **Harvesting gains in the 0% bracket**: MFJ couples with taxable income under $96,700
  (after deductions) can realize LTCG at 0% federal tax
- **Strategy for early retirees, sabbatical years, gap years**: deliberately sell appreciated
  positions to "fill up" the 0% bracket. Resets basis to current FMV.
- **Example**: MFJ couple with $60,000 ordinary income, $31,500 standard deduction.
  Taxable income before LTCG = $28,500. Can realize $96,700 - $28,500 = $68,200 of LTCG
  at 0% federal rate. On $68K of gains, this saves ~$10,230 (vs. 15% rate).
- **Watch out**: realized gains increase MAGI, which affects: ACA premium tax credits,
  NIIT threshold, Medicare Part B premiums (IRMAA), student loan IDR payments.

### Qualified Dividends
- Taxed at long-term capital gains rates (0%/15%/20%)
- Must meet holding period: held stock for more than 60 days during the 121-day period
  beginning 60 days before ex-dividend date (90/181 days for preferred stock)
- Most domestic corporate dividends and many foreign dividends qualify
- Non-qualifying: REITs, MLPs, money market funds, short-sale-related dividends,
  dividends on shares lent in securities lending (payments in lieu — see below)

### Ordinary Dividends and Interest
- Taxed at ordinary income rates
- Includes: non-qualified dividends, REIT distributions (may qualify for 20% Section 199A
  deduction), bond interest, bank interest, CD interest
- Report on Schedule B if total exceeds $1,500

### Net Investment Income Tax (NIIT) — Section 1411
- 3.8% surtax on the lesser of: net investment income OR MAGI exceeding $200,000 (single) /
  $250,000 (MFJ)
- Applies to: interest, dividends, capital gains, rental income, royalties, passive business income
- Does NOT apply to: wages, SE income, tax-exempt interest, distributions from retirement plans,
  Social Security, income from active trade/business in which taxpayer materially participates
- Report on Form 8960

### NIIT Planning Strategies
- **Material participation in S-Corp**: if a business owner materially participates, the S-Corp
  income is NOT subject to NIIT (it is active, not investment income). Contrast with a passive
  K-1 investor who IS subject to NIIT.
- **RE Professional status**: rental income of a qualifying RE Professional who materially
  participates is arguably NOT net investment income (Reg. §1.1411-4(g)(7) provides a
  special election for RE Professionals).
- **S-Corp election for rental activity**: does NOT work — rental income is still rental
  income regardless of entity. The RE Professional election is the proper approach.
- **Timing income**: if near the MAGI threshold, defer income recognition to a year when
  AGI will be below $250K (MFJ).

## Tax-Loss Harvesting

### Strategy
- Sell investments at a loss to offset capital gains
- Net short-term losses first offset short-term gains; net long-term losses first offset
  long-term gains; then cross-offset
- Up to $3,000 of net capital losses ($1,500 MFS) can offset ordinary income per year
- Excess losses carry forward indefinitely (but do NOT carry back for individuals)
- Maintain portfolio exposure by purchasing a similar (but not substantially identical) investment

### Wash Sale Rule (IRC §1091)
- Loss disallowed if you purchase substantially identical securities within 30 days before
  or after the sale (61-day window)
- Disallowed loss is added to the basis of the replacement shares (not lost — deferred)
- Applies across ALL accounts (IRA, spouse's account, entities you control)
- "Substantially identical": same security; same class of stock in same company; ETFs tracking
  same narrow index (broad market ETFs generally OK to swap — e.g., S&P 500 ETF to total market ETF)
- No wash sale rule for gains — you can immediately repurchase after a gain sale
- **Wash sale into an IRA**: loss disallowed AND basis adjustment is permanently lost (the IRA
  does not track basis for this purpose). This is the worst outcome.
- Cross-reference: WASH-SALE-RULES.md for complete treatment

### Constructive Sale Rules (IRC §1259)
- Cannot lock in gain without triggering tax by entering offsetting positions
- **Triggers**: short sale against the box, entering into futures/forward contract for owned
  shares, acquiring a put + writing a call at same strike (synthetic short)
- **Exception**: certain limited risk-reduction transactions that do not eliminate substantially
  all risk of loss and opportunity for gain
- If triggered: gain recognized as if sold at FMV on date of constructive sale; holding period
  resets. Loss is NOT recognized in a constructive sale.
- **Example**: investor owns 10,000 shares of XYZ at $50 (basis $10). Shorts 10,000 shares
  of XYZ = constructive sale. Must recognize $400K gain even though no actual sale occurred.

### Straddle Rules (IRC §1092)
- A "straddle" exists when you hold offsetting positions in personal property (stocks, options,
  futures, etc.)
- **Loss deferral**: losses on one leg of a straddle are deferred to the extent of unrealized
  gain in the offsetting position
- **Holding period**: holding period does not begin until the offsetting position is closed
- **Interest and carrying charges**: may need to be capitalized rather than currently deducted
- These rules primarily affect options traders, futures traders, and sophisticated hedgers

## Section 1256 Contracts — 60/40 Treatment (IRC §1256)

- Applies to: regulated futures contracts, foreign currency contracts, nonequity options
  (broad-based index options like SPX), dealer equity options, dealer securities futures contracts
- **Mark-to-market**: all open positions are treated as sold at FMV on Dec 31
- **60/40 rule**: regardless of actual holding period, gains/losses are treated as 60% long-term
  and 40% short-term
- **Benefit**: even short-term trading of §1256 contracts gets blended rate (~26.8% max for
  MFJ in top bracket vs. 37% for regular short-term gains)
- **Loss carryback**: §1256 losses can be carried BACK 3 years (applied only against §1256 gains
  in those years). Unique provision — other capital losses cannot be carried back.
- Report on Form 6781

## Margin Interest Deduction (IRC §163(d))

### Basic Rules
- Interest paid on margin loans is **investment interest expense**
- Deductible on Schedule A as itemized deduction
- **Limited to net investment income** (investment income minus investment expenses)

### Net Investment Income Calculation for §163(d)
- Investment income = interest, non-qualified dividends, short-term capital gains, royalties
- By default: qualified dividends and long-term capital gains are NOT included
- **Election**: can elect to treat qualified dividends and/or net LTCG as investment income
  for purposes of §163(d), but they then lose preferential rate treatment (taxed at ordinary rates)
- This election is made on Form 4952 and is irrevocable for that year

### Carrying Charges
- Excess investment interest carries forward indefinitely (no expiration)
- Track carryforward on Form 4952 year-to-year

### Example
- Margin interest paid: $15,000
- Investment income (interest, non-qualified dividends, short-term gains): $8,000
- Qualified dividends: $12,000
- LTCG: $20,000
- Without election: deductible = $8,000. Carryforward = $7,000.
- With election to include qualified dividends: deductible = $15,000 (full amount). But the
  $12,000 of qualified dividends is now taxed at ordinary rates (up to 37% instead of 20%).
  Net benefit depends on marginal rate and amount of margin interest.

## Short Sale Rules

### Holding Period
- Short sale of stock you already own (short against the box): constructive sale under §1259
- Short sale of stock you do NOT own: gain/loss is short-term if you held the delivered shares
  for 1 year or less at the time of closing. The holding period of shares used to close the
  short does NOT include the period of the short sale.
- **Substantially identical property**: if you hold stock and sell short substantially identical
  stock, the holding period of the long position is suspended or eliminated.
  This prevents converting short-term gains to long-term.

### Payments in Lieu (PILs) from Securities Lending
- When a broker lends your shares to a short seller, dividends paid during the lending period
  come as "payments in lieu of dividends" (PILs)
- PILs do NOT qualify as "qualified dividends" — taxed at ordinary income rates
- Reported on Form 1099-MISC (not 1099-DIV)
- Cross-reference: PILs-SECURITIES-LENDING.md if available

## Tax-Lot Optimization

### Identification Methods
- **Specific identification**: designate which lots to sell at the time of sale. Requires
  written confirmation from broker. Maximum control over gain/loss recognition.
- **FIFO (First In, First Out)**: default method if no specific identification. Oldest shares
  sold first — typically produces largest gain (highest appreciation).
- **Average cost**: available ONLY for mutual fund shares and certain dividend reinvestment
  plans. Once elected, applies to all shares in that account for that fund.

### Strategy
- **Sell highest-basis lots first** to minimize gain (or maximize loss)
- **Sell specific low-basis lots** when you want to realize gains (e.g., to fill the 0% bracket
  or to harvest gains before a rate increase)
- **Must designate at or before the time of sale** — cannot retroactively choose lots
- Most brokers support specific identification through online platforms; confirm the default
  method your broker uses (often FIFO)

## ETF vs. Mutual Fund Tax Efficiency

### Why ETFs Are More Tax-Efficient
- ETFs use the **in-kind creation/redemption** process: when large holders redeem shares,
  the ETF delivers low-basis stock in kind (not cash). This purges embedded capital gains
  without triggering taxable events for remaining shareholders.
- Mutual funds must sell holdings to meet redemptions, distributing realized gains to all
  shareholders (even those who just bought in).
- Result: many ETFs distribute zero capital gains for years; actively managed mutual funds
  often distribute large annual capital gains.

### When Mutual Funds May Be Acceptable
- Tax-deferred accounts (IRA, 401(k)): tax efficiency is irrelevant
- Index funds with very low turnover (e.g., Vanguard Total Market Index)
- Tax-managed funds that actively harvest losses and manage distributions

## Municipal Bond Analysis

- Interest is exempt from federal income tax
- If bond is from your state of residence: typically exempt from state tax too ("double tax-free")
- Private activity bond interest may be an AMT preference item
- **Taxable equivalent yield calculation**: muni yield / (1 - marginal tax rate)
- Example: 3.5% muni at 37% federal + 3.8% NIIT + 13.3% CA state = 3.5% / (1 - 0.541) = 7.63%
  taxable equivalent (extremely attractive for high-income CA residents)
- Capital gains on muni bond sales ARE taxable
- Market discount on munis: taxable as ordinary income (can elect to accrue annually)
- **De minimis rule**: if you buy a muni at a discount less than 0.25% x years to maturity,
  the discount is capital gain, not ordinary income

## UBTI in IRAs from Leveraged Investments

- **Unrelated Business Taxable Income (UBTI)**: if an IRA holds investments that generate
  "debt-financed income" (leveraged real estate, MLPs with leverage, leveraged ETNs), the IRA
  may owe UBTI tax (IRC §511-514)
- UBTI exemption: first $1,000 is exempt
- Tax rate: trust tax rates (37% above ~$15,450) — extremely compressed brackets
- **Common triggers**: MLP K-1s with UBTI, leveraged real estate partnerships, margin trading
  within an IRA (if allowed by custodian)
- Report on Form 990-T (filed by the IRA, not the individual)
- **Practical tip**: avoid holding MLPs generating significant UBTI in IRAs. A small MLP
  position may not trigger tax (under $1,000 UBTI), but large allocations will.

## Asset Location Strategy

Optimize which account type holds which investments:

| Asset Type | Best Account Location | Rationale |
|-----------|----------------------|-----------|
| Taxable bonds | Tax-deferred (IRA/401k) | High ordinary income tax rate |
| REITs | Tax-deferred | Dividends taxed as ordinary income |
| High-turnover funds | Tax-deferred | Frequent short-term gains |
| Growth stocks (low dividend) | Taxable | Benefit from LTCG rate + step-up at death |
| Index funds (tax-efficient) | Taxable | Low distributions, tax-loss harvesting possible |
| Municipal bonds | Taxable | Already tax-exempt; wasted in tax-deferred |
| International stocks | Taxable | Preserve foreign tax credit eligibility |
| MLPs | Taxable | Avoid UBTI issues in IRA |

## Applicable Forms

| Form | Purpose |
|------|---------|
| Form 8949 | Sales and Other Dispositions of Capital Assets (detail of each transaction) |
| Schedule D | Capital Gains and Losses (summary) |
| Schedule B | Interest and Ordinary Dividends (if > $1,500) |
| Form 8960 | Net Investment Income Tax |
| Form 4952 | Investment Interest Expense Deduction |
| Form 6781 | Section 1256 Contracts (60/40 gains) |
| Form 8995/8995-A | QBI deduction for REIT/PTP income |
| Form 1099-B | Proceeds from Broker Transactions |
| Form 1099-DIV | Dividends and Distributions |
| Form 1099-INT | Interest Income |

## Optimization Strategies

1. **Harvest losses throughout the year** — don't wait until December; monitor portfolio quarterly
2. **Donate appreciated stock to charity** — avoid capital gains AND get fair market value
   deduction (if held > 1 year). Max 30% of AGI for appreciated property.
3. **Use specific identification method** — select highest-basis lots for sale to minimize gains;
   requires broker designation at time of sale
4. **Time gains to 0% bracket** — in lower-income years (sabbatical, early retirement, gap year),
   realize gains at 0% rate up to $96,700 (MFJ)
5. **Offset gains with prior-year carryforward losses** — track your loss carryforward carefully;
   it does not appear on 1099s
6. **Installment sales for concentrated positions** — spread gain recognition over multiple years
   (Section 453). Cannot use for publicly traded stock.
7. **Opportunity Zone investment** — invest capital gains in qualified opportunity zone funds for
   deferral and potential exclusion (Section 1400Z-2)
8. **Consider direct indexing** — hold individual stocks instead of funds for granular
   tax-loss harvesting. Automated platforms (Wealthfront, Parametric) manage this.
9. **Use §1256 contracts for short-term trading** — SPX options, futures get automatic
   60/40 treatment. At top bracket: ~26.8% blended vs. 37% straight short-term rate.
10. **Elect to include LTCG in investment income** — only when margin interest deduction benefit
    exceeds the cost of losing preferential rate on LTCG.

## Cryptocurrency Considerations

- IRS treats crypto as property, not currency — every disposal is a taxable event
- Taxable events: selling for fiat, exchanging one crypto for another, spending crypto, receiving as payment
- NOT taxable: transferring between your own wallets, buying crypto with fiat (no gain/loss until disposal)
- Cost basis methods: specific identification (preferred), FIFO (default if not specified)
- Reporting: Form 8949 for each transaction; brokers required to issue 1099-DA starting 2026
- Mining/staking rewards: ordinary income at FMV when received
- DeFi transactions: complex; each protocol interaction may be a taxable event
- Wash sale rule: currently does NOT explicitly apply to crypto (it references "stock or securities"),
  but legislation pending; apply cautiously

## Common Mistakes

1. **Ignoring wash sale rules across accounts** — buying in IRA within 30 days of selling at a
   loss in taxable account permanently destroys the loss
2. **Not reporting cost basis correctly** — brokers may not have basis for shares transferred in;
   you must track it. Form 8949 Column (f) adjustments are critical.
3. **Forgetting to report crypto transactions** — IRS receives data from exchanges; Form 1040
   asks directly about digital assets
4. **Missing the NIIT** — 3.8% surtax often overlooked in planning; applies above $200K/$250K MAGI
5. **Not carrying forward capital losses** — prior-year losses do not auto-populate on tax
   software from 1099s; must manually track (Schedule D, Line 6/14 carryforward worksheet)
6. **Failing to elect specific identification** — defaulting to FIFO may trigger larger gains
7. **Selling winners in December and losers in January** — reverses the benefit; harvest losses
   before year-end, defer gains if possible
8. **Not adjusting Form 8949 for RSU/ESPP basis** — brokers often report $0 basis on 1099-B
   for equity compensation shares. Failing to add the correct basis results in double taxation.
9. **Ignoring §1256 contract opportunities** — options traders using equity options (taxed as
   regular short/long-term) when index options (§1256, 60/40) achieve similar exposure
10. **UBTI surprise in IRA** — holding leveraged MLPs or partnerships generating >$1,000 UBTI
    triggers Form 990-T filing and trust-rate tax inside the IRA

## State-Specific Notes

- **California**: taxes capital gains as ordinary income (up to 13.3%); no preferential rate.
  Muni bonds from other states are taxable at state level.
- **New York**: same — capital gains taxed as ordinary income at state level. NY muni bonds
  are exempt from NY/NYC tax.
- **New Hampshire**: taxes interest and dividends at 3% (phasing out by 2027)
- **Washington**: 7% tax on LTCG above $270,000 (starting 2025). Only capital gains, not
  interest/dividends. Upheld by state supreme court as an "excise tax."
- **Florida, Texas, Nevada, Wyoming, Tennessee**: no state income tax on investment income
- Most states do not have a separate NIIT equivalent
- State treatment of municipal bond interest varies: most exempt in-state bonds but tax
  out-of-state bond interest
- Some states have their own capital loss limitation amounts different from the $3,000 federal limit
