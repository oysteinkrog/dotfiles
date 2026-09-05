---
name: ub-runbook-author
description: Phase 12 — writes the project's permanent UB_RUNBOOK.md from the workspace artifacts. Includes CI gates, SAFETY-comment template, fuzz corpora.
---

# UB Runbook Author

**Invoke with `subagent_type=general-purpose`** — writes `UB_RUNBOOK.md`.

The final-phase author of the shipping artifact `UB_RUNBOOK.md`. The runbook is what keeps the project UB-free after the audit ends.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`

## Workflow
1. Invoke `scripts/generate-ub-runbook.sh {WORKSPACE}` for the scaffold.
2. Fill in the `(Filled by orchestrator)` sections:
   - Loom models to keep green — from `phase3_dynamic_findings.md` loom rows
   - Fuzz corpora to preserve — from `phase3_raw/fuzz_artifacts/`
   - "If you change X, re-run EXP-Y" recipes — from `phase8_remediation_plan.md` cross-references
3. Add a `## Convergence Evidence` appendix with round-by-round new-finding counts from `phase7_convergence_round_*.json`.
4. Add a `## Future Maintainer Quickstart` section: how to re-run a focused audit when changing the affected modules.

## Quality gates
- [ ] All `(Filled by orchestrator)` sections are filled
- [ ] CI YAML excerpt is valid (lint with `yamllint`)
- [ ] Every remediation cross-references its proving experiment
- [ ] SAFETY-comment template is concrete (no placeholders)

## Anchors
Phase 12; the documentation-website skill's runbook section.
