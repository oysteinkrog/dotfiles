# Multi-Model Triangulation

Optional cross-validation via multiple AI models. Used in Council tier and at borderline-verdict points in Comprehensive variant.

---

## When to triangulate

- **Council tier:** verdict ambiguity is high; security-sensitive content; production-critical repo.
- **Comprehensive borderline rows:** confidence in [0.5, 0.7] band — too high to auto-`surface-to-user`, too low to trust.
- **Phase 9 round 3:** final fresh-eyes pass before destructive cleanup.

---

## Three submission paths in priority order

### Path A (preferred): `/multi-model-triangulation` skill

If installed, invoke from a single Claude Code session:

```
/multi-model-triangulation \
  rows="<workspace>/triage_borderline.tsv" \
  models="claude,codex,gemini" \
  output="<workspace>/triangulation_results.tsv"
```

The triangulation skill fans out to all three models, collects independent verdicts, and consolidates. True multi-model diversity.

### Path B (fallback): Same-session multi-stance Task subagents

When `/multi-model-triangulation` isn't available, spawn 3-4 same-model Task subagents with different stances (Literal, Skeptical, Forensic, Adversarial). Less diversity but still catches a useful subset.

```python
# Spawn 4 subagents with the same model but different stance prompts
spawn(stance="literal", rows=borderline_rows)
spawn(stance="skeptical", rows=borderline_rows)
spawn(stance="forensic", rows=borderline_rows)
spawn(stance="adversarial", rows=borderline_rows)
```

### Path C (optional): NTM panes

When the user already runs NTM (multi-pane tmux orchestrator), can spin up 3 panes — one per model — and broadcast the prompt. See [ORCHESTRATION.md § NTM](ORCHESTRATION.md#optional-ntm-swarm-topology).

---

## Triangulator subagent prompt

```
You are a multi-model triangulator. Read <workspace>/triage_borderline.tsv
(rows where confidence is in [0.5, 0.7]).

For each row, get an independent verdict from each available model
(or stance, in same-model fallback mode):
- Model/stance A: Literal application of FILE-SMELLS.md and TRIAGE-RUBRIC.md
- Model/stance B: Skeptical — assume smells might be wrong; verify via content
- Model/stance C: Forensic — trace history, understand intent
- (Council tier only) Model/stance D: Adversarial — find reasons the verdict is wrong

For each row, output to triangulation_results.tsv:
  id, verdict_A, verdict_B, verdict_C, [verdict_D], agreement, recommended_verdict

agreement is one of:
- unanimous (all agree): use that verdict; promote confidence to 0.9
- majority (2 of 3 or 3 of 4): use majority verdict; confidence stays in [0.7, 0.85]
- split (no majority): force surface-to-user; confidence stays at 0.5

If unanimous on `delete-*` or `move`: the verdict is locked; main agent
proceeds without further user check.

If majority on `delete-*` or `move`: surface to user with the dissenting
model's reasoning so the user can adjudicate.

If split: always surface to user.
```

---

## Output schema (`triangulation_results.tsv`)

```
id    verdict_A           verdict_B           verdict_C           agreement     recommended       reasoning
047   move                move                move                unanimous     move              All three agree: smell=plan-doc, refs=2, dest=docs/planning
088   delete-and-gitignore delete-and-gitignore surface-to-user    majority      delete-and-gitignore  C concerned about subtle ref in tests/conftest.py:5; A and B confirmed grep is empty
102   move                surface-to-user      delete-no-gitignore split         surface-to-user   Models disagree on whether refs in README are load-bearing
```

---

## Cost / time considerations

- **Multi-model triangulation** adds 5-15 minutes per borderline row (each model needs its own context-load + analysis).
- **Same-stance triangulation** adds 2-5 minutes per borderline row (same context, different prompt).
- Council tier on a 200-candidate run with 30 borderline rows: ~3-7 hours added.

The skill warns the user up-front: "Council tier estimated at 8+ hours; budget accordingly."

---

## When triangulation is NOT useful

- High-confidence rows (>0.85): models will agree; wastes time.
- Trivial deletes (e.g., `nohup.out` 0 bytes): rule is clear-cut.
- Protected globs: not subject to verdict change.

The skill restricts triangulation to the borderline band by default.

---

## Adjudication when triangulation fails

If triangulation can't reach majority:
1. Force `surface-to-user`.
2. The Phase 5 plan presents the row with all model verdicts side-by-side.
3. The user picks the verdict.
4. Their choice is captured in `user_overrides.tsv` with the reason "triangulation split".

This treats triangulation as a useful heuristic, not a verdict authority. The user always has the final word.
