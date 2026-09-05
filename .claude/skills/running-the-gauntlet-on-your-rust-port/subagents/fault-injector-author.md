# fault-injector-author

> Phase 6 • Build FaultKind + FaultSpec with stable seeds + named profiles with expected_behavior.invariants_preserved; one instance per fault category.

## Inputs
- `<workspace>/phase0_project_class.json` (selects fault taxonomy).
- Fault category (`<category>`, one of `torn_write | partial_write | power_cut | io_error | read_failure | write_failure | latency | disk_full | network_drop | rdb_corruption | aof_truncation | nccl_drop | checkpoint_corruption | request_drop | header_truncation`) — passed as argument.
- Target port VFS / IO layer.

## Deliverables
- `<target>/crates/<project>-harness/src/fault_vfs.rs` extended with the relevant `FaultKind` variant + `FaultSpec` builder.
- Named fault profiles under `<target>/crates/<project>-harness/src/fault_profiles/<category>.rs` with `expected_behavior.invariants_preserved`.
- Metric counter `<project>_test_vfs_faults_injected_total` increments per injection.
- Per-trigger `FaultTriggerRecord` in the run report.
- `<workspace>/phase6_fault_<category>.md` documenting the F-1..F-8 checklist completion + invariants-preserved spec.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase6-fault-<category>`
- **Reservations needed:** `tool://fault-vfs-write::<category>` (TTL 90m).
- **Lane:** cc_4 (fault / soak).

## Verbatim Prompt

You are the fault injector author for category `<category>`. Follow the F-1..F-8 adoption checklist verbatim:

- **F-1:** Define the `FaultKind` enum entry. Canonical SQL-class enum (extend per class):
```rust
pub enum FaultKind {
    TornWrite     { valid_bytes: usize },
    PartialWrite  { valid_bytes: usize },
    PowerCut,
    IoError,
    ReadFailure,
    WriteFailure,
    Latency       { base_millis: u64, jitter_millis: u64 },
    DiskFull,
}
```
- **F-2:** Define `FaultSpec` with declarative rules + stable seeds:
```rust
pub struct FaultSpec {
    pub file_glob: String, pub kind: FaultKind,
    pub at_offset: Option<u64>, pub after_nth_sync: Option<u32>,
    after_count: Option<u64>, max_triggers: u32, trigger_count: u32, match_count: u64,
}
const DEFAULT_FAULT_SEED: u64 = 0xD1A6_A3F4_9B17_0C5E;
```
- **F-3:** Wire `FaultInjectingVfs` (or class-equivalent: `RdbFaultVfs`, `CheckpointFaultVfs`, `RequestFaultMiddleware`) around the real VFS / IO layer.
- **F-4:** Define named profiles (e.g., `torn-wal-frame`, `partial-checkpoint`, `power-cut-mid-commit`).
- **F-5:** Each profile records `expected_behavior.invariants_preserved`: which invariants must hold after recovery (e.g., `committed_or_not_committed`, `no_partial_commit`, `wal_recoverable_to_consistent_state`).
- **F-6:** Metric counter `<project>_test_vfs_faults_injected_total` increments per injection.
- **F-7:** Each triggered fault emits a `FaultTriggerRecord { profile, kind, file, offset, trigger_index, timestamp }` into the run report.
- **F-8:** CI dashboard answers "how many `<category>` faults did we exercise this week".

**Determinism rule:** Same seed + same scenario → same fault triggered at same offset every run. Verify by running the same scenario twice and asserting `FaultTriggerRecord` sequences are byte-identical.

Per-class adaptations (write the appropriate variant):
- **SQL-class:** `FaultInjectingVfs` around the OS VFS; torn WAL frames at offset 8192 with `valid_bytes=17`; power-cut after-nth-sync.
- **RESP-class:** `RdbFaultVfs` — partial AOF rewrites, mid-RDB torn writes, fsync-then-power-cut, `EAGAIN` storms on replication socket.
- **ML-System-class:** `CheckpointFaultVfs` — partial `torch.save`, mid-shard NCCL drops, `CUDA_ERROR_LAUNCH_FAILED` mid-collective.
- **HTTP-Protocol-class:** `RequestFaultMiddleware` — connection drops mid-body, slow-loris, partial multipart.

Document F-1..F-8 completion + invariants-preserved spec in `phase6_fault_<category>.md`.

## Exit Criteria
- Every F-1..F-8 step has a passing acceptance test.
- Determinism test: two runs of the same scenario produce byte-identical `FaultTriggerRecord` sequences.
- `expected_behavior.invariants_preserved` is non-empty for every named profile.
- `<project>_test_vfs_faults_injected_total` counter increments on every injection (verified by `cargo test --test fault_<category>_smoke`).
- `phase6_fault_<category>.md` committed.

## References
- [PHASES.md § Phase 6](../references/PHASES.md)
- [tooling/ORACLE-TOOLCHAIN.md § Fault VFS / FaultSpec](../references/tooling/ORACLE-TOOLCHAIN.md)
- [taxonomy/PROJECT-CLASSES.md § per-class fault adaptations](../references/taxonomy/PROJECT-CLASSES.md)
