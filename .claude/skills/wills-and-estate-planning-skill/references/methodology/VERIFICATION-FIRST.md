# Verification-First Protocol

Estate planning combines a lot of **evergreen method** with a lot of **volatile law**.
The method changes slowly. The law does not.

This skill should therefore behave like the tax skill: use the evergreen kernel and
operators from memory, but treat live legal/tax figures and state-specific execution
rules as **must-verify** items.

---

## Core Rule

**Do not give a live estate-planning recommendation that depends on a volatile number,
threshold, filing deadline, or state-specific rule until it has been verified from a
primary official source and logged in `analyses/official-source-log.md`.**

Examples:

- Good from memory: "Beneficiary designations usually override wills."
- Not good from memory: "Washington's estate-tax exclusion is X in 2026."
- Good from memory: "A non-citizen spouse often requires QDOT analysis."
- Not good from memory: "The 2026 annual exclusion to a non-citizen spouse is X."

---

## Evergreen vs. Volatile

### Evergreen Method

These are generally stable and can be applied without live research:

- Will/trust/beneficiary/titling coherence
- Incapacity-first planning
- Basis step-up vs. transfer-tax tradeoff framing
- Blended-family QTIP logic
- Vulnerable-heir routing
- Liquidity-at-death analysis
- Family communication and conflict minimization
- Need for attorney review and execution formalities

### Volatile Current-Law Items

These require verification:

- Federal estate, gift, and GST exclusion amounts
- Annual gift exclusion and non-citizen-spouse annual exclusion
- State estate and inheritance tax thresholds, rates, cliffs, portability, and filing dates
- Electronic-will, remote-online-notarization, and witness requirements
- TOD deed / transfer-on-death registration / Lady Bird deed availability
- Common-law marriage recognition and scope
- Elective-share percentages and augmented-estate rules
- No-contest-clause enforceability
- Medicaid figures and state timing rules
- POLST / MOLST naming and workflow in the user's state
- State small-estate affidavit thresholds
- Washington capital-gains-tax thresholds and rates
- ATF/NFA transfer procedures if regulated firearms are involved

---

## Primary Source Hierarchy

Use sources in this order:

1. Federal agency instructions, forms, bulletins, notices, revenue procedures, and statutes
2. State tax department, court administration, or health department pages and current form instructions
3. State statutes or official administrative rules
4. Uniform Law Commission pages for uniform-act adoption tracking, then confirm with state law if it matters to the recommendation

Avoid relying on:

- Secondary law-firm summaries if an official source exists
- Old IRS FAQ pages when later IRS instructions or revenue procedures supersede them
- Crowd-sourced tables with no publication date
- Generic estate-planning blog posts

---

## Mandatory Verification Triggers

Verify live whenever the plan depends on any of the following:

1. **Federal transfer-tax projections**
   - exclusion amount
   - annual exclusion
   - non-citizen spouse exclusion
   - portability / DSUE mechanics
   - Form 706 / 709 filing timing

2. **State tax projections**
   - estate or inheritance tax threshold
   - rates
   - cliff rules
   - portability
   - nonresident real-property exposure

3. **State execution and probate mechanics**
   - will witness count
   - notarization requirement
   - self-proving affidavit rules
   - holographic will recognition
   - electronic will / remote execution rules
   - small-estate procedure

4. **State property-transfer shortcuts**
   - TOD deed availability
   - enhanced life estate / Lady Bird deed availability
   - transfer-on-death registration for vehicles or securities

5. **Family-status and spousal-rights law**
   - common-law marriage
   - elective share
   - community property treatment
   - homestead restrictions
   - no-contest enforceability

6. **Healthcare / incapacity specifics**
   - POLST vs. MOLST naming
   - mental-health-directive statute
   - Medicaid lookback / CSRA / MMNA figures
   - medical-aid-in-dying legality

7. **Specialty assets**
   - ATF/NFA transfer procedure
   - state firearms restrictions
   - digital-fiduciary statute status
   - foreign-property local-law forced-heirship questions

---

## Official Source Log

Before finalizing a recommendation, create or update `analyses/official-source-log.md`
using a table like this:

