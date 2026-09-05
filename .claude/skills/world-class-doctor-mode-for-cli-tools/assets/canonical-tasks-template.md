# Canonical Tasks (Template for Phase 10 Cold-Prober)

The cold-agent-prober subagent (Phase 10) attempts each task below using ONLY the binary, `<tool> doctor robot-docs`, and `<tool> doctor --help`. Each task tests a distinct aspect of the doctor's agent-ergonomics. The prober's transcripts are saved to `<workspace>/agent_simulations/post_pass_<N>/<task>.transcript.jsonl`.

This template covers the canonical 10 tasks. The lead agent customizes per project (adding project-specific scenarios from cass findings).

---

## Task 01 — Healthy workspace baseline

**Scenario.** A freshly-bootstrapped workspace with no findings.
**Setup.** `<tool> init` in a tempdir.
**Goal.** Confirm the doctor reports healthy with exit 0.

Expected agent invocation:
```
<tool> doctor
```

Expected behavior:
- Exit 0
- Output ≤ 5 lines mentioning "healthy" / "ok" / equivalent
- `<tool> doctor --json | jq -e .ok` returns true

If the prober gets stuck here, the doctor's first-try-success (Axiom 0) is broken.

---

## Task 02 — Diagnose a single P2 finding

**Scenario.** Workspace with one P2 finding (the prober doesn't know which).
**Setup.** Run `tests/doctor_fixtures/fm-state-files-jsonl-tombstone-drift/corrupt.sh`.
**Goal.** Identify the finding, propose a remediation.

Expected agent invocation:
```
<tool> doctor --json
```

Expected response from the agent's perspective:
- Find one P2 finding in `findings[]`
- Read its `remediation.command` field
- Plan to run that command next

If the prober reads the human-readable output (not `--json`), score `agent_ergonomics` lower.

---

## Task 03 — Apply the fix and verify

**Scenario.** Continued from Task 02.
**Goal.** Apply `--fix`, confirm healthy.

Expected:
```
<tool> doctor --fix --only fm-state-files-jsonl-tombstone-drift
<tool> doctor   # exit 0
```

If the prober runs `--fix` without `--only`, that's still acceptable but score `agent_ergonomics::macros-vs-granular` lower (the prober didn't use the precise targeting).

---

## Task 04 — Reverse a fix that went wrong

**Scenario.** After Task 03, simulate user regret: undo the fix.
**Goal.** Restore byte-identical to corrupted state.

Expected:
```
<tool> doctor undo latest
```

Or if the prober inspects more carefully:
```
<tool> doctor ls
<tool> doctor undo <specific-run-id>
```

If the prober doesn't find the undo command in `<tool> doctor --help`, score `diagnostic_specificity` lower.

---

## Task 05 — Diagnose a P0 finding (refused for safety)

**Scenario.** Workspace with the project's lock currently held by another (simulated) process.
**Setup.** `tests/doctor_fixtures/scenarios/lock_held_by_other.sh` (creates a fake lock file with a live PID).
**Goal.** Recognize the doctor refused with exit 5; understand why; suggest the right next move.

Expected:
```
<tool> doctor --json
# Exit 5; output includes a finding with reason="lock_held"
```

Agent should plan: "wait for the lock holder and retry, OR if the evidence proves the holder is stale, follow the doctor's stale-lock remediation path." `--force --yes` is not a valid response to a live lock.

If the prober suggests `--force --yes` for the live-lock case, score `blast_radius_containment` lower.

---

## Task 06 — Multi-finding fix

**Scenario.** Workspace with 5 findings: 1 P0, 2 P1, 2 P2 (combinatorial).
**Setup.** Run multiple corrupt.sh scripts.
**Goal.** Plan the fix order; apply.

Expected:
```
<tool> doctor --robot-triage --json
# Returns {actions_planned: [...], recommended_command: "..."}
<tool> doctor --fix
# Applies in dependency-graph order; reports actions_taken: 5
<tool> doctor   # exit 0
```

If the prober applies fixes in the WRONG order (P2 before P0), the doctor SHOULD have prevented this via `dependency_graph.json`. If it didn't, score `data_safety` lower.

---

## Task 07 — Refuse to fix because of unmet precondition

**Scenario.** Schema migration required, but the binary doesn't have the migration script.
**Setup.** Plant a beads.db with `schema_version` two versions ahead of binary's compiled version.
**Goal.** Recognize the doctor refused with exit 4; identify the unmet precondition.

Expected:
```
<tool> doctor --json
# Exit 4; finding: schema downgrade required; doctor refuses.
```

Agent reads `manual_remediations[]` to find the upgrade instruction.

---

## Task 08 — Online check (optional)

**Scenario.** Run `<tool> doctor --online` against a tool that has online detectors.
**Setup.** Network available; vendor sandbox configured.
**Goal.** Online detectors run; their findings appear.

Expected:
```
<tool> doctor --online --json
# Network detectors execute; emit any vendor-side findings.
```

If `--online` is unavailable in the test environment, the prober skips this task and notes it.

---

## Task 09 — Capabilities reflection

**Scenario.** Discover what the doctor can do.
**Goal.** Read the contract.

Expected:
```
<tool> doctor capabilities --json | jq '.detectors | length'
<tool> doctor capabilities --json | jq '.fixers | length'
<tool> doctor capabilities --json | jq '.exit_codes | keys'
<tool> doctor robot-docs
```

If the prober reads SKILL.md or any other workspace file, the test is invalid (Phase 10 fresh-context discipline).

---

## Task 10 — Concurrency-safety smoke

**Scenario.** Two doctor invocations in parallel.
**Setup.** A corrupted fixture; spawn `<tool> doctor --fix` twice.
**Goal.** One wins, one refuses with exit 5.

Expected:
```
( cd $sandbox && <tool> doctor --fix ) &
( cd $sandbox && <tool> doctor --fix ) &
wait
# Exactly one of the two exited 0/2; the other exited 5.
```

The prober reports the actual exit codes observed.

---

## After all tasks

The prober writes `<workspace>/agent_simulations/post_pass_<N>/notes.md`:

```markdown
# Cold-Prober Notes — Pass <N>

## Tasks attempted: 10
## Tasks completed: <X>
## Tasks stuck: <Y>
## Tasks skipped (e.g., --online unavailable): <Z>

## Confusing surfaces
- <e.g., "Task 04: --help did not mention `undo latest` is a valid form;
       I had to grep the source to find it.">

## Wished-this-existed
- <e.g., "Task 10: I could have used a `<tool> doctor --concurrent-test` flag
        to deliberately exercise the lock contention.">

## Per-task summary
| Task | Result | Time-to-action | Notes |
|------|--------|----------------|-------|
| 01   | pass   | < 5s           |       |
| 02   | pass   | < 30s          |       |
| ...  | ...    | ...            | ...   |
```

This summary feeds Phase 10's polish pass — the most acted-on items.

---

## Customizing the canonical tasks

The lead agent customizes Tasks 01–10 per project:

- For Pattern 4 (daemon CLI): add a "daemon-running" task variant.
- For Pattern 7 (AI-agent CLI): add a session-integrity task.
- For Pattern 9 (distributed): expand Task 08 with vendor-specific scenarios.
- For Pattern 10 (absorb-playbook): add tasks that exactly replicate the source playbook's user scenarios.

The 10 canonical tasks are the universal subset; project-specific tasks 11+ are appended.
