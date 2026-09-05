# Pattern 130 — Focused Benches

## What

Alongside the broad `comprehensive_bench`, a small set of narrow per-workload benches (one per high-stakes workload shape) live as separate binaries with their own JSON schemas, their own `.bench-history` files, their own pass-over-pass gates. The broad bench identifies the *red surface*; the focused bench *isolates the owning subphase* so a regression maps to one workload shape, one bottleneck, one repro command. Both gates must move in the same run window; improving focused while regressing broad is a rejection.

## Why

> "When comprehensive-bench identifies red surface, this isolates DML shape *without* ceremony." — MINING-3 §2.3

> "Both gates same window: Focused + broad must both pass in same run window (same git, same `target/`, same machine, same minute)." — MINING-3 §4

Failure mode prevented: chasing a 5% improvement in the broad geomean by writing a 1000-line bench that mixes everything; the regression detector then can't tell which workload moved. A focused bench is a *named subset* with a stable schema; a regression in it points at a stable owner.

## Where in FrankenSQLite

- `crates/fsqlite-e2e/src/bin/mt_mvcc_bench.rs` (1,445 LOC) — concurrent MVCC under N threads.
- `crates/fsqlite-e2e/src/bin/mt_oltp_bench.rs` (914 LOC) — readers vs writers mixed OLTP.
- `crates/fsqlite-e2e/src/bin/mt_read_bench.rs` — read-only fan-out.
- `crates/fsqlite-e2e/src/bin/perf_update_delete.rs` (1,497 LOC) — DML shape isolation.
- `crates/fsqlite-e2e/src/bin/swarm_multiprocess.rs` (79 KB) — cross-process MVCC stress (GitHub #70).
- Each emits its own JSON schema and writes its own `.bench-history/<bench>.latest.json`.

## Verbatim shape

### mt_mvcc_bench.rs (1,445 LOC)

- N OS threads × file-backed DB × `BEGIN CONCURRENT`
- Modes: shared-table (disjoint rowid ranges) or `--separate-tables`
- Output: `fsqlite-e2e.mt_mvcc_bench_report.v3`
- Discipline: one connection per thread; shared file DB; disjoint rowid ranges; explicit C SQLite WAL comparison with identical busy-timeout/retry; fresh temp files per iteration.

### mt_oltp_bench.rs (914 LOC)

- 4 readers + 2 writers, 5,000 seed rows, 5,000 ops/thread, 3 iterations.
- Measures: read latency p50/p95/p99, write throughput, Jain fairness.
- Answers: "do readers block under write load?"

### perf_update_delete.rs (1,497 LOC)

```
perf-update-delete [rows] [iters] [update|delete|both]
                   [fsqlite|sqlite|compare]
                   [standard|isolated|rollback-isolated|sparse-isolated]
```

When comprehensive-bench identifies a red DML surface, this isolates the DML shape without the ceremony of a full matrix. Supports `FSQLITE_BENCH_PROFILE_DML=1` for hot-path counter dumps.

### swarm_multiprocess.rs (79 KB)

Cross-process MVCC correctness stress (GitHub #70). Protocol:

1. Parent inits one WAL DB.
2. Spawns N child processes (default 8, max 1024) all opening the *same* file.
3. `DEFAULT_SECONDS = 60`, `DEFAULT_SEED = 0x4653_514C_5357_4152` ("FSQLSWAR").
4. `DEFAULT_HOT_ROWS = 32` writers target fixed rowid base `HOT_ROW_BASE = -1_000_000`.
5. Non-hot writers use `ROW_ID_STRIDE = 1_000_000_000` for disjoint ranges.
6. Post-run verifier checks #70 invariants.
7. `START_DELAY_MS = 1_500`, `PARENT_TIMEOUT_GRACE_MS = 20_000`.
8. Report: `fsqlite-e2e.swarm-multiprocess-report.v1`.
9. Env: `FSQLITE_TRACE_GROUP_COMMIT=1`.

### Why narrow benches exist

The broad bench's strength — covering 93 scenarios — is its weakness as a *diagnostic*. A 7% regression in `summary.geomean_ratio` could be one slow scenario or seven 1% regressions; the report can tell you which scenarios but not *why*. A focused bench narrows the question to one workload shape, lets you wire scenario-level hot-path counters (DML profiling, group-commit tracing), and produces a smaller `.bench-history` file whose regression is unambiguous.

## Per-class instantiation

| Class | Narrow-bench set | Per-bench schema |
|---|---|---|
| SQL | `mt_mvcc_bench`, `mt_oltp_bench`, `mt_read_bench`, `perf_update_delete`, `swarm_multiprocess` | `mt_mvcc_bench_report.v3`, `mt_oltp_bench_report.v3`, `swarm-multiprocess-report.v1` |
| RESP | `pubsub_fanout_bench`, `pipeline_throughput_bench`, `cluster_redirect_bench`, `xadd_xread_bench`, `aof_rewrite_bench` | `redis_pubsub_report.v1`, ... |
| Numerical-Python | `ufunc_elementwise_bench`, `reduction_axis_bench`, `linalg_blas_thread_bench`, `rng_stream_bench` | `numpy_ufunc_report.v1`, ... |
| ML-System (Torch) | `aten_dispatch_bench`, `autograd_step_bench`, `transformer_block_bench`, `nccl_allreduce_bench` | `torch_aten_report.v1`, ... |
| ML-System (JAX) | `jaxpr_compile_bench`, `pjit_partition_bench`, `vmap_unroll_bench`, `xla_hlo_pass_bench` | `jax_pjit_report.v1`, ... |
| HTTP-Protocol | `route_match_bench`, `extractor_validation_bench`, `middleware_chain_bench`, `concurrent_request_pool_bench`, `streaming_body_bench` | `http_route_report.v1`, ... |

Each narrow bench has its own primary statistic (often p99 latency or throughput) and its own pass-over-pass threshold.

## Composition

- [pattern:125-COMPREHENSIVE-BENCH](125-COMPREHENSIVE-BENCH.md) — focused benches *complement* the broad one; neither replaces the other.
- [pattern:165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md) — both gates must move in the same run window. Improving focused while regressing broad ⇒ rejection.
- [pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md) — each focused bench has its own `.bench-history/<bench>.latest.json` committed alongside the broad one.
- [pattern:145-HOT-PATH-COUNTERS](145-HOT-PATH-COUNTERS.md) — focused benches typically run with the project's `*_PROFILE_*=1` env vars enabled to dump counters per iteration.
- [pattern:160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md) — MT8 attribution is *anchored on* `mt_mvcc_bench --threads=8`; it is the canonical concurrent profiler workload.
- [pattern:175-CONCURRENT-MODE-GUARD](175-CONCURRENT-MODE-GUARD.md) — each focused bench drops a per-class guard file in its artifact lane.
- [pattern:135-MEASURE-WITH-TEARDOWN](135-MEASURE-WITH-TEARDOWN.md) — focused benches frequently use teardown-outside variant (DML benches drop and recreate tables between iters).

## Pitfalls

- **Treating focused-bench wins as keep-able without re-running the broad bench** — violates K-4. Only same-window pairs count.
- **Letting focused benches drift to different timing constants than the broad bench** — `WARMUP_ITERS`, `MIN_ITERS`, `MAX_ITERS`, `TARGET_DURATION` come from the shared `measure()` module; do not redefine per-binary.
- **Writing a focused bench that secretly covers a different workload than its name** — a "DELETE" bench that also INSERTs to set up rows but counts the INSERTs in the timer. Setup happens in `measure_with_teardown`'s teardown function.
- **Forgetting `--separate-tables` mode** — shared-table contention and disjoint-table contention are different bottlenecks; both modes belong in the matrix.
- **Skipping `swarm_multiprocess` because "we have `mt_mvcc_bench`"** — multi-thread and multi-process exercise different code paths (kernel file locks, fork-safety, single-writer SHM). Both are required for an MVCC class.
- **Reporting a focused-bench p99 without `cv_pct`** — p99 with 3 iterations is noise. The narrow benches use `iterations` higher than the broad (often 5–10) and still report `cv_pct`.
- **Letting per-bench schema versions drift** — the regression detector keys off `schema_version` to know how to parse the artifact; a silent bump leaves the detector reading stale fields and reporting false greens.
- **Running narrow benches at lower iteration counts to "save time"** — narrow benches are the place to *spend* iterations; the broad bench's 5-second cap is the budget guardrail, not a target.
