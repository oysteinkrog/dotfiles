# When NOT to Use This Skill

This skill is overkill for some situations and inappropriate for others. Recognize them before invoking.

The skill's overhead — recovery bundle, fan-out triage, harmonization plan — pays off at scale (≥5 worktrees OR ≥30 non-protected branches). Below that, a few minutes of `git branch -vv` + `git worktree list` is faster than running the skill.

> Why this matters: per [SKILL.md "Decision Tree"](../SKILL.md#decision-tree--should-the-skill-run), the pre-conditions are explicit and the soft-warnings are non-blocking but visible. Refusing a run that shouldn't happen is a feature, not a limitation.

---

## NTU-1: Fewer Than 2 Worktrees AND Fewer Than 5 Non-Protected Branches

**Symptom:**

```bash
git worktree list | wc -l    # 1 (just the main checkout) → W=0 linked worktrees
git branch | wc -l           # ≤6 (canonical + ≤5 non-protected)
```

**Why not:** the recovery-bundle infrastructure overhead doesn't pay off. A user with 1 worktree and 4 branches can `git branch -vv` and inspect them in 30 seconds.

**Better approach:**

```bash
git branch -vv               # human-readable, shows tracking + ahead/behind
git worktree list            # all worktrees with their HEADs
git log --all --oneline -20  # recent activity across branches
# For per-branch detail:
git log canonical..<branch> --oneline
```

The skill can still be invoked on small repos, but Phase 0 warns:

> You have 1 linked worktree and 4 non-protected branches. The skill's
> overhead (recovery bundle, fan-out triage, harmonization plan) is calibrated
> for >2 worktrees AND/OR >30 branches. For your scale, manual inspection
> via `git branch -vv` + `git worktree list` is usually faster. Run anyway?
> (Default: no)

---

## NTU-2: Worktrees-as-Parallel-Review Workflow

**Symptom:** the user's team has a deliberate convention of one worktree per open PR for parallel review. Multiple worktrees, all of them legitimate, all on `feature/<ticket>` branches matching open PRs.

**Why not:** the workflow assumes worktrees accumulate from neglect. If the user's workflow is to *intentionally* keep one worktree per active review, triaging them out is destructive.

**Detection heuristic:** ≥3 worktrees, all matching `<basename>-wt-<feature/*>` or similar deliberate pattern, AND all branches have open PRs (detectable via `gh pr list --state=open`), AND the user mentions "review" or "parallel work" in conversational context.

**Better approach:** ask first.

> Your worktree pattern looks like deliberate parallel-review infrastructure:
> 7 worktrees, each on a feature branch with an open PR. Are you using
> worktrees as a per-PR review pattern? If so, this skill will look like
> cleanup but might erase your active workflow. Confirm you want to proceed.

---

## NTU-3: CI Checkout

**Symptom:** the working directory is `/__w/<repo>/...` (GitHub Actions), `/cloudbuild/...` (Google Cloud Build), `/builds/<id>/...` (GitLab Runner), or similar CI paths AND has many local branches or worktrees.

**Why not:** a CI host should have minimal local state. If it has many local branches or worktrees, the residue is evidence of:

- A misconfigured cleanup step (the CI didn't reset between runs)
- A bug in a custom CI script
- Infrastructure drift (a daemon caching state across runs)
- A leftover from a debug-on-CI session

The right move is to investigate the cause, not triage the symptom.

**Detection heuristic:** working dir matches a CI path pattern AND no human user is logged in (no controlling tty, no `$USER` set to a human-looking value).

**Better approach:** refuse and surface:

> You appear to be on a CI host (path matches /__w/...). CI hosts should
> have minimal local state. If you have many branches/worktrees here, the
> residue is a symptom of something else wrong — a misconfigured cleanup,
> a debug-on-CI leftover, or infrastructure drift. The skill won't run;
> investigate the root cause first.

---

## NTU-4: Mid-Rebase / Mid-Merge / Mid-Cherry-Pick on the Active Worktree

**Symptom:** `git status` in the active worktree shows:

- `interactive rebase in progress`
- `unmerged paths`
- `cherry-pick in progress`
- `revert in progress`
- `bisect in progress`

Or any of these state files exists in the active worktree's `.git/`:

```
MERGE_HEAD, REBASE_HEAD, CHERRY_PICK_HEAD, REVERT_HEAD, BISECT_LOG
```

**Why not:** the skill needs a clean checkout state on the active worktree to base the rationalization branch from. Mid-operation states have ambiguous semantics and risk corrupting the in-progress operation.

**Important:** mid-operation in a *linked* worktree is NOT a refusal condition for the skill — only the active worktree must be clean. A linked worktree mid-rebase is treated as dirty per [WORKTREE-STATE.md](WORKTREE-STATE.md) and gets its dirty state captured in the bundle but is NOT removed during Phase 10.

**Better approach:** finish the operation first.

```bash
# Resume the rebase:
git rebase --continue
# Or abort:
git rebase --abort

# Then run the skill.
```

Phase 0 detects this and refuses to start.

---

## NTU-5: Detached HEAD on the Active Worktree With No Canonical to Base From

**Symptom:** active worktree `git status` shows `HEAD detached at <sha>`, no obvious canonical branch to land the rationalization branch from.

**Why not:** the skill needs canonical (`main` / `master` / `develop` / etc.) as a base for `branch-rationalization-<DATE>`. Detached HEAD has no implicit target.

**Better approach:** check out canonical first:

```bash
git checkout main   # or whatever the detected canonical is
# Then run the skill.
```

Phase 0 detects this and asks the user to fix it before proceeding.

---

## NTU-6: Bare Repository

**Symptom:** the project is a bare repo (no working tree).

```bash
git rev-parse --is-bare-repository   # returns "true"
```

**Why not:** `git worktree` and dirty-state captures are not meaningful for bare repos — there's no working tree to capture, no `git status` to snapshot, no concept of "active worktree." The skill's invariants depend on a non-bare repo.

**Better approach:** clone the bare repo into a working directory; run the skill against the clone (and remember that branch deletions in the clone don't propagate back to the bare repo until pushed).

Phase 0 detects this via `git rev-parse --is-bare-repository` and refuses.

---

## NTU-7: User's CWD Is `/`, `/tmp`, `~`, or Another Non-Project Directory

**Symptom:** the user invokes the skill from a directory that isn't a git work tree, OR is at the filesystem root, OR is a generic scratch directory like `/tmp` or `~`.

**Why not:** the skill operates on a single project. It's almost never correct to run it from a non-project directory. Most likely the user meant to `cd` into a project first and forgot.

**Better approach:** refuse with a friendly message.

> Your current directory is /tmp (not a git work tree). The skill operates
> on one project at a time. Did you mean to cd into a project first?
>
> If you meant to triage worktrees ACROSS multiple projects, the skill
> doesn't do that — it's designed to focus on one project's branch + worktree
> ecosystem at a time. Run it from each project's root directory separately.

Phase 0 detects this via `git rev-parse --show-toplevel` (which fails outside a git work tree) and refuses with the message above.

---

## NTU-8: Repos With Submodules Where the User Hasn't Confirmed Submodule Semantics

**Symptom:** `git submodule status` returns non-empty AND the user hasn't acknowledged understanding the worktree+submodule interaction.

**Why not:** submodule init state is per-worktree (per [WORKTREE-STATE.md](WORKTREE-STATE.md)); removing a worktree leaves the parent's submodule cache untouched but the worktree's inner submodule clones disappear with the worktree. This is rarely catastrophic but can confuse downstream workflows that expected the submodule to be cloned somewhere.

**Better approach:** warn-and-proceed (NOT refusal).

> This repo has 3 submodules (per `git submodule status`). Worktree+submodule
> interaction has subtleties:
>
> - `git worktree add` does NOT auto-init submodules in new worktrees.
> - Each worktree has its own submodule init state.
> - `git worktree remove` cleans the worktree's directory (including any
>   submodule clones inside it), but the parent repo's submodule cache
>   stays intact.
>
> The bundle's `worktrees/<slug>/meta.txt` records each worktree's submodule
> state. Confirm you understand and want to proceed.

If the user confirms, the run proceeds; the bundle's per-worktree meta.txt records `submodules_init=yes|no|partial(M/N)`.

---

## NTU-9: Very Old Git (<2.20)

**Symptom:**

```bash
git --version    # outputs e.g., "git version 2.18.1"
```

**Why not:** `git worktree` semantics changed significantly across git versions:

- Pre-2.5: no `git worktree` command at all
- 2.5–2.10: experimental, missing `worktree list --porcelain`
- 2.10–2.17: `worktree lock`/`unlock` added
- 2.20+: stable semantics, `worktree list --porcelain` reliable, `worktree remove` available
- 2.30+: `worktree repair` available

The skill's invariants assume git 2.20+ behavior:

- `git worktree list --porcelain` produces the documented machine-readable format
- `git worktree remove <path>` is the structured operation (refuses on dirty by default; `--force` available)
- `git worktree prune` cleans residual admin metadata
- `git bundle create --all` and `git bundle list-heads` work as documented

**Better approach:** refuse and ask the user to upgrade git.

> git version 2.18.1 detected. The skill requires git 2.20+ — `git worktree`
> semantics changed substantively across older versions, and the safety
> guarantees rely on the 2.20+ behavior. Please upgrade git first.

---

## NTU-10: Repository With No Commits Yet

**Symptom:**

```bash
git log
# fatal: your current branch '<x>' does not have any commits yet
```

**Why not:** branches without commits are nominal — there's nothing to rationalize. Same for worktrees on a no-commits canonical (couldn't even cut the rationalization branch).

**Better approach:** the skill refuses with a clear message; the user creates an initial commit first if they actually want to set up the rationalization workflow.

---

## NTU-11: Read-Only Filesystem

**Symptom:** writing to `<project>/.git/` fails with `EROFS` or similar.

**Why not:** the skill needs to write `refs/branch-rationalization-backup/*` and `.worktree_branch_rationalization_workspace/`.

**Better approach:** copy the repo to a writable filesystem first, or remount read-write.

---

## NTU-12: Goal Is Secret-Purging, Not Rationalization

**Symptom:** the user says "I have branches that contain accidentally-committed API keys; help me NUKE them."

**Why not:** this skill creates a *recovery bundle* that contains every branch's content. If the goal is to PURGE secrets, the bundle works against the goal — it's a permanent archive of exactly the content the user wants to destroy.

**Better approach:** for secret-purging, use:

- `git filter-repo` (modern; recommended)
- BFG Repo Cleaner (older but still functional)

Then drop the branches. Then rotate the credentials. Then run *this* skill if you also want to rationalize the surviving branches.

The skill explicitly does not support secret-purging. If the user mentions this goal, redirect them.

---

## NTU-13: User Just Wants to Understand WHAT'S in the Branches/Worktrees

**Symptom:** the user asks "what's in all these agent-* branches?" or "are any of my worktrees worth keeping?" but doesn't want destructive cleanup.

**Better approach:** run only Phases 0–6 (`output_mode=triage-only` per [SKILL.md "Inputs"](../SKILL.md#inputs)) — produce the recovery bundle, the triage TSV, and the user-facing decision table; stop before Phase 7 harmonization.

This is a valid skill invocation in `triage-only` mode — but Phases 7+ should not run, and no destructive actions should be authorized. The user gets a complete picture without commitment.

---

## NTU-14: Repository Where the User Was Explicitly Told NOT to Operate

**Symptom:** CLAUDE.md, AGENTS.md, or conversational context explicitly says "do not run rationalization on this repo."

**Why not:** authorization is a hard rule.

**Better approach:** refuse to proceed. Ask for explicit fresh authorization if the user changes their mind.

---

## Soft-Warnings (Proceed but Flag)

These conditions don't trigger refusal — the skill proceeds in a degraded but acceptable mode. Each is surfaced once at Phase 0 so the user knows what to expect.

### SW-1: Non-Empty Working Tree in Any Worktree

**Symptom:** any worktree's `git status --porcelain` is non-empty at Phase 0.

**Why proceed:** per AGENTS.md "Note for Codex/GPT-5.5", concurrent agents in any worktree are normal — that's the asupersync workflow model. Refusing on the basis of working-tree drift would prevent the skill from ever running on a real multi-agent project.

**What to flag:** report each worktree's pre-existing dirty state at Phase 0. The skill won't disturb concurrent work; per [WORKTREE-STATE.md](WORKTREE-STATE.md), captures are made for posterity but no auto-removal of dirty worktrees happens without explicit user OK on a per-worktree basis.

### SW-2: No Remote Configured

**Symptom:** `git remote -v` returns empty.

**Why proceed:** the skill works without a remote, but several features degrade:

- Canonical detection — no `origin/HEAD` to query; falls back to `git config init.defaultBranch` and heuristics
- Push instructions in the handoff — nothing to push to
- `[gone]` upstream detection (B15) — irrelevant without a remote
- Remote-cleanup-list preparation — irrelevant

**What to flag:**

> No remote configured. The rationalization branch will be based on local
> canonical (<canonical-name>) only. The handoff will include local-only
> instructions (no `git push` step). Remote cleanup is N/A.

This is a degraded but acceptable mode.

### SW-3: Branches With `[gone]` Upstream Tracking

**Symptom:** `git branch -vv` shows one or more branches with `[origin/<name>: gone]`.

**Why proceed:** these branches usually have unique commits even though the remote tracking ref is gone. They need full triage like any other branch — `[gone]` is a hint, not a verdict per [BRANCH-WORKTREE-SMELLS.md B15](BRANCH-WORKTREE-SMELLS.md#smell-b15-branches-with-gone-upstream-tracking--have-unique-commits).

**What to flag:**

> N branches have [gone] upstream tracking. They will be triaged normally;
> the skill never auto-deletes a branch just because tracking is gone.

### SW-4: Locked Worktrees on Stale Paths

**Symptom:** `git worktree list --porcelain` shows `locked` entries on paths >30 days old or paths that don't exist on disk.

**Why proceed:** the locks are advisory; the underlying worktrees may be reclaimable. But never force-remove a locked worktree without explicit user OK per [BRANCH-WORKTREE-SMELLS.md W6](BRANCH-WORKTREE-SMELLS.md#smell-w6-locked-worktrees-on-stale-paths).

**What to flag:**

> N worktrees are locked. The skill will surface them in Phase 4/6 but
> will not unlock or force-remove them without explicit user authorization.

### SW-5: Submodules Present, User Confirmed Understanding

**Symptom:** `git submodule status` non-empty, user confirmed at Phase 0.

**Why proceed:** the user accepted the worktree+submodule semantics; the bundle records per-worktree submodule state.

**What to flag:** add a "submodule note" to the handoff describing per-worktree submodule init state.

### SW-6: Path Under `/tmp/...` for the Active Worktree

**Symptom:** the user's CWD is under `/tmp/...`.

**Why proceed:** the user might be operating on a deliberate scratch clone (e.g., the skill was invoked with a git URL and cloned to `/tmp/<basename>`).

**What to flag:**

> Active worktree is under /tmp/... — possibly a temporary clone. The
> recovery bundle will be placed at /tmp/<basename>-branch-worktree-archive-<DATE>/,
> which is also ephemeral. If you truly want to triage from a throwaway
> clone, this is fine, but consider whether the original repo (where the
> branches come from) is what you should be operating on.

---

## Decision Table

| Condition | Action |
|-----------|--------|
| <2 worktrees AND <5 non-protected branches | Warn; default to manual inspection |
| Worktrees-as-parallel-review-workflow | Confirm with user before proceeding |
| CI checkout with many branches/worktrees | Refuse; investigate root cause |
| Mid-merge/rebase/cherry-pick on active worktree | Refuse; finish operation first |
| Detached HEAD on active worktree | Ask user to checkout canonical first |
| Bare repo | Refuse; ask for working clone |
| CWD is `/`, `/tmp`, `~`, non-project | Refuse with friendly message |
| Submodules + user hasn't confirmed semantics | Warn-and-confirm; proceed if user OK |
| Git <2.20 | Refuse; recommend upgrade |
| No commits | Refuse |
| Read-only filesystem | Refuse |
| Goal is secret-purging | Redirect to git-filter-repo / BFG |
| Goal is "what's in there" | Run in `triage-only` mode |
| Unauthorized (CLAUDE.md / AGENTS.md says no) | Refuse |
| Non-empty working tree in any worktree | Soft-warn; proceed; never disturb |
| No remote | Soft-warn; degraded handoff |
| `[gone]` upstream branches | Soft-warn; triage normally |
| Locked worktrees on stale paths | Soft-warn; never force-remove |
| Submodules present, user confirmed | Soft-warn; record per-worktree state |
| Active worktree under `/tmp/` | Soft-warn |

---

## Cross-References

- The decision tree at the top of the skill: [SKILL.md "Decision Tree"](../SKILL.md#decision-tree--should-the-skill-run)
- Working-tree-state guidance for the soft-warning cases: [WORKTREE-STATE.md](WORKTREE-STATE.md)
- Branch + worktree smells that drive verdicts: [BRANCH-WORKTREE-SMELLS.md](BRANCH-WORKTREE-SMELLS.md)
- Bundle layout for the secret-purging redirect: [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md)
- Sibling skill's refusal matrix: [WHEN-NOT-TO-USE.md](../../git-stash-janitor/references/WHEN-NOT-TO-USE.md)
- AGENTS.md "Note for Codex/GPT-5.5" (the rationale for never disturbing concurrent work): [AGENTS.md](../../../../AGENTS.md)
