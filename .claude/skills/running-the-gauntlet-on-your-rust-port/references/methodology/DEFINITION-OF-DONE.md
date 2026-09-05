# Definition of Done — Per Phase + Per Bead

Crisp criteria for "this is done; the gauntlet can proceed." Each row: phase or bead-type, the exit criteria, the validator script that checks them.

## Phase exit criteria

### Phase 0 — TOOLCHAIN BOOTSTRAP + WORKSPACE INIT
- [ ] `phase0_toolchain_inventory.json` exists; `red_count == 0`.
- [ ] `phase0_project_class.json` exists; `confidence >= 0.8`, or `phase0_intake.json.project_class_confirmed` records the human-confirmed override.
- [ ] `phase0_skill_inventory.json` exists.
- [ ] `phase0_intake.json` exists with user-confirmed values.
- [ ] `<workspace>/AGENTS.md` contains the gauntlet mandate paragraph.
- [ ] `<workspace>/MEMORY.md` exists (initial session_001 entry).
- [ ] `<workspace>/.git/` initialized.
- [ ] Phase 0 oracle-preflight readiness recorded; `yellow` is acceptable until Phase 2 pins contracts and Phase 3 wires the oracle, but `red` blocks.
- **Validator:** `scripts/oracle-preflight-doctor.sh <target> --workspace <workspace>` exits 0 (green) or 1 (yellow/advisory); exit 2 is red/blocking.

### Phase 1 — RECON
- [ ] `phase1_recon_<crate>.md` exists for every crate in `<port>/crates/*/`.
- [ ] `phase1_unified_recon.md` collates all per-crate reports.
- [ ] Total `public_api_count` across all crates is non-zero (sanity).
- [ ] Every per-crate file's frontmatter validates against `gauntlet.phase1_recon.v1` schema.
- **Validator:** orchestrator manually checks per-crate file presence; no script (recon is judgment-laden).

### Phase 2 — REFERENCE PINNING + SURFACE CONTRACT
- [ ] `docs/contracts/<reference>_version_contract.toml` exists; valid TOML; `schema_version` field present.
- [ ] `docs/contracts/supported_surface_matrix.toml` exists; every feature has status `in {present, partial, missing, n/a, excluded}`; every `excluded` has both `exclusion_rationale` and `retry_condition_predicate`.
- [ ] `docs/contracts/parity_score_contract.toml` exists; loader-enforced `sum(weights) == 1.0` per category passes.
- [ ] `docs/canonical_parity_contract.md` exists (the narrative).
- [ ] `phase2_scope_decision.md` documents what's in scope + what's explicitly out.
- **Validator:** `scripts/check-contracts.sh <workspace>` exits 0.

### Phase 3 — ORACLE WIRING
- [ ] `crates/<port>-harness/src/oracle.rs` exists with the 30-line `scenario()` template + EngineIdentity constants.
- [ ] `crates/<port>-harness/src/differential_v2.rs` exists with `ExecutionEnvelope` + `artifact_id()`.
- [ ] `crates/<port>-harness/src/oracle_preflight_doctor.rs` exists; runs green on the current workspace.
- [ ] `tests/oracle_smoke.rs` passes (the scenario template against one fixture).
- **Validator:** `scripts/oracle-preflight-doctor.sh <target> --workspace <workspace>` re-run; still green.

### Phase 4 — GOLDEN CAPTURE
- [ ] `<workspace>/golden/manifest.v1.json` exists; SHA-256s match files.
- [ ] `<workspace>/golden/checksums.sha256` exists; valid format.
- [ ] At least one Tier 1, one Tier 2, one Tier 3 fixture present.
- **Validator:** `scripts/verify-golden-integrity.sh <workspace>` exits 0.

### Phase 5 — PERFORMANCE HARNESS
- [ ] `crates/<port>-e2e/src/bin/comprehensive-bench.rs` exists with the 6 timing constants verbatim + `measure()` + `measure_with_teardown()`.
- [ ] `.bench-history/<primary-bench>.latest.json` exists (initial no-op baseline).
- [ ] `crates/<port>-harness/src/perf_loop.rs` exists.
- [ ] `Cargo.toml` includes the `[profile.release-perf]` block verbatim.
- [ ] `concurrent_mode_default_guard.txt` (or class-equivalent) writer is wired into every bench.
- **Validator:** `cargo build --profile release-perf --bin comprehensive-bench` succeeds.

