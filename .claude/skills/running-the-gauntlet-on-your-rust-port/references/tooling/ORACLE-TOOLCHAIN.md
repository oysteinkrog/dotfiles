# ORACLE-TOOLCHAIN.md — Reference Oracle Wiring + Preflight Doctor

How to bridge the subject (the Rust port) to the reference (sqlite, redis, numpy, torch, fastapi, ...) so every conformance claim is a *measurement* against a pinned, identity-asserted oracle, not a *belief*. Cross-links: [BENCH-TOOLCHAIN.md](BENCH-TOOLCHAIN.md) for the bench harness that drives both sides; [FUZZ-TOOLCHAIN.md](FUZZ-TOOLCHAIN.md) for differential-fuzz harnesses; [CONCURRENCY-TOOLCHAIN.md](CONCURRENCY-TOOLCHAIN.md) for fault-VFS wiring.

## 0. The Core Discipline

> **EngineIdentity discriminator + oracle preflight doctor.** Every comparator output carries `Subject::<port>` and `Oracle::<reference>`; asserted-distinct at the comparator. No oracle-vs-oracle false greens; no subject-vs-subject self-comparisons; no silently-swapped reference versions.

---

## 1. The 30-Line `scenario()` Template — Subject vs Oracle Parity

**File:** `crates/<project>-e2e/tests/<behavior>_oracle_e2e.rs`

Verbatim from MINING-2 §1 (SQL-class example; adapt the imports and renderers per class — §5 below):

```rust
fn scenario(stmts: &[&str], queries: &[&str], label: &str) {
    let f = fsqlite::Connection::open(":memory:").expect("open frank");
    let r = rusqlite::Connection::open_in_memory().expect("open rusqlite");

    // 1. Setup: panic if engines DISAGREE on success
    for s in stmts {
        let fe = f.execute(s);
        let re = r.execute_batch(s);
        match (&fe, &re) {
            (Ok(_), Ok(())) | (Err(_), Err(_)) => {},
            (Ok(_), Err(e)) => panic!("frank OK, csql ERROR({e})"),
            (Err(e), Ok(())) => panic!("frank ERROR({e}), csql OK"),
        }
    }

    // 2. Queries: classify each
    let mut mismatches = Vec::new();
    for q in queries {
        match (frank_rows(&f, q), sqlite_rows(&r, q)) {
            (Ok(a), Ok(b)) if a == b   => { /* PASS */ },
            (Ok(a), Ok(b))             => mismatches.push(format!("MISMATCH: {q}\n  frank: {a:?}\n  csql:  {b:?}")),
            (Err(e), Ok(b))            => mismatches.push(format!("FRANK_ERR: {q}\n  frank: ERROR({e})\n  csql:  {b:?}")),
            (Ok(a), Err(e))            => mismatches.push(format!("CSQL_ERR: {q}\n  frank: {a:?}\n  csql: ERROR({e})")),
            (Err(_), Err(_))           => { /* both ERROR — agreement */ },
        }
    }

    assert!(mismatches.is_empty(),
        "{label}: {} mismatch(es)\n{}", mismatches.len(), mismatches.join("\n"));
}
```

### The Critical Rules (Non-Negotiable)

- **Both-error = agreement.** Error message text is irrelevant. Two engines that fail differently on the same input *agree that the input is invalid* — that's parity.
- **One-error-one-OK = hard failure.** If one engine accepts and the other rejects, the engines do not agree on what the language *is*.
- **String rendering uniform:** `Vec<Vec<String>>` with NULL capitalized, integers base-10, floats via `Display`, text in single quotes, blob as `X'<hex>'`. The rendering function is part of the contract — its source code is committed and reviewed.

---

## 2. NormalizedValue Rendering — The Canonical Stringifier

Verbatim from MINING-2 §1 (`oracle.rs` 284–310):

```rust
pub fn normalize_value(value: &str) -> String {
    let trimmed = value.trim();
    if let Ok(f) = trimmed.parse::<f64>() {
        if f.is_nan() { return "NaN".to_string(); }
        if f.is_infinite() {
            return if f.is_sign_positive() { "Inf".to_string() } else { "-Inf".to_string() };
        }
        return format!("{f:.15}");
    }
    if trimmed.is_empty() || trimmed.eq_ignore_ascii_case("null") {
        return "NULL".to_string();
    }
    trimmed.to_string()
}
```

