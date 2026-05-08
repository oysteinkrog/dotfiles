# Cognitive Operators for Tax Analysis

Composable "thinking moves" for systematic tax savings discovery. Each operator is a lens through which to examine every dollar of income, deduction, credit, and timing decision. Apply operators individually or chain them (see Strategy-Chain) for compounding effects.

---

## $ Stack-Decompose

**Definition:** "What is the full tax on this dollar?" Decompose the marginal tax burden on a single dollar of income through every layer of the tax stack. Most taxpayers and even many preparers think only of the federal bracket. The stack reveals the true marginal rate, which is often 15-25 percentage points higher than the headline federal rate.

**When to Use:**
- Evaluating whether a deduction is worth pursuing (compare deduction value against full stack rate)
- Comparing two income sources that hit different layers (W-2 vs. 1099 vs. rental vs. capital gain)
- Modeling the value of a retirement contribution (the saved rate is the full stack, not just federal)
- Deciding between Roth and traditional contributions
- Pricing freelance work (must cover the full stack to net the target)

**The Generic Tax Stack:**

```
Layer                        Typical Range       Applies To
─────────────────────────────────────────────────────────────────────
Federal ordinary rate        10% - 37%           All ordinary income
State income tax             0% - 13.3%          Varies by state (9 states have 0%)
City/local income tax        0% - 3.876%         NYC, some PA/OH/MD cities, others
Self-employment tax          15.3% (first $176,100 for 2025)
                             2.9% above           SE income only
Additional Medicare (0.9%)   0.9%                Wages + SE > $200K (S) / $250K (MFJ)
Net Investment Income Tax    3.8%                Investment income if MAGI > thresholds
Alternative Minimum Tax      26% / 28%           If AMT exceeds regular tax
State AMT                    Varies               CA, CT, CO, IA, MN, WI have state AMT
FICA (employer side)         7.65%               W-2 (economic cost even if employer pays)
─────────────────────────────────────────────────────────────────────
```

**Stack Example -- Self-employed individual, high earner, living in a high-tax state:**

```
$1.00 of Schedule C net income at margin:
  Federal 35%                                    $0.350
  State 9.3%                                     $0.093
  City 0%                                        $0.000
  SE tax (employer-equivalent 7.65%)             $0.076
  SE tax (employee-equivalent 7.65%)             $0.076
  Deductible half SE adjustment                 -$0.027  (saves federal + state on half)
  Additional Medicare 0.9%                       $0.009
  ─────────────────────────────────────────────
  TOTAL MARGINAL RATE                            ~57.7%
  NET RETAINED                                   ~$0.423
```

**Stack Example -- Same dollar as long-term capital gain:**

```
$1.00 of LTCG:
  Federal 20%                                    $0.200
  State 9.3%                                     $0.093
  NIIT 3.8%                                      $0.038
  ─────────────────────────────────────────────
  TOTAL MARGINAL RATE                            ~33.1%
  NET RETAINED                                   ~$0.669
```

The difference (57.7% vs. 33.1%) is the arbitrage gap that other operators exploit.

**Failure Modes:**
- Forgetting the state layer (especially for remote workers in high-tax states)
- Ignoring SE tax on Schedule C income (the biggest hidden cost for freelancers)
- Not accounting for phase-outs that create phantom rates (e.g., SALT cap interaction, QBI phase-out, child tax credit phase-out, EITC cliffs)
- Using the average rate instead of the marginal rate
- Ignoring the AMT crossover point where deductions lose value

**Prompt Module:**
> "Build the full tax stack for [INCOME_TYPE] income at [TAXPAYER_MARGINAL_BRACKET]. Include federal, [STATE], [CITY IF APPLICABLE], SE tax if applicable, Additional Medicare, NIIT, and any phase-out phantom rates. Show the net retained per dollar."

---

## ⟳ Entity-Arbitrage

**Definition:** "What entity should hold this income?" Evaluate whether income or assets should flow through a sole proprietorship (Schedule C), single-member LLC (disregarded), multi-member LLC, S-Corporation, or C-Corporation to minimize the total tax stack.

**When to Use:**
- Net Schedule C income exceeds ~$60,000 (S-Corp election may save SE tax)
- Business has significant retained earnings potential (C-Corp 21% flat rate)
- Multiple family members could be employed (income splitting)
- Liability protection is needed alongside tax planning
- Qualified Business Income (QBI) deduction optimization
- State-level pass-through entity tax (PTET) elections available

**Decision Matrix:**

```
Factor              Schedule C    LLC (DE)     S-Corp        C-Corp
────────────────────────────────────────────────────────────────────────
SE tax              Full 15.3%    Full 15.3%   On salary     None (but
                                  (disregarded) only          double tax)
QBI deduction       Yes (20%)     Yes (20%)    Yes (20%)     No
                                                on distrib.
Salary flexibility  N/A           N/A          Must be       Full
                                               "reasonable"   flexibility
Retained earnings   Taxed to      Taxed to     Taxed to      21% flat
                    owner         owner        owner         (until distrib.)
Health insurance    SE deduction  SE deduction  >2% S/H       Corp deduction
                                               SE deduction
Retirement plans    SEP/Solo 401k SEP/Solo 401k All types     All types
                                               (W-2 based)   (W-2 based)
State PTET          No            Maybe        Yes (most     No (not
                                  (check state) states)       pass-through)
Payroll cost        None          None         ~$500-2K/yr   ~$500-2K/yr
Complexity          Low           Low-Med      Medium        High
Audit risk          Higher        Higher       Lower for     Lowest for
                                               reasonable    small corps
                                               salary
────────────────────────────────────────────────────────────────────────
```

