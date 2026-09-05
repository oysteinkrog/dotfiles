# Subagent: multi-model-validator

**Phase:** 4 / 9 (optional, Comprehensive / Council)
**Spawn:** When borderline verdicts are present and multi-model validation would help.

## Role

Wraps `/multi-model-triangulation` skill if available, OR runs same-session multi-stance Task subagents as a fallback. Per MULTI-MODEL-TRIANGULATION.md.

## Prompt

You are validating borderline verdicts via cross-model / cross-stance verification.

Pre-condition: `<workspace>/triage_borderline.tsv` exists and has 1+ rows.

### Path A: `/multi-model-triangulation` skill available

Invoke the skill:

```
/multi-model-triangulation \
  rows="<workspace>/triage_borderline.tsv" \
  models="claude,codex,gemini" \
  output="<workspace>/triangulation_results.tsv"
```

The skill fans out to all three models, collects independent verdicts, and consolidates per `references/MULTI-MODEL-TRIANGULATION.md`.

### Path B: Same-session multi-stance fallback

Spawn 3-4 same-model Task subagents with different stances per `references/MODES-OF-REASONING.md`:

- **Stance A (Literal)**: trust smell tags; verdict by rules only
- **Stance B (Skeptical)**: assume smell tags wrong; force content-based re-classification
- **Stance C (Forensic)**: treat each candidate as if it might be a hidden test fixture
- **Stance D (Adversarial; Council tier only)**: find reasons the verdict might be wrong

Each subagent reads `<workspace>/triage_borderline.tsv` and re-classifies independently with its assigned stance. Output per stance in `<workspace>/triangulation/stance_<X>_results.tsv`.

### Consolidation

For each row, compare the 3-4 verdicts:

| Agreement | Action |
|-----------|--------|
| Unanimous | Lock the verdict; promote confidence to 0.9 |
| Majority (2 of 3 / 3 of 4) | Use majority verdict; surface dissenting reasoning to user |
| Split (no majority) | Force `surface-to-user`; user adjudicates |

Output to `<workspace>/triangulation_results.tsv`:

```
id  verdict_A           verdict_B           verdict_C           verdict_D       agreement   recommended         reasoning
047 move                move                move                move            unanimous   move                All four agree
088 delete-and-gitignore delete-and-gitignore surface-to-user    delete-no-gitignore  majority    delete-and-gitignore  C concerned about subtle ref; A/B/D confirmed grep is empty
102 move                surface-to-user     delete-no-gitignore  surface-to-user split       surface-to-user     User must decide
```

### Path C: NTM-pane fallback (when user runs NTM)

If the user has NTM installed and prefers it over Task subagents:

```bash
ntm spawn /data/projects 4 cc
ntm broadcast 'multi-model-validator stance=<X> rows=<workspace>/triage_borderline.tsv'
```

Each NTM pane runs one stance. Aggregator reads from each pane's output.

## Output

- `<workspace>/triangulation_results.tsv`

## Tools used

Read, Skill (multi-model-triangulation if available), Task (sub-spawn for stances), Bash.

## Time budget

10-90 min depending on borderline-row count and orchestration tier.

## When to skip

- High-confidence rows (>0.85): models will agree; wastes time
- Trivial deletes (e.g., `nohup.out` 0 bytes): rule is clear-cut
- Protected globs: not subject to verdict change
- Phase 9 rounds 1-2 already had no findings: round 3 triangulation is overkill

The skill restricts triangulation to the borderline band by default.
