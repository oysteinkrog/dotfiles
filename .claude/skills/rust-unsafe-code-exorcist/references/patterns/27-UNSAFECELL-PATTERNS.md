# 27-UNSAFECELL-PATTERNS.md — `UnsafeCell` and Interior Mutability

`UnsafeCell<T>` is the language-level primitive that **all** interior mutability is built on. `Cell`, `RefCell`, `OnceCell`, `RwLock`, `Mutex`, `AtomicXxx`, the various `parking_lot::*` types — they all wrap `UnsafeCell` internally. The compiler treats `UnsafeCell` specially: it's the **only** legal way to obtain a `&mut T` while another `&T` exists into the same allocation, and only inside an `unsafe` block.

Hand-rolled `UnsafeCell` usage is rare but real — primarily in lock primitive implementations, single-threaded-aware optimizations, and zero-cost abstractions on top of other unsafe primitives. This bundle covers when manual `UnsafeCell` is justified, when it should be replaced with a higher-level primitive, and the soundness obligations that come with it.

The audit enumerator surfaces `UnsafeCell::new` / `UnsafeCell::get` sites as `kind: unsafe_cell_decl` in `unsafe-inventory.jsonl`.

---

## What this bundle covers

| Pattern | Kind | Typical bucket | Section |
|---------|------|----------------|---------|
| `Cell<T>` used as a thin field | safe primitive | (C) refactor target | § UC-1 |
| `RefCell<T>` for single-threaded interior mutability | safe primitive | (C) refactor target | § UC-2 |
| `OnceCell<T>` / `LazyCell<T>` for lazy init | safe primitive | (C) refactor target | § UC-3 |
| Manual `UnsafeCell` for lock implementations | hand-rolled lock | (A) | § UC-4 |
| Manual `UnsafeCell` for single-thread-aware optimization | escape hatch | (A) / (B) | § UC-5 |
| Manual `UnsafeCell` inside `Pin` projections | self-ref | (A) | § UC-6 (cross-ref [80-PIN-PROJECTIONS.md](80-PIN-PROJECTIONS.md)) |
| `UnsafeCell` in `Sync` types | sync impl | (A) audit must verify | § UC-7 (cross-ref [50-SEND-SYNC-IMPLS.md](50-SEND-SYNC-IMPLS.md)) |

---

## The shared invariant

For all `UnsafeCell` usage, the soundness obligation is:

> The set of `&mut T`s derived from `UnsafeCell::get(&cell)` (cast to `&mut T`) must NEVER overlap with any `&T` derived from `&*UnsafeCell::get(&cell)` for the same `cell`. The user code, NOT the compiler, must enforce this.

The borrow checker bypasses its usual checks at the `UnsafeCell::get` boundary. Every other safety property — exclusivity of mutable references, lifetimes — falls back to the audit, the test suite, and miri.

This is the only safe-Rust mechanism for "interior mutability through a shared reference." Every other interior-mutability type composes on top of this.

---

## § UC-1 — `Cell<T>` (the simplest interior-mutability primitive)

`Cell<T>` allows mutation through `&Cell<T>` but only for `Copy` types (or types where the entire value is replaced atomically via `set`/`replace`/`swap`).

### When to use

Read-mostly fields where the writer is rare AND the reader needs `&T` access — e.g., a counter inside a `&self` method.

### Sound usage

```rust
struct Counter { count: Cell<u32> }

impl Counter {
    fn increment(&self) {        // takes &self, NOT &mut self
        self.count.set(self.count.get() + 1);
    }
}
```

`Cell::get` returns a *copy* of the value; there's no `&T` view, so the soundness rule above is trivially satisfied.

### Audit checklist

| Question | Verifier |
|----------|----------|
| Could the user have written `&mut self` instead? If yes, `Cell` is unnecessary. | Static analysis: trace the callers. |
| Is the `Cell` `Sync`? | NO — `Cell` is `!Sync` by default. If the project asserts `Sync` for a type containing `Cell`, that's a soundness bug. |
| Is the `T` larger than ~32 bytes? `Cell` requires `Copy` for `get`/`set`. | Consider `RefCell` for non-`Copy` types. |

### Common refactor target

Replace hand-rolled `UnsafeCell<u32>` for counters with `Cell<u32>`. The `Cell` version is safe; the `UnsafeCell` version requires manual audit.

---

## § UC-2 — `RefCell<T>` (single-threaded RefCell with runtime borrow checking)

`RefCell<T>` allows runtime-checked borrow tracking. It panics if `borrow_mut` is called while a `borrow` is active (and vice versa).

### When to use

Single-threaded ownership of a `T` that needs `&mut T` access through `&RefCell<T>`. Useful in tree / graph data structures where the borrow checker's static rules are too strict.

### Sound usage

```rust
struct Cache { entries: RefCell<HashMap<Key, Value>> }

impl Cache {
    fn get_or_insert(&self, k: Key) -> Value {
        if let Some(v) = self.entries.borrow().get(&k) { return v.clone(); }
        let mut entries = self.entries.borrow_mut();
        entries.entry(k).or_insert_with(...).clone()
    }
}
```

