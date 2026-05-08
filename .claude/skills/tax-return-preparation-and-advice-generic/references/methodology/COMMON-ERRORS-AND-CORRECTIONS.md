# Common Errors and Corrections

Hard-won lessons from actual tax preparation practice. These errors were discovered through multi-model cross-validation (Claude, GPT/Codex, Gemini) catching each other's mistakes during real return preparation. Every entry below cost or nearly cost real dollars.

Format: Error Pattern | Why It Happens | Correct Rule | How To Verify | Dollar Impact

---

## Mortgage Interest Errors

### Servicer Transfer Creates Multiple 1098s

**Error Pattern:** Claiming mortgage interest from only ONE Form 1098 when the loan was transferred between servicers mid-year.

**Why It Happens:** When a mortgage is transferred (e.g., SoFi to Select Portfolio Servicing), each servicer issues a separate 1098 for their servicing period. The first servicer's 1098 may show only 1-2 months of interest. Preparers see "mortgage interest" on one 1098 and move on, never looking for a second.

**Correct Rule:** Sum ALL 1098s from ALL servicers for the same loan. Each 1098 covers only its servicing period. The total across all 1098s should approximate the full year's interest.

**How To Verify:**
- Ask the taxpayer: "Was your mortgage transferred or sold to a different company this year?"
- Count the number of 1098s received. If fewer than expected, contact the prior servicer.
- Reconstruct monthly interest: principal balance x annual rate / 12. At 6.125% on $905K, monthly interest is approximately $4,620. If a 1098 shows $4,620, that is ONE month, not the full year.
- Cross-reference against monthly mortgage statements or online account history.

**Dollar Impact:** Missing 10 months of mortgage interest at $4,620/month = $46,200 in missed deductions. At 32% marginal rate = $14,784 in excess tax.

---

### Prepaid Interest at Closing Is a Third Source

**Error Pattern:** Omitting prepaid interest from the closing disclosure when claiming mortgage interest deductions.

**Why It Happens:** Prepaid interest (from closing date to end of that month) appears on the closing disclosure/settlement statement (HUD-1 or TRID Closing Disclosure). This amount appears on NO Form 1098 because the loan has not yet been reported to the IRS by the servicer for that stub period. It falls through the cracks.

**Correct Rule:** When a mortgage originates or refinances mid-month, the borrower pays prepaid interest from the closing date through the end of that month. This interest is fully deductible in the year paid. Source: IRS Publication 936.

**How To Verify:**
- Request the closing disclosure from the closing year.
- Look at Section G (Prepaid Items) or the equivalent section for "Prepaid Interest."
- Add this amount to the 1098 total for the year.

**Dollar Impact:** Typically $500-5,000 depending on loan size and closing date. A closing on the 1st of a month produces nearly a full month of prepaid interest.

---

### Points Deduction in Purchase Year

**Error Pattern:** Deducting points in full on a refinance, or failing to deduct points at all on a purchase.

**Why It Happens:** Confusion between purchase and refinance rules.

**Correct Rule (IRS Pub 936):**
- **Purchase:** Points are fully deductible in the year paid IF all conditions are met: (1) primary residence acquisition, (2) points are customary for the area, (3) computed as a percentage of the loan, (4) stated on the closing disclosure, (5) paid from buyer's funds (not seller-paid unless seller-paid points are allocated to the buyer), (6) loan is secured by the home.
- **Refinance:** Points must be amortized over the life of the loan. Exception: if you refinance again, the remaining unamortized points from the old loan become deductible in that year.

**How To Verify:**
- Check closing disclosure for points paid.
- Confirm the transaction type (purchase vs. refinance).
- For refinance amortization: total points / loan term in months = annual deductible amount.

**Dollar Impact:** On a $905K loan with 1 point ($9,050), incorrectly amortizing a purchase deduction costs $9,050 in year-1 deductions minus the amortized fraction. At 32% rate = approximately $2,700 in year-1 tax difference.

---

## Self-Employment Tax Errors

### SEP-IRA Contribution Rate: 20% Not 25%

**Error Pattern:** Contributing 25% of net self-employment income to a SEP-IRA.

**Why It Happens:** The 25% rate is widely cited and is correct for W-2 employees of corporations. For self-employed individuals (Schedule C filers), the formula requires a "circular" adjustment because the contribution itself reduces the compensation base.

**Correct Rule:** The effective rate for self-employed individuals is:
```
Plan rate / (1 + plan rate) = 25% / 125% = 20%
```
Applied to net SE income AFTER the deductible portion of SE tax (i.e., net profit minus 1/2 of SE tax).

