# Handoff Report Template

Used by `handoff-report.sh` and the handoff-reporter subagent for Phase 10. See the script for the auto-generated version.

---

```markdown
# Stash Janitor — Handoff Report

**Project:** {PROJECT_PATH}
**Run date:** {RUN_DATE}
**Run id:** {RUN_ID}
**Mode:** {MODE} ({TIER} tier)
**Recovery branch:** {RECOVERY_BRANCH}
**Bundle path:** {BUNDLE_PATH}
**Beads issue:** {BEADS_ID} (or "skipped" if beads unavailable)

## Counts

- **Initial stashes:** {INITIAL_COUNT}
- **Triaged:**
  - novel-and-accretive: {N_NOVEL} (applied)
  - partially-novel: {N_PARTIAL} (split-applied)
  - superseded: {N_SUPER} (dropped)
  - superseded-by-newer-stash: {N_SUPER_NEWER} (dropped)
  - garbage: {N_GARBAGE} (dropped)
  - novel-but-stale: {N_STALE} (dropped per user, with note)
  - unknown: {N_UNKNOWN} (resolved to specific verdicts in Phase 5)
- **Applied (Phase 6):** {APPLIED_COUNT}
- **Split-applied (Phase 7):** {PARTIAL_COUNT}
- **Conflict-skipped:** {CONFLICT_SKIPPED}
- **Dropped (Phase 9):** {DROPPED_COUNT}
- **Final stash list:** {FINAL_STASH_COUNT}

## Recovered commits

| sha | from stash | message | gates | duration |
|-----|------------|---------|-------|----------|
| {full_sha} | stash@{N} | {message subject} | passed | {sec}s |
| ... | ... | ... | ... | ... |

## Conflict resolutions (if any)

| stash | type | context |
|-------|------|---------|
| stash@{N} | refactor (if/else if → match) | <workspace>/conflicts/stash_{NPAD}.context.md |
| ... | ... | ... |

## Triangulation summary (Comprehensive mode only)

- Phase 4 borderline rows triangulated: {N_TRIANGULATED}
- Unanimous: {N_UNANIMOUS}
- Majority-only: {N_MAJORITY}
- Disagreement (surfaced): {N_DISAGREEMENT}

## Phase 8 fresh-eyes summary

- Rounds run: {ROUNDS}
- Findings per round: round 1 = {F1}, round 2 = {F2}, ...
- Termination: {2-consecutive-trivial-rounds | early-termination | escalated}

## Recovery recipes (verbatim)

If you regret any drop, every stash is recoverable:

\```bash
# By backup ref (preferred):
git cherry-pick -m 1 refs/stash-backup/NNN     # NNN = zero-padded stash index (stash backup refs are merge commits)

# By bundle diff (when ref already pruned):
git apply --3way "{BUNDLE_PATH}/diffs/NNN.diff"
# If index.tsv says has_untracked=true, also copy stashed-untracked/NNN/.

# Or for a specific stash example:
git cherry-pick -m 1 refs/stash-backup/{EXAMPLE_NPAD}

# The bundle's full index (one row per stash):
cat "{BUNDLE_PATH}/index.tsv"
\```

## Push instructions

The skill never pushes. To land the recovered work:

\```bash
git push origin "{RECOVERY_BRANCH}"
# Then open a PR against {PRIMARY_BRANCH} for review
\```

If branch protection requires reviews, request from {SUGGESTED_REVIEWERS_FROM_CODEOWNERS}.

## Bundle lifecycle

The bundle at `{BUNDLE_PATH}` is yours to manage. Recommended:

- Keep for at least one release cycle (1–4 weeks)
- Once you're sure nothing was missed, `mv` it to a trash location:
  \```bash
  mv "{BUNDLE_PATH}" "$HOME/Trash/{BASENAME}-stash-archive-{DATE}"
  \```
  (DCG would block `rm -rf`; `mv` works.)

## Backup refs in this repo

\```bash
$(git for-each-ref refs/stash-backup/ --format='%(refname:short) %(objectname:short)' | head -10)
$(if [[ $(git for-each-ref refs/stash-backup/ | wc -l) -gt 10 ]]; then echo "... (and $(git for-each-ref refs/stash-backup/ | wc -l) total)"; fi)
\```

## Polish Bar verification

\```
{output of polish-bar-check.sh}
\```

## Newly unblocked beads (if bv available)

\```
{output of bv --robot-triage with newly-unblocked items}
\```

## Skill feedback (if Phase 11 ran)

See `<workspace>/skill_feedback.md` for the run's user-experience review.
That file is for skill maintainers; you don't need to act on it.

## Done

The skill has finished its work. Push the recovery branch when ready.
```

---

## Required content per mode

- Quick: counts, recovered commits, recovery recipes, push instructions
- Standard: + conflict resolutions, fresh-eyes summary, polish bar
- Comprehensive: + triangulation summary, bv triage, skill feedback

## What MUST be present

| Element | Why |
|---------|-----|
| Counts | User can verify the run's scope |
| Recovered commit SHAs | User can audit what landed |
| Recovery recipes (verbatim) | User can undo any drop |
| Bundle path | User knows where the safety net is |
| Push command (NOT executed) | User owns the push decision |
| polish-bar-check.sh result | Audit trail of self-verification |
