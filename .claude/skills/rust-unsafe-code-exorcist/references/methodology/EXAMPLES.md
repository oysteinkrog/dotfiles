# EXAMPLES.md — Before/After Refactor Gallery

Paste-ready transforms for the most common (C) refactors. Indexed by pattern bundle for browsability. Each entry: the unsafe original, the safe rewrite, the property test, and the citation.

For deeper context per pattern, see the bundle ID in parentheses.

---

## Index by frequency

| Rank | Pattern | Where | Frequency in audits |
|------|---------|-------|---------------------|
| 1 | transmute byte → integer | `[T-2]` | Very common |
| 2 | raw `*mut T` linked list → slab indices | `[P-1]` / `[AL-1]` | Common (10-50 sites per project) |
| 3 | `MaybeUninit` array → `array::from_fn` | `[U-1]` | Common |
| 4 | `unsafe impl Send` on raw pointer field → newtype | `[SS-1]` | Common |
| 5 | hand-rolled `AtomicPtr<Arc<T>>` → `arc-swap::ArcSwap` | `[LF-1]` | Medium |
| 6 | manual `Pin::new_unchecked` Future → `pin-project-lite` | `[P-1]` (pin) | Medium |
| 7 | `slice::get_unchecked` → bounds-check (often graduates B → C) | `[S-4]` | Medium |
| 8 | sharded `Mutex<HashMap>` → `DashMap` | `[LF-2]` | Medium |
| 9 | XOR linked list → slab indices (provenance violation) | `[T-4]` | Rare-but-impactful |
| 10 | hand-written `unsafe impl FromBytes` → `#[derive(zerocopy::FromBytes)]` | `[M-1]` | Common in serialization |

---

## Example 1 — transmute byte→integer ([T-2] from [70-UNINIT-AND-TRANSMUTE.md](../patterns/70-UNINIT-AND-TRANSMUTE.md))

**Before (UNSAFE):**
```rust
fn read_u32_be(buf: &[u8; 4]) -> u32 {
    unsafe { std::mem::transmute::<[u8; 4], u32>(*buf) }.to_be()
}
```

**After (SAFE):**
```rust
fn read_u32_be(buf: &[u8; 4]) -> u32 {
    u32::from_be_bytes(*buf)
}
```

**Equivalence test:**
```rust
proptest! {
    #[test]
    fn read_u32_be_equiv(b: [u8; 4]) {
        prop_assert_eq!(
            original::read_u32_be(&b),
            rewritten::read_u32_be(&b)
        );
    }
}
```

**Notes:**
- Identical codegen (LLVM produces the same machine instructions).
- No allocator change; no API change.
- Risk: Low.

**Cited in:** beads_rust [E-011]; frankensqlite zerocopy migration [E-052].

---

## Example 2 — raw pointer doubly-linked list → slab ([P-1] from [10-POINTER-MIGRATIONS.md](../patterns/10-POINTER-MIGRATIONS.md))

**Before (UNSAFE):**
```rust
struct Node {
    next: *mut Node,
    prev: *mut Node,
    value: u64,
}

unsafe impl Send for List {}
struct List {
    head: *mut Node,
    tail: *mut Node,
}

impl List {
    fn push_back(&mut self, value: u64) {
        let node = Box::into_raw(Box::new(Node {
            next: std::ptr::null_mut(),
            prev: self.tail,
            value,
        }));
        unsafe {
            if !self.tail.is_null() {
                (*self.tail).next = node;
            } else {
                self.head = node;
            }
            self.tail = node;
        }
    }
    // pop_front, iter, etc. — all unsafe
    // Drop impl needed: walks the list and Box::from_raw(p) each
}
```

**After (SAFE):**
```rust
use slab::Slab;

struct Node {
    next: Option<usize>,
    prev: Option<usize>,
    value: u64,
}

struct List {
    nodes: Slab<Node>,
    head: Option<usize>,
    tail: Option<usize>,
}

impl List {
    fn push_back(&mut self, value: u64) {
        let key = self.nodes.insert(Node {
            next: None,
            prev: self.tail,
            value,
        });
        if let Some(t) = self.tail {
            self.nodes[t].next = Some(key);
        } else {
            self.head = Some(key);
        }
        self.tail = Some(key);
    }
    // pop_front, iter — all safe; use slab indices
    // No Drop needed; slab handles cleanup
}
```

**Equivalence test:**
```rust
proptest! {
    #[test]
    fn list_fifo_order(ops in proptest::collection::vec(any::<Op>(), 0..100)) {
        let mut original = OriginalList::new();
        let mut rewritten = RewrittenList::new();
        for op in &ops { apply(&op, &mut original); apply(&op, &mut rewritten); }
        let orig_drain: Vec<u64> = std::iter::from_fn(|| original.pop_front()).collect();
        let new_drain: Vec<u64> = std::iter::from_fn(|| rewritten.pop_front()).collect();
        prop_assert_eq!(orig_drain, new_drain);
    }
}
```

