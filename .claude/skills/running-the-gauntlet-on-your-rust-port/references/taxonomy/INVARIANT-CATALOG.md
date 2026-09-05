# INVARIANT-CATALOG.md — ProofObligation Taxonomy + ArtifactRef Contract

The `InvariantCatalog` is the structured manifest of every parity invariant the port claims to hold, with verifiable proof obligations and content-addressed evidence artifacts. It lives in `crates/<port>-harness/src/invariant_catalog.rs`. Where `FeatureUniverse` answers "what surface does the port claim?", the `InvariantCatalog` answers "what *guarantees* does the port make about that surface, and where is the evidence?"

Cross-references: [`FEATURE-UNIVERSE.md`](FEATURE-UNIVERSE.md), [`PROJECT-CLASSES.md`](PROJECT-CLASSES.md), [`../THREE-PILLARS.md`](../THREE-PILLARS.md), [`../tooling/ORACLE-TOOLCHAIN.md`](../tooling/ORACLE-TOOLCHAIN.md), [`../tooling/FUZZ-TOOLCHAIN.md`](../tooling/FUZZ-TOOLCHAIN.md), [`../tooling/CONCURRENCY-TOOLCHAIN.md`](../tooling/CONCURRENCY-TOOLCHAIN.md), [`../methodology/CONFORMAL-RATCHET.md`](../methodology/CONFORMAL-RATCHET.md).

---

## ParityInvariant Struct (Verbatim)

From MINING-3 §11 catalog diagram, expanded into struct form:

```rust
pub struct ParityInvariant {
    pub invariant_id: InvariantId,         // e.g., "INV-SQL-001"
    pub statement: String,                 // Human-readable invariant statement
    pub assumptions: Vec<String>,          // Preconditions / scoping caveats
    pub linked_feature_ids: Vec<FeatureId>,
    pub proof_obligations: Vec<ProofObligation>,
}
```

The catalog itself:
```
FeatureUniverse (bd-1dp9.1.1)
  ▼
InvariantCatalog
  ├── ParityInvariant (1:N per Feature)
  │     ├── invariant_id, statement, assumptions
  │     └── proof_obligations[]
  │           ├── ProofObligation { kind, evidence_ref, status }
  │           └── ArtifactRef { path, hash, schema_version }
  ├── validate()             → Vec<Violation>
  ├── release_traceability() → ReleaseTraceabilityReport
  └── stats()                → CatalogStats
```

`InvariantId` scheme: `INV-{CATEGORY}-{SEQ}[-{SUFFIX}]` — e.g., `INV-SQL-001`, `INV-SQL-042-recursive`, `INV-RESP-014-fifo`. The CATEGORY matches the `FeatureUniverse` CATEGORY codes (see [`FEATURE-UNIVERSE.md § FeatureId Scheme`](FEATURE-UNIVERSE.md)).

Invariants are 1:N per Feature: one feature can have multiple invariants (e.g., `F-SQL-001 SELECT with WHERE` has `INV-SQL-001-oracle` for differential parity AND `INV-SQL-001-metamorphic-predicate` for metamorphic equivalence under WHERE rewrites).

---

## ProofObligation Struct + 7 ProofKind Variants

```rust
pub struct ProofObligation {
    pub kind: ProofKind,
    pub evidence_ref: ArtifactRef,
    pub status: ProofStatus,
    pub notes: Option<String>,
}

pub enum ProofKind {
    OracleDifferential,
    MetamorphicProperty,
    ProptestInvariant,
    CrashBoundary,
    EProcess,
    FuzzNonPanic,
    InstaSnapshot,
}

pub enum ProofStatus {
    Pending,        // obligation declared, evidence not yet generated
    Satisfied,      // evidence exists, artifact_ref resolves and hash-matches
    Failing,        // evidence exists but artifact reports failure
    Stale,          // artifact_ref hash mismatch — regenerate
    Missing,        // artifact_ref path does not resolve — regenerate
}
```

### `OracleDifferential`
The invariant holds because subject and oracle agree on the same input under the 30-line `scenario()` template comparator. Evidence artifact is a Differential V2 envelope (`crates/<port>-harness/src/differential_v2.rs`) with `artifact_id = SHA-256 of canonical JSON excluding run_id`. The artifact records EngineVersions, PragmaConfig, schema, workload, canonicalization rules, plus per-query result with `MismatchClassification`.

Required for every `Passing` feature at minimum.

