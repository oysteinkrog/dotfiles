# Recovery Recipes

How to undo every kind of move, delete, or `.gitignore` change the skill performs. Copy-paste-ready.

---

## Recipe key

- `<DATE>` = the run date (UTC), e.g., `2026-04-27`. Find via `cat .repo_janitor_workspace/handoff_report.md` or `ls refs/repo-janitor-backup/`.
- `<bundle>` = the bundle path. Find via `cat .repo_janitor_workspace/bundle_path.txt`.
- `<sha>` = a specific commit SHA from the recovery branch. Find via `git log --oneline repo-janitor-<DATE>`.

---

## "I want everything back the way it was" (full rollback)

```bash
# Layer 1 (preferred) — surgical
git checkout refs/repo-janitor-backup/<DATE>-pre-cleanup -- .
git status   # review changes
git commit -m "rollback: undo cleanup run <DATE>"

# OR Layer 3 — revert the cleanup commits one by one
git revert --no-commit <first-cleanup-sha>..<last-cleanup-sha>
git commit -m "rollback: undo cleanup run <DATE>"
```

DO NOT use `git reset --hard` on a shared branch — it loses any subsequent work from concurrent agents.

---

## "Restore one file that was deleted"

Three options, each robust:

```bash
# Option 1 — Layer 1 backup ref (preferred)
git checkout refs/repo-janitor-backup/<DATE>-pre-cleanup -- <path>
git add <path>
git commit -m "restore: <path>"

# Option 2 — Layer 2 bundle copy
cp <bundle>/working-tree-copies/<path> <project>/<path>
git add <path>
git commit -m "restore: <path> from cleanup bundle"

# Option 3 — Layer 3 git revert
# Find the delete commit:
git log --oneline --diff-filter=D -- <path> | head -3
git revert <delete-commit-sha>
```

---

## "Restore a moved file to its original location"

```bash
# The reference_rewrite_log.tsv has every path-rewrite pair.
# Move back:
git mv <new-path> <old-path>

# Then reverse the reference rewrites — for every (file, line, old → new) row
# in reference_rewrite_log.tsv that touched the moved file, swap old/new:
$EDITOR <files-to-rewrite-back>
git add -A
git commit -m "restore: undo move of <path>"
```

For a single move undone via Layer 3:
```bash
git log --oneline --diff-filter=R -- <new-path> | head -3
git revert <move-commit-sha>
```

This reverts both the rename AND the reference rewrites in the same commit.

---

## "Stop ignoring a `.gitignore`'d file"

```bash
# Find the gitignore commit
git log --oneline -- .gitignore | head -5

# Option 1 — revert the entire gitignore commit
git revert <gitignore-commit-sha>

# Option 2 — surgically remove just one rule
$EDITOR .gitignore   # delete the offending line
git add .gitignore
git commit -m "stop ignoring <pattern>"
```

If the `.gitignore` commit also did `git rm --cached` for some files (untrack-without-delete), you need to re-stage them too:

```bash
git checkout <pre-gitignore-sha> -- <previously-untracked-paths>
git add <previously-untracked-paths>
git commit -m "re-track <paths>"
```

---

## "I want to keep the file but stop tracking it" (untrack without delete)

```bash
git rm --cached <path>
echo '<path>' >> .gitignore   # or a glob that matches
git add .gitignore
git commit -m "untrack <path> while keeping local copy"
```

The file stays on disk; future `git status` won't show it.

---

## "Restore byte-identical content from the bundle"

The bundle's `working-tree-copies/<path>` is byte-identical to the file at the moment Phase 3 ran. If you want to restore that exact content (not the post-cleanup version):

```bash
cp <bundle>/working-tree-copies/<path> <project>/<path>
sha256sum <project>/<path> <bundle>/working-tree-copies/<path>   # should match

git add <path>
git commit -m "restore: <path> from bundle (byte-identical to pre-cleanup state)"
```

For LFS-tracked files that were smudged into the bundle: the bundle has the actual blob, so the `cp` brings back the real content. After `git add`, git's LFS hooks will re-pointerize the tracked path.

---

## "Recover after a force-push (secret-leak playbook went wrong)"

If you pushed a `git filter-repo` rewrite and need to undo it:

```bash
# The mirror backup is your friend
ls /tmp/<repo>-backup-*.git/

# Restore from mirror to a fresh dir
git clone /tmp/<repo>-backup-<TS>.git /tmp/<repo>-restore
cd /tmp/<repo>-restore

# Push back to origin (with --force-with-lease since you intentionally
# want to overwrite the rewritten history):
git remote remove origin   # if mirror has it as 'origin' already
git remote add origin <origin-url>
git push --force-with-lease origin --all
git push --force-with-lease origin --tags
```

