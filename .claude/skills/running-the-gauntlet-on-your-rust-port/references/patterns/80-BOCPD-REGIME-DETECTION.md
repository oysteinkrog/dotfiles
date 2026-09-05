# Pattern 80 — BOCPD REGIME DETECTION (`Regime::{Stable, Improving, Regressing, ShiftDetected}`)

## What

Bayesian Online Change-Point Detection (Adams-MacKay 2007) applied to the live parity-score / throughput / abort-rate stream. Maintains a posterior over "run length" since the last change point; when the posterior mass shifts to short run lengths, a regime change is declared. Two predictive models: Normal-Gamma conjugate posterior for continuous streams (throughput, contention); Beta-Binomial conjugate posterior for binary streams (abort rates, per-category pass rates). Hazard rate `H = 1/250` (i.e., expected segment length = 250 observations). Minimum 100 observations before any terminal regime declaration. Produces one of four `Regime` labels per window — `Stable` is the only release-eligible terminal label.

## Why

E-processes detect that *something* violated an invariant. BOCPD detects that the *whole distribution* shifted — a different population, not a worse population. Without BOCPD, a refactor that legitimately improves throughput from 100k to 120k looks identical to a regression that drops it from 100k to 80k (both are "change"). BOCPD says "improvement detected" vs "regression detected" vs "shift to a new regime we don't recognize".

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/replay_harness.rs` (bead `bd-1dp9.2.4`) — `Regime` + `ReplayHarnessResult` (MINING-2 §7)
- `crates/fsqlite-harness/src/drift_monitor.rs` (bead `bd-1dp9.8.2`) — BOCPD layer integration

## Verbatim shape — the `Regime` enum + result struct

From MINING-2 §7, verbatim:

```rust
pub enum Regime {
    Stable,           // no statistical change
    Improving,        // better than baseline
    Regressing,       // worse than baseline
    ShiftDetected,    // BOCPD detected regime shift mid-run
}

pub struct ReplayHarnessResult {
    pub regime: Regime,
    pub throughput_posterior: BetaParams,        // Normal-Gamma
    pub abort_rate_posterior: BetaParams,        // Beta-Binomial
    pub window_regimes: Vec<Regime>,
}
```

### Calibration (verbatim MINING-2 §7)

> "**Calibration:** H = 1/250 (hazard rate). Normal-Gamma for throughput/contention. Beta-Binomial for abort rates."

## Adams-MacKay 2007 BOCPD — the algorithm

Maintain `P(r_t | x_{1:t})` where `r_t` is the run length since the last change point.

```rust
// Hazard function: probability of change point at any step.
fn hazard(r: usize) -> f64 { 1.0 / 250.0 }   // H = 1/250

// Predictive probability under each run-length hypothesis.
fn predictive_prob(model: &PredictiveModel, r: usize, x: f64) -> f64 {
    model.posterior_predictive(r, x)         // Normal-Gamma or Beta-Binomial
}

pub struct BocpdState {
    pub run_length_posterior: Vec<f64>,      // P(r_t | x_{1:t}), len = t+1
    pub predictive_models: Vec<PredictiveModel>, // one model per r_t
}

impl BocpdState {
    pub fn update(&mut self, x: f64) {
        let t = self.run_length_posterior.len();
        let mut new_posterior = vec![0.0; t + 1];

        // Growth probabilities (r_t = r_{t-1} + 1)
        for r in 0..t {
            let pi = predictive_prob(&self.predictive_models[r], r, x);
            new_posterior[r + 1] = self.run_length_posterior[r] * pi * (1.0 - hazard(r));
        }

        // Change-point probability (r_t = 0)
        let mut cp = 0.0;
        for r in 0..t {
            let pi = predictive_prob(&self.predictive_models[r], r, x);
            cp += self.run_length_posterior[r] * pi * hazard(r);
        }
        new_posterior[0] = cp;

        // Normalize
        let z: f64 = new_posterior.iter().sum();
        for p in &mut new_posterior { *p /= z; }
        self.run_length_posterior = new_posterior;

        // Update predictive models
        for model in &mut self.predictive_models { model.update_sufficient_stats(x); }
        self.predictive_models.push(PredictiveModel::default());
    }

