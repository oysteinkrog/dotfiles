# Case Study: FrankenNumPy — `/dp/franken_numpy`

The closest Numerical-Python-class sibling to FrankenSQLite's discipline level. Conformance is mature; the lift is on the performance pillar (`comprehensive_bench`-equivalent) and on the math-toolkit application.

---

## 1. Snapshot

| Field | Value |
|---|---|
| **Class** | Numerical-Python-class ([PROJECT-CLASSES.md § Numerical-Python-Class](../taxonomy/PROJECT-CLASSES.md)) |
| **Tier** | **T3 — Workspace** with numerical-determinism overlay. Crates: `fnp-conformance`, `fnp-dtype`, `fnp-io`, `fnp-iter`, `fnp-linalg`, `fnp-ndarray`, `fnp-python`, `fnp-random`, `fnp-runtime`, `fnp-ufunc` |
| **Recommended mode** | `gauntlet-full` to complete the partial adoption; `incremental-rebase` for routine |
| **Reference pinning** | `docs/contracts/numpy_version_contract.toml` likely at `numpy-1.26.0` or `2.0.x`; preflight doctor verifies `numpy.__version__`, `numpy.show_config()` SIMD flags + BLAS thread count match the contract |
| **README claims summary** | `numpy.__all__`-level structural parity; bit-exact PCG64DXSM RNG stream; per-ufunc ULP-tolerant; Arrow-backed `ndarray`. Recent activity (commits `d73b4644`, `59e5b44f`, `2a918d75`) is "fresh-eyes harden conformance runner" — the discipline is being formalized in real time. |

---

## 2. Adoption Matrix

| Pillar / Discipline | Status | Notes |
|---|:---:|---|
| Conformance | ✅ | `numpy.__all__` structural-gate parity; tensor bundles; dtype/shape manifests; RNG-stream fixtures |
| Negative ledger | ✅ DIVERGENCES | More focused than FrankenSQLite's "rejected ideas" — surfaces actual NumPy divergences |
| cass | ✅ | wired |
| Agent Mail | ✅ | wired |
| bv | ✅ | wired |
| Math layer (§75–76) | ⚠️ partial | bit-exact RNG but **not the full §75–76 toolkit applied to ufunc dispatch** |
| MT-scale harness | ❌ N/A | NumPy hot paths fundamentally single-threaded (BLAS multi-threading is the exception, not the rule) |
| RaptorQ | ✅ | re-used from FrankenSQLite ecosystem |
| `comprehensive_bench.rs` equivalent | ❌ | benches present but unweighted; no six-category structure |
| Per-ufunc ULP tolerance table | ⚠️ | implicit via tests; **not formalized as `ulp_tolerance_v1.toml`** |

---

## 3. Per-Pillar Deep Dive

### (a) Performance — current state + first 3 gaps

**Current state.** Benches exist per-ufunc. SIMD vectorization story implicit. No weighted-category aggregate. No `.bench-history` ratchet.

**First 3 gaps:**
1. **No weighted `comprehensive_bench`** with the proposal weights (`UfuncDispatch 0.30 / Reductions 0.20 / ShapeTransforms 0.15 / Linalg 0.15 / RNGDistributions 0.10 / IOFormats 0.10`). Every perf claim is unprovable across versions.
2. **`ufunc_dispatch_time_ns` not exposed as counter** — dispatch overhead is the dominant cost for small arrays; without instrumentation, a regression here is invisible.
3. **`copy_on_write_breaks` not exposed** — NumPy 2.0 introduces copy-on-write semantics; tracking when a view becomes a copy under fast-path SIMD is essential.

### (b) Conformance — current state + first 3 gaps

**Current state.** Best-in-class for this maturity tier. PCG64DXSM byte-exact. `numpy.__all__` enumerated. Tensor bundles + dtype/shape manifests. DIVERGENCES ledger captures actual divergences.