### Audit checklist

| Question | Verifier |
|----------|----------|
| Is the `RefCell` ever held across `.await`? | If yes, deadlock risk — switch to `Mutex` / `RwLock`. |
| Could `parking_lot::RwLock` (or `std::sync::RwLock`) work? | If the type is `Sync`-needed, yes; `RefCell` is `!Sync`. |
| Is the panic on overlapping borrow handled? | Property test: assert no double-borrow path; if rare, document. |

### Common refactor target

Replace hand-rolled `UnsafeCell<HashMap<K,V>>` with `RefCell<HashMap<K,V>>` (single-threaded) or `RwLock<HashMap<K,V>>` (multi-threaded). The performance overhead is usually trivial.

---

## § UC-3 — `OnceCell<T>` / `LazyCell<T>` (one-time init)

`OnceCell<T>` allows setting a value once and reading it many times. Stable since Rust 1.70.

### When to use

Lazy-initialized state: configuration loaded on first access, a `Regex` compiled on first use, etc.

### Sound usage

```rust
struct Config { regex: OnceCell<Regex> }

impl Config {
    fn matcher(&self) -> &Regex {
        self.regex.get_or_init(|| Regex::new(r"^...").unwrap())
    }
}
```

### Audit checklist

| Question | Verifier |
|----------|----------|
| Is it `OnceLock<T>` (Sync) or `OnceCell<T>` (!Sync)? | Different types; the wrong choice is a soundness bug. |
| Can the initializer panic? | If yes, future `get_or_init` calls reinitialize (could differ from prior calls; document). |
| MSRV ≥ 1.70? | If older, use the `once_cell` crate. |

### Common refactor target

Replace hand-rolled `UnsafeCell<Option<T>>` + manual init-tracking with `OnceCell` / `OnceLock`. The `UnsafeCell<Option<T>>` form is racy in the multi-threaded case; the audit's job is to surface this when found.

---

## § UC-4 — Manual `UnsafeCell` in lock implementations

This is where `UnsafeCell` actually justifies itself: implementing a mutex, an rwlock, an arc-swap, etc. The lock primitive needs to expose `&self` operations that internally yield `&mut T` access, and the borrow checker fundamentally cannot track this.

### Sound usage

```rust
pub struct SpinMutex<T> {
    locked: AtomicBool,
    data: UnsafeCell<T>,
}

// SAFETY: SpinMutex is Sync as long as T: Send (we transfer ownership to
// whichever thread holds the lock; we never share &T or &mut T concurrently).
unsafe impl<T: Send> Sync for SpinMutex<T> {}

impl<T> SpinMutex<T> {
    pub fn lock(&self) -> SpinGuard<'_, T> {
        while self.locked.compare_exchange(false, true,
                                           Ordering::Acquire, Ordering::Relaxed).is_err() {
            core::hint::spin_loop();
        }
        SpinGuard { mutex: self }
    }
}

pub struct SpinGuard<'a, T> { mutex: &'a SpinMutex<T> }

impl<'a, T> core::ops::Deref for SpinGuard<'a, T> {
    type Target = T;
    fn deref(&self) -> &T {
        // SAFETY: we hold the lock; no other thread can deref the cell.
        unsafe { &*self.mutex.data.get() }
    }
}

impl<'a, T> core::ops::DerefMut for SpinGuard<'a, T> {
    fn deref_mut(&mut self) -> &mut T {
        // SAFETY: we hold the lock + we're the only guard alive (we're &mut SpinGuard).
        unsafe { &mut *self.mutex.data.get() }
    }
}

impl<'a, T> Drop for SpinGuard<'a, T> {
    fn drop(&mut self) {
        self.mutex.locked.store(false, Ordering::Release);
    }
}
```

### Classification

**(A) STRICTLY_UNAVOIDABLE.** The lock primitive can't be expressed without `UnsafeCell` — it's the language's exception escape hatch for "interior mutability through `&self`."

### Audit checklist

| Question | Verifier |
|----------|----------|
| Does the SAFETY comment cite the protocol that maintains the no-overlap invariant? | The atomic + the guard discipline. |
| Is there a `loom` test exercising the protocol? | Required per CLASSIFICATION-RUBRIC for concurrent (A). |
| Does miri pass on a multi-thread test? | Required. |
| Is `Send`/`Sync` correctly declared? | `Send` requires `T: Send`. `Sync` requires `T: Send` (because the lock transfers ownership). Carefully verify. |
| Poison policy? | If `T` can panic during the critical section, document the policy. `std::sync::Mutex` poisons; `parking_lot::Mutex` doesn't. |

### The auto-derive interaction

`UnsafeCell<T>` is `!Sync` by default — placing one in a struct removes auto-derived `Sync`. The `unsafe impl Sync` is then required + must be carefully justified. The audit must verify the justification per § UC-7.

### Refactor target

Almost never — if a project is implementing a lock primitive, that IS the project's purpose. The (A) classification holds. However, audit whether the project actually needs a custom lock vs adopting `parking_lot::Mutex` or `std::sync::Mutex`. See [E-072] for an example where a custom-Sync hand-rolled queue was replaced by `crossbeam::queue::SegQueue`.

