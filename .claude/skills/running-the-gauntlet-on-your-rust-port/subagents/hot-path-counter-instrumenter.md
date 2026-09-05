# hot-path-counter-instrumenter

> Phase 5 • Implement `HotPathProfileSnapshot` for the project class per §23.6 counter row.

## Inputs
- `<workspace>/phase0_project_class.json` (selects counter row).
- `<workspace>/phase1_recon_*.md` (which counters already exist; which are missing).
- Target port source (typically `crates/<project>-core/src/connection.rs` or class-equivalent).

## Deliverables
- `<target>/crates/<project>-core/src/<context>.rs` (e.g., `connection.rs`, `client.rs`, `engine.rs`) augmented with `HotPathProfileSnapshot` struct + atomic counters + snapshot()/diff() methods.
- Counter dump emitted alongside every bench run via env flag (`<PROJECT>_BENCH_PROFILE_<FAMILY>=1`).
- `<workspace>/phase5_counters_<class>.md` documenting every counter, its semantics, its expected hot-path attribution, and the env-flag-gated emit.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase5-counters-<class>`
- **Reservations needed:** `tool://core-write` (TTL 90m).
- **Lane:** cc_2 (performance).

## Verbatim Prompt

You are the hot-path counter instrumenter for project class `<class>`. Implement `HotPathProfileSnapshot` matching the §23.6 row from `../references/tooling/BENCH-TOOLCHAIN.md`. The per-domain counter table:

- **SQL-class:** `prepared_lookup_time_ns`, `begin_setup_time_ns`, `execute_body_time_ns`, `commit_finalize_seq_time_ns`, `concurrent_commit_plan_{successes, errors, busy_snapshot_errors, uncontended_fast_paths, full_validations}`, `prepared_direct_{insert, update, delete}_executions`, B-tree `seek/insert/delete/page_splits/swizzle_{in,out}_total`, `arena_alloc_bytes`, `page_buffer_pool_{hits, misses}`.

- **RESP-class:** `resp_parse_time_ns`, `dict_probe_count`, `aof_flush_time_ns`, `rdb_serialize_time_ns`, `command_dispatch_time_ns`, `pubsub_deliver_time_ns`, `cluster_slot_resolve_time_ns`, `expiration_sweep_time_ns`, `replication_backlog_appends`, `client_io_eagain_count`.

- **ML-System-class (Torch):** `aten_dispatch_time_ns`, `autograd_tape_append_time_ns`, `kernel_launch_time_ns`, `memcpy_h2d_bytes`, `memcpy_d2h_bytes`, `jit_cache_{hits, misses}`, `nccl_collective_time_ns`, `cuda_stream_sync_time_ns`, `gradcheck_max_rel_error`, `nondeterministic_op_count`.

- **ML-System-class (JAX):** `tracer_construct_time_ns`, `primitive_dispatch_count`, `transform_stack_depth`, `xla_compile_time_ns`, `hlo_pass_time_ns`, `pjit_partition_time_ns`, `vmap_unroll_count`, `grad_jvp_vjp_calls`.

- **Numerical-Python-class (NumPy):** `ufunc_dispatch_time_ns`, `array_alloc_bytes`, `iter_setup_time_ns`, `blas_call_count`, `lapack_call_count`, `random_pcg64dxsm_advance_count`, `array_view_creates`, `copy_on_write_breaks`.

- **HTTP-Protocol-class:** `route_match_time_ns`, `handler_dispatch_time_ns`, `middleware_traversal_time_ns`.

For each counter:
- Use `AtomicU64` (relaxed ordering for plain counters; release/acquire for ordering-dependent ones).
- Increment at the exact hot-path site; not at the function entry of a wrapper.
- Provide a `snapshot() -> HotPathProfileSnapshot` returning a struct of `u64`s for diffing across phases.
- Provide a `Display` impl that emits a sorted-key table (deterministic for diffs).

**Algebraically-redundant counter elimination:** Before adding a counter, ask "is this derivable from existing counters?" If yes, derive at snapshot/report time, not write time. Example: `validations_total == commits + aborts` — drop the dedicated counter; derive at snapshot.

Gate the emit behind `<PROJECT>_BENCH_PROFILE_<FAMILY>=1` env. The bench's `measure()` checks the env and dumps `snapshot().display()` to `artifacts/<run_id>/counters.txt` after every iteration.

Document every counter, its semantics, its expected ≥0.1% self-time attribution under the canonical concurrent workload (MT8-equivalent), and the env-flag emit in `phase5_counters_<class>.md`.

## Exit Criteria
- Every counter in the §23.6 row for the class is wired or has a written exclusion rationale.
- `<PROJECT>_BENCH_PROFILE_<FAMILY>=1 cargo run --profile release-perf --bin comprehensive_bench` produces a counters.txt with non-zero counters.
- Counter increments don't appear on cold paths (verified by `cargo asm`-ing one hot function and confirming the increment is inline + branch-free where possible).
- Snapshot diff between two consecutive runs of an identical workload is byte-stable within ±1 count per counter.
- `phase5_counters_<class>.md` committed.

## References
- [PHASES.md § Phase 5](../references/PHASES.md)
- [tooling/BENCH-TOOLCHAIN.md § HotPathProfileSnapshot](../references/tooling/BENCH-TOOLCHAIN.md)
- [methodology/OPERATORS.md § Instrument-Hot-Path](../references/methodology/OPERATORS.md)
- [remediation/REMEDIATION-PATTERNS.md § Pattern 3 (algebraically-redundant counter elimination)](../references/remediation/REMEDIATION-PATTERNS.md)
