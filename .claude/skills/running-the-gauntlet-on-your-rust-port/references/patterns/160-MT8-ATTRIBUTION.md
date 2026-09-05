# Pattern 160 — MT8 Attribution

## What

Every kept performance win must cite a specific profile frame at ≥0.1% self-time captured under the project's canonical concurrent workload (MT8 = 8-thread MVCC bench for FrankenSQLite, per-class equivalent elsewhere). Below 0.1% is the *micro-lever trap* — sub-noise-floor work that produces no detectable signal at the gate level. The 0.1%–1.0% range is where productive optimization work happens; ≥1.0% frames are rare and high-value. The ledger citation format is uniform: "Closed N.NN% MT8 <function/symbol> <self-time | inclusive | residual>".

## Why

> "A frame at 0.05% is below the noise floor of the bench (cv_pct 3-5%); the **micro-lever trap**. A frame at 1% is rare and high-value. The 0.1-1% range is where productive optimization work happens." — CC.md line 2393 (MINING-3 §3)

Failure mode prevented: chasing nanosecond improvements on cold paths that round to nothing at the gate level. After 20 hours of work the bench moves 0.1% (well within cv_pct); the keep gate cannot distinguish from noise; the change lands as a "kept (durable infra)" rationalization. The 0.1% threshold rule turns this into a pre-flight question: does the frame I'm targeting actually qualify?

## Where in FrankenSQLite

- `crates/fsqlite-e2e/src/bin/mt_mvcc_bench.rs` — the MT8 reference workload (8 threads, file-backed DB, BEGIN CONCURRENT).
- Flamegraph + samply outputs in `artifacts/{bead_id}/proof_pack/baseline_profile.flame.svg` and `candidate_profile.flame.svg`.
- Memory ledger citations: `MEMORY.md` perf entries that read "Closed 0.44% MT8 PublishedPages::clear residual", "Closed 0.63% MT8 inclusive self-time", "Closed 0.51% MT8 self-time symbol".

## Verbatim shape

### The 0.1% rule (CC.md line 2390)

"Each frame ≥0.1% is a *candidate*."

A frame's *self-time* (exclusive time spent executing in that function, not in its callees) at ≥0.1% qualifies it as a candidate. Inclusive-time citations are also accepted but must be labeled; "0.63% MT8 inclusive self-time" is a different attribution than "0.63% MT8 self-time."

### Canonical example (CC.md line 2256, verbatim)

```
ConcurrentPublishedPages::clear() empty-overflow
  2.92µs → 1 ns
  ≈ 2922x speedup
  Closed 0.44% MT8 PublishedPages::clear residual
```

The entry contains: function name + call site qualifier + before/after timing + relative speedup + frame attribution percentage + workload context (MT8) + which frame closed.

### The three zones

| Zone | Self-time range | Verdict |
|---|---|---|
| Micro-lever trap | < 0.1% | Sub-noise-floor (cv_pct typically 3–5%). Do not open beads on these unless multiple frames in this band sum to ≥0.1% and the bead closes all of them together. |
| Sweet spot | 0.1% – 1.0% | Productive optimization range. Most kept FrankenSQLite wins live here. |
| Rare high-value | ≥ 1.0% | Rare; high reward when found. Investigate before assuming the profile is wrong. |

### Citation format (verbatim from MEMORY.md)

- "Closed 0.44% MT8 PublishedPages::clear residual" — closed a frame that was the residual fraction (after a previous optimization left some attribution behind).
- "Closed 0.63% MT8 inclusive self-time" — inclusive-time variant; counts callees.
- "Closed 0.51% MT8 self-time symbol" — exclusive self-time; canonical form.

Every kept perf win in the ledger uses one of these forms; "improved by X%" without frame attribution is rejected.

### MT8 attribution discipline (CC.md §63)

1. Run `mt-mvcc-bench --threads=8 --rows-per-thread=1000 --iters=3`.
2. Capture flamegraph during *steady-state* (not warmup; not startup).
3. Identify top 5–10 self-time frames.
4. Each ≥0.1% is a candidate.
5. Pick highest cost-effort ratio (the EV-score gate; see [pattern:150-PROFILE-FIRST-CARD](150-PROFILE-FIRST-CARD.md)).

## Per-class instantiation

