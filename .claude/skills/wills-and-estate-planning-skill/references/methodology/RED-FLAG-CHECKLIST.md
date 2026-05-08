# Red Flag Checklist — Estate Planning Triage and Risk Scoring

Use this checklist during intake, document review, and final validation to classify
which issues are true planning emergencies, which are high-EV improvements, and which
are cleanup items that should not distract from the critical path.

This file is the routing layer for `analyses/red-flag-triage.md`.

---

## Severity Levels

| Severity | Meaning | Required action |
|----------|---------|-----------------|
| `CRITICAL` | Plan likely fails, or immediate harm could occur on death/incapacity | Surface immediately; do not bury later in the report |
| `HIGH` | Material wealth leakage, litigation risk, or major operational gap | Address in the current planning cycle |
| `MEDIUM` | Important but not catastrophic; optimize after core plan is coherent | Track in decision ledger and handoff packet |
| `CLEANUP` | Administrative polish, convenience, or quality-of-life improvement | Batch after critical / high issues |

---

## Critical Red Flags

| Red flag | Why it is critical | Minimum response |
|----------|--------------------|------------------|
| No durable POA or no healthcare directive for an adult with real assets or dependents | Incapacity can trigger conservatorship, blocked accounts, and medical conflict | Route immediately to incapacity module; flag in plan report and attorney brief |
| Minor children but no guardian nomination and no trust for inherited assets | Court may decide guardian; minors cannot manage inherited assets directly | Build guardian recommendation and minor-child trust structure |
| Beneficiary form names ex-spouse, deceased person, minor, or "estate" | Asset may pass contrary to intent, through probate, or with tax drag | Add to beneficiary-form audit and required update queue |
| Blended family with "everything to spouse" and no QTIP / protective design | First-marriage children can be unintentionally disinherited | Route to blended-family + QTIP analysis |
| Outright inheritance to disabled / means-tested-benefits beneficiary | Can destroy SSI / Medicaid / housing eligibility | Route to vulnerable-heirs + special-needs trust review |
| Strong evidence of coercion, sudden last-minute plan change, or questionable capacity | Will contest / undue-influence risk | Flag for attorney-controlled execution process with contemporaneous capacity record |
| Large digital / crypto exposure but no access map or recovery instructions | Assets may be practically unrecoverable | Build digital inventory and emergency access protocol |
| Family business / farm / concentrated illiquid estate with no liquidity plan | Forced sale risk to pay taxes, debts, or equalization obligations | Run liquidity analysis and funding / insurance / section 6166 review |
| Out-of-state real estate with no ancillary probate strategy | Multiple-state probate and title friction | Route to domicile + titling + trust funding / TOD analysis |
| Trust-centered plan but no funding path | Empty revocable trust does little or nothing | Create implementation ledger and funding checklist |

---

## High Red Flags

| Red flag | Why it matters | Required response |
|----------|----------------|------------------|
| Net worth near or above state estate-tax threshold | State transfer tax may dominate planning | Run state tax projection and verify live numbers |
| No successor agents / trustees / executors | Single-point-of-failure planning | Require at least one backup for every fiduciary role |
| Large appreciated low-basis assets being gifted below exemption without analysis | May burn step-up for no real transfer-tax benefit | Run step-up-vs-gifting analysis |
| Vacation home or family cabin left equally without governance mechanics | Partition / deadlock / maintenance warfare | Route to lumpy-asset division and LLC / buyout rules |
| Non-citizen spouse | QDOT / gift / portability rules can differ materially | Route to non-citizen spouse file and official-source verification |
| Gun collection or NFA items | Executor / heir transfer risk | Route to firearms reference and counsel-specialist flag |
| Foreign assets or foreign heirs | Local law, forced heirship, and compliance risk | Route to foreign-assets and cross-border review |
| Retirement accounts naming trust without see-through review | SECURE Act / conduit-vs-accumulation issues | Route to retirement-accounts analysis |
| Recent interstate move | Execution validity, homestead, elective share, and incapacity rules may shift | Route to domicile and state execution review |
| Document set older than 5 years plus major life event | Staleness likely means the plan tells the wrong story | Perform prior-plan gap analysis |

---

## Medium Red Flags

| Red flag | Why it matters | Response |
|----------|----------------|----------|
| No letter of instruction or emergency packet | Family may have legal plan but no practical roadmap | Generate operational deliverables |
| No family communication plan despite unequal treatment | Surprise accelerates litigation | Build family-meeting agenda and rationale memo |
| Personal-property wishes only in conversation | Sentimental asset disputes are common | Create personal-property memorandum |
| No regular review cadence | Good plan today becomes stale plan later | Add maintenance schedule |
| Asset inventory relies mostly on memory | Hidden accounts and liabilities get missed | Build evidence-confidence map and acquisition plan |

---

## Cleanup Items

| Item | Why it is cleanup |
|------|-------------------|
| Registry submission for advance directive where available | Useful, but not usually dispositive |
| Naming charity contingent gifts with exact EIN/legal name | Good hygiene once the core structure is set |
| Personal letters, ethical will, and legacy materials | Valuable, but secondary to legal-operational integrity |
| Formatting consistency across drafts and summaries | Important for handoff quality, not planning substance |

---

## Family-Conflict Trigger Set

Escalate conflict-prevention planning when any of the following are true:

- Unequal inheritance among siblings
- Blended family or second marriage
- Disinheritance or near-disinheritance
- Co-owned vacation property or family business
- One child is caregiver / one child is estranged
- Substance-use history, creditor problems, or unstable marriages
- A fiduciary choice is likely to be perceived as favoritism

Produce:

- `deliverables/family-meeting-agenda.md`
- `deliverables/conflict-prevention-plan.md`
- rationale entries in `analyses/decision-ledger.md`

---

## Execution-Risk Trigger Set

Escalate execution-formality review when any of the following are true:

- Domicile changed since the last plan
- The user wants a holographic, emergency, or bedside will
- The user wants remote signing / remote notarization
- The user is elderly, hospitalized, or has capacity concerns
- Real property sits in another state
- The plan depends on transfer-on-death deed availability

Produce:

- state-specific execution notes in `analyses/official-source-log.md`
- `deliverables/attorney-engagement-brief.md` section on execution priorities

---

## Document-Evidence Trigger Set

Escalate document acquisition when:

- The user is answering from memory about beneficiary forms or account titling
- Net worth estimate varies by more than 20% across sources
- There are undocumented private investments, loans, or partnership interests
- The user says "I think" or "probably" on beneficiary designations
- No one knows where deeds, policies, or original signed estate docs are

Produce:

- `analyses/document-acquisition-plan.md`
- `analyses/evidence-confidence-map.md`

---

## Output Template for `analyses/red-flag-triage.md`

```markdown
# Red Flag Triage

## Critical
- [Issue] — why it matters, what controls today, what must change now

## High
- [Issue] — planning response and attorney-review question

## Medium
- [Issue] — recommended improvement and timing

## Cleanup
- [Issue] — batch later

## Routing Decisions
- Tier:
- Loaded overlays:
- Loaded state / execution references:
- Loaded advanced-planning references:

## First 5 Actions
1. ...
2. ...
```

---

## Operating Rule

Do not let optimization work hide structural failure.

If a user has a $40 million GRAT question and an ex-spouse is still on the 401(k), the
beneficiary cleanup is still the more urgent issue.
