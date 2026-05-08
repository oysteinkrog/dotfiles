# International Tax — Comprehensive Reference (TY 2025)

## Overview

US citizens and resident aliens are taxed on worldwide income regardless of where they live
or where the income is earned. This fundamental principle, combined with an overlapping web
of reporting requirements (FBAR, FATCA, Forms 5471, 8865, 8938, 3520), creates a compliance
burden that is unique among developed nations. Penalties for non-compliance are among the
harshest in the tax code — a single unreported foreign account can trigger a $12,909 non-willful
penalty or up to 50% of the account balance for willful violations. This reference covers the
major international tax provisions affecting individual taxpayers.

## Foreign Earned Income Exclusion — Section 911

### Exclusion Amounts
- **2025**: $130,000 per qualifying individual.
- Indexed annually for inflation.
- Applies only to **earned income** (wages, salaries, self-employment income) — NOT investment
  income, pensions, or Social Security.

### Qualification Tests (Must Meet ONE)
1. **Bona Fide Residence Test**: Taxpayer is a bona fide resident of a foreign country for an
   uninterrupted period that includes an entire calendar year. Requires establishing a genuine
   domicile in the foreign country — not merely physical presence. Factors: intention to remain,
   family location, nature of employment, local ties, foreign tax filings, visa type.
2. **Physical Presence Test**: Taxpayer is physically present in a foreign country for at least
   330 full days during any consecutive 12-month period. Days in transit through the US count
   as US days. *A single day's presence in the US breaks the "full day" count for that day.*
   Partial days in a foreign country do NOT count.

### Key Rules
- **Tax home must be in the foreign country**: If the taxpayer's tax home (principal place of
  business) remains in the US, §911 does not apply regardless of physical presence abroad.
- **Cannot exclude income earned in the US**: §911 applies only to foreign-source earned income.
- **Self-employment tax**: FEIE does NOT exclude income from self-employment tax.
  §911(a) exclusion applies only for income tax purposes. Social Security totalization
  agreements provide SE tax relief (see below).
- **Stacking rule**: Excluded income is "stacked" at the bottom of the tax brackets. Remaining
  taxable income is taxed as if the excluded amount were still taxable (higher effective rate).
  §911(d)(7). Example: $180K total income, $130K excluded, $50K taxable — but taxed at the
  rate applicable to someone earning $180K (roughly 22-24% bracket, not 12%).
- **Election**: Made on Form 2555. Once revoked, cannot re-elect for 5 years without IRS consent.

### Worked Example
```
US citizen living in Singapore:
Total earned income: $200,000
FEIE exclusion: $130,000
Remaining taxable: $70,000

Without FEIE: Tax on $200,000 ≈ $40,000 (after standard deduction)
With FEIE: Tax on $70,000 (stacked) ≈ $8,200
Foreign tax credit for Singapore tax paid on the $70,000 may further reduce US tax.

BUT: Self-employment tax (if self-employed) still applies on the full $200,000.
SE tax: $200,000 × 92.35% × 15.3% = ~$28,260 (up to SS wage base, then 2.9%)
```

## Foreign Housing Exclusion/Deduction

### Above the FEIE
Taxpayers qualifying for the FEIE may also exclude (employees) or deduct (self-employed) a
portion of foreign housing costs above a base amount.

- **Base amount**: 16% of FEIE maximum ($130,000 × 16% = $20,800 for 2025)
- **Housing expenses**: Rent, utilities (not phone/internet), insurance, furniture rental,
  parking, repairs. NOT: mortgage payments, purchased furniture, domestic help, pay TV.
- **Limitation**: 30% of FEIE ($39,000 for 2025) minus the base amount = maximum exclusion
  of $18,200. *Higher limits apply for certain high-cost cities (Tokyo, London, Hong Kong,
  Singapore, etc.) as published annually by the IRS.*
- **Report on Form 2555**

## Foreign Tax Credit — Section 901

### Credit vs. Deduction
- **Credit** (Form 1116): Dollar-for-dollar reduction of US tax. Almost always more valuable.
- **Deduction** (Schedule A): Reduces taxable income. Useful only if taxpayer has very low
  income or credits exceed limitation. Must choose credit OR deduction for ALL foreign taxes
  in a given year — cannot mix.

### Limitation Formula
```
FTC Limitation = US tax × (Foreign-source taxable income / Worldwide taxable income)
```
Cannot credit more foreign tax than the US tax attributable to foreign-source income.

