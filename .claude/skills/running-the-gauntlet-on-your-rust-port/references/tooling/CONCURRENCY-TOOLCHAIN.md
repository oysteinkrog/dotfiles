# CONCURRENCY-TOOLCHAIN.md — loom / shuttle / asupersync / Fault VFS / Crash Boundaries / Deadlock Taxonomy

How to exhaustively explore interleavings of concurrent primitives (`loom`), randomly sample large interleaving spaces (`shuttle`), deterministically replay schedules of distributed protocols (`asupersync LabRuntime` with DPOR + Mazurkiewicz traces), and inject crashes at named protocol boundaries (Fault VFS). Cross-links: [SANITIZER-TOOLCHAIN.md](SANITIZER-TOOLCHAIN.md) for TSan as a runtime data-race detector; [FUZZ-TOOLCHAIN.md](FUZZ-TOOLCHAIN.md) for differential fuzz of concurrent APIs; [ORACLE-TOOLCHAIN.md](ORACLE-TOOLCHAIN.md) for the crash-boundary parity oracle.

## 0. Core Discipline

> **Concurrency bugs are not "rare race conditions"; they are exhaustively-or-statistically explorable interleavings.** `loom` explores them all (small state spaces); `shuttle` samples millions (large state spaces); fault VFS forces crashes at named protocol boundaries; the deadlock taxonomy says where to look. **There is almost always a fourth instance.**

---

## 1. `loom` — Exhaustive Interleaving Exploration

For testing concurrent primitives (Mutex, AtomicU64, channels) under EVERY possible thread interleaving.

### 1.1 Setup

```toml
# Cargo.toml
[dev-dependencies]
loom = "0.7"

[features]
loom = []
```

```rust
// crates/fsqlite-mvcc/src/atomic_gate.rs

#[cfg(loom)]
pub(crate) use loom::sync::atomic::{AtomicBool, Ordering};
#[cfg(not(loom))]
pub(crate) use std::sync::atomic::{AtomicBool, Ordering};

#[cfg(loom)]
pub(crate) use loom::sync::Arc;
#[cfg(not(loom))]
pub(crate) use std::sync::Arc;
```

### 1.2 Test Skeleton

```rust
// crates/fsqlite-mvcc/tests/loom_atomic_gate.rs
#![cfg(loom)]

use loom::thread;
use std::sync::Arc;

#[test]
fn loom_atomic_gate_no_lost_wakeup() {
    loom::model(|| {
        let gate = Arc::new(AtomicGate::new());
        let g1 = gate.clone();
        let g2 = gate.clone();

        let producer = thread::spawn(move || {
            g1.signal();
        });
        let consumer = thread::spawn(move || {
            g2.wait();
        });

        producer.join().unwrap();
        consumer.join().unwrap();
    });
}
```

### 1.3 Run

```bash
cargo +nightly test --test loom_atomic_gate --features loom --release
```

### 1.4 Configuration

```bash
# Bound exploration to avoid combinatorial explosion
RUSTFLAGS="--cfg loom" \
LOOM_MAX_PREEMPTIONS=3 \
LOOM_LOCATION=1 \
cargo +nightly test --test loom_atomic_gate --features loom --release
```

| Env var | Meaning |
|---|---|
| `LOOM_MAX_PREEMPTIONS` | Cap on number of preemptions per execution. Default 2. Increase carefully — 4+ can take hours. |
| `LOOM_MAX_BRANCHES` | Stops exploration after N branches. Use for time-bounded debugging. |
| `LOOM_LOCATION=1` | Records source location for each operation; crash dumps cite the line. |
| `LOOM_CHECKPOINT_FILE=foo` | Resume from checkpoint after Ctrl-C; great for week-long explorations. |

### 1.5 The Small-State-Space Gotcha

> **Loom's state space grows exponentially in operation count.** A 4-operation test explores ~10^3 schedules in seconds; a 12-operation test explores ~10^9 schedules and never finishes.

Rule: loom tests model a **primitive**, not a workflow. Test `AtomicGate::signal_then_wait`, not `BeginTransaction → Insert → Commit`. The latter is `shuttle`'s job (§2).

If loom hits state explosion: split the test into smaller primitives, or relax `LOOM_MAX_PREEMPTIONS`.

---

## 2. `shuttle` — Faster Probabilistic Complement to loom

Same API shape as `loom`, but instead of exhaustively exploring schedules, samples them randomly. Much faster; catches the bugs loom would catch in a tiny fraction of the schedules but with no guarantee of completeness.

