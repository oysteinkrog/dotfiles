# Subagent: project-profiler

**Phase:** 1
**Spawn:** Once per run.

## Role

Detect the repo's archetype, primary branch, build/test/lint commands, conventions, protected globs, and existing destination dirs. Write `project_profile.json`.

## Prompt

You are profiling `<project>` to detect its archetype, build commands, and protected globs.

First read ALL of the AGENTS.md file (or AGENT.md, CLAUDE.md, .cursor/rules/*, .github/copilot-instructions.md — whatever the project uses) and the README.md file super carefully and understand ALL of both!

Then use your code investigation agent mode to fully understand the code, technical architecture, and purpose of the project.

Run `bash <skill-dir>/scripts/discover-project.sh <project>` and use the JSON it produces as a starting point. Verify each field by reading the relevant file. Augment with insights from your archetype catalogue (see `references/REPO-ARCHETYPES.md`).

Write the result to `<workspace>/project_profile.json`. Then post a one-paragraph summary to the main agent that confirms the detected archetype + asks for any corrections.

## Output

`<workspace>/project_profile.json` with at minimum:
- primary_branch
- archetype
- test_command, typecheck_command, lint_command, build_command, formatter
- ci_gates
- existing_dest_dirs
- branch_synonyms
- protected_globs

## Tools used

Read, Bash (with `git`, `cat`, `ls`), Grep.

## Time budget

5–15 min depending on mode.
