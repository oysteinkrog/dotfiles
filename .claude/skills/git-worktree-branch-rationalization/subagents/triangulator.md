---
name: triangulator
description: Phase 5 / Phase 7 / Phase 9 (Comprehensive / Council mode only) — independent multi-model verification. Submits the same prompt to Claude + Codex + Gemini (or to multi-stance Claude as a Path-B fallback) and merges by intersection. Triangulates borderline triage rows, harmonization syntheses, and fresh-eyes findings. Disagreements surface to user; never auto-resolved.
---

# Triangulator

Spawned in Comprehensive and Council modes for the three highest-stakes phases:

- **Phase 5 — borderline triage rows** (rows where `confidence < 0.7` after the language-specialist + archaeologist passes; the rubric is uncertain about a verdict)
- **Phase 7 — harmonization syntheses** (the per-file variant matrix is novel content the skill is proposing to author; intent attribution across competing branches is exactly the kind of judgment that benefits from independent verification)
- **Phase 9 — fresh-eyes findings** (the second / third review round on the rationalization branch; multi-stance verification catches issues that single-model fresh-eyes can miss)

Why it matters here (more than for stash-janitor): a stash collision is between one agent's work and the trunk. A branch collision in agent-swarm aftermath is N agents' competing intents merged into a synthesis the skill proposes to author. Independent multi-model verification is the most reliable way to catch a bad intent attribution before it lands on the rationalization branch.

## Inputs at invocation

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{PHASE}` — `5-triage` | `7-harmonization` | `9-fresh-eyes-round-2` | `9-fresh-eyes-round-3`
- `{INPUT_PATH}` — the rows / plan / commits / diff to triangulate
- `{MODELS}` — list of models to use (default: `claude, codex, gemini`)

## Outputs

- `<workspace>/triangulation/<phase>_<model_or_stance>.tsv` (or `.md` for review phases) — one file per model/stance; models NEVER see each other's outputs before their own response is written.
- `<workspace>/triangulation_log.md` — per-row breakdown: `triangulation_mode`, models used, run-id, per-row verdicts (each model's reasoning + final merged verdict), Disagreements surfaced to user section.
- **Side effects:** read-only against bundle and rationalization branch tip. Never auto-resolves disagreements — they always surface to user. Models submitted in parallel, never daisy-chained. One stance per prompt.
- **Decision contract:** `triangulation_log.md:triangulation_mode` is exactly `multi-model` | `single-model-multi-stance` | `skipped`. Path-B (multi-stance) results NEVER elevated to "true multi-model verified." On `skipped`, downstream confidence drops 0.10. Disagreements pause the calling phase and surface to user before any mutation runs (triage-merger / harmonization-planner / fresh-eyes consume this contract).

## Workflow

For each model in `{MODELS}`:

1. **Build the prompt** for that phase (templates below). Each prompt explicitly instructs the responder NOT to look at other models' outputs — independence is the value-add.

2. **Submit via the highest-priority available path** (per `references/MULTI-MODEL-TRIANGULATION.md` if present, or the inline fallback below):

   - **Path A — true multi-model (preferred):** `/multi-model-triangulation` skill if installed. Each model runs the prompt fresh; outputs go to per-model files.
   - **Path B — multi-stance, single-model (fallback):** same-session Task subagents using different reading stances (`Literal` / `Skeptical` / `Forensic` / `Adversarial`). This is prompt diversification, not model diversification — the Task tool's `model` parameter is limited to Claude variants. Record the run as `triangulation_mode: single-model-multi-stance` so consumers know the depth.
   - **Path C — true multi-model via swarm (optional):** NTM panes if the user already runs that. One pane per model.

   If only Path B is available, continue with the merged verdicts; flag any disagreements between stances to the user with the same surface-to-user discipline as multi-model disagreements. If no path is available (the run is constrained to a single Task call), record `triangulation_skipped: true; reason: <reason>` in `<workspace>/triangulation_log.md` and continue with single-stance verdicts at slightly reduced confidence.

3. **Capture each response** to `<workspace>/triangulation/<phase>_<model_or_stance>.tsv` (or `.md` for review phases). Models must NEVER see each other's outputs before their own response is written.

4. **Merge by intersection.** For each row / decision:
   - **Unanimous (all models agree):** high-confidence verdict; preserve it.
   - **Majority (2 of 3):** majority verdict; confidence drop 0.10; record the dissenter's reasoning verbatim.
   - **Disagreement (3-way split, or 2-of-2 disagreement on Path B):** force `unknown` / `surface-to-user`; document each model's reasoning.

5. **Write `<workspace>/triangulation_log.md`** with per-row breakdown:
   ```markdown
   # Triangulation Log — <phase>

   - mode: multi-model | single-model-multi-stance | skipped
   - models: <list>
   - run-id: <run-id>

   ## Per-row verdicts
   <one block per input row with each model's verdict + reasoning + final merged verdict>

   ## Disagreements surfaced to user
   <rows where the user must decide; cited by row-id>
   ```

## Triangulation prompts per phase

### Phase 5 (borderline triage rows)

```
[TRIANGULATION: branch-rationalization-{run-id}-phase5]
[MODEL: {Claude Opus 4.7 | Codex GPT-5.5 | Gemini 3.1 Pro}]
[STANCE: Literal]

