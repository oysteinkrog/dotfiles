# VERIFICATION-UNDER-UNCERTAINTY.md — Bayesian Framework For Bead Completion Confidence

<!-- TOC: Why probabilistic | Likelihood / prior / posterior | Conformal calibration | Sequential testing | When to use over deterministic rubric | Worked example -->

> The default rubric (`RUBRIC.md`) is deterministic: same evidence → same score. That's the right default — it's auditable and reproducible. But for high-stakes audits where you want to express **confidence intervals** rather than point estimates, this file describes a Bayesian framing. Adapted from established conformal-prediction and Bayesian-verification literature.

> **Read this if:** you're auditing safety-critical code, regulatory-compliance code, or any project where "the bead is 95% likely complete" is more useful than "the bead scored 850/1000."

---

## Why probabilistic verification

The deterministic rubric answers "did this bead pass?" The Bayesian framing answers "what's the probability this bead's *real-world claim* is true?" The latter is more honest about three uncertainties:

1. **Test coverage uncertainty.** A test passing on 1,000 inputs doesn't prove correctness on input 1,001. Coverage gives a sample, not a guarantee.
2. **Theater-detection uncertainty.** Phase 5's regex / AST patterns catch *known* theater patterns. Novel theater may slip through.
3. **Spec-extraction uncertainty.** Phase 2 parses bead body literally; what the bead's author *intended* may be richer than what the spec extractor captured.

A 95% confidence interval is more truthful than a 850/1000 point estimate when these uncertainties dominate.

---

## The Bayesian model

Define the random variable `D` = "the bead's claim is true (the implementation actually does what the bead says)". The audit produces evidence `E` (Phase 4 verdicts, Phase 5 findings, etc.). We want `P(D | E)`.

```
P(D | E) = P(E | D) · P(D) / P(E)
```

### Prior `P(D)`

Probability that an arbitrary closed bead's claim is true, **before evidence**. Calibrated from your project's history:

| Project state | Default `P(D)` |
|---------------|---------------:|
| Mature, audit-converged for months | 0.85 |
| Active development, audit running | 0.70 |
| Onboarding (first audit) | 0.55 |
| Project with known sloppy sessions | 0.45 |

### Likelihood `P(E | D)`

Probability of observing the evidence given the bead's claim is true. Derived from:

| Evidence type | High `P(E | D)` (consistent with D) | Low `P(E | D)` (inconsistent with D) |
|---------------|------------------------------------|--------------------------------------|
| Phase 4 unit tests PASS | 0.90 | 0.20 |
| Phase 4 e2e PASS hitting real services | 0.95 | 0.05 |
| Phase 5: 0 BLOCKING findings | 0.85 | 0.40 |
| Phase 5: 1 BLOCKING finding | 0.30 | 0.85 |
| Phase 6: line coverage ≥ 80% | 0.80 | 0.50 |
| Phase 6: fuzz ran for stated time, no crashes | 0.85 | 0.30 |
| Phase 7: 0 cross-bead findings | 0.80 | 0.50 |
| `git_xref.txt` non-empty | 0.90 | 0.10 |
| `closed_by_session` not in sloppy list | 0.85 | 0.50 |

### Independence assumption

The evidence types are NOT fully independent (a stub causes both Phase 4 to "pass trivially" and Phase 5 to BLOCKING). For a conservative posterior, treat the evidence as a chain through the **most informative** signal — typically Phase 5 BLOCKING findings, which are most diagnostic.

### Posterior `P(D | E)`

Multiplied through Bayes' rule. For the chained-evidence approximation:

```python
def bead_posterior(prior: float, evidence: dict) -> float:
    p = prior
    for signal, value in evidence.items():
        likelihood_d = LIKELIHOOD_TABLE[signal]["D"]
        likelihood_not_d = LIKELIHOOD_TABLE[signal]["not_D"]
        p_e = p * likelihood_d + (1 - p) * likelihood_not_d
        p = p * likelihood_d / p_e if p_e > 0 else p
    return p
```

A bead with `Phase 5: 1 BLOCKING finding` starts at prior 0.70, ends with posterior ~0.30 — flipping the verdict from "probably complete" to "probably incomplete."

---

## Conformal calibration

To produce **calibrated** confidence intervals, use the Phase 10 spot-checks as a calibration set:

1. Run a deterministic-rubric pass.
2. The Phase 10 fresh-eyes spot-check independently re-derives 5 random scores.
3. The deviations form a calibration distribution.
4. For each new bead's posterior, attach a (1-α) confidence interval based on the calibration quantile.

```python
def conformal_interval(posterior: float, calibration_residuals: list[float], alpha: float = 0.05) -> tuple[float, float]:
    """Return a (1-alpha) prediction interval for the bead's true posterior."""
    n = len(calibration_residuals)
    if n < 5:
        # Not enough calibration; return wide interval
        return max(0, posterior - 0.3), min(1, posterior + 0.3)
    quantile = sorted([abs(r) for r in calibration_residuals])[int((1 - alpha) * (n + 1)) - 1]
    return max(0, posterior - quantile), min(1, posterior + quantile)
```

A bead with posterior 0.85 and calibration residuals showing ±0.10 deviation gets the conformal interval **[0.75, 0.95]**. The user knows: with 95% confidence, the bead's actual completion probability is between 75% and 95%.

---

## Sequential testing across passes

For tripwire mode, sequential testing reduces alert noise:

```
H0: project quality is unchanged
H1: project quality has regressed

After each pass, accumulate evidence. Alert only when the cumulative
likelihood ratio crosses a decision boundary (Wald SPRT).
```