Contributing more than 20% of the adjusted net SE income triggers a 6% excise tax (IRS Form 5329) on the excess contribution for each year it remains in the account.

**How To Verify:**
- IRS Publication 560, Chapter 5, "Deduction Limit for Self-Employed Individuals"
- The IRS provides a rate table and worksheet in Pub 560.
- Cross-check: if net SE income after 1/2 SE tax deduction = $100,000, maximum SEP contribution = $20,000 (not $25,000).

**Dollar Impact:** On $200K net SE income, the excess contribution at 25% vs 20% = $10,000 over-contribution. 6% excise tax = $600/year compounding until corrected. Plus potential plan disqualification risk.

**This is the single most common self-employment calculation error across all AI models tested.**

---

### SE Tax Base: The 92.35% Factor

**Error Pattern:** Computing SE tax on 100% of net self-employment income instead of 92.35%.

**Why It Happens:** Preparers forget that the SE tax base is reduced by the "employer-equivalent" portion of FICA. The 92.35% factor represents 100% minus 7.65% (the employer-equivalent share).

**Correct Rule:**
```
SE tax base = Net SE income x 0.9235
SE tax = SE tax base x 15.3% (up to SS wage base) + SE tax base x 2.9% (above SS wage base)
```

**How To Verify:**
- IRS Schedule SE, Line 4a (short) or Line 4a-6 (long form).
- Multiply net SE income by 0.9235 before applying the 15.3%/2.9% rates.

**Dollar Impact:** On $200K SE income, the difference is $200,000 x 7.65% x 15.3% = approximately $2,341 in overstated SE tax.

---

### Social Security Wage Base Interaction

**Error Pattern:** Applying the full 15.3% SE tax rate when the taxpayer's W-2 wages already exceed the Social Security wage base.

**Why It Happens:** Failure to coordinate W-2 wages with SE income for Social Security tax purposes.

**Correct Rule:** The Social Security wage base for 2025 is $176,100. If W-2 wages already exceed this threshold, only the Medicare portion (2.9%) applies to SE income. The 12.4% Social Security portion does NOT apply. Additionally, the 0.9% Additional Medicare Tax applies to combined wages + SE income above $250,000 (MFJ).

**How To Verify:**
- Schedule SE, Section B (long form) is required when W-2 wages exist.
- Line 8a/8b coordinates W-2 wages with the SS wage base.
- If W-2 Box 3 (Social Security wages) >= $176,100, the SE SS tax is zero.

**Dollar Impact:** On $150K SE income where W-2 wages already exceed the SS base, the error is $150,000 x 0.9235 x 12.4% = $17,157 in phantom SE tax.

---

## Home Office Errors

### Livable Square Footage Denominator

**Error Pattern:** Using total home square footage (including garage, unfinished basement, attic, utility areas) as the denominator in the business-use percentage calculation.

**Why It Happens:** Tax software asks for "total square footage of home." Taxpayers enter the number from their property listing or appraisal, which includes all space. The IRS instruction says "total area of your home" but means the LIVABLE area.

**Correct Rule:** The denominator should be the livable (finished, habitable) square footage. Exclude:
- Unfinished basements
- Garages (unless used as office space)
- Unfinished attics
- Utility closets and mechanical rooms
- Storage-only areas that are not part of the living space

Source: IRS Publication 587 and Form 8829 instructions.

**How To Verify:**
- Compare the livable square footage against the property listing (which often separates finished vs. total).
- Walk through the home mentally: could you use each room as living space? If not, exclude it.
- Example: 300 sq ft office / 3,000 sq ft livable = 10.0%, NOT 300 / 4,000 total = 7.5%.

**Dollar Impact:** The 2.5% difference applied to $30,000 in home expenses = $750/year in missed deductions. Over multiple years, this compounds. For homes with large unlivable areas, the error can be $1,000-3,000/year.

---

### Identical Percentages Across Different Residences

**Error Pattern:** Using the same home office percentage for different residences (e.g., after a mid-year move).

**Why It Happens:** Laziness or assumption that "about the same" is good enough.

**Correct Rule:** Each residence must be independently measured. Different homes have different total livable square footage and different office dimensions. The percentage should reflect the actual measurements for each home.

**How To Verify:**
- If the taxpayer moved during the year, confirm that two separate Form 8829s were prepared.
- Each Form 8829 should show different percentages (unless the homes happen to have identical ratios, which is extremely unlikely).

