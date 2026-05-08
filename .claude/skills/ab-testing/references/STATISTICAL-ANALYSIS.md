# Statistical Analysis for A/B Testing

## Table of Contents
- [Method Comparison](#method-comparison)
- [Sample Size Planning](#sample-size-planning)
- [Frequentist Approach](#frequentist-approach)
- [Bayesian Approach](#bayesian-approach)
- [Multi-Armed Bandits](#multi-armed-bandits)
- [Choosing Your Method](#choosing-your-method)
- [Common Pitfalls](#common-pitfalls)
- [Implementation Code](#implementation-code)

---

## Method Comparison

| Aspect | Frequentist | Bayesian | Bandit |
|--------|-------------|----------|--------|
| **Question Answered** | "Is B different from A?" | "What's the probability B is better?" | "Which arm should I pull now?" |
| **Sample Size** | Fixed upfront | Flexible | Continuous |
| **Peeking** | Inflates false positives | Safe to monitor | Expected behavior |
| **Output** | p-value, CI | P(B>A), credible interval | Allocation ratio |
| **Stopping Rule** | Predetermined N | P(B>A) > threshold | Traffic allocation converges |
| **Regret** | Fixed (50/50 split) | Fixed | Minimized |
| **Complexity** | Low | Medium | High |

---

## Sample Size Planning

### The Problem

Testing without enough data = noise mistaken for signal.

### Minimum Sample Size Formula

For detecting a relative lift with 80% power at 95% confidence:

```
n = 16 × σ² / δ²

Where:
  σ = standard deviation of conversion rate = √(p × (1-p))
  δ = minimum detectable effect (absolute difference)
  p = baseline conversion rate
```

### Quick Reference Table

| Baseline Rate | 10% Relative Lift | 20% Relative Lift | 50% Relative Lift |
|---------------|-------------------|-------------------|-------------------|
| 2% | 78,000 per variant | 19,500 | 3,100 |
| 5% | 30,500 | 7,600 | 1,200 |
| 10% | 14,500 | 3,600 | 580 |
| 20% | 6,400 | 1,600 | 260 |

### Calculator (Python)

```python
import scipy.stats as stats
import numpy as np

def sample_size_per_variant(
    baseline_rate: float,
    relative_lift: float,
    alpha: float = 0.05,
    power: float = 0.8
) -> int:
    """Calculate required sample size per variant."""
    p1 = baseline_rate
    p2 = baseline_rate * (1 + relative_lift)
    effect = p2 - p1

    # Pooled variance
    p_pooled = (p1 + p2) / 2
    var_pooled = 2 * p_pooled * (1 - p_pooled)

    # z-scores
    z_alpha = stats.norm.ppf(1 - alpha / 2)
    z_beta = stats.norm.ppf(power)

    n = var_pooled * ((z_alpha + z_beta) ** 2) / (effect ** 2)
    return int(np.ceil(n))

# Example: 5% baseline, detect 20% relative lift
n = sample_size_per_variant(0.05, 0.20)  # → ~7,600 per variant
```

---

## Frequentist Approach

### When to Use

- Fixed sample size predetermined
- Need to control false positive rate strictly
- Regulatory or compliance requirements
- Traditional stakeholders expect p-values

### The Test (Chi-Squared)

```python
import scipy.stats as stats

def chi_squared_test(
    conversions_a: int, visitors_a: int,
    conversions_b: int, visitors_b: int
) -> dict:
    """Perform chi-squared test for A/B experiment."""

    # Contingency table
    #              Convert  No Convert
    # Variant A      a         b
    # Variant B      c         d
    table = [
        [conversions_a, visitors_a - conversions_a],
        [conversions_b, visitors_b - conversions_b]
    ]

    chi2, p_value, dof, expected = stats.chi2_contingency(table)

    rate_a = conversions_a / visitors_a
    rate_b = conversions_b / visitors_b
    lift = (rate_b - rate_a) / rate_a

    return {
        'rate_a': rate_a,
        'rate_b': rate_b,
        'lift': lift,
        'chi2': chi2,
        'p_value': p_value,
        'significant': p_value < 0.05
    }

# Example
result = chi_squared_test(50, 1000, 72, 1000)
# {
#   'rate_a': 0.05,
#   'rate_b': 0.072,
#   'lift': 0.44,  # 44% lift
#   'p_value': 0.035,
#   'significant': True
# }
```

### Confidence Intervals

```python
def confidence_interval(conversions: int, visitors: int, confidence: float = 0.95):
    """Wilson score interval (better than Wald for proportions)."""
    from scipy.stats import norm

    n = visitors
    p = conversions / n
    z = norm.ppf(1 - (1 - confidence) / 2)

    denominator = 1 + z**2 / n
    center = (p + z**2 / (2*n)) / denominator
    spread = z * np.sqrt((p * (1-p) + z**2 / (4*n)) / n) / denominator

    return (center - spread, center + spread)

# Example: 72/1000 conversions
ci = confidence_interval(72, 1000)  # → (0.057, 0.090)
# "We're 95% confident true rate is between 5.7% and 9.0%"
```

### Stopping Rules

**Fixed horizon (standard)**:
- Determine sample size upfront
- Run until reached
- Analyze once at the end

**Sequential testing (if you must peek)**:
Use alpha-spending (O'Brien-Fleming) or sequential probability ratio test:

```python
# Simplified SPRT
def sequential_test(conversions_a, n_a, conversions_b, n_b, threshold=0.05):
    """Simplified sequential test using repeated significance."""
    result = chi_squared_test(conversions_a, n_a, conversions_b, n_b)

    # Adjust for peeking (Bonferroni-like correction based on # of peeks)
    num_peeks = 10  # How many times you'll check
    adjusted_alpha = threshold / num_peeks

    return {
        **result,
        'adjusted_significant': result['p_value'] < adjusted_alpha
    }
```

---

## Bayesian Approach

### Why Bayesian?

| Frequentist Says | Bayesian Says |
|------------------|---------------|
| "p < 0.05, reject null" | "96% probability B is better than A" |
| "95% CI doesn't contain 0" | "95% chance true lift is between X and Y" |
| Can't peek without correction | Peek anytime, probabilities update |
| "Not significant" = inconclusive | "43% chance B is better" = still uncertain |

### Beta-Binomial Model

For conversion rate experiments:
- Prior: Beta(α₀, β₀) — often Beta(1, 1) = uniform
- Likelihood: Binomial(n, p)
- Posterior: Beta(α₀ + conversions, β₀ + non-conversions)

```python
import scipy.stats as stats
import numpy as np

def bayesian_ab_test(
    conversions_a: int, visitors_a: int,
    conversions_b: int, visitors_b: int,
    prior_alpha: float = 1.0,
    prior_beta: float = 1.0,
    n_samples: int = 100_000
) -> dict:
    """Bayesian A/B test using Beta-Binomial model."""

    # Posterior distributions
    alpha_a = prior_alpha + conversions_a
    beta_a = prior_beta + visitors_a - conversions_a

    alpha_b = prior_alpha + conversions_b
    beta_b = prior_beta + visitors_b - conversions_b

    # Sample from posteriors
    samples_a = stats.beta(alpha_a, beta_a).rvs(n_samples)
    samples_b = stats.beta(alpha_b, beta_b).rvs(n_samples)

    # P(B > A)
    prob_b_wins = (samples_b > samples_a).mean()

    # Expected lift
    lift_samples = (samples_b - samples_a) / samples_a
    expected_lift = lift_samples.mean()
    lift_ci = np.percentile(lift_samples, [2.5, 97.5])

    # Credible intervals
    ci_a = np.percentile(samples_a, [2.5, 97.5])
    ci_b = np.percentile(samples_b, [2.5, 97.5])

    return {
        'prob_b_wins': prob_b_wins,
        'expected_lift': expected_lift,
        'lift_ci_95': tuple(lift_ci),
        'rate_a_mean': samples_a.mean(),
        'rate_a_ci_95': tuple(ci_a),
        'rate_b_mean': samples_b.mean(),
        'rate_b_ci_95': tuple(ci_b)
    }

# Example: A=50/1000, B=72/1000
result = bayesian_ab_test(50, 1000, 72, 1000)
# {
#   'prob_b_wins': 0.964,  # 96.4% chance B is better
#   'expected_lift': 0.42,  # Expected 42% improvement
#   'lift_ci_95': (0.05, 0.91),  # 95% credible interval for lift
#   'rate_a_mean': 0.051,
#   'rate_a_ci_95': (0.038, 0.066),
#   'rate_b_mean': 0.073,
#   'rate_b_ci_95': (0.057, 0.090)
# }
```

### Decision Rules

| P(B > A) | Interpretation | Action |
|----------|----------------|--------|
| > 95% | Very likely B is better | Deploy B |
| 80-95% | Probably B is better | Continue testing or deploy B |
| 50-80% | Uncertain | Need more data |
| < 50% | A might be better | Reconsider or test longer |

Also consider:
- **Minimum practical lift**: Is expected lift worth the change?
- **Downside risk**: What's P(B < A by more than 5%)?

```python
def practical_significance(samples_a, samples_b, min_lift=0.05):
    """Check if B is meaningfully better (not just statistically)."""
    lift = (samples_b - samples_a) / samples_a

    prob_b_better = (samples_b > samples_a).mean()
    prob_meaningful = (lift > min_lift).mean()
    prob_harmful = (lift < -min_lift).mean()

    return {
        'prob_b_better': prob_b_better,
        'prob_meaningful_lift': prob_meaningful,  # P(lift > 5%)
        'prob_harmful': prob_harmful,  # P(lift < -5%)
    }
```

### Informative Priors

If you have historical data, use it:

```python
# Historical: 5% conversion rate, ~1000 conversions observed
# This gives prior "strength" of about 1000 observations
prior_alpha = 50  # Expected conversions
prior_beta = 950  # Expected non-conversions

# Now new data updates from this starting point
# Less susceptible to early noise
```

---

## Multi-Armed Bandits

### Thompson Sampling

Continuously allocate traffic to likely winner:

```python
import numpy as np
from scipy import stats

class ThompsonSamplingBandit:
    def __init__(self, n_arms: int = 2, prior_alpha=1, prior_beta=1):
        self.n_arms = n_arms
        self.alphas = [prior_alpha] * n_arms  # Successes + prior
        self.betas = [prior_beta] * n_arms    # Failures + prior

    def select_arm(self) -> int:
        """Sample from each arm's posterior, pick highest."""
        samples = [
            stats.beta(self.alphas[i], self.betas[i]).rvs()
            for i in range(self.n_arms)
        ]
        return int(np.argmax(samples))

    def update(self, arm: int, reward: int):
        """Update posterior after observing reward (0 or 1)."""
        if reward == 1:
            self.alphas[arm] += 1
        else:
            self.betas[arm] += 1

    def get_allocation_probs(self, n_simulations: int = 10000) -> list:
        """Estimate current probability each arm would be selected."""
        selections = [self.select_arm() for _ in range(n_simulations)]
        return [selections.count(i) / n_simulations for i in range(self.n_arms)]

    def get_win_probs(self, n_samples: int = 100000) -> list:
        """Probability each arm is actually the best."""
        samples = np.array([
            stats.beta(self.alphas[i], self.betas[i]).rvs(n_samples)
            for i in range(self.n_arms)
        ])
        best = samples.argmax(axis=0)
        return [np.mean(best == i) for i in range(self.n_arms)]

# Usage
bandit = ThompsonSamplingBandit(n_arms=2)

# Simulate traffic
for user in range(1000):
    arm = bandit.select_arm()  # 0 = A, 1 = B

    # Simulate conversion (true rates: A=5%, B=7%)
    true_rates = [0.05, 0.07]
    converted = np.random.random() < true_rates[arm]

    bandit.update(arm, int(converted))

# After 1000 users:
print(bandit.get_win_probs())  # e.g., [0.12, 0.88] → B likely winner
print(bandit.get_allocation_probs())  # e.g., [0.15, 0.85] → Mostly showing B
```

### When to Use Bandits

**Good for**:
- Continuous optimization (not one-off tests)
- High opportunity cost of showing inferior variant
- Many variants (A/B/C/D...)
- You value conversion during the test

**Not good for**:
- Need clean causal inference
- Reporting to stakeholders expecting traditional stats
- Regulatory requirements for fixed protocols

### Epsilon-Greedy (Simpler Alternative)

```python
class EpsilonGreedyBandit:
    def __init__(self, n_arms: int = 2, epsilon: float = 0.1):
        self.n_arms = n_arms
        self.epsilon = epsilon
        self.successes = [0] * n_arms
        self.trials = [0] * n_arms

    def select_arm(self) -> int:
        if np.random.random() < self.epsilon:
            return np.random.randint(self.n_arms)  # Explore
        else:
            rates = [
                self.successes[i] / max(self.trials[i], 1)
                for i in range(self.n_arms)
            ]
            return int(np.argmax(rates))  # Exploit

    def update(self, arm: int, reward: int):
        self.trials[arm] += 1
        if reward:
            self.successes[arm] += 1
```

---

## Choosing Your Method

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DECISION FLOWCHART                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   "Must control false positive rate strictly?"                      │
│            │                                                        │
│       Yes ─┴─ No                                                    │
│        │      │                                                     │
│        ▼      ▼                                                     │
│   FREQUENTIST   "Need to peek at results during test?"              │
│                        │                                            │
│                   Yes ─┴─ No                                        │
│                    │      │                                         │
│                    ▼      ▼                                         │
│                 BAYESIAN  "Optimizing during test matters?"         │
│                                  │                                  │
│                             Yes ─┴─ No                              │
│                              │      │                               │
│                              ▼      ▼                               │
│                           BANDIT   BAYESIAN (or Frequentist)        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Recommendation by Scenario

| Scenario | Method |
|----------|--------|
| First A/B test, unsure | Frequentist (well understood) |
| Regular testing, want flexibility | Bayesian |
| High-traffic, many variants | Bandit |
| Stakeholders want "statistical significance" | Frequentist |
| Want to stop early if clear winner | Bayesian |
| Personalization (best variant per segment) | Contextual Bandit |

---

## Common Pitfalls

### 1. Peeking (Frequentist)

**Problem**: Checking p-values daily inflates false positive rate to ~30%.

**Solutions**:
- Pre-specify sample size, analyze once
- Use sequential testing with alpha spending
- Switch to Bayesian (peeking is fine)

### 2. Underpowered Tests

**Problem**: Small sample → can't detect real effects → "no significant difference" → wrong conclusion.

**Solution**: Always calculate required sample size upfront.

### 3. Multiple Comparisons

**Problem**: Testing 10 variants = ~40% chance of false positive.

**Solution**: Bonferroni correction (α/n) or use Bayesian model that naturally handles multiplicity.

### 4. Novelty/Primacy Effects

**Problem**: New design seems better initially (novelty), or old design wins because users learned it (primacy).

**Solution**: Run tests for 2+ weeks, segment by new vs returning users.

### 5. Segment Paradox (Simpson's Paradox)

**Problem**: B wins overall, but A wins in every segment.

**Example**:
```
Desktop:  A=10% (9000 users), B=12% (1000 users)  → B wins
Mobile:   A=2% (1000 users),  B=3% (9000 users)   → B wins
Overall:  A=9.2%, B=3.9%  → A wins!
```

**Solution**: Always analyze by segments (device, geo, traffic source).

### 6. Stopping Too Early

**Problem**: "B is winning at 90% after 100 visitors!" — likely noise.

**Rule of thumb**: Minimum 1000 conversions total, or 2 weeks, whichever is longer.

---

## Implementation Code

### Full TypeScript/JavaScript Implementation

```typescript
// lib/ab-stats.ts

interface ABResult {
  rateA: number
  rateB: number
  lift: number
  probBWins: number
  liftCI: [number, number]
  sampleSizeReached: boolean
  recommendation: 'A' | 'B' | 'continue'
}

export function analyzeBayesian(
  conversionsA: number,
  visitorsA: number,
  conversionsB: number,
  visitorsB: number,
  minSamplePerVariant: number = 1000
): ABResult {
  const rateA = conversionsA / visitorsA
  const rateB = conversionsB / visitorsB
  const lift = (rateB - rateA) / rateA

  // Monte Carlo for P(B > A) and credible interval
  const nSamples = 50000
  const samplesA = betaSample(1 + conversionsA, 1 + visitorsA - conversionsA, nSamples)
  const samplesB = betaSample(1 + conversionsB, 1 + visitorsB - conversionsB, nSamples)

  const liftSamples = samplesB.map((b, i) => (b - samplesA[i]) / samplesA[i])
  const probBWins = samplesB.filter((b, i) => b > samplesA[i]).length / nSamples

  const sortedLift = [...liftSamples].sort((a, b) => a - b)
  const liftCI: [number, number] = [
    sortedLift[Math.floor(nSamples * 0.025)],
    sortedLift[Math.floor(nSamples * 0.975)]
  ]

  const sampleSizeReached = visitorsA >= minSamplePerVariant && visitorsB >= minSamplePerVariant

  let recommendation: 'A' | 'B' | 'continue' = 'continue'
  if (sampleSizeReached) {
    if (probBWins > 0.95) recommendation = 'B'
    else if (probBWins < 0.05) recommendation = 'A'
  }

  return { rateA, rateB, lift, probBWins, liftCI, sampleSizeReached, recommendation }
}

// Simple beta sampling using Box-Muller and inverse transform
function betaSample(alpha: number, beta: number, n: number): number[] {
  // Using scipy-style sampling would require a library
  // For production, use jstat, stdlib, or call Rust-WASM
  const samples: number[] = []
  for (let i = 0; i < n; i++) {
    samples.push(betaRandom(alpha, beta))
  }
  return samples
}

function betaRandom(alpha: number, beta: number): number {
  // Gamma sampling for beta distribution
  const x = gammaRandom(alpha)
  const y = gammaRandom(beta)
  return x / (x + y)
}

function gammaRandom(shape: number): number {
  // Marsaglia and Tsang's method
  if (shape < 1) {
    return gammaRandom(1 + shape) * Math.pow(Math.random(), 1 / shape)
  }

  const d = shape - 1/3
  const c = 1 / Math.sqrt(9 * d)

  while (true) {
    let x: number, v: number
    do {
      x = randn()
      v = 1 + c * x
    } while (v <= 0)

    v = v * v * v
    const u = Math.random()

    if (u < 1 - 0.0331 * (x * x) * (x * x)) return d * v
    if (Math.log(u) < 0.5 * x * x + d * (1 - v + Math.log(v))) return d * v
  }
}

function randn(): number {
  // Box-Muller transform
  const u1 = Math.random()
  const u2 = Math.random()
  return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2)
}
```

### Rust-WASM (High Performance)

See [RUST-WASM.md](RUST-WASM.md) for optimized statistical functions.
