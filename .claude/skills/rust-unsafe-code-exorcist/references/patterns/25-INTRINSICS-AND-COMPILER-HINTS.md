# 25-INTRINSICS-AND-COMPILER-HINTS.md — `core::intrinsics::*` and `core::hint::*_unchecked`

The intrinsics family is the bottom of the Rust stack: compiler hints, primitive pointer operations, atomic operations not exposed via `core::sync::atomic`, and miscellaneous codegen primitives. Almost every site here is **(A) STRICTLY_UNAVOIDABLE** or **(B) PERF_ONLY** — there's rarely a "clean refactor" because the intrinsic IS the codegen hint.

This bundle is the dedicated home for the kinds the audit enumerator surfaces as `intrinsic_call` and `intrinsic_ptr`. The companion topic is SIMD intrinsics, covered separately in [20-SIMD-AND-PERF.md](20-SIMD-AND-PERF.md).

---

## What this bundle covers

| Pattern | Kind | Typical bucket | Section |
|---------|------|----------------|---------|
| `core::hint::unreachable_unchecked()` | optimizer hint | (A) | § HU-1 |
| `core::hint::assert_unchecked(cond)` | optimizer hint | (A) | § HU-2 |
| `core::intrinsics::likely / unlikely` | branch hint | (B), often → (C) | § HU-3 |
| `core::intrinsics::assume(cond)` | optimizer hint | (A) | § HU-4 |
| `core::ptr::read(p)` / `write(p, v)` | raw read/write | (A) / (B) | § PR-1 |
| `core::ptr::read_unaligned` / `write_unaligned` | unaligned access | (B), often → (C) via `from_ne_bytes` | § PR-2 |
| `core::ptr::read_volatile` / `write_volatile` | volatile MMIO | (A) | § PR-3 (cross-ref [55-EMBEDDED-PATTERNS.md](55-EMBEDDED-PATTERNS.md)) |
| `core::ptr::copy` / `copy_nonoverlapping` | memcpy | (B), often → (C) via `slice::copy_from_slice` | § PR-4 |
| `core::ptr::swap` / `swap_nonoverlapping` | mem swap | (B), often → (C) | § PR-5 |
| `core::ptr::drop_in_place(p)` | manual drop | (A) | § PR-6 |
| `core::intrinsics::atomic_*_unsynchronized` | atomic without fence | (A) | § AT-1 |
| `core::mem::transmute_copy` | unaligned reinterpret | (A) / (B) | § MM-1 |

The bundle does NOT cover SIMD intrinsics from `core::arch::x86_64::*` / `core::arch::aarch64::*` — see [20-SIMD-AND-PERF.md](20-SIMD-AND-PERF.md).

---

## § HU-1 — `core::hint::unreachable_unchecked()`

Signal to LLVM that a code path is statically impossible. The compiler may use this to optimize away a check, a panic, or an exhaustive-match fallback.

### Typical use

```rust
// SAFETY: `state` is one of the three variants by the upstream parser invariant.
match state {
    State::A => path_a(),
    State::B => path_b(),
    State::C => path_c(),
    _ => unsafe { core::hint::unreachable_unchecked() },
}
```

### Classification

**(A) STRICTLY_UNAVOIDABLE** when:
- The hot path is millions of calls per second.
- The safe `unreachable!()` macro adds a branch + panic infrastructure that the perf budget can't absorb.
- The upstream invariant is genuinely enforced (a validated input).

**Demoting to (B) or (C)** is rare; the typical refactor is to express the exhaustiveness *in the type system* (e.g., turn an open enum into a closed one), which collapses the match arm itself.

### Audit checklist

| Question | Verifier |
|----------|----------|
| Is the unreachability proved or asserted? | Look upstream for the validation; if absent, this is bugbait — reclassify to bug, not (A). |
| Is the perf claim measured? | criterion + flamegraph (per CLASSIFICATION-RUBRIC § B). |
| Did the (A) survive an adversarial pass that proposed `unreachable!()`? | See [E-104] for the canonical defense. |

### Sound use

The site is sound iff every path NOT in the match-arms is provably absent. The proof obligation is on the SAFETY comment, which must trace to the validation that ruled the variant out.

