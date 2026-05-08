# Tax Preparation Intake Questionnaire — Universal Reference

> **Purpose:** This is the master reference for gathering all information needed to
> prepare a complete, optimized federal and state tax return. The AI agent uses this
> document to drive the interactive intake conversation.

> **For the agent:** Ask one category at a time. Use plain language. Explain briefly
> why each question matters (what deduction, credit, or filing decision it affects).
> Do not dump the entire questionnaire at once. Adapt follow-up questions based on
> prior answers — skip irrelevant sections. Summarize what you have collected after
> each major category before moving to the next.

---

## TABLE OF CONTENTS

1. [Prior Year Returns — PDF Intake Flow](#1-prior-year-returns--pdf-intake-flow)
2. [Filing Basics](#2-filing-basics)
3. [Personal Information](#3-personal-information)
4. [Income Sources](#4-income-sources)
5. [Deductions](#5-deductions)
6. [Credits and Life Situations](#6-credits-and-life-situations)
7. [Life Events](#7-life-events)
8. [Prior Year Context and Carryforwards](#8-prior-year-context-and-carryforwards)
9. [State-Specific Questions](#9-state-specific-questions)
10. [Routing Logic](#10-routing-logic)

---

## 1. PRIOR YEAR RETURNS — PDF INTAKE FLOW

**This section is critical for first-time users of this skill.** Multi-year return
analysis is the single highest-value activity — it finds CPA errors, missed deductions,
inconsistencies, and optimization opportunities that no single-year review can detect.

### Ask the User

> "Before we start on this year's return, I'd like to review your prior year returns.
> This is the most valuable thing I can do — comparing returns across years catches
> errors, missed deductions, and optimization opportunities that are invisible when
> looking at a single year in isolation.
>
> **Do you have PDF copies of your last 2-3 years of filed federal and state tax returns?**
> (e.g., 2022, 2023, 2024 returns — the full returns including all schedules and forms)"

### If the User Has PDF Returns

1. **Ask for file paths:** "Please share the file path(s) for each return. If you have
   them in a folder, just share the folder path and I'll find the PDFs."

2. **Process oldest first:** Read the returns sequentially, starting with the oldest year.
   This builds context chronologically — each subsequent year is analyzed with the
   prior year(s) as baseline.

3. **For each return, generate a structured analysis** covering:
   - Filing status, dependents, and AGI
   - All income sources with amounts (W-2, Schedule C, Schedule E, Schedule D, K-1s, etc.)
   - All deductions claimed (standard vs. itemized, above-the-line adjustments)
   - All credits claimed
   - Tax liability, effective tax rate, payments, and refund/balance due
   - Key elections made (depreciation methods, entity types, grouping elections)
   - Carryforward items identified (capital losses, NOLs, unused credits, passive losses)
   - Potential errors or missed opportunities flagged

4. **Read next year with prior analysis as context:** When processing the second return,
   reference the prior year analysis to identify:
   - Year-over-year income changes (and whether deductions/elections adapted)
   - Inconsistencies (e.g., rental property depreciation that doesn't match prior year)
   - Missing carryforwards (e.g., capital loss carryforward from prior year not appearing)
   - New income sources or life events not reflected in elections
   - Strategies that should have been implemented given prior year data

5. **Repeat for each subsequent year.** Each analysis builds on all prior analyses.

6. **Generate a multi-year summary** after all returns are processed:
   - Cross-year trend table (AGI, effective rate, key deductions, refund/owed)
   - Confirmed errors found (with specific line references)
   - Missed optimization opportunities (with estimated dollar impact)
   - Recommended amendments (if within the 3-year window)
   - Current-year strategy recommendations based on historical patterns

### If the User Does NOT Have PDF Returns

> "No problem. We can still prepare an excellent return. A few things that would help
> as substitutes:
> - Do you know your approximate AGI from last year?
> - Did you file federal and state? Which state(s)?
> - Did you itemize or take the standard deduction?
> - Do you have any carryforward items you're aware of (capital losses, passive losses, NOL)?
> - Did anything significant change from last year (income, marriage, home purchase, new business)?"

Proceed to Section 2.

---

## 2. FILING BASICS

Ask these first — they determine which subsequent questions matter.

### 2A. Filing Status

> "What is your filing status for this year?"

| Status | Criteria | Agent Follow-up |
|---|---|---|
| **Single** | Unmarried, no dependents qualifying for HOH | None needed |
| **Married Filing Jointly (MFJ)** | Legally married as of Dec 31, filing together | Ask about spouse income, withholding |
| **Married Filing Separately (MFS)** | Legally married, filing separate returns | Ask why — MFS loses many credits; may be strategic for PSLF, IBR, or liability protection |
| **Head of Household (HOH)** | Unmarried (or "considered unmarried"), paid >50% of household costs, qualifying person lived with you >6 months | Verify qualifying person, household expenses |
| **Qualifying Surviving Spouse (QSS)** | Spouse died in 2023 or 2024, dependent child, did not remarry | Verify year of death, dependent child |

**Agent note:** If the taxpayer says "married" but one spouse has student loans on
income-driven repayment or PSLF, explore MFS vs. MFJ trade-off. If they say
"single with kids," verify HOH eligibility (significantly better brackets and
standard deduction than Single).

### 2B. State of Residence

> "What state did you live in for the majority of 2025? Did you live in or earn
> income in any other states during the year?"

- Primary state determines which state return(s) to file
- Multi-state situations require allocation/apportionment
- Some cities have separate income tax (NYC, Yonkers, Detroit, Philadelphia, etc.)
- If the taxpayer moved states during the year, note the dates — part-year resident returns required

### 2C. Approximate Income Range

> "To help me focus on the most relevant strategies, roughly what was your total
> household income for 2025? A range is fine (e.g., $75K-$100K, $200K-$300K, $500K+)."

This determines:
- Which credits phase out (EITC, CTC, education credits, Saver's Credit)
- Whether AMT is a concern
- Whether NIIT and Additional Medicare apply
- Which QBI deduction limitations apply
- Which strategies have the highest expected value

---

## 3. PERSONAL INFORMATION

### 3A. Primary Taxpayer

- Full legal name (as it appears on Social Security card)
- Date of birth
- Social Security Number (SSN) or ITIN
- Occupation/profession
- Email address (for e-filing confirmation)
- Daytime phone number
- Mailing address (for paper correspondence)

**Agent note:** For Aiwyn integration, SSN must be formatted as a 9-digit string (no dashes).

### 3B. Spouse (if MFJ or MFS)

Same information as primary taxpayer, plus:
- Did your spouse work during 2025?
- Did your spouse have self-employment income?
- Does your spouse have a separate business or entity?

### 3C. Dependents

> "Do you have any dependents to claim on your return? This includes children,
> stepchildren, foster children, or other relatives you support."

**For each dependent, ask:**

| Question | Why It Matters |
|---|---|
| Full name | Required on return |
| Date of birth | Determines: Child Tax Credit (under 17), dependent care credit (under 13), AOTC eligibility (student), kiddie tax |
| SSN or ITIN | Required — no SSN means no CTC (ITIN dependents get $500 credit for other dependents) |
| Relationship to taxpayer | Determines qualifying child vs. qualifying relative test |
| Did they live with you all year? | CTC, EITC, HOH all require >6 months; if split custody, who has Form 8332? |
| Did they have income? | Qualifying child cannot be self-supporting; over $5,050 gross income for qualifying relative |
| Are they a student? | Full-time student under 24 gets more favorable rules; affects kiddie tax and AOTC |
| Are they disabled? | No age limit for qualifying child if permanently/totally disabled |
| Did they attend college? | AOTC or LLC eligibility; need 1098-T; which year of post-secondary? |
| Did anyone else claim them? | Verify no dual claiming; divorced/separated parents — custodial parent claims unless Form 8332 |

**Agent follow-up for divorced/separated parents:**
- Who is the custodial parent (child spent more nights with)?
- Has Form 8332 been signed releasing the exemption to the non-custodial parent?
- Which parent paid childcare expenses?
- Which parent claims the child for CTC, EITC, HOH, and dependent care credit?
  (Different credits have different rules — CTC can follow Form 8332; EITC and HOH always go to custodial parent.)

---

## 4. INCOME SOURCES

> "Let's go through your income for 2025. I'll ask about each type — just tell me
> if it applies to you."

### 4A. W-2 Employment Income

> "Did you or your spouse have W-2 employment income?"

**For each W-2:**

| Item | Where It Appears |
|---|---|
| Employer name and EIN | Box c, b |
| Wages, tips, other compensation | Box 1 |
| Federal income tax withheld | Box 2 |
| Social Security wages | Box 3 |
| Social Security tax withheld | Box 4 |
| Medicare wages | Box 5 |
| Medicare tax withheld | Box 6 |
| State wages and state tax withheld | Boxes 15-17 |
| Local wages and local tax withheld | Boxes 18-20 |
| Retirement plan participation (Box 13) | Checked if contributed to 401(k), 403(b), etc. |
| Box 12 codes | D=401(k), W=HSA, DD=health insurance cost, AA=Roth 401(k), etc. |
| Box 14 items | State disability, union dues, transit benefits, etc. |

**Follow-up questions for W-2 recipients:**
- Did you have multiple W-2 jobs? (Important for Social Security over-withholding, Additional Medicare tax)
- Did you receive stock options (ISOs or NSOs), RSUs, or ESPP shares?
  - **ISOs:** Was there an exercise in 2025? What was the spread? (AMT preference item.) Did you sell ISO shares?
  - **NSOs:** Exercise income appears in Box 1 of W-2. Was basis correctly reported on 1099-B for subsequent sales?
  - **RSUs:** Vesting income appears in Box 1 of W-2. Track cost basis = FMV at vesting for future sales.
  - **ESPP:** Purchase date, purchase price, FMV at purchase, sale details. Qualifying vs. disqualifying disposition.
- Did you receive any signing bonus, severance, or relocation assistance?
- Did your employer provide any fringe benefits (company car, housing, tuition assistance)?
- Did you contribute to a pre-tax retirement plan (401(k), 403(b), 457)?
  - How much did you contribute? (Check Box 12 codes)
  - Employer match amount?
  - Did you max out? Did you make catch-up contributions?
- Did you contribute to an HSA through payroll? (Box 12 code W)

### 4B. Self-Employment / Freelance Income

> "Did you do any freelance, consulting, or independent contractor work in 2025?"

**If yes:**

| Question | Why It Matters |
|---|---|
| What type of work? | Determines if SSTB for QBI; determines applicable industry deductions |
| Business name (if any) | Schedule C identification |
| EIN or SSN used for business | Required on Schedule C |
| Total revenue / 1099-NEC forms | Gross income reporting |
| Cash accounting or accrual? | Accounting method |
| Did you have a home office? | Section 280A deduction; address for principal place of business |
| Did you have expenses? | See Business Expenses section below |
| Did you make estimated tax payments? | Credits against tax owed; also helps determine if underpayment penalty applies |
| Did you use your vehicle for business? | Mileage log or actual expenses |
| Do you have any employees or contractors? | Impacts SEP/Solo 401(k) eligibility; Form 1099-NEC filing obligations |
| What was your approximate net profit? | Determines SE tax, QBI, retirement contribution limits |
| Is this an LLC? Sole proprietorship? | Entity classification; potential S-Corp election analysis |

### 4C. Business Ownership

> "Do you own a business (other than freelancing)? An LLC, S-Corp, C-Corp, or partnership?"

**For each entity:**

| Question | Why It Matters |
|---|---|
| Entity type (LLC, S-Corp, C-Corp, Partnership) | Determines which forms, SE tax treatment, QBI eligibility |
| Tax classification | LLC can be disregarded, partnership, S-Corp, or C-Corp for tax purposes |
| EIN | Required for entity returns |
| Industry/NAICS code | Schedule C code; determines if SSTB |
| Number of owners/members | Single-member LLC = Schedule C; multi-member = 1065 |
| Number of employees | Impacts retirement plan options, SEP contribution requirements |
| Gross revenue | Top line |
| Major expense categories | Cost of goods sold, payroll, rent, supplies, insurance, professional fees |
| Did you pay yourself a salary (S-Corp)? | Reasonable compensation analysis |
| K-1 received? | Partnership/S-Corp income flows to individual via K-1 |
| Date entity was established | New entity setup vs. ongoing; S-Corp election timing |
| Any ownership changes in 2025? | Mid-year changes affect allocation |

### 4D. Gig Economy / Platform Income

> "Did you earn income from any gig platforms (Uber, Lyft, DoorDash, Airbnb,
> Instacart, Etsy, eBay, Fiverr, Upwork, etc.)?"

**If yes:**
- Which platforms?
- Total income from each platform
- Did you receive 1099-K or 1099-NEC from the platform?
- What were your expenses? (Vehicle for rideshare, supplies for Etsy, etc.)
- Did you track mileage? (Critical for rideshare/delivery — often the largest deduction)

### 4E. Investment Income

> "Did you have any investment income — stocks, bonds, mutual funds, crypto,
> or other investments?"

**For each type:**

| Investment Type | Key Questions |
|---|---|
| **Brokerage accounts** | 1099-B for sales, 1099-DIV for dividends, 1099-INT for interest. Were there wash sales? |
| **Stocks sold** | Long-term vs. short-term? Basis reported to IRS? Any worthless securities? |
| **Mutual funds** | Capital gains distributions? Reinvested dividends? (Still taxable even if reinvested) |
| **Bonds** | Municipal bond interest (tax-exempt but may affect AMT)? Treasury interest (state-exempt)? OID? |
| **Cryptocurrency** | Sales, exchanges, payments? What was your cost basis method? Did you receive staking/mining income? Did you receive any airdrops? Were there any hard forks? |
| **Options trading** | Puts, calls, straddles? Section 1256 contracts (60/40 treatment)? |
| **Commodities** | Section 1256 mark-to-market? |
| **Private investments** | Angel investments, venture capital? QSBS (Section 1202) eligibility? |
| **Collectibles** | Art, antiques, coins, stamps? Taxed at 28% rate. |
| **Capital loss carryforward** | From prior years? What is the remaining amount? |

**Basis tracking follow-up:**
- Do you know your cost basis for assets sold?
- Does your brokerage report cost basis to the IRS (Box A/D on 1099-B)?
- If basis is NOT reported, do you have records (purchase confirmations, old statements)?
- For inherited assets: date of death, FMV at death (stepped-up basis)?
- For gifted assets: donor's basis and FMV at time of gift?

### 4F. Rental Property Income

> "Do you own any rental properties?"

**For each property:**

| Question | Why It Matters |
|---|---|
| Property address | Schedule E identification; state filing requirements |
| Type (residential, commercial, vacation, Airbnb) | Recovery period (27.5 vs. 39 years); short-term rental rules |
| Date acquired | First-year depreciation; applicable bonus depreciation rate |
| Purchase price and basis | Depreciation calculation; land vs. building allocation |
| Total rental income received | Schedule E Part I |
| Personal use days vs. rental days | Hobby loss rules if personal use >14 days AND >10% of rental days |
| Short-term rental (avg <7 days)? | May not be "rental activity" under Section 469; material participation changes analysis |
| Expenses: mortgage interest, taxes, insurance, repairs, management fees, utilities, HOA | Direct deductions against rental income |
| Were there vacancies? | Expected vs. actual rental days |
| Did you make improvements vs. repairs? | Capitalize vs. expense |
| Has a cost segregation study been done? | Accelerated depreciation opportunity |
| Do you actively participate in management? | $25,000 loss allowance; RE Professional status |
| How many hours did you spend on this property? | Material participation; RE Professional test |

**RE Professional follow-up (if applicable):**
- Do you or your spouse work in a real estate trade or business?
- Do you spend more than 750 hours per year in real property activities?
- Is more than 50% of your total work time in real property activities?
- Do you maintain an hour log?
- Have you elected to aggregate rental activities?

### 4G. Partnership / S-Corp Income (K-1)

> "Did you receive any K-1 forms from partnerships, S-Corps, or trusts/estates?"

**For each K-1:**

| Item | Box | Significance |
|---|---|---|
| Ordinary business income/loss | Box 1 (1065), Box 1 (1120-S) | Active or passive depending on material participation |
| Net rental income/loss | Box 2 (1065) | Usually passive |
| Guaranteed payments | Box 4 (1065) | Subject to SE tax |
| Interest, dividends, capital gains | Boxes 5-11 | Portfolio income category |
| Section 179 deduction | Box 12 (1065), Box 11 (1120-S) | Subject to individual Section 179 limits |
| Self-employment earnings | Box 14 (1065) | For SE tax calculation |
| Distributions received | Box 16/19 (1065), Box 16 (1120-S) | Not income if within basis; excess = capital gain |
| Basis and at-risk amounts | Not on K-1 — taxpayer must track | Loss deductions limited to basis and at-risk |

**Follow-up:**
- Do you materially participate in this business? (Determine passive vs. non-passive treatment)
- What is your current basis in the entity? (Loss deductions limited to basis)
- Were there any distributions in excess of basis?
- Any Section 754 step-up basis adjustments?
- Were there any debt changes (recourse vs. nonrecourse)?

### 4H. Retirement Income

> "Did you receive any retirement account distributions, Social Security benefits,
> or pension income in 2025?"

| Source | Key Questions |
|---|---|
| **401(k)/IRA distributions** | Amount? Was it a rollover? Was it a Roth conversion? Any early distribution (before 59.5)? Exception to 10% penalty (separation from service at 55+, SEPP/72(t), first home, medical, birth/adoption)? |
| **Roth conversions** | Amount converted? This is taxable income. Were there any recharacterizations? |
| **Social Security** | Total benefits received (SSA-1099)? Up to 85% may be taxable depending on provisional income. |
| **Pension/annuity** | 1099-R? Was there a cost basis in the plan (after-tax contributions)? Simplified Method for excluding basis. |
| **Required Minimum Distributions** | Were RMDs taken from all applicable accounts? Did any accounts miss RMDs? |
| **Inherited IRA distributions** | From whom? When did the original owner die? (Pre-2020 = stretch rules; post-2019 = 10-year rule) |

### 4I. Other Income Sources

> "Do any of these apply to you?"

| Source | Follow-up |
|---|---|
| **Alimony received** | From divorce agreement finalized before or after Dec 31, 2018? (Pre-2019 = taxable; post-2018 = not taxable) |
| **Gambling income** | W-2G received? Total winnings and losses? (Losses deductible only up to winnings, only if itemizing) |
| **Debt cancellation** | 1099-C received? Amount forgiven? Was it qualified principal residence debt, student loan, or insolvency? (Exclusions may apply) |
| **Foreign income** | Foreign earned income? Foreign bank accounts? (FBAR/FinCEN 114 if aggregate >$10K at any time; Form 8938 FATCA if above thresholds) |
| **State/local tax refund** | 1099-G? Only taxable if you itemized in the prior year and deducted state taxes |
| **Jury duty pay** | Small but reportable as other income |
| **Prize/award income** | Taxable unless assigned to charity |
| **Royalty income** | Oil/gas, intellectual property, mineral rights? (Schedule E Part I or Schedule C) |
| **Trust/estate income** | K-1 (Form 1041)? |
| **Rental of personal property** | Equipment rental, car rental, etc. |
| **Bartering income** | FMV of goods/services exchanged |
| **Hobby income** | If not a business, income is taxable but expenses are not deductible (post-TCJA) |
| **Unemployment compensation** | 1099-G; fully taxable |
| **Tip income** | Unreported tips must be included |
| **Digital asset income** | NFT sales, DeFi yield, liquidity pool rewards — all taxable events |

---

## 5. DEDUCTIONS

> "Now let's look at your deductions. I'll first determine whether itemizing or
> taking the standard deduction is better for you, then we'll make sure you capture
> every above-the-line deduction regardless."

### 5A. Above-the-Line Deductions (Available Regardless of Itemizing)

These reduce AGI — they benefit every taxpayer.

| Deduction | Questions |
|---|---|
| **Traditional IRA contributions** | Did you contribute? Are you/spouse covered by an employer plan? (Determines deductibility phase-out) |
| **HSA contributions** | Amount contributed? Self-only or family HDHP? Through payroll or individual? |
| **Self-employment tax (50%)** | Computed automatically from Schedule SE |
| **SEP/SIMPLE/Solo 401(k) contributions** | How much? When was the plan established? |
| **Student loan interest** | Amount paid? (Up to $2,500; check MAGI phase-out) |
| **Educator expenses** | K-12 educator? Amount spent on classroom supplies? (Up to $300) |
| **Alimony paid** | To whom? Under agreement finalized before Jan 1, 2019? |
| **Moving expenses** | Active-duty military only |
| **Health insurance premiums (SE)** | Self-employed? Premiums for self, spouse, dependents, children under 27 |
| **Penalty on early withdrawal of savings** | From bank CD or similar? |

### 5B. Housing

> "Do you own or rent your home?"

**If homeowner:**

| Question | Why It Matters |
|---|---|
| Mortgage balance(s) | Determine deductible interest limit ($750K/$1M) |
| Mortgage interest paid (Form 1098) | Schedule A deduction |
| Points paid (Form 1098, Box 6) | Deductible if for purchase; amortized if for refinance |
| Property taxes paid | SALT deduction (subject to cap) |
| PMI premiums | Check current-year deductibility status |
| Did you refinance in 2025? | Unamortized points from old loan deductible; new points amortized |
| Date mortgage originated | Pre-12/16/2017 = $1M limit; after = $750K limit |
| Is this your primary residence? | Must be qualified residence |
| Do you have a second home? | One second home qualifies for mortgage interest deduction |
| Did you sell your home? | Section 121 exclusion: $250K single, $500K MFJ; must have owned + lived in as primary 2 of last 5 years |
| Did you use any part for business? | Home office allocation; depreciation recapture on sale |

### 5C. Charitable Contributions

> "Did you make any charitable donations in 2025?"

| Type | Questions |
|---|---|
| **Cash donations** | To which organizations? Total amounts? Receipts for $250+ donations? |
| **Donated stock or securities** | Which securities? FMV and cost basis? Holding period? (Long-term appreciated = deduct FMV, no capital gains) |
| **Donor-Advised Fund (DAF)** | Contributions to DAF? Which sponsor? (Bunching strategy — contribute multiple years' worth in one year to exceed standard deduction) |
| **Qualified Charitable Distribution (QCD)** | Age 70.5+? IRA distributions sent directly to charity? (Excluded from income, counts toward RMD) |
| **Non-cash donations** | Clothing, household items, vehicles? FMV determination? Form 8283 if >$500; appraisal if >$5,000 |
| **Volunteer expenses** | Out-of-pocket expenses for volunteering? Mileage ($0.14/mile)? |
| **Conservation easement** | Donated development rights? Appraisal required. (Aggressive position — IRS heavily scrutinizes) |

### 5D. Medical Expenses

> "Did you have significant medical expenses not covered by insurance?"

- Total unreimbursed medical expenses (only amounts exceeding 7.5% of AGI are deductible)
- Insurance premiums paid with after-tax dollars (not pre-tax payroll deductions)
- Dental expenses, vision, prescriptions, medical equipment
- Long-term care insurance premiums (age-based limits)
- Transportation for medical care (mileage at $0.21/mile or actual costs)
- Did you have an HSA? How much did you contribute? Distributions for qualified expenses?

### 5E. Education Expenses

> "Did you or your dependents have education-related expenses?"

| Item | Questions |
|---|---|
| **Tuition and fees** | 1098-T received? Which institution? Undergraduate or graduate? Year of study? |
| **Student loan interest** | 1098-E? Total interest paid? |
| **529 plan** | Contributions (state deduction in some states)? Distributions (tax-free if for qualified expenses)? |
| **Coverdell ESA** | Contributions? Distributions? |
| **Employer tuition assistance** | Up to $5,250 excluded from income |
| **Scholarship/fellowship income** | Amount? Excess over qualified expenses is taxable |

**Credit determination:**
- AOTC (first 4 years, $2,500 max, partially refundable) vs. LLC ($2,000 max, non-refundable)
- Cannot claim both for the same student
- Cannot claim credit for expenses paid with 529 distributions

### 5F. Childcare and Dependent Care

> "Did you pay for childcare or dependent care to enable you (and your spouse) to work?"

| Question | Why It Matters |
|---|---|
| Childcare provider name and address | Required on Form 2441 |
| Provider's SSN or EIN | Required on Form 2441 |
| Amount paid per child | Up to $3,000 (1 child) or $6,000 (2+ children) for credit |
| Child's age | Must be under 13 |
| Dependent Care FSA | Did employer FSA cover any? (Reduces eligible expenses for credit) |
| Day camp (qualifies) vs. overnight camp (does not) | Only day camp expenses qualify |
| Before/after school programs | Qualify if for care (not tuition) |

### 5G. Retirement Contributions

> "What retirement contributions did you make in 2025?"

| Plan | Key Questions |
|---|---|
| **401(k) / 403(b) / 457** | Amount? Roth or traditional? (Already reflected in W-2 Box 12) |
| **Traditional IRA** | Amount? Deductible? (Depends on employer plan coverage and income) |
| **Roth IRA** | Amount? Income within limits? Backdoor Roth? |
| **SEP-IRA** | Amount? (Up to 25%/20% of compensation, max $70,000) |
| **Solo 401(k)** | Employee and employer portions? When was the plan adopted, and what contribution type is being claimed? |
| **SIMPLE IRA** | Amount? Employer match? |
| **Defined benefit plan** | Actuarial contribution amount? |

### 5H. Business Expenses (Schedule C / Business Returns)

> "Let's detail your business expenses."

| Category | Examples | Documentation Needed |
|---|---|---|
| **Office/workspace** | Rent, coworking space, home office | Lease, home office calculation |
| **Supplies and materials** | Office supplies, shipping, raw materials | Receipts |
| **Equipment** | Computers, furniture, tools (Section 179 or depreciation) | Purchase records |
| **Software and subscriptions** | SaaS tools, cloud services, professional subscriptions | Statements |
| **Professional services** | Accountant, lawyer, bookkeeper, consultant | Invoices |
| **Insurance** | Business insurance, E&O, general liability | Statements |
| **Advertising and marketing** | Ads, website, business cards, SEO | Receipts, platform reports |
| **Travel** | Airfare, hotels, ground transport for business purposes | Receipts with business purpose documented |
| **Meals** | Business meals with clients/colleagues (50% deductible) | Receipts with who/what/why documented |
| **Vehicle** | Business mileage ($0.70/mile) or actual expenses | Mileage log with dates, destinations, purpose |
| **Phone and internet** | Business-use percentage of personal plans | Monthly statements |
| **Continuing education** | Courses, conferences, certifications related to current business | Receipts |
| **Bank and merchant fees** | Payment processing, bank charges | Statements |
| **Licenses and permits** | Business license, professional license renewals | Receipts |
| **Cost of goods sold** | Inventory, materials for products sold | Inventory records |
| **Contractor payments** | 1099-NEC issued to subcontractors | 1099 records |
| **Depreciation** | Prior year assets still being depreciated | Prior returns, Form 4562 |

---

## 6. CREDITS AND LIFE SITUATIONS

> "Let's check if you qualify for any tax credits."

### 6A. Child and Family Credits

| Credit | Trigger Question |
|---|---|
| **Child Tax Credit** | Do you have children under 17 with SSNs? |
| **Child and Dependent Care Credit** | Did you pay for childcare to work? |
| **Adoption Credit** | Did you adopt a child or have adoption expenses in 2025? |
| **Earned Income Tax Credit (EITC)** | Income below thresholds? (Often overlooked by moderate-income families) |

### 6B. Education Credits

| Credit | Trigger Question |
|---|---|
| **American Opportunity Tax Credit** | Student in first 4 years of college? |
| **Lifetime Learning Credit** | Any post-secondary education or job-skill courses? |
| **Student loan interest deduction** | Paid student loan interest? |

### 6C. Energy and Vehicle Credits

| Credit | Trigger Question |
|---|---|
| **Energy Efficient Home Improvement (25C)** | Install heat pump, insulation, windows, doors in primary residence? |
| **Residential Clean Energy (25D)** | Install solar panels, battery storage, geothermal, wind? |
| **Clean Vehicle Credit (30D)** | Purchase or lease a new EV/PHEV? |
| **Used Clean Vehicle Credit (25E)** | Purchase a used EV from a dealer? |

### 6D. Other Credits

| Credit | Trigger Question |
|---|---|
| **Foreign Tax Credit** | Pay taxes to a foreign country? Foreign income? |
| **Saver's Credit** | Lower income and contributed to retirement plan? |
| **Premium Tax Credit** | Health insurance through the Marketplace? |
| **Residential Energy Credit (carryforward)** | Unused credit from prior year? |
| **General Business Credit** | Small business — R&D, disabled access, employer-provided childcare? |

---

## 7. LIFE EVENTS

> "Did any major life events happen in 2025? These often have significant tax implications."

### Comprehensive Life Events Checklist

| Life Event | Tax Implications | Follow-up Questions |
|---|---|---|
| **Got married** | Filing status change; may create marriage penalty or bonus; review withholding | Wedding date? Will you file MFJ or MFS? Spouse income? |
| **Got divorced/separated** | Filing status change; alimony; property division; dependency allocation | Final decree date? Alimony terms? Who claims children? |
| **Had a baby** | New dependent; CTC; childcare credit; FSA changes | Birth date? SSN obtained? Childcare planned? |
| **Adopted a child** | Adoption credit (up to ~$17,000); new dependent | Domestic or international? Special needs? Total expenses? |
| **Child turned 17** | Lost CTC ($2,200); may still qualify as dependent | Still a dependent? Student? |
| **Child turned 13** | Lost childcare credit eligibility | Other care expenses? |
| **Child started college** | AOTC; 529 distributions; scholarship income | Which year? Full-time? 1098-T? |
| **Child graduated/no longer dependent** | Lost dependent; lost credits; may change filing status | Still under 24 and student? Income? |
| **Bought a home** | Mortgage interest deduction; property tax; points deduction | Purchase date? Price? Mortgage amount? Points paid? First-time buyer? |
| **Sold a home** | Section 121 exclusion ($250K/$500K); depreciation recapture if home office | Sale price? Basis? Improvements made? Ownership and use test met? |
| **Moved to a new state** | Part-year resident returns; allocation rules; moving expense deduction (military only) | From/to states? Move date? Reason? |
| **Started a business** | Schedule C; entity election; SE tax; retirement plans; home office | Entity type? EIN? Start date? |
| **Closed a business** | Final returns; asset disposition; loss recognition | Reason? Remaining assets? Suspended losses? |
| **Changed jobs** | Multiple W-2s; 401(k) rollover; stock vesting; severance; moving | Gap in employment? Retirement plan rollover? |
| **Lost a job** | Unemployment income; COBRA; job search expenses; severance | Duration? Unemployment received? |
| **Retired** | Pension/IRA distributions; Social Security; Medicare; RMD planning | Full or partial? Which accounts will you draw from? |
| **Spouse died** | Filing status change (QSS for 2 years); stepped-up basis; estate | Date of death? Jointly owned assets? Estate filed? |
| **Parent/other family member died** | Inheritance; stepped-up basis; estate/trust K-1 | Inherited assets? Trust distributions? |
| **Received an inheritance** | Stepped-up basis; inherited IRA (10-year rule); estate tax considerations | What was inherited? FMV at death? |
| **Made a large gift** | Gift tax return (Form 709) if >$19,000/recipient | Total gifts? To whom? Using lifetime exemption? |
| **Became disabled** | ABLE accounts; disability income; medical deductions | SSDI? Employer disability insurance? |
| **Experienced a disaster** | Casualty loss deduction (federally declared); special extensions | FEMA declaration? Insurance recovery? |
| **Sued or received legal settlement** | Taxability depends on nature (physical injury = excluded; punitive = taxable; lost wages = taxable) | Nature of settlement? Attorney fees? |
| **Received stock options** | ISO exercise = AMT preference; NSO exercise = ordinary income | Type? Exercise date? FMV and strike price? |
| **Converted entity type** | S-Corp election; partnership conversion; different tax treatment | From/to? Effective date? |
| **Bought/sold rental property** | Depreciation start/recapture; 1031 exchange; passive loss rules | Date? Price? Was 1031 exchange used? |
| **Did a 1031 exchange** | Deferred gain; strict 45-day identification / 180-day closing rules | Relinquished and replacement properties? Qualified intermediary used? |
| **Received forgiven debt** | 1099-C income (unless insolvency, bankruptcy, qualified residence, or student loan exclusion applies) | Amount? Type of debt? Solvent or insolvent at time? |
| **Started collecting Social Security** | Up to 85% taxable depending on provisional income | Which month? Benefits amount? |
| **Turned 65** | Medicare; additional standard deduction; HSA rules change | Medicare enrollment? HSA contribution proration if mid-year? |
| **Turned 73 or 75** | RMD begins (73 if born 1951-1959; 75 if born 1960+) | Which accounts? Calculated RMD amount? |

---

## 8. PRIOR YEAR CONTEXT AND CARRYFORWARDS

> "Let me ask about some items from prior years that may carry into 2025."

| Carryforward Item | Questions |
|---|---|
| **Capital loss carryforward** | Amount remaining? Short-term or long-term? (Check prior year Schedule D) |
| **Net operating loss (NOL)** | Post-2017 NOLs limited to 80% of taxable income; no carryback (with exceptions) |
| **Passive activity loss carryforward** | From which activities? Amounts? (Check prior year Form 8582) |
| **Charitable contribution carryforward** | Excess contributions from prior years? (5-year carryforward) |
| **Foreign tax credit carryforward** | Unused credits? (10-year carryforward, 1-year carryback) |
| **General business credit carryforward** | Unused credits from prior years? |
| **AMT credit carryforward** | From prior year AMT paid? |
| **Section 179 carryover** | Excess Section 179 from prior year? |
| **Installment sale payments** | Receiving payments on a prior year sale? (Form 6252) |
| **Depreciation schedules** | Assets still being depreciated from prior years |
| **Suspended losses (at-risk, basis)** | Losses limited by basis or at-risk in prior years that may be freed this year |
| **Prior year overpayment applied** | Did you apply part of last year's refund to this year's estimated tax? |
| **Estimated tax payments made** | Amounts and dates of quarterly payments for 2025 |
| **Extension payment** | Payment made with Form 4868? |

---

## 9. STATE-SPECIFIC QUESTIONS

> "Based on your state of residence, I need a few additional details."

### General State Questions (All States with Income Tax)

- Total state income tax withheld from all W-2s and 1099s
- Estimated state tax payments made during 2025
- State tax refund received from prior year (1099-G) — was it taxable federally?
- Any state-specific credits or deductions (property tax credits, renter's credits, etc.)

### High-Impact State-Specific Topics

| State Situation | Questions |
|---|---|
| **High-tax state (CA, NY, NJ, CT, etc.)** | SALT cap impact? PTET election available? Timing of state payments (Dec prepay)? |
| **No income tax state (TX, FL, WA, NV, WY, SD, AK, TN, NH)** | Sales tax deduction election? (May exceed income tax in these states) |
| **Multi-state income** | Income allocation method? Reciprocity agreements? Credits for taxes paid to other states? |
| **State moved during year** | Part-year resident returns? Income allocation by period? |
| **Remote work in different state from employer** | Convenience of employer rules (NY, NJ, CT, etc.)? Employer withholding in correct state? |
| **City income tax** | NYC, Yonkers, Detroit, Philadelphia, Columbus, etc.? |
| **PTET (Pass-Through Entity Tax) election** | Did the entity elect PTET? Which state(s)? Amount paid? Credit on individual return? |

---

## 10. ROUTING LOGIC

After completing the intake, use the following logic to determine which reference
files and strategy modules to load.

### Based on Income Sources

| If the taxpayer has... | Load reference... |
|---|---|
| Self-employment income | `strategies/ENTITY-OPTIMIZATION.md`, `strategies/SE-TAX-REDUCTION.md` |
| Rental properties | `strategies/RENTAL-PROPERTY.md`, `strategies/RE-PROFESSIONAL.md` |
| Capital gains/losses | `strategies/CAPITAL-GAINS.md` |
| Stock options (ISO/NSO/RSU/ESPP) | `strategies/EQUITY-COMPENSATION.md` |
| K-1 income | `strategies/PASS-THROUGH-INCOME.md` |
| Foreign income | `strategies/FOREIGN-INCOME.md` |
| High income ($500K+) | `strategies/HIGH-INCOME.md`, `strategies/AMT-PLANNING.md` |

### Based on Filing Status

| If the taxpayer is... | Load reference... |
|---|---|
| MFS | `situations/MFS-ANALYSIS.md` (when is MFS actually beneficial?) |
| HOH | `situations/HOH-VERIFICATION.md` (common audit trigger) |
| QSS | `situations/QSS-RULES.md` |
| Newly married | `life-events/MARRIAGE.md` |
| Newly divorced | `life-events/DIVORCE.md` |

### Based on Profession

| If the taxpayer works in... | Load reference... |
|---|---|
| Medicine (physician, dentist, nurse) | `professions/MEDICAL.md` |
| Law | `professions/LEGAL.md` |
| Technology (engineer, developer) | `professions/TECH.md` |
| Real estate | `professions/REAL-ESTATE.md` |
| Creative (artist, musician, writer) | `professions/CREATIVE.md` |
| Finance (trader, advisor, banker) | `professions/FINANCE.md` |
| Gig economy | `professions/GIG-ECONOMY.md` |
| Military | `professions/MILITARY.md` |

### Based on Life Events

| If the taxpayer experienced... | Load reference... |
|---|---|
| Home purchase | `life-events/HOME-PURCHASE.md` |
| Home sale | `life-events/HOME-SALE.md` |
| Business start | `life-events/BUSINESS-START.md` |
| Retirement | `life-events/RETIREMENT.md` |
| Death of spouse/family | `life-events/DEATH-AND-INHERITANCE.md` |
| Divorce | `life-events/DIVORCE.md` |
| Major medical event | `life-events/MEDICAL-EVENT.md` |
| Disaster loss | `life-events/DISASTER-LOSS.md` |

### Based on State

| State characteristic | Load reference... |
|---|---|
| Any income tax state | `states/{STATE-ABBREV}.md` |
| PTET-eligible | `strategies/PTET.md` |
| Community property state (CA, AZ, NV, NM, TX, WA, WI, ID, LA) | `situations/COMMUNITY-PROPERTY.md` |

**Note:** Not all referenced files may exist yet. The routing logic serves as the
master plan for which files SHOULD be created and loaded. When a referenced file
does not exist, the agent should note this and apply general knowledge for that
topic area.

---

## APPENDIX: INTAKE SUMMARY TEMPLATE

After completing the intake, produce a summary in this format before proceeding
to analysis and preparation:

```
## INTAKE SUMMARY — [Taxpayer Name] — Tax Year 2025

### Filing Profile
- Status: [Single/MFJ/MFS/HOH/QSS]
- State: [Primary state, additional states]
- Dependents: [Count, names, ages]
- Approximate AGI: [$X]

### Income Sources
- [ ] W-2 employment: [Employer(s), approximate amounts]
- [ ] Self-employment: [Business type, approximate net]
- [ ] Rental income: [# properties, approximate net]
- [ ] Investment income: [Types, approximate amounts]
- [ ] K-1 income: [Entity names, types]
- [ ] Retirement income: [Types, amounts]
- [ ] Other: [Describe]

### Key Deductions Identified
- [ ] Standard or Itemized (estimated: $X)
- [ ] [List significant deductions]

### Credits to Evaluate
- [ ] [List applicable credits]

### Life Events
- [ ] [List any 2025 life events]

### Carryforwards
- [ ] [List any carryforward items]

### Prior Year Returns Reviewed
- [ ] [Years reviewed, key findings]

### Reference Files to Load
- [ ] [List based on routing logic]

### Red Flags / Items Requiring Verification
- [ ] [List any concerns or items needing documentation]
```

---

*This questionnaire is designed to be comprehensive. Not every question applies to
every taxpayer. The agent should use professional judgment to skip irrelevant
sections and drill deeper on relevant ones.*