### 2.1 Setup

```toml
[dev-dependencies]
shuttle = "0.7"

[features]
shuttle = []
```

```rust
#[cfg(shuttle)]
use shuttle::{thread, sync::Mutex};
#[cfg(not(shuttle))]
use std::{thread, sync::Mutex};
```

### 2.2 Test Skeleton

```rust
// crates/fsqlite-mvcc/tests/shuttle_concurrent_commit.rs
#![cfg(shuttle)]

use shuttle::check_random;

#[test]
fn shuttle_concurrent_commit_invariant() {
    check_random(
        || {
            let db = setup_database();
            let h1 = shuttle::thread::spawn({ let db = db.clone(); move || db.commit_txn(1) });
            let h2 = shuttle::thread::spawn({ let db = db.clone(); move || db.commit_txn(2) });
            h1.join().unwrap();
            h2.join().unwrap();
            assert!(db.invariant_holds());
        },
        100_000,   // number of random schedules
    );
}
```

### 2.3 Run

```bash
cargo +nightly test --test shuttle_concurrent_commit --features shuttle --release
```

### 2.4 Schedule-Controlling Strategies

| Strategy | When |
|---|---|
| `check_random(f, iters)` | First pass; fast; 100K iters is ~minutes. |
| `check_pct(f, iters, depth)` | "Probabilistic concurrency testing"; biases toward bug-finding schedules. Better than random when bugs are rare. |
| `check_dfs(f, max_depth)` | Bounded DFS over schedules; like loom but with explicit depth bound. Good middle ground. |
| `check_replay(f, schedule)` | Replay a specific schedule from a logged failure. Used for triage. |

### 2.5 Loom vs Shuttle Decision

| Property | loom | shuttle |
|---|---|---|
| Soundness (guaranteed to find bug if exists) | Yes (within preemption bound) | No (probabilistic) |
| Throughput | 100s of schedules/sec | 100Ks/sec |
| Memory cost | Linear in schedule depth | Constant |
| State-space ceiling | ~10^6 schedules | ~10^9+ schedules |
| Use for | Primitive correctness | Workflow correctness |

**Both** are run in Phase 15 soak; loom on primitives, shuttle on workflows.

---

## 3. asupersync `LabRuntime` — Deterministic Distributed-Protocol Testing

For testing **distributed** protocols (multi-process MVCC, replication, AOF, distributed training) under deterministic virtual time + DPOR (Flanagan-Godefroid POPL 2005) + Mazurkiewicz traces (1977).

### 3.1 Why Not Just shuttle?

`shuttle` controls thread interleavings within a single process. Distributed protocols span processes, sockets, file systems. `LabRuntime` simulates the full distributed stack with virtual time.

### 3.2 Wiring Pattern

```rust
use asupersync::{LabRuntime, VirtualClock};

#[test]
fn replication_consistency_under_message_reordering() {
    let mut lab = LabRuntime::new();
    let clock  = lab.virtual_clock();

    let master_node  = lab.spawn_node("master",  fsqlite_master_main);
    let replica_node = lab.spawn_node("replica", fsqlite_replica_main);

    // Inject a message-reordering schedule
    lab.set_message_scheduler(MessageScheduler::ReverseAfter(Duration::from_millis(50)));

    lab.run_until(clock.virtual_seconds(10.0));

    let master_state  = master_node.snapshot_state();
    let replica_state = replica_node.snapshot_state();
    assert_eq!(master_state, replica_state);
}
```

### 3.3 DPOR — Dynamic Partial Order Reduction

DPOR (Flanagan-Godefroid POPL 2005) avoids exploring schedules that are **equivalent up to Mazurkiewicz traces** — two events that commute (independent operations on disjoint state) only need one schedule explored, not both orderings.

For an N-event execution where K events pairwise commute, the search space drops from N! to ~(N/K)!. For typical distributed protocols this is the difference between minutes and centuries.

### 3.4 Mazurkiewicz Traces

A Mazurkiewicz trace is the equivalence class of all schedules that produce the same partial order of dependent events. Operations on disjoint resources commute; operations on shared resources do not. `LabRuntime` computes the commutativity relation from the I/O type signatures and uses it to drive DPOR.

### 3.5 Run

```bash
cargo +nightly test --test labruntime_replication --features asupersync --release
```

---

## 4. Crash-Boundary Protocol Injection — 8 Named WAL Boundaries

**File:** `crates/fsqlite-wal/src/fault_hooks.rs`

