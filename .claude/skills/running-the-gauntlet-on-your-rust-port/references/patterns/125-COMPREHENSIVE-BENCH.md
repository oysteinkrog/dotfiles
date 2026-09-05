# Pattern 125 — Comprehensive Bench

## What

A single, large, parameterized benchmark binary per port that exercises three orthogonal axes (workload size × value shape × concurrency), spans six weighted scenario categories, emits one self-describing JSON v3 report per run, and is the primary score the project's keep gate keys off of. Six timing constants (`WARMUP_ITERS`, `MIN_ITERS`, `MAX_ITERS`, `TARGET_DURATION`) are *hard* — not flags, not env vars. The `measure()` and `measure_with_teardown()` bodies are *hard* — no per-scenario timing custom code. Every run drops a per-environment fingerprint plus a per-category weighted score; the regression gate consults the same JSON the dashboard does.

## Why

> "Both engines get identical PRAGMAs. This is a 30-line block at `comprehensive_bench.rs:502–541`, not a verbal convention." — MINING-3 §1.5

Failure mode prevented: hand-rolled per-scenario benches with drift in warmup count, in iteration count, in PRAGMA / config defaults, in timing methodology (mean vs median, p95 vs p99). The comprehensive bench is the *one* place these decisions live; every scenario inherits them by being a closure handed to `measure()`. A change to the methodology is a single edit, audited by `git log` against one file.

## Where in FrankenSQLite

- `crates/fsqlite-e2e/src/bin/comprehensive_bench.rs` (6,040 LOC).
- PRAGMA block: lines `502–541`.
- Six timing constants: lines `49–52`.
- `release-perf` profile invocation contract: see [pattern:140-RELEASE-PERF-PROFILE](140-RELEASE-PERF-PROFILE.md).

## Verbatim shape

### Six timing constants (CC.md lines 49–52)

```rust
const WARMUP_ITERS: usize = 2;
const MIN_ITERS:    usize = 3;
const MAX_ITERS:    usize = 10;
const TARGET_DURATION: Duration = Duration::from_secs(5);
```

Warmup-2 discards cold-start. MIN_ITERS=3 is the statistical minimum for median / cv_pct. MAX_ITERS=10 with TARGET=5s lets fast scenarios finish quickly and slow scenarios still bound wall time. These are hard constants by design — every scenario shares them.

### `measure()` body (verbatim)

```rust
fn measure<F>(label: &str, f: F) -> Measurement where F: Fn() -> () {
    for w in 0..WARMUP_ITERS { f(); }              // 1) WARMUP, discarded
    let start_total = Instant::now();
    let mut times = vec![];
    for iter in 0..MAX_ITERS {
        let start = Instant::now();
        f();
        let elapsed = start.elapsed();
        times.push(elapsed);
        let total_elapsed = start_total.elapsed();
        if iter >= MIN_ITERS && total_elapsed >= TARGET_DURATION { break; }
    }
    Measurement { /* median, mean, p95, p99, stddev, cv_pct, rows/sec, us/row */ }
}
```

`Measurement` always emits *median* (not mean) as the primary statistic, plus p95, p99, stddev, cv_pct. The mean is reported for cross-reference but never gates.

### Three orthogonal axes

1. **Workload size:** `[100, 1_000, 10_000, 100_000]` rows; `--quick` drops 100K to fit a 5-minute smoke run.
2. **Value shape:** `Tiny` (1 col), `Small` (3 cols ≈30 B), `Medium` (6 cols ≈180 B), `Large` (10 cols ≈600 B with overflow).
3. **Concurrency:** `[2, 4, 8]` in comprehensive; `[1, 2, 4, 8, 16]` in `mt_mvcc_bench`.

### Six weighted scenario categories

```
ReadSingle        0.35
ReadAggregate     0.15
WriteSingle       0.30
WriteBulk         0.10
ConcurrentWriters 0.05
MixedOltp         0.05
```

Weights must sum to exactly 1.0; the CI regression gate keys off `per_category_weighted.score`, not raw average.

### JSON v3 self-describing report

```jsonc
{
  "schema_version": "fsqlite-e2e.comprehensive-bench-report.v3",
  "detected_environment": {
    "os": "Linux", "arch": "x86_64", "cpu_count": 64, "cpu_model": "...",
    "kernel": "...", "rustc_version": "...", "cargo_version": "...",
    "git_sha": "...", "cargo_profile": "release-perf", "feature_flags": "..."
  },
  "summary": {
    "total_scenarios": 93,
    "fsqlite_faster": 78, "comparable": 3, "csqlite_faster": 12,
    "average_ratio": 0.5048, "geomean_ratio": 0.2757, "median_ratio": 0.2971,
    "p90_ratio": 1.0855, "p99_ratio": 3.3268,
    "per_category_weighted": { "score": 0.3792, "weights": {...} }
  },
  "ci_regression_gate": {
    "schema_version": "fsqlite-e2e.comprehensive-bench-ci-regression-gate.v2",
    "primary_score_max_regression_pct": 0.03,
    "geomean_max_regression_pct": 0.05,
    "category_geomean_max_regression_pct": 0.10,
    "p90_max_regression_pct": 0.15
  },
  "sections": [{
    "section_id": "...", "title": "...",
    "rows": [{
      "scenario_id": "...", "scenario": "...", "category": "ReadSingle",
      "csqlite": {"median_ms":..., "p95_ms":..., "p99_ms":..., "cv_pct":..., "rows_per_sec":..., "us_per_row":..., "iterations":...},
      "fsqlite": { /* same shape */ },
      "ratio": 0.XX, "winner": "fsqlite"
    }]
  }]
}
```

