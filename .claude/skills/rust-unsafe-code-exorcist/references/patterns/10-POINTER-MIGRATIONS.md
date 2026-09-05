# 10-POINTER-MIGRATIONS.md — Raw Pointer → Safe Owned Type

The most accretive (C) refactor cluster is the migration of raw pointer types to progressively safer alternatives:

```
*const T   /   *mut T
    │
    ▼
NonNull<T>                 — guaranteed non-null, still aliasable, no lifetime
    │
    ▼
&T  /  &mut T              — borrow with lifetime; aliasing tracked
    │
    ▼
Pin<&mut T>                — borrow + pin guarantee (for self-ref)
    │
    ▼
Box<T> / Vec<T> / Rc<T>    — fully owned safe types
```

Each step UP eliminates one class of bug AND constrains the API; each step DOWN admits more APIs at the cost of soundness reasoning. The audit's goal is to push every site as high as possible in this hierarchy without breaking behavior or perf.

---

## Step 1: `*const T` / `*mut T` → `NonNull<T>`

**When.** Raw pointers that are KNOWN to be non-null (e.g., obtained from `Box::into_raw`, `Arc::into_raw`, or a successful FFI call with a null-check guard).

**Rewrite.**

```rust
// Before
struct Handle {
    inner: *mut Inner,
}
impl Handle {
    fn new() -> Self {
        Handle { inner: Box::into_raw(Box::new(Inner::default())) }
    }
    unsafe fn frob(&self) {
        (*self.inner).frob();  // UB if inner is null or freed
    }
}

// After
use std::ptr::NonNull;
struct Handle {
    inner: NonNull<Inner>,
}
impl Handle {
    fn new() -> Self {
        let boxed = Box::new(Inner::default());
        // SAFETY: Box::into_raw never returns null.
        Handle { inner: unsafe { NonNull::new_unchecked(Box::into_raw(boxed)) } }
    }
    fn frob(&self) {
        // SAFETY: inner is non-null by NonNull invariant; valid for the lifetime
        // of Self (released only in Drop).
        unsafe { self.inner.as_ref().frob() };
    }
}
```

**Equivalence proof.** Property test: same input → same `Inner::frob()` outputs. `NonNull` is a transparent newtype over `*mut T`, so codegen is identical.

**Risk.** Low.

---

## Step 2: `NonNull<T>` → `&T` / `&mut T` with lifetime

**When.** The pointer's lifetime can be tied to a parent value.

**Rewrite.**

```rust
// Before — Handle owns a pointer; user must guarantee lifetime separately
struct Handle {
    inner: NonNull<Inner>,
}
impl Handle {
    fn frob(&self) { unsafe { self.inner.as_ref().frob(); } }
}

// After — Handle BORROWS Inner; lifetime tracked
struct Handle<'a> {
    inner: &'a Inner,
}
impl<'a> Handle<'a> {
    pub fn frob(&self) { self.inner.frob(); }
}

// User-side
let inner = Inner::default();
let handle = Handle { inner: &inner };
handle.frob();
// `inner` outlives `handle` is enforced by the borrow checker.
```

**When this works.** When the parent value is in scope at every use of the handle.

**When this DOESN'T work.** When the handle must outlive the parent's stack frame (e.g., stored in a `Vec` and used later). In that case, the next step:

---

## Step 3: borrow → `Pin<&mut T>` (only for self-referential)

**When.** The type has a self-reference — a field that points into another field of the same struct.

**Rewrite.** Use `pin-project-lite` for the common case:

```toml
[dependencies]
pin-project-lite = "0.2"
```

```rust
pin_project_lite::pin_project! {
    pub struct WsStream {
        #[pin]
        socket: tokio::net::TcpStream,
        buffer: Vec<u8>,
    }
}

impl WsStream {
    pub fn read(self: Pin<&mut Self>) -> impl Future<Output = io::Result<usize>> + '_ {
        let this = self.project();
        // `this.socket` is `Pin<&mut TcpStream>`; `this.buffer` is `&mut Vec<u8>`.
        // The library handles the unsafe pin-projection internally.
        ...
    }
}
```

**When this DOESN'T work.** When the self-reference is across a generic type or across a `repr(C)` boundary that `pin-project` can't safely project. Then the unsafe stays as (A) per `00-CANONICAL-UNAVOIDABLE.md § 8`.

---

## Step 4: borrow / `Pin<&mut T>` → `Box<T>` / `Vec<T>` / `Rc<T>` (fully owned)

**When.** The data can be owned by the type instead of borrowed from outside.

**Rewrite.** Just remove the lifetime / pin requirement:

```rust
// Before
struct Handle<'a> {
    inner: &'a Inner,
}

// After
struct Handle {
    inner: Box<Inner>,        // or Rc<Inner> / Arc<Inner> if shared
}
```

The user-facing API typically gets simpler:

```rust
// Before (user has to keep `inner` alive)
let inner = Inner::default();
let handle = Handle { inner: &inner };

// After
let handle = Handle::new();
```

**Trade-off.** One allocation per `Handle::new()`. For most sites, this is acceptable; for hot-path code, it's a (B) decision (measure first).

---

## Common patterns in the exemplar repos

### Pattern P-1: arena pointer → safe arena type

`/dp/frankenfs/src/cache/lru.rs` originally had:

```rust
struct LruEntry {
    next: *mut LruEntry,
    prev: *mut LruEntry,
    value: u64,
}
```

Refactor (via beads `br-2031` and `br-2032`):

```rust
struct LruEntry {
    next: Option<usize>,   // index into arena
    prev: Option<usize>,
    value: u64,
}
struct Lru {
    arena: slab::Slab<LruEntry>,
    head: Option<usize>,
    tail: Option<usize>,
}
```

