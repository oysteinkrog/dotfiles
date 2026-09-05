# 30-CONCURRENCY-PATTERNS.md — Safer Concurrent Data Structures

Hand-rolled lock-free patterns (CAS loops, hazard pointers, RCU) are common in performance-sensitive Rust. Most of them have well-tested crate equivalents that are EITHER fully safe OR have a smaller, audited unsafe surface than the project's own attempt.

This file catalogs the swap candidates.

---

## arc-swap: atomic Arc replacement

**Use when.** The project has an `AtomicPtr<T>` that's "an Arc<T>, atomically swappable."

**Hand-rolled (typical).**

```rust
struct Config {
    inner: AtomicPtr<Inner>,
}
impl Config {
    fn store(&self, new: Arc<Inner>) {
        let raw = Arc::into_raw(new) as *mut Inner;
        let old = self.inner.swap(raw, Ordering::AcqRel);
        if !old.is_null() {
            // SAFETY: old was a valid Arc::into_raw'd pointer.
            unsafe { Arc::from_raw(old); }
        }
    }
    fn load(&self) -> Arc<Inner> {
        let raw = self.inner.load(Ordering::Acquire);
        // SAFETY: raw is non-null and a valid Arc::into_raw'd pointer.
        unsafe {
            Arc::increment_strong_count(raw);
            Arc::from_raw(raw)
        }
    }
}
```

**Swap to arc-swap.**

```rust
use arc_swap::ArcSwap;
struct Config {
    inner: ArcSwap<Inner>,
}
impl Config {
    fn store(&self, new: Arc<Inner>) {
        self.inner.store(new);
    }
    fn load(&self) -> Arc<Inner> {
        self.inner.load_full()
    }
}
```

`arc_swap::ArcSwap` has a small audited unsafe surface internally. The project's hand-rolled version typically has 3–4 unsafe blocks; the arc-swap version has zero in the project.

**Equivalence test.** Property: under concurrent N threads doing `store` + `load` + `load_full`, the load always returns either the previous or the current Arc; never null, never partially-initialized.

**Loom model.** Required. The default arc-swap test suite has loom coverage; the project's loom test just exercises the project's usage pattern.

---

## crossbeam channels: replacing std::sync::mpsc + custom Sync

**Use when.** The project uses `std::sync::mpsc` AND has a custom `unsafe impl Send/Sync` for the message type.

**Hand-rolled (typical).**

```rust
struct Message {
    payload: *const Payload,   // because Payload isn't Send
}
unsafe impl Send for Message {}   // promises payload doesn't escape thread

let (tx, rx) = std::sync::mpsc::channel::<Message>();
// ...
```

**Swap to crossbeam.**

```rust
use crossbeam::channel::{unbounded, Sender, Receiver};
let (tx, rx) = unbounded::<Arc<Payload>>();   // Arc<Payload> is Send if Payload is Sync
// Or for types that are NOT thread-safe:
let (tx, rx) = unbounded::<SyncSend<Payload>>();
```

If `Payload` is fundamentally not `Send`, the (A) for the SendPtr-style newtype stays; but crossbeam's channel is safer than `std::sync::mpsc` for performance-sensitive uses (lock-free, supports multiple receivers, no `unsafe` in the channel itself).

---

## dashmap: replacing locked HashMap with manual unsafe

**Use when.** The project has `Mutex<HashMap<K, V>>` and wants per-bucket locking, OR has hand-rolled sharded maps.

**Hand-rolled (typical).** Several variants; usually involve `unsafe impl Send/Sync` on a custom shard type.

**Swap to dashmap.**

```rust
use dashmap::DashMap;
let map: DashMap<String, i64> = DashMap::new();
// ...
map.insert("foo".to_string(), 42);
let val = map.get("foo").map(|v| *v);
```

`dashmap` has its own internal unsafe but it's well-audited (used in `lambdaworks`, `arroyo`, `lance`, etc.). The project's hand-rolled version typically has more unsafe.

**Equivalence test.** Concurrent insert/remove/get; assert no key-value pair is observed in a state that wasn't written.

---

## indexmap: replacing custom-ordered HashMap

**Use when.** The project has a `HashMap<K, V> + Vec<K>` pair for ordered iteration, often with unsafe to keep them in sync.

**Swap to indexmap.**

```rust
use indexmap::IndexMap;
let map: IndexMap<String, i64> = IndexMap::new();
map.insert("a".to_string(), 1);
map.insert("b".to_string(), 2);
for (k, v) in &map {
    println!("{k}: {v}");   // iteration order is insertion order
}
```

