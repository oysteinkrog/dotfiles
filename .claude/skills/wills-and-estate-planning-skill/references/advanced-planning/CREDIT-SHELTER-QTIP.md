# Credit-Shelter Trust + QTIP (Marital Trust Architecture)

The classic two-trust structure for married couples: at first spouse's death, assets split into a Credit-Shelter Trust ("Family Trust" or "Bypass Trust" or "B Trust") and a QTIP marital trust ("A Trust"). It can preserve state or federal transfer-tax capacity, lock in remainder beneficiaries, and protect the survivor, but it should be modeled rather than deployed automatically.

## When to Use

**Strong candidates when:**
- State estate tax with non-portable exemption (NY, MA, IL, OR, MN, etc.) — preserve both state exemptions
- Blended family — protect first-marriage children's eventual inheritance
- Estate tax exposure on couple's combined assets above either spouse's individual exemption
- Spouse with vulnerable heir from prior relationship
- Concerns about surviving spouse's future remarriage / estate planning

**Often lower-yield or unnecessary when:**
- Estate well below the federal single-person exclusion, and any married-couple exposure is still well below the combined shelter likely to be preserved and available
- No state estate tax
- All children mutual; full trust between spouses; portability sufficient
- Surviving spouse capable + no vulnerable beneficiaries

## Architecture

```
At first spouse's death:
                         ┌─────────────────────────────────┐
                         │     Decedent's Half of Estate   │
                         │              ($X)                │
                         └─────────────────┬───────────────┘
                                           ↓
                ┌──────────────────────────┴──────────────────────────┐
                ↓                                                     ↓
    ┌─────────────────────┐                           ┌────────────────────────┐
    │  Credit Shelter     │                           │   QTIP Marital Trust   │
    │    "B Trust"        │                           │      "A Trust"         │
    │                     │                           │                        │
    │  Funded up to       │                           │  Funded with remainder │
    │  applicable         │                           │  ($X minus B Trust)    │
    │  exemption          │                           │                        │
    │                     │                           │                        │
    │  Spouse: income +   │                           │  Spouse: ALL income    │
    │  HEMS principal     │                           │  for life (mandatory)  │
    │                     │                           │  + HEMS principal      │
    │  Children at        │                           │                        │
    │  spouse's death:    │                           │  Children at spouse's  │
    │  Federal & state    │                           │  death: included in    │
    │  estate-tax FREE    │                           │  spouse's estate       │
    │                     │                           │  (often preserves a    │
    │                     │                           │   later basis          │
    │                     │                           │   adjustment)          │
    └─────────────────────┘                           └────────────────────────┘
```

## Credit Shelter Trust (B Trust) — The Tax Saver

**Funding amount:** Up to the applicable exemption (federal or state, whichever is smaller and used).

**Purpose:** Use the deceased spouse's exemption. Without it (just leaving everything outright to spouse), the deceased's exemption is wasted in non-portable states.

**Tax treatment:**
- At funding: uses deceased's federal/state exemption; no estate tax
- During spouse's life: spouse can receive income + HEMS principal
- At spouse's death: remainder passes to children FREE of estate tax (it bypassed the survivor's estate)

**Trade-off:** No second step-up in basis on B Trust assets at second death. Assets keep the basis from first death. For estates that won't owe federal estate tax under $15M, this can cost more in capital gains than it saves in estate tax.

## QTIP Marital Trust (A Trust) — The Spouse Protector

**Qualified Terminable Interest Property** trust that generally qualifies for the federal marital deduction when the federal requirements are met; state-only QTIP elections and noncitizen-spouse QDOT issues require separate analysis.

**Required elements (per IRC §2056(b)(7)):**
- Surviving spouse entitled to ALL income at least annually
- No one (including spouse) can have power to direct property to anyone other than spouse during spouse's lifetime
- Election made on Form 706

**Spouse's rights:**
- All income for life (mandatory)
- Principal for HEMS (Health, Education, Maintenance, Support — IRS-safe standard)
- Principal for any standard the grantor specifies

**At spouse's death:**
- Remainder passes to first spouse's chosen beneficiaries (typically first-marriage children)
- QTIP assets included in surviving spouse's taxable estate (uses spouse's exemption)
- Includible appreciated assets often preserve a later basis-adjustment opportunity (advantage over B Trust)

## When to Use Which