```python
def sequential_alert(passes: list[dict], threshold: float = 5.0) -> bool:
    """Sequential Probability Ratio Test. Threshold 5.0 ≈ 0.05 type-I error."""
    log_lr = 0.0
    for p in passes[-10:]:
        if p["false_closed_delta"] > 0:
            log_lr += math.log(0.7 / 0.3)  # regression evidence
        elif p["false_closed_delta"] < 0:
            log_lr += math.log(0.3 / 0.7)  # improvement evidence
    return log_lr >= math.log(threshold)
```

This is more rigorous than "alert when 5 false-closed in 1 day" — it adapts to the project's noise floor.

---

## When to use this framework

| Scenario | Use Bayesian? |
|----------|:-------------:|
| Routine standard-mode audit | No — deterministic rubric is fine |
| Pre-release for safety-critical code | **Yes** |
| Regulatory-compliance audit (SOC2, HIPAA, PCI) | **Yes** |
| Project with > 200 closed beads (large enough for conformal calibration) | Optional |
| First audit on a project | No — prior is too uncertain to be useful |
| Tripwire mode | **Sequential testing only**, not full Bayesian |

---

## Worked example: high-stakes audit

Scenario: pre-release audit of payment-processing code. Bead `bd-stripe-webhook` claims to validate webhook signatures.

**Prior.** Project is mature, audit-converged for 3 months. `P(D) = 0.85`.

**Evidence collected:**

| Evidence | Observation | `P(E | D)` | `P(E | ¬D)` |
|----------|-------------|------------:|------------:|
| Phase 4 unit tests | PASS, 12 assertions | 0.90 | 0.20 |
| Phase 4 e2e | PASS, hit real Stripe sandbox, signature verified | 0.95 | 0.05 |
| Phase 5 BLOCKING | 0 findings | 0.85 | 0.40 |
| Phase 6 line coverage | 92% over `src/webhooks/` | 0.85 | 0.30 |
| Phase 6 branch coverage | 88% | 0.85 | 0.40 |
| Phase 6 e2e real-service | structured log evidence | 0.85 | 0.10 |
| `git_xref.txt` | 4 commits | 0.90 | 0.10 |
| `closed_by_session` | not in sloppy list | 0.85 | 0.50 |

**Posterior calculation (chained):**

```
Start: 0.85
After unit PASS:        0.85 × 0.90 / (0.85 × 0.90 + 0.15 × 0.20) = 0.96
After e2e PASS:         0.96 × 0.95 / (0.96 × 0.95 + 0.04 × 0.05) = 0.998
After 0 BLOCKING:       0.998 × 0.85 / ...               ≈ 0.999
After line cov 92%:     0.999 × 0.85 / ...               ≈ 0.9994
... (converges to ~0.999+)
```

**Conformal interval (95%):** Calibration residuals from prior passes show ±0.04. Interval: **[0.96, 1.00]**.

**Verdict:** This bead's claim is true with ≥ 96% confidence. **Ship-ready for the release.**

Compare to deterministic rubric: 985/1000 (🟢 Verified). Same conclusion, different framing. The Bayesian version expresses the residual uncertainty explicitly.

---

## A bead that the Bayesian framing flags worse

Same project, bead `bd-perf-04`. Deterministic rubric: 720 (🟡 Partial — passes threshold). Bayesian:

**Prior.** 0.85.

**Evidence:**

| Evidence | Observation | Diagnostic |
|----------|-------------|-----------|
| Phase 4 bench | PASS, p95 = 2.3ms (budget 2ms) | Budget missed |
| Phase 5 | 0 BLOCKING | Helpful |
| Phase 6 line cov | 75% (under 80% threshold) | Concerning |
| `git_xref.txt` | 1 commit (with `// optimize later` comment) | Hedge phrase |

**Posterior:** ~0.65. **Conformal interval:** [0.55, 0.75].

**Verdict (Bayesian):** "There's a 35% chance this bead's perf claim is *not* satisfied." The deterministic rubric scored 720 and waved through. The Bayesian framing surfaces the residual risk for human judgment.

---

## Implementation

The Bayesian framework is **opt-in** per audit. Set in `rubric.md`:

```yaml
scoring_mode: bayesian   # default: deterministic
prior_calibration: 0.85
conformal_alpha: 0.05
```

When enabled, `score-bead.py` emits both the deterministic score AND the Bayesian posterior + conformal interval. The scorecard shows both:

```
**Score: 985 / 1000**
**Posterior: P(complete | evidence) = 0.999, 95% CI [0.96, 1.00]**
```

The deterministic score remains primary (for convergence semantics across passes); the Bayesian numbers are advisory.

---

## When to actually invest in this framework

For most audits, the deterministic rubric is sufficient. Adopt the Bayesian framework when:

1. **Stakes are existential.** Aviation, medical, financial — false-negatives (false-closed beads in production) cost real lives or real dollars.
2. **You're submitting an audit report to a regulator.** Confidence intervals are more defensible than point estimates.
3. **You have ≥ 100 closed beads with calibration history.** Without calibration data, the conformal intervals are too wide to be useful.

For everything else, deterministic + the Polish Bar is a strong baseline. The audit's value is in catching real false-closures, not in producing publication-quality confidence intervals.

---

## Don't fall for false rigor

A common failure mode: replacing a deterministic-but-clear rubric with a Bayesian-but-opaque one. The Bayesian framing is a *complement*, not a replacement. If a stakeholder asks "why did this bead score 720?" — the deterministic rubric points at 6 dimension scores with citations. The Bayesian posterior says "it's probably done with 65% confidence." The deterministic answer is more actionable.

Use Bayesian when its strength (expressing uncertainty) outweighs its weakness (less directly actionable).