**Notes:**
- 8 `unsafe` blocks eliminated; 1 unsafe impl Send eliminated (auto-derive applies now).
- Cache locality preserved (slab uses a Vec internally).
- Risk: Low.
- Pitfall: indices are NOT generational; if you re-insert after remove, the old index points to the new entry. Use `slotmap` if you need generational keys.

**Cited in:** frankenfs [E-091] (bead `br-ffs-148`).

---

## Example 3 — MaybeUninit array → array::from_fn ([U-1] from [70-UNINIT-AND-TRANSMUTE.md](../patterns/70-UNINIT-AND-TRANSMUTE.md))

**Before (UNSAFE):**
```rust
fn build_table(seed: u64) -> [u64; 16] {
    let mut arr: [MaybeUninit<u64>; 16] = unsafe { MaybeUninit::uninit().assume_init() };
    for i in 0..16 {
        arr[i] = MaybeUninit::new(seed.wrapping_add(i as u64));
    }
    unsafe { std::mem::transmute(arr) }
}
```

**After (SAFE):**
```rust
fn build_table(seed: u64) -> [u64; 16] {
    std::array::from_fn(|i| seed.wrapping_add(i as u64))
}
```

**Equivalence test:**
```rust
proptest! {
    #[test]
    fn build_table_equiv(seed: u64) {
        prop_assert_eq!(original::build_table(seed), rewritten::build_table(seed));
    }
}
```

