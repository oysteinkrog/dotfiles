# 70-UNINIT-AND-TRANSMUTE.md — MaybeUninit, transmute, and Repr Casts

A common source of (C) opportunities. Most hand-written `MaybeUninit::assume_init` and `mem::transmute` calls have safer equivalents.

---

## MaybeUninit::assume_init refactors

### Pattern U-1: stack-allocated array → `std::array::from_fn`

```rust
// Before
let mut arr: [MaybeUninit<u64>; 16] = unsafe { MaybeUninit::uninit().assume_init() };
for i in 0..16 {
    arr[i] = MaybeUninit::new(compute(i));
}
let arr: [u64; 16] = unsafe { std::mem::transmute(arr) };

// After
let arr: [u64; 16] = std::array::from_fn(compute);
```

Zero unsafe. Identical codegen for trivially-constructible types.

### Pattern U-2: heap array → `Vec` from iterator

```rust
// Before
let mut vec: Vec<MaybeUninit<u64>> = Vec::with_capacity(n);
for i in 0..n {
    vec.push(MaybeUninit::new(compute(i)));
}
let vec: Vec<u64> = unsafe { std::mem::transmute(vec) };

// After
let vec: Vec<u64> = (0..n).map(compute).collect();
```

`Vec::collect` from a sized iterator pre-allocates exactly `n` slots. Identical perf.

### Pattern U-3: partial init with guard

When initialization can fail partway:

```rust
// Before
struct Builder {
    arr: [MaybeUninit<Item>; 16],
    init_count: usize,
}
impl Builder {
    fn push(&mut self, item: Item) {
        self.arr[self.init_count] = MaybeUninit::new(item);
        self.init_count += 1;
    }
    unsafe fn into_array(self) -> [Item; 16] {
        debug_assert_eq!(self.init_count, 16);
        unsafe { std::mem::transmute(self.arr) }
    }
}
impl Drop for Builder {
    fn drop(&mut self) {
        for i in 0..self.init_count {
            unsafe { self.arr[i].assume_init_drop(); }
        }
    }
}

// After (using arrayvec)
use arrayvec::ArrayVec;
struct Builder {
    arr: ArrayVec<Item, 16>,
}
impl Builder {
    fn push(&mut self, item: Item) {
        self.arr.push(item);   // panics if full; or use try_push
    }
    fn into_array(self) -> Result<[Item; 16], TooFewItems> {
        self.arr.into_inner().map_err(|_| TooFewItems)
    }
}
// Drop is handled by ArrayVec — items that were pushed but not finalized
// have their destructors run automatically.
```

`arrayvec` covers the bounded-vector + partial-init + correct-drop case safely.

### Pattern U-4: zeroable type → `Box::new_zeroed` (unstable) or `zerocopy::FromZeroes`

For large structs that can validly be all-zero:

```rust
// Before
let mut buf: Box<[u8; 1_000_000]> = unsafe {
    let layout = std::alloc::Layout::new::<[u8; 1_000_000]>();
    let raw = std::alloc::alloc_zeroed(layout) as *mut [u8; 1_000_000];
    Box::from_raw(raw)
};

// After (stable, via zerocopy)
use zerocopy::FromZeroes;
let buf: Box<[u8; 1_000_000]> = FromZeroes::new_box_zeroed();
```

zerocopy uses `alloc_zeroed` internally; same perf, zero unsafe at the call site.

---

## transmute refactors

### Pattern T-1: byte slice → typed slice

```rust
// Before
fn parse_u32_array(bytes: &[u8]) -> &[u32] {
    assert!(bytes.as_ptr() as usize % 4 == 0);   // alignment check
    assert!(bytes.len() % 4 == 0);
    let len = bytes.len() / 4;
    unsafe { std::slice::from_raw_parts(bytes.as_ptr() as *const u32, len) }
}

// After
use zerocopy::Ref;
fn parse_u32_array(bytes: &[u8]) -> Option<&[u32]> {
    Ref::<&[u8], [u32]>::new_slice(bytes).map(|r| r.into_slice())
}
```

`zerocopy::Ref` returns `Option` for the alignment + length checks; the safe API doesn't panic on bad input.

### Pattern T-2: endian-aware read

