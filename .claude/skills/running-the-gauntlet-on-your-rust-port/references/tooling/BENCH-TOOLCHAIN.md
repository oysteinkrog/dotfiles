# BENCH-TOOLCHAIN.md — Performance Measurement Tooling

Every tool and invocation an agent needs to defend a perf claim under hostile reading. Cross-links: [ORACLE-TOOLCHAIN.md](ORACLE-TOOLCHAIN.md) for the parity oracle the bench runs both sides through; [STATIC-TOOLCHAIN.md](STATIC-TOOLCHAIN.md) for surface-side hot-path counters; [../methodology/KEEP-GATE-RULES.md](../methodology/KEEP-GATE-RULES.md) for the gates these tools feed.

## 0. The Core Rule

> **No code-changing performance bead starts without measured hotspot evidence, an EV-scored recommendation card, a one-lever scope, and a proof pack.**

If you don't have a flamegraph or samply profile showing the hotspot ≥0.1% self-time *before* the change, you do not have a perf bead — you have a hunch. Use the [../experiments/EXPERIMENT-DESIGNS-TEMPLATE.md](../experiments/EXPERIMENT-DESIGNS-TEMPLATE.md) to stage it as a hypothesis first.

---

## 1. The `release-perf` Profile

The single most-violated rule in Rust perf work. **Never `--release`** (size-optimized default) for any perf claim. Add this verbatim to the workspace `Cargo.toml`:

```toml
[profile.release-perf]
inherits = "release"
opt-level = 3
lto = "thin"
codegen-units = 1
debug = "line-tables-only"
strip = false
RUSTFLAGS = "-C force-frame-pointers=yes"
```

Then build with `cargo build --profile release-perf`. Why each field:

| Field | Why |
|---|---|
| `opt-level = 3` | Default `release` is already `3`, but be explicit so a future workspace toolchain bump can't silently change it. |
| `lto = "thin"` | "thin" gets ~95% of fat-LTO with 5x less compile time; both are vastly better than the default `false`. |
| `codegen-units = 1` | Default release is 16. Cross-CGU inlining is the largest single source of measurement noise between runs. |
| `debug = "line-tables-only"` | Needed for `samply` / `cargo flamegraph` symbolication; cheaper than `debug = true`. |
| `strip = false` | Stripping kills symbol names in the perf output. |
| `force-frame-pointers=yes` | Without this, `perf` / `samply` unwinding is `DWARF`-only and 30% slower; with it, `perf record --call-graph=fp` works. |

**Pitfall:** if you see "`unknown profile` released-perf" or similar, you renamed the profile mid-stream — every agent in the workflow must use the same name. Pin it in `AGENTS.md`.

**concurrent_mode_default_guard.txt** (verbatim from FrankenSQLite, §1.9): every artifact lane drops a feature-mode file:

```
CONCURRENT_MODE_DEFAULT=true
GIT_SHA=<sha>
TIMESTAMP=<ISO-8601>
```

Generalization: `RESP_VERSION=3` (frankenredis), `CUDA_DEVICE_COUNT=N` (frankentorch), `DETERMINISM_FLAG=true` (any seeded numerical). The point is *any silent default flip* is caught by a diffing CI step on this proof file.

---

## 2. `comprehensive-bench` — The Headline Matrix

The single binary that produces the JSON v3 report consumed by the pass-over-pass gate. ~6000 LOC in FrankenSQLite; ~1500 LOC minimum viable for a port.

### 2.1 The Six Timing Constants (Verbatim, MINING-3 §1.1)

```rust
const WARMUP_ITERS:    usize    = 2;
const MIN_ITERS:       usize    = 3;
const MAX_ITERS:       usize    = 10;
const TARGET_DURATION: Duration = Duration::from_secs(5);
```

Hard constants. Do not parameterize. Warmup-2 discards cold-start. MIN_ITERS=3 is the statistical minimum for a meaningful median. MAX_ITERS=10 with TARGET_DURATION=5s adapts: fast workloads run 10 iters, slow workloads stop at the time bound.

### 2.2 `measure()` Body (Verbatim)

```rust
fn measure<F>(label: &str, f: F) -> Measurement
where F: Fn() -> ()
{
    for _w in 0..WARMUP_ITERS { f(); }              // 1) WARMUP, discarded
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
    Measurement {
        /* median, mean, p95, p99, stddev, cv_pct, rows/sec, us/row */
    }
}
```

