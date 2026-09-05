---
name: cleanup-conductor
description: Phase 10 — gated combined worktree + branch cleanup. Worktree-first ordering. Verbatim authorization restated before each operation. Worktrees → `git worktree prune` (residual metadata only) → branches by bucket. Protected branches NEVER deleted. No mass-delete primitives. Remote cleanup out-of-scope by default.
---

# Cleanup Conductor

Owns Phase 10. The skill's only destructive phase. Heavily gated. Per AGENTS.md "Mandatory explicit plan" and Axiom 14 (verbatim authorization).

Why combined: Axiom 9 — a worktree pinned to a branch protects that branch from `git branch -d`. The worktree-first ordering is structural, not stylistic.

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path
- `{TRIAGE}` — `<workspace>/triage.tsv`
- `{APPLY_LOG}` — `<workspace>/apply_log.tsv`

## Outputs

- `<workspace>/cleanup_plan.tsv` — combined plan with columns `phase|target|bucket|verdict|reason|is_force`; worktrees first, then branches by bucket (garbage → superseded → already-merged → novel-stale → divergent-refactor → applied-keepers).
- `<workspace>/cleanup_authorization.txt` — verbatim user authorization text + UTC timestamp; written before any destructive command runs.
- `<workspace>/cleanup_log.tsv` — one row per executed action: `phase|kind|target|verdict|command_run|backup_ref|timestamp_utc|notes`.
- `<workspace>/remote_cleanup_suggestions.sh` — only when `--prepare-remote-list` was set; lists `git push --delete origin <branch>` commands prefixed with `# DO NOT RUN AS-IS`.
- **Side effects:** runs `git worktree remove`, `git worktree prune` (residual metadata only, exactly once), and `git branch -d` / `-D`. NEVER touches `refs/branch-rationalization-backup/*`, the bundle, the canonical branch, the active worktree, protected branches, branches in `ci_unresolved.tsv`, or any remote.
- **Decision contract:** Pre-conditions and verbatim authorization are HARD GATES — failure to meet any results in a refusal-to-start with no destructive ops run. After completion, `audit-conductor` runs `post-phase-10` and decides PROCEED-TO-PHASE-11 or HALT.

## Pre-conditions (HARD GATES)

- [ ] Phase 9 termination rule met (≥2 clean fresh-eyes rounds, gates green)
- [ ] `<workspace>/cleanup_authorization.txt` does NOT yet exist
- [ ] `triage.tsv` and `apply_log.tsv` are present and complete
- [ ] Every applied keeper-commit is on the rationalization branch (verified via `git log --oneline {RATIONALIZATION_BRANCH}` includes every `new_commit_sha` from `apply_log.tsv`)
- [ ] Every backup ref `refs/branch-rationalization-backup/<slug>` exists for every branch to be deleted (no missing backups)
- [ ] Bundle exists and `git bundle verify <bundle>/object-bundle.pack` exits 0

If any pre-condition fails, refuse to start.

## Workflow

### 1. Build combined cleanup plan — worktrees first, branches second

Materialize as `<workspace>/cleanup_plan.tsv` with columns `phase` (`worktree-remove` | `worktree-prune-residual` | `branch-delete-d` | `branch-delete-D`), `target` (path or branch name), `bucket`, `verdict`, `reason`, `is_force` (bool).

#### a. Worktree removals — order

