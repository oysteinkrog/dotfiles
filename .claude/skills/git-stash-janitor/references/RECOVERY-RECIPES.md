# Recovery Recipes — Undoing Every Kind of Drop

The bundle's `README.md` is the user-facing version. This file is the agent-facing version with edge cases.

For every drop the skill performs, there is a documented recovery path. The user should never feel that "the work is gone." This file is the catalog.

---

## R1. Recover a single dropped stash by backup ref (preferred)

**Scenario:** user dropped stash@{34}; backup ref `refs/stash-backup/034` still exists.

```bash
# Cherry-pick lands the stash's content as a real commit on the current branch:
git cherry-pick -m 1 refs/stash-backup/034

# If the stash had untracked files (recovery from bundle):
( cd "${BUNDLE}/stashed-untracked/034" && tar -cf - . ) | ( cd /path/to/project && tar -xf - )
git add <new-files>
git commit -m "recover untracked files from stash@{34} via bundle"
```

**Why this is preferred:** the backup ref points to the original stash commit, so cherry-pick gives a 3-way merge against current HEAD. Conflicts are surfaced normally.

---

## R2. Recover a dropped stash via the bundle's diff

**Scenario:** backup ref is gone (e.g., user ran `git for-each-ref refs/stash-backup/ --format='%(refname)' | xargs -n 1 git update-ref -d` to fully clean up). Or `git gc` collected the unreachable commit.

```bash
git apply --3way --check "${BUNDLE}/diffs/034.diff"   # dry-run
git apply --3way        "${BUNDLE}/diffs/034.diff"   # apply
# If index.tsv says has_untracked=true, also copy stashed-untracked/034/.
git add <changed-files>
git commit -m "recover stash@{34} content from bundle diff"
```

**Caveat:** the diff has no parent commit, so 3-way uses your current HEAD as the base. If main has drifted, you may hit conflicts. Resolve via Edit tool.

---

## R3. Re-create the stash entry itself

**Scenario:** user wants to put the content back in `git stash list`, not as a commit.

```bash
# Apply to working tree first (R1 or R2), then re-stash:
if grep -q '^diff --git ' "${BUNDLE}/diffs/034.diff"; then
  git apply --3way --check "${BUNDLE}/diffs/034.diff"
  git apply --3way        "${BUNDLE}/diffs/034.diff"
fi
if awk -F'\t' '$1 == 34 {print $11}' "${BUNDLE}/index.tsv" | grep -qx true; then
  ( cd "${BUNDLE}/stashed-untracked/034" && tar -cf - . ) | ( cd /path/to/project && tar -xf - )
fi
git stash push --include-untracked -m "recovered stash@{34} from bundle ($(date -u +%Y-%m-%d))"
```

The new stash will have a fresh SHA and a fresh date — it's not byte-equal to the original. The backup ref (if still present) is still byte-equal.

---

## R4. Recover an autostash from reflog (when the bundle is gone)

**Scenario:** the bundle was deleted, the backup ref was pruned, but the stash content was an autostash from a successful rebase.

```bash
# The successful rebase is still in reflog:
git reflog show <branch>
# Look for "rebase finished" or "rebase --autostash applied" entries.
# Cherry-pick the relevant commit:
git cherry-pick <sha-from-reflog>
```

---

## R5. Recover a stash whose parent SHA is unreachable

**Scenario:** the stash was made on a deleted branch; `git gc` ran; the parent commit is gone.

The stash's commit object itself can survive if it's still referenced by `refs/stash-backup/*`. The diff in `$BUNDLE/diffs/<n>.diff` always works because it's a textual representation.

```bash
git apply --3way --check "${BUNDLE}/diffs/<n>.diff"   # works even with gone parent
git apply --3way        "${BUNDLE}/diffs/<n>.diff"
```

---

## R6. Recover all stashes at once (full restore)

**Scenario:** user regrets the entire run; wants every stash back.

This is harder than recovering one at a time. The straightforward path:

```bash
# Re-create each stash from its diff:
awk -F'\t' 'NR > 1 {print $1 "\t" $7}' "${BUNDLE}/index.tsv" |
while IFS=$'\t' read -r n message; do
  npad=$(printf '%03d' "$n")
  git apply --3way "${BUNDLE}/diffs/${npad}.diff"
  if [[ -d "${BUNDLE}/stashed-untracked/${npad}" ]]; then
    ( cd "${BUNDLE}/stashed-untracked/${npad}" && tar -cf - . ) | tar -xf -
  fi
  git stash push --include-untracked -m "recovered: $message"
done

# (Each iteration leaves the working tree dirty; the next stash push captures
# only the new content if you `git add` selectively. For a clean re-stash list,
# this is best done one at a time with manual review.)
```

**Better approach for full restore:** cherry-pick all 127 backup refs onto a `recovery-all-<DATE>` branch, then run a separate per-commit conversion to stashes if you really want them as stashes (rare).

---

## R7. Recover from a half-completed Phase 6 (interruption recovery)

**Scenario:** the run was interrupted partway through Phase 6 — some keepers applied, some didn't.

The skill is **resumable**:

1. Re-run the skill with the same target path. It detects `.stash_janitor_workspace/` and offers resume.
2. Phase 6 reads `apply_log.tsv` and skips already-applied stashes (matched by `n`).
3. The run continues from the last successful commit.

