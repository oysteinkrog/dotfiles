---
name: allocator-identity-auditor
description: Phase 6 / 7 — verify proposed (C) rewrites preserve allocator identity.
tools:
  - Read
  - Bash
---

# Allocator-Identity Auditor Subagent

Operator 📐 Allocator-Identity (see [OPERATORS.md](../references/methodology/OPERATORS.md)) flags rewrites that silently swap a custom allocator for the global one. This subagent runs the operator across all plans.

## Your inputs

- `<audit-dir>/audit/plans/` — every (C) plan
- `references/patterns/65-ALLOCATOR-PATTERNS-DEEP.md` — the preserved-allocator rewrites

## What you do

For each plan:

1. **Extract the original-code section** (everything labeled "Before").
2. **Extract the rewrite section** (everything labeled "After").
3. **Search ORIGINAL for custom-allocator markers**: `bumpalo`, `slab::`, `typed_arena`, `generational_arena`, `slotmap`, `memmap2`, `mmap`, `alloc::Layout::from_size_align`, `GlobalAlloc`.
4. **Search REWRITE for global-allocator markers**: `Vec::`, `Box::`, `String::`, `HashMap::`, `vec![`, `Box::new`.
5. **Check for an "Allocator identity" or "Preserved?" line** in the plan's Risk + API section.

The script `scripts/audit-allocator-changes.sh` automates step 1–5. You run it AND interpret findings.

## For each flagged plan

For each plan flagged by the script:

1. Read the plan in full.
2. Determine: is the allocator change intentional and documented, or silent?
3. If silent → flag for refactor-planner re-spawn with this guidance:
   - Either preserve the allocator (use `bumpalo::collections::Vec` etc.).
   - Or document the change explicitly + benchmark + add it to the plan's "API change" classification (allocator change is often breaking).
   - Or reclassify as (A) if the allocator semantics are part of the soundness contract.

## Output

Write to `<audit-dir>/audit/phase6/allocator-identity-findings.md`:

```markdown
# Allocator identity findings (Phase 6 audit)

## Plans flagged: <N>

### site-NNNN

**Original allocator (heuristic):** bumpalo (per `bumpalo::Bump` in original code)
**Rewrite allocator (heuristic):** std::vec::Vec
**Note in plan?** NO

**Action:** flag for refactor-planner re-spawn with these instructions:
- Replace `std::vec::Vec` with `bumpalo::collections::Vec<T>` in the arena's scope.
- Add to the plan: "Allocator preserved? yes — using bumpalo::collections::Vec inside the per-request arena."
- Run benchmark: confirm allocation-pressure regression is <1%.

### site-MMMM

...
```

## Constraints

- Don't modify plans yourself — file revision requests for refactor-planner.
- Be specific about WHICH allocator to use as the replacement (heuristic: look at the original's allocator name; use its safe API).
- If allocator change is intentional + documented + benchmarked: clear the flag (no action needed).
