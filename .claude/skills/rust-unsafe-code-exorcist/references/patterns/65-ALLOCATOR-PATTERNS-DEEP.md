# 65-ALLOCATOR-PATTERNS-DEEP.md — Custom Allocators, Arenas, and Slabs

Custom allocators are a frequent (A) cluster — they ARE unsafe by language definition. But the call-site usage of those allocators is often (C) refactorable from raw pointers to safer arena APIs.

This file is the deep dive on the per-allocator-style patterns.

---

## The allocator-identity rule (repeated for emphasis)

A (C) rewrite MUST NOT silently change the allocator. Operator 📐 Allocator-Identity (see [OPERATORS.md](../methodology/OPERATORS.md)) checks for this.

The safe rewrite of arena-using code uses the SAFE API of the SAME arena, not `std::vec::Vec` etc.

| Original | Preserved-allocator rewrite | NOT allowed (without explicit user OK) |
|----------|----------------------------|---------------------------------------|
| raw pointer into `bumpalo::Bump` | `bumpalo::collections::Vec<T>` | `std::vec::Vec<T>` |
| raw pointer into `slab::Slab` | `slab::Slab` indices + `&T` / `&mut T` | `HashMap<usize, T>` |
| raw pointer into custom arena | wrapper type that owns into the arena | `Box<T>` |
| `mmap`'d region pointer | `memmap2::Mmap` newtype | `Vec<u8>` |
| Page-aligned allocation for io_uring | `Layout::from_size_align(N, 4096)` wrapped in custom owned type | unaligned `Vec<u8>` |

---

## Arena crates and their use cases

| Crate | Use case | Safe API for callers |
|-------|----------|----------------------|
| `bumpalo` | Per-request bump arena; all items dropped together | `bumpalo::Bump`, `bumpalo::collections::{Vec, String}` |
| `typed-arena` | Per-thread typed arena; items live for arena's lifetime | `typed_arena::Arena<T>::alloc(t) -> &mut T` |
| `slab` | Insert / remove with stable usize indices | `slab::Slab<T>::insert` / `get` / `get_mut` / `remove` |
| `slotmap` | Generational indices (catches use-after-free) | `slotmap::SlotMap<K, V>::insert` / `get` |
| `generational-arena` | Older slot-map equivalent | `generational_arena::Arena<T>` |
| `id-arena` | Lightweight; non-generational | `id_arena::Arena<T>` |

Pick by ownership needs:

```
Do items have varying lifetimes?  → slab / slotmap / id-arena (indexed)
Do all items live together?       → bumpalo / typed-arena (lifetime-scoped)
Do you need use-after-free detection? → slotmap (use generational keys)
Do you need cache locality + small footprint? → slab
```

---

## Pattern AL-1 — Doubly-linked list with raw pointers → slab

Classic refactor. Before:

```rust
struct Node {
    next: *mut Node,
    prev: *mut Node,
    value: T,
}
struct LinkedList {
    head: *mut Node,
    tail: *mut Node,
}
```

After:

```rust
use slab::Slab;

struct Node {
    next: Option<usize>,
    prev: Option<usize>,
    value: T,
}

struct LinkedList {
    nodes: Slab<Node>,
    head: Option<usize>,
    tail: Option<usize>,
}

impl LinkedList {
    fn push_back(&mut self, value: T) {
        let key = self.nodes.insert(Node { next: None, prev: self.tail, value });
        if let Some(t) = self.tail {
            self.nodes[t].next = Some(key);
        } else {
            self.head = Some(key);
        }
        self.tail = Some(key);
    }
    fn pop_front(&mut self) -> Option<T> {
        let head = self.head?;
        let node = self.nodes.remove(head);
        self.head = node.next;
        if let Some(n) = node.next {
            self.nodes[n].prev = None;
        } else {
            self.tail = None;
        }
        Some(node.value)
    }
}
```

Zero unsafe; cache-friendly (slab uses a Vec internally); stable indices.

**Equivalence test.** Property: insert N values, pop N values, verify FIFO order matches original.

---

## Pattern AL-2 — Generation-aware indices for use-after-free protection

When indices outlive the inserted item, raw `usize` indices can refer to a different-now-occupied slot ("ABA"). `slotmap` adds a generation:

```rust
use slotmap::{SlotMap, DefaultKey};

struct Foo {
    items: SlotMap<DefaultKey, Item>,
}

let key = items.insert(item);
items.remove(key);
let item2 = items.insert(item_other);
// key is stale; will not reference item2:
assert!(items.get(key).is_none());     // OK
assert!(items.get(items.keys().next().unwrap()).is_some());  // new key, OK
```

The generation counter is invisible to consumers but enforces "stale key returns None".

**Refactor (C):** when raw pointer or `usize` indices were used + ABA was theoretically possible, switch to slotmap. Cost: extra u32 per index, slight slow.

---

## Pattern AL-3 — Per-request bump arena

Many request-scoped allocations are wasted if they all go to the global allocator (high fragmentation; many small `malloc`s):