### Phase 6 — CONFORMANCE HARNESS
- [ ] Per-behavior-class `<class>_oracle_e2e.rs` exists; each compiles + passes against a smoke fixture.
- [ ] `metamorphic.rs` exists with all 4 TransformFamily variants + EquivalenceExpectation + MismatchClassification + SeedContract.
- [ ] `mismatch_minimizer.rs` exists + `MismatchSignature` dedup tested.
- [ ] Per-class FaultSpec / FaultVfs exists (`fault_vfs.rs` or class-equivalent).
- [ ] All named crash boundaries wired (8 for SQL, 6+ for RESP, 5+2 for ML, 5 for HTTP).
- [ ] `eprocess.rs` exists; per-invariant calibration loaded from `docs/contracts/eprocess_calibration.toml`.
- [ ] `replay_harness.rs` exists with BOCPD regime detection.
- **Validator:** `cargo test --lib -p <port>-harness` exits 0.

### Phase 7 — SURFACE PARITY INVENTORY
- [ ] `parity_taxonomy.rs` exists; loader enforces sum-of-weights + iteration order.
- [ ] `invariant_catalog.rs` exists; every invariant has `ProofObligation` array.
- [ ] `feature_coverage_dashboard.rs` exists; runs against the surface matrix.
- [ ] `validation_manifest.rs` exists; aggregates evidence.
- [ ] `verification_contract_enforcement.rs` exists; gating logic wired.
- **Validator:** `cargo test --lib -p <port>-harness parity` exits 0.

### Phase 8 — NEGATIVE-LEDGER + AGENTS.MD MANDATE
- [ ] `docs/progress/perf-negative-results.md` exists with verbatim preamble.
- [ ] `docs/progress/conformance-negative-results.md` exists.
- [ ] `docs/progress/surface-deferrals.md` exists.
- [ ] `<port>/AGENTS.md` (target project's, not the workspace's) updated with the mandate paragraph.
- **Validator:** `scripts/mine-ledger.sh --lint docs/progress/perf-negative-results.md` exits 0.

### Phase 9 — BASELINE RUN
- [ ] `phase9_baseline_summary.md` exists.
- [ ] `phase9_baseline/conformance_findings.json` valid.
- [ ] `phase9_baseline/perf_findings.json` valid; `comprehensive_bench_report` points to a real JSON v3.
- [ ] `phase9_baseline/surface_findings.json` valid.
- [ ] `.bench-history/<primary-bench>.latest.json` updated and committed.
- [ ] `reports/ratchet_state.json` initialized from the baseline scores.
- [ ] Every divergence has a FailureBundle.
- **Validator:** `scripts/compute-parity-score.sh <workspace>` produces a valid scorecards.json.

### Phase 10 — IDEA-WIZARD ROUND
- [ ] `phase10_idea_wizard_yield.md` exists with at least 5 promoted techniques.
- [ ] Each promoted technique has an entry in the appropriate hypothesis ledger.
- **Validator:** none — judgment-laden.

### Phase 11 — ITERATE PHASES 5-10
- [ ] `round_count >= 10` in `reports/convergence_tracker.json`.
- [ ] `clean_last_two == true`.
- [ ] `open_hypothesis_count == 0`.
- [ ] Every round directory `round_<N>/` exists with the standard layout.
- **Validator:** `scripts/convergence-tracker.sh <workspace>` exits 0.

### Phase 12 — REMEDIATION DESIGN
- [ ] `phase12_remediation_<gap>.md` exists for every confirmed gap (severity > LOW).
- [ ] `phase12_remediation_index.md` lists all per-gap files.
- [ ] Every per-gap file declares: selected rewrite + score + at least 1 runner-up + test/remediation evidence references.
- [ ] Perf candidates: `Impact × Confidence / Effort >= 2.0`.
- [ ] Conformance candidates: conformal-lower-bound monotonicity check passes.
- [ ] Surface candidates: `partial → full` for at least one Feature.
- **Validator:** orchestrator's manual review against `methodology/RUBRICS.md`.

### Phase 13 — BEADS HANDOFF
- [ ] `.beads/issues.jsonl` populated with every remediation as a bead.
- [ ] `br dep cycles` returns empty.
- [ ] `bv --robot-insights | jq '(.Cycles // []) | length == 0'` passes.
- [ ] Every remediation bead has: test-bead dep + bench-bead dep + doc-bead dep.
- [ ] `phase13_beads_summary.md` exists with frontmatter passing `gauntlet.phase13_beads_summary.v1`.
- **Validator:** `scripts/bead-graph-validator.sh <target> --output-root <workspace>` exits 0.

