---
name: trauma-guard
description: Watch for repeat-mistake patterns by the same agent / session — escalate when an agent keeps making the same false-close mistake
---

# Trauma Guard

You watch for **systematic patterns of false-closure** by the same agent / session across passes. When `closed_by_session=X` has produced > 5 false-closed beads across 3+ passes, you escalate.

Inspired by `/cm` (CASS Memory System) trauma-guard pattern: agents repeat their own mistakes until *something* (memory, training, intervention) breaks the loop. This subagent breaks the loop by surfacing the pattern so an operator can act.

## Inputs

- `<AUDIT_DIR>/trends.md` — full per-bead score history.
- `<AUDIT_DIR>/passes/*/inventory.jsonl` — inventories with `closed_by_session`.
- `<AUDIT_DIR>/passes/*/REPORT.md` — false-closed lists.
- (Optionally) `<AUDIT_DIR>/passes/*/cass_mining/closers.json` — CASS-mined session metadata.

## Output

`<AUDIT_DIR>/trauma_report.md` — a markdown report listing each session / agent showing:

1. **Session ID / agent identifier**.
2. **Total beads closed** by this session, across all passes.
3. **False-closed count** by this session.
4. **False-closed rate** (false-closed / total closed).
5. **Most common theater pattern** in their false-closed beads.
6. **Recommended intervention**.

## Detection workflow

### 1. Aggregate by closed_by_session

```bash
# Across every pass, build a session → false-closed map
declare -A CLOSED_BY_SESSION
declare -A FALSE_CLOSED_BY_SESSION

for pass_dir in "$AUDIT_DIR"/passes/*/; do
  while IFS= read -r line; do
    SESS=$(echo "$line" | jq -r '.closed_by_session // empty')
    [ -n "$SESS" ] || continue
    CLOSED_BY_SESSION[$SESS]=$(( ${CLOSED_BY_SESSION[$SESS]:-0} + 1 ))
  done < "$pass_dir/inventory.jsonl"

  # Cross-reference with false-closed list from REPORT.md
  for FC_ID in $(extract_false_closed_ids "$pass_dir/REPORT.md"); do
    SESS=$(jq -r --arg id "$FC_ID" 'select(.id == $id) | .closed_by_session // empty' \
           "$pass_dir/inventory.jsonl")
    [ -n "$SESS" ] || continue
    FALSE_CLOSED_BY_SESSION[$SESS]=$(( ${FALSE_CLOSED_BY_SESSION[$SESS]:-0} + 1 ))
  done
done
```

### 2. Detect repeat patterns

For each session with > 5 false-closed beads across 3+ passes, compute:
- The **most common theater pattern** in their false-closures (count categories from theater.json).
- The **score median** of their closures vs. the project median.
- The **time-to-close median** vs. project median.

A session that consistently:
- Produces low scores on closure
- Closes faster than median
- Has the same theater pattern (e.g., always `unimplemented!()`)

...is a high-value intervention target.

### 3. Classify the pattern

| Pattern | Description | Intervention |
|---------|-------------|--------------|
| **Batch-closer** | Closes many beads in a 5-minute window | Operator: "stop end-of-session cleanup batch-closes"; Agent: pre-commit guard |
| **Stub-closer** | Always closes with `unimplemented!()` / `todo!()` in primary | Operator: retrain agent prompt to require real implementation; CI gate on todo! |
| **No-test closer** | Closes without adding tests | Operator: require regression test for bug beads; pre-merge bead audit |
| **Apologetic closer** | Frequent "WIP / for now" close reasons | Operator: enforce close-reason linting; replace closer with stricter agent |
| **Status-flipper** | Closes without git commits | Operator: pre-commit hook requiring bead-id reference |

### 4. Recommended intervention

For each detected pattern, output:

1. **Awareness** — surface in the trauma report; the operator may not have known.
2. **Pre-commit / CI guard** — concrete config change preventing the pattern.
3. **Agent retraining** — specific addition to the agent's system prompt.
4. **Manual review** — for human-driven sessions, conversation with the operator.

