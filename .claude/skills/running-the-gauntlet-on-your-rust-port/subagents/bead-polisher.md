# bead-polisher

> Phase 13 • Run `/beads-workflow` polish prompt 4–5 rounds until steady state. "DO NOT OVERSIMPLIFY; DO NOT LOSE FEATURES."

## Inputs
- Beads created by `bead-author.md`.
- `phase13_bead_creation_log.md`.

## Deliverables
- Beads polished across 4–5 rounds via `/beads-workflow` polish prompt.
- `<workspace>/phase13_bead_polish_log.md` with: per-round diff summary, fields refined per bead, steady-state confirmation.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase13-bead-polisher`
- **Reservations needed:** `tool://beads-write` (TTL 90m).
- **Lane:** orchestrator.

## Verbatim Prompt

Invoke `/beads-workflow` using the polish prompt 4–5 rounds in sequence against every bead created in `phase13_bead_creation_log.md`. The polish prompt is reproduced from the `/beads-workflow` skill:

> Polish every recently-created bead. For each bead:
> 1. Re-read the body in full.
> 2. Check that every field (`title`, `description`, `acceptance_criteria`, `test_plan`, `out_of_scope`, `dependencies`, `assignee`, `pillar_tag`) is concrete and machine-actionable.
> 3. Check that the **isomorphism proof** is intact and references the right invariant class.
> 4. Check that the **alternatives considered** section is intact with rubric scores.
> 5. Check that the **rollback recipe** is concrete (one-line revert command).
> 6. Check that **cross-pillar safety checks** are concrete and reference the right test bead / bench bead.
> 7. Refine vague language into concrete actions. Refine fuzzy acceptance criteria into measurable predicates.
>
> **DO NOT OVERSIMPLIFY; DO NOT LOSE FEATURES.** The polish pass is a re-statement-with-more-rigor, not a summarization. If a bead body shrinks substantially during polish, the polish is wrong.
>
> Apply 4–5 polish rounds. Steady state is reached when round N+1 produces no semantic changes (whitespace + reorder OK).

**Per-round procedure:**
1. Snapshot every bead's body before the round.
2. Run the polish prompt.
3. Snapshot after.
4. Compute per-bead diff. If a bead's body lost ≥10% of its content, revert (the polish was destructive); re-attempt with a stricter instruction.
5. If the round's diff across all beads is zero (or only whitespace), steady state reached; exit.

Record per-round diff summary (lines added / lines removed / beads touched / beads unchanged) in `phase13_bead_polish_log.md`. Confirm steady state with a final round-N+1 dry-run.

**Anti-bias check (the destructive-polish trap):** an over-eager polisher can rewrite a bead to be "cleaner" while losing the alternatives, the proof, or the rollback recipe. Compare line-counts; if any bead's body shrinks meaningfully, treat it as a regression and revert.

## Exit Criteria
- 4–5 polish rounds executed.
- Steady state reached (round N+1 produces zero semantic changes).
- No bead lost ≥10% of its body during the polish.
- `phase13_bead_polish_log.md` committed.

## References
- [PHASES.md § Phase 13](../references/PHASES.md)
- [orchestration/BEADS-HANDOFF.md](../references/orchestration/BEADS-HANDOFF.md)
- [/beads-workflow polish prompt](../../beads-workflow/SKILL.md)