### Separate Limitation Categories
- **General category**: Most active business income, wages
- **Passive category**: Dividends, interest, rents, royalties, passive income
- Each category has its own limitation calculation — excess credits in one category cannot
  offset tax in another.

### Carryback/Carryforward
- Excess foreign tax credits carry back 1 year and forward 10 years. §904(c).

### High-Tax Kickout
If passive income is taxed by a foreign country at a rate higher than the highest US rate,
it may be reclassified from the passive category to the general category. This prevents
high-taxed passive income from "wasting" the passive basket limitation.

### Country-by-Country Issues
- **Tax treaties**: May reduce foreign withholding rates (e.g., 15% instead of 30% on dividends).
  Must claim treaty benefits on the foreign side to get the reduced rate; then credit the
  actual amount paid.
- **Foreign tax must be creditable**: Must be an income tax (or tax in lieu of income tax).
  VAT, property tax, and most transaction taxes are NOT creditable.

### Tax Treaty Depth

**Limitation on Benefits (LOB) Clauses:**
Most modern US tax treaties include LOB provisions designed to prevent **treaty shopping** --
the practice of routing income through a treaty-country entity to claim reduced withholding
rates that the ultimate beneficial owner would not be entitled to. LOB clauses require the
treaty claimant to satisfy one or more tests: qualified person (publicly traded, government,
tax-exempt), ownership/base erosion test, active trade or business test, or derivative benefits
test. Failure to satisfy the LOB clause means the treaty benefit is denied even if the claimant
is otherwise a resident of the treaty country.

**The Saving Clause (Article 1(4) in Most US Treaties):**
The saving clause preserves the US right to tax its own citizens and residents as if the treaty
did not exist. This is a uniquely American provision -- it means that US citizens living abroad
generally cannot use a tax treaty to reduce their US tax on US-source income. **Limited exceptions**
to the saving clause exist (typically listed in the treaty protocol): foreign tax credits,
certain pension/social security provisions, and non-discrimination articles. Always check the
specific treaty's saving clause and its exceptions before advising a US citizen on treaty benefits.

**Treaty Shopping Risks:**
The IRS actively scrutinizes treaty claims. If a structure exists primarily to obtain treaty
benefits (e.g., a Netherlands holding company with no substance), the IRS may deny treaty
benefits under the LOB clause, the Principal Purpose Test (PPT, in newer treaties following
the OECD MLI), or the economic substance doctrine. Penalties for incorrect treaty claims
include accuracy-related penalties under Section 6662 and potential fraud penalties for egregious cases.

## FBAR — FinCEN Form 114

### Filing Requirement
Any US person (citizen, resident, entity) with a financial interest in or signature authority
over foreign financial accounts with an aggregate value exceeding **$10,000** at any time during
the calendar year must file an FBAR.

### What Counts as a Foreign Financial Account
- Bank accounts (checking, savings, time deposits)
- Securities accounts (brokerage accounts)
- Mutual funds and pooled investment vehicles
- Insurance policies with a cash value
- Pension accounts (in many cases)
- **Cryptocurrency**: FinCEN has proposed regulations extending FBAR to foreign-held crypto
  accounts. As of 2025, enforcement is increasing but regulatory clarity is still developing.

### Filing Details
- **Due date**: April 15 (automatic extension to October 15)
- **Filed electronically** through BSA E-Filing System (NOT with the tax return)
- **Separate from the tax return** — an FBAR is a Treasury Department filing, not an IRS filing

### Penalties
| Violation | Penalty | Notes |
|-----------|---------|-------|
| Non-willful | Up to $12,909 per account per year (2025) | Inflation-adjusted annually |
| Willful | Greater of $100,000 or 50% of account balance per year | Criminal penalties possible |
| Criminal | Up to $250,000 fine and/or 5 years imprisonment | 31 U.S.C. §5322 |

- **Willfulness**: Includes "willful blindness" — deliberately avoiding knowledge of filing
  requirements. *US v. Williams*, 489 Fed. Appx. 655 (4th Cir. 2012).
- **Reasonable cause defense**: Available for non-willful violations. Must show that the failure
  was due to reasonable cause and not willful neglect. Document reliance on professional advice.
- **Supreme Court limitation**: *Bittner v. United States*, 598 U.S. 85 (2023) — non-willful
  FBAR penalties are per report, not per account. This significantly limits penalties for
  taxpayers with multiple unreported accounts.

## FATCA — Form 8938

