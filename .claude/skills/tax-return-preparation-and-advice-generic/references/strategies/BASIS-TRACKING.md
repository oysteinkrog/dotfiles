# BASIS TRACKING — Comprehensive Guide to Tax Basis Across All Asset Types

## Overview

Basis is the foundational concept in tax accounting — it determines the gain or loss on every disposition, the amount of depreciation allowable, and the deductibility of losses from pass-through entities. Incorrect basis tracking is the single most common cause of overpaid taxes (failing to include improvements, missing inherited basis step-ups) and underpaid taxes (forgetting depreciation recapture, double-counting losses). This guide covers basis rules for every major asset category.

---

## S-CORP SHAREHOLDER BASIS — THE FOUR GATES

### Stock Basis Calculation

S-Corp shareholder stock basis is tracked on a per-share, per-day basis. The annual adjustment order (ss1367):

```
Starting stock basis (beginning of year)
  + Separately and non-separately stated income items
  + Tax-exempt income
  + Excess depletion deduction
  - Non-deductible, non-capital expenses (e.g., 50% meals, penalties)
  - Distributions (but not below zero)
  - Losses and deductions (only to extent of remaining basis after distributions)
= Ending stock basis (cannot go below zero)
```

**Critical ordering rule** (Reg. ss1.1367-1(f)): Income increases are applied BEFORE distribution decreases, and distributions are applied BEFORE loss decreases. This ordering can allow a shareholder to take a distribution AND deduct losses in the same year — but only if income increases provide enough basis first.

### Debt Basis (ss1366(d)(1)(A))

If stock basis reaches zero, a shareholder with DIRECT loans to the S-Corp can use debt basis to deduct additional losses:

- Debt basis = Outstanding balance of shareholder's direct loans to the S-Corp
- Does NOT include bank loans guaranteed by the shareholder (unlike partnerships)
- Does NOT include loans from related parties on behalf of the shareholder
- Debt basis is reduced by losses deducted against it

**Key case**: Oren v. Commissioner, T.C. Memo 2002-172 — taxpayer's guarantee of S-Corp debt did NOT create basis. Only actual economic outlay (a direct loan from the shareholder to the corporation) creates debt basis.

**Restore debt basis before stock basis**: When S-Corp income restores basis, debt basis is restored FIRST (to the extent previously reduced), then stock basis. This is counterintuitive but explicitly required by ss1367(b)(2)(B).

### Accumulated Adjustments Account (AAA)

AAA tracks the cumulative net income of the S-Corp that has been previously taxed but not yet distributed. It is a corporate-level account (not per-shareholder):

- Increased by income items (same as stock basis increases)
- Decreased by losses, deductions, and distributions
- CAN go negative (unlike stock basis)
- Used to determine whether distributions are tax-free returns of previously taxed income or dividends from C-Corp accumulated E&P (if the S-Corp was formerly a C-Corp)

**Why AAA matters**: If the S-Corp has accumulated E&P from C-Corp years, distributions in excess of AAA are treated as dividends (taxable as qualified dividends). AAA ensures that S-Corp earnings are distributed tax-free before dipping into C-Corp E&P.

### Other Adjustments Account (OAA)

Tracks tax-exempt income and related expenses. Distributions from OAA are tax-free. Relevant primarily for S-Corps that received PPP loan forgiveness (tax-exempt income that increases OAA and stock basis).

### The Four Loss Limitation Gates

S-Corp losses pass through to shareholders but must clear FOUR sequential gates:

**Gate 1: Stock and Debt Basis (ss1366(d))**
- Loss limited to combined stock + debt basis
- Excess loss is suspended and carried forward indefinitely
- Suspended losses are personal to the shareholder (do not transfer with stock sale)

**Gate 2: At-Risk Rules (ss465)**
- Loss limited to amounts "at risk" — generally amounts the shareholder could actually lose
- For S-Corps, at-risk amount ≈ stock basis + debt basis (direct loans only)
- At-risk suspended losses carry forward

**Gate 3: Passive Activity Rules (ss469)**
- If the shareholder does NOT materially participate, losses are passive
- Passive losses can only offset passive income
- Exceptions: $25K rental allowance (if AGI < $150K), Real Estate Professional, Short-Term Rental

