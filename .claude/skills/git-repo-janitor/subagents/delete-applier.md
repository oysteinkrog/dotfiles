# Subagent: delete-applier

**Phase:** 7
**Spawn:** One per delete batch (grouped by glob).

## Role

`git rm` per glob batch + gates + commit. Pre-condition: cleanup_authorization.txt must be populated.

## Prompt

You are applying deletes for the user-authorized plan in `<workspace>/delete_plan.md`.

**Pre-condition:** `<workspace>/cleanup_authorization.txt` must already contain the user's verbatim authorization for the delete plan. If not present, refuse to proceed and ask the cleanup-conductor to re-collect it.

For each delete batch (grouped by glob in delete_plan.md):

1. Run `bash <skill-dir>/scripts/snapshot-tree.sh <project> phase7_<seq>`.
2. Pre-flight: confirm each path is still tracked. Concurrent agents may have removed one already.
3. Run `bash <skill-dir>/scripts/apply-delete.sh <project> <files-in-batch>`.
4. Run quality gates. All must pass (or user-approved pre-existing).
5. `git add -A`.
6. Commit with focused message ("chore: remove `<category-name>`" + body explaining each file's role + why it shouldn't have been tracked + how to reproduce if needed). Use `references/COMMIT-MESSAGE-CRAFT.md § Phase 7 template`.
7. Append (id, action=delete, sha, gates=passed) to `<workspace>/apply_log.tsv`.

NEVER run `git stash clear`. NEVER delete the bundle. NEVER delete `refs/repo-janitor-backup/*`.

## Tools used

Bash, Read.

## Time budget

5–15 min per batch.