### 2.3 `measure_with_teardown()` Body — The Critical Discipline (Verbatim)

```rust
fn measure_with_teardown<F, T>(label: &str, f: F, teardown: T) -> Measurement
where F: Fn() -> (), T: Fn() -> ()
{
    for _w in 0..WARMUP_ITERS { f(); teardown(); }
    let start_total = Instant::now();
    let mut times = vec![];
    for iter in 0..MAX_ITERS {
        let start = Instant::now();
        f();
        let elapsed = start.elapsed();   // ← BEFORE teardown()
        times.push(elapsed);
        teardown();                       // ← OUTSIDE the timed window
        // ... same exit as measure() ...
    }
}
```

> **The teardown call is *outside* the timed window — `start.elapsed()` is captured *before* `teardown()` runs.**

Pitfall: putting `teardown()` inside the timed window is the #1 source of "we got a free 30% win!" claims that evaporate on review. Always: `start.elapsed()` first, *then* teardown.

### 2.4 Three Orthogonal Axes

1. **Workload size:** `[100, 1_000, 10_000, 100_000]`. Quick smoke-runs drop 100K.
2. **Value shape:** Tiny (1 col), Small (3 cols ≈30B), Medium (6 cols ≈180B), Large (10 cols ≈600B with overflow). Generalize per class: Redis = `(key_len × val_len × val_type)`; Torch = `(tensor_rank × dtype × device)`.
3. **Concurrency:** `[2, 4, 8]` in comprehensive; `[1, 2, 4, 8, 16]` in `mt-mvcc-bench`.

The matrix is `size × shape × concurrency` per scenario family. 93 scenarios is typical for SQL-class.

### 2.5 Identical PRAGMAs / Config — Symmetric Setup

> **"Both engines get identical PRAGMAs. This is a 30-line block at `comprehensive_bench.rs:502–541`, not a verbal convention."**

For SQL-class: `journal_mode=wal, synchronous=NORMAL, cache_size=-2000, page_size=4096`. For Redis: `maxmemory-policy, save, appendonly, io-threads` all identical. For Torch: `torch.set_num_threads(N)`, `torch.set_num_interop_threads(N)` identical between subject and oracle harnesses.

The byte-identical PRAGMA block is a copy-paste, not a generated function with conditionals. Conditionals here are how "we did A/B testing of the test setup" creeps in.

### 2.6 Six Weighted Scenario Categories

```
ReadSingle        0.35
ReadAggregate     0.15
WriteSingle       0.30
WriteBulk         0.10
ConcurrentWriters 0.05
MixedOltp         0.05
```

CI regression gate keys off `per_category_weighted.score` — NOT raw average. Adapt weights to your project class but keep `sum(weights) == 1.0` enforced by the loader (see [../taxonomy/FEATURE-UNIVERSE.md](../taxonomy/FEATURE-UNIVERSE.md) for the invariant).

### 2.7 The release-perf Profile Block

See §1 above. Cited again here because every `comprehensive-bench` invocation MUST be:

```
cargo build --profile release-perf --bin comprehensive-bench
target/release-perf/comprehensive-bench --output reports/comprehensive_bench_$(date +%Y%m%d_%H%M%S).json
```

### 2.8 JSON v3 Self-Describing Report — The Source of Truth

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
    "per_category_weighted": { "score": 0.3792, "weights": {/* §2.6 weights */} }
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

**Critical fields:** `schema_version` (every version bump is a breaking change to all downstream consumers — write it in the file); `detected_environment` (re-derive every run; if a host differs, the JSON forces the question of comparability); `cv_pct` per row (rows with `cv_pct > 5` are noise and ineligible for a keep claim).

### 2.9 `concurrent_mode_default_guard.txt`

(See §1.) Same file in every artifact lane. CI greps for the literal string.

---

## 3. Focused Narrow Benches

When `comprehensive-bench` reveals a red surface, focused benches isolate the DML / operator / workload shape *without* the ceremony.

### 3.1 `mt-mvcc-bench` (1,445 LOC in FrankenSQLite)

```
mt-mvcc-bench --threads=8 --rows-per-thread=1000 --iters=3
              [--separate-tables]
              [--engine=fsqlite|sqlite|both]
              --output reports/mt_mvcc_$(date +%s).json
```