**Gate 4: Excess Business Loss Limitation (ss461(l))**
- After passing Gates 1-3, losses exceeding $305,000 (single) / $610,000 (MFJ) in 2025 are DISALLOWED
- Treated as an NOL carryforward to the next year
- Applies to aggregate business losses across ALL activities

**Worked Example — Four Gates**:
- S-Corp loss: $200,000
- Stock basis: $120,000, Debt basis: $30,000
- At-risk: $150,000
- Shareholder materially participates (non-passive)
- Other business income: $100,000
- Filing: Single

| Gate | Allowed | Suspended |
|---|---|---|
| 1. Basis | $150,000 | $50,000 (suspended, no basis) |
| 2. At-risk | $150,000 | $0 (at-risk = basis for S-Corps) |
| 3. Passive | $150,000 (non-passive, material participation) | $0 |
| 4. Excess business loss | $150,000 - $100,000 other income = $50,000 net loss, under $305K limit | $0 |
| **Final deductible** | **$150,000** | **$50,000 at Gate 1** |

---

## PARTNERSHIP OUTSIDE BASIS

### Key Concepts

**Outside basis**: The partner's basis in their partnership interest (what they could deduct if the partnership dissolved and they received their share of assets). Tracked on each partner's own records.

**Inside basis**: The partnership's basis in its assets. Tracked on the partnership's books. Does NOT directly limit partner deductions.

**Tax basis capital**: Starting in 2020, partnerships must report each partner's tax basis capital on Schedule K-1 (Item L). This is the partner's share of the partnership's assets minus liabilities at tax basis.

### Outside Basis Calculation

```
Initial contribution (cash + FMV of contributed property)
  + Allocable share of partnership income (all items)
  + Allocable share of tax-exempt income
  + Share of partnership liabilities (ss752)
  - Allocable share of partnership losses
  - Distributions received (cash + FMV of distributed property)
  - Share of non-deductible, non-capital expenses
  - Decrease in share of partnership liabilities (ss752)
= Adjusted outside basis (cannot go below zero)
```

### ss752 Liability Allocations — The Complexity Driver

