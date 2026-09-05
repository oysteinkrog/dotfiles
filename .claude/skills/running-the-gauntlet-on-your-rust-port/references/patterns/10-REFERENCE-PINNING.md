# Pattern 10 — REFERENCE PINNING (`<reference>_version_contract.toml`)

## What

A single TOML file at `docs/contracts/<reference>_version_contract.toml` that names the exact reference version the port is being tested against, the vendor method (linked / vendored / pyo3-bridge / http-replay), the fixture corpus's SHA-256 manifest, the subject/reference identity strings (K-9), the byte-identical PRAGMAs (K-4), and the contract revision counter. Every artifact in the gauntlet embeds the contract's SHA-256 so a silent drift (e.g., a CI image bump that changes the reference binary version) is caught by `oracle-preflight-doctor.sh` on the next run.

## Why

> "If a silent drift (e.g., a CI image bump that changes the reference binary version) is caught by oracle-preflight-doctor.sh on the next run." — [assets/version-contract-template.toml](../../assets/version-contract-template.toml) header

Without a pinned contract, "tested against the reference" means "tested against whatever the reference was on the day this CI job happened to run." This shows up as silent drift: parity drops by 2% overnight because the base image bumped `sqlite3` from 3.51.0 to 3.52.0 and the new version changes NULL handling in one obscure edge case. The contract turns this into a loud failure: the oracle-preflight-doctor refuses to certify, and the agent must explicitly bump `revision` and re-baseline.

## Where in FrankenSQLite

- `docs/contracts/sqlite_version_contract.toml` — pinned SQLite 3.52.0, vendor_method "linked", fixture manifest SHA, identity strings `frankensqlite` / `csqlite-oracle`.
- `crates/fsqlite-harness/src/oracle_preflight_doctor.rs` — reads and asserts contract; emits green/yellow/red (MINING-2 §13).
- `crates/fsqlite-harness/src/fixture_root_contract.rs` — `FixtureRootContract.manifest_sha256` field; see [pattern:25-FIXTURE-ROOT-CONTRACT](25-FIXTURE-ROOT-CONTRACT.md).

## Verbatim shape — the TOML schema

From [`assets/version-contract-template.toml`](../../assets/version-contract-template.toml), verbatim header:

```toml
schema_version = "gauntlet.version_contract.v1"

[reference]
name = "<REFERENCE_NAME>"                  # e.g. "sqlite", "redis", "torch", "numpy"
version = "<PINNED_VERSION>"               # e.g. "3.52.0", "7.2.5", "2.1.2", "1.26.0"
source_url = "<DOWNLOAD_URL>"
source_sha256 = "<SHA256_OF_SOURCE_TARBALL>"
vendor_method = "<linked|vendored|pyo3-bridge|http-replay>"
build_flags = []
configure_args = []

[reference.extras]
# per-class fields (see Per-class table below)

[fixture_corpus]
manifest_sha256 = "<SHA256_OF_FIXTURE_MANIFEST_FILE>"
fixture_directory = "<RELATIVE_PATH_FROM_PROJECT_ROOT>"

[fixture_corpus.cardinality_floors]
# per-category minimums; preflight-doctor refuses if shrunk

[fixture_corpus.required_category_families]
families = [...]

[[fixture_corpus.hash_locked_roots]]
path = "<RELATIVE_PATH>"
expected_content_hash = "<SHA256>"

[fixture_corpus.included_extensions]
extensions = [...]
minimum_included_files = 0

[engine_identity]
subject_identity_label = "<PORT_NAME>"               # e.g. "frankensqlite"
reference_identity_label = "<REFERENCE_NAME>-oracle" # e.g. "csqlite-oracle"

[pragmas]
# per-class identical-config (see Per-class table)

[contract_metadata]
created_at_utc = "<ISO_8601>"
created_by_agent = "scope-decider"
ratchet_floor_at_creation = 0.0
revision = 1
```

## Per-class instantiation