### Common footgun

Pasted in to silence a "non-exhaustive match" warning without verifying the upstream invariant. If you can't name a specific call site that enforces the invariant, the site is UB-bait.

---

## § HU-2 — `core::hint::assert_unchecked(cond)`

Promise to the compiler that `cond` is true. Allows LLVM to use the condition for downstream optimizations (e.g., bounds-check elimination).

### Typical use

```rust
// SAFETY: caller guaranteed at construction time that buf.len() == 16.
unsafe { core::hint::assert_unchecked(buf.len() == 16); }
for byte in &buf[..16] { ... }  // bounds-check elided
```

### Classification

**(A)** when the assertion is the only way to communicate the invariant to the optimizer AND the safe alternative (a runtime `assert!`) shows measurable perf cost.

**(C)** when changing the data type to encode the invariant (e.g., `&[u8; 16]` instead of `&[u8]`) lets the compiler infer the same thing. Always prefer this when the API allows.

### Audit checklist

| Question | Verifier |
|----------|----------|
| Can the invariant be encoded in the type? | If yes, propose (C) refactor to fixed-size array / `NonZero*` / `bounded::*`. |
| Is the assertion ever violated? | Property test: generate inputs that fall outside the asserted range and verify the caller path prevents them. |
| Is `core::hint::assert_unchecked` available on this MSRV? | Stable since 1.81.0. Earlier versions need `assume()` from intrinsics (nightly). |

### Sound use

Site is sound iff every path that reaches it has already established `cond` is true. If the upstream code can produce a state where `cond` is false, the audit reclassifies the site to a bug.

---

## § HU-3 — `core::intrinsics::{likely, unlikely}`

Branch-predictor hints. Stable equivalents are NOT YET available; you typically see this only in nightly-only crates or projects pinning a specific nightly.

### Typical use

```rust
if unsafe { core::intrinsics::unlikely(error) } {
    return Err(ErrorKind::Specific);
}
// fast path
```

### Classification

**(B)** by default — there's a safe formulation (omit the hint; let LLVM's heuristics decide). The safe form is almost always within perf budget on modern CPUs; LLVM's static predictor is good.

**(C) (graduated)** when bench shows no measurable delta — delete the hint entirely.

**(A)** is rare and requires a documented hot path where the branch direction is provably skewed AND LLVM consistently mispredicts.

### Audit checklist

| Question | Verifier |
|----------|----------|
| Did benchmark before-after show measurable difference? | `cargo bench` with the hint vs without; document the delta. |
| Is the hint nightly-only? | Yes; check the project's toolchain pin. If pinned to nightly anyway, the hint is available. |

---

## § HU-4 — `core::intrinsics::assume(cond)`

The nightly intrinsic equivalent of `core::hint::assert_unchecked`. Use the stable form on stable toolchains.

Same audit checklist as HU-2.

---

## § PR-1 — `core::ptr::read(p)` / `core::ptr::write(p, v)`

Read or write a value through a raw pointer without invoking `Drop`. Almost always inside an `unsafe` block.

### Typical use

```rust
// SAFETY: `slot` is aligned, valid, and we won't double-drop because we
// overwrite the slot's bytes immediately after read.
let old = unsafe { core::ptr::read(slot) };
unsafe { core::ptr::write(slot, new_value) };
```

### Classification

- **(A)** when the operation models something the safe API can't (e.g., the slot's `Drop` shouldn't run because we're reusing the memory).
- **(B)** when the operation models a known-equivalent safe pattern but measurement shows the safe pattern is slower. Bench it.
- **(C)** when a `mem::replace`, `mem::take`, `Option::take`, or trivially-`Copy` substitute exists. Most `read`/`write` sites graduate to (C) on inspection.

### Audit checklist

| Question | Verifier |
|----------|----------|
| Does the slot's type `Drop`? Are we leaking it? | Check via miri; if the audit finds the slot's `Drop` wasn't run and SHOULD have been, that's a soundness bug. |
| Alignment + validity invariants stated in SAFETY? | Required for (A). |
| Could `mem::replace(slot, new_value)` replace this entirely? | Almost always yes; propose (C). |

### Common refactor target

