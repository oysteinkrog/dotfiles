# Startup Founder — Tax Reference Guide (TY 2025)

## 1. Overview

Startup founders face a uniquely complex tax landscape where decisions made at incorporation
can save (or cost) millions of dollars at exit. The intersection of IRC Section 83(b) elections,
Qualified Small Business Stock (§1202), entity selection, and equity compensation design creates
a decision matrix that demands planning from day zero. A founder who files an 83(b) election
on $1,000 of restricted stock in a C-Corp can potentially exclude $10M of gain at exit — but
only if every structural requirement is met along the way. This reference covers the critical
tax rules for technology startup founders, from formation through liquidity event.

## 2. Section 83(b) Election — The Single Most Important Tax Decision

### How It Works
When a founder receives restricted stock (stock subject to vesting), IRC §83(a) normally taxes
the stock as ordinary income as it vests, at the FMV on each vesting date. An §83(b) election
instead elects to recognize income at the time of grant, on the current (low) FMV.

### Filing Requirements (Non-Negotiable)
- **30-day deadline**: Must be filed with the IRS within 30 days of the stock grant date.
  There is NO extension, NO late-filing relief, and NO exception. *Cramer v. Commissioner*,
  T.C. Memo 2022-90 (election denied for filing on day 31).
- **File with IRS service center** where taxpayer files returns (or per instructions).
- **Attach copy to tax return** for the year of the election.
- **Provide copy to the company** (the transferor).
- **Recommended**: Send via certified mail, return receipt requested. Keep the green card forever.

### Tax Mechanics
- **Income recognized at grant**: FMV at grant minus amount paid. For typical founder stock
  purchased at par value ($0.0001/share), the income is negligible.
- **Holding period starts at grant**, not vesting. This is critical for LTCG treatment and §1202.
- **If stock is forfeited** (founder leaves before vesting): NO deduction for the tax previously
  paid. This is the risk of the election.
- **All future appreciation** after the election is capital gain (LTCG if held >1 year from grant).

### Worked Example: 83(b) Election
```
Founder receives 1,000,000 shares at incorporation
Purchase price: $0.001/share ($1,000 total)
FMV at grant: $0.001/share (same — no premium yet)
83(b) income recognized: $1,000 - $1,000 = $0

4 years later, company is acquired for $50/share:
Total proceeds: $50,000,000
Basis: $1,000
Gain: $49,999,000 — ALL long-term capital gain

Without 83(b) — stock vests over 4 years:
Year 1 vesting (250K shares at $2/share FMV): $500,000 ordinary income
Year 2 vesting (250K shares at $8/share FMV): $2,000,000 ordinary income
Year 3 vesting (250K shares at $15/share FMV): $3,750,000 ordinary income
Year 4 vesting (250K shares at $30/share FMV): $7,500,000 ordinary income
Total ordinary income: $13,750,000 (taxed up to 37%)
Plus LTCG on appreciation above vest prices on eventual sale
```

## 3. Qualified Small Business Stock (§1202) — The $10M Exclusion

### Requirements (ALL Must Be Met)
1. **C-Corporation**: Must be a domestic C-Corp at issuance and substantially all of the
   holding period. S-Corps, LLCs, and partnerships do NOT qualify.
2. **Gross assets test**: Corporation's aggregate gross assets must not exceed $50M at any
   time before and immediately after the stock issuance. Gross assets = cash + adjusted
   basis of all other assets.
3. **Original issuance**: Stock must be acquired at original issuance (directly from the
   company) in exchange for money, property (other than stock), or services.
4. **Active business requirement**: At least 80% of assets (by value) must be used in the
   active conduct of a qualified trade or business during substantially all of the holding period.
5. **Excluded businesses**: Professional services (health, law, engineering, accounting,
   consulting, financial services, performing arts, athletics), banking, insurance, farming,
   mining, hotel/restaurant/similar hospitality. *Software and technology companies generally qualify.*
6. **5-year holding period**: Stock must be held for more than 5 years.

### Exclusion Amount
- **100% exclusion** for stock acquired after September 27, 2010 (still in effect for 2025).
- **Per-issuer limit**: Greater of $10M or 10x the adjusted basis of the stock.
- The excluded gain is also exempt from the 3.8% NIIT.
- **AMT**: 100% exclusion stock is NOT an AMT preference item (7% of excluded gain was AMT
  preference for pre-2010 stock only).

### QSBS Stacking Strategies
Each taxpayer has a separate $10M exclusion per issuer. Strategies to multiply the exclusion:

- **Spousal gifts**: Gift shares to spouse — each spouse gets $10M exclusion = $20M for a couple.
  Tacking of holding period applies under §1223(2).