### `MetamorphicProperty`
The invariant holds because subject's answer to a query Q matches subject's answer to a rewritten query Q' under a declared `EquivalenceExpectation` (`ExactRowMatch | MultisetEquivalence | SetEquivalence | TypeCoercionEquivalent`) from a `TransformFamily` (`Predicate | Projection | Structural | Literal`). Evidence is a `MetamorphicCorpus` JSONL with one entry per (Q, transform, Q', subject_result, expectation, classification).

Soundness-proof sketch required as `notes`: "Rewrite preserves semantics because <one paragraph>". Without this, the metamorphic relation is suspect.

### `ProptestInvariant`
The invariant holds because a `proptest` (or `bolero`) property generates inputs and observes the invariant. Evidence is `tests/artifacts/proptest/<invariant>.proptest.json` with seed, generated input count, shrunk failures (if any), and pass rate.

Used for invariants that are properties of subject alone (e.g., "page size is always a power of 2") rather than subject-vs-oracle.

### `CrashBoundary`
The invariant holds because crash injection at a named `CrashBoundary` followed by recovery produces a consistent state. Evidence is `tests/artifacts/crash/<boundary>.recovery.json` with `(boundary, fault_seed, recovered_state, consistency_predicate, predicate_result)`.

Per [`PROJECT-CLASSES.md § Crash Boundaries`](PROJECT-CLASSES.md):
- SQL: 8 named WAL boundaries (`BeforeWalHeaderWrite … AfterCheckpoint`)
- RESP: 6+ AOF/RDB boundaries
- ML: 5 checkpoint-save + 2 distributed-collective
- HTTP: 5 request-lifecycle + 1 cancellation

### `EProcess`
The invariant holds because an e-process under the global null hypothesis stays below `1/α` over the observation window. Evidence is `tests/artifacts/eprocess/<invariant>.eprocess.json` with `(invariant_id, calibration {p0, lambda, alpha}, observations, e_values, max_e_value, ville_threshold_crossed)`.

Per MINING-2 §10:
- Hardware-enforced (CAS guarantees): `p₀ = 1e-9, λ = 0.999, α = 1e-6`
- Software-enforced: `p₀ = 1e-6, λ = 0.9, α = 0.001`
- Global E-Value (arithmetic mean): `E_global(t) = Σ wᵢ Eᵢ(t)` with equal `wᵢ = 1/N`
- Ville's Inequality: `P_{H_0}(∃t: E_t ≥ 1/α) ≤ α` — anytime-valid, no Bonferroni

### `FuzzNonPanic`
The invariant holds because differential fuzz against the API surface produces no `TrueDivergence` and no panic over a documented wall-time window. Evidence is `tests/artifacts/fuzz/<target>.fuzz.json` with `(target, corpus_sha, wall_time_seconds, executions, panics, crashes, true_divergences, false_positive_dedup_count)`.

Minimum wall-time for Phase 15 soak: 24h per target. Phase 9 baseline: 1h.

### `InstaSnapshot`
The invariant holds because `cargo insta` snapshot of subject output matches the committed `.snap` file. Evidence is the snapshot file path + hash. Used for bytecode, plan output, OpenAPI schema, RESP protocol traces, MCP capability documents — any subject-side artifact that should not change without explicit review.

`.snap` files are committed to git; changes require explicit `cargo insta review` with diff explained in the bead.

---

## ArtifactRef Contract

```rust
pub struct ArtifactRef {
    pub path: PathBuf,         // relative to <workspace>/ or to <port>/
    pub hash: String,          // SHA-256 hex of the artifact contents
    pub schema_version: String, // e.g., "fsqlite-e2e.comprehensive-bench-report.v3"
}
```

Three-field contract; nothing more, nothing less.

### `path`
Relative path. Resolved against `<workspace>/` for round artifacts; against `<port>/` for committed fixtures (e.g., `.snap` files); against `<workspace>/tests/artifacts/` for generated artifacts. The catalog loader rejects absolute paths and rejects paths that escape the root (no `../..` traversal).

### `hash`
SHA-256 hex (lowercase, no separators) of the artifact file contents AFTER canonicalization. For JSON artifacts, canonicalize via canonical-JSON (sorted keys, no insignificant whitespace, RFC 8785). For text artifacts, normalize line endings to LF, trailing-newline normalized, no BOM. For binary artifacts, raw SHA-256 of the bytes.

The hash field is what makes the obligation tamper-evident: if the artifact contents change without updating the hash, `invariant_catalog::validate()` returns `Violation::HashMismatch { invariant_id, expected, actual }`.

