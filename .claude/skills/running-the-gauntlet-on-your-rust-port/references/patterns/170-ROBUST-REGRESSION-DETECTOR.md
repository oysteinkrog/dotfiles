# Pattern 170 — Robust Regression Detector

## What

The regression detector uses *median + MAD* (Median Absolute Deviation) rather than *mean + stddev* to compute baselines and severities. Robust statistics are distribution-free and outlier-resistant; mean/stddev assume normality that benchmark distributions routinely violate (heavy-tailed, bimodal, GC-induced spikes). The detector emits latency-ratio, throughput-drop, and robust-z-score signals against per-metric default tolerance bands with `warning` and `critical` severities. Waivers are *structured, dated, severity-bounded* — no invisible exceptions; an active waiver expires unless renewed.

## Why

MAD is distribution-free and outlier-robust. Unlike stddev, doesn't assume normality. Bench distributions are often heavy-tailed (occasional GC pause, scheduler hiccup, fsync stall) or bimodal (warm vs cold cache); a single tail iteration destroys mean-based detection.

Failure mode prevented: false-positive regression alerts triggered by single-iteration outliers, masking real regressions behind alert fatigue; or false-negative greens when a mean-based detector smooths over a real shift because a balancing outlier in the other direction canceled it out.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/performance_regression_detector.rs` — the detector implementation.
- Consumed by: `.github/workflows/verification-gates.yml`, `scripts/apply-ratchet.sh`.
- Waiver records: `docs/perf-waivers/<bench>__<scenario>__<expiry>.toml`.

## Verbatim shape

### BenchmarkSample

```rust
pub struct BenchmarkSample {
    pub scenario: String,
    pub run_id: String,
    pub git_sha: String,
    pub seed: u64,
    pub p50_ms: f64,
    pub p95_ms: f64,
    pub p99_ms: f64,
    pub throughput: f64,
    pub host_id: String,
    pub params_hash: String,
}
```

### Robust statistics

```
Median(p50_samples) as baseline
MAD = Median(|sample - median|) as spread
```

### Checks

- Latency ratio: `candidate_p50 / baseline_p50`
- Throughput drop ratio: `(baseline_throughput - candidate_throughput) / baseline_throughput`
- Robust z-score: `(candidate - median_baseline) / (1.4826 * MAD_baseline)`
- Confidence (1 − tail prob under robust assumption)
- Severity: `warning | critical`

### Default tolerance table

| Metric | Warning | Critical |
|--------|---------|----------|
| Latency ratio | 1.10x | 1.25x |
| Throughput drop | −10% | −20% |

These pair with the absolute ratchet thresholds ([pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md)): the ratchet thresholds gate at commit time; the detector severities surface as PR-level warnings well before a regression reaches the ratchet wall.

### Structured waivers (no invisible exceptions)

A waiver is a TOML file:

```toml
[waiver]
bench = "mt_oltp_bench"
scenario = "writer_4__reader_8__txn_oltp"
metric = "p99_latency"
severity = "warning"
opened = "2026-04-10"
expires = "2026-05-10"
rationale = "Pending bd-1dp9.7.4 group-commit redesign"
owner = "agent:cc_2"
linked_bead = "bd-1dp9.7.4"
```

`scripts/apply-ratchet.sh` parses waivers, applies them only within their bounds, and emits a separate `waivers_active.json` artifact so dashboards can show "you have 3 active waivers, none about to expire." Expired waivers stop suppressing the alert immediately; no grace.

## Per-class instantiation

| Class | Primary detector signal | Per-class tolerance overrides |
|---|---|---|
| SQL | `p99_latency` ratio on `mt_oltp_bench`; throughput on `mt_mvcc_bench` | Defaults. |
| RESP | RPS throughput drop on `pipeline_throughput_bench`; p99 on `pubsub_fanout_bench` | Defaults. |
| Numerical-Python | per-ufunc median latency; allocation-rate counter | Allocation counter critical at 1.50x (RSS-sensitive workloads). |
| ML-System | per-op median latency; `gradcheck_max_rel_error` for correctness-adjacent perf | `gradcheck_max_rel_error` warning at 1.5x baseline, critical at 3x. |
| HTTP-Protocol | p99 latency under concurrent load; p50 under nominal load | Concurrent p99 critical at 1.30x (HTTP tails inherently noisier). |

Per-class adapters live in `crates/{c}-harness/src/regression_detector_adapter.rs` and override only the *default tolerance table*; the median + MAD discipline is class-invariant.

## Composition

- [pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md) — provides the baseline file the detector reads.
- [pattern:165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md) — paired with the detector to ensure same-window evidence.
- [pattern:125-COMPREHENSIVE-BENCH](125-COMPREHENSIVE-BENCH.md) — the per-sample cv_pct from the bench feeds the detector's `host_id` + iteration-noise context.
- [pattern:150-PROFILE-FIRST-CARD](150-PROFILE-FIRST-CARD.md) — the card's "fallback trigger" field cites detector severity (e.g., "auto-revert if mt-mvcc p99 ratio > 1.25 critical").
- [pattern:80-BOCPD-REGIME-DETECTION](80-BOCPD-REGIME-DETECTION.md) — BOCPD operates on the *stream* of detector outputs to identify regime shifts (Stable / Improving / Regressing / ShiftDetected); the detector is per-pair, BOCPD is per-stream.
- [pattern:175-CONCURRENT-MODE-GUARD](175-CONCURRENT-MODE-GUARD.md) — detector skips samples whose guard file shows a non-default mode; mixing modes invalidates comparison.

## Pitfalls

- **Switching to mean + stddev because "MAD is unfamiliar"** — defeats the whole point. The variance / cv_pct fields in the bench JSON are reference; the detector uses median + MAD.
- **Using a single sample as baseline** — both mean and median are undefined on n=1; the detector requires ≥3 baseline samples. Refuses to score otherwise.
- **`MAD = 0`** — happens when all samples are identical (often integer rates). Use `MAD = max(MAD, smallest_positive_delta)` so the z-score doesn't divide by zero.
- **Tolerating a `warning` without recording a waiver** — warnings accumulate; without expiry they become "the new normal" and the next regression rides through unflagged. Every warning needs a waiver or a fix.
- **Waivers without `expires`** — eternal exceptions. Validator refuses to load waiver TOMLs missing `expires`.
- **Waiver scope too broad (`bench = "*"`)** — masks unrelated regressions. Waivers must specify bench + scenario + metric explicitly.
- **Treating critical severity as auto-block** — the ratchet decision is the auto-block; the detector severity is the *signal*. Critical without ratchet-block means "this happened, investigate"; critical with ratchet-block means "the PR cannot merge."
- **Detector reading from `.bench-history/` files with different `schema_version`** — silently misaligned fields; results meaningless. Validator must check.
- **Computing detector statistics on `mean_ms` instead of `median_ms`** — the bench reports both; detector consumes the median.
- **Per-iteration outlier removal *inside* the detector** — the detector is supposed to be outlier-robust by construction; removing outliers first is double-application and biases.
- **Forgetting to record `params_hash`** — two runs with different scenario parameters compared as if equal. The hash is the audit; mismatched hashes ⇒ different baselines, not different builds.
