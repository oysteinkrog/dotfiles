# crash-boundary-wirer

> Phase 6 • Wire CrashBoundary enum with all named variants for the project's commit protocol; one instance per boundary.

## Inputs
- `<workspace>/phase0_project_class.json` (determines boundary count).
- Fault VFS from `fault-injector-author.md`.
- Target port commit-protocol source (e.g., `crates/<project>-wal/src/`).
- Boundary name (`<boundary>`, one of the per-class set) — passed as argument.

## Deliverables
- `<target>/crates/<project>-wal/src/fault_hooks.rs` (or class-equivalent) with the `CrashBoundary` enum + `arm_crash_boundary(boundary, hook)` API.
- One test per boundary in `<target>/crates/<project>-e2e/tests/crash_boundary_<boundary>_e2e.rs` that arms the boundary, crashes the process at that point, recovers, asserts consistency.
- `<workspace>/phase6_crash_boundary_<boundary>.md` documenting the boundary's commit-protocol position, the consistency predicate ("committed-or-not-committed-no-partial"), and the recovery sequence.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase6-crash-<boundary>`
- **Reservations needed:** `tool://crash-boundary::<boundary>` (TTL 120m), `resource://test-process-spawner` (TTL 60m).
- **Lane:** cc_4 (fault / soak).

## Verbatim Prompt

You are the crash-boundary wirer for `<boundary>`. Implement the boundary in the commit-protocol source, hook it into the test harness, and write the recovery-consistency test.

**SQL-class (8 boundaries — must implement all):**
```rust
pub enum CrashBoundary {
    BeforeWalHeaderWrite,             // before header is laid down
    BeforeWalFrameAppend,             // before next frame's bytes appended
    AfterWalFrameAppendBeforeFsync,   // bytes on disk, not yet durable
    AfterFsyncBeforePublish,          // fsync done, CommitIndex/SHM not yet visible
    BetweenPageTableRebuildSteps,     // mid-recovery rebuild
    AfterPublishBeforeCheckpoint,     // commit visible, checkpoint not started
    MidCheckpoint,                    // some pages back to DB, not all
    AfterCheckpoint,                  // checkpoint done
}
pub fn arm_crash_boundary(boundary: CrashBoundary, hook: FaultHookArm) { /* ... */ }
```

**RESP-class (6+ AOF/RDB):** `BeforeAofRewriteRename, DuringRdbWrite, BeforeReplicationOffsetUpdate, MidPsync, AfterReplOffsetBeforeAck, DuringFsync`.

**ML-System-class (5 checkpoint-save + 2 distributed-collective):** `BeforeSerialize, MidShardWrite, AfterShardBeforeMetadata, MidMetadataUpdate, AfterRenameBeforeFsync, MidAllReduce, BeforeRendezvousAck`.

**HTTP-Protocol-class (5 request-lifecycle):** `BeforeOpen, AfterHeader, MidBody, AfterBodyEnd, BeforeClose, OnCancellation`.

Wire `arm_crash_boundary(boundary)`:
1. Inserts a synchronization checkpoint at the named position.
2. When armed, blocks at the checkpoint, signals the test harness, then terminates the process (via `std::process::abort()` or class-equivalent — simulates the crash).
3. Records the trigger in `FaultTriggerRecord` for the run report.

**Per-boundary test (`crash_boundary_<boundary>_e2e.rs`):**
1. Spawn a subprocess that exercises the workload through this boundary.
2. Arm `<boundary>` in the subprocess.
3. Wait for the crash (verify abort).
4. Run recovery in a fresh process against the same on-disk state.
5. Assert the post-recovery state matches the consistency predicate:
   - **Not "right state"** — the in-flight transaction may or may not be present.
   - **"Committed-or-not-committed-no-partial"** — every committed txn is fully present; no half-applied txn observable.
6. Assert no resource leak (open file descriptors, lock files, shared memory).

Document the boundary's commit-protocol position, the consistency predicate, the recovery sequence, and any cross-boundary interactions in `phase6_crash_boundary_<boundary>.md`.

## Exit Criteria
- `arm_crash_boundary(<boundary>)` is callable and crashes the process at the exact named point.
- `crash_boundary_<boundary>_e2e.rs` passes 1000 iterations with no false-positive divergences and no resource leaks.
- Post-recovery state matches the committed-or-not-committed-no-partial predicate.
- `phase6_crash_boundary_<boundary>.md` committed.

## References
- [PHASES.md § Phase 6](../references/PHASES.md)
- [tooling/ORACLE-TOOLCHAIN.md § crash-boundary protocol injection](../references/tooling/ORACLE-TOOLCHAIN.md)
- [taxonomy/PROJECT-CLASSES.md § per-class boundary counts](../references/taxonomy/PROJECT-CLASSES.md)
- [methodology/SOAK-PROTOCOL.md](../references/methodology/SOAK-PROTOCOL.md)