**First 3 gaps:**
1. **SIMD vectorization path NaN propagation order** — at least one ufunc where SIMD path orders NaN propagation differently from scalar path; surfaces under `UlpToleranceEqual { n_ulps=2 }` for transcendentals.
2. **`numpy.testing.assert_array_almost_equal` defaults conflated with explicit tolerances.** First-pass review: 20–50 tests use defaults; should use explicit per-op tolerances from the table.
3. **`np.shares_memory` semantics for views of views.** View-of-view invariants: when does the third-level slice share memory with the original? NumPy 2.0 changes; the port may not have updated.

### (c) Surface — current state + first 3 gaps

**Current state.** `numpy.__all__` is the structural gate; what's exposed is enumerated. But weights per family not assigned.

**First 3 gaps:**
1. **`numpy.lib.*` submodules likely under-enumerated** — `numpy.lib.format`, `numpy.lib.npyio` are legitimate parts of the API.
2. **`numpy.ma` (masked arrays) likely `excluded` collectively** — strict-100% hollow on this dimension.
3. **`numpy.distutils` officially deprecated** — should be `excluded` with a "deprecated upstream" justification.

---

## 4. First-Pass Recipe

```bash
SKILL_ROOT="${GAUNTLET_SKILL_ROOT:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
[ -d "$SKILL_ROOT" ] || SKILL_ROOT="$HOME/.codex/skills/running-the-gauntlet-on-your-rust-port"

"$SKILL_ROOT/scripts/kickoff.sh" gauntlet-full
"$SKILL_ROOT/scripts/gauntlet.sh" /dp/franken_numpy /dp/franken_numpy__gauntlet_workspace \
  --mode gauntlet-full --dry-run

# Phase-specific inputs for the orchestrator/subagents:
# - reference pin: numpy-1.26.0 + OpenBLAS + AVX2/SIMD contract
# - oracle mode: PyO3 in-process NumPy; BLAS/OpenMP thread counts pinned to 1
# - perf weights: UfuncDispatch=0.30, Reductions=0.20, ShapeTransforms=0.15,
#   Linalg=0.15, RNGDistributions=0.10, IOFormats=0.10
# - conformance floor: TensorSpec comparator, ULP table, bit-exact PCG64DXSM
# - failure terms: SIMD broke dtype, view became copy, RNG stream diverged,
#   NaN propagated where reference returned scalar, BLAS thread count drifted,
#   ufunc loop selection changed

"$SKILL_ROOT/scripts/gauntlet.sh" /dp/franken_numpy /dp/franken_numpy__gauntlet_workspace \
  --mode gauntlet-full --soak-hours 72
```

Wall time T3 × `gauntlet-full`: **14–28 days.** `rch`-offload recommended for full bench matrix.

---

## 5. Expected Pillar Findings

### Performance
1. **`ufunc_dispatch_time_ns` dominates small-array ops** — first profile-card.
2. **SIMD path takes longer than scalar for small arrays** — vectorization-tip below break-even.
3. **`array_alloc_bytes` non-zero for slices** — a slice that should be a view is allocating; pattern 2 lesson (AtomicBool gate on view-vs-copy decision).
4. **`copy_on_write_breaks` spike** under specific stride patterns — CoW heuristic too aggressive.
5. **`blas_call_count` for ops that don't need BLAS** — small matmul going to BLAS when it shouldn't.
6. **`random_pcg64dxsm_advance_count` mismatch** — RNG state advance differs by 1 between sub-streams.
7. **`iter_setup_time_ns` non-amortized** for tiny arrays — iter setup is a hot constant overhead.
8. **`array_view_creates` cost** — view-creation is fast but not free; hot loops may create gratuitously.

