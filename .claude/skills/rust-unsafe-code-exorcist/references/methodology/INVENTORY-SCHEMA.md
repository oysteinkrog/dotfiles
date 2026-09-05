# INVENTORY-SCHEMA.md — `unsafe-inventory.jsonl` Canonical Schema

The single canonical artifact every audit produces. Every downstream tool — `compute-risk-score.mjs`, `generate-bead-graph.mjs`, third-party dashboards, custom linters — reads this file. This document is the contract.

Produced by Phase 1 (`scripts/enumerate-unsafe.sh` → `scripts/generate-inventory.mjs`). Consumed by Phase 2 (site-analyzer) onward.

---

## File format

One JSON object per line (JSONL). UTF-8. No trailing comma; no enclosing array. Standard `jq` reads it via `jq -c '.' < unsafe-inventory.jsonl`.

Sort order: by `crate` (alphabetical), then by `file` (alphabetical), then by `line_start` (ascending).

IDs are assigned post-sort, so `site-0001` is the first site by sort order across the entire workspace. IDs are stable as long as the source files don't change above the site — a new site added later in a file gets a new ID; sites above it keep theirs.

---

## Required fields (every row)

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | `site-NNNN` (4-digit zero-padded sequence). Stable post-Phase 1. The primary key. |
| `crate` | string | Cargo package name (from `cargo metadata`). Single-crate projects use the package name. |
| `file` | string | Source path relative to the project root. Forward slashes regardless of OS. For macro-origin-only rows with no source span, this is `phase1/<crate>__expand.rs`; use `macro_origin_path` for the exact line. |
| `line_start` | integer | First line of the site (1-indexed). |
| `line_end` | integer | Last line of the site (1-indexed). For single-line sites, equal to `line_start`. |
| `kind` | enum (see below) | What kind of unsafe construct this is. |
| `source_excerpt` | string | First 300 chars of the site's raw source. For long sites, truncated. |
| `geiger_count` | integer | Number of unsafe items in the site per cargo-geiger's accounting. Usually 1, occasionally >1 for complex blocks. |

## Required nullable fields (filled by Phase 2 site-analyzer)

These fields are present on every row but start as `null` until Phase 2 enriches them:

| Field | Type (post-fill) | Description |
|-------|------------------|-------------|
| `enclosing_fn` | string \| null | Name of the function containing the site, if any. `null` for sites at module scope (e.g., `unsafe impl` outside a fn). |
| `enclosing_type` | string \| null | Name of the type (`impl Foo { ... }`) containing the site, if any. |
| `public_api_exposed` | boolean \| null | True if the site is reachable from any `pub fn` in the rustdoc call graph. Phase 2 sets this from rustdoc JSON + call-graph extraction. |
| `rustdoc_anchor` | string \| null | `crate::path::to::item` reference, when applicable. Used for cross-referencing into rustdoc HTML. |

## Boolean signal flags (set by enumerator)

These flags are computed from the source excerpt without expensive analysis:

| Field | Type | Description |
|-------|------|-------------|
| `macro_origin` | boolean | True if the site was found in `cargo expand` output (i.e., emerged from a macro). |
| `macro_origin_path` | string \| null | If `macro_origin=true`, path into `phase1/<crate>__expand.rs` with line anchor. |
| `ffi` | boolean | True if `libc::` / `extern "C"` appears in the source excerpt. |
| `intrinsic` | boolean | True if `core::intrinsics` / `std::intrinsics` or unchecked `core::hint` / `std::hint` appears in the source excerpt. |

## Optional / late-filled fields

| Field | Type | Description |
|-------|------|-------------|
| `ubs_findings` | array of strings | UBS (Ultimate Bug Scanner) findings for this site's file. Populated when `ubs` is on PATH during enumeration. |

---

## `kind` enum

The exhaustive list of values `kind` may take. Each is produced by a specific ast-grep shape (or its ripgrep fallback) in `enumerate-unsafe.sh`. See that file's SHAPE_PATTERNS for the matching shapes.

