# Cross-Year Carryforward Ledger

> **Why this matters:** Carryforward errors are the #1 source of missed deductions and
> the #1 thing CPAs get wrong. Items generated in one year but usable only in future
> years are routinely lost, mischaracterized, or incorrectly computed. A master ledger
> that tracks every carryforward item across years is non-negotiable for accurate
> multi-year tax preparation.

---

## Master Ledger Template

Maintain one row per carryforward item. Update annually during Phase 5 (draft validation)
and Phase 6 (post-filing). The ledger is the single source of truth for all carryforward
amounts entering and leaving each tax year.

| Item | Character | Expiration | Beginning Balance | Generated This Year | Used This Year | Ending Balance | Source Form/Line | Verification |
|------|-----------|------------|-------------------|---------------------|----------------|----------------|------------------|--------------|
| Capital Loss — ST | Short-term | None (indefinite) | $X | $X | $X | $X | Sch D line 7 / Form 8949 | Prior year Sch D line 7 |
| Capital Loss — LT | Long-term | None (indefinite) | $X | $X | $X | $X | Sch D line 15 / Form 8949 | Prior year Sch D line 15 |
| Net Operating Loss (post-2017) | Ordinary | None (indefinite) | $X | $X | $X | $X | Form 1045 / 1040 line 8 | Prior year NOL worksheet |
| Net Operating Loss (pre-2018) | Ordinary | 20 years from origin | $X | $X | $X | $X | Form 1045 / 1040 line 8 | Prior year NOL worksheet |
| Passive Activity Loss — [Activity] | Passive | None (released on disposition) | $X | $X | $X | $X | Form 8582 | Prior year 8582 worksheet |
| Suspended Partnership Loss — [Entity] | Basis/At-risk/Passive | None (see three-layer rules) | $X | $X | $X | $X | K-1 / Form 6198 / 8582 | Prior year K-1 + worksheets |
| QBI Loss | QBI | None (indefinite) | $X | $X | $X | $X | Form 8995/8995-A | Prior year 8995 line 16 |
| Home Office Expense | Business | None (indefinite) | $X | $X | $X | $X | Form 8829 line 43/44 | Prior year 8829 line 44 |
| Investment Interest Expense | Investment | None (indefinite) | $X | $X | $X | $X | Form 4952 line 7 | Prior year 4952 line 7 |
| Charitable Contribution — 60% | Ordinary | 5 years from contribution | $X | $X | $X | $X | Sch A + charity worksheet | Prior year charity worksheet |
| Charitable Contribution — 30% | Capital gain | 5 years from contribution | $X | $X | $X | $X | Sch A + charity worksheet | Prior year charity worksheet |
| Foreign Tax Credit — General | Per-basket | 10 years forward (1 yr carryback) | $X | $X | $X | $X | Form 1116 | Prior year 1116 |
| AMT Credit | Credit | None (indefinite) | $X | $X | $X | $X | Form 8801 | Prior year 8801 / 6251 |
| General Business Credit | Credit | 20 years forward (1 yr carryback) | $X | $X | $X | $X | Form 3800 | Prior year 3800 |
| Section 179 | Business | None (indefinite) | $X | $X | $X | $X | Form 4562 line 13 | Prior year 4562 line 13 |
| At-Risk Limitation — [Activity] | At-risk | None (indefinite) | $X | $X | $X | $X | Form 6198 | Prior year 6198 |
| Excess Business Loss | Ordinary/NOL | None (becomes NOL, indefinite) | $X | $X | $X | $X | Form 461 | Prior year 461 |

---

## Capital Loss Carryforward

**Code section:** IRC section 1212

**Key rules:**
- Short-term (ST) and long-term (LT) losses are tracked SEPARATELY — this is the most
  commonly botched item. Mixing character produces incorrect tax results.
- section 1212 ordering rules: current-year ST losses offset ST gains first, then LT gains.
  Current-year LT losses offset LT gains first, then ST gains. Only after all netting
  does the $3,000 ordinary income offset apply.