### `schema_version`
The artifact's self-declared schema version. The loader cross-checks: open the artifact, find the `schema_version` field at the top level, ensure it matches the `ArtifactRef.schema_version`. If the artifact has no `schema_version` field, the loader rejects with `Violation::SchemaVersionMissing { invariant_id, artifact_path }`.

Common schema versions:
- `fsqlite-e2e.comprehensive-bench-report.v3` (perf bench)
- `fsqlite-e2e.comprehensive-bench-ci-regression-gate.v2` (perf gate config)
- `fsqlite-e2e.mt_mvcc_bench_report.v3` (MT-MVCC bench)
- `fsqlite-e2e.swarm-multiprocess-report.v1` (swarm cross-process bench)
- `fsqlite-harness.differential-v2-envelope.v1` (differential V2 envelope)
- `fsqlite-harness.failure-bundle.v1.0.0` (failure bundle)
- `fsqlite-harness.e2e-log.v1.0.0` (E2E log)
- `fsqlite-harness.eprocess-trace.v1` (e-process observation trace)
- `fsqlite-harness.metamorphic-corpus.v1` (metamorphic corpus JSONL)
- `fsqlite-harness.crash-recovery.v1` (crash-boundary recovery proof)
- `fsqlite-harness.fuzz-report.v1` (fuzz wall-time report)

For other classes, prefix with project namespace (e.g., `frankenredis-e2e.resp-bench-report.v1`).

---

## How to Write an Invariant: Template + Worked Example INV-SQL-001

### Template

```rust
ParityInvariant {
    invariant_id: InvariantId::from("INV-<CATEGORY>-<SEQ>[-<SUFFIX>]"),
    statement: String::from("<one-sentence invariant; subject behaves identically to oracle under <scope>>"),
    assumptions: vec![
        "<assumption 1: e.g., 'identical PRAGMAs configured on both engines'>",
        "<assumption 2: e.g., 'identical seed for any RNG-driven path'>",
        // ...
    ],
    linked_feature_ids: vec![FeatureId::from("F-<CATEGORY>-<SEQ>"), /* possibly more */],
    proof_obligations: vec![
        ProofObligation {
            kind: ProofKind::OracleDifferential,
            evidence_ref: ArtifactRef {
                path: PathBuf::from("tests/artifacts/oracle/<invariant>.differential-v2.json"),
                hash: "<sha256_hex_after_canonical_JSON>".to_string(),
                schema_version: "fsqlite-harness.differential-v2-envelope.v1".to_string(),
            },
            status: ProofStatus::Satisfied,
            notes: None,
        },
        // additional obligations as relevant
    ],
}
```

Plus the on-disk TOML representation (`docs/contracts/invariant_catalog.toml`):
```toml
[[invariant]]
id = "INV-<CATEGORY>-<SEQ>"
statement = "..."
assumptions = ["...", "..."]
linked_features = ["F-<CATEGORY>-<SEQ>"]

[[invariant.proof]]
kind = "OracleDifferential"
path = "tests/artifacts/oracle/<invariant>.differential-v2.json"
hash = "..."
schema_version = "fsqlite-harness.differential-v2-envelope.v1"
status = "Satisfied"
```

### Worked Example: INV-SQL-001

Linked to `F-SQL-001` (SELECT with WHERE and basic projections).

