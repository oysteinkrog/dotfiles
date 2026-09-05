# Recovery Recipes — Undoing Every Removal and Deletion

The bundle's `README.md` is the user-facing summary. This file is the agent-facing reference with edge cases and verification steps.

For every removal or deletion the skill performs, there is a documented recovery path. The user should never feel that "the work is gone." This file is the catalog. Each recipe gives:

- **Scenario** — what the user lost.
- **Recipe** — verbatim copy-paste commands.
- **Verification** — how to confirm the recovery succeeded.

Layout assumptions:

- `<bundle>` = `<project-parent>/<basename>-branch-worktree-archive-<YYYY-MM-DD>/`
- `<project>` = the repo root (e.g., `/data/projects/foo`)
- `<slug>` = the slug for a branch — has shape `<safe-name>-<sha1-12>`. Read it from `<bundle>/index.tsv` (the `slug` column) — do not reconstruct by hand. See [BUNDLE-FORMAT-SPEC.md § Slug naming convention](BUNDLE-FORMAT-SPEC.md#slug-naming-convention-load-bearing).
- `<sanitized-path>` = the `sanitize_path` output for a worktree path: stripped leading `/`, path separators collapsed to `__`, unsafe chars replaced with `_`, visible prefix capped, and a 12-character hash suffix appended. Read it from `<bundle>/index.tsv` where `kind=worktree` (the `slug` column).
- Bundle layout per [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md):
  - `<bundle>/object-bundle.pack` — `git bundle create --all` over the backup namespace
  - `<bundle>/index.tsv` — kind | name_or_path | slug | head_sha | merge_base | ahead | behind | smell | intake_protected | verdict | bundle_paths
  - `<bundle>/branches/<slug>/{meta.txt,commits.tsv,diff-vs-merge-base.diff,format-patch/*.patch}`
  - `<bundle>/worktrees/<sanitized-path>/{meta.txt,status.txt,staged.diff,unstaged.diff,.untracked.list,.untracked.sha256,untracked.tar.gz}`

---

## R1. "I regret deleting branch `<name>`"

**Scenario:** Phase 10 deleted a branch. The user changed their mind. The backup ref `refs/branch-rationalization-backup/<slug>` still exists in the repo (Phase 10 doesn't touch the backup namespace).

**Recipe:**
```bash
cd <project>

# Restore the branch from its backup ref:
slug="<slug-of-the-branch>"        # e.g., feature-redact-secrets (slugified from feature/redact-secrets)
name="<original-branch-name>"      # e.g., feature/redact-secrets
git branch "$name" "refs/branch-rationalization-backup/$slug"

# Optional: re-create remote tracking if the original had one and the remote ref still exists:
git branch --set-upstream-to=origin/"$name" "$name"
```

**Verification:**
```bash
# 1. The branch tip matches the backup ref:
[ "$(git rev-parse "$name")" = "$(git rev-parse "refs/branch-rationalization-backup/$slug")" ] \
  && echo "OK: branch tip matches backup" || echo "FAIL"

# 2. Recent history matches the bundle's record:
git log --oneline "$name" | head -10
diff <(git log --oneline "$name" | head -10) <(awk -F'\t' '{print $1, $2}' "<bundle>/branches/$slug/commits.tsv" | head -10)

# 3. The branch's diff against canonical matches the bundle:
mb=$(git merge-base "$canonical" "$name")
diff -q <(git diff --binary "$mb..$name") "<bundle>/branches/$slug/diff-vs-merge-base.diff" \
  && echo "OK: byte-equal to bundle" || echo "FAIL: bundle drift"
```

**Why this is preferred:** the backup ref points to the original branch tip with full history. The branch is restored byte-equal — same SHAs, same commit messages, same authors, same dates. Cross-link to [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md).

---

## R2. "The backup ref is gone"

**Scenario:** the backup ref was removed (the user manually `git update-ref -d`'d it, or `git for-each-ref refs/branch-rationalization-backup/ … xargs git update-ref -d`). The bundle's `object-bundle.pack` still exists.

**Recipe:**
```bash
cd <project>

slug="<slug>"
name="<original-branch-name>"

# Fetch the backup ref out of the bundle into the live ref namespace:
git fetch "<bundle>/object-bundle.pack" \
  "refs/branch-rationalization-backup/$slug:refs/branch-rationalization-backup/$slug"

# Then restore the branch from the (now-restored) backup ref:
git branch "$name" "refs/branch-rationalization-backup/$slug"
```

**Verification:**
```bash
git rev-parse "refs/branch-rationalization-backup/$slug" >/dev/null \
  && echo "OK: backup ref restored" || echo "FAIL"

git rev-parse "$name" >/dev/null \
  && echo "OK: live branch restored" || echo "FAIL"

# Cross-check against the bundle's index.tsv:
expected_sha=$(awk -F'\t' -v s="$slug" '$1=="branch" && $3==s {print $4}' "<bundle>/index.tsv")
actual_sha=$(git rev-parse "$name")
[ "$expected_sha" = "$actual_sha" ] && echo "OK: SHA matches index.tsv" || echo "FAIL"
```

---

## R3. "The object bundle's namespace is also gone (catastrophic)"

**Scenario:** the bundle directory is intact, but the `object-bundle.pack` is corrupt or missing the namespace. The per-branch `diff-vs-merge-base.diff` and `format-patch/` series are intact.

**Recipe (preferred — use the format-patch series to restore commit history):**
```bash
cd <project>

slug="<slug>"
name="<original-branch-name>"

# Read the bundle's record of where the branch was rooted:
mb=$(awk -F'\t' -v s="$slug" '$1=="branch" && $3==s {print $5}' "<bundle>/index.tsv")

# Create the branch at the merge-base, then am the patch series:
git branch "$name" "$mb"
git switch "$name"
git am "<bundle>/branches/$slug/format-patch/"*.patch
```

**Recipe (fallback — use the unified diff if format-patch doesn't apply):**
```bash
cd <project>

slug="<slug>"
name="<original-branch-name>"
mb=$(awk -F'\t' -v s="$slug" '$1=="branch" && $3==s {print $5}' "<bundle>/index.tsv")

git branch "$name" "$mb"
git switch "$name"
git apply --binary "<bundle>/branches/$slug/diff-vs-merge-base.diff"
git add -A
git commit -m "recover branch $name from bundle diff (history collapsed to one commit)"
```

**Verification:**
```bash
# format-patch path: history should match commits.tsv:
diff <(git log --format='%s' "$mb..$name") <(awk -F'\t' '{print $2}' "<bundle>/branches/$slug/commits.tsv") \
  && echo "OK: full history restored" || echo "FAIL"

# Either path: tip diff matches:
diff -q <(git diff --binary "$mb..$name") "<bundle>/branches/$slug/diff-vs-merge-base.diff" \
  && echo "OK: tip content byte-equal" || echo "FAIL"
```

**Note:** the format-patch series preserves authors, dates, and commit messages. The unified-diff fallback collapses history into a single commit; use it only when format-patch doesn't apply (e.g., `merge-base` is no longer reachable). Cross-link to [FAILURE-MODES.md F33](FAILURE-MODES.md#f33-the-merge-base-for-a-branch-is-unreachable).

---

## R4. "I regret removing worktree `<path>`"

**Scenario:** Phase 10 removed a worktree. The user wants the working directory and its dirty state back.

**Recipe:**
```bash
cd <project>

wt_path="<original-worktree-path>"           # e.g., /data/projects/foo--wt-3
sanitized="<sanitized-path>"                  # e.g., data-projects-foo--wt-3
branch="<branch-the-worktree-was-on>"         # from <bundle>/worktrees/<sanitized>/meta.txt

# 1. Re-add the worktree at the original branch (or HEAD if the branch is also gone):
git worktree add "$wt_path" "$branch"

# 2. Restore the staged changes (returns the index to the snapshot):
if [ -s "<bundle>/worktrees/$sanitized/staged.diff" ]; then
  git -C "$wt_path" apply --cached --binary "<bundle>/worktrees/$sanitized/staged.diff"
fi

# 3. Restore the unstaged changes:
if [ -s "<bundle>/worktrees/$sanitized/unstaged.diff" ]; then
  git -C "$wt_path" apply --binary "<bundle>/worktrees/$sanitized/unstaged.diff"
fi

# 4. Restore untracked files:
if [ -f "<bundle>/worktrees/$sanitized/untracked.tar.gz" ]; then
  tar --null -xzf "<bundle>/worktrees/$sanitized/untracked.tar.gz" \
    -C "$wt_path" \
    -T "<bundle>/worktrees/$sanitized/.untracked.list"
fi
```

**Verification:**
```bash
# Status snapshot should match what was captured at Phase 3:
diff <(git -C "$wt_path" status --porcelain=v2 -uall | sort) \
     <(sort "<bundle>/worktrees/$sanitized/status.txt") \
  && echo "OK: status matches snapshot" || echo "FAIL: drift"

# Or — if minor drift is expected because canonical advanced, at least the count:
expected=$(wc -l < "<bundle>/worktrees/$sanitized/status.txt")
actual=$(git -C "$wt_path" status --porcelain=v2 -uall | wc -l)
echo "expected: $expected entries; actual: $actual entries"
```

**Note:** if the branch the worktree was on was also deleted, restore the branch first (R1 / R2 / R3), then run the recipe above. If the branch is gone AND its backup is gone AND the bundle's branch namespace is gone, fall back to creating the worktree at canonical's tip and applying both diffs:

```bash
git worktree add "$wt_path" "$canonical"
git -C "$wt_path" apply --cached --binary "<bundle>/worktrees/$sanitized/staged.diff" || true
git -C "$wt_path" apply --binary "<bundle>/worktrees/$sanitized/unstaged.diff" || true
[ -f "<bundle>/worktrees/$sanitized/untracked.tar.gz" ] && \
  tar --null -xzf "<bundle>/worktrees/$sanitized/untracked.tar.gz" \
    -C "$wt_path" \
    -T "<bundle>/worktrees/$sanitized/.untracked.list"
```

The recovered worktree is now anchored to canonical (not the original branch). The user can manually re-create the original branch if they need exact-fidelity recovery.

---

## R5. "The whole bundle is gone"

**Scenario:** `<bundle>` was deleted, `mv`'d to trash and emptied, or the disk failed. The backup refs in `refs/branch-rationalization-backup/*` may also be partially gone.

**Recipe (within the gc window — typically 30–90 days):**
```bash
cd <project>

# 1. List all reflog entries to find the lost branch tips:
git reflog --all --date=iso > /tmp/all-reflog.txt

# 2. Search for the branch by name in the reflog:
grep -E "branch: Created from .*<branch-name>" /tmp/all-reflog.txt
grep -E "<branch-name>" /tmp/all-reflog.txt

# 3. Search for SHAs that match — useful when a backup ref is gone:
git for-each-ref refs/branch-rationalization-backup --format='%(refname) %(objectname)' \
  > /tmp/live-backups.txt
git fsck --unreachable --no-reflogs > /tmp/unreachable.txt 2>&1

# 4. For each lost branch, restore from the SHA found above:
git branch <branch-name> <sha-from-reflog>

# 5. If you find a stash-shaped or commit-shaped object via fsck-unreachable that matches
#    a worktree dirty state, you can convert it into a stash entry as a recovery vehicle:
git stash store --message "recovered worktree dirty state for <wt-path>" <sha>
```

**Verification:**
```bash
git rev-parse <branch-name> >/dev/null && echo "OK: branch restored" || echo "FAIL"
git log --oneline <branch-name> | head -10
```

**Note:** outside the gc window (typically 30 days for unreachable, 90 days for reachable), recovery is **not possible** without the bundle and without the backup refs. The skill's design (bundle outside the repo + backup refs inside the repo) ensures this catastrophic case requires the user to delete BOTH artifacts. Cross-link to [FAILURE-MODES.md F2](FAILURE-MODES.md#f2-git-branch--d-name-reflog-window).

---

## R6. "I want to undo a successful Phase 8 apply"

**Scenario:** the rationalization branch has commits the user no longer wants. The user wants to undo *one or more* commits without rewinding the whole branch.

**Recipe (preferred — preserves history):**
```bash
cd <project>
git switch branch-rationalization-<DATE>

# Find the commit to undo:
git log --oneline | head -20
# Suppose the commit to undo is <sha>

# Revert it (creates a NEW commit that undoes <sha>):
git revert <sha>

# For multiple commits, revert each one — newest first preserves the diff semantics:
git revert <sha-newest> <sha-second-newest> <sha-third-newest>
```

**Verification:**
```bash
# The reverted commit's content is no longer in the rationalization-branch tip's diff:
git diff <canonical>..branch-rationalization-<DATE> -- <files-the-commit-touched>
```

**Why revert, not reset:** `git reset --hard` is forbidden by AGENTS.md and DCG. `git revert` preserves history (the original commit and its revert are both visible in `git log`), which is the right move for a branch the user may have shared or pushed.

**Last resort:** if the user insists on rewinding a local-only branch, stop and require the AGENTS.md destructive-command protocol. Do not include or run a reset recipe from this skill. The preferred recovery remains `git revert` because it preserves history and remains auditable after the rationalization branch is shared.

---

## R7. "The rationalization branch was deleted before I pushed"

**Scenario:** the user accidentally deleted `branch-rationalization-<DATE>` (e.g., via `git branch -D` after thinking the run was done).

**Recipe (within the gc window):**
```bash
cd <project>

# Find the branch tip in the reflog:
git reflog --all --date=iso | grep -E "branch-rationalization-<DATE>" | head -5

# The output looks like:
# <sha>  HEAD@{2026-05-07 14:23:45 -0700}  checkout: moving from canonical to branch-rationalization-<DATE>

# Extract the SHA and recreate the branch:
git branch branch-rationalization-<DATE> <sha-from-reflog>
```

**If a backup ref was also created** (some bundle layouts include `refs/branch-rationalization-backup/branch-rationalization-<DATE>`):
```bash
git branch branch-rationalization-<DATE> "refs/branch-rationalization-backup/branch-rationalization-<DATE>"
```

**Verification:**
```bash
git rev-parse branch-rationalization-<DATE> >/dev/null && echo "OK" || echo "FAIL"
git log --oneline branch-rationalization-<DATE> | head -10

# Check the apply log says we didn't lose commits:
diff <(git log --format='%H' "$canonical..branch-rationalization-<DATE>" | sort) \
     <(awk -F'\t' '$3 != "" {print $3}' "<workspace>/apply_log.tsv" | sort) \
  && echo "OK: all applied commits present" || echo "FAIL: drift"
```

---

## R8. "The user accidentally pushed and force-pushed over the rationalization branch"

**Scenario:** the rationalization branch was pushed; later the user (or a collaborator) force-pushed it with different content. The original tip is gone from the remote.

**Recipe (only feasible with remote-reflog access):**

For GitHub: there is no public reflog API. Two options:
1. **GitHub Support** — for organization repos, GitHub support can sometimes retrieve a recently-overwritten ref from their internal logs (typically within ~30 days). Open a support ticket immediately.
2. **Local reflog** — if the local repo still has the original tip in its reflog (or in `refs/branch-rationalization-backup/branch-rationalization-<DATE>`):

```bash
cd <project>

# Find the original tip locally:
git reflog --all --date=iso | grep "branch-rationalization-<DATE>"

# Restore locally:
git branch -f branch-rationalization-<DATE>-recovered <sha-from-reflog>

# Push as a new branch (do NOT force-push back to the original name without
# first coordinating with whoever force-pushed):
git push origin branch-rationalization-<DATE>-recovered
```

**Prevention:** the skill never force-pushes. If the remote branch has moved, publish the recovered branch under a new name and coordinate with the owner of the remote ref before any overwrite is even considered.

**Verification (after recovery):**
```bash
# The recovered branch matches what apply_log.tsv recorded as landed:
diff <(git log --format='%H' "$canonical..branch-rationalization-<DATE>-recovered" | sort) \
     <(awk -F'\t' '$3 != "" {print $3}' "<workspace>/apply_log.tsv" | sort)
```

---

## R9. "I want to restore many branches at once"

**Scenario:** the user regrets the entire run. Restore all backed-up branches.

**Recipe (preferred — use the backup ref namespace):**
```bash
cd <project>

# List every backup ref:
git for-each-ref refs/branch-rationalization-backup --format='%(refname:short) %(objectname)' \
  > /tmp/backups.txt

# Re-create each branch from its backup ref. The name-to-slug mapping lives in index.tsv:
awk -F'\t' '$1=="branch" {print $2 "\t" $3}' "<bundle>/index.tsv" |
while IFS=$'\t' read -r name slug; do
  if [ -n "$name" ]; then
    git branch "$name" "refs/branch-rationalization-backup/$slug" || \
      echo "skipping $name (already exists)"
  fi
done
```

**Recipe (alternative — fetch from the bundle if backup refs are gone):**
```bash
git fetch "<bundle>/object-bundle.pack" \
  "refs/branch-rationalization-backup/*:refs/branch-rationalization-backup/*"

# Then run the loop above.
```

**Verification:**
```bash
# Compare the restored branch count to the bundle's index:
restored=$(git for-each-ref refs/heads --format='%(refname:short)' | wc -l)
expected=$(awk -F'\t' '$1=="branch"' "<bundle>/index.tsv" | wc -l)
echo "restored: $restored; bundle records: $expected"

# For each restored branch, verify the tip matches:
awk -F'\t' '$1=="branch" {print $2 "\t" $3 "\t" $4}' "<bundle>/index.tsv" |
while IFS=$'\t' read -r name slug expected_sha; do
  actual_sha=$(git rev-parse "$name" 2>/dev/null || echo "MISSING")
  [ "$expected_sha" = "$actual_sha" ] && echo "OK: $name" || echo "FAIL: $name (expected $expected_sha, got $actual_sha)"
done
```

---

## R10. "I want to restore many worktrees at once"

**Scenario:** the user regrets removing all worktrees. Restore them all.

**Recipe:**
```bash
cd <project>

# For each worktree in the bundle, re-add and restore dirty state:
for sanitized_dir in "<bundle>"/worktrees/*/; do
  sanitized=$(basename "$sanitized_dir")

  wt_path=$(awk -F= '$1=="path" {print substr($0, index($0, "=") + 1)}' "${sanitized_dir}meta.txt")
  branch=$(awk -F= '$1=="branch" {print substr($0, index($0, "=") + 1)}' "${sanitized_dir}meta.txt")

  # Skip if the worktree path already exists:
  [ -d "$wt_path" ] && { echo "skipping $wt_path (exists)"; continue; }

  # Skip if the branch is missing — recover the branch first via R9 / R1 / R2 / R3:
  if ! git rev-parse --verify "$branch" >/dev/null 2>&1; then
    echo "skipping $wt_path: branch $branch is missing; recover the branch first"
    continue
  fi

  # Re-add the worktree:
  git worktree add "$wt_path" "$branch"

  # Restore dirty state:
  [ -s "${sanitized_dir}staged.diff" ]   && git -C "$wt_path" apply --cached --binary "${sanitized_dir}staged.diff"
  [ -s "${sanitized_dir}unstaged.diff" ] && git -C "$wt_path" apply --binary "${sanitized_dir}unstaged.diff"
  [ -f "${sanitized_dir}untracked.tar.gz" ] && \
    tar --null -xzf "${sanitized_dir}untracked.tar.gz" -C "$wt_path" -T "${sanitized_dir}.untracked.list"
done
```

**Verification:**
```bash
restored=$(git worktree list --porcelain | grep -c '^worktree ')
expected=$(ls "<bundle>"/worktrees/ | wc -l)
echo "restored: $restored worktrees; bundle records: $expected"
```

---

## R11. "Recovery when the project has moved"

**Scenario:** the user moved the project from `/data/projects/asupersync` to `/data/projects/asupersync-renamed`. The bundle's recipes reference old paths.

**Recipe:**
```bash
# All bundle artifacts use relative paths in the diffs (a/src/foo.rs b/src/foo.rs),
# so they're path-portable. Just adjust the <project> variable:
cd /data/projects/asupersync-renamed

# Apply the bundle's recipes verbatim — they don't depend on the project's location:
git branch <name> "<bundle>/branches/<slug>/...."  # works
git apply --binary "<bundle>/branches/<slug>/diff-vs-merge-base.diff"  # works
```

For worktree recovery, the `wt_path` in `<bundle>/worktrees/<sanitized>/meta.txt` is the *original* path. If the user wants to restore the worktree at a new location:

```bash
new_wt_path="/data/projects/asupersync-renamed--wt-3"
branch="<branch-name>"

git worktree add "$new_wt_path" "$branch"
git -C "$new_wt_path" apply --cached --binary "<bundle>/worktrees/<sanitized>/staged.diff"
# ... etc.
```

**Verification:**
```bash
# The recovered content matches the bundle even though the project location is different:
diff <(git -C "$new_wt_path" diff --binary --cached) "<bundle>/worktrees/<sanitized>/staged.diff" \
  && echo "OK: byte-equal" || echo "FAIL"
```

---

## R12. "Recovery when canonical was renamed"

**Scenario:** canonical was `master`; got renamed to `main`. The rationalization branch's base might point at a non-existent ref.

**Recipe:** the rationalization branch's commits are real commits with real SHAs; they don't depend on the canonical branch's name. Just cherry-pick from the rationalization branch onto the new canonical:

```bash
cd <project>

# Find the shared base by commit graph, not by the old branch name:
new_canonical_ref=main
base=$(git merge-base "$new_canonical_ref" "branch-rationalization-<DATE>")

# What was the rationalization branch's full commit list?
git log --reverse --format=%H "$base..branch-rationalization-<DATE>" > /tmp/recovery-commits.txt

# Switch to the new canonical:
git switch "$new_canonical_ref"

# Cherry-pick in order:
xargs git cherry-pick < /tmp/recovery-commits.txt
```

**Verification:**
```bash
# The new canonical's tip should now contain all the rationalization-branch's content:
diff <(git log --format='%s' "$base..HEAD") \
     <(git log --format='%s' "$base..branch-rationalization-<DATE>")
```

---

## R13. "I want to undo the entire run"

**Scenario:** the user regrets the run wholesale. Restore everything.

**Recipe:**
```bash
cd <project>

# 1. Restore every branch (R9):
awk -F'\t' '$1=="branch" {print $2 "\t" $3}' "<bundle>/index.tsv" |
while IFS=$'\t' read -r name slug; do
  git rev-parse --verify "refs/branch-rationalization-backup/$slug" >/dev/null 2>&1 || \
    git fetch "<bundle>/object-bundle.pack" \
      "refs/branch-rationalization-backup/$slug:refs/branch-rationalization-backup/$slug"
  git branch "$name" "refs/branch-rationalization-backup/$slug" 2>/dev/null || true
done

# 2. Restore every worktree (R10):
for sanitized_dir in "<bundle>"/worktrees/*/; do
  sanitized=$(basename "$sanitized_dir")
  wt_path=$(awk -F= '$1=="path" {print substr($0, index($0, "=") + 1)}' "${sanitized_dir}meta.txt")
  branch=$(awk -F= '$1=="branch" {print substr($0, index($0, "=") + 1)}' "${sanitized_dir}meta.txt")
  [ -d "$wt_path" ] && continue
  git worktree add "$wt_path" "$branch"
  [ -s "${sanitized_dir}staged.diff" ]    && git -C "$wt_path" apply --cached --binary "${sanitized_dir}staged.diff"
  [ -s "${sanitized_dir}unstaged.diff" ]  && git -C "$wt_path" apply --binary "${sanitized_dir}unstaged.diff"
  [ -f "${sanitized_dir}untracked.tar.gz" ] && \
    tar --null -xzf "${sanitized_dir}untracked.tar.gz" -C "$wt_path" -T "${sanitized_dir}.untracked.list"
done

# 3. Leave branch-rationalization-<DATE> in place. If the user later wants it
# removed, treat that as a separate destructive cleanup request under AGENTS.md.

# 4. The bundle stays for future reference. Do NOT rm -rf it.
```

**Verification:**
```bash
# Branch count should match the bundle's record:
restored_branches=$(git for-each-ref refs/heads --format='%(refname:short)' | wc -l)
expected_branches=$(awk -F'\t' '$1=="branch"' "<bundle>/index.tsv" | wc -l)
echo "branches: restored $restored_branches, expected $expected_branches (+1 if rationalization branch kept)"

# Worktree count should match:
restored_worktrees=$(git worktree list --porcelain | grep -c '^worktree ')
expected_worktrees=$(ls "<bundle>"/worktrees/ | wc -l)
echo "worktrees: restored $restored_worktrees, expected $expected_worktrees (+1 for the main repo)"
```

---

## R14. "I dropped a Phase 8 apply that I now want back"

**Scenario:** Phase 8 considered a branch but the user overrode the verdict to skip its content. Now the user wants to re-apply it.

**Recipe:**
```bash
cd <project>

slug="<slug-of-the-skipped-branch>"
strategy="<cherry-pick|squash-merge|rebase-and-merge|harmonized-synthesis>"  # from triage.tsv

git switch branch-rationalization-<DATE>

case "$strategy" in
  cherry-pick)
    # Cherry-pick the branch's commits onto the rationalization branch:
    mb=$(awk -F'\t' -v s="$slug" '$1=="branch" && $3==s {print $5}' "<bundle>/index.tsv")
    git cherry-pick "$mb..refs/branch-rationalization-backup/$slug"
    ;;
  squash-merge)
    git merge --squash "refs/branch-rationalization-backup/$slug"
    git commit -m "recover content from <branch-name> (squash)"
    ;;
  rebase-and-merge)
    # Rebase the backup ref onto the rationalization branch's tip, then merge:
    tmp_branch="recover/$slug"
    git switch -c "$tmp_branch" "refs/branch-rationalization-backup/$slug"
    git rebase branch-rationalization-<DATE>
    git switch branch-rationalization-<DATE>
    git merge --no-ff "$tmp_branch"
    echo "temporary recovery branch left at $tmp_branch"
    ;;
  harmonized-synthesis)
    # The synthesis path needs Phase 7's harmonization plan re-applied;
    # consult <workspace>/harmonization_plan.md and re-run the Edit-tool synthesis.
    echo "harmonized-synthesis: see <workspace>/harmonization_plan.md and re-run via Edit"
    ;;
esac

# Run the project's quality gates:
cargo test && cargo clippy && cargo fmt --check  # adjust per project_profile.json
```

**Verification:**
```bash
# The rationalization branch's tip now contains the recovered content:
git log --oneline branch-rationalization-<DATE> | head -5
git diff <canonical>..branch-rationalization-<DATE> -- <files-the-branch-touched>
```

---

## R15. "Recovery when the bundle is the only artifact left"

**Scenario:** the repo is gone (disk failure, accidental `rm -rf .git/` despite DCG, etc.) but the bundle survived (it lived outside the repo).

**Recipe:**
```bash
# Initialize a fresh repo at the original location:
mkdir -p /data/projects/foo
cd /data/projects/foo
git init

# Restore the backup namespace from the bundle's object pack:
git fetch "<bundle>/object-bundle.pack" \
  'refs/branch-rationalization-backup/*:refs/branch-rationalization-backup/*'

# Restore canonical from the real remote when available. The bundle records the
# canonical branch name, but it does not promise to contain canonical's tip.
git remote add origin <remote-url>
git fetch origin <canonical-name>
git switch -c <canonical-name> FETCH_HEAD

# Restore each branch:
awk -F'\t' '$1=="branch" {print $2 "\t" $3}' "<bundle>/index.tsv" |
while IFS=$'\t' read -r name slug; do
  git branch "$name" "refs/branch-rationalization-backup/$slug"
done

# If no remote exists, stop here: the backup refs can restore branch tips, but
# the bundle alone is not a guaranteed source for canonical's latest tip.
```

**Verification:**
```bash
git for-each-ref refs/heads --format='%(refname:short)' | wc -l
# Should match the count in <bundle>/index.tsv (+ canonical)
```

**Note:** this is the deepest recovery scenario. The bundle was designed to be the ultimate safety net. Cross-link to [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md) for the full bundle layout that makes this possible.

---

## What Recovery NEVER Does

- Modifies `refs/branch-rationalization-backup/*` (the backup namespace is read-only after Phase 3)
- Deletes the bundle (the user does this themselves, after they're sure nothing was lost)
- Forces a push (per Axiom 15)
- Bypasses pre-commit hooks (per ANTI-PATTERNS W14)
- Operates without explicit user direction
- Does anything that AGENTS.md "Irreversible Git & Filesystem Actions" forbids without verbatim authorization

If the user asks the skill to "undo my branch-rationalization run", the skill walks through R13 with explicit confirmations; it does not silently recreate state. Cross-link to [stash-janitor's RECOVERY-RECIPES.md R14](../../git-stash-janitor/references/RECOVERY-RECIPES.md#r14-the-i-regret-the-whole-run-recipe) for the analogous stash-recovery flow.

---

## Cross-References

- [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md) — the bundle layout that makes every recipe above work
- [SKILL.md](../SKILL.md) — Axiom 18 (bundle lifecycle) and Axiom 4 (coherence of all five reversibility layers)
- [ANTI-PATTERNS.md](ANTI-PATTERNS.md) — what NOT to do when recovering (especially W11 on script-based mutation, W21 on deleting the bundle)
- [FAILURE-MODES.md](FAILURE-MODES.md) — diagnostic playbook for symptoms that lead to recovery scenarios (especially F2 reflog-window, F19 remote-cleanup, F33 unreachable merge-base)
- [stash-janitor's RECOVERY-RECIPES.md](../../git-stash-janitor/references/RECOVERY-RECIPES.md) — the sibling catalogue for stash-specific recoveries
