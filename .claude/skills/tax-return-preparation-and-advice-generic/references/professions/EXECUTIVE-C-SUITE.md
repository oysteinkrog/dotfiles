# Executive / C-Suite — Tax Reference Guide (TY 2025)

## 1. Overview

C-suite executives at public and large private companies face a unique constellation of tax
issues driven by complex compensation packages: RSUs, ISOs, deferred compensation, golden
parachute provisions, and supplemental retirement plans. The interplay between IRC §162(m),
§409A, §280G, and various equity compensation rules creates a landscape where a single
misstep — like failing to make a §409A deferral election on time — can trigger a 20% penalty
tax plus interest on the entire deferred amount. This reference covers the critical tax rules
for corporate officers, directors, and senior executives.

## 2. Section 162(m) — $1M Deduction Limit

### Rule
IRC §162(m) limits the deduction a publicly held corporation can claim for compensation paid
to "covered employees" to $1,000,000 per year per individual.

### Who Is a Covered Employee
Post-TCJA (2018+), "covered employee" includes:
- CEO (or principal executive officer)
- CFO (or principal financial officer)
- Next three highest-compensated officers
- **Once a covered employee, always a covered employee** — status is permanent once triggered
  (for tax years beginning after 12/31/2026 for certain employees first covered before 2027).
  This "once covered, always covered" rule was expanded by the American Rescue Plan Act (2021).

### What Counts as Compensation
Post-TCJA: ALL remuneration, including performance-based compensation. The prior exception
for performance-based pay and commissions was eliminated by TCJA for tax years after 2017
(with limited transition relief for binding contracts in effect on 11/2/2017).

### Impact on the Executive
- §162(m) limits the COMPANY's deduction, not the executive's income. The executive still
  pays full tax on all compensation.
- Negotiating point: companies may structure compensation to mitigate lost deductions
  (e.g., shift to equity, deferred compensation that is not immediately deductible).

## 3. Section 409A — Deferred Compensation Rules

### Scope
§409A governs virtually all deferred compensation arrangements, including:
- Supplemental Executive Retirement Plans (SERPs)
- Deferred bonus arrangements
- Severance packages (if exceeding certain thresholds)
- Stock appreciation rights (SARs) settled in cash
- Discounted stock options (exercise price below FMV at grant)
- Phantom stock plans

### Key Requirements
1. **Initial deferral election**: Must be made before the beginning of the year in which
   services are performed. For new hires, within 30 days of eligibility (covering only
   compensation earned after the election). For performance-based comp with a performance
   period of 12+ months, by 6 months before the end of the performance period.
2. **Permissible distribution events**: Separation from service, disability, death, specified
   time or fixed schedule, change in control, or unforeseeable emergency. No other triggers.
3. **Six-month delay**: Distributions to "specified employees" (generally top 50 officers by
   compensation at public companies) upon separation from service must be delayed 6 months.
   §409A(a)(2)(B)(i). This catches many departing executives by surprise.
4. **Anti-acceleration rule**: Cannot accelerate the time or schedule of any payment, with
   limited exceptions (domestic relations orders, conflicts of interest, de minimis cashouts).
5. **Subsequent deferral elections**: Can delay payment by at least 5 additional years, but
   the new election must be made at least 12 months before the originally scheduled payment date.