```markdown
| Topic | Jurisdiction | Question | Official source | Date verified | Result | Notes |
|-------|--------------|----------|-----------------|---------------|--------|-------|
| Estate tax exclusion | Federal | 2026 BEA | IRS news release + Rev. Proc. 2025-32 | 2026-04-16 | $15,000,000 | Use for 2026 deaths |
| Estate tax exclusion | New York | 2026 NY exclusion | NY Dept. of Taxation estate tax page | 2026-04-16 | $7,350,000 | Check cliff at 105% |
```

If a source is not yet updated for the current year:

- say that explicitly,
- log the latest official published number,
- mark the issue for attorney/state-specific follow-up,
- do not silently extrapolate.

---

## Known Baselines Verified On 2026-04-16

These are safe starting points, not a substitute for re-checking when the user's
jurisdiction or fact pattern makes them outcome-determinative.

### Federal

- **Basic exclusion amount for 2026 deaths:** `$15,000,000`
  - IRS news release: `https://www.irs.gov/newsroom/irs-releases-tax-inflation-adjustments-for-tax-year-2026-including-amendments-from-the-one-big-beautiful-bill`
- **Annual gift exclusion for 2026:** `$19,000`
  - IRS Rev. Proc. 2025-32 § 4.42(1): `https://www.irs.gov/pub/irs-drop/rp-25-32.pdf`
- **Annual exclusion for gifts to a non-citizen spouse for 2026:** `$194,000`
  - IRS news release above
  - IRS Rev. Proc. 2025-32 § 4.42(2)
- **Nonresident noncitizen surviving spouse and portability:** generally cannot use DSUE except to the extent a treaty allows
  - Form 706 instructions: `https://www.irs.gov/instructions/i706/ch01.html`

### New York

- **2026 basic exclusion amount:** `$7,350,000`
  - NY Department of Taxation estate-tax page:
    `https://www.tax.ny.gov/pit/estate/etidx.htm`
- **Cliff / 105% phaseout mechanics:** confirm against current NY technical guidance
  - NY technical memo:
    `https://www.tax.ny.gov/pdf/memos/estate_%26_gift/m14_6m.pdf`
- **Current ordinary will-execution baseline:** EPTL 3-2.1 governs paper wills and notes electronic-will language as effective December 12, 2027
  - NY Senate statute page:
    `https://www.nysenate.gov/legislation/laws/EPT/3-2.1`

### Washington

- **2026 filing threshold / exclusion amount:** `$3,076,000`
  - WA DOR estate-tax tables:
    `https://dor.wa.gov/taxes-rates/other-taxes/estate-tax-tables`
- **No portability for WA estate tax**
  - WA DOR FAQ:
    `https://dor.wa.gov/taxes-rates/other-taxes/estate-tax/estate-tax-faq`
- **Top WA estate-tax rate after July 1, 2025:** `35%`
  - WA DOR estate-tax tables above
- **Washington capital-gains tax for tax year 2025 and later:** `7%` on first `$1,000,000` of taxable Washington capital gains and `9.9%` above that
  - WA DOR special notice:
    `https://dor.wa.gov/forms-publications/publications-subject/special-notices/new-tiered-rates-washingtons-capital-gains-tax`
- **Electronic wills available for decedents dying on or after January 1, 2022**
  - RCW ch. 11.12:
    `https://app.leg.wa.gov/rcw/default.aspx?cite=11.12&full=true&pdf=true`

### Massachusetts

- **Estate-tax threshold:** `$2,000,000`
  - Mass.gov estate-tax page:
    `https://www.mass.gov/estate-tax`
  - Mass.gov estate-tax guide:
    `https://www.mass.gov/info-details/massachusetts-estate-tax-guide`
- **Will execution baseline:** signed by the testator and by at least two witnesses
  - M.G.L. ch. 190B § 2-502:
    `https://malegislature.gov/Laws/GeneralLaws/PartII/TitleII/Chapter190B/Section2-502`
- **Self-proved will mechanism:** available under M.G.L. ch. 190B § 2-504
  - `https://malegislature.gov/Laws/GeneralLaws/PartII/TitleII/Chapter190B/Section2-504`

### California

- **Attested will baseline:** writing + signature + at least two same-time witnesses, with a clear-and-convincing-evidence cure if formal execution fails
  - Probate Code § 6110:
    `https://leginfo.legislature.ca.gov/faces/codes_displaySection.xhtml?lawCode=PROB&sectionNum=6110.`
- **Holographic will baseline:** signature and material provisions in the testator's handwriting
  - Probate Code § 6111:
    `https://leginfo.legislature.ca.gov/faces/codes_displaySection.xhtml?lawCode=PROB&sectionNum=6111.`
