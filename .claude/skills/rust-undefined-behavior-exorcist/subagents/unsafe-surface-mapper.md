---
name: unsafe-surface-mapper
description: Inventories every unsafe site in one module of a Rust project, tags each with UB-taxonomy bucket(s), and records SAFETY-comment status. Phase 1.
---

# Unsafe Surface Mapper

Owns the Phase 1 RECON pass for a single module. Output is read-only against the source code but **WRITES new files under `<workspace>/phase1_notes/`** — so the orchestrator MUST invoke this subagent with `subagent_type=general-purpose`. `Explore`-typed agents lack `Write`/`Edit` and will silently drop the per-module digest.

## Inputs at invocation
- `{WORKSPACE}` — absolute path to ub-exorcism workspace
- `{SOURCE_PATH}` — absolute path to the Rust project
- `{MODULE}` — module subpath (relative to SOURCE_PATH)
- `{RUN_ID}`

## Workflow
Use [Phase 1 prompt](../references/AGENT-PROMPTS.md#phase-1--unsafe-surface-mapper-per-module) verbatim.

## Outputs
- Append row block to `{WORKSPACE}/phase1_unsafe_surface_inventory.md`
- `{WORKSPACE}/phase1_notes/{MODULE}.md` — module digest

## Quality gates
- [ ] Every `unsafe` keyword in the module appears in the inventory (cross-check via `rg -c 'unsafe' --type rust {SOURCE_PATH}/{MODULE}/`)
- [ ] Every site has a UB-taxonomy bucket tag
- [ ] SAFETY-comment status is recorded for every `unsafe { ... }` block
- [ ] `cargo expand` was run; any macro-generated unsafe is flagged MACRO_GENERATED
- [ ] Module digest has all required headings

## Failure modes
- **Missing sites:** the unsafe-keyword count must equal the inventory row count (modulo macro-generated, which appears in expand only). If counts diverge, find the missing rows.
- **No expand run:** macro-generated unsafe slips past Phase 2 entirely. Always run `cargo expand`.
- **Vague bucket tag:** "Aliasing+Provenance+Alignment" without justification means the mapper didn't actually classify. Re-classify.

## Coordination
Reservation: none. Read-only against source.
Mail thread: `ub-exorcism-{RUN_ID}-phase1-{MODULE}`.

## Orchestrator invocation example

```python
# Right:
Agent(
    subagent_type="general-purpose",
    description=f"Phase 1 RECON: {MODULE}",
    prompt=<contents of AGENT-PROMPTS.md §Phase 1 with placeholders substituted>,
)

# Wrong (silently drops the per-module digest file):
Agent(
    subagent_type="Explore",   # ← Explore CANNOT call Write/Edit
    ...
)
```
