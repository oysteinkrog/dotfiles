# Worked Example: Conformal Band (Vovk-Gammerman-Shafer 2005)

End-to-end worked example showing how `crates/fsqlite-harness/src/score_engine.rs` computes the distribution-free conformal band on a Beta-posterior per-category pass rate, and why **release decisions use the LOWER bound, not the point estimate**.

**The release decision under test:** "should we ship the port given that conformance evidence shows 974/1000 tests passing across 6 weighted categories?" Naive answer: 97.4% pass rate. Conformal answer: lower 95% bound on the score under distribution-free assumptions.

---

## 1. Setup

Six weighted categories (SQL-class weights):

| Category | Weight `w_c` | Pass | Partial | Missing | Excluded |
|---|---:|---:|---:|---:|---:|
| ReadSingle | `0.35` | 200 | 0 | 0 | 0 |
| ReadAggregate | `0.15` | 95 | 3 | 2 | 0 |
| WriteSingle | `0.30` | 198 | 0 | 2 | 0 |
| WriteBulk | `0.10` | 92 | 4 | 4 | 0 |
| ConcurrentWriters | `0.05` | 48 | 1 | 1 | 0 |
| MixedOltp | `0.05` | 49 | 0 | 1 | 0 |

Total: 1000 tests (200 + 100 + 200 + 100 + 50 + 50). 974 pure-pass + 8 partial + 18 missing + 0 excluded.

**Scoring rule:**
- Pass → success weight `1.0`
- Partial → `0.5` (half-credit)
- Missing → `0.0`
- Excluded → not counted

Per-category weighted successes / failures:

| Category | weighted_successes | weighted_failures | trials |
|---|---:|---:|---:|
| ReadSingle | 200 · 1 = 200 | 0 | 200 |
| ReadAggregate | 95 + 3·0.5 = 96.5 | 100 − 96.5 = 3.5 | 100 |
| WriteSingle | 198 | 2 | 200 |
| WriteBulk | 92 + 4·0.5 = 94 | 6 | 100 |
| ConcurrentWriters | 48 + 1·0.5 = 48.5 | 1.5 | 50 |
| MixedOltp | 49 | 1 | 50 |

---

## 2. Beta Posterior per Category

Prior `Beta(α=1, β=1)` (Jeffreys-like uniform). Posterior after `s` weighted successes + `f` weighted failures:

```
θ_c | data ~ Beta(α + s, β + f)
```

| Category | Posterior | Mean = α/(α+β) | 95% lower | 95% upper |
|---|---|---:|---:|---:|
| ReadSingle | `Beta(201, 1)` | 0.9950 | 0.9763 | 0.9999 |
| ReadAggregate | `Beta(97.5, 4.5)` | 0.9559 | 0.9026 | 0.9863 |
| WriteSingle | `Beta(199, 3)` | 0.9851 | 0.9626 | 0.9966 |
| WriteBulk | `Beta(95, 7)` | 0.9314 | 0.8657 | 0.9684 |
| ConcurrentWriters | `Beta(49.5, 2.5)` | 0.9519 | 0.8723 | 0.9897 |
| MixedOltp | `Beta(50, 2)` | 0.9615 | 0.8807 | 0.9929 |

(Quantiles via bisection on regularized incomplete beta; from `BetaParams::quantile` in `score_engine.rs`.)

Global posterior-mean score:
```
S_mean = 0.35·0.9950 + 0.15·0.9559 + 0.30·0.9851 + 0.10·0.9314 + 0.05·0.9519 + 0.05·0.9615
       = 0.34825 + 0.14339 + 0.29553 + 0.09314 + 0.04760 + 0.04808
       = 0.97598
```

Naive "point estimate" release: 0.976 → looks great.

---

## 3. The Distribution-Free Conformal Band

The Beta posterior assumes the *generative* model (Beta-Binomial) is correct — but in practice, the residuals from this model are not iid Beta-distributed under the actual test corpus. They may be:
- **Heavy-tailed** — a few categories with rare-event failures push the tail wider.
- **Bimodal** — some workloads pass at 99% or fail at 50%, no middle.
- **Regime-shifting** — pass rate drifts across the run (caught by BOCPD; see [math/bocpd-worked.md](bocpd-worked.md)).

**Conformal prediction** gives distribution-free finite-sample coverage: the true score lies within the band with probability ≥ 1−α regardless of the residual distribution. Cost: wider intervals. Benefit: honest.

### Algorithm (Vovk-Gammerman-Shafer 2005)

