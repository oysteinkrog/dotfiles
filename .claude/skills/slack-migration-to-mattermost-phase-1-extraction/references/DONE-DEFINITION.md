# Phase 1 Done Definition

Phase 1 is complete only when every item below is true.

## Required Artifacts

- `artifacts/raw/manifest.raw.json` exists and hashes match raw artifacts
- `artifacts/enriched/manifest.enriched.json` exists if enrichment occurred
- `artifacts/import-ready/manifest.import-ready.json` exists
- `artifacts/import-ready/mattermost_import.jsonl` exists
- `artifacts/import-ready/mattermost-bulk-import.zip` exists
- `artifacts/reports/handoff.md` exists
- `artifacts/reports/handoff.json` exists
- `artifacts/reports/verification.md` exists
- `artifacts/reports/unresolved-gaps.md` exists

## Required Validation Gates

- `scripts/validate-phase1-artifacts.py` passes
- `scripts/validate-phase1-jsonl.py` passes
- `scripts/validate-enrichment-completeness.py` has no unexplained critical gaps
- `scripts/reconcile-phase1-counts.py` has no unexplained mismatches
- known gaps are classified, not merely noted

## Required Decision Outputs

- authoritative export source is explicit
- gap disposition classes are explicit:
  - native-importable
  - sidecar-only
  - manual-rebuild
  - unrecoverable
- Phase 2 required settings are explicit
- sidecar channels are explicit
- evidence pack is buildable without guesswork

## Not Done If

- the final ZIP hash is unknown
- the authoritative ZIP is ambiguous
- files were referenced but not downloaded or explicitly accepted as losses
- sidecars exist but are not named in the handoff
- the JSONL is only “non-empty” but not semantically validated
