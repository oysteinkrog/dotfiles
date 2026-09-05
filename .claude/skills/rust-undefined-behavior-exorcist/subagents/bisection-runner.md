---
name: bisection-runner
description: Drives `git bisect run` against a reproducer to find the commit that introduced a CONFIRMED_UB finding. Phase 8 helper.
---

# Bisection Runner

**Invoke with `subagent_type=general-purpose`** — runs `git bisect` (mutates the repo's bisect state), writes a bisection log, and amends the experiment block.

Locates the commit that introduced a CONFIRMED_UB finding via automated `git bisect`. See [BISECTION.md](../references/BISECTION.md) for the methodology.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{EXP_ID}` — experiment that reproduces the UB
- `{GOOD_REF}` — a git ref known to NOT have the UB (older tag / commit)
- `{BAD_REF}` — defaults to HEAD; ref that DOES have the UB

## Workflow
1. Verify the EXP-NNN reproducer exists in `{WORKSPACE}/experiments/{EXP_ID}/repro.rs`
2. Author `scripts/bisect-ub.sh` if not present (template in BISECTION.md)
3. `cd {SOURCE_PATH}` ; `git bisect start` ; `git bisect bad {BAD_REF}` ; `git bisect good {GOOD_REF}`
4. `git bisect run scripts/bisect-ub.sh "$(pwd)" {EXP_ID}`
5. When bisect terminates, capture the offending commit
6. Read the commit message; note if the introducing change was intentional
7. Append to `{WORKSPACE}/phase5_experiment_results/{EXP_ID}-bisection.log`:
   - Introducing commit hash
   - Commit message
   - File:line of the relevant change
   - Whether backporting applies (per BACKPORTING.md decision matrix)

## Outputs
- `phase5_experiment_results/{EXP_ID}-bisection.log`
- Inline update to `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md`: add `**Introduced in:** <commit-hash> (<date>)` to the EXP-NNN block

## Quality gates
- [ ] Bisect completed (didn't get stuck on skips)
- [ ] Introducing commit has a date older than the audit's run date
- [ ] If the bisection landed on a merge, follow up with `--first-parent` rerun
- [ ] If introducing commit is in a released version, flag for backport candidacy

## Failure modes
- **Bisect runs out of commits with all skips:** the reproducer is flaky; loop with 5-run majority voting
- **Bisect lands on a "fixup" commit that doesn't itself introduce UB:** read commit message; trace to the squashed-into commit
- **Bisect crosses an MSRV bump:** record the rustup pin in the log

## Coordination
Reservation: `path://{SOURCE_PATH}` shared-read while bisecting (no writes).
Mail thread: `ub-exorcism-{RUN_ID}-bisect-{EXP_ID}`.

## References
- [BISECTION.md](../references/BISECTION.md) — full methodology
- [BACKPORTING.md](../references/BACKPORTING.md) — what to do with the introducing commit
