# Conflict Resolution Template

Used by Phase 8 keeper-applier when a cherry-pick / squash-merge / rebase-and-merge dry-run fails. The agent surfaces this to the user; the user decides how to resolve. NEVER `--reject` (creates `.rej` files); NEVER force the apply; NEVER sed/awk the resolution.

---

```markdown
# Conflict on {BRANCH_NAME}: {BRANCH_SUBJECT}

## Apply-strategy

Per `triage.tsv`, the chosen strategy was: **{STRATEGY}** (cherry-pick / squash-merge / rebase-and-merge / harmonized-synthesis-via-Edit / split-commits / dirty-state-diffs)

## Failure

`{COMMAND} --no-commit` exited non-zero or produced conflict markers.

Output:
\```
{git error output}
\```

## Hypothesis

{One paragraph explaining the most likely cause: refactor on canonical, file
rename, file move, structural form change (e.g., `if/else if` → `match`), or
context drift due to time passed since the branch was made.}

## The branch's intent (forensic reconstruction)

Per the FORENSIC reading of the branch's diff vs. its merge-base:
- Functions/methods introduced: {fn names}
- Tests/fixtures introduced: {test names + fixture paths}
- Files modified: {file count}
- Apparent goal: {summary in plain English}

## Current state on the rationalization branch

The affected file `{path}` currently looks like:

\```{lang}
{first 30 lines of the affected file in current state}
\```

The branch's hunk (from <bundle>/branches/{SLUG}/diff-vs-merge-base.diff) is:

\```diff
{the failing hunk}
\```

## Cross-check: harmonization plan

{If this file is in harmonization_plan.md, link to the relevant variant matrix and
note: "the proposed synthesis already accounts for this branch — recommend dropping
this conflict and applying the synthesis instead." Otherwise, note: "this file is
not in the harmonization plan; the conflict is between the rationalization branch's
current state and this branch alone."}

## Proposed manual resolution

To preserve the branch's intent in the rationalization branch's current structure,
the resolution would be:

\```diff
{proposed Edit-tool changes}
\```

This:
- Preserves: {what aspect of intent}
- Adapts: {what surface change}
- Tests: {which tests will pass after}

## Options

1. **Apply this resolution.** Reply "yes" — I'll Edit the files as proposed,
   run gates, and commit with a message that documents the manual port.

2. **Skip this branch.** Reply "skip" — I'll mark `conflict-skipped` in
   apply_log.tsv and continue. The branch's content is still in the bundle
   (and the backup ref) for later recovery.

3. **Different resolution.** Reply with your preferred approach (e.g., "drop
   the function altogether, just keep the test"). I'll apply your approach
   via Edit (no sed/awk).

4. **Switch to harmonization synthesis.** Reply "harmonize" — I'll fold this
   branch's content into the harmonization-plan synthesis for this file
   (Phase 7 will be re-invoked for the affected file only).

5. **Surface to a human reviewer.** Reply "needs-human" — I'll mark the row
   for manual review and continue.

The bundle and backup ref for this branch are intact regardless of choice.
```

---

## When to use this template

- Cherry-pick produces conflict markers
- `git merge --squash` reports unmerged paths
- Rebase fails mid-rebase (the `git rebase` operation is aborted; conflict context surfaces here)
- Dirty-worktree-only diff fails to apply on the rationalization branch
- Working-tree drift on the rationalization branch causes context mismatch
- Refactor on canonical (since the branch was made) changed structural form
- File rename or move on canonical vs. branch's path

---

## What this template avoids

- **Auto-resolving silently.** The skill never decides without user input.
- **Forcing the apply.** `git cherry-pick --strategy=ours` would silently drop the branch's content; the skill doesn't.
- **`git apply --reject`.** Creates `.rej` files; the skill doesn't.
- **Bypassing 3-way merge.** A regular `git apply` (without `--3way`) might silently apply wrong content; the skill always uses `--3way` for direct diff applications.
- **sed/awk the resolution.** Per AGENTS.md "No Script-Based Changes"; only the Edit tool.
- **Pre-commit hook bypass (`--no-verify`).** Hooks exist for a reason; surface the failure if a hook objects.

---

## After user direction

Whatever the user chooses, the conflict context goes into
`<workspace>/conflicts/branch_{SLUG}.context.md` (this template + user's
response). It survives compaction and informs future runs of this same
conflict (resumability).