`{f:.15}` is 15 decimal digits — the maximum that round-trips a `f64`. Two `f64`s that render identically at 15 digits are bitwise equal modulo NaN-bit-pattern.

**Per-class generalizations:**
- **Redis:** `render_resp_value()` for RESP3 — 14 variants (see §6 below).
- **Torch:** `render_tensor_spec()` for `(shape, dtype, device, requires_grad)`.
- **NumPy:** `render_ndarray()` for `(shape, dtype, strides, data_hash)`.
- **HTTP:** `render_response()` for `(status, headers_case_insensitive_sorted, body_mime_aware)`.

---

## 3. Differential V2 Envelope — Content-Addressed Artifact Identity

**File:** `crates/<project>-harness/src/differential_v2.rs`

Verbatim struct from MINING-2 §2:

```rust
pub struct ExecutionEnvelope {
    pub format_version: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub run_id: Option<String>,
    #[serde(default = "default_scenario_id")]
    pub scenario_id: String,
    pub seed: u64,
    pub engines: EngineVersions,
    pub pragmas: PragmaConfig,
    pub schema: Vec<String>,
    pub workload: Vec<String>,
    pub canonicalization: CanonicalizationRules,
}
```

### Artifact ID — Content-Addressed

```rust
pub fn artifact_id(&self) -> String {
    let canonical = CanonicalEnvelope {
        // same fields as ExecutionEnvelope MINUS run_id
        format_version: self.format_version,
        scenario_id: self.scenario_id.clone(),
        seed: self.seed,
        engines: self.engines.clone(),
        pragmas: self.pragmas.clone(),
        schema: self.schema.clone(),
        workload: self.workload.clone(),
        canonicalization: self.canonicalization.clone(),
    };
    let json = serde_json::to_string(&canonical).expect("envelope serialization must not fail");
    sha256_hex(json.as_bytes())
}
```

**Invariant:** `artifact_id = SHA-256 of canonical JSON excluding run_id`. Two runs with identical semantic inputs produce the **same** artifact ID even with different `run_id` (timestamp/PID). This is the deduplication key for the failure-bundle store; it's how "we saw this divergence yesterday on host A" is matched to "we saw it today on host B".

### EngineVersions

```rust
pub struct EngineVersions {
    pub fsqlite: String,
    pub csqlite: String,
    pub subject_identity: String,    // must be "frankensqlite" in parity mode
    pub reference_identity: String,  // must be "csqlite-oracle" in parity mode
}
```

### PragmaConfig (SQL-class defaults)

```rust
pub struct PragmaConfig {
    pub journal_mode: String,    // "wal"
    pub synchronous: String,     // "NORMAL"
    pub cache_size: i64,         // -2000 (2MB)
    pub page_size: u32,          // 4096
}
```

Per-class:
- **Redis:** `{maxmemory_policy, save, appendonly, io_threads, resp_version}`.
- **Torch:** `{num_threads, num_interop_threads, deterministic_algorithms, cudnn_benchmark, cuda_device_count}`.
- **HTTP:** `{worker_count, keep_alive, max_body_size, response_compression}`.

### CanonicalizationRules

```rust
pub struct CanonicalizationRules {
    pub float_tolerance: String,                // "1e-12" stored as string for determinism
    pub unordered_results_as_multiset: bool,    // true
    pub error_match_by_category: bool,          // true
    pub normalize_whitespace: bool,             // true
}
```

`float_tolerance` is a string, not an `f64`. f64 serialization is platform-dependent at the last bit; string is byte-exact.

---

## 4. EngineIdentity Discriminator

Verbatim from MINING-2 §3:

```rust
const SUBJECT_IDENTITY_LABEL:   &str = "frankensqlite";
const REFERENCE_IDENTITY_LABEL: &str = "csqlite-oracle";
```

Strict parity validation: `subject_identity == "frankensqlite"` and `reference_identity == "csqlite-oracle"`. **Enforced at harness entry**; prevents oracle-on-oracle false greens.

The failure mode this prevents: a refactor accidentally points both `subject` and `reference` at `rusqlite::Connection`. Every test passes. The conformance suite reports 100%. Nothing meaningful was tested.

