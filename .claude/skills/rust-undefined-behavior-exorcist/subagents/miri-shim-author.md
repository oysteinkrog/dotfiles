---
name: miri-shim-author
description: Authors `#[cfg(miri)]` shims for FFI calls Miri cannot execute. Phase 3 helper that unblocks Miri runs.
---

# Miri Shim Author

**Invoke with `subagent_type=general-purpose`** — authors `src/miri_shims.rs` and notes file.

When Phase 3's miri-runner reports `unsupported operation: can't call foreign function X`, this subagent authors the appropriate `#[cfg(miri)]` shim per [MIRI-SHIMS.md](../references/MIRI-SHIMS.md).

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{UNSUPPORTED_CALLS}` — list of `(call_name, file:line)` from Miri's output

## Workflow
1. For each unsupported call, classify into shim category S1–S9 (see MIRI-SHIMS.md)
2. Author the shim in `crates/<proj>/src/miri_shims.rs` (create if missing)
3. Re-route the call site:
   ```rust
   #[cfg(miri)] use crate::miri_shims as os;
   #[cfg(not(miri))] use libc as os;
   ```
4. Verify the shim *exercises* the aliasing contract (writes through dst when memcpy, reads source bytes, etc.) — a no-op shim is wrong
5. Re-run Miri to confirm progress
6. Document the shim's fidelity gap in `phase3_raw/miri_shim_notes.md`

## Outputs
- `<source>/src/miri_shims.rs` (new or amended)
- `phase3_raw/miri_shim_notes.md` documenting fidelity gaps

## Quality gates
- [ ] Each shim is at least as strict as the real call (no softer aliasing model)
- [ ] Shim exercises every pointer parameter through the abstract machine
- [ ] Fidelity gap documented: what the shim does NOT model (multi-process visibility, signal delivery, etc.)
- [ ] Re-routing uses `#[cfg(miri)]` consistently — no production overhead

## Failure modes
- **Shim too strict** — Miri fails on perfectly sound code; relax the shim's preconditions
- **Shim too lax** — Miri-clean while real call would aliased-write; tighten
- **Missing allocator side-table** — `free` shim doesn't know the layout; add the side-table pattern from MIRI-SHIMS.md §S4

## Coordination
Reservation: `path://<source>/src/miri_shims.rs` exclusive while editing.
Mail thread: `ub-exorcism-{RUN_ID}-miri-shims`.

## References
- [MIRI-SHIMS.md](../references/MIRI-SHIMS.md) — shim catalogue with S1–S9 patterns
- [TOOLING.md §Miri](../references/TOOLING.md) — broader Miri context