### Penalty for Noncompliance
- **20% additional tax** on the amount deferred (not just the current year's payment)
- Plus interest at the underpayment rate plus 1% from when the amount was first deferred
  or, if later, when it was no longer subject to a substantial risk of forfeiture
- These penalties are in ADDITION to regular income tax
- Example: $2M deferred over 5 years, §409A violation → $400,000 penalty tax + interest
  from the vesting date, plus regular income tax

### Common §409A Traps
- **Stock options granted at a discount**: If exercise price < FMV on grant date, the option
  is deferred compensation subject to §409A. Common with private companies that undervalue stock.
  Must use a proper 409A valuation (typically a third-party valuation, safe harbor under
  Reg. §1.409A-1(b)(5)(iv)).
- **Modified severance agreements**: Changing the time or form of payment in a severance
  arrangement can create a §409A violation.
- **Linked plans**: If two plans are treated as a single plan and one is compliant but the
  other is not, both may be in violation.

## 4. Section 280G — Golden Parachute Payments

### The 3x Base Amount Test
When there is a "change in ownership or control" of a corporation, payments to "disqualified
individuals" (officers, shareholders, highly compensated employees) that equal or exceed 3x
their "base amount" trigger the parachute payment rules.

- **Base amount**: Average W-2 compensation for the 5 calendar years preceding the change in
  control (or shorter period if employed less than 5 years). Includes salary, bonuses, equity
  vesting, and other taxable compensation.
- **Excess parachute payment**: The amount by which the total parachute payments exceed 1x
  the base amount. §280G(b)(1).

### Penalties (Dual)
1. **To the executive**: 20% excise tax on excess parachute payments. §4999. This is in
   ADDITION to regular income tax. Not deductible.
2. **To the corporation**: Loss of deduction for any excess parachute payment. §280G(a).

### Worked Example
```
Executive base amount (5-year average compensation): $800,000
Change-in-control triggers total payments of: $2,500,000
   (acceleration of RSUs: $1,200,000; severance: $800,000; bonus: $500,000)

3x test: 3 × $800,000 = $2,400,000
Total parachute payments ($2,500,000) EXCEED 3x threshold → §280G applies

Excess parachute payment: $2,500,000 - $800,000 (1x base) = $1,700,000
20% excise tax to executive: $1,700,000 × 20% = $340,000
Plus regular income tax: $2,500,000 × 37% = $925,000
Plus FICA/Medicare: additional amounts
Total tax on $2,500,000: approximately $1,265,000+ (50%+ effective rate)
Company loses $1,700,000 deduction (tax cost at 21%: $357,000)
```

### Planning Strategies
- **Gross-up provision**: Company pays the executive additional compensation to cover the
  excise tax (and the tax on the gross-up). Extremely expensive — can cost 2-3x the excise
  tax amount. Increasingly rare post-Dodd-Frank and say-on-pay scrutiny.
- **Cutback (best-net) provision**: Payments are reduced to just below 3x the base amount
  (the "safe harbor"), but only if the executive is better off after tax with the reduced
  amount than with the full amount plus excise tax. Most common current approach.
- **Shareholder approval exception**: If payments are approved by >75% vote of shareholders,
  §280G does not apply. Only available to private companies. §280G(b)(5)(B).
- **Reasonable compensation exception**: Payments for services rendered after the change in
  control (e.g., genuine consulting agreements) may be excluded from parachute calculations
  if they represent reasonable compensation for actual services. Reg. §1.280G-1, Q&A-9.

## 5. RSU Taxation for Executives

### Basic Rules
- **At vesting**: FMV of shares is ordinary income (W-2 Box 1). Basis = FMV at vest.
- **At sale**: Gain/loss above/below vest-date FMV is capital gain/loss. Short-term if sold
  within 1 year of vesting; long-term if held >1 year after vesting.
- **Withholding**: Employers typically withhold at the 37% supplemental wage rate for federal
  (for supplemental wages over $1M in the year) plus applicable state and FICA.

### The $0 Basis Problem
- **1099-B from broker**: Often reports cost basis as $0 or blank (especially for RSUs managed
  through platforms like Morgan Stanley, Schwab, Fidelity, E*TRADE).
- **If reported as-is**: IRS sees the full sale proceeds as gain → CP2000 notice for unreported income.
- **Correct treatment**: Basis = FMV at vesting (as reported on W-2 and supplemental pay stub).
  Must reconcile 1099-B with W-2 and adjust basis on Form 8949 using code B (short-term,
  basis not reported) or code E (long-term, basis not reported).
- *This is the single most common mistake on executive tax returns.*

### Double Counting Trap
RSU income appears on both the W-2 and the 1099-B. If the executive reports the W-2 income
AND reports the 1099-B with $0 basis, they are taxed twice on the same income. Always
reconcile these two documents.

## 6. ISO Strategies for Executives

### AMT Planning
- **ISO exercise spread** (FMV minus exercise price) is an AMT preference item. §56(b)(3).
- Large ISO exercises can trigger AMT in the hundreds of thousands of dollars.
- **Strategy**: Exercise only enough ISOs each year to keep AMT equal to regular tax
  ("AMT crossover" analysis). Use Form 6251 projections.
- **AMT credit carryforward**: Excess AMT paid due to ISO timing creates a minimum tax credit
  (Form 8801) that can be used against regular tax in future years when regular tax > AMT.
- After selling ISO shares (qualifying or disqualifying disposition), the AMT adjustment
  reverses, generating AMT credit recovery.

### Qualifying vs. Disqualifying Dispositions
- **Qualifying**: Hold 2 years from grant date AND 1 year from exercise date. All gain is LTCG.
- **Disqualifying**: Sell before either holding period is met. Spread at exercise is ordinary
  income (W-2 income); gain above exercise-date FMV is capital gain.
- **Strategy when stock has dropped**: If stock FMV has dropped below exercise price, a
  disqualifying disposition may be beneficial — ordinary income is limited to the actual gain
  (or $0 if sold at a loss), and the AMT preference item is reversed.

## 7. Section 83(i) — Qualified Equity Grant Deferral

For executives and employees of private companies (not publicly traded):
- **Deferral election**: Can elect to defer income recognition on qualified stock received in
  exchange for services for up to 5 years from the taxable event.
- **Requirements**: Company must have written plan granting equity to at least 80% of employees;
  employee cannot be CEO, CFO, or among the 4 highest-paid officers; employee cannot be a 1%+
  shareholder. *This effectively excludes most C-suite executives but may benefit VP-level and below.*
- **Practical use**: Limited adoption due to restrictive requirements and complexity.

## 8. Executive Retirement Planning

### Supplemental Executive Retirement Plans (SERPs)
- **Unfunded, unsecured promise** to pay retirement benefits. Not subject to ERISA funding
  requirements (if limited to a "select group of management or highly compensated employees").
- **Tax treatment**: Deferred under §409A rules. Taxed as ordinary income when distributed.
  Company gets deduction when executive recognizes income. §404(a)(5).
- **Risk**: SERPs are unsecured — if the company goes bankrupt, the executive is a general
  creditor. *Enron executives lost millions in SERPs.*
- **Rabbi trusts**: Assets set aside in a trust that is still subject to claims of general
  creditors (maintaining the "unfunded" status for tax purposes). Provides some protection
  against unwillingness to pay but not inability.

### Net Unrealized Appreciation (NUA) Strategy
If the executive holds employer stock in a 401(k):
- **At separation from service**: Take a lump-sum distribution of the ENTIRE account balance
  (required for NUA treatment).
- **Employer stock**: Transfer in-kind to a taxable brokerage account. Pay ordinary income tax
  ONLY on the cost basis of the stock in the plan (often very low).
- **NUA** (appreciation while in the plan): Taxed at LTCG rates when the stock is eventually sold.
  No 10% early withdrawal penalty on the NUA portion.
- **Other plan assets** (non-employer stock): Roll over to an IRA to avoid current taxation.

### Worked Example: NUA
```
Executive retires at age 58 with 401(k) containing:
- 10,000 shares of employer stock: cost basis in plan = $100,000, current FMV = $1,500,000
- Other investments: $500,000

NUA Strategy:
- Take lump-sum distribution of entire plan
- Transfer employer stock in-kind to brokerage → pay ordinary tax on $100,000 basis only
  Tax at 37%: $37,000 (NO 10% early withdrawal penalty on NUA portion)
- Roll other $500,000 to IRA (no current tax)
- When stock is sold: $1,400,000 NUA taxed at 20% LTCG + 3.8% NIIT = $333,200
- Total tax on $1,500,000 of stock: $370,200 (24.7% effective rate)

Without NUA (all rolled to IRA then distributed):
- $1,500,000 × 37% = $555,000 ordinary income tax
- Savings from NUA: approximately $184,800
```

## 9. Split-Dollar Life Insurance

### Two Regimes
1. **Economic benefit regime** (endorsement method): Employer owns the policy. Executive
   is taxed annually on the "economic benefit" (roughly the term insurance cost) of the
   coverage. At policy termination, executive's interest is taxed. Can provide significant
   tax-free wealth transfer to executive's family through an ILIT.
2. **Loan regime** (collateral assignment method): Executive (or trust) owns the policy.
   Employer's premium payments are treated as loans. Must charge AFR interest or the
   forgone interest is compensation. At death, loan is repaid from death benefit; excess
   passes to beneficiaries.

### Estate Planning Application
- Executive's ILIT owns the policy under the economic benefit regime
- Death benefit passes to the trust outside the executive's estate
- Used to fund estate taxes, provide liquidity, or simply transfer wealth
- *Must comply with split-dollar final regulations (Reg. §1.61-22, §1.7872-15)*

## 10. Clawback Provisions

### Tax Treatment of Returned Compensation
- Under Dodd-Frank (and SOX §304), executives may be required to return compensation.
- **In the same year**: Reduces W-2 income for the year.
- **In a subsequent year**: Executive may claim a deduction under §1341 (claim of right doctrine)
  OR take a credit for the tax paid in the prior year on the repaid amount — whichever produces
  the greater benefit.
- **§1341 election**: If the repaid amount exceeds $3,000, the executive can either (a) deduct
  the repayment as a miscellaneous deduction (limited utility post-TCJA) or (b) reduce current
  year's tax by the tax attributable to the repaid income in the prior year.
- The prior-year credit is almost always more favorable for high-income executives.

## 11. Non-Compete Payments

- Payments for a covenant not to compete are **ordinary income** to the recipient. §197 for
  the payor (15-year amortization).
- **Multi-state allocation**: May be taxable in every state where the executive was restricted
  from competing. Allocation methods vary by state. California does not enforce non-competes
  but may still tax payments allocated there.
- **Timing**: Taxable when received (cash basis) or when right to receive is established
  (if subject to §409A).

## 12. Change-in-Control Planning Checklist

### Pre-Transaction
- [ ] Calculate base amount (5-year average W-2 compensation)
- [ ] Model total parachute payments (acceleration of equity, severance, bonuses, benefits)
- [ ] Determine if 3x threshold is exceeded
- [ ] Run "best net" / cutback analysis (compare after-tax results with and without §280G)
- [ ] Review §409A compliance for all deferred compensation arrangements
- [ ] Confirm six-month delay provisions for specified employees
- [ ] Model AMT impact of accelerated ISO vesting (if applicable)
- [ ] Review non-compete payment structure and state tax allocation
- [ ] Consider reasonable compensation allocations for post-closing services
- [ ] Evaluate charitable strategies for concentrated stock (CRT, DAF before closing)

### Medicare IRMAA Planning
- **Income-Related Monthly Adjustment Amount**: High-income retirees pay surcharges on
  Medicare Part B and Part D premiums.
- **2025 MAGI thresholds**: Surcharges begin at $106,000 (single) / $212,000 (MFJ).
  Uses MAGI from 2 years prior (2023 income for 2025 premiums).
- **Planning**: In the 2 years before Medicare enrollment (age 63-64), minimize MAGI.
  Defer income, maximize pre-tax contributions, avoid large Roth conversions.
- **IRMAA appeal**: If income was high due to a one-time event (retirement, severance),
  file Form SSA-44 for a "life-changing event" redetermination.

## 13. Charitable Strategies for Concentrated Stock

### Charitable Remainder Trust (CRT)
- Transfer appreciated stock to CRT before sale. CRT sells stock tax-free (no capital gains
  inside the trust). Executive receives income stream for life or a term of years.
- Partial charitable deduction at contribution. Diversification without immediate capital gains.
- **Limitation**: CRT cannot hold S-Corp stock. Must be structured carefully to avoid §409A issues.

### Donor-Advised Fund (DAF)
- Contribute appreciated stock directly. Full FMV deduction (up to 30% AGI for appreciated
  capital gain property). No capital gains on the donated shares.
- Simple, immediate tax benefit. No ongoing trust administration.
- Stock must have been held >1 year for full FMV deduction.

## 14. Section 457A — Deferred Compensation from Foreign Entities

### Rule
IRC §457A requires that compensation deferred under a nonqualified deferred compensation plan
of a "nonqualified entity" (certain foreign corporations and partnerships) must be included in
income when there is no longer a substantial risk of forfeiture — regardless of when payment
is actually received.

### Nonqualified Entities
- Foreign corporations not subject to comprehensive US income tax (i.e., not effectively
  connected income and not subject to a comprehensive foreign income tax)
- Partnerships with foreign corporate partners meeting the same criteria
- Common examples: Cayman Islands hedge funds, offshore private equity fund vehicles,
  foreign-domiciled holding companies

### Key Provisions
- **20% additional tax**: Deferrals that violate §457A are subject to a 20% penalty tax
  (in addition to regular income tax) on the amount includible in income. §457A(c)(1).
- **Interest charge**: Premium interest accrues from the later of when the amount was first
  deferred or when it was no longer subject to a substantial risk of forfeiture. §457A(c)(2).
- **Carried interest impact**: Some hedge fund carried interest arrangements structured as
  deferred compensation from offshore fund vehicles fall squarely under §457A. The "carry"
  vests (risk of forfeiture lapses) and must be immediately included in income even if the
  fund has not yet distributed cash.

### Who This Affects
- Executives at foreign-domiciled companies (especially those incorporated in low-tax
  jurisdictions like Cayman Islands, BVI, Bermuda, Ireland)
- Hedge fund managers receiving carried interest from offshore fund structures
- Private equity professionals with deferred compensation from foreign fund entities
- US executives of foreign multinationals with nonqualified deferred comp plans funded
  by the foreign parent

### Planning Considerations
- Structure compensation to avoid §457A by ensuring the foreign entity IS subject to a
  comprehensive foreign income tax, or by using entities that are US tax-paying
- For hedge fund managers: structure carry as partnership allocations (not deferred
  compensation) to avoid §457A treatment — but this interacts with §1061 (carried interest
  3-year holding period)
- §457A overrides §409A where both could apply — §457A's acceleration rules take precedence

## 15. IRC Section 4960 — Excise Tax on Excess Compensation from Tax-Exempt Organizations

### Rule
IRC §4960 imposes a 21% excise tax on "remuneration" in excess of $1,000,000 paid by an
applicable tax-exempt organization to any of its five highest-compensated employees (the
"covered employees"). The excise tax also applies to "excess parachute payments" made by
tax-exempt organizations.

### Applicable Organizations
- 501(c)(3) organizations (hospitals, universities, charities)
- 501(c)(4), (c)(5), (c)(6), and other tax-exempt organizations
- State and local government entities that exclude income from tax (certain public universities,
  government hospitals)
- Related organizations under common control

### Key Provisions
- **$1M threshold**: All remuneration (salary, bonuses, deferred compensation distributions,
  equity-like incentive payments) counts toward the $1M limit. The threshold is NOT indexed
  for inflation.
- **Excess parachute payments**: Payments contingent on separation from employment that exceed
  3x the employee's base amount (similar to §280G for for-profit companies) are subject to
  the 21% excise tax. The "reasonable compensation" exception under §280G does NOT apply
  to §4960.
- **Who pays**: The organization (employer) pays the excise tax, NOT the individual executive.
  Reported on Form 4720.
- **Impact on compensation design**: Although the executive does not directly pay the tax, it
  affects total compensation package negotiations. The organization's cost of paying $1M+
  to a covered employee is effectively increased by 21%. This often leads to restructuring
  compensation packages to stay at or below $1M, or to justify the additional organizational
  cost.

### Common Scenarios
- Hospital system CEOs earning $2M+ (common at large academic medical centers)
- University presidents and athletic directors with total compensation exceeding $1M
- Nonprofit executive directors with performance bonuses pushing total comp over $1M
- Departing executives receiving severance packages that trigger excess parachute payment rules

## 16. SPAC Executive Compensation

### Overview
Special Purpose Acquisition Company (SPAC) transactions create complex tax situations for
executives involved as SPAC sponsors, target company officers, or post-merger executives.

### Founder Shares (Promote)
- SPAC sponsors typically receive "founder shares" (usually 20% of post-IPO equity) for a
  nominal investment ($25,000 for 20% of a $200M SPAC).
- **Tax characterization risk**: The IRS may treat founder shares as compensatory — meaning
  the difference between the nominal purchase price and the fair market value at vesting/
  de-SPAC closing is **ordinary income**, not capital gain.
- If treated as a capital asset purchase, gain on later sale would be capital gain (20% + 3.8%
  NIIT maximum vs. 37% + 3.8% for ordinary income).
- **Section 83 applies**: If founder shares are subject to vesting or transfer restrictions,
  §83(a) defers income recognition until vesting. An §83(b) election within 30 days of
  receipt can lock in the low value at grant — but if the SPAC liquidates without completing
  a deal, the election is wasted (no loss deduction for the forfeited shares beyond basis).

### Earnouts
- Post-merger earnout arrangements (additional shares or cash contingent on performance
  milestones) create §409A deferred compensation issues.
- If structured as contingent purchase price, the tax treatment follows installment sale rules.
- If structured as compensatory earnouts, they are ordinary income when received or vested.
- The distinction depends on whether the recipient is a continuing service provider (compensatory)
  or a selling shareholder (purchase price).

### Timing of Income Recognition
- **At de-SPAC closing**: If founder shares vest upon closing, §83(a) triggers ordinary income
  on the spread between basis and FMV.
- **Post-closing vesting**: If shares have post-closing vesting conditions (time-based or
  performance-based), income is deferred until vesting under §83(a) unless an §83(b) election
  was made.
- **Lock-up periods**: Lock-up restrictions alone generally do NOT constitute a "substantial
  risk of forfeiture" under §83 — income is recognized at vesting even if shares cannot be sold.

### Planning Considerations
- §83(b) election analysis is critical: compare the tax cost of electing at grant (low value,
  ordinary income) vs. deferring to vesting (higher value, ordinary income) vs. the risk of
  forfeiture if the SPAC fails
- Founder share promote structures should be documented to support capital asset treatment
  where possible — but the IRS position increasingly treats these as compensatory
- Coordinate with §280G analysis if the de-SPAC constitutes a "change in control"

## 17. Common Mistakes

1. **Not reconciling RSU 1099-B with W-2** — Double taxation is the most common executive tax error.
2. **Missing §409A deadlines** — Initial deferral elections, subsequent deferral modifications.
   20% penalty plus interest is devastating.
3. **Ignoring six-month delay** — Specified employee distributions within 6 months of separation
   trigger §409A penalties on the entire deferred compensation arrangement.
4. **Failing to model §280G before a deal closes** — The excise tax can consume 50%+ of the
   change-in-control payment. Model in advance and negotiate cutback or gross-up provisions.
5. **Exercising ISOs without AMT analysis** — Can trigger six-figure AMT surprise.
6. **Not using NUA when available** — Many executives roll employer stock into an IRA by
   default, missing significant LTCG rate savings.
7. **Ignoring IRMAA** — A single year of high income at age 63 can increase Medicare
   premiums by $5,000+/year for years.
8. **Accepting parachute gross-up without modeling** — Gross-ups are extremely expensive to the
   company and may trigger negative shareholder reactions. Sometimes cutback is better after tax.