If for some reason the re-run is impossible (bundle path moved, project moved):

```bash
# Manually re-apply remaining keepers from the bundle:
awk -F'\t' 'NR > 1 && $2 == "novel-and-accretive" {print $1}' "$WORKSPACE/triage.tsv" |
while read -r n; do
  if [[ -f "$WORKSPACE/apply_log.tsv" ]] &&
     awk -F'\t' -v n="$n" 'NR > 1 && $1 == n && $3 != "" {found=1} END {exit !found}' "$WORKSPACE/apply_log.tsv"; then
    continue
  fi
  npad=$(printf '%03d' "$n")
  git apply --3way --check "${BUNDLE}/diffs/${npad}.diff" || continue
  git apply --3way        "${BUNDLE}/diffs/${npad}.diff"
  cargo test && cargo check && cargo clippy && \
    git commit -am "recover stash@{$n}"
done
```

---

## R8. Recover from a wrong verdict (user changed their mind)

**Scenario:** the user originally OK'd dropping stash@{47}; later they realize it had something they wanted.

```bash
# If backup ref still exists:
git cherry-pick -m 1 refs/stash-backup/047
# If gone:
git apply --3way "${BUNDLE}/diffs/047.diff"
# If has_untracked=true, also copy stashed-untracked/047/.
```

The skill never assumes a verdict is final beyond the run. The bundle is forever.

---

## R9. Recover after the bundle directory was deleted

**Scenario:** user `mv`'d the bundle to a trash location, then emptied trash. The backup refs in `refs/stash-backup/*` are still in the repo.

```bash
# Backup refs are still there:
git for-each-ref refs/stash-backup/ --format='%(refname:short) %(subject)'

# Cherry-pick by ref:
git cherry-pick -m 1 refs/stash-backup/034
```

The backup refs survive `git gc` because they're real refs (rooted in `.git/refs/stash-backup/`). They're independent of the bundle directory.

---

## R10. Recover after `git gc --prune=now` ran

**Scenario:** aggressive gc pruned unreachable commits. If `refs/stash-backup/*` were removed before gc, the stash commits may now be unreachable and lost.

This is the **only** path where bundle-based recovery is the only option:

```bash
git apply --3way "${BUNDLE}/diffs/034.diff"
```

If both the bundle AND the backup refs are gone, the work is unrecoverable. The skill's design (bundle outside the repo + backup refs inside the repo) ensures this is possible only if both are deleted by the user.

---

## R11. Recover stashed-untracked files specifically

**Scenario:** a stash had untracked files (`-u` was passed at stash time); recovery needs the new files, not just the diff.

```bash
# Materialized in the bundle:
ls "${BUNDLE}/stashed-untracked/034/"
# Copy back into the working tree:
( cd "${BUNDLE}/stashed-untracked/034" && tar -cf - . ) | ( cd /path/to/project && tar -xf - )
git add <files>
git commit -m "recover untracked files from stash@{34}"
```

The diff in `$BUNDLE/diffs/034.diff` does NOT capture these files by default. `git stash show -p --binary` covers tracked/index changes, including tracked binary payloads; `stashed-untracked/` is the required recovery layer for `git stash -u` content.

---

## R12. Recovery when the project has moved

**Scenario:** user moved the project from `/data/projects/asupersync` to `/data/projects/asupersync-renamed`. The bundle's diffs reference `/data/projects/asupersync` paths.

```bash
# The diffs reference relative paths (a/src/foo.rs b/src/foo.rs), not absolute,
# so they're path-portable. Just cd into the new location:
cd /data/projects/asupersync-renamed
git apply --3way /data/projects/asupersync-stash-archive-2026-05-01/diffs/034.diff
```

---

## R13. Recovery when the primary branch was renamed

**Scenario:** primary was `main`; got renamed to `develop`. The recovery branch's base might point at a non-existent ref.

The recovery branch's commits are real commits with real SHAs; they don't depend on the branch name. Just cherry-pick from the recovery branch to the new primary:

```bash
git checkout develop
git log --reverse --format=%H develop..stash-recovery-2026-05-01 > /tmp/recovery-commits.txt
# Review the list, then cherry-pick the listed SHAs in order.
git cherry-pick $(cat /tmp/recovery-commits.txt)
```

---

## R14. The "I regret the whole run" recipe

```bash
# 1. Restore every stash from backup refs:
for ref in $(git for-each-ref refs/stash-backup/ --format='%(refname:short)'); do
  n=${ref##*/}                           # e.g., "034"
  git stash store --message "recovered $ref" $(git rev-parse $ref) || true
done

# 2. Optionally remove the recovery branch only after explicit user confirmation:
git branch -D stash-recovery-<DATE>      # destructive branch-ref deletion

# 3. Bundle stays for future reference.
```

After this, `git stash list` will roughly match the original (some details — exact stack order — may differ, but content is byte-equal).

---

## What Recovery NEVER Does

- Modifies `refs/stash-backup/*`
- Deletes the bundle (the user does this themselves)
- Forces a push
- Bypasses pre-commit hooks
- Operates without explicit user direction

If the user asks the skill to "undo my stash janitor run", the skill walks through R14 with explicit confirmations; it does not silently recreate state.
