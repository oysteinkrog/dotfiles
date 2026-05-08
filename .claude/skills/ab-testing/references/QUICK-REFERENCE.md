# Quick Reference

## Tool Recommendations

| Need | Free Option | Paid Option |
|------|-------------|-------------|
| Variant assignment | Next.js Middleware | - |
| Event tracking | GTM + GA4 | - |
| Config management | Supabase | Vercel Edge Config |
| Statistical analysis | Python/R, Rust-WASM | Statsig, Optimizely |
| Contextual bandits | Custom (complex) | Statsig, VWO |

---

## Decision Guide: DIY vs Platform

### Stay DIY when:
- < 5 concurrent experiments
- Technical team runs tests
- Simple 50/50 splits
- GA4 analysis is sufficient

### Upgrade to platform when:
- Non-technical team needs visual editor
- 5+ concurrent experiments
- Need built-in significance calculations
- Compliance/audit requirements
- > 100k monthly users

---

## Quick Formulas

### Sample Size (per variant)
```
n = 16 × σ² / δ²

Where:
  σ = √(p × (1-p))    # baseline rate variance
  δ = p × lift        # minimum detectable effect
```

### Quick Reference Table
| Baseline Rate | 10% Lift | 20% Lift | 50% Lift |
|---------------|----------|----------|----------|
| 2% | 78,000 | 19,500 | 3,100 |
| 5% | 30,500 | 7,600 | 1,200 |
| 10% | 14,500 | 3,600 | 580 |
| 20% | 6,400 | 1,600 | 260 |

---

## Cookie Naming Convention

```
exp_{page}_{element}_{test_id}
```

Examples:
- `exp_landing_hero_v1`
- `exp_pricing_cta_q1_2024`
- `exp_signup_form_length`
- `exp_checkout_upsell_modal`

---

## Event Schema

```typescript
// All A/B test events include:
interface ABTestEventParams {
  experiment_id: string;      // Unique ID
  experiment_name: string;    // Human-readable
  variant: string;            // A, B, C...
  variant_source: string;     // 'random' | 'rule' | 'bandit'
}

// Event types:
// - experiment_exposure     (user saw variant)
// - experiment_interaction  (click, scroll)
// - experiment_conversion   (primary goal)
// - experiment_goal         (secondary goal)
```

---

## Decision Rules (Bayesian)

| P(B > A) | Interpretation | Action |
|----------|----------------|--------|
| > 95% | Very likely B is better | Deploy B |
| 80-95% | Probably B is better | Continue or deploy B |
| 50-80% | Uncertain | Need more data |
| < 50% | A might be better | Reconsider |

---

## Minimum Requirements Checklist

Before launching any experiment:

- [ ] Sample size calculated (aim for 1000+ per variant)
- [ ] Test runs minimum 2 weeks (weekly patterns)
- [ ] No overlapping tests on same element
- [ ] Only ONE change per variant
- [ ] Primary metric defined
- [ ] Cookie consent handled (functional = OK before consent)

---

## Common CLI Commands

```bash
# Build WASM stats module
wasm-pack build --target bundler --release

# Test with seed for reproducibility
cargo test -- --nocapture

# Size-optimized WASM build
wasm-pack build --target web --release -- --features wee_alloc
```

---

## GTM Variables Needed

| Variable Name | Type | Data Layer Key |
|--------------|------|----------------|
| DLV - Experiment ID | Data Layer Variable | experiment_id |
| DLV - Experiment Name | Data Layer Variable | experiment_name |
| DLV - Variant | Data Layer Variable | variant |
| DLV - Variant Source | Data Layer Variable | variant_source |
| DLV - Event ID | Data Layer Variable | event_id |

---

## BigQuery Quick Query

```sql
-- Conversion rate by variant (last 30 days)
SELECT variant,
  COUNT(DISTINCT CASE WHEN event = 'exposure' THEN user_id END) as exposed,
  COUNT(DISTINCT CASE WHEN event = 'conversion' THEN user_id END) as converted,
  SAFE_DIVIDE(converted, exposed) as rate
FROM experiment_events
WHERE experiment_id = 'your_experiment'
  AND created_at > DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY variant;
```
