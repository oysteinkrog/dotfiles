# Invariant Catalog — 60+ Common Rust Safety Invariants

Every `unsafe { ... }` block carries a SAFETY contract. The contract is a set of **invariants** the unsafe operation depends on. Vague SAFETY comments fail (see anti-pattern A1, A5).

This file is the catalog. Each entry has the **invariant**, **how to write the SAFETY comment**, and **how to enforce or test** the invariant.

Use this catalog when writing or reviewing SAFETY comments. Operator ☣ SAFETY-NOTES-FIRST in particular benefits from a checklist.

---

## Aliasing invariants (UB bucket #1)

### I-A01 — `*mut T` deref while no live `&T` to the same place

**SAFETY:** "The shared borrow `r` from line N is out of scope by line M before we deref `m`."

**Enforce:** Lifetimes already enforce this for safe Rust. For raw pointers, manual reasoning + Miri tree-borrows.

**Test:** Miri TB; if SB is also clean, the invariant is robust.

### I-A02 — `&mut T` is unique for its entire lifetime

**SAFETY:** "No `&T` or `&mut T` to the same memory exists during this lifetime."

**Enforce:** Borrow checker + careful raw-pointer code.

**Test:** Miri TB.

### I-A03 — Multiple `&T` are OK but no concurrent `&mut`

**SAFETY:** "Every concurrent reference is shared (`&`); no `&mut` exists."

**Enforce:** `RwLock` for runtime; `&T` borrows for compile-time.

**Test:** Miri + TSan for multi-threaded.

### I-A04 — `slice::from_raw_parts_mut` regions don't overlap with `from_raw_parts`

**SAFETY:** "The pointer ranges `[ptr_a, ptr_a + len_a)` and `[ptr_b, ptr_b + len_b)` are disjoint."

**Enforce:** Bounds-check the offsets manually before constructing the slices.

**Test:** Miri; assert via `assert!(ptr_a.add(len_a) <= ptr_b || ptr_b.add(len_b) <= ptr_a);` in debug builds.

---

## Provenance invariants (UB bucket #2)

### I-P01 — Pointer arithmetic stays within the original allocation

**SAFETY:** "offset is in `0..len_of_allocation`."

**Enforce:** `slice.get(offset).map(|x| x as *const _)` instead of `ptr.add(offset)`.

**Test:** Miri strict-provenance.

### I-P02 — Pointer ↔ integer roundtrip preserves provenance

**SAFETY:** "We use `ptr.with_addr(addr)` or `ptr.map_addr(|a| ...)`, not `(ptr as usize as *const _)`."

**Enforce:** Clippy `clippy::ptr_as_ptr`, `clippy::cast_ptr_alignment`.

**Test:** Miri strict-provenance.

### I-P03 — Pointer cast preserves type compatibility

**SAFETY:** "Source and target types have the same layout (size + alignment + niches)."

**Enforce:** `static_assertions::assert_eq_size!`, `static_assertions::assert_eq_align!`.

**Test:** Miri.

---

## Alignment invariants (UB bucket #3)

### I-AL01 — Pointer alignment ≥ alignof::<T>()

**SAFETY:** "`ptr.addr() % align_of::<T>() == 0`."

**Enforce:** `debug_assert!(ptr.addr() % align_of::<T>() == 0);` before deref.

**Test:** Miri symbolic-alignment-check.

### I-AL02 — `#[repr(packed)]` field never read by reference

**SAFETY:** "We use `addr_of!(packed.field)` and `read_unaligned`, not `&packed.field`."

**Enforce:** Clippy `unaligned_references` (now hard-error).

**Test:** Build clean under modern rustc.

### I-AL03 — Mmap base pointer alignment

**SAFETY:** "mmap returns page-aligned memory; PAGE_SIZE >= align_of::<T>() for our types."

**Enforce:** `assert_eq!(ptr.addr() % PAGE_SIZE, 0)` after mmap.

**Test:** Run on the smallest page-size target (16K aarch64 mac) before shipping.

---

## Validity invariants (UB bucket #4)

### I-V01 — `bool` is 0 or 1

**SAFETY:** "We never transmute non-{0,1} bytes into bool."

**Enforce:** `mem::zeroed::<bool>()` is OK (0 = false). `transmute::<u8, bool>(2)` is UB.

