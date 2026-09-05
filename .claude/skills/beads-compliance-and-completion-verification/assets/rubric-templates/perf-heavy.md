---
rubric_version: "perf-heavy-1.0.0"
threshold: 750
score_threshold: 750
weights_by_type:
  perf:
    implementation: 200
    tests:           150
    anti_theater:    100
    test_depth:      400    # benchmarks ARE the proof
    docs:             50
    integration:     100
  optimization:
    implementation: 200
    tests:           150
    anti_theater:    100
    test_depth:      400
    docs:             50
    integration:     100
weights_by_label:
  hot-path:
    test_depth:     500     # critical paths need exhaustive perf evidence
    integration:    100
---

# Rubric — perf-heavy variant

For latency-sensitive services or projects with many `perf` / `optimization`
beads. Re-weights toward `test_depth` (statistical-significance benchmarks)
and adds explicit per-bead numeric-budget enforcement.

## Default 6 dimensions (apply to non-perf beads)

Same as `assets/rubric-template.md`. See it for the full table.

## Per-type overrides for `perf` / `optimization` beads

| Dimension | perf max | Default | Why |
|-----------|---------:|--------:|-----|
| Implementation | 200 | 300 | Optimizations often surface as small diffs |
| Tests | 150 | 250 | Functional tests less important than benchmarks |
| Anti-theater | 100 | 150 | Bench-as-fake is rare; flag separately |
| **Test depth** | **400** | 150 | Benchmarks dominate — ≥30 samples, paired stats vs prior pass |
| Docs | 50 | 100 | Less |
| Integration | 100 | 50 | Bumped — perf changes ripple |

## Threshold = 750 (vs default 700)

Perf claims that aren't statistically backed are worse than no claim.
The bar is high.

## Hard rules

- Any perf bead claiming a numeric budget (`p95 < 100ms`, etc.) MUST include:
  - ≥30 samples (per `subagents/performance-auditor.md`)
  - Paired statistical test vs the prior pass
  - Environment fingerprint (OS / kernel / CPU / governor)
  - Failure to provide any of these → automatic FAIL on `test_depth` dimension
- Any perf bead WITHOUT a numeric budget in the spec → REJECTED at spec-quality-gate (use `subagents/spec-quality-reviewer.md`)
- Bench feature-flag mismatch (bench uses different features than the prod build) → BLOCKING (Pattern 40 in `references/FAILURE-MODES.md`)

## When to use

- Latency-sensitive service (API, search, DB engine)
- Project with > 20% of beads tagged `perf` / `optimization` / `bench`
- Pre-release perf gate (cutting a version, validating SLO targets)
- Post-incident: a latency regression in production prompted the audit
