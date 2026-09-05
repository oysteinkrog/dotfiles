# 75-LOCK-FREE-PATTERNS.md — Lock-Free Data Structures Audit

Hand-rolled lock-free data structures are a frequent source of subtle bugs. The audit's bias is strongly toward "use a vetted crate instead" — but lock-free runtime crates ARE the exception (they're the project's purpose).

This file is the audit protocol for sites that look lock-free.

---

## The decision tree

```
Is the project ITSELF a lock-free primitive (queue, allocator, runtime)?
├─ Yes → (A) cluster; audit per-line; loom mandatory.
└─ No → (C) refactor: swap for a vetted crate.
```

---

## Vetted lock-free crates

| Pattern | Crate(s) | Audited? |
|---------|----------|----------|
| Atomic-Arc replacement | `arc-swap` | Yes (well-known; used by `tokio`, `tracing`) |
| MPMC queue (unbounded) | `crossbeam::queue::SegQueue` | Yes |
| MPMC queue (bounded) | `crossbeam::queue::ArrayQueue` | Yes |
| MPMC channel | `crossbeam::channel`, `flume`, `kanal` | Yes |
| Async channel | `tokio::sync::mpsc`, `async-channel` | Yes |
| Concurrent map | `dashmap`, `scc`, `papaya` | Yes |
| Lock-free Vec-like | `lockfree::queue::Queue`, `concurrent-queue` | Yes |
| Generational concurrent map | `evmap` (older), `flurry` | Yes |
| Wait-free deque (work-stealing) | `crossbeam::deque::Worker` / `Stealer` | Yes |
| Atomic option | `arc-swap::ArcSwapOption`, custom | Yes |

The (C) refactor: identify the pattern; swap for the vetted crate.

---

## When custom lock-free is justified

A custom impl is justified when:

