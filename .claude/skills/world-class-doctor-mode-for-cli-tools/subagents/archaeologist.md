# subagent: archaeologist (Phase 1, parallel by subsystem)

**Description.** Enumerate every realistic failure mode for ONE subsystem of the target CLI. Cross-reference bug tracker, git log, cass findings, and AGENTS.md.

## Inputs

- `{{target}}` — target repo path
- `{{subsystem}}` — one of `state_files | configs | schemas | caches | sockets | hooks | plugins | secrets | permissions | external_artifacts | concurrency_primitives | network | userland_state` (or a project-specific one)
- `{{subsystem_paths}}` — paths under target_repo that constitute this subsystem
- `{{workspace}}/cass_findings.jsonl` — output of `scripts/cass-mine.sh` (Phase 0)
- `{{workspace}}/changelog_findings.jsonl` — output of `scripts/mine-changelog.py` (Phase 0). Pre-classified bug-fix lines from the target's CHANGELOG, keyed to `classified_subsystem`. Filter for entries matching this archaeologist's `{{subsystem}}` — these are real past failure modes the doctor should detect.
- `{{workspace}}/known_fms_for_language.jsonl` — output of `scripts/query-corpus.py --language <lang>` (Phase 0). Pre-suggested FMs from the cross-project corpus (`references/corpus/known-fms.jsonl`). Use as a seed list; many will already apply to this target.

## Outputs

- `{{workspace}}/analysis/failure_modes/{{subsystem}}.md`
- One row appended to `{{workspace}}/analysis/inventory_summary.md`

## Prompt

The full prompt is in [../references/methodology/AGENT-PROMPTS.md § archaeologist](../references/methodology/AGENT-PROMPTS.md#archaeologist-phase-1). Use verbatim.

## Exit criteria

- `{{workspace}}/analysis/failure_modes/{{subsystem}}.md` has ≥ 3 failure modes (or an explicit "n/a" block per category)
- Every FM file passes `python3 scripts/validate-fm.py {{workspace}}/analysis/failure_modes/{{subsystem}}.md` (exit 0)
- Inventory summary updated

## Failure modes

- The subsystem genuinely has no failure modes worth detecting (rare). Write the file with a single `## n/a` block citing why and the search you did.
- Bug tracker has 0 issues touching the subsystem. That's data — note it. Mine git log + cass instead.
- Hundreds of issues. Cluster by symptom; produce ~10 representative FMs, not 100.