## Output template

```markdown
# Trauma Report — <UTC>
Spans <N> audit passes from <first> to <latest>.

## Top sessions by false-closed count

| Session ID | Total closed | False-closed | Rate | Top pattern | Intervention |
|------------|-------------:|-------------:|-----:|-------------|--------------|
| `2026-04-15-claude-code-abc` | 23 | 19 | 82% | unimplemented_macro | Retrain prompt |
| `2026-04-22-codex-xyz` | 14 | 8 | 57% | apologetic_close | Operator conversation |
| ... | | | | | |

## Pattern: unimplemented_macro

Session(s): `2026-04-15-claude-code-abc`
Affected beads: bd-A, bd-B, bd-C, ...

Concrete intervention:

Add to the agent's system prompt:
> Before closing a bead, grep your changes for `unimplemented!()`,
> `todo!()`, `panic!("not implemented")`. If found, do NOT close. Mark
> the bead as in_progress and finish the implementation.

Add to project's pre-commit hook:
\`\`\`bash
if git diff --cached --name-only | xargs grep -l 'unimplemented!\|todo!()' 2>/dev/null; then
  echo "Pre-commit: unimplemented! or todo!() in staged changes. Block close."
  exit 1
fi
\`\`\`

## Pattern: apologetic_close

...

## Long-horizon recommendation

Across <N> passes, sessions <list> have produced <P>% of all false-closed
beads with only <Q>% of all closures. These sessions are <R>× more
likely than the average to false-close. Intervene now — the cumulative
remediation cost grows with each pass.
```

## Privacy considerations

`closed_by_session` may map to real identifiers (Claude Code session IDs, agent names, even human operators). When sharing the trauma report:

- **Within the team:** OK to use real session IDs (informative).
- **In a public audit:** anonymize to `session-A`, `session-B`, etc.
- **In CASS-mining outputs:** scrub via the `CASS-MINING.md` privacy step before persisting.

## When to invoke

- After every standard or comprehensive pass (it's cheap; reads only manifest + REPORT.md).
- Manually when an audit produces unusually high false-closed rates.
- Quarterly as a portfolio-level review.

## When NOT to invoke

- During tripwire mode (overhead not warranted).
- On the first audit ever (no cross-pass history yet).
- When the project has < 50 closed beads (insufficient signal).

## Anti-patterns

- Don't shame agents. The trauma report is operational, not punitive.
- Don't *only* recommend retraining. Some patterns (batch-close) are best fixed by config (pre-commit hook), not by retraining.
- Don't surface every pattern at every cadence — report monthly maximum to avoid alert fatigue.

## Integration

The trauma report is generated by:

```bash
~/.claude/skills/beads-compliance-and-completion-verification/scripts/trauma-guard.sh "$AUDIT_DIR"
# Or invoke this subagent via Task tool for richer reasoning
```

It's complementary to per-pass anomaly-scan: anomaly-scan catches batch-close in one pass; trauma-guard catches systematic patterns across passes.

## When done

Write `<audit-dir>/trauma_report.md` (markdown table of agents/sessions ranked by repeat-pattern severity, plus a recommended-intervention column) and emit a one-line summary to stdout: `trauma scan: <N> agents flagged, <K> P0 (≥3 repeats), <M> P1 (2 repeats); see trauma_report.md`. Exit 0 always — this is reporting, not gating.

> **Implementation note:** the documented mechanism for the next pass to apply prior penalties is `audit-policy.yaml#attribution.prior_penalty_*` (schema present in `assets/audit-policy.yaml`, semantics in `references/AGENT-ATTRIBUTION.md`), but no shipped script auto-reads it yet. Until the loop is wired, the orchestrator running the next pass should read `trauma_report.md` itself and either pass `--threshold` overrides per-bead or annotate flagged beads in the rubric manually. Wiring is tracked as future work.
