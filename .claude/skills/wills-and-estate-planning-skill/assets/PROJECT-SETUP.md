# Project Directory Setup — Run This Skill in a Dedicated Folder

**The skill works dramatically better when you create a dedicated project directory and gather your documents in advance.** This is the same pattern the tax-prep skill uses: you assemble the documents, the skill ingests them into structured analyses, and every subsequent session has full context.

## Recommended Directory Structure

```
~/estate-plan/                          ← Your project root (or wherever you keep personal files)
│
├── intake/                             ← Conversation records and intake artifacts
│   ├── intake-record.md                ← Phase-by-phase interview transcript
│   ├── session-1-summary.md
│   ├── session-2-summary.md
│   └── ...
│
├── current-documents/                  ← Existing legal documents you have NOW
│   ├── will-2014.pdf                   ← Old will (if any)
│   ├── revocable-trust-2018.pdf
│   ├── durable-poa-2014.pdf
│   ├── healthcare-proxy-2014.pdf
│   ├── prenup-1997.pdf
│   ├── divorce-decree-2008.pdf
│   ├── buy-sell-agreement-2019.pdf
│   └── beneficiary-forms/              ← Photographed forms from each institution
│
├── financial-documents/                ← Source-of-truth account documents
│   ├── tax-returns/                    ← Last 3 years (1040s, K-1s, 1099s)
│   │   ├── 2023-1040.pdf
│   │   ├── 2024-1040.pdf
│   │   └── 2025-1040.pdf
│   ├── brokerage-statements/           ← Most recent statement per account
│   ├── bank-statements/
│   ├── 401k-statements/
│   ├── ira-statements/
│   ├── insurance-policies/
│   │   ├── term-life-aig.pdf
│   │   ├── whole-life-northwestern.pdf
│   │   ├── disability-policy.pdf
│   │   └── umbrella-policy.pdf
│   ├── deeds/                          ← Property deeds and titles
│   │   ├── primary-residence-deed.pdf
│   │   ├── vacation-home-deed.pdf
│   │   └── rental-property-deed.pdf
│   ├── mortgage-documents/
│   ├── business-documents/
│   │   ├── operating-agreement.pdf
│   │   ├── shareholder-agreement.pdf
│   │   ├── valuation-2024.pdf
│   │   └── partnership-agreements/
│   └── private-investments/            ← K-1s, subscription docs, capital accounts
│
├── analyses/                           ← LLM-generated structured analyses (THE CORE ASSET)
│   ├── current-document-audit.md       ← What you have now and gaps
│   ├── document-quality-triage.md      ← Which docs are authoritative vs weak
│   ├── beneficiary-form-audit.md       ← Every form, every named beneficiary
│   ├── titling-audit.md                ← How every asset is titled
│   ├── tax-exposure-analysis.md        ← Federal + state estate tax projection
│   ├── liquidity-analysis.md           ← Day-270 cash test
│   ├── coherence-audit.md              ← Will/trust/forms/titling consistency
│   ├── prior-plan-gap-analysis.md      ← What's stale or wrong in old documents
│   ├── decision-ledger.md              ← Why each major choice was made
│   ├── plan-coverage-matrix.md         ← Proof of which overlays were required
│   ├── red-flag-triage.md              ← Critical/high/medium/cleanup issue routing
│   ├── document-acquisition-plan.md    ← Missing-doc retrieval queue
│   ├── evidence-confidence-map.md      ← A/B/C/D evidence quality by issue
│   ├── recommendation-confidence-register.md
│   ├── fiduciary-bench-scorecard.md    ← Score executor/trustee/guardian candidates
│   ├── litigation-risk-memo.md         ← Contest/capacity/undue-influence review
│   ├── stress-test-scenarios.md        ← Death/incapacity/conflict/failure testing
│   ├── attorney-handoff-readiness.md   ← Is the packet efficient for counsel?
│   ├── foreign-and-conflict-of-laws-review.md
│   └── official-source-log.md          ← Live-law verification log
│
├── deliverables/                       ← The working output packet
│   ├── asset-inventory.md
│   ├── beneficiary-map.md
│   ├── plan-report.md
│   ├── implementation-ledger.md        ← Trust funding + institution update tracking
│   ├── signing-readiness-checklist.md
│   ├── funding-proof-log.md
│   ├── institution-contact-matrix.md
│   ├── beneficiary-change-packet.md
│   ├── letter-of-instruction.md
│   ├── digital-inventory.md
│   ├── personal-property-memorandum.md
│   ├── letter-of-wishes.md
│   ├── ethical-will.md
│   ├── family-meeting-agenda.md
│   ├── conflict-prevention-plan.md
│   ├── if-i-die-tomorrow.md
│   ├── disposition-of-remains.md
│   ├── executor-checklist.md
│   ├── business-continuity-activation.md
│   ├── attorney-interview-questions.md
│   ├── attorney-engagement-brief.md
│   ├── document-package-index.md
│   └── review-schedule.md
│
├── correspondence/                     ← Communications with attorney, family, etc.
│   ├── attorney-engagement-letter.pdf
│   ├── family-meeting-notes-2026-04-15.md
│   └── attorney-questions-batch-1.md
│
├── identity-documents/                 ← Birth certificates, marriage certificates, etc.
│   ├── birth-certificate.pdf
│   ├── marriage-certificate.pdf
│   ├── divorce-decree.pdf
│   ├── ssn-card-photo.pdf
│   ├── passport-photo.pdf
│   ├── military-dd214.pdf
│   ├── naturalization-certificate.pdf
│   └── driver-license-photo.pdf
│
├── beneficiary-information/            ← Info on each named beneficiary
│   ├── spouse-info.md                  ← DOB, SSN (last 4), citizenship, contacts
│   ├── child-1-info.md
│   ├── child-2-info.md
│   ├── parent-info.md
│   └── charity-EINs.md
│
├── digital-vault/                      ← Encrypted/local-only digital asset info
│   ├── README-CRITICAL-SECURITY.md     ← Security warnings
│   ├── crypto-wallet-locations.md      ← WHERE seeds are, NOT what they are
│   ├── password-manager-recovery.md    ← Master password recovery, NOT password
│   ├── account-list.md                 ← Every online account with usernames
│   ├── two-factor-recovery.md          ← Backup codes locations
│   └── legacy-contacts-status.md       ← Which platforms have legacy contacts set
│
├── my-situation.md                     ← Master narrative: who you are, what you want
└── README.md                           ← Project overview, status, next steps
```