1. `/tmp/*` worktrees (lowest stickiness; user least likely to be using them)
2. Conventional `<basename>-wt-*` worktrees
3. User-flagged-removable worktrees from triage (the long tail)
4. (NEVER) the active worktree (the user's CWD; auto-protected per Axiom 11)
5. (NEVER) worktrees flagged `protected-preserve` in triage

For each removal entry:
- `git worktree remove <path>` — refuses if dirty (built-in safety check); the dirty state was archived in Phase 3, so `--force` is allowed only if the user explicitly OK'd losing it (per-worktree, restated verbatim).
- Never `rm -rf <worktree-path>` (Axiom 11; DCG would block it anyway).

#### b. `git worktree prune` — admin-metadata cleanup

ONLY after every explicit `git worktree remove` has run. This is residual `.git/worktrees/<id>/` metadata for entries already structurally removed. NEVER as a substitute for explicit removal (Axiom 9).

#### c. Branch deletions — bucket order

After all worktrees are gone (so no branch is "checked out elsewhere" anymore):

1. `garbage` — empty diffs / formatting churn (use `-d`; falls back to `-D` only with explicit user OK on the verbatim plan)
2. `superseded` — content already on canonical via fingerprint match (use `-d`; the branch is fully merged from rationalization-branch's perspective)
3. `already-merged` — `git cherry -v` showed all `-` (use `-d`; same reasoning)
4. `novel-but-stale` (opt-in only — user must individually flag each) — use `-d` if merged into rationalization branch; `-D` only with explicit acknowledgment that content was *not* recovered
5. `divergent-refactor` (opt-in only) — same discipline; usually only flagged after the variant was harmonized in Phase 7 + 8
6. `applied-keepers` — branches whose content landed on the rationalization branch via cherry-pick / squash-merge / rebase-and-merge / harmonized-synthesis. Use `-d` (the branch IS fully merged from the rationalization branch's perspective per Axiom 8).

#### d. NEVER deleted

- Canonical branch (auto-protected)
- Currently-checked-out branch (auto-protected; would be refused by git anyway, but the skill enforces independently)
- Any branch matching `protected_patterns` from `project_profile.json`
- Any branch the user explicitly flagged in Phase 4

### 2. Build verbatim authorization request

```
I'm about to run the following destructive commands in this order:

# Phase A — worktree removals (safe-bucket first):
  git worktree remove /tmp/myrepo-wt-1     # /tmp bucket: <reason>
  git worktree remove /tmp/myrepo-wt-2     # /tmp bucket: <reason>
  ...
  git worktree remove ../myrepo-wt-feat-x  # conventional: <reason>
  ...
  git worktree prune                       # cleans residual .git/worktrees/<id>/ metadata

# Phase B — branch deletions (bucket-ordered):
  git branch -d garbage/empty-diff-1       # garbage: <message>
  ...
  git branch -d feat/already-merged-1      # already-merged: <message>
  ...
  git branch -d feat/applied-keeper-1      # applied-keeper: landed in <SHA>
  ...

NOT removed/deleted:
  - active worktree (your CWD): <path>
  - protected branches: <list>
  - canonical branch: <name>
  - branches matching protected_patterns: <count>

Backup refs at refs/branch-rationalization-backup/* (B refs) and the bundle at
<BUNDLE> stay intact. Remote refs are untouched (out of scope by default).

To proceed, paste this verbatim:
  yes I understand and want to remove <Wn> worktrees and delete <Bn> branches per the plan above
```

### 3. Wait for verbatim authorization

If the user types something different ("yes", "ok", "go ahead"), refuse and re-ask. If the user objects to the verbatim requirement, explain it's per AGENTS.md "Mandatory explicit plan".

### 4. Record authorization

```bash
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > <workspace>/cleanup_authorization.txt
echo "<user's exact authorization text>" >> <workspace>/cleanup_authorization.txt
```

### 5. Execute removals & deletions

Use `scripts/drop-retire-confirmed.sh` per entry. Per Axiom 10, the only acceptable batching is iterating the plan one entry at a time, restating the verbatim command before each:

```bash
for row in cleanup_plan.tsv:
  case row.phase:
    worktree-remove:
      if [[ "$is_force" == "true" ]]; then
        # Only when the user explicitly OK'd force for this exact worktree and the bundle preflight passes.
        WORKTREE_FORCE_OK=1 ./scripts/drop-retire-confirmed.sh "{PROJECT}" worktree "<path>" "confirm=YES_REMOVE_WT_<basename>"
      else
        ./scripts/drop-retire-confirmed.sh "{PROJECT}" worktree "<path>" "confirm=YES_REMOVE_WT_<basename>"
      fi
    worktree-prune-residual:
      git -C "{PROJECT}" worktree prune
      printf 'A\tworktree\t(prune)\tresidual-metadata\tgit -C %q worktree prune\t-\t%s\tpruned-residual-admin-metadata\n' "{PROJECT}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "{WORKSPACE}/cleanup_log.tsv"
    branch-delete-d:
      ./scripts/drop-retire-confirmed.sh "{PROJECT}" branch "<name>" "confirm=YES_DELETE_BR_<slug>"
    branch-delete-D:
      BRANCH_FORCE_OK=1 ./scripts/drop-retire-confirmed.sh "{PROJECT}" branch "<name>" "confirm=YES_DELETE_BR_<slug>"
```

`scripts/drop-retire-confirmed.sh` has only two operation forms: `worktree` and `branch`, both scoped by `{PROJECT}`. Force is gated by `WORKTREE_FORCE_OK=1` or `BRANCH_FORCE_OK=1`; there is no separate force confirmation token. The script restates the verbatim worktree/branch command before executing and records to `cleanup_log.tsv` (`phase`, `kind`, `target`, `verdict`, `command_run`, `backup_ref`, `timestamp_utc`, `notes`). The conductor runs `git worktree prune` itself exactly once, only after the authorized explicit removals, and logs that residual-metadata step separately.

### 6. Post-cleanup verification

- `git worktree list --porcelain | grep -c ^worktree` matches `expected_remaining_worktrees`.
- `git for-each-ref refs/heads | wc -l` matches `expected_remaining_branches` (canonical + protected + rationalization branch).
- Every backup ref `refs/branch-rationalization-backup/<slug>` still resolves.
- `git bundle verify <bundle>/object-bundle.pack` still exits 0.
- `cleanup_log.tsv` has one row per planned action.

### 7. Remote cleanup — OUT OF SCOPE by default

The skill never runs `git push --delete`, `git push --force`, or any remote-mutating command (Axiom 15). If the user opted into `--prepare-remote-list`, emit `<workspace>/remote_cleanup_suggestions.sh` containing the list of `git push --delete origin <branch>` commands the user runs themselves; mark it `# DO NOT RUN AS-IS — review then execute one-by-one`.

## Critical rules

- **NEVER run `git branch | xargs git branch -D`** or any other mass-delete primitive (Axiom 10).
- **NEVER use `rm -rf <worktree-path>`** (Axiom 11). DCG would block it; the skill is designed not to need it.
- **NEVER run `git worktree prune` as a substitute for `git worktree remove`** (Axiom 9).
- **NEVER run `git push --delete`, `git push --force`, or any remote-mutating command** (Axiom 15).
- **NEVER delete the bundle.** User manages bundle lifecycle (Axiom 18).
- **NEVER delete `refs/branch-rationalization-backup/*`.** They survive branch deletion only because they're separate refs.
- **Worktree-first; branches second.** Within branches: garbage → superseded → already-merged → novel-stale → divergent-refactor (opt-in) → applied-keepers.
- **Prefer `-d` over `-D`** for merged branches (Axiom 8). Use `-D` only with explicit user acknowledgment per-branch.
- **Active worktree (user's CWD) is NEVER removed by the skill.** Handoff report tells the user how to remove it themselves from a different working directory.
- **Protected items NEVER deleted.** Canonical, currently-checked-out, anything matching `protected_patterns`, anything user-flagged in Phase 4.
- **If a removal/deletion fails** (e.g., a worktree was already gone because a concurrent agent removed it), HALT and rebuild the cleanup plan from current state before continuing. Do not continue on a stale plan.
- **If state shifts unexpectedly** (a worktree path or branch ref doesn't match what was authorized), HALT and ask the user.
- **Never bypass pre-commit hooks** (no commits in this phase, but stated for completeness).
- **Never use sed/awk on source files.**
- **Never disturb concurrent agents' working-tree state.** If a worktree is dirty mid-cleanup with content that wasn't there at Phase 3, that's concurrent-agent activity — surface to user, do not force-remove.
- **Never delete files without express user permission.** Worktree directories are deleted by `git worktree remove` only after the user typed the verbatim authorization that named them.
- **Never run mass-delete primitives.**

## Coordination

- File reservation: `paths=[".git/refs/heads/**", ".git/worktrees/**", "<workspace>/cleanup_*"]`, `exclusive=true`, `reason="branch-rationalization-phase10"`.
- Thread id: `branch-rationalization-<run-id>`.

## Quality gates

- [ ] `cleanup_authorization.txt` exists with verbatim user text
- [ ] `cleanup_plan.tsv` has worktrees-first then branches-by-bucket order
- [ ] Every removed worktree has a corresponding row in `cleanup_log.tsv`
- [ ] Every deleted branch has a corresponding row in `cleanup_log.tsv`
- [ ] All `refs/branch-rationalization-backup/*` refs still exist
- [ ] Bundle directory still exists and `git bundle verify` exits 0
- [ ] No protected branch was deleted
- [ ] No active worktree was removed
- [ ] If `--prepare-remote-list` was set: `remote_cleanup_suggestions.sh` exists with `# DO NOT RUN AS-IS` header

## Exit criteria

Final state: `git worktree list` and `git branch` reflect the planned set; every backup ref intact; bundle intact; main agent proceeds to Phase 11.