Protocol:
- N OS threads × file-backed DB × `BEGIN CONCURRENT`
- Modes: shared-table (disjoint rowid ranges) OR `--separate-tables`
- Output schema: `fsqlite-e2e.mt_mvcc_bench_report.v3`
- Discipline: **one connection per thread**, shared file DB, disjoint rowid ranges to avoid trivial conflicts; explicit C SQLite WAL comparison with **identical busy-timeout/retry**; **fresh temp files per iteration**.

### 3.2 `mt-oltp-bench` (914 LOC)

```
mt-oltp-bench --readers=4 --writers=2 --seed-rows=5000 --ops-per-thread=5000 --iters=3
```

Measures: read latency p50/p95/p99, write throughput, Jain fairness index. Answers the question: "do readers block under write load?"

### 3.3 `mt-read-bench`

Pure-read concurrency scaling. Same shape as `mt-mvcc-bench` but with `--writers=0`. Used as the "did we regress reads while optimizing writes" detector.

### 3.4 `perf-update-delete` (1,497 LOC)

```
perf-update-delete [rows] [iters] [update|delete|both]
                   [fsqlite|sqlite|compare]
                   [standard|isolated|rollback-isolated|sparse-isolated]
```

Use when comprehensive-bench identifies red DML surface. Supports `FSQLITE_BENCH_PROFILE_DML=1` for hot-path counter dumps inline.

### 3.5 `swarm-multiprocess` (79 KB)