**S-Corp Breakeven Analysis:**
The S-Corp saves SE tax on distributions but adds payroll costs, payroll tax compliance, and reduces SEP-IRA contribution basis. The breakeven typically occurs around $50K-$80K net income, depending on state.

Formula: `SE_tax_saved = (Net_income - Reasonable_salary) x 15.3%` (up to SS wage base)
Minus: `Payroll_costs + Additional_compliance + Lost_SEP_basis_value`

**Failure Modes:**
- Setting S-Corp salary too low (IRS scrutinizes; must be "reasonable" for role/industry)
- Ignoring state-level entity taxes (CA $800 minimum franchise tax, NYC UBT, etc.)
- Not considering QBI impact (S-Corp salary reduces QBI; distributions are QBI)
- Forgetting that S-Corp election is irrevocable for 5 years (without IRS consent)
- C-Corp double taxation trap (21% + dividend rate on distributions)

**Prompt Module:**
> "Given [NET_BUSINESS_INCOME] of Schedule C income in [STATE], compare the total tax under: (1) sole proprietorship, (2) S-Corp with reasonable salary of [SALARY_AMOUNT], (3) C-Corp. Include SE tax, QBI deduction, state entity taxes, and payroll compliance costs. What is the annual savings of the optimal structure?"

---

## ⌂ Space-Split

**Definition:** "What percentage of this space is business use?" Determine the correct allocation of shared spaces (home office, vehicle, equipment) between business and personal use to maximize deductions while maintaining audit defensibility.

**When to Use:**
- Taxpayer works from home (any amount)
- Vehicle used for both business and personal
- Equipment (computer, phone, internet) used for both purposes
- Rental property with partial personal use
- Mixed-use property (e.g., Airbnb with personal use days)

**Allocation Methods:**

### Home Office

| Method | Calculation | Pros | Cons |
|--------|-------------|------|------|
| **Simplified** | $5/sq ft, max 300 sq ft = $1,500 | Easy, low audit risk | Capped at $1,500; no depreciation |
| **Regular -- Square Footage** | (Office sq ft / Total sq ft) x Expenses | Most common | Requires measurement |
| **Regular -- Room Count** | (Office rooms / Total rooms) x Expenses | Simple for equal rooms | Unfair if rooms differ in size |
| **Regular -- Time** | Hours of business use / Total hours available | For shared spaces | Harder to document |

**Expenses Allocable (Regular Method):**
- Direct expenses: 100% to office (paint the office, office-only repairs)
- Indirect expenses: Pro-rata (mortgage interest, rent, utilities, insurance, repairs, depreciation)
- Unrelated expenses: 0% (landscaping for non-visible areas, pool maintenance)

**Key Rules:**
- Regular and exclusive use required (no dual-purpose rooms) -- Exception: daycare, storage, rental
- Must be principal place of business OR place where taxpayer meets clients
- Home office depreciation is mandatory (not optional) under regular method -- recaptured on sale at 25% rate
- Gross income limitation: home office deduction cannot create a loss (excess carries forward)

### Vehicle

| Method | Calculation | Key Requirements |
|--------|-------------|-----------------|
| **Standard Mileage** | [IRS_RATE]/mile x Business miles | Must use from first year placed in service; log required |
| **Actual Expense** | (Business miles / Total miles) x Actual costs + depreciation | Receipts for all expenses; depreciation recapture |

**Mileage Log Requirements:**
- Date of trip
- Destination and business purpose
- Starting and ending odometer (or trip miles)
- Total miles for the year (business + personal + commute)

### Mixed-Use Rental Property

```
Personal use days: Days used by owner or family (or rented below FMV)
Rental use days: Days rented at FMV
Total use days: Personal + Rental

If personal use > greater of (14 days or 10% of rental days):
  -> Property is "personal residence" -- rental expenses limited to rental income
  -> Mortgage interest and taxes still deductible on Schedule A

If personal use <= 14 days AND property rented >= 1 day:
  -> Full rental property treatment on Schedule E

If rented < 15 days total:
  -> Income is tax-free (not reported)
  -> No rental expenses deductible (but mortgage interest/taxes still on Sch A)
```

**Failure Modes:**
- Claiming 100% business use on anything shared (immediate audit flag)
- Round percentages (exactly 50%, 25%) without measurement documentation
- No contemporaneous mileage log (reconstructed logs are weak in audit)
- Forgetting recapture on home office depreciation when selling the home
- Mixed-use rental miscounting personal use days (maintenance days may count as personal)

**Prompt Module:**
> "Calculate the home office deduction for a [TOTAL_SQ_FT] sq ft home with a [OFFICE_SQ_FT] sq ft dedicated office. The taxpayer pays [RENT_OR_MORTGAGE] in rent/mortgage interest, [UTILITIES] in utilities, [INSURANCE] in insurance, and [REPAIRS] in home repairs. Compare simplified vs. regular method. What documentation is needed?"

---

## ↻ Carryforward-Harvest

**Definition:** "What is sitting unused from prior years?" Inventory all tax attributes that carry forward from prior years and determine whether current-year planning can unlock their use before they expire.

**When to Use:**
- Every year during Phase 1 (prior year return review)
- Income spike year (opportunity to absorb accumulated losses)
- Business generating losses (track for future use)
- Capital losses exceeding the $3,000 annual limit
- NOL carryforwards from prior businesses
- Charitable contributions exceeding AGI limits

**Carryforward Inventory Template:**

