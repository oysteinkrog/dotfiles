# Pattern 75 — BAYESIAN + CONFORMAL SCORE (Beta posterior + distribution-free band; release uses LOWER bound)

## What

A two-layer release-decision engine. Layer 1: per-category pass rate modeled as `theta_c ~ Beta(α_prior + Σ weighted_successes, β_prior + Σ weighted_failures)` — subjective prior + observed evidence yields a posterior distribution over the true pass rate. Layer 2: distribution-free conformal band (Vovk-Gammerman-Shafer 2005) calibrated from per-category residuals (frequentist vs Bayesian gap); cost is wider intervals, benefit is honest coverage under heavy-tailed / bimodal / regime-shifting workload distributions. Release decisions use the **conformal LOWER bound**, not the point estimate, and `truncate_score` to 6 decimal places for cross-platform bit-equality (K-5).

## Why

> "Lower confidence bound for release decisions" — MINING-2 §11
> "x86 vs ARM vs WASM differ at LSB; truncation ensures bytewise identical scores regardless of CPU." — MINING-2 §11

A release decision based on a point estimate ("parity = 0.94") is a coin flip the moment the workload distribution shifts. The conformal lower bound ("we are 95% confident parity ≥ 0.91") is a guarantee that doesn't fail catastrophically under distribution shift. `truncate_score` makes the bound bit-identical across CPUs so the ratchet doesn't flicker.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/score_engine.rs` (bead `bd-1dp9.1.3`) — `BetaParams`, `truncate_score`, conformal band (MINING-2 §11)
- `reports/ratchet_state.json` — persisted lower bound; ratchet only ever monotonically increases this value
- `reports/scorecards.json` — per-category posterior summaries

## Verbatim shape — `BetaParams`

From MINING-2 §11, verbatim:

```rust
pub struct BetaParams { pub alpha: f64, pub beta: f64 }

impl BetaParams {
    pub fn mean(self) -> f64 { self.alpha / (self.alpha + self.beta) }
    pub fn variance(self) -> f64 {
        let ab = self.alpha + self.beta;
        (self.alpha * self.beta) / (ab * ab * (ab + 1.0))
    }
    pub fn quantile(self, p: f64) -> f64 { /* bisection on regularized incomplete beta */ }
    pub fn credible_interval(self, confidence: f64) -> (f64, f64) {
        let tail = (1.0 - confidence) / 2.0;
        (self.quantile(tail), self.quantile(1.0 - tail))
    }
}
```

## Beta posterior math

The per-category model (verbatim, MINING-2 §11):

> - Passing → success (1.0, weighted by feature weight)
> - Partial → fractional success (0.5, weighted)
> - Missing → failure (0.0, weighted)
> - Per-category pass rate `theta_c ~ Beta(α_prior + Σ weighted_successes, β_prior + Σ weighted_failures)`
> - Global score `S_t = weighted sum of category posterior means`
> - **Lower confidence bound for release decisions**

```rust
pub struct CategoryEvidence {
    pub category_id: String,
    pub weighted_successes: f64,      // sum of (1.0 * weight) over passing features
    pub weighted_partials: f64,       // sum of (0.5 * weight) over partial
    pub weighted_failures: f64,       // sum of (1.0 * weight) over missing
}

