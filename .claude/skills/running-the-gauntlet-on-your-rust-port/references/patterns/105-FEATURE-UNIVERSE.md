# Pattern 105 — Feature Universe

## What

A single typed enumeration of every behavioral feature the port intends to claim parity on, with a normalized weight per category (summing to exactly 1.0), a parity status drawn from a small enum (`Passing | Partial | Missing | Excluded`), and a deterministic iteration order keyed by `FeatureId`. The loader enforces the invariants; without enforcement the score is a number with no contract. With enforcement, the same source tree on x86 and ARM and WASM produces the same per-category score, the same global score, and the same SHA-256 of the emitted parity report.

## Why

> "The catalog doesn't just say 'we tested X', it says 'we tested X, the evidence is at path P with SHA-256 H against schema version V'. A release that ships the catalog ships the proof-of-work." — MINING-3 §11

Failure mode prevented: "we cover 90% of SQLite features" claims that no script can verify, that drift silently as new features land, and that round different ways on different machines. The FeatureUniverse turns the claim into a structured invariant the loader rejects if violated.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/parity_taxonomy.rs` (defines `Feature`, `FeatureId`, `ParityStatus`, `FeatureUniverse`)
- `crates/fsqlite-harness/src/score_engine.rs` (consumes the universe; applies `truncate_score`)
- `docs/contracts/supported_surface_matrix.toml` (versioned per-feature `supported | partial | excluded` declaration)

## Verbatim shape

```rust
pub struct Feature {
    pub id: FeatureId,                   // F-SQL-001
    pub title: String,
    pub weight: f64,                     // sum-per-category == 1.0
    pub status: ParityStatus,            // Passing | Partial | Missing | Excluded
    pub exclusion_rationale: Option<String>,
}
```

### Three loader-enforced invariants

1. `sum(weights) == 1.0` per category — enforced by the loader; load fails on violation.
2. `truncate_score` applied at every score boundary — 6 decimal places; ensures cross-platform bytewise identity (x86 vs ARM vs WASM differ at LSB).
3. `FeatureUniverse::features()` returns features sorted by `FeatureId` — deterministic iteration produces deterministic scoring produces meaningful SHA-256 of report.

### FeatureId scheme

`F-<CLASS>-<NNN>` — e.g., `F-SQL-001`, `F-RESP-014`, `F-TORCH-073`. The class prefix is the project class shorthand; the number is monotone within the class. New features take the next free number; numbers never recycle.

### ParityStatus semantics

| Status | Meaning | Counts toward release-100%? |
|---|---|---|
| `Passing` | Subject matches oracle on full corpus for this feature | yes |
| `Partial` | Subject matches oracle on some sub-cases; others diverge in known ways | no (partial NEVER rounds up; see [pattern:120-VERIFICATION-CONTRACT](120-VERIFICATION-CONTRACT.md)) |
| `Missing` | Subject does not implement this feature; oracle does | no |
| `Excluded` | Subject deliberately does not implement; `exclusion_rationale` required | counts as **debt** against strict-100% — see polish bar |

## Per-class instantiation

| Class | Categories (each must sum to 1.0) | Weight assignment rubric |
|---|---|---|
| SQL | DML, DDL, SELECT-shapes, NULL-semantics, JOIN, ORDER-LIMIT, AGGREGATE-WINDOW, PRAGMA, BLOB, CTE, TRIGGER, VIEW, CONFLICT, FK, TXN | Weight by (a) frequency in TPC-C / TPC-H / sqllogictest, (b) blast radius if broken, (c) C-SQLite test count for this surface. Default within category: equal-weight. |
| RESP | Strings, Hashes, Lists, Sets, SortedSets, Streams, PubSub, Transactions, Scripting, Cluster, Replication, Persistence | Weight by Redis 7.2.x command-count per category × `OBJECT FREQ` from production Redis sampling. |
| Numerical-Python | Dtype-promotion, Broadcasting, Ufunc-dispatch, Reduction, Linalg, FFT, RNG, IO | Weight by NumPy `__all__` membership × downstream-package import frequency (pandas, scipy, scikit-learn). |
| ML-System | Aten-ops, Autograd, JIT, Optim, DataLoader, Distributed, Sparse, Quantization | Weight by `torch.nn.functional` API surface × HuggingFace model-zoo usage. |
| HTTP-Protocol | Routing, Extractors, Validation, OpenAPI, Middleware, DI, WebSocket, Streaming, Cancellation | Weight by FastAPI tutorial / docs-example frequency × OWASP failure-class severity. |

### SurfaceMatrix companion

`docs/contracts/supported_surface_matrix.toml` declares per-feature `supported | partial | excluded` independently of measured `ParityStatus`. The loader cross-checks: a `Missing` measured against `supported` declared is a regression; a `Passing` measured against `excluded` declared is an inconsistency (drop the exclusion). This is a *versioned contract* — bumping it requires a beads bead.

## Composition

- [pattern:110-INVARIANT-CATALOG](110-INVARIANT-CATALOG.md) — each `Feature` is the root of a 1:N tree of `ParityInvariant`s, each of which has `ProofObligation`s pointing at `ArtifactRef`s.
- [pattern:115-CLOSURE-WAVE](115-CLOSURE-WAVE.md) — closure-wave enumerates expected behaviors per pipeline stage; each enumerated behavior becomes a `Feature`.
- [pattern:75-BAYESIAN-CONFORMAL-SCORE](75-BAYESIAN-CONFORMAL-SCORE.md) — the per-category posterior is `theta_c ~ Beta(α_prior + Σ weighted_successes, β_prior + Σ weighted_failures)`; the weights are exactly the FeatureUniverse weights.
- [pattern:120-VERIFICATION-CONTRACT](120-VERIFICATION-CONTRACT.md) — bead-close gate consults FeatureUniverse to verify the bead's claimed-improved features are actually measured `Passing`.
- See [methodology/KERNEL.md § K-5](../methodology/KERNEL.md) for the `truncate_score` axiom and [taxonomy/FEATURE-UNIVERSE.md](../taxonomy/FEATURE-UNIVERSE.md) for the full per-class playbook.

## Pitfalls

- **Letting weights drift from 1.0** — "they're approximately 1.0, the score is approximately right". The loader must reject `|sum - 1.0| > 1e-9`. Approximately-1.0 is undefined behavior.
- **Iterating via `HashMap`** — non-deterministic order ⇒ non-deterministic floating-point sum ⇒ non-bytewise-identical SHA-256. Always sort by `FeatureId`.
- **Counting `Partial` as a fractional `Passing`** — the score-engine does this internally (0.5 weight), but the *parity status* reported in the catalog is `Partial`, never "0.5 Passing". Don't conflate.
- **Treating `Excluded` as not counting against 100%** — for non-strict releases this is fine; for `RELEASE_CERTIFICATION_TEMPLATE.md`'s strict-100% claim, `Excluded` is debt that must be retired or the claim is false.
- **Bumping the universe between baseline and current without bumping the schema version** — the regression detector compares old-baseline scores against new-universe scores and finds spurious drift. Always bump `parity_taxonomy_schema_version` when adding/removing a feature.
- **Editing `exclusion_rationale` to "covered by another feature"** — that means the feature isn't actually excluded; merge it instead and bump the schema.
- **Dropping `truncate_score`** — cross-platform diff explodes; the ratchet flickers; the lower bound on the conformal band looks like noise.