Cross-process MVCC correctness stress (GitHub #70). Protocol verbatim:

1. Parent inits one WAL DB.
2. Spawns N child processes (default 8, max 1024) all opening *same* file.
3. `DEFAULT_SECONDS = 60`, `DEFAULT_SEED = 0x4653_514C_5357_4152` ("FSQLSWAR").
4. `DEFAULT_HOT_ROWS = 32` writers target fixed rowid base `HOT_ROW_BASE = -1_000_000`.
5. Non-hot writers use `ROW_ID_STRIDE = 1_000_000_000` for disjoint ranges.
6. Post-run verifier checks GitHub #70 invariants.
7. `START_DELAY_MS = 1_500`, `PARENT_TIMEOUT_GRACE_MS = 20_000`.
8. Report: `fsqlite-e2e.swarm-multiprocess-report.v1`.

Env: `FSQLITE_TRACE_GROUP_COMMIT=1` to trace the commit critical section.

**Per-class adaptations:** For frankenredis: N client connections to single Redis instance; verifier checks FIFO PUBSUB. For distributed training: N ranks rendezvous on model; verifier checks all-reduce sum matches closed-form.

---

## 4. criterion — Microbenchmarks

```
cargo bench --bench <name> --profile release-perf -- \
    --baseline <git-sha> \
    --save-baseline <new-sha>
```

Workflow:

1. Establish baseline: `cargo bench --bench parser_micro --profile release-perf -- --save-baseline pre-opt`.
2. Make change.
3. Compare: `cargo bench --bench parser_micro --profile release-perf -- --baseline pre-opt --save-baseline post-opt`.
4. criterion prints "Change: -12.4% [confidence interval ...]".

**cv_pct reporting:** criterion gives `cv_pct` per benchmark; the keep gate rejects any kept change where `cv_pct > 5`.

**The micro-lever trap (MINING-3 §3):** *below 0.1% self-time is below the noise floor*. A criterion benchmark showing "your function is 38% of the function" tells you nothing if "the function" is 0.05% of any real workload. Always cross-reference the criterion target back to a real `comprehensive-bench` scenario or flamegraph frame ≥0.1% self-time.

**Pitfall:** criterion's "Change: +X%" is computed against the baseline stored in `target/criterion/`. If a parallel agent ran the same bench on a different commit, the comparison is wrong. Always use `--save-baseline <git-sha>` to namespace baselines by commit.

---

## 5. hyperfine — End-to-End Command Comparison

```
hyperfine --warmup 3 --runs 10 --export-json out.json \
    './target/release-perf/cmd-A' \
    './target/release-perf/cmd-B'
```

Output:
```
Summary
  './target/release-perf/cmd-A' ran
    1.27 ± 0.04 times faster than './target/release-perf/cmd-B'
```

Use for: end-to-end CLI timing comparison (e.g., `comprehensive-bench-fsqlite` vs `comprehensive-bench-sqlite` driving the same workload). NOT for in-process micro work (use criterion).

**Pitfalls:**
- `--warmup 3` matters; without it, first run is JIT/page-cache/fs noise.
- `--runs 10` is minimum for meaningful stddev; `--runs 30` is better for noisy systems.
- `--export-json` is mandatory if any other tool consumes the result.

---

## 6. `cargo flamegraph` — Hierarchical Time Attribution

```
cargo flamegraph --bin <bench> --profile release-perf -- --workload <id>
```

Requires `RUSTFLAGS="-C force-frame-pointers=yes"` (already in the release-perf profile, §1).

Produces `flamegraph.svg`. Open in browser, click to drill, use it to find the **specific frame ≥0.1% self-time** that justifies a perf bead.

**Pitfall:** if you see "[unknown]" or numeric addresses, you forgot `--profile release-perf` (which keeps line tables) or you're running on a different toolchain than was used to build.

**Pitfall:** flamegraph is sampled at 99Hz by default; for fast benches (<1s), the sample count is too low. Use `--freq 999` for higher sample rate or run a longer workload.

---

## 7. `samply` — Structured Profile Viewer

```
samply record -- target/release-perf/cmd
samply load samply.json
```

`samply` opens the Firefox profiler in a browser — same model as `perf record | flamegraph` but with a structured tree view, marker support, and stack filtering. Better for finding "this 0.3% frame is actually two 0.15% frames being collapsed".

**Advantage over flamegraph:** can view inverted tree (callee-up), filter by stack predicate, view marker events from `tracing` spans if you instrument them.

**Pitfall:** `samply.json` files are large (50-500MB); don't commit them to the repo. Symlink the latest into `artifacts/{bead_id}/proof_pack/`.

---

## 8. dhat-rs / heaptrack / memray — Allocation Profiling

### 8.1 `dhat-rs` (in-process Rust)

```rust
#[global_allocator]
static ALLOC: dhat::Alloc = dhat::Alloc;

fn main() {
    let _profiler = dhat::Profiler::new_heap();
    // ... benchmark body
    // dhat-heap.json drops at exit
}
```

Then `dh_view.html` shows per-call-site bytes/blocks/lifetimes. Catches: leak-shaped allocation patterns, "small thing allocated 10M times", boxed-content cloning.

### 8.2 `heaptrack` (system-level)

```
heaptrack ./target/release-perf/cmd
heaptrack_gui heaptrack.cmd.<pid>.gz
```

Tracks every malloc/free at process level. Better when the bench uses C dependencies (libsqlite3, BLAS) since dhat only sees Rust's GlobalAllocator.

### 8.3 `memray` (PyO3 bridges)

For Numerical-Python / ML-System classes with PyO3-embedded Python:

```
memray run --output memray.bin ./target/release-perf/bench
memray flamegraph memray.bin
```

Sees both Python and C-extension allocations — catches `numpy` array allocations triggered by the Rust subject.

---

## 9. strace / perf stat / fio — System-Level Attribution

### 9.1 `strace -c` — Syscall Attribution

```
strace -c -f ./target/release-perf/bench 2>strace.log
```

Output (sorted by time):
```
% time     seconds  usecs/call     calls    errors syscall
 32.41    0.382  84      4548    pwrite64
 25.10    0.296  16      18500   read
```

When `pwrite64` dominates, the bench is fsync-bound; when `futex` dominates, it's contention; when `mmap` dominates, it's page-fault.

### 9.2 `perf stat -d` — Hardware Counters

```
perf stat -d ./target/release-perf/bench
```

Reports: instructions/cycle, L1/L2/LLC misses, branch mispredictions, frontend stalls. The single number to watch first: **instructions per cycle** (IPC). IPC < 1.0 means the CPU is stalled (cache miss, branch mispredict, dependency chain); IPC > 2.0 means well-vectorized code.

### 9.3 `fio` — I/O Subsystem Characterization

```
fio --name=random-write --rw=randwrite --bs=4k --size=1G --numjobs=8 \
    --runtime=60 --ioengine=libaio --direct=1 --group_reporting
```

Use to characterize the **storage subsystem** the bench runs on, independent of the bench. If `fio` shows the disk can do 50k IOPS but your bench is hitting 5k, the bottleneck is in the subject, not the disk.

**Pitfall:** running `fio` on the same disk as the bench during the bench corrupts both measurements.

---

## 10. taskset + chrt + cgroups — Placement Reproducibility

```
taskset -c 0-7 chrt -f 50 ./target/release-perf/bench
```

`taskset -c 0-7`: pin to physical cores 0-7 (not their SMT siblings).
`chrt -f 50`: SCHED_FIFO priority 50; preempts most user-space.

For cgroup-bounded runs:

```
systemd-run --user --scope -p MemoryMax=4G -p CPUQuota=400% ./bench
```

**The placement profiles** (verbatim discipline):

| Profile | When |
|---|---|
| `baseline_unpinned` | Default; what the user sees in production. |
| `recommended_pinned` | `taskset` + `chrt`; what we publish in the README. |
| `adversarial_cross_node` | Pin half of threads to NUMA node 0, half to node 1; catches accidental NUMA-locality assumptions. |

Every kept perf win is captured under at least `recommended_pinned`. Adversarial profile runs in [../methodology/SOAK-PROTOCOL.md](../methodology/SOAK-PROTOCOL.md).

---

## 11. cargo-show-asm — Hot-Loop Assembly

```
cargo install cargo-show-asm
cargo asm --profile release-perf --bin <bench> '<crate>::<module>::<symbol>'
```

Use when criterion + flamegraph have isolated the function but you need to see *whether* the compiler did what you expected (bounds elision, autovectorization, inlining).

Common patterns:
- Look for `bndcheck:` / `panic_bounds_check`; if present, bounds aren't elided.
- Look for `vfmadd` / `vmulps` (AVX) or `fmadd` (NEON); if absent and you expected vectorization, the loop didn't vectorize.
- Look for `call` to your function instead of inlined body; if present despite `#[inline]`, the inliner declined (often due to size).

**Pitfall:** symbol mangling differs by toolchain. Run `cargo asm` with the same nightly as the build.

---

## 12. `tracing` Crate `enabled!()` Gates

Verbatim from MINING-1 Pattern 7:

> **Rule:** Gate non-trivial tracing arguments behind `if tracing::enabled!(Level)` to avoid argument evaluation when no subscriber.

Wrong (allocates `format!` arguments even when no subscriber listens):
```rust
debug!("rows={}, plan={:?}, cost={}", rows, planner.dump(), compute_cost());
```

Right (zero cost when disabled):
```rust
if tracing::enabled!(tracing::Level::DEBUG) {
    debug!("rows={}, plan={:?}, cost={}", rows, planner.dump(), compute_cost());
}
```

**Measurement:** planner perf 2026-05-20 found 3× `env::var` calls inside debug-trace ceremony. Gating behind `if tracing::enabled!(tracing::Level::INFO)`: **4-10x oltp_cost** (commit `f43902e2`, bd-mziaw).

Audit every `tracing::` macro in hot paths. The fix is mechanical.

---

## 13. HotPathProfileSnapshot — Per-Domain Counter Table

**File:** `crates/<project>-core/src/connection.rs` (or per-class equivalent).

Verbatim from MINING-3 §6, §23.6:

### Connection lifecycle
`background_status_time_ns`, `prepared_lookup_time_ns`, `prepared_schema_refresh_time_ns`, `cached_read_snapshot_reuses`, `cached_read_snapshot_parks`

### Transaction phases
`begin_setup_time_ns`, `execute_body_time_ns`, `commit_pre_txn_time_ns`, `commit_txn_roundtrip_time_ns`, `commit_finalize_seq_time_ns`

### MVCC & concurrency
`concurrent_commit_plan_{successes, errors, busy_snapshot_errors, uncontended_fast_paths, full_validations}`, `prepared_direct_{insert, update, delete}_executions`

### B-tree & storage
`seek/insert/delete/page_splits/swizzle_{in,out}_total`, `arena_alloc_bytes`, `page_buffer_pool_{hits,misses}`

### Parser & VDBE
`parser: ParserHotPathProfileSnapshot`, `window_func_partitions_total`

### Per-Domain Counter Table (§23.6 verbatim)

| Domain | Critical counters |
|--------|---|
| **FrankenSQL** | `prepared_lookup_time_ns`, `begin_setup_time_ns`, `execute_body_time_ns`, `commit_finalize_seq_time_ns`, concurrent_commit_plan_{successes, errors, busy_snapshot_errors, uncontended_fast_paths, full_validations}, prepared_direct_{insert,update,delete}_executions, B-tree seek/insert/delete/page_splits/swizzle_{in,out}_total, arena_alloc_bytes, page_buffer_pool_{hits,misses} |
| **Redis** | `resp_parse_time_ns`, `dict_probe_count`, `aof_flush_time_ns`, `rdb_serialize_time_ns`, `command_dispatch_time_ns`, `pubsub_deliver_time_ns`, `cluster_slot_resolve_time_ns`, `expiration_sweep_time_ns`, `replication_backlog_appends`, `client_io_eagain_count` |
| **Torch** | `aten_dispatch_time_ns`, `autograd_tape_append_time_ns`, `kernel_launch_time_ns`, `memcpy_h2d_bytes`, `memcpy_d2h_bytes`, `jit_cache_{hits,misses}`, `nccl_collective_time_ns`, `cuda_stream_sync_time_ns`, `gradcheck_max_rel_error`, `nondeterministic_op_count` |
| **JAX** | `tracer_construct_time_ns`, `primitive_dispatch_count`, `transform_stack_depth`, `xla_compile_time_ns`, `hlo_pass_time_ns`, `pjit_partition_time_ns`, `vmap_unroll_count`, `grad_jvp_vjp_calls` |
| **NumPy** | `ufunc_dispatch_time_ns`, `array_alloc_bytes`, `iter_setup_time_ns`, `blas_call_count`, `lapack_call_count`, `random_pcg64dxsm_advance_count`, `array_view_creates`, `copy_on_write_breaks` |
| **HTTP (FastAPI Rust)** | `route_match_time_ns`, `handler_dispatch_time_ns`, `middleware_traversal_time_ns` |

Counter representation: `AtomicU64` for counts, `AtomicU64` accumulating nanoseconds. Snapshot via `HotPathProfileSnapshot::capture()` returns a frozen struct that bench reports embed.

---

## 14. Algebraically-Redundant Counter Elimination

Verbatim from MINING-3 §7 (CC.md §55):

> **Pattern:** Counter provably equal to algebraic combination of others is work-doubling.
> **Example:** `FSQLITE_SSI_VALIDATIONS_TOTAL` was static AtomicU64 incrementing on every SSI commit. `validations_total == commits_total + aborts_total` by construction.
> **Result:** **3.91 → 1.90 ns/call (−51.5%, ~2x)** (commit `36504496`).
> **Rule:** When adding counter, ask "is this algebraically derivable from existing counters?" If yes, derive at read time. Counter writes = every-hot-call cost; counter reads = report-time cost (orders of magnitude rarer).

The 1-question audit before adding any new `AtomicU64` counter: *can I derive this from existing counters at snapshot time?* If yes, do not add it.

---

## 15. Proof-Pack Layout

Verbatim from MINING-3 §8:

```
artifacts/{bead_id}/proof_pack/
  baseline_profile.{flame.svg,samply.json}
  candidate_profile.*
  delta_summary.json
  correctness.txt
  invariant_check.txt
  rerun.sh
  rollback.md
```

Required env keys captured into each: `RUSTFLAGS`, `FEATURE_FLAGS`, `MODE`, `GIT_SHA`, `PLATFORM`.
Required tools installed: `cargo-flamegraph`, `hyperfine`, `heaptrack`, `strace`, `samply`, `perf`.

The 19 required proof-card fields (MINING-3 §5): hotspot artifact, baseline artifact, mapped primitive/technique lineage, EV score, relevance score, priority tier, score formula (`Impact × Confidence / Effort ≥ 2.0`), hotspot rank, comparator, rollout posture, budgeted mode, fallback trigger, benchmark/profile commands, p50/p95/p99 targets, throughput targets, primary failure risk, proof artifact, rerun command, rollback recipe.

---

## 16. Pass-Over-Pass Gate

**Files:** `.bench-history/<bench>.latest.json` — committed.

```rust
const PASS_OVER_PASS_MAX_RATIO_DROP_PCT: f64 = 5.0;
let ratio_drop_pct = ((previous_ratio - row.throughput_ratio) / previous_ratio) * 100.0;
if ratio_drop_pct > PASS_OVER_PASS_MAX_RATIO_DROP_PCT {
    return Err(RatioRegression { /* ... */ });
}
```

### The 5 gate thresholds:

| Metric | Threshold |
|--------|-----------|
| Primary score regression | **−3%** |
| Geomean regression | **−5%** |
| Per-category geomean regression | **−10%** |
| p90 regression | **−15%** |
| Pass-over-pass throughput drop | **−5%** |

Cross-link: [../methodology/KEEP-GATE-RULES.md](../methodology/KEEP-GATE-RULES.md) for the broader keep-gate doctrine.

> **"Pass-over-pass gate is a *file*. `.bench-history/*.latest.json` is committed. You can't bench on your machine, see a 30% drop, and quietly not commit."**

**Both gates same window:** Focused + broad must both pass in same run window (same git, same `target/`, same machine, same minute).

---

## 17. Robust Regression Detection — Median + MAD

Verbatim from MINING-3 §9:

```
Median(p50_samples) as baseline
MAD = Median(|sample - median|) as spread
```

Default tolerance:
| Metric | Warning | Critical |
|--------|---------|----------|
| Latency ratio | 1.10x | 1.25x |
| Throughput drop | −10% | −20% |

MAD is **distribution-free and outlier-robust**. Unlike stddev, doesn't assume normality. A single 5x flake doesn't blow up the spread estimate.

**Structured dated waivers:** every exception is logged with `{date, scenario, reason, owner, expiry_date}`. No invisible exceptions.

---

## 18. Pitfalls — Common Failure Modes

| Pitfall | Why it bites | Fix |
|---|---|---|
| Used `--release` instead of `--profile release-perf` | LTO/CGU differences swamp the signal | Always `--profile release-perf`; pin in `AGENTS.md`. |
| `cv_pct` dropped from report | Noise looks like signal | Every microbench reports `cv_pct`; `>5%` is noise, not eligible for keep. |
| `target/` not warmed identically | First build's link order is non-deterministic | `cargo build --profile release-perf --workspace` BEFORE the bench loop; warmup-2 in `measure()` is for the running code, not for the binary loading. |
| Mixing focused + broad runs across time windows | Same git state, different `target/`, different host → not comparable | Both gates same run window: same git, same `target/`, same machine, same minute. |
| Teardown inside timed window | Free 30% win that evaporates | `measure_with_teardown` captures `start.elapsed()` BEFORE `teardown()`. |
| Cherry-picked baseline | The kept win evaporates next pass | Baseline = `.bench-history/<bench>.latest.json` committed to git, period. |
| Concurrent mode silently off | "MVCC perf win" was running serial | `concurrent_mode_default_guard.txt` (or class equivalent) in every artifact lane. |
| Sampled freq too low for fast bench | Top frame is "[unknown]" | `--freq 999` in flamegraph; run longer workload. |
| dhat global allocator conflicts | Compile error from second `#[global_allocator]` | dhat is a runtime feature flag, not the default; gate the `#[global_allocator]` behind `#[cfg(feature = "dhat")]`. |
| flamegraph "[unknown]" symbols | `debug` profile not built; or stripped | `release-perf` profile + `strip = false` + `force-frame-pointers=yes`. |
| Below-0.1% optimization | Micro-lever trap | Cite the specific frame and self-time before optimizing; reject if <0.1%. |

---

## See Also

- [ORACLE-TOOLCHAIN.md](ORACLE-TOOLCHAIN.md) — wire the reference oracle the bench drives both sides through.
- [STATIC-TOOLCHAIN.md](STATIC-TOOLCHAIN.md) — surface enumeration that pairs with hot-path counters.
- [SANITIZER-TOOLCHAIN.md](SANITIZER-TOOLCHAIN.md) — bench under sanitizer to catch UB-class regressions.
- [../methodology/KEEP-GATE-RULES.md](../methodology/KEEP-GATE-RULES.md) — the verdicts these tools feed.
- [../methodology/CONFORMAL-RATCHET.md](../methodology/CONFORMAL-RATCHET.md) — the lower-bound math that turns these numbers into release decisions.
- [../experiments/EXPERIMENT-DESIGNS-TEMPLATE.md](../experiments/EXPERIMENT-DESIGNS-TEMPLATE.md) — the hypothesis template every perf bead starts from.