1. **No vetted crate covers the pattern.** Truly novel; rare.
2. **The vetted crate's perf is unacceptable on this workload AND the gap is measured.** Per [20-SIMD-AND-PERF.md § Per-target bench protocol](20-SIMD-AND-PERF.md), the gap must be documented with criterion + hyperfine + flamegraph.
3. **The vetted crate adds a dep that the project explicitly excludes** (e.g., no-std targets where crossbeam isn't available).

In all cases, the (A) for the custom impl requires:

- Loom model exercising every public method from 2+ threads.
- Reasoning about every Ordering choice (per [35-ATOMICS-AND-ORDERINGS.md](35-ATOMICS-AND-ORDERINGS.md)).
- ABA-safety analysis (does the data structure use generational counters / tagged pointers / hazard pointers?).
- Memory reclamation strategy: epoch-based (crossbeam-epoch), hazard pointers (haphazard), reference-counted (Arc), or "leak on remove" (rare; documented).

---

## Pattern LF-1 — Replace hand-rolled CAS loop with `arc-swap`

Common case: a config that's swapped atomically and read frequently:

```rust
// Before — hand-rolled
struct Config {
    inner: AtomicPtr<Inner>,
}
impl Config {
    fn store(&self, new: Arc<Inner>) {
        let raw = Arc::into_raw(new) as *mut Inner;
        let old = self.inner.swap(raw, Ordering::AcqRel);
        if !old.is_null() {
            unsafe { Arc::from_raw(old); }
        }
    }
    fn load(&self) -> Arc<Inner> {
        let raw = self.inner.load(Ordering::Acquire);
        unsafe {
            Arc::increment_strong_count(raw);
            Arc::from_raw(raw)
        }
    }
}

// After
use arc_swap::ArcSwap;
struct Config {
    inner: ArcSwap<Inner>,
}
impl Config {
    fn store(&self, new: Arc<Inner>) { self.inner.store(new); }
    fn load(&self) -> Arc<Inner> { self.inner.load_full() }
}
```

The hand-rolled version had 3 unsafe blocks (`Arc::into_raw`, `Arc::increment_strong_count`, `Arc::from_raw`). The replacement has zero project-side unsafe; the (A) lives in arc-swap's internals.

---

## Pattern LF-2 — Replace hand-sharded HashMap with `DashMap`

Concurrent map access via a per-shard lock is common:

```rust
// Before — hand-sharded with N Mutex<HashMap>
struct ShardedMap {
    shards: [Mutex<HashMap<K, V>>; 16],
}
impl ShardedMap {
    fn shard_index(&self, key: &K) -> usize {
        // hash function
    }
    fn insert(&self, k: K, v: V) {
        let i = self.shard_index(&k);
        self.shards[i].lock().unwrap().insert(k, v);
    }
}

// After
use dashmap::DashMap;
let map: DashMap<K, V> = DashMap::new();
map.insert(k, v);
```

`dashmap` shards internally; the API is HashMap-shaped. Auto-derives Send + Sync. Project-side unsafe count drops to zero.

---

## Pattern LF-3 — Work-stealing deque

When implementing a custom task scheduler, work-stealing is the standard pattern:

```rust
use crossbeam::deque::{Worker, Stealer};

let local_worker: Worker<Task> = Worker::new_fifo();
let stealer: Stealer<Task> = local_worker.stealer();

// On the local thread:
local_worker.push(task);
if let Some(t) = local_worker.pop() { execute(t); }

// On a stealing thread:
match stealer.steal() {
    crossbeam::deque::Steal::Success(t) => execute(t),
    crossbeam::deque::Steal::Empty => /* idle */,
    crossbeam::deque::Steal::Retry => continue,
}
```

The (A) is in crossbeam-deque's impl. Consumer code is safe.

**Refactor (C):** projects with hand-rolled work-stealing typically have 5-20 unsafe sites; swap to crossbeam-deque eliminates them.

---

## Pattern LF-4 — Epoch-based memory reclamation

For lock-free data structures that need to free memory:

```rust
use crossbeam::epoch::{Atomic, Guard, Owned};

struct LfList<T> {
    head: Atomic<Node<T>>,
}

impl<T> LfList<T> {
    fn insert(&self, value: T) {
        let guard = crossbeam::epoch::pin();
        let new = Owned::new(Node { value, next: Atomic::null() });
        loop {
            let cur = self.head.load(Ordering::Acquire, &guard);
            new.next.store(cur, Ordering::Relaxed);
            match self.head.compare_exchange(
                cur, new.into_shared(&guard),
                Ordering::AcqRel, Ordering::Acquire, &guard
            ) {
                Ok(_) => break,
                Err(e) => { new = e.new.into_owned(); }
            }
        }
    }
}
```

The `crossbeam::epoch` framework handles memory reclamation safely; nodes are freed only when no thread is holding a guard. Consumer code uses the framework's API; the unsafe is internal to crossbeam-epoch.

---

## When loom isn't enough

Loom catches finite-interleaving bugs within the budget. For unbounded-state data structures (e.g., queues with arbitrary item counts), loom needs careful bounding:

- Test with 2 producer threads, 2 consumer threads, fixed item counts.
- Use `loom::model::Builder::preemption_bound(3)` for deeper schedules.
- Document the bound; the loom test verifies INTERLEAVINGS within the bound, not arbitrary item-counts.

For coverage beyond loom: use **shuttle** (different randomized concurrency tester) and run on real hardware (aarch64 + x86_64) for hours.

---

## Anti-patterns

- **Custom lock-free queue without loom.** Bug-prone; loom is the minimum.
- **Custom lock-free without an ABA analysis.** Tagged pointers or generations are usually needed; document.
- **Releasing-without-Acquiring.** A `Release` write only synchronizes with an `Acquire` read; without the Acquire side, no synchronization.
- **Using `Relaxed` for the success ordering of a CAS that gates other state.** The CAS's success ordering must be at least Acquire if it gates a subsequent read; AcqRel if it gates both read AND write.

---

## Exemplar precedent

- `/dp/franken_engine/src/sched/work_steal.rs` — uses `crossbeam::deque`. Was hand-rolled briefly; refactored after measured perf was equivalent. (C).
- `/dp/franken_engine/src/config.rs` — `arc-swap::ArcSwap<Config>` for hot-reload. (C).
- `/dp/asupersync/src/io/cqe_reader.rs` — single-threaded by ownership; `unsafe impl Sync` removed in favor of `!Sync`. (C).

---

## Acceptance signal

A lock-free site passes when:

1. The pattern matches a vetted-crate (LF-1 through LF-4) OR the custom impl is justified per the three criteria.
2. For custom impls: loom model exists; ABA analysis is documented; memory reclamation strategy is named.
3. Orderings are weakest correct.
4. cross-architecture tested (aarch64 + x86_64).
5. miri + loom + stress test pass.
