# Pattern 50 — THREE-TIER EQUIVALENCE (Tier 1 raw / Tier 2 canonical / Tier 3 logical)

## What

A three-valued `EquivalenceTier` enum that every golden-artifact match self-labels: Tier 1 = raw SHA-256 byte equality; Tier 2 = canonical-form byte equality (after VACUUM INTO + stable PRAGMAs / `torch.use_deterministic_algorithms(True)` / equivalent normalization); Tier 3 = logical equality (row count + columns + values via `==`, or tensor shape + dtype + per-op-ULP-binned data hash). The JSON match report must name which tier succeeded. The cardinal rule: *encode the distinction; never paper over it*.

## Why

> "Rule (CC §7.6): 'Encode the distinction; never paper over it.' A Tier2 match is not Tier1; the JSON report must name which tier succeeded." — MINING-2 §6

Two engines that "agree" might agree byte-for-byte (Tier 1), or only after we normalize whitespace and float formatting (Tier 2), or only at the logical level after we sort and ULP-bin (Tier 3). A reviewer reading a green report deserves to know which it is — claiming "100% byte equivalence" when the truth is "100% logical equivalence with 4-ULP tolerance" is the K-2 anti-pattern in disguise. The tier label keeps the comparator's strictness visible at every gate.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/equivalence_tier.rs` — the enum + helpers (MINING-2 §6)
- `crates/fsqlite-e2e/tests/golden_artifact_capture.rs` — golden-artifact emission with tier labels
- Insta snapshots are Tier 2 by default; raw byte fixtures are Tier 1; logical dumps are Tier 3.

## Verbatim shape — the enum + the rule

From MINING-2 §6, verbatim:

```rust
pub enum EquivalenceTier {
    Tier1Raw,         // raw SHA-256 byte equality
    Tier2Canonical,   // after normalization (VACUUM INTO + stable PRAGMAs / torch.use_deterministic_algorithms)
    Tier3Logical,     // logical deterministic SQL or tensor dump (row count + columns + values via ==)
}
```

**Rule (verbatim, MINING-2 §6):** "Encode the distinction; never paper over it."

### JSON report shape

Every match report carries the tier:

```jsonc
{
  "schema_version": "gauntlet.golden_match.v1",
  "subject_artifact": "artifacts/bd-xyz/subject.db",
  "subject_sha256": "abc123…",
  "oracle_artifact": "fixtures/oracle/baseline.db",
  "oracle_sha256": "def456…",
  "equivalence_tier_attempted": "Tier1Raw",     // strictest attempted
  "equivalence_tier_succeeded": "Tier2Canonical", // weakest needed
  "tier1_diff_summary": { "byte_offset_first_diff": 4096, "diff_bytes": 17 },
  "tier2_normalization_applied": ["vacuum_into", "pragma_user_version=0"],
  "tier2_diff_summary": null,                   // Tier 2 succeeded
  "tier3_logical_columns": null
}
```

## Per-class instantiation

### SQL-class