    pub fn map_run_length(&self) -> usize {
        self.run_length_posterior.iter().enumerate()
            .max_by(|a, b| a.1.partial_cmp(b.1).unwrap()).unwrap().0
    }
}
```

### Predictive models

**Normal-Gamma (continuous streams)** — throughput, contention:

```rust
pub struct NormalGammaPosterior {
    pub mu: f64, pub kappa: f64, pub alpha: f64, pub beta: f64,
}
// Posterior predictive is Student-t. Update via standard conjugate formulas.
```

**Beta-Binomial (binary / proportion streams)** — abort rates, per-category pass rates:

```rust
pub struct BetaBinomialPosterior {
    pub alpha: f64, pub beta: f64,
}
// Posterior predictive is Beta-Binomial. Update: alpha += x; beta += 1 - x.
```

## Regime classification from BOCPD state

```rust
pub fn classify(state: &BocpdState, baseline_mean: f64, observed_mean: f64, n_obs: usize) -> Regime {
    if n_obs < 100 { return Regime::Stable; }    // min observations
    let map_r = state.map_run_length();
    let posterior_at_zero = state.run_length_posterior[0];

    // Strong evidence of change point: posterior mass at r_t = 0 > threshold.
    if posterior_at_zero > 0.5 { return Regime::ShiftDetected; }

    // Otherwise, compare observed vs baseline within the current segment.
    let delta = observed_mean - baseline_mean;
    let std_err = compute_segment_stderr(state, map_r);
    if delta > 2.0 * std_err { Regime::Improving }
    else if delta < -2.0 * std_err { Regime::Regressing }
    else { Regime::Stable }
}
```

### Release rule

- `Stable` — release allowed (assuming the conformal-lower-bound ratchet from [pattern:75-BAYESIAN-CONFORMAL-SCORE](75-BAYESIAN-CONFORMAL-SCORE.md) also passes)
- `Improving` — release allowed, but reset baseline to the new segment's mean (so future "regressions" are measured against the improved baseline)
- `Regressing` — release blocked; root-cause investigation required
- `ShiftDetected` — release blocked; the distribution itself changed (e.g., workload changed shape); review needed before re-baselining

## Per-class instantiation

| Class | Stream observed | Predictive model | Baseline source |
|---|---|---|---|
| **SQL** | `mt-mvcc-bench` throughput; SSI false-positive rate; per-category pass rate | Normal-Gamma for throughput; Beta-Binomial for rates | `.bench-history/mt-mvcc-bench.latest.json` median over last 30 commits |
| **RESP** | RPS p99 latency; AOF flush time; per-command success rate | Normal-Gamma for latency; Beta-Binomial for success rate | `.bench-history/comprehensive_bench.latest.json` |
| **ML** | Operator throughput (ops/sec); gradcheck max rel error; per-op-family pass rate | Normal-Gamma for throughput + error; Beta-Binomial for pass rate | `.bench-history/torch-ops-bench.latest.json` |
| **Numerical** | Ufunc throughput; PCG64DXSM determinism check rate | Normal-Gamma for throughput; Beta-Binomial for determinism | `.bench-history/numpy-ufunc-bench.latest.json` |
| **HTTP** | Request p99 latency; OpenAPI schema generation time; per-route success rate | Normal-Gamma for latency; Beta-Binomial for success rate | `.bench-history/http-route-bench.latest.json` |

## Composition

- [pattern:70-E-PROCESSES](70-E-PROCESSES.md) — e-processes detect invariant violations; BOCPD detects distribution shifts. Sibling layers.
- [pattern:75-BAYESIAN-CONFORMAL-SCORE](75-BAYESIAN-CONFORMAL-SCORE.md) — BOCPD's `Stable` regime is a precondition for the conformal ratchet's "release" decision.
- [pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md) — `.bench-history/` is the baseline source for BOCPD's comparison.
- [pattern:170-ROBUST-REGRESSION-DETECTOR](170-ROBUST-REGRESSION-DETECTOR.md) — median + MAD detector is the simpler sibling; BOCPD is the principled version.
- [pattern:85-ADVERSARIAL-SEARCH](85-ADVERSARIAL-SEARCH.md) — adversarial probes can induce `ShiftDetected`; that's a feature, not a bug.

## Pitfalls

- **Declaring regime with < 100 observations.** The posterior over run length is too diffuse to be reliable. The min-100 rule is non-negotiable; bridge with `Stable` as the conservative default.
- **Hazard rate too high (`H = 1/50`).** Frequent regime declarations; the system never stabilizes. `1/250` is calibrated for typical CI cadence (one bench per commit, dozens of commits per day).
- **Hazard rate too low (`H = 1/10000`).** BOCPD never declares a change; real regressions are absorbed into the long-running segment. Defeats the purpose.
- **Using one predictive model across heterogeneous streams.** Throughput is continuous (Normal-Gamma); abort rate is binary-proportion (Beta-Binomial). Wrong model produces miscalibrated change-point posteriors.
- **`MAP run length` confused with `mean run length`.** MAP is the mode (most-probable single hypothesis); mean is the expected value. For change-point detection, MAP is sharper but mean is more robust. The canonical algorithm uses MAP for the regime label.
- **No predictive-model update step.** Each step must update *both* the run-length posterior *and* the per-segment sufficient statistics. Skipping the model update means BOCPD compares against stale baselines.
- **Treating `ShiftDetected` as a failure.** It's an instrumented event — the distribution changed; the question is *why*. If the workload changed, re-baseline. If the workload didn't change, *that's* the failure.
- **Persistence: serializing only `run_length_posterior` without the predictive models.** Reloading produces incorrect predictive probabilities; the system is now blind to the segment's distributional properties.
- **Conflating BOCPD with anomaly detection.** Anomaly detectors flag individual outliers; BOCPD flags shifts in the underlying distribution. A run of 50 elevated points is anomaly-noise to a per-point detector but `ShiftDetected` to BOCPD.
- **Using BOCPD on the conformance-score stream without the e-process layer.** BOCPD tells you "the distribution shifted"; e-processes tell you "an invariant violated". Both layers are required for a complete picture.
