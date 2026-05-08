# Business Exit — Tax Reference Guide (TY 2025)

## Overview

The tax treatment of a business exit — whether by sale, merger, or liquidation — can vary by
millions of dollars depending on deal structure. The fundamental tension: buyers prefer asset
sales (stepped-up basis, amortizable goodwill) while sellers prefer stock sales (single level
of tax, LTCG treatment). The negotiation between these positions, combined with installment
sale planning, earnout structuring, tax-free reorganizations, and QSBS exclusions, makes
business exit planning the highest-stakes area of individual tax law. A poorly structured
$10M exit can easily cost $1-2M more in tax than a well-structured one.

## Asset Sale vs. Stock Sale

### Asset Sale
**Buyer perspective**: Strongly preferred.
- Buyer gets a **stepped-up basis** in all acquired assets equal to the purchase price
  (allocated under §1060 / §338).
- Goodwill and going-concern value are amortizable over 15 years under §197.
- Equipment, real property, and other tangible assets get new depreciable lives.
- Buyer does NOT assume unknown tax liabilities of the entity.

**Seller perspective**: Generally disfavored.
- **C-Corp seller**: Double taxation — corporate-level gain on asset sale (21% federal),
  then shareholder-level tax on liquidating distribution (up to 23.8% federal). Combined
  rate can reach 40%+.
- **S-Corp seller**: Single level of tax, but character of gain varies by asset class
  (ordinary income on inventory, depreciation recapture; LTCG on goodwill, real property).
- **Partnership/LLC seller**: Same as S-Corp — pass-through, character varies by asset.
- Allocation of purchase price among assets (§1060) determines character:
  - Class I: Cash and equivalents
  - Class II: Actively traded securities
  - Class III: Accounts receivable, mortgages, credit card receivables
  - Class IV: Inventory
  - Class V: All other tangible and intangible assets (equipment, real estate)
  - Class VI: §197 intangibles (excluding goodwill/going concern)
  - Class VII: Goodwill and going-concern value (residual — everything not allocated above)

### Stock Sale
**Seller perspective**: Strongly preferred.
- Single level of tax at LTCG rates (if held >1 year): 20% + 3.8% NIIT = 23.8% federal max.
- No depreciation recapture, no ordinary income allocation.
- Clean transaction: sell shares, receive cash, pay tax on gain.

**Buyer perspective**: Generally disfavored.
- Buyer takes a carryover basis in the company's assets (no step-up).
- Buyer inherits all known and unknown liabilities (tax, environmental, legal).
- Buyer gets NO new depreciation or amortization deductions.

### The §338(h)(10) Compromise

**What it does**: Allows a stock sale to be treated as an asset sale for tax purposes.
The buyer purchases stock but elects (jointly with the seller) to treat the transaction
as if the target sold all its assets and liquidated.

**Who benefits**:
- **Buyer**: Gets the stepped-up basis and §197 amortization as if it were an asset sale.
- **Seller (S-Corp/consolidated group)**: Reports gain as if it were an asset sale — but
  still a single level of tax for S-Corp sellers. Character is determined by asset class.
- **NOT available for C-Corp stock sales to unrelated parties** outside of a consolidated group
  (use §338(g) instead, which triggers the double-tax problem).

**Requirements**:
- Target must be a corporation (S-Corp or subsidiary in a consolidated group).
- Buyer must acquire at least 80% of the target's stock in a qualified stock purchase.
- Election must be made jointly on Form 8023 by the 15th day of the 9th month after the
  acquisition month.

### Worked Example: S-Corp Exit
```
FACTS:
- S-Corp with 2 shareholders (50/50), basis in stock = $500,000 each
- Sale price: $10,000,000 (stock sale)
- Inside assets: $2M equipment (book value), $500K inventory, $7.5M goodwill

STOCK SALE (no §338(h)(10)):
Each shareholder's gain: ($5,000,000 - $500,000) = $4,500,000 LTCG
Federal tax per shareholder (23.8%): $1,071,000
Total federal tax: $2,142,000

ASSET SALE (or §338(h)(10) election):
Inventory gain: $300,000 ordinary income (allocated to shareholders)
Equipment gain: $800,000 (mix of §1245 recapture + §1231 gain)
Goodwill: $7,500,000 LTCG (allocated to shareholders)
Ordinary income tax (37% × $1,100,000): $407,000
LTCG tax (23.8% × $7,500,000): $1,785,000
Total federal tax: $2,192,000

Difference: $50,000 more in tax with asset sale structure
BUT: Buyer may pay $500K-$1M MORE for asset sale (due to tax benefits of step-up)
Net benefit to seller: negotiate higher price to compensate for higher tax
```