**Dollar Impact:** Small individually, but identical percentages are an audit red flag that can trigger examination of the entire home office deduction.

---

### Schedule C Profit Zeroing Out Exactly

**Error Pattern:** Home office deduction perfectly zeroes out Schedule C profit.

**Why It Happens:** The preparer adjusts the home office deduction to eliminate all Schedule C profit, creating a suspiciously round zero.

**Correct Rule:** Let natural deductions flow. The Form 8829 limitation (cannot create a loss) means excess home office expenses carry forward -- this is normal and expected. A small Schedule C profit ($500-5,000) is much safer than a perfect zero, which signals manufactured deductions to the IRS.

**How To Verify:**
- Review Schedule C bottom line. If it is exactly $0 or a suspiciously round number, investigate.
- Check Form 8829 Line 35 vs Line 28. If Line 35 was artificially adjusted, that is the problem.
- A legitimate carryforward on Line 43/44 is fine and expected.

**Dollar Impact:** The dollar impact is in audit risk, not immediate tax savings. An audit of the home office deduction can cascade to examination of the entire Schedule C.

---

### Two Forms 8829 in a Move Year

**Error Pattern:** Filing only one Form 8829 when the taxpayer moved between homes during the tax year.

**Why It Happens:** Software may not prompt for a second home office, or the preparer forgets.

**Correct Rule:** Each residence gets its own Form 8829 with:
- Its own independently measured business-use percentage
- Pro-rated expenses for the months occupied
- Periods that must NOT overlap (move-out date of home 1 < move-in date of home 2)

**How To Verify:**
- If the taxpayer moved, ask: "Did you have a home office in both homes?"
- Verify move-in/move-out dates. The periods on the two 8829s should be contiguous or have a gap, never overlap.

**Dollar Impact:** Missing the second Form 8829 loses several months of home office deductions. On a $3,000/month mortgage + expenses, missing 7 months at 10% = $2,100.

---

### Both Spouses Claiming Home Office

**Error Pattern:** Both spouses each claiming a home office on their respective Schedule C businesses, but with a combined percentage that is unreasonable for the home.

**Why It Happens:** Each spouse independently calculates their percentage without considering the combined total.

**Correct Rule:** Both spouses CAN each have their own Form 8829 IF: (1) each has a separate Schedule C business, and (2) each has their own exclusive-use space. However, the combined office percentage should be reasonable for the home. Two 15% offices = 30% of the home used as offices is plausible only in large homes; in a 1,500 sq ft apartment, it strains credibility.

**How To Verify:**
- Add both percentages. If combined > 25-30%, verify the home is large enough to support that claim.
- Confirm each office space is physically separate and used exclusively for that business.

**Dollar Impact:** Audit risk. An unreasonable combined percentage invites scrutiny of both home office claims.

---

## Depreciation Errors

### Capital Improvements vs. Repairs

**Error Pattern:** Capitalizing repairs (which should be expensed immediately) or expensing capital improvements (which should be depreciated).

**Why It Happens:** The distinction is genuinely difficult and fact-specific. AI models frequently miscategorize.

**Correct Rule (with real examples):**

| Expense | Classification | Treatment | Reasoning |
|---------|---------------|-----------|-----------|
| Fence ($7,845) | Capital improvement | 15-year MACRS land improvement + bonus depreciation | Adds new structure to property |
| Driveway ($4,000) | Capital improvement | 15-year MACRS land improvement + bonus depreciation | Adds new structure to property |
| Bathroom renovation ($2,100) | Capital improvement | 27.5-year (residential rental) | Betterment of existing structure |
| Exterminator ($2,066) | Repair/maintenance | Expense immediately | Maintains existing condition |
| Leak detection ($753) | Repair/maintenance | Expense immediately | Diagnostic, maintains condition |
| Painting ($1,200) | Repair/maintenance | Expense immediately | Maintains existing condition |
| Roof replacement ($15,000) | Capital improvement | 27.5-year (residential rental) | Replacement of major component |
| Furnace repair ($500) | Repair/maintenance | Expense immediately | Maintains existing condition |

**De minimis safe harbor:** Items under $2,500 each can be expensed immediately with a proper election statement attached to the return, regardless of whether they are technically capital. This is a per-item, per-invoice threshold.