**Test:** Clippy `transmute_int_to_bool`, Miri validity check.

### I-V02 — `char` is a valid Unicode scalar

**SAFETY:** "Source value is < 0xD800 or > 0xDFFF and < 0x110000."

**Enforce:** `char::from_u32(n).ok_or(...)?` instead of `mem::transmute::<u32, char>(n)`.

**Test:** Miri validity check.

### I-V03 — `enum` discriminant is one of the declared variants

**SAFETY:** "Source value is in the discriminant range."

**Enforce:** Clippy `transmute_int_to_non_zero`, `transmute_undefined_repr`.

**Test:** Miri validity check.

### I-V04 — `NonZero*` is non-zero, `NonNull` is non-null

**SAFETY:** "Source value is statically non-zero/non-null."

**Enforce:** Use `NonNull::new(p).ok_or(...)?` instead of `NonNull::new_unchecked`.

**Test:** Miri validity check.

### I-V05 — `&T` / `&mut T` / `Box<T>` are non-null and aligned

**SAFETY:** "Source pointer is non-null and aligned for T; the pointee is initialized and valid for T."

**Enforce:** Bounds + alignment checks before reference materialization.

**Test:** Miri.

---

## Uninit invariants (UB bucket #5)

### I-U01 — `MaybeUninit::assume_init` only after every byte is written

**SAFETY:** "All N bytes of `T` are initialized via `MaybeUninit::write` or direct assignment before `assume_init`."

**Enforce:** Track initialization state in the type system; prefer `array::from_fn` or `Vec::extend`.

**Test:** Miri; the MaybeUninit pattern is well-tested.

### I-U02 — `Vec::set_len` only after writes

**SAFETY:** "Indices `[old_len, new_len)` are all initialized before `set_len(new_len)`."

**Enforce:** Use `Vec::spare_capacity_mut` + `MaybeUninit::write` + `set_len`.

**Test:** Miri + property test.

### I-U03 — Reading padding bytes only as `MaybeUninit<u8>`

**SAFETY:** "Reads of struct padding are typed as `MaybeUninit<u8>`, not `u8`."

**Enforce:** `bytemuck::Pod` derives forbid padding implicitly.

**Test:** Miri.

---

## Type punning invariants (UB bucket #6)

### I-T01 — `transmute<A, B>` source and target are layout-compatible

**SAFETY:** "A and B have identical size, alignment, and niche optimizations. Both are `#[repr(C)]`, `#[repr(transparent)]`, or identical primitives."

**Enforce:** `static_assertions::assert_eq_size!`, `assert_eq_align!`. Prefer `bytemuck::cast`.

**Test:** Miri; the bytemuck/zerocopy derive macros enforce at compile time.

### I-T02 — `transmute<&T, &mut T>` is forbidden

**SAFETY:** Never write this. There is no SAFETY contract that makes it sound.

**Enforce:** Clippy `transmute_ref_to_mut` (= `cast_ref_to_mut` = `invalid_reference_casting`).

**Test:** Static analysis is sufficient.

---

## Data race invariants (UB bucket #7)

### I-R01 — Atomic ordering establishes happens-before

**SAFETY:** "Producer uses `Release`; consumer uses `Acquire`. Together they establish happens-before for the protected data."

**Enforce:** Audit every `Ordering::Relaxed` for whether HB is needed.

**Test:** Loom + TSan. TSan + `--test-threads=1` is the gold standard.

### I-R02 — Shared mutable state behind a lock

**SAFETY:** "All access to `Inner` is gated by `Mutex<Inner>::lock()`."

**Enforce:** Type system: `Mutex<Inner>` instead of `UnsafeCell<Inner>` + `unsafe impl Sync`.

**Test:** Loom.

### I-R03 — Single producer / single consumer

**SAFETY:** "Only thread X writes; only thread Y reads. No other threads access the data."

**Enforce:** Move into `&mut` references at thread boundaries; use channels for handoff.

**Test:** Loom; document the SPSC pattern in the type's docs.

---

## Send/Sync invariants (UB bucket #8)

### I-S01 — `unsafe impl Send for T` synchronization story

**SAFETY:** "Field `raw_ptr` is only dereferenced via `&self` method `pub_method`, which acquires `self.lock` before deref."

**Enforce:** Encapsulation: `raw_ptr` is private; only `pub_method` accesses it.