## Installment Sales — Section 453

### Basic Rule
When the seller receives at least one payment after the year of sale, gain is recognized
proportionally as payments are received. §453(a).

**Installment sale ratio**: Gross profit / Contract price
**Gain recognized per payment**: Payment received × installment sale ratio

### Requirements and Limitations
- **NOT available for**: Inventory sales, dealer dispositions, publicly traded securities,
  depreciation recapture (§1245/§1250 recapture is recognized in year 1 regardless of
  payment timing). §453(b)(2), §453(i).
- **Interest requirement**: Seller must charge adequate interest (at least the applicable
  federal rate, or AFR) on deferred payments. §483 / §1274.
- **Related party resale**: If buyer is a related party (>50% ownership under §267(b) or
  §707(b)) and resells within 2 years, the original seller recognizes gain immediately. §453(e).

### Section 453A — Interest Charge on Deferred Tax
For installment obligations where the face amount exceeds $5M:
- Seller must pay interest on the deferred tax liability attributable to the installment obligation.
- Interest rate = underpayment rate (currently ~8%).
- Calculated on the tax deferred as of year end.
- **Planning**: If total installment obligations from the sale exceed $5M, the interest charge
  may make installment treatment less attractive. Model the cash flow.

### Self-Canceling Installment Note (SCIN)
- Installment note that cancels upon the seller's death — remaining payments are NOT included
  in the seller's estate.
- **Risk premium**: Must include a premium (higher interest rate or higher principal) to
  compensate for the cancellation risk. If no premium, IRS will recharacterize as a gift.
  *Estate of Costanza v. Commissioner*, T.C. Memo 2001-128.
- **Tax treatment at death**: Remaining gain is accelerated — recognized on the seller's
  final return. But the note is NOT in the estate (no estate tax).
- **Use case**: Elderly seller transferring a business to family members. The SCIN provides
  income during life and estate tax savings at death.

### Worked Example: Installment Sale
```
Sale price: $8,000,000
Seller's basis: $2,000,000
Gross profit: $6,000,000
Installment ratio: $6,000,000 / $8,000,000 = 75%

Payment schedule: $2,000,000 at closing + $1,500,000/year for 4 years
Plus 6% interest on outstanding balance (adequate stated interest)

Year 1: $2,000,000 × 75% = $1,500,000 gain recognized
Year 2: $1,500,000 × 75% = $1,125,000 gain recognized
Year 3: $1,500,000 × 75% = $1,125,000 gain recognized
Year 4: $1,500,000 × 75% = $1,125,000 gain recognized
Year 5: $1,500,000 × 75% = $1,125,000 gain recognized

Tax benefit: Spreading $6M of gain over 5 years may keep the seller in lower
brackets (especially if seller has no other income post-exit) and defers NIIT exposure.

§453A interest charge: Applies because face amount ($8M) > $5M.
Deferred tax at end of Year 1 = tax on $4,500,000 deferred gain ≈ $1,071,000
Interest at 8%: ~$85,680 per year (decreasing as gain is recognized)
```

## Earnout Provisions

### Tax Treatment of Contingent Payments
When part of the purchase price depends on future performance (revenue targets, EBITDA
milestones, customer retention), the earnout creates contingent payment obligations.

### Two Treatment Methods
1. **Closed transaction (stated maximum)**: If there is a maximum aggregate price, the
   installment sale rules apply using the maximum price. If the maximum is never reached,
   seller has a loss in the final year. Preferred by most practitioners.
2. **Open transaction (no stated maximum)**: No installment method available. Seller recovers
   basis first, then all subsequent payments are gain. *Burnet v. Logan*, 283 U.S. 404 (1931).
   IRS generally disfavors open transaction treatment — it is available only in "rare and
   extraordinary" circumstances. Reg. §15A.453-1(d)(2)(iii).

### Character of Earnout Payments
- Generally, same character as the underlying sale (LTCG if the original sale qualified).
- But: if the earnout is tied to the seller continuing to provide services (employment,
  consulting), the IRS may recharacterize earnout payments as ordinary compensation.
  *Lane v. Commissioner*, T.C. Memo 2020-148.
- **Structure tip**: Separate the purchase agreement from any consulting/employment agreement.
  Keep the earnout tied to company performance, not seller's personal services.

