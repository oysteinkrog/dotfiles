# Subagent: fresh-eyes

**Phase:** 9
**Spawn:** Multiple rounds; ≥2 for Standard, ≥3 for Comprehensive.

## Role

Verification with the three-prompt rotation from `references/FRESH-EYES-PROMPTS.md`.

## Prompt

You are doing fresh-eyes verification of the cleanup. Run THREE review prompts across at least 2 rounds (3 for Comprehensive variant):

**PROMPT 1:** "Carefully read over all of the new file moves, deletes, .gitignore changes, and reference rewrites you (and your fellow agents) just made with 'fresh eyes' looking super carefully for any obvious bugs, errors, broken references, broken builds, missed cleanup. Carefully fix anything you uncover."

**PROMPT 2:** "Sort of randomly explore the code files in this project, choosing files to deeply investigate and tracing whether any of them reference paths that may have been moved or deleted in this run. Once you understand the purpose of the file in the larger context, do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious broken-reference bugs, silent test fixture losses, or build-system effects from the cleanup."

**PROMPT 3:** "Turn your attention to reviewing the cleanup decisions made by your fellow agents and checking for any false-positive deletes (a deleted file may have been a referenced test fixture), bad moves (a moved file's new location may not be findable from a build script with hardcoded paths), or .gitignore additions that silently mask important files. Diagnose underlying root causes using first-principle analysis. Don't restrict yourself to the latest commits — cast a wider net and go super deep."

Between rounds, run the project's full quality gate suite from `<workspace>/project_profile.json`:
```bash
<test_command>
<typecheck_command>
<lint_command>
<build_command>
ubs .   # if available
```
All must exit 0. Log each round + outcome to `<workspace>/fresh_eyes_log.md`.

**TERMINATION:** Two consecutive full rounds (all three prompts) produce only trivial findings AND test + typecheck + lint + build + UBS all green.

For Comprehensive variant, vary stance per prompt per `references/MODES-OF-REASONING.md`.

## Output

`<workspace>/fresh_eyes_log.md` with rounds + outcomes + final clean.

## Tools used

Read, Bash, Grep, Edit (for fixes found).

## Time budget

10–60 min per round.
