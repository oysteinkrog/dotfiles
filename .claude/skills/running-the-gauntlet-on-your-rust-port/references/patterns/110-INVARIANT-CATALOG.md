# Pattern 110 — Invariant Catalog

## What

Below the FeatureUniverse sits a typed catalog of ParityInvariants — one-to-many per Feature — each declaring `(invariant_id, statement, assumptions, proof_obligations[])`. Each `ProofObligation` names a `ProofKind`, points at an `ArtifactRef` (path + SHA-256 + schema version), and carries a `status`. The catalog has a `validate()` that returns `Vec<Violation>` (missing artifacts, hash mismatches, schema-version mismatches) and a `release_traceability()` that emits a per-feature report tying every claim to its evidence. A release that ships the catalog ships the proof-of-work.

## Why

> "The catalog doesn't just say 'we tested X', it says 'we tested X, the evidence is at path P with SHA-256 H against schema version V'. A release that ships the catalog ships the proof-of-work." — MINING-3 §11

Failure mode prevented: "feature X is verified" claims that point at no artifact, or point at an artifact whose hash has changed, or point at an artifact whose schema the current reader can no longer parse. Without an InvariantCatalog the evidence chain is verbal; with one it is verifiable from the release artifact alone.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/parity_invariant_catalog.rs` — the catalog and its `validate()` / `release_traceability()` / `stats()` methods.
- `crates/fsqlite-harness/src/parity_taxonomy.rs` — the Feature → ParityInvariant 1:N edge.
- `tests/artifacts/parity/*` — the ArtifactRef targets (oracle differential corpora, metamorphic results, crash-boundary recoveries, e-process trace summaries, fuzz no-panic certificates, insta snapshots).

## Verbatim shape

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

pub enum ProofKind {
    OracleDifferential,
    MetamorphicProperty,
    ProptestInvariant,
    CrashBoundary,
    EProcess,
    FuzzNonPanic,
    InstaSnapshot,
}
```

### The seven ProofKind variants

| Kind | What it proves | Typical ArtifactRef target |
|---|---|---|
| `OracleDifferential` | Subject answer == Oracle answer on a corpus | `tests/artifacts/parity/oracle_diff/{feature_id}.json` (Differential V2 envelope) |
| `MetamorphicProperty` | Subject(T(x)) ≡ Subject(x) under a transform family | `tests/artifacts/parity/metamorphic/{feature_id}.json` |
| `ProptestInvariant` | Property holds across `cargo proptest` generated inputs | `tests/artifacts/parity/proptest/{feature_id}.regressions` |
| `CrashBoundary` | Recovery after crash at named boundary B yields consistent state | `tests/artifacts/parity/crash/{feature_id}/{boundary}.json` |
| `EProcess` | Anytime-valid e-process never crossed `1/α` over N operations | `tests/artifacts/parity/eprocess/{invariant_id}.summary.json` |
| `FuzzNonPanic` | M hours of differential fuzz produced no panics; coverage report attached | `tests/artifacts/parity/fuzz/{feature_id}.coverage.json` |
| `InstaSnapshot` | Internal-layer textual output (plan / bytecode / IR) matches committed `.snap` | `crates/{c}/tests/snapshots/{feature_id}__*.snap` |

### ArtifactRef contract

```rust
pub struct ArtifactRef {
    pub path: PathBuf,             // relative to repo root
    pub hash: String,              // SHA-256, lowercase hex
    pub schema_version: String,    // e.g., "fsqlite-e2e.comprehensive-bench-report.v3"
}
```

`validate()` checks: (1) `path` resolves; (2) `sha256(read(path)) == hash`; (3) the artifact's embedded `schema_version` field matches. Any mismatch is a `Violation` and the release gate refuses.

## Per-class instantiation

| Class | Typical invariant statements |
|---|---|
| SQL | "NULL = NULL evaluates to UNKNOWN" (three-valued logic). "ROWID monotone within a single INSERT...SELECT" (storage). "WAL recovery preserves committed prefix" (durability). "INV-1: TxnId monotone (CAS)" (MVCC). |
| RESP | "DEL idempotent within MULTI/EXEC" (transactions). "PUBSUB FIFO per subscriber" (concurrency). "RDB ↔ AOF round-trip preserves all keys with TTLs" (persistence). "Cluster slot ownership covers 0..=16383" (cluster). |
| Numerical-Python | "ufunc broadcasts per NumPy rules" (broadcasting). "RNG `default_rng(seed).standard_normal(N)` produces bit-exact stream against reference" (RNG). "Array `view` does not allocate; `copy` does" (views). |
| ML-System | "softmax outputs sum to 1.0 within ε" (numeric). "Autograd gradient matches forward-mode JVP within ε" (autograd). "NCCL all-reduce sum matches closed-form" (distributed). |
| HTTP-Protocol | "Response status code matches reference for every fixture" (routing). "OpenAPI schema diff vs reference framework is empty modulo declared excluded paths" (surface). "Cancellation at body-mid returns 499/closed connection per reference" (lifecycle). |

Per-class invariants are owned by the class's harness crate; the catalog is the projection of those owners into a single reportable tree.

## Composition

- [pattern:105-FEATURE-UNIVERSE](105-FEATURE-UNIVERSE.md) — every `ParityInvariant` is a child of a `Feature`; the catalog cannot have invariants whose Feature id is missing from the universe.
- [pattern:120-VERIFICATION-CONTRACT](120-VERIFICATION-CONTRACT.md) — bead-close gate runs `validate()` and refuses to close if any `ProofObligation.status != Met` or any `ArtifactRef` fails resolution.
- [pattern:100-E2E-LOG-SCHEMA](100-E2E-LOG-SCHEMA.md) — log events carry `context.invariant_ids` so per-event coverage can be back-attributed to invariants.
- [pattern:90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) — every divergence bundle names the invariant(s) it violates; the catalog projects the count over time.
- [pattern:70-E-PROCESSES](70-E-PROCESSES.md) — invariants tagged `EProcess` connect to MVCC's INV-1..7 (or per-class equivalents).
- See [taxonomy/INVARIANT-CATALOG.md](../taxonomy/INVARIANT-CATALOG.md) for the full ProofObligation taxonomy.

## Pitfalls

- **`ArtifactRef.hash` stored as "TODO"** — turns the catalog into theater. Either compute the hash at artifact-write time or refuse to register the obligation.
- **`schema_version` defaulted to `"v1"`** — masks real schema drift. Every artifact emitter must stamp its own version constant; the catalog records what it actually finds.
- **`validate()` short-circuiting on first violation** — release reports need the full list of broken evidence; collect violations, don't bail.
- **Treating `Met` as "we ran the test once"** — `Met` means: artifact exists, hash matches, schema version matches, the artifact's contents pass the per-ProofKind acceptance predicate. Three preconditions, not one.
- **Allowing `ProofObligation` without a `ProofKind`** — every obligation must declare its kind; "we'll figure out how to verify later" obligations rot and become invisible debt.
- **`release_traceability()` emitting prose instead of structured JSON** — downstream consumers (the certification bundler, ratchet, dashboard) need machine-readable output. The markdown is the human view; the JSON is the API.
- **Letting invariants reference artifacts in `target/`** — `target/` is git-ignored; the artifact path must be tracked or pulled-from-CI. The catalog needs a stable address.
