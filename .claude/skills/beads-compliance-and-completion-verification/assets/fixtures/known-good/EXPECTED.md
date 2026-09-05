# EXPECTED — fixture `known-good`

A small project with one closed bead whose implementation, tests, and close
reason all match the spec.

## What this fixture catches

This fixture's value is in detecting **changes to the wrapper's behavior**:
if `run-pass.sh` ever silently stops emitting a REPORT.md, fails to parse br
output, or produces a malformed summary, the count assertions below will
catch it.

## Assertions

- total_beads: 1
- closed_count: 1

## Why we don't assert `false_closed_count: 0` here

The `run-pass.sh` wrapper STUBS Phase 4 — it doesn't actually run the
project's tests because real test re-execution requires the
`compliance-verifier` subagent (Phase 4 has resource-coordination needs the
wrapper can't safely handle). With Phase 4 stubbed, every closed bead's
test-passes evidence is empty, so the scorer docks the test dimension and
the bead lands below threshold.

In other words: under the wrapper alone, EVERY closed bead is "false-closed"
because the wrapper can't verify the test claim. To get a true `0`
false-closed result on this fixture, you must drive Phases 1–10 via
subagents (with the `compliance-verifier` actually running `cargo test`).

A future enhancement to this fixture would add a `--with-real-phase4` mode
to `regression-test.sh` that orchestrates subagents instead of using the
wrapper, at which point we can re-introduce `false_closed_count: 0` here.

## Why this fixture still exists despite the limitation

It exercises the full wrapper pipeline (br stats, br list, git xref, spec
extraction, evidence gathering, theater scan, scoring, master-report
generation) on a minimum-realistic project. Most regressions in those
deterministic phases will manifest as failures here (e.g. bead-id parsing
breaks → `total_beads` assertion fails).
