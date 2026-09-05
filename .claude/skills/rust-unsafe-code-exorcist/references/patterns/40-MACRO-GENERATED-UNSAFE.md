# 40-MACRO-GENERATED-UNSAFE.md — Hidden Unsafe in Macro Output

The unsafe you can't see in source. `derive` macros, `macro_rules!`, and proc-macros all expand to code that may contain `unsafe { ... }` — and a source-text grep misses every one. This file is the protocol for surfacing and refactoring macro-generated unsafe.

---

## The X-ray pass (Phase 1)

`cargo expand` reveals macro expansion verbatim. The enumerator agent runs:

```bash
cargo expand --crate <crate-name> > <audit-dir>/phase1/<crate>__expand.rs
ast-grep run -l Rust -p 'unsafe $$$' <audit-dir>/phase1/<crate>__expand.rs --json \
  > <audit-dir>/phase1/<crate>__expand_unsafe.json
```

Expanded hits that do not correspond to a source-text occurrence become inventory rows with `macro_origin: true` and `macro_origin_path` pointing into the expand file. Source-authored unsafe repeated by `cargo expand` is consumed first so ordinary source sites are not double-counted; surplus identical expanded hits are still kept because they can be genuine macro-emitted unsafe.

If `cargo expand` errors (some unstable proc-macros struggle with current rustc), the fallback is `cargo rustc -- -Zunpretty=expanded` on nightly — same idea, less polished output.

---

## Common macro sources of unsafe

### `zerocopy-derive` (FromBytes, AsBytes, Unaligned)

```rust
#[derive(zerocopy::FromBytes, zerocopy::AsBytes, zerocopy::Unaligned)]
#[repr(C)]
struct Header {
    version: u32,
    flags: u32,
}
```

Expands to:

```rust
unsafe impl ::zerocopy::FromBytes for Header { ... }
unsafe impl ::zerocopy::AsBytes for Header { ... }
unsafe impl ::zerocopy::Unaligned for Header { ... }
```

**Audit position.** The `unsafe impl`s are sound IFF the struct's fields are all `FromBytes` / `AsBytes` / `Unaligned`. The derive macro checks this; the project trusts the derive. **(A) in zerocopy itself; the project's site is "via macro" and inherits the soundness.**

**Refactor opportunity.** If the project has HAND-WRITTEN `unsafe impl zerocopy::FromBytes for X` because of a derive-can't-handle-it edge case, check whether newer zerocopy versions cover it.

### `bytemuck-derive` (Pod, Zeroable)

```rust
#[derive(bytemuck::Pod, bytemuck::Zeroable)]
#[repr(transparent)]
struct Wrap(u64);
```

Similar pattern. `bytemuck`'s derive is more conservative than `zerocopy`'s but covers the common cases without unsafe at the call site.

**Audit position.** Inherits soundness from bytemuck. **(A) in bytemuck; project site (C)-equivalent.**

### `pin-project-lite` (pin_project!)

```rust
pin_project_lite::pin_project! {
    pub struct WsStream {
        #[pin] socket: TcpStream,
        buffer: Vec<u8>,
    }
}
```

Expands to:

```rust
pub struct WsStream { ... }
impl WsStream {
    fn project(self: ::core::pin::Pin<&mut Self>) -> WsStreamProj<'_> {
        unsafe {
            let this = self.get_unchecked_mut();
            WsStreamProj {
                socket: ::core::pin::Pin::new_unchecked(&mut this.socket),
                buffer: &mut this.buffer,
            }
        }
    }
}
```

**Audit position.** `pin-project-lite`'s expansion is sound IFF the field-by-field pin/!pin annotations are correct. The macro enforces this via trait bounds.

**Refactor opportunity.** Replace hand-written `unsafe impl Unpin` and manual pin-projections with `pin_project!`. See `references/patterns/80-PIN-PROJECTIONS.md`.

### `tokio::main`, `tokio::test`, `tokio::pin!`

`tokio::pin!` expands to:

```rust
let mut my_fut = my_fut;
// SAFETY: the pinned value is allocated on the stack here and never moved.
let my_fut = unsafe { ::std::pin::Pin::new_unchecked(&mut my_fut) };
```

