# Operators — Cognitive Moves for Estate Planning

Operators are **composable mental moves** you apply to any asset, beneficiary, or objective. They are recurring lenses, not a rigid algorithm. Each card has a **trigger**, an **action**, a **prompt module**, and **failure modes** to watch for.

When designing or auditing a plan, cycle through the operators in roughly the order below when useful. Reorder or skip them if the actual fact pattern demands it.

---

## § Probate-Bypass

**Trigger:** Any asset on the inventory.

**Action:** Ask — does this asset avoid probate? Should it?

**Prompt module:**

> "For each asset on the inventory, identify: (a) current titling/beneficiary status, (b) whether it passes through probate today, (c) whether it should avoid probate, (d) the cheapest mechanism to change it if needed (TOD/POD, beneficiary designation, retitling to revocable trust, TOD deed)."

**Failure modes:**

- Forcing probate avoidance when probate's creditor-cutoff benefit is actually wanted (uncommon, but real for estates with suspected creditor claims)
- Naming beneficiaries on an account but forgetting to name contingent beneficiaries — if the primary predeceases, asset goes through probate anyway
- Joint tenancy "fix" that gives survivor full ownership but unintentionally disinherits the decedent's children

---

## ⚖ Spousal-Rights Check

**Trigger:** Married user, separated user, or any user in a community-property state.

**Action:** Confirm the plan does not violate the surviving spouse's elective share, community property rights, or ERISA default beneficiary rule.

**Prompt module:**

> "The client is married and proposes [plan]. Check: (1) Does their state give the spouse an elective share of X%? (2) Is any asset community property that cannot be devised away from the spouse? (3) Does the plan include ERISA retirement plans where the spouse must consent to a non-spouse beneficiary? (4) Has a prenup or postnup with valid waiver been executed? If any answer blocks the plan, flag it and propose an alternative (QTIP, valid waiver, adjusted shares)."

**Failure modes:**

- Assuming the spouse "agreed" without a written waiver that meets state-specific form requirements
- Missing community-property character of assets acquired during marriage, even if titled in one name
- Assuming a state divorce-revocation statute cleans up a workplace plan when the actual federal plan rules may still control

---

## ⧉ Beneficiary-Title Coherence

**Trigger:** Always. Run this after every design change.

**Action:** Build a matrix: row per asset, column per controlling document. Check that every document agrees.

**Prompt module:**

> "For each asset, identify the controlling legal mechanism (will, revocable trust, beneficiary designation, title, contract, buy-sell agreement) and confirm the named recipient is consistent across all mechanisms and matches the user's intent. Flag any contradictions."

**Failure modes:**

- The classic: 401(k) still names ex-spouse
- Life insurance names "the estate" forcing probate and triggering IRD acceleration
- Revocable trust created but never funded — title of real estate still in individual name
- House titled joint tenancy with one child, will says split among all children — title wins

---

## $↑ Step-Up-vs-Transfer Tradeoff

**Trigger:** Any proposal to gift appreciated assets during life, use lifetime exemption, or fund an irrevocable trust.

**Action:** Compare: (a) estate tax saved by removing the asset (using the applicable federal and state transfer-tax rates), vs. (b) capital gains tax cost to heirs from lost step-up (using the likely combined federal, NIIT, and state capital-gains burden on the lifetime appreciation plus any further appreciation before sale).

**Prompt module:**

> "The client wants to gift asset X (current FMV $Y, basis $Z) to an irrevocable structure. Calculate: (1) Estate tax savings if kept in estate — is the estate likely to be above the applicable federal and state exemptions? (2) Income tax cost to heirs from lost step-up — (Y − Z) × heir's expected capital-gains rate. If estate is below exemption, step-up usually dominates. Above exemption, transfer-tax usually dominates. Show the crossover."

**Failure modes:**

- Gifting appreciated stock below the federal exemption to "save taxes" when no estate tax problem was actually modeled — often a near-pure loss of step-up
- Irrevocable trust created in 2014 at lower exemption that should now be decanted or unwound
- Ignoring state estate tax in the crossover calculation

---

## ⧗ Liquidity-at-Death

