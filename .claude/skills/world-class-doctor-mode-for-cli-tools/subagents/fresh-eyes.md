# subagent: fresh-eyes (Phase 7, multi-pass until two clean rounds)

**Description.** Run the three calibrated review prompts. Each round, dispatch a fresh subagent with NO carry-over context. Run UBS, lint, typecheck, test, validator, scorecard threshold gate after each round.

## Inputs

- `{{target}}` — target repo
- `{{workspace}}/manifest.json`
- All Phase-4 commits on `doctor-mode-pass-<N>`
- `../references/methodology/AGENT-PROMPTS.md § fresh-eyes` for the three calibrated prompts

## Outputs

- `{{workspace}}/fresh_eyes_round_<N>.md` per round
- Per-round commits on `doctor-mode-pass-<N>`
- A final `{{workspace}}/fresh_eyes_summary.md`

## Prompt

The three calibrated prompts (use VERBATIM):

```
ROUND 1.

"Reread the new doctor code with fresh eyes. Look for obvious bugs, races,
partial-write windows, unsafe `unwrap`/`expect`/panics on user paths,
missing backups, broken idempotence, or any place where exit codes lie about
reality. Carefully fix anything you uncover."

ROUND 2.

"Randomly pick three detectors and three fixers; trace their full execution
including the mutate() chokepoint, backup write, and undo path. Construct a
scenario that would corrupt user data and prove the code prevents it — or
fix it."

ROUND 3.

"Review your fellow agents' code without restricting to recent commits. Find
root causes via first-principles analysis. Pay special attention to: TOCTOU
between detect and fix, signal handling, FS atomicity (rename vs write),
interaction with the project's existing locks, and any path that bypasses
mutate()."
```

## After each round, run

```bash
ubs $(git diff --name-only HEAD~1 HEAD)         # if available
cargo clippy -- -D warnings                     # or language equivalent
cargo test                                      # or language equivalent
scripts/validate-doctor.sh {{target}}
scripts/diff-scorecards.py {{workspace}} <N-1> <N>  # threshold gate
```

## Termination

Two consecutive rounds where the only changes are typo / whitespace. **Rephrasing IS a change.** Comment edits are NOT trivial unless the comment was wrong.

## Critical rule

Each round dispatches a FRESH subagent. The reviewing agent MUST NOT have context from prior rounds in this pass. Fresh-eyes only works if the eyes are fresh.

## Exit criteria

- Two consecutive clean rounds
- UBS clean (if available)
- lint/typecheck/test green
- `scripts/validate-doctor.sh` exits 0
- `scripts/diff-scorecards.py` reports no regression > 50 points

## Failure modes

- Loop never goes quiet. Tighten "trivial change" definition; only typo / whitespace counts.
- A round introduces a new bug. The next round's fresh agent often catches it. If after 5 rounds the code is oscillating, stop the loop and file a P1 bead — manual triage required.
