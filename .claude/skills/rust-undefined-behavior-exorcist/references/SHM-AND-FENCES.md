# SHM And Fences — Unsafe mmap Introduction Checklist

When introducing unsafe `libc::mmap` / `MAP_SHARED` / cross-process shared memory in Rust, the soundness story is non-obvious. This is a checklist mined from cass Q-102 (frankensqlite SHM layer).

Anchor: cass Q-102 — *"Replaced noop `shm_barrier()` with `std::sync::atomic::fence(SeqCst)`"* + 8 new tests across mmap, cross-handle, multi-region, cleanup, cross-process visibility.

---

## The checklist

Every new mmap/SHM introduction must answer YES to ALL of these:

- [ ] Is the mmap region wrapped in a typed Drop that calls `libc::munmap` exactly once?
- [ ] Is the typed wrapper's `unsafe` constructor documented with SAFETY contract covering: (a) the pointer's lifetime, (b) the size, (c) the MAP_SHARED vs MAP_PRIVATE invariant?
- [ ] Is `Send`/`Sync` justified via the [Q-201 multi-part pattern](../corpus/quote_bank/quote_bank.md) — naming the sync mechanism (fcntl, mutex, atomic) AND the only public deref path?
- [ ] Is there a `fence(SeqCst)` (or stronger) **before** any cross-handle/cross-process visibility is claimed?
- [ ] Are all atomic operations on mmap memory using `AtomicU64::from_ptr` (or equivalent), NOT raw `*mut u64` cast to `&AtomicU64`?
- [ ] Is the alignment of the offset within the page validated at every accessor?
- [ ] Is the offset arithmetic checked for overflow (`checked_add`, `checked_mul`)?
- [ ] Is the lock-byte page (SQLite's reserved lock-byte page) explicitly rejected if dereferenced?
- [ ] Does the test suite include all 4 axes: **mmap**, **cross-handle sharing**, **multi-region**, **cleanup**, **cross-process visibility**?

If any answer is NO, the introduction is `LIKELY-UB` until proven otherwise.

---

## Why these specifically?

### Typed Drop wrapping `munmap`

Without typed Drop, mmap leak. With typed Drop, lifetime correctness is in the type system. Pattern:

```rust
pub struct MmapBacking {
    ptr: *mut c_void,
    len: usize,
}

impl Drop for MmapBacking {
    fn drop(&mut self) {
        // SAFETY: ptr + len were returned by a successful libc::mmap call;
        //   no other code holds an outstanding reference to this region by
        //   construction (only ShmRegionGuard dereferences ptr, and it
        //   borrows from self).
        unsafe {
            libc::munmap(self.ptr, self.len);
        }
    }
}

// SAFETY: see Q-201 — MAP_SHARED + fcntl + memory barriers + ShmRegionGuard.
unsafe impl Send for MmapBacking {}
unsafe impl Sync for MmapBacking {}
```

### `fence(SeqCst)` before cross-handle visibility

POSIX says memory barriers are required between mmap-writes-from-process-A and mmap-reads-by-process-B to make the writes visible. C SQLite uses `__sync_synchronize()`; Rust equivalent is `std::sync::atomic::fence(SeqCst)`.

```rust
pub fn shm_barrier(&self) {
    // SAFETY contract: callers rely on every preceding write through this
    // SHM region being visible to other processes after this fence.
    std::sync::atomic::fence(std::sync::atomic::Ordering::SeqCst);
}
```

A noop `shm_barrier` is a soundness bug, not a perf nit. (Cass Q-102 explicitly framed it this way.)

### `AtomicU64::from_ptr` over raw cast

Stable in Rust 1.84 (still `unsafe` — `AtomicU64::from_ptr(ptr: *mut u64) -> &'a AtomicU64`, where the caller's binding site infers `'a`):
```rust
// SAFETY: ptr is page-aligned by construction (mmap returns page-aligned), so
//   the 8-byte alignment requirement of AtomicU64 is satisfied; ptr+8 is in
//   the same mmap region; the `'a` lifetime inferred at the binding site
//   below does not outlive `self`, which owns the mmap; no other reference
//   to *ptr is live for that `'a`.
let atom: &AtomicU64 = unsafe { AtomicU64::from_ptr(ptr.cast::<u64>()) };
//        ^ `'a` is inferred to be ≤ the borrow of `self`; never `'static`
//          unless the mmap region itself is 'static.
```

Replaces the historic pattern:
```rust
let atom: &AtomicU64 = unsafe { &*(ptr as *const AtomicU64) };
//  ^ caller must hand-prove alignment + dereferenceability
```

`from_ptr` doesn't remove the `unsafe`, but it documents the contract canonically in `std`'s stability docs (alignment, exclusive provenance, lifetime) — the SAFETY comment can reference the std contract by name instead of re-deriving it.

### Lock-byte page rejection

SQLite reserves a specific page (the "lock-byte page", PSize bytes at SQLITE_LOCK_BYTE_OFFSET) for byte-range locking. Dereferencing that page as if it were data is corrupting state. frankensqlite's `record_integrity_page_owner` now rejects references to the reserved lock-byte page.

```rust
fn validate_page_offset(page: u32, page_size: u32) -> Result<()> {
    let lock_byte_page = (LOCK_BYTE_OFFSET / page_size as u64) as u32 + 1;
    if page == lock_byte_page {
        return Err(Corrupt::LockBytePageRef);
    }
    Ok(())
}
```

### The 4-axis test matrix

Per Q-102, the SHM rewrite shipped with 8 tests in this matrix:

| Axis | Test |
|---|---|
| **mmap correctness** | Single-process write/read roundtrip |
| **cross-handle sharing** | Multiple `MmapBacking` over the same fd see each other's writes |
| **multi-region** | Two non-overlapping SHM regions don't interfere |
| **cleanup** | Drop ordering: munmap before close(fd); no double-munmap |
| **cross-process visibility** | Process A writes → fence → Process B reads (different process IDs) |

A new SHM introduction without all 4 axes covered is shipping a soundness-untested change.

---

## Tooling

- `ast-grep -p 'libc::mmap($$$)'` — find every existing mmap call
- `rg 'unsafe impl (Send|Sync) for.*Mmap'` — find every mmap-related manual impl
- `rg 'libc::munmap' --type rust` — find every munmap; pair each with its typed Drop

---

## Anti-patterns

| ✗ | Why |
|---|---|
| Returning `*mut c_void` from a function | Lets the raw pointer escape the type system; aliasing is unbounded |
| `unsafe impl Send` without naming the sync mechanism | SAFETY comment fails the multi-part rule |
| Skipping `fence(SeqCst)` between cross-process writer and reader | Other process may not see the writes |
| Casting `*mut u8` to `&AtomicU64` without alignment check | Alignment proof is on the caller; easy to forget |
| Trusting libc::munmap returns success | Check the return code; failure means leak or wrong-pointer free |
| Skipping the multi-process test axis | The very thing MAP_SHARED is for |

---

## Cross-references

- [INVARIANT-CATALOG.md §I-AL03 mmap base pointer alignment](INVARIANT-CATALOG.md) — alignment invariants
- [UB-TAXONOMY.md §3 Alignment](UB-TAXONOMY.md) — taxonomy
- [PROJECT-TYPES.md §P10 Database / Storage Engine](PROJECT-TYPES.md) — archetype priors
- cass Q-102, Q-201, Q-202 — verbatim source