### Phase 14 — FRESH-EYES REVIEW
- [ ] `phase14_fresh_eyes_diff.md` cumulative diff exists.
- [ ] At least 2 consecutive clean rounds documented.
- [ ] Static gates green: `cargo check` + `cargo clippy -D warnings` + `cargo fmt --check` + `cargo test --workspace`.
- [ ] Optional T3+: `phase14_red_team_<lens>.md` for each invoked lens; `phase14_triangulation_<lens>/CONSENSUS.md` for each invoked lens; no CRITICAL findings open.
- **Validator:** `scripts/run-fresh-eyes-pass.sh <target> <workspace>` exits 0.

### Phase 15 — SOAK / DEEP-VALIDATION
- [ ] Every soak runner ran for its target duration AND produced a `summary.json`.
- [ ] BOCPD terminal regime is `Stable`.
- [ ] Zero CRITICAL adversarial findings open.
- [ ] Zero `TrueDivergence` newly surfaced.
- [ ] Miri findings count is 0 OR every finding has an open bead.
- **Validator:** orchestrator's manual review of each `phase15_soak_*/summary.json`.

### Phase 16 — FINAL ARTIFACTS
- [ ] `FINAL_GAUNTLET_REPORT.md` rendered + all 9 sections populated.
- [ ] `PARITY_RUNBOOK.md` rendered + all 10 sections populated.
- [ ] `RELEASE_CERTIFICATION_TEMPLATE.md` rendered.
- [ ] `certification_bundle/` exists with all 9 required JSON files + `BUNDLE_MANIFEST.json`.
- [ ] `cookbook/` populated with 12+ recipes.
- [ ] `release_certificate.json#/certifying == true` (or `RELEASE_BLOCKED.md` written).
- **Validator:** `scripts/final-report-builder.sh <workspace>` exits 0.

---

## Per-bead exit criteria (Definition of Done)

A bead can close only when:

- [ ] Implementation: the change exists in the port's source tree at a specific commit.
- [ ] Test evidence: a test-type dependency bead is closed (oracle test / metamorphic property / sanitizer run / fuzz target / property test / golden snapshot).
- [ ] Bench evidence: for perf-affecting beads, a bench-type dependency bead is closed (criterion / hyperfine / comprehensive-bench).
- [ ] Doc evidence: a doc-type dependency bead is closed (`// SAFETY:` comment added, `# Safety` doc section updated, `docs/contracts/*.toml` declaration current, spec-document section updated, AGENTS.md guidance updated if applicable).
- [ ] Proof pack: for perf-affecting beads, `artifacts/<bead_id>/proof_pack/` exists with all 13 required artifacts per `methodology/PROOF-PACK-RUBRIC.md`.
- [ ] Ratchet OK: `scripts/apply-ratchet.sh` returns `Allow` (or `Waiver` with signed-off waiver).
- [ ] Verification contract: `scripts/bead-graph-validator.sh` accepts this bead.
- [ ] Negative-ledger entry: if the bead is a perf rejection, the ledger entry has a retry-condition predicate from the 8 verbatim forms.

The bead-close hook (`assets/hooks/run-bead-graph-validator.sh` if installed) enforces these at PreToolUse on `git commit`.

## Per-pillar release-readiness

The gauntlet is RELEASE-READY when:

- [ ] Convergence reached (Phase 11 exit criteria).
- [ ] Phase 14 fresh-eyes clean for 2 consecutive rounds; static gates green.
- [ ] Phase 15 soak: terminal BOCPD regime Stable; no CRITICAL adversarial; no new TrueDivergence; Miri clean.
- [ ] All Phase 12 remediations have closed beads.
- [ ] `certification_bundle/release_certificate.json#/certifying == true`.

If any check fails, the workspace is NOT release-ready. The orchestrator writes `<workspace>/RELEASE_NOT_READY.md` explaining which check failed.

## Cross-references

- [`PHASES.md`](../PHASES.md) — per-phase playbook with full details.
- [`methodology/CONVERGENCE.md`](CONVERGENCE.md) — Phase 11 convergence math.
- [`methodology/PROOF-PACK-RUBRIC.md`](PROOF-PACK-RUBRIC.md) — proof-pack 13 artifacts.
- [`methodology/CERTIFICATION.md`](CERTIFICATION.md) — strict-conformant-release.v1 constants.
- [`methodology/RUBRICS.md`](RUBRICS.md) — per-pillar candidate scoring.