**How To Verify:**
- Apply the BRA test: Does it Betterment the property, Restore it to operating condition, or Adapt it to a new use? If yes to any, capitalize.
- Check the dollar amount against the de minimis threshold.
- For rental property, use IRS Reg. 1.263(a)-3.

**Dollar Impact:** A $7,845 fence incorrectly expensed instead of depreciated creates a timing difference. Conversely, a $2,066 exterminator incorrectly capitalized delays the deduction by years.

---

### Cost Segregation Timing

**Error Pattern:** Delaying the tax return to complete a cost segregation study.

**Why It Happens:** The preparer believes cost segregation must be done before the first return is filed.

**Correct Rule:** File the return using standard depreciation schedules (27.5-year straight-line for residential, 39-year for commercial). Later, obtain a cost segregation study and file Form 3115 (Application for Change in Accounting Method) to claim the catch-up depreciation in a single year. There is no penalty for starting with straight-line and switching later.

**How To Verify:**
- Is the return being delayed for a cost seg study? If yes, file with standard depreciation now.
- The Form 3115 catch-up is an automatic change (no IRS approval required for most situations).

**Dollar Impact:** The cost seg itself is the same either way. The delay risk is penalties and interest for late filing, or missed extension deadlines.

---

### OBBBA Bonus Depreciation Rules

**Error Pattern:** Applying the wrong bonus depreciation percentage based on acquisition/placed-in-service date.

**Why It Happens:** The OBBBA (One Big Beautiful Bill Act) restored 100% bonus depreciation, but only for property acquired AND placed in service after January 19, 2025. The old TCJA phasedown still applies to earlier acquisitions.

**Correct Rule:**
- Property acquired AND placed in service after January 19, 2025: 100% bonus depreciation
- Property placed in service in 2025 but acquired before January 20, 2025: 40% bonus (TCJA phasedown)
- The placed-in-service date AND the acquisition date both matter.

**How To Verify:**
- Check the purchase/acquisition date against January 19, 2025.
- Check the placed-in-service date.
- Both conditions must be met for 100% bonus.

**Dollar Impact:** On a $100,000 asset, 100% vs 40% bonus = $60,000 difference in first-year deduction. At 32% rate = $19,200 tax difference.

---

## Standard Deduction, Rate, and Threshold Errors

### 2025 MFJ Standard Deduction

**Error Pattern:** Using an outdated standard deduction amount.

**Why It Happens:** AI models are trained on historical data and frequently cite pre-OBBBA amounts. The standard deduction changes annually and was increased by OBBBA.

**Correct Rule:**
- 2025 MFJ: $31,500 (OBBBA increased from $30,000)
- 2025 Single: $15,750
- 2025 HOH: $23,625
- Additional for 65+/blind: $1,600 (MFJ), $2,000 (Single/HOH)

**How To Verify:** Check IRS.gov or the current year Form 1040 instructions. Do NOT trust AI-provided amounts without verification.

**Dollar Impact:** $1,500 difference (MFJ) at 32% rate = $480 tax impact. Seems small, but combined with other rate errors, the cumulative effect is significant.

---

### 2025 Mileage Rate

**Error Pattern:** Using the prior-year mileage rate.

**Why It Happens:** Rates change annually and AI models frequently cite outdated rates.

**Correct Rule:**
- 2025 business mileage: $0.70/mile (up from $0.67 in 2024)
- 2025 medical/moving: $0.22/mile
- 2025 charitable: $0.14/mile (fixed by statute, rarely changes)

**How To Verify:** IRS Notice or Revenue Procedure for the current year. Published annually, usually in December for the following year.

**Dollar Impact:** On 15,000 business miles, $0.03/mile difference = $450.

---

### SALT Cap Under OBBBA

**Error Pattern:** Using the old $10,000 SALT cap.

**Why It Happens:** The $10,000 cap was in effect from 2018-2024 under TCJA. OBBBA changed it for 2025+.

**Correct Rule:**
- 2025 personal SALT cap: generally $40,000 ($20,000 if MFS), subject to limitation for
  higher-MAGI taxpayers under the current Schedule A / Form 1040 instructions.
- Do not rely on stale single-status or phase-down summaries without checking the current
  worksheet / instructions.

**How To Verify:** OBBBA text, Section [relevant section]. IRS.gov guidance for 2025 tax year.

**Dollar Impact:** For a taxpayer with $25,000 in SALT who was previously capped at $10,000, the new cap unlocks $15,000 in additional deductions. At 32% rate = $4,800 tax savings.

---

### Child Tax Credit Under OBBBA

