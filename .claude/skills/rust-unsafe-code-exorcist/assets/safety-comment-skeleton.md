# SAFETY-Comment Skeleton (for (A) Sites)

Paste at the unsafe site. Fill in every `<PLACEHOLDER>`. Read [00-CANONICAL-UNAVOIDABLE.md](../references/patterns/00-CANONICAL-UNAVOIDABLE.md), [CLIPPY-LINT-AUTHORING.md](../references/methodology/CLIPPY-LINT-AUTHORING.md), and [LANGUAGE-REFERENCES.md](../references/methodology/LANGUAGE-REFERENCES.md) first.

---

```rust
/// <PROSE — one paragraph describing what this unsafe operation does. Plain
/// language, no jargon. ~3-5 sentences.>
///
/// # Safety
///
/// The caller MUST guarantee:
///
/// - <SPECIFIC-INVARIANT-1 — testable; cite the validating fn if any>
/// - <SPECIFIC-INVARIANT-2>
/// - <SPECIFIC-INVARIANT-3>
///
/// These invariants are enforced by:
///
/// - <SPECIFIC-INVARIANT-1>: <file>:<line> (`<function-or-type-name>`).
/// - <SPECIFIC-INVARIANT-2>: <file>:<line> (`<function-or-type-name>`).
/// - <SPECIFIC-INVARIANT-3>: <file>:<line> (`<function-or-type-name>`).
///
/// What breaks if any invariant is violated:
///
/// - <SPECIFIC-UB-OUTCOME — e.g., "read past the mapped region; segfault on
///   most platforms; arbitrary read on x86_64 if the read lands in a mapped
///   page">.
///
/// Unwinding behavior:
///
/// - <Rust unwinding through this site is UB / safe under panic="abort" /
///   handled via std::panic::catch_unwind at <file>:<line>>.
///
/// Async cancellation behavior:
///
/// - <not reachable from async fn / fully cancellation-safe / handled via
///   a guard struct that restores invariants on drop>.
///
/// Allocator identity:
///
/// - <preserved (the allocation is in <named-allocator>) / N/A (no allocation)>.
///
/// Co-aliasing:
///
/// - <list of other sites that touch the same memory or atomic, by file:line>.
///
/// Reference (Rust language docs):
///
/// - <URL to Rust Reference / nomicon / RFC section that establishes this is
///   in fact unavoidable in current Rust>.
///
/// Reviewer attack surface:
///
/// - Strongest plausible attack: <one-sentence steel-man>.
/// - Response: <one-sentence rebuttal>.
unsafe fn or_block_or_impl(...) {
    // The unsafe operation goes here.
}
```

---

## Per-pattern customization

### FFI extern "C" call

Replace the body's "What breaks" with:

```
/// - The C side may write past the buffer (no length check on the C side).
/// - errno is thread-local and read after the call; do not interleave with
///   other libc calls before reading errno.
```

Add to "Unwinding":

```
/// - The C side does not unwind through Rust. Rust panics through this
///   call are UB. The wrapper is non-panicking by construction (no `?`,
///   no `unwrap`, no `expect` between the unsafe call and the return).
```

### `unsafe impl Send/Sync`

Place the SAFETY comment at the `unsafe impl` line, NOT at every method:

```rust
// SAFETY: <field-level audit per [50-SEND-SYNC-IMPLS.md]>.
unsafe impl Send for MyType { ... }
```

Body:

```
/// # Safety
///
/// `MyType` is Send because:
/// - field `a: Arc<Inner>` is Send (auto-derive).
/// - field `b: AtomicU32` is Send (auto-derive).
/// - field `c: *const Worker` is treated as a non-owning view; the pointed-to
///   `Worker` outlives the `MyType` via Arc<Worker> ownership held elsewhere.
///   This field's Send-ness is asserted here.
///
/// If a future field addition breaks any of the above (e.g., adding `Rc<X>`),
/// this impl becomes unsound. The clippy lint `mycrate::send-audit` catches
/// such additions.
```

### `Pin::new_unchecked`

Add:

```
/// # Safety
///
/// After construction (via `<Type>::open`), the value is wrapped in `Pin<Box<Self>>`
/// and never moved. The `<field>` at offset N remains at a stable address for the
/// lifetime of the value.
///
/// Moving a constructed `<Type>` would dangle `<field>` and cause UB. The type is
/// `!Unpin` (via `PhantomPinned`), so moves are statically prevented in any context
/// where the user holds `&mut <Type>` or pinned access.
```

### `MaybeUninit::assume_init`

Add:

```
/// # Safety
///
/// Every field of `<TargetType>` is initialized before this `assume_init` runs:
/// - `a` is initialized at <file>:<line>.
/// - `b` is initialized at <file>:<line>.
/// - `c` is initialized at <file>:<line>.
///
/// If a panic occurs after some fields are initialized but before all, the
/// guard struct `<GuardName>` runs `Drop` to release the partially-init memory.
```

### `core::hint::unreachable_unchecked`

Add:

```
/// # Safety
///
/// The exhaustiveness of the preceding match is proved by:
/// - The input is validated to be in <range> by <validating fn at file:line>.
/// - The match covers <enumerated values>.
///
/// Reaching this line means the validating function admitted an invalid input,
/// which would itself be a bug. The clippy lint <name> catches the addition of
/// new variants without updating the match.
```

---

## Anti-patterns in SAFETY comments

| ✗ | Why it fails | Fix |
|---|--------------|-----|
| "Safe because the caller knows what they're doing." | No invariant named; reviewer can't verify | Name the SPECIFIC invariant |
| "See the docs." | Citation missing | Cite the specific URL + section |
| "We've thought about this." | No proof obligation | Name what the caller must guarantee |
| "Performance reasons." | (A) requires soundness reason; perf is (B) | Reclassify as (B); use safe-only feature |
| Comment but no Rust Reference / nomicon URL | Lacks authoritative backing | Add URL; ensure it resolves |
| Generic "do not call this with bad input" | "Bad" is undefined | Define "bad" specifically (null pointer / out-of-bounds / non-aligned / etc.) |

---

## Per-comment checklist

When done filling in:

- [ ] Every `<PLACEHOLDER>` is replaced with concrete content (not "<TODO>" or "<FIXME>").
- [ ] At least one invariant is named with the form "caller must guarantee: <X>".
- [ ] Enforcement path cites file:line for each invariant.
- [ ] Specific UB outcome is named (segfault / read of invalid memory / etc.).
- [ ] Unwinding behavior is documented.
- [ ] Async cancellation behavior is documented (or N/A explicitly stated).
- [ ] Allocator identity is documented (or N/A explicitly stated).
- [ ] Rust Reference / nomicon URL is cited and resolves.
- [ ] Reviewer attack surface is steel-manned + rebutted.

If any item is missing, the comment is NOT hardened. Phase 7 fresh-eyes will flag it.
