# Drift Auditor Subagent

**Role:** Phase 10 methodology drift check.
**MUST be a fresh agent.** NOT one of the original swarm panes (per AP-O11). Use a `general-purpose` Agent or `/idea-wizard` Agent dispatched from outside the brennerbot session.

**Reads:**
- `<workspace>/.brenner_workspace/phase0_scope_decision.md`
- `<workspace>/.brenner_workspace/phase_*_complete.flag` (timestamps)
- `<workspace>/session-logs/round-*.md`
- `<workspace>/session-logs/dispatch-*.log`
- `<workspace>/deliverables/RESUME.md`
- `<workspace>/deliverables/HANDBACK.md`
- All beads via `br list --json`
- This skill's `references/DRIFT-RUBRIC.md`, `references/OPERATORS.md`, `references/PHASES.md`

**Writes:**
- `<workspace>/deliverables/DRIFT-CHECK.md`
- ≥1 update to this skill's `references/` directory (lessons fed back)

**Operators favored:** ∿ Dephase, ◊ Paradox-Hunt (between trajectory and method).

**Anti-patterns to watch for:**
- Treating "we couldn't" as automatic improvement (apply Replacement Test strictly)
- Citing without `§`-anchors to canonical Brenner sources
- Skipping the lessons step (F-1003 hard invariant)
- Forming domain opinions on the question of record (drift check is methodology-level)

**Procedure:** see [`assets/marching-orders/MO-10-drift-check.md`](../assets/marching-orders/MO-10-drift-check.md) for the full rubric-walkthrough.

---

## How operator dispatches this

Operator does NOT dispatch via `ntm send`. Use the Agent tool:

```
Agent({
  description: "Brennerbot drift check",
  subagent_type: "general-purpose",
  prompt: "<contents of MO-10-drift-check.md, with <WORKSPACE_PATH> filled in>"
})
```

Or via `/idea-wizard` if the methodology suggests new operators worth proposing.

The agent runs to completion, writes `DRIFT-CHECK.md`, and returns a summary. Operator commits the lessons updates.

---

## Quality bar for the drift check

A drift check is *good* when it:

1. Cites specific `§`-anchors from the Brenner corpus for every operator verdict.
2. Names the F-### code for every regression.
3. Provides a number-bearing metric for every claimed improvement.
4. Updates ≥1 `references/` file with a concrete lesson.
5. Verdict at the top is one of {convergent, divergent-improvement, divergent-regression, mixed}.

If any of (1)–(5) is missing, the audit is itself drift-checkable.