The report is *self-describing*: `schema_version` lets downstream tools branch on it; `detected_environment` records everything needed to reproduce; `ci_regression_gate` carries the gate thresholds *in* the artifact so a future agent reading only the artifact knows the contract.

### Identical PRAGMAs / config

The 30-line block at `comprehensive_bench.rs:502–541` applies identical PRAGMAs to both engines. *Verbal convention is forbidden*: if you cannot grep for the line that sets it, both sides aren't actually getting it.

## Per-class instantiation

| Class | Scenario categories (must sum to 1.0) | Comparator-side identity |
|---|---|---|
| SQL | ReadSingle 0.35, ReadAggregate 0.15, WriteSingle 0.30, WriteBulk 0.10, ConcurrentWriters 0.05, MixedOltp 0.05 | Identical PRAGMAs block |
| RESP | GET 0.20, SET 0.15, MGET/MSET 0.10, HASH 0.10, LIST 0.10, ZSET 0.15, STREAM 0.10, PUBSUB 0.05, EXPIRE 0.05 | Identical `redis.conf` (maxmemory, AOF mode, RESP version) |
| Numerical-Python | UfuncElementwise 0.30, Reduction 0.20, ShapeTransform 0.10, Linalg 0.15, FFT 0.10, RNG 0.10, IO 0.05 | Identical BLAS thread count, identical RNG bit-generator |
| ML-System | ForwardSmall 0.15, ForwardLarge 0.15, Backward 0.20, OptimStep 0.10, Transformer 0.20, DataLoader 0.10, Distributed 0.10 | Identical determinism flags (`use_deterministic_algorithms(True)`), identical dtype policy |
| HTTP-Protocol | RouteMatch 0.20, Extractor 0.15, Validation 0.20, OpenApiGen 0.10, Middleware 0.15, ConcurrentRequests 0.15, Streaming 0.05 | Identical worker count, identical keep-alive, identical TLS off / on |

Each class's primary score is `per_category_weighted.score` (the headline number the regression gate gates on).

## Composition

- [pattern:135-MEASURE-WITH-TEARDOWN](135-MEASURE-WITH-TEARDOWN.md) — for scenarios with setup-per-iter, use the teardown-outside variant; teardown must never be in the timed window.
- [pattern:140-RELEASE-PERF-PROFILE](140-RELEASE-PERF-PROFILE.md) — comprehensive-bench is *only* meaningful under `--profile release-perf`. Plain `--release` is forbidden.
- [pattern:130-FOCUSED-BENCHES](130-FOCUSED-BENCHES.md) — broad gates point at categories; focused benches isolate one sub-phase. Both must pass in the same window (K-4).
- [pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md) — `summary.per_category_weighted.score` is the primary number tracked in `.bench-history/comprehensive_bench.latest.json`.
- [pattern:165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md) — the broad-gate half of the same-run-window rule.
- [pattern:175-CONCURRENT-MODE-GUARD](175-CONCURRENT-MODE-GUARD.md) — every artifact lane drops a default-mode guard file alongside the bench JSON.
- [pattern:145-HOT-PATH-COUNTERS](145-HOT-PATH-COUNTERS.md) — `HotPathProfileSnapshot` is captured under the same `release-perf` build during a representative subset of scenarios.

## Pitfalls

- **Changing `WARMUP_ITERS` per-scenario to "tune"** — defeats methodological consistency; constants are hard. Tuning belongs in scenario design, not in the timer.
- **Reporting mean instead of median** — mean is destroyed by a single tail iteration. The primary statistic is median; mean is reference-only.
- **Splitting the PRAGMA block into per-scenario applications** — drift becomes invisible. One block, one location, both engines.
- **Dropping `cv_pct` to "clean up the report"** — `cv_pct > 5` is the noise-disqualification trigger ([pattern:160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md)). Without it, noise looks like signal.
- **Adding a 7th scenario category with weight 0.05 without renormalizing** — sum != 1.0 invalidates the per-category score. Renormalize and bump `parity_score_contract` version.
- **Embedding the scenario closure with `f: Fn() -> Result<...>`** — `measure()` takes `Fn() -> ()`; a `Result` swallows the error inside the timed window. Convert to panic-on-error inside `f`; correctness divergences belong in the oracle harness, not the bench.
- **Reading `detected_environment` from `env::var` *inside* a measured iteration** — adds 3× `env::var` overhead (see [pattern:230-ENABLED-LEVEL-TRACING-GATE](230-ENABLED-LEVEL-TRACING-GATE.md)). Capture once at startup.
- **Re-using the same `Connection` / client / process across iterations without explicit warmup of the pool** — first iteration shows cold-start latency masked as "the new baseline". Always discard warmup; never reuse warmup time.
- **`--release` instead of `--profile release-perf`** — size-optimized release strips frame pointers, kills flamegraphs, changes LTO. The bench number is from a different binary than the profile.
- **Forgetting to emit `feature_flags`** — two benches with different cargo features produce different scores; without the flags field, the regression gate can't reject the comparison.