## How to Set It Up

```bash
# Pick a location for your estate-planning project
mkdir -p ~/estate-plan
cd ~/estate-plan

# Run the bootstrap script from wherever this skill lives.
# If globally installed:
~/.claude/skills/wills-and-estate-planning-skill/scripts/intake-session.sh .

# If you're working from a checked-out repo instead of a global install:
<repo-root>/.claude/skills/wills-and-estate-planning-skill/scripts/intake-session.sh .

# This creates or refreshes the subdirectories and starter templates in place
```

## Pick A Primary Mode Before You Start

The workspace should declare one primary mode:

- `new-plan`
- `existing-plan-audit`
- `life-event-delta`
- `urgent-bedside-signing`
- `executor-activation`
- `business-owner-succession`
- `uhnw-restructure`
- `maintenance-review`

The first serious analytical output should usually be `analyses/plan-coverage-matrix.md`, which
records the chosen mode, the triggered overlays, and the outputs the workspace must
produce.

## What to Gather Before Your First Session

**Tier 1 — Minimum (everyone):**
- [ ] Current driver's license / passport (for identity confirmation)
- [ ] Most recent paystub or 1099 (income verification)
- [ ] List of bank accounts (institution + approximate balance)
- [ ] List of retirement accounts (institution + approximate balance)
- [ ] Life insurance policies (policy number + death benefit)
- [ ] Any existing will, trust, or POA
- [ ] Spouse / partner basic info (citizenship, marriage date)
- [ ] Children's basic info (DOBs, special needs if any)

