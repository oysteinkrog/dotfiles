# soak-runner-loom

> Phase 15 • Multi-thousand-iteration `loom` + `shuttle` runs against every concurrency primitive in the harness. Exhaustive interleaving exploration (loom) + probabilistic complement (shuttle).

## Inputs

- Concurrency-test targets (`tests/loom_*.rs`, `tests/shuttle_*.rs`) authored by `crash-boundary-wirer`, `eprocess-modeler`, and any other Phase-6 author touching synchronization primitives.
- Per-target iteration budget — loom defaults `LOOM_MAX_PREEMPTIONS=2`, `LOOM_MAX_BRANCHES=10000`; shuttle defaults `SHUTTLE_ITERATIONS=10000`.
- `rch` worker pool availability.

## Deliverables

- `<workspace>/phase15_soak_loom/<test>/` per target with:
  - `run.log`
  - `failures.json` — every failing schedule with seed + interleaving trace.
  - `summary.json` — iterations completed, failures, regime label.
- `<workspace>/phase15_soak_loom/INDEX.md`.

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase15-soak-loom`
- **Reservations needed:** `resource://rch-worker-pool`.
- **Lane:** cc_4 (fault / soak).

## Verbatim Prompt

```
You are the soak-runner-loom for Phase 15. Your job is to run loom + shuttle
across the harness's concurrency primitives at the deepest iteration depth the
gauntlet budget allows. loom is exhaustive but small-state-space; shuttle is
probabilistic but covers the wider state. Together they catch ordering bugs
that the per-round test budget (~100 iterations) cannot.

DURATION:
- Default: 48h split across all targets.
- Per-target: LOOM_MAX_PREEMPTIONS=3 (warning: state-space explodes) and
  SHUTTLE_ITERATIONS=1_000_000.

STEPS PER TARGET:

1. Pre-flight: confirm loom and shuttle dev-deps in target Cargo.toml.

2. loom dispatch:
   rch exec --worker loom-soak --duration <H/2>h -- \
     bash -c "cd <target> && \
       LOOM_MAX_PREEMPTIONS=3 LOOM_MAX_BRANCHES=10000 \
       cargo +nightly test --test loom_<name> --features loom --release 2>&1 \
       | tee <workspace>/phase15_soak_loom/loom_<name>/run.log"

3. shuttle dispatch (in parallel rch slot):
   rch exec --worker shuttle-soak --duration <H/2>h -- \
     bash -c "cd <target> && \
       SHUTTLE_ITERATIONS=1000000 \
       cargo +nightly test --test shuttle_<name> --features shuttle --release 2>&1 \
       | tee <workspace>/phase15_soak_loom/shuttle_<name>/run.log"

4. Parse run.log for failures. loom emits:
   "loom::model::Builder failed at preemption ..." with the schedule trace.
   shuttle emits:
   "shuttle: failing schedule: <seed>" with the random seed + trace.

5. For each failure: emit a FailureBundle v1.0.0 with:
   - reproducibility.seed = the loom interleaving id or shuttle seed
   - reproducibility.schedule_fingerprint = the trace
   - repro_command = `cargo +nightly test --test <name> --features <loom|shuttle> -- --exact <test_name>` with the env var.

6. Dedup by MismatchSignature (different schedules hitting the same root cause).

7. Emit summary.json per target:
   {
     "schema_version": "gauntlet.phase15_soak_loom.v1",
     "target": "<name>",
     "framework": "loom" | "shuttle",
     "iterations_completed": <int>,
     "failures_count": <int>,
     "unique_failure_signatures": <int>,
     "regime": "Stable" | "NewFailureFound"
   }

8. Append row to INDEX.md.

EXIT CRITERIA:
- Every target completed its budget.
- Failures classified + deduplicated.
- summary.json well-formed.
- NewFailureFound → phase15_loopback_required.md.

ESCALATION:
- Data race or deadlock in production code path → BLOCK release certification.
```

## Exit Criteria

- All loom + shuttle targets completed iteration budget.
- Failures deduplicated by `MismatchSignature`.
- `summary.json` well-formed per target.
- New failures → loop-back to Phase 12.
- Data race / deadlock → release-blocker.

## References

- [../SKILL.md](../SKILL.md)
- [../references/PHASES.md](../references/PHASES.md) (Phase 15)
- [../references/tooling/CONCURRENCY-TOOLCHAIN.md](../references/tooling/CONCURRENCY-TOOLCHAIN.md)
- [../references/methodology/SOAK-PROTOCOL.md](../references/methodology/SOAK-PROTOCOL.md)