```
Attribute                    Carryforward Period    Annual Limit           Where to Find
──────────────────────────────────────────────────────────────────────────────────────────────
Net Operating Loss (NOL)     Indefinite (post-2017) 80% of taxable income  Form 1045, Sch C
                             20 years (pre-2018)    No limit (pre-2018)
Capital loss carryforward    Indefinite             $3,000/yr deduction    Schedule D, line 21
                                                    (unlimited vs. gains)
Passive activity losses      Until disposition       Net passive income     Form 8582
  - Rental real estate       of activity             only (or $25K active
  - Other passive                                    participation)
Charitable contributions     5 years                 60% AGI (cash)         Schedule A
                                                    30% AGI (LTCG prop.)
Home office carryforward     Indefinite             Gross income limit     Form 8829
Business credit carryforward 20 years forward       Tax liability limit    Form 3800
                             1 year back
AMT credit carryforward      Indefinite             Regular tax - TMT      Form 8801
Foreign tax credit           10 years forward       Per-country/overall    Form 1116
                             1 year back            limitation
Section 179 carryforward     Indefinite             Business income limit  Form 4562
Qualified business loss      Indefinite             Becomes NOL            Form 461
(excess business loss)
Investment interest expense  Indefinite             Net investment income  Form 4952
At-risk loss carryforward    Indefinite             At-risk amount         Form 6198
Suspended partnership losses Indefinite             Basis, at-risk,        Schedule K-1, Form
                                                    passive limits         8582
Student loan interest        No carryforward        $2,500/yr             1098-E
(use-it-or-lose-it)
──────────────────────────────────────────────────────────────────────────────────────────────
```

**Harvesting Strategies:**
1. **Capital gain recognition:** If capital loss carryforward exists, consider recognizing gains to absorb it (tax-free gain up to loss amount)
2. **Passive activity disposition:** Selling a passive activity releases all suspended losses
3. **Real estate professional status:** If qualified (750 hours + material participation), rental losses become non-passive
4. **NOL planning:** In high-income years, NOLs automatically offset 80% of income
5. **Charitable bunching:** If prior year carryforwards exist, moderate current year giving to stay within limits
6. **AMT credit recovery:** File Form 8801 every year AMT credit exists; refundable in some cases

**Failure Modes:**
- Not reviewing prior year returns for existing carryforwards
- Letting carryforwards expire (especially business credits -- 20 year limit)
- Misapplying passive loss rules (material participation tests)
- Forgetting that suspended losses release on taxable disposition (not gift)
- Not filing Form 8801 when AMT credit carryforward exists

**Prompt Module:**
> "Review [PRIOR_YEAR_RETURN] for carryforward attributes. Check: Schedule D line 21 (capital loss), Form 8582 (passive losses), Form 8829 (home office), Form 3800 (business credits), Form 8801 (AMT credit), Form 1116 (foreign tax credit), and any NOL worksheets. List all carryforwards with amounts, remaining periods, and current-year strategies to harvest them."

---

## Depreciation-Accelerate

**Definition:** "Can I reclassify this asset to recover its cost faster?" Evaluate every depreciable asset for acceleration opportunities that move tax deductions from the future into the present.

**When to Use:**
- Any asset purchase exceeding $2,500 (de minimis threshold)
- Purchase or construction of commercial/rental real property
- Vehicle purchase for business use
- Equipment, furniture, technology purchases
- Building improvements and renovations
- Year of high income (maximize current deductions)

**Acceleration Stack (apply in order):**

```
Priority  Method                 Limit                    Asset Types           Recovery
────────────────────────────────────────────────────────────────────────────────────────────
1         De Minimis Safe Harbor  $2,500/item (no AFS)    Any tangible property  100% Year 1
                                 $5,000/item (with AFS)
2         Section 179 Expense    $1,220,000 (2024)        Tangible personal      100% Year 1
                                 phases out at $3,050,000  property, some
                                 of total purchases       real property,
                                                          software, vehicles*
3         Bonus Depreciation     Declining:               Most tangible          Year 1
                                 60% (2024), 40% (2025)   property, used         (declining %)
                                 20% (2026), 0% (2027+)   property OK,
                                                          not real property
4         MACRS Accelerated      N/A                      All depreciable        Per class life
          (200% DB, 150% DB)                              property
5         Cost Segregation       Study cost: $5K-$15K     Real property          Reclassify to
          Study                                           (building components)  5/7/15 year
────────────────────────────────────────────────────────────────────────────────────────────
```

**Key Asset Class Lives:**

| Property Type | MACRS Life | Method |
|--------------|-----------|--------|
| Computers, peripherals | 5 years | 200% DB |
| Office furniture | 7 years | 200% DB |
| Appliances (rental) | 5 years | 200% DB |
| Vehicles (autos) | 5 years | 200% DB (luxury limits apply) |
| Land improvements | 15 years | 150% DB |
| Residential rental | 27.5 years | Straight-line |
| Commercial real property | 39 years | Straight-line |
| Qualified Improvement Property | 15 years | Straight-line (bonus eligible) |

**Cost Segregation Deep Dive:**
A cost segregation study reclassifies components of a building from 27.5/39-year property to shorter-lived categories:

- **5-year property:** Carpeting, appliances, certain electrical, specialty lighting, decorative millwork
- **7-year property:** Furniture, fixtures, certain equipment
- **15-year property:** Land improvements (parking lots, landscaping, sidewalks, fencing)
- **Land (non-depreciable):** Sometimes components allocated to building are actually land