### Separate from FBAR
Form 8938 (Statement of Specified Foreign Financial Assets) is filed WITH the tax return.
It covers a broader range of assets than the FBAR but has higher filing thresholds.

### Thresholds
| Filing Status | End-of-Year Value | Any-Time-During-Year Value |
|--------------|-------------------|--------------------------|
| Single (US resident) | $50,000 | $75,000 |
| MFJ (US resident) | $100,000 | $150,000 |
| Single (abroad) | $200,000 | $300,000 |
| MFJ (abroad) | $400,000 | $600,000 |

### Assets Covered (Broader Than FBAR)
- All FBAR-reportable accounts PLUS:
- Foreign stock or securities not in a financial account
- Foreign partnership interests
- Foreign mutual funds
- Foreign hedge funds
- Foreign-issued life insurance or annuities with cash value
- Any financial instrument or contract with a foreign counterparty

### Penalties
- $10,000 failure-to-file penalty
- Additional $10,000 for each 30 days of non-filing after IRS notice (up to $50,000)
- 40% accuracy-related penalty on underpayments attributable to undisclosed foreign assets. §6662(j).
- Statute of limitations does not begin to run on the entire return if Form 8938 is not filed. §6501(c)(8).

## Form 3520 / 3520-A — Foreign Trusts and Large Foreign Gifts

### Filing Requirements

**Form 3520** (Annual Return to Report Transactions with Foreign Trusts and Receipt of Certain
Foreign Gifts) is required for:
1. **US persons receiving distributions from foreign trusts** -- any amount.
2. **US persons treated as owners of foreign trusts** -- under the grantor trust rules
   (Sections 671-679). This includes any US person who transfers property to a foreign trust
   with a US beneficiary (Section 679).
3. **US persons receiving gifts or bequests exceeding $100,000** from foreign persons
   (individuals or estates) during the tax year. For gifts from foreign corporations or
   foreign partnerships, the threshold is $19,570 (2025, indexed).

**Form 3520-A** (Annual Information Return of Foreign Trust with a US Owner) must be filed by
the foreign trust itself if it has a US owner. In practice, the US owner is responsible for
ensuring the trust files the form.

### Due Dates
- Form 3520: Due with the taxpayer's income tax return (April 15, or extended deadline).
  Extensions of the income tax return also extend Form 3520.
- Form 3520-A: Due March 15 (calendar-year trust). Extension available on Form 7004.

### Penalties
| Violation | Penalty |
|-----------|---------|
| Failure to report foreign trust distribution | **35%** of the gross value of the distribution |
| Failure to report US ownership of a foreign trust | **5%** of the gross value of trust assets (per year) |
| Failure to ensure Form 3520-A is filed | **5%** of the gross value of trust assets |
| Failure to report large foreign gifts | $10,000 initial penalty + $10,000 for each 30 days of non-filing after IRS notice (up to 25% of gift amount) |

Penalties are severe and largely automatic. Reasonable cause defense is available but the
standard is high. The statute of limitations does not begin to run on the entire tax return
if Form 3520 is not filed (§6501(c)(8)).

## Form 8865 — Return of US Persons with Respect to Certain Foreign Partnerships

### Filing Requirements

Form 8865 is required for US persons with certain interests in foreign partnerships:

| Category | Who Must File | Trigger |
|----------|--------------|---------|
| Category 1 | US person who controlled the partnership at any time during the year | >50% interest (by value or capital) |
| Category 2 | US person who owned 10%+ interest at any time AND the partnership was controlled by US persons | 10%+ interest in a US-controlled partnership |
| Category 3 | US person who contributed property to a foreign partnership | Contributions exceeding $100,000 (or if the contributor owned 10%+ interest after the contribution) |
| Category 4 | US person who had a reportable event (acquisition, disposition, change in proportional interest) | Certain acquisitions, dispositions, or changes |

### Penalties
- **$10,000 per return per year** for failure to file.
- **Continuation penalty**: Additional $10,000 for each 30-day period of non-filing after
  IRS notice (up to $50,000).
- **10% penalty** on the value of contributions not reported (Category 3 violations).
- Statute of limitations does not begin to run on the entire return if Form 8865 is not
  filed (§6501(c)(8)).

**Practical note:** Many US taxpayers with foreign business interests inadvertently hold
interests in entities classified as foreign partnerships under US tax rules (e.g., a foreign
LLC, a foreign joint venture). Entity classification under the check-the-box regulations
(Reg. 301.7701-3) determines whether a foreign entity is a partnership, corporation, or
disregarded entity for US tax purposes.

