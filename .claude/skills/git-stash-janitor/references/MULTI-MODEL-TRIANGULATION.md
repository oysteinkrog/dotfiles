# Multi-Model Triangulation

When verdict ambiguity is high or the recovered work is high-stakes, the same triage / review prompt is run across multiple models. The intersection is the high-confidence subset; the disagreement set surfaces to user.

Adapted from documentation-website's triangulation pattern + multi-model-triangulation skill.

---

## When to triangulate

| Phase | Trigger | Models recommended |
|-------|---------|--------------------|
| 4 (triage) | >15% of rows have confidence < 0.75 | Claude Opus 4.7 + Codex (GPT-5.5) |
| 4 (triage) | Comprehensive mode, all rows | + Gemini 3.1 Pro |
| 6 (apply, conflict resolution) | Resolution touches >50 lines or crosses architectural boundaries | Claude + Codex |
| 8 round 2 (fresh-eyes) | Standard mode | Claude + Codex |
| 8 round 3 (fresh-eyes) | Comprehensive mode | Claude + Codex + Gemini |
| 11 (user-lens) | Comprehensive mode | Claude + Gemini (Gemini's "different reasoning style" surfaces different friction points) |

Rule of thumb: triangulate on rows the rubric is least confident about, not on rows where the rubric is sure.

---

## How to triangulate (Phase 4 example)

### Step 1: Identify rows for triangulation

```bash
awk -F'\t' 'NR > 1 && $3 < 0.75 {print $1}' triage.tsv > triage/borderline_rows.txt
```

### Step 2: Build the triangulation prompt

Same as Phase 4 worker prompt (see AGENT-PROMPTS.md), but with:

```
[TRIANGULATION: stash-janitor-{run-id}-phase4]
[MODEL: {Claude Opus 4.7 | Codex GPT-5.5 | Gemini 3.1 Pro}]
[STANCE: {Literal | Skeptical}]

Independent re-triage of stashes in {WORKSPACE}/triage/borderline_rows.txt.

You are NOT given the previous worker's verdicts. Run the rubric fresh on each
row. Output to triage/batch_<run-id>_<model>.tsv with the SAME schema as a
batch tsv.

Do NOT collude with other models. Treat the bundle as your only input.
```

### Step 3: Submit to each model

The skill has three submission paths, in priority order:

**Path A (preferred — true multi-model): the [`/multi-model-triangulation`](../../multi-model-triangulation/SKILL.md) skill** if installed. Wraps the model-specific submission logic for Codex / Gemini / etc. and works from a single Claude Code session. This is the only single-session way to reach non-Claude models, because the Task tool's `model` parameter only supports Claude variants (sonnet / opus / haiku).

**Path B (fallback — multi-stance, single-model): same-session prompt diversification.** The main agent spawns multiple Task subagents using the SAME (Claude) model but DIFFERENT reading stances (Literal / Skeptical / Forensic / Adversarial — see [MODES-OF-REASONING.md](MODES-OF-REASONING.md)). This is *prompt diversification*, not model diversification. It catches a strict subset of issues that true multi-model would, but it's better than no second opinion. Use Path B when:
- The `/multi-model-triangulation` skill isn't installed
- The user doesn't run NTM
- Single-model verification is acceptable for the run's stakes

**Path C (optional — true multi-model via swarm): NTM panes.** Only when the user already runs NTM panes for each model:

```bash
ntm send claude-pane "<triangulation prompt for Claude>"
ntm send codex-pane  "<triangulation prompt for Codex>"
ntm send gemini-pane "<triangulation prompt for Gemini>"
```

The skill never *requires* NTM. It falls back through A → B → C based on what's available, and explicitly records which path was used (and whether triangulation was effectively single-model) in `triangulation_log.md`.

### Step 4: Merge by intersection

```bash
# Pseudo-code:
for n in borderline_rows:
  c = claude_verdict[n]
  o = codex_verdict[n]
  g = gemini_verdict[n]

  if c == o == g:
    final_verdict = c
    final_confidence = max(orig_conf, 0.95)
    # Unanimous; auto-classify
  elif majority(c, o, g) is well-defined:
    final_verdict = majority
    final_confidence = orig_conf - 0.10  # one model dissented
    # Surface only if confidence still < 0.70
  else:
    final_verdict = unknown
    # Surface to user with all 3 model verdicts shown
```

### Step 5: Surface to user (Phase 5)

The triage_decision.md gains a `triangulation` column:

```markdown
| n | message | rubric_verdict | claude | codex | gemini | unanimous? | proposed |
|---|---------|---------------|--------|-------|--------|-----------|----------|
| 47 | wip-foo | partially-novel (0.72) | partially-novel | superseded | partially-novel | majority | partially-novel |
| 88 | wip-bar | unknown (0.62) | novel-but-stale | superseded | unknown | NO | surface |
```

Rows with disagreement get the full per-model breakdown so the user can adjudicate.

---

## How to triangulate (Phase 8 example)

Each fresh-eyes round prompt goes to a different model in parallel:

```
Round 1 (Claude, MODE=Literal):
  "Carefully read over all of the new code you just wrote..."

Round 2 (Codex, MODE=Forensic):
  "Sort of randomly explore the code files..."

Round 3 (Gemini, MODE=Adversarial):
  "Turn your attention to reviewing the code written by your fellow agents..."
```

Each model writes findings to `<workspace>/fresh_eyes_round_<N>_<model>.md`.

Merge: a finding is "real" if at least 2 models flagged it (or it's a high-severity finding from a single model). Single-model low-severity findings are recorded but don't block termination.

---

## How to triangulate (Phase 11 user-lens)

Two models produce independent user-lens reviews:

```
Claude prompt: "Review this run from a user-experience perspective..."
Gemini prompt: "Review this run from a user-experience perspective..."
```

Each writes to `<workspace>/skill_feedback_<model>.md`. The handoff includes both. Where they agree, the feedback is acted on; where they disagree, the disagreement itself is the feedback.

---

## Resource accounting

Triangulation roughly multiplies agent compute by the number of models. Rough estimates per phase, per model:

| Phase | Per-model cost |
|-------|---------------|
| 4 borderline rows (assume 20 rows) | ~$0.50 |
| 6 conflict resolution (per conflict) | ~$0.20 |
| 8 fresh-eyes round | ~$1.00 |
| 11 user-lens | ~$0.50 |

A Comprehensive run with 80+ stashes that triangulates Phase 4 + Phase 8 rounds 2-3 + Phase 11 costs roughly $5–$10 in agent compute on top of the base run cost.

---

## Anti-Patterns in Triangulation

| ✗ | Why |
|---|-----|
| Submitting the same prompt to the same model twice | No new information; just redundant cost |
| Triangulating on rows the rubric is already sure about | Wastes compute; intersection rate >99% |
| Letting models see each other's verdicts before they answer | Defeats the independence; collusion biases the result |
| Always going Claude+Codex+Gemini even on Quick mode | Overkill; the rubric is sufficient for high-confidence rows |
| Using triangulation to delay user decisions | Triangulation is an aid, not a replacement for the user gate |

---

## Failure modes

- **Model unavailable:** if Codex is rate-limited, run with Claude+Gemini only; document the missing model in the triangulation log.
- **Models all wrong:** the rubric is right and 3 models are wrong; surface to user with the rubric's evidence.
- **Models disagree on >50% of rows:** the rubric is failing on this language/repo; consider spawning language-specialist subagents instead of more models.

---

## Output: `triangulation_log.md`

```markdown
# Triangulation log — Phase 4

Mode: Comprehensive
Triangulated rows: 23 (of 127 total; rows with confidence < 0.75)
Models: Claude Opus 4.7, Codex GPT-5.5, Gemini 3.1 Pro

## Summary

- Unanimous: 19 rows (all 3 agree → high-confidence verdicts)
- Majority (2 of 3): 3 rows
- Disagreement (3-way): 1 row (surfaced to user)

## Disagreement detail

### Row n=88: stash@{88}: wip-old-cli-flag-handling

| Model | Verdict | Confidence | Reasoning |
|-------|---------|-----------|-----------|
| Rubric | unknown | 0.62 | apply rejects every hunk; files mostly missing |
| Claude | novel-but-stale | 0.70 | abandoned-refactor-branch; recovery would require rewrite |
| Codex | superseded | 0.65 | ParseError type renamed in commit abc123; semantically same |
| Gemini | unknown | 0.60 | not enough context to decide |

User decision: novel-but-stale; defer rewrite to a separate effort.

## Verdict adjustments applied

- 3 rows had confidence raised to 0.95 (unanimous agreement)
- 19 rows: no change (unanimous on the rubric's verdict)
- 3 rows: confidence dropped 0.10 (majority-only)
- 1 row: forced to `unknown`; surfaced to user
```

This log is referenced from the handoff report.
