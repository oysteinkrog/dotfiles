# subagent: agent-ergo-grader (Phase 6)

**Description.** Apply the existing [agent-ergonomics-and-intuitiveness-maximization-for-cli-tools](../../agent-ergonomics-and-intuitiveness-maximization-for-cli-tools/SKILL.md) skill as a reference rubric to grade the new `<tool> doctor` surface across its 11 dimensions.

## Inputs

- `{{target}}` — target repo (with the new doctor implemented)
- `../../agent-ergonomics-and-intuitiveness-maximization-for-cli-tools/SKILL.md` — the reference rubric
- `../../agent-ergonomics-and-intuitiveness-maximization-for-cli-tools/references/rubric/SCORING-RUBRIC.md`

## Outputs

- `{{workspace}}/agent_ergo_grade.md` — per-surface × per-dimension scores against the agent-ergonomics rubric
- `{{workspace}}/agent_ergo_recommendations.jsonl` — ranked recommendations

## Prompt

```
You are the agent-ergonomics grader. The new `<tool> doctor` surface has been
implemented. Score it against the rubric in the
agent-ergonomics-and-intuitiveness-maximization-for-cli-tools skill
(11 agent-ergonomics dimensions, distinct from the doctor's own 10-dimension
scorecard rubric used in step 3 below),
treating each subcommand and each flag as a scorable surface.

PROCEDURE.

1. Read the agent-ergonomics SKILL.md and references/rubric/SCORING-RUBRIC.md.

2. Enumerate the doctor surfaces (cross-checked against CLI-SURFACE.md):
   - Subcommands: diagnose, fix, undo, explain, capabilities, health,
     robot-docs, gc, ls, diff (10)
   - Universal flags: --json, --robot, --quiet, --verbose/-v, --no-color,
     --no-progress (6)
   - Diagnose/fix flags: --fix, --dry-run, --only, --skip, --since, --online,
     --explain, --severity, --budget, --quick, --force, --yes (12)
   - Undo flags: --strict (and --no-strict), --dry-run (2 distinct, 1 shared)
   Total: 10 subcommands + 19 distinct flags. Each is a scorable surface.

3. For each surface, score 0-1000 across the 11 agent-ergonomics dimensions:
   agent_intuitiveness, agent_ergonomics, agent_ease_of_use,
   output_parseability, error_pedagogy, intent_inference,
   safety_with_recovery, determinism_and_reproducibility,
   self_documentation, composability, regression_resistance.

4. For each score >= 700, cite evidence (file:line for source-defined
   behavior, or transcript for runtime-discovered behavior).

5. Identify the top 5 below-quartile surfaces. For each, write a recommended
   fix block with:
   - minimal diff sketch
   - expected score-after-fix per dimension
   - risk notes
   - test additions required

6. Save results to:
   - `{{workspace}}/agent_ergo_grade.md` (human-readable)
   - `{{workspace}}/agent_ergo_recommendations.jsonl` (one rec per line)

CITATION RULES.
- Cite the agent-ergonomics rubric section by name when scoring (e.g.,
  "scoring as 750 per Rubric §4 anchor").
- Citations from this skill: the agent-ergonomics rubric IS the meta-rubric
  for this skill's Phase 6.

EXIT CRITERIA.
- Every surface has a row in agent_ergo_grade.md.
- agent_ergo_recommendations.jsonl has 1-5 ranked recs.
- No score >= 700 lacks a citation.
```

## Exit criteria

- Every surface graded
- Recommendations ranked

## Failure modes

- The agent-ergonomics skill isn't installed. Fall back to the 10-dim rubric in [../references/rubric/SCORING-RUBRIC.md](../references/rubric/SCORING-RUBRIC.md). Note the substitution in `agent_ergo_grade.md`.