Verbatim from MINING-2 §9:

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

### Verification Pattern

`arm_crash_boundary(boundary)` → crash at that exact point → recovery → assert consistent state (not "right state" but "committed-or-not-committed-no-partial").

The invariant is **atomicity, not durability**: after recovery, every committed transaction is either fully present or fully absent. No partial commits, no half-applied DDL, no truncated rows.

### Per-Class Boundary Counts (Verbatim)

| Project | Boundaries |
|---------|-----------|
| FrankenSQLite | 8 WAL commit-protocol boundaries (above) |
| FrankenRedis | 6+ AOF/RDB: `BeforeAofRewriteRename`, `DuringRdbWrite`, `BeforeReplicationOffsetUpdate`, `MidPsync`, `AfterReplOffsetBeforeAck`, `DuringFsync` |
| FrankenTorch | 5 checkpoint-save: `BeforeSerialize`, `MidShardWrite`, `AfterShardBeforeMetadata`, `MidMetadataUpdate`, `AfterRenameBeforeFsync`; plus distributed: `MidAllReduce`, `BeforeRendezvousAck` |
| FastAPI | 5 request-lifecycle: open/header/body-start/body-end/close + cancellation |

### Wiring Pattern

```rust
#[test]
fn wal_atomicity_at_every_boundary() {
    use CrashBoundary::*;
    for boundary in [BeforeWalHeaderWrite, BeforeWalFrameAppend, AfterWalFrameAppendBeforeFsync,
                     AfterFsyncBeforePublish, BetweenPageTableRebuildSteps, AfterPublishBeforeCheckpoint,
                     MidCheckpoint, AfterCheckpoint] {
        let db = setup_test_database();
        let txn_id = db.begin_transaction();
        db.insert("INSERT INTO t VALUES (1, 2, 3)");

        arm_crash_boundary(boundary, FaultHookArm::FireOnce);

        let _ = db.commit();   // may panic via the armed hook
        drop(db);

        // Reopen — recovery runs
        let db = reopen_test_database();
        let committed_rows = db.query_count("SELECT * FROM t");
        // Atomicity invariant: either 0 rows (txn aborted) or all rows (txn committed). Never partial.
        assert!(committed_rows == 0 || committed_rows == 1,
            "atomicity violation at {boundary:?}: partial commit");
    }
}
```

---

## 5. Fault VFS — Deterministic Crash Testing

**File:** `crates/fsqlite-harness/src/fault_vfs.rs` (bd-3go.2, 57 KB in FrankenSQLite)

Verbatim from MINING-2 §8:

### FaultKind Enum

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

### FaultSpec Struct

```rust
pub struct FaultSpec {
    pub file_glob:        String,
    pub kind:             FaultKind,
    pub at_offset:        Option<u64>,
    pub after_nth_sync:   Option<u32>,
    after_count:          Option<u64>,
    max_triggers:         u32,
    trigger_count:        u32,
    match_count:          u64,
}
```

### Usage Idiom

```rust
let mut vfs = FaultInjectingVfs::new(MemoryVfs::new());
vfs.inject_fault(FaultSpec::torn_write("*.wal")
    .at_offset_bytes(8192)
    .valid_bytes(17));
vfs.inject_fault(FaultSpec::power_cut("*.wal").after_nth_sync(2));
```

### Determinism Contract

```rust
const DEFAULT_FAULT_SEED: u64 = 0xD1A6_A3F4_9B17_0C5E;
// Torn-write at WAL offset 8192 with valid_bytes=17 produces exactly 17 bytes every run.
```

Same fault spec + same seed → byte-identical fault sequence across runs. Reproducible bug reports.

### F-1..F-8 Adoption Checklist

| ID | Step |
|---|---|
| F-1 | Define `FaultKind` enum. |
| F-2 | Define `FaultSpec` with declarative rules + stable seeds. |
| F-3 | Wire `FaultInjectingVfs` around real VFS layer. |
| F-4 | Define named profiles (e.g., `torn-wal-frame`, `partial-checkpoint`). |
| F-5 | Each profile has `expected_behavior.invariants_preserved`. |
| F-6 | Metric counter `fsqlite_test_vfs_faults_injected_total`. |
| F-7 | Each fault becomes `FaultTriggerRecord` in run report. |
| F-8 | CI dashboard answers "how many partial writes did we exercise this week". |

### Per-Class Adaptations

