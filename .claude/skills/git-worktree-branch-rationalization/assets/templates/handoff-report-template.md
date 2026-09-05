# Handoff Report Template

Used by `handoff-report.sh` and the handoff-reporter subagent for Phase 11. See the script for the auto-generated version.

---

```markdown
# Worktree + Branch Rationalization — Handoff Report

**Project:** {PROJECT_PATH}
**Run date:** {RUN_DATE}
**Run id:** {RUN_ID}
**Mode:** {MODE} ({TIER} tier)
**Canonical branch:** {CANONICAL_BRANCH}
**Rationalization branch:** {RATIONALIZATION_BRANCH} (tip: {RB_TIP_SHA})
**Bundle path:** {BUNDLE_PATH}
**Beads issue:** {BEADS_ID} (or "skipped" if beads unavailable)

## Counts

- **Initial branches:** {B_INITIAL}
- **Initial worktrees:** {W_INITIAL}
- **Triaged:**
  - protected-preserve: {N_PROTECTED} (untouched)
  - novel-and-accretive: {N_NOVEL} (applied)
  - partially-novel: {N_PARTIAL} (split-applied)
  - dirty-worktree-only: {N_DIRTY_WT} (applied via captured diffs)
  - already-merged: {N_MERGED} (deleted)
  - superseded: {N_SUPER} (deleted)
  - superseded-by-newer-branch: {N_SUPER_NEWER} (deleted)
  - garbage: {N_GARBAGE} (deleted)
  - novel-but-stale: {N_STALE} (deleted per user, with note)
  - divergent-refactor: {N_DIVERGENT} (skipped or deleted per user opt-in)
  - unknown: {N_UNKNOWN} (resolved to specific verdicts in Phase 6)
- **Worktrees removed (Phase 10):** {WT_REMOVED}
- **Branches deleted (Phase 10):** {BR_DELETED}
- **Disk freed:** {DISK_FREED} ({DISK_FREED_HUMAN})
- **Final branch list:** {B_FINAL} (= canonical + protected + rationalization + any unprocessed)
- **Final worktree list:** {W_FINAL} (= main + protected + active)

## Recovered commits on {RATIONALIZATION_BRANCH}

| sha | strategy | sources | message subject | gates | duration |
|-----|----------|---------|-----------------|-------|----------|
| {sha} | cherry-pick | {branch} | {subject} | passed | {sec}s |
| {sha} | squash-merge | {branch} | {subject} | passed | {sec}s |
| {sha} | rebase-and-merge | {branch} | {subject} | passed | {sec}s |
| {sha} | harmonized-synthesis | {branch_A}, {branch_B}, {wt_path} | {subject} | passed | {sec}s |
| {sha} | split-commits | {branch} | {subject} | passed | {sec}s |
| {sha} | dirty-worktree-only | {wt_path} | {subject} | passed | {sec}s |

## Harmonization summary

{N_COLLIDING_FILES} files were touched by ≥2 non-protected branches and entered
the Phase 7 variant matrix. Of these:

- {N_HARMONIZED} were synthesized on the rationalization branch (best-of-all-worlds)
- {N_FILE_OVERRIDE_PICK} had a user-override "pick <branch> for <file>"
- {N_FILE_OVERRIDE_DROP} had a user-override "drop <file>"

| file | sources | synthesis commit |
|------|---------|------------------|
| {path} | {N} sources: {branch_A}, {branch_B}, ... | {sha} |
| ... | ... | ... |

For full per-file variant matrices and synthesis rationale, see
`<workspace>/harmonization_plan.md`.

## Conflict resolutions (if any)

| branch | type | context |
|--------|------|---------|
| {branch} | refactor (`if/else if` → `match`) | <workspace>/conflicts/branch_{slug}.context.md |
| ... | ... | ... |

## Triangulation summary (Comprehensive / Council mode only)

- Phase 5 borderline rows triangulated: {N_TRIANGULATED}
- Phase 7 borderline syntheses triangulated: {N_TRIANGULATED_HARMONY}
- Unanimous: {N_UNANIMOUS}
- Majority-only: {N_MAJORITY}
- Disagreement (surfaced): {N_DISAGREEMENT}

## Phase 9 fresh-eyes summary

- Rounds run: {ROUNDS}
- Findings per round: round 1 = {F1}, round 2 = {F2}, ...
- Termination: {2-consecutive-trivial-rounds | early-termination | escalated}

## Worktrees removed

| path | branch | dirty? | size_freed | bundle_artifacts |
|------|--------|--------|------------|------------------|
| {path} | {branch} | yes | {bytes} | <bundle>/worktrees/{sanitized}/ |
| ... | ... | ... | ... | ... |

The currently-active worktree (`{ACTIVE_WT}`) was NOT removed by the skill.
If you want to remove it: from a different working directory, run
`git -C "{PROJECT_PATH}" worktree remove "{ACTIVE_WT}"` after pushing the rationalization branch.

## Branches deleted

| name | verdict | last commit | backup ref |
|------|---------|-------------|------------|
| {name} | {verdict} | {sha} | refs/branch-rationalization-backup/{slug} |
| ... | ... | ... | ... |

## Branches preserved

| name | reason |
|------|--------|
| {CANONICAL_BRANCH} | canonical (auto-protected) |
| {ACTIVE_BRANCH} | currently checked out (auto-protected) |
| {RATIONALIZATION_BRANCH} | the rationalization staging branch |
| release/2.x | release line (auto-protected by convention) |
| dependabot/cargo-tokio-1.40 | dependabot (auto-protected) |
| ... | ... |

## Recovery recipes (verbatim)

If you regret any deletion or removal, every entry is recoverable:

\```bash
# Restore a deleted branch by backup ref (preferred):
git branch <name> refs/branch-rationalization-backup/<slug>

# If the backup ref was also lost, restore from the object bundle:
git fetch "{BUNDLE_PATH}/object-bundle.pack" \
  refs/branch-rationalization-backup/<slug>:refs/heads/<name>

# As a last resort, apply the per-branch diff in a dedicated recovery worktree:
git worktree add "<recovery-path>" {RATIONALIZATION_BRANCH}
git -C "<recovery-path>" apply --3way --check "{BUNDLE_PATH}/branches/<slug>/diff-vs-merge-base.diff"
git -C "<recovery-path>" apply --3way "{BUNDLE_PATH}/branches/<slug>/diff-vs-merge-base.diff"
# Or via format-patch series:
git -C "<recovery-path>" am "{BUNDLE_PATH}/branches/<slug>/format-patch/"*.patch

# Restore a removed worktree:
git worktree add "<path>" <branch>
git -C "<path>" apply --3way --cached "{BUNDLE_PATH}/worktrees/<sanitized>/staged.diff"
git -C "<path>" apply --3way "{BUNDLE_PATH}/worktrees/<sanitized>/unstaged.diff"
tar --null -xzf "{BUNDLE_PATH}/worktrees/<sanitized>/untracked.tar.gz" \
  -C "<path>" \
  -T "{BUNDLE_PATH}/worktrees/<sanitized>/.untracked.list"

# The bundle's full index (one row per branch + per worktree):
cat "{BUNDLE_PATH}/index.tsv"
\```

## Push instructions

The skill never pushes. To land the recovered work:

\```bash
git push origin "{RATIONALIZATION_BRANCH}"
# Then open a PR against {CANONICAL_BRANCH} for review
\```

If branch protection requires reviews, request from {SUGGESTED_REVIEWERS_FROM_CODEOWNERS}.

If you want to remove the active worktree (`{ACTIVE_WT}`):

\```bash
# From a different working directory (NOT inside the active worktree):
cd /tmp   # or anywhere outside {ACTIVE_WT}
git -C "{PROJECT_PATH}" worktree remove "{ACTIVE_WT}"
\```

## Remote cleanup (out of scope by default)

If you opted in to `--prepare-remote-list`, the suggested commands are at:

\```
{WORKSPACE}/remote_cleanup_commands.txt
\```

Review them before running. The skill does NOT run them. To execute manually:

\```bash
# Per branch you want to delete remotely:
git push --delete origin <branch_name>
\```

Remote cleanup is irreversible without remote reflog access.

## Bundle lifecycle

The bundle at `{BUNDLE_PATH}` is yours to manage. Recommended:

- Keep for at least one release cycle (1–4 weeks)
- Once you're sure nothing was missed, `mv` it to a trash location:
  \```bash
  mv "{BUNDLE_PATH}" "$HOME/Trash/{BASENAME}-branch-worktree-archive-{DATE}"
  \```
  (DCG would block `rm -rf`; `mv` works.)

## Backup refs in this repo

\```bash
$(git for-each-ref refs/branch-rationalization-backup/ --format='%(refname:short) %(objectname:short)' | head -10)
$(if [[ $(git for-each-ref refs/branch-rationalization-backup/ | wc -l) -gt 10 ]]; then echo "... (and $(git for-each-ref refs/branch-rationalization-backup/ | wc -l) total)"; fi)
\```

## Polish Bar verification

\```
{output of polish-bar-check.sh}
\```

## Newly unblocked beads (if bv available)

\```
{output of bv --robot-triage with newly-unblocked items}
\```

## Skill feedback (if Phase 12 ran)

See `<workspace>/skill_feedback.md` for the run's user-experience review.
That file is for skill maintainers; you don't need to act on it.

## Done

The skill has finished its work. Push the rationalization branch when ready.
```