Rule of thumb: Cost seg studies are worthwhile when building cost basis exceeds ~$500,000. Typical reclassification: 15-40% of building cost to shorter lives.

**Vehicle Special Rules:**

```
Luxury auto limits (2024):
  Year 1: $12,400 (or $20,400 with bonus depreciation)
  Year 2: $19,800
  Year 3: $11,900
  Year 4+: $7,160

SUV/Truck > 6,000 lbs GVWR:
  Section 179: up to $28,900 (2024)
  Bonus depreciation: remaining basis
  No luxury auto limits (but SUV 179 cap applies)

Vehicle > 14,000 lbs GVWR:
  Full Section 179 / bonus depreciation, no limits
```

**Failure Modes:**
- Deducting land (land is never depreciable)
- Forgetting the business-use percentage (only business % is depreciable)
- Listed property rules: if business use drops below 50%, must recapture excess depreciation
- Not making the de minimis safe harbor election on the tax return
- Bonus depreciation on real property (generally not eligible; QIP is the exception)
- Taking Section 179 when there is no business income to offset (creates no benefit, carries forward)

**Prompt Module:**
> "Analyze the depreciation strategy for [ASSET_DESCRIPTION] with a cost basis of [COST], placed in service on [DATE], used [BUSINESS_USE_%] for business. Apply the acceleration stack: (1) de minimis safe harbor, (2) Section 179, (3) bonus depreciation at current rate, (4) MACRS. What is the first-year deduction under each scenario? Which maximizes current-year benefit?"

---

## Deadline-Gate

**Definition:** "What irreversible deadline is approaching?" Identify time-sensitive elections, filing deadlines, and planning windows that, once missed, cannot be recovered. Some gates cost thousands if missed by a single day.

**When to Use:**
- At the start of every engagement (scan for approaching gates)
- Quarterly during proactive planning
- Before any major financial transaction
- When a life event occurs (marriage, business formation, home purchase)

**Critical Gates List:**

| Deadline | Date | What Happens If Missed | Recovery |
|----------|------|----------------------|----------|
| **S-Corp Election (Form 2553)** | March 15 (for calendar year) | Cannot be S-Corp for current year | Late election relief possible within 3 years 75 days with reasonable cause |
| **Solo 401(k) Adoption / Contribution Timing** | Verify live | Wrong assumptions can destroy elective-deferral or employer-contribution planning | Check entity type and current IRS rules before routing to SEP-IRA |
| **SEP-IRA Contribution** | Filing deadline + extensions | No contribution for that year | File extension to get more time |
| **Traditional/Roth IRA Contribution** | April 15 (no extension) | Lose the year's contribution room forever | None -- permanently lost |
| **HSA Contribution** | April 15 (no extension) | Lose the year's contribution room | None -- permanently lost |
| **Q4 Estimated Tax Payment** | January 15 | Underpayment penalty | File return by Jan 31 and pay in full |
| **PTET Election** | Varies by state (often March 15 or earlier) | Cannot use PTET to bypass SALT cap | Some states allow late elections |
| **1031 Exchange -- ID Period** | 45 days from sale | Exchange fails; gain is taxable | None -- absolutely hard deadline |
| **1031 Exchange -- Completion** | 180 days from sale | Exchange fails | None |
| **Roth Conversion** | December 31 | Cannot convert for that tax year | None -- cannot be done in arrears |
| **Tax-Loss Harvesting** | December 31 (settle by) | Losses not available for current year | Must account for T+1 settlement |
| **Quarterly Estimated Taxes** | Apr 15, Jun 15, Sep 15, Jan 15 | Underpayment penalty accrues | Pay ASAP to stop penalty accrual |
| **Gift Tax Annual Exclusion** | December 31 | Cannot make gifts for that year | None |
| **Charitable Contributions** | December 31 | Not deductible for current year | Carryforward from prior years still available |
| **FSA Spending** | March 15 (grace) or Dec 31 | Forfeited | $610 rollover if plan allows |
| **Backdoor Roth (pro-rata cleanup)** | December 31 | Pro-rata rule applies to conversion | Roll traditional IRA to 401(k) before year-end |
| **Augusta Rule (14-day rental)** | Must be planned in advance | IRS scrutiny if not documented | None retroactively |
| **R&D Credit (Form 6765)** | With timely filed return (+ ext) | Credit lost for that year | Amended return within 3 years |
| **Estimated tax safe harbor** | Ongoing throughout year | 110% prior year or 90% current year | Annualized income method may help |

**Failure Modes:**
- Assuming extensions extend payment deadlines (they do not -- only filing deadlines)
- Confusing "filing deadline" with "contribution deadline" (IRA = April 15, no extensions; SEP = filing + extensions)
- Missing state deadlines that differ from federal
- Not calendaring 1031 exchange identification and completion periods
- Assuming PTET elections can be made at tax filing time (most states require advance election)

**Prompt Module:**
> "It is currently [CURRENT_DATE]. The taxpayer is filing as [FILING_STATUS] in [STATE]. Scan for all irreversible deadlines within the next 90 days. Flag any that have already passed for the current tax year. List each gate with its date, consequence of missing, and recommended action."

---

## Income-Shift

**Definition:** "Can this income be recognized at a better time or by a better taxpayer?" Evaluate opportunities to shift income across tax years (timing) or across family members/entities (splitting) to minimize the aggregate tax.

**When to Use:**
- Income will be significantly higher or lower next year
- Approaching retirement (lower brackets ahead)
- Starting a business (loss years ahead)
- Children or spouse in lower brackets
- Selling a business or large asset
- Year of unusually high capital gains

