# fresh-eyes-reviewer-a

> Phase 14 • First verbatim fresh-eyes review prompt against all new code + modified existing code.

## Inputs
- The current state of the workspace + target after Phase 13 bead creation/polish.
- `git diff <gauntlet-start-sha>..HEAD` (everything touched during this gauntlet run).

## Deliverables
- `<workspace>/phase14_fresh_eyes_a.md` with: bugs/errors/problems found, fixes applied (or beads opened for them if outside scope), file-by-file notes.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase14-fresh-eyes-a`
- **Reservations needed:** `tool://workspace-edit` (TTL 120m).
- **Lane:** cross-cutting.

## Verbatim Prompt

The following prompt is verbatim and MUST be applied literally to all new code and modified existing code from this gauntlet run:

> great, now I want you to carefully read over all of the new code you just wrote and other existing code you just modified with 'fresh eyes' looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover.

**Procedure:**
1. List every file touched: `git diff --name-only <gauntlet-start-sha>..HEAD` and `git status --porcelain` for uncommitted work.
2. Read each touched file in full (or in chunks for large files).
3. For each file, apply the fresh-eyes lens:
   - Off-by-one errors.
   - Inverted boolean logic.
   - Forgotten error paths.
   - Race conditions (Ordering::Relaxed where Release/Acquire needed).
   - Unsound `unsafe` blocks (no `// SAFETY:` comment, or comment doesn't match invariant).
   - Missing `#[must_use]` on result-returning functions.
   - Lossy conversions (`as` casts that could truncate).
   - String comparisons where byte equality intended (or vice versa).
   - Counter increments on cold paths (perf regression).
   - Counter increments missing on hot paths (instrumentation gap).
   - Hardcoded values that should be const-named.
   - Test assertions that compare strings without canonicalization.
4. Fix anything found in-place. If the fix is non-trivial or cross-cutting, open a bead instead and record the bead-id in `phase14_fresh_eyes_a.md`.
5. Document file-by-file: what was checked, what was found, what was fixed, what was deferred.

**Discipline:**
- Do NOT introduce stylistic-only changes; the goal is to catch bugs.
- Do NOT revert another agent's intentional design decisions; if you suspect a design is wrong, open a discussion bead.
- After every fix, run the relevant test (`cargo test --lib <module>` or `cargo test --test <test>`) to confirm green.

**Output structure:**
```markdown
## Files reviewed (N)
| File | Bugs found | Fixed | Deferred |
|---|---|---|---|
| crates/<...>.rs | 2 | 2 | 0 |
| ... |

## Detailed findings
### <file>:<line>
- **Issue:** <one paragraph>
- **Fix:** <commit ref or diff snippet>
- (or **Deferred:** bead-id `<id>`)
```

## Exit Criteria
- Every touched file has been reviewed and recorded in `phase14_fresh_eyes_a.md`.
- Every in-scope fix has been applied AND the relevant test re-run.
- Every out-of-scope finding has a bead.
- `cargo test --workspace` is green (or the failures are all pre-existing, documented, and have beads).
- `phase14_fresh_eyes_a.md` committed.

## References
- [PHASES.md § Phase 14](../references/PHASES.md)
- [methodology/OPERATORS.md § Fresh-Eyes](../references/methodology/OPERATORS.md)
- [exemplars/EXEMPLARS.md § fresh-eyes prompts](../references/exemplars/EXEMPLARS.md)