---

## Required content per mode

- Quick: counts, recovered commits, recovery recipes, push instructions
- Standard: + conflict resolutions, fresh-eyes summary, harmonization summary, polish bar
- Comprehensive: + triangulation summary, bv triage, skill feedback
- Council: + multi-model agreement details on triage AND harmonization

## What MUST be present

| Element | Why |
|---------|-----|
| Counts (per verdict + per cleanup action) | User can verify the run's scope |
| Recovered commit SHAs | User can audit what landed |
| Harmonization summary | User can audit the conceptual centerpiece |
| Worktrees removed table | User can verify nothing protected was touched |
| Branches preserved table | User can verify nothing protected was deleted |
| Recovery recipes (verbatim) | User can undo any removal/deletion |
| Bundle path | User knows where the safety net is |
| Push command (NOT executed) | User owns the push decision |
| Active-worktree removal instructions (separate) | User completes the cleanup the skill can't do |
| polish-bar-check.sh result | Audit trail of self-verification |

## What MUST NOT appear

- A `git push` command actually executed (the skill never pushes)
- A `git push --delete` command actually executed (the skill never runs remote-mutating commands)
- Any `Co-Authored-By` line in any cited commit message (unless the user explicitly asked)
- Any reference to `--no-verify` (the skill never bypasses pre-commit hooks)