- The $3,000 annual offset against ordinary income ($1,500 MFS) is automatic — it is not
  an election. Software applies it, but verify the character split is correct.
- ST losses offset ordinary income at the taxpayer's marginal rate; LT losses offset at
  what would have been the preferential capital gains rate. ST carryforwards are therefore
  more valuable per dollar.

**Verification protocol:**
1. Pull prior year Schedule D lines 7 and 15
2. Confirm beginning balance matches prior year ending balance exactly
3. Verify current year Form 8949 transactions are correctly classified ST vs LT
4. Check that $3,000 offset was applied before computing carryforward
5. Verify wash sale adjustments did not distort the carryforward character

**Common errors:**
- CPA mixes ST and LT into a single number
- Software carries forward net loss without preserving character split
- Wash sales incorrectly treated as realized losses in the carryforward computation
- Failure to adjust basis after section 1014 step-up (inherited assets) — the step-up
  can eliminate or reduce the loss that generated the carryforward

---

## Net Operating Loss (NOL)

**Code section:** IRC section 172

**Key rules (post-TCJA, 2018+):**
- NOLs generated in 2021+ carry forward indefinitely (no carryback except farming)
- 80% of taxable income limitation — NOL can only offset 80% of current-year taxable
  income, not 100%. The remaining 20% is taxed at the current marginal rate.
- Farming losses (section 172(b)(1)(B)): 2-year carryback + unlimited carryforward, and
  the 80% limitation does not apply to the carryback portion
- NOL deduction is claimed on Form 1040 line 8 as a negative number
- Excess business loss limitation (section 461(l)) feeds into NOL — excess business losses
  above the threshold become NOL carryforwards

**Verification protocol:**
1. Confirm NOL was actually generated (not just a paper loss from passive activities)
2. Verify the 80% limitation was correctly applied in the usage year
3. Track cumulative NOL across all carryforward years
4. Ensure farming NOL is tracked separately (different rules)

---

## Passive Activity Loss

**Code section:** IRC section 469

**Key rules:**
- Tracked by INDIVIDUAL activity or property — never lump all passive losses together
- Suspended losses carry forward until the activity generates passive income OR the
  taxpayer completely disposes of the activity in a fully taxable transaction
- section 469(g): upon complete disposition, ALL accumulated suspended losses for that
  activity are released and become non-passive (deductible against any income)
- Grouping election (section 469(c)(3)(C) / Reg 1.469-4): taxpayer can group activities
  as a single activity for section 469 purposes. Once made, the election is binding and
  changes the disposition trigger. Grouping multiple rental properties means ALL must be
  disposed to release suspended losses.
- $25,000 rental real estate exception (section 469(i)): phases out between $100K-$150K
  MAGI. Only available for active participation in rental activities.
- Real Estate Professional status (section 469(c)(7)): 750+ hours + more than half of
  personal services. Reclassifies rental activities as non-passive.

**Verification protocol:**
1. Maintain a per-activity/per-property running balance of suspended losses
2. Verify grouping elections are documented and consistent year over year
3. When a property is sold, confirm ALL suspended losses for that property were released
4. Verify at-risk basis before allowing passive loss deduction (section 465 applies first)
5. Check whether RE Professional status changes the passive characterization

**Common errors:**
- Failure to release suspended losses when property is sold (this is the most expensive
  carryforward error — can be thousands to tens of thousands of dollars)
- Grouping election changes without proper documentation
- Treating a partial disposition as a complete disposition for section 469(g) purposes
- Not tracking basis adjustments (depreciation reduces at-risk basis)

---

## QBI Loss Carryforward

**Code section:** IRC section 199A

**Key rules:**
- Negative QBI from a qualified trade or business carries forward to subsequent years
- The carryforward offsets ONLY future QBI from the same or other qualified businesses —
  it does not offset W-2 income, investment income, or any other non-QBI income
- Character tracking matters: the carryforward reduces the QBI deduction, not income itself
- Each business's QBI is computed separately, then aggregated. Negative QBI from one
  business reduces positive QBI from another in the aggregation step.
