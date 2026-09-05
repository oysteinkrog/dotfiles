# subagent: synthesizer (Phase 3, single agent)

**Description.** Read all repair specs and produce taxonomy, dependency graph, conflict matrix, project-specific safety envelope, and the user-facing playbook narrative chapters.

## Inputs

- All `{{workspace}}/analysis/repair_specs/*.md`
- All `{{workspace}}/analysis/failure_modes/*.md`
- `../references/methodology/SAFETY-ENVELOPE-TEMPLATE.md`

## Outputs

- `{{workspace}}/analysis/taxonomy.md`
- `{{workspace}}/analysis/dependency_graph.md` + `dependency_graph.json`
- `{{workspace}}/analysis/conflict_matrix.md`
- `{{workspace}}/analysis/safety_envelope.md`
- `{{workspace}}/playbook.md` (the user-facing narrative)
- `{{workspace}}/recommendations.jsonl` — ranked recommendations consumed by Phase 4 implementer and emitted as the primary deliverable for `audit-only` mode. **Schema is defined in [IO-CONTRACTS.md § recommendations.jsonl](../references/methodology/IO-CONTRACTS.md) — use that as the source of truth.** Each line is a JSON object: `{id, title, priority, estimated_uplift, complexity, applied, diff_sketch}`. Field guidance:
    - `id`: an R-NNN identifier for this recommendation (NOT the same as `fm_id` — one FM may produce multiple recommendations, and one recommendation may address multiple FMs).
    - `title`: short human-readable summary of the proposed change.
    - `priority`: numeric float derived from the FM(s) the recommendation addresses (use `frequency × blast_radius × severity_weight` as a starting heuristic; ranking matters more than absolute value).
    - `estimated_uplift`: object keyed by scoring-rubric dimensions (e.g., `{"data_safety": 200, "observability": 50}`) — predicted score-points-gained per dimension if applied. Estimate from the spec's claims, refined by experience.
    - `complexity`: `"S"`, `"M"`, or `"L"` — implementer effort.
    - `applied`: always `false` at synthesizer-emission time; Phase 4 implementer flips to `true` after merging.
    - `diff_sketch`: one-line summary of what the patch will look like (e.g., `"Add fsync after each WriteFile op in mutate.rs"`).

## Prompt

Full prompt in [../references/methodology/AGENT-PROMPTS.md § synthesizer](../references/methodology/AGENT-PROMPTS.md#synthesizer-phase-3). Use verbatim.

## Required sections in `playbook.md`

Three chapters, all required:

1. **What doctor will and will not do.** Capabilities + the negative-space spec ("doctor will NEVER delete during diagnose/fix/undo / run rm -rf / probe network without --online / mutate when lock is held"), plus the separate `gc --before <date> --yes` retention-cleanup exception.
2. **What you should back up first.** Even though doctor backs up, recommend the user `git stash` + a separate copy of the workspace before pass-1 in upgrade mode.
3. **How to recover if doctor itself goes wrong.** Meta-recovery: invoking `doctor undo` from a busted state, reading `actions.jsonl` manually, where verbatim backups live, what to do if the lock file itself is corrupted.

## Exit criteria

- `dependency_graph.json` is a DAG (verified by `scripts/validate-dag.py`)
- Every conflict pair has a one-line "why"
- `safety_envelope.md` extends but does not contradict the universal envelope
- `playbook.md` has all three required chapters
- `recommendations.jsonl` exists and every line parses as JSON matching the IO-CONTRACTS.md schema (caught by Phase 4's pre-implementer validator)

## Failure modes

- Two repair specs disagree about which write goes first. The synthesizer's job is to pick one and document the choice. If the choice is non-obvious, file a question for the implementers ("at Phase 4, please confirm <X> is the right ordering").
- Cycles in the dependency graph. Hard stop — this is a real problem. Identify which spec is wrong (usually one assumed a precondition that another invalidates) and re-enter Phase 2 for those FMs.