---

## § UC-5 — Manual `UnsafeCell` for single-thread-aware optimization

Less common: code that knows the surrounding context is single-threaded and wants to skip the atomic ops a multi-thread-safe primitive would impose.

### Example

```rust
// !Sync; intended for single-thread use only.
struct ThreadLocalCache {
    table: UnsafeCell<HashMap<Key, Value>>,
}

impl ThreadLocalCache {
    fn get(&self, k: &Key) -> Option<Value> {
        // SAFETY: !Sync; this method takes &self; the borrow doesn't escape
        // and the cell is single-threaded by construction.
        unsafe { (*self.table.get()).get(k).cloned() }
    }
}
```

### Classification

**(B) PERF_ONLY** by default — `Cell<HashMap<K,V>>` doesn't work (HashMap is not `Copy`), but `RefCell<HashMap<K,V>>` does, with `.borrow()` / `.borrow_mut()` adding a runtime borrow-counter check.

**(A)** rare; requires the perf measurement showing `RefCell`'s borrow-counter check is over budget.

### Audit checklist

| Question | Verifier |
|----------|----------|
| Is the type really `!Sync`? | Verify there's no `unsafe impl Sync`. |
| Is the perf claim measured? | criterion before-after with `RefCell` substituted. |
| Could thread-local storage replace this entirely? | `thread_local!` macros sometimes apply; consider. |

### Common refactor target

Replace `UnsafeCell<T>` + manual single-thread-safety arguments with `RefCell<T>`. The audit's bias is toward `RefCell` unless perf measurement justifies otherwise.

---

## § UC-6 — `UnsafeCell` inside `Pin` projections

When `Pin<&mut Self>` is in play AND the pinned type has fields that need interior mutability, the projection often involves `UnsafeCell`.

See [80-PIN-PROJECTIONS.md](80-PIN-PROJECTIONS.md) for the full pattern; this section just notes the cross-reference.

The relevant invariant: the projected `&mut Field` must respect Pin's "no-move-after-pinning" guarantee. `pin-project-lite` handles this for you; hand-rolled projections must audit it.

---

## § UC-7 — `UnsafeCell` and `unsafe impl Sync`

If a type contains an `UnsafeCell<T>` AND is asserted `Sync`, the auto-derive REMOVED `Sync` (correctly — `UnsafeCell` is `!Sync`), and someone added `unsafe impl Sync` back.

### The hidden gotcha

`UnsafeCell<T>` removing `Sync` from the surrounding type is a deliberate language feature. Any `unsafe impl Sync` on a type containing `UnsafeCell` is an assertion that the user has manually upheld the `Sync` invariant despite the cell. The audit MUST verify this.

### Audit checklist

| Question | Verifier |
|----------|----------|
| Does the SAFETY comment cite the protocol that upholds `Sync`? | Required. |
| Is there a `loom` test for the protocol? | Required for concurrent code. |
| Is the `Sync` actually needed? | Sometimes the type is single-threaded; the `unsafe impl Sync` was speculative. |

See [50-SEND-SYNC-IMPLS.md](50-SEND-SYNC-IMPLS.md) for the broader Send/Sync audit; this section's checklist is the UnsafeCell-specific addendum.

---

## Phase-4 default classification

When the enumerator surfaces an `unsafe_cell_decl` site, the classifier should:

1. Locate the surrounding struct and check whether it's used as one of UC-1..UC-3's typical patterns (counter / single-thread map / lazy init). If yes, propose (C) with a refactor target named.
2. If it's a lock primitive (UC-4), propose (A).
3. If it's an optimization escape hatch (UC-5), propose (B); require measurement.
4. Always cross-reference with `unsafe impl Sync` / `unsafe impl Send` per UC-7.

The classifier's write-up cites this bundle's `§` number.

---

## Cross-references

- [50-SEND-SYNC-IMPLS.md](50-SEND-SYNC-IMPLS.md) — Send/Sync impl audit (UC-7 cross-ref).
- [80-PIN-PROJECTIONS.md](80-PIN-PROJECTIONS.md) — Pin + UnsafeCell (UC-6 cross-ref).
- [30-CONCURRENCY-PATTERNS.md](30-CONCURRENCY-PATTERNS.md) — concurrency primitives (Mutex / RwLock alternatives).
- [35-ATOMICS-AND-ORDERINGS.md](35-ATOMICS-AND-ORDERINGS.md) — atomic primitives often paired with `UnsafeCell` in lock implementations.
- [75-LOCK-FREE-PATTERNS.md](75-LOCK-FREE-PATTERNS.md) — lock-free data structures, many of which use `UnsafeCell` internally.
- [CLASSIFICATION-RUBRIC.md](../methodology/CLASSIFICATION-RUBRIC.md) — the (A) / (B) / (C) rule.
- [REJECTED-PATTERNS.md](../methodology/REJECTED-PATTERNS.md) — refactors involving lock primitives that were considered + rejected.
