# Phase 1 Start Here

Use this file when you need one safe first move instead of the full runbook.

## Default Path

1. Determine Slack plan tier and export approval status.
2. If Business+ / Enterprise with approval, use official export as source of truth.
3. If Pro / Free or approval is impossible, use `slackdump` as primary and write the blind spots down immediately.
4. Build artifacts under `artifacts/`, never overwrite prior stages.
5. Run semantic validation before handoff:
   - `./migrate.sh all` for the default executable path, or drive the stages one by one
   - `scripts/validate-phase1-artifacts.py`
   - `scripts/validate-phase1-jsonl.py`
   - `scripts/validate-enrichment-completeness.py`
   - `scripts/reconcile-phase1-counts.py`

## Stop Immediately If

- plan tier is unknown
- legal/compliance approval is unresolved
- you do not know which export source is authoritative
- raw artifacts are not being hashed into manifests
- files, emoji, or sidecars are being silently dropped

## First-Hop References

- `references/playbooks/LEGAL-APPROVAL-GATE.md`
- `references/specs/CROSS-PHASE-STATE-MACHINE.md`
- `references/specs/CROSS-PHASE-INTAKE-CONTRACT.md`
- `references/personas/OPERATOR-ROUTER.md`
- `references/DONE-DEFINITION.md`
