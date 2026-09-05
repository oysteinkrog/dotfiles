# site-NNNN — <one-line summary>

**Inventory row.** `unsafe-inventory.jsonl#NNNN`
**File.** `<crate>/src/path/file.rs:<line_start>-<line_end>`
**Kind.** `block | unsafe_fn | unsafe_impl | unsafe_trait | extern_block | asm`
**Enclosing.** `fn <name>` (or `impl <T>`, `type <T>`, or top-level)
**Public-API exposure.** `<yes — reached from <pub item> | no>`
**Macro origin.** `<no | yes, expanded from <macro source>>`

## Source excerpt

```rust
<verbatim source, with context, ~20 lines>
```

## 1. What does this `unsafe` do?

<1 paragraph, plain language. Describe the operation, not the syntax.>

## 2. Invariants

This `unsafe` is sound IFF:
- <invariant 1>
- <invariant 2>
- <invariant 3>

Cited line(s) where each invariant is established:
- <invariant 1>: `<file>:<line>` — `<short reason>`
- <invariant 2>: `<file>:<line>` — `<short reason>`

## 3. Data provenance

Where does the input data come from?
- <caller / kernel / FFI peer / allocator / etc.>

What type of value is being trusted?
- <raw pointer from FFI; pointer from Box::into_raw; etc.>

## 4. Co-aliasing

Who else touches the same memory or atomic?
- <file>:<line> — <how>
- <file>:<line> — <how>

## 5. SAFETY comment audit

Existing SAFETY comment (verbatim):
```
<existing comment, or "(none)">
```

Trace the call graph today. Is the claim still true?
- <yes — confirmed at <file>:<line>>
- <no — <changed how>>

## 6. Panic-in-Drop trace

If `panic!()` unwinds through this block:
- Resources allocated NOT released by destructor: <list, or "none">
- Type's `Drop` impl invariants after partial init: <state>
- Held locks on unwind: <list, or "none">

## 7. Async cancellation trace (if reachable from async fn)

For each `.await` reachable from this site, dropping the future at that point leaves:
- <await point>: <state>
- <await point>: <state>

Pin / move-after-pin hazards: <list, or "none">

## 8. FFI boundary (if FFI)

See `references/patterns/60-FFI-PATTERNS.md` § contract template.

- C side promises: <list>
- Rust side promises: <list>
- Ownership of returned values: <description>
- Errors: <how conveyed, errno or out-param>
- Panicking: <can the C side panic / abort / longjmp?>
- Thread safety: <documented guarantee>
- Endianness / padding / ABI: <assumptions>

## Operator applications

| Operator | Applied? | Findings |
|----------|----------|----------|
| ⊙ Invariant-Locator | yes | <see §2> |
| ⊕ Reachability-From-Safe | <yes / N/A> | <see §3, §4> |
| ⌖ Macro-X-Ray | <yes / N/A> | <see "Macro origin" header> |
| 🔒 Panic-In-Drop-Trace | yes | <see §6> |
| 🔁 Async-Cancellation-Trace | <yes / N/A> | <see §7> |
| 🪟 FFI-Boundary-Contract | <yes / N/A> | <see §8> |
| ⚖ Send-Sync-Audit | <yes / N/A> | <if applicable> |

## Cross-references

- Cluster (if any): `audit/synthesis/refactor-clusters.md § <cluster-name>`
- Related sites (shared invariant): <site-NNNN, site-MMMM>
- Exemplar precedent: <E-NNN from EXEMPLAR-CATALOG.md, if applicable>

## Open questions

- <If anything in the write-up is uncertain — list here. Phase 3 picks these up.>
