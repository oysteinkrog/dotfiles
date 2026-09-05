---
name: static-bucket-sweeper
description: Owns one UB-taxonomy bucket end-to-end in Phase 2 — runs the bucket's static arsenal, drafts experiments. Parameterized by BUCKET.
---

# Static Bucket Sweeper

One per UB-taxonomy bucket. Reads Phase 1 inventory, runs the bucket's tooling, writes `phase2_findings_{BUCKET}.md`. **Invoke with `subagent_type=general-purpose`** (the sweeper writes the findings file; `Explore` would silently drop it).

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{BUCKET}` — one of: aliasing, provenance, alignment, validity, uninit, type-punning, data-races, send-sync, pin, ffi, panic-safety, std-trait-invariants, refcount, const-mutation, lifetime-escape

## Workflow
Use [Phase 2 prompt](../references/AGENT-PROMPTS.md#phase-2--static-bucket-sweeper-one-per-ub-taxonomy-bucket) verbatim. See [UB-TAXONOMY.md §{BUCKET}](../references/UB-TAXONOMY.md) for the bucket's specific arsenal.

## Outputs
- `{WORKSPACE}/phase2_findings_{BUCKET}.md` — one or more `## F-NNN` blocks, or a single "N/A; no sites in this project" line.

## Tooling cheat sheet by bucket

| Bucket | Primary tools |
|---|---|
| aliasing | ast-grep, syn-walker `aliasing.rs`, clippy `cast_ref_to_mut` / `invalid_reference_casting` |
| provenance | ast-grep `provenance-int-cast.yml`, clippy `cast_ptr_alignment` / `ptr_as_ptr` |
| alignment | ast-grep `repr-packed-field-ref.yml`, clippy `unaligned_references` |
| validity | syn-walker `validity.rs`, clippy `uninit_assumed_init` / `transmute_int_to_bool` |
| uninit | ast-grep `maybeuninit-assume-init.yml` |
| type-punning | syn-walker `transmute_pairs.rs`, clippy `transmute_undefined_repr` |
| data-races | syn-walker `data_races.rs` |
| send-sync | manual audit of every `unsafe impl (Send|Sync) for ...`; check synchronization story |
| pin | ast-grep `pin-new-unchecked.yml`, syn-walker `pin.rs` |
| ffi | rustc `-W improper_ctypes`, cross-ref to C headers, `static_assertions!` coverage |
| panic-safety | drop-impl audit; manual review of `mem::forget` / `ManuallyDrop` |
| std-trait-invariants | clippy `derive_ord_xor_partial_ord` / `derive_hash_xor_eq`; proptest harness for `Hash`+`Eq` |
| refcount | grep `(Arc|Box|Rc)::from_raw`; pair with `into_raw`/`forget` |
| const-mutation | ast-grep `const-to-mut-cast.yml`; clippy `invalid_reference_casting` |
| lifetime-escape | syn-walker `escape.rs` |

## Quality gates
- [ ] Every Phase-1 row tagged with this bucket is acknowledged (confirmed or downgraded)
- [ ] Every finding has a severity, static evidence, draft experiment
- [ ] No row block without a `Cross-refs` field

## Failure modes
- **Empty findings file with no "N/A" line:** ambiguous; redo
- **Severity inflation:** marking everything MUST-BE-UB. Use the bucket's calibration (see [UB-TAXONOMY.md §Severity Calibration](../references/UB-TAXONOMY.md#bucket-severity-calibration))

## Coordination
Reservation: none (read-only).
Mail thread: `ub-exorcism-{RUN_ID}-phase2-{BUCKET}`.