## Controlled Foreign Corporation (CFC) Rules

### GILTI — Section 951A
Global Intangible Low-Taxed Income. US shareholders of CFCs must include GILTI in income:
- **GILTI** = CFC's tested income minus deemed tangible income return (10% of qualified
  business asset investment, or QBAI).
- **C-Corp shareholders**: 50% deduction under §250, resulting in effective 10.5% rate
  (increasing to 13.125% for tax years after 2025 as the deduction drops to 37.5%).
- **Individual shareholders**: No §250 deduction. GILTI is taxed at ordinary income rates
  (up to 37%). *This is a major disadvantage for individual CFC shareholders.*
- **Workaround**: Individual can make §962 election to be taxed as if a corporation (claiming
  the §250 deduction), but this creates complexity — must pay tax at corporate rate on GILTI,
  then additional tax when amounts are actually distributed. See Section 962 Election detail below.
- **Form 5471**: Required for US persons who are officers, directors, or 10%+ shareholders of
  a CFC. Penalty for failure to file: $10,000 per form per year.

### Section 962 Election — Individual Taxed as Corporation for GILTI/Subpart F

A US individual shareholder of a CFC can elect under **Section 962** to be taxed as if they
were a domestic corporation for purposes of GILTI and Subpart F income inclusions. This is
a powerful planning tool because it unlocks two benefits otherwise available only to C corporations:

1. **Section 250 deduction**: 50% deduction for GILTI (37.5% for tax years after 2025), reducing
   the effective tax rate on GILTI from up to 37% (individual rate) to approximately **10.5-13.125%**
   (corporate rate after the Section 250 deduction).
2. **Foreign tax credits**: The individual can claim deemed-paid foreign tax credits under
   Section 960 that would otherwise only be available to corporate shareholders.

**Mechanics:**
- The election is made annually on the taxpayer's income tax return (attached statement).
- GILTI/Subpart F income is taxed at the **corporate rate** (21%) after the Section 250 deduction.
- When the CFC actually distributes the previously-taxed income, the individual recognizes
  the excess of the distribution over the tax already paid at the corporate rate as a dividend
  (potentially qualifying for the 20% LTCG rate if from a qualified foreign corporation).
- **Net effect**: Two layers of tax, but the combined effective rate is significantly lower
  than the individual's marginal rate on the initial inclusion.

**When to use:** Individual CFC shareholders with significant GILTI inclusions, especially
those whose CFCs pay meaningful foreign taxes (which generate credits under the election).

### GILTI High-Tax Exclusion

Under **Reg. 1.951A-2(c)(7)**, if a CFC pays foreign taxes at an effective rate exceeding
**90% of the US corporate rate** (currently 21% x 90% = **18.9%**), the tested income from
that CFC can be **excluded from GILTI** entirely.

**Key rules:**
- The election is made **annually** on the taxpayer's return.
- Applied on a **CFC-by-CFC, tested-unit-by-tested-unit** basis -- the high-tax exclusion
  can apply to one CFC while another CFC's income is still included in GILTI.
- The effective foreign tax rate is calculated by dividing the foreign taxes paid by the
  tested income (before any GILTI deductions).
- If the exclusion applies, the income is also excluded from Subpart F (it shifts from GILTI
  to the Section 954(b)(4) high-tax exception for Subpart F purposes).

**Practical impact:** US individuals with CFCs in high-tax jurisdictions (e.g., Japan at 30%+,
Germany at 30%+, France at 25%+) may be able to exclude the CFC's income from GILTI entirely,
eliminating the US tax on the CFC's earnings until actually distributed.

### Subpart F Income — Section 952
Certain passive and easily-movable income of a CFC is taxed currently to US shareholders,
regardless of whether distributed:
- Foreign personal holding company income (dividends, interest, rents, royalties)
- Foreign base company sales income (related-party transactions)
- Foreign base company services income
- Insurance income

## Passive Foreign Investment Company (PFIC) — Section 1291

### The PFIC Trap
A PFIC is any foreign corporation where:
- 75%+ of gross income is passive (income test), OR
- 50%+ of average assets produce (or are held to produce) passive income (asset test)

### Default Treatment (§1291 "Excess Distribution" Regime)
- Gain on sale or "excess distribution" is allocated ratably over the holding period.
- Amounts allocated to prior years are taxed at the highest rate in effect for each year
  PLUS an interest charge (as if the tax had been due in each prior year).