```rust
ParityInvariant {
    invariant_id: InvariantId::from("INV-SQL-001"),
    statement: String::from(
        "FrankenSQLite SELECT with WHERE produces row-identical results to CSQLite oracle, \
         in the same order when ORDER BY is present, as a multiset when not."
    ),
    assumptions: vec![
        "Both engines configured with identical PRAGMAs (journal_mode=wal, synchronous=NORMAL, cache_size=-2000, page_size=4096) per CanonicalEnvelope defaults".to_string(),
        "Schema setup statements agree on both engines (panic on disagreement per scenario() template)".to_string(),
        "EngineIdentity::Subject = 'frankensqlite' and EngineIdentity::Oracle = 'csqlite-oracle' asserted-distinct".to_string(),
        "NormalizedValue rendering applied symmetrically on both sides".to_string(),
    ],
    linked_feature_ids: vec![FeatureId::from("F-SQL-001")],
    proof_obligations: vec![
        ProofObligation {
            kind: ProofKind::OracleDifferential,
            evidence_ref: ArtifactRef {
                path: PathBuf::from("tests/artifacts/oracle/INV-SQL-001.differential-v2.json"),
                hash: "9f6a3c1d2e4b5a8c7d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c".to_string(),
                schema_version: "fsqlite-harness.differential-v2-envelope.v1".to_string(),
            },
            status: ProofStatus::Satisfied,
            notes: Some("18 scenarios × 4 dataset sizes × 3 concurrency levels = 216 cases".to_string()),
        },
        ProofObligation {
            kind: ProofKind::MetamorphicProperty,
            evidence_ref: ArtifactRef {
                path: PathBuf::from("tests/artifacts/metamorphic/INV-SQL-001-predicate.corpus.jsonl"),
                hash: "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b".to_string(),
                schema_version: "fsqlite-harness.metamorphic-corpus.v1".to_string(),
            },
            status: ProofStatus::Satisfied,
            notes: Some(
                "TransformFamily::Predicate: WHERE x = 5 ↔ WHERE 5 = x; \
                 WHERE x IN (5) ↔ WHERE x = 5; \
                 WHERE NOT NOT x = 5 ↔ WHERE x = 5. \
                 EquivalenceExpectation::ExactRowMatch when ORDER BY present, \
                 MultisetEquivalence otherwise. \
                 Soundness: predicate-only edits preserve row set; projection unchanged."
                .to_string()
            ),
        },
        ProofObligation {
            kind: ProofKind::ProptestInvariant,
            evidence_ref: ArtifactRef {
                path: PathBuf::from("tests/artifacts/proptest/INV-SQL-001-projection.proptest.json"),
                hash: "2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c".to_string(),
                schema_version: "fsqlite-harness.proptest-report.v1".to_string(),
            },
            status: ProofStatus::Satisfied,
            notes: Some(
                "Property: for any schema S and any random row R, \
                 (SELECT * FROM t WHERE pk = R.pk) returns R for both engines. \
                 10,000 generated inputs; 0 shrunk failures."
                .to_string()
            ),
        },
        ProofObligation {
            kind: ProofKind::FuzzNonPanic,
            evidence_ref: ArtifactRef {
                path: PathBuf::from("tests/artifacts/fuzz/select_where_basic.fuzz.json"),
                hash: "3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d".to_string(),
                schema_version: "fsqlite-harness.fuzz-report.v1".to_string(),
            },
            status: ProofStatus::Satisfied,
            notes: Some(
                "24h soak wall-time, 47M executions, 0 panics, 0 TrueDivergence, 12 FalsePositive (deduped via MismatchSignature)."
                .to_string()
            ),
        },
    ],
}
```

The example shows four `ProofObligation` types of the seven (`OracleDifferential`, `MetamorphicProperty`, `ProptestInvariant`, `FuzzNonPanic`). The remaining three (`CrashBoundary`, `EProcess`, `InstaSnapshot`) attach when relevant (e.g., `INV-SQL-MVCC-001` would attach `CrashBoundary` for the 8 WAL boundaries AND `EProcess` for the 8 MVCC invariants).

---

## CatalogStats and ReleaseTraceabilityReport

```rust
pub struct CatalogStats {
    pub total_invariants: usize,
    pub by_status: BTreeMap<ProofStatus, usize>,
    pub by_kind: BTreeMap<ProofKind, usize>,
    pub by_category: BTreeMap<String, usize>,
    pub total_features_covered: usize,
    pub features_with_no_invariant: Vec<FeatureId>,
}

pub struct Violation {
    pub invariant_id: InvariantId,
    pub kind: ViolationKind,
}

pub enum ViolationKind {
    HashMismatch { expected: String, actual: String, path: PathBuf },
    PathNotResolvable { path: PathBuf },
    SchemaVersionMismatch { expected: String, actual: String, path: PathBuf },
    SchemaVersionMissing { path: PathBuf },
    NoProofObligation,
    OrphanedFeatureReference { feature_id: FeatureId },
    StaleArtifact { path: PathBuf, age_hours: u64 },
}

pub struct ReleaseTraceabilityReport {
    pub stats: CatalogStats,
    pub violations: Vec<Violation>,
    pub per_invariant: Vec<InvariantTraceability>,
    pub bundle_manifest: BundleManifest,
}

pub struct InvariantTraceability {
    pub invariant_id: InvariantId,
    pub statement: String,
    pub linked_features: Vec<FeatureId>,
    pub proof_obligation_summary: Vec<(ProofKind, ProofStatus, PathBuf, String /* hash */)>,
}

pub struct BundleManifest {
    pub artifact_count: usize,
    pub total_bytes: u64,
    pub artifacts: Vec<(PathBuf, String /* hash */, String /* schema_version */)>,
}
```