- **Gifts to family members**: Gift shares to children, parents, siblings. Each donee gets their
  own $10M exclusion. Holding period tacks. *But*: must be completed gifts (donee must have
  dominion and control). Gift tax applies (use annual exclusion $19,000/person or lifetime
  exemption $13.99M for 2025).
- **Trust stacking**: Each trust that is a separate taxpayer gets its own $10M exclusion.
  - Grantor trusts: QSBS exclusion belongs to the grantor (no stacking benefit).
  - Non-grantor trusts: separate taxpayer, separate $10M exclusion.
  - Multiple non-grantor trusts for different beneficiaries can multiply the exclusion.
  - *Caution*: IRS may challenge trusts created solely for QSBS stacking. Trusts must have
    independent non-tax purpose. See Notice 2024-39 (IRS signaling scrutiny).
- **§1045 rollover**: Sell QSBS held >6 months and reinvest proceeds in new QSBS within
  60 days — gain is deferred (not excluded). Rolled basis reduces new stock's basis. Can be
  used to move into a better-positioned QSBS investment.

### State Tax Treatment of QSBS
- **California**: Does NOT conform to federal 100% exclusion. CA allows only 50% exclusion,
  limited to the greater of $10M or 10x basis, and ONLY for stock in California-qualified
  small businesses. *This means CA founders often owe significant state tax on exits that are
  100% excluded federally.* R&TC §18152.5.
- **New York**: Conforms to federal §1202 exclusion.
- **New Jersey**: Does NOT conform. No QSBS exclusion at the state level.
- **Massachusetts**: Does NOT conform. No QSBS exclusion.
- **Most other states**: Follow federal treatment. Verify for your specific state.

## 4. Section 351 — Tax-Free Incorporation

### General Rule
No gain or loss is recognized when property is transferred to a corporation solely in exchange
for stock, if the transferors are in "control" (80% of voting power and 80% of each class of
non-voting stock) immediately after the exchange. IRC §351(a).

### What Counts as "Property"
- Cash, equipment, real estate, patents, trade secrets, software code, domain names
- Services do NOT count as "property" — stock received for services is taxable under §83
- **Critical for founders**: Contributing your codebase, IP, or business assets to a new
  C-Corp can be tax-free under §351 if structured properly

### Boot Recognition
If the founder receives anything other than stock (cash, debt instruments, other property = "boot"),
gain is recognized to the extent of boot received. §351(b).

### Basis and Holding Period
- **Founder's basis in stock received**: Same as basis in property transferred, minus boot
  received, plus gain recognized. §358(a).
- **Corporation's basis in property received**: Same as transferor's basis, plus gain recognized
  by transferor. §362(a).
- **Holding period of stock**: Tacks the holding period of the transferred property if the
  property was a capital asset or §1231 property in the transferor's hands. §1223(1).
  This matters for §1202's 5-year holding period.

### Common Pitfall: §351 and QSBS Interaction
Stock received in a §351 exchange counts as "original issuance" for §1202 purposes if the
property contributed has a basis (i.e., it is not purely services). Rev. Rul. 2003-48. But the
$50M gross assets test must still be met at the time of the §351 exchange.

## 5. Founder Stock vs. Options: The Decision Framework

### Restricted Stock with 83(b) Election (Preferred for Founders)
- **Advantages**: Starts LTCG clock immediately, starts §1202 clock immediately, income
  recognized is minimal (pennies per share at incorporation)
- **Risk**: If forfeited, tax paid is lost (but typically negligible for founders)
- **When to use**: At incorporation or very early stage when FMV is lowest

### Incentive Stock Options (ISOs)
- **No regular tax at exercise** (but AMT adjustment for the spread)
- **Qualifying disposition**: Hold 2 years from grant + 1 year from exercise → LTCG on entire gain
- **Disqualifying disposition**: Spread at exercise taxed as ordinary income
- **$100K vesting limit**: ISOs that vest in any calendar year exceeding $100K FMV (at grant date)
  are treated as NQSOs for the excess. §422(d).
- **When to use**: Employees and later-stage founders when stock has appreciated significantly

### Non-Qualified Stock Options (NQSOs)
- **Ordinary income at exercise**: Spread (FMV minus exercise price) is taxable
- **When to use**: When ISO limits are exceeded, for advisors, for consultants

### Early Exercise + 83(b) Strategy
Some companies allow option exercise before vesting ("early exercise"). Combined with 83(b):
- Exercise all options immediately at grant (pay exercise price on unvested shares)
- File 83(b) within 30 days — recognize spread as ordinary income (if any)
- At early stage, spread may be $0 or minimal
- Starts LTCG and §1202 holding periods immediately
- Risk: if you leave, company repurchases unvested shares at lower of FMV or exercise price

