# Working Tree State Guidance

The working tree (the files in the repo that aren't yet committed) is shared with concurrent agents and the user. The skill must reason about it carefully.

---

## The State Space

At any point during the run, the working tree can be in one of these states:

| State | `git status` shows | What it means |
|-------|-----|-------|
| **Clean** | nothing to commit | No working changes; safe to apply diffs |
| **Self-modified** | files modified by *this* run | Mid-Phase-6 apply in progress |
| **Concurrent-modified** | files modified by *other* agents | Concurrent work; per AGENTS.md, treat as if you made them |
| **Mixed** | both self and concurrent | Common during Phase 6 |
| **Mid-merge** | unmerged paths | A merge in progress; HALT |
| **Mid-rebase** | rebase / cherry-pick / revert in progress | An incomplete operation; HALT |

The skill needs to:
- **Refuse to start** in Mid-merge / Mid-rebase (Phase 0).
- **Snapshot at start** so it can distinguish "self" from "concurrent" later (Phase 0).
- **Re-snapshot before each apply** (Phase 6) so it can detect new concurrent work.
- **Never overwrite** concurrent agents' files.

---

## Phase 0 Snapshot

```bash
scripts/snapshot-tree.sh <project> phase0
```

This is the baseline. Anything in this snapshot is "pre-existing concurrent work" and should not be disturbed.

If the baseline is non-empty, the skill should report it to the user:

> Working tree starts non-empty. The following files have changes that
> were here before this run started — I will not modify them. They appear
> to be concurrent agents' work in progress (per AGENTS.md):
>
>   M src/foo.rs
>   M src/bar.rs
>   ?? .scratch/
>
> Continuing.

---

## Per-Apply Snapshot (Phase 6)

Before each Phase 6 apply:

```bash
git -C <project> status --porcelain=v2 \
  > .stash_janitor_workspace/wt_pre_apply_<N>.txt
```

The diff between `wt_phase0.txt` and `wt_pre_apply_<N>.txt` tells you:

- **What new files appeared** between Phase 0 and now → concurrent agents' work
- **What new files appeared since last apply** → either concurrent agents OR the previous apply's effect

The Phase 6 worker reasons:

```
new_files_total = files_in_wt_pre_apply_<N> - files_in_wt_phase0
new_files_from_self = files_in_apply_log_for_already_applied
new_files_from_concurrent = new_files_total - new_files_from_self

# Concurrent files: do not touch.
# Self files: expected; we authored them.
```

---

## After-Apply State

After a Phase 6 apply commits successfully, the working tree should be clean (because we committed everything we changed). If it's NOT clean after `git commit`:

- Either there were concurrent changes that we did NOT commit (good — we left them alone).
- Or our `git add` missed something (bad — investigate).

The Phase 6 worker logs the post-commit state:

```bash
git -C <project> status --porcelain=v2 \
  > .stash_janitor_workspace/wt_post_apply_<N>.txt
```

If `wt_post_apply_<N>.txt` shows files we expected to commit, the apply is partial — halt and investigate.

---

## Why Not Use a Worktree

A natural thought: "spawn a worktree, do all the apply work there, never touch the main checkout."

This doesn't work cleanly because:

1. **Stashes are per-repo, not per-worktree.** A worktree's `git stash list` shows the same stashes. Phase 9 drops would affect the user's main checkout.
2. **The recovery branch needs to land on the user's primary.** Working in a worktree adds a `git worktree push` / `git fetch` / `git pull` step the skill would have to manage.
3. **DCG might block worktree operations** depending on configuration.
4. **The user already accepts that concurrent agents work in the same checkout.** This is the AGENTS.md model.

The right approach is to share the checkout but be principled about disturbance: snapshot, don't overwrite concurrent work, surface conflicts.

---

## Handling The "I Did Not Touch That" Pattern

Per AGENTS.md "Note for Codex/GPT-5.5":

> NEVER EVER DO THAT AGAIN. The answer is literally ALWAYS the same: those
> are changes created by the potentially dozen of other agents working on
> the project at the same time.

The skill explicitly does NOT ask the user about working-tree drift it didn't cause. When `wt_pre_apply_<N>.txt` shows new files:

- **Don't ask.** Don't say "I see unexpected changes, please advise."
- **Treat as self-committed.** Proceed with the apply.
- **Note in apply_log.tsv** that drift was detected (`pre_apply_drift: concurrent`).

The 3-way merge handles context drift via Git's merge logic, not via Q&A with the user.

---

## When Concurrent Drift Conflicts With An Apply

If `git apply --3way` fails specifically because of concurrent drift (a file the apply touches was *also* modified by a concurrent agent):

This IS a case where surfacing to the user is correct, because:

- The user (or the other agent) has context the skill doesn't.
- Resolving the conflict requires knowing which side is "right" — the stash's recovered hunk, or the concurrent agent's in-progress work.
- Auto-resolving could corrupt either party's intent.

The escalation flow:

```
The apply for stash@{34} would touch src/foo.rs at line 218.
Another agent has unsaved changes to src/foo.rs (visible in the working tree
but not committed yet — possibly mid-edit).

The stash's change: <hunk>
The concurrent agent's change: <diff vs. HEAD>

Possible resolutions:
  (a) Apply the stash; the concurrent agent's edit may need to be redone
      (their working state would conflict with the new commit).
  (b) Skip this stash for now; come back when the concurrent work is committed.
  (c) Surface to the concurrent agent (via Agent Mail) and coordinate.

Default: (b). Continue?
```

The user (or a coordinator agent reading the Mail) makes the call.

---

## Edge Case: Worktree-Specific Stashes

If the user is operating in a worktree (`git worktree list` shows multiple), stashes are still shared across worktrees, but the working tree is the worktree's, not the main repo's.

Phase 0 detects worktree mode:
```bash
$ git -C <project> rev-parse --git-dir
/data/projects/main/.git/worktrees/feature-x   # worktree
# vs.
/data/projects/main/.git                       # main checkout
```

Worktree-specific guidance in Phase 10's handoff:

> You're operating in worktree `feature-x` at `/data/projects/main/feature-x`.
> Stash drops affect the entire repo (not just this worktree). Backup refs
> at `refs/stash-backup/*` are visible from all worktrees on this repo.
>
> The recovery branch `stash-recovery-<DATE>` was created in this worktree.
> If you want to ship from the main checkout, you'll need to fetch from this
> worktree or push and re-checkout. See `git worktree --help`.

---

## Edge Case: Detached HEAD

If the user is on a detached HEAD (`git status` shows `HEAD detached at <sha>`), the skill needs a primary branch to land keepers onto. Phase 0 surfaces:

> You're on a detached HEAD. The stash janitor lands keeper commits on a
> recovery branch off the primary branch (`<primary>`). Do you want to:
>   (a) Checkout the primary branch first; come back to detached HEAD after
>   (b) Use a different recovery base (specify branch)
>   (c) Abort

Default: (a) with explicit user OK.

---

## Edge Case: Submodules

If `<project>` has submodules, stashes can include submodule pointer changes. The bundle's diff captures these as `Subproject commit <old> -> <new>` lines.

Recovery via `git apply --3way` works for submodule pointer changes if the new submodule SHA is fetchable. If not, the apply fails with a clear error — escalate to user.

---

## Edge Case: LFS-tracked Files

If the repo uses Git LFS, stashes of LFS-tracked files include LFS pointers, not file contents. Recovery requires `git lfs fetch` to be functional. If LFS is misconfigured, the apply succeeds but the file is just a pointer.

Phase 0 detects LFS:
```bash
git config --get-all filter.lfs.process
```

If present, the handoff report includes a note: "this repo uses Git LFS; ensure `git lfs fetch` works before relying on recovered files' content."