**Test:** Loom + audit of public surface.

### I-S02 — `unsafe impl Sync for T` shared-read invariant

**SAFETY:** "`&T` access is read-only; concurrent reads of `raw_ptr` are safe because the pointee is never mutated through `&T`."

**Enforce:** `&self` methods don't take `&mut self`-shaped paths to the pointee.

**Test:** Loom + TSan.

---

## Pin invariants (UB bucket #9)

### I-PI01 — `!Unpin` value never moves after first `Pin::new_unchecked`

**SAFETY:** "After `Pin::new_unchecked(&mut x)` is called, the value pointed to will never be moved or otherwise invalidated until it is dropped (no `mem::replace`, no return-by-value of `x`, no aliasing access that could overwrite the bytes in place). This matches `Pin::new_unchecked`'s stdlib SAFETY contract verbatim."

**Enforce:** Wrap in `Pin<Box<T>>` or `pin!(x)` to make the pin compile-time enforced.

**Test:** Miri TB.

### I-PI02 — `Pin<&mut T>` projection to a `!Unpin` field uses `pin_project!`

**SAFETY:** "Projection follows the `pin_project!` rules; structural fields are pinned, non-structural are not."

**Enforce:** Use `pin_project_lite` or `pin_project` crate.

**Test:** Compile-time + Miri TB.

---

## FFI invariants (UB bucket #10)

### I-FF01 — `extern "C" fn(arg: *const T)` arg is null-or-valid-for-N

**SAFETY:** "Either `arg.is_null()` is true, or `arg` is aligned for T and the N bytes starting at arg are initialized."

**Enforce:** Wrap raw FFI calls in safe Rust functions that check.

**Test:** Cross-reference C header; ASan against a calling-from-C test harness.

### I-FF02 — `*const c_char` is NUL-terminated within MAX_PATH

**SAFETY:** "Callers guarantee the string has a NUL byte within MAX_PATH (256/4096) bytes."

**Enforce:** Convert at the boundary: `CStr::from_ptr(p).to_str()?.to_owned()`.

**Test:** Fuzz the FFI boundary with non-NUL-terminated inputs.

### I-FF03 — Calling convention matches the C ABI on this platform

**SAFETY:** "`extern "C"` matches the target's C ABI; for `extern "system"` see Windows."

**Enforce:** `bindgen`-generated declarations; never hand-edit.

**Test:** Run on every target platform listed in `Cargo.toml`'s `targets` metadata.

---

## Panic safety invariants (UB bucket #11)

### I-PA01 — `Drop` impls don't panic during unwinding

**SAFETY:** "This Drop never panics. If a fallible operation appears, it's wrapped in `let _ = ...;` or `if std::thread::panicking() { skip }`."

**Enforce:** Inspect every `Drop` for `unwrap`, `expect`, `?`.

**Test:** Property test: panic at every fallible point, assert process doesn't double-abort.

### I-PA02 — Container invariants restored if `extend` panics mid-write

**SAFETY:** "If iteration panics partway through, the container is left in a state where Drop is safe (e.g., `set_len` to the count of successfully-written items)."

**Enforce:** Use scope guards (`scopeguard::guard`) to restore len on panic.

**Test:** Property test inserting panic-on-Drop items.

### I-PA03 — `mem::forget` only on values whose Drop is observational

**SAFETY:** "Skipping Drop here is OK because Drop only logs; no resources leak."

**Enforce:** Use `ManuallyDrop<T>` if you genuinely want to skip Drop; `mem::forget` is fragile.

**Test:** LSan + ASan.

---

## Library trait invariants (bucket #12)

### I-LT01 — `Hash::hash` and `Eq::eq` use the same fields

**INVARIANT:** "Both `hash` and `eq` use exactly `{field_a, field_b}`; no other fields contribute." This is correctness-only unless unsafe code trusts it.

**Enforce:** Derive both, OR write both manually and document the field set.

**Test:** Proptest `a == b ⟹ hash(a) == hash(b)`.

### I-LT02 — `Ord::cmp` matches `PartialEq::eq`

**INVARIANT:** "`a.cmp(b) == Equal` if and only if `a == b`."

**Enforce:** Derive both, OR write both manually and document.

**Test:** Proptest `(a.cmp(b) == Equal) == (a == b)`.