- Form 8995 (simplified) or Form 8995-A (standard) line 16 shows the carryforward

**Verification protocol:**
1. Pull prior year Form 8995/8995-A to confirm carryforward amount
2. Verify the carryforward was applied only against QBI, not other income
3. If multiple businesses, verify per-business QBI was computed correctly before aggregation
4. Check whether W-2 wage / UBIA limitations apply (above income thresholds)

---

## Home Office Expense Carryforward

**Code section:** Form 8829 lines 43/44

**Key rules:**
- When allowable home office expenses exceed the business income allocated to the home
  office, the excess carries forward to the next year
- The carryforward is applied in the next year BEFORE current-year expenses
- Form 8829 line 43 shows the amount carried forward from the prior year
- Form 8829 line 44 shows the amount carried to the next year
- This carryforward is specific to the simplified vs. actual method — switching methods
  can forfeit the carryforward

**Verification protocol:**
1. Confirm prior year Form 8829 line 44 matches current year line 43
2. Verify that business income limitation was properly computed
3. Check ordering: carryforward applied first, then current-year expenses

---

## Investment Interest Expense Carryforward

**Code section:** IRC section 163(d)

**Key rules:**
- Investment interest expense is deductible only to the extent of net investment income
- Excess carries forward indefinitely until sufficient net investment income exists
- Form 4952 line 7 tracks the carryforward
- The taxpayer may elect to treat qualified dividends and net capital gains as investment
  income (thereby making them ineligible for preferential rates) to increase the deduction
- Net investment income = investment income minus investment expenses (after 2% floor
  elimination under TCJA, most investment expenses are non-deductible)

**Verification protocol:**
1. Pull prior year Form 4952 line 7
2. Verify net investment income computation
3. Evaluate whether the election to include capital gains/qualified dividends is beneficial

---

## Charitable Contribution Carryforward

**Code section:** IRC section 170(d)

**Key rules:**
- Contributions exceeding AGI percentage limits carry forward for 5 years
- Different limit categories carry separately: 60% AGI (cash to public charities), 30% AGI
  (capital gain property to public charities), 30% AGI (cash to private foundations), 20%
  AGI (capital gain property to private foundations)
- Current-year contributions are deducted FIRST; carryforwards are used only to the extent
  the limit is not consumed by current-year contributions
- The 5-year clock starts in the year the contribution was made — unused amounts after 5
  years are permanently lost
- FIFO ordering within each category

**Verification protocol:**
1. Track each carryforward by category (60%/30%/20%) and year of origin
2. Verify remaining life of each carryforward (how many years remain)
3. Confirm current-year contributions are applied first
4. If approaching expiration, consider engineering additional income to absorb the deduction

---

## Foreign Tax Credit Carryforward

**Code section:** IRC section 904(c)

**Key rules:**
- Excess foreign tax credits carry back 1 year, forward 10 years
- Per-basket tracking required: general category, passive category, section 901(j), etc.
- Form 1116 must be filed for each applicable basket
- The carryforward is used only when the limitation allows (foreign source income in the
  basket generates limitation room)
- Election to deduct vs. credit must be consistent for all foreign taxes in a given year

**Verification protocol:**
1. Confirm per-basket carryforward amounts from prior year Form 1116
2. Verify limitation computation for each basket
3. Check whether deduction vs. credit election is optimal for current year
4. Track remaining carryforward life (10-year limit)

---

## AMT Credit Carryforward

**Code section:** IRC section 53

**Key rules:**
- AMT credit is generated when AMT liability exceeds regular tax liability (AMT is paid
  on top of regular tax, and the excess generates a future credit)
- The credit is used in future years when regular tax exceeds tentative minimum tax
- Unlimited carryforward period — no expiration
- Form 8801 computes the allowable credit in the carryforward year
- Post-TCJA, AMT rarely applies to individuals (higher exemption), but pre-TCJA AMT
  credits may still be sitting unused

**Verification protocol:**
1. Pull prior year Form 8801 or 6251 to confirm AMT credit amount
2. Verify whether regular tax exceeds tentative minimum tax (room to use credit)
3. Check whether ISO exercises or other AMT preference items generated new AMT

