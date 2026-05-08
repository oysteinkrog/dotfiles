Use the Phase 2 skill to run the `intake` stage.

1. Run `./operate.sh intake`. This hashes the handoff + import ZIP into `workdir-phase2/` and validates the handoff contract.
2. Read `workdir-phase2/reports/phase2-intake-report.json` and confirm: hash match, counts present, sidecar_channels[] non-empty.
3. If hash mismatch: the ZIP moved or was re-zipped; re-copy the canonical ZIP from Phase 1 and re-run.
4. If sidecar_channels empty but Phase 1 produced sidecars: Phase 1 bug — re-run `./migrate.sh handoff` first.