| Kind | Meaning | Primary pattern bundle |
|------|---------|------------------------|
| `block` | A bare `unsafe { ... }` expression block. The most common kind. | varies by content |
| `unsafe_fn` | A function declared `unsafe fn ...`. Callers must satisfy the function's contract. | [60-FFI-PATTERNS.md](../patterns/60-FFI-PATTERNS.md) |
| `unsafe_impl` | An `unsafe impl Trait for Type`. Caller-supplied invariant for the trait. | [50-SEND-SYNC-IMPLS.md](../patterns/50-SEND-SYNC-IMPLS.md) |
| `unsafe_trait` | An `unsafe trait Trait { ... }`. Implementors uphold the trait's contract. | [50-SEND-SYNC-IMPLS.md](../patterns/50-SEND-SYNC-IMPLS.md) |
| `extern_block` | An `extern "C" { ... }` block (or other ABI). The FFI surface. | [60-FFI-PATTERNS.md](../patterns/60-FFI-PATTERNS.md) |
| `asm` | An inline assembly invocation (`core::arch::asm!`). | [55-EMBEDDED-PATTERNS.md](../patterns/55-EMBEDDED-PATTERNS.md), [00-CANONICAL-UNAVOIDABLE.md](../patterns/00-CANONICAL-UNAVOIDABLE.md) |
| `unsafe_cell_decl` | A `UnsafeCell::new(...)` or `UnsafeCell::<T>` construction. The legal interior-mutability primitive. | [27-UNSAFECELL-PATTERNS.md](../patterns/27-UNSAFECELL-PATTERNS.md) |
| `intrinsic_call` | A call to `core::intrinsics::*`, `core::hint::*_unchecked`, etc. Compiler-level primitives. | [25-INTRINSICS-AND-COMPILER-HINTS.md](../patterns/25-INTRINSICS-AND-COMPILER-HINTS.md) |
| `intrinsic_ptr` | A call to `core::ptr::read` / `write` / `copy` / `swap` / `drop_in_place` and variants. | [25-INTRINSICS-AND-COMPILER-HINTS.md](../patterns/25-INTRINSICS-AND-COMPILER-HINTS.md) |
| `raw_ptr_decl` | A `let p: *const T = ...` or `*mut T` declaration. The declaration itself is safe; flagged because the deref will likely be unsafe. | [10-POINTER-MIGRATIONS.md](../patterns/10-POINTER-MIGRATIONS.md) |
| `raw_ptr_cast` | An `expr as *const T` / `as *mut T` cast. Same rationale as `raw_ptr_decl`. | [10-POINTER-MIGRATIONS.md](../patterns/10-POINTER-MIGRATIONS.md) |

The `kind` field is exhaustive; downstream tools should treat unknown values as an enumerator-version mismatch and warn rather than crash.

---

## Example rows