- **Result**: Punitive effective tax rate that can exceed 50-60%.

### Elections to Mitigate
1. **QEF election (§1295)**: Elect to include PFIC's ordinary earnings and net capital gains
   currently (like a CFC). Avoids the excess distribution regime. Requires the PFIC to provide
   a "PFIC Annual Information Statement." *Often impractical — many foreign funds refuse.*
2. **Mark-to-market election (§1296)**: For PFICs with marketable stock (traded on a qualified
   exchange). Mark to market annually — recognize gain/loss each year. Gain is ordinary income;
   loss is ordinary (limited to prior mark-to-market gains).

### Common PFIC Traps
- **Foreign mutual funds**: Almost all foreign mutual funds are PFICs. US persons should invest
  in US-domiciled funds that hold foreign securities, NOT directly in foreign funds.
- **Foreign holding companies**: A foreign corporation with substantial investment assets.
- **Foreign pension plans**: Some foreign pension plans hold PFIC investments, creating
  reporting nightmares. Treaty exemptions may apply (limited).

## Self-Employment Tax and Totalization Agreements

### The Problem
US self-employment tax (15.3% up to SS wage base, 2.9% above) applies to worldwide SE income.
A US citizen working abroad may also be subject to the foreign country's social security system,
creating double taxation of social insurance contributions.

### Totalization Agreements
The US has bilateral totalization agreements with approximately 30 countries (including UK,
Canada, Germany, France, Japan, Australia, South Korea, and others). These agreements:
- Prevent double social security taxation — worker pays into only ONE system.
- Generally: if assignment abroad is <5 years, pay into home country system.
  If >5 years, pay into host country system.
- **Certificate of Coverage**: Obtain from the Social Security Administration (Form SSA-7004
  or through totalization application). Provides proof of exemption from the foreign system.

### Countries WITHOUT Totalization Agreements
China, India, Brazil, Russia, most of Southeast Asia, most of Africa and the Middle East.
Workers in these countries may face double social security taxation with no relief mechanism.

## Expatriation Tax — Section 877A

### Covered Expatriate
A US citizen who renounces citizenship or a long-term resident (green card holder for 8+ of
the last 15 years) who surrenders the green card is a "covered expatriate" if ANY of:
1. Average annual net income tax for the 5 years preceding expatriation exceeds $201,000 (2025)
2. Net worth on the date of expatriation is $2M or more
3. Failed to certify full tax compliance for the 5 years preceding expatriation on Form 8854

### Mark-to-Market Exit Tax
- All worldwide assets are treated as sold at FMV on the day before expatriation.
- **Exclusion**: $866,000 of gain (2025, indexed) is excluded.
- Tax is owed on the deemed gain, even though no actual sale occurred.
- **Deferred compensation**: Subject to 30% withholding when distributed. §877A(d).
- **Specified tax-deferred accounts** (IRAs, 401(k)s): Treated as distributed in full on the
  day before expatriation. Entire balance is taxable (no 10% penalty). §877A(e).

### Section 2801 — Covered Expatriate Gift/Bequest Tax

US persons receiving **gifts or bequests from "covered expatriates"** (those who expatriated
after June 17, 2008 and meet the covered expatriate thresholds above) owe a tax under
Section 2801 equal to the **highest estate/gift tax rate (40%)** on the value of the gift
or bequest exceeding the annual exclusion amount ($19,000 for 2025).

**Key rules:**
- The tax is imposed on the US **recipient**, not the expatriate donor.
- Applies to transfers from covered expatriates regardless of the amount of time elapsed
  since expatriation -- there is no expiration.
- The annual exclusion amount applies per donor per year (same as the gift tax annual exclusion).
- Transfers to US charities and transfers to the expatriate's US citizen spouse (with a
  marital deduction) are exempt.
- A US trust receiving a covered gift/bequest may elect to be treated as a US person for
  this purpose, paying the tax directly rather than passing it through to beneficiaries.
- **Form 708** (proposed) is the designated reporting form, though IRS implementation of
  the reporting mechanism has been delayed. Taxpayers should track covered expatriate
  transfers and be prepared to report when final regulations are issued.

**Practical note:** This provision is frequently overlooked. US persons receiving gifts from
individuals who have renounced US citizenship should determine whether the donor is a
"covered expatriate" before accepting large transfers.

