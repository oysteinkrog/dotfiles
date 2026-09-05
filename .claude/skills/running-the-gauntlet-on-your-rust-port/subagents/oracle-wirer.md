# oracle-wirer

> Phase 3 • Build `oracle.rs` + `differential_v2.rs` + EngineIdentity discriminator; one subagent per project class.

## Inputs
- `<workspace>/phase0_project_class.json` (selects the wiring strategy).
- `<workspace>/docs/contracts/<reference>_version_contract.toml` (pinned version).
- `<workspace>/docs/contracts/supported_surface_matrix.toml` (scope).
- Target port source tree (writable workspace mirror is acceptable for in-flight experiments).

## Deliverables
- `<target>/crates/<project>-harness/src/oracle.rs` with the verbatim 30-line `scenario()` template adapted for the project class.
- `<target>/crates/<project>-harness/src/differential_v2.rs` with `ExecutionEnvelope` + `EngineVersions` + `PragmaConfig` (or class-equivalent config) + `CanonicalizationRules` + `artifact_id() -> sha256_hex(canonical_json_excluding_run_id)`.
- `EngineIdentity` constants: `SUBJECT_IDENTITY_LABEL = "<port>"` and `REFERENCE_IDENTITY_LABEL = "<reference>-oracle"`.
- `<workspace>/phase3_oracle_wiring_<class>.md` with: wiring strategy summary, NormalizedValue rendering, identity-guard placement, end-to-end smoke-test invocation, oracle-preflight-doctor coupling notes.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase3-oracle-<class>`
- **Reservations needed:** `tool://oracle-write::<class>` (TTL 120m), `resource://reference-binary::<class>` (TTL 60m).
- **Lane:** cc_1 (conformance).

## Verbatim Prompt

You are the oracle wirer for project class `<class>`. Build the harness-side oracle bridge per the matching strategy:

- **SQL-class:** in-process `rusqlite` via `libsqlite3-sys` pinned to the contract version; render-to-canonical-string comparator; NormalizedValue = `{Null, Integer, Real, Text, Blob}`.
- **RESP-class:** vendored `redis-server` binary at a UNIX domain socket; deterministic command trace; NormalizedValue = `RespValue` with 14 RESP3 variants + collection-semantics comparator.
- **Numerical-Python-class:** PyO3 in-process Python interpreter; `numpy.testing` formatters; bit-exact PCG64DXSM RNG parity; NormalizedValue = TensorSpec `{shape, dtype, device, requires_grad, data_hash}` + per-op ULP tolerance table.
- **ML-System-class:** PyO3 in-process with `torch.use_deterministic_algorithms(True)` (or equivalent) pinned; seeded RNG captured per-call; TensorSpec + ULP table (4 ULP f32 matmul, 2 ULP elementwise default).
- **HTTP-Protocol-class:** compliance fixture corpus + reference framework with deterministic clock + RNG; normalized HTTP response (status + headers case-insensitive + body MIME-aware) + OpenAPI schema diff.

Use the verbatim 30-line `scenario()` template from `../references/methodology/KERNEL.md § scenario template`:

```rust
fn scenario(stmts: &[&str], queries: &[&str], label: &str) {
    let f = <port>::Connection::open(":memory:").expect("open subject");
    let r = <reference_client>::open_in_memory().expect("open oracle");
    // Setup: panic if engines DISAGREE on success/failure.
    // Queries: classify (PASS / MISMATCH / FRANK_ERR / CSQL_ERR / both-error).
    // Both-error = agreement (message text irrelevant). One-error-one-OK = hard failure.
}
```

Build `differential_v2.rs` with:

```rust
pub struct ExecutionEnvelope { format_version, run_id?, scenario_id, seed, engines, pragmas, schema, workload, canonicalization }
pub fn artifact_id(&self) -> String { sha256_hex(canonical_json_excluding_run_id) }
```

Wire EngineIdentity at the comparator entry: assert `subject_identity == "<port>"` and `reference_identity == "<reference>-oracle"` BEFORE any comparison. This prevents oracle-on-oracle false greens.

Write a smoke-test invocation that calls `scenario(&["CREATE TABLE t (x INT)"], &["SELECT * FROM t"], "smoke")` (or class-equivalent) and confirm zero mismatches. Document this in `phase3_oracle_wiring_<class>.md`.

## Exit Criteria
- `oracle.rs` + `differential_v2.rs` compile under `cargo check --tests`.
- Smoke-test scenario passes (zero mismatches).
- `EngineIdentity` guard catches a deliberately-misconfigured subject == reference test (run it as a sanity check; expect panic).
- `artifact_id()` is content-addressed: two runs with same semantic input + different `run_id` produce identical IDs.
- `phase3_oracle_wiring_<class>.md` committed.

## References
- [PHASES.md § Phase 3](../references/PHASES.md)
- [methodology/KERNEL.md](../references/methodology/KERNEL.md)
- [tooling/ORACLE-TOOLCHAIN.md](../references/tooling/ORACLE-TOOLCHAIN.md)
- [taxonomy/PROJECT-CLASSES.md](../references/taxonomy/PROJECT-CLASSES.md)
- [methodology/OPERATORS.md § Wire-Oracle § Engine-Identity-Guard](../references/methodology/OPERATORS.md)