## 6. SAFEs and Convertible Notes

### Simple Agreement for Future Equity (SAFE)
- **At issuance**: Generally not a taxable event for the investor or company. The SAFE is a
  contractual right, not equity.
- **At conversion**: Investor receives stock. Tax treatment depends on whether the conversion
  is treated as a §351 exchange (generally yes if SAFE is "property") or a mere settlement.
  Most practitioners treat SAFE conversion as non-taxable, with basis = amount invested.
- **QSBS**: The holding period for §1202 likely starts at conversion (when stock is actually
  issued), NOT at the date the SAFE was purchased. This is a contested area — conservative
  position is to start the clock at conversion.
- **IRS scrutiny**: Notice 2024-2 indicated the IRS is examining SAFE tax treatment.

### Convertible Notes
- **Debt instrument**: Interest accrues (taxable to holder). OID rules may apply.
- **At conversion**: Generally treated as a recapitalization (§368(a)(1)(E)) — no gain or loss.
  Basis in stock = adjusted basis in note (principal + accrued OID, minus payments received).
- **QSBS**: Holding period starts at conversion, not note issuance. Same issue as SAFEs.

## 7. Section 1244 Small Business Stock — Ordinary Loss Treatment

If the startup fails, §1244 provides a valuable consolation:
- **Ordinary loss** (not capital loss) on worthless or sold-at-a-loss stock: up to $50,000
  per year ($100,000 MFJ)
- Excess over the limit is treated as capital loss (subject to $3,000 annual offset limit)
- **Requirements**: Stock must be issued for money or property (not services), corporation's
  aggregate paid-in capital must not exceed $1M at time of issuance, corporation must derive
  >50% of gross receipts from active business (not passive income) for 5 years preceding the loss
- **No formal election required** — but taxpayer must maintain records proving eligibility
- **Comparison**: Without §1244, the loss on worthless stock is a capital loss (deductible only
  against capital gains + $3,000/year of ordinary income)

### Worked Example
```
Founder invests $100,000 in startup C-Corp stock
Startup fails — stock is worthless

With §1244: $100,000 ordinary loss deduction (MFJ)
Tax savings at 37% bracket: $37,000

Without §1244: $100,000 capital loss
If no capital gains: deduct $3,000/year for 33+ years
Tax savings in year 1: $1,110 (at 37%)
```

## 8. Entity Selection Decision Matrix

### C-Corp: Choose When
- Raising venture capital (institutional investors require it)
- Planning for an exit (acquisition/IPO) within 5-10 years
- Want §1202 QSBS exclusion (potentially $10M+ tax-free gain)
- Can tolerate double taxation on current earnings (corporate tax 21% + dividend tax 23.8%)
- Retaining earnings in the company (no pass-through phantom income to founders)

### S-Corp: Choose When
- Bootstrapping / lifestyle business with no plans to raise institutional capital
- Want pass-through taxation (single level of tax)
- Planning to distribute profits to founders regularly
- SE tax savings on distributions (S-Corp distributions not subject to SE tax)
- Limited to 100 shareholders, one class of stock (no preferred), US persons only

### LLC (Partnership Taxation): Choose When
- Multiple founders wanting maximum flexibility in allocation of profits/losses
- Special allocations needed (e.g., allocate losses to investors, profits to founders)
- Planning to convert to C-Corp later (but watch: conversion is generally taxable or
  requires careful structuring under §351)
- No plan for institutional VC (most VCs will require C-Corp conversion)

### Conversion Considerations
- **LLC → C-Corp**: Can be structured as tax-free under §351 if done properly. All members
  contribute their LLC interests for C-Corp stock. Must have 80% control after exchange.
  Any liabilities in excess of basis may trigger gain. §357(c).
- **S-Corp → C-Corp**: Revocation of S election. Built-in gains tax (§1374) may apply for 5
  years on assets with built-in gain at conversion (applies to C→S→C but structure matters).
- **Timing**: Convert BEFORE the company is worth a lot. Lower FMV = lower tax friction.

## 9. Pre-IPO and Pre-Exit Tax Planning

### Income Acceleration Strategies
- **Exercise ISOs in low-income years**: If you know an IPO is coming, exercise ISOs the year
  before when your income is lower. AMT from the ISO spread may be offset by AMT credits
  in the high-income post-IPO year.
- **Roth conversions before liquidity**: Convert traditional IRA to Roth while income is low
  (pre-revenue startup phase). Pay tax at lower bracket now; enjoy tax-free growth later.
