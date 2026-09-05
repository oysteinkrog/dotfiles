# Pattern 20 — ORACLE PREFLIGHT DOCTOR (green/yellow/red precondition gate)

## What

A deterministic check that runs *before* any parity / certification / differential lane. Emits a structured report with an aggregate verdict (`green | yellow | red`) and refuses to certify (`certifying: true`) unless verdict is `green`. Verifies: reference binary path + version, identity strings (K-9), fixture corpus cardinality floors, fixture manifest mtime freshness, manifest SHA-256 match, and remediation class + fix command for every failure. Implemented as `scripts/oracle-preflight-doctor.sh` plus `crates/<project>-harness/src/oracle_preflight_doctor.rs`.

## Why

> "Aggregate outcome: green | yellow | red. **certifying: true ONLY for green**." — MINING-2 §13

Without a preflight, a certification run will happily execute against a missing `redis-server` binary (subprocess fails, all tests skip, lane reports "0 failures / 0 tests"), or against a fixture corpus shrunk by an accidental `rm -rf`, or against a reference binary that's the wrong version. The preflight is the K-2 instantiation for the oracle harness: *honesty in the harness* means the harness refuses to run before it knows what it's measuring against.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/oracle_preflight_doctor.rs` — the verifier
- `scripts/oracle-preflight-doctor.sh` — wrapper called by every Phase-3+ lane in the gauntlet
- Output: `<workspace>/phase3_oracle_preflight.json`

## Verbatim shape — emission fields

From MINING-2 §13, verbatim list of every field in the report:

- `schema_version`
- `bead_id`
- `run_id`
- `trace_id`
- `scenario_id`
- `seed`
- `generated_at` (UTC timestamp)
- `aggregate_outcome`: `green | yellow | red`
- `certifying`: bool (true ONLY for green)
- `first_failure_diagnosis`
- `fixture_ingestion_counters`
- `resolved_reference_binary_path` (e.g., resolved `sqlite3` path)
- `resolved_reference_version` (e.g., "3.52.0")
- `fixture_manifest_mtime`
- `fixture_manifest_sha256`
- `deterministic_replay_command`
- `remediation_class`
- `fix_command`

### What the doctor verifies (verbatim from MINING-2 §13)

> "C SQLite oracle binary exists; expected version matches contract (3.52.0); subject identity is 'frankensqlite'; reference identity is 'csqlite-oracle'; fixture corpus cardinality floors met; fixture manifest mtime fresh; manifest SHA-256 matches."

### Verdict semantics

| Verdict | `certifying` | Meaning |
|---|---|---|
| **green** | `true` | All checks pass; certification lanes may run. |
| **yellow** | `false` | Non-blocking warnings (e.g., fixture manifest mtime older than 7 days but SHA matches); test lanes may run but the run is not certifying. |
| **red** | `false` | Blocking failure (binary missing, wrong version, fixture hash drift, identity-label mismatch, cardinality floor violation); no test lane runs. |

## Per-class instantiation

| Class | Reference binary / bridge verification | Identity check | Fixture check |
|---|---|---|---|
| **SQL** | `sqlite3 --version` matches `[reference].version`; `libsqlite3-sys` linked version probed via `unsafe { sqlite3_libversion() }` | `subject == "frankensqlite"`, `reference == "csqlite-oracle"` | SQL fixture count per `[fixture_corpus.cardinality_floors]` (`null_semantics_min`, `group_by_min`, etc.) |
| **RESP** | `redis-server --version` matches contract; protocol mode 3; persistence config matches; module set probed via `MODULE LIST`; cluster mode flag verified | `subject == "frankensqlite"`-class label | RESP fixture counts (`command_min`, `pipeline_min`, `pubsub_min`); RDB v11 byte fixture hashes |
| **ML** | PyTorch version + CUDA version + cuDNN version + driver version match contract; determinism flags applied (`torch.use_deterministic_algorithms(True)` probed); dtype policy applied; RNG seed policy applied; model corpus hashes match | `subject == "frankentorch"`, `reference == "torch-pyo3-oracle"` | Tensor fixture counts per category; safetensors fixture hashes |
| **Numerical** | NumPy version + SIMD flag set + BLAS impl + BLAS thread count + RNG state policy match contract | `subject == "franken_numpy"`, `reference == "numpy-pyo3-oracle"` | `.npy` / `.npz` fixture counts; PCG64DXSM stream fixture hashes |
| **HTTP** | Reference framework version (FastAPI 0.110.0 or MCP version); middleware stack hash matches; deterministic clock + RNG bound | `subject == "fastapi_rust"`, `reference == "fastapi-python-oracle"` | HTTP transcript count per route; OpenAPI golden file SHA |

### `remediation_class` taxonomy

| Class | Triggered when | Example `fix_command` |
|---|---|---|
| `MissingReferenceBinary` | Resolved binary path doesn't exist | `apt-get install -y redis-server && which redis-server` |
| `ReferenceVersionMismatch` | Binary version != contract | `bash scripts/install-pinned-reference.sh sqlite-3.52.0` |
| `IdentityLabelDrift` | Subject/Reference labels don't match contract `[engine_identity]` | Manual: edit `docs/contracts/<reference>_version_contract.toml` and re-run |
| `FixtureCardinalityViolation` | Some category below `cardinality_floors` | `bash scripts/restore-fixtures.sh && bash scripts/check-fixture-manifest.sh` |
| `FixtureManifestHashDrift` | Manifest SHA-256 differs from contract | Investigate `git log -p tests/fixtures/manifest.txt` then bump `[contract_metadata].revision` |
| `FixtureManifestStaleMtime` | Manifest mtime older than 30 days (yellow) | `touch tests/fixtures/manifest.txt && git commit -m "refresh manifest mtime"` |

## Composition

- [pattern:10-REFERENCE-PINNING](10-REFERENCE-PINNING.md) — every check sources its expected value from the version contract.
- [pattern:15-ENGINE-IDENTITY](15-ENGINE-IDENTITY.md) — the identity-string assertion is one of the preflight's checks.
- [pattern:25-FIXTURE-ROOT-CONTRACT](25-FIXTURE-ROOT-CONTRACT.md) — the fixture cardinality/hash checks are wrapped by `FixtureRootContract::verify()`.
- [pattern:90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) — when preflight emits red, a `FailureBundle` is written so the agent has a reproducible repro on disk.
- [pattern:95-FIRST-FAILURE-EXPLAINER](95-FIRST-FAILURE-EXPLAINER.md) — the `first_failure_diagnosis` + `remediation_class` + `fix_command` triple is the preflight's contribution to the CI 5-line summary.

## Pitfalls

- **Preflight runs but result is ignored.** A common shortcut: `oracle-preflight-doctor.sh || true`. This makes the preflight cosmetic. Every CI job must `set -e` and propagate the exit code.
- **Yellow upgraded to green by hand.** "It's just a stale mtime, ship it." No. Yellow is non-certifying by definition. If the run is acceptable as non-certifying, that's fine; if it needs to be certifying, fix the yellow.
- **Doctor checks at startup but not before each lane.** A single preflight at process start doesn't catch a fixture file deleted mid-run (e.g., by a concurrent agent). Each certification lane re-runs preflight at entry, cheaply (the heavy work is cached by manifest SHA).
- **Doctor depends on the harness it's gating.** If `oracle_preflight_doctor.rs` requires `fsqlite::Connection::open` to verify the contract, a broken subject blocks its own preflight. Keep the doctor's dependencies to *reference-side only* + filesystem + version-string parsing.
- **`fixture_manifest_sha256` recomputed from disk every run.** That defeats the contract. The expected SHA lives in `<reference>_version_contract.toml`; the doctor computes the actual SHA and compares. Match = green; mismatch = red with `remediation_class = FixtureManifestHashDrift`.
- **Doctor emits only on red.** Wrong. Every run emits a report (green or otherwise). The `green` reports are what prove the gate ran; their absence is itself a failure signal in CI.
- **Identity labels checked against hardcoded values instead of the contract.** The labels are sourced from `[engine_identity]` in the contract. Hardcoding them in the doctor means a project-name change requires a recompile; sourcing them means a contract edit suffices.
