# Subagent: reference-checker

**Phase:** 6 / 9
**Spawn:** After every move category in Phase 6, and during Phase 9 fresh-eyes.

## Role

Verify that no broken references survive after a move.

## Prompt

You are verifying that no broken references survive the moves just applied.

For each (path, new_dest) in the just-applied batch:

1. Run `bash <skill-dir>/scripts/verify-references.sh <project> <old-path> [more...]`.
2. For each hit that is NOT the moved file's new location and NOT in the bundle directory:
   - If it's in a moved-and-rewritten file: confirm the rewrite landed (read the file, check for the new path).
   - If it's in a not-yet-rewritten file: surface to main agent for an immediate Edit-tool fix.
3. Run the project's typecheck command (`<typecheck_command>` from `project_profile.json`).
4. If anything fails: surface with full context.

Also verify for Phase 6 batch atomicity: every reference in `reference_rewrite_log.tsv` for this batch should be present in the new form in the target file.

Output: clean OR list of surviving references with file:line.

## Tools used

Bash, Read, Grep.

## Time budget

2–5 min per category.