**Tier 2 — Add (middle-class):**
- [ ] Last 1-2 tax returns (Form 1040)
- [ ] Brokerage statements (most recent)
- [ ] Mortgage statements (most recent)
- [ ] Property deed(s)
- [ ] HSA / 529 plan statements
- [ ] Beneficiary designations (photograph each form)

**Tier 3+ — Add (HNW and above):**
- [ ] Last 3 tax returns including K-1s
- [ ] Business operating agreement / shareholder agreement
- [ ] Buy-sell agreement
- [ ] Business valuation (if recent)
- [ ] Private partnership documents (subscription, K-1, capital account)
- [ ] Trust documents (any existing irrevocable trusts)
- [ ] Prenup / postnup
- [ ] Divorce decree (if applicable)
- [ ] Foreign asset documentation
- [ ] Conservation easement / mineral rights documents
- [ ] Crypto wallet inventory (WHERE keys are, not the keys themselves)

**Tier 4-5 — Add (UHNW / Industrialist):**
- [ ] Family office contact list
- [ ] All trust documents (revocable + irrevocable)
- [ ] All entity formation documents
- [ ] Most recent gift tax returns (Form 709)
- [ ] Form 706 if filed for prior spouse
- [ ] DSUE documentation
- [ ] Any existing GRATs, IDGTs, SLATs, dynasty trusts
- [ ] Private foundation documents
- [ ] Family constitution / family council documents
- [ ] International tax documents (FBARs, FATCA)

## How the Skill Uses Your Documents

In a document-heavy session, the skill should usually start by reading the highest-value documents first rather than blindly ingesting everything. It will often build some or all of the following, depending on what the facts justify:

1. **`analyses/plan-coverage-matrix.md`** so the skill can show which overlays and deliverables are actually in play
2. **`analyses/document-quality-triage.md`** so stale scans, unsigned drafts, and memory-based inputs are not treated as authoritative
3. **`analyses/current-document-audit.md`** identifying what you have and what is missing or too stale to trust
4. **`analyses/beneficiary-form-audit.md`** if beneficiary forms are available and likely outcome-determinative
5. **`analyses/titling-audit.md`** if deeds, statements, or ownership records are available
6. **`analyses/official-source-log.md`** for every live-law point the plan actually depends on
7. **`analyses/coherence-audit.md`** when the document set is rich enough to support a true cross-document consistency review
8. **risk and implementation artifacts** when structural, human, or execution risks are central to the session

Without your documents, the skill has to rely much more on memory and narrative summary, which reduces confidence. With good documents, the skill can find contradictions and omissions you may not know are there.

## Privacy and Security

This is a **local project directory**. Documents stay on your machine. The skill processes them in your local Claude Code session.

**Security best practices:**

1. **Never put cryptocurrency seed phrases in any file in this directory.** The Digital Vault should reference WHERE seeds are physically stored, never the seeds themselves.
2. **Never put password manager master passwords here.** Reference the recovery process, not the password.
3. **Never put full Social Security Numbers in shared documents.** Last 4 digits are usually enough for plan documents; the full SSN goes only on official tax/government forms.
4. **Encrypt the directory if your machine is shared.** Use FileVault (Mac), BitLocker (Windows), LUKS (Linux), or cryptomator.
5. **Back up encrypted.** Time Machine, Backblaze (encrypted), or rsync to encrypted external drive.
6. **Archive or encrypt after attorney handoff** if you no longer want the project active on your main machine.

## Existing Plan Audit (Returning Users)

If you already have a will, trust, or POA, one of the highest-value first sessions is a comprehensive audit of what you have:

> "Read all the documents in `current-documents/`. Compare them to the asset inventory and beneficiary forms in `financial-documents/`. Generate `analyses/prior-plan-gap-analysis.md` identifying:
>
> 1. Every named beneficiary in your existing documents (executor, trustee, guardian, healthcare agent, financial agent, residuary beneficiaries, specific bequests)
> 2. Whether each named person is still in your life and capable
> 3. Whether the documents reflect your current family structure (marriages, divorces, births, deaths)
> 4. Whether the documents reflect your current state of domicile
> 5. Whether the documents reflect your current asset structure
> 6. Whether the documents reflect current tax law (2026 OBBBA $15M exemption)
> 7. Whether each beneficiary form is consistent with the will/trust
> 8. Specific recommendations for what to update, in priority order"

