# Multi-Model Triangulation

When verdict ambiguity is high (Phase 5 confidence < 0.7 OR Phase 7 harmonization confidence < 0.7) or the recovered work is high-stakes, the same triage / harmonization / review prompt is run across multiple **independent reasoners**. The intersection is the high-confidence subset; the disagreement set surfaces to user.

> **The skill never *requires* multiple models.** High-confidence single-model verdicts proceed. Council tier requires triangulation; Comprehensive tier opt-in; Standard / Quick skip by default.

Adapted from [git-stash-janitor's MULTI-MODEL-TRIANGULATION.md](../../git-stash-janitor/references/MULTI-MODEL-TRIANGULATION.md), with extensions for the harmonization-planner role specific to this skill.

---

## When to Triangulate

| Phase | Trigger | Models recommended |
|---|---|---|
| 5 (triage) | >15% of rows have confidence < 0.75 | Claude Opus 4.7 + Codex (GPT-5.5) |
| 5 (triage) | Comprehensive mode, all rows | + Gemini 3.1 Pro |
| 5 (triage) | Council mode | All 3 — required |
| 7 (harmonization-planner) | Any colliding-file group with confidence < 0.7 | Claude + Codex |
| 7 (harmonization-planner) | Comprehensive mode, all colliding-file groups | + Gemini |
| 7 (harmonization-planner) | Council mode | All 3 — required (per [SKILL.md § Mode Variants](../SKILL.md#mode-variants)) |
| 8 (apply, conflict resolution) | Resolution touches >50 lines or crosses architectural boundaries | Claude + Codex |
| 8 (apply, harmonized synthesis review) | Comprehensive mode, every harmonized synthesis | Claude + Codex |
| 9 round 2 (fresh-eyes) | Standard mode | Claude + Codex |
| 9 round 3 (fresh-eyes) | Comprehensive mode | Claude + Codex + Gemini |
| 11 (user-lens) | Comprehensive mode + ≥3 keepers authored | Claude + Gemini (Gemini's "different reasoning style" surfaces different friction points) |

**Rule of thumb:** triangulate on rows the rubric or harmonization planner is least confident about, not on rows where they're sure. Triangulating high-confidence rows wastes compute (intersection rate >99%) without surfacing useful signal.

> **Why:** Per [KEY-INSIGHTS.md §I-16](KEY-INSIGHTS.md): "Confidence < 0.7 forces user surface. The rubric is statistical; the user is the ground truth." Triangulation is the path between "rubric is sure → auto-classify" and "user surface".

---

## Three Submission Paths (in priority order)

The skill has three submission paths for triangulation. Use whichever is available; explicitly record in `triangulation_log.md` which path was used.

### Path A (preferred — true multi-model from one Claude Code session)

Use the [`/multi-model-triangulation`](../../multi-model-triangulation/SKILL.md) skill if installed. It wraps the model-specific submission logic for Codex / Gemini / etc. and works from a single Claude Code session.

This is the **only** single-session way to reach non-Claude models, because the Task tool's `model` parameter only supports Claude variants (sonnet / opus / haiku). The `/multi-model-triangulation` skill bridges to Codex, Gemini, and other reasoners via their respective SDKs.

**When to use:** the `/multi-model-triangulation` skill is installed AND the user wants true model diversity without launching NTM.

### Path B (fallback — same-session multi-stance Task subagents)

Same Claude model, different reading stances per [MODES-OF-REASONING.md](MODES-OF-REASONING.md). The main agent spawns multiple Task subagents with different `[MODE: ...]` tags and compares their outputs.

Stances appropriate for each phase:

- **Phase 5 triage borderline rows:** Literal × Skeptical × Forensic (three Task subagents reading the same diff with different priors)
- **Phase 7 harmonization plan:** Forensic (intent identification) × Adversarial (synthesis stress-test)
- **Phase 9 fresh-eyes round 3:** Adversarial × Skeptical (catches what literal-reading rounds missed)

This is **prompt diversification**, not model diversification. It catches a strict subset of issues that true multi-model would, but it's better than no second opinion. Use Path B when:

- The `/multi-model-triangulation` skill isn't installed
- The user doesn't run NTM
- Single-model verification is acceptable for the run's stakes (Standard, sometimes Comprehensive)

### Path C (optional — true multi-model via NTM panes)

Only when the user already runs NTM panes for each model:

```
ntm send claude-pane "<triangulation prompt for Claude with [STANCE: Literal]>"
ntm send codex-pane  "<triangulation prompt for Codex with [STANCE: Forensic]>"
ntm send gemini-pane "<triangulation prompt for Gemini with [STANCE: Adversarial]>"
```

The skill never *requires* NTM. It falls back through A → B → C based on what's available, and explicitly records which path was used (and whether triangulation was effectively single-model) in `triangulation_log.md`.

---

## How to Triangulate Phase 5 (Triage)

### Step 1 — Identify rows for triangulation

```
awk -F'\t' 'NR > 1 && $4 < 0.75 {print $1 "|" $2}' triage.tsv > triage/borderline_rows.txt
```

(Column 4 is `confidence` per the [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md) schema.)

### Step 2 — Build the triangulation prompt

Same as the Phase 5 worker prompt (see [AGENT-PROMPTS.md § Phase 5 — Triage Worker](AGENT-PROMPTS.md#phase-5--triage-worker-parallel)), but with:

```
[TRIANGULATION: branch-rationalization-{run-id}-phase5]
[MODEL: {Claude Opus 4.7 | Codex GPT-5.5 | Gemini 3.1 Pro}]
[STANCE: {Literal | Skeptical | Forensic}]

Independent re-triage of branches and worktrees in
{WORKSPACE}/triage/borderline_rows.txt.

You are NOT given the previous worker's verdicts. Run the rubric fresh on each
row. Output to triage/batch_<run-id>_<model>.tsv with the SAME schema as a
batch tsv.

Do NOT collude with other models. Treat the bundle as your only input.
```

### Step 3 — Submit to each model via the chosen path

Path A → invoke `/multi-model-triangulation` with the prompt + the model list.
Path B → invoke 3 Task subagents with the same prompt but different `[STANCE]` tags.
Path C → `ntm send` to each model's pane.

### Step 4 — Merge by intersection

```
for entry in borderline_rows:
  c = claude_verdict[entry]
  o = codex_verdict[entry]   (or stance_2 in Path B)
  g = gemini_verdict[entry]  (or stance_3 in Path B; or skip if 2-model run)

  if c == o == g:
    final_verdict = c
    final_confidence = max(orig_conf, 0.95)   # Unanimous; auto-classify
  elif majority(c, o, g) is well-defined:
    final_verdict = majority
    final_confidence = orig_conf - 0.10        # one model dissented
    # Surface to user only if final < 0.70
  else:
    final_verdict = unknown
    # Surface to user with all 3 model verdicts shown
```

### Step 5 — Surface to user (Phase 6)

The `triage_decision.md` gains a `triangulation` column:

```markdown
| kind   | name                | rubric_verdict        | claude         | codex      | gemini       | unanimous? | proposed         |
|--------|---------------------|----------------------|----------------|------------|--------------|------------|------------------|
| branch | agent-cc-44-jwt     | partially-novel(0.72)| partially-novel| superseded | partially-novel | majority   | partially-novel  |
| branch | agent-old-cli-flags | unknown(0.62)        | novel-but-stale| superseded | unknown      | NO         | surface          |
| worktree | foo-wt-stale     | dirty-worktree-only(0.68) | dirty-worktree-only | dirty-worktree-only | unknown | majority | dirty-worktree-only |
```

Rows with disagreement get the full per-model breakdown so the user can adjudicate. Rows with `unanimous=YES` skip the table by default (visible only in `<details>`).

---

## How to Triangulate Phase 7 (Harmonization Planner)

The harmonization planner produces, for each colliding-file group, a variant matrix + a proposed synthesis (per [HARMONIZATION.md](HARMONIZATION.md)). Triangulation runs that whole process in parallel across multiple reasoners.

### Step 1 — Identify groups for triangulation

Comprehensive mode: all colliding-file groups whose proposed-synthesis confidence < 0.7.
Council mode: ALL colliding-file groups (per [SKILL.md § Mode Variants](../SKILL.md#mode-variants): "Council triangulation on the variant matrix").

### Step 2 — Build the triangulation prompt

Same as the Phase 7 harmonization-planner prompt (see [AGENT-PROMPTS.md § Phase 7 — Harmonization Planner](AGENT-PROMPTS.md#phase-7--harmonization-planner-the-conceptual-centerpiece)), but with:

```
[TRIANGULATION: branch-rationalization-{run-id}-phase7]
[MODEL: {Claude Opus 4.7 | Codex GPT-5.5 | Gemini 3.1 Pro}]
[STANCE: {Forensic | Adversarial}]

Independent harmonization plan for the colliding-file group at <path>.

You are NOT given the previous planner's proposed synthesis. Run the
HARMONIZATION.md methodology fresh on each variant. Output your variant
matrix + proposed synthesis to harmonization/<sanitized-path>_<model>.md
with the SAME schema as the planner's output.

Do NOT collude with other models. Treat the bundle as your only input.
```

### Step 3 — Submit to each model

Same as Phase 5: Path A → B → C.

### Step 4 — Compare proposed syntheses

A harmonization synthesis is harder to compare than a triage verdict (a synthesis is a multi-line proposed diff, not a single label). Use this comparison protocol:

1. **Identical verbatim:** unanimous; raise confidence to 0.95; auto-include in `harmonization_plan.md`.
2. **Identical at the hunk level (same hunks chosen from same source branches; same composition order):** unanimous-equivalent; raise confidence to 0.92; auto-include.
3. **Different hunk choices, but same identified intent set:** majority synthesis if 2 of 3 agree on the same hunk set; surface the dissenting plan to user as "alternative synthesis".
4. **Different identified intents:** 3-way disagreement; surface ALL plans verbatim to user; user picks one.
5. **Disagreement on whether the file is `divergent-refactor`:** if any model says "do not synthesize", flag the file as `divergent-refactor` and surface the synthesis disagreement to user. Per [HARMONIZATION.md § 5](HARMONIZATION.md): "When in doubt, flag rather than synthesize."

### Step 5 — User reviews triangulated harmonization plan

The Phase 7 user gate now shows:

```markdown
## File: src/parser.rs (4 variants colliding)

### Triangulation summary

| Model   | Stance      | Synthesis confidence | Decision         |
|---------|-------------|---------------------|------------------|
| Claude  | Forensic    | 0.85                | compose A+B+C    |
| Codex   | Adversarial | 0.78                | compose A+B (drop C) |
| Gemini  | Forensic    | 0.82                | compose A+B+C    |

Unanimous on: variants A and B should compose.
Disagreement on: variant C — Codex flagged a hidden incompatibility (line 257 type mismatch).

### Proposed synthesis (consensus, with Codex's concern noted)

[diff fragment]

### Codex's concern verbatim

"Variant C's redact_secrets() returns String, but the synthesis call site
at line 257 expects &str — needs an &result-of-redact intermediate. Either
fix the call site or drop variant C."

### Recommended action

Either:
  (a) accept the consensus synthesis and add Codex's fix at line 257
  (b) drop variant C entirely
  (c) skip this file group; flag as divergent-refactor

Your call:
```

The user picks (a), (b), or (c) and the choice goes into `user_overrides.tsv`.

---

## How to Triangulate Phase 9 (Fresh-Eyes)

Each fresh-eyes round prompt goes to a different model + stance in parallel:

```
Round 1 (Claude, MODE=Literal):
  "Carefully read over all of the new code you just wrote..."

Round 2 (Codex, MODE=Forensic):
  "Sort of randomly explore the code files..."

Round 3 (Gemini, MODE=Adversarial):
  "Turn your attention to reviewing the code written by your fellow agents..."
```

Each model writes findings to `<workspace>/fresh_eyes_round_<N>_<model>.md`.

**Merge rule:** a finding is "real" if at least 2 models flagged it (or it's a high-severity finding from a single model). Single-model low-severity findings are recorded but don't block termination.

For Council mode, ADD a meta-round that triangulates the findings themselves: "given the three rounds' findings, which are real and which are false positives?" This catches the model's own confirmation bias.

---

## How to Triangulate Phase 11 (User-Lens)

Two models produce independent user-lens reviews:

```
Claude prompt: "Review this run from a user-experience perspective..."
Gemini prompt: "Review this run from a user-experience perspective..."
```

Each writes to `<workspace>/skill_feedback_<model>.md`. The handoff includes both. Where they agree, the feedback is acted on; where they disagree, the disagreement itself is the feedback (it identifies a friction point that's perceived differently by different reasoners — a sign the documentation might be ambiguous).

---

## Resource Accounting

Triangulation roughly multiplies agent compute by the number of models. Rough estimates per phase, per model:

| Phase | Per-model cost (rough) |
|---|---|
| 5 borderline rows (assume 30 rows out of 200) | ~$0.80 |
| 7 colliding-file group (per group, assume 8 groups) | ~$0.40 per group → $3.20 total |
| 8 conflict resolution (per conflict, assume 5 conflicts) | ~$0.20 per conflict → $1.00 total |
| 8 harmonized-synthesis review (per synthesis, assume 8) | ~$0.30 per synthesis → $2.40 total |
| 9 fresh-eyes round | ~$1.50 |
| 11 user-lens | ~$0.50 |

A Comprehensive run on a 213-branch + 47-worktree repo that triangulates Phase 5 borderlines + Phase 7 (8 groups) + Phase 8 conflicts + Phase 9 rounds 2-3 + Phase 11 costs roughly **$15–$25** in agent compute on top of the base run cost (Claude-only).

A Council run that triangulates everything across all 3 models costs roughly **$40–$80** on top of the base.

---

## Anti-Patterns in Triangulation

| ✗ | Why |
|---|---|
| Submitting the same prompt to the same model twice | No new information; just redundant cost |
| Triangulating on rows the rubric / planner is already sure about | Wastes compute; intersection rate >99% |
| Letting models see each other's verdicts before they answer | Defeats the independence; collusion biases the result |
| Always going Claude+Codex+Gemini even on Quick mode | Overkill; the rubric is sufficient for high-confidence rows |
| Using triangulation to delay user decisions | Triangulation is an aid, not a replacement for the user gate |
| Triangulating Phase 8 by running two parallel applies | Phase 8 is strictly serial (per [ORCHESTRATION.md § Parallelism Boundaries](ORCHESTRATION.md#parallelism-boundaries-non-negotiable)). Triangulation in Phase 8 is *review* of each apply, not parallel applies |
| Triangulating Phase 7 syntheses without showing the user the disagreement | The disagreement IS the surface; hide it and you've dropped useful signal |

---

## Failure Modes

- **Model unavailable:** if Codex is rate-limited, run with Claude+Gemini only; document the missing model in the triangulation log. Per [INCIDENT-PLAYBOOK.md I7](INCIDENT-PLAYBOOK.md#i7) for related model-availability incidents.
- **Models all wrong:** the rubric / planner is right and 3 models are wrong. Surface to user with the rubric's evidence; the user is ground truth.
- **Models disagree on >50% of rows:** the rubric is failing on this language/repo. Per [INCIDENT-PLAYBOOK.md I10](INCIDENT-PLAYBOOK.md#i10): consider spawning language-specialist subagents instead of more models.
- **Path A (`/multi-model-triangulation` skill) not installed:** fall back to Path B. Document in `triangulation_log.md` that triangulation was effectively single-model with stance diversification.
- **Path C (NTM) panes wedged:** fall back to Path A or B. Don't block the run on a stuck pane; surface and continue.
- **Council mode + Path A unavailable + Path B used:** record `effective_diversification: prompt_only` in the triangulation log; surface to user as a deviation from full Council triangulation; user can decide to proceed or upgrade the path.

---

## Output: `triangulation_log.md`

```markdown
# Triangulation log — Phase 5 + Phase 7

Mode: Comprehensive
Run id: branch-rationalization-2026-05-07T18-30-00Z

## Phase 5 (triage)

Path used: A (/multi-model-triangulation)
Triangulated rows: 23 (of 187 total; rows with confidence < 0.75)
Models: Claude Opus 4.7, Codex GPT-5.5, Gemini 3.1 Pro

### Summary

- Unanimous: 19 rows (all 3 agree → high-confidence verdicts)
- Majority (2 of 3): 3 rows
- Disagreement (3-way): 1 row (surfaced to user)

### Disagreement detail

#### Row: branch agent-old-cli-flags

| Model  | Verdict          | Confidence | Reasoning                                            |
|--------|------------------|------------|------------------------------------------------------|
| Rubric | unknown          | 0.62       | apply rejects every hunk; files mostly missing       |
| Claude | novel-but-stale  | 0.70       | abandoned-refactor-branch; recovery would require rewrite |
| Codex  | superseded       | 0.65       | ParseError type renamed in commit abc123; semantically same |
| Gemini | unknown          | 0.60       | not enough context to decide                         |

User decision: novel-but-stale; defer rewrite to a separate effort.

## Phase 7 (harmonization)

Path used: A (/multi-model-triangulation)
Triangulated groups: 8 (every colliding-file group)
Models: Claude Opus 4.7, Codex GPT-5.5, Gemini 3.1 Pro

### Summary

- Unanimous synthesis: 5 groups (all 3 propose the same hunk-level synthesis)
- Majority synthesis: 2 groups (2 of 3 propose the same; 1 dissents on a hunk)
- 3-way disagreement: 1 group (src/parser.rs — surfaced to user; user picked Claude's proposal)

### Per-group detail

#### Group: src/util/logger.rs

Variants: 3 (agent-cleanup-pass-3, feature/length-cap, feature/redact-secrets)
All 3 models: identical synthesis (compose all three defensive checks at function entry,
ordered most-permissive → most-restrictive). Confidence raised to 0.95. Auto-include.

#### Group: src/parser.rs

Variants: 4 (agent-cc-12, agent-cc-77, agent-cod-3, worktree:foo-wt-stale)
3-way disagreement on the worktree:foo-wt-stale variant.
[See harmonization_plan.md § src/parser.rs for full breakdown]
User decision: include worktree's tracing instrumentation as a separate commit.

## Verdict adjustments applied

- Phase 5: 19 rows had confidence raised to 0.95 (unanimous)
- Phase 5: 3 rows: confidence dropped 0.10 (majority-only)
- Phase 5: 1 row: forced to `unknown`; surfaced to user
- Phase 7: 5 groups had synthesis confidence raised to 0.95
- Phase 7: 2 groups: confidence dropped 0.10 (majority-only)
- Phase 7: 1 group: surfaced to user; user picked Claude's proposal
```

This log is referenced from `handoff_report.md` and from `harmonization_plan.md`. It's part of the Polish Bar's "Verdict evidence" dimension: the user can audit not just the verdict but the triangulation that produced it.

---

## Cross-References

- Reading-stance definitions for Path B: [MODES-OF-REASONING.md](MODES-OF-REASONING.md)
- Phase-by-phase fan-out where triangulation slots in: [ORCHESTRATION.md](ORCHESTRATION.md)
- Per-mode default triangulation behavior: [SKILL.md § Mode Variants](../SKILL.md#mode-variants), [KICKOFF-PROMPTS.md § What Each Mode Triggers](KICKOFF-PROMPTS.md#what-each-mode-triggers)
- Harmonization planner methodology: [HARMONIZATION.md](HARMONIZATION.md)
- Triage rubric (the verdict catalogue + confidence calibration): [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md)
- Mid-run triangulation incidents: [INCIDENT-PLAYBOOK.md](INCIDENT-PLAYBOOK.md)
- The `/multi-model-triangulation` skill itself: [`/multi-model-triangulation`](../../multi-model-triangulation/SKILL.md)
