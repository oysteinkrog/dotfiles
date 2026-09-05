# pattern:220-BOUNDS-ELIDE-AS-CHUNKS

## What

Convert slice indexing in a parsing loop to a **const-array conversion** so the compiler can elide bounds-checks. Use `<[u8; N]>::try_from(slice)` (or, for chunked iteration, `slice.as_chunks::<N>()`) rather than `slice[i..i+N]` indexing or `chunks_exact()`. The key distinction: `as_chunks::<N>()` returns slices whose length is a compile-time constant, which the compiler can prove fits and skip the runtime bounds-check; `chunks_exact()` still emits per-element bounds-checks. Pair with `#[inline]` so the elision compounds across call sites.

## Why

> "Convert slice indexing to array conversion (`TryInto::<[u8; N]>` or `as_chunks::<N>`) to let compiler elide bounds-checks." — CC.md §57 (verbatim)

Failure mode prevented: *bounds-checks dominating a parsing loop*. The motivating case was `BtreePageHeader::parse`: a header layout with 8 fixed-size fields was being parsed with 8 separate `slice[i..i+N]` reads, each emitting a runtime length check. A profile showed the bounds-check instructions accounting for ≥1% MT8 inclusive self-time. Converting to a single `<[u8; HEADER_LEN]>::try_from(slice)` followed by direct array indexing collapsed all 8 checks into one.

## Where in FrankenSQLite

- `BtreePageHeader::parse` — 8 bounds-checks → 1 array conversion
- `read_cell_pointers` — same shape, −29%
- `write_cell_pointers` — same shape, −53%
- (Source under `crates/fsqlite-btree/src/`.)

## Verbatim shape

Before (8 runtime bounds-checks):

```rust
fn parse(buf: &[u8]) -> Result<BtreePageHeader> {
    let kind = buf[0];
    let first_free = u16::from_be_bytes([buf[1], buf[2]]);
    let cell_count = u16::from_be_bytes([buf[3], buf[4]]);
    let content_start = u16::from_be_bytes([buf[5], buf[6]]);
    let fragmented = buf[7];
    // ...
}
```

After (1 array conversion, zero bounds-checks in the body):

```rust
#[inline]
fn parse(buf: &[u8]) -> Result<BtreePageHeader> {
    let arr: &[u8; HEADER_LEN] = buf.get(..HEADER_LEN)
        .ok_or(Error::ShortBuffer)?
        .try_into()
        .unwrap();
    Ok(BtreePageHeader {
        kind:          arr[0],
        first_free:    u16::from_be_bytes([arr[1], arr[2]]),
        cell_count:    u16::from_be_bytes([arr[3], arr[4]]),
        content_start: u16::from_be_bytes([arr[5], arr[6]]),
        fragmented:    arr[7],
        // ...
    })
}
```

For chunked iteration:

```rust
// BEFORE: per-element bounds-check
for chunk in buf.chunks_exact(8) { ... }

// AFTER: chunk length is compile-time, no per-element check
let (chunks, _tail) = buf.as_chunks::<8>();
for chunk in chunks { ... }  // chunk: &[u8; 8]
```

## Measurement proof (verbatim)

| Site | Before | After | Speedup |
|---|---|---|---|
| `BtreePageHeader::parse` | 10.7 ns | 3.7 ns | **−65%, ~2.9x** |
| `read_cell_pointers` | — | — | **−29%** |
| `write_cell_pointers` | — | — | **−53%** |

The `#[inline]` annotation compounds across call sites — at one inlining level the elision is local, at deeper levels the compiler can fold the bounds-check into the caller's context and remove it entirely.

## Spot the shape

In an unfamiliar codebase:

1. A profile (samply / perf) showing a `parse` / `decode` / `read_*_header` function in the top 10 self-time frames.
2. `cargo asm` (or `cargo show-asm`) reveals `cmp` + `jae` / `panic_bounds_check` sequences in the function body — the bounds-check instructions.
3. The function reads from a slice using `[i..j]` indexing where `j - i` is a compile-time constant.
4. The function is small enough to inline.

If those four hold, the array-conversion rewrite is straightforward and almost always wins.

## Per-class transferability

| Class | Bounds-elide opportunity sites |
|---|---|
| **SQL** | B-tree page header parsing; WAL frame header parsing; varint decoding when length is known; row-format parsing |
| **RESP** | RESP frame parsing (length-prefixed); RDB header parsing; integer-format inline parsing; AOF frame parsing |
| **Numerical** | Strided slice reads of fixed-element-count vectors; NumPy `.npy` header parse; arrow IPC frame headers |
| **ML** | Tensor shape header parse; model checkpoint magic-number reads; safetensors header parse; ONNX proto frame parse |
| **HTTP** | Fixed-format HTTP/2 frame header (9 bytes); WebSocket frame header (2–14 bytes); TLS record header (5 bytes); MessagePack fixint reads |

## Composition

- Pairs with [pattern:200-HOT-OPCODE-PROMOTION](200-HOT-OPCODE-PROMOTION.md) — both reduce instruction count in inner loops; bounds-elide also enables more aggressive inlining.
- Pairs with [pattern:160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md) — the BtreePageHeader::parse win was attributed to MT8 self-time.
- Pairs with [pattern:250-ISOMORPHISM-PROOF](250-ISOMORPHISM-PROOF.md) — the rewrite is purely a representation change; behavior identical when the slice is long enough; the `Result<_, Error::ShortBuffer>` arm preserves the error case.
- Pairs with [pattern:140-RELEASE-PERF-PROFILE](140-RELEASE-PERF-PROFILE.md) — `release-perf` with `opt-level=3, lto="thin"` is required for the elision to compound; debug builds still bounds-check.

## Pitfalls

- **Using `chunks_exact()` instead of `as_chunks::<N>()`.** `chunks_exact()` returns `&[u8]` with unknown-at-compile-time length, so the compiler still bounds-checks each index. The subtlety is exactly what the optimization targets.
- **Calling `try_into()` without `#[inline]` on the parse function.** Without inlining, the conversion is opaque to the caller; the win is restricted to the function body only. `#[inline]` lets the elision propagate.
- **Using `.expect()` or `.unwrap()` instead of `?`.** Panicking on short buffer is a behavior change. The before code returned `Err`; the after code must too.
- **Reading past `HEADER_LEN` because someone added a field.** The fixed-size assumption is load-bearing. When the format extends, the array length and `HEADER_LEN` constant must move together; add a `static_assertions::assert_eq_size!` check.
- **Per-class trap (HTTP): HTTP/2 frame *payload* lengths are variable; only the *header* is fixed.** The optimization applies to the header only.
- **Per-class trap (Numerical): NumPy v1 vs v2 `.npy` headers have different magic-number positions.** Version-dispatch the parse before applying the optimization.
- **Forgetting that `try_into()` requires the slice be exactly the right length.** Use `buf.get(..HEADER_LEN)` first to slice it, then `try_into()`; otherwise `try_from(&[u8])` returns `Err` for slices longer than N.
