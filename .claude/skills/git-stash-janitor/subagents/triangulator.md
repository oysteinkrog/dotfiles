---
name: triangulator
description: Multi-model independent triage / review for high-stakes phases. Submits the same prompt to Claude + Codex + Gemini; merges by intersection.
---

# Triangulator

Spawned for Comprehensive runs (Phase 4 borderline rows, Phase 8 rounds 2-3, Phase 11). The same prompt goes to multiple models; their independent verdicts are merged.

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{PHASE}` — `4 | 6-conflict | 8-round-2 | 8-round-3 | 11`
- `{INPUT_PATH}` — the rows / commits / diff to triangulate
- `{MODELS}` — list of models to use (default: `claude, codex, gemini`)

## Workflow

For each model in `{MODELS}`:

1. Build the prompt for that phase (see `references/MULTI-MODEL-TRIANGULATION.md`).
2. Submit via the highest-priority available path (see MULTI-MODEL-TRIANGULATION § "Step 3"):
   - Path A (preferred — true multi-model): `/multi-model-triangulation` skill if installed
   - Path B (fallback — multi-stance, single-model): same-session Task subagents using different reading stances (Literal / Skeptical / Forensic / Adversarial). Note: this is prompt diversification, not model diversification — the Task tool's `model` parameter is limited to Claude variants.
   - Path C (optional — true multi-model via swarm): NTM panes if the user runs that
3. Capture the response to `<workspace>/triangulation/<phase>_<model_or_stance>.tsv` (or `.md` for review phases).

If only Path B (single-model multi-stance) is available, record the run as `triangulation_mode: single-model-multi-stance` in `triangulation_log.md` so consumers know the verification depth. Continue with the merged verdicts; flag any disagreements between stances to the user with the same surface-to-user discipline as multi-model disagreements.

If no path is available (e.g., the run is constrained to a single Task call), record `triangulation_skipped: true; reason: <reason>` and continue with single-stance verdicts at slightly reduced confidence.

After all models respond:

4. **Merge by intersection.** For each row:
   - Unanimous: high-confidence verdict
   - Majority (2 of 3): majority verdict, confidence drop 0.10
   - Disagreement (3-way): force `unknown`, surface to user

5. Write `<workspace>/triangulation_log.md` with per-row breakdown.

## Triangulation prompts per phase

### Phase 4 (triage borderline rows)

```
[TRIANGULATION: stash-janitor-{run-id}-phase4]
[MODEL: {Claude Opus 4.7 | Codex GPT-5.5 | Gemini 3.1 Pro}]
[STANCE: Literal]

You are NOT given the previous worker's verdicts. Run the rubric fresh on
each row in {INPUT_PATH}. Output to {OUTPUT_PATH} with the SAME schema as a
batch tsv.

Do NOT collude with other models. Treat the bundle as your only input.
```

### Phase 6 (conflict resolution review)

```
[TRIANGULATION: stash-janitor-{run-id}-phase6-conflict-<n>]
[MODEL: {model}]
[STANCE: Expert in {language}]

The proposed manual conflict resolution for stash@{n} is at
<workspace>/conflicts/stash_<NPAD>.context.md.

Independently review:
1. Does the resolution preserve the stash's intent?
2. Does it conform to the project's idioms / style?
3. Are there hidden bugs?

Output to {OUTPUT_PATH}: approval | revision-suggested | reject (with reason).
```

### Phase 8 (fresh-eyes round 2 or 3)

```
[TRIANGULATION: stash-janitor-{run-id}-phase8-round-{N}]
[MODEL: {model}]
[STANCE: Forensic (round 2) | Adversarial (round 3)]

Read the recovered commits on the stash-recovery branch. Apply the
{STANCE} reading. Find issues that previous rounds missed.
```

## Critical rules

- **Models must NOT see each other's outputs before responding.** Independence is the value-add.
- **One stance per prompt.** Don't mix Literal + Adversarial in the same submission.
- **Document every dissent.** A row where 2 of 3 agree but 1 dissents is data — record the dissenter's reasoning.

## Coordination

- File reservations: per-model output path
- Thread id: `stash-janitor-<run-id>-triangulation-<phase>`

## Quality gates

- [ ] Each model produced a non-empty output
- [ ] Merger logic ran on all rows
- [ ] Disagreements are documented with each model's full reasoning

## Exit criteria

`triangulation_log.md` written. Calling subagent (Phase 4 / 8 / 11) consumes it.
