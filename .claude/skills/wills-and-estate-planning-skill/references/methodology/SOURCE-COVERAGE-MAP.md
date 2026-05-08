# Source Coverage Map

This file maps the major content clusters in
`/data/projects/je_private_skills_repo/multi_agent_wills_guide.md`
to the current skill so that coverage is auditable instead of implicit.

It is not a substitute for reading the guide. It is a proof-of-coverage index.

---

## How To Use This File

When a user asks whether a topic from the guide is covered:

1. Find the topic cluster below.
2. Pull the linked reference files.
3. If the recommendation depends on current-law facts, also pull
   [VERIFICATION-FIRST.md](VERIFICATION-FIRST.md).

---

## Coverage Map

| Guide Topic Cluster | Where It Lives In The Skill |
|---------------------|-----------------------------|
| Estate plan is more than a will | [SKILL.md](../../SKILL.md), [CORE-DOCUMENTS.md](../foundations/CORE-DOCUMENTS.md), [BENEFICIARY-COORDINATION.md](../foundations/BENEFICIARY-COORDINATION.md) |
| Document collection, evidence quality, source-of-truth discipline | [DOCUMENT-CHECKLIST.md](DOCUMENT-CHECKLIST.md), [PROJECT-SETUP.md](../../assets/PROJECT-SETUP.md), [document-organizer.md](../../subagents/document-organizer.md), [asset-discovery-auditor.md](../../subagents/asset-discovery-auditor.md) |
| Red-flag triage, issue severity, planning order of operations | [RED-FLAG-CHECKLIST.md](RED-FLAG-CHECKLIST.md), [COMPREHENSIVE-PLAN-REPORT.md](../../assets/COMPREHENSIVE-PLAN-REPORT.md) |
| Intestacy, probate, ancillary probate, privacy | [PROBATE-AND-INTESTACY.md](../foundations/PROBATE-AND-INTESTACY.md), [DOMICILE.md](../foundations/DOMICILE.md), state files |
| Federal estate, gift, portability, GST, basis step-up | [FEDERAL-TRANSFER-TAX.md](../foundations/FEDERAL-TRANSFER-TAX.md), [STEP-UP-BASIS-PLANNING.md](../advanced-planning/STEP-UP-BASIS-PLANNING.md), [DYNASTY-GST-PLANNING.md](../advanced-planning/DYNASTY-GST-PLANNING.md) |
| State estate and inheritance taxes, cliffs, portability, domicile | [STATE-ESTATE-TAX.md](../foundations/STATE-ESTATE-TAX.md), [states/README.md](../states/README.md), [NEW-YORK.md](../states/NEW-YORK.md), [WASHINGTON.md](../states/WASHINGTON.md), [OTHER-ESTATE-TAX-STATES.md](../states/OTHER-ESTATE-TAX-STATES.md) |
| State will-execution rules, self-proving, holographic / e-wills, TOD routing | [execution-formalities/README.md](../execution-formalities/README.md), [VERIFICATION-FIRST.md](VERIFICATION-FIRST.md), state files |
| Executor selection, trustee selection, fiduciary failure modes | [KERNEL.md](KERNEL.md), [ANTI-PATTERNS.md](../anti-patterns/ANTI-PATTERNS.md), [EXECUTOR-PLAYBOOK.md](../post-death/EXECUTOR-PLAYBOOK.md), [EXECUTOR-CHECKLIST.md](../../assets/EXECUTOR-CHECKLIST.md) |
| Guardian selection for minors | [MINOR-CHILDREN.md](../family-structures/MINOR-CHILDREN.md), [INTERVIEW-FLOW.md](INTERVIEW-FLOW.md), [INTAKE-QUESTIONNAIRE.md](../intake/INTAKE-QUESTIONNAIRE.md) |
| Specific bequests, residuary, per stirpes, anti-lapse, ademption, abatement, tax apportionment | [CORE-DOCUMENTS.md](../foundations/CORE-DOCUMENTS.md), [BENEFICIARY-COORDINATION.md](../foundations/BENEFICIARY-COORDINATION.md), [OPERATORS.md](OPERATORS.md) |
| Equal vs. equitable inheritance, conflict prevention, no-contest, mediation | [FAMILY-COMMUNICATION.md](../legacy-and-logistics/FAMILY-COMMUNICATION.md), [DISINHERITANCE.md](../family-structures/DISINHERITANCE.md), [ANTI-PATTERNS.md](../anti-patterns/ANTI-PATTERNS.md), [CONFLICT-PREVENTION-PLAN.md](../../assets/CONFLICT-PREVENTION-PLAN.md), [conflict-prevention-planner.md](../../subagents/conflict-prevention-planner.md) |
| Beneficiary designations overriding wills | [SKILL.md](../../SKILL.md), [BENEFICIARY-COORDINATION.md](../foundations/BENEFICIARY-COORDINATION.md), [beneficiary-audit.md](../../subagents/beneficiary-audit.md) |
| Married with mutual children | [TIER-2-MIDDLE-CLASS.md](../tiers/TIER-2-MIDDLE-CLASS.md), [CREDIT-SHELTER-QTIP.md](../advanced-planning/CREDIT-SHELTER-QTIP.md) |
| Single / no kids / aging alone | [SINGLE-NO-KIDS.md](../family-structures/SINGLE-NO-KIDS.md), [AGING-ALONE.md](../situations/AGING-ALONE.md) |
| Blended families, second marriages, stepchildren | [BLENDED-FAMILY.md](../family-structures/BLENDED-FAMILY.md), [CREDIT-SHELTER-QTIP.md](../advanced-planning/CREDIT-SHELTER-QTIP.md) |
| Divorce, separation, ex-spouse beneficiary traps | [DIVORCED-OR-SEPARATED.md](../family-structures/DIVORCED-OR-SEPARATED.md), [DIVORCE.md](../life-events/DIVORCE.md), [BENEFICIARY-COORDINATION.md](../foundations/BENEFICIARY-COORDINATION.md) |
| Unmarried partners, common-law marriage, nontraditional households | [UNMARRIED-PARTNERS.md](../family-structures/UNMARRIED-PARTNERS.md), [PROBATE-AND-INTESTACY.md](../foundations/PROBATE-AND-INTESTACY.md), [VERIFICATION-FIRST.md](VERIFICATION-FIRST.md) |
| Non-citizen spouse, QDOT, portability limits, NRA issues | [NON-CITIZEN-SPOUSE.md](../family-structures/NON-CITIZEN-SPOUSE.md), [FEDERAL-TRANSFER-TAX.md](../foundations/FEDERAL-TRANSFER-TAX.md) |
| Special needs beneficiaries, addiction, spendthrift, predatory spouse, bankrupt heirs | [VULNERABLE-HEIRS.md](../family-structures/VULNERABLE-HEIRS.md), [OPERATORS.md](OPERATORS.md) |
| Posthumous conception, frozen embryos, donor issues | [POSTHUMOUS-REPRODUCTION-CHILDREN.md](../family-structures/POSTHUMOUS-REPRODUCTION-CHILDREN.md) |
| Incarcerated heirs, foreign heirs, cross-border issues | [INCARCERATED-OR-FOREIGN-HEIRS.md](../family-structures/INCARCERATED-OR-FOREIGN-HEIRS.md), [FOREIGN-ASSETS.md](../assets/FOREIGN-ASSETS.md) |
| Revocable living trust, pour-over will, trust funding | [REVOCABLE-LIVING-TRUST.md](../advanced-planning/REVOCABLE-LIVING-TRUST.md), [ANTI-PATTERNS.md](../anti-patterns/ANTI-PATTERNS.md) |
| Trust funding and implementation discipline | [IMPLEMENTATION-LEDGER.md](../../assets/IMPLEMENTATION-LEDGER.md), [funding-checklist-generator.md](../../subagents/funding-checklist-generator.md), [COMPREHENSIVE-PLAN-REPORT.md](../../assets/COMPREHENSIVE-PLAN-REPORT.md) |
| Credit-shelter trust, bypass, QTIP, portability coordination | [CREDIT-SHELTER-QTIP.md](../advanced-planning/CREDIT-SHELTER-QTIP.md) |
| GRAT, IDGT, SLAT, QPRT, dynasty trust, GST | [GRAT-IDGT.md](../advanced-planning/GRAT-IDGT.md), [SLAT-QPRT.md](../advanced-planning/SLAT-QPRT.md), [DYNASTY-GST-PLANNING.md](../advanced-planning/DYNASTY-GST-PLANNING.md) |
| ILIT, liquidity, closely held business tax liquidity | [ILIT.md](../advanced-planning/ILIT.md), [PRIVATE-BUSINESS.md](../assets/PRIVATE-BUSINESS.md), [OPERATORS.md](OPERATORS.md) |
| Charitable planning: DAF, CRT, CLT, private foundation | [CHARITABLE-PLANNING.md](../advanced-planning/CHARITABLE-PLANNING.md) |
| Trust situs, decanting, protectors, dynasty jurisdictions | [TRUST-SITUS.md](../advanced-planning/TRUST-SITUS.md), [ASSET-PROTECTION.md](../advanced-planning/ASSET-PROTECTION.md) |
| Primary residence, homestead, TOD deed, reverse mortgage | [PRIMARY-RESIDENCE.md](../assets/PRIMARY-RESIDENCE.md), [REVERSE-MORTGAGES.md](../assets/REVERSE-MORTGAGES.md), [states/README.md](../states/README.md) |
| Vacation homes, lumpy assets, partition risk | [VACATION-HOMES.md](../assets/VACATION-HOMES.md), [OPERATORS.md](OPERATORS.md) |
| Retirement accounts, IRD, see-through trusts, SECURE Act impacts | [RETIREMENT-ACCOUNTS.md](../assets/RETIREMENT-ACCOUNTS.md), [BENEFICIARY-COORDINATION.md](../foundations/BENEFICIARY-COORDINATION.md) |
| Brokerage, concentrated stock, margin, step-up | [INVESTMENT-ACCOUNTS-MARGIN.md](../assets/INVESTMENT-ACCOUNTS-MARGIN.md), [STEP-UP-BASIS-PLANNING.md](../advanced-planning/STEP-UP-BASIS-PLANNING.md) |
| Private partnerships, PE, hedge funds, capital calls | [INVESTMENT-PARTNERSHIPS.md](../assets/INVESTMENT-PARTNERSHIPS.md), [OPERATORS.md](OPERATORS.md) |
| Family business / S-corp / buy-sell / succession | [PRIVATE-BUSINESS.md](../assets/PRIVATE-BUSINESS.md), [FOUNDER.md](../professions/FOUNDER.md), [EXECUTIVE.md](../professions/EXECUTIVE.md) |
| Crypto, seed phrases, exchange accounts, digital handoff | [CRYPTO-AND-DIGITAL.md](../assets/CRYPTO-AND-DIGITAL.md), [DIGITAL-LEGACY.md](../legacy-and-logistics/DIGITAL-LEGACY.md), [DIGITAL-INVENTORY.md](../../assets/DIGITAL-INVENTORY.md) |
| Digital assets, RUFADAA, platform access | [DIGITAL-LEGACY.md](../legacy-and-logistics/DIGITAL-LEGACY.md), [DURABLE-POA.md](../incapacity/DURABLE-POA.md), [VERIFICATION-FIRST.md](VERIFICATION-FIRST.md) |
| IP, royalties, creator economy, NIL / publicity concerns | [INTELLECTUAL-PROPERTY.md](../assets/INTELLECTUAL-PROPERTY.md) |
| Firearms / NFA / executor criminal risk | [FIREARMS-NFA.md](../assets/FIREARMS-NFA.md) |
| Farmland, ranches, timber, mineral and water rights | [FARMLAND-MINERAL-RIGHTS.md](../assets/FARMLAND-MINERAL-RIGHTS.md) |
| Art, cars, jewelry, collections, sentimental property | [ART-COLLECTIONS-PERSONAL-PROPERTY.md](../assets/ART-COLLECTIONS-PERSONAL-PROPERTY.md), [PERSONAL-PROPERTY-MEMORANDUM.md](../../assets/PERSONAL-PROPERTY-MEMORANDUM.md) |
| Pets, horses, caretakers, pet trusts | [PETS-AND-ANIMALS.md](../assets/PETS-AND-ANIMALS.md) |
| Foreign real estate, forced heirship, treaty/cross-border | [FOREIGN-ASSETS.md](../assets/FOREIGN-ASSETS.md), [DOMICILE.md](../foundations/DOMICILE.md) |
| Durable POA, healthcare proxy, HIPAA, living will | [DURABLE-POA.md](../incapacity/DURABLE-POA.md), [HEALTHCARE-AND-DIRECTIVES.md](../incapacity/HEALTHCARE-AND-DIRECTIVES.md) |
| POLST / MOLST | [POLST-MOLST.md](../incapacity/POLST-MOLST.md), [VERIFICATION-FIRST.md](VERIFICATION-FIRST.md) |
| Dementia directives, Ulysses clauses, mental-health directives | [MENTAL-HEALTH-DIRECTIVES.md](../incapacity/MENTAL-HEALTH-DIRECTIVES.md), [HEALTHCARE-AND-DIRECTIVES.md](../incapacity/HEALTHCARE-AND-DIRECTIVES.md) |
| Long-term care, Medicaid planning, MERP, MAPTs | [LONG-TERM-CARE.md](../incapacity/LONG-TERM-CARE.md), [MEDICAID-PLANNING.md](../incapacity/MEDICAID-PLANNING.md), [VERIFICATION-FIRST.md](VERIFICATION-FIRST.md) |
| Funeral wishes, organ donation, disposition of remains, sepulcher-style conflicts | [FUNERAL-AND-DISPOSITION.md](../legacy-and-logistics/FUNERAL-AND-DISPOSITION.md), [DISPOSITION-OF-REMAINS.md](../../assets/DISPOSITION-OF-REMAINS.md) |
| Letter of instruction, death binder, if-I-die-tomorrow packet | [LETTER-OF-INSTRUCTION.md](../../assets/LETTER-OF-INSTRUCTION.md), [IF-I-DIE-TOMORROW.md](../../assets/IF-I-DIE-TOMORROW.md) |
| Family meeting, explanation process, ethical will | [FAMILY-COMMUNICATION.md](../legacy-and-logistics/FAMILY-COMMUNICATION.md), [ETHICAL-WILL.md](../legacy-and-logistics/ETHICAL-WILL.md), [FAMILY-MEETING-AGENDA.md](../../assets/FAMILY-MEETING-AGENDA.md) |
| Plan maintenance / periodic refresh / life-event review | [PLAN-MAINTENANCE-OS.md](PLAN-MAINTENANCE-OS.md), [REVIEW-SCHEDULE.md](../../assets/REVIEW-SCHEDULE.md), [life-events/README.md](../life-events/README.md) |
| Scenario stress testing and failure-mode analysis | [STRESS-TEST-SCENARIOS.md](STRESS-TEST-SCENARIOS.md), [COMPREHENSIVE-PLAN-REPORT.md](../../assets/COMPREHENSIVE-PLAN-REPORT.md) |
| Disclaimer planning after death | [DISCLAIMERS.md](../post-death/DISCLAIMERS.md) |
| Executor post-death workflow and heir playbook | [EXECUTOR-PLAYBOOK.md](../post-death/EXECUTOR-PLAYBOOK.md), [HEIR-PLAYBOOK.md](../post-death/HEIR-PLAYBOOK.md) |
| Wealth-tier routing from modest estate to industrialist | [TIER-TRIAGE.md](TIER-TRIAGE.md), [TIER-1-MODEST-ESTATE.md](../tiers/TIER-1-MODEST-ESTATE.md), [TIER-2-MIDDLE-CLASS.md](../tiers/TIER-2-MIDDLE-CLASS.md), [TIER-3-HNW.md](../tiers/TIER-3-HNW.md), [TIER-4-UHNW.md](../tiers/TIER-4-UHNW.md), [TIER-5-INDUSTRIALIST.md](../tiers/TIER-5-INDUSTRIALIST.md) |
| Profession, life-event, and situation overlays | [professions/README.md](../professions/README.md), [life-events/README.md](../life-events/README.md), [situations/README.md](../situations/README.md) |

---

## Operational Notes

- The guide contains many volatile figures. Coverage alone is not enough.
  Pair topic coverage with [VERIFICATION-FIRST.md](VERIFICATION-FIRST.md).
- If you discover a guide topic not well represented here, add it to the map before
  considering the skill “fully updated.”
- Treat this file as the skill’s auditable answer to: "Did we actually carry the
  source guide into the skill, or did we merely summarize it?"