Generalize per class:
- `SUBJECT="frankenredis"`, `REFERENCE="redis-oracle"` (vendored 7.2.4 binary).
- `SUBJECT="frankentorch"`, `REFERENCE="pytorch-oracle"` (PyO3-loaded 2.X.Y).
- `SUBJECT="franken_numpy"`, `REFERENCE="numpy-oracle"` (PyO3-loaded 1.26.0).
- `SUBJECT="fastapi-rust"`, `REFERENCE="fastapi-oracle"` (Python in sub-interpreter).

---

## 5. SQL-Class Oracle Wiring — `rusqlite` Bridge

**Library:** `rusqlite` linked via `libsqlite3-sys` against pinned `sqlite-3.52.0` (or whatever version is in `docs/contracts/sqlite_version_contract.toml`).

```toml
# Cargo.toml
[dependencies]
rusqlite = { version = "0.31", features = ["bundled"] }
# `bundled` ensures we link our pinned C source, not the system libsqlite3.
```

```rust
// crates/<project>-e2e/src/oracle/sqlite.rs

use rusqlite::Connection;

pub fn sqlite_rows(c: &Connection, sql: &str) -> Result<Vec<Vec<String>>, String> {
    let mut stmt = c.prepare(sql).map_err(|e| e.to_string())?;
    let col_count = stmt.column_count();
    let rows = stmt.query_map([], |row| {
        let mut out = Vec::with_capacity(col_count);
        for i in 0..col_count {
            let v: rusqlite::types::Value = row.get(i)?;
            out.push(render_sqlite_value(&v));
        }
        Ok(out)
    }).map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
}

fn render_sqlite_value(v: &rusqlite::types::Value) -> String {
    use rusqlite::types::Value::*;
    match v {
        Null         => "NULL".to_string(),
        Integer(i)   => i.to_string(),
        Real(f)      => normalize_value(&format!("{f}")),
        Text(s)      => format!("'{}'", s.replace('\'', "''")),
        Blob(b)      => format!("X'{}'", hex::encode(b)),
    }
}
```

### `sqlite_version_contract.toml` File Format

```toml
[reference]
project = "sqlite"
version = "3.52.0"
source_tarball_sha256 = "..."
linked_features = ["FTS5", "JSON1", "RTREE"]

[oracle_identity]
label = "csqlite-oracle"

[subject_identity]
label = "frankensqlite"

[pragma_block]
journal_mode = "wal"
synchronous = "NORMAL"
cache_size  = -2000
page_size   = 4096
```

The contract file's SHA-256 goes into every emitted `ExecutionEnvelope`.

---

## 6. RESP-Class Oracle Wiring — Vendored `redis-server` via UNIX Socket

**Library:** vendored `redis-server` binary in `vendor/redis-7.2.4-bin/`; driven over UNIX domain socket for deterministic, no-port-collision invocation.

```rust
// crates/frankenredis-e2e/src/oracle/redis.rs

pub struct RedisOracle {
    socket_path: PathBuf,
    process: Child,
}

impl RedisOracle {
    pub fn spawn(tmp: &Path) -> Self {
        let socket_path = tmp.join("redis.sock");
        let log_path    = tmp.join("redis.log");
        let process = Command::new("vendor/redis-7.2.4-bin/redis-server")
            .args([
                "--port", "0",                               // disable TCP
                "--unixsocket", socket_path.to_str().unwrap(),
                "--unixsocketperm", "700",
                "--daemonize", "no",
                "--save", "",                                // disable RDB
                "--appendonly", "no",
                "--logfile", log_path.to_str().unwrap(),
                "--loglevel", "warning",
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .spawn()
            .expect("redis-server spawn");
        // wait_for_socket_ready(&socket_path, Duration::from_secs(2));
        Self { socket_path, process }
    }

    pub fn cmd(&self, args: &[&str]) -> RespValue {
        let mut stream = UnixStream::connect(&self.socket_path).unwrap();
        // RESP2/3 encoded request → parse RespValue response
        // ...
    }
}
```

### `RespValue` — 14 RESP3 Variants