### Worked Example
```
US citizen expatriating with:
- Stock portfolio: basis $1M, FMV $5M → gain $4M
- Primary residence: basis $500K, FMV $1.5M → gain $1M
- IRA: $800,000

Exit tax calculation:
Total deemed gain: $5,000,000
Exclusion: ($866,000)
Taxable gain: $4,134,000
Tax at 23.8% (LTCG + NIIT): ~$983,892

IRA: $800,000 taxed as ordinary income → ~$296,000

Total exit tax: ~$1,279,892
PLUS: loss of future US tax treaty benefits as a covered expatriate
```

## State Tax Obligations While Abroad

### California
- Taxes worldwide income for **residents**. Residency does not automatically end by moving abroad.
- FTB applies a multi-factor "closer connection" test. Maintaining a CA home, family in CA,
  or CA professional licenses can maintain residency.
- **Safe harbor**: CA Pub 1031 lists factors. No absolute rule — facts-and-circumstances analysis.
- *Pro tip*: Establish domicile in a no-income-tax state BEFORE moving abroad. Otherwise, CA
  may claim continuing residency.

### New York
- Similar to CA in aggressiveness. Maintains "statutory resident" status if taxpayer maintains
  a "permanent place of abode" in NY and spends 183+ days in NY.
- **Convenience of employer rule**: If working remotely for a NY employer from abroad, NY may
  still tax the income unless the work is done for the "necessity" of the employer.

### Other States
- Most states: residency ends when you establish domicile abroad AND demonstrate intent not
  to return.
- **Virginia, New Mexico, South Carolina**: Known for aggressive pursuit of departing residents.
- **No-income-tax states**: Establish residency in FL, TX, NV, WA, TN, WY, SD, AK before
  going abroad to avoid state tax complications entirely.

## Digital Nomad Considerations

### Tax Home
- A taxpayer's "tax home" is generally the main place of business. §911(d)(3).
- A digital nomad with no fixed place of business may have their "tax home" wherever they
  spend the most time. If that place changes frequently, the nomad may be deemed to have
  NO tax home — which disqualifies the §911 FEIE.
- **Strategy**: Establish a principal place of business in one foreign location. Sign a lease,
  join a coworking space, register a business. Create facts supporting a fixed tax home abroad.

### Permanent Establishment Risk
- Working from a foreign country for extended periods may create a "permanent establishment"
  (PE) for the employer or the nomad's business, triggering corporate tax obligations in
  that country. Tax treaties define PE thresholds (typically 183 days of presence).
- Many countries have updated PE definitions to capture remote workers.

## Foreign Bank Account Voluntary Disclosure

### Streamlined Filing Compliance Procedures
For taxpayers who were not willful in failing to report foreign accounts:
- **Streamlined Domestic Offshore Procedures** (for US residents): File 3 years of amended
  returns + 6 years of FBARs. 5% penalty on the highest aggregate balance of unreported
  foreign accounts.
- **Streamlined Foreign Offshore Procedures** (for qualifying nonresidents): Same filing
  requirements but NO penalty. Must certify non-willfulness.

### Delinquent FBAR Submission Procedures
For taxpayers with no unreported income (just missed the FBAR):
- File the delinquent FBARs with a statement of reasonable cause.
- No penalty if the IRS has not already contacted the taxpayer.

### IRS Criminal Investigation (CI)
- Foreign account cases with willful violations are referred to CI.
- **5th Amendment**: Invoke immediately if contacted by CI. Retain criminal tax counsel.
- FBAR willfulness penalties and criminal prosecution are not mutually exclusive.

## Common Mistakes

1. **Confusing FBAR and Form 8938** — Both may be required. Different thresholds, different
   filing mechanisms, different penalties.
2. **Assuming the FEIE eliminates all tax** — Does not exclude SE tax, NIIT, or investment income.
3. **Investing in foreign mutual funds** — Creates PFIC reporting nightmares. Use US-domiciled
   funds to hold foreign investments.
4. **Not tracking foreign tax credits by category** — General and passive baskets cannot be
   mixed. Excess credits in one basket are wasted if the other basket has capacity.
5. **Failing to file Form 5471 for a CFC** — $10,000 penalty per form per year. And the statute
   of limitations does not begin to run on the entire return.
6. **Ignoring state tax while abroad** — CA and NY may continue to claim you as a resident.
   Establish clean domicile break before departure.
7. **Digital nomads without a tax home** — Moving every 3 months disqualifies the FEIE. Pick
   a base and establish genuine ties.
8. **Not using totalization agreements** — Double SE tax with agreement countries is unnecessary.
   Obtain a certificate of coverage.