### Conformance
1. **f32 → f64 promotion in mixed-type ops** — order-of-operations divergence.
2. **View vs copy edge case** — when does `a[a > 0]` (boolean indexing) return a view vs copy?
3. **Axis ordering in reductions of high-rank arrays** — `(0,1,2)` vs `(2,1,0)` differs by f64-ULP on f32 sums.
4. **Broadcast over zero-dim** — `np.array(1)` + `np.array([1,2,3])` corner.
5. **NaN/Inf propagation in ufuncs** — `np.maximum(nan, x)` vs `np.fmax(nan, x)` semantics.
6. **RNG state advance after sub-stream skip** — `np.random.Generator.advance(N)` byte-identity.
7. **Integer overflow at type boundaries** — `int32 max + 1` wrapping behavior.
8. **`numpy.linalg.svd` sign convention** — non-unique decomposition; canonical-sign choice.
9. **`np.fft.fft` normalization mode** — `'backward'` vs `'forward'` vs `'ortho'` differences.
10. **`np.einsum` path optimization** — `optimize='optimal'` produces same numerical result; default does not.

### Surface
1. **`numpy.polynomial.*` likely partial-present**.
2. **Structured arrays (`np.dtype([('x', 'f4'), ('y', 'f4')])`)** edges.
3. **`numpy.f2py` likely excluded** (Fortran wrapping).

---

## 6. Patterns to Apply First

1. **[pattern:125-COMPREHENSIVE-BENCH](../patterns/125-COMPREHENSIVE-BENCH.md)** — lift FrankenSQLite template; six weighted categories adapted for NumPy.
2. **Per-ufunc ULP tolerance table as `docs/contracts/ulp_tolerance_v1.toml`** — per-op default + per-dtype exception rows.
3. **[pattern:40-METAMORPHIC-TRANSFORMS](../patterns/40-METAMORPHIC-TRANSFORMS.md)** — per-ufunc: `ExactBitEqual` for integer ops, `UlpToleranceEqual { n_ulps }` for float ops, `BroadcastEquivalent` for shape transforms.
4. **§75–76 toolkit selectively applied** — Beta-Binomial for ufunc pass rates, e-process for `numpy.testing` invariant monitoring, BOCPD for performance regime tracking.
5. **[pattern:155-BENCH-HISTORY-RATCHET](../patterns/155-BENCH-HISTORY-RATCHET.md)** — `.bench-history/comprehensive_bench.latest.json` committed; pass-over-pass ratchet.

---

## 7. Estimated Rounds to Convergence

**8–12 rounds.** Existing DIVERGENCES ledger and bit-exact RNG give a strong baseline; rounds 1–5 add structure (comprehensive_bench, tolerance table, weights), rounds 6–12 close per-ufunc tail.

---

## 8. Risk Register

1. **NumPy 2.0 migration churn.** NumPy 2.0 changes promotion rules, copy semantics, and `np.bool` vs `bool`. Pinning to 1.26.0 vs 2.0.x is a strategic choice. *Mitigation:* contract names the major version; `migration` mode bumps.
2. **OpenBLAS thread-count drift.** `OPENBLAS_NUM_THREADS=1` must be enforced at process start; some test harnesses inherit ambient env. *Mitigation:* `blas_thread_count_default_guard.txt` per artifact lane.
3. **PCG64DXSM byte-identity at sub-stream boundaries.** Reference numpy implementation may use slightly different sub-stream advance; verify per-N-element stream identity at multiple stream lengths.

---

## 9. What Ships from Convergence

`certification_bundle/`:
- Universal floor
- `ulp_tolerance_compliance.json` — per-ufunc observed vs tolerated
- `rng_stream_proof.json` — PCG64DXSM byte-identity proof for N seeds × M stream lengths
- `view_copy_invariants.json` — per-op `shares_memory` agreement
- `simd_path_agreement.json` — SIMD vs scalar path equivalence proof

Plus standard triple + bead graph.

---

## Cross-references

- [SIBLING-PROJECTS-STATUS.md § FrankenNumPy](../exemplars/SIBLING-PROJECTS-STATUS.md)
- [PROJECT-CLASSES.md § Numerical-Python-Class](../taxonomy/PROJECT-CLASSES.md)
- [first-bug-hunt/numerical-python-class.md](../first-bug-hunt/numerical-python-class.md)
