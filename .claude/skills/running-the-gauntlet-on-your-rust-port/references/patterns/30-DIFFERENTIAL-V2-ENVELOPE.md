# Pattern 30 — DIFFERENTIAL V2 ENVELOPE (content-addressed `artifact_id = SHA-256(canonical JSON \ run_id)`)

## What

A typed Rust struct, `ExecutionEnvelope`, that wraps every differential-test execution. Carries the format version, optional run_id (provenance), scenario_id (default if absent), seed, engine versions including the [pattern:15-ENGINE-IDENTITY](15-ENGINE-IDENTITY.md) discriminator, pragma config (byte-identical to both engines per [K-4](../methodology/KERNEL.md#k-4)), schema setup statements, workload statements, and canonicalization rules. The `artifact_id()` method computes the SHA-256 of the envelope's canonical JSON *excluding `run_id`*, so two distinct runs of the same semantic test produce the same artifact id — making the ledger queryable, the regression detector stable, and the ratchet bytewise reproducible across machines. Operationalizes [K-11](../methodology/KERNEL.md#k-11).

## Why

> "Invariant: `artifact_id = SHA-256 of canonical JSON excluding run_id`. Two runs with identical semantic inputs produce the same artifact ID even with different `run_id` (timestamp/PID)." — MINING-2 §2

Conformance lanes produce thousands of artifacts. Without a content-addressed identity, you cannot say "we already tested this thing" because every artifact looks unique (different timestamp, different PID). The envelope separates *provenance* (`run_id`) from *identity* (`artifact_id`), enabling: deduplication of identical reruns, stable cross-machine ratchet diffing, and content-addressable storage of envelope+result pairs.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/differential_v2.rs` (202+ lines, bead `bd-1dp9.1.2`) — the `ExecutionEnvelope` struct definition (MINING-2 §2)
- `crates/fsqlite-harness/src/canonical_envelope.rs` — the `CanonicalEnvelope` shape used for the `artifact_id` hash
- Schema version: `format_version: u32` (currently `2`)

## Verbatim shape — the struct + the `artifact_id` function

From MINING-2 §2, verbatim:

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

pub fn artifact_id(&self) -> String {
    let canonical = CanonicalEnvelope { /* same fields minus run_id */ };
    let json = serde_json::to_string(&canonical).expect("envelope serialization must not fail");
    sha256_hex(json.as_bytes())
}
```

### `EngineVersions` (carries the K-9 discriminator)

```rust
pub struct EngineVersions {
    pub fsqlite: String,
    pub csqlite: String,
    pub subject_identity: String,    // must be "frankensqlite" in parity mode
    pub reference_identity: String,  // must be "csqlite-oracle" in parity mode
}
```

### `PragmaConfig` (the K-4 byte-identical config block)

> "PragmaConfig: journal_mode default 'wal', synchronous 'NORMAL', cache_size -2000, page_size 4096." — MINING-2 §2

### `CanonicalizationRules`

> "CanonicalizationRules: float_tolerance '1e-12' (stored as string for determinism), unordered_results_as_multiset true, error_match_by_category true, normalize_whitespace true." — MINING-2 §2

```rust
pub struct CanonicalizationRules {
    pub float_tolerance: String,             // stored as string for determinism
    pub unordered_results_as_multiset: bool,
    pub error_match_by_category: bool,
    pub normalize_whitespace: bool,
}
```

### Why "SHA-256 of canonical JSON excluding run_id"

- **Canonical JSON**: keys sorted, no trailing whitespace, no insignificant nulls. The `CanonicalEnvelope` struct's `serde_json::to_string` with a `BTreeMap`-backed field order produces this naturally.
- **Excluding `run_id`**: `run_id` is `{bead_id}-{timestamp}-{pid}`, which is unique per process. Hashing it in would make every run produce a different artifact id, defeating content addressing.
- **SHA-256**: 32 bytes; collision-resistant; standard; ergonomic in hex form (64 chars) for filesystem-safe filenames (`artifacts/<artifact_id>.envelope.json`).

## Per-class instantiation — `CanonicalizationRules` per class

| Class | `float_tolerance` | `unordered_results_as_multiset` | `error_match_by_category` | `normalize_whitespace` | Class-specific rules |
|---|---|---|---|---|---|
| **SQL** | `"1e-12"` | `true` (SELECT without ORDER BY is multiset) | `true` (error categories match per `MismatchClassification::TrueDivergence`) | `true` | NULL capitalized, blob as `X'<hex>'`, text in single quotes (see [pattern:35-NORMALIZED-VALUE](35-NORMALIZED-VALUE.md)) |
| **RESP** | `"1e-12"` (RESP3 doubles) | `true` (SMEMBERS, HKEYS are sets/maps without canonical order) | `true` (`WRONGTYPE`, `NOAUTH`, etc. as category enums) | `true` | RESP3 type-tag preserved; nested Maps sorted by key |
| **Numerical** | per-op ULP table; canonical default `"4e-7"` for f32 matmul, `"2e-7"` elementwise | `false` (array order matters!) | `true` (`ValueError`, `TypeError`, `OverflowError` categories) | `true` | `np.errstate` policy embedded; dtype-cast policy embedded |
| **ML** | per-op ULP table; `"4e-6"` for f32 attention, `"1e-6"` for f64 | `false` (tensor order matters!) | `true` (`RuntimeError`, `AssertionError` categories) | `true` | `torch.use_deterministic_algorithms(True)` enforced; gradient checking ULP separate |
| **HTTP** | N/A (no floats in routing) | `false` (response order matters) | `true` (HTTP status code categories: 4xx/5xx semantics) | `true` (case-insensitive header normalization) | OpenAPI schema diff Tier 2 canonical |

### Per-class `format_version` history

- SQL `format_version = 2` (V2 envelope is the current; V1 is pre-bd-1dp9.1.2).
- RESP `format_version = 1` (only one revision so far).
- ML `format_version = 1`.

## Composition

- [pattern:15-ENGINE-IDENTITY](15-ENGINE-IDENTITY.md) — `EngineVersions.subject_identity/reference_identity` are the K-9 discriminator.
- [pattern:25-FIXTURE-ROOT-CONTRACT](25-FIXTURE-ROOT-CONTRACT.md) — `manifest_sha256` is embedded in `EngineVersions` (or as a sibling field in extended envelopes).
- [pattern:35-NORMALIZED-VALUE](35-NORMALIZED-VALUE.md) — the `normalize_value()` function is what `CanonicalizationRules` parameterizes for the comparator stage.
- [pattern:90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) — every `FailureBundle` carries the envelope's `artifact_id` so the failure is reproducibly tied to its inputs.
- [pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md) — perf reports embed `artifact_id` for the same content-addressing benefit.
- [pattern:195-RUN-IDENTITY-STACK](195-RUN-IDENTITY-STACK.md) — `run_id` is the provenance side; this pattern is the identity side.

## Pitfalls

- **Including `run_id` in the hash.** Defeats content addressing. The most common mistake: `let json = serde_json::to_string(self)` instead of constructing the `CanonicalEnvelope` shape. Add a test that asserts `e1.artifact_id() == e2.artifact_id()` when only `run_id` differs.
- **Non-canonical JSON.** Using `serde_json::to_string_pretty` (adds whitespace), or a `HashMap`-backed struct (non-deterministic key order), or `f64` fields that round-trip differently. Use `BTreeMap`, `to_string` (not pretty), and stringify floats (`float_tolerance: "1e-12"`).
- **`format_version` bumped without migration.** A new format version invalidates every prior `artifact_id`. Bump only when truly necessary, and document the migration (old envelopes can be replayed with `--format-version 1`).
- **Embedding mutable runtime state in the envelope.** Anything that changes between identical reruns (current timestamp, current PID, OS-allocated socket port) belongs in `run_id`-adjacent provenance, not in the hashed fields.
- **PRAGMAs reordered between subject and reference.** Both must apply the same PRAGMAs in the same order; reordering produces different `cache_size` / `journal_mode` interaction state. The `PragmaConfig` struct's field order is the canonical order.
- **Engine versions populated as `env!("CARGO_PKG_VERSION")`.** That's the *port's* version, not the reference's. The reference version comes from [pattern:10-REFERENCE-PINNING](10-REFERENCE-PINNING.md) and the actual probe (`sqlite3_libversion()`, `redis-server --version`, `torch.__version__`). Mismatch between contract and probe is preflight-red.
- **Computing `artifact_id` once and caching across modifications.** The envelope is immutable post-construction; if a test path mutates `workload.push(...)` and then reads the cached id, it lies. Compute on read or make the struct truly immutable (`pub(crate)` fields with constructor).
