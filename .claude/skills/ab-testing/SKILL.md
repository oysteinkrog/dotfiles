---
name: ab-testing
description: >-
  Build home-rolled A/B testing platform for Next.js 16 SaaS. Server-side variant
  assignment, GA4/GTM tracking, Bayesian analysis, Rust-WASM stats, contextual bandits.
  Use when: A/B test, experiment, variant, conversion optimization, or personalization.
---

# A/B Testing Platform for SaaS

> **Stack**: Next.js 16 + Edge Middleware + GA4/GTM + Supabase + Rust-WASM (for stats)
> **Why DIY?**: Google Optimize sunset Sept 2023. GA4 has no native A/B testing.

## Quick Start

```tsx
// middleware.ts - Server-side assignment (no flicker)
import { NextResponse, type NextRequest } from 'next/server'

export function middleware(request: NextRequest) {
  const response = NextResponse.next()

  if (!request.cookies.get('exp_hero')) {
    const variant = Math.random() < 0.5 ? 'A' : 'B'
    response.cookies.set('exp_hero', variant, { maxAge: 60*60*24*30, path: '/' })
  }

  return response
}
```

```tsx
// Track with GA4
window.dataLayer?.push({
  event: 'experiment_view',
  experiment_name: 'hero_test',
  experiment_variant: variant
})
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         A/B TESTING FLOW                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   1. ASSIGN (Edge Middleware)                                       │
│   ══════════════════════════                                        │
│   Request → Check cookie → Random assign → Set cookie → Response    │
│   ✓ No flicker (server-side)  ✓ Consistent (cookie-based)          │
│                                                                     │
│   2. RENDER                                                         │
│   ═════════                                                         │
│   Server/Client Component → Read cookie → Show variant              │
│                                                                     │
│   3. TRACK (GTM + GA4)                                              │
│   ════════════════════                                              │
│   dataLayer.push → GTM triggers → GA4 events with variant param     │
│                                                                     │
│   4. ANALYZE                                                        │
│   ═════════                                                         │
│   GA4 Explorations OR Supabase + Rust-WASM Bayesian analysis        │
│                                                                     │
│   5. PERSONALIZE (Advanced)                                         │
│   ═════════════════════════                                         │
│   Contextual bandit → Best variant per user segment                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Workflow

- [ ] 1. Define experiment config (name, variants, weight, segment rules)
- [ ] 2. Implement middleware assignment (see [VARIANT-ASSIGNMENT.md](references/VARIANT-ASSIGNMENT.md))
- [ ] 3. Wire up GTM tracking (experiment_view, conversions with variant param)
- [ ] 4. Register `experiment_variant` as Custom Dimension in GA4
- [ ] 5. Collect data (minimum 2 weeks for weekly patterns)
- [ ] 6. Analyze significance (see [STATISTICAL-ANALYSIS.md](references/STATISTICAL-ANALYSIS.md))
- [ ] 7. Roll out winner or iterate

---

## Statistical Methods (Choose One)

| Method | Best For | Decision Output |
|--------|----------|-----------------|
| **Frequentist** | Fixed sample, strict control | p-value < 0.05 → significant |
| **Bayesian** | Continuous monitoring, intuitive | P(B > A) = 96% → B likely better |
| **Multi-Armed Bandit** | Optimize during test | Auto-shift traffic to winner |
| **Contextual Bandit** | Personalization | Best variant per user segment |

**Quick Bayesian (Beta-Binomial)**:
```python
# A: 50/1000 conversions, B: 72/1000
import scipy.stats as stats
a_samples = stats.beta(51, 951).rvs(100000)  # Beta(1+50, 1+950)
b_samples = stats.beta(73, 929).rvs(100000)  # Beta(1+72, 1+928)
p_b_wins = (b_samples > a_samples).mean()     # → ~0.96 (96%)
```

**Full analysis guide**: [STATISTICAL-ANALYSIS.md](references/STATISTICAL-ANALYSIS.md)

---

## Key Patterns

### Multiple Concurrent Experiments

```tsx
// middleware.ts
const EXPERIMENTS = {
  hero_cta: { weight: 0.5 },
  pricing_layout: { weight: 0.5 },
  signup_flow: { weight: 0.2 },  // 20% on new variant
}

