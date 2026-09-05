---
name: keeper-applier
description: Phase 8 — sequentially apply each keeper to the rationalization branch using strategy from triage row + project_profile.json's preferred merge style. Cherry-pick / squash-merge / rebase-and-merge / harmonized-synthesis / split-commits / dirty-state diffs. Per-apply quality gates. Re-fingerprint downstream after each apply. Conflicts surface to user; manual Edit-tool resolution only.
---

# Keeper Applier

Owns Phase 8. Sequential by definition (each apply changes the 3-way base for later applies and can flip downstream verdicts via `⊞ RE-FINGERPRINT`). Runs quality gates **per apply**, not at the end (Axiom 13).

Why sequential, never parallel: two parallel keeper-appliers would race the working tree, the rationalization branch's tip, and the verdict re-fingerprint pass.

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path
- `{CANONICAL}` — canonical branch
- `{RATIONALIZATION_BRANCH}` — default `branch-rationalization-<YYYY-MM-DD>`
- `{TRIAGE}` — `<workspace>/triage.tsv` (frozen at Phase 6)
- `{HARMONIZATION_PLAN}` — `<workspace>/harmonization_plan.md` (frozen at Phase 7)
- `{MERGE_STYLE}` — from `project_profile.json`

## Outputs

- `<workspace>/apply_log.tsv` — append-only log: `name|strategy|new_commit_sha|gates_status|superseded-during-apply|paths_committed|source_branches_cited|...`. Every KEEP row resolves to one of: `new_commit_sha`, `conflict-skipped`, `superseded-during-apply`, `deferred-to-partial-splitter`, `skipped`, `already-merged-during-apply`.
- `<workspace>/drift_log.tsv` — concurrent-agent working-tree drift detected by `↺ WORKING-TREE-DRIFT` per apply (never auto-resolved).
- `<workspace>/conflicts/branch_<slug>.context.md` — one file per conflict: bundle diff + current file state + harmonization plan reference + refactor hypothesis + proposed Edit-tool resolution; survives compaction.
- **Side effects:** creates `{RATIONALIZATION_BRANCH}` from `{CANONICAL}` if absent (resumable runs reuse it); commits keepers ON THIS BRANCH ONLY (never canonical, never source branches). Pre-commit hooks run normally; never `--no-verify`. Stages only the bundle-diff or harmonization-plan paths (never `git add -A` / `git add .`). Never deletes source branches in this phase (Phase 10's job). Never pushes. Sequential by definition.
- **Decision contract:** Phase 8 exit requires every KEEP row in `triage.tsv` to have a resolution in `apply_log.tsv` AND quality gates green on `{RATIONALIZATION_BRANCH}` tip. Phase 8b (`partial-splitter`) handles `split-commits` rows; Phase 9 (`fresh-eyes`) gates on Phase 8 + 8b completion.

## Workflow

### Setup once at phase start

Create the rationalization branch only if it does not already exist (resumable runs reuse it):

```bash
git -C {PROJECT} show-ref --verify --quiet refs/heads/{RATIONALIZATION_BRANCH} \
  && git -C {PROJECT} checkout {RATIONALIZATION_BRANCH} \
  || git -C {PROJECT} checkout -b {RATIONALIZATION_BRANCH} {CANONICAL}
```

Per Axiom 6: keepers land on the rationalization branch, never directly on canonical (unless `--land-on-canonical` was explicitly passed AND the user typed a separate verbatim authorization for that override).

### For each KEEP-row in `triage.tsv`, ordered chronologically by branch's last-commit date (oldest first)

Run the following sub-loop per row.

#### a. ↺ WORKING-TREE-DRIFT (operator `↺`)

Re-snapshot `git -C <each-worktree> status --porcelain` for every active worktree. Compare to `wt_phase0.txt`. If files appeared from concurrent agents, record the drift in `<workspace>/drift_log.tsv`; never stage unrelated paths; never stash, revert, or overwrite (Axiom 12, AGENTS.md "Note for Codex/GPT-5.5").

#### b. ⊞ RE-FINGERPRINT (operator `⊞`)

Re-run FINGERPRINT/VERIFY-ON-CANONICAL against the rationalization branch's HEAD (which has previous keepers applied). If fingerprint coverage flips ≥0.8 with same-signature confirmed, mark `superseded-during-apply` in `apply_log.tsv` and skip this row. Why: earlier keepers may have already landed the same content from a different branch, harmonized via the plan; downstream candidates flip verdict mid-run.

#### c. Choose strategy from triage row + `{MERGE_STYLE}`

| Triage strategy | Apply mechanic |
|-----------------|----------------|
| `cherry-pick` | `✧ CHERRY-PICK` — `git cherry-pick --no-commit <SHA>` once, then commit the staged result with source credit |
| `squash-merge` | `⊟ SQUASH-MERGE` — `git merge --squash <branch>` then commit with focused message |
| `rebase-and-merge` | `⊠ REBASE-AND-MERGE` — replay `{MERGE_BASE}..<branch>` onto `{RATIONALIZATION_BRANCH}` without mutating the source branch |
| `harmonized-synthesis` | DO NOT cherry-pick. Hand-author synthesis commit using the **Edit tool**, following `harmonization_plan.md`. The synthesis is a manual edit on top of canonical's current rationalization-branch state, citing source branches in the commit message. NEVER use `git apply` from the bundle for this case — the bundle diff is one branch's full delta, not the harmonized synthesis. |
| `split-commits` | Delegate to `partial-splitter` (Phase 8b). Skip in this loop. |
| `dirty-worktree-only` | For `dirty-worktree-only` rows: `git apply <bundle>/worktrees/<sanitized-path>/staged.diff` then commit; `git apply <bundle>/worktrees/<sanitized-path>/unstaged.diff` then commit; copy untracked via `.untracked.list` + `untracked.tar.gz` after collision check, then commit. Three separate commits, each focused. |
| `archaeology-then-rewrite` | Meta-strategy emitted by the archaeologist subagent (Phase 5) for `novel-but-stale` rows that need forensic intent reconstruction before any apply. The apply-keeper script does NOT auto-apply this strategy: the archaeologist surfaces a recommendation to the user, who either (a) accepts it — at which point the strategy is rewritten to `cherry-pick` or `harmonized-synthesis` and the keeper-applier handles it on the next pass — or (b) drops it — at which point the strategy is rewritten to `none` and the branch is deleted in Phase 10. In this loop, treat as `skip` and surface in the Phase 11 handoff. |
| `skip` | Do nothing; record `skipped` in `apply_log.tsv`. |

#### d. Strategy-specific dry-run

Always dry-run before mutate:
- `cherry-pick`: `git cherry-pick --no-commit <SHA>` then immediately `git cherry-pick --abort` if exploring; or use `git merge-tree --write-tree {RATIONALIZATION_BRANCH_TIP} <SHA>` for a no-touch preview.
- `squash-merge`: `git merge --no-commit --no-ff <branch>` followed by `git merge --abort` to preview conflicts without committing.
- `rebase-and-merge`: preview the source-intact replay with `git cherry-pick --no-commit {MERGE_BASE}..<branch>` followed by `git cherry-pick --abort`.
- `harmonized-synthesis`: do the Edit-tool authoring on a sandbox copy first if uncertain; otherwise edit in-place and verify with `git diff` before staging.
- `dirty-worktree-only`: `git apply --check <diff>` first.

#### e. Apply (only on clean dry-run)

Strategy-specific actual mutation, scoped to:
- the paths the bundle diff lists (for `cherry-pick`, `squash-merge`, `rebase-and-merge`, `dirty-worktree-only`)
- the paths the harmonization plan lists (for `harmonized-synthesis`)

Stage **only** those paths. Per AGENTS.md, do not `git add -A` or `git add .`.

#### f. ⊕ RECOVER (operator `⊕`) — per-apply quality gates

Run from `project_profile.json`:
```bash
{test_command}
{typecheck_command}
{lint_command}
ubs .   # if available
```

All must exit 0. If any fail:
- Inspect the failure. If trivial (formatter rewrite, lint auto-fix), apply the fix via Edit tool, re-stage, re-run gates.
- If non-trivial (genuine test break or typecheck error), surface to user as a conflict (see `g.` below).

Never bypass pre-commit hooks with `--no-verify`. If a hook fails, fix the underlying issue.

#### g. Commit with focused message

The commit message must explain *why* the content is being recovered, naming source branches and variant intents. Templates:

For `cherry-pick`:
```
recover <feature> from <branch-name>

<2–4 sentences explaining what this commit adds and why it's worth keeping>

Source: refs/branch-rationalization-backup/<slug>
Triage evidence: <file.rs:line citation OR cherry summary>
```

For `harmonized-synthesis`:
```
harmonize <file> from <branch-A> + <branch-B> + <branch-C>

Recover <intent-1> from <branch-A> (lines X–Y), <intent-2> from <branch-B>
(lines P–Q), and <intent-3> from <branch-C> (lines M–N), synthesized on top
of canonical's current structure per harmonization_plan.md.

Dropped: <branch-D's variant of intent-1, superseded by branch-A's stronger version>
Sources: refs/branch-rationalization-backup/<slug-A>,
         refs/branch-rationalization-backup/<slug-B>,
         refs/branch-rationalization-backup/<slug-C>
Plan: .worktree_branch_rationalization_workspace/harmonization_plan.md#<file>
```

NO `Co-Authored-By` lines unless user requests.

Append to `<workspace>/apply_log.tsv`: `name`, `strategy`, `new_commit_sha`, `gates_status`, `superseded-during-apply` flag, paths committed, source branches cited.

#### h. On conflict — escalate, never force

DO NOT force the apply. Surface to user with full context:
- The branch's change (the bundle diff)
- The current state of affected files (from canonical/rationalization-branch tip)
- The harmonization plan's synthesis if applicable
- Your refactor hypothesis (rename, file move, signature change)
- A proposed Edit-tool resolution preserving the branch's INTENT (not surface form)

Wait for explicit OK. On user OK: apply the resolution via Edit tool, run gates, commit. On user "skip": mark `conflict-skipped`. Write conflict context to `<workspace>/conflicts/branch_<slug>.context.md` so it survives compaction.

## Critical rules

- **Sequential only.** One keeper-applier in flight at a time.
- **Never use `git stash pop` or `git stash apply`.** Apply via the bundle's diff or via cherry-pick / merge / Edit-tool synthesis.
- **Never bypass pre-commit hooks** with `--no-verify`. Per AGENTS.md.
- **Never push.** The user pushes in their own time after handoff.
- **Never modify the canonical branch.** Keepers land on the rationalization branch only.
- **Never disturb concurrent agents' working-tree changes** in any worktree (Axiom 12).
- **Never use sed/awk on source files.** Synthesis happens via the Edit tool.
- **Never delete files without express user permission.**
- **Never run mass-delete primitives.**
- **Never delete a source branch in this phase.** Branch deletion is Phase 10's job. Source branches stay alive through Phases 8 and 9 so their content is reachable if a fresh-eyes finding requires re-checking the original.
- **Cherry-picking a merge commit needs `-m 1`** (or appropriate parent). Document the choice in the commit message and the bundle's recovery recipe.
- **Cherry-picking a squash-merged commit produces "nothing to commit"** — `git cherry -v` should have flagged it in Phase 5; if it shows up here, mark `already-merged-during-apply` and skip via `git cherry-pick --skip` if mid-pick.

## Coordination

- File reservation: `paths=["**"]` (whole repo), `exclusive=true`, `reason="branch-rationalization-phase8"`, `ttl_seconds=14400`.
- Thread id: `branch-rationalization-<run-id>`.

## Quality gates

- [ ] Every applied row has `gates_status=passed` in `apply_log.tsv`
- [ ] Every commit message names ≥1 source branch and explains *why* (not auto-generated boilerplate)
- [ ] Every harmonized-synthesis commit cites the harmonization_plan.md row it implements
- [ ] Every conflict has a `conflicts/branch_<slug>.context.md`
- [ ] No commits authored on canonical
- [ ] No push occurred
- [ ] No source branches deleted in this phase
- [ ] No `--no-verify` bypasses

## Exit criteria

Every KEEP row in `triage.tsv` has either `new_commit_sha`, `conflict-skipped`, `superseded-during-apply`, or `deferred-to-partial-splitter` in `apply_log.tsv`. Quality gates green on the rationalization branch tip. Phase 8b (`partial-splitter`) runs after this phase for any `split-commits` rows; Phase 9 (fresh-eyes) runs after Phase 8b.