**Error Pattern:** Using the old $2,000 CTC amount.

**Why It Happens:** TCJA set CTC at $2,000. OBBBA increased it.

**Correct Rule:**
- 2025 CTC: $2,200 per qualifying child under 17
- Phase-out begins at $400,000 MAGI (MFJ), $200,000 (Single)
- Refundable portion (ACTC): up to $1,700

**How To Verify:** IRS Form 1040 instructions, Schedule 8812 for current year.

**Dollar Impact:** $200/child x number of children. For 3 children = $600.

---

## Crypto and Investment Errors

### Zero-Basis Election for Unknown Cost Basis

**Error Pattern:** Spending excessive time reconstructing cost basis for crypto assets from defunct exchanges or lost records.

**Why It Happens:** The preparer believes exact cost basis is required and attempts to reconstruct it from incomplete records.

**Correct Rule:** When cost basis genuinely cannot be determined (lost records, defunct exchange, pre-reporting-era transactions), you can elect zero basis. This means the entire proceeds are treated as gain. However, if the taxpayer has large capital loss carryforwards, these gains are absorbed by the losses with minimal or no net tax impact. Zero basis is a valid, conservative election.

**How To Verify:**
- Confirm that records are genuinely unavailable (not just inconvenient to find).
- Check if capital loss carryforwards are sufficient to absorb the resulting gains.
- Document the basis election in workpapers.

**Dollar Impact:** Varies enormously. For small crypto dispositions absorbed by loss carryforwards, the impact is zero. For large dispositions without offsetting losses, zero basis maximizes the reported gain.

---

### 1099-B Zero Basis for RSUs

**Error Pattern:** Accepting the $0 cost basis shown on the brokerage 1099-B for RSU (Restricted Stock Unit) sales.

**Why It Happens:** Brokers report RSU sales with $0 cost basis (Box 1e) because the basis was not tracked by the broker. The actual basis is the fair market value at the vesting date, which was already included in W-2 income.

**Correct Rule:** The cost basis for RSUs is the FMV at vest date (the amount included in W-2 Box 1). File Form 8949 with:
- Column (b): Date acquired = vest date
- Column (d): Date sold
- Column (e): Proceeds from 1099-B
- Column (f): Cost basis = FMV at vest x shares sold
- Column (g): Adjustment code "B" (basis reported to IRS is incorrect)

Failing to make this adjustment results in DOUBLE taxation: once through the W-2 (at vest) and again through the capital gain (at sale).

**How To Verify:**
- Compare 1099-B Box 1e against the RSU vest confirmation from the employer.
- The vest confirmation shows FMV at vest date and shares vested.
- The difference between 1099-B basis and actual basis should approximately equal the W-2 RSU income.

**Dollar Impact:** On $50,000 of RSU sales, accepting zero basis creates $50,000 in phantom capital gains. At 23.8% (long-term + NIIT) = $11,900 in excess tax.

---

### Payments in Lieu (PILs) from Securities Lending

**Error Pattern:** Treating Payments in Lieu of dividends as qualified dividends.

**Why It Happens:** PILs look like dividends on statements. Brokers may even label them similarly. But when shares are lent out for short selling, the "dividend" received is actually a payment-in-lieu, which does not qualify for the reduced dividend rate.

**Correct Rule:** PILs are taxed as ordinary income, not qualified dividends. The difference in rate for high-income taxpayers:
- Qualified dividends: 20% + 3.8% NIIT = 23.8%
- Ordinary income: 37% + 3.8% NIIT = 40.8%

**How To Verify:**
- Check 1099-DIV for "substitute payments" or "payments in lieu of dividends."
- Some brokers report PILs in a separate section of the year-end statement.
- If the taxpayer participates in a securities lending program (margin account, fully paid lending), PILs are likely present.

**Dollar Impact:** On $10,000 in PILs, the rate difference (40.8% vs 23.8%) = $1,700 in additional tax if incorrectly classified. But this is the CORRECT tax -- the error would be understating tax, which creates audit exposure.

---

## Nanny and Household Employee Errors

### Cash Nanny with No Documentation

**Error Pattern:** Claiming the Child and Dependent Care Credit (Form 2441) for a nanny paid in cash with no employment records.

**Why It Happens:** The taxpayer paid for childcare and wants the credit. The preparer enters the amounts without verifying documentation.

**Correct Rule:** Form 2441 requires:
- Provider's name, address, and SSN or EIN
- If provider is an individual, their SSN must be reported
- If provider refuses to provide SSN, you report it as "refused" but still must have the name and address
- Without ANY identifying information, the credit WILL be disallowed

