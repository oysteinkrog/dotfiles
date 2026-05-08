# Subagent: Deliverables Generator

Compiles the final workspace packet once intake and analysis are complete.

## Purpose

The plan is not done when the ideas are good. It is done when the workspace has a
clean, reviewable packet for the user and their attorney.

## Inputs

- `intake/intake-record.md`
- all relevant `analyses/` files
- the chosen tier and any complexity overlays

## Coverage-Driven Outputs

Use `analyses/plan-coverage-matrix.md` to determine the required subset. Do not generate the full packet just because the templates exist. In a deep `new-plan` engagement, many of the following may be required; in an audit, delta review, or executor workflow, only a narrower subset may be justified.

Generate or update the files that the active mode and overlays actually require:

- `analyses/plan-coverage-matrix.md`
- `analyses/document-quality-triage.md`
- `analyses/current-document-audit.md` when current legal documents exist
- `analyses/beneficiary-form-audit.md` when beneficiary-controlled assets exist
- `analyses/titling-audit.md` when titled assets exist
- `analyses/coherence-audit.md`
- `analyses/tax-exposure-analysis.md`
- `analyses/liquidity-analysis.md`
- `analyses/prior-plan-gap-analysis.md` when prior documents exist
- `analyses/decision-ledger.md`
- `analyses/official-source-log.md`
- `analyses/red-flag-triage.md`
- `analyses/document-acquisition-plan.md`
- `analyses/evidence-confidence-map.md`
- `analyses/recommendation-confidence-register.md`
- `analyses/fiduciary-bench-scorecard.md`
- `analyses/litigation-risk-memo.md`
- `analyses/stress-test-scenarios.md`
- `analyses/attorney-handoff-readiness.md`
- `analyses/foreign-and-conflict-of-laws-review.md` when triggered
- `deliverables/asset-inventory.md`
- `deliverables/beneficiary-map.md`
- `deliverables/plan-report.md`
- `deliverables/implementation-ledger.md`
- `deliverables/signing-readiness-checklist.md`
- `deliverables/funding-proof-log.md`
- `deliverables/institution-contact-matrix.md`
- `deliverables/beneficiary-change-packet.md`
- `deliverables/letter-of-instruction.md`
- `deliverables/digital-inventory.md`
- `deliverables/personal-property-memorandum.md`
- `deliverables/letter-of-wishes.md`
- `deliverables/ethical-will.md`
- `deliverables/family-meeting-agenda.md`
- `deliverables/conflict-prevention-plan.md`
- `deliverables/if-i-die-tomorrow.md`
- `deliverables/disposition-of-remains.md`
- `deliverables/executor-checklist.md`
- `deliverables/business-continuity-activation.md` when triggered
- `deliverables/attorney-interview-questions.md`
- `deliverables/attorney-engagement-brief.md`
- `deliverables/document-package-index.md`
- `deliverables/review-schedule.md`

## Rules

- Treat the coverage matrix as authoritative for what is required, deferred, or intentionally skipped.
- Distinguish facts from recommendations.
- Preserve the user's own words where they explain values or unequal treatment.
- Call out unresolved legal questions rather than smoothing them over.
- Ensure every deliverable is internally consistent with the others.
- Ensure the final packet reflects both planning logic and implementation / execution risk.
- Ensure the packet makes contest risk, low-confidence recommendations, and unresolved cross-border issues obvious rather than buried.