```rust
// BEFORE (unsafe)
let old = unsafe { core::ptr::read(slot) };
unsafe { core::ptr::write(slot, new_value) };

// AFTER (safe, identical codegen on -O3 for Copy types)
let old = core::mem::replace(slot, new_value);
```

---

## § PR-2 — `core::ptr::read_unaligned` / `write_unaligned`

For data that doesn't satisfy the type's natural alignment (e.g., bytes parsed from a network packet).

### Classification

**Almost always (C)** — `u32::from_ne_bytes(buf[..4].try_into().unwrap())` produces identical codegen on modern architectures (LLVM merges the loads). The `try_into().unwrap()` panics on length mismatch; if the audit prefers no-panic, use `from_ne_bytes` with explicit bounds-checked extraction.

### Refactor target

```rust
// BEFORE
let v: u32 = unsafe { core::ptr::read_unaligned(buf.as_ptr() as *const u32) };

// AFTER
let v = u32::from_ne_bytes(buf[..4].try_into().unwrap());
// OR for safer panicking discipline:
let v = u32::from_ne_bytes(*buf.first_chunk::<4>().ok_or(Error::short)?);
```

---

## § PR-3 — `core::ptr::read_volatile` / `write_volatile`

Required for MMIO. Always (A). See [55-EMBEDDED-PATTERNS.md](55-EMBEDDED-PATTERNS.md) for embedded-specific guidance, and [R-008] in [REJECTED-PATTERNS.md](../methodology/REJECTED-PATTERNS.md) for why non-volatile reads don't work as a substitute.

### Sound use

```rust
// SAFETY: GPIO0 mapped at 0x40000000 by the linker script; the address is
// valid for the lifetime of the GpioPort newtype; concurrent access is
// guarded by a `cortex_m::interrupt::CriticalSection`.
let reg = unsafe { core::ptr::read_volatile(0x40000000 as *const u32) };
```

### Refactor opportunity

Switch to `volatile-register::RW<u32>` for typed register access. See [E-031] in [EXEMPLAR-CATALOG.md](../source/EXEMPLAR-CATALOG.md). The (A) shrinks to the register-block construction; per-field accesses become safe.

---

## § PR-4 — `core::ptr::copy` / `copy_nonoverlapping`

memcpy-style copy through raw pointers.

### Classification

**Almost always (C)** — `slice::copy_from_slice` autovectorizes to the same code. The unsafe version is only needed when the source and destination are NOT slices (e.g., FFI buffer + Rust slice).

### Refactor target

```rust
// BEFORE
unsafe { core::ptr::copy_nonoverlapping(src.as_ptr(), dst.as_mut_ptr(), n); }

// AFTER (when src + dst are slices)
dst[..n].copy_from_slice(&src[..n]);

// AFTER (when working from a raw pointer of known-good provenance)
let src_slice = unsafe { core::slice::from_raw_parts(src, n) };
dst[..n].copy_from_slice(src_slice);
// The slice construction is one isolated unsafe; the copy is safe.
```

The bias is to concentrate the unsafe at the slice construction (a single audited site) and use safe copies downstream.

### Audit checklist

| Question | Verifier |
|----------|----------|
| Are both endpoints slices? | If yes, propose (C) refactor. |
| Could autovec produce identical code? | Verify via `cargo asm` or `cargo show-asm`. |
| Source / dest overlap? Use `copy` not `copy_nonoverlapping`. | Document in SAFETY. |

---

## § PR-5 — `core::ptr::swap` / `swap_nonoverlapping`

### Classification

**Almost always (C)** — `core::mem::swap(&mut a, &mut b)` is the safe equivalent and produces identical code.

### Refactor target

```rust
// BEFORE
unsafe { core::ptr::swap(&mut a as *mut _, &mut b as *mut _); }

// AFTER
core::mem::swap(&mut a, &mut b);
```

The only case where `core::ptr::swap` is needed is when the slots are NOT exclusively borrowed via `&mut` — which is itself usually a soundness smell.

---

## § PR-6 — `core::ptr::drop_in_place(p)`

Run `Drop` for the value at `p` without freeing the memory.

### Typical use

