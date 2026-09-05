---
name: shape-sweeper
description: When a UB shape is found at one site, scans for all same-shape sites across the codebase. Phase 8 helper invoked before remediation design.
---

# Shape Sweeper

**Invoke with `subagent_type=general-purpose`** — writes `phase2_shape_sweep_*.md` and appends F-NNN-a/-b siblings.

The user's recurring practice is to fix UB pattern X at one site AND immediately sweep for all same-shape sites in the same commit. This subagent automates the sweep.

Anchors: cass Q-801, Q-802 — float-modulo bug found in two code paths in the same fresh-eyes pass.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{FINDING_ID}` — F-NNN that surfaced the original site
- `{SHAPE_PATTERN}` — ast-grep pattern OR rg literal OR semgrep rule

## Workflow

Per [SHAPE-SWEEP.md](../references/SHAPE-SWEEP.md):

1. Read F-NNN; identify the shape's syntactic + semantic pattern
2. Choose the right tool:
   - Lexical shape (literal substring) → `rg`
   - Syntactic shape (Rust AST node pattern) → `ast-grep`
   - Dataflow shape (cross-function reasoning) → `semgrep`
   - Type-level shape (e.g., zero-validity) → syn-walker
3. Run the sweep:
   ```bash
   ast-grep run -l Rust -p '<pattern>' {SOURCE_PATH}
   # OR: rg -n '<pattern>' --type rust {SOURCE_PATH}
   # OR: semgrep --config=<rule> {SOURCE_PATH}
   ```
4. For each hit, classify:
   - **Same intent, same bug** → file as `F-NNN-a`, `F-NNN-b`, ... (siblings)
   - **Same syntax, different intent** → record as "intentionally different — <reason>"
   - **Already-fixed variant** → record as "previously fixed at <commit>"
5. Output the sweep findings to `{WORKSPACE}/phase2_shape_sweep_{F-NNN}.md`
6. Add `[ancillary]` beads to the parent remediation epic (per UB-BEAD-LADDER.md)

## Outputs
- `{WORKSPACE}/phase2_shape_sweep_{F-NNN}.md` — sweep results table
- Sibling findings F-NNN-a, F-NNN-b, ... appended to `phase4_unified_findings.md`
- `[ancillary]` bead requests for `bead-author` to file in Phase 9

## Quality gates
- [ ] At least one sweep tool was used (rg / ast-grep / semgrep / syn-walker)
- [ ] Every hit is classified (same-bug / intentional-different / already-fixed)
- [ ] Sibling F-IDs use the `-a / -b` suffix convention
- [ ] All same-bug siblings are batched into the same remediation epic

## Failure modes
- **Pattern too narrow** — misses obvious siblings; iterate broader
- **Pattern too broad** — flags many unrelated sites; iterate narrower
- **Pattern caught in tests** — flag sites in `src/` separately from `tests/`; `tests/` may legitimately exercise the shape

## Coordination
Mail thread: `ub-exorcism-{RUN_ID}-shape-sweep-{F-NNN}`.

## References
- [SHAPE-SWEEP.md](../references/SHAPE-SWEEP.md) — methodology
- [HIDDEN-BARRIERS.md](../references/HIDDEN-BARRIERS.md) — pattern catalog
- [UB-BEAD-LADDER.md](../references/UB-BEAD-LADDER.md) — execution form