## ESOP Sale — Section 1042 Rollover

### Tax-Free Rollover for C-Corp Owners
When a C-Corp owner sells stock to an Employee Stock Ownership Plan (ESOP):
- **§1042 election**: Seller defers gain by reinvesting proceeds in "qualified replacement
  property" (QRP) — stocks and bonds of domestic operating companies (NOT mutual funds,
  real estate, or government bonds) — within 12 months after the sale (starting 3 months
  before the sale).
- **Requirements**: ESOP must own at least 30% of the company stock after the sale. Seller
  must have held the stock for at least 3 years. Stock must NOT have been received from a
  qualified plan or §83 stock transfer.
- **Floating rate notes (FRNs)**: The most common QRP. Seller reinvests in FRNs from domestic
  operating companies, locking in the deferral while maintaining liquidity-like access.
- **Permanent deferral**: If the seller holds the QRP until death, the basis steps up to FMV
  under §1014. The gain is NEVER taxed. *This is one of the most powerful estate planning
  tools in the tax code.*

### ESOP Sale Limitations
- Only available for C-Corp stock (NOT S-Corp).
- S-Corp owners considering an ESOP sale must convert to C-Corp first (and manage §1374
  built-in gains tax for the 5-year recognition period).
- The company must be able to support the ESOP debt service.
- §409(p) anti-abuse rules prevent excessive allocation to family members.

## QSBS Exclusion on Exit — Section 1202

See STARTUP-FOUNDER.md for comprehensive §1202 treatment. Key exit-specific points:
- Stock must be held >5 years at the time of sale.
- Up to $10M gain (or 10x basis) excluded per taxpayer per issuer.
- **Stacking with installment sale**: §1202 exclusion applies first to gains recognized in each
  year of an installment sale. If total gain = $15M and exclusion = $10M, the $10M exclusion
  is applied to the earliest installment payments (most favorable to seller).
- **Stacking with §1045 rollover**: Sell QSBS held >6 months, roll into new QSBS. The rolled
  basis reduces the new QSBS basis, potentially increasing the 10x basis exclusion.

## Goodwill and Intangible Assets

### For the Seller
- Goodwill is a capital asset. Gain on sale of goodwill is LTCG (if held >1 year).
- Personal goodwill (reputation, relationships) may belong to the individual, not the entity.
  *Martin Ice Cream Co. v. Commissioner*, 110 T.C. 189 (1998). Can be sold separately from
  entity assets, avoiding double taxation in C-Corp asset sales.
- **Personal goodwill strategy for C-Corp exits**: Shareholder enters into a non-compete or
  consulting agreement directly with the buyer. Payments for personal goodwill bypass the
  C-Corp entirely. Treated as LTCG to the shareholder.
  *Caution*: IRS scrutinizes aggressive personal goodwill claims. Must be genuine, documented,
  and not merely a disguised dividend or distribution.

### For the Buyer
- §197 intangibles (goodwill, going-concern value, customer lists, trade names, non-competes,
  covenants not to compete, patents, copyrights, licenses) are amortized over 15 years on a
  straight-line basis, regardless of actual useful life.
- Amortization begins in the month of acquisition.

## Non-Compete Agreements

- **To the seller**: Payments for a covenant not to compete are **ordinary income**. Not LTCG.
  §197 does not benefit the seller — only the buyer.