**Timing Strategies:**

### Deferral (Push Income Forward)
- **Installment sales (Section 453):** Spread gain over payment years; cannot use for publicly traded securities or dealer property
- **Like-kind exchanges (Section 1031):** Defer gain on real property exchanges indefinitely
- **Opportunity Zone investment (Section 1400Z):** Defer and potentially exclude capital gains
- **Deferred compensation (Section 409A):** Employers can structure deferred comp arrangements
- **Retirement contributions:** 401(k), SEP-IRA, defined benefit plans
- **Cash method timing:** Delay invoicing/billing to January (for cash-basis taxpayers)
- **Charitable remainder trust:** Defer and spread recognition of gain on appreciated assets

### Acceleration (Pull Income Forward)
- **Roth conversion in low-income year:** Convert traditional IRA at low brackets
- **Recognize capital gains to absorb losses:** Use carryforward losses to offset accelerated gains
- **Accelerate income before rate increases:** If tax rates expected to rise
- **Exercise ISOs in low-AMT year:** AMT spread is smaller
- **Harvest gains before moving to high-tax state**

### Splitting (Shift Between Taxpayers)
- **Employ family members:** Reasonable wages to children (under 18: no FICA if sole proprietorship) or spouse
- **Family limited partnerships:** Shift income to lower-bracket family members (gift tax and valuation rules apply)
- **Kiddie tax awareness:** Unearned income of children under 19 (or under 24 if full-time student) taxed at parents' rate above $2,500 (2024)
- **Trust income distribution:** Distribute trust income to lower-bracket beneficiaries
- **Gift appreciated assets:** Donee takes donor's basis; sell in donee's lower bracket (but kiddie tax)
- **Spousal IRA:** Non-working spouse can contribute based on working spouse's income

**Key Constraints:**
- Constructive receipt doctrine: Cannot refuse to accept income already available
- Assignment of income doctrine: Cannot assign earned income to another person
- Economic substance doctrine: Transaction must have purpose beyond tax avoidance
- Wash sale rule: Cannot recognize loss and repurchase substantially identical security within 30 days
- Related party rules (Section 267): Losses between related parties are disallowed

**Failure Modes:**
- Violating constructive receipt (the check was available in December even if not cashed until January)
- Assignment of income on personal services (cannot shift W-2 or 1099 income to a child)
- Wash sale on loss harvesting (especially across accounts including IRAs)
- Kiddie tax surprise on gifted assets sold by children
- Section 1031 used for personal property (only real property post-TCJA)

**Prompt Module:**
> "The taxpayer expects [CURRENT_YEAR_INCOME] this year and [NEXT_YEAR_INCOME] next year. They are [FILING_STATUS] in [STATE]. Evaluate: (1) timing shifts to equalize income across years, (2) Roth conversion opportunity if low-income, (3) capital gain/loss harvesting, (4) income splitting with family members in [LOWER_BRACKET_SITUATIONS]. What is the total tax savings from optimal timing?"

---

## Audit-Shield

**Definition:** "How would this look to an IRS examiner?" Score every position on the return for audit risk and ensure documentation meets or exceeds the substantiation requirements. The goal is not to avoid aggressive positions -- it is to ensure that every position taken is defensible and documented.

**When to Use:**
- Before finalizing any return
- When a deduction is large relative to income
- When a position relies on a judgment call (reasonable salary, FMV, business purpose)
- When the same deduction appears on multiple returns (e.g., home office year after year)
- When DIF score risk factors are present

**Risk Scoring Matrix:**

| Risk Factor | Score (1-5) | Description |
|------------|-------------|-------------|
| **Schedule C loss** | 4 | Especially 3+ consecutive years, hobby loss risk |
| **Home office deduction** | 3 | Common audit target; must be exclusive use |
| **Large charitable deductions** | 3-5 | >3% of AGI gets attention; >20% high risk |
| **Rental losses with high income** | 3 | Passive loss rules are complex; REP status contested |
| **Cash business, no records** | 5 | Automatic high-risk; IRS assumes unreported income |
| **High mileage, no log** | 4 | Most common disallowed deduction in audit |
| **Round numbers throughout** | 3 | Suggests estimation rather than actual records |
| **Large meal/entertainment** | 3 | Receipts + business purpose for each |
| **Crypto transactions** | 2-4 | IRS is increasing enforcement; basis tracking critical |
| **Employee vs. contractor** | 4 | Worker classification disputes are aggressive IRS targets |
| **Offshore accounts (FBAR)** | 5 | Willful non-filing penalties are severe |
| **ERC claims** | 5 | IRS moratorium on processing; heavy audit risk |

**Documentation Standards by Deduction:**

```
Position                     Required Documentation
─────────────────────────────────────────────────────────────────────
Home office                  Floor plan with measurements, photos,
                             dated at start of use
Vehicle (mileage)            Contemporaneous log: date, destination,
                             business purpose, miles
Charitable (cash)            Bank statement or receipt for any amount;
                             written acknowledgment > $250
Charitable (non-cash > $500) Form 8283; qualified appraisal > $5,000
Business meals               Receipt + notation: who, business topic
Travel                       Receipts + business purpose; combined
                             business/personal must allocate
Medical expenses             Receipts; insurance EOBs; must exceed
                             7.5% AGI floor
Casualty loss                Photos, police report, insurance claim,
                             appraisals (before/after)
Foreign tax credit           Foreign tax returns or statements; Form 1116
                             calculations
─────────────────────────────────────────────────────────────────────
```

