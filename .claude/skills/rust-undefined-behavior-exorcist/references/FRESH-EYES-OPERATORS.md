# Fresh-Eyes Operators — Canonical Rituals (Cass-Anchored)

The user's fresh-eyes review is a calibrated ritual. The exact wording is captured in cass and recurs across ≥6 sessions. The skill must use these prompts **verbatim**.

Anchors: cass Q-201 (long form), Q-202 (short form), Q-203 (multi-repo triage), Q-204 (frankensqlite time-travel), Q-205 (frankensearch TOCTOU), Q-206 (AGENTS.md readback as prefix).

---

## Operator ↻A — Reread AGENTS.md

**Trigger:** Mandatory prefix before any audit/fresh-eyes pass. Not optional.

**Prompt (verbatim):**
> Reread AGENTS dot md so it's still fresh in your mind.

(or the longer form: "Reread AGENTS.md so it's still fresh in your mind. proceed.")

**Why it matters:** The codebase's project-specific constraints in AGENTS.md (no destructive commands, no file deletion, multi-agent concurrent edits, etc.) must be loaded into the agent's working context *before* the audit. Skipping this leads to remediations that violate the project's invariants.

**When:** As the first sentence of every:
- Fresh-eyes review pass (Phase 10)
- Long-running session resume after compaction
- Bead-author polish round (Phase 9)
- Spot-audit invocation

**Exit:** The agent has acknowledged the AGENTS.md content. If the agent skips this, the orchestrator re-prompts.

---

## Operator 👁L — Fresh-Eyes Audit (Long Form)

**Trigger:** Initial fresh-eyes pass on a codebase (not a follow-up). Phase 10 round 1.

**Prompt (verbatim from cass Q-201):**
> I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious bugs, problems, errors, issues, silly mistakes, etc. and then systematically and meticulously and intelligently correct them. Be sure to comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in the AGENTS.md file.

**Often reinforced with:**
> YOU MUST FIX ALL BUGS

**Why this works:** The "random exploration + import-graph trace" preamble forces the agent to build a mental model before the audit, which catches structural inconsistencies (the float-mod-vs-int-mod bug in frankensqlite was caught by tracing VDBE → MVCC and noticing the same shape twice).

**Exit:** Agent has produced a list of findings; for each, either (a) fixed in place, or (b) filed as F-NNN for Phase 8 design.

---

## Operator 👁S — Fresh-Eyes Audit (Short Form)

**Trigger:** Follow-up fresh-eyes pass after a recent change. Phase 10 rounds 2+.

**Prompt (verbatim from cass Q-202, Q-203, Q-204):**
> great, now I want you to carefully read over all of the new code you just wrote and other existing code you just modified with 'fresh eyes' looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover.

**Pair with ↻A:**
> Reread AGENTS.md so it's still fresh in your mind. proceed.
> great, now I want you to carefully read over all of the new code you just wrote and other existing code you just modified with 'fresh eyes' looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover.

**Why this works (and why short form):** When the agent has just made changes, the long form's "random exploration" wastes a turn. The short form anchors on "the new code you just wrote and other existing code you just modified" — narrower scope, faster turn.

**Exit:** Same as long form.

---

## Operator 👁X — Fresh-Eyes Audit (Cross-Cluster Form)

**Trigger:** Phase 10 final-round review across N peer agents' contributions. Per cass Q-203 (multi-repo triage).

**Prompt (constructed from Q-203 evidence):**
> Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep!

**Why this works:** Phase 10's three-prompt structure (A/B/C from the documentation-website skill) maps to:
- A → 👁S (short form, "your own work")
- B → 👁L (long form, "trace through imports")
- C → 👁X (cross-cluster, "your fellow agents")

This is the natural composition order. Use all three in Phase 10.

**Exit:** All three prompts ran cleanly twice consecutively.

---

## Operator ⊕P — Parallel Per-Crate Subagent Dispatch

**Trigger:** Long-form fresh-eyes review on a workspace (P3 archetype). Per cass Q-201, Q-203.

**Prompt (constructed):**
> Spawn parallel subagents — one per crate in this workspace. Each subagent applies the fresh-eyes ritual to its own crate. Coordinate via Agent Mail thread `<run-id>-phase10-<crate>`. Collect findings; the main agent does final synthesis.

**Why this works:** A single agent fresh-eyeing a 50-crate workspace runs out of context. Per-crate parallel agents each fit comfortably. Cass Q-203 surfaced 7 different audit bugs across 7 repos in a single parallel dispatch.

**Exit:** All subagent findings consolidated in `phase10_fresh_eyes_log.md`.

---

## Operator composition — the canonical Phase 10 ritual

```
1. ↻A    — orchestrator: "Reread AGENTS.md so it's still fresh in your mind."
2. 👁L   — fresh-eyes long form (first pass)
3. ⊕P    — fan out parallel per-crate subagents (if P3 workspace)
4. ↻A    — re-prompt before round 2
5. 👁S   — fresh-eyes short form (second pass on the new edits)
6. 👁X   — fresh-eyes cross-cluster form (review the parallel agents' edits)
7. Loop steps 4–6 until two consecutive passes yield only trivial changes
8. Gate: cargo check + clippy + fmt + miri (on scratch implementations)
```

The user's cass corpus shows this exact 8-step sequence in Q-201..Q-206.

---

## Anti-patterns

| ✗ | Why |
|---|---|
| Skipping ↻A | AGENTS.md compliance is a frequent failure mode for unprompted agents |
| Paraphrasing 👁L | The "random exploration + import-graph trace" preamble is what catches the bugs short form misses; rewording loses the cue |
| Running 👁S without prior context | Short form assumes "the code you just wrote"; on a fresh agent this is empty |
| Running 👁X first | Cross-cluster review presupposes peer agents' work exists |
| One-shot fresh-eyes (no iteration) | The corpus shows the ritual is iterative; one pass misses cross-pollination findings |

---

## Cross-references

- [PHASES.md §Phase 10](PHASES.md#phase-10-fresh-eyes-review) — the Phase 10 spec
- [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md) — full operator catalogue
- [corpus/primary_sources/cass_quotes.md](../corpus/primary_sources/cass_quotes.md) — Q-201..Q-206 verbatim