```rust
// Before
fn read_u32_be(buf: &[u8; 4]) -> u32 {
    unsafe { std::mem::transmute::<[u8; 4], u32>(*buf).to_be() }
}

// After
fn read_u32_be(buf: &[u8; 4]) -> u32 {
    u32::from_be_bytes(*buf)
}
```

`u32::from_be_bytes` / `from_le_bytes` / `from_ne_bytes` are stable safe API. Identical codegen.

### Pattern T-3: enum repr cast

```rust
// Before
#[repr(u8)]
enum Kind { A, B, C }

fn from_byte(b: u8) -> Option<Kind> {
    if b > 2 { return None; }
    Some(unsafe { std::mem::transmute(b) })
}

// After (option 1: TryFrom)
impl TryFrom<u8> for Kind {
    type Error = ();
    fn try_from(b: u8) -> Result<Self, Self::Error> {
        match b { 0 => Ok(Kind::A), 1 => Ok(Kind::B), 2 => Ok(Kind::C), _ => Err(()) }
    }
}

// After (option 2: num_enum)
use num_enum::TryFromPrimitive;
#[repr(u8)]
#[derive(TryFromPrimitive)]
enum Kind { A, B, C }
let k = Kind::try_from(b)?;
```

The match version generates the same code as the transmute. `num_enum` derives it for you.

### Pattern T-4: bytemuck::Pod for fixed-layout structs

```rust
// Before
#[repr(C, packed)]
struct Header {
    version: u32,
    flags: u32,
}

fn read_header(bytes: &[u8]) -> Option<Header> {
    if bytes.len() < std::mem::size_of::<Header>() { return None; }
    Some(unsafe {
        std::ptr::read_unaligned(bytes.as_ptr() as *const Header)
    })
}

// After
use bytemuck::Pod;
#[repr(C, packed)]
#[derive(Pod, Copy, Clone)]
struct Header {
    version: u32,
    flags: u32,
}

fn read_header(bytes: &[u8]) -> Option<Header> {
    bytemuck::try_pod_read_unaligned(bytes).ok()
}
```

`bytemuck` covers `Pod` (no padding, all-bits-valid) types safely.

---

## Anti-patterns

### Anti-pattern A-1: transmute to silence the compiler

```rust
// NEVER
let s: &str = unsafe { std::mem::transmute(some_bytes) };   // skips UTF-8 validation
```

If you have bytes and need a `&str`, use `std::str::from_utf8`. If perf matters AND you know the bytes are valid UTF-8 from upstream, use `std::str::from_utf8_unchecked` — but that's (A) or (B) depending on the audit context.

### Anti-pattern A-2: assume_init on an array containing types with Drop

```rust
// NEVER
let mut arr: [MaybeUninit<String>; 16] = unsafe { MaybeUninit::uninit().assume_init() };
// If you panic after writing some but not all elements, the partial-init array's
// Drop runs on uninit memory — UB.
```

Use the guard pattern from U-3, or use `arrayvec`.

### Anti-pattern A-3: zero-sized type tricks

```rust
// NEVER
struct Zst;
let s = std::slice::from_raw_parts(std::ptr::NonNull::<Zst>::dangling().as_ptr(), n);
```

This is technically sound for ZSTs but extremely fragile under future Rust changes. Use `std::iter::repeat(Zst).take(n)` or `vec![Zst; n]`.

---

## Equivalence-proving uninit refactors

The property test for an uninit refactor should generate inputs that:

1. **Trigger early-return.** If the original `assume_init` was reachable only after a check, the safe version must return the same `None` / error on the same input.
2. **Trigger panic.** If the original could `assume_init` after only partial writes (the partial-init bug pattern), the safe version must either not have the bug OR panic at the same input.
3. **Test Drop order.** Use a `DropTracker` test fixture to log destructor calls; assert the safe version's drop log matches the original's.

---

## Acceptance signal

An uninit / transmute (C) classification passes when:

1. The safe alternative is named (`from_be_bytes` / `zerocopy::Ref` / `bytemuck::try_pod_read` / etc.).
2. Full safe replacement code is in the plan.
3. Property test covers the failure modes of the original (alignment, length, partial-init, Drop).
4. `miri` runs clean on the rewrite.
5. Allocator identity is preserved (`Box::from_raw` round-trips don't silently change the allocator).