This restores the full pre-filter-repo history including the secret. You'd only do this if the rewrite caused worse problems than the leak — rare.

---

## "I want the cleanup branch but with one specific commit reverted"

```bash
git checkout repo-janitor-<DATE>
git revert <unwanted-sha>
git commit --amend  # if you want to combine with the revert above
git push origin repo-janitor-<DATE>
```

If the branch hasn't been pushed yet, you can also do an interactive rebase to drop the commit entirely:

```bash
git rebase -i <pre-cleanup-sha>
# In the editor, delete the line for the unwanted commit
# Save and exit; rebase will replay the rest
```

---

## "Recover after the bundle was accidentally deleted"

Layer 1 (the backup ref) has you mostly covered:

```bash
# Every pre-cleanup file is reachable via the ref
git checkout refs/repo-janitor-backup/<DATE>-pre-cleanup -- <any-path>
```

What's lost: the bundle's standalone metadata (`index.tsv`, `meta/`, `reference-graph.json`, `gitignore-before.txt`). These are reconstructable from `git log` and the `.repo_janitor_workspace/` artifacts on the recovery branch.

To minimize this risk: keep `.repo_janitor_workspace/` for at least one full release cycle, because the bundle is stored inside it. If you need durable long-term storage, copy or archive the workspace after the cleanup is complete.

---

## "I need to redo the whole cleanup from scratch on a different branch"

```bash
# Leave the old recovery branch intact and create a new redo branch at the
# pre-cleanup ref.
git switch -c repo-janitor-redo-<DATE> refs/repo-janitor-backup/<DATE>-pre-cleanup

# Re-run the skill
# It will detect the existing .repo_janitor_workspace/, offer to resume or restart
```

---

## "I lost the workspace dir but still have the bundle and git history"

The workspace (`<project>/.repo_janitor_workspace/`) is local-only and recreatable.

To rebuild from the bundle + git log:

```bash
# Reconstruct project_profile.json (can be derived from current state)
mkdir -p <project>/.repo_janitor_workspace
# Run the discover-project script:
bash <skill-dir>/scripts/discover-project.sh <project> > <project>/.repo_janitor_workspace/project_profile.json

# Reconstruct apply_log.tsv from git log:
git log --pretty='%H%x09%s' refs/repo-janitor-backup/<DATE>-pre-cleanup..HEAD > <project>/.repo_janitor_workspace/apply_log.tsv
```

---

## "I want to verify the cleanup didn't lose anything"

```bash
# Compare the file count
echo "Pre-cleanup top-level files:"
git ls-tree refs/repo-janitor-backup/<DATE>-pre-cleanup | grep -v / | wc -l

echo "Current top-level files:"
git ls-files . | grep -v / | wc -l

echo "Difference:"
git diff --stat refs/repo-janitor-backup/<DATE>-pre-cleanup..HEAD | tail -1

# Verify every candidate has a backup
while IFS=$'\t' read -r id sha path size mtime smell first_sha; do
  [[ "$id" == "id" ]] && continue   # skip header
  if [[ ! -f "<bundle>/working-tree-copies/$path" ]]; then
    echo "MISSING IN BUNDLE: $path"
  fi
done < .repo_janitor_workspace/candidates.tsv
```

---

## "I want to delete the bundle (run is settled)"

The skill never auto-deletes or moves the bundle toward deletion. When the user says the run is settled, remind them that `.repo_janitor_workspace/` contains the recovery bundle and that removing it is their manual lifecycle decision, not an agent action.

The backup ref `refs/repo-janitor-backup/<DATE>-pre-cleanup` is still there in git's local refs and can be cleaned up separately:

```bash
git update-ref -d refs/repo-janitor-backup/<DATE>-pre-cleanup
```

---

## Auditing tools

After any run, useful commands to inspect the recovery state:

```bash
# Backup refs (Layer 1)
git show-ref refs/repo-janitor-backup/

# Bundle (Layer 2)
cat <bundle>/index.tsv | head -20
ls <bundle>/working-tree-copies/

# Git log of cleanup commits (Layer 3)
git log --oneline repo-janitor-<DATE>

# Mirror backup if any (Layer 4 — secret-leak runs only)
ls /tmp/<repo>-backup-*.git/

# Mutation logs
cat .repo_janitor_workspace/apply_log.tsv
cat .repo_janitor_workspace/reference_rewrite_log.tsv

# Authorization records
cat .repo_janitor_workspace/cleanup_authorization.txt
```

If any of these are missing or empty when you expect them to be populated: the skill's run was incomplete or interrupted. Re-run from the last known-good state — the skill is designed to be resumable.