```rust
pub enum RespValue {
    SimpleString(String),
    Error(String),                          // "ERR <msg>"
    Integer(i64),
    BulkString(Option<Vec<u8>>),            // None = nil
    Array(Option<Vec<RespValue>>),
    Null,                                   // RESP3 _\r\n
    Boolean(bool),
    Double(f64),
    BigNumber(String),                      // arbitrary precision
    BulkError(Vec<u8>),
    VerbatimString { format: String, data: Vec<u8> },
    Map(Vec<(RespValue, RespValue)>),       // RESP3 % marker
    Set(Vec<RespValue>),                    // RESP3 ~ marker
    Push(Vec<RespValue>),                   // RESP3 > marker
}
```

### Collection-Semantics-Aware Comparator

```rust
pub fn resp_equal(a: &RespValue, b: &RespValue) -> bool {
    use RespValue::*;
    match (a, b) {
        // Sets: unordered
        (Set(xs), Set(ys)) => {
            let mut a_sorted: Vec<_> = xs.iter().collect();
            let mut b_sorted: Vec<_> = ys.iter().collect();
            a_sorted.sort_by(|p, q| resp_cmp(p, q));
            b_sorted.sort_by(|p, q| resp_cmp(p, q));
            a_sorted == b_sorted
        }
        // Maps: unordered by key, key uniqueness required
        (Map(xs), Map(ys)) => {
            xs.iter().collect::<HashMap<_, _>>() == ys.iter().collect::<HashMap<_, _>>()
        }
        // Arrays: ordered
        (Array(Some(xs)), Array(Some(ys))) => xs == ys,
        // Doubles: ULP tolerance
        (Double(x), Double(y)) => (x - y).abs() < 1e-12,
        // ... etc
        (x, y) => x == y,
    }
}
```

### Validating Replication / Cluster Mode

For replication: spawn a second `redis-server` as replica via `replicaof <socket>`; assert replica converges to master state after each command sequence; convergence timeout = 5s with poll-every-50ms.

For cluster: spawn 3 master + 3 replica with `cluster-enabled yes`; assert slot ownership matches reference after `CLUSTER ADDSLOTS`.

---

## 7. Numerical / ML-Class Oracle Wiring — PyO3 In-Process Bridge

**Library:** `pyo3` 0.21+ with `auto-initialize` feature; reference imported into sub-interpreter at harness start.

```rust
// crates/franken_numpy-e2e/src/oracle/numpy.rs

use pyo3::prelude::*;
use pyo3::types::{PyDict, PyTuple};

pub struct NumpyOracle {
    py_state: Python<'static>,
    numpy: PyObject,
}

impl NumpyOracle {
    pub fn init() -> Self {
        pyo3::prepare_freethreaded_python();
        Python::with_gil(|py| {
            let numpy = py.import_bound("numpy").unwrap();
            // Pin RNG state
            let np_random = numpy.getattr("random").unwrap();
            let rng = np_random.call_method1("default_rng", (DEFAULT_SEED,)).unwrap();
            // Verify version matches contract
            let version: String = numpy.getattr("__version__").unwrap().extract().unwrap();
            assert_eq!(version, EXPECTED_NUMPY_VERSION,
                "numpy version drift: got {version}, contract={EXPECTED_NUMPY_VERSION}");
        });
        // ...
    }
}
```

### Torch — Determinism Pinning (Non-Negotiable)

```python
# pinned at test start, via PyO3:
torch.use_deterministic_algorithms(True)
torch.backends.cudnn.deterministic = True
torch.backends.cudnn.benchmark = False
torch.manual_seed(DEFAULT_SEED)
if torch.cuda.is_available():
    torch.cuda.manual_seed_all(DEFAULT_SEED)
```

`torch.use_deterministic_algorithms(True)` is a **cargo test invariant** — set in the test harness `setup()`, not per-test. If a single test forgets to set it, that test is silently nondeterministic.

### Seeded RNG State Captured Per-Call

Every oracle call records the RNG state before and after; if the subject's RNG state diverges, the next call is meaningfully nondeterministic.

### `TensorSpec` — Normalized Tensor Comparator

```rust
pub struct TensorSpec {
    pub shape: Vec<usize>,
    pub dtype: DType,           // F32, F64, I32, I64, BF16, F16, BOOL
    pub device: Device,         // CPU, CUDA(usize), MPS, XLA
    pub requires_grad: bool,
    pub data_hash: [u8; 32],    // BLAKE3 of raw bytes
}
```