The cycles in the doubly-linked list became indices into a `Slab`. Cache locality preserved; safety from the borrow checker. The (C) refactor saved 8 unsafe blocks AND eliminated a use-after-free that miri had been flagging intermittently.

### Pattern P-2: `Send` newtype for "raw pointer that's actually thread-safe"

`/dp/franken_engine/src/worker.rs` originally had:

```rust
unsafe impl Send for WorkerHandle {}   // because of *const Worker
unsafe impl Sync for WorkerHandle {}
struct WorkerHandle {
    inner: *const Worker,
}
```

Refactor (via `br-1788`):

```rust
// Newtype with audited Send/Sync
#[derive(Copy, Clone)]
struct WorkerPtr(*const Worker);
// SAFETY: WorkerPtr is only created by Worker::handle() which guarantees the
// pointed-to Worker outlives the WorkerPtr (via Arc<Worker> ownership).
unsafe impl Send for WorkerPtr {}
unsafe impl Sync for WorkerPtr {}

struct WorkerHandle {
    inner: WorkerPtr,
}
// WorkerHandle now gets Send + Sync via auto-derive (because WorkerPtr is
// Send + Sync). No unsafe impl on WorkerHandle.
```

The (A) stays on `WorkerPtr` (justified per `00-CANONICAL-UNAVOIDABLE.md § 8`); `WorkerHandle` graduates from (A) to (C).

### Pattern P-3: `mem::take` for ownership transfer

When a function needs to take a `&mut T` and replace it with a new value:

```rust
// Before
unsafe fn replace_in_place<T>(slot: *mut T, new_val: T) -> T {
    let old = std::ptr::read(slot);
    std::ptr::write(slot, new_val);
    old
}

// After
fn replace_in_place<T>(slot: &mut T, new_val: T) -> T {
    std::mem::replace(slot, new_val)
}
```

`std::mem::replace` is safe and identical-codegen for the common case. The (C) refactor is one-liner.

### Pattern P-4: invariant-establishing constructor with `pub` boundary

`/dp/mcp_agent_mail_rust/src/inbox.rs` had:

```rust
pub struct Inbox {
    /// pre-decoded entries; INVARIANT: every entry is valid UTF-8
    entries: Vec<RawEntry>,
}
// Internal code uses `from_utf8_unchecked` because of the invariant.
```

This is (B) (perf-only — saving UTF-8 re-validation). But the soundness surface includes any `pub fn` that mutates `entries`. The hardening was a `pub` constructor that ESTABLISHES the invariant + private mutation methods:

```rust
pub struct Inbox {
    entries: Vec<RawEntry>,
}
impl Inbox {
    pub fn from_jsonl(raw: &str) -> Result<Inbox, InboxError> {
        // Validate UTF-8 ONCE at the boundary.
        let entries = raw.lines()
            .map(RawEntry::parse_utf8)
            .collect::<Result<_, _>>()?;
        Ok(Inbox { entries })
    }
    pub fn push(&mut self, entry: ValidatedEntry) {
        self.entries.push(entry.into_raw());   // ValidatedEntry guarantees UTF-8
    }
    // No pub fn that takes &mut [RawEntry] or returns &mut Vec<RawEntry>.
}
```

Now the (B) `from_utf8_unchecked` internal calls are sound because every `RawEntry` was constructed through a UTF-8-validating path. Caller-side soundness is automatic.

---

## Equivalence-proving patterns

For a `*mut T` → `NonNull<T>` migration, the equivalence test is trivial — the operations have identical semantics. For higher-step migrations, the test should exercise:

1. **Normal use.** Inputs that produce a value: `f_unsafe(x) == f_safe(x)`.
2. **Failure cases.** Inputs that produce an error: `f_unsafe(x).err() == f_safe(x).err()` (error variants must match).
3. **Panic cases.** Inputs that panic: same panic message, same payload (use `std::panic::catch_unwind` + `Any::downcast_ref::<&str>` for primitive panics).
4. **Drop order.** Inputs that cause early-drop: the order of destructor calls must match. Use a `DropTracker` test fixture that logs drop events to a `Vec<&'static str>`.
5. **Allocator pressure** (for (B) graduating to (C)). Inputs that allocate: same total allocation count, same max-concurrent allocations (via `tikv-jemallocator` stats or `tracking-allocator`).

A property test that covers all five classes is hard to fake. The audit-grade equivalence test is one of these.

---

## What NOT to do

- **Don't introduce `unwrap()` to convert `NonNull` to `&T`.** A panic in a function that the unsafe version assumed couldn't panic is a behavioral regression — even if the panic "can't happen." Use `?` + a proper error variant if the operation is fallible; or document the unreachable-ness in a SAFETY comment.
- **Don't change the public API silently.** A `pub fn handle(&self) -> *const Inner` → `pub fn handle(&self) -> &Inner` is API-changing. The (C) plan must document the migration path for downstream users.
- **Don't change the allocator silently.** A raw pointer obtained from a custom allocator must NOT graduate to `Box<T>` without preserving the allocator.
- **Don't widen visibility.** A previously-private `unsafe fn` becoming a `pub fn safe_thing` widens the soundness surface; every new caller must be audit-ready.

---

## Acceptance signal

A pointer-migration (C) classification passes when:

1. The step in the hierarchy is named (e.g., "step 1: `*mut T` → `NonNull<T>`").
2. Full safe replacement code is pasted into the plan.
3. The property-based equivalence test is authored and passes.
4. `cargo +nightly miri test` runs the equivalence test clean.
5. Allocator identity is preserved (or the change is approved).
6. Public API is unchanged (or the migration path is documented).
7. The bench (criterion + hyperfine) shows no regression > the user's perf budget.

If any of these is missing, the site goes back to refactor-planner.
