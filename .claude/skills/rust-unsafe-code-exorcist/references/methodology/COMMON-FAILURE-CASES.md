# COMMON-FAILURE-CASES.md — Failure Catalog

A reference catalog of unsafe-related failure modes the exemplar repos have shipped (and fixed). Each entry: symptom, what was wrong, how the audit would catch it, how to fix.

Use during Phase 4/6 classification — when you see a symptom, find the matching entry to inform the classification.

---

## F-001 — Use-after-free in arena pointer

**Symptom.** Crash (SIGSEGV) when iterating after a Vec resize.

**Root cause.** Code stored a raw `*mut T` into a `Vec<T>`. When the Vec resized, the backing buffer moved; the raw pointer became dangling.

**How to catch.** miri stacked-borrows; cargo-fuzz hitting a resize during iteration.

**Fix.** (C): replace raw pointer with `usize` index into the Vec, or replace Vec with `slab::Slab<T>` for stable indices.

**Exemplar.** `/dp/frankenfs/src/cache/lru.rs` — bead `br-ffs-148` analog.

---

## F-002 — Double-drop via panic in mid-init

**Symptom.** Heisenbug: occasional double-free reports from the allocator.

**Root cause.** Code used `MaybeUninit::<[T; N]>::uninit().assume_init()` then wrote fields in a loop. A panic from one of the field constructors left the array partially initialized; the array's destructor ran on partially-uninit memory, calling `Drop` on garbage.

**How to catch.** miri; or a property test that injects panics partway through init.

**Fix.** (C): use `std::array::from_fn`, OR use a guard struct with custom `Drop` that only drops initialized prefix, OR use `arrayvec::ArrayVec`.

**Exemplar.** [70-UNINIT-AND-TRANSMUTE.md § Pattern U-3](../patterns/70-UNINIT-AND-TRANSMUTE.md).

---

## F-003 — Data race on `unsafe impl Sync`

**Symptom.** Tests pass; production has nondeterministic incorrect-data bugs under load.

**Root cause.** `unsafe impl Sync` was declared without auditing every field. A later field addition (`Rc<T>` or `Cell<T>`) silently broke the soundness obligation.

**How to catch.** miri with `-Zmiri-disable-isolation` and threaded tests; loom modeling.

**Fix.** (C): delete the manual impl; add `static_assertions::assert_impl_all!(MyType: Send + Sync)` to lock auto-derive. Or, if `Sync` must remain, refactor the offending field into an audited `SendPtr<T>` newtype.

**Exemplar.** [50-SEND-SYNC-IMPLS.md](../patterns/50-SEND-SYNC-IMPLS.md).

---

## F-004 — Panic across FFI

**Symptom.** Process aborts when a Rust callback panics inside a C library.

**Root cause.** `extern "C"` Rust functions don't catch panics; Rust unwinding through C frames is UB. Default-panic-strategy `unwind` was active.

**How to catch.** cargo-fuzz on the C-side callbacks; or a test that deliberately panics inside an FFI callback.

**Fix.** (A) hardening: set `[profile.release] panic = "abort"` AND/OR wrap every `#[no_mangle] extern "C" fn` body in `std::panic::catch_unwind`. Document in the FFI boundary contract.

**Exemplar.** [60-FFI-PATTERNS.md § F-3](../patterns/60-FFI-PATTERNS.md).

---

## F-005 — Pin invariant violated after move

**Symptom.** Async future segfaults after being scheduled.

**Root cause.** A future containing a self-reference was constructed and then moved (e.g., transferred ownership to a Vec). The self-reference now points to invalid memory.

**How to catch.** miri on the pinned-then-moved path; explicit `static_assertions::assert_not_impl_any!(MyFuture: Unpin)` test.

**Fix.** (A) for the self-referential case: the constructor MUST return `Pin<Box<Self>>` (not `Self`); the type MUST be `!Unpin` via `PhantomPinned`. Document in the SAFETY comment.

**Exemplar.** [80-PIN-PROJECTIONS.md § P-3](../patterns/80-PIN-PROJECTIONS.md); `/dp/mcp_agent_mail_rust/src/ws/stream.rs`.