**Audit position.** Sound by construction (stack-pinning is safe). **(A) in tokio; project site (C)-equivalent.**

### `bindgen`-generated code

When `bindgen` produces FFI bindings from C headers, every `extern "C"` block + every `repr(C)` struct with manual `FromBytes`-style impls comes through. The expand output may be tens of thousands of lines for a large C library.

**Audit position.** All (A) inherently. The audit's job is to check whether the project's call SITES wrap each binding in a safe Rust API.

### Custom proc-macros in the project

If the project has its own `*-derive` crate, the unsafe in the proc-macro's expansion needs the same audit as hand-written unsafe. Apply operators ⊙ Invariant-Locator and ⊕ Reachability-From-Safe to the expanded output. The audit may surface that a derive macro EMITS unsafe that the derive macro's author hadn't fully justified.

### Compiler-emitted derive output (rustc 1.97-nightly+)

Recent Rust nightlies emit `unsafe` blocks from built-in `#[derive(...)]` for several internal perf optimizations. These do NOT trip `#![forbid(unsafe_code)]` because the derive expansion is marked `#[allow_internal_unsafe]` by the compiler. They surface only in `cargo expand` output.

**Categories seen so far (rustc 1.97-nightly+):**

- `unsafe impl ::core::clone::TrivialClone for T {}` — emitted by `#[derive(Clone)]` on `Copy` types as a memcpy-optimization opt-in. The compiler emits this *only* when it has statically proven the type qualifies (sealed trait, automatic impl). One per `Copy + Clone` derive site, so the count scales with the size of the enum/struct catalog.
- `_ => unsafe { ::core::intrinsics::unreachable() }` — emitted in derived match arms (`Debug`, `Hash`, `PartialOrd`, etc.) where the compiler has proven the arm unreachable. Bounded by the number of derived match arms across the crate.

**Audit position.** Both are **(A) STRICTLY_UNAVOIDABLE** by definition: sound by construction (compiler-verified), and the only way to eliminate them is to drop the derive — typically not viable because the derived traits are required by serde / schemars / clap / etc.

**Worked example (beads_rust v0.2.10, run 2026-05-14):**

`cargo expand --lib` produced 261,511 lines. `grep -c '\bunsafe\b'` returned 103 occurrences:

| Category | Count | Origin |
|----------|------:|--------|
| `unsafe impl ::core::clone::TrivialClone for ...` | 88 | `#[derive(Clone)]` on `Copy` types |
| `unsafe { ::core::intrinsics::unreachable() }` | 6 | Derived match arms |
| Comment / string-literal hits ("Cannot repair: ... unsafe", etc.) | 9 | Source text, not unsafe declarations |

The project has `#![forbid(unsafe_code)]` and zero hand-written unsafe; `cargo check --all-features` passes clean.

**Verification harness coverage.** The bundled `assets/verify-forbid-soundness.sh.template` runs an accounting pass:

```bash
EXPAND_TRIVIAL=$(grep -cE 'unsafe impl ::core::clone::TrivialClone' "$EXPAND_OUT")
EXPAND_UNREACH=$(grep -cE 'unsafe \{ ::core::intrinsics::unreachable\(\) \}' "$EXPAND_OUT")
EXPAND_OTHER=$((EXPAND_UNSAFE - EXPAND_TRIVIAL - EXPAND_UNREACH))
# If $EXPAND_OTHER drifts above the project's baseline (typically 5-15 for comment/string hits),
# something new appeared. Investigate before merging.
```

This makes drift visible. A future rustc that adds a third compiler-emitted category will land in `OTHER` and trigger investigation — much better than a silent shift.

**When this matters.** Mostly informational. The cases where it DOES matter:

1. A reviewer who runs `cargo expand` themselves and sees the unsafe — the audit should acknowledge it up-front to avoid an "umm actually" exchange.
2. If MSRV is bumped past a rustc release that adds a new built-in derive emission, the `verify.sh` "other" budget needs recalibration.
3. If a project uses a custom proc-macro that emits unsafe with the SAME shape as one of these (e.g., a user-authored `impl ::core::clone::TrivialClone`), it WON'T be visible in the diff. Match on full path including `::core::` to distinguish.