| Class | Contract filename | `vendor_method` | `[reference.extras]` keys | `[pragmas]` keys |
|---|---|---|---|---|
| **SQL** (frankensqlite, sqlmodel_rust) | `sqlite_version_contract.toml` | `linked` (via `libsqlite3-sys`) | `enable_fts5`, `enable_rtree`, `enable_json1` | `journal_mode = "wal"`, `synchronous = "NORMAL"`, `cache_size = -2000`, `page_size = 4096`, `foreign_keys = true` |
| **RESP** (frankenredis) | `redis_version_contract.toml` | `vendored` (`redis-server` binary, UNIX socket) | `modules = ["RedisJSON", "RedisSearch"]`, `cluster_mode = false` | `protocol_version = 3`, `persistence = "aof+rdb"`, `maxmemory_policy = "noeviction"` |
| **ML** (frankentorch, frankenjax) | `torch_version_contract.toml` (or `jax_version_contract.toml`) | `pyo3-bridge` | `cuda_version = "12.2"`, `cudnn_version = "8.9.5"`, `driver_version = "535.104.05"`, `determinism_flags = ["torch.use_deterministic_algorithms(True)"]`, `dtype_policy = "float32"`, `rng_seed_policy = "torch.manual_seed(42); numpy.random.seed(42); random.seed(42)"` | `torch_use_deterministic_algorithms = true`, `torch_set_num_threads = 1`, `cuda_deterministic = true` |
| **Numerical** (franken_numpy, frankenpandas, frankenscipy) | `numpy_version_contract.toml` (etc.) | `pyo3-bridge` | `simd_flags = ["avx2", "fma"]`, `blas_impl = "openblas"`, `blas_threads = 1`, `rng_state_policy = "PCG64DXSM-bit-exact"` | `numpy_seterr = "raise"`, `blas_set_num_threads = 1` |
| **HTTP** (fastapi_rust, fastmcp_rust) | `fastapi_version_contract.toml` (or `mcp_version_contract.toml`) | `http-replay` (recorded transcripts) | `framework = "fastapi"`, `framework_version = "0.110.0"`, `middleware_stack_hash = "<sha256>"` | `request_timeout_ms = 30000`, `max_body_size_bytes = 1048576` |

## Composition

- [pattern:15-ENGINE-IDENTITY](15-ENGINE-IDENTITY.md) — `[engine_identity]` block sources the two labels asserted by the K-9 discriminator.
- [pattern:20-ORACLE-PREFLIGHT-DOCTOR](20-ORACLE-PREFLIGHT-DOCTOR.md) — reads this contract on every certification lane; refuses to certify if revision is stale or fixture manifest hash drifted.
- [pattern:25-FIXTURE-ROOT-CONTRACT](25-FIXTURE-ROOT-CONTRACT.md) — `[fixture_corpus]` block is hashed into a `FixtureRootContract` struct.
- [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) — every envelope embeds the contract's SHA-256 in `EngineVersions.csqlite` (or class-equivalent).
- [pattern:75-BAYESIAN-CONFORMAL-SCORE](75-BAYESIAN-CONFORMAL-SCORE.md) — `ratchet_floor_at_creation` is the initial conformal lower bound; the ratchet only ever monotonically increases this value.

## Pitfalls

- **Contract not committed to git.** A `.toml` in `.gitignore` is not a contract. The whole point is reviewability and CI-checkability.
- **`revision` never incremented.** When the reference version bumps, the agent must edit `version`, `source_sha256`, `[reference.extras]` as appropriate, AND bump `revision`. The preflight doctor uses `revision` to detect "agent edited the contract but didn't notice they were re-baselining" — every revision bump triggers a new baseline capture.
- **`fixture_corpus.manifest_sha256` left as placeholder.** The preflight doctor refuses if the value is `<SHA256_OF_FIXTURE_MANIFEST_FILE>`; the literal token short-circuits to red.
- **PRAGMAs declared in the contract but not applied at the harness.** The contract is the source of truth; the harness must read `[pragmas]` and apply, not duplicate the values inline. Mismatch between contract `[pragmas]` and harness-applied PRAGMAs is the K-4 anti-pattern in disguise.
- **Multiple contracts for one project.** If the project pins both `sqlite_version_contract.toml` and `sqlite_secondary_version_contract.toml`, the preflight doctor must read both and assert consistency. The cleaner alternative: one contract per `[reference]` table, multi-reference projects use `[[reference]]` arrays.
- **Vendoring the reference but not pinning the build flags.** Two builds of SQLite 3.52.0 with different `--enable-fts5` compile differently and parse differently for FTS queries. `build_flags` and `configure_args` must be filled or `vendor_method = "vendored"` is a lie.
