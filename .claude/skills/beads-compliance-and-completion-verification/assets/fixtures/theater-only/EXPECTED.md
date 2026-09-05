# EXPECTED — fixture `theater-only`

A project with one closed bead whose "implementation" is a `todo!()` macro
and whose only test is `assert!(true)`. The closer wrote a confident close
reason ("Implemented and tested.") that doesn't match reality.

The audit MUST flag this bead as false-closed.

## Assertions

- total_beads: 1
- closed_count: 1
- false_closed_count: 1

## Notes

- Two of the canonical theater patterns are present:
  - `todo!()` in production path → caught by `theater-detector` (BLOCKING)
  - `assert!(true)` test theater → caught by `theater-detector` (BLOCKING)
- A future enhancement could add `score_max_for: <id> <= 250` to assert the
  score lands in the Theater band (0–249), which would catch a regression
  where the rubric softened enough to score this above the Severe-False-Closed
  range.

## Why this fixture exists

This is the canary fixture. If `false_closed_count` ever drops to 0 here,
the audit has stopped catching the most egregious form of false-closed.
That's the moment to roll back whatever change just landed.