**Notes:**
- Identical codegen.
- No allocator change.
- Panic-safety automatically improved (the original's MaybeUninit + transmute pattern was a double-drop hazard if the closure panicked partway).
- Risk: Low.

---

## Example 4 — unsafe impl Send on raw-pointer field → audited newtype ([SS-1] from [50-SEND-SYNC-IMPLS.md](../patterns/50-SEND-SYNC-IMPLS.md))

**Before (UNSAFE):**
```rust
struct WorkerHandle {
    inner: *const Worker,
    id: u64,
    flags: AtomicU32,
}

unsafe impl Send for WorkerHandle {}
unsafe impl Sync for WorkerHandle {}
```

**After (SAFE):**
```rust
use std::sync::Arc;

// Newtype concentrates the unsafe + documents the invariant.
#[derive(Copy, Clone)]
struct WorkerPtr(*const Worker);

// SAFETY: WorkerPtr is created only by Worker::handle(); the pointed-to Worker
// outlives the WorkerPtr via Arc<Worker> ownership transfer. Worker is Send + Sync.
unsafe impl Send for WorkerPtr {}
unsafe impl Sync for WorkerPtr {}

struct WorkerHandle {
    inner: WorkerPtr,     // Send + Sync now
    id: u64,
    flags: AtomicU32,
}

// WorkerHandle: Send + Sync auto-derived. No unsafe impl needed on the handle.

use static_assertions::assert_impl_all;
assert_impl_all!(WorkerHandle: Send, Sync);   // locks in the property
```

**Equivalence test:**
```rust
// Compile-time assertion (no runtime test needed):
const _: () = {
    fn _assert_send_sync<T: Send + Sync>() {}
    fn _check() { _assert_send_sync::<WorkerHandle>(); }
};
```

**Notes:**
- The (A) stays on `WorkerPtr` (justified per [00-CANONICAL-UNAVOIDABLE.md § 8](../patterns/00-CANONICAL-UNAVOIDABLE.md)).
- `WorkerHandle` itself graduates from (A) to (C).
- If a future refactor adds an `Rc<X>` field to `WorkerHandle`, the auto-derive fails (compile error) — early warning of unsoundness.
- Risk: Low.

**Cited in:** franken_engine [E-021] (bead `br-fengine-1788`).

---

## Example 5 — AtomicPtr<Arc<T>> → arc-swap::ArcSwap ([LF-1] from [75-LOCK-FREE-PATTERNS.md](../patterns/75-LOCK-FREE-PATTERNS.md))

**Before (UNSAFE):**
```rust
struct Config {
    inner: AtomicPtr<Inner>,
}

impl Config {
    fn store(&self, new: Arc<Inner>) {
        let raw = Arc::into_raw(new) as *mut Inner;
        let old = self.inner.swap(raw, Ordering::AcqRel);
        if !old.is_null() {
            unsafe { drop(Arc::from_raw(old)); }
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
```

**After (SAFE):**
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

**Loom model (sketch — see note):**
```rust
#[cfg(loom)]
#[test]
fn loom_config_swap() {
    // NOTE: Out of the box, `arc-swap` uses `std::sync::atomic` (real atomics),
    // NOT loom-instrumented atomics — so plain `loom::model(|| { ArcSwap::new(...) })`
    // doesn't actually exercise loom's interleavings on arc-swap's internals.
    // To get loom coverage, either:
    //   (1) Use loom only to model your USAGE pattern (what the example below does);
    //       this verifies your code's external invariants but NOT arc-swap's internals.
    //   (2) Use a custom shim that points arc-swap at loom's atomics under cfg(loom).
    //
    // For most projects, (1) is enough — arc-swap's internals are audited upstream.
    loom::model(|| {
        use loom::sync::Arc;
        let cfg = Arc::new(/* your Config wrapper holding an ArcSwap<Inner> */);
        let cfg2 = Arc::clone(&cfg);
        let t1 = loom::thread::spawn(move || cfg2.store(std::sync::Arc::new(Inner::v2())));
        let observed = cfg.load();
        t1.join().unwrap();
        // Must observe either v1 (initial) or v2 (after store)
        assert!(observed.id == 1 || observed.id == 2);
    });
}
```

**Notes:**
- 3 unsafe blocks eliminated; the (A) survives only inside `arc-swap`'s audited crate.
- Latency improvement on some workloads (arc-swap has hazard-pointer-style fast path).
- Risk: Low.

**Cited in:** franken_engine [E-071] (bead `br-fengine-198`).

---

## Example 6 — manual Pin::new_unchecked → pin-project-lite ([P-1] from [80-PIN-PROJECTIONS.md](../patterns/80-PIN-PROJECTIONS.md))

**Before (UNSAFE):**
```rust
pub struct MyFuture {
    inner: SomeFuture,
    state: State,
}

impl Future for MyFuture {
    type Output = Result<(), Error>;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        let this = unsafe { self.get_unchecked_mut() };
        let inner = unsafe { Pin::new_unchecked(&mut this.inner) };
        match inner.poll(cx) {
            Poll::Ready(r) => Poll::Ready(r),
            Poll::Pending => Poll::Pending,
        }
    }
}
```

**After (SAFE):**
```rust
pin_project_lite::pin_project! {
    pub struct MyFuture {
        #[pin]
        inner: SomeFuture,
        state: State,
    }
}

impl Future for MyFuture {
    type Output = Result<(), Error>;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        let this = self.project();
        match this.inner.poll(cx) {
            Poll::Ready(r) => Poll::Ready(r),
            Poll::Pending => Poll::Pending,
        }
    }
}
```

**Equivalence test:**
```rust
// The functions are observably identical; tests of the future's behavior pass on both.
// pin-project-lite's expansion contains audited unsafe (inherited soundness).
```

**Notes:**
- 2 unsafe blocks eliminated; macro-generated unsafe is audited per `40-MACRO-GENERATED-UNSAFE.md`.
- API unchanged.
- Risk: Low.
- Doesn't apply if the future has a true self-reference (then [00-CANONICAL-UNAVOIDABLE.md § 8](../patterns/00-CANONICAL-UNAVOIDABLE.md) — keep (A)).

---

## Example 7 — slice::get_unchecked → bounds-check (B → C graduation)

**Before (UNSAFE, claimed (B) for perf):**
```rust
fn dot_product(a: &[f32], b: &[f32]) -> f32 {
    debug_assert_eq!(a.len(), b.len());
    let mut acc = 0.0;
    for i in 0..a.len() {
        acc += unsafe { *a.get_unchecked(i) * *b.get_unchecked(i) };
    }
    acc
}
```

**After (SAFE, B graduated to C):**
```rust
fn dot_product(a: &[f32], b: &[f32]) -> f32 {
    a.iter().zip(b).map(|(&x, &y)| x * y).sum()
}
```

**Bench results (the (B) graduation criterion):**

| Target | unsafe (ns) | safe (ns) | Δ |
|--------|-------------|-----------|---|
| x86_64-v3 | 142 | 144 | +1.4% |
| x86_64-v4 | 102 | 102 | 0% |
| aarch64-apple-darwin | 156 | 157 | +0.6% |

Within 5% perf budget on all targets → (C) graduation.

**Notes:**
- LLVM autovectorizes the iterator-based version equivalently.
- Loop bounds-checks eliminated by the compiler's domain analysis (`a.iter().zip(b)` knows both have the same length).
- Risk: Low.
- The original (B) classification was based on intuition, not measurement; operator ⏱ Profile-Or-It-Didn't-Happen flagged this and forced the bench.

**Cited in:** rich_rust [E-042], frankentui [E-062].

---

## Example 8 — sharded `Mutex<HashMap>` → DashMap ([LF-2])

**Before:**
```rust
struct ShardedMap {
    shards: [Mutex<HashMap<String, u64>>; 16],
}

impl ShardedMap {
    fn shard_index(&self, key: &str) -> usize {
        let mut h: u64 = 0xcbf29ce484222325;
        for b in key.bytes() { h = h.wrapping_mul(0x100000001b3) ^ b as u64; }
        (h % 16) as usize
    }
    fn insert(&self, k: String, v: u64) {
        let i = self.shard_index(&k);
        self.shards[i].lock().unwrap().insert(k, v);
    }
    fn get(&self, k: &str) -> Option<u64> {
        let i = self.shard_index(k);
        self.shards[i].lock().unwrap().get(k).copied()
    }
}
```

**After:**
```rust
use dashmap::DashMap;

struct ShardedMap {
    inner: DashMap<String, u64>,
}

impl ShardedMap {
    fn new() -> Self { Self { inner: DashMap::new() } }
    fn insert(&self, k: String, v: u64) { self.inner.insert(k, v); }
    fn get(&self, k: &str) -> Option<u64> { self.inner.get(k).map(|v| *v) }
}
```

**Notes:**
- No project-side unsafe.
- Latency: typically -7% p99 on lookup, -32% on insert (DashMap's lock-free path on uncontended cases).
- API unchanged.
- Risk: Low.

**Cited in:** mcp_agent_mail_rust [E-103].

---

## Example 9 — XOR linked list → slab (strict-provenance fix) ([T-4])

**Before (FUNDAMENTALLY broken under strict-provenance):**
```rust
struct Node {
    xor_neighbor: *mut Node,   // (prev ^ next)
}

impl Node {
    fn next(&self, prev: *mut Node) -> *mut Node {
        ((self.xor_neighbor as usize) ^ (prev as usize)) as *mut Node
    }
}
```

**After (slab; strict-provenance clean):**
```rust
struct Node {
    next: Option<usize>,
    prev: Option<usize>,
}

// Plus slab::Slab<Node> in the containing list.
```

**Notes:**
- The XOR trick saved one pointer per node; the slab approach uses 16 bytes total (two `Option<usize>`).
- Memory cost: ~25% increase per node, but cache locality is the same.
- Strict-provenance compliance: full.
- miri-clean: yes.

**Cited in:** franken_engine `br-fengine-89` (the rationale + measured trade-off is in the bead).

---

## Example 10 — hand-written `unsafe impl FromBytes` → derive ([M-1] from [40-MACRO-GENERATED-UNSAFE.md](../patterns/40-MACRO-GENERATED-UNSAFE.md))

**Before:**
```rust
#[repr(C)]
struct Header {
    version: u32,
    flags: u32,
}

unsafe impl zerocopy::FromBytes for Header { fn only_derive_is_allowed_to_implement_this_trait() {} }
unsafe impl zerocopy::AsBytes for Header { fn only_derive_is_allowed_to_implement_this_trait() {} }
```

**After:**
```rust
use zerocopy_derive::{FromBytes, AsBytes};

#[repr(C)]
#[derive(FromBytes, AsBytes)]
struct Header {
    version: u32,
    flags: u32,
}
```

**Notes:**
- The derive generates THE SAME unsafe impls but with compile-time verification that fields are Pod-compatible.
- If a future refactor adds a non-Pod field, the derive fails (compile error).
- The `only_derive_is_allowed_to_implement_this_trait` method is a quirky guard in older `zerocopy` versions; newer versions removed it.
- Risk: None.

**Cited in:** beads_rust [E-012], frankenfs [E-092].

---

## How to use this gallery

1. The audit's classification phase identifies an (A) / (B) / (C) bucket per site.
2. For each (C), the refactor-planner subagent looks up the SHAPE of the unsafe (FFI / Pin / transmute / etc.).
3. The pattern-bundle reference (e.g., `[10-POINTER-MIGRATIONS.md]`) gives the principles.
4. THIS file gives the concrete before/after with property tests.
5. The planner adapts the example to your specific site.

If your site doesn't match any example: it's either novel (file feedback so we can add it) or it doesn't fit (C) and should be reclassified.

---

## Browsing tips

- Sort by frequency to pick examples worth memorizing.
- All examples come with the exemplar repo citation `[E-NNN]` you can verify.
- Each example's "Notes" section documents tradeoffs + risks.
- The `Cited in` line tells you which beads in which exemplar repos shipped this pattern — read those for the rationale.

Pattern bundles ([00-CANONICAL-UNAVOIDABLE.md] through [130-TAGGED-POINTER-MIGRATION.md]) are the comprehensive reference; this file is the quick-access subset.
