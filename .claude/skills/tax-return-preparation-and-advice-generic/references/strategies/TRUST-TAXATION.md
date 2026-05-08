# TRUST TAXATION — Comprehensive Guide

## Overview

Trust taxation is among the most complex areas of the Internal Revenue Code. The fundamental question — WHO pays the tax — depends entirely on trust classification. Trusts are taxed under Subchapter J (IRC ss641-692), and the compressed brackets make planning essential: a non-grantor trust hits the 37% bracket at just $15,650 of taxable income (2025), compared to $626,350 for a single individual.

---

## GRANTOR VS NON-GRANTOR TRUSTS

### The Threshold Question

Every trust analysis begins here. Under ss671-679, a "grantor trust" is disregarded for income tax purposes — ALL income, deductions, and credits are reported on the grantor's individual return (Form 1040). The trust does not file its own income tax return (though some practitioners file an informational Form 1041 with a grantor trust statement per Reg. ss1.671-4).

A "non-grantor trust" is a separate taxpaying entity, filing Form 1041 and paying tax at the trust's compressed rates — OR distributing income to beneficiaries via Schedule K-1, who then report it on their own returns.

### Grantor Trust Triggers (ss671-679)

Any ONE of these makes the trust a grantor trust as to the portion affected:

| IRC Section | Trigger | Common Application |
|---|---|---|
| ss673 | Reversionary interest >5% | Grantor retains right to get assets back |
| ss674 | Power to control beneficial enjoyment | Grantor can decide who gets what/when |
| ss675 | Administrative powers | Grantor can swap assets, borrow without security |
| ss676 | Power to revoke | Revocable living trusts |
| ss677 | Income for benefit of grantor/spouse | Trust pays grantor's obligations |
| ss678 | Person other than grantor treated as owner | Beneficiary with withdrawal power (Crummey) |
| ss679 | Foreign trusts with US beneficiaries | Anti-abuse for offshore trusts |

### Non-Grantor Trust Tax Rates (2025)

| Taxable Income | Rate |
|---|---|
| $0 - $3,150 | 10% |
| $3,151 - $11,450 | 24% |
| $11,451 - $15,650 | 35% |
| Over $15,650 | 37% |

Plus 3.8% Net Investment Income Tax (ss1411) on the LESSER of undistributed net investment income or AGI exceeding $14,450. Effective top marginal rate: **40.8%**.

**Critical insight**: A non-grantor trust with $100,000 of ordinary income pays approximately $35,498 in federal tax if it retains the income. If the same income is distributed to a beneficiary in the 24% bracket, the tax is $24,000 — a savings of $11,498. This is WHY distributable net income (DNI) planning is paramount.

---

## REVOCABLE LIVING TRUSTS

### Tax Treatment

A revocable living trust (RLT) is a grantor trust under ss676. During the grantor's lifetime:
- NO separate tax return required (though Reg. ss1.671-4(b)(2) permits optional Form 1041 filing)
- All income reported on grantor's Form 1040 using the grantor's SSN
- NO separate EIN needed during grantor's lifetime
- NO change in basis — assets retain the same basis as before transfer

### At Death

Upon the grantor's death, the RLT becomes irrevocable:
- Trust obtains its own EIN (IRS Form SS-4)
- Files Form 1041 for the first time
- Assets receive stepped-up basis under ss1014
- Trust may continue as a non-grantor trust or be distributed to beneficiaries per its terms
- First fiscal year can be chosen (not required to use calendar year) — allows income deferral of up to 11 months

**Practice tip**: The ability to choose a fiscal year-end for a newly irrevocable trust (Rev. Rul. 57-586) creates a planning opportunity. If the grantor dies in March, electing a January 31 fiscal year-end means the first return covers only 10 months, and beneficiaries don't report K-1 income until their return for the year containing January 31 of the following year.

---

## INTENTIONALLY DEFECTIVE GRANTOR TRUSTS (IDGTs)

### The Elegant Paradox

An IDGT is irrevocable for estate/gift tax purposes but intentionally structured to be a grantor trust for income tax purposes. Result: assets are OUTSIDE the grantor's estate, but the grantor pays the income tax — effectively making tax-free gifts to beneficiaries equal to the income tax paid.

