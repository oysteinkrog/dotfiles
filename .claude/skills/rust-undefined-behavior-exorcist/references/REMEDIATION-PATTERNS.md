# Remediation Patterns — The Isomorphic-Rewrite Playbook

When `⊕ REWRITE` fires, the architect must enumerate *at least two* isomorphic rewrites for the UB shape and score each on the rubric. This file is the playbook for common shapes.

---

## Rubric (every rewrite gets a 0–4 score per axis)

| Axis | What it asks |
|---|---|
| **Correctness margin** | Does this *eliminate* the UB, or just *hide* it? Does it shrink the unsafe surface or relocate it? |
| **Performance delta** | Vs. current code (benchmark when available). 0 = severe regression; 4 = neutral or faster |
| **Diff blast radius** | LOC and files touched. 0 = whole-module rewrite; 4 = one-line patch |
| **Reviewability** | How easy is it to peer-review? 0 = requires deep familiarity with the codebase; 4 = self-evidently correct |
| **Maintainability** | Will this stay correct as the codebase evolves? 0 = fragile to neighbor changes; 4 = robust |

Pick the winner; record runners-up with scores and tradeoffs. A future maintainer revisiting the choice should be able to see the alternatives without re-deriving them.

---

## Shape 1: Self-Referential Struct

A struct that holds a pointer into its own data (e.g., a parser that owns a `String` and a `&str` into it).

| Candidate | Pros | Cons |
|---|---|---|
| `Pin<Box<T>>` with `Pin::new_unchecked` | Smallest diff; preserves layout | Requires `!Unpin`; easy to get wrong; UB if `Pin` invariant breaks |
| Arena + `Index` (e.g., `usize` into a `Vec<T>`) | No raw pointers; index instead of reference; cheap clones via the index | Need to thread the arena handle through |
| `Rc<RefCell<T>>` graph | No `unsafe`; familiar | Refcount overhead; cycles leak |
| `ouroboros` crate | Macro-generated boilerplate; documented contract | Adds a dep; macro magic harder to debug |
| `yoke` crate | Same shape as ouroboros; idiomatic for zero-copy parsing | Cognitive overhead |

**Default pick:** arena + index, unless the perf delta is unacceptable, in which case `ouroboros`.

---

## Shape 2: Intrusive Linked List

A list where the node's prev/next pointers are inside the node, not in a separate Box.

| Candidate | Pros | Cons |
|---|---|---|
| `intrusive-collections` crate | Well-audited; covers most needs | Adds dep |
| Doubly-linked `Vec`-backed list with `Option<usize>` next/prev | No unsafe; cache-friendly | Doesn't allow O(1) "remove from middle by reference" without a side table |
| `Pin<Box<Node>>` graph with manual `Drop` | Smallest diff if the API constraints require pointer identity | Easy to leak; `Drop` for cycles requires care |
| `slotmap` crate + index | Same as Vec-backed but with safe handle invalidation | Adds dep |

**Default pick:** `slotmap` for new code; `intrusive-collections` for ports of existing C code.

---

## Shape 3: Lock-Free Queue / Stack

Custom MPMC/SPSC/etc. queues with hand-written atomic logic.

| Candidate | Pros | Cons |
|---|---|---|
| `crossbeam::queue::ArrayQueue` / `SegQueue` | Battle-tested; loom-modeled | Less flexible than custom |
| `flume` / `kanal` | Convenient API | mpsc-only or other constraint |
| `tokio::sync::mpsc` / `mpmc` | Async-friendly | tokio dep |
| Keep custom + comprehensive loom + shuttle + fuzz | Best perf if the custom impl was tuned | Engineering cost; requires loom & shuttle harness as permanent CI gates |

**Default pick:** crossbeam unless the custom impl was demonstrably faster *and* you commit to permanent loom/shuttle CI. The runner-up should always be "drop the custom impl and use crossbeam".

---

## Shape 4: Custom `unsafe impl Send` / `unsafe impl Sync`

A type wraps a `*mut T` or a non-Sync type and declares itself thread-safe.

| Candidate | Pros | Cons |
|---|---|---|
| Wrap in `Arc<Mutex<T>>` | Removes the unsafe impl entirely | Lock overhead per access |
| Wrap in `Arc<RwLock<T>>` | Read-heavy workloads | Same overhead, larger struct |
| Use atomic primitives directly (`AtomicPtr`, `AtomicU64`) | No locks; minimal overhead | Requires re-thinking the data structure |
| Keep `unsafe impl` + loom proof | If the synchronization is external (mmap + fcntl, hardware barriers) | Loom model must cover every reachable interleaving |
| Use parking_lot's lock types | Faster than std; same API | Adds dep |

