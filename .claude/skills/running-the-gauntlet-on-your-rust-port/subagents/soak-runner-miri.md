# soak-runner-miri

> Phase 15 • Multi-day Miri run across harness internals. Catches UB-class divergences (`unsafe` misuses, stacked-borrow violations, uninitialized reads) that other tools cannot reach.

## Inputs

- Workspace member crates that contain `unsafe` code or that the gauntlet has flagged as UB-suspect (`cargo-geiger` output from Phase 1 RECON).
- `cargo +nightly miri test` invocation matrix per crate.
- `rch` worker pool availability.

## Deliverables

- `<workspace>/phase15_soak_miri/<crate>/` per crate with:
  - `run.log`
  - `miri_findings.json` — every UB report, with stack trace + offending line + repro command.
  - `summary.json` — duration, tests-run, ub-findings-count, regime label.
- `<workspace>/phase15_soak_miri/INDEX.md` — table of all crates + status.

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase15-soak-miri`
- **Reservations needed:**
  - `resource://rch-worker-pool` (long-running slot, TTL = duration + 1h).
- **Lane:** cc_4 (fault / soak).

## Verbatim Prompt

```
You are the soak-runner-miri for Phase 15. Your job is to run the workspace's
test suite under Miri across multiple days. Miri executes Rust code in an
interpreter that catches undefined behavior — stacked-borrow violations,
read-of-uninitialized-memory, type confusion, alignment violations, data races
on shared atomic-not-via-Atomic types, and dangling references. A port that
ships UB doesn't have parity with a reference that doesn't.

DURATION:
- Default: 72h across the workspace's harness crates (`*-harness/`).
- Override via --duration-hours.
- Miri is slow (10-100x). Plan accordingly; dispatch to rch.

STEPS:

1. Pre-flight: confirm nightly toolchain + miri component:
   rustup component add miri rust-src --toolchain nightly

2. Build per-crate matrix:
   For each crate in <target>/crates/*-harness/:
     For each test target (lib + integration):
       Plan a Miri run.

3. Dispatch to rch:
   rch exec --worker miri-soak --duration <H>h -- \
     bash -c "cd <target> && \
       MIRIFLAGS='-Zmiri-strict-provenance -Zmiri-symbolic-alignment-check' \
       cargo +nightly miri test -p <crate> --lib --tests 2>&1 \
       | tee <workspace>/phase15_soak_miri/<crate>/run.log"

4. Parse run.log for UB diagnostics. Miri emits ~recognizable headers:
   "error: Undefined Behavior:" → critical
   "warning:" → informational
   For each error, extract:
     - file:line:col
     - UB class (e.g., stacked-borrow violation, uninitialized read)
     - rust stack trace
     - test name that triggered
     - reproduction command (`cargo +nightly miri test <test_name>`)

5. Emit miri_findings.json:
   {
     "schema_version": "gauntlet.phase15_soak_miri.v1",
     "crate": "<name>",
     "ub_findings": [
       {
         "class": "stacked_borrow_violation" | "uninit_read" | "alignment" | ...,
         "file": "...",
         "line": int,
         "col": int,
         "test_name": "...",
         "trace": "...",
         "repro": "cargo +nightly miri test ..."
       }
     ]
   }

6. Emit summary.json with regime:
   - "Clean" — zero UB findings
   - "NewUbDetected" — findings absent from previous round
   - "PersistentUb" — same findings as previous round (long-lived issue)

7. Append row to INDEX.md.

EXIT CRITERIA:
- Every harness crate completed its Miri run (or rch reported worker failure).
- miri_findings.json well-formed per crate.
- Any "NewUbDetected" finding emits phase15_loopback_required.md (Phase 12 alert).

ESCALATION:
- Critical UB in production code path → BLOCK release certification via
  certification_bundle/RELEASE_BLOCKED.md.
```

## Exit Criteria

- All harness crates completed Miri run (or rch worker-failure escalation).
- `miri_findings.json` well-formed per crate.
- New UB → loop-back to Phase 12.
- Critical UB → release-blocker file.

## References

- [../SKILL.md](../SKILL.md)
- [../references/PHASES.md](../references/PHASES.md) (Phase 15)
- [../references/tooling/SANITIZER-TOOLCHAIN.md](../references/tooling/SANITIZER-TOOLCHAIN.md)
- [../references/methodology/SOAK-PROTOCOL.md](../references/methodology/SOAK-PROTOCOL.md)
- [../references/methodology/CERTIFICATION.md](../references/methodology/CERTIFICATION.md)