---

## General Business Credit

**Code section:** IRC section 38

**Key rules:**
- Composite of multiple credits (R&D, Work Opportunity, Small Employer Health, etc.)
- Excess carries back 1 year, forward 20 years
- Form 3800 aggregates and limits the credits
- Subject to net income tax / tentative minimum tax limitation

---

## Section 179 Carryforward

**Key rules:**
- Section 179 deduction is limited to the business's taxable income (active income)
- Excess above business income carries forward to the next year
- Form 4562 line 13 shows the carryforward amount
- The carryforward is per-entity, not per-asset

---

## At-Risk Limitation

**Code section:** IRC section 465

**Key rules:**
- Tracked separately by activity
- Losses are deductible only to the extent the taxpayer is at risk in the activity
- At-risk amount = cash invested + borrowed amounts for which taxpayer is personally liable
  + FMV of property pledged
- Losses suspended under section 465 carry forward until additional at-risk basis is created
- Form 6198 computes the at-risk limitation
- section 465 is applied BEFORE section 469 (passive activity rules)

---

## Excess Business Loss Limitation

**Code section:** IRC section 461(l)

**Key rules:**
- For 2025: excess business losses above $305,000 (single) / $610,000 (MFJ) are disallowed
  (verify current-year thresholds — these are inflation-adjusted annually)
- The disallowed excess becomes a net operating loss carryforward under section 172
- Applies to all non-corporate taxpayers
- Computed after section 469 passive activity rules are applied
- Form 461 computes the limitation

---

## Suspended Partnership Losses (Three-Layer Limitation)

**Code sections:** IRC sections 704(d), 465, 469

**Why this deserves a dedicated section:** Partnership and S-Corporation losses flow through on
Schedule K-1, but the taxpayer cannot simply deduct them. Three separate limitations must be
applied in sequence, and a loss suspended at any layer carries forward under that layer's rules.
Failing to track which layer suspended the loss is the most common K-1 carryforward error.

**The Three Layers (applied in this order):**

```
Layer 1: BASIS LIMITATION (section 704(d) for partnerships; section 1366(d) for S-Corps)
  -> Loss deductible only to the extent of the partner's/shareholder's outside basis
  -> Basis = contributions + share of income + share of debt (partnerships) - distributions - share of losses
  -> For partnerships: recourse and nonrecourse debt allocations increase basis
  -> For S-Corps: shareholder loans TO the corp (not from third parties) increase basis
  -> Suspended losses carry forward indefinitely until basis is restored
  -> Form: No specific IRS form — tracked on partner's/shareholder's basis worksheet

Layer 2: AT-RISK LIMITATION (section 465)
  -> Losses passing Layer 1 are deductible only to the extent the taxpayer is "at risk"
  -> At-risk amount = cash invested + adjusted basis of property contributed + amounts borrowed
    for which taxpayer is personally liable or has pledged property
  -> Nonrecourse debt generally does NOT increase at-risk amount (exception: qualified
    nonrecourse financing for real estate)
  -> Suspended losses carry forward indefinitely until additional at-risk amount is created
  -> Form 6198 computes the limitation

Layer 3: PASSIVE ACTIVITY LIMITATION (section 469)
  -> Losses passing Layers 1 and 2 are deductible only against passive income (unless the
    taxpayer materially participates under one of the 7 material participation tests)
  -> Suspended passive losses carry forward indefinitely until passive income is generated
    OR the entire interest is disposed of in a fully taxable transaction
  -> Form 8582 computes the limitation
```

**Per-Entity Tracking Template:**

| Entity | K-1 Loss | Layer 1: Basis Available | Layer 1: Suspended | Layer 2: At-Risk Available | Layer 2: Suspended | Layer 3: Passive Income Available | Layer 3: Suspended | Deductible |
|--------|----------|------------------------|--------------------|---------------------------|--------------------|----------------------------------|--------------------|-----------:|
| [Entity A] | $X | $X | $X | $X | $X | $X | $X | $X |
| [Entity B] | $X | $X | $X | $X | $X | $X | $X | $X |