Additionally, if the nanny is a household employee (works in the taxpayer's home, taxpayer controls how work is done), Schedule H is required:
- Withholding and payment of FICA (employer + employee shares)
- FUTA payments
- Issuance of W-2 to the nanny
- Filing of Schedule H with the return

**How To Verify:**
- Ask: "Do you have the nanny's full name, address, and Social Security number?"
- Ask: "Did you issue a W-2 to the nanny?"
- If no to either: the credit cannot be claimed for prior years.
- For future years: set up proper employment (W-4, I-9, quarterly estimated payments or annual Schedule H).

**Dollar Impact:** The credit itself is up to approximately $1,200 federal. Combined with FSA (Flexible Spending Account) savings from proper documentation, the annual benefit of compliance is approximately $3,100/year.

---

## State Filing Errors

### School District Identification

**Error Pattern:** Entering the wrong school district on a state return (particularly Ohio, Pennsylvania, and other states with school district income taxes).

**Why It Happens:** Taxpayers know their city/village but not their school district, or the school district does not match the city name.

**Correct Rule:** The school district must be the ACTUAL district where the residence is located, which may differ from the mailing address city. State Departments of Taxation provide lookup tools by address.

**How To Verify:**
- Use the state's official school district lookup tool (e.g., Ohio's SD Finder at tax.ohio.gov).
- Verify against the property tax bill, which typically lists the school district.

**Dollar Impact:** Incorrect school district can cause: (1) state rejection requiring re-filing, (2) incorrect local tax computation, (3) payments to wrong jurisdiction requiring correction.

---

### Part-Year NYC Allocation

**Error Pattern:** Reducing NYC part-year tax to a simple day-count proration (e.g., "lived in NYC 120 days / 365 = 32.9% of income").

**Why It Happens:** Day-count seems intuitive and is how many other jurisdictions work.

**Correct Rule:** NYC Form IT-360.1 (Change of City Resident Status) requires:
- Actual income received during the NYC resident period (not prorated annual income)
- Accrual adjustments for income earned during the NYC period but received later
- Separate computation of NYC taxable income for the resident period
- This requires a paycheck-by-paycheck reconciliation

**How To Verify:**
- Build a paycheck reconciliation: list each paycheck date, amount, and whether the taxpayer was a NYC resident on that date.
- Compare the IT-360.1 result against a simple day-count to see if the difference is material.

**Dollar Impact:** NYC income tax rates are 3.078% to 3.876%. On $200K income, a 10% misallocation = $20,000 x 3.5% = $700.

---

### W-2 Box 18 Local Wages Discrepancy

**Error Pattern:** Accepting W-2 Box 18 (local wages) at face value for local tax returns.

**Why It Happens:** W-2 is treated as the authoritative source, but employers may use allocation methods that differ from the correct local rules.

**Correct Rule:** The employer's allocation method for Box 18 may differ from the actual allocation required by the local jurisdiction. Common issues:
- Employer uses fixed percentage instead of actual days worked
- Employer does not adjust for remote work days
- Employer allocates to the wrong locality

**How To Verify:**
- Build your own reconciliation using actual work location by pay period.
- Compare against W-2 Box 18.
- Use the more accurate number, with documentation supporting the departure from the W-2.

**Dollar Impact:** Varies by jurisdiction. In high-tax localities (NYC, Philadelphia, Columbus OH), a 5-10% misallocation on $200K wages = $10,000-20,000 x local rate.

---

## Carryforward Errors

### Capital Loss Carryforward Character Tracking

**Error Pattern:** Mixing short-term and long-term capital loss carryforward characters, or tracking only a single combined number.

**Why It Happens:** The prior-year return shows a net capital loss on Schedule D Line 21, and the preparer carries forward a single number without separating ST and LT components.

**Correct Rule:** Capital loss carryforwards must be tracked separately by character:
- Short-term losses offset short-term gains first, then excess offsets long-term gains
- Long-term losses offset long-term gains first, then excess offsets short-term gains
- The annual $3,000 deduction against ordinary income is taken from short-term losses first, then long-term

The carryforward calculation requires the Capital Loss Carryover Worksheet in the Schedule D instructions.

**How To Verify:**
- Prior year Schedule D:
  - Line 7: Net short-term capital gain/loss
  - Line 15: Net long-term capital gain/loss
  - Line 16: Combined
  - Line 21: Net loss (limited to $3,000)
