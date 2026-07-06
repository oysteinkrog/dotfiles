#!/usr/bin/env bash
# intake-session.sh — Initialize or normalize an estate-planning project directory
# Usage: ./intake-session.sh <project-dir>

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <project-dir>"
    exit 1
fi

PROJECT_DIR="$1"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/../assets"

copy_asset_template() {
    local target="$1"
    local asset_name="$2"
    if [ ! -f "$target" ] && [ -f "$ASSETS_DIR/$asset_name" ]; then
        cp "$ASSETS_DIR/$asset_name" "$target"
    fi
}

mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

mkdir -p \
    intake \
    current-documents \
    current-documents/beneficiary-forms \
    financial-documents \
    financial-documents/tax-returns \
    financial-documents/brokerage-statements \
    financial-documents/bank-statements \
    financial-documents/401k-statements \
    financial-documents/ira-statements \
    financial-documents/insurance-policies \
    financial-documents/deeds \
    financial-documents/mortgage-documents \
    financial-documents/business-documents \
    financial-documents/private-investments \
    analyses \
    deliverables \
    correspondence \
    identity-documents \
    beneficiary-information \
    digital-vault

if [ ! -f README.md ]; then
    cat > README.md <<EOF
# Estate Planning Project

Created: $TIMESTAMP

Use this directory as the working home for the wills-and-estate-planning skill.

## Core workflow

