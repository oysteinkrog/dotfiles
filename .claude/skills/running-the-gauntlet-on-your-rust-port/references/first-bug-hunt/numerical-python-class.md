# First-Bug-Hunt Recipe: Numerical-Python-Class

These 10 bug classes surface in the first day on Numerical-Python-class ports (franken_numpy, frankenpandas, frankenscipy, franken_networkx).

**Prerequisites:** PyO3 in-process Python interpreter; reference library pinned; bit-exact PCG64DXSM RNG seeded; `TensorSpec` / `DataFrameSpec` / `GraphSpec` normalized comparator; per-op ULP tolerance table in `docs/contracts/ulp_tolerance_v1.toml`.

Per item: **symptom** → **paste-ready repro** → **MismatchClassification expected** → **severity** → **fix pattern**.

---

## 1. Dtype promotion in mixed-type ops

**Symptom.** `np.array([1], dtype=np.int8) + np.array([1.0], dtype=np.float32)` — NumPy 2.0 changed promotion rules (NEP 50). Subject may inherit 1.x or 2.x promotion; mismatch on first run.

**Repro:**
```bash
cargo test --package fnp-conformance --test dtype_promotion_oracle -- --nocapture
```

```python
# in oracle-side
import numpy as np
a = np.array([1], dtype=np.int8); b = np.array([1.0], dtype=np.float32)
out = a + b; out.dtype  # float32 under NEP 50; float64 pre-NEP 50
```

```rust
scenario_numpy(
    "a + b",
    inputs = {"a": int8([1]), "b": float32([1.0])},
    "dtype_promotion_int8_plus_float32"
);
```

**MismatchClassification:** `TypeAffinityDifference` (priority 2) or `TrueDivergence` if dtype mismatched as bug.
**Severity:** **high** — downstream computations use wrong dtype, cascading precision loss.
**Fix pattern:** [pattern:30-DIFFERENTIAL-V2-ENVELOPE](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md) with explicit `numpy_version` in contract; per-NumPy-version golden.

---

## 2. View vs copy edge cases

**Symptom.** `a[a > 0]` — boolean indexing returns a copy in NumPy; subject may return a view. Subsequent `a[a > 0] = 0` mutation behaves differently.

**Repro:**
```rust
scenario_numpy(
    inputs = {"a": float32([-1.0, 0.0, 1.0, 2.0])},
    "view_copy_boolean_indexing",
    assertions = [
        ("view = a[a > 0]", "np.shares_memory(a, view)"),  // False in NumPy
        ("view[0] = 99", "a == [-1.0, 0.0, 1.0, 2.0]"),     // a unchanged
    ],
);
```

**MismatchClassification:** `TrueDivergence { description: "shares_memory disagreement" }`.
**Severity:** **critical** — silent mutation bugs.
**Fix pattern:** `np.shares_memory(a, b)` agreement as required equality on every view-creating op.

---

## 3. Axis ordering in reductions of high-rank arrays

**Symptom.** `np.sum(a, axis=(0, 1, 2))` vs `np.sum(a, axis=(2, 1, 0))` — for float arrays, sum is not associative; differs by f64-ULP. Subject may iterate in different axis order than reference, exceeding ULP tolerance.

**Repro:**
```rust
scenario_numpy(
    inputs = {"a": rand_pcg64dxsm_float32(shape=(10, 10, 10, 10), seed=42)},
    "axis_order_reduction",
    assertions = [
        ("s1 = np.sum(a, axis=(0,1,2))", "s2 = np.sum(a, axis=(2,1,0))"),
        ("np.allclose(s1, s2, atol=1e-6)", "True"),
    ],
);
```

**MismatchClassification:** `FloatingPointDifference { max_epsilon_str: "<observed>" }`.
**Severity:** **medium-high** — ULP-table tolerance violation.
**Fix pattern:** [pattern:75-BAYESIAN-CONFORMAL-SCORE](../patterns/75-BAYESIAN-CONFORMAL-SCORE.md) with per-reduction-axis-order tolerance; document `axis` parameter semantics in contract.

---

## 4. Broadcast over zero-dim

**Symptom.** `np.array(1) + np.array([1, 2, 3])` — 0-D array + 1-D array broadcasts to 1-D. Subject may fail or return 0-D.

**Repro:**
```rust
scenario_numpy(
    inputs = {"a": scalar(1), "b": float32([1.0, 2.0, 3.0])},
    "broadcast_zero_dim",
    assertions = [("out = a + b", "out.shape == (3,)")],
);
```

**MismatchClassification:** `TrueDivergence`.
**Severity:** **high** — common pattern.
**Fix pattern:** dedicated test corpus for 0-D + N-D combinations.

---

## 5. NaN / Inf propagation in ufuncs

**Symptom.** `np.maximum(np.nan, 1.0)` → `nan` per NumPy. `np.fmax(np.nan, 1.0)` → `1.0`. Subject may swap the two.

**Repro:**
```rust
scenario_numpy(
    inputs = {"x": float32([nan, 1.0, inf, -inf]), "y": float32([2.0, nan, -1.0, 0.0])},
    "nan_inf_propagation",
    assertions = [
        ("np.maximum(x, y)", "[nan, nan, inf, 0.0]"),
        ("np.fmax(x, y)", "[2.0, 1.0, inf, 0.0]"),
        ("np.minimum(x, y)", "[nan, nan, -1.0, -inf]"),
    ],
);
```

**MismatchClassification:** `TrueDivergence` or `NullHandlingDifference` (treat NaN as Null analog).
**Severity:** **critical** — silent NaN propagation breaks downstream.
**Fix pattern:** explicit NaN-propagation corpus per ufunc; ULP tolerance does NOT apply (exact NaN/Inf required).