### Per-Op ULP Tolerance Table

| Op family | Tolerance |
|---|---|
| `matmul` f32 | **4 ULP** |
| `matmul` f64 | **2 ULP** |
| Elementwise (add, mul, etc.) | **2 ULP** default |
| Reductions (sum, mean) | **8 ULP** for f32, **4 ULP** for f64 |
| Transcendentals (exp, log, sin, cos) | **8 ULP** |
| `softmax` outputs | sum-to-1.0 within `1e-7` (f32) / `1e-15` (f64) |

Stored verbatim in `docs/contracts/ulp_tolerance_v1.toml`. The reference for the table: PyTorch's own test suite tolerances + the `torch.testing.assert_close` defaults.

### `gradcheck_max_rel_error` as CI Invariant

```rust
// crates/frankentorch-e2e/tests/autograd_oracle_e2e.rs
#[test]
fn gradcheck_invariant() {
    let max_rel_err = run_gradcheck_corpus();
    assert!(max_rel_err < 1e-5,
        "gradcheck regression: max_rel_err = {max_rel_err}");
}
```

### Bit-Exact PCG64DXSM RNG Parity for `franken_numpy`

**Non-negotiable** for explicit-seed reproducibility. NumPy 1.26+'s default `Generator` uses PCG64DXSM. The Rust port MUST implement PCG64DXSM bit-exact; verify with:

```rust
#[test]
fn pcg64dxsm_bit_exact_against_numpy() {
    let our_seq:   Vec<u64> = our_pcg64dxsm::seeded(42).take(1_000_000).collect();
    let numpy_seq: Vec<u64> = numpy_pcg64dxsm_via_pyo3(42, 1_000_000);
    assert_eq!(our_seq, numpy_seq, "PCG64DXSM stream divergence — bit-exact RNG parity is non-negotiable");
}
```

---

## 8. HTTP / Protocol-Class Oracle Wiring

**Strategy:** compliance fixture corpus + reference framework (FastAPI/Starlette, FastMCP) running in the test harness with deterministic clock + RNG.

### HTTP Response Normalized Type

```rust
pub struct NormalizedHttpResponse {
    pub status: u16,
    pub headers: BTreeMap<String, String>,   // case-insensitive normalized to lowercase; sorted
    pub body: NormalizedBody,
}

pub enum NormalizedBody {
    Json(serde_json::Value),                 // re-parsed for canonical key ordering
    Text(String),
    Bytes(Vec<u8>),
    Empty,
}
```

`headers` is **case-insensitive** (HTTP/1.1 RFC 7230 §3.2). Subject-side and oracle-side both lowercase header names before comparison. `body` is MIME-aware: `application/json` is reparsed to canonical form (sorted keys, no whitespace); `text/plain` is string-compared; everything else is byte-compared.

### OpenAPI Schema Diff as `cargo test` Invariant

```rust
#[test]
fn openapi_schema_parity() {
    let subject_schema:   serde_json::Value = subject_app().openapi().to_value();
    let reference_schema: serde_json::Value = parse_fixture("fixtures/openapi-reference.json");
    let diff = json_diff::diff(&subject_schema, &reference_schema);
    let actionable: Vec<_> = diff.into_iter()
        .filter(|d| !is_known_acceptable_difference(d))
        .collect();
    assert!(actionable.is_empty(),
        "OpenAPI schema drift:\n{}", actionable.iter().map(|d| format!("  {d:?}")).collect::<Vec<_>>().join("\n"));
}
```

### Cancellation-Correctness as Primary Invariant for fastmcp_rust

MCP servers MUST respect `CancellationToken`; abandoned requests free their resources. Test:

```rust
#[tokio::test]
async fn cancellation_releases_resources() {
    let server = spawn_mcp_server().await;
    let req_id = server.start_long_tool("sleep", 60_000).await;
    let counter_before = server.active_tasks_count();
    server.cancel(req_id).await;
    tokio::time::sleep(Duration::from_millis(100)).await;
    let counter_after = server.active_tasks_count();
    assert_eq!(counter_after, counter_before - 1, "cancellation must drop the task");
}
```

