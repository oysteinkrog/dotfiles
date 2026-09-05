# Worked Math: Bayesian Posterior Update for the Conformal-Band Ratchet

How the parity-score engine uses Beta-Bernoulli conjugacy to maintain per-category posterior estimates of pass-rate, why this composes with the conformal band, and the implementation details that prevent cross-platform LSB drift from breaking the ratchet. Companion to [`math/conformal-band-worked.md`](conformal-band-worked.md) (numerical worked example) + [`pattern:75-BAYESIAN-CONFORMAL-SCORE`](../patterns/75-BAYESIAN-CONFORMAL-SCORE.md) (operational pattern).

---

## 1. The setup

The gauntlet's parity score is structured per-category. For SQL-class:

```
ReadSingle        0.35
ReadAggregate     0.15
WriteSingle       0.30
WriteBulk         0.10
ConcurrentWriters 0.05
MixedOltp         0.05
```

Per-category pass-rate `θ_c` is unknown; we observe `n_c` trials with `k_c` passes per round. Treat `k_c ~ Binomial(n_c, θ_c)` and put a `Beta(α₀, β₀)` prior on each `θ_c`. By Beta-Bernoulli conjugacy:

```
θ_c | data ~ Beta(α₀ + k_c, β₀ + (n_c - k_c))
```

The conjugate update is closed-form (no MCMC), so the ratchet can apply after every round without computational overhead.

## 2. Choosing the prior

Three common choices for `(α₀, β₀)`:

### Uniform prior (`α₀ = β₀ = 1`)

Treats every pass-rate as equally likely a priori. Use when:
- This is the gauntlet's first round (no historical data).
- A new category was just added to the FeatureUniverse.
- The category's prior performance is genuinely unknown.

Posterior after `n_c` trials with `k_c` passes:
```
Beta(1 + k_c, 1 + n_c - k_c)
```

Mean: `(1 + k_c) / (2 + n_c)`. Mode (for `n_c ≥ 1`): `k_c / n_c`.

### Jeffreys prior (`α₀ = β₀ = 0.5`)

Improper at the boundary but well-defined in the interior. Slightly more aggressive than uniform — pulls posteriors away from `0.5` toward the data. Use when:
- The category has a hard cutoff (e.g., "either the SUBJECT and REFERENCE agree or they don't") and you want to surface even small majorities.
- The reference implementation has known pathological edges (and you want to weight those properly).

### Round-N-1 informative prior

For continuous-monitoring scenarios (Phase 11 round-over-round), use the prior round's posterior as this round's prior:

```
(α₀, β₀)_t = (α₀, β₀)_{t-1} + (k_{c, t-1}, n_{c, t-1} - k_{c, t-1})
```

This is just sequential Bayesian update — equivalent to treating all observations as one big batch but lets you discard old observation data after the posterior is updated. Use when:
- The category's underlying rate is genuinely stationary (BOCPD says "Stable" — [`math/bocpd-worked.md`](bocpd-worked.md)).
- You want the round-over-round ratchet to be sensitive to gradual drift.

**Caution:** if BOCPD says "ShiftDetected" or "Regressing", DON'T use round-N-1 prior — it will anchor you to a stale rate. Reset to uniform.

## 3. The posterior credible interval

For `θ_c ~ Beta(α, β)`, the central `100(1-α_conf)%` credible interval is:

```
[Q_{Beta(α, β)}(α_conf/2),  Q_{Beta(α, β)}(1 - α_conf/2)]
```

where `Q_{Beta}` is the Beta quantile function. For `α_conf = 0.05` (95% credible interval), use 2.5% and 97.5% quantiles.

For `α + β` large (≥ 20), the Beta posterior is well-approximated by `Normal(α/(α+β), √(αβ/((α+β)²(α+β+1))))`. For `α + β` small (< 20), use the exact Beta quantile (typically via Newton-Raphson on the regularized incomplete beta function `I_x(α, β)`).

## 4. Composing per-category posteriors into a global score

The per-category posteriors `θ_c | data ~ Beta(...)` give per-category pass-rate distributions. The global parity score:

```
S = Σ_c w_c · θ_c
```

is a weighted sum of Beta-distributed RVs. Closed-form distribution: not a standard distribution; the moments are easy:

```
E[S]   = Σ_c w_c · E[θ_c]    = Σ_c w_c · α_c / (α_c + β_c)
Var[S] = Σ_c w_c² · Var[θ_c] = Σ_c w_c² · α_c β_c / ((α_c + β_c)² (α_c + β_c + 1))
```

