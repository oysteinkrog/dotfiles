# Conflict Resolution Template

Used by Phase 6 keeper-applier when `git apply --3way --check` fails. The agent surfaces this to the user; the user decides how to resolve.

---

```markdown
# Conflict on stash@{N}: {STASH_MESSAGE}

## Apply-check failure

`git apply --3way --check <bundle>/diffs/{NPAD}.diff` exited non-zero.

Output:
\```
{git apply error output}
\```

## Hypothesis

{One paragraph explaining the most likely cause: refactor, rename, file move,
or context drift due to time passed since the stash was made.}

## The stash's intent (forensic reconstruction)

Per the FORENSIC reading of the diff:
- Functions introduced: {fn names}
- Tests introduced: {test names}
- Apparent goal: {summary in plain English}

## Current state on the recovery branch

The affected file `{path}` currently looks like:

\```
{first 30 lines of the affected file in current state}
\```

The stash's hunk (from <bundle>/diffs/{NPAD}.diff) is:

\```
{the failing hunk}
\```

## Proposed manual resolution

To preserve the stash's intent in main's current structure, the resolution
would be:

\```
{proposed Edit-tool changes}
\```

This:
- Preserves: {what aspect of intent}
- Adapts: {what surface change}
- Tests: {which tests will pass after}

## Options

1. **Apply this resolution.** Reply "yes" — I'll Edit the files as proposed,
   run gates, and commit with a message that documents the manual port.

2. **Skip this stash.** Reply "skip" — I'll mark `conflict-skipped` in
   apply_log.tsv and continue to the next keeper. The stash's content is
   still in the bundle for later recovery.

3. **Different resolution.** Reply with your preferred approach (e.g.,
   "drop the function altogether, just keep the test"). I'll apply your
   approach.

4. **Surface to a human reviewer.** Reply "needs-human" — I'll mark the row
   for manual review and continue.

The bundle and backup ref for this stash are intact regardless of choice.
```

---

## When to use this template

- Apply-check fails on a row that triage classified `novel-and-accretive`
- Working-tree drift causes context mismatch
- Refactor on main changed structural form (`if/else if` → `match`, etc.)
- File rename or move on main vs. stash's path

---

## What this template avoids

- **Auto-resolving silently.** The skill never decides without user input.
- **Forcing the apply.** `git apply --reject` would create `.rej` files; the skill doesn't.
- **Bypassing 3-way merge.** A regular `git apply` (without `--3way`) might silently apply wrong content; the skill always uses `--3way`.

---

## After user direction

Whatever the user chooses, the conflict context goes into
`<workspace>/conflicts/stash_{NPAD}.context.md` (this template + user's
response). It survives compaction and informs future runs.