- Carryover Worksheet: separates the $3,000 deduction between ST and LT, then computes each character's carryforward.

**Dollar Impact:** The character distinction matters because long-term gains are taxed at preferential rates (0/15/20%) while short-term gains are ordinary income (up to 37%). Misclassifying $50,000 of LT carryforward as ST wastes the preferential rate benefit when gains arise.

---

### Home Office Carryforward (Form 8829 Lines 43/44)

**Error Pattern:** Dropping the Form 8829 carryforward between tax years.

**Why It Happens:** When changing preparers, changing software, or preparing returns out of sequence, the Form 8829 carryforward from the prior year's Lines 43/44 is simply forgotten. It does not appear on any 1098/1099 or other information return -- it exists only on the prior year's Form 8829.

**Correct Rule:** Form 8829 Lines 43 and 44 show casualty loss and operating expense carryforwards respectively. These must be entered on the current year's Form 8829, Line 29 (casualty) and Line 30 (operating expenses).

**How To Verify:**
- Pull the prior year's Form 8829.
- Check Lines 43 and 44.
- Verify these amounts appear on the current year's Form 8829, Lines 29 and 30.
- A real-world example: $5,535 carryforward was dropped between years, costing $5,535 x 32% = $1,771 in excess tax.

**Dollar Impact:** The full carryforward amount times the marginal tax rate. Can be $500-5,000+ depending on the carryforward size.

---

## Multi-Model Verification

### Cross-Model Validation Protocol

**Error Pattern:** Trusting a single AI model's output without independent verification.

**Why It Happens:** The first model's answer looks confident and well-reasoned. The preparer accepts it.

**Correct Rule:** Run aggressive positions through at least 2 AI models independently. In actual practice during the 2025 filing season, multi-model review caught:
- Claude used 25% SEP-IRA rate (Codex caught it -- correct rate is 20%)
- Claude used $0.67/mile mileage rate (Codex caught it -- 2025 rate is $0.70)
- GPT used outdated standard deduction (Claude caught it -- OBBBA changed the amount)
- Both Claude and GPT missed the zero-basis crypto election approach (Codex suggested it)
- Gemini flagged a home office percentage calculation that other models accepted

**How To Verify:**
- Present the same fact pattern to 2+ models without showing them each other's work.
- Focus review on DISAGREEMENTS between models -- these are the highest-value findings.
- For any disagreement, go to the primary source (IRS publication, statute, regulation).

**Dollar Impact:** In the 2025 filing season, multi-model review caught errors totaling approximately $20,000+ in incorrect deductions/credits across a single complex return.

---

### Arithmetic Must Be Deterministic

**Error Pattern:** Relying on AI models for arithmetic calculations.

**Why It Happens:** AI models can do simple math but make errors on complex multi-step calculations, especially with tax formulas involving circular references (like the SEP-IRA computation).

**Correct Rule:** Use deterministic calculators for ALL arithmetic:
- Aiwyn MCP tool for federal and state tax calculations
- Spreadsheet formulas for custom calculations
- Tax software's built-in calculations
- AI models should be used ONLY for: strategy analysis, identifying applicable rules, recommending optimizations, reviewing for completeness

**How To Verify:**
- Can you reproduce the number by hand or in a spreadsheet?
- Does the number match what Aiwyn/tax software calculates?
- If two deterministic sources disagree, investigate the input difference.

**Dollar Impact:** Arithmetic errors can range from trivial to catastrophic. A misplaced decimal in a $100,000 calculation is a $90,000 error.

---

## Aiwyn MCP Workflow Errors

### Namespace Naming Convention

**Error Pattern:** Guessing Aiwyn namespace names and getting them wrong.

**Why It Happens:** The namespace names use underscores and specific formatting that is not intuitive (e.g., `irs1040_schedule_d`, not `irs1040_scheduled` or `schedule_d`).

**Correct Rule:** ALWAYS call `tax_namespaces` first to discover the correct namespace names for the target tax year and jurisdiction. Do not guess.

**How To Verify:**
- Run `tax_namespaces` and use the exact names returned.
- If a namespace call fails, re-check the name against the `tax_namespaces` output.

**Dollar Impact:** No direct dollar impact, but workflow errors cause delays and frustration.

---

### Input JSON Complexity

**Error Pattern:** Underestimating the complexity of the Aiwyn input JSON for a complex return.

**Why It Happens:** A complex return (multiple W-2s, Schedule C, Schedule E, Form 8829, capital gains, state return) can require 650+ lines of JSON input.