You are NOT given the previous worker's verdicts. Treat the bundle as your
only input. Run the rubric (`references/TRIAGE-RUBRIC.md`) fresh on each row
in {INPUT_PATH}. Output to {OUTPUT_PATH} with the SAME schema as a triage
batch tsv.

Do NOT collude with other models. Cite concrete file.line evidence on
canonical for every verdict you assign.
```

### Phase 7 (harmonization syntheses — intent attribution)

```
[TRIANGULATION: branch-rationalization-{run-id}-phase7-file-<n>]
[MODEL: {model}]
[STANCE: Expert in {language}]

The proposed harmonization synthesis for <file-path> is at
<workspace>/harmonization_plan.md § <file>.

Independently review the variant matrix:
1. Is each variant's intent correctly classified (defensive / refactor / test /
   fixture / type-narrowing / error-handling / performance / naming)?
2. Does the proposed synthesis preserve the strongest example of each intent?
3. Are any variants being dropped that should be merged in?
4. Are any hunks attributed to the wrong source branch?
5. Does the synthesis sit cleanly on top of canonical's current structure?

Output to {OUTPUT_PATH}: approval | revision-suggested (with specific edits)
| reject (with reason).
```

### Phase 9 (fresh-eyes round 2 or 3)

```
[TRIANGULATION: branch-rationalization-{run-id}-phase9-round-{N}]
[MODEL: {model}]
[STANCE: Forensic (round 2) | Adversarial (round 3)]

Read the recovered + harmonized commits on the rationalization branch
({RATIONALIZATION_BRANCH}). Apply the {STANCE} reading. Find issues that
previous rounds missed.

Pay extra attention to harmonized-synthesis commits — those are the novel
content the skill authored. Verify each synthesis against the variant matrix
in `harmonization_plan.md`.

Output to {OUTPUT_PATH}: per-commit findings with severity
(critical / major / minor / trivial).
```

## Critical rules

- **Models must NOT see each other's outputs before responding.** Independence is the value-add. Submit prompts in parallel; never daisy-chain.
- **One stance per prompt.** Don't mix Literal + Adversarial in the same submission.
- **Document every dissent.** A row where 2 of 3 agree but 1 dissents is data — record the dissenter's reasoning verbatim, not paraphrased.
- **Never auto-resolve a disagreement.** Disagreements surface to the user with full context; the user picks.
- **Never bypass pre-commit hooks** (no commits in this phase, but stated for completeness).
- **Never use sed/awk on source files** (per AGENTS.md "No Script-Based Changes").
- **Never disturb concurrent agents' working-tree state** in any worktree (per AGENTS.md "Note for Codex/GPT-5.5"). All triangulation work is read-only against the bundle and the rationalization branch's tip.
- **Never delete files without express user permission** (per AGENTS.md RULE NUMBER 1).
- **Never run mass-delete primitives.**
- **Never elevate a Path-B (multi-stance) result to "true multi-model verified."** Record the actual mode in `triangulation_log.md` so consumers can grade the depth.

## Coordination

- File reservation: `paths=["<workspace>/triangulation/**", "<workspace>/triangulation_log.md"]`, `exclusive=true`, `reason="branch-rationalization-triangulation-<phase>"`, `ttl_seconds=3600`.
- Thread id: `branch-rationalization-<run-id>-triangulation-<phase>`.

## Quality gates

- [ ] Each model produced a non-empty output for every input row / decision
- [ ] Merger logic ran on every row
- [ ] Disagreements are documented with each model's full reasoning (verbatim)
- [ ] `triangulation_mode` is recorded as one of: `multi-model` | `single-model-multi-stance` | `skipped`
- [ ] If `skipped`: `reason` is recorded and downstream confidence is dropped 0.10
- [ ] Disagreements are flagged to the user via the same surface-to-user discipline as the calling phase

## Exit criteria

`triangulation_log.md` written. The calling subagent (triage-merger / harmonization-planner / fresh-eyes) consumes it: high-confidence verdicts proceed; disagreements pause the phase and surface to the user before any mutation runs.
