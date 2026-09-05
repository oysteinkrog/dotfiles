# CONFORMAL-RATCHET — Bayesian + Conformal Scoring Math

This file is the math layer of the gauntlet. It documents how a per-category Beta posterior gets a distribution-free conformal band wrapped around it, why release decisions use the lower bound instead of the point estimate, why `truncate_score` is required for cross-platform determinism, and what the ratchet state machine does with the resulting number. See [KERNEL.md § K-5 + K-6](KERNEL.md) for the axioms and [../../SKILL.md § Three Pillars § Conformance](../../SKILL.md) for where this lives in the loop. The implementation reference is `crates/fsqlite-harness/src/score_engine.rs` per MINING-2 §11.

---

## (a) The Beta posterior per category × pass rate

The unit of analysis is one (category, test) pair. Each test outcome is:

| Outcome | Numeric value | Weighted contribution |
|---|---|---|
| Passing | 1.0 | `1.0 × feature_weight` |
| Partial | 0.5 | `0.5 × feature_weight` |
| Missing | 0.0 | `0.0 × feature_weight` |
| Excluded | (skipped; counts toward debt) | `feature_weight × 0.0` toward success, but full weight stays in the denominator for strict-100% claims — see (e) |

Per-category pass rate is modeled with a Beta posterior:

```
theta_c ~ Beta( alpha_prior + Σ weighted_successes,
                 beta_prior  + Σ weighted_failures )
```

Where successes and failures are weighted by `feature_weight` (see [../taxonomy/FEATURE-UNIVERSE.md](../taxonomy/FEATURE-UNIVERSE.md) for the per-feature weight assignment + loader-enforced `sum(weights) == 1.0` invariant).

The global parity score is:
```
S_t = Σ_c category_weight_c × E[theta_c]      (point estimate)
S_t^lower = Σ_c category_weight_c × Q_{theta_c}(α/2)   (conformal-lower)
```

The structures (`BetaParams`, `mean()`, `variance()`, `quantile()`, `credible_interval()`) are in MINING-2 §11. The variance formula is the standard Beta:
```
Var[theta] = alpha × beta / ((alpha + beta)^2 × (alpha + beta + 1))
```

**Prior choice (FrankenSQLite default):** `alpha_prior = beta_prior = 1.0` (uniform Jeffreys-style). Project-specific priors that reflect the reference engine's expected behavior are allowed but must be declared in `docs/contracts/<project>_score_contract.toml` and held constant across the ratchet's lifetime.

---

## (b) Distribution-free conformal band

> "Distribution-free finite-sample coverage. Calibrated from per-category residuals (frequentist vs Bayesian gap). `P(R_{n+1} ≤ q) ≥ 1 − α` for any distribution. Cost: wider intervals. Benefit: honest under heavy-tailed / bimodal / regime-shifting distributions." — MINING-2 §11

**Reference:** Vovk-Gammerman-Shafer 2005, *Algorithmic Learning in a Random World*. The conformal prediction framework gives finite-sample coverage guarantees **without** distributional assumptions on the underlying score stream.

### Why this matters for the gauntlet

The Beta posterior alone assumes the test outcomes are exchangeable Bernoulli-like draws. Real workload distributions are not:

| Workload property | Why Bayesian alone fails |
|---|---|
| **Heavy-tailed** | A few extreme failures dominate; Beta posterior under-weights tail. Conformal coverage holds regardless. |
| **Bimodal** | Test results cluster around two modes (passes and a specific failure class). Beta mean is between modes, where no probability mass lies. Conformal preserves both tails. |
| **Regime-shifting** | Workload distribution changes mid-run (a checkpoint, a code change, a new fixture). Beta posterior with old data is biased. Conformal's exchangeability requirement degrades gracefully; coupled with [SOAK-PROTOCOL.md § BOCPD](SOAK-PROTOCOL.md), regime shifts get caught explicitly. |

### Calibration recipe

1. Hold out a calibration set of test outcomes (typically 20% of the corpus).
2. Compute the Beta-posterior point estimate on the training 80%.
3. Compute per-category residuals: `R_i = |observed_pass_rate_i − E[theta_c]|` for each calibration test `i`.
4. The `(1 − α)`-quantile of `{R_i}` is the conformal half-width.
5. The conformal band is `[E[theta_c] − conformal_halfwidth, E[theta_c] + conformal_halfwidth]`.

The cost is wider intervals — conformal bands are strictly no narrower than the Beta credible interval for the same coverage level. The benefit is the band's coverage guarantee survives any distributional pathology.

