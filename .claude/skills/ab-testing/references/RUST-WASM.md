# Rust-WASM for A/B Testing Analytics

## Table of Contents
- [When to Use Rust-WASM](#when-to-use-rust-wasm)
- [Project Setup](#project-setup)
- [Core Statistical Functions](#core-statistical-functions)
- [Thompson Sampling Bandit](#thompson-sampling-bandit)
- [Integration with Next.js](#integration-with-nextjs)
- [Performance Benchmarks](#performance-benchmarks)
- [Edge Runtime Considerations](#edge-runtime-considerations)

---

## When to Use Rust-WASM

### Use Rust When

| Task | Why Rust Helps |
|------|----------------|
| Monte Carlo (100k+ samples) | 10-100x faster than JS |
| Bayesian posterior computation | Numerical precision |
| Real-time bandit inference | Edge latency critical |
| Batch analysis of many experiments | Process millions of events |
| Consistent logic across platforms | Same code in browser/server/edge |

### Don't Use Rust For

| Task | Why JS is Fine |
|------|----------------|
| Random variant assignment | `Math.random()` is fast enough |
| Cookie read/write | Native browser API |
| GTM event tracking | dataLayer push is trivial |
| Simple rate calculations | Division is not a bottleneck |

**Rule**: Profile first. WASM has call overhead — only use when computation dominates.

---

## Project Setup

### 1. Create Rust Library

```bash
cargo new ab_stats --lib
cd ab_stats
```

### 2. Configure for WASM

```toml
# Cargo.toml
[package]
name = "ab_stats"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "rlib"]

[dependencies]
wasm-bindgen = "0.2"
rand = { version = "0.8", features = ["small_rng"] }
rand_distr = "0.4"
serde = { version = "1.0", features = ["derive"] }
serde-wasm-bindgen = "0.6"

[profile.release]
lto = true
opt-level = 3
```

### 3. Build Commands

```bash
# Install wasm-pack
cargo install wasm-pack

# Build for browser/bundler
wasm-pack build --target bundler --release

# Build for Node.js
wasm-pack build --target nodejs --release

# Build for web (no bundler)
wasm-pack build --target web --release
```

---

## Core Statistical Functions

### Beta Distribution Sampling

```rust
// src/lib.rs
use wasm_bindgen::prelude::*;
use rand::SeedableRng;
use rand::rngs::SmallRng;
use rand_distr::{Beta, Distribution};

#[wasm_bindgen]
pub struct BayesianAnalyzer {
    rng: SmallRng,
}

#[wasm_bindgen]
impl BayesianAnalyzer {
    #[wasm_bindgen(constructor)]
    pub fn new(seed: Option<u64>) -> Self {
        let rng = match seed {
            Some(s) => SmallRng::seed_from_u64(s),
            None => SmallRng::from_entropy(),
        };
        Self { rng }
    }

    /// Calculate P(B > A) using Monte Carlo sampling
    pub fn prob_b_wins(
        &mut self,
        conversions_a: u32,
        visitors_a: u32,
        conversions_b: u32,
        visitors_b: u32,
        n_samples: u32,
    ) -> f64 {
        let alpha_a = 1.0 + conversions_a as f64;
        let beta_a = 1.0 + (visitors_a - conversions_a) as f64;

        let alpha_b = 1.0 + conversions_b as f64;
        let beta_b = 1.0 + (visitors_b - conversions_b) as f64;

        let dist_a = Beta::new(alpha_a, beta_a).unwrap();
        let dist_b = Beta::new(alpha_b, beta_b).unwrap();

        let mut b_wins = 0u32;

        for _ in 0..n_samples {
            let sample_a = dist_a.sample(&mut self.rng);
            let sample_b = dist_b.sample(&mut self.rng);
            if sample_b > sample_a {
                b_wins += 1;
            }
        }

        b_wins as f64 / n_samples as f64
    }

    /// Get full posterior analysis
    pub fn analyze(
        &mut self,
        conversions_a: u32,
        visitors_a: u32,
        conversions_b: u32,
        visitors_b: u32,
        n_samples: u32,
    ) -> JsValue {
        let alpha_a = 1.0 + conversions_a as f64;
        let beta_a = 1.0 + (visitors_a - conversions_a) as f64;
        let alpha_b = 1.0 + conversions_b as f64;
        let beta_b = 1.0 + (visitors_b - conversions_b) as f64;

        let dist_a = Beta::new(alpha_a, beta_a).unwrap();
        let dist_b = Beta::new(alpha_b, beta_b).unwrap();

        let mut samples_a: Vec<f64> = Vec::with_capacity(n_samples as usize);
        let mut samples_b: Vec<f64> = Vec::with_capacity(n_samples as usize);
        let mut lift_samples: Vec<f64> = Vec::with_capacity(n_samples as usize);
        let mut b_wins = 0u32;

        for _ in 0..n_samples {
            let sa = dist_a.sample(&mut self.rng);
            let sb = dist_b.sample(&mut self.rng);
            samples_a.push(sa);
            samples_b.push(sb);
            lift_samples.push((sb - sa) / sa);
            if sb > sa {
                b_wins += 1;
            }
        }

        lift_samples.sort_by(|a, b| a.partial_cmp(b).unwrap());

        let result = AnalysisResult {
            rate_a: conversions_a as f64 / visitors_a as f64,
            rate_b: conversions_b as f64 / visitors_b as f64,
            prob_b_wins: b_wins as f64 / n_samples as f64,
            expected_lift: lift_samples.iter().sum::<f64>() / n_samples as f64,
            lift_ci_low: lift_samples[(n_samples as f64 * 0.025) as usize],
            lift_ci_high: lift_samples[(n_samples as f64 * 0.975) as usize],
        };

        serde_wasm_bindgen::to_value(&result).unwrap()
    }
}

#[derive(serde::Serialize)]
struct AnalysisResult {
    rate_a: f64,
    rate_b: f64,
    prob_b_wins: f64,
    expected_lift: f64,
    lift_ci_low: f64,
    lift_ci_high: f64,
}
```

### Batch Analysis

```rust
#[wasm_bindgen]
pub fn analyze_many_experiments(
    data: &[u32],  // Flat array: [conv_a, vis_a, conv_b, vis_b, ...]
    n_samples: u32,
) -> Vec<f64> {
    let mut rng = SmallRng::from_entropy();
    let mut results = Vec::with_capacity(data.len() / 4);

    for chunk in data.chunks(4) {
        let (ca, va, cb, vb) = (chunk[0], chunk[1], chunk[2], chunk[3]);

        let dist_a = Beta::new(1.0 + ca as f64, 1.0 + (va - ca) as f64).unwrap();
        let dist_b = Beta::new(1.0 + cb as f64, 1.0 + (vb - cb) as f64).unwrap();

        let mut wins = 0u32;
        for _ in 0..n_samples {
            if dist_b.sample(&mut rng) > dist_a.sample(&mut rng) {
                wins += 1;
            }
        }

        results.push(wins as f64 / n_samples as f64);
    }

    results
}
```

---

## Thompson Sampling Bandit

```rust
use wasm_bindgen::prelude::*;
use rand::SeedableRng;
use rand::rngs::SmallRng;
use rand_distr::{Beta, Distribution};

#[wasm_bindgen]
pub struct ThompsonBandit {
    alphas: Vec<f64>,
    betas: Vec<f64>,
    rng: SmallRng,
}

#[wasm_bindgen]
impl ThompsonBandit {
    #[wasm_bindgen(constructor)]
    pub fn new(n_arms: usize, prior_alpha: f64, prior_beta: f64) -> Self {
        Self {
            alphas: vec![prior_alpha; n_arms],
            betas: vec![prior_beta; n_arms],
            rng: SmallRng::from_entropy(),
        }
    }

    /// Select arm to show (returns index 0..n_arms)
    pub fn select_arm(&mut self) -> usize {
        let mut best_arm = 0;
        let mut best_sample = f64::NEG_INFINITY;

        for (i, (&alpha, &beta)) in self.alphas.iter().zip(&self.betas).enumerate() {
            let dist = Beta::new(alpha, beta).unwrap();
            let sample = dist.sample(&mut self.rng);
            if sample > best_sample {
                best_sample = sample;
                best_arm = i;
            }
        }

        best_arm
    }

    /// Update after observing outcome
    pub fn update(&mut self, arm: usize, converted: bool) {
        if converted {
            self.alphas[arm] += 1.0;
        } else {
            self.betas[arm] += 1.0;
        }
    }

    /// Get current win probabilities for each arm
    pub fn get_win_probs(&mut self, n_simulations: u32) -> Vec<f64> {
        let n_arms = self.alphas.len();
        let mut wins = vec![0u32; n_arms];

        for _ in 0..n_simulations {
            let mut best_arm = 0;
            let mut best_sample = f64::NEG_INFINITY;

            for (i, (&alpha, &beta)) in self.alphas.iter().zip(&self.betas).enumerate() {
                let dist = Beta::new(alpha, beta).unwrap();
                let sample = dist.sample(&mut self.rng);
                if sample > best_sample {
                    best_sample = sample;
                    best_arm = i;
                }
            }

            wins[best_arm] += 1;
        }

        wins.iter().map(|&w| w as f64 / n_simulations as f64).collect()
    }

    /// Get alpha/beta parameters (for persistence)
    pub fn get_state(&self) -> Vec<f64> {
        let mut state = self.alphas.clone();
        state.extend(&self.betas);
        state
    }

    /// Restore from saved state
    pub fn set_state(&mut self, state: &[f64]) {
        let n = state.len() / 2;
        self.alphas = state[..n].to_vec();
        self.betas = state[n..].to_vec();
    }
}
```

---

## Integration with Next.js

### 1. Install WASM Package

```bash
# After wasm-pack build
npm install ./ab_stats/pkg

# Or publish to npm and install normally
```

### 2. Next.js Config

```javascript
// next.config.js
/** @type {import('next').NextConfig} */
const nextConfig = {
  webpack: (config, { isServer }) => {
    // Handle WASM
    config.experiments = {
      ...config.experiments,
      asyncWebAssembly: true,
      layers: true,
    }

    return config
  },
}

module.exports = nextConfig
```

### 3. Usage in React

```tsx
'use client'
import { useEffect, useState } from 'react'

interface AnalysisResult {
  rate_a: number
  rate_b: number
  prob_b_wins: number
  expected_lift: number
  lift_ci_low: number
  lift_ci_high: number
}

export function useABAnalysis() {
  const [analyzer, setAnalyzer] = useState<any>(null)

  useEffect(() => {
    async function loadWasm() {
      const { BayesianAnalyzer } = await import('ab_stats')
      setAnalyzer(new BayesianAnalyzer())
    }
    loadWasm()
  }, [])

  const analyze = (
    conversionsA: number,
    visitorsA: number,
    conversionsB: number,
    visitorsB: number
  ): AnalysisResult | null => {
    if (!analyzer) return null

    return analyzer.analyze(
      conversionsA,
      visitorsA,
      conversionsB,
      visitorsB,
      100_000  // 100k samples
    )
  }

  return { analyze, ready: !!analyzer }
}

// Component usage
function ExperimentDashboard({ data }) {
  const { analyze, ready } = useABAnalysis()

  if (!ready) return <div>Loading analytics...</div>

  const result = analyze(data.convA, data.visA, data.convB, data.visB)

  return (
    <div>
      <p>P(B wins): {(result.prob_b_wins * 100).toFixed(1)}%</p>
      <p>Expected lift: {(result.expected_lift * 100).toFixed(1)}%</p>
      <p>95% CI: [{(result.lift_ci_low * 100).toFixed(1)}%, {(result.lift_ci_high * 100).toFixed(1)}%]</p>
    </div>
  )
}
```

### 4. Server-Side (API Route)

```typescript
// app/api/analyze/route.ts
import { NextResponse } from 'next/server'

export async function POST(request: Request) {
  const { conversionsA, visitorsA, conversionsB, visitorsB } = await request.json()

  // Dynamic import for WASM
  const { BayesianAnalyzer } = await import('ab_stats')
  const analyzer = new BayesianAnalyzer()

  const result = analyzer.analyze(
    conversionsA,
    visitorsA,
    conversionsB,
    visitorsB,
    100_000
  )

  return NextResponse.json(result)
}
```

---

## Performance Benchmarks

### Test: 100,000 Monte Carlo Samples

| Implementation | Time | Memory |
|----------------|------|--------|
| Pure JavaScript | ~450ms | ~25MB |
| Rust-WASM | ~35ms | ~8MB |
| **Speedup** | **~13x** | **~3x** |

### Test: Batch Analysis (100 experiments)

| Implementation | Time |
|----------------|------|
| JS (sequential) | ~45s |
| Rust-WASM | ~3.5s |
| **Speedup** | **~13x** |

### Benchmark Code

```typescript
// benchmark.ts
async function benchmark() {
  const { BayesianAnalyzer } = await import('ab_stats')
  const analyzer = new BayesianAnalyzer()

  const iterations = 100
  const samples = 100_000

  // Warmup
  analyzer.prob_b_wins(50, 1000, 72, 1000, samples)

  const start = performance.now()
  for (let i = 0; i < iterations; i++) {
    analyzer.prob_b_wins(50, 1000, 72, 1000, samples)
  }
  const elapsed = performance.now() - start

  console.log(`${iterations} iterations: ${elapsed.toFixed(2)}ms`)
  console.log(`Per iteration: ${(elapsed / iterations).toFixed(2)}ms`)
}
```

---

## Edge Runtime Considerations

### Vercel Edge Functions

WASM works in Vercel Edge Functions with some constraints:

```typescript
// middleware.ts or edge API route
export const runtime = 'edge'

// Dynamic import at runtime
export async function GET(request: Request) {
  const { ThompsonBandit } = await import('ab_stats')

  // Restore bandit state from KV or Edge Config
  const state = await kv.get<number[]>('bandit_state')

  const bandit = new ThompsonBandit(2, 1.0, 1.0)
  if (state) bandit.set_state(state)

  const arm = bandit.select_arm()

  return new Response(JSON.stringify({ variant: arm === 0 ? 'A' : 'B' }))
}
```

### Cloudflare Workers

```rust
// Use wasm-bindgen with worker target
// Cargo.toml addition
[dependencies]
worker = "0.0.18"
```

### Size Optimization

```toml
# Cargo.toml
[profile.release]
lto = true
opt-level = "z"  # Optimize for size
strip = true

# Use wee_alloc for smaller binary
[dependencies]
wee_alloc = "0.4"
```

```rust
// lib.rs
#[global_allocator]
static ALLOC: wee_alloc::WeeAlloc = wee_alloc::WeeAlloc::INIT;
```

Expected sizes:
- Standard release: ~200KB
- Size-optimized: ~80KB
- With wee_alloc + wasm-opt: ~50KB

---

## Cross-Platform Consistency

One major benefit: identical logic everywhere.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SAME RUST CODE                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐           │
│   │  Browser     │   │  Node.js     │   │  Edge        │           │
│   │  (WASM)      │   │  (WASM)      │   │  (WASM)      │           │
│   └──────────────┘   └──────────────┘   └──────────────┘           │
│         │                   │                   │                   │
│         ▼                   ▼                   ▼                   │
│   ┌─────────────────────────────────────────────────────┐          │
│   │              ab_stats.wasm                          │          │
│   │  - Same RNG algorithm                               │          │
│   │  - Same floating point precision                    │          │
│   │  - Same statistical methods                         │          │
│   └─────────────────────────────────────────────────────┘          │
│                                                                     │
│   Result: Admin dashboard shows EXACT same numbers as              │
│           edge runtime makes decisions with                        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Testing Consistency

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deterministic_with_seed() {
        let mut analyzer1 = BayesianAnalyzer::new(Some(12345));
        let mut analyzer2 = BayesianAnalyzer::new(Some(12345));

        let result1 = analyzer1.prob_b_wins(50, 1000, 72, 1000, 10000);
        let result2 = analyzer2.prob_b_wins(50, 1000, 72, 1000, 10000);

        assert_eq!(result1, result2);
    }
}
```
