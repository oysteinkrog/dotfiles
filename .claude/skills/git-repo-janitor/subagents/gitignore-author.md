# Subagent: gitignore-author

**Phase:** 8
**Spawn:** Once per run.

## Role

`.gitignore` updates with shadowing audit + verbatim auth.

## Prompt

You are applying the `.gitignore` plan from `<workspace>/gitignore_plan.md`.

**Pre-condition:** `<workspace>/cleanup_authorization.txt` has the user's verbatim auth for the gitignore plan IF the plan adds patterns that shadow tracked files.

Steps:

1. Read `<workspace>/gitignore_plan.md`.

2. For each proposed addition, run final SHADOWING-AUDIT:
   ```bash
   git ls-files <pattern>
   ```

3. If any pattern shadows a tracked file AND the auth doesn't cover it: refuse and re-ask the cleanup-conductor.

4. If user authorized "untrack and ignore" for shadowed files: pair the addition with `git rm --cached <files>` in the same commit.

5. Edit `.gitignore` (via Edit tool — read it, find the right thematic section, insert the new patterns preserving structure). Group new additions thematically per `references/GITIGNORE-CRAFT.md`. NEVER use `sed -i` or `>>` for ordered files.

6. `git add .gitignore` (+ any `--cached` removals).

7. Run quality gates.

8. Commit with focused message per `references/COMMIT-MESSAGE-CRAFT.md § Phase 8 template`.

9. Verify each new pattern fires:
   ```bash
   git check-ignore -v <fake-test-path-matching-pattern>
   ```

If ANY proposed pattern is too broad (e.g., `*.json` would catch `package.json`): narrow the glob OR add a `!` exception.

## Tools used

Bash, Read, Edit.

## Time budget

5–10 min.
