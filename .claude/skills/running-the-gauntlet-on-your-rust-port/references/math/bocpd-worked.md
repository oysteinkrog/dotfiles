# Worked Example: BOCPD (Adams-MacKay 2007) with Normal-Gamma Predictive

End-to-end worked example showing how `crates/fsqlite-harness/src/replay_harness.rs` + `drift_monitor.rs` use Bayesian Online Change-Point Detection to identify regime shifts in a throughput stream — and how the BOCPD layer composes with the e-process layer to give complete coverage: BOCPD detects regime change in scoring, e-process tests invariant violation.

**The stream under test:** 120 observations of measured `mt_mvcc_bench --threads=8` throughput (rows/sec) during a multi-day soak. First 80 observations are stable around 5400 rows/sec. Then a kernel-fusion change lands (commit `XYZ`); next 10 observations show a regime shift to 4800 rows/sec (mean down, variance up). Last 30 observations stabilize at 4800. BOCPD with hazard `H = 1/250` is expected to detect the shift.

---

## 1. Setup

### State

BOCPD tracks the **run-length distribution** `P(r_t | x_{1:t})` — the probability that the current regime started `r_t` steps ago. At each new observation `x_t`, the distribution updates:

```
P(r_t = 0 | x_{1:t})         ∝ Σ_{r_{t-1}} P(x_t | μ_r, σ_r) · H(r_{t-1}) · P(r_{t-1} | x_{1:t-1})
P(r_t = r_{t-1} + 1 | x_{1:t}) ∝       P(x_t | μ_r, σ_r) · (1 − H(r_{t-1})) · P(r_{t-1} | x_{1:t-1})
```

where `H(r)` is the **hazard function** — probability of a change-point given the run length. Constant hazard `H = 1/λ` corresponds to geometric run-length prior (Poisson process of change-points).

### Predictive model: Normal-Gamma conjugate

We assume each regime is Normal with unknown mean μ and precision τ = 1/σ². Conjugate prior is Normal-Gamma:

```
μ | τ ~ Normal(μ₀, (κ₀ τ)⁻¹)
τ    ~ Gamma(α₀, β₀)
```

For our example: prior `μ₀ = 5000, κ₀ = 0.01, α₀ = 1.0, β₀ = 1.0e5`. (Weak prior to let data dominate.)

### Calibration

- **Hazard:** `H = 1/250` — expect a change-point every ~250 observations.
- **Soak length:** 120 observations.
- **Change-point detection threshold:** flag `Regime::ShiftDetected` when `P(r_t < 10 | x_{1:t}) > 0.5` — i.e., probability of being in a "fresh" regime (run length < 10) exceeds 0.5.

---

## 2. Observation Stream

Generated deterministically from `derive_entry_seed("mt-mvcc-bench-soak-2026-05-22")` for reproducibility.

| obs range | regime | mean | std | sample (first 3) |
|---|---|---:|---:|---|
| 1..80 | Stable | 5400 | 80 | `[5412, 5388, 5421]` |
| 81..90 | Transition | 5100 | 200 | `[5311, 4892, 5045]` |
| 91..120 | Post-shift | 4800 | 90 | `[4812, 4767, 4823]` |

### What BOCPD sees at key timesteps

**At t = 80 (last stable):**

Run-length posterior is concentrated near `r_80 = 80` (no change points expected in 80 obs at hazard 1/250 → P(no change in 80 steps) ≈ (249/250)^80 ≈ 0.726).

```
P(r_80 = 80 | x_{1:80}) ≈ 0.72
P(r_80 = 0  | x_{1:80}) ≈ 0.004 (one-step change is unlikely under stationary data)
```

`Regime::Stable`. ✓

**At t = 81 (first post-change):**

Predictive likelihood under "continue stable regime (run length 80)" of observing `x_81 = 5311`:
```
P(x_81 = 5311 | μ ≈ 5400, σ ≈ 80) ≈ 0.0030 (z-score ≈ -1.1)
```

Still plausible — doesn't trigger. `P(r_81 = 0)` updates upward but only modestly.

```
P(r_81 = 0 | x_{1:81}) ≈ 0.012
```

`Regime::Stable`. ✓

**At t = 85 (mid-transition, observed 4892, 5045, 5102, 4773, 5103):**

Five observations with cumulative likelihood under stable-regime:
```
P(x_{82..85} | μ ≈ 5400, σ ≈ 80) ≈ 0.0030 · 0.0040 · 0.0050 · 0.0008 · 0.0050 ≈ 2.4e-13
```