| Class | Fault module |
|---|---|
| **FrankenRedis** | `RdbFaultVfs` — partial AOF rewrites, mid-rdb torn writes, fsync-then-power-cut, `EAGAIN` storms on replication socket. |
| **FrankenTorch** | `CheckpointFaultVfs` — partial `torch.save`, mid-shard NCCL drops, `CUDA_ERROR_LAUNCH_FAILED` mid-collective. |
| **FastAPI Rust** | `RequestFaultMiddleware` — connection drops mid-body, slow-loris, partial multipart. |

---

## 6. 9-Class Deadlock Taxonomy

From `/deadlock-finder-and-fixer`. **There is almost always a fourth instance** — when you find three of one class, search for the fourth before declaring the class closed.

### The Nine Classes

| # | Class | Symptom | Where to look |
|---|---|---|---|
| **1** | **Classic AB-BA** | Two threads hold A and B in opposite order, each waiting for the other's lock. | Audit every function holding ≥2 locks; build the lock-acquire graph; cycles = bugs. |
| **2** | **Async/sync re-entrance** | Async task holds lock, calls sync function that re-acquires the same lock. | Search for `block_on(...)` inside an `async` body that's reachable while holding a lock. |
| **3** | **Waker starvation** | Future is woken but the executor never re-polls it (e.g., dropped Waker, single-thread runtime overloaded). | Audit every `wake()`; ensure the Waker isn't dropped before the wake happens. |
| **4** | **RAII Drop in lock scope** | `Drop` impl re-enters the lock the guard is holding. | Audit every type with a `Drop` impl; check no path acquires the same lock. |
| **5** | **Reader-writer upgrade** | Reader holds shared lock, tries to upgrade to exclusive; another reader holds shared → deadlock. | Avoid `RwLock::upgradable_read → upgrade`. Use `Mutex` or release-then-acquire. |
| **6** | **Channel/queue cycle** | Task A sends to B's queue while holding A's queue mutex; B sends to A while holding B's. | Build the channel-dependency graph; cycles = bugs. |
| **7** | **Shared cache miss-storm** | First requester holds cache lock while loading; N concurrent requesters wait on same lock. | Use `OnceCell::get_or_try_init` or singleflight pattern; not raw `Mutex<Option<T>>`. |
| **8** | **Signal handler in critical section** | Signal arrives mid-lock; handler calls non-async-signal-safe code that acquires same lock. | Audit `signal-hook` registrations; signal handlers MUST NOT lock. |
| **9** | **External resource (DB, socket, FS) cycle** | Thread A holds DB lock while waiting on HTTP that needs to call DB again. | Build cross-system call graph; outbound calls from locked sections = suspicious. |

### Discipline: "There is almost always a fourth instance"

When you find an AB-BA pair in `commit.rs` and another in `recovery.rs` and another in `checkpoint.rs`, **search for the fourth in `replication.rs`** before declaring the AB-BA class closed. The fourth instance has bitten every FrankenSQLite agent who didn't look for it.

### Detection Strategy per Class

| Class | Tool |
|---|---|
| 1 (AB-BA) | `parking_lot::deadlock::check_deadlock()`; loom; manual lock-acquire-graph audit. |
| 2 (re-entrance) | Static: search for `block_on` inside `async fn`. Dynamic: TSan (see [SANITIZER-TOOLCHAIN.md](SANITIZER-TOOLCHAIN.md)). |
| 3 (waker starvation) | `tokio-console` traces; assert every Future polled within budget. |
| 4 (Drop) | Manual audit; cargo-expand to see Drop sites. |
| 5 (RW upgrade) | Ban `upgradable_read` via clippy lint. |
| 6 (channel cycle) | tokio-console; manual call graph. |
| 7 (cache storm) | Replace `Mutex<Option<T>>` with `OnceCell`. |
| 8 (signal) | Manual audit; signal handlers strictly async-signal-safe. |
| 9 (external cycle) | Distributed trace; no outbound calls from locked sections. |

---

## 7. Specific Test Commands

```bash
# loom — exhaustive interleaving
RUSTFLAGS="--cfg loom" \
LOOM_MAX_PREEMPTIONS=3 LOOM_LOCATION=1 \
cargo +nightly test --test 'loom_*' --features loom --release

# shuttle — random interleavings (100K iters, ~minutes)
cargo +nightly test --test 'shuttle_*' --features shuttle --release

# asupersync LabRuntime
cargo +nightly test --test 'labruntime_*' --features asupersync --release

# Crash-boundary suite (each test boundary-parameterized)
cargo +nightly test --test 'crash_boundary_*' --release

# Fault-VFS suite (per named profile)
cargo +nightly test --test 'fault_vfs_*' --release

# TSan — runtime data-race detector (cross-link: SANITIZER-TOOLCHAIN.md)
RUSTFLAGS="-Zsanitizer=thread" \
cargo +nightly test --target x86_64-unknown-linux-gnu --release

# parking_lot deadlock detector — must be called from a watchdog thread
# (typically a long-running E2E test)
```

