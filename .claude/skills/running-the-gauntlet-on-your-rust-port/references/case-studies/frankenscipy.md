# Case Study: FrankenSciPy — `/dp/frankenscipy`

The condition-number-aware solver-portfolio class. SciPy decisions depend on condition × sparsity × problem-size — and the port's choices must agree with live SciPy where it matters and document where it doesn't. CASP solver policy is the math-layer foothold; the rest is unbuilt.

---

## 1. Snapshot

| Field | Value |
|---|---|
| **Class** | Numerical-Python-class with numerical-determinism + solver-portfolio overlays ([PROJECT-CLASSES.md § Numerical-Python-Class](../taxonomy/PROJECT-CLASSES.md)) |
| **Tier** | **T3 — Workspace** with two complexity overlays |
| **Recommended mode** | `gauntlet-full` (first proper application) |
| **Reference pinning** | `docs/contracts/scipy_version_contract.toml` likely at `scipy-1.13.x`; preflight verifies `scipy.__version__`, `scipy.show_config()` for LAPACK/BLAS backend |
| **README claims summary** | Domain crates for `linalg / sparse / opt / integrate / fft / stats / signal / spatial`; CASP solver-selection-policy with declared tolerance per domain. Recent activity (commits `b198a2e1`, `ca739177`, `11ada231`) shows per-domain test-hardening — `tf2sos`, `constants.find`, `ndimage` order-3 reflect/nearest fix. |

---

## 2. Adoption Matrix

| Pillar / Discipline | Status | Notes |
|---|:---:|---|
| Conformance | ⚠️ "767 files" | per CODEX.md row; coverage broad but unstructured |
| Negative ledger | ❌ | absent |
| cass | ⚠️ partial | |
| Agent Mail | ⚠️ partial | |
| bv | ⚠️ partial | |
| Math layer (§75–76) | ⚠️ CASP only | CASP solver-selection wired; no e-process; no conformal; no BOCPD |
| MT-scale harness | ❌ | absent |
| RaptorQ | ❌ | not applicable |
| Per-solver portfolio bench | ❌ | not benchmarked at gauntlet level |
| Tolerance policy as contract (`scipy_tolerance_policy_v1.toml`) | ❌ | tolerances scattered across test files |
| Decision-fingerprint capture (CASP) | ⚠️ partial | logged but not differential |

---

## 3. Per-Pillar Deep Dive

### (a) Performance — current state + first 3 gaps

**Current state.** Per-solver benches exist informally. Condition-number × sparsity matrix not gridded.

**First 3 gaps:**
1. **No condition-number-bucketed bench matrix** — solver perf depends on cond(A) by orders of magnitude; current benches likely use one cond(A) sample per problem-class.
2. **No sparsity-pattern-bucketed bench matrix** — sparse vs dense decision threshold is one of the most consequential perf cliffs.
3. **No solver-selection-cost measured** — CASP policy chooses solver X over Y; the cost of *making* the choice is itself measurable and rarely measured.

### (b) Conformance — current state + first 3 gaps

**Current state.** 767 conformance files; CASP solver policy. Per-domain test files (`tf2sos`, `constants.find`, `ndimage`) show active per-feature coverage.

**First 3 gaps:**
1. **Solver-selection threshold drift** — at a specific condition number boundary, the port chooses a different solver than SciPy; output differs within tolerance but the *choice* is the divergence.
2. **Tolerance policy not in contract** — `scipy.linalg.solve(A, b, assume_a='gen')` uses a default tolerance; port may use a different default; passes most tests but fails ill-conditioned.
3. **Sparse format conversion silent recasts** — `scipy.sparse.csr_matrix` ↔ `csc_matrix` conversions may differ in tie-breaking for duplicate entries.

### (c) Surface — current state + first 3 gaps

**Current state.** Per-domain enumeration partial.

**First 3 gaps:**
1. **`scipy.signal` filter design surface** — `butter`, `cheby1`, `ellip`, `bessel`, `firwin`; per-method enumeration likely partial.
2. **`scipy.optimize` minimize methods** — 14+ methods (`Nelder-Mead`, `Powell`, `CG`, `BFGS`, `L-BFGS-B`, `TNC`, `COBYLA`, `SLSQP`, …) — per-method bench + correctness partial.
3. **`scipy.special` surface** — 500+ special functions; likely partial coverage with no formal `present|partial|missing|excluded`.

---

## 4. First-Pass Recipe

```bash
SKILL_ROOT="${GAUNTLET_SKILL_ROOT:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
[ -d "$SKILL_ROOT" ] || SKILL_ROOT="$HOME/.codex/skills/running-the-gauntlet-on-your-rust-port"

"$SKILL_ROOT/scripts/kickoff.sh" gauntlet-full
"$SKILL_ROOT/scripts/gauntlet.sh" /dp/frankenscipy /dp/frankenscipy__gauntlet_workspace \
  --mode gauntlet-full --dry-run

# Phase-specific inputs for the orchestrator/subagents:
# - reference pin: scipy-1.13.x
# - oracle mode: PyO3 in-process SciPy
# - perf weights: LinAlg=0.25, Sparse=0.15, Optimize=0.15, Integrate=0.10,
#   FFT=0.10, Stats=0.10, Signal=0.10, Spatial=0.05
# - primary metric: Condition-Aware Solver Portfolio routing accuracy
# - failure terms: solver selection threshold, tolerance weakening,
#   special function approximation, sparse format conversion, FFT normalization,
#   filter design corner, optimization convergence criterion

"$SKILL_ROOT/scripts/gauntlet.sh" /dp/frankenscipy /dp/frankenscipy__gauntlet_workspace \
  --mode gauntlet-full --soak-hours 72
```

