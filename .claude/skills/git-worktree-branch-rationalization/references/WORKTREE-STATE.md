# Working Tree State Guidance — Multi-Worktree Edition

The working trees are shared with concurrent agents and the user. With 5–80 simultaneously-bloated worktrees, the skill must reason about each working tree carefully and never disturb in-flight work in any of them.

> **One Rule.** Per [SKILL.md Axiom 12](../SKILL.md#the-rationalization-kernel-universal-axioms), treat working-tree drift in any worktree as if you made it. Snapshot once at Phase 0; re-snapshot before each destructive operation; never stash, revert, or overwrite a parallel agent's work.

---

## The State Space (per worktree)

At any point during the run, each worktree can be in one of these states:

| State | `git status` shows | What it means |
|-------|---|---|
| **Clean** | nothing to commit | No working changes; safe to remove (after bundle capture confirms empty dirty state) |
| **Self-modified** | files modified by *this* run | Mid-Phase-8 apply in progress on the rationalization branch (active worktree only) |
| **Concurrent-modified** | files modified by *other* agents | Concurrent work; per AGENTS.md, treat as if you made them; never overwrite |
| **Mixed** | both self and concurrent | Common during Phase 8 in the active worktree; never on linked worktrees |
| **Mid-merge** | unmerged paths | A merge in progress in this worktree; HALT all destructive ops on it |
| **Mid-rebase** | rebase / cherry-pick / revert in progress | An incomplete operation; HALT |
| **Locked** | `git worktree list --porcelain` shows `locked` | Another tool reserved the worktree; surface to user before any action |

The skill needs to:

- **Refuse to start** if the *active* worktree (CWD) is in Mid-merge / Mid-rebase (Phase 0 pre-condition).
- **Snapshot every worktree** at Phase 0 so it can distinguish "self" from "concurrent" later (`wt_phase0.txt` per worktree).
- **Re-snapshot before each Phase 8 apply** in the active worktree so it can detect new concurrent work.
- **Re-snapshot before each Phase 10 removal** of any linked worktree so a last-second dirty-state capture is in the bundle.
- **Never overwrite** concurrent agents' files in any worktree.

> Why per-worktree? Because dirty state is per-worktree but stashes are not (per the sibling skill's [WORKING-TREE-STATE.md](../../git-stash-janitor/references/WORKING-TREE-STATE.md)). With many worktrees, you have N independent state spaces to track.

---

## Phase 0 Snapshot — Every Worktree

```bash
scripts/snapshot-tree.sh <project> phase0
```

For a multi-worktree repo this means: enumerate every worktree (active + linked), snapshot `git status --porcelain=v2` for each, write to `wt_phase0/<sanitized-path>.txt`.

```bash
# Concrete commands for the snapshot:
git -C <project> worktree list --porcelain > .worktree_branch_rationalization_workspace/worktrees_phase0.porcelain

while IFS= read -r path; do
  # sanitize the path for use as filename: replace / with _, strip leading _
  slug=$(echo "$path" | tr '/' '_' | sed 's/^_//')
  git -C "$path" status --porcelain=v2 \
    > ".worktree_branch_rationalization_workspace/wt_phase0/${slug}.txt"
done < <(awk '/^worktree /{print $2}' .worktree_branch_rationalization_workspace/worktrees_phase0.porcelain)
```

This is the baseline. Anything in any of these snapshots is "pre-existing concurrent work" and should not be disturbed.

If any snapshot is non-empty, the skill reports:

> Working tree starts non-empty in N worktrees. The following files have changes
> that were here before this run started — I will not modify them. They appear
> to be concurrent agents' work in progress (per AGENTS.md):
>
> /data/projects/asupersync (active):
>   M src/foo.rs
>   M src/bar.rs
>   ?? .scratch/
>
> /data/projects/asupersync-wt-feature-x (linked):
>   M src/baz.rs
>
> /data/projects/asupersync-wt-tokio-rich (linked):
>   ?? bench/results/
>
> Continuing.

---

## Per-Apply Snapshot (Phase 8) — Active Worktree Only

Phase 8 commits land on the **active worktree** (the user's CWD), where the rationalization branch lives. Linked worktrees on other branches are NOT touched by Phase 8 applies.

Before each Phase 8 apply:

```bash
git -C <project> status --porcelain=v2 \
  > .worktree_branch_rationalization_workspace/wt_pre_apply_<N>.txt
```

The diff between `wt_phase0/<active-slug>.txt` and `wt_pre_apply_<N>.txt` tells you:

- **What new files appeared** between Phase 0 and now → concurrent agents' work
- **What new files appeared since last apply** → either concurrent agents OR the previous apply's effect (logged in `apply_log.tsv`)

The Phase 8 worker reasons:

```
new_files_total = files_in_wt_pre_apply_<N> - files_in_wt_phase0[active]
new_files_from_self = files_in_apply_log_for_already_applied
new_files_from_concurrent = new_files_total - new_files_from_self

# Concurrent files: do not touch.
# Self files: expected; we authored them.
```

> Why: per [SKILL.md operator ↺ WORKING-TREE-DRIFT](../SKILL.md#operator-library--the-cognitive-moves), "before each Phase 8 apply, re-snapshot `git status` in every active worktree; if changes appear from other agents, treat as if you made them; never stash/revert/overwrite."

---

## Per-Removal Snapshot (Phase 10) — Every Linked Worktree About to Be Pruned

Before each Phase 10 worktree removal, re-snapshot the target worktree's state and compare against the bundle's captured state:

```bash
# Re-snapshot just before removal:
git -C "$target_wt" status --porcelain=v2 \
  > .worktree_branch_rationalization_workspace/wt_pre_remove_<slug>.txt

# Compare to bundle's captured state:
diff "$BUNDLE/worktrees/<slug>/status.txt" \
     ".worktree_branch_rationalization_workspace/wt_pre_remove_<slug>.txt"
```

If the comparison shows new changes that are NOT in the bundle:

- A concurrent agent has added work in this worktree since Phase 3.
- Re-capture the dirty state into the bundle BEFORE proceeding (or refuse to remove and surface to user).

> Why: a worktree may sit dormant during the long Phase 5–9 cycle, then a concurrent agent drops into it just before Phase 10. Snapshotting at Phase 3 alone is insufficient.

---

## Active Worktree Gets Special Treatment

The active worktree (the user's CWD) is where Phase 8 commits actually land on the rationalization branch. Special invariants:

- **Never auto-removed.** Per [SKILL.md Axiom 11](../SKILL.md#the-rationalization-kernel-universal-axioms), the active worktree is auto-protected. The handoff at Phase 11 tells the user how to remove it themselves from a different working directory if they want to.
- **Mid-rebase / mid-merge / mid-cherry-pick aborts the run.** Phase 0 refuses to start if the active worktree is in any of these states; the user finishes the operation first.
- **Phase 8 applies happen here.** The rationalization branch is created from canonical's tip in this worktree, and every cherry-pick / squash-merge / harmonized-synthesis lands here.
- **Concurrent drift is acknowledged but not blocked-on.** Per AGENTS.md "Note for Codex/GPT-5.5", do NOT stop and ask the user about concurrent work in the active worktree — proceed with the apply, log the drift in `apply_log.tsv`, and let git's merge logic handle context drift.

---

## Linked Worktrees on the Same Branch as the Rationalization Branch

The rationalization branch `branch-rationalization-<DATE>` is created in the active worktree from canonical's tip. It exists nowhere else. Therefore:

- **No linked worktree is ever on the rationalization branch.** Git refuses to check out the same branch in multiple worktrees, so this is impossible by construction.
- **But files in linked worktrees may be open in the user's editor.** When you commit to the rationalization branch in the active worktree, those changes don't propagate to the linked worktrees' filesystems — they're on different branches. Still, if the user has their editor open with files from the linked worktree, the editor's "last saved" buffer is independent of git operations.

The warning matters operationally, even though git protects against the cross-worktree branch conflict:

> Note: linked worktrees `/data/projects/asupersync-wt-feature-x` and
> `/data/projects/asupersync-wt-tokio-rich` are on different branches than
> the rationalization branch — Phase 8 commits don't propagate to them. If
> you have files from those worktrees open in your editor, your editor's
> view of those files is independent of this run.

---

## Submodule Init State per Worktree

`git worktree add` does NOT auto-init submodules. Each worktree may have a different submodule state:

- **Initialized:** `<worktree>/<submodule>/.git` exists; cloned content is present.
- **Uninitialized:** `<worktree>/<submodule>/` is empty; the submodule pointer is set in the index but no files.
- **Partially initialized:** some nested submodules cloned, others not.

The skill must capture submodule init state per worktree in `worktrees.tsv`:

```
path                                  branch          dirty   submodules_init   ...
/data/projects/asupersync             main            mixed   yes               ...
/data/projects/asupersync-wt-foo      feature/foo     clean   no                ...
/data/projects/asupersync-wt-tokio    tokio-rich      clean   partial(2/3)      ...
```

Why this matters:

- **Removing a worktree** does NOT propagate submodule cache changes. `git worktree remove` cleans `.git/worktrees/<id>/` admin metadata but the submodule's inner `.git/` (if cloned inside the worktree) goes away with the worktree's directory.
- **Restoring a worktree** (via `git worktree add`) doesn't re-init submodules; the user runs `git submodule update --init` if needed.

> Why: [SKILL.md Failure Modes](../SKILL.md#failure-modes-table--branch--worktree-footguns): "Submodule init state varies per worktree — git worktree add doesn't auto-init submodules; some worktrees may have submodules cloned, others not. Removing a worktree leaves the submodule cache untouched; .git/worktrees/<id>/ IS pruned. Document the per-worktree submodule state in worktrees.tsv."

---

## Agent-Mail Coordination (When Available)

When `agent-mail` is available, reserve relevant paths to prevent a parallel skill run from kicking off:

```python
# Phase 0 — at session start:
agent_mail.macro_start_session(
    project_key="/data/projects/asupersync",
    program="claude-code",
    model="claude-opus-4-7",
)

agent_mail.file_reservation_paths(
    project_key="/data/projects/asupersync",
    agent_name="<self>",
    paths=[
        ".git/worktrees/**",        # worktree admin metadata
        ".git/refs/heads/**",        # all local branches
        ".git/refs/branch-rationalization-backup/**",  # our backup namespace
    ],
    ttl_seconds=14400,              # 4 hours; renew as needed
    exclusive=True,
    reason="branch-rationalization-<run-id>",
)
```

The reservation is **advisory only** — git itself doesn't honor it. But other Claude/Codex/Gemini agents reading `agent_mail` see the reservation and avoid kicking off a competing branch-rationalization run on the same repo.

> Why: per [SKILL.md "Up-Front Confirmations"](../SKILL.md#up-front-confirmations-ask-before-starting): "If yes [other agents in this repo right now], run agent-mail file_reservation_paths(... [".git/worktrees/**", ".git/refs/heads/**"], reason='branch-rationalization-<run-id>') advisory-only."

Release reservations at Phase 11 (handoff complete):

```python
agent_mail.release_file_reservations(
    project_key="/data/projects/asupersync",
    agent_name="<self>",
    paths=[".git/worktrees/**", ".git/refs/heads/**", ".git/refs/branch-rationalization-backup/**"],
)
```

---

## After-Apply State (Active Worktree)

After a Phase 8 apply commits successfully, the active worktree should be clean (because we committed everything we changed). If it's NOT clean after `git commit`:

- Either there were concurrent changes that we did NOT commit (good — we left them alone).
- Or our `git add` missed something (bad — investigate).

The Phase 8 worker logs the post-commit state:

```bash
git -C <project> status --porcelain=v2 \
  > .worktree_branch_rationalization_workspace/wt_post_apply_<N>.txt
```

If `wt_post_apply_<N>.txt` shows files we expected to commit, the apply is partial — halt and investigate. If it shows files that match the pre-apply concurrent-drift list, that's expected (we left them alone) — proceed.

---

## Why Not Spawn a Worktree for the Run?

A natural thought: "spawn a fresh worktree just for the rationalization run, never touch any existing worktree."

This doesn't work cleanly because:

1. **Branches are repo-global.** The rationalization branch and backup refs live in `.git/refs/`, which all worktrees share. Phase 10 deletions affect every worktree's view.
2. **The user already accepts that concurrent agents work in the same checkout.** This is the AGENTS.md model.
3. **The rationalization branch has to be checked-out somewhere.** The active worktree is the natural home; spawning a fresh one would just shift where "active" means.
4. **Worktree spawning itself would compound the very problem the skill is solving** — adding more worktrees to a repo that's already drowning in them.

The right approach is to share the existing active worktree but be principled about disturbance: snapshot every worktree, don't overwrite concurrent work in any of them, surface conflicts.

---

## Handling The "I Did Not Touch That" Pattern

Per AGENTS.md "Note for Codex/GPT-5.5":

> NEVER EVER DO THAT AGAIN. The answer is literally ALWAYS the same: those
> are changes created by the potentially dozen of other agents working on
> the project at the same time.

The skill explicitly does NOT ask the user about working-tree drift it didn't cause. When `wt_pre_apply_<N>.txt` shows new files in the active worktree:

- **Don't ask.** Don't say "I see unexpected changes, please advise."
- **Treat as self-committed for the purpose of git's merge semantics.** Proceed with the apply.
- **Note in apply_log.tsv** that drift was detected (`pre_apply_drift: concurrent`).

The 3-way merge handles context drift via Git's merge logic, not via Q&A with the user.

The same principle applies for linked worktrees in Phase 10: if a linked worktree shows new changes since Phase 3, RE-CAPTURE them into the bundle (don't ask), then proceed with the removal authorization flow.

---

## When Concurrent Drift Conflicts With An Apply

If a Phase 8 apply (cherry-pick / squash-merge / Edit-tool harmonized synthesis) fails specifically because of concurrent drift in the active worktree (a file the apply touches was *also* modified by a concurrent agent):

This IS a case where surfacing to the user is correct, because:

- The user (or the other agent) has context the skill doesn't.
- Resolving the conflict requires knowing which side is "right" — the keeper's recovered hunk, or the concurrent agent's in-progress work.
- Auto-resolving could corrupt either party's intent.

The escalation flow:

```
The apply for branch <feature/foo> would touch src/foo.rs at line 218.
Another agent has unsaved changes to src/foo.rs in this worktree
(visible in `git status` but not committed yet — possibly mid-edit).

The keeper's change: <hunk>
The concurrent agent's change: <diff vs. HEAD>

Possible resolutions:
  (a) Apply the keeper; the concurrent agent's edit may need to be redone
      (their working state would conflict with the new commit).
  (b) Skip this keeper for now; come back when the concurrent work is committed.
  (c) Surface to the concurrent agent (via Agent Mail) and coordinate.

Default: (b). Continue?
```

The user (or a coordinator agent reading the Mail) makes the call.

---

## Concrete Commands — Snapshot, Diff, Interpret

### Snapshot every worktree (Phase 0)

```bash
mkdir -p .worktree_branch_rationalization_workspace/wt_phase0
git worktree list --porcelain > .worktree_branch_rationalization_workspace/worktrees.porcelain

awk '/^worktree /{print $2}' .worktree_branch_rationalization_workspace/worktrees.porcelain |
while IFS= read -r path; do
  slug=$(echo "$path" | tr '/' '_' | sed 's/^_//')
  if [ -d "$path/.git" ] || [ -f "$path/.git" ]; then
    git -C "$path" status --porcelain=v2 \
      > ".worktree_branch_rationalization_workspace/wt_phase0/${slug}.status"
    git -C "$path" rev-parse HEAD \
      > ".worktree_branch_rationalization_workspace/wt_phase0/${slug}.head"
    # Capture branch (or "DETACHED" if detached HEAD):
    branch=$(git -C "$path" symbolic-ref --quiet --short HEAD || echo "DETACHED")
    echo "$branch" > ".worktree_branch_rationalization_workspace/wt_phase0/${slug}.branch"
  else
    echo "MISSING: $path" >> .worktree_branch_rationalization_workspace/wt_phase0/_missing.log
  fi
done
```

### Interpret `git status --porcelain=v2` output

`--porcelain=v2` is the machine-friendly format the skill uses (over the older `--porcelain=v1`). Key prefixes:

| Prefix | Meaning |
|--------|---------|
| `1 <XY> ...` | Ordinary changed entry; `XY` is staged/unstaged status (`M.` = staged-modified, `.M` = unstaged-modified, `MM` = both) |
| `2 <XY> ...` | Renamed/copied entry |
| `u <XY> ...` | Unmerged entry (conflict) — HALT signal for the worktree |
| `? <path>` | Untracked entry |
| `! <path>` | Ignored entry (only with `--ignored`) |

Detection rules:

- **Clean:** zero non-empty lines.
- **Self-modified vs concurrent:** compare to `wt_phase0` snapshot; new entries since Phase 0 are "post-Phase-0", which on the active worktree is either self (Phase 8 work) or concurrent.
- **Mid-merge / mid-rebase:** any `u <XY>` line, OR `git rev-parse --git-dir`/`MERGE_HEAD`, `REBASE_HEAD`, `CHERRY_PICK_HEAD` exists.

```bash
# Quick "is this worktree mid-something?" check:
for state_file in MERGE_HEAD REBASE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  if [ -f "<worktree>/.git/$state_file" ] || \
     [ -f "$(git -C <worktree> rev-parse --git-dir)/$state_file" ]; then
    echo "MID-OPERATION: $state_file present"
  fi
done
```

### Diff snapshots across phases

```bash
# What changed in the active worktree since Phase 0?
diff -u .worktree_branch_rationalization_workspace/wt_phase0/<active-slug>.status \
        .worktree_branch_rationalization_workspace/wt_pre_apply_<N>.status \
  | grep -E '^[+-][12u?]'   # show only entry-line changes
```

### Capture dirty-state into the bundle (Phase 3 + Phase 10 re-capture)

Per [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md) `worktrees/<slug>/`:

```bash
# For each non-active worktree (active is auto-protected):
slug=$(echo "$path" | tr '/' '_' | sed 's/^_//')
mkdir -p "$BUNDLE/worktrees/$slug"

# meta.txt:
{
  echo "original_path=$path"
  echo "branch=$(cat $WORKSPACE/wt_phase0/${slug}.branch)"
  echo "head_sha=$(cat $WORKSPACE/wt_phase0/${slug}.head)"
  echo "captured_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "locked=$(awk -v p="$path" '/^worktree /{cur=$2} /^locked/{if(cur==p) print "true"}' $WORKSPACE/worktrees.porcelain | head -1 || echo false)"
  echo "submodules_init=<probe per submodule>"
} > "$BUNDLE/worktrees/$slug/meta.txt"

# status.txt — porcelain snapshot:
git -C "$path" status --porcelain=v2 > "$BUNDLE/worktrees/$slug/status.txt"

# staged.diff — index vs HEAD:
git -C "$path" diff --binary --cached > "$BUNDLE/worktrees/$slug/staged.diff"

# unstaged.diff — working tree vs index:
git -C "$path" diff --binary > "$BUNDLE/worktrees/$slug/unstaged.diff"

# untracked.tar.gz — only if untracked content existed:
untracked_count=$(git -C "$path" ls-files --others --exclude-standard | wc -l)
if [ "$untracked_count" -gt 0 ]; then
  git -C "$path" ls-files --others --exclude-standard -z > "$BUNDLE/worktrees/$slug/.untracked.list"
  tar --null -czf "$BUNDLE/worktrees/$slug/untracked.tar.gz" \
    -C "$path" \
    -T "$BUNDLE/worktrees/$slug/.untracked.list"
fi
```

---

## Edge Case: Detached HEAD on a Linked Worktree

A worktree can be on detached HEAD (`git checkout <sha>` instead of a branch). The skill captures the SHA as the "branch" field in `worktrees.tsv` with a `DETACHED:` prefix.

Triage logic:

- The "branch" is just the commit SHA; `git cherry -v <canonical> <sha>` still works for already-merged detection.
- Removing the worktree doesn't free a branch ref (there's no branch to free), so [SKILL.md Axiom 9](../SKILL.md#the-rationalization-kernel-universal-axioms) ordering doesn't apply — detached-HEAD worktrees can be removed in any order.
- The handoff lists detached-HEAD worktrees separately so the user knows their commit SHAs aren't branch-anchored.

If the *active* worktree is in detached HEAD, [SKILL.md "When NOT to Use"](../SKILL.md#when-not-to-use-this-skill) refuses: "Detached HEAD on the active worktree with no rationalization-branch base."

---

## Edge Case: LFS-Tracked Files in Linked Worktrees

If the repo uses Git LFS, dirty staged/unstaged diffs in a worktree may include LFS pointers, not file contents. Recovery requires `git lfs fetch` to be functional in the target environment.

Phase 0 detects LFS:

```bash
git config --get-all filter.lfs.process
```

If present, the bundle's `worktrees/<slug>/meta.txt` includes `lfs_in_use=true`, and the handoff report notes: "this repo uses Git LFS; ensure `git lfs fetch` works before relying on recovered files' content."

---

## Cross-References

- The bundle layout that consumes per-worktree captures: [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md)
- Branch and worktree smell taxonomy: [BRANCH-WORKTREE-SMELLS.md](BRANCH-WORKTREE-SMELLS.md)
- Refusal conditions per worktree state: [WHEN-NOT-TO-USE.md](WHEN-NOT-TO-USE.md)
- Sibling skill's working-tree-state guide: [WORKING-TREE-STATE.md](../../git-stash-janitor/references/WORKING-TREE-STATE.md)
- The 19-axiom kernel: [SKILL.md "THE RATIONALIZATION KERNEL"](../SKILL.md#the-rationalization-kernel-universal-axioms)
- AGENTS.md "Note for Codex/GPT-5.5": [AGENTS.md](../../../../AGENTS.md)