**Trigger:** Any estate with illiquid assets (business, farm, real estate, private fund) AND either federal or state estate tax exposure OR significant debt (mortgage, margin, capital call).

**Action:** Build a Day-270 cash flow. What cash is in the estate on Day 270? What must be paid (federal estate tax, state estate tax, mortgage catch-up, credit-card debt, funeral, administration fees, specific cash bequests)? Gap = liquidity problem.

**Prompt module:**

> "On Day 270 after death, the estate must pay: federal estate tax (if above exemption), state estate tax (if applicable), ongoing mortgage on the house, ongoing carrying costs on real estate, capital calls on PE funds, and administration expenses. Compute the expected cash need and the expected cash available (checking, money market, liquid brokerage, life insurance proceeds). If the gap is negative, design liquidity: ILIT-owned life insurance, §6166 deferral, §303 redemption, liquid reserve, or pre-death debt paydown."

**Failure modes:**

- Assuming heirs can refinance a business during probate (they usually can't — lenders wait for letters testamentary)
- Forgetting to factor ongoing carrying costs during the 9-18 month administration
- Ignoring margin debt — margin lenders can force-liquidate during probate, shredding step-up

---

## ⧒ Incapacity-Transition

**Trigger:** Every adult, especially over 50 or with any cognitive/psychiatric history.

**Action:** Define the transition trigger explicitly. Name the successor. Build the handoff.

**Prompt module:**

> "Specify for each incapacity scenario: (1) The trigger — e.g., 'two physicians certify in writing the principal lacks capacity to manage financial affairs.' (2) The immediate successor (financial trustee, POA agent, healthcare agent). (3) The backup successor. (4) Whether the POA should be immediate or springing, factoring in state law, bank practice, family trust, and abuse risk. (5) Whether a trust protector or family council has authority to accelerate the transition. (6) Any Ulysses-clause pre-commitments for mental-health or substance-abuse episodes."

**Failure modes:**

- Springing POA that requires physician certification — banks refuse, doctors won't certify, agent can't act
- No gifting authority in the POA — can't continue annual exclusion program during incapacity
- No incapacity transition clause in revocable trust — successor trustee can't step in

---

## ⌂ Lumpy-Asset Division

**Trigger:** Any asset the user wants to leave to multiple heirs (vacation home, art, business, classic cars, boats, jewelry collection, wine cellar).

**Action:** Either assign it to one heir with equalizing cash to others, put it in an LLC with an operating agreement governing use and buyout, or direct sale with proceeds split.

**Prompt module:**

> "Asset X is held by the decedent and is intended for heirs A, B, C. Options: (1) Sell and split proceeds equally (cleanest, relationship-preserving). (2) Assign to one heir with cash equalization to others (needs independent appraisal + liquidity). (3) Family LLC with operating agreement covering scheduling, expenses, buyout formula, forced-sale trigger. (4) Trust with independent trustee to break deadlocks. For each option, identify: required liquidity, governance needs, conflict likelihood. Recommend based on the specific heirs' relationships and financial capacity."

**Failure modes:**

- Default "to my three children equally" on a single house — very high risk of deadlock and eventual partition litigation
- No forced-sale trigger — one sibling holds the others hostage for decades
- No right of first refusal — sibling with most cash buys out at a lowball price

---

## ⟳ Cross-State Domicile

**Trigger:** User has lived in multiple states, owns property in multiple states, split residency (snowbird), recently relocated, or plans to relocate.

**Action:** Confirm current domicile. Confirm ancillary probate exposure. Evaluate strategic relocation.

**Prompt module:**

> "Identify (1) the user's current domicile state, (2) every state where they own real property, (3) every state where a named heir lives. For domicile: check driver's license, voter registration, homestead declaration, primary physician, primary accountant, days present. For ancillary probate exposure: recommend trust or TOD deed for out-of-state real estate. For relocation: calculate state estate-tax savings (if moving from NY/MA/OR to FL/TX/NV) and note the 'clean break' requirements. Flag NY and CA's aggressive statutory-resident and former-resident rules."

**Failure modes:**

- Claiming FL domicile while keeping the NY house open year-round and the NY doctor — NY audit wins
- Missing that MA taxes real property of non-residents
- Failing to update will after interstate move — old state's execution formalities may not satisfy new state's probate court

---

## ⩚ Vulnerable-Beneficiary Filter

**Trigger:** Any heir who is disabled, on SSI/Medicaid/SNAP/Section 8/VA Aid, has addiction, mental illness, debt crisis, recent bankruptcy, predatory spouse, gambling problem, or developmental/financial immaturity.

**Action:** Route inheritance to a structure that supplements but does not disqualify, protects from creditors/spouses, and provides trustee-controlled distributions.

**Prompt module:**

> "Beneficiary B presents risk factors: [list]. Route their inheritance to: (1) Third-party Special Needs Trust if means-tested benefits are at stake. (2) Spendthrift + discretionary trust with independent corporate trustee if addiction/creditor/divorce risk. (3) Incentive trust with milestone triggers if financial-immaturity risk. (4) Staged distributions with HEMS plus discretion if simply young. Avoid blunt outright distributions when benefits eligibility, addiction, creditor pressure, or coercive relationships are real risks. For SNT: first-party (self-settled) vs. third-party — choose third-party where possible to avoid Medicaid payback. Coordinate with ABLE account if eligible. Require letter of wishes to trustee."

**Failure modes:**

- Outright $50K to a beneficiary on SSI — disrupts benefits eligibility and may force rushed spend-down or restructuring
- Family-member trustee for an addicted beneficiary — emotional compromise, manipulation, eventual cash distributions "just this once"
- No trust protector — decades-old trust becomes unworkable as beneficiary's life changes

---

## ∵ Tax-Apportionment

**Trigger:** Any estate with expected federal or state estate tax, AND with both probate and non-probate (beneficiary-designated) assets.

**Action:** Include explicit tax-apportionment clause. Default rules often produce unintended outcomes.

**Prompt module:**

> "The estate expects $X of estate tax. Identify the probate and non-probate assets and the beneficiaries of each. Under default state apportionment, taxes typically charge to residuary — meaning specific-bequest and non-probate beneficiaries take free of tax, while residuary takers absorb the full bill. Is this the user's intent? If not, draft a tax-apportionment clause that (a) assigns a pro-rata share of tax to each beneficiary based on fair-market-value of their inheritance, or (b) assigns all tax to a specific source (e.g., the life insurance proceeds, or a specific liquid account). Coordinate with the executor's powers."

**Failure modes:**

- Residuary beneficiary absorbs 100% of estate tax while life-insurance-designated heir takes tax-free — unintended inequity
- Business heir forced to sell because no liquidity clause in will
- State tax apportionment differs from federal tax apportionment

---

## ⚑ Blended-Family QTIP

**Trigger:** Remarriage, stepchildren, biological children from prior relationships, a testator who has been married more than once.

**Action:** Test whether "to spouse, remainder to children" is actually enforceable or whether the spouse can rewrite/remarry/spend down.

**Prompt module:**

> "The user is in their second marriage with children from the first. The proposed plan leaves [X] to the surviving spouse, with the remainder intended for the first-marriage children at the spouse's later death. Under this plan: (1) If assets pass outright, how much practical ability does the surviving spouse have to redirect them away from the first-marriage children through later planning, remarriage, spending, or creditor pressure? (2) If a trust is used, how much principal discretion exists and who controls it? (3) Does the plan leave the first-marriage children materially exposed? If yes, propose a QTIP or similarly protective structure: marital deduction at first death, income for life to surviving spouse, remainder to first-marriage children at second death."

**Failure modes:**

- Trusting verbal agreement that "Mom said she'd leave the rest to you kids" — unenforceable, routinely broken
- QTIP funded but no independent trustee — surviving spouse as trustee has too much discretion
- Forgetting life-insurance equalization for first-marriage children who won't otherwise benefit until the surviving spouse's death (often decades later)

---

## ☍ Disclaimer Window

**Trigger:** A death just occurred and a plan needs mid-course correction.

**Action:** Within 9 months of the death, identify whether a qualified disclaimer by one or more beneficiaries produces a better tax/family outcome than accepting.

**Prompt module:**

> "Beneficiary B would inherit X. If B is (a) already wealthy and adding X creates more eventual estate-tax exposure, (b) in bankruptcy or facing creditors, (c) the asset is a burden (timeshare, contaminated land, low-basis stock with carried capital calls), or (d) disclaiming lets X pass to a more tax-efficient recipient (child/grandchild skipping a generation of estate tax, CRT, charity), consider a qualified disclaimer. Requirements: in writing, within 9 months of death, no acceptance of benefit prior, disclaimant cannot direct — asset passes as if disclaimant predeceased. Partial disclaimers allowed. Verify the contingent beneficiary in the will or trust is the desired recipient."

**Failure modes:**

- Missing the 9-month window
- Partial acceptance before disclaiming (e.g., cashing a dividend check) — poisons the disclaimer
- Assuming the disclaimant can redirect — they can't; the instrument's default applies

---

## ☖ Trust-Situs Selection

**Trigger:** Long-term (generational) trust, dynasty planning, substantial ongoing trust income, beneficiary in a high-tax state where the trust is taxed, creditor-protection goals.

**Action:** Evaluate situs selection: South Dakota, Nevada, Delaware, Wyoming, Alaska, Tennessee for no state income tax on trusts + long/perpetual duration + favorable creditor law.

**Prompt module:**

> "A long-term trust with assets generating $X/year of income is being created. Evaluate situs in (a) the user's home state, (b) SD/NV/DE/WY/AK/TN. Factors: state income tax on trust income (if undistributed or going to non-state beneficiary), duration (rule against perpetuities), creditor protection, directed-trust statutes. If situs selection produces meaningful savings or protection, structure: corporate trustee in selected state, investment committee elsewhere, distribution committee elsewhere, trust protector with power to change situs. Warn about aggressive home-state rules (CA, NY, NJ targeting DING/NING structures)."

**Failure modes:**

- Claiming SD situs but all administrative decisions made in NY — NY taxes anyway
- Missing the trust protector to change situs later if law changes
- Using offshore situs without understanding FBAR/FATCA/Form 3520 reporting

---

## ⇢ Basis-Consistency

**Trigger:** Post-death administration, especially for estates filing Form 706.

**Action:** Capture date-of-death FMV for every asset. File Form 8971 if required. Communicate basis to each beneficiary in writing.

**Prompt module:**

> "For each asset on the estate inventory, determine date-of-death FMV using the IRS-accepted method: publicly traded securities = average of high and low on date of death (or alternate valuation date if elected). Real estate, business interests, art: qualified appraisal. Record, aggregate, and report on Form 706 if filed. If Form 8971 applies, file it on the current timetable, generally 30 days after the earlier of the Form 706 due date (including extensions) or the actual filing date, and communicate basis information to the affected beneficiaries. Retain documentation — years later, a beneficiary selling will need this to prove basis to their own tax preparer."

**Failure modes:**

- No Form 8971 filing when required — potentially significant penalties plus downstream basis confusion
- No documented basis — the beneficiary's eventual sale becomes much harder to substantiate, and tax reporting can deteriorate badly
- Alternate valuation date elected without modeling — sometimes reduces estate tax but increases future capital gains by more

---

## Composition Pattern

Operators compose. A single asset often triggers several:

**Example:** A concentrated position in pre-IPO stock owned by a 58-year-old with a blended family and a non-citizen spouse.

- § Probate-Bypass — TOD? Trust? Beneficiary form?
- ⚖ Spousal-Rights Check — non-citizen spouse triggers QDOT / treaty / portability analysis
- $↑ Step-Up-vs-Transfer — GRAT candidate (high-growth asset)
- ⧗ Liquidity-at-Death — yes, illiquid, needs ILIT
- ⚑ Blended-Family QTIP — first-marriage children protection
- ☖ Trust-Situs — if GST planning, consider SD dynasty trust
- ∵ Tax-Apportionment — who pays the estate tax?

The final design is the intersection of all operators' outputs.
