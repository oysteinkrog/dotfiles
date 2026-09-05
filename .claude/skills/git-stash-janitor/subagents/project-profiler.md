---
name: project-profiler
description: Phase 1 — read AGENTS.md/README.md, run codebase archaeology, detect primary branch and quality-gate commands, write project_profile.json.
---

# Project Profiler

Owns Phase 1. Reads the project's instructions, samples the codebase, and produces `project_profile.json` — the source of truth for primary branch, quality-gate commands, conventions, and stash-message patterns.

## Inputs at invocation

- `{PROJECT}` — absolute path to the target repo
- `{WORKSPACE}` — `<project>/.stash_janitor_workspace/`

## Workflow

Use the **Brennerian opener** verbatim:

> First read ALL of the AGENTS.md file (or AGENT.md, CLAUDE.md, .cursor/rules/*, .github/copilot-instructions.md — whatever the project uses) and the README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code and technical architecture and purpose of the project.

After reading the rules:

1. Run `scripts/discover-project.sh {PROJECT}` to scaffold `project_profile.json` with auto-detected fields.
2. Read 5–10 representative source files (largest top-level directories) to understand architecture.
3. Sample the last 50 commit messages to confirm the auto-detected commit-message convention.
4. Inspect the existing stash list's message prefixes to populate `stash_message_conventions`.
5. Augment `project_profile.json` with a 200-word `architecture_summary` field.

## Coordination

- File reservation: `paths=[".stash_janitor_workspace/project_profile.json"]`, `reason="stash-janitor-phase1"`, `exclusive=true`, `ttl_seconds=900`.
- Thread id: `stash-janitor-<run-id>`.

## Quality gates

- [ ] AGENTS.md / CLAUDE.md / equivalent has been read in full
- [ ] README.md has been read in full
- [ ] `project_profile.json` has a non-empty `primary_branch`, and has `test_command` / `typecheck_command` keys (empty string means no command detected)
- [ ] Stash message prefixes sampled from real `git stash list` output
- [ ] Architecture summary is ≥150 words and references actual file paths from the repo

## Exit criteria

`project_profile.json` exists and is read-back valid JSON. Main agent reads the `architecture_summary` to the user as a sanity check.
