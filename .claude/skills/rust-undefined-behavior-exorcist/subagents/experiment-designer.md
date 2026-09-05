---
name: experiment-designer
description: Designs falsifiable experiments for OPEN findings in Phase 4 (initial design) and Phase 6 (project-shaped techniques).
---

# Experiment Designer

**Invoke with `subagent_type=general-purpose`** — edits the experiment registry.

Authors entries in `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` for findings that don't yet have one, and for project-shaped UB techniques surfaced by `/idea-wizard` in Phase 6.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{TARGETS}` — list of `F-NNN` finding IDs or technique descriptions to convert

## Workflow

For each target:
1. Read the finding row (Phase 4) or technique description (Phase 6).
2. Identify the falsifiable claim ("This site UBs because X").
3. Design a minimal reproducer (≤30 lines).
4. Identify the tool whose signal will arbitrate.
5. State falsifiability — what would refute the claim.
6. Write the experiment block using the exact format from [EXPERIMENT-DESIGNS.md](../references/EXPERIMENT-DESIGNS.md).

For ambiguous targets, design *multiple* experiments, each isolating a different assumption (e.g., one for aliasing, one for provenance, even if both could explain the symptom).

## Outputs
- New `## EXP-NNN` blocks in `{WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md`
- Verdict initialized to `OPEN`

## Quality gates
- [ ] Every block has all 7 fields (Finding ref, Bucket, Severity, Hypothesis, Reproducer, Expected signal, Falsifiability, Invocation, Verdict)
- [ ] Reproducer is ≤30 lines
- [ ] Invocation is a single shell command that emits the verdict signal

## Failure modes
- **Non-falsifiable hypothesis:** the experiment "always confirms" — that's a demo, not a test. Re-design.
- **Reproducer pulls in the whole crate:** minimize harder
- **Vague expected signal:** name the specific Miri / TSan / loom diagnostic, not "an error"

## Coordination
Reservation: `path://{WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` exclusive, TTL 5min.
Mail thread: `ub-exorcism-{RUN_ID}-phase4-designs` (Phase 4) or `...-phase6-designs` (Phase 6).
