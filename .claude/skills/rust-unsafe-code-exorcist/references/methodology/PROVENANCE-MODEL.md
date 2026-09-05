# PROVENANCE-MODEL.md — Strict vs Permissive Provenance

Rust's pointer model is in the middle of a transition. The audit must know which model it's operating under, because what counts as UB differs.

This file is a focused reference: what provenance means, how to detect provenance bugs, and how to write code that's correct under both models.

---

## Two models

| Model | Meaning | Audit impact |
|-------|---------|--------------|
| **Permissive (legacy)** | Pointers are integers; you can cast `usize ↔ *mut T` freely; only out-of-bounds dereference is UB. | Easy to write; many old idioms (XOR linked lists, tagged pointers via `usize`) are accepted. |
| **Strict** | Pointers have a logical "provenance" — the allocation they were derived from. Casting `usize → *mut T` synthesizes a "free" provenance which is UB to dereference if you didn't get it from a valid allocation. | XOR linked lists are UB. Tagged pointers via `usize` need `with_addr` / `expose_addr` /  `from_exposed_addr`. |

The **strict** model is what miri tests with `-Zmiri-strict-provenance`. It's also what the language is moving toward: see [RFC 3559 Strict Provenance](https://rust-lang.github.io/rfcs/3559-rust-has-provenance.html) and [the std stabilization PR](https://github.com/rust-lang/rust/pull/130350).

The audit's bar: a rewrite is "sound" iff it passes `cargo +nightly miri test -Zmiri-strict-provenance`.

---

## What provenance is, operationally

When you write:

```rust
let v: Vec<u32> = vec![1, 2, 3];
let p: *const u32 = v.as_ptr();
```

`p` carries the provenance of `v`'s allocation. You can read through `p` for as long as the allocation lives.

When you write:

```rust
let addr: usize = p as usize;
let p2: *const u32 = addr as *const u32;
```

Under PERMISSIVE: `p2` is equivalent to `p`. Same provenance.

Under STRICT: the cast `usize → *const u32` synthesizes a "no provenance" — `p2` is a pointer with no allocation behind it. Dereferencing `p2` is UB even though it's bit-identical to `p`.

---

## How to write code that works under both

The strict-provenance methods on `*mut T` (stable as of 1.84):

| Operation | Old idiom | Strict-provenance API |
|-----------|-----------|----------------------|
| Get the address of a pointer | `p as usize` | `p.addr()` |
| Reset a pointer's address (keep provenance) | `(p as usize + 8) as *mut T` | `p.with_addr(p.addr() + 8)` |
| Round to alignment | `(p as usize & !7) as *mut T` | `p.map_addr(\|a\| a & !7)` |
| Round up | `((p as usize + 7) & !7) as *mut T` | `p.map_addr(\|a\| (a + 7) & !7)` |
| Expose for later round-trip | (implicit) | `p.expose_addr()` then `ptr::with_exposed_provenance(addr)` |

In the audit:

- **Spot legacy idiom `(p as usize ... ) as *mut T`** → flag as a (C) candidate for migration to `with_addr` / `map_addr`.
- **Spot `*mut T` constructed from `usize` arithmetic with no `expose`** → strict-provenance violation; (C) or (A) depending on context.

---

## How the audit detects provenance violations

```bash
# Run miri with strict-provenance flag
MIRIFLAGS="-Zmiri-strict-provenance" cargo +nightly miri test --workspace --all-features

# Miri will print:
# error: Undefined Behavior: out-of-bounds pointer use: expected a pointer with provenance, but got 0x...
```

The audit script `run-miri.sh` runs both default and strict-provenance modes (see [TOOLCHAIN-RUNBOOK.md § miri](TOOLCHAIN-RUNBOOK.md#miri)).

If the default mode passes but strict-provenance fails:
- The site is using a legacy idiom that's accepted today but won't be tomorrow.
- The (C) refactor is: swap for the strict-provenance API.
- The (A) hardening (if a (C) refactor isn't possible) is: document the provenance assumption explicitly + pin the miri config used.

---

## Common patterns that look like provenance bugs but aren't

### Tagged pointers (low bits free)

`Box::leak`-style allocations are typically 8-byte aligned; the low 3 bits can be used as flags:

```rust
// Before (legacy)
let tagged: usize = (p as usize) | flag;
let untagged: *mut T = (tagged & !flag) as *mut T;
```

Under strict-provenance:

```rust
// After
let tagged: *mut T = p.map_addr(|a| a | flag);
let untagged: *mut T = tagged.map_addr(|a| a & !flag);
```

`map_addr` preserves provenance; the cast detour does not.

### Sentinel pointers (NonNull::dangling())

`NonNull::<T>::dangling()` returns a non-null pointer with no provenance, intended only as a marker. Don't deref. Strict-provenance accepts this.

### XOR linked lists

```rust
// XOR-doubly-linked list (legacy; UB under strict-provenance)
let xor_ptr = (prev as usize) ^ (next as usize);
let neighbor = (xor_ptr ^ (other as usize)) as *mut Node;
```

This pattern is FUNDAMENTALLY incompatible with strict-provenance. The reconstructed pointer has no provenance.

Refactor (C): use `slab::Slab` with `usize` indices instead. The XOR trick was a memory-savings hack; the slab provides both index-based access and cache locality.

Or (A): document that the crate requires permissive provenance; mark with `#[cfg_attr(miri, ignore)]` on the relevant tests; do NOT run strict-provenance miri.

---

## Special cases

### FFI

FFI pointers come from C with no Rust-side provenance. Use `core::ptr::with_exposed_provenance` after a "trusted" cast to give the pointer a fresh provenance derived from the C side:

```rust
let raw = unsafe { libc::mmap(...) };
let p = core::ptr::with_exposed_provenance::<u8>(raw as usize);
```

The audit's `60-FFI-PATTERNS.md` boundary contract should document this.

### Volatile MMIO

`read_volatile` / `write_volatile` on pointers constructed from `0x4000_0000 as *mut u32` ARE strict-provenance UB by default. For embedded crates, this is (A); the (A) hardening pins the miri config to permit such constructions (custom miri shim) or skips miri on these tests.

See [55-EMBEDDED-PATTERNS.md](../patterns/55-EMBEDDED-PATTERNS.md) when present.

---

## Acceptance signal

A site involving pointer-int casts passes the provenance check when:

1. **`run-miri.sh` exits 0 in both default AND strict-provenance modes**, OR
2. The site is documented as permissive-only with an explicit reason (e.g., legacy XOR linked list, embedded MMIO), AND the test config skips strict-provenance for the relevant tests, AND the SAFETY comment cites this.

For (C) rewrites: provenance-clean is required. The rewrite that drops strict-provenance compliance is not a successful rewrite.