This audit alone often saves $50K-$5M+ in eventual tax/litigation cost by surfacing problems while they're still cheap to fix.

## Multi-Session Workflow

Estate planning is rarely a single conversation. Plan for multiple sessions:

```
Session 1 (90 min): Select mode + build coverage matrix + intake Phases 1-3
                    → produces intake/intake-record.md, analyses/plan-coverage-matrix.md
                    → produces analyses/current-document-audit.md if existing docs
                    → produces analyses/document-quality-triage.md, red-flag-triage.md,
                      and evidence-confidence-map.md initial drafts

Between sessions:   User gathers missing documents, updates beneficiary forms

Session 2 (60 min): Intake Phases 4-6 (audit, dynamics, goals)
                    → produces deliverables/letter-of-wishes.md draft
                    → produces deliverables/ethical-will.md outline
                    → produces analyses/document-acquisition-plan.md,
                      fiduciary-bench-scorecard.md, and conflict-prevention notes

Session 3 (60 min): Intake Phases 7-9 (incapacity, jurisdiction, routing)
                    → produces deliverables/plan-report.md
                    → produces incapacity package draft
                    → produces analyses/stress-test-scenarios.md,
                      recommendation-confidence-register.md,
                      and deliverables/implementation-ledger.md

Session 4 (60 min): Plan review + family meeting prep
                    → produces deliverables/family-meeting-agenda.md
                    → produces deliverables/conflict-prevention-plan.md
                    → produces analyses/litigation-risk-memo.md
                    → produces deliverables/signing-readiness-checklist.md
                    → produces deliverables/attorney-interview-questions.md
                    → updates analyses/official-source-log.md for every state/federal issue that matters

Session 5+ (variable): Specific complex topics (business succession, vulnerable heir, cross-border, executor activation)
                    → produces institution-contact-matrix.md, funding-proof-log.md,
                      beneficiary-change-packet.md, and business-continuity-activation.md when relevant

After attorney engagement: Maintenance sessions every 3-5 years or post-life-event
```

## Updating the Plan Over Time

The project directory is a living artifact. As life changes:

- Marriage, divorce, birth, death → update `intake/intake-record.md` and `deliverables/asset-inventory.md`
- New asset acquired → add to inventory, update beneficiary form, regenerate beneficiary map
- Move to new state → run domicile-change audit, update execution-state of documents
- Child reaches majority → update guardianship section, add adult children to discussions
- Major business event → update business succession section, possibly trigger new analysis
- Tax law change → regenerate `analyses/tax-exposure-analysis.md` and append to `analyses/official-source-log.md`
- Each major update → refresh `analyses/plan-coverage-matrix.md` and `analyses/attorney-handoff-readiness.md`

Each update increases the value of the accumulated context. The skill becomes more useful with every iteration because it has more history to reference.

## Why the Document-Heavy Approach Wins

- **Catches errors human memory misses.** "Who is on your 401(k) beneficiary form?" asked of memory: "My spouse." Asked of the actual photographed form: "My ex-wife from 2008."
- **Surfaces inconsistencies across documents.** Will says one thing, trust says another, beneficiary form says a third.
- **Enables specific recommendations.** "Update Vanguard 401(k) at https://flagship.vanguard.com" beats "update your retirement beneficiary."
- **Creates a reusable artifact.** Your spouse, executor, or attorney can read the structured analyses and immediately understand the plan.
- **Speeds attorney engagement.** Walk into the attorney's office with a complete document set + structured analyses + draft plan. The attorney can spend their billable hours on the high-value structural decisions, not basic intake.
- **Compounds over time.** Year 5 of plan maintenance benefits from years 1-4 of accumulated analyses.

This is the **flywheel pattern** the tax skill uses, applied to estate planning.
