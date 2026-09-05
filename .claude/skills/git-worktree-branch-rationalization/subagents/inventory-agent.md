---
name: inventory-agent
description: Phase 2 — two-pass inventory. Worktree-inventory parses `git worktree list --porcelain`; branch-inventory parses `git for-each-ref refs/heads` with ahead/behind, `git cherry -v`, upstream tracking, touched files, commits-not-on-canonical. Writes worktrees.tsv + branches.tsv + inventory_grouped.md.
---

# Inventory Agent

Owns Phase 2. Pure observation — no destructive actions, no modifications to repo state. Captures the **two snapshot points** the rest of the run treats as authoritative: every linked worktree and every local branch.

Why two roles, one subagent: Axiom 0 says "two units of management, one safety story." A single agent runs both passes back-to-back so the inventories are consistent with each other; they are written separately so destructive phases can target one namespace at a time.

## Inputs

- `{PROJECT}` — absolute path to repo
- `{WORKSPACE}` — workspace dir
- `{CANONICAL}` — canonical branch from `project_profile.json`

## Outputs

- `<workspace>/worktrees.tsv` — one row per linked worktree with the columns described under Role A (path, head_sha, branch, detached, bare, locked, prunable, last_sha, last_date, dirty, staged_size, unstaged_size, untracked_size, untracked_count, age_days, inside_main_repo, active, submodules_initialized).
- `<workspace>/branches.tsv` — one row per local branch with the columns described under Role B (name, slug, head_sha, last_date, author, subject, ahead, behind, commits_ahead, cherry_plus, cherry_minus, upstream, upstream_status, worktree_path, touched_files, insertions, deletions, files_changed, age_days, prefix_family).
- `<workspace>/inventory_grouped.md` — worktrees grouped by is_main / locked / prunable / dirty / clean; branches grouped by name-prefix family sorted by family size desc.
- **Side effects:** pure observation; no `git checkout`, `git branch`, `git stash`, or commits. May augment `project_profile.json:branch_name_conventions` when prefix families appear in inventory but not in profile.
- **Decision contract:** reconciliation halts the run if `worktrees.tsv` row count != `git worktree list --porcelain` blocks, OR `branches.tsv` row count != `git for-each-ref refs/heads` count, OR a `worktrees.tsv:branch` doesn't appear in `branches.tsv:name`. Halt → re-run Phase 2 (likely concurrent-agent torn snapshot).

## Workflow

Run `scripts/discover-branches-worktrees.sh {PROJECT}` end-to-end, then verify each pass.

### Role A — worktree-inventory (★ INVENTORY for worktrees)

Parse `git worktree list --porcelain` (NEVER the human-readable format — Axiom: locked-flag detection is only reliable via `--porcelain`). Per worktree capture into `worktrees.tsv`:

| Column | Source |
|--------|--------|
| `path` | `worktree <path>` line |
| `head_sha` | `HEAD <sha>` line (full SHA, never abbreviated) |
| `branch` | `branch refs/heads/<name>` line; empty string when detached |
| `detached` | `true` if the worktree is in detached-HEAD state (no `branch` line in porcelain) |
| `bare` | `true` if the worktree is the bare-repo entry from `worktree list --porcelain` |
| `locked` | `true` if a `locked` line appears in the porcelain block (parse the optional reason from text after `locked `) |
| `prunable` | `true` if a `prunable` line appears (the working directory is gone but admin metadata remains) |
| `last_sha` | tip SHA of the worktree's HEAD (full) |
| `last_date` | committer date of HEAD, ISO-8601 |
| `dirty` | `true` if `git -C <path> status --porcelain` is non-empty |
| `staged_size` | byte count of `git -C <path> diff --cached --binary` |
| `unstaged_size` | byte count of `git -C <path> diff --binary` |
| `untracked_size` | total byte size of untracked files (`git ls-files --others --exclude-standard`) |
| `untracked_count` | count of untracked files |
| `age_days` | now − `last_date`, in days |
| `inside_main_repo` | `true` if `path` is inside the main repo's working tree (sub-checkout) |
| `active` | `true` if the user's CWD is inside this worktree (auto-protected from removal per Axiom 11) |
| `submodules_initialized` | summary of `git -C <path> submodule status --recursive` (per Failure-Modes note on per-worktree submodule state) |

The bare/prunable rows are recorded but skipped from later inventory operations on disk (their working-tree content is already gone). They still appear in `index.tsv` so Phase 10 can run `git worktree prune` ONCE at the end to clear admin metadata (per Axiom 9 — `prune` is residual cleanup, never a substitute for explicit removal).

Skip the `prunable` worktrees from later inventory operations on disk (their disk content is already gone) but still record them so Phase 10 can run `git worktree prune` once at the end to clear admin metadata.

### Role B — branch-inventory (★ INVENTORY for branches)

Parse `git for-each-ref --format='%(refname:short)|%(objectname)|%(upstream:short)|%(upstream:track)|%(authordate:iso8601)|%(committerdate:iso8601)' refs/heads`. Per branch capture into `branches.tsv`:

