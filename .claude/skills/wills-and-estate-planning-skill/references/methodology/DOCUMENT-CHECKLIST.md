# Estate Planning Document Checklist and Evidence Hierarchy

Estate planning is document-heavy. The right plan depends on what the deeds, beneficiary
forms, policies, entity agreements, and existing signed documents actually say, not what
anyone remembers them saying.

This file is the routing layer for:

- `analyses/document-acquisition-plan.md`
- `analyses/evidence-confidence-map.md`
- `deliverables/document-package-index.md`

---

## Evidence Hierarchy

| Level | Description | Examples | Reliability |
|-------|-------------|----------|-------------|
| `A` | Controlling signed legal record or institutional record | Signed will, deed, trust, beneficiary confirmation, policy contract, account statement | Highest |
| `B` | Secondary official or institution-generated record | Downloaded summary from custodian portal, county tax card, secretary of state filing, mortgage statement | High |
| `C` | Prepared summary / spreadsheet / family notes | Net-worth spreadsheet, adviser memo, inventory list | Medium |
| `D` | Memory or oral statement only | "I think my brother is the beneficiary" | Low |

Default rule: do not finalize a recommendation that depends on `D` evidence when `A` or `B`
evidence is realistically obtainable.

---

## Everyone: Core Documents to Request

| Document | Why it matters |
|----------|----------------|
| Prior will(s), codicils, revocations, and trust documents | Baseline architecture, stale provisions, governing law |
| Durable financial POA | Incapacity authority and bank-operability |
| Healthcare proxy / advance directive / living will / HIPAA | Medical decision-making and end-of-life instructions |
| Marriage certificate, divorce decree, prenup / postnup | Spousal-rights baseline and beneficiary cleanup |
| Government ID / legal names / domicile evidence | Correct identification and governing-state analysis |
| Recent tax returns | Asset discovery, entity discovery, and transfer-tax clues |
| Account statements for all major financial accounts | Ownership, titling, approximate value, institution details |
| Beneficiary confirmations for retirement, insurance, annuities, TOD/POD | Often the real transfer mechanism |
| Life insurance policy contracts and beneficiary endorsements | Coverage, ownership, and tax/liquidity structure |
| Real-estate deeds and mortgage documents | Title, survivorship, trust funding, ancillary probate risk |

---

## People and Family-Structure Documents

| Document | Trigger |
|----------|---------|
| Birth certificates / adoption orders / guardianship papers | Minor-child planning, kinship complexity |
| Death certificate of prior spouse or beneficiary | Portability, DSUE, beneficiary cleanup |
| Support / custody orders | Divorce, blended-family, dependent planning |
| Special-needs benefit documentation | SNT / outright-distribution risk |
| Immigration / citizenship records if relevant | Non-citizen spouse or foreign-heir planning |

---

## Asset and Liability Documents

### Financial Accounts

| Document | What to extract |
|----------|-----------------|
| Brokerage statement | Registration, TOD, margin, concentrated positions, cost-basis clues |
| Bank statement | Ownership, POD, cash liquidity |
| 401(k) / 403(b) / 457 / IRA statement | Beneficiary designations, approximate balances, inherited IRA status |
| HSA / 529 / annuity statement | Beneficiary / successor-owner structure |
| Stock-plan materials | RSUs, options, deferred comp, concentration risk |

### Real Estate

| Document | What to extract |
|----------|-----------------|
| Recorded deed | Title form, survivorship language, trust ownership |
| Property tax bill | Situs, assessed value, mailing address clues |
| Mortgage / HELOC statements | Debt pressure and lender contact path |
| HOA / co-op docs | Restrictions affecting transfer / occupancy |
| TOD deed / lady-bird deed if any | Probate-avoidance mechanism and state-law implications |

### Business / Private Investment

| Document | What to extract |
|----------|-----------------|
| Operating agreement / partnership agreement / shareholder agreement | Transfer restrictions, buy-sell, valuation rights, death-trigger clauses |
| Cap table and stock certificates | Ownership percentages and transfer mechanics |
| Buy-sell agreement and funding evidence | Liquidity plan on death/disability |
| Promissory notes / intra-family loans | Estate inclusion and equalization issues |
| K-1s / private-fund statements | Hidden assets, capital-call risk, GP/LP structure |

