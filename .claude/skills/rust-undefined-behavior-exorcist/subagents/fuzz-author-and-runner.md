---
name: fuzz-author-and-runner
description: Authors a libFuzzer target for an unsafe API that lacks one, then runs a bounded campaign and triages crashes under Miri.
---

# Fuzz Author-and-Runner

**Invoke with `subagent_type=general-purpose`** — authors target source files and writes logs/findings.

One per `cargo fuzz` target — existing targets get re-run, missing targets get authored. The author-and-runner is split into "author" and "runner" responsibilities but the same subagent owns both.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{TARGET}` — fuzz target name
- `{NEEDS_AUTHORING}` — true if the target doesn't exist yet

## Workflow
Use [Phase 3 fuzz-author-and-runner prompt](../references/AGENT-PROMPTS.md#phase-3--fuzz-author-and-runner-one-per-existing-target--one-per-missing-target) verbatim.

### Authoring a new target

When `{NEEDS_AUTHORING}` is true:
1. Identify the unsafe API to exercise (per Phase 2 findings).
2. Author a target at `{SOURCE_PATH}/fuzz/fuzz_targets/{TARGET}.rs` using structured input via `arbitrary::Arbitrary`.
3. Add the target to `{SOURCE_PATH}/fuzz/Cargo.toml`.
4. Run a smoke pass: `cargo +nightly fuzz run {TARGET} -- -runs=100` to verify it builds and doesn't crash on init.

### Running

5. Reserve `tool://fuzz-corpus/{TARGET}` exclusive.
6. Run a bounded campaign (default 10 min for Standard mode; soak in Phase 11):
   ```bash
   cargo +nightly fuzz run {TARGET} -- -max_total_time=600 -timeout=5 \
     -artifact_prefix={WORKSPACE}/phase3_raw/fuzz_artifacts/{TARGET}/
   ```
7. For each crash artifact:
   - Write a finding row in `phase3_dynamic_findings.md`
   - Triage by re-running under Miri: `cargo +nightly miri test repro_{TARGET}_<hash>`
   - Record the Miri verdict alongside the crash

## Outputs
- `{SOURCE_PATH}/fuzz/fuzz_targets/{TARGET}.rs` (if authored)
- `{WORKSPACE}/phase3_raw/fuzz_artifacts/{TARGET}/` — crash corpus
- Findings appended to `phase3_dynamic_findings.md`

## Quality gates
- [ ] Authored targets compile and pass a 100-run smoke pass
- [ ] Every crash artifact has a Miri verdict
- [ ] Corpus is preserved (not deleted)

## Failure modes
- **Timeout warnings:** target is too slow on certain inputs; cap input size in the target
- **No crashes found, expected some:** extend wall time; add structured input via Arbitrary
- **Crash not reproducible:** export to a Miri-runnable `#[test]` (see [TROUBLESHOOTING.md §Fuzzing](../references/TROUBLESHOOTING.md#fuzzing))

## Coordination
Mail thread: `ub-exorcism-{RUN_ID}-phase3-fuzz-{TARGET}`.
