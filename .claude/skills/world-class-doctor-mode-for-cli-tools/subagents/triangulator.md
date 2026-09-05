# subagent: triangulator (Phase 4 / Phase 7; multi-model only)

**Description.** Cross-validate top recommendations and irreversible-path code via Codex and Gemini in parallel using `/multi-model-triangulation`. Compare answers; flag disagreements.

## Inputs

- `{{target}}` — target repo
- `{{patches}}` — the diff under review. Concretely:
  - Phase 4: `git -C {{target}} diff doctor-mode-pass-{{N}}~..doctor-mode-pass-{{N}}` (or a comma-separated list of `analysis/repair_specs/<id>.md` paths to triangulate spec-only)
  - Phase 7: `{{workspace}}/fresh_eyes_findings_pass_{{N}}.md` (the calibrated-prompt output from `subagents/fresh-eyes.md`)
  - The orchestrator must produce `{{patches}}` as a concrete file or git ref before dispatching this subagent — never leave it as a literal `{{patches}}` placeholder in the prompt body.
- `/multi-model-triangulation` skill

## Outputs

- `{{workspace}}/triangulation_<phase>_<round>.md` — per-question multi-model verdict
- Beads filed for any disagreement that names a real bug

## Prompt

```
You are the triangulator. Cross-validate decisions using Claude (you), Codex,
and Gemini via the /multi-model-triangulation skill.

INPUTS.
- The patches under review: {{patches}}
- The questions to triangulate (one or more):
  - "Does this `mutate()` implementation correctly preserve byte-for-byte
    backup invariants under SIGKILL?"
  - "Is this fixer's `--dry-run` output a strict superset of its actual
    write set?"
  - "Does the `--force` path bypass any precondition?"
  - <question from the calling phase>

PROCEDURE.

1. Invoke /multi-model-triangulation with the patch + question.

2. Capture each model's response. Compare:
   - Identical answers → strong signal; record as consensus.
   - Different answers → record the divergence. Investigate the source of
     the disagreement.

3. For each disagreement that names a real bug (not a stylistic preference):
   - File a P0/P1 bead.
   - Quote each model's verbatim concern in the bead body.

4. For stylistic disagreements: note in the triangulation report; do not
   file a bead.

OUTPUT.
{{workspace}}/triangulation_<phase>_<round>.md with per-question consensus
or divergence record.

EXIT CRITERIA.
- Every question has a verdict.
- Every named bug has a bead.
```

## Exit criteria

- Triangulation report committed
- Beads filed for real bugs

## Failure modes

- One model is unavailable. Use a 2-of-2 quorum instead of 2-of-3. Note in the report.
- All three models disagree. Probably an actually hard call — escalate to the user.
- Models agree but are all wrong (verifiable later by Phase 5 / 9). The fixture suite catches this; not the triangulator's job.