Zero unsafe at the call site. `indexmap`'s internal unsafe is audited.

---

## flume: alternative to crossbeam channels

For projects that prefer a smaller dependency footprint than crossbeam, `flume` is a similar safe channel. Pick based on perf bench, not preference.

---

## Lock-free queues

For SPSC / MPSC / MPMC queues, prefer:

- `crossbeam::queue::SegQueue` (MPMC, unbounded).
- `crossbeam::queue::ArrayQueue` (MPMC, bounded).
- `flume::bounded` / `flume::unbounded` (channel-like, also queue-usable).
- `tokio::sync::mpsc` (async-aware).

Hand-rolled lock-free queues are a high source of subtle UB. Unless the project's purpose IS the queue (e.g., a runtime crate), swap to a crate.

---

## When concurrency-touching unsafe SHOULD stay

Some patterns stay (A) per the canonical catalog:

- The runtime crate ITSELF (tokio's scheduler, glommio's reactor) has lock-free unsafe that's audited per-line. Don't propose to swap it for crossbeam.
- A worker-parking protocol with platform-specific orderings (see `/dp/franken_engine/src/sched/worker_park.rs`) — the (A) survives.
- A truly bespoke data structure with measured perf cliffs (rare, but real). The (B) requires loom + per-target benches.

The audit's job is to find the (C) opportunities and prove them; not to convert every lock-free concurrent algorithm to `Mutex<...>`.

---

## Loom usage for concurrent (C) rewrites

Every (C) rewrite that touches atomics or threads MUST have a loom model. The model exercises the swap pattern:

```rust
#[cfg(loom)]
#[test]
fn loom_swap_safe() {
    loom::model(|| {
        use loom::sync::Arc;
        let cfg = Arc::new(Config::new());
        let cfg2 = Arc::clone(&cfg);
        let t1 = loom::thread::spawn(move || {
            cfg2.store(Arc::new(Inner::v2()));
        });
        let r = cfg.load();
        t1.join().unwrap();
        // r must be either v1 (initial) or v2 (after store)
        assert!(r == Arc::new(Inner::v1()) || r == Arc::new(Inner::v2()));
    });
}
```

Run with `RUSTFLAGS="--cfg loom" cargo test --features loom_concurrency_tests --release`. The test must complete within the default budget (no `preemption_bound` overrides) for routine cases; expand only when the model is bigger.

---

## Common concurrent (C) refactor wins from exemplar repos

### `/dp/franken_engine` — config hot-reload

Originally `AtomicPtr<Config>` with hand-rolled Arc round-trip (6 unsafe blocks). After (C):
- `ArcSwap<Config>` for the hot-reloadable section.
- `unsafe impl Send/Sync` impls deleted; auto-derive provides them on `Arc<Config>`.
- Loom model in `tests/loom_config_swap.rs` proves no data race.

### `/dp/asupersync` — completion ring readers

Originally `unsafe impl Sync for CqReader { ring: *mut io_uring_cqe }`. After (C):
- The `ring: *mut io_uring_cqe` field stays (the kernel writes to it), BUT
- `CqReader` becomes `!Sync` (only one reader at a time, enforced by ownership).
- The (A) on the field's atomic ordering stays per `00-CANONICAL-UNAVOIDABLE.md § 5`.

Net: 1 unsafe impl deleted; 1 unsafe field remains but is now type-system-safer.

### `/dp/mcp_agent_mail_rust` — inbox shard

Originally hand-sharded `[Mutex<HashMap<MsgId, Msg>>; 16]` plus custom unsafe to compute shard index. After (C):
- Single `DashMap<MsgId, Msg>`.
- All unsafe deleted; perf within 1.02× per bench.

---

## Anti-patterns

- **Sprinkling `RwLock<...>` to "fix" thread-unsafe types.** RwLock is fine but heavy; consider whether ArcSwap or DashMap is closer to the access pattern.
- **Replacing `unsafe impl Send/Sync` with `static_assertions::assert_impl_all!(MyType: Send + Sync)` and CALLING IT DONE.** The assertion proves the type IS Send+Sync after the refactor; it doesn't prove the refactor is correct. The behavioral equivalence test is still required.
- **Loom test that exercises only 1 thread.** loom is for concurrency; single-thread tests run under normal `cargo test`. A loom test with `loom::thread::spawn` and at least 2 threads is required.
- **Ignoring `Acquire` / `Release` / `SeqCst` in the rewrite.** If the original used `SeqCst`, the rewrite must justify weakening to `Acquire`/`Release`; usually requires a loom model showing the weaker ordering is sufficient.
