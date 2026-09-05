# subagent: implementer (Phase 4, parallel by subsystem)

**Description.** Implement detectors, fixers, the `mutate()` chokepoint, backup/restore primitives, per-run artifact emission, and the `<tool> doctor` surface in the project's native language. ONE subagent per subsystem.

## Inputs

- `{{workspace}}/analysis/repair_specs/*.md` (filter to your subsystem)
- `{{workspace}}/analysis/dependency_graph.json` (your fixers depend in this order)
- `{{workspace}}/analysis/safety_envelope.md`
- `../references/recipes/{{language}}.md` (language-specific recipe)
- `../references/methodology/MUTATE-CHOKEPOINT.md` (READ FIRST)
- `../references/methodology/CLI-SURFACE.md` (verbatim help + flags + JSON shapes)
- `../references/methodology/OUTPUT-SCHEMA.md` (run-artifact layout)
- `../references/exemplars/exemplars.md` (canonical patterns)

## Outputs

- Code on the feature branch `doctor-mode-pass-{{N}}` of `{{target}}`
- One commit per repair spec
- One bead per spec
- Per-FM rows appended to `{{workspace}}/applied_changes.jsonl`

## Prompt

Full prompt in [../references/methodology/AGENT-PROMPTS.md § implementer](../references/methodology/AGENT-PROMPTS.md#implementer-phase-4). Use verbatim.

## Critical non-negotiables (verbatim)

- READ MUTATE-CHOKEPOINT.md BEFORE WRITING ANY CODE.
- Detectors are PURE. They never call `mutate()`, never write to disk.
- Fixers route EVERY write through `mutate(path, op)`. No exceptions.
- The doctor surface MUST match `CLI-SURFACE.md` verbatim — same flag spelling, same exit codes, same JSON shape.
- Use the project's existing build system, lint, and test runner.
- One commit per spec. Commit message: `doctor({{subsystem}}): {{fm_id}}: <verb>`.
- Acquire Agent Mail file reservations for any file shared across implementers (`mutate.<ext>`, run-artifact emitter, capabilities schema, `--help` text generator). Thread id: `doctor-{{N}}-impl-{{subsystem}}`.

## Critical AGENTS.md compliance

- **No file deletion** (per AGENTS.md RULE 1). Quarantine via `Op::Rename` instead. The `Op` enum has no `DeletePath` variant under `--fix`.
- **No destructive shell** (`rm -rf`, `git reset --hard`, `git clean -fd`). Implement equivalent semantics in code.
- **No backwards-compat shims**. Per AGENTS.md, just change the code.
- **No script-based code transformations**. Manual edits or targeted Edit-tool calls only.

## Exit criteria

- Project's build system green (cargo build / go build / bun run typecheck / pytest --collect-only / equivalent)
- `scripts/validate-doctor.sh {{target}}` exits 0
- `<tool> doctor --help`, `--fix`, `--dry-run --fix`, `--json`, `--robot-triage`, `capabilities --json`, `robot-docs`, `health`, `undo <id>`, `explain <id>`, `ls`, `gc --before <date> --yes` all exist and respond correctly on a fixture
- Each commit's diff stands alone

## Failure modes

- A spec's detector requires a feature the language doesn't have (e.g., reflective struct iteration in Bash). Implement it differently — drop the elegance, keep the contract. File an "ergonomic improvement" bead at priority 3.
- The `mutate()` chokepoint requires a per-path lock primitive the language's stdlib doesn't have. Use a well-maintained crate/module (`fs2`, `portalocker`, `proper-lockfile`). Note the dependency in the recipe; not a blocker.
- The project's existing build system has a hook that conflicts with doctor's writes (e.g., a pre-commit that runs the formatter, which would touch our backup files in `.doctor/`). Add `.doctor/` to the formatter's ignore list and to the project's `.gitignore` if not already.