---

## 8. Per-Class Adaptations Summary

### FrankenSQLite (SQL-class)
- loom: AtomicGate, PublishedPages, ShardedPageCache primitives
- shuttle: concurrent_commit workflow with 4+ writers
- LabRuntime: swarm-multiprocess style cross-process MVCC
- crash boundary: 8 WAL boundaries
- fault VFS: torn-write, power-cut, mid-checkpoint

### FrankenRedis (RESP-class)
- loom: dict probe, replication offset CAS
- shuttle: pubsub FIFO ordering, transaction-block (MULTI/EXEC) atomicity
- LabRuntime: master + N replicas under message reordering
- crash boundary: 6 AOF/RDB boundaries
- fault VFS: `RdbFaultVfs`

### FrankenTorch (ML-System class)
- loom: autograd tape append, kernel-launch queue
- shuttle: multi-GPU all-reduce ordering
- LabRuntime: distributed training with rendezvous
- crash boundary: 5 checkpoint + 2 distributed-collective
- fault VFS: `CheckpointFaultVfs`

### FastAPI (HTTP-class)
- loom: request queue, middleware chain
- shuttle: connection-pool fairness under contention
- LabRuntime: rarely needed (single-process); useful for service mesh
- crash boundary: 5 request-lifecycle
- fault VFS: `RequestFaultMiddleware`

---

## 9. Pitfalls

| Pitfall | Why it bites | Fix |
|---|---|---|
| Loom state-space explosion | Test with 15 ops runs for days, finds nothing | Split into per-primitive tests; bound `LOOM_MAX_PREEMPTIONS=3`. |
| Shuttle non-determinism | Bug found once, can't repro | Capture schedule on failure (`shuttle::record_schedule`); replay via `check_replay`. |
| Loom + std::sync mixed | Loom only intercepts loom types; std::sync escapes the model | All concurrent types go through the `#[cfg(loom)]` swap; no exceptions. |
| Crash boundary not visible | Bug at `MidCheckpoint` blamed on checkpoint code, not the partial-state recovery | Enumerate every boundary explicitly; name it; arm one at a time. |
| Fault VFS over-aggressive | Every test crashes; coverage drops | Per profile `max_triggers` bound; named profile with `expected_behavior.invariants_preserved`. |
| Fault seed unstable | "Same fault" produces different bytes each run | `DEFAULT_FAULT_SEED` is a constant; pin it; never use `rand::random()`. |
| Single deadlock class declared closed too early | Class 1 (AB-BA) "fixed" but Class 9 (DB-HTTP cycle) ignored | Audit ALL 9 classes after fixing any one. There is almost always a fourth instance — and likely a different class entirely. |
| TSan with loom | Loom replaces sync primitives; TSan doesn't see them | Run TSan WITHOUT loom (against real std types); run loom WITHOUT TSan. |
| LabRuntime in CI | Long-running, machine-pinned | Run nightly in `rch`, not in PR CI. |
| Signal handlers in tests | Test races signal handler against test body | Don't install handlers in tests; mock the signal path. |

---

## See Also

- [SANITIZER-TOOLCHAIN.md](SANITIZER-TOOLCHAIN.md) — TSan as runtime data-race detector; complementary to loom (static-state) and shuttle (random-state).
- [FUZZ-TOOLCHAIN.md](FUZZ-TOOLCHAIN.md) — differential fuzz against concurrent APIs; combine with loom for primitive coverage.
- [ORACLE-TOOLCHAIN.md](ORACLE-TOOLCHAIN.md) — the crash-boundary parity oracle that asserts post-recovery consistency.
- [BENCH-TOOLCHAIN.md](BENCH-TOOLCHAIN.md) — mt-mvcc-bench / mt-oltp-bench / swarm-multiprocess for concurrent perf.
- [../methodology/SOAK-PROTOCOL.md](../methodology/SOAK-PROTOCOL.md) — multi-day loom + shuttle + LabRuntime + fault-VFS campaigns in Phase 15.
