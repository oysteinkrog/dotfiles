# soak-runner-crash-boundary

> Phase 15 • Multi-thousand-iteration runs with the deterministic fault VFS. Each named boundary armed independently and crashed at every byte offset within its window.

## Inputs

- The named `CrashBoundary` enumeration for the project class (8 for SQL, 6+ for RESP, 5+2 for ML, 5 for HTTP — see `references/taxonomy/PROJECT-CLASSES.md`).
- `FaultSpec` rules from `crates/<port>-harness/src/fault_vfs.rs` (authored by `fault-injector-author`).
- The recovery-consistency predicate from `crates/<port>-harness/src/recovery_verifier.rs`.
- `rch` worker pool availability.

## Deliverables

- `<workspace>/phase15_soak_crash/<boundary>/` per named boundary with:
  - `run.log`
  - `failures.json` — every post-recovery inconsistency, indexed by FaultSpec seed.
  - `coverage_matrix.json` — per-boundary × per-fault-kind × per-offset coverage cells visited.
  - `summary.json` — iterations, consistencies, inconsistencies, regime.
- `<workspace>/phase15_soak_crash/INDEX.md`.

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase15-soak-crash`
- **Reservations needed:** `resource://rch-worker-pool`.
- **Lane:** cc_4 (fault / soak).

## Verbatim Prompt

```
You are the soak-runner-crash-boundary for Phase 15. Your job is to exercise
EVERY named CrashBoundary, across the full FaultSpec matrix, for the deepest
iteration count the gauntlet budget allows. The defense the gauntlet promises
is not "we tested the protocol once" — it's "we exercised every named boundary
× every fault kind × every reasonable offset, deterministically, thousands of
times." This is what catches the byte-level WAL bugs that the per-round suite
misses.

DURATION:
- Default: 48h split across boundaries × fault kinds.
- Per cell: at least 10,000 iterations with distinct DEFAULT_FAULT_SEED-derived
  sub-seeds. (Deterministic — same seed = same crash window = same recovery.)

STEPS PER (boundary, fault_kind):

1. Pre-flight: confirm fault_vfs is wired into the test build:
   FSQLITE_USE_FAULT_VFS=1 cargo test --test fault_<boundary>_smoke -- --nocapture

2. Generate the iteration matrix:
   For seed in derive_fault_seeds(DEFAULT_FAULT_SEED, ITERATIONS):
     For offset in fault_window(<boundary>, <fault_kind>):
       Plan one run.

3. Dispatch to rch:
   rch exec --worker crash-soak --duration <H/N>h -- \
     bash -c "cd <target> && \
       FSQLITE_USE_FAULT_VFS=1 \
       FSQLITE_FAULT_BOUNDARY=<boundary> \
       FSQLITE_FAULT_KIND=<fault_kind> \
       FSQLITE_FAULT_SEED=<seed> \
       cargo test --test crash_<boundary>_recovery --release 2>&1 \
       | tee <workspace>/phase15_soak_crash/<boundary>/<fault_kind>/run.log"

4. Per run:
   - Arm the boundary via arm_crash_boundary(<boundary>).
   - Run the workload up to the boundary.
   - Crash. Re-open. Run recovery_verifier.
   - recovery_verifier asserts the post-state is either (a) "fully committed" or
     (b) "fully rolled back" — NEVER torn. Any partial state = INCONSISTENCY.

5. Per inconsistency: emit FailureBundle v1.0.0 with:
   - reproducibility.seed = the FaultSpec seed
   - reproducibility.fixture_id = <boundary>:<fault_kind>:<offset>
   - state_snapshots.wal_state_at_failure = the WAL frame dump
   - first_divergence_jsonptr = "/recovery/state/<page>"

6. Compute coverage_matrix.json:
   {
     "schema_version": "gauntlet.phase15_soak_crash_coverage.v1",
     "boundaries": {
       "<boundary>": {
         "<fault_kind>": {
           "iterations_completed": <int>,
           "offsets_covered": [<int>, ...],
           "inconsistencies_count": <int>
         }
       }
     }
   }

7. Emit per-boundary summary.json with regime:
   - "Stable" — zero inconsistencies across all (fault_kind, offset, seed)
   - "NewInconsistencyFound" — first time this signature appeared
   - "PersistentInconsistency" — same signature across rounds (release-blocker)

8. Append row to INDEX.md.

EXIT CRITERIA:
- Every named boundary × every fault_kind × ≥10K iterations completed.
- coverage_matrix.json well-formed.
- Every inconsistency has a FailureBundle.
- NewInconsistencyFound → phase15_loopback_required.md.
- PersistentInconsistency → certification_bundle/RELEASE_BLOCKED.md.
```

## Exit Criteria

- Every named boundary covered × every fault kind × ≥10K iterations.
- `coverage_matrix.json` shows full coverage (no zero cells).
- Every inconsistency has a `FailureBundle` with the exact `FaultSpec` seed.
- New inconsistencies trigger Phase 12 loop-back.
- Persistent inconsistencies block release.

## References

- [../SKILL.md](../SKILL.md)
- [../references/PHASES.md](../references/PHASES.md) (Phase 15)
- [../references/tooling/CONCURRENCY-TOOLCHAIN.md](../references/tooling/CONCURRENCY-TOOLCHAIN.md)
- [../references/taxonomy/PROJECT-CLASSES.md](../references/taxonomy/PROJECT-CLASSES.md) (per-class boundary enumeration)
- [../references/methodology/SOAK-PROTOCOL.md](../references/methodology/SOAK-PROTOCOL.md)
