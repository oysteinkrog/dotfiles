# idea-generator Subagent

**Role:** Phase 3a — broaden hypothesis generation by invoking `/idea-wizard` (if installed) for systematic idea-space exploration.

**Reads:** `intake/question_of_record.md`, the Proposer pane's preliminary slate.

**Writes:** additional `H-*` candidates suggested by `/idea-wizard`. Final filing of beads is by the Proposer pane (not this subagent) so the Proposer remains the owner.

**Operators favored:** ⊕ Cross-Domain (cross-field pattern matching), ⊙ Productive-Ignorance (when paired with first-principles framing).

**Hard constraints:**

1. Only invoke for non-productive-ignorance Proposer panes. The ignorance pane reasons from first principles, not from breadth-generation tools.
2. Each idea-wizard suggestion must be transformed into a Brenner-style H bead schema (claim, mechanism, falsifier, expected_evidence, category, origin) by the Proposer pane before filing.
3. Do NOT auto-file beads from idea-wizard output. Brenner H beads have stricter invariants than idea-wizard's general "ideas".

---

## Procedure

**Step 1 — Verify /idea-wizard installed.**

Per `phase0_skill_inventory.json`. If missing → output skip note and exit.

**Step 2 — Invoke /idea-wizard.**

```
Skill({
  skill: "idea-wizard",
  args: "Generate hypothesis candidates for question: <QUESTION_OF_RECORD>. Apply ⊕ Cross-Domain pattern matching — surface candidates from adjacent fields. Output ≥10 distinct candidates with rationale per candidate."
})
```

**Step 3 — Filter for falsifiability.**

For each idea-wizard candidate:

- Can it be expressed as a claim with an observable falsifier? If no → discard.
- Can `expected_evidence` be specified? If no → discard.

Discarded candidates are not files; they're filtered out.

**Step 4 — Hand survivors to Proposer pane.**

Output a list of survivors with rationale. The Proposer pane (running MO-03a-propose.md) receives this list and:

- Selects 2–5 of strongest survivors.
- Refines into Brenner H bead schema (adds mechanism, category, origin, confidence).
- Files via `br create`.

**Step 5 — Output summary.**

```
idea-generator subagent summary:

/idea-wizard invoked: <yes | no — reason>
Candidates returned: N
Survivors after falsifiability filter: M
Survivors handed to Proposer pane <PANE_N>: <list>

Recommended priority for Proposer:
1. <candidate 1> — <rationale>
2. <candidate 2> — <rationale>
3. <candidate 3> — <rationale>
```

---

## When /idea-wizard is unavailable

Proposer pane proceeds without breadth-augmentation. The pane's hypothesis generation is narrower but methodologically sound.

Phase 10 drift-check should note "idea-wizard not invoked" so the next session can install it if breadth was a concern.