---

## 9. Oracle Preflight Doctor

**File:** `crates/<project>-harness/src/oracle_preflight_doctor.rs`

Runs **before** any parity / certification lane. Exits non-zero on red. Verbatim from MINING-2 §13:

Emits deterministic report with:
- schema version, bead id, run_id, trace_id, scenario_id, seed
- generated timestamp
- aggregate outcome: green | yellow | red
- **`certifying: true` ONLY for green**
- first failure diagnosis
- fixture ingestion counters
- resolved sqlite3 binary path
- resolved SQLite version
- fixture manifest mtime + SHA-256
- deterministic replay command
- remediation class + fix_command

### Per-Class Adaptation Table (Verbatim)

| Class | Checks |
|---|---|
| **SQL** | C SQLite oracle binary exists; expected version matches contract (3.52.0); subject identity is "frankensqlite"; reference identity is "csqlite-oracle"; fixture corpus cardinality floors met; fixture manifest mtime fresh; manifest SHA-256 matches. |
| **Redis** | server version + protocol mode + persistence + module set + cluster mode |
| **Torch** | PyTorch version + CUDA/cuDNN/driver + determinism flags + dtype policy + RNG seed policy + model corpus hashes |
| **NumPy** | NumPy version + SIMD flags + RNG state policy + BLAS thread count |
| **HTTP** | reference Python runtime + framework version + OpenAPI fixture hash + deterministic-clock injection + body-size limits |

---

## 10. Fixture Root Contract

**File:** `crates/<project>-harness/src/fixture_root_contract.rs`

Verbatim from MINING-2 §14:

```rust
pub struct FixtureRootContract {
    pub manifest_sha256: String,
    pub fixture_directory: PathBuf,
    pub accepted_aliases: Vec<String>,
    pub cardinality_floors: CardinalityFloors,
    pub required_category_families: Vec<String>,
    pub hash_locked_roots: Vec<(PathBuf, String)>,
    pub included_extensions: Vec<String>,
    pub expected_root_content_hash: Option<String>,
    pub minimum_included_files: usize,
}
```

> **Fixture root contracts turn corpora into auditable inputs. Source of truth for "what am I testing against?"**

The contract is a TOML file committed to the repo. It specifies what files MUST be in the fixture directory, what their hashes MUST be, what the minimum count MUST be. A run that fails the contract refuses to start — better to fail loudly than to silently test against half a corpus.

---

## 11. Metamorphic Machinery

**File:** `crates/<project>-harness/src/metamorphic.rs`

Verbatim from MINING-2 §4:

### TransformFamily
```rust
pub enum TransformFamily {
    Predicate,    // WHERE/HAVING edits without changing projection
    Projection,   // SELECT-list edits without changing filter
    Structural,   // wrap in subquery, add compound operators (INTERSECT)
    Literal,      // rewrite literals/type annotations (42 → CAST(42 AS INTEGER))
}
impl TransformFamily {
    pub const ALL: [Self; 4] = [Self::Predicate, Self::Projection, Self::Structural, Self::Literal];
}
```

### EquivalenceExpectation
```rust
pub enum EquivalenceExpectation {
    ExactRowMatch,                 // same rows, same order
    MultisetEquivalence,           // same multiset, order irrelevant (plan-changing OK)
    SetEquivalence,                // same set of distinct rows (INTERSECT-like)
    TypeCoercionEquivalent,        // CAST round-trip
}
```

### MismatchClassification
```rust
pub enum MismatchClassification {
    TrueDivergence { description: String },
    OrderDependentDifference,
    TypeAffinityDifference,
    NullHandlingDifference,
    FloatingPointDifference { max_epsilon_str: String },
    FalsePositive { reason: String },
}
impl MismatchClassification {
    pub fn is_actionable(&self) -> bool { matches!(self, Self::TrueDivergence { .. }) }
    pub fn triage_priority(&self) -> u8 {
        match self {
            Self::TrueDivergence { .. } => 0,
            Self::NullHandlingDifference => 1,
            Self::TypeAffinityDifference => 2,
            Self::FloatingPointDifference { .. } => 3,
            Self::OrderDependentDifference => 4,
            Self::FalsePositive { .. } => 5,
        }
    }
}
```