| Tier | Equality predicate | When to use |
|---|---|---|
| **Tier 1 raw** | `sha256(subject_db_bytes) == sha256(oracle_db_bytes)` | After identical-`VACUUM INTO` + identical PRAGMAs + same `page_size`; the strictest claim possible. Insta snapshots of WAL frames are Tier 1. |
| **Tier 2 canonical** | After `VACUUM INTO temp.db` with identical PRAGMAs, then SHA-256 of the canonicalized file | Most golden-artifact tests live here. Catches "logically same but page-layout differs due to insertion order". |
| **Tier 3 logical** | `SELECT * FROM <table> ORDER BY <pk>` produces same `Vec<Vec<String>>` after [pattern:35-NORMALIZED-VALUE](35-NORMALIZED-VALUE.md) rendering | Use when page layout legitimately differs (e.g., compared engine doesn't support VACUUM INTO). |

### RESP-class

| Tier | Equality predicate | When to use |
|---|---|---|
| **Tier 1 raw** | `sha256(rdb_bytes) == sha256(reference_rdb_bytes)` | Pinned RDB v11 byte fixtures; the strictest claim. |
| **Tier 2 canonical** | RDB → in-memory KV → re-serialize with canonical encoding (same compression / hash-table seed) → SHA-256 | Most RDB comparisons. Insulates from per-build hash-seed differences. |
| **Tier 3 logical** | Per-key `RespValue` via [pattern:35-NORMALIZED-VALUE](35-NORMALIZED-VALUE.md) | Multiprocess + cluster comparisons where on-disk layout differs but logical KV is identical. |

### Numerical / ML-class

| Tier | Equality predicate | When to use |
|---|---|---|
| **Tier 1 raw** | `sha256(tensor.contiguous().to_bytes()) == sha256(oracle.to_bytes())` | Bit-exact deterministic ops (integer reductions, exact-arithmetic). |
| **Tier 2 canonical** | After `torch.use_deterministic_algorithms(True)` + casting to canonical dtype + memory-format `contiguous_format` → SHA-256 | Most ML golden artifacts. |
| **Tier 3 logical** | TensorSpec via [pattern:35-NORMALIZED-VALUE](35-NORMALIZED-VALUE.md) with per-op ULP-binned `data_hash` (4 ULP f32 matmul, 2 ULP elementwise) | Use when bit-exact is impossible (non-deterministic CUDA kernels, mixed-precision). |

### HTTP-class

| Tier | Equality predicate | When to use |
|---|---|---|
| **Tier 1 raw** | `sha256(response_bytes) == sha256(reference_response_bytes)` | Static-content endpoints. |
| **Tier 2 canonical** | After header case-fold + header sort + JSON body canonicalization → SHA-256 | Most HTTP golden artifacts (the OpenAPI golden files). |
| **Tier 3 logical** | Status code category + parsed-body field-equality | When body field order varies (set-typed fields). |

## Composition

- [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) — `CanonicalizationRules` parameterize the Tier 2 normalization.
- [pattern:35-NORMALIZED-VALUE](35-NORMALIZED-VALUE.md) — Tier 3 logical equality goes through the canonical rendering.
- [pattern:40-METAMORPHIC-TRANSFORMS](40-METAMORPHIC-TRANSFORMS.md) — `EquivalenceExpectation::ExactRowMatch` ~ Tier 1; `MultisetEquivalence` ~ Tier 2; `SetEquivalence` ~ Tier 3.
- [pattern:55-INSTA-GOLDEN-SNAPSHOTS](55-INSTA-GOLDEN-SNAPSHOTS.md) — insta snapshots are typically Tier 1 byte (raw bytecode/plan text); regression at Tier 1 is the regression-pin guarantee.

## Pitfalls

- **Reporting only the succeeded tier, not the attempted tier.** A report that says `Tier3Logical: pass` hides whether Tier 1 and Tier 2 were tried and failed. The schema carries both `equivalence_tier_attempted` and `equivalence_tier_succeeded`.
- **Tier 3 silently used when Tier 2 is feasible.** Some teams downgrade to Tier 3 to "make CI green"; this is the K-2 violation. Tier 2 should always be attempted first; downgrading to Tier 3 must be explicitly opted in per-test.
- **Tier 1 considered "the goal" for every artifact.** Tier 1 is wonderful when achievable but not always feasible (non-deterministic kernels, hash-randomization on hash maps). Demand the strictest tier each artifact can plausibly meet, no stricter.
- **Tier 2 normalization different between subject and oracle.** Tier 2 normalization is a *function* — it must apply identically to both sides. A test that VACUUMs the subject but not the oracle is comparing apples to oranges and Tier 2 is meaningless.
- **Adding a Tier 4 "approximate" or Tier 0 "exact-instruction-trace".** Don't. The three-tier taxonomy is a deliberate floor + canonical + logical decomposition; extending it dilutes the per-tier semantics. New use cases either fit one of the three or warrant a new comparator type entirely (e.g., probabilistic equivalence is *not* a tier).
- **JSON report omits `tier1_diff_summary` when Tier 1 fails.** Even when Tier 1 fails and Tier 2 succeeds, the Tier 1 diff is valuable diagnostic data — it tells you *what* the canonicalization needed to absorb. Always include the per-tier diff summaries.
- **"Tier 3 logical" comparator that uses `==` on `f64` directly.** That's not logical; that's bit-exact. Tier 3 must apply per-op ULP tolerance or the equivalent normalization for the data type.
