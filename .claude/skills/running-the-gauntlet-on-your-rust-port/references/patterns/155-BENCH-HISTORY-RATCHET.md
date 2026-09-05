# Pattern 155 — Bench-History Ratchet

## What

For every bench (broad + every focused), a single `.bench-history/<bench>.latest.json` file is *committed to git*. The regression detector compares the in-PR bench output against this file; if the headline score regresses beyond named thresholds the PR fails. The file is the gate: an engineer who runs a bench on a workstation, sees a 30% drop, and quietly doesn't commit the file is now *visibly out of date* on the next pass — the gate refuses both the regression and the staleness. Five gate thresholds anchor every comparison, with a sixth (`PASS_OVER_PASS_MAX_RATIO_DROP_PCT = 5.0`) policing throughput-ratio drift across consecutive runs.

## Why

> "Pass-over-pass gate is a *file*. `.bench-history/*.latest.json` is committed. You can't bench on your machine, see a 30% drop, and quietly not commit." — MINING-3 §4

Failure mode prevented: "I'll just re-bench tomorrow" perf entropy. A workstation run that regresses 30% is fine — *if* the file changes and the next pass starts from the new baseline. The git-committed file converts the regression into a *committed* change reviewable in the PR; silently skipping is no longer possible.

## Where in FrankenSQLite

- `.bench-history/comprehensive_bench.latest.json` — broad gate primary.
- `.bench-history/mt-mvcc-bench.latest.json` — MT MVCC focused gate.
- `.bench-history/mt-mvcc-bench.separate-tables.latest.json` — MT MVCC under separate-tables mode.
- `.bench-history/mt-oltp-bench.latest.json`, `.bench-history/perf-update-delete.latest.json`, `.bench-history/swarm-multiprocess.latest.json`.
- `crates/fsqlite-harness/src/perf_loop.rs` — the gate evaluator.

## Verbatim shape

### The 5 gate thresholds

| Metric | Threshold |
|--------|-----------|
| Primary score regression | −3% |
| Geomean regression | −5% |
| Per-category geomean regression | −10% |
| p90 regression | −15% |
| Pass-over-pass throughput drop | −5% |

### Pass-over-pass throughput-ratio constant

```rust
const PASS_OVER_PASS_MAX_RATIO_DROP_PCT: f64 = 5.0;
let ratio_drop_pct = ((previous_ratio - row.throughput_ratio) / previous_ratio) * 100.0;
if ratio_drop_pct > PASS_OVER_PASS_MAX_RATIO_DROP_PCT { /* RatioRegression */ }
```

The 5% pass-over-pass ratio drop is the *fastest-moving* gate. The other 4 thresholds compare against the persisted ratchet baseline; pass-over-pass compares against the *immediately prior* committed run. A bead that drifts 4% per pass for three passes accumulates 12% drift unnoticed by the absolute thresholds; the pass-over-pass gate catches the drift early.

### File schema

The `.bench-history/<bench>.latest.json` file embeds the *full* run JSON v3 plus a `previous_ratchet` block:

```jsonc
{
  "schema_version": "fsqlite-e2e.comprehensive-bench-report.v3",
  "detected_environment": { ... },
  "summary": { "per_category_weighted": { "score": 0.3792, ... }, ... },
  "previous_ratchet": {
    "primary_score": 0.3910,
    "geomean_ratio": 0.2710,
    "p90_ratio": 1.0500,
    "throughput_ratios_by_scenario": { ... }
  },
  "ratchet_decision": { "verdict": "allow" | "block" | "quarantine" | "waiver", "reasons": [...] }
}
```

### Both gates same run window

The pass-over-pass gate is paired with the same-window rule (K-4): focused + broad benches both run from the same `target/`, same machine, same minute. Reading both `.bench-history/comprehensive_bench.latest.json` and `.bench-history/mt-mvcc-bench.latest.json` and finding inconsistent timestamps (>5 minute spread) is itself a gate failure.

## Per-class instantiation