Custom allocators / arena types that manage a region of memory holding `T`s and need to destruct without freeing.

### Classification

**(A)** when the surrounding code is a custom-allocator implementation. The (A) cluster typically includes `core::ptr::drop_in_place` + a partner `core::ptr::write` that initialized the slot.

**(C)** when the surrounding code is NOT an allocator but just leaning on the primitive. Refactor to use owned types (`Box<T>` / `Vec<T>` / `Option::take()`).

### Audit checklist

| Question | Verifier |
|----------|----------|
| Will the memory at `p` be freed separately? | Required; otherwise this leaks. |
| Will `p` be re-used after this call? Sound iff the slot is overwritten before any subsequent read. | miri verifies. |
| Could the surrounding flow be rewritten with owned types? | If yes, (C). |

---

## § AT-1 — `core::intrinsics::atomic_*_unsynchronized`

Atomic operations that don't insert the implied fence that `core::sync::atomic` operations do. Nightly-only.

### Typical use

Tightly-coupled producer-consumer protocols where the surrounding fences are already issued by the consumer, and the load is ordered ONLY relative to those.

### Classification

**(A)** by default — `core::sync::atomic::*` has a guaranteed fence that the protocol can't tolerate. See [E-070], [E-109] in [EXEMPLAR-CATALOG.md](../source/EXEMPLAR-CATALOG.md) and [R-003] in [REJECTED-PATTERNS.md](../methodology/REJECTED-PATTERNS.md) for the canonical defense.

**Mandatory:** a `loom` test demonstrating the protocol's correctness, cited in the SAFETY comment.

### Sound use

```rust
// SAFETY: see tests/loom_worker_park.rs — the loom model proves this
// unsynchronized load is correct relative to the surrounding Release/Acquire
// fences in `unpark_one` and `park_self`. See [E-109] for the rejection of
// the `AtomicU64::load(Relaxed)` alternative.
let raw = unsafe { core::intrinsics::atomic_load_unsynchronized(&STATE) };
```

---

## § MM-1 — `core::mem::transmute_copy`

Reinterpret bits across types, even when alignments differ. The unaligned version of `mem::transmute`.

### Classification

**(B)** when the source/dest types are POD-like and the perf matters. **(C)** when `zerocopy::transmute` or `bytemuck::pod_read_unaligned` applies.

See [70-UNINIT-AND-TRANSMUTE.md](70-UNINIT-AND-TRANSMUTE.md) for the broader transmute landscape; this section covers only the unaligned variant.

---

## Audit-time scripted checks

Once the enumerator runs (`scripts/enumerate-unsafe.sh`), the `intrinsic_call` and `intrinsic_ptr` kinds appear in `unsafe-inventory.jsonl`. The site-analyzer should consult this bundle's audit checklists when writing the per-site write-up.

For each `intrinsic_*` site, the analyzer fills in:
1. Which `§` subsection applies.
2. Whether the site survives the section's classification rule.
3. The proposed bucket + the falsification test.

The classifier's Phase 4 pass uses the per-section default bucket as the starting recommendation.

---

## Cross-references

- [20-SIMD-AND-PERF.md](20-SIMD-AND-PERF.md) — SIMD intrinsics (separate bundle).
- [00-CANONICAL-UNAVOIDABLE.md](00-CANONICAL-UNAVOIDABLE.md) — (A) catalog by language section.
- [55-EMBEDDED-PATTERNS.md](55-EMBEDDED-PATTERNS.md) — MMIO + volatile (PR-3 cross-ref).
- [35-ATOMICS-AND-ORDERINGS.md](35-ATOMICS-AND-ORDERINGS.md) — atomics fence semantics (AT-1 cross-ref).
- [70-UNINIT-AND-TRANSMUTE.md](70-UNINIT-AND-TRANSMUTE.md) — transmute + MaybeUninit (MM-1 cross-ref).
- [REJECTED-PATTERNS.md](../methodology/REJECTED-PATTERNS.md) — refactors we tried + chose not to land for these primitives.
- [CLASSIFICATION-RUBRIC.md](../methodology/CLASSIFICATION-RUBRIC.md) — the (A) / (B) / (C) decision rule the per-section defaults follow.