**Correct Rule:**
1. Start with `tax_simple_return` to get the base structure.
2. Call `tax_namespace_schema` for each namespace you need to populate.
3. Systematically fill in each namespace, one at a time.
4. Use `check_tax` to validate before `calculate_tax`.
5. Build incrementally -- do not try to construct the entire JSON in one pass.

**How To Verify:**
- Does `check_tax` pass without errors?
- Are all expected income sources, deductions, and credits represented?
- Compare the namespace count against the expected forms.

**Dollar Impact:** Indirect -- an incomplete input JSON produces an incorrect calculation, which can mislead the entire return.

---

### MCP Server Configuration Location

**Error Pattern:** Adding MCP server configuration to `~/.claude/settings.json` instead of `~/.claude.json`.

**Why It Happens:** Both files exist and both contain Claude-related configuration. The naming is confusing.

**Correct Rule:** MCP server configuration (the `mcpServers` key) goes in `~/.claude.json` (the root-level file), NOT in `~/.claude/settings.json` (the directory-based settings file). Adding it to the wrong file means the MCP server never loads.

**How To Verify:**
- Check `~/.claude.json` for the `mcpServers` key.
- Run a simple MCP tool call (like `tax_namespaces`) to confirm the server is connected.

**Dollar Impact:** No direct dollar impact, but a non-functional MCP server means falling back to manual calculations, which increases error risk.

---

### Disqualification Handling

**Error Pattern:** Attempting to fix inputs or continue filing after Aiwyn returns a disqualification.

**Why It Happens:** The preparer wants to complete the return and tries to work around the disqualification.

**Correct Rule:** If `check_tax` or `calculate_tax` returns a response with a `disqualifications` key, STOP immediately. Do not attempt to modify inputs to bypass the disqualification. Inform the taxpayer of the reason and stop. Disqualifications exist for legal and compliance reasons.

**How To Verify:**
- Check the response for the `disqualifications` key.
- If present, read the disqualification reason and stop.

**Dollar Impact:** Attempting to bypass a disqualification can result in an invalid return, penalties, or worse.

---

## Source Document Hierarchy

### Trust Primary Documents Over Narrative

**Error Pattern:** Optimizing from memory or narrative notes instead of actual source documents.

**Why It Happens:** The taxpayer provides verbal or written descriptions of their situation. The preparer builds the return from these descriptions without verifying against documents.

**Correct Rule:** Source-of-truth hierarchy (highest to lowest priority):

1. **IRS/state filed returns and official transcripts** -- The definitive record of what was filed
2. **1098/1099/W-2/K-1 from issuers** -- Third-party-reported amounts that the IRS already has
3. **Bank statements and brokerage confirmations** -- Direct evidence of transactions
4. **Closing disclosures and settlement statements** -- Legal documents from real estate transactions
5. **Business ledgers and expense exports** -- Taxpayer-maintained records
6. **Narrative notes and memory** -- LOWEST priority, must be corroborated

**How To Verify:**
- For every number on the return, can you point to a document at level 1-5?
- If the only source is level 6 (narrative), flag it for follow-up and request documentation.
- Discrepancies between levels favor the higher-priority source.

**Dollar Impact:** Narrative-based errors can be enormous. A taxpayer who says "I made about $150K" when W-2 shows $170,242 creates a $20,242 underreporting risk.

---

## Summary: Top 10 Highest-Impact Errors

| Rank | Error | Typical Dollar Impact |
|------|-------|--------------------|
| 1 | SEP-IRA 25% vs 20% rate | $600+/year excise tax + plan risk |
| 2 | Missing second 1098 (servicer transfer) | $5,000-15,000 in missed deductions |
| 3 | RSU zero basis on 1099-B (double taxation) | $5,000-20,000 in excess tax |
| 4 | SS wage base not coordinated with SE tax | $5,000-17,000 in phantom SE tax |
| 5 | Wrong home office denominator | $1,000-3,000/year |
| 6 | Dropped Form 8829 carryforward | $500-5,000 |
| 7 | Capital loss character mixing | Variable, potentially large |
| 8 | Outdated standard deduction / SALT cap | $500-5,000 |
| 9 | Missing prepaid interest from closing | $500-5,000 |
| 10 | Cash nanny without documentation | $3,100/year in lost credits/savings |

---

*Last updated: 2026-04-13. Based on actual 2025 filing season multi-model cross-validation experience.*