```rust
use bumpalo::Bump;

fn handle_request(input: &[u8]) -> Result<Output, Error> {
    let arena = Bump::new();
    let parsed = parse(input, &arena)?;       // allocates in arena
    let transformed = transform(parsed, &arena)?;
    let serialized = serialize(transformed, &arena)?;
    Ok(serialized.to_global())     // copy out of arena before arena drops
}
```

All arena allocations are freed in O(1) when `arena` drops. No per-allocation `free` calls.

**Refactor (C):** in a fn that did multiple `Box::new` / `Vec::push` for short-lived items, introduce a `Bump` arena. The intermediate items live in the arena; only the final result moves to the global heap.

**Watch for.** Arena items must NOT escape the arena's lifetime. The borrow checker prevents this for `&'arena T` references; `Box::new_in` would not (you'd be moving an arena-owned Box outside its source allocator, which is UB).

---

## Pattern AL-4 — Layout-aware allocation for FFI / DMA

Some unsafe is unavoidable when the allocation has a specific layout requirement:

```rust
use std::alloc::{alloc, dealloc, Layout};

fn alloc_page_aligned(size: usize) -> *mut u8 {
    let layout = Layout::from_size_align(size, 4096).unwrap();
    unsafe { alloc(layout) }
}
```

This is (A) — language primitive. Wrap in a newtype:

```rust
pub struct PageAlignedBuffer {
    ptr: NonNull<u8>,
    layout: Layout,
}

impl PageAlignedBuffer {
    pub fn new(size: usize) -> Result<Self, AllocError> {
        let layout = Layout::from_size_align(size, 4096)?;
        let ptr = unsafe { alloc(layout) };
        let ptr = NonNull::new(ptr).ok_or(AllocError)?;
        Ok(Self { ptr, layout })
    }
    pub fn as_slice(&self) -> &[u8] {
        unsafe { core::slice::from_raw_parts(self.ptr.as_ptr(), self.layout.size()) }
    }
    pub fn as_mut_slice(&mut self) -> &mut [u8] {
        unsafe { core::slice::from_raw_parts_mut(self.ptr.as_ptr(), self.layout.size()) }
    }
}

impl Drop for PageAlignedBuffer {
    fn drop(&mut self) {
        unsafe { dealloc(self.ptr.as_ptr(), self.layout); }
    }
}
```

The (A) is concentrated in `new` and `Drop`; everything else is safe.

---

## Pattern AL-5 — Custom GlobalAlloc impl

Implementing `GlobalAlloc` IS (A) — see [00-CANONICAL-UNAVOIDABLE.md § 7](00-CANONICAL-UNAVOIDABLE.md). The audit's job is verifying the impl is sound.

Per-impl checks:

- `alloc`: returns null on failure or a valid layout-conforming pointer; never returns garbage.
- `dealloc`: accepts only pointers from a previous `alloc` with matching `Layout`; double-free is UB.
- `alloc_zeroed`: the returned region is zero-initialized.
- `realloc`: behaves as `alloc` + copy + `dealloc` (or in-place when feasible).
- Thread safety: `GlobalAlloc` is required to be `Sync` (the global allocator is shared across threads).

Miri can check the allocator under stacked-borrows AND tree-borrows. Both must pass.

---

## Exemplar precedents

- `/dp/frankenfs/src/alloc/slab.rs` — `GlobalAlloc` impl is (A); the in-crate consumers were refactored to `bumpalo` ((C); bead `br-ffs-148` analog).
- `/dp/frankenfs/src/cache/lru.rs` — raw `*mut LruEntry` → `slab::Slab` ((C); pattern AL-1).
- `/dp/asupersync/src/io/ring.rs` — page-aligned DMA buffers via custom `PageAlignedBuffer`-style type ((A) localized; consumers safe).

---

## Anti-patterns

- **Replacing arena with `Vec` "for simplicity".** Allocator identity is part of the perf contract.
- **Using `Box::new_in(arena)` and then moving the box outside the arena's scope.** UB — the Box would `dealloc` against the global allocator. Use plain arena references instead.
- **Multiple allocator implementations active simultaneously.** Rust only allows ONE `#[global_allocator]`. Use `Allocator` trait (unstable) or per-type wrappers for crate-local custom allocators.
- **Custom GlobalAlloc that calls `malloc` internally.** Defeats the point; just don't have a custom allocator.
- **Allocator that panics on OOM.** Returns null instead. Panicking from `alloc` is UB (the allocator must not unwind into the caller).

---

## Acceptance signal

A custom-allocator site passes when:

1. The allocator's `GlobalAlloc`/`Allocator` impl has a hardened SAFETY comment per [00-CANONICAL-UNAVOIDABLE.md § 7](00-CANONICAL-UNAVOIDABLE.md).
2. In-crate consumers use the allocator's SAFE API (`Bump::alloc_with`, `Slab::insert`, etc.) rather than raw pointers.
3. miri runs clean under stacked-borrows AND tree-borrows.
4. The (C) refactors of consumer code preserve allocator identity (operator 📐).
5. The bench shows no allocation-pressure regression vs the prior raw-pointer version.