---

## Clustering by macro source

Macro-generated unsafe often appears 100s of times — once per derive site. The inventory row count balloons unless you cluster.

Per Phase 3 synthesis:

```
Cluster M-001: zerocopy::FromBytes derive
  Member sites: site-0421, site-0422, ..., site-0517  (97 sites)
  Origin macro: zerocopy-derive @ 0.7.x
  Audit position: (A) inherited from zerocopy
  Refactor: NONE (zerocopy is the canonical safe-impl for this; don't reinvent)
  Hardening: ensure all #[derive(zerocopy::FromBytes)] structs have #[repr(C)] or #[repr(transparent)]
```

One cluster entry covers 97 sites. The plan document for the cluster lists every member site by ID; per-site write-ups can be skinny ("see cluster M-001").

---

## When a macro-generated unsafe is NOT inherited soundness

Some macros emit unsafe that the macro itself doesn't fully verify:

- A project's own custom derive that emits `transmute` without checking the layout.
- A `macro_rules!` macro that emits `unsafe { *p }` where `p` is a macro argument the macro doesn't bound.
- A proc-macro that emits `Box::from_raw` round-trips assuming a specific allocator.

For these, the audit must classify the macro EMISSION (the per-site unsafe), not just the macro itself. Operators apply per-site.

Example from a hypothetical project:

```rust
// src/parse.rs
let header = repr_cast!(buf, Header);   // custom macro

// src/macros.rs
macro_rules! repr_cast {
    ($buf:expr, $ty:ty) => {
        unsafe { &*($buf.as_ptr() as *const $ty) }
    }
}
```

The macro emits an unsafe at every call site that doesn't verify alignment or size. Audit position: every call site is a separate (C) — refactor to `zerocopy::Ref::new()` or similar.

---

## Refactoring macro-generated unsafe

### Pattern M-1: replace hand-written `unsafe impl FromBytes` with `derive`

If newer `zerocopy-derive` supports the type's shape (after a small refactor to make fields `Pod`-compatible), delete the hand impl and use the derive. Net: more sites but each inherited; geiger count up but all hidden behind audited macros.

### Pattern M-2: replace custom proc-macro with an audited equivalent crate

If the project's custom derive replicates what `zerocopy-derive` does, delete the custom derive. The migration is risky (deps churn) but the unsafe-audit win is large.

### Pattern M-3: replace `macro_rules!` `unsafe { transmute }` with a function

```rust
// Before
macro_rules! cast {
    ($x:expr, $ty:ty) => { unsafe { std::mem::transmute::<_, $ty>($x) } }
}

// After
fn cast<S, T>(x: S) -> T
where
    S: AsBytes,
    T: FromBytes,
    Sealed: AssertSameSize<S, T>,    // const-assert via type-level math
{
    // Safe via zerocopy
    let bytes = x.as_bytes();
    T::read_from(bytes).expect("size mismatch is a compile error via Sealed bound")
}
```

The function replacement adds compile-time checks the macro couldn't enforce. The (C) refactor is "swap the macro for a function with proper bounds."

---

## Anti-patterns

- **Ignoring `cargo expand` output.** The whole point of operator ⌖ Macro-X-Ray is to surface what source-text greps miss. Phase 1 must run cargo expand per crate.
- **Per-site write-ups for inherited-soundness macro sites.** If 100 sites all come from the same `zerocopy::FromBytes` derive, write a single cluster note, not 100 individual write-ups. Save the per-site format for sites with unique invariants.
- **Refactoring across crate boundaries.** If the macro is in a published crate, refactoring the EXPANSION isn't in your power; you can only refactor your USAGE of the macro (e.g., switch to a different derive crate).

---

## Acceptance signal

A macro-generated unsafe cluster passes when:

1. `cargo expand` output is captured in `phase1/<crate>__expand.rs`.
2. Every `unsafe` in the expand output is in the inventory (`macro_origin: true`).
3. The cluster note in `refactor-clusters.md` names the origin macro + audit position (inherited / custom).
4. For inherited-soundness clusters, no further action (a hardening note may apply).
5. For custom-emission clusters, every call site has a per-site classification (most will be (C) — swap for an audited equivalent).