### I-LT03 — `Iterator::size_hint` lower bound is honest

**INVARIANT:** "`size_hint().0 ≤ remaining_items_for_real`." This becomes safety-relevant only when unsafe code trusts the bound.

**Enforce:** Default impl returns `(0, None)`; only override if you're sure.

**Test:** Proptest: collect into Vec, assert `len ≥ size_hint().0`.

### I-LT04 — Custom `Allocator` matches deallocate with allocate layout

**SAFETY:** "Every `deallocate(ptr, layout)` is called with the same `layout` that was passed to `allocate` for `ptr`."

**Enforce:** Side-table tracking layouts; or use `bumpalo` / standard allocator.

**Test:** Kani / property test sequences of `alloc` + `dealloc`.

---

## Refcount lifecycle invariants (UB bucket #13)

### I-RC01 — `Arc::from_raw` paired with `Arc::into_raw` / `mem::forget`

**SAFETY:** "This pointer was produced by `Arc::into_raw` at call site X; no other call to `Arc::from_raw` on this pointer has occurred."

**Enforce:** Encapsulate the lifecycle in one type; audit vtable consistency (see exemplar E4 RawWaker pattern).

**Test:** ASan + LSan; Miri tree-borrows.

### I-RC02 — `Box::from_raw` only on pointers from `Box::into_raw`

**SAFETY:** "Pointer came from `Box::into_raw` and the Box used Rust's global allocator."