**Verification protocol:**
1. For each K-1 entity, compute outside basis using the prior year basis worksheet and current
   year K-1 items (income allocations, contributions, distributions, debt changes)
2. Apply Layer 1: compare loss to basis. If loss exceeds basis, suspend the excess at Layer 1.
3. For losses passing Layer 1, compute the at-risk amount (Form 6198). Apply Layer 2.
4. For losses passing Layer 2, determine if the activity is passive or non-passive. If passive,
   apply Layer 3 (Form 8582). If the taxpayer materially participates, Layer 3 does not apply.
5. Track the suspended amount at each layer separately — this determines what restores usability.

**Common errors:**
- Lumping all three layers together into a single "suspended loss" number (cannot determine
  how to unlock the loss without knowing which layer suspended it)
- Confusing S-Corp basis rules with partnership basis rules (S-Corp: entity-level debt does NOT
  increase shareholder basis; partnership: partner's share of entity debt DOES increase basis)
- Applying section 469 before section 465 (at-risk must be applied first)
- Not updating basis for debt changes reported on K-1 (partnerships: compare Schedule K-1
  line 20 footnotes for recourse and nonrecourse debt allocations year over year)
- Forgetting that suspended losses at all three layers are released on complete disposition
  of the partnership/S-Corp interest in a fully taxable transaction
- Not tracking the qualified nonrecourse financing exception for real estate partnerships
  (this financing increases at-risk amount, which is unique to real estate)

---

## Reconciliation Protocol

**Perform this reconciliation for EVERY carryforward item at three checkpoints:**

### Checkpoint 1: Prior Year Return Review
1. Open the prior year filed return
2. Extract every carryforward amount from its source form/line
3. Enter as "Beginning Balance" in the ledger
4. Cross-reference against the prior year analysis file (if it exists)
5. Flag any discrepancy between the filed return and the analysis

### Checkpoint 2: Current Year Input Verification
1. When preparing the current year return, verify that every beginning balance in the
   tax software or Aiwyn input matches the ledger
2. If using a CPA's workpapers, verify their beginning balances match yours
3. Flag any item in the ledger that is NOT reflected in the current year input

### Checkpoint 3: Current Year Output Validation
1. After the draft return is prepared, extract every carryforward amount
2. Verify the ending balance computation: Beginning + Generated - Used = Ending
3. Cross-reference against the draft analysis file
4. Flag any item that was used without documentation of the triggering event

---

## Common Errors to Watch For

1. **Wrong character (ST vs LT):** The single most common carryforward error. CPAs and
   software frequently collapse ST and LT capital losses into a single number.

2. **Failure to track section 1014 step-up:** When a taxpayer inherits an asset, the basis
   steps up to FMV at date of death. If the inherited asset was the source of unrealized
   losses that contributed to a carryforward, the step-up may eliminate or reduce the
   carryforward. This is frequently missed.

3. **Failure to release passive losses on disposition:** When rental property or a passive
   business interest is sold in a fully taxable transaction, ALL accumulated suspended
   passive losses must be released. This is commonly worth $5,000-$50,000+ and is
   routinely missed by CPAs who do not track per-activity suspended losses.

4. **Applying NOL to 100% of income instead of 80%:** Post-TCJA NOLs can only offset 80%
   of taxable income. Using 100% understates the tax.

5. **Losing charitable carryforwards to expiration:** The 5-year clock is absolute. If high
   AGI-percentage contributions are not tracked by year of origin, carryforwards expire
   silently.

6. **Forgetting home office carryforward after method switch:** Switching from actual to
   simplified method forfeits the carryforward from the actual method.

7. **Double-counting:** Using a carryforward that was already consumed in a prior year.
   This happens when the ledger is not maintained and amounts are pulled from the wrong
   year's return.

8. **Ignoring section 465 before section 469:** At-risk rules apply first. A loss may be
   suspended under section 465 before passive activity rules are even evaluated. If the
   at-risk limitation is skipped, the passive loss carryforward is overstated.