### Insurance and Benefits

| Document | What to extract |
|----------|-----------------|
| Life insurance policy | Owner, insured, beneficiary, loan balance, term/permanent type |
| Disability insurance | Income-continuity plan for incapacity |
| Long-term-care policy | Benefit periods and planning assumptions |
| Pension election paperwork | Survivor options and annuity form |

### Digital / Special Assets

| Document | What to extract |
|----------|-----------------|
| Password-manager emergency-access setup | Whether access continuity exists |
| Crypto custody records | Custodian vs self-custody, access model |
| Domain registrar / creator-platform / royalty statements | Monetizable digital rights |
| Firearms trust / NFA paperwork | Transfer constraints and criminal-risk issues |

---

## Document Checklist by Planning Pattern

### Minor-Child Planning

- Existing guardianship nominations
- 529 statements and successor-owner designations
- Life insurance with beneficiary details
- Any UTMA / UGMA accounts
- School / medical emergency authorizations if parents travel often

### Blended Family

- Prior divorce judgments
- Prenup / postnup
- Separate-property evidence
- Existing spousal waivers
- Retirement-plan beneficiary forms
- Any prior family settlement agreements

### High-Net-Worth / Transfer-Tax Planning

- Gift-tax returns (Forms 709)
- Prior estate-tax return and portability filing, if applicable
- Appraisals, valuation reports, and entity agreements
- Existing irrevocable-trust instruments
- Premium-funding history for ILITs / split-dollar / private insurance structures

### Aging / Incapacity / Medicaid Pressure

- Current POA and healthcare documents
- Long-term-care coverage details
- Home-care contracts / caregiver agreements
- Prior gifts or asset transfers in lookback window
- Account-operability evidence with agent access constraints

---

## Missing-Document Acquisition Workflow

1. Build a master list of every asset, liability, person, and legal document mentioned.
2. Mark each item `A`, `B`, `C`, or `D` evidence quality.
3. Prioritize retrieval in this order:
   - beneficiary forms
   - deeds / titles
   - existing estate docs
   - insurance / retirement statements
   - business-transfer restrictions
4. For every missing document, record:
   - who likely has it
   - how to request it
   - whether it is legally controlling or merely helpful
   - what planning decisions are blocked without it
5. If a critical document cannot be obtained, downgrade confidence and say so explicitly in the plan report.

---

## Acquisition Targets by Source

| Source | Typical documents |
|--------|-------------------|
| Employer HR / benefits portal | 401(k), life insurance, deferred comp, pension elections |
| Broker / custodian portal | account registration, TOD, beneficiary confirmations |
| County recorder / clerk | deeds, TOD deeds, recorded trust transfers |
| Lawyer who drafted prior plan | signed originals, drafts, memo, execution package |
| Insurance carrier | ownership / beneficiary endorsement, premium history |
| CPA / bookkeeper | gift-tax returns, K-1s, entity returns |
| Business counsel | operating agreement, shareholder restrictions, buy-sell |
| Secretary of State / business registry | entity existence and public filing details |

---

## Output Template — `analyses/evidence-confidence-map.md`

```markdown
# Evidence Confidence Map

| Item | Current evidence level | Best available source | Blocks what decision? | Next action |
|------|------------------------|-----------------------|-----------------------|------------|
| 401(k) beneficiary | D | Employer benefits portal | beneficiary coherence | obtain portal confirmation |
| Florida condo deed | B | County recorder certified copy | ancillary probate / TOD options | pull recorded deed |
```

---

## Output Template — `analyses/document-acquisition-plan.md`

```markdown
# Document Acquisition Plan

## Critical Missing Documents
- [Document] — why it matters, who likely has it, how to obtain it

## High-Priority But Not Blocking
- ...

## Nice To Have
- ...

## Retrieval Queue by Institution
1. ...
2. ...
```

---

## Operating Rule

Do not confuse a beautiful planning memo with a verified plan.

If the deed, beneficiary form, or trust schedule has not been seen, treat the point as
unverified and say so.
