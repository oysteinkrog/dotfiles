# Numerical-Python-class Adoption Checklist

For ports in the Numerical-Python class (franken_numpy, frankenpandas, frankenscipy, franken_networkx).

## Phase 0 — Workspace
- [ ] `<workspace>/` git-init'd
- [ ] `docs/contracts/<ref>_version_contract.toml` pins (e.g., `numpy=1.26.0`)
- [ ] `[reference.extras]`: `simd_flags=[avx2,fma]`, `blas_impl="openblas"`, `blas_threads=1`, `rng_state_policy="PCG64DXSM-bit-exact"`
- [ ] PyO3 deps in `crates/<port>-harness/Cargo.toml`

## Phase 3 — Oracle wiring
- [ ] PyO3 in-process bridge with reference imported into sub-interpreter
- [ ] Determinism flags pinned: `OPENBLAS_NUM_THREADS=1`, `PYTHONHASHSEED=0`
- [ ] **Bit-exact PCG64DXSM RNG parity** for explicit seeds (NON-NEGOTIABLE for franken_numpy)
- [ ] `ArraySpec { shape, dtype, strides, base, writeable }` normalized comparator
- [ ] EngineIdentity strict-distinct
- [ ] Per-call seed capture + replay verification

## Phase 4 — Golden capture
- [ ] `.npy` / `.npz` fixture corpus with `manifest.v1.json`
- [ ] Per-dtype × per-shape coverage matrix
- [ ] RNG stream fixtures (PCG64DXSM seed → expected first 1024 outputs byte-identical)

## Phase 5 — Performance
- [ ] Per-ufunc-family bench (add/multiply/divide/...)
- [ ] Per-dtype bench (f32/f64/i32/i64/complex64/complex128)
- [ ] Per-axis reductions (sum/mean/max along axis)
- [ ] Linalg benches (matmul / solve / svd / eig)
- [ ] Shape-transform benches (reshape / transpose / broadcast / concatenate)
- [ ] `release-perf` profile (no SIMD-flag mismatch with reference)
- [ ] `simd_flags_guard.txt` in every artifact lane
- [ ] HotPath counters: `ufunc_dispatch_time_ns, array_alloc_bytes, iter_setup_time_ns, blas_call_count, lapack_call_count, random_pcg64dxsm_advance_count, array_view_creates, copy_on_write_breaks`

## Phase 6 — Conformance
- [ ] Oracle E2E per behavior class: dtype casting, array views vs copies, axis semantics, broadcasting rules, ufunc loop selection, error handling, NaN/Inf propagation, integer overflow semantics
- [ ] Differential V2 envelope with `ArraySpec` canonicalization
- [ ] Metamorphic transforms: order-invariance (`sum(a) + sum(b) ≡ sum(concatenate([a,b]))`), reshape-equivalence, transpose-roundtrip
- [ ] Per-op tolerance table (per-ufunc default + override per op) in `docs/contracts/ulp_tolerance_v1.toml`
- [ ] Mismatch minimizer with array-shape-preservation guard
- [ ] Insta snapshots: ufunc dispatch trace, BLAS call sequence
- [ ] **`scripts/run-numpy-all-check.sh`** — strict 100% `numpy.__all__` coverage gate
- [ ] Differential fuzz: `arbitrary` ArraySpec generator → both reference and subject
- [ ] E-processes: dtype-promotion stability, view-aliasing invariants

## Phase 7 — Surface
- [ ] FeatureUniverse covers every `numpy.__all__` entry (499/499 for numpy 1.26.0)
- [ ] Per-IO-format axis for pandas (CSV, parquet, feather, JSON, HDF5, SQL, pickle, Excel, HTML, fixed-width, XML, ORC, BigQuery, GBQ) — 14+ formats
- [ ] Per-aggregation-family axis for pandas (groupby, rolling, expanding, ewm, resample)
- [ ] (NetworkX) traversal-order MultisetEquivalence by default (since iteration order isn't part of NetworkX's API contract)

## Phase 8 — Negative ledger
- [ ] AGENTS.md mandate with Numerical-class failure terms: `SIMD/vectorization changing dtype, view/copy shortcuts, RNG acceleration breaking bit-exact seeds, columnar storage drift, groupby fast paths, query expression rewrites, IO parser shortcuts`

## Class-specific extras
- [ ] **franken_numpy**: 6,392 test gate; bit-exact PCG64DXSM RNG; "G1-G8 CI gates"
- [ ] **frankenpandas**: 1,252 conformance packets; 14+ IO format coverage
- [ ] **frankenscipy**: Condition-Aware Solver Portfolio routing accuracy as a primary metric
- [ ] **franken_networkx**: NetworkX 3.x dual-mode backend + standalone parity