Partnership liabilities increase outside basis — this is a fundamental difference from S-Corps (where guarantees DON'T create basis). The allocation rules depend on liability type:

**Recourse liabilities** (ss752(a), Reg. ss1.752-2):
- Allocated to the partner who bears the Economic Risk of Loss (EROL)
- EROL = the partner who would be obligated to pay the creditor if the partnership were to constructively liquidate (all assets worthless, all liabilities due)
- General partners: typically bear EROL for recourse debts
- Limited partners: typically have NO EROL (capped at their investment)
- Guarantees: A partner who guarantees a partnership debt may have EROL — increases their basis

**Nonrecourse liabilities** (Reg. ss1.752-3):
- No partner has EROL — allocated in a 3-tier system:
  1. First, to partners with ss704(c) minimum gain allocations
  2. Second, to partners designated by the agreement to receive ss704(b) regulatory allocations attributable to the nonrecourse liabilities (typically profit-sharing ratio)
  3. Third, in accordance with partners' share of partnership profits

**Practical impact**: A real estate partnership with $10M in nonrecourse mortgage debt allocates that debt across partners — each partner's basis is increased by their share. A 10% partner gets $1M of additional basis — allowing $1M more in loss deductions without any additional cash investment.

### ss704(b) Capital Accounts

Capital accounts track each partner's economic interest in the partnership. They are maintained under the ss704(b) "substantial economic effect" rules:

```
Initial contribution (FMV)
  + Allocable share of income/gain
  - Allocable share of loss/deduction
  - Distributions
= Ending capital account
```

Capital accounts are at FMV (book value), NOT tax basis. The difference between book and tax is tracked as ss704(c) adjustments (built-in gains/losses on contributed property).

---

## ss1014 — STEPPED-UP BASIS AT DEATH

### General Rule

Property included in a decedent's gross estate receives a basis equal to its Fair Market Value at the date of death (or the alternate valuation date under ss2032, if elected — 6 months after death).

### What Qualifies for Step-Up

| Asset | Steps Up? | Notes |
|---|---|---|
| Stocks, bonds, mutual funds | YES | FMV at date of death |
| Real property | YES | Appraisal at date of death |
| Personal property | YES | FMV (art, collectibles, vehicles) |
| IRAs, 401(k)s | NO | These are Income in Respect of a Decedent (IRD) — ss691 |
| Annuities | NO | IRD |
| Traditional IRA | NO | IRD — heirs pay income tax on distributions |
| Roth IRA | N/A | Already tax-free; no step-up needed |
| Joint tenancy (non-spouse) | PARTIAL | Only decedent's share steps up (ss2040) |
| Community property | **BOTH halves** | ss1014(b)(6) — FULL step-up on both halves |
| Revocable trust assets | YES | Included in estate under ss2038 |
| IDGT assets | DEPENDS | If NOT included in estate (ss2036/2038 don't apply), NO step-up |

### Alternate Valuation Date (ss2032)

Executor can elect to value ALL estate assets at the date 6 months after death, IF:
- The election REDUCES the gross estate value AND
- The election REDUCES the estate tax liability

This is useful when asset values have declined since death. The election applies to ALL assets — cannot cherry-pick.

### Step-Up vs Step-Down

The ss1014 basis is FMV at death — which can be LOWER than the decedent's basis. Loss assets "step down" to FMV, permanently destroying the loss.

**Planning**: Sell loss assets BEFORE death to harvest the capital loss on the decedent's final return. Leave the cash to heirs.

---

## ss1015 — CARRYOVER BASIS FOR GIFTS

### General Rule

For gifts, the donee's basis equals the donor's adjusted basis (carryover basis), with modifications:

**If FMV at time of gift > donor's basis**:
- Donee's basis = donor's basis (for both gain and loss purposes)
- Plus: adjustment for gift tax paid on the appreciation (ss1015(d))

**If FMV at time of gift < donor's basis** (gift of loss property):
- For GAIN purposes: donee's basis = donor's basis
- For LOSS purposes: donee's basis = FMV at time of gift
- If donee sells between FMV and donor's basis: NO gain, NO loss (the "no-man's land")

### Gift Tax Basis Adjustment (ss1015(d))

If gift tax is paid on appreciated property, the donee's basis is increased by:

**Increase = Gift tax paid x (Net appreciation / Amount of gift)**

Where net appreciation = FMV at gift - donor's basis

**Worked Example**:
- Donor's basis: $200,000
- FMV at gift: $1,000,000
- Net appreciation: $800,000
- Gift tax paid: $160,000 (40% on the amount above exemption)
- Basis increase: $160,000 x ($800,000 / $1,000,000) = $128,000
- Donee's basis: $200,000 + $128,000 = $328,000

---

## ss1016 — ADJUSTMENTS TO BASIS

### Increases to Basis

| Adjustment | Authority | Example |
|---|---|---|
| Capital improvements | ss1016(a)(1) | Adding a room, new roof, renovation |
| Assessments for local improvements | ss1016(a)(1) | Sidewalks, sewer connections |
| Costs of defending title | Case law | Legal fees to clear title |
| Zoning costs | Rev. Rul. 78-38 | Legal fees for zoning change |
| Restoration after casualty | ss1016(a)(1) | Rebuilding after fire (not insured portion) |

### Decreases to Basis

| Adjustment | Authority | Example |
|---|---|---|
| Depreciation (allowed or allowable) | ss1016(a)(2) | Annual MACRS depreciation — must reduce basis even if NOT claimed |
| Casualty loss deductions | ss1016(a)(1) | Insurance proceeds + deducted loss |
| Tax-free return of capital | ss1016(a)(4) | Non-dividend distributions from corporations |
| Energy credits | ss50(c) | Reduce basis by credit amount (for certain credits) |
| Amortization | ss1016(a)(13) | ss197 intangibles, startup costs |
| Easement sales | ss1016(a)(1) | Reduce land basis by easement payment |

### "Allowed or Allowable" Rule

Under ss1016(a)(2), basis is reduced by depreciation "allowed or allowable" — whichever is GREATER. This means:
- If you SHOULD have claimed $10,000 depreciation but claimed $0: basis is still reduced by $10,000
- If you claimed $12,000 but only $10,000 was allowable: basis reduced by $12,000
- **You cannot avoid depreciation recapture by failing to claim depreciation**

---

## LIKE-KIND EXCHANGE BASIS (ss1031)

### Replacement Property Basis

In a like-kind exchange:

```
Basis of relinquished property
  + Boot paid (cash or non-like-kind property given)
  + Gain recognized (on boot received)
  + Exchange expenses
  - Boot received (cash, debt relief, non-like-kind property)
  - Loss recognized (generally $0 in like-kind exchanges)
= Basis of replacement property
```

### Worked Example

- Relinquished property basis: $200,000
- FMV of relinquished: $500,000
- Mortgage on relinquished: $150,000 (assumed by buyer — treated as boot received)
- Replacement property FMV: $600,000
- New mortgage on replacement: $250,000
- Cash paid from exchange proceeds: $0

**Boot analysis**:
- Boot received: $150,000 (debt relief on relinquished)
- Boot paid: $250,000 (new debt on replacement)
- Net boot: $250,000 - $150,000 = $100,000 paid (no gain recognized — boot paid > boot received)

**Basis of replacement**:
- $200,000 (old basis) + $100,000 (net boot paid) = **$300,000**
- The $200,000 in deferred gain ($500,000 FMV - $300,000 basis) is now embedded in the replacement property

### Multiple Property Exchanges

When the replacement property includes both like-kind and non-like-kind property, basis must be allocated. The regulations under Reg. ss1.1031(j)-1 provide detailed allocation rules.

### Depreciation on Replacement Property

The replacement property's depreciable basis is split:
- **Exchange basis** ($200,000 in example): Continues the depreciation schedule and method of the relinquished property (no new depreciation)
- **Excess basis** ($100,000 in example): New depreciable basis — starts a new depreciation schedule, eligible for bonus depreciation

This split is critical for cost segregation planning on replacement properties.

---

## INHERITED IRA BASIS

### After-Tax Contributions

If the decedent made nondeductible (after-tax) contributions to a Traditional IRA, those contributions have BASIS. This basis:
- Carries over to the beneficiary
- Reduces the taxable portion of inherited IRA distributions
- Is tracked on Form 8606

**Worked Example**:
- Decedent's IRA: $500,000 total, of which $50,000 was nondeductible contributions
- Basis: $50,000 / $500,000 = 10% of each distribution is tax-free
- Beneficiary takes $100,000 distribution: $90,000 taxable, $10,000 return of basis

### Common Error

Beneficiaries often forget about the decedent's Form 8606 basis and pay tax on 100% of inherited IRA distributions. The executor should provide Form 8606 records to all beneficiaries.

### Roth IRA Basis

Roth IRA contributions have basis (since they were made with after-tax dollars). For inherited Roth IRAs:
- Distributions of contributions: always tax-free
- Distributions of earnings: tax-free if the 5-year holding period has been met (counted from the DECEDENT's first Roth contribution)
- If the 5-year period has not been met: earnings are taxable, but contributions are still tax-free

---

## HOME BASIS

### Calculating Home Basis

```
Original purchase price
  + Closing costs capitalized (title insurance, recording fees, transfer tax, surveys — NOT deductible items like prepaid interest or property taxes)
  + Capital improvements (additions, remodeling, new roof, HVAC, landscaping — must be permanent and add value or extend useful life)
  - Casualty loss deductions taken
  - Depreciation claimed (if home office or rental use)
  - ss121 exclusion previously used (for prior primary residences)
  - Insurance reimbursements for casualties
  - Energy credits that required basis reduction
= Adjusted basis
```

### Home Office Depreciation Impact

If a taxpayer uses the REGULAR home office method (Form 8829), they must depreciate the business-use portion:
- Business use %: typically 10-20% of home
- Annual depreciation: (Business % x Building basis) / 39 years (home office is nonresidential property, not 27.5 years)
- At sale: the depreciation claimed is NOT eligible for the ss121 exclusion — it is taxed at 25% (unrecaptured ss1250 gain)

**Worked Example**:
- Home cost: $500,000 (building: $400,000, land: $100,000)
- Home office: 15% of home
- Annual depreciation: 15% x $400,000 / 39 = $1,538/year
- Used home office for 10 years: $15,380 total depreciation
- Sell home for $800,000
- ss121 exclusion: Up to $500,000 (MFJ) of the $300,000 gain = $300,000 excluded
- Depreciation recapture: $15,380 x 25% = $3,845 — this is NOT excluded by ss121

### Rental Property Conversion

When a primary residence is converted to rental use:
- Depreciable basis = LESSER of (a) adjusted basis at conversion or (b) FMV at conversion
- If FMV < adjusted basis: the loss is permanently trapped (cannot depreciate more than FMV, and the loss on sale is limited)
- ss121 exclusion: May still be available if the taxpayer lived in the property for 2 of the last 5 years before sale (but rental-period depreciation is recaptured)

---

## WASH SALE BASIS ADJUSTMENT (ss1091)

### The Rule

If a taxpayer sells a security at a loss and purchases "substantially identical" securities within 30 days BEFORE or AFTER the sale, the loss is disallowed.

### Basis Adjustment

The disallowed loss is NOT lost — it is ADDED to the basis of the replacement security:

```
Basis of replacement = Purchase price of replacement + Disallowed loss from wash sale
Holding period of replacement includes the holding period of the original security
```

**Worked Example**:
- Buy 100 shares of XYZ at $50/share ($5,000 basis)
- Sell 100 shares at $30/share ($3,000 proceeds, $2,000 loss)
- Within 30 days, buy 100 shares at $32/share ($3,200 cost)
- Wash sale: $2,000 loss is DISALLOWED
- Basis of replacement: $3,200 + $2,000 = **$5,200**
- If sold later at $50/share: gain = $50 x 100 - $5,200 = ($200) — the original loss is effectively recovered

### Cross-Account Wash Sales

Wash sales apply across ALL accounts — taxable brokerage, IRA, spouse's accounts:
- Sell at a loss in taxable account, buy in IRA within 30 days → wash sale. But the disallowed loss CANNOT be added to IRA basis — it is permanently lost.
- Sell in one brokerage, buy in another → wash sale, but basis adjustment applies normally.

---

## CRYPTO BASIS

### Methods of Basis Tracking

The IRS requires specific identification of crypto lots (Notice 2014-21, Rev. Rul. 2019-24). Available methods:

| Method | Description | Best For |
|---|---|---|
| **Specific identification** | Choose which lot to sell | Tax optimization (sell highest-basis lots first) |
| **FIFO (First In, First Out)** | Default if no specific ID | Simple, but often results in higher gains |
| **HIFO (Highest In, First Out)** | Sell highest-basis lots first | Minimizing current-year gain |
| **LIFO (Last In, First Out)** | Sell most recently purchased lots first | May minimize gain if recent purchases are at higher prices |

### Universal vs Per-Wallet Tracking

**Universal tracking**: Track all lots of a cryptocurrency across ALL wallets and exchanges as a single pool. Specific identification pulls from the global pool.

**Per-wallet tracking**: Track lots within each wallet/exchange separately. A transfer between wallets is NOT a taxable event, but the lots must follow the transfer.

**Best practice**: Use universal tracking with specific identification. Maintain a master ledger across all platforms.

### Crypto-Specific Basis Issues

**Airdrops and forks**: Basis = FMV at time of receipt (included in ordinary income). If received from a hard fork, the IRS position (Rev. Rul. 2019-24) is that the forked currency has FMV at the time of the fork as basis.

**Staking rewards**: Basis = FMV at time rewards are received (included in ordinary income per Rev. Rul. 2023-14).

**Mining**: Basis = FMV at time cryptocurrency is received from mining (included in self-employment income).

**DeFi transactions**: Each swap, liquidity pool entry/exit, and yield farming event is a potentially taxable event. Basis must be tracked for each token received and disposed of.

**NFTs**: Basis = purchase price (in crypto or fiat). If purchased with crypto, the crypto disposal is a taxable event, and the NFT basis = FMV of the crypto at the time of exchange.

**Zero-basis crypto**: If a taxpayer cannot establish basis (lost records, defunct exchange), the IRS may assert $0 basis — meaning 100% of the sale proceeds are gain. Reconstruct basis from blockchain records, exchange statements (even deleted accounts may have records via GDPR requests), and email confirmations.

### Reporting Requirements (2025+)

Starting with 2025 tax year, exchanges must report basis on Form 1099-DA (Digital Asset). However:
- Only covers centralized exchanges
- DeFi transactions, wallet-to-wallet transfers, and non-custodial activities are NOT reported by exchanges
- Taxpayers remain responsible for tracking and reporting all transactions

---

## WORKING EXAMPLES — COMPREHENSIVE BASIS SCENARIOS

### Example 1: S-Corp Shareholder Basis Lifecycle

**Year 1**:
- Initial stock investment: $50,000
- S-Corp income: $80,000 (K-1)
- Distribution: $60,000
- Stock basis: $50,000 + $80,000 - $60,000 = **$70,000**

**Year 2**:
- S-Corp loss: ($100,000)
- Direct loan to S-Corp: $20,000
- No distribution
- Stock basis: $70,000 - $70,000 (loss limited to stock basis) = **$0**
- Debt basis: $20,000 - $10,000 (remaining loss from debt basis) = **$10,000**
- Suspended loss: $100,000 - $70,000 - $10,000 = **$20,000** (insufficient basis)

**Year 3**:
- S-Corp income: $50,000
- No distribution
- Debt basis restored first: $10,000 + $10,000 (restore to original $20,000 debt) = **$20,000**
- Stock basis: $0 + $40,000 (remaining income after debt restoration) = **$40,000**
- Previously suspended $20,000 loss: NOW deductible (basis restored) → **deduct $20,000**
- Final stock basis: $40,000 - $20,000 = **$20,000**

### Example 2: Partnership Basis with Liabilities

- Partner A contributes $100,000 cash for 50% interest
- Partnership borrows $400,000 nonrecourse mortgage to buy rental property
- Partner A's share of nonrecourse debt: 50% x $400,000 = $200,000
- Partner A's outside basis: $100,000 + $200,000 = **$300,000**
- Partnership has $80,000 loss in Year 1
- Partner A's share: $40,000
- After loss: $300,000 - $40,000 = **$260,000**
- Note: The $200,000 of debt-driven basis allows Partner A to deduct the loss despite only investing $100,000 cash. This is fundamentally different from S-Corps where debt guarantees do NOT create basis.

### Example 3: Home Basis Through Multiple Events

- Purchase: $400,000 ($320,000 building, $80,000 land)
- Year 2: New roof: $15,000 (capital improvement)
- Year 3-7: Home office (10%), depreciation: 10% x $335,000 / 39 x 5 = $4,295
- Year 5: Bathroom remodel: $25,000 (capital improvement)
- Year 8: Kitchen casualty (fire), $30,000 damage, $25,000 insurance proceeds
- Year 8: Casualty loss deduction: $30,000 - $25,000 - ss165(h) limitations = ~$4,600

**Adjusted basis at sale (Year 10)**:
- $400,000 + $15,000 + $25,000 - $4,295 - $30,000 (casualty) + $25,000 (insurance already netted) = need to track carefully
- Purchase: $400,000
- Improvements: +$40,000
- Depreciation: -$4,295
- Casualty loss deducted: -$4,600
- **Adjusted basis: ~$431,105**

---

## KEY TAKEAWAYS

1. **S-Corp basis is stock + debt (direct loans only)** — guarantees do NOT create basis (unlike partnerships)
2. **Partnership basis includes share of ALL liabilities** — ss752 allocations are critical and complex
3. **ss1014 step-up at death is the most valuable tax provision in the code** — plan around it
4. **ss1015 carryover basis for gifts** means the donee inherits the donor's (usually low) basis — gift high-basis assets, bequeath low-basis assets
5. **"Allowed or allowable" depreciation** reduces basis whether or not you actually claimed the deduction — always claim it
6. **ss1031 exchange basis carries forward** — the deferred gain is embedded in the replacement property
7. **Inherited IRA basis (Form 8606)** is frequently forgotten — beneficiaries overpay by ignoring after-tax contributions
8. **Home office depreciation is recaptured at 25%** and is NOT covered by the ss121 exclusion — factor this into home sale planning
9. **Wash sale losses are added to replacement basis** — the loss is deferred, not lost (unless the replacement is in an IRA)
10. **Crypto basis tracking is the taxpayer's responsibility** — maintain a universal ledger with specific lot identification
11. **S-Corp four-gate loss limitation** (basis → at-risk → passive → excess business loss) must be applied sequentially — a loss that passes Gate 1 may still be suspended at Gate 3
12. **Community property states give FULL step-up** on both halves at first death — a massive advantage over common-law states
