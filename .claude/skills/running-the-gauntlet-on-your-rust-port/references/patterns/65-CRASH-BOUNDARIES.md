# Pattern 65 — CRASH BOUNDARIES (named protocol-boundary injection)

## What

An enumeration of every named point in a protocol where a crash can occur, paired with `arm_crash_boundary(boundary)` that wires the [pattern:60-FAULT-VFS](60-FAULT-VFS.md) to inject a power-cut at exactly that point. After the crash, recovery runs and the consistency assertion is *not* "right state" but **"committed-or-not-committed, no partial"** — i.e., the recovered state is some consistent prefix of acknowledged operations, never a torn middle.

## Why

> "Verification: `arm_crash_boundary(boundary)` → crash at that exact point → recovery → assert consistent state (not 'right state' but 'committed-or-not-committed-no-partial')." — MINING-2 §9

A crash test that says "the system recovered to *some* state" is not a test. A crash test that says "the system recovered to a consistent prefix of acknowledged commits" is a test. The enumeration of named boundaries is what makes the test reproducible: instead of "the disk died at a random point", you say "the disk died at `AfterFsyncBeforePublish`", and the same test runs identically on every machine.

## Where in FrankenSQLite

- `crates/fsqlite-wal/src/fault_hooks.rs` — `CrashBoundary` enum + `arm_crash_boundary` (MINING-2 §9)
- Per-boundary recovery assertion in `crates/fsqlite-wal/tests/crash_boundary_*.rs`

## Verbatim shape — the 8 SQL-class WAL boundaries

From MINING-2 §9, verbatim:

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

pub fn arm_crash_boundary(boundary: CrashBoundary, hook: FaultHookArm) { }
```

### Recovery assertion (canonical)

```rust
#[test]
fn after_fsync_before_publish_yields_consistent_prefix() {
    let temp = tempfile::tempdir().unwrap();
    let db_path = temp.path().join("test.db");

    // Phase 1: workload + crash at exact boundary.
    {
        let conn = open_with_fault_vfs(&db_path, DEFAULT_FAULT_SEED);
        seed_workload(&conn, &["INSERT INTO t VALUES (1)", "INSERT INTO t VALUES (2)"]);
        arm_crash_boundary(CrashBoundary::AfterFsyncBeforePublish, FaultHookArm::Once);
        let _ = conn.execute("INSERT INTO t VALUES (3)"); // panics/aborts at boundary
    }

    // Phase 2: reopen + recover + assert consistent prefix.
    let recovered = open_with_real_vfs(&db_path);
    let rows = recovered.query_all("SELECT x FROM t ORDER BY x").unwrap();
    let xs: Vec<i64> = rows.into_iter().map(|r| r[0].parse().unwrap()).collect();

    // The crash was AFTER fsync but BEFORE publish.
    // Per WAL protocol, after-fsync-before-publish bytes ARE durable, so
    // recovery may include or exclude the (3); both are consistent prefixes.
    assert!(xs == vec![1, 2] || xs == vec![1, 2, 3],
        "recovered to non-prefix state: {xs:?}");
}
```

## Per-class boundary enumeration

### SQL-class — 8 WAL commit-protocol boundaries (verbatim above)

### RESP-class — 6+ AOF/RDB boundaries

From MINING-2 §9, verbatim:

```rust
pub enum RedisCrashBoundary {
    BeforeAofRewriteRename,            // AOF rewrite finished, rename not done
    DuringRdbWrite,                    // mid-RDB write to disk
    BeforeReplicationOffsetUpdate,     // command applied, offset not bumped
    MidPsync,                          // mid-partial-sync
    AfterReplOffsetBeforeAck,          // offset bumped, ack not sent
    DuringFsync,                       // fsync syscall in progress
}
```

Recovery assertion: post-restart, the in-memory KV is some consistent prefix of acknowledged commands, AND the AOF/RDB on disk is byte-recoverable to the same KV.

### ML-class — 5 checkpoint-save + 2 distributed-collective boundaries

From MINING-2 §9, verbatim:

```rust
pub enum TorchCrashBoundary {
    // Checkpoint save:
    BeforeSerialize,                  // before any bytes written
    MidShardWrite,                    // mid-write of one shard
    AfterShardBeforeMetadata,         // shard done, metadata index not yet updated
    MidMetadataUpdate,                // mid-update of metadata
    AfterRenameBeforeFsync,           // rename done, fsync not done

