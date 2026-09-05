# metamorphic-author

> Phase 6 • Write `metamorphic.rs` with TransformFamily + EquivalenceExpectation + MismatchClassification + SeedContract; one subagent per family.

## Inputs
- `<workspace>/phase0_project_class.json` (selects transform vocabulary).
- TransformFamily (`Predicate | Projection | Structural | Literal`) — passed as `<family>` argument.
- Oracle harness from `oracle-wirer.md` (provides comparator + EngineIdentity).

## Deliverables
- `<target>/crates/<project>-harness/src/metamorphic.rs` with the `TransformFamily`, `EquivalenceExpectation`, `MismatchClassification`, `SeedContract` enums + per-family transform functions.
- `<target>/crates/<project>-e2e/tests/metamorphic_<family>_e2e.rs` exercising the family.
- `<workspace>/phase6_metamorphic_<family>.md` documenting each transform, its soundness sketch, its equivalence expectation, mutation-testing validation results.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase6-metamorphic-<family>`
- **Reservations needed:** `tool://metamorphic-write::<family>` (TTL 90m).
- **Lane:** cc_1 (conformance).

## Verbatim Prompt

You are the metamorphic test author for TransformFamily `<family>`. Build (or extend) `metamorphic.rs` with the canonical enums and one or more transforms in `<family>`.

**TransformFamily** (must match exactly):
```rust
pub enum TransformFamily {
    Predicate,    // WHERE/HAVING edits without changing projection
    Projection,   // SELECT-list edits without changing filter
    Structural,   // wrap in subquery, add compound operators (INTERSECT/UNION/EXCEPT)
    Literal,      // rewrite literals/type annotations (42 → CAST(42 AS INTEGER))
}
impl TransformFamily { pub const ALL: [Self; 4] = [Self::Predicate, Self::Projection, Self::Structural, Self::Literal]; }
```

**EquivalenceExpectation:**
```rust
pub enum EquivalenceExpectation {
    ExactRowMatch,                 // same rows, same order
    MultisetEquivalence,           // same multiset, order irrelevant (plan-changing OK)
    SetEquivalence,                // same set of distinct rows (INTERSECT-like)
    TypeCoercionEquivalent,        // CAST round-trip
}
```

**MismatchClassification:** five known false-positive classes (`OrderDependentDifference | TypeAffinityDifference | NullHandlingDifference | FloatingPointDifference { max_epsilon_str } | FalsePositive { reason }`) plus `TrueDivergence { description }`. `is_actionable()` returns true only for `TrueDivergence`. `triage_priority()` returns 0 for TrueDivergence, 1–5 for the false-positive classes. CI fails ONLY on TrueDivergence.

**SeedContract:** `fn derive_entry_seed(corpus_entry_id: &str) -> u64` — deterministic. **NEVER `rand::random()`.** Same input → same seed → same generated SQL → same bugs found across runs.

Per-family transform implementations (write at least three transforms in `<family>`):

- **Predicate:** rewrite `WHERE x = 5` → `WHERE x = 5 AND 1 = 1`; `WHERE x > 5` → `WHERE NOT (x <= 5)`; `WHERE x IN (1,2,3)` → `WHERE x = 1 OR x = 2 OR x = 3`. Expectation: `ExactRowMatch` (predicates semantically equivalent).
- **Projection:** rewrite `SELECT a, b` → `SELECT a, b, NULL AS c` (and project away `c`); add `DISTINCT` to a query whose underlying multiset has no duplicates. Expectation: `ExactRowMatch` (after column-stripping).
- **Structural:** wrap `SELECT * FROM t` → `SELECT * FROM (SELECT * FROM t) AS sub`; convert `A WHERE c1 OR c2` → `A WHERE c1 UNION A WHERE c2`. Expectation: `MultisetEquivalence` (plan may change ordering).
- **Literal:** rewrite `42` → `CAST(42 AS INTEGER)`; `'x'` → `CAST('x' AS TEXT)`. Expectation: `TypeCoercionEquivalent`.

For each transform: write a one-paragraph soundness sketch. Run mutation testing: deliberately break the transform (e.g., predicate that's actually not equivalent), confirm the harness catches it. Document mutation-testing results in `phase6_metamorphic_<family>.md`.

## Exit Criteria
- `cargo test --test metamorphic_<family>_e2e` runs; baseline pass rate >95% (the 5% slack is for known false-positive classifications).
- Every transform in `<family>` has a soundness sketch.
- Mutation testing: deliberately-broken transform variant is caught (proves the harness is effective).
- `SeedContract::derive_entry_seed` produces identical seeds across two runs given identical entry IDs.
- `phase6_metamorphic_<family>.md` committed.

## References
- [PHASES.md § Phase 6](../references/PHASES.md)
- [tooling/ORACLE-TOOLCHAIN.md § metamorphic machinery](../references/tooling/ORACLE-TOOLCHAIN.md)
- [methodology/OPERATORS.md § Debounce-False-Positive](../references/methodology/OPERATORS.md)