`validate() -> Vec<Violation>` walks every invariant, dereferences every `ArtifactRef.path`, recomputes the SHA-256, checks the schema version, and collects violations. Returns empty `Vec` when the catalog is releasable.

`release_traceability() -> ReleaseTraceabilityReport` produces the per-invariant report that lands in the certification bundle as `certification_bundle/invariant_traceability.json`. The release reader can answer "which invariants are claimed, what's the proof, where is the evidence, what's its hash" in one document.

`stats() -> CatalogStats` is the at-a-glance summary; Phase 16 `FINAL_GAUNTLET_REPORT.md` opens with these stats.

---

## "Ship the Catalog Ships the Proof-of-Work" Discipline

Verbatim from MINING-3 §11:

> "The catalog doesn't just say 'we tested X', it says 'we tested X, the evidence is at path P with SHA-256 H against schema version V'. A release that ships the catalog ships the proof-of-work."

This is the bedrock discipline of the gauntlet. The catalog is not documentation; it is the executable, content-addressed, tamper-evident manifest of every claim the release makes. Three concrete consequences:

### 1. No invariant without an evidence artifact
Every `ParityInvariant` must have at least one `ProofObligation` with `ProofStatus::Satisfied` (or, if `Pending`, with a clear blocker pointer to an open bead). `invariant_catalog::validate()` returns `Violation::NoProofObligation` if any invariant has zero obligations. The Phase 7 surface-archaeologist subagent rejects this at construction time, but the validator is a runtime gate at every Phase 9+ baseline.

### 2. No evidence artifact without a content hash
Every `ArtifactRef` must have a populated `hash`. The catalog loader rejects empty hashes. The release-time `validate()` recomputes every hash; mismatch is `Violation::HashMismatch`. This is what makes "ship the catalog ships the proof-of-work" tamper-evident — you can't ship the catalog with stale or fabricated artifacts; the hash will mismatch.

### 3. No release without a clean validate()
The Phase 16 certification bundler runs `invariant_catalog::validate()` as its first action. If the returned `Vec<Violation>` is non-empty, the bundler refuses to issue `RELEASE_CERTIFICATION_TEMPLATE.md` as strict-conformant-release.v1 — the top-line verdict flips to `BLOCKED` and the bundler emits a per-violation diagnostic in `certification_bundle/violations.json`.

The catalog + the universal-floor evidence directory (`tests/artifacts/{oracle,metamorphic,proptest,crash,eprocess,fuzz,insta}/`) is the **complete** answer to "what does this release guarantee, and how do you know?" Nothing in the bundle is unsupported; nothing outside the bundle is a release claim.

---

## Integration with the 16-Phase Loop

| Phase | What touches the catalog |
|---|---|
| 2 | Initial `docs/contracts/invariant_catalog.toml` skeleton; one invariant per in-scope feature, all `Pending` |
| 3 | Oracle wiring populates the first `OracleDifferential` obligation per invariant |
| 4 | Golden capture populates `InstaSnapshot` obligations |
| 5 | Bench artifacts can be linked as `ArtifactRef` for performance-related invariants (rare; perf usually lives in `.bench-history/` not the catalog) |
| 6 | Conformance harness populates `MetamorphicProperty`, `ProptestInvariant`, `CrashBoundary`, `EProcess`, `FuzzNonPanic` obligations |
| 7 | `invariant-catalog-builder` subagent builds the full catalog with `validate()` clean exit |
| 9 | First full `release_traceability()` report; lands in `<workspace>/round_0/surface/invariant_traceability.json` |
| 11 | Each round re-runs `validate()`; convergence-tracker counts unresolved `Pending` + `Failing` |
| 12 | Remediation architect proposes work that flips `Pending → Satisfied` or `Failing → Satisfied` |
| 15 | Soak runs regenerate `FuzzNonPanic`, `EProcess`, `CrashBoundary` artifacts with longer wall-times; hashes update |
| 16 | Bundler runs `validate()`; ships `release_traceability()` report in certification bundle |

The catalog is the spine of Phase 11 convergence: convergence requires `validate() == empty` AND every invariant in state `Satisfied` (or `Excluded` per the corresponding `Feature` status). The Phase 15 soak is the last opportunity for `Pending → Satisfied` flips via long-running evidence generation.
