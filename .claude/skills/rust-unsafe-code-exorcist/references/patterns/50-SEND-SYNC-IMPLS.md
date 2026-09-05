# 50-SEND-SYNC-IMPLS.md — `unsafe impl Send` / `unsafe impl Sync` Audit

Every `unsafe impl Send for T` and `unsafe impl Sync for T` is a soundness claim that the compiler couldn't make automatically. This file is the per-impl audit protocol.

---

## What the auto-derive does (and doesn't)

`Send` and `Sync` are auto-traits: the compiler derives them for any type whose fields are all `Send` / `Sync`. The auto-derive is removed by:

- Containing a `*const T` or `*mut T` field (raw pointers are `!Send + !Sync` by default).
- Containing an `Rc<T>` field (`Rc` is `!Send + !Sync`).
- Containing a `Cell<T>` field (`Cell` is `!Sync`).
- An explicit `impl !Send for T` (rare; used to mark types like `PhantomData<*mut T>`-bearing).

When the auto-derive is removed, the project asserts the impl with `unsafe impl Send for T` / `unsafe impl Sync for T`, taking on the soundness obligation.

---

## The audit per impl

For each `unsafe impl Send for T` (or `Sync`):

### Step 1 — List every field of T

```
T = WorkerHandle
Fields:
  - inner: *const Worker
  - id:    u64
  - flags: AtomicU32
```

### Step 2 — Classify each field's Send/Sync-ness

| Field | Send? | Sync? | Why |
|-------|-------|-------|-----|
| `inner: *const Worker` | NO (raw pointer) | NO (raw pointer) | This is why the unsafe impl exists |
| `id: u64` | yes (auto) | yes (auto) | primitive |
| `flags: AtomicU32` | yes (auto) | yes (auto) | atomic |

### Step 3 — Name the invariant the unsafe impl is asserting

For the example: "The `*const Worker` is only ever read; the `Worker` it points to outlives the `WorkerHandle` via `Arc<Worker>` ownership; the `Worker`'s methods are themselves `Send + Sync`."

### Step 4 — Trace the invariant enforcement

- Who creates `WorkerHandle` instances? — `Worker::spawn_handle(self: &Arc<Self>) -> WorkerHandle`.
- Does `Worker::spawn_handle` enforce the `Worker` outlives the handle? — Yes: it bumps the Arc count and stores the resulting `*const Worker` in `WorkerHandle::inner`. The handle's `Drop` decrements via `Arc::from_raw(self.inner).` … wait, the example doesn't show a Drop impl. Investigate.
- If there's no `Drop` impl, the `Arc` count is leaked. This is a soundness issue.

This kind of trace catches real bugs. Walk every field for every `unsafe impl`.

### Step 5 — Determine: is the auto-derive achievable after a refactor?

If the only non-auto field is a raw pointer, and the raw pointer's invariants can be moved into a `Send`+`Sync` newtype:

```rust
#[derive(Copy, Clone)]
struct WorkerPtr(*const Worker);
// SAFETY: WorkerPtr is constructed only by Worker::spawn_handle which guarantees the
// pointed-to Worker outlives the WorkerPtr (via Arc<Worker> ownership transfer).
// Worker is Send + Sync, so concurrent access via *const Worker is sound.
unsafe impl Send for WorkerPtr {}
unsafe impl Sync for WorkerPtr {}

struct WorkerHandle {
    inner: WorkerPtr,    // Send + Sync now
    id: u64,
    flags: AtomicU32,
}
// WorkerHandle gets Send + Sync via auto-derive. Delete the manual impl.
```

The (A) stays on `WorkerPtr` (per `00-CANONICAL-UNAVOIDABLE.md § 8`); `WorkerHandle` graduates from (A) to (C). Net: one unsafe impl deleted, the remaining one is clustered into a single audited newtype.

---

## Common Send/Sync (C) refactor wins

### Pattern SS-1: Newtype the raw pointer