```jsonl
{"id":"site-0001","crate":"frankenlibc","file":"src/syscall/mod.rs","line_start":142,"line_end":167,"kind":"block","enclosing_fn":"open_o_direct","enclosing_type":null,"public_api_exposed":true,"macro_origin":false,"macro_origin_path":null,"ffi":true,"intrinsic":false,"source_excerpt":"unsafe { libc::open(path.as_ptr(), libc::O_DIRECT | libc::O_RDWR) }","rustdoc_anchor":"frankenlibc::syscall::open_o_direct","geiger_count":1,"ubs_findings":[]}
{"id":"site-0002","crate":"frankenlibc","file":"src/syscall/mod.rs","line_start":201,"line_end":201,"kind":"raw_ptr_decl","enclosing_fn":"build_iovec","enclosing_type":null,"public_api_exposed":false,"macro_origin":false,"macro_origin_path":null,"ffi":false,"intrinsic":false,"source_excerpt":"let base: *const u8 = buffer.as_ptr();","rustdoc_anchor":null,"geiger_count":0,"ubs_findings":[]}
{"id":"site-0003","crate":"franken_engine","file":"src/sched/worker_park.rs","line_start":58,"line_end":58,"kind":"intrinsic_call","enclosing_fn":"park_unsynchronized","enclosing_type":"Worker","public_api_exposed":false,"macro_origin":false,"macro_origin_path":null,"ffi":false,"intrinsic":true,"source_excerpt":"unsafe { core::intrinsics::atomic_load_unsynchronized(&self.state) }","rustdoc_anchor":null,"geiger_count":1,"ubs_findings":[]}
{"id":"site-0004","crate":"my_lock","file":"src/spin.rs","line_start":12,"line_end":12,"kind":"unsafe_cell_decl","enclosing_fn":"new","enclosing_type":"SpinMutex","public_api_exposed":true,"macro_origin":false,"macro_origin_path":null,"ffi":false,"intrinsic":false,"source_excerpt":"data: UnsafeCell::new(value),","rustdoc_anchor":"my_lock::SpinMutex::new","geiger_count":0,"ubs_findings":[]}
```

Note that `unsafe_cell_decl` and `raw_ptr_decl` sites have `geiger_count: 0` because they don't themselves require `unsafe`. They're flagged as inventory rows because they're strong signals that an unsafe site exists nearby; the Phase 2 site-analyzer cross-references them with the surrounding code.

---

## How fields are filled (lifecycle)

| Phase | Tool | Sets |
|-------|------|------|
| 1 (enumerate) | `enumerate-unsafe.sh` | All ast-grep / ripgrep raw match data |
| 1 (normalize) | `generate-inventory.mjs` | `id`, `crate`, `file`, `line_start`, `line_end`, `kind`, `source_excerpt`, `geiger_count`, `macro_origin`, `macro_origin_path`, `ffi`, `intrinsic`, `ubs_findings` |
| 2 (analyze) | site-analyzer subagent | `enclosing_fn`, `enclosing_type`, `public_api_exposed`, `rustdoc_anchor` |
| 4 (classify) | classifier — does NOT modify the inventory; writes `audit/classification/site-NNNN.md` separately. | — |

The inventory is **immutable** after Phase 2. Classification and plans live in separate files keyed by `id`.

---

## Validation

`scripts/generate-inventory.mjs` enforces the schema on emit. To validate an existing inventory:

```bash
jq -c 'select(
  (.id // "") | test("^site-[0-9]{4}$") | not
)' < unsafe-inventory.jsonl
# Empty output = all IDs well-formed.

jq -r '.kind' < unsafe-inventory.jsonl | sort -u
# Verify only known enum values appear.
```

---

## Compatibility

Schema version is encoded implicitly via the skill's `CHANGELOG.md`. When adding a new `kind` or required field, bump the skill version and:

1. Update this document.
2. Update `enumerate-unsafe.sh` SHAPE_PATTERNS.
3. Update `generate-inventory.mjs` `classifyKind`.
4. Update `compute-risk-score.mjs` if the new kind affects scoring.
5. Update downstream consumers.

Breaking schema changes are rare; the audit's bias is to add fields (defaulting to `null`) rather than rename / remove existing ones.

---

## Cross-references

- [PHASES.md § Phase 1](PHASES.md) — when the inventory is produced.
- [CLASSIFICATION-RUBRIC.md](CLASSIFICATION-RUBRIC.md) — what happens to each row in Phase 4.
- [RISK-SCORING.md](RISK-SCORING.md) — how `kind` + `public_api_exposed` + bucket combine for risk.
- [25-INTRINSICS-AND-COMPILER-HINTS.md](../patterns/25-INTRINSICS-AND-COMPILER-HINTS.md), [27-UNSAFECELL-PATTERNS.md](../patterns/27-UNSAFECELL-PATTERNS.md) — pattern bundles for the new kinds.