### How to Create

Typically triggered by retaining a power under ss675(4)(C) — the power to substitute assets of equivalent value in a non-fiduciary capacity. See Rev. Rul. 2008-22 (power to substitute does not cause estate inclusion under ss2036/2038 if exercisable in non-fiduciary capacity).

### The Installment Sale to IDGT

The most powerful IDGT strategy (endorsed by Fidelity Investments v. Commissioner, T.C. Memo 2012-345, by analogy):

1. **Seed the IDGT** with a gift of ~10% of intended value (uses gift tax exemption)
2. **Sell appreciated assets** to the IDGT in exchange for an installment note (ss453)
3. **No gain recognized** on the sale — because the grantor is selling to himself for income tax purposes (Rev. Rul. 85-13)
4. **Interest paid** at the Applicable Federal Rate (AFR) — currently ~4.5% for long-term, far below market returns
5. **Appreciation above AFR** passes to beneficiaries transfer-tax-free
6. **Grantor pays income tax** on trust income — further reducing the estate without gift tax

**Worked Example**:
- Grantor seeds IDGT with $1M gift (uses $1M of $13.99M exemption)
- Sells $9M of assets to IDGT for 9-year installment note at 4.5% AFR
- Assets appreciate at 8% annually
- After 9 years: IDGT holds ~$18M in assets, has paid back $9M + interest
- Net transfer to beneficiaries: ~$9M — using only $1M of gift tax exemption
- Grantor's payment of income tax on trust income over 9 years: additional ~$2M transferred tax-free

### IDGT + Life Insurance