for (const [name, config] of Object.entries(EXPERIMENTS)) {
  if (!request.cookies.get(`exp_${name}`)) {
    const variant = Math.random() < config.weight ? 'B' : 'A'
    response.cookies.set(`exp_${name}`, variant, { maxAge: 2592000, path: '/' })
  }
}
```

### Phased Rollout

```tsx
// Config stored in Supabase or Vercel Edge Config
const rolloutPhases = {
  early_access: 0.1,   // 10% new
  public_beta: 0.5,    // 50% new
  general: 1.0         // 100% new (winner)
}
```

### Tracking Conversions

```tsx
// Include variant in ALL relevant events
window.dataLayer?.push({
  event: 'sign_up',
  method: 'google',
  experiment_name: 'hero_cta',
  experiment_variant: getCookie('exp_hero_cta'),
  eventId: crypto.randomUUID()  // De-duplication
})
```

---

## When to Use Rust-WASM

| Use Case | Why Rust |
|----------|----------|
| Monte Carlo simulation (100k+ draws) | 10-100x faster than JS |
| Bayesian posterior computation | Numerical precision |
| Contextual bandit inference | Real-time ML at edge |
| Cross-platform consistency | Same logic in browser + server |

**WASM is NOT needed for**: Simple random assignment, cookie handling, event tracking

See: [RUST-WASM.md](references/RUST-WASM.md)

---

## Anti-Patterns

| Don't | Why |
|-------|-----|
| Client-side variant assignment | Causes flicker, inconsistent |
| End test early ("B winning after 2 days!") | Random noise, not signal |
| Multiple changes in one variant | Can't isolate what worked |
| Overlapping tests on same element | Interaction effects confound |
| Skip sample size calculation | Under-powered = false negatives |
| Ignore segments | Winner overall may lose for key segment |

---

## Validation Checklist

- [ ] No flicker on page load (verify in slow 3G)
- [ ] Cookie persists across sessions (check 30-day expiry)
- [ ] GTM Preview shows correct variant in dataLayer
- [ ] GA4 DebugView receives events with variant param
- [ ] Custom dimension `experiment_variant` registered in GA4
- [ ] ~50/50 split verified (check GA4 Realtime)
- [ ] Conversion events include variant attribution

---

## Reference Index

### By Task

| I need to... | Read |
|--------------|------|
| **Implement variant assignment** | [VARIANT-ASSIGNMENT.md](references/VARIANT-ASSIGNMENT.md) |
| **Choose a statistical method** | [STATISTICAL-ANALYSIS.md](references/STATISTICAL-ANALYSIS.md) |
| **Set up GTM/GA4 tracking** | [GA4-GTM-TRACKING.md](references/GA4-GTM-TRACKING.md) |
| **Build admin dashboard** | [ADMIN-DASHBOARD.md](references/ADMIN-DASHBOARD.md) |
| **Add personalization/bandits** | [PERSONALIZATION.md](references/PERSONALIZATION.md) |
| **Optimize with Rust-WASM** | [RUST-WASM.md](references/RUST-WASM.md) |
| **Quick lookup (tools, formulas)** | [QUICK-REFERENCE.md](references/QUICK-REFERENCE.md) |

### By Topic

| Topic | Reference |
|-------|-----------|
| Server-side assignment, multiple experiments, weighted splits | [VARIANT-ASSIGNMENT.md](references/VARIANT-ASSIGNMENT.md) |
| Frequentist vs Bayesian vs Bandits, sample size, pitfalls | [STATISTICAL-ANALYSIS.md](references/STATISTICAL-ANALYSIS.md) |
| GTM variables, GA4 events, BigQuery queries, debugging | [GA4-GTM-TRACKING.md](references/GA4-GTM-TRACKING.md) |
| Database schema, API routes, UI components, real-time updates | [ADMIN-DASHBOARD.md](references/ADMIN-DASHBOARD.md) |
| Segments, rules-based, Thompson sampling, contextual bandits | [PERSONALIZATION.md](references/PERSONALIZATION.md) |
| Rust setup, beta sampling, bandit implementation, Next.js integration | [RUST-WASM.md](references/RUST-WASM.md) |
| Tool recommendations, decision guide, formulas, cheat sheet | [QUICK-REFERENCE.md](references/QUICK-REFERENCE.md) |
