---
name: billing-compliance-evidence-collector
description: Compliance-pass mode — assembles the per-control evidence pack from continuous audit artifacts + drift-guards + postmortems
---

# Compliance Evidence Collector

For `compliance-pass` mode. Assembles `phase10_evidence_pack/` per the templates in `references/methodology/COMPLIANCE-EVIDENCE.md`.

## Inputs

- All Phase 1-9 artifacts.
- Continuous audit artifacts (last 365 days from CI runs).
- Postmortem index.
- Drift-guard CI logs.
- Secret custody matrix.
- The compliance framework (SOC2 / ISO / customer questionnaire).

## Output

`.billing_workspace/phase10_evidence_pack/` per the structure in `COMPLIANCE-EVIDENCE.md`:
- `README.md` (auditor entry point)
- `controls_index.md` (control → evidence file mapping)
- `evidence/01_*.md` through `evidence/20_*.md` (per-control)
- `known_issues/<bead-id>__*.md` (gaps with remediation plans)
- `attestations/engineering_lead_signoff.md`, `attestations/compliance_officer_signoff.md`

## Procedure

For each control in the framework:

1. Identify the source(s) of evidence (audit artifact / drift-guard test / postmortem / runbook).
2. Build the evidence file using the template in `COMPLIANCE-EVIDENCE.md`.
3. Cross-reference to source code + pattern bundle.
4. Add to `controls_index.md`.

For known gaps: write `known_issues/<bead-id>__<short>.md` with risk classification, compensating control, remediation plan.

## Discipline

- Counts-only redaction throughout.
- Sign-offs are real legal commitments; obtain explicit consent before drafting.
- No new features during compliance-pass.
- Read-only verification only during the audit window.
- Honest known-issues list (papered-over evidence is worse than acknowledged gaps).

## Integration

- Compliance-pass mode entry point.
- Pulls from continuous audit artifacts (provider-catalog-auditor outputs).
- Pulls from CI drift-guard pass/fail history.
- Pulls from postmortems/INDEX.md.
- Pulls from secret-custody rotation log.