1. Hold out a **calibration set** of `n_cal = 200` tests across categories (proportionally sampled; deterministic seed from `corpus_entry_id`).
2. For each calibration test, compute the **non-conformity score** = `|observed_outcome - Beta_predicted_mean_for_category|`.
3. Sort calibration scores ascending: `R_1 ≤ R_2 ≤ ... ≤ R_{n_cal}`.
4. The **(1-α) quantile** of calibration residuals is `q = R_{⌈(1-α)(n_cal+1)⌉}` — for α=0.05 and n_cal=200, q = R_191.
5. The conformal band on the global score is `[S_mean - q · normalizer, S_mean + q · normalizer]`.

### Numerical instance

Suppose the calibration residuals look like:

| Percentile | Residual |
|---:|---:|
| 50% | 0.012 |
| 75% | 0.024 |
| 90% | 0.041 |
| 95% (R_191) | **0.058** |
| 99% | 0.092 |
| 100% | 0.144 |

Normalizer for weighted score (sum of category weights × per-category trial count, normalized): `1.0` (categories already weight-normalized).

Conformal band for `S_mean = 0.976`:
```
[0.976 - 0.058, 0.976 + 0.058] = [0.918, 1.000]  (clamped at 1.0)
```

Truncate to 6 decimal places per `truncate_score` (avoids x86/ARM/WASM LSB drift):
```
S_conformal_lower = 0.918000
S_conformal_upper = 1.000000
```

---

## 4. Why the LOWER bound is the release-decision target

The release certificate uses `CERTIFICATION_REQUIRED_SUITE_PASS_RATE_PCT = 100.0` per [methodology/CERTIFICATION.md](../methodology/CERTIFICATION.md). But "100%" of what?

- **Point estimate `S_mean = 0.976`**: the certifier rationalizes "97.6% is close to 100%; ship it." This is the **honesty failure mode**: under heavy-tailed residuals, the true pass rate could be 88%, and the certifier shipped.
- **Beta posterior 95% lower bound**: per category, e.g., `WriteBulk` lower = 0.866. Better than naive. But this is the *posterior* lower bound under the Beta-Binomial *model*. The model may be wrong.
- **Conformal 95% lower bound `S_conformal_lower = 0.918`**: distribution-free. Even if the residuals are heavy-tailed / bimodal / regime-shifting, the true score is ≥ 0.918 with 95% probability.

The ratchet rule (`⚖ Ratchet-Lower-Bound` operator):
- **Compute `S_conformal_lower` after every round.**
- **Release-eligible only if `S_conformal_lower >= persisted_high_water_mark - epsilon`** (typically `epsilon = 0.001`).
- **Persisted ratchet state in `certification_bundle/ratchet_state.json`**.

This makes the gauntlet's release decision **monotonically increasing in evidence quality** — a regression in any category lowers the conformal lower bound, blocking release; only by improving categories can the bound rise and unblock.

---

## 5. Behavior Under Heavy-Tailed / Bimodal / Regime-Shifting Workloads

### Heavy-tailed residuals

Suppose one category (ConcurrentWriters) has a long tail of rare-event failures: 5% of tests have residual > 0.2 (instead of the median 0.012).

| Percentile | Residual (heavy-tailed) |
|---:|---:|
| 50% | 0.012 |
| 90% | 0.045 |
| 95% (R_191) | **0.215** |
| 99% | 0.380 |

Conformal band: `[0.976 - 0.215, 0.976 + 0.215] = [0.761, 1.000]`.

The lower bound collapses to 0.761 — far below the persisted ratchet. The Beta-posterior approach would have given lower ≈ 0.866 (per-category × weights), masking the heavy tail.

**The conformal band correctly refuses to release** when the residual distribution has long tails the Beta model didn't capture.

### Bimodal residuals

Suppose the calibration residuals are bimodal: 80% are < 0.02, 20% are > 0.10. The empirical 95% quantile lands inside the upper mode at ≈ 0.13.

Conformal band lower = `0.976 - 0.13 = 0.846`.

The Beta-posterior approach would have estimated a unimodal pass rate per category and missed the bimodality. Conformal honestly reports the wider band.

### Regime-shifting residuals (between-round)

Round 1: residuals tight around 0.015 (q = 0.038).
Round 2: residuals widen to 0.040 median (q = 0.085).
Round 3: residuals back to 0.020 (q = 0.045).

Conformal lower bounds per round: 0.938, 0.891, 0.931.

**The ratchet would block release after Round 2** (since 0.891 < 0.938 by more than ε). Investigation reveals BOCPD detected a regime shift at obs 450 in Round 2 — a flaky test added without proper instrumentation. Round 3 confirms post-fix recovery; ratchet advances.

This composition of conformal lower-bound ratchet + BOCPD regime detection is the gauntlet's *honesty discipline* in numerical form.

---

## 6. Rust Snippet — Band Computation

