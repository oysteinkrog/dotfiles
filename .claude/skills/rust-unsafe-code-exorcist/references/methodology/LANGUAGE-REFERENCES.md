# LANGUAGE-REFERENCES.md — Citation Index for Soundness Justifications

A (A) classification's falsification block cites the Rust Reference / RFC / nomicon / specific issue. This file is the citation index — what to cite for each common invariant.

A citation that's just "see Rust docs" is too vague to survive Phase 6 adversarial review. Cite the section + URL anchor.

---

## Rust language references

| Resource | URL | When to cite |
|----------|-----|--------------|
| **Rust Reference — `unsafe` keyword** | https://doc.rust-lang.org/reference/unsafe-keyword.html | Any (A) justifying the use of `unsafe` |
| **Rust Reference — Behavior considered undefined** | https://doc.rust-lang.org/reference/behavior-considered-undefined.html | When invoking UB is the explicit concern |
| **Rust Reference — Types — Pointer types** | https://doc.rust-lang.org/reference/types/pointer.html | Raw pointer aliasing rules |
| **Rust Reference — Memory layout — Type layout** | https://doc.rust-lang.org/reference/type-layout.html | repr(C), repr(transparent), repr(packed) decisions |
| **Rust Reference — Inline assembly** | https://doc.rust-lang.org/reference/inline-assembly.html | `asm!` justifications |
| **Rust Nomicon** | https://doc.rust-lang.org/nomicon/ | Deeper UB / aliasing discussion |
| **Rust Nomicon — Aliasing** | https://doc.rust-lang.org/nomicon/aliasing.html | Stacked Borrows, Tree Borrows context |
| **Rust Nomicon — Subtyping** | https://doc.rust-lang.org/nomicon/subtyping.html | Lifetime variance arguments |
| **Rust Nomicon — Send and Sync** | https://doc.rust-lang.org/nomicon/send-and-sync.html | `unsafe impl Send/Sync` justifications |
| **Rust Nomicon — Drop check** | https://doc.rust-lang.org/nomicon/dropck.html | Drop-glue justifications |
| **Rust Nomicon — Coercions / Repr** | https://doc.rust-lang.org/nomicon/repr-rust.html | Layout / cast justifications |
| **Rust Nomicon — Casts** | https://doc.rust-lang.org/nomicon/casts.html | `as` cast soundness |
| **Rust Nomicon — Lifetime elision** | https://doc.rust-lang.org/nomicon/lifetime-elision.html | Inferred-lifetime arguments |
| **Rust Nomicon — Higher-rank trait bounds** | https://doc.rust-lang.org/nomicon/hrtb.html | HRTB-driven unsafe |

---

## Authoritative RFCs

The accepted RFCs that govern unsafe / sound code patterns:

