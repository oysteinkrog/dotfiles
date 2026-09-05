# oracle-preflight-doctor-builder

> Phase 3 • Build `oracle_preflight_doctor.rs` with per-class adaptations; the green/yellow/red precondition gate for every parity / certification lane.

## Inputs
- `<workspace>/phase0_project_class.json` (selects per-class checks).
- `<workspace>/docs/contracts/<reference>_version_contract.toml` (expected version + binary path).
- `oracle.rs` + `differential_v2.rs` from `oracle-wirer.md` (identity strings to enforce).

## Deliverables
- `<target>/crates/<project>-harness/src/oracle_preflight_doctor.rs` with deterministic JSON report.
- `<workspace>/phase3_oracle_preflight_<class>.md` documenting check list, remediation classes, fix-command catalog.
- CLI shim `bin/oracle-preflight-doctor` runnable as `cargo run --bin oracle-preflight-doctor -- --json`.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase3-preflight-<class>`
- **Reservations needed:** `tool://preflight-write` (TTL 60m), `resource://reference-binary::<class>` (TTL 60m).
- **Lane:** cc_1 (conformance).

## Verbatim Prompt

You are building the `oracle_preflight_doctor.rs` module. It runs BEFORE every parity / certification lane and emits a deterministic JSON report with a single aggregate verdict (`green | yellow | red`). Only `green` permits the downstream lane to start; `certifying: true` is set ONLY when aggregate is `green`.

Universal report fields (every class):
- `schema_version` ("oracle-preflight-doctor.v1"), `bead_id`, `run_id`, `trace_id`, `scenario_id`, `seed`
- `generated_timestamp` (ISO-8601 UTC)
- `aggregate_outcome` ("green" | "yellow" | "red")
- `certifying: bool` (true iff aggregate is "green")
- `first_failure_diagnosis` (null if aggregate green)
- `fixture_ingestion_counters` (per-category)
- `resolved_<reference>_binary_path`, `resolved_<reference>_version`
- `fixture_manifest_mtime`, `fixture_manifest_sha256`
- `deterministic_replay_command`
- `remediation_class` + `fix_command` per failed check.

Per-class checks:

**SQL-class:** `rusqlite` link version equals contract; oracle binary exists; subject identity is "<port>"; reference identity is "<reference>-oracle"; fixture corpus cardinality floors met; manifest mtime fresh; manifest SHA-256 matches.

**RESP-class:** server version + protocol mode (RESP2/RESP3) + persistence (RDB/AOF) + module set + cluster mode.

**ML-System-class:** PyTorch version + CUDA/cuDNN/driver version + determinism flags (`torch.use_deterministic_algorithms(True)`) + dtype policy + RNG seed policy + model corpus hashes.

**Numerical-Python-class:** NumPy version + SIMD flags + RNG state policy + BLAS thread count.

**HTTP-Protocol-class:** reference framework version + deterministic clock confirmed + RNG seeded + fixture corpus cardinality floors.

For each check that can fail in a known way, record a `remediation_class` (e.g., `version_mismatch | binary_missing | identity_swap | manifest_stale`) and a `fix_command` (an exact one-line shell invocation the next agent can run).

Output must be deterministic byte-for-byte across runs with the same env (same git SHA, same fixtures, same reference binary). Sort all JSON keys; use ISO-8601 with explicit UTC; truncate any floats per `truncate_score` policy.

Document the check list, remediation classes, and fix commands in `phase3_oracle_preflight_<class>.md`. Commit `oracle_preflight_doctor.rs` + the bin shim + the markdown.

## Exit Criteria
- `cargo run --bin oracle-preflight-doctor -- --json` exits zero with `aggregate_outcome: "green"` on a clean workspace.
- Deliberately corrupting the fixture manifest yields `aggregate_outcome: "red"` with the correct `remediation_class` and a fix-command that, when run, restores green.
- Deliberately swapping identity strings yields a red verdict with `remediation_class: identity_swap`.
- `phase3_oracle_preflight_<class>.md` committed.

## References
- [PHASES.md § Phase 3](../references/PHASES.md)
- [tooling/ORACLE-TOOLCHAIN.md § oracle preflight doctor](../references/tooling/ORACLE-TOOLCHAIN.md)
- [methodology/IDENTITY-AND-REPRODUCIBILITY.md](../references/methodology/IDENTITY-AND-REPRODUCIBILITY.md)
- [taxonomy/PROJECT-CLASSES.md](../references/taxonomy/PROJECT-CLASSES.md)