pub fn posterior(prior: BetaParams, ev: &CategoryEvidence) -> BetaParams {
    BetaParams {
        alpha: prior.alpha + ev.weighted_successes + ev.weighted_partials,
        beta:  prior.beta + ev.weighted_failures + (ev.weighted_partials), // partial counts in both
    }
}
```

**Default prior:** `BetaParams { alpha: 1.0, beta: 1.0 }` — uninformative uniform on `[0,1]`.

## Conformal bands (verbatim — MINING-2 §11)

> ```
> // Distribution-free finite-sample coverage.
> // Calibrated from per-category residuals (frequentist vs Bayesian gap).
> // P(R_{n+1} ≤ q) ≥ 1 − α for any distribution.
> // Cost: wider intervals. Benefit: honest under heavy-tailed / bimodal / regime-shifting distributions.
> ```

Vovk-Gammerman-Shafer 2005 conformal prediction: pick a nonconformity score `R_i` (e.g., absolute difference between observed pass rate and Beta-mean estimate); the `(1-α)`-quantile of `R_1..R_n` gives a band `[μ̂ - q, μ̂ + q]` with finite-sample coverage `≥ 1 - α` regardless of the underlying distribution.

```rust
pub fn conformal_lower_bound(
    posterior: BetaParams,
    residuals: &[f64],         // |observed - Bayesian-predicted| from prior cycles
    confidence: f64,           // e.g., 0.95
) -> f64 {
    let point = posterior.mean();
    let mut sorted = residuals.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let q_idx = ((1.0 - (1.0 - confidence)) * sorted.len() as f64).floor() as usize;
    let q = sorted.get(q_idx.min(sorted.len() - 1)).copied().unwrap_or(0.0);
    (point - q).max(0.0)
}
```

**Release rule:** A new release is allowed iff `truncate_score(conformal_lower_bound(...))` is `>=` the persisted ratchet floor, AND no per-category bound dropped.

## `truncate_score` — cross-platform LSB-determinism

From MINING-2 §11, verbatim:

```rust
pub fn truncate_score(x: f64) -> f64 { /* truncate to 6 decimal places */ }
```

Canonical implementation:

```rust
pub fn truncate_score(x: f64) -> f64 {
    let scaled = (x * 1_000_000.0).floor();
    scaled / 1_000_000.0
}
```

**Why** (verbatim from MINING-2 §11): *x86 vs ARM vs WASM differ at LSB; truncation ensures bytewise identical scores regardless of CPU.*

**Application:** every release-boundary value passes through `truncate_score`:

- per-category posterior means
- conformal lower bounds
- ratchet floor in `reports/ratchet_state.json`
- per-feature `S_t` in `scorecards.json`

A score that hasn't been `truncate_score`'d is a score that may disagree between Mac and Linux builds at the LSB and break the ratchet diff.

## Per-class instantiation

### SQL-class (FrankenSQLite)

- Per-category: NULL semantics, GROUP BY, joins, window functions, … (the categories from [pattern:25-FIXTURE-ROOT-CONTRACT](25-FIXTURE-ROOT-CONTRACT.md))
- Prior: `BetaParams { alpha: 1.0, beta: 1.0 }`
- Confidence: `0.95`
- Residuals: per-category pass-rate observations from last N=30 cycles

### RESP-class (FrankenRedis)

- Per-category: commands, persistence, replication, cluster, pubsub
- Prior: `BetaParams { alpha: 2.0, beta: 2.0 }` (slightly informative — Redis behavior is well-specified)
- Confidence: `0.95`

### Numerical / ML-class

- Per-category: per-op-family (ufunc / reduction / linalg / autograd / optimizer)
- Prior: `BetaParams { alpha: 1.0, beta: 1.0 }`
- Confidence: `0.95`
- Residuals also include per-op ULP-tolerance violations (treated as "partial" not "missing")

### HTTP-class

- Per-category: routing, validation, OpenAPI schema, middleware, extractor
- Prior: `BetaParams { alpha: 2.0, beta: 1.0 }` (slightly optimistic — HTTP semantics are well-defined by RFC)
- Confidence: `0.95`

## Composition

- [pattern:70-E-PROCESSES](70-E-PROCESSES.md) — runtime invariant monitoring (Ville's inequality); this pattern is the release-decision layer.
- [pattern:80-BOCPD-REGIME-DETECTION](80-BOCPD-REGIME-DETECTION.md) — BOCPD on the parity-score stream detects regime shifts that should trigger ratchet review.
- [pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md) — the perf-side analogue; both ratchets use `truncate_score` for cross-machine stability.
- [pattern:50-THREE-TIER-EQUIVALENCE](50-THREE-TIER-EQUIVALENCE.md) — tier downgrades count as "partial" in the Beta evidence.
- [pattern:105-FEATURE-UNIVERSE](105-FEATURE-UNIVERSE.md) — feature weights flow into `weighted_successes` / `weighted_failures`.

## Pitfalls

- **Release on the point estimate (`posterior.mean()`).** Point estimates are wrong by definition in expectation; the *direction* of error matters. Always use `conformal_lower_bound`.
- **Conformal residuals computed from the same cycle being scored.** That's overfitting. Residuals come from *prior* cycles (held-out conformal calibration set).
- **Skipping `truncate_score` because "the consumer truncates anyway".** The K-2 anti-pattern: the consumer might forget. Truncate at the producer.
- **Truncating to fewer than 6 places "to save space".** 6 places is calibrated to the LSB-difference threshold. Truncating to 4 loses signal; truncating to 8 retains LSB noise.
- **Wrong handling of "Partial" in the Beta update.** A partial pass should contribute to BOTH alpha and beta (it's half-success and half-failure); only crediting it to alpha biases the posterior up. The canonical update above does this correctly.
- **Confidence too tight (`0.99`).** The conformal band widens with tighter confidence; release decisions stall because the lower bound never moves. `0.95` is the operating point that balances coverage and ratchet progress.
- **No conformal residuals on day 1.** Before there are residuals, the conformal band is undefined. Bootstrap with a wide prior-derived band for the first N cycles.
- **Per-category bounds not enforced.** "Global score went up" while one category went down is the K-4 anti-pattern in scoring form. The ratchet requires global ≥ AND per-category ≥ for every category.
- **Weighted partials counted with weight 1.0 instead of 0.5.** Weight policy: success = 1.0 × feature_weight; partial = 0.5 × feature_weight; missing = 0.0 (i.e., contributes only to beta). Implementing partial as 1.0 × feature_weight inflates the mean.
- **`BetaParams { alpha: 0.0, beta: 0.0 }` as prior.** Improper prior; the posterior is undefined when evidence is zero. Use at least `BetaParams { alpha: 1.0, beta: 1.0 }`.