**Substantial Authority Standard:**
- **Reasonable basis (20%):** Minimum for avoiding negligence penalty
- **Substantial authority (40%):** Avoids substantial understatement penalty; no disclosure needed
- **More likely than not (>50%):** Required for tax shelters and certain positions
- **Disclosure (Form 8275):** Filing Form 8275 reduces penalty standard to reasonable basis

**Failure Modes:**
- Assuming small returns are never audited (correspondence audits are automated)
- Over-documentation anxiety leading to abandoned deductions (the position may be correct)
- Not keeping records the required period (generally 3 years, but 6 years if >25% omission, indefinite if fraud)
- Relying on "everyone does it" instead of substantive authority
- Not disclosing uncertain positions when appropriate

**Prompt Module:**
> "Score the following return positions for audit risk on a 1-5 scale: [LIST_OF_POSITIONS]. For each position scoring 3+, specify: (1) the IRS examination technique for this issue, (2) required documentation, (3) the legal authority supporting the position, and (4) whether Form 8275 disclosure is advisable."

---

## Strategy-Chain

**Definition:** "What other strategies does this unlock or conflict with?" Tax strategies rarely exist in isolation. A single decision (e.g., electing S-Corp status) cascades through retirement contributions, QBI deductions, self-employment tax, health insurance deductions, and more. Map the chain before executing any strategy.

**When to Use:**
- Before implementing any strategy from the other operators
- When multiple strategies are being considered simultaneously
- When a change in one area unexpectedly affects another
- During Phase 3 optimization to maximize compounding effects

**Key Strategy Chains:**

### Chain 1: S-Corp Election Cascade
```
S-Corp Election
  -> Reduces SE tax on distributions
  -> BUT reduces QBI (salary is not QBI; distributions are)
  -> AND changes retirement contribution basis (W-2 only, not full SE income)
  -> AND requires reasonable salary (payroll costs)
  -> AND enables PTET election (SALT cap workaround)
  -> AND changes health insurance deduction pathway (>2% S/H rule)
  -> AND eliminates Solo 401(k) employee mega-backdoor option in some cases
```

### Chain 2: Real Estate Professional + Cost Seg
```
Real Estate Professional Status
  -> Rental losses become non-passive
  -> UNLOCKS cost segregation benefit (accelerated losses are usable immediately)
  -> UNLOCKS bonus depreciation on reclassified components
  -> Can create large current-year loss against W-2/business income
  -> BUT requires 750 hours + material participation (documentation intensive)
  -> AND may trigger AMT if losses are large
  -> AND recapture on sale at ordinary rates for Section 1250 property
```

### Chain 3: Backdoor Roth
```
Backdoor Roth Conversion
  -> Requires zero traditional IRA balance at year-end (pro-rata rule)
  -> CONFLICTS with SEP-IRA (is a traditional IRA)
  -> Solution: roll SEP to Solo 401(k) or employer 401(k) before year-end
  -> AND must do conversion in same year as contribution (or next year)
  -> ENABLES tax-free growth on up to $7,000/year (2024)
  -> CHAINS with mega-backdoor Roth if Solo 401(k) has after-tax provision
```

### Chain 4: Charitable Bunching + DAF
```
Donor Advised Fund (DAF) Contribution
  -> Bunches multiple years of giving into one year
  -> Exceeds standard deduction in bunching year -> itemize
  -> ENABLES donating appreciated stock (avoid LTCG + get full FMV deduction)
  -> CHAINS with QCD (Qualified Charitable Distribution) in off-years for 70.5+
  -> Off-years: take standard deduction
  -> Net effect: same charitable giving, but with tax benefit
```

### Chain 5: Health Insurance + HSA + SE
```
Self-employed Health Insurance
  -> SE health insurance deduction (line 17, above the line)
  -> If HDHP: HSA eligible
  -> HSA: triple tax benefit (deduction + tax-free growth + tax-free medical withdrawal)
  -> HSA: $4,150 single / $8,300 family (2024) + $1,000 catch-up if 55+
  -> CONFLICTS with Medicare enrollment (no HSA contribution after Medicare Part A)
  -> CONFLICTS with FSA (general purpose FSA disqualifies HSA; limited-purpose OK)
  -> CHAINS with: early retirement bridge (ACA subsidy optimization)
```

**Conflict Map:**

```
Strategy A                  CONFLICTS WITH              Resolution
──────────────────────────────────────────────────────────────────────────
SEP-IRA                     Backdoor Roth               Roll SEP to 401(k)
S-Corp election             Solo 401(k) mega-backdoor   Evaluate net benefit
HSA contributions           Medicare Part A              Stop HSA before Medicare
Standard deduction          Itemizing                   Charitable bunching / DAF
Passive loss deduction      Material participation      Cannot be both passive and active
AMT preference items        Regular tax deductions      Model both systems
SALT deduction ($10K cap)   PTET election               PTET may bypass cap
Installment sale            Depreciation recapture      Recapture taxed in year of sale
                                                        regardless of installment
──────────────────────────────────────────────────────────────────────────
```

**Failure Modes:**
- Implementing one strategy without modeling downstream effects
- Assuming strategies are independent (they almost never are)
- Not modeling the AMT impact of combined strategies
- Optimizing federal without checking state interaction
- Not revisiting chains annually (law changes break chains)

**Prompt Module:**
> "The taxpayer is considering implementing [STRATEGY_LIST]. For each strategy, map: (1) what it unlocks, (2) what it conflicts with, (3) prerequisites, (4) the net combined effect of all strategies together (not just individually). Flag any conflicts and propose resolutions. Model the total tax savings of the optimal chain vs. the sum of individual strategy savings."