| RFC | Topic | Cite when |
|-----|-------|-----------|
| [RFC 1191 Match Default Bindings](https://rust-lang.github.io/rfcs/2005-match-ergonomics.html) | Pattern binding modes | Pattern matching changes |
| [RFC 1444 Union](https://rust-lang.github.io/rfcs/1444-union.html) | `union` declarations | `union` field access soundness |
| [RFC 2008 Non-exhaustive enums](https://rust-lang.github.io/rfcs/2008-non-exhaustive.html) | `#[non_exhaustive]` | Adding variants without breaking sources |
| [RFC 2585 Unsafe blocks in unsafe fn](https://rust-lang.github.io/rfcs/2585-unsafe-block-in-unsafe-fn.html) | The 2024-edition unsafe-fn-body rule | Why unsafe blocks must still appear inside `unsafe fn` (in 2024 edition) |
| [RFC 3128 #[deprecated_safe]](https://rust-lang.github.io/rfcs/3128-io-safety.html) | I/O safety | `OwnedFd` / `BorrowedFd` |
| [RFC 3559 Strict Provenance](https://rust-lang.github.io/rfcs/3559-rust-has-provenance.html) | Pointer provenance model | Pointer-int casts |
| [RFC 3320 Specialization (subset)](https://rust-lang.github.io/rfcs/2451-re-rebalancing-coherence.html) | Coherence | trait coherence soundness |

---

## Per-pattern citations

### FFI / extern "C"

- **Cite:** Rust Reference § External blocks; Rust Reference § Behavior considered undefined § Unwinding through extern "C"; [RFC 2945 c-unwind](https://rust-lang.github.io/rfcs/2945-c-unwind-abi.html).
- **Key claim:** Rust unwinding through `extern "C"` is UB unless using `-C panic=abort` or the `extern "C-unwind"` ABI.

### `unsafe impl Send/Sync`

- **Cite:** Rust Nomicon § Send and Sync; std::marker docs for `Send` and `Sync`.
- **Key claim:** Implementer asserts thread-safety properties the compiler couldn't derive.

### `Pin::new_unchecked`

- **Cite:** std::pin docs ("Drop guarantee"); Rust Nomicon § Pin.
- **Key claim:** After being pinned, the value's memory address must not change until Drop.

### `MaybeUninit::assume_init`

- **Cite:** std::mem::MaybeUninit docs.
- **Key claim:** Must call after EVERY field is initialized; partial init is UB.

### `mem::transmute`

- **Cite:** std::mem::transmute docs; Rust Reference § Behavior considered undefined § Producing an invalid value.
- **Key claim:** Source and destination must have the same size; the resulting value must be a valid bit pattern for the destination type.

### `slice::get_unchecked`

- **Cite:** std::slice docs.
- **Key claim:** Index must be in-bounds; safety obligation transfers to caller.

### `core::hint::unreachable_unchecked`

- **Cite:** core::hint::unreachable_unchecked docs.
- **Key claim:** Reaching this is immediate UB; caller must prove unreachability.

### `core::intrinsics::*` (unstable)

- **Cite:** core::intrinsics docs + the specific intrinsic's docs.
- **Key claim:** Intrinsics are unstable; document the rustc version expected.

### `GlobalAlloc::alloc`

- **Cite:** std::alloc::GlobalAlloc docs.
- **Key claim:** Returned pointer must satisfy the requested layout; nullable on failure.

### Volatile MMIO

- **Cite:** core::ptr::read_volatile / write_volatile docs.
- **Key claim:** Volatile operations are NOT atomic; not synchronized with other threads; intended for memory-mapped I/O.

### `core::arch::asm!`

- **Cite:** Rust Reference § Inline assembly; target-arch-specific docs.
- **Key claim:** Asm clobbers must be exhaustive; flow-control through asm must match Rust expectations.

---

## Anti-citation patterns

- **"Per the Rust docs."** Too vague. Name the specific page + section.
- **"Per a StackOverflow answer."** SO answers are not authoritative; if a SO answer is helpful, find the underlying Reference / nomicon section it's citing.
- **"Per common knowledge."** Common knowledge has been wrong before. Find a citation.
- **"Per `rustc` source code."** Acceptable as a last resort when no documentation exists, but cite the specific file + commit hash.

---

## Citation format in (A) JUSTIFICATION blocks

The standard form:

> "This is unavoidable because [INVARIANT], per [CITATION URL or §section name]."

Example:

> "This is unavoidable because Rust unwinding through `extern "C"` is UB (per [Rust Reference § Behavior considered undefined § Unwinding](https://doc.rust-lang.org/reference/behavior-considered-undefined.html#out-of-scope), and per [RFC 2945 c-unwind](https://rust-lang.github.io/rfcs/2945-c-unwind-abi.html))."

The reviewer can click the citation and verify the claim in <30 seconds. That's the bar.

---

## Citation freshness

Rust references update. A 2-year-old citation might reference an URL that's moved. Before relying on a citation in a final audit summary:

1. Fetch the URL; verify it resolves.
2. Verify the relevant text is still there (Rust docs version-stamp; check the version tag).
3. If the citation has moved, update both the URL and the section-anchor.

The `validate-corpus.py` script (per `/operationalizing-expertise`) can be extended to validate URLs in citations; consider adding the check.
