# Pattern 145 — Hot-Path Counters

## What

Every project class declares a `HotPathProfileSnapshot` struct enumerating the counters that live on the per-class hot path — time-in-namespace nanoseconds, op-count totals, cache hit/miss breakdowns, per-subsystem dispatch counts. The counters are read at scenario boundaries (start, end) and `delta`'d to attribute regression to a *specific named subsystem* rather than to "the whole bench got slower." The naming convention is uniform across classes (`<subsystem>_<verb>_time_ns` for durations, `<subsystem>_<verb>_count` for counts, `<subsystem>_<resource>_bytes` for memory) so cross-class tooling can parse counters without per-class adapters.

## Why

> "Each frame ≥0.1% is a *candidate*." — CC.md line 2390 (MINING-3 §3)

Failure mode prevented: a 5% regression in geomean with no attribution. Without per-subsystem counters the only way to attribute is by re-running with a flamegraph, often on a different machine than the regression-detecting CI runner. With counters, the regression report names the subsystem(s) whose count or duration moved, and the flamegraph confirms.

## Where in FrankenSQLite

- `crates/fsqlite-core/src/connection.rs:686–835` — the FrankenSQLite `HotPathProfileSnapshot` definition.
- Per-subsystem counters mounted under: `crates/fsqlite-vdbe/src/profile.rs`, `crates/fsqlite-btree/src/profile.rs`, `crates/fsqlite-mvcc/src/profile.rs`, `crates/fsqlite-wal/src/profile.rs`, etc.
- Snapshot is captured at scenario boundaries by `comprehensive_bench.rs` (`FSQLITE_BENCH_PROFILE_*` env vars enable per-counter emission).

## Verbatim shape

```rust
pub struct HotPathProfileSnapshot {
    // Connection lifecycle
    pub background_status_time_ns: u64,
    pub prepared_lookup_time_ns: u64,
    pub prepared_schema_refresh_time_ns: u64,
    pub cached_read_snapshot_reuses: u64,
    pub cached_read_snapshot_parks: u64,

    // Transaction phases
    pub begin_setup_time_ns: u64,
    pub execute_body_time_ns: u64,
    pub commit_pre_txn_time_ns: u64,
    pub commit_txn_roundtrip_time_ns: u64,
    pub commit_finalize_seq_time_ns: u64,

    // MVCC & concurrency
    pub concurrent_commit_plan_successes: u64,
    pub concurrent_commit_plan_errors: u64,
    pub concurrent_commit_plan_busy_snapshot_errors: u64,
    pub concurrent_commit_plan_uncontended_fast_paths: u64,
    pub concurrent_commit_plan_full_validations: u64,
    pub prepared_direct_insert_executions: u64,
    pub prepared_direct_update_executions: u64,
    pub prepared_direct_delete_executions: u64,

    // B-tree & storage
    pub btree_seek_total: u64,
    pub btree_insert_total: u64,
    pub btree_delete_total: u64,
    pub btree_page_splits: u64,
    pub btree_swizzle_in_total: u64,
    pub btree_swizzle_out_total: u64,
    pub arena_alloc_bytes: u64,
    pub page_buffer_pool_hits: u64,
    pub page_buffer_pool_misses: u64,

    // Parser & VDBE
    pub parser: ParserHotPathProfileSnapshot,
    pub window_func_partitions_total: u64,
}
```

### §23.6 Per-Domain Counter Table (verbatim)

| Domain | Critical counters |
|--------|---|
| **FrankenSQL** | `prepared_lookup_time_ns`, `begin_setup_time_ns`, `execute_body_time_ns`, `commit_finalize_seq_time_ns`, `concurrent_commit_plan_{successes, errors, busy_snapshot_errors, uncontended_fast_paths, full_validations}`, `prepared_direct_{insert,update,delete}_executions`, B-tree `seek/insert/delete/page_splits/swizzle_{in,out}_total`, `arena_alloc_bytes`, `page_buffer_pool_{hits,misses}` |
| **Redis** | `resp_parse_time_ns`, `dict_probe_count`, `aof_flush_time_ns`, `rdb_serialize_time_ns`, `command_dispatch_time_ns`, `pubsub_deliver_time_ns`, `cluster_slot_resolve_time_ns`, `expiration_sweep_time_ns`, `replication_backlog_appends`, `client_io_eagain_count` |
| **Torch** | `aten_dispatch_time_ns`, `autograd_tape_append_time_ns`, `kernel_launch_time_ns`, `memcpy_h2d_bytes`, `memcpy_d2h_bytes`, `jit_cache_{hits,misses}`, `nccl_collective_time_ns`, `cuda_stream_sync_time_ns`, `gradcheck_max_rel_error`, `nondeterministic_op_count` |
| **JAX** | `tracer_construct_time_ns`, `primitive_dispatch_count`, `transform_stack_depth`, `xla_compile_time_ns`, `hlo_pass_time_ns`, `pjit_partition_time_ns`, `vmap_unroll_count`, `grad_jvp_vjp_calls` |
| **NumPy** | `ufunc_dispatch_time_ns`, `array_alloc_bytes`, `iter_setup_time_ns`, `blas_call_count`, `lapack_call_count`, `random_pcg64dxsm_advance_count`, `array_view_creates`, `copy_on_write_breaks` |
| **HTTP (FastAPI Rust)** | `route_match_time_ns`, `handler_dispatch_time_ns`, `middleware_traversal_time_ns` |

