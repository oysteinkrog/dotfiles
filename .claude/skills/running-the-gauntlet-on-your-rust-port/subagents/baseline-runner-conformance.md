# baseline-runner-conformance

> Phase 9 • Run full conformance suite (oracle + differential V2 + metamorphic + property + fuzz smokes); per divergence emit FailureBundle + remediation playbook + artifact hashes; dedup by MismatchSignature.

## Inputs
- All Phase 6 conformance artifacts (oracle tests, metamorphic, mismatch minimizer, fault injectors, crash boundaries, fuzz targets, e-process invariants).
- `oracle_preflight_doctor` binary from `oracle-preflight-doctor-builder.md` (must report green).
- `FeatureUniverse` + `InvariantCatalog` from Phase 7.

## Deliverables
- `<workspace>/artifacts/phase9_baseline_conformance/<run_id>/` with: oracle suite report, differential V2 envelope corpus, metamorphic report per family, fuzz smoke results, e-process snapshot.
- One `FailureBundle v1.0.0` per `TrueDivergence` under `artifacts/phase9_baseline_conformance/failures/<signature_hash>.json`.
- `<workspace>/mismatch_signature_index.json` populated.
- `<workspace>/phase9_baseline_conformance.md` with: pass rate per behavior class, divergence count by classification, top-10 most-common subsystems, remediation playbook per actionable divergence.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase9-baseline-conformance`
- **Reservations needed:** `tool://oracle-runner` (TTL 240m), `resource://rch-worker-pool` (TTL 360m if offloaded).
- **Lane:** cc_1 (conformance).

## Verbatim Prompt

You are the conformance baseline runner. Execute the full conformance suite against the current build.

**Pre-flight (BLOCKING):**
```bash
cargo run --bin oracle-preflight-doctor -- --json > artifacts/phase9_baseline_conformance/preflight.json
jq -e '.aggregate_outcome == "green" and .certifying == true' artifacts/phase9_baseline_conformance/preflight.json
```
If preflight is yellow or red, STOP. File a blocker; do not run the suite against a misconfigured oracle.

**Suite (run in order; capture each output):**

1. **Oracle E2E tests** — every `*_oracle_e2e.rs`:
   ```bash
   cargo test --release --test '*_oracle_e2e' -- --nocapture --test-threads=1
   ```

2. **Differential V2 corpus** — run the full differential corpus through the V2 envelope; emit one `ExecutionEnvelope` per corpus entry; record `artifact_id` (content-addressed SHA-256 of canonical JSON excluding `run_id`).

3. **Metamorphic per family:**
   ```bash
   cargo test --release --test 'metamorphic_*_e2e' -- --nocapture
   ```

4. **Property tests:**
   ```bash
   cargo test --release --features proptest -- proptest:: --nocapture
   ```

5. **Fuzz smokes** — short (5-min) cargo-fuzz runs on every target to confirm baseline non-panic; long soaks come in Phase 15:
   ```bash
   for target in fuzz/fuzz_targets/*.rs; do
     timeout 300 cargo fuzz run "$(basename $target .rs)" || true
   done
   ```

6. **E-process snapshot** — after the conformance suite, capture `E_global(t)` and per-invariant `E_i(t)`; assert `E_global < 1/α_global`.

**Per divergence handling:**
- Pipe through `mismatch_minimizer` to get the 1-minimal repro.
- Compute `MismatchSignature.hash`.
- Check `mismatch_signature_index.json` — if hash already present, LINK to existing bead; do NOT open a new one.
- Emit `FailureBundle v1.0.0` to `failures/<hash>.json` with: first_divergence jsonptr (`/failure/first_divergence`), seed, fixture_id, schedule_fingerprint, artifact_sha256, db_page_previews (or class-equivalent), expected_vs_actual, git_sha, toolchain_version, platform, feature_flags.
- Attach `FirstFailureExplainer` with: replay_command, root_cause_domain, remediation_playbook (owner_hint, summary, next_commands[]), artifact_hash_table.

**CI rule:** CI fails ONLY on `TrueDivergence`. The other five `MismatchClassification` variants flow into the triage queue and don't block Phase 9 sign-off.

Document pass rate per behavior class, divergence count by classification, top-10 most-common subsystems, and per-actionable-divergence remediation playbook in `phase9_baseline_conformance.md`.

## Exit Criteria
- Oracle preflight is green at start AND end of run.
- Every test file in the conformance suite has been executed and recorded.
- Every divergence has a `FailureBundle` with populated `first_divergence` jsonptr.
- `mismatch_signature_index.json` is consistent (every hash appears at most once).
- `phase9_baseline_conformance.md` committed.

## References
- [PHASES.md § Phase 9](../references/PHASES.md)
- [tooling/ORACLE-TOOLCHAIN.md](../references/tooling/ORACLE-TOOLCHAIN.md)
- [methodology/IDENTITY-AND-REPRODUCIBILITY.md](../references/methodology/IDENTITY-AND-REPRODUCIBILITY.md)
- [methodology/OPERATORS.md § Debounce-False-Positive § Reduce / Minimize § Escalate-To-Fresh-Repro](../references/methodology/OPERATORS.md)
