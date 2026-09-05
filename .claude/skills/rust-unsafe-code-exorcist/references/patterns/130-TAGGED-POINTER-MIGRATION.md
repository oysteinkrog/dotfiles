# 130-TAGGED-POINTER-MIGRATION.md — Tagged Pointer Specialty

Many legacy Rust codebases use tagged pointers via `as usize` arithmetic to pack flags into pointer's low bits. With strict-provenance, the same trick needs the `with_addr` / `map_addr` API.

This bundle is the specialty for migrating tagged-pointer patterns.

---

## The pattern

Pointers are typically 8-byte aligned (or 4 on 32-bit). The low 3 (or 2) bits are reserved by the alignment guarantee. Code packs flags into those bits:

```rust
// Tag a pointer with a "needs-init" flag in low bit
let raw = Box::into_raw(Box::new(MyStruct::default()));
let tagged: usize = (raw as usize) | 1;   // mark "needs init"
```

This works under permissive provenance. Under strict-provenance, the `(raw as usize) | 1` synthesizes a "no-provenance" pointer; dereferencing it later is UB.

---

## Migration patterns

### Pattern T-1 — `map_addr` for in-place low-bit manipulation

```rust
// Before (permissive provenance)
let raw: *mut MyStruct = Box::into_raw(Box::new(...));
let tagged: usize = (raw as usize) | 1;
let untagged: *mut MyStruct = (tagged & !1) as *mut MyStruct;

// After (strict-provenance)
let raw: *mut MyStruct = Box::into_raw(Box::new(...));
let tagged: *mut MyStruct = raw.map_addr(|a| a | 1);
let untagged: *mut MyStruct = tagged.map_addr(|a| a & !1);
```

`map_addr` preserves provenance; the cast detour does not.

### Pattern T-2 — `with_addr` for setting an absolute address

```rust
// When you have a base pointer + a known address offset:
let base: *const u8 = ...;
let next: *const u8 = base.with_addr(other_addr_with_some_provenance.addr());
```

`with_addr` REPLACES the address while PRESERVING provenance.

### Pattern T-3 — Tagged pointer in struct field

```rust
// Before
struct Node {
    next: *mut Node,  // low bit: "marked for deletion"
}

impl Node {
    unsafe fn deleted(&self) -> bool {
        (self.next as usize) & 1 != 0
    }
    unsafe fn unmark(&mut self) {
        self.next = ((self.next as usize) & !1) as *mut Node;
    }
}

// After (strict-provenance + safer)
struct Node {
    next: *mut Node,
}

impl Node {
    unsafe fn deleted(&self) -> bool {
        self.next.addr() & 1 != 0
    }
    unsafe fn unmark(&mut self) {
        self.next = self.next.map_addr(|a| a & !1);
    }
}
```

The `unsafe fn` marker stays — these are still raw-pointer manipulations — but the strict-provenance API replaces the cast.

### Pattern T-4 — XOR linked list → slab

XOR linked lists fundamentally violate strict-provenance:

```rust
// FUNDAMENTALLY incompatible with strict-provenance
struct Node {
    xor_neighbor: *mut Node,   // (prev ^ next)
}
```

Refactor to safe `slab::Slab` indices:

```rust
// SAFE replacement
use slab::Slab;

struct Node {
    next: Option<usize>,    // index into the slab
    prev: Option<usize>,
}

struct LinkedList {
    nodes: Slab<Node>,
    head: Option<usize>,
    tail: Option<usize>,
}
```

The XOR trick saved one pointer-worth of memory at the cost of complexity. The slab approach preserves cache locality + adds use-after-free protection (slab indices don't reuse).

### Pattern T-5 — Sentinel pointer values

Some codebases use `*mut T` with a specific sentinel value (e.g., `0xDEADBEEF as *mut T`) to mean "uninitialized."

```rust
// Permissive-provenance
const UNINIT: *mut MyStruct = 0xDEADBEEF as *mut MyStruct;

// Strict-provenance (use Option<NonNull<MyStruct>>)
let p: Option<NonNull<MyStruct>> = None;   // explicit "uninitialized"
```

The strict-provenance way is just to use `Option<NonNull<T>>` or `Cell<Option<NonNull<T>>>`. The sentinel-value trick was for memory-efficiency that's rarely worth the complexity.

---

## Audit checklist for tagged pointers

For each site using `as usize`:

- [ ] Identify the purpose: low-bit-flag, address arithmetic, XOR, sentinel, other.
- [ ] Match against patterns T-1 through T-5.
- [ ] Apply the strict-provenance API or recommend a safer refactor.
- [ ] Verify with `MIRIFLAGS="-Zmiri-strict-provenance" cargo +nightly miri test`.

---

## When tagged pointers MUST stay permissive

Some legacy interfaces require the as-usize idiom:

- Cross-FFI when the C side uses tagged pointers and we have to interpret the bytes.
- Custom syscall ABIs that pack into `usize`.
- Hardware MMIO where the bit pattern is the contract.

For these, document the permissive-provenance dependence in the SAFETY comment:

```rust
// SAFETY: This site relies on permissive provenance. The hardware MMIO at
// 0x4000_0000 has the bit pattern as the interface; strict-provenance would
// reject the read. We skip miri's strict-provenance mode for this test:
// see #[cfg_attr(any(miri, miri_strict_provenance), ignore)] on the test.
```

Document the exception; let CI skip strict-provenance for these specific tests.

---

## Strict-provenance API quick reference

The stable API (Rust 1.84+):

| Operation | API |
|-----------|-----|
| Get address (usize) | `p.addr()` |
| Set new address (preserve provenance) | `p.with_addr(new_addr)` |
| Transform address | `p.map_addr(\|a\| ...)` |
| Expose for later round-trip | `p.expose_addr()` |
| Recover from exposed address | `ptr::with_exposed_provenance(addr)` |
| Strict cast (alignment check) | `p as *const U` (compile-time check via const_ptr_methods) |

---

## Anti-patterns

- **`(p as usize) | tag) as *mut T`**. The classic permissive pattern; UB under strict-provenance. Use `map_addr`.
- **XOR linked lists**. Not fixable in-place; refactor to slab indices.
- **`Cell<*mut T>` with embedded flag bits**. Same issue; same fix.
- **`AtomicPtr<T>` with tagged values**. Use `AtomicPtr::compare_exchange` with strict-provenance pointers; cast through `usize` is UB.

---

## Exemplar precedent

- `/dp/franken_engine/src/sched/list.rs` — historically had XOR linked lists for cache-locality + low-memory; refactored in bead `br-fengine-89` to slab indices. Lost a tiny bit of memory; gained strict-provenance compatibility + miri-clean status. The bead documents the trade-off.

---

## Acceptance signal

A tagged-pointer-migration site passes when:

1. The pattern is identified (T-1 through T-5).
2. The strict-provenance API is applied (or the refactor to safe types is landed).
3. miri runs clean under `-Zmiri-strict-provenance`.
4. If permissive-provenance must stay (legacy / hardware interface), the SAFETY comment documents the reason + tests are tagged appropriately.
5. The bead's acceptance criteria include the strict-provenance miri check.