---

## 💰 Credit-Optimize

**Definition:** "What credits am I leaving on the table?" Systematically scan for all available tax credits at both the federal and state level. Credits reduce tax dollar-for-dollar, making them categorically more valuable than deductions of the same amount. Some credits are refundable (paid even if tax liability is zero), amplifying their value further.

**When to Use:**
- Every return, without exception — credits are the highest-value items on a return
- When AGI changes significantly (phase-outs shift; credits may appear or disappear)
- When life events change eligibility (child born, education enrollment, home solar install, EV purchase)
- When a business is started or expanded (R&D, General Business Credit)
- When foreign income is present (Foreign Tax Credit vs. deduction election)
- When ACA marketplace insurance is used (Premium Tax Credit reconciliation)

**Credit Scan Checklist:**

```
Credit                          Max Amount        Refundable?     Key Phase-Out (MFJ)        Form
───────────────────────────────────────────────────────────────────────────────────────────────────────
Child Tax Credit (CTC)          $2,000/child      Partially       $400,000 MAGI              Sch 8812
                                                  ($1,700 ACTC)
Child & Dependent Care Credit   $3,000 (1) /      No              No phase-out; reduced       Form 2441
                                $6,000 (2+)                       percentage above $43K AGI
Earned Income Tax Credit        $7,830 (3+ kids)  Yes             $63,398 (3+ kids, MFJ)     Sch EIC
American Opportunity Credit     $2,500/student    Partially       $160,000-$180,000 MAGI     Form 8863
(AOTC)                                           (40% = $1,000)
Lifetime Learning Credit        $2,000/return     No              $160,000-$180,000 MAGI     Form 8863
Saver's Credit                  $1,000/$2,000     No              $73,000 MFJ (2024)         Form 8880
Residential Clean Energy Credit 30% of cost       No              No phase-out               Form 5695
EV Credit (New)                 $7,500            Yes (2024+)     $300,000 MAGI (MFJ)        Form 8936
EV Credit (Used)                $4,000            Yes (2024+)     $150,000 MAGI (MFJ)        Form 8936
R&D Credit (Section 41)         Varies            No (but payroll No phase-out               Form 6765
                                                  tax offset for
                                                  small biz)
General Business Credit         Varies            No              Tax liability limitation    Form 3800
Adoption Credit                 $16,810 (2024)    No              $252,150-$292,150 MAGI     Form 8839
Foreign Tax Credit              Taxes paid/       No              Per-basket limitation       Form 1116
                                accrued
Premium Tax Credit (PTC)        Varies            Yes             Based on household income   Form 8962
                                                                  vs. FPL
───────────────────────────────────────────────────────────────────────────────────────────────────────
```

**Key Insight:** Credits reduce tax dollar-for-dollar, making them higher-value than deductions. A $2,000 credit saves exactly $2,000 in tax; a $2,000 deduction at a 35% marginal rate saves only $700. Refundable credits (EITC, ACTC, PTC, EV credits post-2024) can produce a refund even when tax liability is zero.

**Analysis Protocol:**
1. For each credit in the checklist, determine eligibility based on the taxpayer's facts
2. Compute the tentative credit amount
3. Check phase-out: is the taxpayer's MAGI in the phase-out range? Compute the reduced amount
4. Determine refundable vs. nonrefundable treatment — nonrefundable credits are limited to tax liability
5. Check for state-level equivalents (many states mirror federal credits or offer unique ones)
6. Order credits strategically: nonrefundable credits should be applied before refundable credits to maximize the refundable portion received

**Failure Modes:**
- Missing credits because income phase-outs were not checked (taxpayer may have just entered or left a phase-out range)
- Not claiming the refundable portion of partially refundable credits (e.g., claiming CTC but not computing ACTC on Schedule 8812)
- Not checking state-level credits that mirror federal (state EITC, state child credit, state EV credit, state solar credit)
- Choosing to deduct foreign taxes instead of crediting them when the credit is more valuable
- Not reconciling Premium Tax Credit (Form 8962) when advance payments were received — this creates a balance due or additional refund
- Missing the R&D credit for small businesses that can apply it against payroll tax (up to $500,000/year for qualified small businesses)
- Failing to coordinate education credits (cannot claim AOTC and LLC for the same student; AOTC is almost always better if eligible)

**Prompt Module:**
> "For each federal and state credit, verify: (1) Do I qualify based on filing status, AGI, and specific eligibility rules? (2) What is the computed credit amount? (3) Am I in a phase-out range, and if so, what is the reduced amount? (4) Is there a refundable component, and have I claimed it? (5) Are there state equivalents in [STATE] that I should also claim?"

---

## 🏦 Retirement-Optimize

**Definition:** "Am I maximizing tax-deferred shelter?" Compare all available retirement vehicles to determine the optimal contribution strategy. The right split between Traditional (pre-tax) and Roth (after-tax) contributions depends on the taxpayer's current marginal rate vs. expected retirement marginal rate — a distinct analysis from entity arbitrage.

**When to Use:**
- Every return — retirement contributions are the single largest legal tax shelter for most taxpayers
- When income increases significantly (higher marginal rate increases the value of Traditional contributions)
- When self-employment begins (SEP-IRA, Solo 401(k), and Defined Benefit plans become available)
- When employer changes (new 401(k) plan may have different features, match, mega-backdoor availability)
- When approaching age milestones (50 = catch-up contributions; 59.5 = penalty-free withdrawals; 73 = RMDs)
- When deciding between Roth conversion and continued deferral

