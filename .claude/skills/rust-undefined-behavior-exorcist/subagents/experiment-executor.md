---
name: experiment-executor
description: Runs one EXP-NNN from UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md, records the verdict in place. Phase 5.
---

# Experiment Executor

**Invoke with `subagent_type=general-purpose`** — writes the reproducer file, the log, and edits the verdict in-place. `Explore` cannot.

One subagent per OPEN experiment per round. Fan out massively in parallel.

> **Preferred reproducer pattern: standalone-cargo-project harness.** Author `{WORKSPACE}/exp-harness-{EXP_ID}/Cargo.toml` + `src/main.rs` that path-depends on the audit target. This avoids the `cargo test --test NAME` gotcha (which fails on auto-discovered tests without explicit `[[test]]` entries). See [EXPERIMENT-DESIGNS.md §Standalone Harness](../references/EXPERIMENT-DESIGNS.md#standalone-cargo-project-harness-recommended-default).

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{EXP_ID}` — e.g., `EXP-007` or `EXP-007-a`

## Workflow
Use [Phase 5 experiment-executor prompt](../references/AGENT-PROMPTS.md#phase-5--experiment-executor-one-per-exp-nnn) verbatim.

## Outputs
- `{WORKSPACE}/experiments/{EXP_ID}/repro.rs` (and `Cargo.toml` if standalone)
- `{WORKSPACE}/phase5_experiment_results/{EXP_ID}.log` (raw tool output)
- In-place edit of the `## {EXP_ID}` block in `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md`:
  - Verdict: one of `CONFIRMED_UB` / `NO_EVIDENCE` / `NEEDS_REFINEMENT` / `DEFERRED`
  - Notes: filled with observations

## Quality gates
- [ ] Verdict is one of the four exact strings (parseable by `convergence-tracker.sh`)
- [ ] Raw log file referenced
- [ ] If NEEDS_REFINEMENT, a follow-up `{EXP_ID}-a` is created with the new hypothesis
- [ ] DEFERRED verdicts include rationale + re-check criteria

## Failure modes
- **Verdict on wrong experiment:** Edit-in-place must target the exact `## {EXP_ID}` heading. Use exclusive reservation on the file during the edit.
- **Spawning extra hypotheses without recording them:** every new EXP-NNN-a gets a full block with verdict OPEN, never inline as a note
- **Skipping the log:** without the raw log, the verdict can't be audited; the log is mandatory

## Coordination
Reservation: `path://{WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` exclusive while editing (TTL 5min).
Mail thread: `ub-exorcism-{RUN_ID}-phase5-{EXP_ID}`.