As above. Move the unsafe impl onto a single-field newtype; the original type gets auto-derive.

### Pattern SS-2: Replace raw pointer with `Arc<T>` field

If the type's actual ownership model is "shared," replace the `*const T` with `Arc<T>`:

```rust
// Before
struct Handle {
    target: *const T,
}
unsafe impl Send for Handle {}
unsafe impl Sync for Handle {}

// After
struct Handle {
    target: Arc<T>,    // Send + Sync if T: Send + Sync
}
// Auto-derive applies; delete the unsafe impls.
```

Cost: a refcount per `Handle::clone()`. Usually negligible.

### Pattern SS-3: Eliminate by making the type single-threaded

Sometimes `unsafe impl Send` exists because "we MIGHT want to send it across threads later." If the actual usage doesn't, just don't implement `Send`. Less code; tighter API.

```rust
// Before
unsafe impl Send for ThreadLocalCache {}  // never actually sent

// After
// No impl. ThreadLocalCache is !Send by default.
// If a caller tries to send it, compile error.
```

### Pattern SS-4: Replace `unsafe impl Sync for X { Cell<...> }` with `RwLock<...>` or `AtomicCell<...>`

If the project has `unsafe impl Sync for X` because of an internal `Cell<...>`:

```rust
// Before
struct Counter {
    n: Cell<u64>,
}
unsafe impl Sync for Counter {}   // promises: only one thread touches n

// After (if actually multi-threaded)
struct Counter {
    n: AtomicU64,
}
// Counter is Sync via auto-derive.

// After (if actually single-threaded but multiple threads can READ)
struct Counter {
    n: RwLock<u64>,
}
// Counter is Sync via auto-derive.
```

The choice between `AtomicU64` and `RwLock<u64>` depends on the contention pattern; bench it.

---

## When `unsafe impl Send/Sync` SHOULD stay

- The project IS a low-level concurrency primitive (channel, queue, allocator). Its purpose is to bridge raw memory access into Send+Sync types. The unsafe impl is part of the contract.
- The type holds an opaque FFI handle whose thread-safety is documented in the C library, not in Rust. Document the C-side guarantee in the SAFETY comment.
- The type is a marker (`PhantomData<*mut T>` or similar). Auto-derive removed Send/Sync; manual impl restores it. Document why.

---

## Anti-patterns

- **`unsafe impl Send for T {}` without a SAFETY comment.** Even if the impl is "obviously" correct, the comment is required. The audit-grade requirement is: comment names the field-level invariants AND the enforcement path.
- **`#[allow(non_camel_case_types)] unsafe impl Send for ...` without auditing.** The lint silence doesn't change the soundness obligation.
- **Deleting the unsafe impl without an equivalence test.** Removing `Send` is API-breaking; some callers may rely on it. The plan must document the migration.
- **Adding the unsafe impl "to make the test pass."** If the test compiles only because of an unsafe impl, the test is exercising thread safety the type doesn't actually have.

---

## The `static_assertions::assert_impl_all!` check

After a refactor that aims to graduate a manual `unsafe impl` to auto-derive, ADD a compile-time assertion:

```rust
use static_assertions::assert_impl_all;

assert_impl_all!(WorkerHandle: Send, Sync);
```

This locks in the property. If a future field addition would un-Send the type, the compile fails until the field is reviewed.

Use this on EVERY type whose `Send + Sync`-ness is part of the public contract.

---

## Acceptance signal

A `unsafe impl Send/Sync` audit passes when:

1. Every field of the impl-targeted type is listed.
2. Each field's Send/Sync-ness is classified (auto-derive or asserted-by-this-impl).
3. The invariant the impl is asserting is named.
4. The enforcement path is traced (who creates the type? what do they guarantee? where is the destructor?).
5. The decision to keep / refactor / delete is documented.
6. If kept: hardened SAFETY comment + (where applicable) `assert_impl_all!` to lock the property.
7. If refactored: the newtype-or-replacement is implemented + auto-derive applies to the original type.
