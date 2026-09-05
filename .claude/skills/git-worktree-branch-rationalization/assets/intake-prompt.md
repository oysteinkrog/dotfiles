# Intake Prompt — Up-Front Confirmations Template

Use this template verbatim when invoking the skill. Replace `{...}` with detected values.

---

I'm about to run the git-worktree-branch-rationalization skill on `{PROJECT_PATH}`.

**Counts up front:**
- Local branches: `{B}` (`git branch | wc -l`, excluding canonical)
- Linked worktrees: `{W}` (`git worktree list | wc -l`, excluding the main repo entry)
- Canonical branch detected: `{CANONICAL_BRANCH}` (per `git symbolic-ref refs/remotes/origin/HEAD` — NOT assumed `main`)

> Note: many users genuinely don't realize how many branches/worktrees they have
> until they look. >100 branches or >20 worktrees is rare enough to surprise
> people; the count is reported here so you know the magnitude before committing
> time.

Before I start, a few confirmations:

1. **Target path:** `{PROJECT_PATH}` — confirm this is the repo you want rationalized.
   (If you provided a git URL, I'll clone it to `/tmp/<basename>` and operate
   on the clone.)

2. **Mode:** auto-detected as **{MODE}** based on counts (B=`{B}`, W=`{W}`):
   - Quick (W<5 AND B<30): single-agent, ~15–30 min, harmonization plan only when ≥2 branches collide
   - Standard (5≤W<20 OR 30≤B<100): 2–4 parallel triage workers, ~30–90 min, harmonization plan triggered on first collision
   - Comprehensive (W≥20 OR B≥100, OR dirty worktrees, OR monorepos, OR many file conflicts): 5+ workers, dedicated harmonization-planner subagent, ~2–6 h
   - Council (B≥300 OR production-critical OR security-sensitive): 12+ workers, multi-model triangulation on triage AND harmonization

   You can override.

3. **Output mode:** default `full` — triage + harmonize + apply keepers + gated cleanup.
   Alternatives:
   - `triage-only`: stop after Phase 6 (decision table) and Phase 7 (harmonization plan); no commits, no removals, no deletions
   - `apply-only`: skip Phase 10 cleanup; leave worktrees and branches intact

4. **Initial protection list.** I auto-protect the canonical branch (`{CANONICAL_BRANCH}`),
   the currently-checked-out branch (`{ACTIVE_BRANCH}`), and anything matching
   `release/*`, `hotfix/*`, `dependabot/*`, `renovate/*`, `gh-pages`, plus
   anything with branch-protection rules I detected in `.github/branch-protection.yml`
   or `.github/CODEOWNERS`.

   Detected auto-protected items: `{AUTO_PROTECTED_LIST}`

   Anything you want to add or remove from the protection list before inventory?
   (You'll get a second chance at Phase 4 with the full inventory in front of you.)

5. **Rationalization branch:** keepers (and harmonized syntheses) will land on
   `branch-rationalization-{YYYY-MM-DD}` cut from `{CANONICAL_BRANCH}`'s tip.
   Confirm OK or specify a different name.

   I will NOT land directly on `{CANONICAL_BRANCH}` unless you explicitly request
   `--land-on-canonical` AND type a separate verbatim authorization for that override.

6. **Remote cleanup scope:** default `out-of-scope`. The skill never runs
   `git push --delete`, `git push --force`, or any remote-mutating command.

   If you want me to prepare a list of `git push --delete origin <branch>` commands
   for branches we delete locally — for you to review and run yourself — pass
   `--prepare-remote-list`. Default is no.

7. **Bundle path:** the recovery bundle (backup refs + git object bundle +
   per-branch diffs/format-patch + per-worktree dirty captures + meta + index +
   README) will be created at `{BUNDLE_PATH}`. This is where every branch and
   every worktree's dirty state is captured before any destructive action runs.
   Confirm OK.

8. **Resuming a prior run?** I see `.worktree_branch_rationalization_workspace/`
   already exists. (Only shown when relevant.) Options:
   - Resume: continue from saved state
   - Fresh: archive old workspace, start over
   - Abort

9. **Concurrent agents in this repo or its worktrees right now?** If yes, I'll
   register an advisory file reservation on `.git/worktrees/**` and
   `.git/refs/heads/**` so a parallel run would notice. Working-tree changes
   from other agents are normal — per AGENTS.md "Note for Codex/GPT-5.5", I'll
   treat them as if I made them and not disturb.

10. **Quality gates auto-detected:**
    - Test: `{TEST_COMMAND}`
    - Typecheck: `{TYPECHECK_COMMAND}`
    - Lint: `{LINT_COMMAND}`
    - Format: `{FORMAT_COMMAND}`
    - UBS available: `{UBS_AVAILABLE}`
    - Merge style preferred: `{MERGE_STYLE}` (squash / rebase-and-merge / merge —
      informs Phase 8 strategy choice)

    These will run on every Phase 8 keeper apply (per-apply, not just at end).
    Confirm or correct.

Reply with "go" (or specify any overrides) and I'll start with Phase 1
(project reconnaissance: read AGENTS.md, README.md, run codebase archaeology,
detect protected-by-convention patterns).