- **Charitable strategies pre-exit**: Contribute appreciated QSBS to a donor-advised fund
  (DAF) before sale. Full FMV deduction, avoid capital gains. But §1202 exclusion may be
  more valuable — model both scenarios.
- **Installment sale**: If selling to a private buyer, structure as installment sale under §453
  to spread gain recognition over multiple years. Watch §453A interest charge for deferred
  tax on sales >$5M.

### 10x Basis Strategy for QSBS
The §1202 exclusion is the greater of $10M or 10x the adjusted basis of the stock. Strategy:
contribute high-basis property (not just cash) to the C-Corp under §351 to increase basis.
Example: contribute $500K of equipment → basis in stock = $500K → 10x exclusion = $5M
(in addition to the $10M per-issuer floor).

## 10. State Considerations

### California
- Taxes QSBS gain (only 50% exclusion, with restrictions) — R&TC §18152.5
- Franchise Tax Board aggressively audits departing founders. Must make a clean break:
  change domicile, driver's license, voter registration, professional licenses, social ties.
  "Closer connection" test. See *Bragg v. FTB* (2003).
- LLC fee based on gross receipts ($800 minimum + up to $11,790 for >$5M gross receipts)
- S-Corp: 1.5% tax on net income (minimum $800)

### Delaware
- Incorporation advantages: well-developed corporate law (Court of Chancery), flexibility
  in corporate governance, no state income tax on out-of-state operations
- Franchise tax can be substantial for large authorized share counts — use the
  "assumed par value capital method" to minimize
- **Delaware does not tax individuals** — no state income tax on founders who are not DE residents

### Other Key States
- **New York**: Conforms to §1202, but high state tax rates (up to 10.9% + 3.876% NYC)
- **Texas**: No state income tax. Franchise (margin) tax applies to entities.
- **Florida**: No state income tax. Popular relocation destination for founders pre-exit.
- **Washington**: No income tax, but 7% capital gains tax on LTCG over $270,000 (2025).

## 11. Comprehensive Exit Example

```
FACTS:
- Founder incorporated C-Corp in Delaware in 2020
- Purchased 2,000,000 shares at $0.001/share ($2,000)
- Filed 83(b) election within 30 days
- Gross assets at issuance: $50,000 (well under $50M)
- Company is a SaaS business (qualifies for §1202)
- Held stock for 6 years (satisfies 5-year requirement)
- Company acquired in 2026 for $60M (founder's 2M shares = $30M after dilution)

TAX ANALYSIS:
Gain: $30,000,000 - $2,000 = $29,998,000

§1202 exclusion: $10,000,000 (100% excluded, no federal tax)
Remaining gain: $19,998,000

Federal tax on remaining gain:
  20% LTCG rate: $3,999,600
  3.8% NIIT: $759,924
  Total federal: $4,759,524

If founder is CA resident:
  CA tax on full $30M gain (only 50% exclusion on $10M):
  $25M taxable at ~13.3% = ~$3,325,000

If founder relocated to FL pre-exit:
  State tax: $0

TOTAL TAX (FL resident): ~$4,759,524 on $30M gain (15.9% effective rate)
TOTAL TAX (CA resident): ~$8,084,524 on $30M gain (26.9% effective rate)

WITHOUT 83(b) and §1202 planning:
$30M ordinary income at 37% + 3.8% NIIT + state = ~$12-15M+ in tax
```

## 12. Common Mistakes

1. **Missing the 83(b) deadline** — 30 days is absolute. No relief, no exceptions. File on day 1.
2. **Forming as LLC then converting to C-Corp too late** — §1202 clock starts only when C-Corp
   stock is issued. Years spent as an LLC do not count toward the 5-year hold.
3. **Exceeding $50M gross assets** — Once the company raises enough capital to exceed $50M in
   gross assets, newly issued stock does not qualify for §1202. Plan fundraising accordingly.
4. **Not tracking QSBS qualification continuously** — The active business and asset tests must
   be met during "substantially all" of the holding period. Document compliance annually.
5. **Ignoring state tax on QSBS exits** — Federal exclusion does not mean state exclusion.
   CA, NJ, MA, and others tax QSBS gains.
6. **Assuming SAFEs start the §1202 clock** — Conservative position: clock starts at conversion
   to stock, not SAFE purchase date.
7. **Failing to maintain §351 control** — If founders bring in co-founders or investors in the
   same transaction and the contributing group does not maintain 80% control, §351 fails.
8. **Not considering §1244 at formation** — Document the stock issuance to qualify under §1244.
   No formal election needed, but records must prove eligibility if the startup fails.
9. **Double taxation surprise** — C-Corps that generate profits face 21% corporate tax plus
   up to 23.8% dividend tax on distributions. Model this for profitable bootstrapped startups.
