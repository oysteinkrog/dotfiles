# Subagent: Beneficiary Audit

Systematically audits all beneficiary designations for coherence with will, trust, and overall estate plan.

## Why This Matters

Beneficiary designations OVERRIDE will and trust provisions for the assets they control. A will leaving "all to my spouse" doesn't help if the 401(k) still names an ex-spouse.

Beneficiary coordination is the #1 most common estate-planning failure.

## Inputs

- **List of accounts:** from intake, including type, institution, approximate balance
- **Will provisions:** who inherits what
- **Trust provisions (if applicable):** who inherits, through what structure
- **Current beneficiary statements** (if available) for each account

## Audit Checklist

### Accounts to Audit

**Retirement accounts:**
- [x] 401(k) (current employer + any rollovers)
- [x] 403(b)
- [x] Traditional IRA
- [x] Roth IRA
- [x] SEP-IRA
- [x] SIMPLE IRA
- [x] Solo 401(k)
- [x] Pension / defined benefit
- [x] Cash balance plan
- [x] Deferred comp (457(b), NQDC)

**Life insurance:**
- [x] Group term (current employer)
- [x] Group term (prior employer still in force)
- [x] Individual term
- [x] Whole life / universal life
- [x] Variable life
- [x] Second-to-die / survivorship
- [x] Business key-person / buy-sell insurance

**Bank accounts:**
- [x] Checking (POD)
- [x] Savings (POD)
- [x] CDs (POD)
- [x] Money market (POD)

**Brokerage:**
- [x] Taxable brokerage (TOD)
- [x] Annuities (beneficiary)
- [x] Mutual fund accounts (TOD)

**Other:**
- [x] 529 plans (successor owner / beneficiary)
- [x] HSA
- [x] Savings bonds (beneficiary)
- [x] US Treasury Direct (beneficiary)
- [x] Crypto exchange accounts (beneficiary where available)
- [x] Stock options / RSUs (beneficiary)

**Real estate:**
- [x] TOD deed (in states that allow)

## For Each Account, Verify

1. **Primary beneficiary named?** — yes/no
2. **Contingent beneficiary named?** — yes/no
3. **Beneficiary is appropriate?** — current spouse? kids? trust?
4. **Beneficiary matches will/trust intent?** — no ex-spouses, no deceased, no irrelevant parties
5. **Trust named correctly?** — exact trust name + tax ID if post-death trust
6. **Per stirpes vs. per capita specified?** — especially if multiple primary beneficiaries
7. **Minor children not named directly** — use UTMA custodian or trust
8. **Tax optimization** — Roth vs. traditional, 10-year rule impact, QCD viability

## Common Issues to Flag

### Critical (Fix Immediately)
- Ex-spouse still named primary beneficiary
- Deceased person still named primary
- No beneficiary (default estate → probate)
- Minor child named directly (UTMA required or trust)
- Estate named as beneficiary (forces probate, accelerates tax)

### Important (Fix Soon)
- No contingent beneficiary
- Single primary without backup
- Trust named but not funded properly
- Spouse + contingent kids, but kids split incorrectly
- Beneficiary doesn't match will intent (unclear which governs)

### Optimization (Review)
- Retirement account to non-spouse triggers 10-year rule
- Large IRA could benefit from CRT beneficiary structure
- Life insurance in estate (no ILIT) for HNW
- No QCD strategy for charitable IRA beneficiary

### Special Situations
- Non-citizen spouse beneficiary (route to QDOT / treaty / marital-deduction analysis if estate-tax treatment matters)
- Disabled beneficiary named directly without special-needs / benefits-preservation review
- Beneficiary with addiction, creditor, or severe money-management risk named for outright distribution without discretionary-structure review
- Minor with UTMA release age at 18 or 21 (consider trust instead)

## Output Report Format

```markdown
# Beneficiary Audit — [User Name]

## Summary
- Accounts reviewed: [N]
- Critical issues: [N]
- Important issues: [N]
- Optimization opportunities: [N]

## Critical Issues

### Account: [Name / Institution]
- **Type:** 401(k)
- **Balance:** $[X]
- **Current primary:** [Ex-spouse name]
- **Current contingent:** [N/A]
- **Issue:** Ex-spouse from divorce 2019 still named; will leaves all to current spouse
- **Risk:** If death today, 401(k) goes to ex despite will
- **Fix:** Update beneficiary form immediately to current spouse; contingent to children per stirpes
- **Action:** Contact [plan administrator]; expected processing 1-2 weeks

[Additional critical issues...]

## Important Issues
[Same format, less urgent]

## Optimizations
[Same format, planning opportunities]

## Special Situations
[Disabled heirs, non-citizen spouse, etc.]

## Action Plan
1. [Immediate actions]
2. [Within 30 days]
3. [Within 90 days]
4. [Annual review going forward]
```

## Additional Considerations

### ERISA Spousal Consent
Plans subject to ERISA (most 401(k)s) require spousal consent to name non-spouse primary beneficiary. Verify:
- If spouse is primary: no issue
- If non-spouse is primary: spousal consent form required; confirm signed and on file

### Per Stirpes vs. Per Capita
Default varies by plan. Confirm desired:
- **Per stirpes:** if child dies before participant, child's children take their share
- **Per capita:** living descendants share equally, regardless of generation

### "Surviving Spouse" Clauses
Some accounts default to "current spouse at time of death" — may be ex-spouse if divorce not updated.

### Trust as Beneficiary
- Name specific trust: "The John Smith Revocable Trust dated 1/1/2024"
- Check tax implications (see-through trust rules for retirement plans)
- Conduit vs. accumulation trust impacts RMD tax treatment

## Deliverable

- `analyses/beneficiary-form-audit.md`
- updates to `deliverables/beneficiary-map.md`
- prioritized changes mirrored into `deliverables/beneficiary-change-packet.md` when action is required
- follow-up timing reflected in `deliverables/review-schedule.md`

## Cross-Reference

- Foundations: [BENEFICIARY-COORDINATION.md](../references/foundations/BENEFICIARY-COORDINATION.md)
- Anti-patterns: Beneficiary-related failure modes
- Templates: [BENEFICIARY-MAP.md](../assets/BENEFICIARY-MAP.md)