---

## (c) Lower-bound vs point-estimate for release decisions

> "Lower confidence bound for release decisions." — MINING-2 §11

**The rule:** release decisions use the LOWER bound of the conformal band, not the point estimate.

Justification:

1. **Asymmetric cost.** Shipping a release that's worse than advertised is much more expensive than shipping one that's better than advertised. The lower bound is the conservative side of the band.
2. **Adversarial reading.** A reviewer hostile to the claim asks: "Is the lower bound also above the ratchet?" If yes, the claim survives the hostile reading.
3. **Calibration honesty.** The point estimate is a function of the priors and the sampled data; the lower bound is a function of those plus the conformal coverage guarantee. The lower bound is doing strictly more work to justify itself.
4. **Ratchet monotonicity.** The ratchet only ever moves up. Using the point estimate would let noise occasionally bump it past where it deserves; using the lower bound ensures every ratchet advance is supported by actual evidence at the chosen coverage level.

**Intermediate dashboards may show the point estimate** (it's useful for "are we trending up?"). The release decision uses the lower bound. The certification bundle's `parity_score` field is the lower bound — see [CERTIFICATION.md](CERTIFICATION.md).

---

## (d) `truncate_score` to 6 decimal places — cross-platform determinism

```rust
pub fn truncate_score(x: f64) -> f64 { /* truncate to 6 decimal places */ }
```

**The problem:** x86, ARM, and WASM differ at the LSB of IEEE 754 double. Identical computations yield different `f64` values across architectures; the differences propagate through Beta posterior arithmetic, conformal quantile bisection, and final score aggregation. Two builds that should produce *the same score* produce scores that differ at the 15th decimal place — and the ratchet, which compares scores bytewise, flickers.

**The fix:** truncate (not round) every score to 6 decimal places at the boundary where it enters a comparison, a ratchet update, or a written artifact. 6 places is comfortably above the noise floor of any real workload (cv_pct 3–5% ≫ 1e-6) and comfortably above the cross-arch LSB drift.

**Truncate, not round:** truncation is associative across the ULP; rounding mode (banker's vs nearest-up) is itself a cross-platform variable. `truncate_score` is the most stable choice.

**Where it must be called:**
- Final `parity_score` before writing `scorecards.json`.
- Per-category bounds before writing `ratchet_state.json`.
- Anywhere two architectures will diff the same field byte-by-byte.

**Where it should NOT be called:**
- Intermediate computations (truncation compounds; only the leaf-of-output truncates).
- Posterior parameter `alpha`/`beta` values (these are sufficient statistics; truncation would lose information).

---

## (e) Ratchet state machine

`reports/ratchet_state.json` is the persisted high-water mark. Schema:

```jsonc
{
  "schema_version": "ratchet_state.v1",
  "current_lower_bound": 0.847291,           // truncate_score'd
  "per_category_bounds": {
    "ReadSingle":        0.892341,
    "ReadAggregate":     0.798123,
    "WriteSingle":       0.901234,
    "WriteBulk":         0.812345,
    "ConcurrentWriters": 0.731234,
    "MixedOltp":         0.842341
  },
  "commit_sha":     "1a2b3c4d5e6f...",
  "timestamp":      "2026-05-22T14:23:11Z",
  "previous_bound": 0.842172,                // before this advance
  "advance_reason": "Phase 12 remediation bd-abc.7 closed 3 metamorphic divergences"
}
```

### `apply-ratchet.sh` decision matrix

```
Inputs:  current_parity_lower_bound (this run, truncate_score'd)
         per_category_lower_bounds  (this run, truncate_score'd)
         ratchet_state.json         (persisted)
         waivers/*.toml             (any active waivers)

Outputs: one of {Allow, Block, Quarantine, Waiver}
         and a write to ratchet_state.json if Allow
```

| Decision | Condition | Effect |
|---|---|---|
| **Allow** | `current_lower_bound ≥ ratchet.current_lower_bound` AND `per_category_lower_bound[c] ≥ ratchet.per_category_bounds[c]` for every c | Update `ratchet_state.json` with new bounds + commit_sha + timestamp + advance_reason. |
| **Block** | Any bound (global or per-category) is below ratchet AND no active waiver covers the regression | Exit non-zero; CI fails; PR cannot merge. |
| **Quarantine** | Global bound holds but exactly one per-category bound dipped by ≤ category-quarantine-threshold (default: 0.005 lower-bound delta) | Exit non-zero; block merge until the operator either resolves the dip or records an explicit waiver. Write a `quarantine_<category>.md` requiring resolution within 7 days. |
| **Waiver** | An active `waivers/<id>.toml` covers the specific regression (category, magnitude, expiry) | Allow with auditable trace; waiver enters expiration window. |

### `ratchet_state.json` invariants
- `current_lower_bound` is monotone non-decreasing across `Allow` updates.
- `per_category_bounds[c]` is monotone non-decreasing across `Allow` updates (except under explicit `Waiver`).
- `commit_sha` advances to the SHA that justifies the advance.
- `previous_bound` is preserved for one ratchet generation for audit.

---

## (f) Legitimate downgrade — the structured waiver process

Sometimes a real regression is the right answer: a security fix that costs perf, a correctness fix that slows a fast path, a deprecation that removes a feature whose weight was non-zero. The ratchet must support legitimate downgrades without losing its discipline.

### Waiver schema (`waivers/<id>.toml`)

```toml
schema_version = "waiver.v1"
id             = "WV-2026-005"
created_at     = "2026-05-22T09:00:00Z"
expires_at     = "2026-08-22T00:00:00Z"          # 90-day max default
created_by     = "release-architect@example.com"
approved_by    = ["safety-lead@example.com", "perf-lead@example.com"]   # ≥2 approvers
applies_to_category   = "WriteSingle"
applies_to_bound_kind = "per_category_lower"     # or "global_lower"
old_bound      = 0.901234
new_bound      = 0.873500                         # the downgrade
delta          = -0.027734
justification  = """
SSI false-positive correctness fix for issue #1247.
The fix re-introduces a CAS in the commit fastpath that this
ratchet entry had previously discounted; the perf cost is
~3% on WriteSingle and the correctness gain is the elimination
of the read-only-anomaly-amplification regression discovered
during BOCPD soak on 2026-05-18.
"""
evidence = [
  "artifacts/bd-ssi-fix.12/proof_pack/baseline_profile.flame.svg",
  "artifacts/bd-ssi-fix.12/correctness.txt",
  "docs/incidents/2026-05-18-ssi-amplification.md",
]
```

### Required for every waiver
1. **≥2 approvers** in distinct roles (security lead + perf lead, or safety + release-architect).
2. **Justification** in prose with named incident or bead-id.
3. **Evidence** as artifact paths (not narrative claims).
4. **Expiration** ≤ 90 days by default; renewal requires re-approval.
5. **Specific scope** — category + bound kind + new bound value. No blanket waivers.

### Waiver expiration behavior
On `expires_at`, `apply-ratchet.sh` reverts to demanding the old bound. If the new world has not closed the regression, the next run blocks. This forces either a real fix or an explicit waiver renewal — never quiet drift.

### What a waiver does NOT do
- It does not modify `ratchet_state.json` permanently. The persisted bound is still the high-water mark; the waiver carves out a temporary exception.
- It does not silence the bound from dashboards. The waiver is visible in every report; the artifact reads "[WAIVED-WV-2026-005]".
- It does not relieve the per-category proof obligation. The category still needs its proof artifacts; the waiver concerns the bound, not the evidence.

---

## Cross-links

- This file implements [KERNEL.md § K-5](KERNEL.md) (`truncate_score`) and [K-6](KERNEL.md) (Bayesian + Conformal + E-process composition).
- Calibration windows that the ratchet may invalidate are detected by [SOAK-PROTOCOL.md § BOCPD](SOAK-PROTOCOL.md).
- The ratchet bounds appear in the certification bundle as `parity_score` and `per_category_bounds` in [CERTIFICATION.md](CERTIFICATION.md).
- Per-category weights and the `sum == 1.0` loader invariant are in [../taxonomy/FEATURE-UNIVERSE.md](../taxonomy/FEATURE-UNIVERSE.md).
- The score engine implementation reference is `crates/fsqlite-harness/src/score_engine.rs` per MINING-2 §11.
- E-processes (the third layer that complements Bayesian + Conformal) are documented under [../tooling/ORACLE-TOOLCHAIN.md § E-Process](../tooling/ORACLE-TOOLCHAIN.md) and underlie the MVCC invariant monitoring; the math is in MINING-2 §10 (Howard-Ramdas-McAuliffe-Sekhon 2021).
- The operator that applies this layer is [OPERATORS.md § ⚖ Ratchet-Lower-Bound](OPERATORS.md) and [§ 📐 Conformal-Band](OPERATORS.md).
