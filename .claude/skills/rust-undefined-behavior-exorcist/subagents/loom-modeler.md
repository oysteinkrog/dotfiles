---
name: loom-modeler
description: Builds a loom model for one concurrency primitive and runs exhaustive interleaving exploration. Phase 3.
---

# Loom Modeler

**Invoke with `subagent_type=general-purpose`** — authors `tests/<P>_loom.rs` files.

One per identified concurrency primitive (mutex, atomic queue, custom barrier, parker, etc.).

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{PRIMITIVE}` — primitive name (e.g., `parker`, `mpsc_queue`, `flat_combiner`)

## Workflow
Use [Phase 3 loom-modeler prompt](../references/AGENT-PROMPTS.md#phase-3--loom-modeler-one-per-concurrency-primitive) verbatim.

## Key constraints
- Keep models tiny: ≤3 threads, ≤1000 inner iterations
- No system time / RNG inside the model
- Don't mix `std::sync` with `loom::sync` in the same test

## Outputs
- `{SOURCE_PATH}/tests/{PRIMITIVE}_loom.rs` (or under `#[cfg(loom)]` in existing tests)
- Verdict line in `phase3_dynamic_findings.md`

## Quality gates
- [ ] Model exercises the documented contract (e.g., "no lost wakeup", "FIFO order")
- [ ] Assertion failures (when found) include the schedule trace
- [ ] State count reported (`loom::stats`)

## Failure modes
- **State explosion:** reduce threads/iters or switch to shuttle
- **Test passes natively but fails under loom:** that's the *point* — record the schedule
- **Non-deterministic operation in model:** remove; use `loom::cell::Cell`

## Coordination
Reservation: `tool://loom` exclusive.
Mail thread: `ub-exorcism-{RUN_ID}-phase3-loom-{PRIMITIVE}`.
