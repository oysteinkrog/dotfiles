# Pattern 40 — METAMORPHIC TRANSFORMS (`TransformFamily × EquivalenceExpectation × MismatchClassification`)

## What

Three composable enums + a seed contract that let the harness generate query/operation rewrites whose answer should equal the original's answer under a named equivalence expectation. `TransformFamily` enumerates the rewrite shape (Predicate / Projection / Structural / Literal); `EquivalenceExpectation` says how strictly the two answers must match; `MismatchClassification` says why they didn't if they don't. The `SeedContract` (`derive_entry_seed`) guarantees that the same corpus entry id always derives the same seed → same generated rewrites → same bugs found. Never `rand::random()`. Operationalizes K-1 in the metamorphic row of the 8-pillar table.

## Why

> "When you can't verify *what* the output is, verify *how* outputs relate to each other under known input transformations." — `/testing-metamorphic` skill (MINING-1 §5)

The oracle differential row of K-1 needs a reference engine. Metamorphic doesn't: Subject and Oracle are the same engine evaluating two related queries. This lets you find bugs that exist in *both* engines (e.g., a NULL-handling quirk that both `fsqlite` and `csqlite` inherit from a shared spec ambiguity) — those are invisible to the differential row but loud in the metamorphic row.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/metamorphic.rs` — `TransformFamily`, `EquivalenceExpectation`, `MismatchClassification`, `SeedContract` (MINING-2 §4)
- Per-family transform implementations in submodules

## Verbatim shape — the four types

### `TransformFamily`

From MINING-2 §4, verbatim:

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

### `EquivalenceExpectation`

```rust
pub enum EquivalenceExpectation {
    ExactRowMatch,                 // same rows, same order
    MultisetEquivalence,           // same multiset, order irrelevant (plan-changing OK)
    SetEquivalence,                // same set of distinct rows (INTERSECT-like)
    TypeCoercionEquivalent,        // CAST round-trip
}
```

### `MismatchClassification`

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

**CI rule (verbatim, MINING-2 §4):** "CI fails only on `TrueDivergence`. Other classes flow into triage queue."

### `SeedContract` — deterministic seed derivation

```rust
fn derive_entry_seed(corpus_entry_id: &str) -> u64 { /* deterministic */ }
```

**Rule (verbatim, MINING-2 §4):** "Never `rand::random()`. Same input → same seed → same SQL → same bugs found."

Canonical implementation:

```rust
fn derive_entry_seed(corpus_entry_id: &str) -> u64 {
    let h = blake3::hash(corpus_entry_id.as_bytes());
    let mut bytes = [0u8; 8];
    bytes.copy_from_slice(&h.as_bytes()[..8]);
    u64::from_le_bytes(bytes)
}
```

## Per-class instantiation — family analogues

### SQL-class

| Family | Example transform | Default `EquivalenceExpectation` |
|---|---|---|
| `Predicate` | `WHERE x = 1` → `WHERE x = 1 AND 1=1` | `ExactRowMatch` |
| `Predicate` | `WHERE x = 1` → `WHERE NOT NOT (x = 1)` | `ExactRowMatch` |
| `Projection` | `SELECT x` → `SELECT x, (SELECT 1) AS dummy` followed by `DROP COLUMN dummy` in result projection | `ExactRowMatch` |
| `Structural` | `SELECT * FROM t` → `SELECT * FROM (SELECT * FROM t)` | `ExactRowMatch` |
| `Structural` | `SELECT * FROM t WHERE x > 5` → `SELECT * FROM t INTERSECT SELECT * FROM t WHERE x > 5` | `SetEquivalence` (DISTINCT-coerced) |
| `Literal` | `WHERE x = 42` → `WHERE x = CAST(42 AS INTEGER)` | `TypeCoercionEquivalent` |

### RESP-class

| Family | Example transform | Default `EquivalenceExpectation` |
|---|---|---|
| `Predicate` | `SCAN MATCH foo*` → `SCAN MATCH foo* COUNT 100` (no semantic change) | `SetEquivalence` (SCAN returns are unordered) |
| `Projection` | `HGETALL key` → `HMGET key f1 f2 f3 ...` for all known fields | `MultisetEquivalence` (then sort) |
| `Structural` | `MGET k1 k2 k3` → `[GET k1; GET k2; GET k3]` (pipeline) | `ExactRowMatch` |
| `Literal` | `INCRBY k 5` ; `INCRBY k 3` → `INCRBY k 8` | `ExactRowMatch` on final state |

### Numerical / ML-class