```rust
use std::cmp::Ordering;

/// Truncate to 6 decimal places — defends against x86/ARM/WASM LSB drift.
pub fn truncate_score(x: f64) -> f64 {
    (x * 1e6).floor() / 1e6
}

pub struct ConformalBand {
    pub lower: f64,
    pub upper: f64,
    pub point_estimate: f64,
    pub quantile: f64,
    pub n_cal: usize,
}

impl ConformalBand {
    pub fn compute(
        point_estimate: f64,
        calibration_residuals: &mut [f64],
        alpha: f64,
    ) -> Self {
        // 1. Sort residuals ascending.
        calibration_residuals.sort_by(|a, b| a.partial_cmp(b).unwrap_or(Ordering::Equal));
        let n = calibration_residuals.len();

        // 2. (1-α) quantile: index ⌈(1-α)(n+1)⌉ - 1 (1-indexed in paper).
        let k = (((1.0 - alpha) * (n as f64 + 1.0)).ceil() as usize).saturating_sub(1);
        let k = k.min(n - 1);
        let q = calibration_residuals[k];

        // 3. Band.
        let lower = truncate_score((point_estimate - q).max(0.0));
        let upper = truncate_score((point_estimate + q).min(1.0));

        Self {
            lower,
            upper,
            point_estimate: truncate_score(point_estimate),
            quantile: q,
            n_cal: n,
        }
    }
}

/// Per-category Beta posterior.
pub struct BetaPosterior {
    pub alpha: f64,
    pub beta: f64,
}

impl BetaPosterior {
    pub fn from_data(weighted_successes: f64, weighted_failures: f64) -> Self {
        Self {
            alpha: 1.0 + weighted_successes,  // Jeffreys-like uniform prior
            beta: 1.0 + weighted_failures,
        }
    }

    pub fn mean(&self) -> f64 {
        self.alpha / (self.alpha + self.beta)
    }
}

/// Global score: weighted sum of category posterior means.
pub fn global_score(categories: &[(BetaPosterior, f64 /*weight*/)]) -> f64 {
    let total_weight: f64 = categories.iter().map(|(_, w)| w).sum();
    let weighted_sum: f64 = categories.iter().map(|(p, w)| p.mean() * w).sum();
    weighted_sum / total_weight
}

/// Ratchet: refuse release if conformal lower bound has dropped.
pub fn ratchet_check(
    current_lower: f64,
    persisted_high_water: f64,
    epsilon: f64,
) -> RatchetVerdict {
    if current_lower >= persisted_high_water - epsilon {
        RatchetVerdict::Pass { new_high_water: current_lower.max(persisted_high_water) }
    } else {
        RatchetVerdict::Block {
            current_lower,
            high_water: persisted_high_water,
            shortfall: persisted_high_water - current_lower,
        }
    }
}

pub enum RatchetVerdict {
    Pass { new_high_water: f64 },
    Block { current_lower: f64, high_water: f64, shortfall: f64 },
}
```

---

## 7. Failure Mode Catalog

Common ways the conformal band layer fails (mined from FrankenSQLite/FrankenNumPy ledgers):

1. **Calibration set drawn from same data as test set** — calibration must be a *held-out* split; otherwise coverage is anti-conservative. (Fix: deterministic split by `corpus_entry_id` mod 5; calibration = mod 0; test = mod 1..4.)
2. **`truncate_score` not applied** — release certificate hash differs between x86 and ARM CI workers; gates flap. (Fix: `truncate_score` at every f64-to-string boundary.)
3. **`epsilon = 0` in ratchet** — round-to-round f64 LSB noise blocks every release. (Fix: `epsilon = 0.001` empirically; `truncate_score(0.001) = 0.001000`.)
4. **Conformal band computed before `Excluded` items removed** — `Excluded` should not count as failure; if it does, band collapses on excluded-heavy categories. (Fix: scoring rule explicit; `Excluded` increments neither success nor failure.)
5. **n_cal too small** — quantile estimate noisy; ratchet flaps. (Fix: `n_cal ≥ 100` minimum; `n_cal ≥ 200` recommended; grow corpus before tightening band.)

---

## Cross-references

- `crates/fsqlite-harness/src/score_engine.rs` — production implementation
- [methodology/CONFORMAL-RATCHET.md](../methodology/CONFORMAL-RATCHET.md) — ratchet policy
- [methodology/CERTIFICATION.md](../methodology/CERTIFICATION.md) — required-pass constants
- [taxonomy/FEATURE-UNIVERSE.md](../taxonomy/FEATURE-UNIVERSE.md) — per-Feature weighting + `truncate_score`
- [patterns/75-BAYESIAN-CONFORMAL-SCORE.md](../patterns/75-BAYESIAN-CONFORMAL-SCORE.md) — pattern reference
- [math/e-process-worked.md](e-process-worked.md) — companion: invariant monitoring
- [math/bocpd-worked.md](bocpd-worked.md) — companion: regime detection
- Vovk-Gammerman-Shafer 2005 — "Algorithmic Learning in a Random World"