(assuming per-category independence, which is approximately true for the gauntlet's category decomposition).

For the global score's distribution, the gauntlet uses Monte Carlo: sample `M = 10000` draws from each `θ_c`, compute `S` for each, take percentiles. Closed-form approximations (e.g., moment-matching to a Beta) lose tail accuracy.

## 5. Why this composes with the conformal band

Two complementary uses:

**Posterior credible interval** is a Bayesian statement: *given the prior, the posterior credible interval is the range of plausible `θ_c` values consistent with the observed data*. The interpretation depends on the prior — if the prior is wrong, the interval is too.

**Conformal band** (per [`math/conformal-band-worked.md`](conformal-band-worked.md)) is a frequentist guarantee: *the true `θ_c` is in the band with probability `1 - α`, regardless of distribution*. The interpretation doesn't depend on a prior.

The gauntlet uses BOTH:
- The posterior is the *operating point* — the orchestrator uses `E[θ_c]` for round-to-round decisions, and the credible interval to detect when posterior uncertainty is large enough to warrant more sampling.
- The conformal band is the *release-decision gate* — `S_conformal_lower` is the input to `apply-ratchet.sh`.

Per [Q-052]: *"the Bayesian posterior tells us where we think the rate is; the conformal band tells us where the rate provably isn't."*

## 6. Implementation: truncate_score for cross-platform determinism

The Beta posterior's mean and CI are computed in `f64` arithmetic. On x86, ARM, and WASM, `f64` operations differ at the LSB (last significant bit) — even with identical inputs. For the ratchet to make deterministic decisions, the scores MUST be bytewise identical across architectures.

The gauntlet uses `truncate_score` (per [`pattern:75-BAYESIAN-CONFORMAL-SCORE`](../patterns/75-BAYESIAN-CONFORMAL-SCORE.md)):

```rust
pub fn truncate_score(x: f64) -> f64 {
    // Truncate to 6 decimal places, rounding toward zero.
    let scale = 1_000_000.0f64;
    (x * scale).trunc() / scale
}
```

Applied at the boundary between computation and persistence: posterior mean, CI bounds, conformal lower-bound, global score `S` — all truncated to 6 decimals before being written to JSON. Internal computation stays full-precision.

**Why truncate (not round):** `round_ties_to_even` (the IEEE default) also varies at LSB on some platforms. `trunc()` is the most platform-stable rounding mode.

**Why 6 decimals (not 12):** 6 decimals gives `±5e-7` precision, which is well below the ratchet's `epsilon = 0.001` tolerance. More decimals would be wasted (and would re-expose the LSB drift).

## 7. Worked numerical example

Round 4 baseline for `ReadSingle` category:
- `n_4 = 200` trials.
- `k_4 = 195` passes (97.5% raw pass rate).
- Round 3 posterior was `Beta(91, 3)` (informative prior).

Posterior update:
```
α_4 = 91 + 195 = 286
β_4 = 3 + (200 - 195) = 8
```

Posterior mean:
```
E[θ_ReadSingle] = 286 / (286 + 8) = 286 / 294 = 0.97278911...
```

`truncate_score(0.97278911...) = 0.972789`.

95% credible interval (Beta(286, 8)): roughly `[0.946, 0.991]` from Newton-Raphson on `I_x`.

Round 5 baseline (no regression, just more data):
- `n_5 = 200`, `k_5 = 197`.

Posterior update:
```
α_5 = 286 + 197 = 483
β_5 = 8 + (200 - 197) = 11
```

Posterior mean:
```
E[θ_ReadSingle] = 483 / 494 = 0.97773279...
```

`truncate_score(0.97773279...) = 0.977732`.

**Ratchet check:** new lower-bound > previous high-water-mark? If round-4 ratchet was `0.946` and round-5 95% CI is `[0.961, 0.989]`, ratchet PASSES (`0.961 > 0.946 - 0.001`).

**Posterior is tightening:** CI width went from `0.045` (round 4) to `0.028` (round 5) — more data, tighter estimate. The ratchet now requires less margin for the next round to pass.

## 8. Handling Tier 3 categories (small sample sizes)

For categories with `n_c < 20` (e.g., ConcurrentWriters with only 12 features), the Beta posterior is wide — the credible interval covers most of `[0, 1]`. The ratchet should NOT block on these alone; the conformal band's distribution-free guarantee is what protects.

For these small-`n` cases, the gauntlet uses:
- Posterior mean for the score weighting (still meaningful).
- Conformal band lower-bound for the ratchet decision (more conservative).
- Round-N-1 informative prior is especially helpful (the round-N-1 posterior accumulates evidence).

## 9. Cross-references

- [`pattern:75-BAYESIAN-CONFORMAL-SCORE`](../patterns/75-BAYESIAN-CONFORMAL-SCORE.md) — operational pattern.
- [`math/conformal-band-worked.md`](conformal-band-worked.md) — companion (frequentist conformal guarantee).
- [`math/ville-supermartingale-proof.md`](ville-supermartingale-proof.md) — companion (e-process anytime-valid testing).
- [`methodology/CONFORMAL-RATCHET.md`](../methodology/CONFORMAL-RATCHET.md) — ratchet mechanism that consumes these scores.
- [`subagents/ratchet-curator.md`](../../subagents/ratchet-curator.md) — emits + persists ratchet state.
- Gelman, A. et al. (2013), *Bayesian Data Analysis*, 3rd ed., Chapter 2 — Beta-Bernoulli conjugacy reference.
- Brown, Cai, DasGupta (2001), *Interval Estimation for a Binomial Proportion* — discussion of Beta posterior vs frequentist CIs for small `n`.