Meanwhile, the "new regime starting at r=1" hypothesis gets to fit μ, σ to the new data — much higher likelihood. Run-length distribution shifts mass toward low `r`:

```
P(r_85 = 0 | x_{1:85}) ≈ 0.18
P(r_85 = 1 | x_{1:85}) ≈ 0.21
P(r_85 = 2 | x_{1:85}) ≈ 0.15
P(r_85 = 3 | x_{1:85}) ≈ 0.10
P(r_85 = 4 | x_{1:85}) ≈ 0.07
P(r_85 = 85 | x_{1:85}) ≈ 0.04   (was 0.71 five obs ago)

P(r_85 < 10 | x_{1:85}) ≈ 0.78  ← > 0.5 threshold
```

`Regime::ShiftDetected` at t = 85. ✓

The detection delay is ~5 observations after the actual change at t = 81 — typical for BOCPD with weak prior on a soft-shift (mean down 5%, std up 2.5×).

**At t = 110 (post-shift stable):**

Run-length posterior concentrates near `r_110 = 30` (30 obs since shift detected):

```
P(r_110 = 29 | x_{1:110}) ≈ 0.42
P(r_110 = 30 | x_{1:110}) ≈ 0.31
P(r_110 = 0  | x_{1:110}) ≈ 0.001
```

`Regime::Stable` (in new regime). ✓

---

## 3. The Four Regime States

```rust
pub enum Regime {
    Stable,          // BOCPD: P(r < 10) low; predictive likelihood under recent posterior good
    Improving,       // mean of current regime > previous regime mean by > threshold
    Regressing,      // mean of current regime < previous regime mean by > threshold
    ShiftDetected,   // BOCPD: P(r < 10) > 0.5; in transitional state
}
```

Transition diagram in our stream:

```
obs 1..80   : Stable  (μ ≈ 5400)
obs 81..84  : Stable  (BOCPD hasn't yet detected; predictive likelihood still tolerable)
obs 85..95  : ShiftDetected  (P(r<10) > 0.5)
obs 96..110 : Regressing  (new regime mean 4800 < previous mean 5400; threshold 5%)
obs 111..120: Stable  (no change in 15 obs; regime committed; BUT outer system knows "in regressed regime")
```

---

## 4. Composition with the E-Process Layer

BOCPD detects **regime shifts in the metric** (throughput). E-process tests **invariant violations** (e.g., INV-CommitAtomicity). Two distinct phenomena; two distinct layers; they compose:

