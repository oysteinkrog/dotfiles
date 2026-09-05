# Advanced Recovery — Edge Cases and Catastrophes

The basic recovery recipes (R1–R14 in [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md)) cover the common cases: regretted branch deletes, lost backup refs, lost format-patch series, lost worktree dirty state. This file is for the hard cases: gc-pruned commits, force-pushed canonicals, lost backup-and-bundle simultaneously, submodule divergence, LFS gaps, branches deleted out-of-band, and lost bundles.

Adapted from [git-stash-janitor's ADVANCED-RECOVERY.md](../../git-stash-janitor/references/ADVANCED-RECOVERY.md). The unit-of-management changes (branches + worktrees vs. stashes) shift several recipes meaningfully.

> **The frame.** Per [SKILL.md "The One Rule"](../SKILL.md): "Every worktree removal and every local branch deletion must be reversible **byte-for-byte** at the moment it's authorized." That covers the common case. AR1–AR7 here cover what happens when the safety net was already partially eaten before the run started, or by something outside the skill mid-run.

---

## AR1. `git gc --prune=now` ran AFTER the backup refs were deleted

**Symptom:** the user explicitly cleaned up `refs/branch-rationalization-backup/*` (intentionally — e.g., 6 weeks after the run, deciding the cleanup was complete), then ran aggressive gc. Branch tip commits referenced ONLY by the deleted backup refs are now garbage-collected. Reflog window has expired (default 30/90 days; user may have shortened).

**Diagnosis:**

```bash
# Are the original SHAs reachable from anywhere?
ORIGINAL_SHA=$(awk -F'\t' -v s="<slug>" '$1=="branch" && $2==s {print $3}' "<bundle>/index.tsv")
git cat-file -e "$ORIGINAL_SHA" 2>/dev/null \
  && echo "Object still exists" \
  || echo "Object pruned — moving to bundle recovery"

# Reflog check (might still have it):
git reflog --all | grep "$ORIGINAL_SHA"
```

If the object is pruned and reflog is empty, the live repo has lost the commits. Recovery is via the bundle's `object-bundle.pack` + per-branch format-patch series.

**Recipe — restore via the object bundle (preferred — preserves SHAs and history):**

```bash
cd <project>
slug="<slug>"
name="<original-branch-name>"

# 1. Fetch the backup ref into the live ref namespace from the object bundle:
git fetch "<bundle>/object-bundle.pack" \
  "refs/branch-rationalization-backup/$slug:refs/branch-rationalization-backup/$slug"

# 2. Restore the live branch from the (now-restored) backup ref:
git branch "$name" "refs/branch-rationalization-backup/$slug"

# 3. Verify byte-equal recovery:
expected_sha=$(awk -F'\t' -v s="$slug" '$1=="branch" && $2==s {print $3}' "<bundle>/index.tsv")
[ "$(git rev-parse "$name")" = "$expected_sha" ] && echo "OK" || echo "FAIL"
```

> **Why `git fetch <bundle>/object-bundle.pack <ref>:<ref>` and not `git bundle unbundle`?** Both work; `git fetch` is more idiomatic and only pulls the refs you ask for, while `unbundle` ingests every object in the bundle. The recovery recipe uses `fetch` to keep the operation surgical.

**Recipe — fall back to format-patch (when the pack is unreadable but per-branch patches survive):**

```bash
cd <project>
slug="<slug>"
name="<original-branch-name>"

# 1. Identify the merge-base from the bundle:
mb=$(awk -F'\t' -v s="$slug" '$1=="branch" && $2==s {print $4}' "<bundle>/index.tsv")
git rev-parse "$mb" >/dev/null 2>&1 || {
  echo "merge-base $mb is also gone; restoration produces a new history line off canonical"
  mb=$(git rev-parse "$canonical")
}

# 2. Replay the format-patch series onto the merge-base:
git checkout -b "$name" "$mb"
git am "<bundle>/branches/$slug/format-patch/"*.patch

# 3. Verify the diff matches the bundle:
diff -q <(git diff --binary "$mb..$name") "<bundle>/branches/$slug/diff-vs-merge-base.diff" \
  && echo "OK: byte-equal diff" || echo "WARN: SHAs differ but content matches"
```

**Note:** `git am` produces NEW SHAs (different commit dates / committers). The history shape (file diffs, ordering, messages) is preserved byte-equal, but the SHAs in `git log` will differ. This is recovery-by-content, not recovery-by-SHA.

> **Why this works for branches but not for stashes:** Per [SKILL.md Axiom 7](../SKILL.md#the-rationalization-kernel-universal-axioms): "`git format-patch` IS valid for branches; it is NOT for stashes." Branches have a clean linear (or merge-tree) commit chain; format-patch produces an ordered series. Stashes are 2-or-3-parent merge commits where format-patch is index-only and produces empty patches. The branch recovery story uses format-patch as a first-class layer; the stash skill does not.

**If the bundle is also gone:** AR3 below.

**Prevention:** keep the bundle. Per [Axiom 18](../SKILL.md#the-rationalization-kernel-universal-axioms): "Drop the bundle only at the user's pace. The skill never deletes the bundle." Typical: 1–4 weeks after the run.

---

## AR2. Force-push to canonical mid-run

**Symptom:** during the run, someone force-pushed to `origin/<canonical>`. The local canonical has commits the new origin/canonical doesn't, and vice versa. The rationalization branch (created at Phase 8 from the OLD canonical's tip) now has a parent that's not reachable from the new canonical.

**Diagnosis:**

```bash
cd <project>

# Detect via fsck and reflog:
git fsck --lost-found 2>&1 | tee "$WS/fsck.log"
git reflog show "<canonical>" | head -20

# What's the rationalization-branch's base?
RB="branch-rationalization-<DATE>"
RB_BASE=$(git merge-base "$canonical" "$RB")
git cat-file -e "$RB_BASE" 2>/dev/null \
  && echo "rationalization-branch base $RB_BASE is reachable" \
  || echo "rationalization-branch base $RB_BASE is unreachable from new canonical (force-push artifact)"
```

If `RB_BASE` is unreachable, the rationalization branch's parents need re-parenting. The branch ref itself is fine (it's a real local ref); the problem is the implicit ancestry from canonical.

**Recovery options:**

### AR2a — `git replace --graft` (preferred — preserves SHAs)

Re-parent the rationalization branch's first commit onto the new canonical's tip without rewriting history:

```bash
cd <project>

NEW_CANONICAL_TIP=$(git rev-parse origin/<canonical>)
RB="branch-rationalization-<DATE>"

# Find the rationalization branch's first commit (just after the merge-base):
RB_FIRST=$(git rev-list --reverse "<canonical>..$RB" | head -1)

# Graft its parent onto the new canonical's tip:
git replace --graft "$RB_FIRST" "$NEW_CANONICAL_TIP"

# Verify:
git log --oneline "$NEW_CANONICAL_TIP..$RB" | head -10
```

The graft is a local-only ref (`refs/replace/<sha>`); it doesn't change SHAs. Push the rationalization branch with `git push --no-replace-objects` if you want the graft excluded; without that flag, `git push` excludes refs/replace/* by default.

### AR2b — Rebase the rationalization branch onto the new canonical (changes SHAs)

```bash
cd <project>
RB="branch-rationalization-<DATE>"
NEW_CANONICAL_TIP=$(git rev-parse origin/<canonical>)

git checkout "$RB"
git rebase --onto "$NEW_CANONICAL_TIP" $(git merge-base "<canonical>" "$RB") "$RB"
```

Conflicts may surface; resolve manually via Edit (per AGENTS.md "No Script-Based Changes"). The bundle's per-branch diffs are useful as references for what the original content was.

### AR2c — Cherry-pick each rationalization commit onto a fresh branch

When rebase fails with too many conflicts:

```bash
cd <project>
RB="branch-rationalization-<DATE>"
NEW_CANONICAL_TIP=$(git rev-parse origin/<canonical>)

git checkout -b "${RB}-onto-new-canonical" "$NEW_CANONICAL_TIP"
for sha in $(git rev-list --reverse "<canonical>..$RB"); do
  git cherry-pick "$sha" || {
    echo "Conflict at $sha; resolve via Edit, then 'git cherry-pick --continue'"
    break
  }
done
```

**Prevention:** Phase 0 captures `git rev-parse origin/<canonical>` into `project_profile.json:canonical_tip_at_phase0`. The cleanup-conductor (Phase 10) re-checks this before any branch deletion; if it differs, the run halts with incident I12 (force-push detected on upstream during run; see `subagents/incident-responder.md`).

---

## AR3. Lost rationalization branch + lost backup refs + lost bundle (the worst case)

**Symptom:** all three primary recovery layers are gone. The rationalization branch was deleted (Phase 10 succeeded for an applied-keeper bucket), the backup refs were `git update-ref -d`'d, and the bundle was `mv`'d to a forgotten location.

**Recovery options:**

### AR3a — Remote reflog (if the rationalization branch was pushed)

```bash
cd <project>

# Has the rationalization branch ever been pushed?
git fetch origin "refs/heads/branch-rationalization-<DATE>:refs/heads/branch-rationalization-<DATE>-recovered"
# If origin still has it, this restores it locally.

# Or via the GitHub/GitLab UI's "deleted branches" tab if the host supports recovery
# (GitHub does for ~90 days post-delete via the API).
```

Verify against the bundle's `index.tsv` if you can find it:

```bash
expected_tip=$(awk -F'\t' '$1=="rationalization-branch" {print $3}' "<bundle>/index.tsv")
[ "$(git rev-parse branch-rationalization-<DATE>-recovered)" = "$expected_tip" ] && echo "OK" || echo "DIVERGED"
```

### AR3b — Filesystem snapshots

If the user's filesystem supports snapshots (zfs, btrfs, Time Machine, Windows VSS, macOS APFS snapshots), there is almost certainly an older snapshot containing `.git/refs/heads/branch-rationalization-<DATE>` or `.git/refs/branch-rationalization-backup/*` or the bundle directory.

```bash
# zfs:
zfs list -t snapshot -o name,creation | grep <pool>/<dataset>
# Mount the snapshot read-only, copy refs back:
zfs clone <pool>/<dataset>@<snap> <pool>/recovery
cp /<recovery>/.git/refs/heads/branch-rationalization-<DATE> .git/refs/heads/

# btrfs:
sudo btrfs subvolume list -t /
sudo btrfs subvolume snapshot -r /<subvol> /<recovery>
# Then copy from the recovery snapshot

# Time Machine:
tmutil listbackups
# Then `cp` from the backup mountpoint

# APFS snapshots (macOS, automatic):
tmutil listlocalsnapshots /
sudo mount_apfs -s "<snapshot-name>" / /tmp/snapshot
```

### AR3c — Forensic git tooling

```bash
cd <project>
git fsck --full --no-reflogs --unreachable 2>&1 | tee "$WS/fsck-unreachable.log"
# Every unreachable commit object is a candidate. Look for ones with messages
# matching the rationalization run's commit-message-style:
git fsck --full --no-reflogs --unreachable | awk '/^unreachable commit/ {print $3}' \
  | xargs -I {} git log -1 --oneline {}
```

If commits matching the keeper-style appear, recover by branching from them:

```bash
git branch branch-rationalization-<DATE>-from-fsck <unreachable-sha>
```

### AR3d — Last resort: reconstruct from agent session history

If `cass` is installed (per [CASS-MINING.md](CASS-MINING.md)), the original session that ran the skill is in cass:

```bash
cass search "branch rationalization $BASENAME" --robot --limit 5 --days 30
```

The session's messages contain the rationalization-branch tip SHA in the handoff report, plus the keeper SHAs from the apply-log. This is reconstruction-by-narrative, not byte-equality recovery, but it can salvage the *intent* of the run.

**The unrecoverable case:** all three layers gone, no remote, no snapshots, no fsck artifacts, no cass. The work is lost. This is the only catastrophic failure the skill cannot save. Per [Axiom 4](../SKILL.md#the-rationalization-kernel-universal-axioms): "Beneficiary-style coherence: all five layers tell the same story" — when ALL the layers are simultaneously gone, the system has failed catastrophically and forensics is the only remaining option.

---

## AR4. Submodule divergence

**Symptom:** a recovered branch's `.gitmodules` points at a submodule SHA that no longer exists on the submodule's upstream (the submodule's upstream was force-pushed, or the SHA was never pushed).

**Diagnosis:**

```bash
cd <project>
git checkout branch-rationalization-<DATE>
git submodule status                           # ` ` = OK, `+` = SHA mismatch, `-` = uninitialized, `U` = merge conflicts
git submodule status | awk '/^-/ {print $2}'  # uninitialized submodules
git submodule status | awk '/^\+/ {print $2}' # diverged submodules
```

**Recovery — three layers:**

### AR4a — Initialize fresh + force update

```bash
git submodule update --init --recursive --remote
```

Pulls the submodule's current upstream tip; the rationalization-branch's recorded SHA is replaced. Acceptable when the submodule's content is "follow upstream" (common for vendored tools); bad when the recorded SHA was a deliberate pin.

### AR4b — Bundle's `.gitmodules` snapshot

The bundle captures `.gitmodules` content as part of `<bundle>/branches/<slug>/diff-vs-merge-base.diff`:

```bash
grep -A 5 ".gitmodules" "<bundle>/branches/<slug>/diff-vs-merge-base.diff"
# Restore the branch's intended pin from the diff record.
```

### AR4c — Request the SHA from submodule's host

If the submodule's upstream is on GitHub/GitLab and the SHA was force-pushed away, the host's reflog (admin-only) may still have it. File a support request with the host.

> **Why submodule divergence is in the advanced-recovery file, not the standard recipes:** Per [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md), the bundle records `.gitmodules` content but does NOT mirror the submodule's content into the bundle (it would balloon the bundle size). Submodule recovery depends on the submodule's host, which is outside the skill's scope.

**Prevention:** at Phase 3, `bundle-builder.md` records each branch's submodule pins into `<bundle>/branches/<slug>/meta.txt:submodule_pins=<list>`. This makes it easy to detect divergence at recovery time without re-reading every `.gitmodules`.

---

## AR5. LFS object missing

**Symptom:** a recovered branch references an LFS-tracked file. The bundle captured the LFS pointer text in the diff; the actual blob is no longer on the LFS server (LFS retention policy expired, server admin pruned it, or the LFS account was downgraded).

**Diagnosis:**

```bash
cd <project>
git checkout branch-rationalization-<DATE>
git lfs ls-files                       # list LFS files in the tree
git lfs fsck                           # verify LFS objects
git lfs pull                           # try to fetch missing blobs
# Errors of the form "object <oid> not found on remote" indicate AR5.
```

**Recovery — limited:**

### AR5a — Find the blob in another LFS source

If the user has a backup LFS server (or a colleague's working copy), copy the blob:

```bash
# On the system that has the blob:
LFS_OID="<oid-from-fsck>"
find ~ -path "*/lfs/objects/*/$LFS_OID*" -print

# Copy to the broken project:
cp /path/to/found/blob "<project>/.git/lfs/objects/<oid-prefix>/<oid-rest>/<oid>"
```

### AR5b — Filesystem snapshots

Same as AR3b — if `.git/lfs/objects/` is in a snapshot, restore from there.

### AR5c — Recover the pointer-only state

The bundle has the LFS pointer text. Apply it without the blob; the file in the working tree is the pointer (a small text file). The branch's history is intact; only the binary content is missing.

```bash
git checkout branch-rationalization-<DATE>
# Pointer files are checked out as-is; the user can decide whether to
# re-generate the binary content from source or accept the pointer-only state.
```

**The unrecoverable case:** if the LFS server is the only source and the blob is gone, the skill cannot help. Recovery requires LFS server admin access. Document the gap in the handoff report; the user pursues out-of-band.

> **Why this isn't a skill bug:** Per [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md), the bundle records the diff (which includes LFS pointer text), not LFS blobs. Mirroring LFS blobs into the bundle would balloon the bundle from megabytes to gigabytes — outside the skill's scope. The user is responsible for separate LFS backup if they need it.

---

## AR6. A branch was deleted before Phase 3 started

**Symptom:** the user (or another agent) deleted a branch out-of-band between Phase 0 and Phase 3. It's not in `branches.tsv` (because Phase 2 didn't see it), not in `refs/branch-rationalization-backup/*` (because Phase 3 didn't capture it), and not in the bundle (same reason). The reflog is the only safety net.

**Diagnosis:**

```bash
cd <project>
# The branch was named, say, "agent-cc-77-broken-attempt".
git reflog --all | grep "agent-cc-77-broken-attempt"
# Look for entries like:
#   abc1234 HEAD@{42}: branch: Created from main
#   def5678 HEAD@{43}: commit: agent's WIP
#   ...
#   ghi9012 HEAD@{44}: branch -D agent-cc-77-broken-attempt: deleted
```

**Recovery options:**

### AR6a — Reflog → re-create the branch

```bash
LAST_TIP=$(git reflog --all | grep -B 1 "branch -D agent-cc-77-broken-attempt" | head -1 | awk '{print $1}')
git branch agent-cc-77-broken-attempt-recovered "$LAST_TIP"
```

### AR6b — fsck unreachable + commit-message search

If the reflog has expired:

```bash
git fsck --full --no-reflogs --unreachable 2>&1 \
  | awk '/^unreachable commit/ {print $3}' \
  | xargs -I {} git log -1 --format='%H %s' {} \
  | grep -i "agent-cc-77\|broken-attempt"
```

Each match is a candidate; restore by branching from the SHA.

**Prevention:** Phase 0 captures the full branch list into `wt_phase0.txt`. Compare at Phase 2:

```bash
diff <(git branch | sort) <(awk 'NR>1 {print $1}' "$WS/wt_phase0_branches.txt" | sort)
```

If branches were deleted between Phase 0 and Phase 2, the inventory-agent surfaces the diff to the user before Phase 3 and offers to recover from reflog before bundling.

> **Why we tolerate this case at all:** Per [Axiom 12](../SKILL.md#the-rationalization-kernel-universal-axioms): "Concurrent agents' working-tree changes in any worktree are normal." Concurrent branch creation/deletion is a valid concurrent-agent workflow; the skill detects but does not block it. The bundle covers branches present *at Phase 3*; the reflog covers branches deleted before then.

---

## AR7. The bundle file itself was deleted

**Symptom:** DCG would block `rm -rf <bundle>`, but a savvy user might `mv <bundle> /tmp/throwaway/` accidentally, or the filesystem-cleanup cron might sweep it.

**Diagnosis:**

```bash
ls "<project-parent>/<basename>-branch-worktree-archive-<DATE>/" 2>&1
# "No such file or directory" → AR7 confirmed.

# Check the parent dir + standard locations:
ls "<project-parent>/" | grep "$BASENAME-branch-worktree-archive"
ls /tmp/ | grep "$BASENAME-branch-worktree-archive"
ls ~/Documents/ ~/Downloads/ ~/Desktop/ 2>/dev/null | grep "$BASENAME-branch-worktree-archive"

# Check the user's git-managed scratch dirs:
find /data/projects/ -maxdepth 3 -name "$BASENAME-branch-worktree-archive*" 2>/dev/null
```

**Recovery options:**

### AR7a — Filesystem snapshots (highest yield)

Same as AR3b. Bundles are typically tens of MB to a few GB; well within snapshot retention. Look for the bundle dir in:

- zfs/btrfs snapshots
- macOS Time Machine / APFS local snapshots
- Windows Volume Shadow Copy
- `~/.Trash` / `~/.local/share/Trash` (Linux desktop trash)

### AR7b — Filesystem trash

Most desktops `mv` to trash before unlinking. Check:

```bash
# Linux desktop (gvfs):
ls ~/.local/share/Trash/files/ 2>/dev/null | grep "$BASENAME-branch-worktree-archive"

# macOS:
ls ~/.Trash/ 2>/dev/null | grep "$BASENAME-branch-worktree-archive"
```

### AR7c — Backup ref recovery only

If the bundle is unrecoverable BUT the backup refs `refs/branch-rationalization-backup/*` are still in `.git/refs/`, the live ref namespace is the alternative recovery surface. Re-create the branches from backup refs:

```bash
cd <project>
git for-each-ref refs/branch-rationalization-backup/ --format='%(refname:short) %(objectname:short)' \
  | while read slug sha; do
      slug="${slug#branch-rationalization-backup/}"
      original_name=$(echo "$slug" | tr '_' '/')   # rough reverse-slug
      git rev-parse "$original_name" >/dev/null 2>&1 || git branch "$original_name" "$sha"
    done
```

Verify counts: `git for-each-ref refs/branch-rationalization-backup/ | wc -l` should match the original `index.tsv` row count for branches.

### AR7d — Leftover pack files

`.git/objects/pack/` may have pack files from the bundle's namespace if the bundle was created via `git bundle create` AND the user ran `git bundle unbundle <bundle>` mid-session (the unbundle imports objects into the live repo). Look for orphaned packs:

```bash
ls -la .git/objects/pack/
# Any pack file modified at the bundle creation time is a candidate.
```

This is rare and only helps if `unbundle` was run; the typical recovery flow uses `git fetch` against the bundle file, which does NOT permanently import.

**Prevention:** the user is told (in [SKILL.md "What This Skill Produces"](../SKILL.md#what-this-skill-produces)) and in the bundle's README never to `mv` or delete the bundle dir while the rationalization branch hasn't been merged. The handoff report explicitly says: "Bundle is at `<path>` — keep it for 1–4 weeks; do not move or delete until the rationalization branch has merged successfully."

---

## When to escalate

The skill's recovery options are designed to make most catastrophes recoverable. The cases that are NOT recoverable in any layer:

- **AR3 with no remote, no snapshots, no fsck artifacts, no cass.** Catastrophic data loss.
- **AR1 with no bundle.** Same as AR3.
- **AR4c with no submodule host access.** Submodule blob is permanently lost.
- **AR5c with no LFS server access AND no snapshot.** LFS blob permanently lost.
- **Filesystem catastrophe.** Disk loss, OS reinstall without backups.
- **Git internal corruption.** `.git/` is mangled and `git fsck` reports object errors.

For these, escalate to:

- The user's backup system (off-skill — out of scope)
- Forensic git tooling (`git fsck`, `git reflog --all`, manual pack-file inspection)
- The hosting provider's deleted-branch / deleted-tag recovery API (GitHub: ~90 days; GitLab: configurable)
- A senior engineer who knows the codebase well enough to reconstruct from memory

The skill never claims to recover from disk loss. It claims to make every removal/deletion reversible *while the bundle and refs are intact* AND to maximize the chance of recovery (via reflog, fsck, snapshots) when they aren't.

---

## Cross-links

- Standard recovery recipes: [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md) R1–R14
- Bundle layout (the recipes' input): [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md)
- Safety guarantees: [SAFETY-MODEL.md](SAFETY-MODEL.md)
- Mid-run incidents: `subagents/incident-responder.md` (see also forthcoming INCIDENT-PLAYBOOK.md)
- Forced-push detection during run: incident I12 (in `subagents/incident-responder.md`)