| Class | Primary `.bench-history` file | Focused files |
|---|---|---|
| SQL | `.bench-history/comprehensive_bench.latest.json` | `.bench-history/mt-mvcc-bench.latest.json`, `.bench-history/mt-mvcc-bench.separate-tables.latest.json`, `.bench-history/mt-oltp-bench.latest.json`, `.bench-history/perf-update-delete.latest.json`, `.bench-history/swarm-multiprocess.latest.json` |
| RESP | `.bench-history/redis-comprehensive-bench.latest.json` | `.bench-history/pubsub-fanout-bench.latest.json`, `.bench-history/pipeline-throughput-bench.latest.json`, `.bench-history/cluster-redirect-bench.latest.json` |
| Numerical-Python | `.bench-history/numpy-comprehensive-bench.latest.json` | `.bench-history/ufunc-elementwise-bench.latest.json`, `.bench-history/reduction-axis-bench.latest.json`, `.bench-history/rng-stream-bench.latest.json` |
| ML-System | `.bench-history/torch-comprehensive-bench.latest.json` | `.bench-history/aten-dispatch-bench.latest.json`, `.bench-history/autograd-step-bench.latest.json`, `.bench-history/nccl-allreduce-bench.latest.json` |
| HTTP-Protocol | `.bench-history/http-comprehensive-bench.latest.json` | `.bench-history/route-match-bench.latest.json`, `.bench-history/extractor-validation-bench.latest.json`, `.bench-history/concurrent-request-pool-bench.latest.json` |

All classes use the same 5 gate thresholds and the same `PASS_OVER_PASS_MAX_RATIO_DROP_PCT = 5.0` constant.

## Composition

- [pattern:125-COMPREHENSIVE-BENCH](125-COMPREHENSIVE-BENCH.md) — the JSON v3 report is what the `.bench-history` file is.
- [pattern:130-FOCUSED-BENCHES](130-FOCUSED-BENCHES.md) — every focused bench has its own `.bench-history` file.
- [pattern:165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md) — the same-window rule that pairs with the file-based ratchet.
- [pattern:170-ROBUST-REGRESSION-DETECTOR](170-ROBUST-REGRESSION-DETECTOR.md) — the regression detector uses median + MAD on top of the ratchet thresholds for early-warning signaling within the bands.
- [pattern:150-PROFILE-FIRST-CARD](150-PROFILE-FIRST-CARD.md) — the card's "baseline artifact" field points at the relevant `.bench-history/<bench>.latest.json`.
- [pattern:120-VERIFICATION-CONTRACT](120-VERIFICATION-CONTRACT.md) — `blocked-by-base-gate` includes "`.bench-history` not updated in same commit as code change".
- See [methodology/KEEP-GATE-RULES.md](../methodology/KEEP-GATE-RULES.md) for the full keep-gate vocabulary.

## Pitfalls

- **`.bench-history/` in `.gitignore`** — kills the whole pattern. Audit periodically; CI greps gitignore for `.bench-history` and fails the workflow if present.
- **`.bench-history/<bench>.latest.json` committed without bumping the per-scenario rows** — the previous summary lingered; the comparison is wrong. The full JSON must update; partial commits are rejected.
- **Manually editing the JSON to "tune" thresholds** — thresholds live in `ci_regression_gate` block of the JSON itself, *which is generated by the bench binary*. Editing in place breaks reproducibility.
- **Running the bench on a beefier machine to "see if it's noise"** — the `detected_environment` doesn't match the committed baseline's environment; the comparison is meaningless. Use the same class of host or the same `rch` worker pool.
- **Committing a regression with no waiver entry** — the file changes silently and the next reviewer sees a worsened baseline accepted without explanation. Regression commits must include a documented waiver under `methodology/CONFORMAL-RATCHET.md` semantics, severity-bounded and dated.
- **Pass-over-pass gate disabled because "the prior run was on a slower machine"** — the right fix is to record the host class and gate against the same class, not to disable. The constant `PASS_OVER_PASS_MAX_RATIO_DROP_PCT` is not flag-configurable.
- **Forgetting per-category thresholds** — `Per-category geomean regression −10%` is per category, not aggregate; a category that drops 9% sneaks past geomean (-5%) but is caught by per-category.
- **`.bench-history` files with different schema versions across benches** — the regression detector parses by `schema_version`; a stale focused file alongside a current broad file silently uses different fields. Bump all in lockstep when bumping any.
- **Quarantine state never revisited** — `quarantine` is a temporary state with an expiry; CI must alert when expiry passes without resolution. Implement quarantine-aging.
- **Running with `--quick` flag for the committed baseline** — `--quick` drops the 100K workload; the baseline now lies about the 100K behavior. The committed baseline is *full*; `--quick` is for dev-loop only.