## Per-class instantiation

### Naming convention

- Duration: `<subsystem>_<verb>_time_ns` (always `u64` nanoseconds).
- Count: `<subsystem>_<verb>_count` or `<subsystem>_<verb>_total`.
- Memory: `<subsystem>_<resource>_bytes`.
- Boolean fast-path: `<subsystem>_<path>_taken` (count of times the fast path was selected).

Counters are accumulated using `AtomicU64::fetch_add(_, Ordering::Relaxed)` — the relaxed ordering is intentional; a few microseconds of skew is irrelevant against `WARMUP_ITERS`-iterations-worth of accumulation, and stronger orderings cost more than they contribute.

### Capture cadence

- Per scenario (start, end) — emit a delta'd snapshot per scenario row in the bench JSON.
- Per iteration (under `FSQLITE_BENCH_PROFILE_DML=1`) — emit per-iter for high-fidelity attribution; used during regression-hunt, not in the steady-state lane.
- Per phase (under `FSQLITE_TRACE_GROUP_COMMIT=1` or per-class equivalent) — emit at transaction boundaries.

### Algebraically-derived counters

A counter whose value is a closed-form function of others (e.g., `validations_total == commits_total + aborts_total`) is *forbidden* on the hot path. Derive it at read time from the constituents; see [pattern:210-ALGEBRAIC-COUNTER-ELIMINATION](210-ALGEBRAIC-COUNTER-ELIMINATION.md).

## Composition

- [pattern:125-COMPREHENSIVE-BENCH](125-COMPREHENSIVE-BENCH.md) — the snapshot is captured at scenario boundaries by the comprehensive bench.
- [pattern:130-FOCUSED-BENCHES](130-FOCUSED-BENCHES.md) — focused benches run with the per-class `*_PROFILE_*=1` env vars enabled.
- [pattern:140-RELEASE-PERF-PROFILE](140-RELEASE-PERF-PROFILE.md) — counters must be compiled under the same profile as the timed binary; inlining drift otherwise.
- [pattern:150-PROFILE-FIRST-CARD](150-PROFILE-FIRST-CARD.md) — the proof-pack card cites *counter* deltas alongside flamegraph frames as hotspot evidence.
- [pattern:160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md) — attribution combines counter deltas (subsystem level) + flamegraph frames (function level).
- [pattern:170-ROBUST-REGRESSION-DETECTOR](170-ROBUST-REGRESSION-DETECTOR.md) — counter deltas feed a per-counter regression detector that runs alongside the headline-ratio detector; a counter that doubled in a release is investigated independently of whether ratio regressed.
- [pattern:210-ALGEBRAIC-COUNTER-ELIMINATION](210-ALGEBRAIC-COUNTER-ELIMINATION.md) — when adding a counter, the audit question is "is this algebraically derivable?"

## Pitfalls

- **Adding a counter to the *hot* path under `Ordering::SeqCst`** — measurable cost just from the fence. Always `Relaxed` for hot-path accumulation.
- **Reading counters inside the timed window** — adds load/atomic op to every iteration. Read at scenario boundaries only.
- **Per-thread counters without a join function** — N counters require N reads at boundary; if the join is wrong, regression report is wrong. Use `thread_local!` + a sum-into-global at scenario end, or sharded counters with an explicit `combine()`.
- **Inconsistent units across counters (some `_time_ns`, some `_time_us`, some `_time_ms`)** — downstream tooling cannot diff. Standardize on `_time_ns` for all durations.
- **Forgetting the `parser:` nested struct** — flat struct layouts are fine until you have 60 counters; the nested `ParserHotPathProfileSnapshot` keeps the report readable.
- **Counters that grow but never reset between scenarios** — must delta in the report ("delta = end_snapshot - start_snapshot"); absolute values across long runs are meaningless.
- **Counter naming that mixes "verb" and "noun" (e.g., `cache_lookup` vs `lookups_in_cache`)** — pick one form per class and stick. The verb-suffix form (`<subsystem>_<verb>_<unit>`) sorts well, autocompletes well, and is greppable.
- **Adding a counter without adding it to `HotPathProfileSnapshot`** — the struct is the *contract*; per-call-site reads without struct membership leak into per-call-site grep patterns and never make the report.
- **Dropping `nondeterministic_op_count` from ML class because "we set deterministic mode"** — the counter is the audit; deterministic mode being on does not mean it was respected. Counter must be present even when expected to be zero.
- **Mixing `u64` and `usize` counters** — `usize` differs on 32-bit targets; always `u64` for cross-platform reproducibility.
