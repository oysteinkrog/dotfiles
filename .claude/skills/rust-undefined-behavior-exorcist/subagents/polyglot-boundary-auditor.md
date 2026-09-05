---
name: polyglot-boundary-auditor
description: Audits Rust↔C/C++/Python/JS boundaries for cross-language UB. Specialized FFI subagent invoked when bucket #10 is project-relevant.
---

# Polyglot Boundary Auditor

**Invoke with `subagent_type=general-purpose`** — writes audit findings files.

Standard bucket sweepers handle pure-Rust UB. The polyglot-boundary-auditor specializes in the *boundary* between Rust and a foreign runtime, where neither side's tooling alone catches the UB.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{FOREIGN_LANG}` — `c | cpp | python | js | go | lua`
- `{BOUNDARY_MODULES}` — Rust module paths where `extern "C"` / `pyo3` / `wasm-bindgen` / `cxx` lives

## Workflow

Per [POLYGLOT.md](../references/POLYGLOT.md), for each boundary:

1. **Identify every `extern "<abi>"` block** — `extern "C"`, `extern "C-unwind"`, `extern "system"`, etc.
2. **For each foreign function called from Rust:**
   - Read the foreign-side documentation / header
   - Cross-reference the Rust binding's types against the foreign declaration
   - Run `static_assertions!` for `size_of` + `align_of` + per-field `offset_of`
   - Note the aliasing contract: can the foreign side mutate during the call? Fire callbacks?
3. **For each Rust function called from the foreign side** (`#[no_mangle] pub extern "C" fn ...`):
   - Document the caller's contract (NUL-terminated string? non-null pointer? aligned?)
   - Wrap the contract in safe-rust at the entry: `let s = unsafe { CStr::from_ptr(p).to_str()? };`
4. **Cross-language allocator pairing:**
   - Every Rust `Box::from_raw(p)` — verify `p` came from `Box::into_raw`, not foreign allocator
   - Every foreign-allocated pointer Rust frees — wrap with the foreign deallocator
5. **Callback aliasing:**
   - Foreign side fires Rust callback → can Rust be mid-borrow at that moment?
   - Document the cancellation/concurrency assumption
6. **File findings:**
   - Each unverified contract → `F-NNN` with bucket #10 (FFI) or #21 (FFI callback)
   - Each layout mismatch → `F-NNN` with bucket #3 (alignment) or #22 (repr packed)

## Outputs
- `{WORKSPACE}/phase2_findings_polyglot_{FOREIGN_LANG}.md` — boundary-specific findings
- For each `extern "C"` block: a section in the workspace digest noting whether the boundary contract is verified

## Quality gates
- [ ] Every `extern "<abi>"` block in `{BOUNDARY_MODULES}` reviewed
- [ ] Every Rust→foreign call has documented preconditions
- [ ] Every foreign→Rust callback has documented aliasing/concurrency assumption
- [ ] `static_assertions!` cover every `#[repr(C)]` type's size + align + field offsets
- [ ] No `Box::from_raw` site uses a pointer from a non-Rust allocator

## Failure modes
- **Foreign header unavailable** — note explicitly; treat the boundary as `CONTRACTUAL-BUT-DEFENSIBLE` pending header acquisition
- **`bindgen`-generated declarations diverge from current header** — regenerate; diff; treat divergence as a finding
- **Callback called from signal handler** — Rust borrow rules don't survive signal context; refactor to atomic + queue

## Coordination
Mail thread: `ub-exorcism-{RUN_ID}-polyglot-{FOREIGN_LANG}`.

## References
- [POLYGLOT.md](../references/POLYGLOT.md) — per-language boundary patterns
- [UB-TAXONOMY.md §10, §21, §22](../references/UB-TAXONOMY.md) — relevant buckets
- [PROJECT-TYPES.md §P7 FFI Binding](../references/PROJECT-TYPES.md) — archetype priors