**CI rule:** CI fails only on `TrueDivergence`. Other classes flow into triage queue.

### SeedContract
```rust
fn derive_entry_seed(corpus_entry_id: &str) -> u64 { /* deterministic hash */ }
```
**Never `rand::random()`.** Same input → same seed → same SQL → same bugs found.

---

## 12. Mismatch Minimizer

**File:** `crates/<project>-harness/src/mismatch_minimizer.rs`

Verbatim from MINING-2 §5:

### Subsystem Attribution
```rust
pub enum Subsystem {
    Parser, Resolver, Planner, Vdbe, Storage, Wal, Mvcc, Functions,
    Extension, TypeSystem, Pragma, Unknown,
}
```

### MismatchSignature (deduplication primitive)
```rust
pub struct MismatchSignature {
    pub hash: String,                        // truncated SHA-256 of canonical minimal repro
    pub classification: MismatchClassification,
    pub subsystem: Subsystem,
    pub minimal_statement_count: usize,
    pub first_diverging_sql: String,
}
```

**Algorithm:** binary partition → recursive narrowing → 1-minimal → schema preservation (schema setup never removed).

**Dedup rule:** Two failures with same `MismatchSignature` are the **same root-cause bug**. A bisect that hits a known bug **links** instead of opens new beads issue. Without dedup, a single root-cause bug spawns hundreds of CI failures and drowns the triage queue.

---

## 13. Three-Tier Equivalence for Golden Artifacts

Verbatim from MINING-2 §6:

```rust
pub enum EquivalenceTier {
    Tier1Raw,         // raw SHA-256 byte equality
    Tier2Canonical,   // after normalization (VACUUM INTO + stable PRAGMAs / torch.use_deterministic_algorithms)
    Tier3Logical,     // logical deterministic SQL or tensor dump (row count + columns + values via ==)
}
```

> **Rule: "Encode the distinction; never paper over it."** A Tier2 match is not Tier1; the JSON report must name which tier succeeded.

The failure mode this prevents: a port that produces a tensor that's logically equal to the reference but with different memory layout gets Tier3-pass but Tier1-fail. Reporting only "passed" obscures the layout drift. The catalog calls it Tier3 explicitly.

---

## 14. Public-API Oracle-Parity Surface — Per-Domain List

Verbatim from MINING-2 §18:

### SQL-class behavior list

NULL semantics, three-valued logic, GROUP BY/HAVING edges, recursive CTEs, JOIN type semantics, trigger semantics, RETURNING, generated columns, window functions, PRAGMA introspection, LIKE/GLOB/ESCAPE, subquery semantics, numeric arithmetic edges, BLOB I/O, foreign keys, CHECK, conflict resolution, compound SELECT, DEFAULT, ATTACH/TEMP, ALTER TABLE rename propagation, collation sequence, date/time functions, scalar string/numeric functions, ORDER BY/LIMIT/OFFSET edge cases, VIEW semantics, transaction and SAVEPOINT nesting, ROWID and WITHOUT ROWID, index features, multi-row VALUES, concurrent DML and isolation, MVCC visibility, WAL checkpoint behavior.

### RESP class
NULL semantics, array ordering, set unordered semantics, hash unordered, integer overflow, FP representation, error message categories.

### Tensor class
dtype promotion, broadcasting, gradient accumulation, autograd chain, device placement, memory format, NaN/Inf propagation.

### NumPy class
dtype casting, array views vs copies, axis semantics, broadcasting, ufunc loop selection, error handling.

Each item must have **at least one** `*_oracle_e2e.rs` file in `crates/<project>-e2e/tests/`. The catalog of items vs files is enumerated in [../taxonomy/FEATURE-UNIVERSE.md](../taxonomy/FEATURE-UNIVERSE.md).

---

## 15. Insta Snapshots — Internal-Layer Regression

```
cargo insta test --review
```

Workflow:

1. Write `assert_yaml_snapshot!(planner.dump())` in your test.
2. First run creates `tests/snapshots/<name>__planner_dump.snap.new`.
3. `cargo insta review` opens an interactive diff; accept or reject.
4. Accepted snapshots are committed.
5. Future runs comparing against committed `.snap`; failure = drift.