---

## F-006 — Async cancellation leaks mmap

**Symptom.** Memory map count grows; eventually `MAP_FAILED: too many mappings`.

**Root cause.** An async function `await`'d in the middle of an mmap-using operation. The future was cancelled (dropped at the await point); the mmap'd region was never `munmap`'d because the cleanup was past the await.

**How to catch.** Property test that cancels the future at every `await` point; check `/proc/<pid>/maps` count.

**Fix.** (C): wrap the mmap'd region in a `MmapHandle` newtype with `Drop` impl. Use the handle as an owned local — its Drop runs on cancellation.

**Exemplar.** [60-FFI-PATTERNS.md § F-2 owned-handle types](../patterns/60-FFI-PATTERNS.md); `/dp/asupersync/src/io/mmap.rs`.

---

## F-007 — Stale stacked-borrows reborrow

**Symptom.** miri error: "no item granting read access ... at offset X".

**Root cause.** Code took `&mut x`, reborrowed as `*mut T`, wrote through the raw pointer, then USED the original `&mut x` again. Under stacked borrows, the original `&mut` was invalidated by the raw write.

**How to catch.** miri default mode.

**Fix.** (C): restructure to drop the `&mut` before the raw-pointer write, OR use `Tree Borrows` if the pattern is otherwise sound (see [STACKED-VS-TREE-BORROWS.md](STACKED-VS-TREE-BORROWS.md)).

---

## F-008 — Provenance violation: usize round-trip

**Symptom.** miri error under `-Zmiri-strict-provenance`: "pointer with no provenance".

**Root cause.** Code did `(p as usize | flag) as *mut T` — the cast through usize lost provenance under strict-provenance.

**How to catch.** miri with strict-provenance flag.

**Fix.** (C): use `p.map_addr(|a| a | flag)` to preserve provenance. See [PROVENANCE-MODEL.md § How to write code that works under both](PROVENANCE-MODEL.md).

---

## F-009 — Transmute size mismatch

**Symptom.** Garbage values; sometimes panic on type-specific invariants (e.g., a `String` with invalid UTF-8).

**Root cause.** `mem::transmute<S, T>` where `S` and `T` had different sizes OR different validity invariants (e.g., transmute from `[u8; 4]` to a non-Pod type).

**How to catch.** Compile-time: `transmute` requires same size; the compiler errors. But for `transmute_copy` or `from_raw_parts` patterns, the check is at runtime.

**Fix.** (C): use `zerocopy::Ref::new` (returns Option) or `bytemuck::try_cast` (returns Result). Eliminates the runtime risk.

**Exemplar.** [70-UNINIT-AND-TRANSMUTE.md § Pattern T-1](../patterns/70-UNINIT-AND-TRANSMUTE.md).

---

## F-010 — Allocator-pressure regression after "safe" refactor

**Symptom.** Hot-path allocation count doubles; p99 latency grows 30%.

**Root cause.** A (C) refactor replaced `bumpalo::Vec<T>` (arena-allocated) with `std::vec::Vec<T>` (global-allocated). Same code shape, different allocator. Per-request arena was a perf load-bearer.

**How to catch.** `cargo bench` + hyperfine on the workload; tracking-allocator stats.

**Fix.** (C) revision: use `bumpalo::collections::Vec<T>` in the arena's scope. Preserve allocator identity. Or document the change explicitly + benchmark + get user approval.