**Retirement Vehicle Comparison:**

```
Vehicle                     2024 Limit           Tax Treatment        Eligibility                  Key Nuance
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
Traditional 401(k)/403(b)  $23,000 (+$7,500     Deductible now,      Employer plan required        Reduces current AGI;
                           catch-up if 50+)      taxed on withdrawal                               subject to RMDs at 73
Roth 401(k)/403(b)         $23,000 (+$7,500     After-tax now,       Employer plan required        No income limit; no
                           catch-up if 50+)      tax-free withdrawal  (no income limit)            RMDs after SECURE 2.0
Traditional IRA            $7,000 (+$1,000      Deductible if no     Anyone with earned income;    Deductibility phases out
                           catch-up if 50+)      employer plan or     deduction phases out with    if covered by employer
                                                 below income limit   employer plan                plan + high income
Roth IRA                   $7,000 (+$1,000      After-tax now,       MAGI < $230K MFJ /           Direct contribution
                           catch-up if 50+)      tax-free withdrawal  $146K single (2024)          barred above limit
Backdoor Roth IRA          $7,000               After-tax ->         Anyone (if no pre-tax         Pro-rata rule: must have
                                                 tax-free (via        IRA balances)                $0 pre-tax IRA balance
                                                 conversion)                                       at year-end
Mega Backdoor Roth         Up to $46,000        After-tax 401(k) ->  Employer plan must allow      Check plan documents;
                           (total 401k limit     Roth (in-plan or     after-tax contributions +    not all plans offer this
                           minus EE + ER)        in-service rollover) in-service distribution
SEP-IRA                    25% of comp, up to   Deductible now,      Self-employed or employer     Employer must contribute
                           $69,000              taxed on withdrawal   (all eligible employees)     same % for all employees
SIMPLE IRA                 $16,000 (+$3,500     Deductible now,      Employers with <=100          2-year waiting period
                           catch-up if 50+)      taxed on withdrawal  employees                    for rollover to other plans
Solo 401(k)                $23,000 EE +         EE: Traditional or   Self-employed with no         Can include Roth EE +
                           up to 25% ER =       Roth; ER: Traditional common-law employees         after-tax for mega backdoor
                           $69,000 total                             (spouse OK)
Defined Benefit Plan /     Up to ~$275,000/yr   Deductible now,      Self-employed or employer;    Actuary required; best for
Cash Balance Plan          (actuarially          taxed on withdrawal  requires annual funding       high-income age 45+ with
                           determined)                                commitment                   stable income
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
```

**Key Insight:** The optimal split between Traditional and Roth depends on comparing the current marginal tax rate (the rate saved by a Traditional contribution) against the expected marginal rate in retirement (the rate paid on withdrawals). If the current rate is higher, Traditional wins. If the expected retirement rate is higher (young high-growth earner, large taxable accounts, expected tax rate increases), Roth wins. This is a separate analysis from entity arbitrage, though the two interact (S-Corp salary is the basis for 401(k) contributions).

**Decision Framework:**

```
Current marginal rate vs. expected retirement rate:
  Current >> Retirement  ->  Maximize Traditional (defer at high rate, withdraw at low rate)
  Current << Retirement  ->  Maximize Roth (pay tax now at low rate, withdraw tax-free)
  Current ≈ Retirement   ->  Diversify (hedge with both)

Special cases:
  Very high income now    ->  Max Traditional 401(k) + Backdoor Roth IRA + consider DB plan
  Self-employed, high     ->  Solo 401(k) + Defined Benefit Plan can shelter $200K-$300K+/yr
  Young, low income now   ->  Roth everything (low current rate + decades of tax-free growth)
  Near retirement         ->  Traditional contributions + Roth conversion ladder planning
```

**Failure Modes:**
- Not considering the Defined Benefit / Cash Balance plan option for high-income self-employed (can shelter $200,000-$300,000+ per year — often the single most valuable planning tool, yet rarely suggested)
- Failing to execute Backdoor Roth due to pro-rata rule confusion (the fix: roll all pre-tax IRA balances to a 401(k) before year-end, then the conversion is tax-free)
- Missing the Mega Backdoor Roth via after-tax 401(k) contributions (requires plan to allow after-tax contributions AND in-service Roth rollovers — check the plan document)
- Ignoring the interaction between S-Corp salary and retirement contribution basis (lower salary = lower 401(k) employee deferral limit basis, but also lower SE tax)
- Not coordinating SEP-IRA with Backdoor Roth (SEP is a traditional IRA — triggers pro-rata rule; solution: use Solo 401(k) instead of SEP)
- Contributing to a Traditional IRA when the deduction is phased out (non-deductible traditional IRA has the worst tax treatment — pay tax twice unless converted to Roth)
- Forgetting catch-up contributions for taxpayers 50+ ($7,500 extra in 401(k), $1,000 extra in IRA)
- Not modeling RMD impact: large Traditional balances force taxable withdrawals starting at 73, potentially pushing into higher brackets and triggering Medicare surcharges (IRMAA)

**Prompt Module:**
> "For each retirement vehicle available to this taxpayer: (1) Am I eligible given my employment status, income, and existing plans? (2) What is the maximum contribution allowed? (3) What is the tax treatment — deductible, Roth, or after-tax? (4) What is my current marginal rate vs. my expected marginal rate in retirement? (5) Is there an employer match, and am I capturing all of it? (6) For self-employed taxpayers: have I evaluated a Defined Benefit or Cash Balance plan in addition to a Solo 401(k) or SEP-IRA?"
