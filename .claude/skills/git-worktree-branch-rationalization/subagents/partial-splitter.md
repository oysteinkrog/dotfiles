---
name: partial-splitter
description: Phase 8b — for each `partially-novel` branch, identify the subset of commits whose content is novel-and-accretive (Phase 5 triage marked these); cherry-pick that subset onto the rationalization branch in dependency order. ⇄ SPLIT-COMMITS-HUNKS.
---

# Partial Splitter

Owns Phase 8b. The branch-aware analogue of git-stash-janitor's hunk-splitter: instead of splitting hunks within a single stash diff, this subagent splits a branch into its novel-only commit subset and cherry-picks that subset onto the rationalization branch.

Why a separate subagent: Phase 8 keeper-applier handles per-branch single-strategy applies. Partial branches need per-commit triage AND per-commit cherry-pick — different cognitive load and different working-tree discipline. Sequencing it after Phase 8 main loop keeps the re-fingerprint baseline consistent.

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path
- `{CANONICAL}` — canonical branch
- `{RATIONALIZATION_BRANCH}` — branch with the keeper commits from Phase 8

## Outputs

- `<workspace>/partial_split_log.tsv` — `branch_slug|original_sha|new_sha|kept_or_dropped|position_in_split|gates_status|notes`; one row per source commit in every `partially-novel` branch.
- `<workspace>/conflicts/partial_<slug>.context.md` — one file per conflict including the dependency-hypothesis (which kept commit depends on which dropped commit's content); survives compaction.
- **Side effects:** cherry-picks the kept-subset commits onto `{RATIONALIZATION_BRANCH}` in original-commit (dependency) order. Pre-commit hooks run normally; never `--no-verify`. Never uses `git apply --include=<path>` (path-level, wrong tool). Never `git stash` / `git reset --hard` / `git checkout -- <path>` to back out — uses `git cherry-pick --abort`. Never deletes the source branch (Phase 10's job).
- **Decision contract:** Phase 8b exit requires every `partially-novel` row in `triage.tsv` to have at least one entry in `partial_split_log.tsv` (kept, dropped, or `partial-skipped` with user direction). Phase 9 (`fresh-eyes`) gates on Phase 8b completion.

## Workflow

For each `partially-novel` row in `triage.tsv` (those with `apply_strategy=split-commits`):

### 1. Identify the novel-commit subset

Read `<bundle>/branches/<slug>/commits.tsv` (one row per commit not on canonical). For each commit:
- Run `git cherry -v {RATIONALIZATION_BRANCH} <commit-sha>^..<commit-sha>` to check whether that *individual* commit's patch-id is on canonical or the rationalization branch tip.
- If `+`, commit is novel-on-rationalization-branch — keep.
- If `-`, commit's content already landed via squash/rebase or via an earlier Phase 8 apply — drop.

Triage's Phase 5 worker should have already produced this subset list; re-verify it here against the *current* rationalization-branch tip (Axiom: re-fingerprint after each apply changes the baseline; the `partially-novel` row's split list may have shifted).

Record kept vs. dropped commit SHAs in `<workspace>/partial_split_log.tsv`.

### 2. Order the kept commits by dependency

Commits depend on their predecessors. Kept commits must apply in original order — `git log --reverse <merge-base>..<branch>` gives the order; preserve it. If a kept commit depends on a dropped commit's content, the cherry-pick will conflict — surface to user with the dependency hypothesis ("kept commit C2 modifies a function introduced by dropped commit C1; C1's introduction must be replayed first or C2 must be re-authored without that dependency").

### 3. ↺ WORKING-TREE-DRIFT (operator `↺`)

Snapshot every active worktree's `git status --porcelain`. Same discipline as keeper-applier: never disturb concurrent agents' work.

### 4. Cherry-pick the subset

For each kept commit in dependency order:

```bash
git -C {PROJECT} cherry-pick --no-commit <SHA>   # dry-run via no-commit
# inspect the staged result
git -C {PROJECT} diff --cached
# if clean, finalize:
git -C {PROJECT} cherry-pick --continue   # OR git commit -m "<message>"
# if dirty, abort:
git -C {PROJECT} reset HEAD               # un-stage; do not git stash
```

NEVER use `git apply --include=<path>` for hunk-level filtering — it's path-level only and not the right tool here. NEVER use ad-hoc sed/awk/regex transformations on the diff (per AGENTS.md "No Script-Based Changes").

### 5. ⊕ RECOVER (operator `⊕`) — per-apply quality gates

After each successful cherry-pick:
```bash
{test_command}
{typecheck_command}
{lint_command}
ubs .
```

All must exit 0. Fail-on-trivial → Edit-tool fix → re-run; fail-on-non-trivial → surface as conflict.

### 6. Commit message — explicit "split-apply" annotation

The commit message rewrites the cherry-pick default with the split-apply context:

```
recover <subject from original commit> (split from partial branch <slug>)

This commit is part of a split apply: branch <slug> contained <X> commits;
<Y> were already on canonical/rationalization-branch (per `git cherry -v`),
this is one of <Z> remaining novel commits applied in dependency order.

Original SHA: <original-sha>
Position in split: <kept-index>/<kept-total>
Dropped (already on canonical): <list of dropped SHAs with subjects>
Source: refs/branch-rationalization-backup/<slug>
```

### 7. Append to `<workspace>/partial_split_log.tsv`

Columns: `branch_slug`, `original_sha`, `new_sha`, `kept_or_dropped`, `position_in_split`, `gates_status`, `notes`.

### 8. On conflict — escalate, never force

Same discipline as keeper-applier (h). Surface to user with full context including the dependency-hypothesis from step 2. Manual Edit-tool resolution only. Write to `<workspace>/conflicts/partial_<slug>.context.md`.

## Critical rules

- **No ad-hoc script edits on diffs or commits.** Per AGENTS.md "No Script-Based Changes".
- **Cherry-pick the subset in original-commit order.** Reordering breaks dependencies.
- **Apply-check via dry-run first.** `--no-commit` then inspect; only finalize on clean.
- **Document kept-vs-dropped explicitly** in the commit message and the log.
- **Never use `git apply --include=<path>`** for hunk filtering — it's path-level.
- **Never use `git stash`, `git checkout -- <path>`, or `git reset --hard`** to back out of a bad cherry-pick. Use `git cherry-pick --abort` (the structured operation).
- **Never bypass pre-commit hooks.**
- **Never use sed/awk on source files.**
- **Never disturb concurrent agents' working-tree state.**
- **Never delete files without express user permission.**
- **Never run mass-delete primitives.**
- **Never delete the source branch in this phase.** Phase 10 owns that.

## Coordination

- File reservation: `paths=["**"]` (whole repo), `exclusive=true`, `reason="branch-rationalization-phase8b"`.
- Sequence: Phase 8b runs only AFTER Phase 8 main loop completes (so re-fingerprint baseline is the post-keeper rationalization-branch tip, not pre-keeper).

## Quality gates

- [ ] Every `partially-novel` row in `triage.tsv` has at least one entry in `partial_split_log.tsv` (kept, dropped, or `partial-skipped` with user direction)
- [ ] Every kept commit has a corresponding new commit on the rationalization branch
- [ ] Every kept-commit message names original SHA and split position
- [ ] No `partially-novel` row remains without resolution
- [ ] No `--no-verify` bypasses

## Exit criteria

`partial_split_log.tsv` complete; quality gates green on rationalization branch tip; Phase 9 (fresh-eyes) may now run.
