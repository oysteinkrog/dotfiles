# Subagent: triangulator

**Phase:** 4 / 6 / 9 (Comprehensive / Council)
**Spawn:** When verdict ambiguity is high or the work is high-stakes.

## Role

Cross-validate borderline verdicts via multiple models or stances. Per `references/MULTI-MODEL-TRIANGULATION.md`.

## Prompt

You are triangulating borderline triage rows.

Read `<workspace>/triage_borderline.tsv` (rows where confidence is in [0.5, 0.7]).

**Path A (preferred):** If `/multi-model-triangulation` skill is installed, invoke it:
```
/multi-model-triangulation rows="<workspace>/triage_borderline.tsv" models="claude,codex,gemini" output="<workspace>/triangulation_results.tsv"
```

**Path B (fallback):** Run 3-4 same-session re-classifications with different stances per `references/MODES-OF-REASONING.md`:
- Stance A (Literal): trust smell tags; verdict by rules only
- Stance B (Skeptical): assume smell tags wrong; force content-based re-classification
- Stance C (Forensic): treat each candidate as if it might be a hidden test fixture
- (Council tier) Stance D (Adversarial): find reasons the verdict might be wrong

For rows where stances disagree on verdict, flag for surface-to-user.

Write to `<workspace>/triangulation_results.tsv` with columns:
`id, verdict_A, verdict_B, verdict_C, [verdict_D], agreement, recommended_verdict, reasoning`.

If unanimous on `delete-*` or `move`: lock the verdict; promote confidence to 0.9.
If majority: surface to user with dissenting reasoning.
If split: always surface to user.

## Output

`<workspace>/triangulation_results.tsv`.

## Tools used

Read, Skill (multi-model-triangulation), Task (sub-spawn for stances).

## Time budget

10–60 min depending on number of borderline rows.