**Exemplar.** [00-CANONICAL-UNAVOIDABLE.md § Allocator-identity](../patterns/00-CANONICAL-UNAVOIDABLE.md#allocator-identity-cross-cutting).

---

## F-011 — Loom budget exhausted

**Symptom.** `loom::model` panics: "preemption_bound exceeded".

**Root cause.** The concurrent code has more interleavings than the default budget allows.

**How to catch.** loom suite running.

**Fix.** Either (a) reduce the model size (test fewer threads / fewer ops), (b) expand the budget via `Builder::preemption_bound(3)`, or (c) accept the partial coverage and document. The bar for (C) acceptance: at least one bound where the test completes; document the bound.

---

## F-012 — Mutation test missed (test isn't pinning behavior)

**Symptom.** A subsequent refactor breaks behavior; the test suite passed for both versions.

**Root cause.** The test was checking only `result.is_ok()` rather than `result == expected`. cargo-mutants would have caught this: a mutation that returned a different `Ok(value)` still passed the test.

**How to catch.** cargo-mutants.

**Fix.** Tighten the test to compare against exact expected values. Re-run mutants until coverage > 80%.

---

## F-013 — Drop order changed in safe rewrite

**Symptom.** A test passes; production trips a lock-already-held assertion.

**Root cause.** Original unsafe code dropped resources in order A → B → C. Safe rewrite uses different scope shapes that drop B → A → C. A subtle ordering dependency exists.

**How to catch.** DropTracker fixture (per [10-POINTER-MIGRATIONS.md § Equivalence-proving patterns](../patterns/10-POINTER-MIGRATIONS.md)).

**Fix.** Restructure the rewrite to preserve the original drop order. Or document the change + get user approval if the new order is actually fine.

---

## F-014 — Async-cancellation hazard from holding mutex across await

**Symptom.** Deadlock under cancellation: a task drops at an await point while holding a mutex; the mutex is never released because no destructor runs (the `MutexGuard` is dropped, but a follow-up async op was waiting on a different lock).

**Root cause.** `let guard = mutex.lock().await; complex_async_op().await;` — between the two awaits, the guard is held; if the second await is cancelled, the program may be left in an inconsistent state.

**How to catch.** clippy's `await_holding_lock` lint; manual review per operator 🔁 Async-Cancellation-Trace.

**Fix.** Restructure to release the guard before the inner await:

```rust
{ let guard = mutex.lock().await; do_quick_op(&*guard); }    // guard dropped
complex_async_op().await;
```

---

## F-015 — `unreachable_unchecked` reached

**Symptom.** Process crashes inexplicably; debug build behaves differently from release.

**Root cause.** Code used `core::hint::unreachable_unchecked()` based on an invariant that's no longer true (e.g., a `match` covered all enum variants at the time; a new variant was added later and the catch-all became reachable).

**How to catch.** miri (reaches the unreachable; reports UB); a property test exercising all enum variants.

**Fix.** Replace `unreachable_unchecked` with `unreachable!()` if perf isn't critical (panic instead of UB). Or, if perf is critical, add a `#[non_exhaustive]` test that catches the next variant addition.

---

## F-016 — `Cell<*mut T>` data race

**Symptom.** Process crashes with various-looking symptoms under multi-thread load.

**Root cause.** A type held `Cell<*mut T>` (interior mutability). The type was `Sync` (incorrectly — `Cell` is `!Sync`). Multiple threads mutated the cell.

**How to catch.** Compile error if you try to `Sync` a `Cell`. Bug if `unsafe impl Sync` was declared anyway.

**Fix.** (C): replace `Cell<*mut T>` with `AtomicPtr<T>` or `RwLock<*mut T>`. Or, if single-threaded usage is the actual contract, mark the type `!Sync` (delete the unsafe impl).

---

## How to use this catalog

When you see a symptom matching one of F-001 through F-016 (and growing), reference the entry in:

- The per-site write-up — "this site appears to match F-001 (use-after-free in arena pointer)."
- The classification — "per F-001, the canonical refactor is (C)."
- The plan — "rewrite per F-001's standard fix."

The catalog grows as the audit finds new failure modes. Each new entry follows the same template: symptom, root cause, how to catch, how to fix, exemplar precedent.

---

## Catalog hygiene

- One F-NNN per distinct failure mode.
- Each entry has at least one detection method (the audit must be able to find this kind of bug).
- Each entry has at least one fix recipe (or explicit "no fix; document as (A)").
- Exemplar precedent links to a real commit / bead / pattern bundle.
- The catalog is referenced by the operator library and the classification rubric.

The `validate-corpus.py` script can be extended to verify catalog integrity (every F-NNN has the required sections).
