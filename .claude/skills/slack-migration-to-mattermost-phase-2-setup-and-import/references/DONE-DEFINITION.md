# Phase 2 Done Definition

Phase 2 is complete only when all of these are true.

## Required Gates

- Phase 1 handoff bundle passes `validate-phase2-intake.py`
- Mattermost config passes `validate-mattermost-config.py`
- staging rehearsal passes
- restore drill passes or is explicitly waived with owner sign-off
- cutover readiness gate passes

## Required Outputs

- intake manifest
- config validation report
- live stack verification report
- staging rehearsal report
- post-import smoke report
- reconciliation report
- cutover readiness report
- readiness score report
- production import watch log
- activation proof report
- final cutover status summary

## Required Operational Outcomes

- import job reaches success
- counts reconcile against the handoff
- smoke tests pass
- user activation path is proven
- rollback owner and abort criteria were explicit before cutover

## Not Done If

- production import happened before staging
- the final package hash was never verified on the Phase 2 side
- the team cannot explain whether it should proceed, abort, or roll back