**Use cases:** planner output, VDBE bytecode, RESP frame sequences, OpenAPI schemas, JIT-compiled IR. Insta catches regressions in *internal layers* that don't show up in observable behavior — useful for catching "this planner change accidentally generated 30% more bytecode" before it shows up as a perf regression.

**Pitfall:** snapshots that include host-specific data (timestamps, file paths, random hashes) churn constantly. Normalize before snapshot: `insta::with_settings!({filters => vec![(r"\d{4}-\d{2}-\d{2}", "<DATE>")]}, {...})`.

---

## 16. TCL Test Suite Lifted as Regression Corpus

For SQLite-class: SQLite's official TCL test suite (`testfixture`) is the gold standard. Lift it as follows:

1. Vendor `sqlite-tcl-tests/` from the SQLite source tree (post-pinned-version).
2. Write a TCL-script-driven Rust test:
   ```rust
   #[test]
   fn tcl_corpus() {
       for tcl_file in tcl_corpus_files() {
           let subject_results   = run_tcl_against(tcl_file, &fsqlite_tcl_driver());
           let reference_results = run_tcl_against(tcl_file, &csqlite_tcl_driver());
           assert_corpus_equal(subject_results, reference_results);
       }
   }
   ```
3. Run nightly; failure dumps a `FailureBundle` per divergent TCL file.

Generalize per class: Redis has its own integration test suite (`tests/integration/`); PyTorch has `test/test_*.py`; FastAPI has `tests/`.

---

## 17. Pitfalls

| Pitfall | Why it bites | Fix |
|---|---|---|
| Oracle compared against itself | Apparent 100% pass rate | EngineIdentity discriminator + preflight doctor checks subject ≠ oracle identity strings. |
| Both engines failing differently, marked agreement | Two different bugs both pass | "both-error = agreement" is correct; "one-error-one-OK = failure" is correct; mixing engines that error-class differently (oracle ParseError vs subject Internal) is OK *only* if categorization rule is `error_match_by_category: true` in `CanonicalizationRules`. |
| String-rendering drift | Subject renders `0.1 + 0.2` as `"0.30000000000000004"`; oracle as `"0.3"` | Use `normalize_value` from §2 in BOTH paths. |
| RNG state divergence | Oracle's RNG state pin doesn't extend to subprocess oracle | Spawn oracle subprocess with `--seed=N`; verify state by hash after each call. |
| PyO3 Python GIL contention | Multiple Rust threads call oracle simultaneously | Hold `Python::with_gil` for entire oracle call; *do not* split it across threads. |
| Float comparison via `==` | `0.1 + 0.2 != 0.3` | Use `normalize_value` (15-digit) or ULP tolerance from §7. |
| Fixture corpus drift | Someone added test files but didn't update manifest | FixtureRootContract `expected_root_content_hash` + cardinality floors enforced at preflight. |
| Subject vs oracle PRAGMA drift | One side has WAL, other has rollback journal | Identical-PRAGMAs rule from BENCH-TOOLCHAIN §2.5; 30-line copy-paste block. |
| Snapshot churn from timestamps | Snapshots fail on every CI run | `insta` filters for `<DATE>`, `<TIMESTAMP>`, `<HOST>`. |
| Determinism flag forgotten in one test | That test is silently nondeterministic | Set `torch.use_deterministic_algorithms(True)` in test harness `setup()`, not per-test. |

---

## See Also

- [BENCH-TOOLCHAIN.md](BENCH-TOOLCHAIN.md) — the bench that drives subject + oracle through this comparator.
- [FUZZ-TOOLCHAIN.md](FUZZ-TOOLCHAIN.md) — differential fuzz that uses this comparator as the equivalence oracle.
- [CONCURRENCY-TOOLCHAIN.md](CONCURRENCY-TOOLCHAIN.md) — the fault VFS for crash-boundary parity.
- [../taxonomy/PROJECT-CLASSES.md](../taxonomy/PROJECT-CLASSES.md) — class-by-class oracle wiring.
- [../taxonomy/FEATURE-UNIVERSE.md](../taxonomy/FEATURE-UNIVERSE.md) — the surface enumeration this oracle is parameterized over.
- [../methodology/CONFORMAL-RATCHET.md](../methodology/CONFORMAL-RATCHET.md) — turning oracle pass rates into release decisions.