Combine IDGT with second-to-die life insurance policy:
- Trust owns the policy (outside both spouses' estates)
- Premium payments are "sales" not gifts (avoiding Crummey notice requirements)
- Death benefit passes to beneficiaries completely income-tax-free AND estate-tax-free

---

## CHARITABLE REMAINDER TRUSTS (CRTs)

### Structure

IRC ss664. Donor transfers assets to trust, receives income stream for life or term of years (max 20), remainder passes to charity. Donor gets upfront charitable deduction for present value of remainder interest.

### CRAT vs CRUT

| Feature | CRAT (Annuity Trust) | CRUT (Unitrust) |
|---|---|---|
| Payment | Fixed dollar amount | Fixed percentage of annually revalued assets |
| Minimum payout | 5% of initial FMV | 5% of annual FMV |
| Maximum payout | 50% of initial FMV | 50% of annual FMV |
| Additional contributions | NOT allowed | Allowed |
| Inflation protection | None (fixed payment) | Yes (payment grows with assets) |
| 10% remainder test | Must pass at creation | Must pass at creation and each addition |
| IRS valuation | ss7520 rate | ss7520 rate |

### Four-Tier Taxation of CRT Distributions (ss664(b))

Distributions are taxed in this order (worst-first):

1. **Ordinary income** (to extent of current and accumulated ordinary income)
2. **Capital gains** (to extent of current and accumulated capital gains, short-term before long-term)
3. **Other income** (tax-exempt interest, etc.)
4. **Return of corpus** (tax-free)

**Worked Example — CRT for Concentrated Stock Position**:
- Taxpayer holds $5M of stock with $500K basis (95% gain)
- Direct sale: $4.5M gain x 23.8% (20% LTCG + 3.8% NIIT) = $1,071,000 tax
- CRT approach: Transfer stock to CRUT, trust sells stock — NO immediate tax (CRT is tax-exempt under ss664(c))
- 5% CRUT pays $250,000/year (growing with trust value)
- Tax on distributions: ordinary rates on ordinary income tier, capital rates on capital gain tier
- Charitable deduction: ~$1.5M (depends on ss7520 rate, age, payout rate)
- Tax savings on deduction: $1.5M x 37% = $555,000
- Net advantage: CRT defers and spreads recognition over decades, provides immediate deduction, and more capital compounds

### The 5% Probability of Exhaustion Test

Rev. Rul. 77-374: IRS requires that CRATs have less than 5% probability of exhaustion (running out of money before the remainder passes to charity). CRUTs are not subject to this test because the payout adjusts with asset value.

### 10% Remainder Test

ss664(d): The present value of the charitable remainder must be at least 10% of the initial fair market value. In high-interest-rate environments, this is easier to meet. In low-rate environments, longer terms or lower payout rates may be needed.

---

## CHARITABLE LEAD TRUSTS (CLTs)

### Structure (Reverse of CRT)

Charity receives income stream FIRST, then remainder passes to donor or donor's family. Two forms:

- **Grantor CLT**: Donor gets upfront income tax deduction, but must report trust income annually. Useful when donor has a single high-income year.
- **Non-grantor CLT**: No upfront deduction, but reduces estate/gift tax on remainder transfer.

### CLAT vs CLUT

| Feature | CLAT (Annuity) | CLUT (Unitrust) |
|---|---|---|
| Payment to charity | Fixed amount | Fixed % of annually revalued assets |
| Estate planning use | "Zeroed-out" CLAT | Less common |
| Best when | Assets will appreciate above ss7520 rate | Uncertain growth |

### The Zeroed-Out CLAT

Analogous to a zeroed-out GRAT. Structure the annuity payments so that the present value of the charitable stream equals the full value of the assets transferred — resulting in $0 taxable gift. Any appreciation above the ss7520 rate passes to heirs gift-tax-free.

**Worked Example**:
- Transfer $10M to 15-year CLAT when ss7520 rate is 5.4%
- Annual annuity to charity: ~$961,000 (calculated to zero out gift value)
- If assets earn 8%: remainder to heirs after 15 years = ~$5.2M (tax-free transfer)
- If assets earn 5.4% (exactly ss7520 rate): remainder = $0
- Total charitable gifts: $14.4M over 15 years

---

## DYNASTY TRUSTS AND GENERATION-SKIPPING TRANSFER TAX

### GSTT Basics (ss2601-2664)

The GST tax is a separate 40% tax imposed on transfers to "skip persons" (generally grandchildren or more remote descendants, or unrelated persons more than 37.5 years younger). The $13.99M GST exemption (2025) is separate from the estate/gift tax exemption (though the same dollar amount).

### Dynasty Trust Strategy

A dynasty trust is designed to last for multiple generations, avoiding estate tax at each generational level:

1. **Fund with GST exemption**: Allocate $13.99M of GST exemption to the trust
2. **Choose favorable state**: Trust situs in a state with no rule against perpetuities and no state income tax on trusts:
   - **South Dakota**: No rule against perpetuities, no state income tax, strong asset protection, directed trust statute
   - **Nevada**: No rule against perpetuities, no state income tax, strong spendthrift protections
   - **Delaware**: 360-year rule against perpetuities, no state income tax on out-of-state beneficiaries, Court of Chancery expertise
   - **Alaska**: No rule against perpetuities, no state income tax, community property trust option
3. **Trust grows tax-free** at estate level: if $13.99M grows at 7% for 100 years, the trust holds ~$11.5 BILLION — all free of estate tax at every generation

### GST Exemption Allocation

**Automatic allocation** (ss2632(c)): GST exemption is automatically allocated to direct skips and transfers to GST trusts, unless the taxpayer elects out on Form 709.

**CRITICAL**: Failure to properly allocate GST exemption is one of the most expensive planning errors. An inadvertently non-exempt dynasty trust worth $50M at the next generation's death would face $20M in GST tax (40%).

---

## QUALIFIED PERSONAL RESIDENCE TRUST (QPRT)

### Mechanics (ss2702)

1. Transfer personal residence to irrevocable trust
2. Retain right to live in home for fixed term of years
3. At end of term, home passes to beneficiaries (or trust for their benefit)
4. Gift value = FMV of home minus present value of retained interest (calculated using ss7520 rate and term)

### Discount Calculation

**Worked Example**:
- Home FMV: $2,000,000
- Grantor age: 65
- Retained term: 10 years
- ss7520 rate: 5.4%
- Gift value: approximately $780,000 (61% discount from FMV)
- Uses only $780,000 of gift/estate tax exemption to transfer $2M home
- If home appreciates to $3M in 10 years: additional $1.22M transferred tax-free

### QPRT Risks

- **Mortality risk**: If grantor dies during retained term, ENTIRE home value returns to estate (ss2036) — as if the QPRT was never created. Mitigate by purchasing term life insurance for the retained period.
- **Post-term rent**: Grantor must pay fair market rent to continue living in the home after the term expires. This is actually a BENEFIT — rent payments further reduce the estate.
- **No step-up**: Beneficiaries receive carryover basis (grantor's basis), not stepped-up basis at grantor's death.

---

## DISTRIBUTABLE NET INCOME (DNI) AND THE 65-DAY ELECTION

### DNI (ss643)

DNI is the mechanism that prevents double taxation of trust income. It caps the amount the trust can deduct for distributions AND the amount beneficiaries must include:

**DNI = Taxable income of trust + tax-exempt interest - capital gains allocated to corpus + distribution deduction adjustments**

### The 65-Day Election (ss663(b))

A trust or estate can elect to treat distributions made within the first 65 days of a tax year as having been made on the LAST day of the preceding tax year.

**Practical application**: Trustee realizes in February that the trust has $200,000 of undistributed income from the prior year, which would be taxed at 37% + 3.8% NIIT. Trustee distributes $200,000 by March 6 and makes the ss663(b) election on the Form 1041 for the prior year. The income is taxed on the beneficiary's return instead — potentially at 24% or lower.

**Election mechanics**: Made on Form 1041, filed by the due date (including extensions). Once made for a year, it is irrevocable for that year.

### Separate Share Rule (ss663(c))

When a trust has multiple beneficiaries, each beneficiary's share of DNI is determined separately. This prevents one beneficiary's distribution from affecting another's tax treatment. Particularly important in estates with specific bequests.

---

## STATE INCOME TAX ON TRUSTS

### The Landscape (Massive Variation)

States use wildly different nexus rules to tax trust income. Key factors:

| Nexus Factor | States Using This Factor |
|---|---|
| Grantor/creator domicile | CA, CT, IL, MD, MI, MN, NY, OH, PA, VA |
| Trustee location | CA, CT, MO, NH, PA, WI |
| Beneficiary residence | CA, GA, NC, ND, TN |
| Trust administration | CA, CT, MO, NY |
| Property situs | Most states (for real property income) |

### High-Impact State Issues

**California**: Taxes ALL income of a trust if ANY trustee or beneficiary is a CA resident — with limited apportionment. Even a non-grantor trust created by a deceased NY resident with a CA beneficiary receiving 10% of distributions may owe CA tax on 10% of ALL trust income. (Cal. Rev. & Tax. Code ss17742-17745)

**New York**: Taxes "resident trusts" (created by NY domiciliary) — BUT provides an exemption if the trust has NO NY trustee, NO NY assets, and NO NY source income. (NY Tax Law ss605(b)(3)(D)). This exemption is powerful but often missed.

**Illinois**: Taxes trusts created by IL residents regardless of where administered — challenged in Linn v. Department of Revenue (2017), where the IL Supreme Court held that taxing a trust solely based on the deceased grantor's residency violated due process.

**Pennsylvania**: Taxes trust income based on trustee residence (72 P.S. ss7601(a)).

### Planning Strategy: Trust Situs Selection

For a wealthy family in California creating a dynasty trust:
1. Choose SD or NV trust situs (no state income tax)
2. Appoint non-CA trustee (or corporate trustee in SD/NV)
3. Ensure no CA-source income in the trust
4. Keep beneficiary distributions as principal (not income) where possible
5. Potential savings: 13.3% CA tax on ALL trust income, every year, for generations

**Warning — Kaestner (2019)**: In North Carolina Department of Revenue v. Kimberley Rice Kaestner 1992 Family Trust, 588 U.S. 293 (2019), the U.S. Supreme Court held that a state cannot tax a trust's income based SOLELY on a beneficiary's in-state residence when the beneficiary has no right to demand distributions. This limits state taxation power but does NOT prevent states from using OTHER nexus factors (trustee, administration, etc.).

---

## FORM 1041 OVERVIEW

### Who Must File

- Domestic trust with gross income of $600 or more
- Trust with ANY taxable income
- Trust with a nonresident alien beneficiary

### Key Schedules and Attachments

| Form/Schedule | Purpose |
|---|---|
| Form 1041 | Trust income tax return |
| Schedule B | Income Distribution Deduction (DNI calculation) |
| Schedule K-1 | Beneficiary's share of income, deductions, credits |
| Form 8960 | Net Investment Income Tax (3.8% surtax) |
| Schedule D | Capital gains and losses |
| Form 4952 | Investment Interest Expense Deduction |

### Trust-Specific Deductions

- **Personal exemption**: $300 for simple trusts (required to distribute all income currently), $100 for complex trusts
- **Administration expenses**: Trustee fees, accounting fees, legal fees — deductible ONLY to the extent they are unique to trust administration (not common individual expenses) per ss67(e) and the TCJA suspension of miscellaneous itemized deductions (though trust-specific fees remain deductible per Notice 2018-61)
- **Charitable deduction**: NO AGI limitation for trusts (ss642(c)) — trusts can deduct 100% of amounts permanently set aside for charity IF the governing instrument authorizes charitable payments

### Trust Accounting Income vs Taxable Income

These are DIFFERENT concepts. Trust accounting income (governed by the trust instrument and state law) determines what must be distributed. Taxable income (governed by the IRC) determines what is taxed. A trustee must track both.

---

## SPECIAL PURPOSE TRUSTS

### Spendthrift Trusts

Include provisions preventing beneficiaries from assigning their interest and protecting trust assets from beneficiaries' creditors. Standard in modern trust drafting. Does NOT protect against IRS tax liens (United States v. Estate of Bess, 357 U.S. 51 (1958)).

### Asset Protection Trusts (DAPTs)

Domestic Asset Protection Trusts — available in 19+ states (NV, SD, DE, AK, etc.) — allow a grantor to be a discretionary beneficiary of their own irrevocable trust while receiving creditor protection. Key requirements vary by state:
- Typically require in-state trustee
- Statute of limitations on fraudulent transfer claims (2-4 years)
- Must be irrevocable
- Federal tax treatment: generally treated as grantor trust (ss677)

**Warning**: Not yet fully tested in bankruptcy courts. In re Huber, 493 B.R. 798 (Bankr. W.D. Wash. 2013) applied the state fraudulent transfer law of the debtor's home state (WA) rather than the trust situs state (AK), undermining the DAPT protection.

### Special Needs Trusts (SNTs)

Two types:
1. **First-party SNT** (ss1917(d)(4)(A) of Social Security Act): funded with the disabled beneficiary's own assets, must include Medicaid payback provision, beneficiary must be under 65 at creation
2. **Third-party SNT**: funded by someone other than the beneficiary, NO Medicaid payback required, can be testamentary or inter vivos

Both are designed to supplement (not supplant) government benefits. Income taxation depends on grantor trust status.

### Electing Small Business Trust (ESBT) — ss1361(e)

Allows a trust to be an S-Corp shareholder. The S-Corp income portion is taxed at the highest individual rate (37%) with NO distribution deduction. The election is made by the trustee and is irrevocable without IRS consent.

### Qualified Subchapter S Trust (QSST) — ss1361(d)(3)

Alternative to ESBT for S-Corp ownership. Must have only ONE current income beneficiary, must distribute all income currently, corpus distributions only to that beneficiary. The beneficiary (not trust) reports the S-Corp income — often more tax-efficient than ESBT.

---

## KEY PLANNING TAKEAWAYS

1. **Always determine grantor trust status first** — it controls everything
2. **Non-grantor trust income over $15,650 is taxed at 37%** — distribute to lower-bracket beneficiaries when possible
3. **The 65-day election (ss663(b)) is a free option** — evaluate annually by mid-February
4. **State trust taxation varies enormously** — trust situs selection can save millions over a dynasty trust's life
5. **IDGTs are the workhorse** of high-net-worth estate planning — income tax payment by grantor is a gift-tax-free transfer
6. **CRTs are unmatched** for concentrated stock positions — tax-free sale inside trust, charitable deduction, income stream
7. **GSTT exemption allocation errors are catastrophic** — always file Form 709 and confirm allocation
8. **Kaestner limits state taxing power** but does not eliminate it — plan around ALL nexus factors, not just beneficiary residence
