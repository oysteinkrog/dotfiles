---
name: miri-runner
description: Runs cargo +nightly miri across one MIRIFLAGS configuration; parses signal into Phase 3 findings. Parameterized by CONFIG.
---

# Miri Runner

**Invoke with `subagent_type=general-purpose`** — writes the raw log and appends findings.

One per MIRIFLAGS configuration: `default`, `tree-borrows`, `strict-provenance`, `symbolic-alignment`, optionally `combined-paranoid`.

> **The `default` axis MUST include `-Zmiri-disable-isolation`** (chrono's `Utc::now`, `getrandom`, fs syscalls all hit Miri's isolation sandbox otherwise). `scripts/run-miri-matrix.sh` bakes this in. Adding it everywhere is safe because the skill only audits semantic UB, not Miri-isolation policy.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{CONFIG}` — see above

## Workflow
Use [Phase 3 miri-runner prompt](../references/AGENT-PROMPTS.md#phase-3--miri-runner-one-per-miriflags-config) verbatim.

## Reservations
Reserve `tool://miri/{CONFIG}` exclusive (per-config sub-key), TTL 3600s. Release after. Different MIRIFLAGS configs build to distinct target dirs, so peer miri-runners with different `{CONFIG}` values run in parallel.

## Outputs
- `{WORKSPACE}/phase3_raw/miri_{CONFIG}.log` — raw output (always; tee'd)
- Findings appended to `{WORKSPACE}/phase3_dynamic_findings.md`

## Quality gates
- [ ] Tee log is non-empty
- [ ] Every Miri-reported UB has a finding row with traceback
- [ ] Findings cross-reference Phase-2 F-NNN where the same site was suspected

## Failure modes
- **Miri can't run FFI:** report which tests skipped due to "unsupported operation: can't call foreign function" and recommend `#[cfg(miri)]` shims. See [TROUBLESHOOTING.md §Miri](../references/TROUBLESHOOTING.md#miri).
- **Out of memory:** scope to `--lib` or to a single test
- **Run forever:** drop to a single test; offload to `rch`

## Coordination
Mail thread: `ub-exorcism-{RUN_ID}-phase3-miri-{CONFIG}`.