| Class | Canonical concurrent workload | Threshold equivalents |
|---|---|---|
| SQL | `mt_mvcc_bench --threads=8 --rows-per-thread=1000 --iters=3` | Same 0.1% / 1.0% zones; same citation format. |
| RESP | `pipeline_throughput_bench --clients=64 --pipeline=16 --duration=60s` | "Closed N.NN% Redis64c <symbol>" |
| Numerical-Python | `ufunc_elementwise_bench --threads=8 --array-size=1e7 --iters=5` | "Closed N.NN% NP8t <symbol>" |
| ML-System (Torch) | `transformer_block_bench --batch=8 --seq=512 --layers=12 --iters=5` | "Closed N.NN% TR-B8 <symbol>" |
| ML-System (JAX) | `pjit_partition_bench --devices=8 --shape=…` | "Closed N.NN% PJIT8 <symbol>" |
| HTTP-Protocol | `concurrent_request_pool_bench --clients=256 --rps=10000 --duration=60s` | "Closed N.NN% HTTP256c <symbol>" |

Per-class canonical workloads must be (a) concurrent (single-thread profiles overstate hot frames), (b) steady-state (warmup excluded), (c) representative of production-like mix (not micro-benchmark of one op).

## Composition

- [pattern:145-HOT-PATH-COUNTERS](145-HOT-PATH-COUNTERS.md) — counter deltas under the same workload provide subsystem-level attribution alongside frame-level.
- [pattern:130-FOCUSED-BENCHES](130-FOCUSED-BENCHES.md) — the MT8 workload *is* one of the focused benches; the profile is captured under it.
- [pattern:150-PROFILE-FIRST-CARD](150-PROFILE-FIRST-CARD.md) — the card's `hotspot rank` field requires top-5 placement in MT8 profile.
- [pattern:140-RELEASE-PERF-PROFILE](140-RELEASE-PERF-PROFILE.md) — frame attribution requires `force-frame-pointers=yes` from `release-perf`; under plain `--release` frames are missing.
- [pattern:165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md) — MT8 result moving alongside broad result moving is the same-window rule; MT8-only wins without broad confirmation are rejected.
- [pattern:225-DEVIRTUALIZE-MATCH-ARM](225-DEVIRTUALIZE-MATCH-ARM.md) — example of an MT8 0.36% + 0.29% closure (TransactionKind devirtualization) following exactly this discipline.
- [pattern:205-ATOMIC-BOOL-EMPTY-GATE](205-ATOMIC-BOOL-EMPTY-GATE.md) — example of an MT8 0.44% closure (PublishedPages::clear).

## Pitfalls

- **Citing inclusive time as self-time** — these are different attributions. Always label.
- **Profile captured on a different machine than the gate ran on** — frame percentages drift with CPU architecture (especially `aten_dispatch` on CUDA vs CPU). Capture profile + gate run on same host.
- **Single-thread profile used to justify a concurrent optimization** — single-thread hides MVCC overhead, contention, and synchronization frames. The MT8 profile is non-negotiable for concurrent claims.
- **"0.05% × 10 = 0.5% effective" rationalization** — 10 frames summing to 0.5% is fine *if* you commit to closing all 10 in one bead. Cherry-picking one 0.05% frame because "they add up" without a sweep across the cluster is the trap.
- **Capturing profile during warmup** — warmup-only profiles include connection-setup costs that don't exist in steady state. The `steady-state` qualifier is non-optional.
- **Confusing "frame N% in the candidate profile" with "frame N% closed"** — closure is the delta from baseline → candidate. A frame at 0.44% in baseline that's 0.00% in candidate is a 0.44% closure; a frame at 0.44% in both is no progress.
- **Citing 0.1% from a profile under a non-MT8 workload** — the workload is part of the attribution. "Closed 0.44% under single-thread reader bench" is not an MT8 closure.
- **Skipping the steady-state filter** — `samply` and `cargo-flamegraph` include startup costs by default; filter to the steady-state window before computing percentages.
- **Optimizing a frame whose attribution comes from an instrumentation counter** — the instrumentation itself shows up as a frame; closing the instrumentation is not closing real work.
- **Failure to record cv_pct alongside the frame %** — a 0.15% frame with cv_pct 5% is at the edge; the win might be noise. Always co-report cv_pct.