**Enforce:** Newtype wrappers for ptrs from foreign allocators (`Box::from_raw` shouldn't take them).

**Test:** ASan.

---

## `*const T` mutation invariants (UB bucket #14)

### I-CM01 — Never mutate through `*const T`

**SAFETY:** This is never sound. Use `UnsafeCell<T>` if interior mutability is needed.

**Enforce:** Clippy `invalid_reference_casting`.

**Test:** Static analysis is sufficient.

---

## Lifetime escape invariants (UB bucket #15)

### I-LE01 — Raw pointer lifetime tied to its borrow

**SAFETY:** "`ptr` is derived from `&buf` (line N); `ptr` is used only in lines N+1..M where `buf` is still in scope."

**Enforce:** Type-system: don't expose raw pointers in struct fields; use lifetime parameters.

**Test:** Miri TB + syn-walker `escape.rs`.

---

## Volatile invariants (UB bucket #16)

### I-VO01 — `read_volatile` / `write_volatile` aligned and valid

**SAFETY:** "Pointer is aligned for T; pointee is initialized (for read_volatile) or writable (for write_volatile); no aliasing non-volatile access."

**Enforce:** Typed wrapper crate (`volatile-register`).

**Test:** Native + hardware test; Miri doesn't model MMIO semantics.

---

## Async drop invariants (UB bucket #17)

### I-AD01 — `Drop` is non-blocking when type may live in async context

**SAFETY:** "`Drop` runs synchronously; no blocking I/O, no `block_on`, no `wait()`."

**Enforce:** Move blocking work to an explicit `close()` method.

**Test:** Run the test under tokio with `tokio::time::timeout`; if it timeouts, Drop blocked.

---

## Inline asm invariants (UB bucket #18)

### I-IA01 — `asm!` clobber list is complete

**SAFETY:** "All registers, flags, and memory locations modified by the asm are in the clobber list. `options(nomem)` only if the asm provably doesn't touch memory; `options(pure)` only if the output depends only on the inputs."

**Enforce:** Read the architecture manual; cross-reference inline asm against equivalent gcc/clang output (Compiler Explorer).

**Test:** Build under multiple optimization levels; run native + sanitizers.

---

## Target-feature invariants (UB bucket #19)

### I-TF01 — `#[target_feature]` callee invoked only after runtime detection

**SAFETY:** "`is_x86_feature_detected!("avx2")` returned `true` on this call path before invoking the AVX2 fn."

**Enforce:** Use the `multiversion` crate or hand-rolled dispatch with explicit detection.

**Test:** Run on a non-AVX2 CPU (qemu-x86_64 with `-cpu pentium`) to catch unchecked paths.

---

## Allocator pairing invariants (UB bucket #20)

### I-AP01 — `Box::from_raw` allocator matches `Box::into_raw` allocator

**SAFETY:** "Pointer came from `Box::into_raw(b)` where `b: Box<T, A>` with our global allocator A."

**Enforce:** Don't accept ptrs from foreign allocators; convert at the boundary.

**Test:** ASan.

---

## FFI callback aliasing invariants (UB bucket #21)

### I-FC01 — C library doesn't mutate `*x` while Rust holds `&mut x`

**SAFETY:** "Per the C library's documented contract, no concurrent mutation occurs while the Rust callback holds the borrow."

**Enforce:** Cross-reference the C library's docs; for unclear contracts, treat as `LIKELY-UB` and use `UnsafeCell` + atomic at the boundary.

**Test:** ASan + TSan against the real C library.

---

## `repr(packed)` invariants (UB bucket #22)

### I-RP01 — Never take a reference to a packed field

**SAFETY:** Already covered by `unaligned_references` hard-error in modern rustc. Use `addr_of!` + `read_unaligned`.

**Enforce:** Clippy + rustc.

**Test:** Build clean.

---

## Observed type changes (UB bucket #23)

### I-OT01 — `*const T → *mut T` only when underlying allocation is mutable

**SAFETY:** "Pointer was originally derived from a `&mut`-style root (Box, Vec, &mut local), not from a `&'static`."

**Enforce:** Clippy `invalid_reference_casting`.

**Test:** Static analysis.

---

## Coherence violations (UB bucket #24)

### I-CO01 — Don't rely on `#![feature(specialization)]` for soundness

**SAFETY:** "Specialization is currently unsound for lifetime-dependent dispatch; only `min_specialization` is considered for stabilization. Any safety guarantee must hold for the most-generic impl, not just the specialized one."

**Enforce:** Avoid `#![feature(specialization)]`; if used, gate behind nightly with explicit "soundness-unverified" docs. Prefer `min_specialization` only when the dispatch is purely on `Sized`/`'static` (lifetime-free) traits.

**Test:** Audit-only; no runtime tool catches coherence breakage. Manual review at every `default impl` and `impl<T: …> Trait for T` site.

---

## Hash + Eq + Borrow invariants (UB bucket #25)

### I-HE01 — `Borrow<U> for T` implies same hash for `T` and `U`

**SAFETY:** "`<T as Hash>::hash(&t, h)` produces the same bytes as `<U as Hash>::hash(t.borrow(), h)`."

**Enforce:** Either don't impl Borrow, OR derive Hash from a function that respects borrow.

**Test:** Proptest the borrow invariant for every Borrow impl.

---

## Quick reference card

| Bucket | Most-violated invariant in /dp/* corpus | Test |
|---|---|---|
| 1 Aliasing | I-A01 (deref while &T live) | Miri TB |
| 3 Alignment | I-AL03 (mmap pointer alignment) | Miri symbolic-alignment |
| 7 Data races | I-R01 (atomic ordering) | TSan + loom |
| 8 Send/Sync | I-S01 (synchronization story) | Loom + audit |
| 10 FFI | I-FF02 (NUL terminator) | Fuzz boundary |
| 11 Panic safety | I-PA01 (panicking Drop) | Property test |
| 12 Std-trait | I-LT01 (Hash/Eq) | Proptest |
| 13 Refcount | I-RC01 (from_raw pairing) | ASan + LSan |
| 15 Lifetime | I-LE01 (raw ptr scope) | Miri + syn-walker |
| 17 Async drop | I-AD01 (blocking in Drop) | tokio::time::timeout |

---

## How to use this catalog

1. **When writing an unsafe block:** scan the catalog for invariants your operation depends on. Cite each invariant ID in the SAFETY comment.
2. **When reviewing an unsafe block:** check the SAFETY comment lists every applicable invariant. If any are missing, that's a Phase 2 finding.
3. **When designing a remediation:** prefer rewrites that move the invariant into the type system (`Mutex<T>` instead of `unsafe impl Sync`).

Sample SAFETY comment using catalog IDs:

```rust
// SAFETY:
//   I-A01 — `r` (line 42) is dropped at line 47 before `m` is derefed at line 48.
//   I-AL01 — `m` is aligned because `ptr` came from `Box::into_raw(b)` with align ≥ 8.
//   I-V05 — `*m` is initialized: we wrote `42u64` at line 45.
unsafe { *m = 99; }
```

Reviewers can now spot-check each invariant ID quickly.