- **To the buyer**: §197 intangible, amortizable over 15 years.
- **Allocation negotiation**: Sellers want more allocated to goodwill (LTCG). Buyers want more
  allocated to non-compete (same 15-year amortization as goodwill, but non-compete payments
  reduce the seller's tax-preferred goodwill treatment). §1060 allocation must be consistent
  between buyer and seller.
- **State allocation**: Non-compete payments may be sourced to multiple states based on where
  the seller was restricted from competing.

## Tax-Free Reorganizations — Section 368

### Type A — Statutory Merger
- Target merges into acquirer (or a subsidiary). Target shareholders receive acquirer stock
  (and possibly cash/boot).
- **Tax treatment**: No gain recognized on stock received. Gain recognized to the extent of
  boot received. §354, §356.
- **Continuity of interest**: Target shareholders must receive a substantial portion (generally
  40%+) of consideration in acquirer stock. *Cash-heavy deals may fail the COI test.*

### Type B — Stock-for-Stock
- Acquirer uses SOLELY its voting stock to acquire at least 80% of target's stock.
- **Strictest form**: No cash, no boot (even $1 of cash disqualifies the entire transaction).
  *Chapman v. Commissioner*, 618 F.2d 856 (1st Cir. 1980).
- Useful for acquirers with highly valued stock and targets with low-basis shareholders who
  want deferral.

### Type C — Practical Merger (Assets for Stock)
- Acquirer acquires "substantially all" (generally 70%+) of target's assets solely for voting
  stock (limited boot allowed up to 20% if the 80% solely-for-voting-stock test is met
  considering the boot). §368(a)(1)(C), §368(a)(2)(B).
- Target must distribute all assets (including the stock received) to its shareholders and
  dissolve. §368(a)(2)(G).

### Reverse Triangular Merger
- Acquirer's subsidiary merges into the target (target survives). Target shareholders exchange
  stock for acquirer's voting stock.
- Preserves target's legal entity (useful when target has non-assignable contracts, licenses, permits).
- **Requirement**: Target must hold "substantially all" of both its own and the subsidiary's
  assets after the merger.

## Opportunity Zone Reinvestment

- **180-day window**: Capital gains from a business exit can be reinvested in a Qualified
  Opportunity Zone Fund within 180 days of the sale to defer recognition.
- **Deferral**: Deferred gain is recognized at the earlier of: sale of the QOZ investment
  or December 31, 2026.
- **Exclusion**: If QOZ investment is held for 10+ years, ALL appreciation in the QOZ
  investment is excluded from income (step-up to FMV at sale). §1400Z-2(c).
- **Post-2026 planning**: The deferral deadline (12/31/2026) is approaching. Gains deferred
  now will be recognized by 12/31/2026 regardless. The 10-year exclusion on appreciation
  remains valuable for new QOZ investments.

## State Tax Considerations

### California
- **Clawback**: CA may tax gains on the sale of a business if the seller was a CA resident
  during the period the gain accrued, even if the seller is no longer a CA resident at the
  time of sale. *Applies to installment sales where the seller moves out of CA before
  payments are received.* CA FTB Pub 1100.
- **1031 exchange clawback**: If a CA property was part of a §1031 exchange and the replacement
  property is out of state, CA tracks the deferred gain and taxes it upon ultimate disposition.

### New York
- **Source rules**: NY taxes nonresidents on income from NY sources. If the business has
  NY operations, a portion of the exit gain may be NY-source income.
- **Convenience of employer rule**: If the seller continues consulting for the buyer from
  outside NY, but the buyer is in NY, NY may claim the consulting income is NY-source.

### Succession Planning: Pre-Exit Gifting
- **Valuation discounts**: Gift minority interests in the business before the exit. Minority
  interests and lack-of-marketability discounts (15-35% combined) reduce the gift tax value.
- **Annual exclusion gifts**: $19,000/donee (2025). Gift small interests to family members.
- **GRAT/IDGT**: Transfer interests to a Grantor Retained Annuity Trust or Intentionally
  Defective Grantor Trust at discounted values. If the business appreciates (as expected
  before an exit), the appreciation passes to beneficiaries gift/estate-tax-free.
- **Timing**: Must be done BEFORE the exit is certain. Once a letter of intent is signed,
  discounts collapse and the IRS will challenge the valuation. *Gift early.*

## Common Mistakes

1. **C-Corp double taxation surprise** — Seller agrees to asset sale without modeling the
   corporate-level tax + shareholder-level tax. Combined rate exceeds 40%.
2. **Not negotiating §338(h)(10) for S-Corp sales** — Buyer gets step-up without the
   double-tax cost. Seller may pay slightly more but can negotiate a price increase.
3. **Missing the §1042 ESOP opportunity** — C-Corp owners who sell to third parties instead
   of an ESOP miss the permanent tax deferral (potentially elimination at death).
4. **Earnout recharacterized as compensation** — Tying earnout to seller's continued employment
   converts LTCG to ordinary income.
5. **Installment sale without §453A interest modeling** — The interest charge on deferred tax
   for sales >$5M can substantially erode the deferral benefit.
6. **Personal goodwill not documented** — Must establish personal goodwill before the sale
   with employment agreements, non-compete structures, and evidence of individual relationships.
7. **Ignoring state tax on exit** — CA clawback, NY source rules, and other state-specific
   traps can add millions in unexpected state tax.
8. **Gifting interests after the deal is announced** — Valuation discounts disappear once a
   sale is imminent. Pre-exit planning must occur well before any LOI or term sheet.