---

## 6. RNG state advance after sub-stream skip

**Symptom.** `rng.advance(N)` advances PCG64DXSM state by N steps; subject may advance by N+1 or N-1; first stream sample after advance diverges.

**Repro:**
```rust
scenario_numpy(
    inputs = {"seed": 42, "skip": 1_000_000},
    "pcg64dxsm_advance",
    assertions = [
        ("rng = np.random.Generator(np.random.PCG64DXSM(42))",
         "rng.bit_generator.advance(1000000)",
         "rng.random()", "==", reference_value),
    ],
);
```

**MismatchClassification:** `TrueDivergence`.
**Severity:** **critical** — reproducibility of seeded experiments breaks.
**Fix pattern:** bit-exact PCG64DXSM at multiple N advance counts; per-N golden in `rng_stream_proof.json`.

---

## 7. Integer overflow at type boundaries

**Symptom.** `np.int8(127) + np.int8(1)` — NumPy wraps to `-128` (silent). Subject may raise OverflowError or saturate.

**Repro:**
```rust
scenario_numpy(
    "x + y",
    inputs = {"x": int8(127), "y": int8(1)},
    "int8_overflow",
    expected = int8(-128)
);
```

**MismatchClassification:** `TypeAffinityDifference` or `TrueDivergence`.
**Severity:** **medium** — divergence between port behaviors.
**Fix pattern:** integer-overflow corpus per integer dtype × op.

---

## 8. Pandas NaN sentinel ambiguity (`np.nan` vs `pd.NA` vs `None`)

**Symptom.** `pd.DataFrame({'x': [None, np.nan, pd.NA]})` — three distinct sentinels coexist; `df.isna()` returns all True but column dtype may be `object` (preserving identity) or `Float64` (coercing all to `NA`). Subject may collapse to one sentinel.

**Repro:**
```rust
scenario_pandas(
    inputs = "pd.DataFrame({'x': [None, np.nan, pd.NA], 'y': pd.array([None, np.nan, pd.NA], dtype='Float64')})",
    "nan_sentinel_ambiguity",
    assertions = [
        ("df['x'].apply(type).tolist()", "[NoneType, float, NAType]"),
        ("df['y'].isna().all()", "True"),
    ],
);
```

**MismatchClassification:** `NullHandlingDifference { sentinel: <variant> }`.
**Severity:** **high** — three-way sentinel ambiguity is the largest pandas conformance hazard.
**Fix pattern:** extend `MismatchClassification::NullHandlingDifference` with explicit `sentinel: NanSentinel ∈ {NpNan, PdNA, None}` field.

---

## 9. SciPy solver-selection threshold drift

**Symptom.** `scipy.linalg.solve(A, b)` chooses LU vs Cholesky based on `assume_a` parameter and matrix structure detection. Subject's structure detector may pick the wrong solver near the threshold.

**Repro:**
```rust
scenario_scipy(
    inputs = {
        "A": near_spd_matrix(n=100, cond=1e8, asymmetry=1e-10),
        "b": rand_pcg64dxsm(n=100, seed=42),
    },
    "solver_selection_near_spd",
    assertions = [
        ("scipy.linalg.solve(A, b, assume_a='gen')",
         "scipy.linalg.solve(A, b, assume_a='pos')"),
        ("np.allclose(out_gen, out_pos, atol=1e-4)", "True"),
    ],
);
```

**MismatchClassification:** `TrueDivergence { description: "solver choice differs at threshold" }`.
**Severity:** **medium** — perf cliff at threshold; correctness within tolerance.
**Fix pattern:** CASP decision-fingerprint differential per [pattern:30-DIFFERENTIAL-V2-ENVELOPE](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md); per-cond-bucket golden.

---

## 10. NetworkX iteration order from hashed graph

**Symptom.** `G.nodes()` returns nodes in insertion order in NetworkX 3.x; subject may return in hash-ordered iteration; downstream `[n for n in G.nodes()]` differs.

**Repro:**
```rust
scenario_networkx(
    inputs = "G = nx.Graph(); G.add_nodes_from(['c', 'a', 'b'])",
    "iteration_order_after_insert",
    assertions = [("list(G.nodes())", "['c', 'a', 'b']")],  // insertion order
);
```

**MismatchClassification:** `OrderDependentDifference` or `TrueDivergence` if contract requires insertion order.
**Severity:** **medium-high** — algorithm output may depend on iteration order (BFS from "first node").
**Fix pattern:** explicit `iteration_order: insertion | sorted | hash_seeded` in GraphSpec; per-graph Tier 3 golden.

---

## Empirical first-day stats

- **3–5 of 10 in first hour** (dtype promotion, view-vs-copy, NaN propagation, integer overflow, RNG advance)
- **7–9 in first day** (add axis-order, pandas NaN sentinel, NetworkX iteration order)
- **All 10 by round 3** (SciPy solver threshold is deepest; requires condition-number-bucketed bench)

Items 3 (axis-order reduction) and 9 (SciPy solver threshold) are the deepest because they require explicit ULP-tolerance contracts AND condition-number gridding.

---

## Cross-references

- [PROJECT-CLASSES.md § Numerical-Python-Class](../taxonomy/PROJECT-CLASSES.md)
- [case-studies/franken_numpy.md](../case-studies/franken_numpy.md)
- [case-studies/frankenpandas.md](../case-studies/frankenpandas.md)
- [case-studies/frankenscipy.md](../case-studies/frankenscipy.md)
- [case-studies/franken_networkx.md](../case-studies/franken_networkx.md)
- [patterns/75-BAYESIAN-CONFORMAL-SCORE.md](../patterns/75-BAYESIAN-CONFORMAL-SCORE.md)