**Default pick:** prefer the lock; the perf cost is rarely worth the soundness risk. Keep the custom impl only when the external synchronization is real and provable (frankensqlite's mmap+fcntl is the textbook case).

---

## Shape 5: Raw FFI Handle

A C library returns a `*mut Handle` and Rust holds onto it.

| Candidate | Pros | Cons |
|---|---|---|
| `OwnedFd` / `OwnedHandle` (std) | Standard library handles UNIX/Windows fd lifecycle correctly | Only applies to fd/HANDLE; not arbitrary opaque pointers |
| Typed newtype wrapper with `Drop` calling the C close fn | Minimal diff; idiomatic | Manual care to never double-close |
| `Pin<Box<RawHandle>>` | When the C library expects address stability | Hardly different from raw pointer in practice |
| Use a crate that wraps the C library (`bindgen` + sys crate split + high-level wrapper) | Long-term maintainability | Initial engineering cost |

**Default pick:** typed newtype with `Drop`. Make `Drop` non-blocking; if the C close fn can block, document it in a `# Panics` section and use a non-blocking variant (e.g., `close_nonblocking`).

---

## Shape 6: Type Punning via `transmute`

Reinterpreting bytes of one type as another.

| Candidate | Pros | Cons |
|---|---|---|
| `bytemuck::cast` / `bytemuck::pod_align_to` | Compile-time-verified safe casts via `Pod` + `Zeroable` | Requires deriving `Pod` (no padding allowed) |
| `zerocopy::FromBytes` + `AsBytes` | Same as bytemuck with slightly different API and per-field control | Similar constraints |
| Explicit byte copy via `to_ne_bytes` / `from_ne_bytes` | Always safe; fewer constraints | Slight overhead for copy |
| `#[repr(C)]` + named-field access | Eliminates the transmute entirely | Requires changing the type |

**Default pick:** `bytemuck` for POD types; `to_ne_bytes` for individual primitives.

---

## Shape 7: `unsafe { …assume_init() }` from `MaybeUninit`

A buffer is allocated via `MaybeUninit::<T>::uninit()`, partially filled, then `assume_init` called early.

| Candidate | Pros | Cons |
|---|---|---|
| Track init-len explicitly; only call `assume_init` on prefix | Sound and minimal | Boilerplate |
| Use `Vec::spare_capacity_mut` + `set_len` after filling | Idiomatic | Easy to forget to set_len |
| Use `MaybeUninit::write` repeatedly + `MaybeUninit::slice_assume_init_ref` (nightly `feature(maybe_uninit_slice)`) — or hand-transmute on stable | Per-element init; provably sound | Verbose; nightly-only without the hand transmute |
| Switch to safe iteration (`collect`) | Trivially sound | Allocates twice for capacity-then-fill |

**Default pick:** `MaybeUninit::write` per element + `set_len` on a `Vec` (stable); fall back to `MaybeUninit::slice_assume_init_ref` only if `Vec`-backed storage is not acceptable and the project already uses nightly with `feature(maybe_uninit_slice)`.

---

## Shape 8: Pointer Arithmetic Across Allocations

`ptr.add(n)` where `n` exceeds the original allocation.

| Candidate | Pros | Cons |
|---|---|---|
| `slice::get(n).map(|x| x as *const _)` | Bounds-checked | Returns Option, must propagate |
| `ptr.wrapping_add(n)` then explicit bounds check | Sound; explicit | Verbose |
| Restructure to slice indexing | Idiomatic | May require rethinking the data structure |

**Default pick:** restructure to slice indexing. Pointer arithmetic should be the last resort.

---

## Shape 9: Macros That Hide Unsafe

A macro expands to `unsafe { … }` that's invisible to readers.

| Candidate | Pros | Cons |
|---|---|---|
| Inline the macro at every callsite | Visibility | Bloats the diff |
| Annotate the macro itself with `#[allow(unsafe_op_in_unsafe_fn)]` and a top-level `// SAFETY:` comment | Documents the unsafe contract once | Doesn't prevent the unsafe from being there |
| Replace the macro with a safe inline function | Best | Sometimes the macro's purpose was the inlining |

**Default pick:** replace with safe inline function if possible; otherwise annotate.

---

## Shape 10: Drop That Performs Blocking I/O

A `Drop` impl that calls `flush()`, `close()`, or `wait()` — any of which can block.

| Candidate | Pros | Cons |
|---|---|---|
| Move the I/O to an explicit `close()` method; `Drop` only releases the memory | Standard pattern (close/dispose) | Caller must remember to close |
| Spawn a background task / detached thread in `Drop` | Non-blocking | Hides the work |
| Reroute via runtime's `blocking_pool` (async-only) | Async-friendly | Tokio dep |
| `Drop` uses non-blocking variant (e.g., `waitpid(WNOHANG)`) | Non-blocking + still cleans up | Requires the OS to support a non-blocking variant |

**Default pick:** explicit close method + assertive `Drop` that warns if not closed (using `track_caller` or a flag set by `close()`).

---

## Selecting a Remediation: The Process

1. Read the `CONFIRMED_UB` finding. Identify which shape (from the list above) it matches. If novel, document the shape in [REMEDIATION-PATTERNS.md](REMEDIATION-PATTERNS.md) as you go.
2. Enumerate at least the two top candidates for that shape.
3. Score each on the rubric (0–4 per axis). Be quantitative on perf — run a benchmark if a candidate is in the "performance delta" 0–1 range.
4. Pick the winner. Document why it beat the runner-up on the dominant axis.
5. Record the runner-up with its scores so future maintainers can revisit.
6. Cross-reference: which `EXP-NNN` proved the original was UB? Which experiment will prove the remediation is sound?

---

## Shape 11: Panicking From `Drop`

A `Drop` impl that can panic, especially during stack unwinding (double-panic = abort).

| Candidate | Pros | Cons |
|---|---|---|
| `Drop` becomes infallible; errors logged via tracing | Sound; never aborts | Loses error visibility for ops |
| `Drop` uses `mem::take` to extract state; user-callable `close()` returns Result | Caller chooses to handle errors | Caller must remember to close |
| `std::panicking::panicking()` guard — skip the panicking branch if already unwinding | Local | Subtle; easy to forget |
| Use `defer` / `scopeguard` for resource cleanup outside `Drop` | Explicit | Adds dep |

**Default pick:** infallible `Drop` + explicit `close() -> Result<()>` for the error path.

---

## Shape 12: Blocking FFI in Async Context

An async function that calls a blocking FFI routine without `spawn_blocking`.

| Candidate | Pros | Cons |
|---|---|---|
| `tokio::task::spawn_blocking(|| ffi_call())` | Standard tokio pattern | Allocates a task |
| `async_std::task::spawn_blocking` | async-std equivalent | Tokio-incompatible |
| Make the function `fn` (not `async`) and let callers wrap | Explicit | Caller burden |
| Use a thread pool dedicated to FFI (rayon-style) | Predictable | More infrastructure |

**Default pick:** `spawn_blocking` for tokio crates; `fn` (not `async`) for general libraries.

---

## Shape 13: Intrusive Linked List With ABA Hazard

Hand-rolled lock-free intrusive list where node addresses get reused (epoch-based reclamation needed).

| Candidate | Pros | Cons |
|---|---|---|
| `crossbeam_epoch` for EBR | Battle-tested | Adds dep + epoch overhead |
| Generation counter per slot (asupersync pattern) | No dep | Manual; easy to mess up |
| Replace with `slotmap` + safe API | No unsafe | API change |
| Tag pointers (64-bit pointer with 16-bit tag) | Tight | Limits address space; UB if pointer escapes the tag-aware code |

**Default pick:** `crossbeam_epoch` unless perf measurement justifies the custom generation-counter path; then keep the generation counter + comprehensive loom model.

---

## Shape 14: Hand-Rolled Atomic Refcount

A custom `Arc`-equivalent built from `AtomicUsize`.

| Candidate | Pros | Cons |
|---|---|---|
| Use `Arc` | Trivially sound | May have features `Arc` doesn't |
| Use `triomphe::Arc` or `archery::ArcK` | Drop-in with features (no-weak-ptr, etc.) | Adds dep |
| Keep custom + comprehensive loom model + soak campaign | If you measured a reason | Engineering cost; high-risk |
| Use `portable-atomic` for cross-platform atomic widths | Sound on platforms missing native CAS | Adds dep |

**Default pick:** `Arc`, unless a specific feature is missing — and even then, prefer a maintained crate over hand-rolled.

---

## Shape 15: Custom Allocator With Arena

A bump-arena allocator where deallocation is per-arena-reset rather than per-allocation.

| Candidate | Pros | Cons |
|---|---|---|
| `bumpalo` crate | Battle-tested | Less customizable |
| `typed-arena` crate | Type-safe | One type per arena |
| Keep custom + Miri + property tests + Kani proof | If you measured a reason | Engineering cost |
| Add a `safe_arena` feature flag with `Box`-backed fallback | Lets users opt-in to safety | More code |

**Default pick:** `bumpalo`. Reserve custom for cases where its API is genuinely insufficient.

---

## Shape 16: MMIO With Volatile

Memory-mapped I/O register access where each read/write must be atomic + observable to hardware.

| Candidate | Pros | Cons |
|---|---|---|
| `volatile-register` crate | Type-safe; per-register read/write rights | Adds dep |
| Direct `ptr::read_volatile` / `write_volatile` + alignment assert | Stdlib only | Manual safety |
| `embedded-hal` traits | Abstracts the register | Heavyweight for one driver |

**Default pick:** `volatile-register` for embedded; raw `ptr::*_volatile` only if the type isn't already wrapped.

---

## Shape 17: Async Cancellation Safety

An async function that holds state across `.await` points; cancellation in the middle leaves the state inconsistent.

| Candidate | Pros | Cons |
|---|---|---|
| Move state into a `tokio::select!` cancellation-safe branch | Standard pattern | Restructures the function |
| Use `Drop` to clean up partial state | Idiomatic | Drop can't be async; may need `tokio::task::block_in_place` |
| Use `tokio::pin!` to keep the future address-stable; clean up explicitly | Explicit | Verbose |
| Make the operation atomic at the syscall level (`io_uring` ops with `set_link`) | Hardware-level atomic | Linux-only |

**Default pick:** restructure so the state is fully constructed before any `.await` AND fully consumed before the next `.await`.

---

## Shape 18: Scoped Threads vs. `Arc` Sharing

A pattern where multiple threads need shared `&` access to local data; the natural fit is scoped threads, not Arc.

| Candidate | Pros | Cons |
|---|---|---|
| `std::thread::scope` (Rust 1.63+) | Stdlib; no Arc cost | Stack-allocated state has a fixed end |
| `rayon::scope` | Work-stealing; no Arc cost | Adds dep |
| `crossbeam::thread::scope` | Pre-stdlib equivalent | Adds dep |
| `Arc<T>` + `Send + Sync` | Familiar | Refcount overhead; UB if `T` isn't actually Sync |

**Default pick:** `std::thread::scope` if available; rayon if work-stealing is desired.

---

## Shape 19: Type-State Machines (encoding state in the type)

A type with multiple states where transitions are enforced by the type system.

| Candidate | Pros | Cons |
|---|---|---|
| Enum with all states + `match` per method | Standard | Runtime check + risk of unreachable arms |
| Sealed traits + phantom types | Compile-time safety | Type-system gymnastics |
| `typestate` crate | Macro-generated | Adds dep |
| `state_machine_future` crate (async) | Async-specific | Older; may be unmaintained |

**Default pick:** for stable APIs, sealed traits + phantom types; for prototyping, enum + `match`.

---

## Shape 20: Hash + Eq Consistency

A type used as a `HashMap` key with mismatched `Hash` and `Eq` impls.

| Candidate | Pros | Cons |
|---|---|---|
| Derive both from the same fields | Trivially consistent | May not give the equality semantics you want |
| Manual `Hash` that calls `Eq`-comparing fields in the same order | Explicit | Easy to drift |
| Wrap in a newtype with `derive(Hash, PartialEq, Eq)` | Sound | Adds wrapper type |
| Use `indexmap::IndexMap` which preserves insertion order (sometimes the actual goal) | Predictable iteration | Adds dep; different perf |

**Default pick:** derive both from the same fields + proptest harness asserting `a == b ⟹ hash(a) == hash(b)` (this is exemplar E8's pattern).

---

## When Formal Verification Is Worth The Cost

Reserve Kani / Prusti / Creusot for code where the consequences of getting the remediation wrong are catastrophic:

- Custom allocator (one wrong byte = corrupt the whole heap)
- Lock-free data structure used in production-critical paths
- Cryptographic primitive
- FFI surface to a kernel module

For ordinary code, the test/Miri/loom/sanitizer stack is enough. Formal verification adds weeks of engineering for diminishing returns when the dynamic stack already converges.