Wall time T3 × `gauntlet-full`: **14–28 days.**

---

## 5. Expected Pillar Findings

### Performance
1. **`scipy.linalg.solve` uses LU even when Cholesky applies** — symmetric-positive-definite detection cost-amortized.
2. **Sparse-dense matmul fallback dispatches to wrong backend** — small sparse × large dense.
3. **`scipy.optimize.minimize` `method='BFGS'` line-search cost** dominant for small problems — should use `method='Newton-CG'`.
4. **FFT `n` not power-of-2** — Bluestein algorithm slower than Cooley-Tukey by 2-10×.
5. **`scipy.special.expit` (sigmoid) saturates at extremes** — branch-free implementation faster.
6. **`scipy.stats.norm.cdf` repeated allocations** — vectorize over batch.
7. **`scipy.integrate.solve_ivp` re-allocates Jacobian per step** — reuse opportunity.
8. **Sparse CSR/CSC conversion cost** quadratic in nnz for some patterns.

### Conformance
1. **`scipy.linalg.svd` sign convention** — non-unique; canonical-sign-of-first-element rule.
2. **`scipy.optimize.minimize` `Nelder-Mead` tie-breaking** — simplex vertex ordering.
3. **`scipy.sparse.linalg.eigsh` `which='LA'`** — convergence criterion under near-degeneracy.
4. **`scipy.signal.filtfilt` edge handling** — `padtype` defaults differ.
5. **`scipy.interpolate.interp1d` `kind='cubic'` boundary** — natural vs not-a-knot.
6. **`scipy.special.gamma(-0.5)`** — convention for negative half-integers.
7. **`scipy.stats.ttest_ind` `equal_var=True` vs Welch** — formula different.
8. **`scipy.fft.fft` normalization** — `'backward'` (default) vs `'forward'` vs `'ortho'`.
9. **`scipy.ndimage` order-3 spline boundary** — `'reflect'` vs `'nearest'` (recent fix per commit `11ada231`).
10. **`scipy.integrate.quad` tolerance interpretation** — `epsabs` vs `epsrel` combination.

### Surface
1. **`scipy.constants` complete enumeration** — partial likely.
2. **`scipy.spatial` (KDTree, ConvexHull, Voronoi)** — partial coverage.
3. **`scipy.io.matlab` (MATLAB file IO)** — typically excluded.

---

## 6. Patterns to Apply First

1. **Per-domain `comprehensive_bench`** with condition-number × sparsity grid axes.
2. **Tolerance policy as contract** — `docs/contracts/scipy_tolerance_policy_v1.toml` with per-solver default + exception rows.
3. **CASP decision-fingerprint differential** — when CASP picks solver X over Y, log `(inputs, score)`; build differential against live SciPy's choices.
4. **[pattern:40-METAMORPHIC-TRANSFORMS](../patterns/40-METAMORPHIC-TRANSFORMS.md)** — same problem solved by alternate solvers should agree within declared tolerance (Condition-Aware Solver Portfolio metamorphic relation).
5. **Per-domain golden artifacts** — linalg (one fixture set per condition number), sparse (one per sparsity pattern), optimization (one per problem class), integrate (one per stiffness class), distributions.

---

## 7. Estimated Rounds to Convergence

**10–16 rounds.** CASP solver story gives partial baseline; wide domain surface requires many rounds. Condition-number-bucketed sweeps surface findings deep in the loop.

---

## 8. Risk Register

1. **LAPACK/BLAS backend variance** across hosts — OpenBLAS vs MKL vs Apple Accelerate. *Mitigation:* pin in contract; rch worker verification.
2. **`scipy.special` special-function implementations** — Cephes vs SciPy's own — drift between versions. *Mitigation:* per-function golden at multiple input ranges.
3. **Convergence-criterion drift** in iterative solvers — `tol`, `maxiter` interactions can produce different *converged* outputs. *Mitigation:* test at multiple `(tol, maxiter)` settings.

---

## 9. What Ships from Convergence

`certification_bundle/`:
- Universal floor
- `solver_portfolio_compliance.json` — per-(domain, condition, sparsity) bucket pass rate
- `tolerance_policy_compliance.json` — per-op tolerance vs contract
- `casp_decision_fingerprint.json` — solver selection agreement vs SciPy
- `special_function_golden.json` — per-function input-range agreement

---

## Cross-references

- [SIBLING-PROJECTS-STATUS.md § FrankenSciPy](../exemplars/SIBLING-PROJECTS-STATUS.md)
- [PROJECT-CLASSES.md § Numerical-Python-Class](../taxonomy/PROJECT-CLASSES.md)
- [first-bug-hunt/numerical-python-class.md](../first-bug-hunt/numerical-python-class.md)