| Family | Example transform | Default `EquivalenceExpectation` |
|---|---|---|
| `Predicate` | `np.where(x > 0, x, 0)` → `np.maximum(x, 0)` | `ExactRowMatch` (bit-exact) |
| `Projection` | `t.sum(dim=0)` → `t.transpose(0,1).sum(dim=1)` | `MultisetEquivalence` with per-op ULP tolerance |
| `Structural` | `torch.matmul(a, b)` → `torch.matmul(b.transpose(-1,-2), a.transpose(-1,-2)).transpose(-1,-2)` | `MultisetEquivalence` with f32-matmul ULP (4 ULP) |
| `Literal` | `tensor(1.0, dtype=float32)` → `tensor(1.0).to(float32)` | `TypeCoercionEquivalent` |

### HTTP-class

| Family | Example transform | Default `EquivalenceExpectation` |
|---|---|---|
| `Predicate` | `GET /items?status=active` → `GET /items?status=active&_=ignored` (unused param) | `ExactRowMatch` |
| `Projection` | `GET /items` → `GET /items` with `Accept: application/json` vs `application/vnd.api+json` | `TypeCoercionEquivalent` (body semantics same, MIME differs) |
| `Structural` | `POST /batch [{"op":"a"}, {"op":"b"}]` → `[POST /single {"op":"a"}; POST /single {"op":"b"}]` | `ExactRowMatch` on final state |
| `Literal` | `?count=5` → `?count=5.0` (string-typed query param coercion) | `TypeCoercionEquivalent` |

## Composition

- [pattern:05-SUBJECT-ORACLE-COMPARATOR](05-SUBJECT-ORACLE-COMPARATOR.md) — metamorphic is the row where Subject == Oracle (same engine, related queries).
- [pattern:35-NORMALIZED-VALUE](35-NORMALIZED-VALUE.md) — `MismatchClassification::FloatingPointDifference { max_epsilon_str }` and `TypeAffinityDifference` are the bypasses for the strict-equality comparator.
- [pattern:45-MISMATCH-MINIMIZER](45-MISMATCH-MINIMIZER.md) — `MismatchClassification` feeds into `MismatchSignature.classification`; same signature = same bug.
- [pattern:50-THREE-TIER-EQUIVALENCE](50-THREE-TIER-EQUIVALENCE.md) — `EquivalenceExpectation` is the runtime expression of the three-tier golden-artifact equivalence; `ExactRowMatch` ~ Tier 1, `MultisetEquivalence` ~ Tier 2, `SetEquivalence` ~ Tier 3.
- [pattern:90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) — `FailureBundle.failure_type = Divergence` carries the metamorphic classification.

## Pitfalls

- **Using `rand::random()` instead of `derive_entry_seed`.** The most common cause of "flaky metamorphic test"; the test passes 99% of the time because the seed-of-the-day happens to miss a known divergence. Same input → same seed; non-negotiable.
- **`EquivalenceExpectation` too weak.** Defaulting to `SetEquivalence` for queries that have a meaningful order (e.g., `ORDER BY`) hides ordering bugs. Use the strictest expectation the transform allows.
- **`EquivalenceExpectation` too strict.** Using `ExactRowMatch` for a metamorphic rewrite that legitimately changes the plan (and thus the row order for ORDER-BY-less queries) produces false positives — flow class `OrderDependentDifference`, not `TrueDivergence`. CI fails on the latter only.
- **Adding a new `MismatchClassification` variant without bumping `triage_priority`.** The priority is what makes the triage queue actionable. Adding `BlobEncodingDifference` without choosing a priority leaves it un-triaged forever.
- **CI failing on `OrderDependentDifference`.** The CI rule (verbatim above): CI fails ONLY on `TrueDivergence`. Tightening this gate breaks non-actionable triage entries into blocking failures and the team learns to ignore CI.
- **Transform that changes more than the family says.** `Predicate` rewrites must not change the SELECT list. A transform that does both is `Structural` by default. Mis-labeling makes the family taxonomy useless.
- **Metamorphic comparator skips `EngineIdentity` check.** Metamorphic is Subject-vs-Subject by design; the K-9 check uses a different envelope (`MetamorphicEnvelope` with one identity field). Don't enable the discriminator and then disable it case-by-case.
- **Generator forgets to record the transform applied.** When a mismatch surfaces, the failure bundle needs `transform_family` + `transform_id` + `original_query` + `transformed_query` to be reproducible. Generate the seed deterministically AND log the rewrite.
- **`FalsePositive` used as an escape hatch.** Reaching for `FalsePositive { reason }` to silence a flake means the next agent will reach for it too. `FalsePositive` is reserved for known-good cases (e.g., "we don't model timezone conversion" reproduced exactly).