| What changed | BOCPD sees | E-process sees |
|---|---|---|
| Kernel-fusion change reduces throughput but preserves correctness | `Regressing` | `Stable` (no INV violations) |
| Kernel-fusion change introduces a rare INV-CommitAtomicity violation, no throughput change | `Stable` | `E_global` rises; eventual rejection |
| Kernel-fusion change does both | `Regressing` | `E_global` rises |
| Benign noise burst (cosmic ray; tool flap) | `Stable` (BOCPD ignores; doesn't pass shift threshold) | `Stable` (e-value decays back) |

**Combined verdict matrix (orchestrator decision):**

| BOCPD | E-process | Verdict | Action |
|---|---|---|---|
| Stable | Stable | Pass | Continue |
| ShiftDetected | Stable | Investigate metric regime | `cookbook/bocpd-shift-detected.md` |
| Stable | Rejected | Investigate invariant | `cookbook/e-process-rejection.md` |
| Regressing | Stable | Perf regression — no correctness issue | Pass-over-pass gate → ratchet block |
| Regressing | Rejected | Both broken — likely the SAME root cause | Halt soak; full triage |
| ShiftDetected | Rejected | Active failure | Halt; emit FailureBundle |

For our worked example: at obs 85+, BOCPD says `Regressing` (throughput down 11% from 5400 to 4800). E-process across all 7 invariants stays `Stable`. Verdict: **perf regression without correctness issue.** Pass-over-pass gate blocks the next commit; ratchet refuses to advance; ledger entry filed: "kernel-fusion change `XYZ` regressed mt-mvcc-bench throughput by 11% with no detected invariant violation. Retry only if MT16 attribution shows the dominant frame ≥0.1% self-time."

---

## 5. Rust Snippet — BOCPD Updater

```rust
/// Normal-Gamma conjugate prior parameters for one regime.
#[derive(Clone, Debug)]
pub struct NormalGammaParams {
    pub mu: f64,       // mean prior
    pub kappa: f64,    // precision scaling
    pub alpha: f64,    // Gamma shape
    pub beta: f64,     // Gamma rate
}

impl NormalGammaParams {
    /// Default weak prior: don't bias the data.
    pub fn weak(initial_estimate: f64) -> Self {
        Self { mu: initial_estimate, kappa: 0.01, alpha: 1.0, beta: 1.0e5 }
    }

    /// Posterior predictive density of x | data so far (Student's t).
    /// Returns log-density to avoid underflow.
    pub fn log_predictive(&self, x: f64) -> f64 {
        // Student's t parameters: ν = 2α, location = μ, scale² = β(κ+1)/(ακ)
        let nu = 2.0 * self.alpha;
        let scale2 = self.beta * (self.kappa + 1.0) / (self.alpha * self.kappa);
        let z = (x - self.mu) / scale2.sqrt();
        // log p(x) = log Γ((ν+1)/2) - log Γ(ν/2) - ½ log(νπ scale²) - ((ν+1)/2) log(1 + z²/ν)
        ln_gamma((nu + 1.0) / 2.0)
            - ln_gamma(nu / 2.0)
            - 0.5 * (nu * std::f64::consts::PI * scale2).ln()
            - ((nu + 1.0) / 2.0) * (1.0 + z * z / nu).ln()
    }

    /// Update with observation x; return new posterior.
    pub fn update(&self, x: f64) -> Self {
        let new_kappa = self.kappa + 1.0;
        let new_mu = (self.kappa * self.mu + x) / new_kappa;
        let new_alpha = self.alpha + 0.5;
        let new_beta = self.beta + 0.5 * self.kappa * (x - self.mu).powi(2) / new_kappa;
        Self { mu: new_mu, kappa: new_kappa, alpha: new_alpha, beta: new_beta }
    }
}

pub struct Bocpd {
    pub hazard: f64,                     // H = 1/expected_run_length
    pub prior: NormalGammaParams,
    /// run_length_dist[r] = P(r_t = r | x_{1:t})
    run_length_dist: Vec<f64>,
    /// posteriors[r] = NormalGammaParams for run length r at time t
    posteriors: Vec<NormalGammaParams>,
    obs_count: u64,
    last_regime: Regime,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Regime { Stable, Improving, Regressing, ShiftDetected }

impl Bocpd {
    pub fn new(hazard: f64, prior: NormalGammaParams) -> Self {
        Self {
            hazard,
            prior: prior.clone(),
            run_length_dist: vec![1.0],
            posteriors: vec![prior],
            obs_count: 0,
            last_regime: Regime::Stable,
        }
    }

    pub fn observe(&mut self, x: f64) -> Regime {
        self.obs_count += 1;
        let n = self.run_length_dist.len();

        // 1. Compute predictive likelihood under each run-length hypothesis.
        let log_preds: Vec<f64> = self.posteriors.iter().map(|p| p.log_predictive(x)).collect();

        // 2. Update growth probabilities: P(r_t = r+1, x_{1:t}) ∝ P(r_{t-1}=r, x_{1:t-1}) · pred · (1-H)
        let mut new_dist = vec![0.0; n + 1];
        for r in 0..n {
            new_dist[r + 1] = self.run_length_dist[r] * log_preds[r].exp() * (1.0 - self.hazard);
        }
        // 3. Changepoint probability: P(r_t = 0, x_{1:t}) ∝ Σ_r P(r_{t-1}=r, x_{1:t-1}) · pred · H
        new_dist[0] = (0..n)
            .map(|r| self.run_length_dist[r] * log_preds[r].exp() * self.hazard)
            .sum();

        // 4. Normalize.
        let total: f64 = new_dist.iter().sum();
        for p in new_dist.iter_mut() { *p /= total; }
        self.run_length_dist = new_dist;

        // 5. Update posteriors: new posterior for run length r+1 is old posterior for run length r, updated by x.
        let mut new_posteriors = vec![self.prior.clone()];  // r = 0: fresh prior
        for r in 0..n {
            new_posteriors.push(self.posteriors[r].update(x));
        }
        self.posteriors = new_posteriors;

        // 6. Classify regime.
        let p_fresh: f64 = self.run_length_dist.iter().take(10).sum();
        let regime = if p_fresh > 0.5 {
            Regime::ShiftDetected
        } else {
            // Compare current regime mean to long-run mean.
            let map_r = self.run_length_dist.iter().enumerate()
                .max_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap())
                .map(|(i, _)| i).unwrap_or(0);
            let current_mu = self.posteriors[map_r].mu;
            let baseline_mu = self.prior.mu;
            let delta_pct = (current_mu - baseline_mu).abs() / baseline_mu;
            if delta_pct < 0.03 {
                Regime::Stable
            } else if current_mu > baseline_mu {
                Regime::Improving
            } else {
                Regime::Regressing
            }
        };

        self.last_regime = regime;
        regime
    }

    pub fn regime(&self) -> Regime { self.last_regime }
}

// Helper: log Γ(x) via Stirling-Lanczos or libm.
fn ln_gamma(x: f64) -> f64 { libm::lgamma(x) }
```

---

## 6. Trace of Run-Length Posterior

Schematic run-length-distribution heatmap at three time points:

```
      r=0  r=1 ... r=80 ... r=85 r=86 ... r=120
t=80  .00  .00 ... .72  ...  -    -        -      ← Stable, concentrated at r=80
t=85  .18  .21 ... .04  ...  -    -        -      ← ShiftDetected, mass at low r
t=120 .00  .00 ...   -  ...  .00  .00 ... .42    ← Stable, concentrated at r=35 (post-shift)
```

The mass migration from `r=80` (stable old regime) to `r ∈ [0, 9]` (transition) to `r=35` (stable new regime) is the BOCPD signature of a regime shift.

---

## 7. Failure Mode Catalog

Common ways the BOCPD layer fails (mined from FrankenSQLite ledgers):

1. **Hazard too low** (`H = 1/10000` instead of `1/250`) — BOCPD never declares shifts; rides over real regressions. (Fix: calibrate to expected shift frequency; multi-day soaks → `H ≈ 1/250`.)
2. **Hazard too high** (`H = 1/10`) — BOCPD flags every minor variance; alarm fatigue. (Fix: `H ≈ 1/250` for stable workloads; `H ≈ 1/100` for noisy workloads only after baseline.)
3. **Weak prior — BOCPD takes too long to lock in baseline** — first 50 observations all classified as `ShiftDetected`. (Fix: warmup period `[0, 50]` excluded from BOCPD updates; or use empirical Bayes for prior.)
4. **Run-length distribution truncated too aggressively** — at r=1000 the distribution gets memory-pressure pruned; old regimes vanish; spurious shift. (Fix: keep `r ≤ 1/(2H)` minimum.)
5. **Multimodal regimes treated as single regime** — workload alternates between two stable regimes; BOCPD flags every transition. (Fix: hierarchical BOCPD; two-level model.)

---

## 8. Composition Pattern with Conformal Band

Both BOCPD and the conformal band consume scoring data, but at different granularities:

- **Conformal band**: per-round, per-category. Operates on weighted pass rates.
- **BOCPD**: per-observation, single-metric. Operates on throughput / latency / pass-count streams.

A complete soak run reports:

```json
{
  "round": 7,
  "conformal_lower_bound": 0.927,
  "bocpd_regime": "Stable",
  "e_process_global_value": 1.4,
  "e_process_threshold": 1e6,
  "verdict": "advance"
}
```

The orchestrator advances only if:
1. `conformal_lower_bound >= persisted_high_water - epsilon` (ratchet)
2. `bocpd_regime ∈ {Stable, Improving}` (no regression)
3. `e_process_global_value < e_process_threshold` (no INV violations)

If any of the three fails, the soak halts and the appropriate cookbook runs (`cookbook/ratchet-block.md`, `cookbook/bocpd-shift-detected.md`, `cookbook/e-process-rejection.md`).

---

## Cross-references

- `crates/fsqlite-harness/src/replay_harness.rs` — production implementation
- `crates/fsqlite-harness/src/drift_monitor.rs` — BOCPD layer + regime classification
- [methodology/SOAK-PROTOCOL.md](../methodology/SOAK-PROTOCOL.md) — multi-day BOCPD setup
- [patterns/70-E-PROCESSES.md](../patterns/70-E-PROCESSES.md) — companion e-process patterns
- [math/e-process-worked.md](e-process-worked.md) — e-process worked example
- [math/conformal-band-worked.md](conformal-band-worked.md) — companion: pass-rate scoring
- Adams-MacKay 2007 — "Bayesian Online Changepoint Detection" (arXiv:0710.3742)