    // Distributed:
    MidAllReduce,                     // mid-NCCL all-reduce
    BeforeRendezvousAck,              // rank reached barrier, ack not sent
}
```

Recovery assertion: post-restart, the recovered checkpoint loads to a `state_dict` that's a consistent snapshot (all-or-nothing per shard); the distributed cluster either completes the collective on resume or fails fast — never silent partial.

### HTTP-class — 5 request-lifecycle boundaries

From MINING-2 §9, verbatim:

```rust
pub enum HttpCrashBoundary {
    BeforeOpen,                       // before connection accept
    AfterHeader,                      // headers received, body not started
    MidBody,                          // body chunk in transit
    AfterBodyBeforeClose,             // body done, close not yet sent
    AfterClose,                       // close sent, response not yet ack'd
    Cancellation,                     // client-side cancellation at arbitrary point
}
```

Recovery assertion: the downstream resource (DB row, file write, mailer queue) is either *fully* applied or *not at all* — never half-applied. Idempotency keys handle the "applied twice on retry" case.

## Composition

- [pattern:60-FAULT-VFS](60-FAULT-VFS.md) — the crash-boundary hook is wired through the FaultInjectingVfs's `PowerCut` injection.
- [pattern:70-E-PROCESSES](70-E-PROCESSES.md) — post-recovery consistency assertions feed into invariant monitoring (e.g., INV-6 CommitAtomicity).
- [pattern:90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) — `FailureBundle.failure_type = WalRecovery` carries the `CrashBoundary` discriminant.
- [pattern:25-FIXTURE-ROOT-CONTRACT](25-FIXTURE-ROOT-CONTRACT.md) — fault-profile fixtures enumerate which boundaries each profile exercises.

## The "consistency-or-no-partial" recovery assertion (verbatim)

> "Assert consistent state (not 'right state' but 'committed-or-not-committed-no-partial')." — MINING-2 §9

Three precise meanings depending on the boundary's position relative to "ack":

1. **Crash BEFORE ack** — neither the ack returned to the client nor the durable state need contain the operation. Recovery: the operation may or may not appear; if it does, it's complete.
2. **Crash AFTER ack BEFORE durability** — the client believes the operation completed; the protocol must guarantee durability (fsync). Recovery: the operation MUST appear.
3. **Crash AFTER ack AFTER durability** — fully committed. Recovery: the operation MUST appear, byte-identically.

A test that conflates these three is broken. Each boundary belongs to exactly one category; the test asserts the category-appropriate post-condition.

## Pitfalls

- **Asserting `xs == vec![1, 2, 3]` for an after-fsync-before-publish crash.** Both `[1,2]` and `[1,2,3]` are consistent prefixes; insisting on one over the other is incorrect (the publish step is what makes the commit visible, not the fsync). The assertion must allow either.
- **Generic crash injection ("kill -9 at random point").** Random crashes hit boundaries you've never named; you can't assert against them. Use named boundaries; random fuzzing finds new boundaries to name, not new bugs to fix.
- **Crash boundary that depends on a specific page size or WAL frame size.** A boundary like "after 8192 bytes" is fragile; "after first WAL frame appended" is robust. Name boundaries by *protocol event*, not byte offset.
- **Recovery test that doesn't actually crash the process.** Returning an error from the write path is NOT a crash; the in-memory state is intact, so recovery is trivial. Crash means *process death*; use `std::process::abort()` or fork + kill.
- **Asserting on the in-memory state instead of the post-restart state.** The whole point is recovery from durable storage. Drop the connection, reopen the file, then assert.
- **Skipping `AfterCheckpoint` because "the checkpoint is done, nothing to crash".** Checkpoint completion is a window — between marking the checkpoint complete and updating the SHM header, a crash leaves a half-state. Test it.
- **Not arming the boundary deterministically.** `FaultHookArm::Random` defeats the purpose. Use `FaultHookArm::Once` (fire at first opportunity) or `FaultHookArm::AfterNthOpportunity(n)` for deterministic placement.
- **One test per boundary, no cross-boundary.** Real-world crashes can hit any of the 8 boundaries; the suite should run all 8 in a loop with the same workload to surface boundary-specific recovery bugs.
- **Distributed-collective boundary tests run on one rank.** `MidAllReduce` is only meaningful when other ranks are mid-collective too. Use `LabRuntime`-style coordinated multi-process tests for distributed boundaries.
