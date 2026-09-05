# UB Taxonomy — Rustonomicon + Soundness-Adjacent Catalog

Every site identified in Phase 1 is tagged with one or more of these buckets. Each bucket has a detection arsenal, common shapes, and reference exemplars from `/dp/*` projects.

The taxonomy follows the [Rustonomicon's "What Unsafe Rust Can Do"](https://doc.rust-lang.org/nomicon/what-unsafe-does.html) for actual UB, plus practice-derived invariant buckets that can feed UB when unsafe code trusts them. Buckets #12 and #25 deliberately include safe-code correctness invariants; they are not automatically UB.

**Beyond the 25 buckets:** the per-bucket detector list below catches UB *inside* the audited crate's `src/`. Several high-value surfaces sit *outside* that scope — compile-time code (`build.rs`, proc-macros), cross-target hazards, cross-Miri-axis verdict divergence, comparative testing vs the last published version, runtime corners (TLS-Drop, panic-across-FFI, custom allocator). Those live in [UB-ADVANCED-DETECTORS.md](UB-ADVANCED-DETECTORS.md) — read it after this file. Each advanced detector still maps back to one or more of the 25 buckets below; the advanced doc tells you *where* the detector slots into the phase model.

---

## 1. Aliasing — `&T` / `&mut T` Violations

**The contract:** `&T` may co-exist with any number of `&T` to the same place but never with `&mut T`. `&mut T` is unique. Violations are UB even if the alias is never dereferenced.

**Common shapes:**
- A `*mut T` deref while a live `&T` to the same place exists
- `slice::from_raw_parts_mut` overlapping with `slice::from_raw_parts`
- A `Cell`-like type implemented manually that lets `&self` mutate without `UnsafeCell`
- Two `Pin<&mut T>` to the same `T`

**Arsenal:**
- `MIRIFLAGS="-Zmiri-tree-borrows"` — strictest aliasing model (TB is more sensitive than SB)
- `MIRIFLAGS=""` — default stacked-borrows; weaker but faster
- ast-grep: see `scripts/patterns/aliasing-*.yml`
- syn walker: `scripts/syn-walkers/src/bin/aliasing.rs` — flags `*mut T` deref within scope of a live `&T` (run via `cargo run --manifest-path scripts/syn-walkers/Cargo.toml --bin aliasing -- <src>`)

**Detection prompt:**
> Find every place where a `*mut T` is dereferenced. For each, trace the lifetime of any `&T` to the same place that is live during the deref. If any such `&T` exists, the deref is UB unless the `&T` is provably dropped before deref.

**Exemplar (asupersync, RawWaker vtable):** every `unsafe fn` reconstructs an `Arc` from the data pointer and pairs `from_raw` with `into_raw`/`forget` to keep aliasing one-of-a-time.

---

## 2. Provenance — Pointer Identity & Arithmetic

**The contract (strict provenance):** a pointer carries provenance (which allocation it came from). Pointer arithmetic must stay within the original allocation's bounds. `int as *const T` loses provenance.

**Common shapes:**
- `(ptr as usize + offset) as *const T` — loses provenance, fails strict-provenance checks
- Pointer arithmetic across allocation boundaries (`p.add(n)` where `n` exceeds the alloc length)
- Casting `*const T` ↔ `*const U` for incompatible types (provenance survives but type assumption rots)

**Arsenal:**
- `MIRIFLAGS="-Zmiri-strict-provenance"`
- `cargo +nightly clippy -- -W clippy::cast_ptr_alignment -W clippy::ptr_as_ptr`
- ast-grep: `scripts/patterns/provenance-int-cast.yml`

**Detection prompt:**
> Search for every `as usize` followed within 20 lines by `as *const` or `as *mut`. For each, determine whether the original provenance is preserved (it is not — these always lose provenance under strict-provenance rules).

---

## 3. Alignment

**The contract:** dereferencing a `*const T` / `*mut T` requires `ptr % align_of::<T>() == 0`. Reading a field through `&packed_struct.field` for a `#[repr(packed)]` field is UB if the field is not naturally aligned.

**Common shapes:**
- `*const T` cast from `*const u8` without alignment check
- Taking a reference to a `#[repr(packed)]` field (always UB in stable Rust if alignment isn't natural)
- mmap-backed atomics without verifying `mmap`'s base address alignment

**Arsenal:**
- `MIRIFLAGS="-Zmiri-symbolic-alignment-check"`
- Clippy `unaligned_references` (default-warn)
- ast-grep: `scripts/patterns/alignment-repr-packed-field-ref.yml`

**Exemplar (frankensqlite):** `atomic_u64_at(ptr, offset)` performs the offset+cast inside `unsafe`; the *caller* validates `offset % 8 == 0` upfront, and the SAFETY comment cites that contract.

---

## 4. Validity Invariants — Bit-Patterns That Are Always Invalid

**The contract:** certain types have validity invariants that hold for *every* value of the type, always:
- `bool` is `0` or `1`
- `char` is a valid Unicode scalar value (not in the surrogate range)
- `enum` is one of its declared discriminants
- `&T` / `&mut T` / `Box<T>` are non-null and aligned
- `NonNull<T>` is non-null
- `NonZero*` is non-zero
- A `fn` pointer is non-null

Violating these is *always* UB, even for an instant.

**Common shapes:**
- `mem::zeroed::<bool>()` is technically OK (0 is valid for bool) but `mem::zeroed::<NonZeroU8>()` is UB
- `transmute::<u8, bool>(2)` is UB
- `transmute::<u32, char>(0xD800)` is UB (surrogate)
- `let _: &T = ptr::null::<T>().as_ref().unwrap_unchecked();` is UB
- Reading a uninit byte into a `bool` field

**Arsenal:**
- Plain `cargo +nightly miri test` catches invalid enum/scalar values on
  current nightlies. Do not add `-Zmiri-check-number-validity`; the flag is
  obsolete and rejected before tests run.
- Clippy `uninit_assumed_init`, `transmute_int_to_bool`, `transmute_int_to_char`
- syn walker `validity.rs` — flags `mem::zeroed::<T>()` calls where T contains a non-zero-valid type

---

## 5. Uninitialized Memory

**The contract:** reading uninit memory as anything other than `MaybeUninit<T>` is UB. `MaybeUninit::assume_init` is a *promise* that the bytes are valid for `T`.

**Common shapes:**
- `MaybeUninit::<T>::uninit().assume_init()` for any non-`()` `T`
- Reading a `Vec`'s `set_len`-extended region before writing
- Reading padding bytes of a struct via `unsafe { *(ptr as *const u8) }`
- `Vec::with_capacity(n)` followed by indexing `[0..n]` before writes

**Arsenal:**
- Plain `cargo +nightly miri test` (catches many invalid value reads)
- Clippy `uninit_assumed_init`
- AddressSanitizer (MSan catches uninit reads but needs Linux)
- ast-grep `scripts/patterns/MaybeUninit-write-after-assume-init.yml`

---

## 6. Type Punning via `transmute` / `union`

**The contract:** `transmute<A, B>` requires `A` and `B` to be layout-compatible. Reading through a different field of a `union` after writing one is layout-dependent and frequently UB.

**Common shapes:**
- `transmute::<&T, &mut T>(...)` — always UB (forges aliasing)
- `transmute::<*const T, &T>(...)` — UB if T doesn't satisfy validity (null/dangling)
- `transmute::<f32, u32>` — *not* UB, but prefer `f32::to_bits()`
- `transmute` between two `#[repr(Rust)]` types — UB unless layout is provably identical

**Arsenal:**
- Clippy `transmute_*` family (many lints)
- syn walker `transmute_pairs.rs` — extracts the source/target types and applies a layout-compatibility judgment
- `bytemuck` / `zerocopy` candidacy scan — most `transmute` calls have safer alternatives

---

## 7. Data Races

**The contract:** concurrent unsynchronized access from two threads where at least one is a write is UB. Atomic operations and locks synchronize; raw reads/writes don't.

**Common shapes:**
- `&mut T` shared across threads via raw pointer
- `Cell<T>` shared across threads (Cell is `!Sync`)
- `AtomicOrdering::Relaxed` where `Acquire`/`Release` is needed
- Manual `Send`+`Sync` on a struct containing `Cell` or `RefCell`

**Arsenal:**
- `RUSTFLAGS="-Zsanitizer=thread"` — ThreadSanitizer (Linux x86_64)
- `loom` — exhaustive interleaving search for small models
- `shuttle` — probabilistic search for larger models
- syn walker `data_races.rs`

**Exemplar (asupersync, commit `0fb6c3e30`):** added a fuzzer that triggers concurrent read/write/seek on an `Arc<File>` shared without synchronization; TSan was the oracle that confirmed the race.

---

## 8. `Send`/`Sync` Invariants

**The contract:** `unsafe impl Send for T` says "T is safe to move between threads"; `unsafe impl Sync for T` says "`&T` is safe to share". Violating these is UB.

**Common shapes:**
- Struct containing `Rc<...>` with manual `Send` — Rc isn't thread-safe
- Struct holding a raw pointer + manual `Send` without explaining the synchronization
- A type that is Send but contains a non-Send field hidden behind an alias

**Arsenal:**
- Inspect every `unsafe impl (Send|Sync) for T`; cross-check fields of T
- Mandatory SAFETY comment naming the external synchronization mechanism
- Loom models that exercise the supposed thread-safety

**Exemplar (frankensqlite mmap, `fsqlite-vfs/src/shm.rs:59`):** dual `unsafe impl` with a 4-line SAFETY comment naming `MAP_SHARED` + fcntl locks + memory barriers + the only public interface (`ShmRegionGuard`) that ever derefs.

---

## 9. `Pin` Invariants

**The contract:** once a value is `Pin<&mut T>` and `T: !Unpin`, the value's address must not change for the rest of its lifetime. Moving it out is UB.

**Common shapes:**
- Self-referential structs created via `Pin::new_unchecked` without enforcing the address-stability
- Async state machines hand-rolled with raw pointers into self
- `Pin::new_unchecked(&mut x)` followed elsewhere by `mem::replace(&mut x, …)` — the replace moves the value, breaking pin
- `Pin::new_unchecked(&mut *boxed)` where the `Box` is later moved out
- Calling `Pin::get_unchecked_mut` on a `!Unpin` and then moving the result
- A `Future` impl that stores `Pin<&mut Self>` from `poll` into a field — `&mut Self` is then re-projected via `unsafe`, easy to violate

**Arsenal:**
- ast-grep `scripts/patterns/pin-new-unchecked.yml`
- syn walker `pin.rs` — flags `Pin::new_unchecked` calls and traces whether the pinned value can be moved
- Manual lifetime audit for any `!Unpin` self-referential struct

---

## 10. FFI Contracts — `extern "C"`, `repr(C|transparent|packed)`

**The contract:** when calling a foreign function, its documented preconditions are part of the unsafe contract. ABI breakage (wrong type for a parameter, wrong calling convention, mismatched layout) is UB.

**Common shapes:**
- `extern "C" fn foo(p: *const i8)` invoked with a `*const u8` that isn't NUL-terminated
- A C struct declared `#[repr(C)]` but with field reorder vs. the actual C header
- `#[repr(transparent)]` wrapper over a non-`Copy` type passed by value through C
- A `bindgen`-generated module that's been edited by hand

**Arsenal:**
- `rustc -W improper_ctypes`
- Cross-reference every `extern "C"` decl against the actual C header (when available)
- `static_assertions::*` for size + alignment + offsetof
- `cargo +nightly miri` for non-FFI-only logic flowing into FFI

---

## 11. Panic Safety, `mem::forget`, `ManuallyDrop`

**The contract:** when a function panics, every drop on the unwind path must leave invariants intact. `mem::forget(x)` skips x's Drop — fine if Drop is observational, UB if Drop releases a resource the rest of the program depends on.

**Common shapes:**
- A custom collection where `push()` writes to memory and increments len, but panics between → next access reads uninit
- `mem::forget` on a `MutexGuard` (the lock stays held forever — not UB but causes deadlock)
- `ManuallyDrop` whose drop is never called because the path was forgotten

**Arsenal:**
- Audit `Drop` impls for: blocking I/O (don't), allocation (be careful), unwinding-safety
- Property-test for panic-safety: panic at every `unsafe` op and assert no torn state remains observable
- `loom` for panic-during-lock-held scenarios

---

## 12. Std-Library Trait Invariants

**The contract:** some library traits carry memory-safety contracts, and many safe traits carry correctness invariants:
- `Eq` + `Hash` must be consistent (`a == b` ⇒ `hash(a) == hash(b)`)
- `Eq` + `Ord` must be consistent
- `Iterator::size_hint` must return a lower-bound `(low, _)` that `low <= actual remaining`
- `GlobalAlloc`/allocator APIs must deallocate only with a layout matching the original allocation
- `Hasher::write` must not panic mid-write (or `Hasher` impl breaks)

Violating safe trait invariants (`Hash`/`Eq`, `Ord`, ordinary `Iterator::size_hint`) is a logic error, not UB by itself; safe standard-library code must not rely on these invariants for memory safety. It becomes UB only when unsafe code or an unsafe trait contract actually trusts the invariant, such as a project-local unsafe bulk collector or allocator boundary.

**Arsenal:**
- Clippy `derive_ord_xor_partial_ord`, `derive_hash_xor_eq`
- Property tests for `Hash`+`Eq` consistency
- Audit any manual `Iterator` impl for `size_hint` honesty

---

## 13. Reference-Count Lifecycle — `Arc::from_raw` / `Box::from_raw` / `Rc::from_raw`

**The contract:** `T::from_raw(p)` reclaims ownership. Calling it twice on the same `p` is double-free UB. Calling it after `into_raw` has been balanced (e.g., via `drop`) is use-after-free.

**Common shapes:**
- RawWaker vtable functions calling `Arc::from_raw` without pairing with `forget`/`into_raw`
- An FFI handle reconstructed via `Box::from_raw` from a C callback after Rust already dropped it
- `Arc::strong_count` checks not synchronized with `from_raw`

**Arsenal:**
- Pattern: every `from_raw` is paired with `into_raw` or `mem::forget` (asupersync's RawWaker is a textbook example)
- ASan for double-free
- TSan if the lifecycle is multi-threaded

---

## 14. Mutation Through `*const T`

**The contract:** `*const T` says "read-only". Mutating through `*(p as *mut T)` when `p` came from `&T` is UB.

**Common shapes:**
- `&self` methods that cast to `*mut` and write
- `Cell` reimplemented manually without `UnsafeCell`

**Arsenal:**
- Clippy `cast_ref_to_mut` (now `invalid_reference_casting`)
- ast-grep `scripts/patterns/const-mutation-cast.yml`

---

## 15. Lifetimes & Escape — Raw Pointer Outliving Its Construction Scope

**The contract:** a raw pointer derived from `&T` is valid only while `T` is live. Using it after T is dropped is UB.

**Common shapes:**
- `let p = &v as *const _; drop(v); unsafe { *p }`
- Storing a `*mut T` in a struct whose lifetime is longer than the borrowed origin
- A closure that captures `&T` and returns a `*const T` derived from it

**Arsenal:**
- syn walker `escape.rs` — flags `*const T` / `*mut T` that escape the scope of the borrow they were derived from
- Miri (catches at run time)
- Manual lifetime algebra for tricky cases

---

---

## 16. Volatile Read/Write Contracts

**The contract:** `ptr::read_volatile` / `ptr::write_volatile` require the same alignment + validity as a regular dereference. Volatile does NOT mean safe — it only suppresses compiler reordering. UB from misaligned volatile is still UB.

**Common shapes:**
- MMIO register access via `read_volatile` on a misaligned pointer
- Mixing volatile with non-volatile reads of the same address (compilers may reorder the non-volatile ones)
- Assuming `volatile` implies atomicity (it does not — for atomic semantics use `core::sync::atomic`)

**Arsenal:** ast-grep for `read_volatile` / `write_volatile`; manual audit of the producing pointer's alignment + validity; cross-check that no non-volatile access aliases.

---

## 17. Async Drop Hazards

**The contract:** Rust does not yet have async `Drop`. A `Drop` impl runs *synchronously* even in async context, which means blocking I/O in `Drop` blocks the runtime.

**Common shapes:**
- `Drop` calls `tokio::runtime::Handle::block_on(...)` — deadlocks on the same runtime
- `Drop` calls `std::fs::File::sync_all()` — blocks the runtime worker
- `Drop` panics — drops the whole task; if any other Drop also runs, may double-drop (`mem::forget` partway through)
- An owned `JoinHandle` whose `Drop` *doesn't* await — detaches the task silently

**Arsenal:** clippy `await_holding_lock` (related); manual audit of every `Drop` impl on a type used in async; tokio's `RuntimeMetrics` for finding worker blocks.

---

## 18. Inline Assembly UB

**The contract:** `core::arch::asm!` / `core::arch::global_asm!` are 100% unsafe. The Rust compiler trusts everything you tell it about clobbers, register constraints, and memory operands.

**Common shapes:**
- `out("rax")` clobber list omits a register the asm actually clobbers
- `in("r8")` reads a register before initializing it
- `nomem` option claimed when the asm actually touches memory
- `nostack` option claimed when the asm pushes/pops
- Cross-block jumps that miss `noreturn` annotation

**Arsenal:** read every `asm!` block by hand; cross-reference against the architecture manual; under Miri, every `asm!` is unsupported — guard with `#[cfg(not(miri))]`.

---

## 19. Target-Feature Mismatch

**The contract:** Calling a SIMD intrinsic that requires a feature the target CPU doesn't support is UB. `#[target_feature(enable = "avx2")]` makes calling the function from a non-AVX2 caller UB unless dispatched correctly.

**Common shapes:**
- AVX2 intrinsic used unconditionally without `is_x86_feature_detected!("avx2")` guard
- `#[target_feature]` fn called from an inner closure that captures non-target-feature context
- `multiversion`-derived dispatch with broken fallback path

**Arsenal:** clippy `target_feature_caller_not_target_feature_callee`; manual audit of every `core::arch::*` call; runtime dispatch via `std::is_x86_feature_detected` / `std::arch::is_aarch64_feature_detected`.

---

## 20. Dangling `Box` / Manual Memory Pairing

**The contract:** `Box::from_raw(p)` requires `p` to come from `Box::into_raw` (or equivalent `Box` allocator). Passing in a pointer from any other allocator is UB (likely heap corruption).

**Common shapes:**
- `Box::from_raw(libc::malloc(n) as *mut T)` — wrong allocator
- `Box::from_raw(p)` where `p` came from C `malloc` via FFI
- `Box::from_raw(Box::leak(b) as *const _ as *mut _)` — works but easy to lose track

**Arsenal:** every `Box::from_raw` site cross-referenced against where the raw pointer was *constructed*; flag any path where it came from `libc::malloc` / `aligned_alloc` / `mmap`.

---

## 21. `mut` From FFI Callbacks

**The contract:** If a C library calls a Rust callback with a `*mut T` and Rust reads `*x`, the C side must not concurrently mutate `*x`. Conversely if Rust calls into C with a `*mut T`, the C side must respect Rust's aliasing assumptions.

**Common shapes:**
- C callback fires while Rust is mid-`&mut` borrow on the same memory
- Rust passes `&mut T` as a `*mut` to a C function that retains it and calls back later
- Both Rust and C hold "the only writer" mental model — neither realizes the other writes

**Arsenal:** cross-reference every `extern "C" fn callback` with the C source (when available); document the aliasing contract explicitly in `# Safety` doc; if the C library's docs are unclear, treat as `LIKELY-UB`.

---

## 22. `repr(packed)` Field Address

**The contract:** Taking `&packed.field` for a non-naturally-aligned field is UB in stable Rust (per RFC 1240, the historical lint became hard error in newer toolchains). Use `addr_of!(packed.field)` and copy-by-value.

**Common shapes:**
- `for x in &packed.array_field` — iterates by reference, UB
- `eprintln!("{}", packed.unaligned_field)` — Display trait takes `&self`, UB
- `match packed.field { … }` — match by value is fine, by ref UB
- `packed.field.method()` — methods take `&self`

**Arsenal:** clippy `unaligned_references` (now hard-error); `addr_of!` instead of `&` for packed fields.

---

## 23. Observed Type Changes (Mutability/Const)

**The contract:** Casting `*const T` to `*mut T` and writing is UB *if* the underlying allocation was actually const (statics, literals). For values originally constructed `mut` it's "merely" the const-mutation bucket; for things in `.rodata` it's segfault-grade UB.

**Common shapes:**
- `(string_literal as *const str as *mut str)` write — writes to read-only memory
- `&static FOO: u32 = 1; let p = &FOO as *const _ as *mut _; *p = 2;` — same
- Any `static` mut-cast that the compiler placed in `.rodata`

**Arsenal:** clippy `invalid_reference_casting`; ast-grep for `(... as *const ... as *mut ...)`; manual audit of every cast that strips const, especially when the source is a `&'static`.

---

## 24. Coherence-Violating Trait Impls

**The contract:** Two crates can't both impl `Trait for Foo` (orphan rule). If they manage to (via specialization, unstable features, or build script tricks), library code that depends on coherence breaks in ways the compiler can't catch.

**Common shapes:** rare in practice but possible with `#![feature(specialization)]` (nightly only).

**Arsenal:** if the project uses `feature(specialization)`, audit every impl carefully; otherwise this bucket is N/A.

---

## 25. Hash + Eq + Borrow Consistency

**The contract:** `Hash::hash(a) == Hash::hash(b)` whenever `a == b`. `Borrow<U>` requires `<T as Hash>::hash` and `<U as Hash>::hash` produce the same bytes for `T` and its borrowed form. Violating this can make `HashMap` lookups miss logically equal keys or behave inconsistently, but it is not UB by itself; report it as UB only if unsafe code in the project depends on the map-level invariant for memory safety.

**Common shapes:**
- Manual `Hash` impl hashes a subset of fields the `Eq` impl compares (or vice versa)
- Custom `PartialEq` that uses different equivalence than `Eq` (e.g., case-insensitive `Eq` but case-sensitive `Hash`)
- Newtype wrapper that derives `PartialEq` from the inner but `Hash` from a different field

**Arsenal:** clippy `derive_hash_xor_eq`, `eq_op`; proptest harness that asserts `a == b ⟹ hash(a) == hash(b)` for the types used as `HashMap` keys.

---

## Bucket-to-Phase-2-Subagent Map

Each bucket gets one `static-bucket-sweeper` subagent in Phase 2. Buckets that are project-irrelevant (e.g., no FFI surface ⇒ skip bucket 10) get a one-line `phase2_findings_<bucket>.md` saying "N/A; no FFI surface in this project".

Buckets 16–25 are *conditional* — they only spawn a subagent when the project's Phase-1 inventory indicates the relevant surface (e.g., bucket 16 only if `read_volatile`/`write_volatile` appears; bucket 18 only if `asm!` appears; bucket 19 only if `target_feature` appears; bucket 23 only if there are casts that strip const from statics).

## Bucket Severity Calibration

Some buckets are "always UB if violated" (validity, alignment of `*const T` deref, data races, type-punning incompatible layouts, observed type changes, dangling `Box`). Others are "depends on contract" (FFI, `unsafe impl Send`/`Sync`, panic safety, async drop, FFI-callback aliasing, unsafe library-trait contracts). Safe trait invariant drift (`Hash`/`Eq`, `Ord`, ordinary `Iterator::size_hint`) is correctness-only unless a concrete unsafe boundary trusts it. Phase 2 sweepers must use the severity scale from PHASES.md (`MUST-BE-UB` / `LIKELY-UB` / `SUSPICIOUS` / `CONTRACTUAL-BUT-DEFENSIBLE`) with this calibration in mind.

## Quick reference card

| # | Bucket | Always-UB on violation? | Phase-3 primary tool |
|---|---|---|---|
| 1 | Aliasing | ✓ | Miri TB |
| 2 | Provenance | ✓ | Miri strict-provenance |
| 3 | Alignment | ✓ | Miri symbolic-alignment-check |
| 4 | Validity invariants | ✓ | Miri (validity check) |
| 5 | Uninitialized memory | ✓ | Miri / MSan |
| 6 | Type punning | depends on layout | Miri |
| 7 | Data races | ✓ | TSan / loom / Miri |
| 8 | Send/Sync invariants | depends on contract | TSan + loom proof |
| 9 | Pin invariants | ✓ | Miri TB + syn-walker |
| 10 | FFI contracts | depends on caller | ASan + Miri (with shim) |
| 11 | Panic safety | depends | property test + Miri |
| 12 | Std-library trait invariants | safe traits: no; unsafe contracts: depends | proptest |
| 13 | Refcount lifecycle | ✓ | ASan + Miri |
| 14 | `*const T` mutation | ✓ | clippy + Miri |
| 15 | Lifetimes & escape | ✓ | Miri + syn-walker |
| 16 | Volatile contracts | ✓ | manual audit |
| 17 | Async drop | depends on context | tokio metrics + audit |
| 18 | Inline asm | depends on clobber list | manual + arch manual |
| 19 | Target-feature mismatch | ✓ | clippy + audit |
| 20 | Dangling Box / allocator pairing | ✓ | ASan + audit |
| 21 | FFI callback aliasing | depends | TSan + audit |
| 22 | repr(packed) field addr | ✓ | clippy unaligned_references |
| 23 | Observed type changes | ✓ | clippy invalid_reference_casting |
| 24 | Coherence violations | rare in stable | only if feature(specialization) |
| 25 | Hash/Eq/Borrow consistency | no by itself | clippy + proptest |