- **Financial POA baseline:** notary or two qualified witnesses
  - Probate Code § 4121:
    `https://leginfo.legislature.ca.gov/faces/codes_displaySection.xhtml?lawCode=PROB&sectionNum=4121.`
- **Statutory AHCD form points to notary-or-two-qualified-witness execution**
  - Probate Code § 4701:
    `https://leginfo.legislature.ca.gov/faces/codes_displaySection.xhtml?lawCode=PROB&sectionNum=4701.`

### Florida

- **Will execution baseline:** writing, signature, and at least two attesting witnesses, with the witnesses signing in the presence of the testator and each other
  - Fla. Stat. § 732.502:
    `https://www.flsenate.gov/Laws/Statutes/2025/732.502`
- **Self-proof baseline:** Fla. Stat. § 732.503 includes the current statutory self-proof form and online-notarization language
  - `https://www.flsenate.gov/Laws/Statutes/2025/732.503`

### Texas

- **Attested will baseline:** writing, signature, and attestation by two or more credible witnesses at least 14 years old
  - Estates Code § 251.051:
    `https://statutes.capitol.texas.gov/DocViewer.aspx?DocKey=ES%2FES.251&ExactPhrase=False&HighlightType=1&Phrases=probate%7Crevocation&QueryText=probate+revocation`
- **Holographic will baseline:** wholly in the testator's handwriting and not required to be attested by subscribing witnesses
  - Estates Code § 251.052:
    same source as above
- **Self-proving affidavit rules:** Estates Code §§ 251.103 and 251.104
  - same source as above

### Rhode Island

- **2026 estate-tax threshold:** `$1,838,056`
  - RI Division of Taxation estate-tax page:
    `https://tax.ri.gov/tax-sections/estate-tax`

### Maine

- **2026 estate-tax exclusion amount:** `$7,160,000`
  - Maine Revenue Services estate-tax page:
    `https://www.maine.gov/revenue/taxes/income-estate-tax/estate-tax-706me`

### Minnesota

- **Minnesota state filing threshold / state exclusion:** `$3,000,000`
  - Minnesota DOR estate-tax filing requirement page:
    `https://www.revenue.state.mn.us/estate-tax-filing-requirement`

### District of Columbia

- **Latest official published exclusion on 2026-04-16:** `$4,873,200` for 2025 deaths
  - DC OTR estate-tax information page:
    `https://otr.cfo.dc.gov/page/dc-estate-inheritance-and-fiduciary-tax-information`
  - 2025 D-76 booklet:
    `https://otr.cfo.dc.gov/sites/default/files/dc/sites/otr/publication/attachments/2025_D-76_v1.0_Final_041825.pdf`
- **Action:** confirm the 2026 booklet before using a 2026 DC threshold in advice

### Connecticut

- **Latest official published exemption on 2026-04-16:** `$13.99 million` for 2025
  - CT DRS estate-and-gift-tax information page:
    `https://portal.ct.gov/drs/individuals/individual-income-tax-portal/estate-and-gift-taxes/tax-information`
- **Action:** confirm 2026 DRS guidance before using a 2026 Connecticut threshold

### New Jersey

- **No New Jersey estate tax for deaths on or after January 1, 2018**
  - NJ Division of Taxation inheritance and estate tax page:
    `https://www.nj.gov/treasury/taxation/inheritance-estate/inheritance.shtml`

---

## Handling Source Conflicts

If official sources conflict:

1. Prefer the newer official instruction or revenue procedure over an older FAQ.
2. Note the conflict explicitly in `analyses/official-source-log.md`.
3. Treat the conflict itself as an attorney follow-up item.
4. Avoid presenting a disputed rule as settled.

Example:

- IRS FAQ pages may still describe a pre-OBBBA 2026 sunset.
- Later IRS 2026 inflation-adjustment guidance and Rev. Proc. 2025-32 reflect the newer law.
- Use the newer IRS materials and note the older FAQ as stale.

---

## Red-Flag Phrases

If you are about to say any of the following, stop and verify first:

- "In your state, the threshold is..."
- "That clause is enforceable in your state..."
- "You can sign electronically in your state..."
- "A TOD deed is available in your state..."
- "The 2026 amount is..."
- "Washington/New York/Massachusetts/DC currently..."
- "A non-citizen spouse can/cannot use portability..."