1. Put current legal documents in \`current-documents/\`
2. Put account statements, tax returns, deeds, policies, and business records in \`financial-documents/\`
3. Pick a primary operating mode and record it in \`analyses/plan-coverage-matrix.md\`
4. Run the intake and save progress in \`intake/intake-record.md\`
5. Generate structured analyses in \`analyses/\`
6. Generate the working plan, implementation queue, and handoff packet in \`deliverables/\`

## Critical note

This directory should never contain cryptocurrency seed phrases, private keys, or password-manager master passwords.
Document locations and recovery procedures only.
EOF
fi

if [ ! -f my-situation.md ]; then
    cat > my-situation.md <<EOF
# My Situation

- Name:
- State of domicile:
- Marital status:
- Children / dependents:
- Trigger for planning right now:
- Primary mode:
- Main goals:
- Known concerns:
EOF
fi

if [ ! -f intake/intake-record.md ]; then
    cat > intake/intake-record.md <<EOF
# Intake Record

**Started:** $TIMESTAMP
**User:** [Name]

## Phase 1: Orientation
[Why now? Trigger event? Disclaimer presented and acknowledged?]

## Phase 2: People
[Map spouse/partner, children, parents, siblings, dependents, fiduciaries, charities]

## Phase 3: Assets and Liabilities
[Reference deliverables/asset-inventory.md and note unknowns]

## Phase 4: Beneficiary Audit
[Reference deliverables/beneficiary-map.md and institution-specific gaps]

## Phase 5: Family Dynamics
[Blended family, estrangement, disability, addiction, divorce, litigation, caregiver issues]

## Phase 6: Goals and Values
[Capture the user's reasoning in their own words]

## Phase 7: Incapacity Scenarios
[Financial agent, healthcare agent, living-will choices, cognitive decline concerns]

## Phase 8: Jurisdiction
[Domicile, out-of-state real estate, foreign assets, state-specific issues]

## Phase 9: Wealth Tier and Routing
[Tier, overlays, and why]
EOF
fi

copy_asset_template analyses/document-quality-triage.md DOCUMENT-QUALITY-TRIAGE.md
copy_asset_template analyses/current-document-audit.md CURRENT-DOCUMENT-AUDIT.md
copy_asset_template analyses/beneficiary-form-audit.md BENEFICIARY-FORM-AUDIT.md
copy_asset_template analyses/titling-audit.md TITLING-AUDIT.md
copy_asset_template analyses/coherence-audit.md COHERENCE-AUDIT.md
copy_asset_template analyses/tax-exposure-analysis.md TAX-EXPOSURE-ANALYSIS.md
copy_asset_template analyses/liquidity-analysis.md LIQUIDITY-ANALYSIS.md
copy_asset_template analyses/prior-plan-gap-analysis.md PRIOR-PLAN-GAP-ANALYSIS.md
copy_asset_template analyses/plan-coverage-matrix.md PLAN-COVERAGE-MATRIX.md
copy_asset_template analyses/red-flag-triage.md RED-FLAG-TRIAGE.md
copy_asset_template analyses/document-acquisition-plan.md DOCUMENT-ACQUISITION-PLAN.md
copy_asset_template analyses/evidence-confidence-map.md EVIDENCE-CONFIDENCE-MAP.md
copy_asset_template analyses/recommendation-confidence-register.md RECOMMENDATION-CONFIDENCE-REGISTER.md
copy_asset_template analyses/fiduciary-bench-scorecard.md FIDUCIARY-BENCH-SCORECARD.md
copy_asset_template analyses/litigation-risk-memo.md LITIGATION-RISK-MEMO.md
copy_asset_template analyses/stress-test-scenarios.md STRESS-TEST-SCENARIOS.md
copy_asset_template analyses/attorney-handoff-readiness.md ATTORNEY-HANDOFF-READINESS.md
copy_asset_template analyses/foreign-and-conflict-of-laws-review.md FOREIGN-AND-CONFLICT-OF-LAWS-REVIEW.md
copy_asset_template analyses/decision-ledger.md DECISION-LEDGER.md
copy_asset_template analyses/official-source-log.md OFFICIAL-SOURCE-LOG.md

if [ ! -f analyses/current-document-audit.md ]; then
    cat > analyses/current-document-audit.md <<EOF
# Current Document Audit

Created: $TIMESTAMP

List every existing document, when executed, the state it appears tied to,
named fiduciaries, covered assets, and obvious freshness / completeness issues.
EOF
fi

if [ ! -f analyses/document-quality-triage.md ]; then
    cat > analyses/document-quality-triage.md <<EOF
# Document Quality Triage

Created: $TIMESTAMP

Classify source documents as authoritative, probative, context-only, or unusable.
Do not treat weak scans, unsigned drafts, or stale confirmations as settled facts.
EOF
fi

if [ ! -f analyses/beneficiary-form-audit.md ]; then
    cat > analyses/beneficiary-form-audit.md <<EOF
# Beneficiary Form Audit

Created: $TIMESTAMP

Track every retirement, insurance, POD/TOD, annuity, and transfer-on-death designation.
Flag ex-spouses, deceased people, minors, estates, and missing contingent beneficiaries.
EOF
fi

if [ ! -f analyses/titling-audit.md ]; then
    cat > analyses/titling-audit.md <<EOF
# Titling Audit

Created: $TIMESTAMP

Document how each major asset is titled today, what controls at death, and
whether the title matches the intended plan.
EOF
fi

if [ ! -f analyses/tax-exposure-analysis.md ]; then
    cat > analyses/tax-exposure-analysis.md <<EOF
# Tax Exposure Analysis

Created: $TIMESTAMP

Summarize federal and state estate / inheritance tax exposure, portability,
step-up considerations, and any state-specific planning pressure points.
EOF
fi

if [ ! -f analyses/liquidity-analysis.md ]; then
    cat > analyses/liquidity-analysis.md <<EOF
# Liquidity Analysis

Created: $TIMESTAMP

Model whether the estate can cover taxes, debts, administration costs, and
immediate family support needs without distressed sales.
EOF
fi

if [ ! -f analyses/coherence-audit.md ]; then
    cat > analyses/coherence-audit.md <<EOF
# Coherence Audit

Created: $TIMESTAMP

Check whether the will, trust, beneficiary forms, titling, and letters of
instruction tell one coherent story.
EOF
fi

if [ ! -f analyses/prior-plan-gap-analysis.md ]; then
    cat > analyses/prior-plan-gap-analysis.md <<EOF
# Prior Plan Gap Analysis

Created: $TIMESTAMP

Identify stale clauses, outdated fiduciaries, domicile mismatches, missing
documents, tax-law drift, and beneficiary/designation inconsistencies.
EOF
fi

if [ ! -f analyses/plan-coverage-matrix.md ]; then
    cat > analyses/plan-coverage-matrix.md <<EOF
# Plan Coverage Matrix

Created: $TIMESTAMP

Record the selected mode, triggered overlays, required references, required
outputs, and any blocked coverage areas.
EOF
fi

if [ ! -f analyses/red-flag-triage.md ]; then
    cat > analyses/red-flag-triage.md <<EOF
# Red Flag Triage

Created: $TIMESTAMP

Classify issues into critical, high, medium, and cleanup. Do not let optimization
questions hide structural failures.
EOF
fi

if [ ! -f analyses/document-acquisition-plan.md ]; then
    cat > analyses/document-acquisition-plan.md <<EOF
# Document Acquisition Plan

Created: $TIMESTAMP

List every missing controlling document, why it matters, who likely has it,
and what planning decisions are blocked without it.
EOF
fi

if [ ! -f analyses/evidence-confidence-map.md ]; then
    cat > analyses/evidence-confidence-map.md <<EOF
# Evidence Confidence Map

Created: $TIMESTAMP

Grade key facts and assets as A/B/C/D evidence quality and identify what needs
better proof before recommendations can be treated as reliable.
EOF
fi

if [ ! -f analyses/recommendation-confidence-register.md ]; then
    cat > analyses/recommendation-confidence-register.md <<EOF
# Recommendation Confidence Register

Created: $TIMESTAMP

Score each major recommendation for evidence quality, law stability,
implementation dependence, and human / conflict sensitivity.
EOF
fi

if [ ! -f analyses/fiduciary-bench-scorecard.md ]; then
    cat > analyses/fiduciary-bench-scorecard.md <<EOF
# Fiduciary Bench Scorecard

Created: $TIMESTAMP

Compare realistic candidates for executor, trustee, guardian, financial agent,
and healthcare agent.
EOF
fi

if [ ! -f analyses/litigation-risk-memo.md ]; then
    cat > analyses/litigation-risk-memo.md <<EOF
# Litigation Risk Memo

Created: $TIMESTAMP

Review capacity, undue influence, execution defect risk, ambiguity, fiduciary
conflict, and family-blowup risk.
EOF
fi

if [ ! -f analyses/stress-test-scenarios.md ]; then
    cat > analyses/stress-test-scenarios.md <<EOF
# Stress-Test Scenarios

Created: $TIMESTAMP

Test the plan against death tonight, multi-year incapacity, simultaneous deaths,
fiduciary failure, liquidity stress, digital lockout, and family conflict.
EOF
fi

if [ ! -f analyses/attorney-handoff-readiness.md ]; then
    cat > analyses/attorney-handoff-readiness.md <<EOF
# Attorney Handoff Readiness

Created: $TIMESTAMP

Score whether the workspace is efficient and complete enough for outside counsel
to draft without redoing basic intake.
EOF
fi

if [ ! -f analyses/foreign-and-conflict-of-laws-review.md ]; then
    cat > analyses/foreign-and-conflict-of-laws-review.md <<EOF
# Foreign and Conflict-of-Laws Review

Created: $TIMESTAMP

Use when foreign assets, foreign heirs, non-citizen spouse issues, or multi-
jurisdiction conflict-of-laws questions are present.
EOF
fi

if [ ! -f analyses/decision-ledger.md ]; then
    cat > analyses/decision-ledger.md <<EOF
# Decision Ledger

Created: $TIMESTAMP

Record each major estate-planning choice, the user's reasoning, tradeoffs
considered, and what still needs attorney review.
EOF
fi

if [ ! -f analyses/official-source-log.md ]; then
    cat > analyses/official-source-log.md <<EOF
# Official Source Log

Created: $TIMESTAMP

Record each live-law verification performed for this plan.

| Topic | Jurisdiction | Source | URL | Verified on | Notes |
|-------|--------------|--------|-----|-------------|-------|
EOF
fi

copy_asset_template deliverables/asset-inventory.md ASSET-INVENTORY.md
copy_asset_template deliverables/beneficiary-map.md BENEFICIARY-MAP.md
copy_asset_template deliverables/plan-report.md COMPREHENSIVE-PLAN-REPORT.md
copy_asset_template deliverables/implementation-ledger.md IMPLEMENTATION-LEDGER.md
copy_asset_template deliverables/signing-readiness-checklist.md SIGNING-READINESS-CHECKLIST.md
copy_asset_template deliverables/funding-proof-log.md FUNDING-PROOF-LOG.md
copy_asset_template deliverables/institution-contact-matrix.md INSTITUTION-CONTACT-MATRIX.md
copy_asset_template deliverables/beneficiary-change-packet.md BENEFICIARY-CHANGE-PACKET.md
copy_asset_template deliverables/letter-of-instruction.md LETTER-OF-INSTRUCTION.md
copy_asset_template deliverables/digital-inventory.md DIGITAL-INVENTORY.md
copy_asset_template deliverables/personal-property-memorandum.md PERSONAL-PROPERTY-MEMORANDUM.md
copy_asset_template deliverables/letter-of-wishes.md LETTER-OF-WISHES.md
copy_asset_template deliverables/ethical-will.md ETHICAL-WILL-TEMPLATE.md
copy_asset_template deliverables/family-meeting-agenda.md FAMILY-MEETING-AGENDA.md
copy_asset_template deliverables/conflict-prevention-plan.md CONFLICT-PREVENTION-PLAN.md
copy_asset_template deliverables/if-i-die-tomorrow.md IF-I-DIE-TOMORROW.md
copy_asset_template deliverables/disposition-of-remains.md DISPOSITION-OF-REMAINS.md
copy_asset_template deliverables/executor-checklist.md EXECUTOR-CHECKLIST.md
copy_asset_template deliverables/business-continuity-activation.md BUSINESS-CONTINUITY-ACTIVATION.md
copy_asset_template deliverables/attorney-interview-questions.md ATTORNEY-INTERVIEW.md
copy_asset_template deliverables/attorney-engagement-brief.md ATTORNEY-ENGAGEMENT-BRIEF.md
copy_asset_template deliverables/document-package-index.md DOCUMENT-PACKAGE-INDEX.md
copy_asset_template deliverables/review-schedule.md REVIEW-SCHEDULE.md

for file in \
    deliverables/asset-inventory.md \
    deliverables/beneficiary-map.md \
    deliverables/plan-report.md \
    deliverables/implementation-ledger.md \
    deliverables/signing-readiness-checklist.md \
    deliverables/funding-proof-log.md \
    deliverables/institution-contact-matrix.md \
    deliverables/beneficiary-change-packet.md \
    deliverables/letter-of-instruction.md \
    deliverables/digital-inventory.md \
    deliverables/personal-property-memorandum.md \
    deliverables/letter-of-wishes.md \
    deliverables/ethical-will.md \
    deliverables/family-meeting-agenda.md \
    deliverables/conflict-prevention-plan.md \
    deliverables/if-i-die-tomorrow.md \
    deliverables/disposition-of-remains.md \
    deliverables/executor-checklist.md \
    deliverables/business-continuity-activation.md \
    deliverables/attorney-interview-questions.md \
    deliverables/attorney-engagement-brief.md \
    deliverables/document-package-index.md \
    deliverables/review-schedule.md
do
    if [ ! -f "$file" ]; then
        cat > "$file" <<EOF
# $(basename "$file" .md | tr '-' ' ' | sed 's/\b\(.\)/\u\1/g')

Created: $TIMESTAMP
EOF
    fi
done

if [ ! -f digital-vault/README-CRITICAL-SECURITY.md ]; then
    cat > digital-vault/README-CRITICAL-SECURITY.md <<EOF
# Critical Security Rules

- Do not store seed phrases, private keys, or master passwords in this directory.
- Store locations, contacts, recovery procedures, and access instructions only.
- Encrypt this project if the machine is shared.
EOF
fi

echo "Estate-planning project initialized or refreshed in: $PROJECT_DIR"
echo
echo "Key directories:"
echo "  intake/"
echo "  current-documents/"
echo "  financial-documents/"
echo "  analyses/"
echo "  deliverables/"
echo
echo "Next: Select the primary mode, update analyses/plan-coverage-matrix.md,"
echo "      then begin Phase 1 and save progress to intake/intake-record.md"
