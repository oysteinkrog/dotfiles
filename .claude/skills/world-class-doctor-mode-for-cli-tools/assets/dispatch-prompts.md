# Dispatch Prompts — Quick Reference

Shorthand prompts for the calling agent to invoke each phase / mode quickly. These are *user-facing* prompts that pre-fill the most common parameters. The full per-phase prompts live in [AGENT-PROMPTS.md](../references/methodology/AGENT-PROMPTS.md).

---

## "Apply the skill end-to-end"

```
Apply the world-class-doctor-mode-for-cli-tools skill to this project:

Target: {{cwd}}
Mode: {{auto-detect; ask if ambiguous}}
Triangulation: peer-claude
CASS: quick
Online: offline-only

Walk through Phase 0 confirmations with me, then run all 10 phases. Stop on any
hard-stop trigger and surface for review. Do not push to main without my
explicit approval.
```

## "Just score it; don't change anything"

```
Apply the world-class-doctor-mode-for-cli-tools skill in audit-only mode:

Target: {{cwd}}
Mode: audit-only

Run Phases 0, 1, 6 (scoring only). Produce scorecard.md, heatmap.svg,
recommendations.jsonl, playbook.md. Do not modify any code in the target
repo. Report the aggregate score and the top 5 below-quartile findings.
```

## "Score against the previous pass"

```
Re-score doctor-mode for {{tool}} against the current target HEAD:

Target: {{cwd}}
Mode: re-score-only
Previous pass workspace: {{auto-detect from manifest}}

Run Phase 6 only. Compare against pass-{{previous}} scorecard. Hard-stop
if any FM regressed > 50 points without a documented ACK.
```

## "Absorb a manual playbook"

```
Apply the world-class-doctor-mode-for-cli-tools skill in absorb-playbook
mode:

Target: {{target-repo}}
Source playbook skill: {{path-to-skill}}
Mode: absorb-playbook
Triangulation: multi-model

Convert each step of the source playbook into a Repair Spec. Run all 10
phases. Phase 8 demotes the source playbook to "fallback" status without
deleting any of its content (per AGENTS.md no-delete).
```

## "Fix one specific failure mode"

```
Single-failure-mode-rescore for the doctor on {{tool}}:

Target: {{target-repo}}
FM id: {{fm-id}}
Mode: single-failure-mode-rescore

Re-mine evidence for {{fm-id}} (Phase 1 scoped to that one FM); re-score
(Phase 6 scoped). Append one row to failure_mode_scores.jsonl; do not touch
other FMs. Hard-stop if the FM regressed > 50 pts.
```

---

## Mid-pass dispatch helpers

These are useful WHILE a pass is running; the lead agent dispatches them on demand.

### "Run the safety harness for one fixer"

```
Run the five Phase-5 verifiers against fm-{{id}} on the current branch:

  export TOOL={{tool}}
  scripts/verify-undo.sh fm-{{id}}
  scripts/verify-idempotence.sh fm-{{id}}
  scripts/verify-crash-recovery.sh fm-{{id}}
  scripts/verify-concurrency.sh fm-{{id}}
  scripts/verify-metamorphic.sh fm-{{id}}

Report any failures; do NOT proceed to Phase 6 if any verifier fails.
```

### "Run the validator and report violations"

```
Run scripts/validate-doctor.sh against {{target}}. For each violation
reported, classify: genuine (file a bead) or false positive (extend the
allow-list). Report the classification.
```

### "Re-render the scorecard"

```
Re-render the scorecard from failure_mode_scores.jsonl:

  python3 scripts/scorecard.py render {{workspace}}

Show the aggregate score and the top 5 / bottom 5 FMs. If pass-N+1, also
run scorecard.py compare-against-baseline {{new}}.json {{baseline}}.json
--max-regression-points=50 and report.
```

### "Spawn fresh-eyes round N"

```
Dispatch a fresh-context fresh-eyes subagent (NO context inheritance from
this conversation) with the calibrated prompt for round {{N}} from
PHASES.md § Phase 7. Capture the agent's findings to
{{workspace}}/fresh_eyes_round_{{N}}.md. Run UBS / clippy / cargo test
afterward. Report status.
```

### "Run the full fixture suite"

```
Run tests/doctor_fixtures/run_all.sh in {{target}}. Report:
- Number of fixtures: N
- Passed: M
- Failed: K (with list of fixture names)
- Round-trip integrity: percentage of fixtures whose
  corrupt → fix → assert → undo → cmp-strict round-tripped
```

### "Update HANDOFF.md"

```
Run subagents/handoff-writer.md against the current pass. Pass:

  pass_n: {{N}}
  workspace: {{workspace}}
  target_sha_before: {{sha-at-pass-start}}
  target_sha_after: {{sha-at-pass-end}}

The output is {{workspace}}/HANDOFF.md.
```

---

## Common mistakes the dispatch prompts protect against

- **Forgetting to specify mode.** The dispatch prompts above always include `Mode: ...`.
- **Implicit triangulation.** Always state explicitly to avoid silently degrading from `multi-model` to `none`.
- **Forgetting offline-by-default.** State explicitly so an agent doesn't accidentally probe network.
- **Pushing without approval.** All dispatch prompts include "Do not push to main without my explicit approval" or equivalent.
- **Stalling on a hard-stop.** Dispatch prompts describe what to do (surface for review, don't proceed silently).

---

## When to use these vs. the verbatim AGENT-PROMPTS.md

- These dispatch prompts: at the **edges of the conversation** (user → top-level agent).
- AGENT-PROMPTS.md: **between** phases (top-level agent → subagent).

The dispatch prompts pre-fill what the user usually wants; the AGENT-PROMPTS prompts are the calibrated, verbatim instructions to receive subagents.