| Situation | Funding Strategy |
|-----------|------------------|
| Federal estate tax exposure, state estate tax, blended family | Usually model some mix of B Trust and QTIP, but optimize basis, survivor access, and control rather than funding by reflex |
| Federal exposure only, no state estate tax | Model outright, QTIP, and B-Trust paths; a pure exemption-maximizing B Trust is not automatic because basis tradeoffs may dominate |
| State estate tax only (no federal exposure under $15M) | State-exemption funding often deserves a serious look, but basis and liquidity need to be modeled alongside the state-tax savings |
| No estate tax, blended family | QTIP or another protected-remainder structure often deserves first consideration; outright-to-spouse is frequently too exposed |
| No estate tax, no blended family | Simple outright or marital-trust planning plus portability is often enough; confirm before adding a bypass trust just because the template exists |

## Disclaimer Trust Alternative

Instead of mandatory funding, give surviving spouse the option to **disclaim** assets into the B Trust within 9 months of death. Surviving spouse decides based on tax law and family situation at the time.

**Pros:** Maximum flexibility post-mortem.
**Cons:** Requires disclaimer planning; spouse may not understand the choice.

Often preferred for couples whose tax exposure is uncertain (e.g., Tier 3 borderline).

## Reverse QTIP for GST

If the deceased spouse has unused GST exemption that should be applied to QTIP assets (which are typically grandchildren-eligible at second death), elect "reverse QTIP" treatment on Form 706. Treats deceased as the transferor for GST purposes.

## Funding Mechanics

The trust document specifies the formula:

- **Pecuniary formula:** B Trust funded with assets equal in value to the applicable exemption (e.g., $7.35M in NY). QTIP gets the rest.
- **Fractional formula:** B Trust gets a fraction of the residue (e.g., 40% if exemption = 40% of estate).
- **Reverse-Marital formula:** QTIP gets the exemption amount; B Trust gets the rest.

The choice has tax consequences (step-up basis allocation, post-mortem appreciation). Coordinate with attorney + CPA.

## Trustee Selection — Critical for Blended Families

In a blended-family QTIP, surviving spouse + first-marriage children have inherently adverse interests (spouse wants principal access; children want preservation).

**Bad: surviving spouse as sole trustee.** Spouse has incentive to spend principal aggressively under HEMS standard.

**Better:**
- **Independent corporate trustee** for QTIP — neutral, can interpret HEMS objectively
- **Family member trustee from spouse's side** (for spouse's comfort) + **independent trustee** (for children's protection)
- **Trust protector** with power to remove trustees and adapt provisions

## Common Failure Modes

1. **No Form 706 filed** — both portability AND reverse-QTIP elections lost
2. **Wrong funding formula** — basis-step-up suboptimal
3. **Surviving spouse as sole QTIP trustee** in blended family — abuse risk
4. **Mandatory income provision** missing — fails QTIP qualification, full inclusion in deceased's estate
5. **No trust protector** — provisions can't adapt to changed law/circumstances
6. **Principal distributions to spouse exceed HEMS** — IRS may include in spouse's estate as completed gift to spouse
7. **B Trust funding wastes step-up** for couples below federal exemption — would have been better to take all step-up at second death

## Worked Example: Massachusetts Couple, $4M

- John dies first. For this simplified example, assume **John's taxable estate is $4M** and Mary's separate estate is negligible. Massachusetts exemption = $2M.
- B Trust funded with $2M (uses the state exemption; federal portability also elected for federal preservation where appropriate).
- QTIP funded with the remaining $2M (assuming the trust qualifies for the intended federal and Massachusetts marital-deduction treatment and the required elections are made, the QTIP portion can defer first-death tax).
- **Without** B-Trust funding: everything passes through the marital-deduction path. At Mary's later death, her taxable estate is $4M. With a $2M Massachusetts exemption, roughly $2M remains exposed, producing about **$182K** of Massachusetts estate tax under the schedule used in this example.
- **With** the $2M B Trust funded at John's death: the bypass trust stays outside Mary's estate. At Mary's later death, the taxable estate is roughly the $2M QTIP portion, which can be offset by Mary's own $2M Massachusetts exemption. Result: **roughly $0 Massachusetts estate tax** in this simplified no-growth example.
- Real files still require modeling for appreciation, spending, QTIP elections, and any Massachusetts-only QTIP differences.

This is why credit-shelter planning still matters in MA, NY, OR, IL even though federal exemption is $15M.

## State-by-State Adoption

- **NY**: Used aggressively due to non-portable $7.35M exemption + cliff
- **MA**: Used for $2M+ estates given $2M non-portable exemption
- **OR**: Used for $1M+ estates (lowest exemption)
- **IL, MN**: Common
- **TX, FL, CA (no state estate tax)**: Less common; only if federal exposure