| Column | Source |
|--------|--------|
| `name` | `%(refname:short)` from `for-each-ref` |
| `slug` | sanitized refname for backup-ref filenames; produced by `slugify_branch` in `project-root.sh` (replaces `/` with `_`, strips unsafe chars, appends a `-<sha1[0:12]>` suffix to disambiguate names that collapse to the same slug — e.g., `feature/a` vs `feature_a` would otherwise collide) |
| `head_sha` | `%(objectname)` (full SHA) |
| `last_date` | `%(committerdate:iso8601)` |
| `author` | `%(authorname)` |
| `subject` | `%(subject)` |
| `ahead` | count from `git rev-list --count <CANONICAL>..<branch>` |
| `behind` | count from `git rev-list --count <branch>..<CANONICAL>` |
| `commits_ahead` | alias for `ahead` (kept for downstream consumers; equals the row count of `commits.tsv` in the bundle) |
| `cherry_plus` | count of `+` lines in `git cherry -v <CANONICAL> <branch>` — commits whose patch-id is NOT on canonical (truly novel content) |
| `cherry_minus` | count of `-` lines — commits whose patch-id IS on canonical even if SHAs differ (the squash-merged / rebase-landed detector; Axiom 17) |
| `upstream` | `%(upstream:short)` or empty |
| `upstream_status` | `%(upstream:track)` parsed: `gone`, `ahead`, `behind`, `ahead-behind`, or empty (`[gone]` means the tracking ref was deleted but the local commits are still real — never auto-prune purely on this signal) |
| `worktree_path` | path of the worktree where this branch is checked out (if any), else empty — cross-link to `worktrees.tsv:branch` |
| `touched_files` | `git diff --name-only <merge-base>...<branch>` joined with `,` (truncated to first 50 paths) |
| `insertions` | `git diff --shortstat <merge-base>...<branch>` insertions count |
| `deletions` | `git diff --shortstat <merge-base>...<branch>` deletions count |
| `files_changed` | `git diff --shortstat <merge-base>...<branch>` files-changed count |
| `age_days` | now − `last_date`, in days |
| `prefix_family` | classification from `scripts/prefix-classifier.sh` (e.g., `release`, `hotfix`, `dependabot`, `agent-attempt`, `wip-take`, `feature`, `unknown`) |

`git cherry -v` is the load-bearing column for Phase 5 already-merged detection. A row where every cherry line is `-` means content is on canonical even when SHAs differ — Axiom 17.

### Role C — grouping

Write `inventory_grouped.md` with sections:

- Worktrees grouped by `is_main` / locked / prunable / dirty / clean
- Branches grouped by name-prefix family (`feat/*`, `fix/*`, `agent/*`, `wip/*`, plus the long tail of unprefixed) — sorted by family size desc

Cross-check prefix families against `project_profile.json:branch_name_conventions`. If a prefix family appears in inventory but not in the profile, augment the profile.

### Reconciliation

- Verify `worktrees.tsv` row count matches `git worktree list --porcelain | grep -c ^worktree`.
- Verify `branches.tsv` row count matches `git for-each-ref refs/heads | wc -l`.
- If either disagrees, halt — a concurrent agent may have changed state mid-snapshot. Re-run.
- Cross-link: every `branch` value in `worktrees.tsv` must appear as a `name` row in `branches.tsv` (a worktree pinned to a branch). If not, halt — likely a torn snapshot.

## Coordination

- File reservation: `paths=[".worktree_branch_rationalization_workspace/worktrees.tsv", ".worktree_branch_rationalization_workspace/branches.tsv", ".worktree_branch_rationalization_workspace/inventory_grouped.md"]`, `exclusive=true`, `reason="branch-rationalization-phase2"`.
- Thread id: `branch-rationalization-<run-id>`.

## Quality gates

- [ ] `worktrees.tsv` row count == `git worktree list --porcelain` worktree blocks
- [ ] `branches.tsv` row count == `git for-each-ref refs/heads` count
- [ ] Every worktrees.tsv row has a non-empty `path` and `head_sha`
- [ ] Every branches.tsv row has a non-empty `name`, `slug`, `head_sha`, `ahead`, `behind`, `cherry_plus`, `cherry_minus`
- [ ] Cross-link consistency: every `worktrees.tsv:branch` (where not detached) appears as a `branches.tsv:name`
- [ ] `inventory_grouped.md` covers every branch and every worktree (sums match totals)

## Critical rules

- **Pure observation only.** No `git checkout`, no `git branch`, no `git stash`, no commits.
- **Never bypass pre-commit hooks** (no commits in this phase, but stated for completeness).
- **Never use sed/awk on source files.**
- **Never disturb concurrent agents' working-tree state.** Per AGENTS.md — running `git status` inside another worktree is read-only and safe; running anything that mutates is forbidden.
- **Never delete files without express user permission.**
- **Never run mass-delete primitives.**
- **Always parse `--porcelain`.** Never the human-readable `git worktree list` format (Failure Modes: locked-flag detection).

## Exit criteria

Both TSVs + grouped markdown written; counts verified; cross-links verified; main agent posts "found W worktrees and B branches across F families" summary to user.
