---
name: sanitizer-runner
description: Runs cargo +nightly test under one LLVM sanitizer (ASan / TSan / MSan / LSan); parses signal into Phase 3 findings.
---

# Sanitizer Runner

**Invoke with `subagent_type=general-purpose`** — writes the raw log and appends findings.

One per sanitizer family. Each sanitizer family is mutually exclusive with the others — never combine in a single build.

> **Skip rule for pure-safe-Rust projects:** projects with `#![forbid(unsafe_code)]` and no FFI have near-zero ASan/MSan/LSan yield. For Standard mode, run only TSan (still catches `Send`-derivation drift); skip the others with a `SKIPPED-pure-safe` note. See [PROJECT-TYPES.md §P15 Pure-Safe Forbid-Unsafe](../references/PROJECT-TYPES.md#p15-pure-safe-forbid-unsafe-projects).

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{SANITIZER}` — one of: `address`, `thread`, `memory`, `leak`

## Workflow
Use [Phase 3 sanitizer-runner prompt](../references/AGENT-PROMPTS.md#phase-3--sanitizer-runner-asan--tsan--msan--lsan) verbatim. See [TOOLING.md §Sanitizers](../references/TOOLING.md#sanitizers-asan-tsan-msan-lsan) for the exact invocations.

## Reservations
Reserve `tool://sanitizer-build` exclusive (sanitizer-instrumented builds are large; one at a time).

## Outputs
- `{WORKSPACE}/phase3_raw/{SANITIZER}.log` — raw output
- Findings appended to `{WORKSPACE}/phase3_dynamic_findings.md`

## Quality gates
- [ ] For TSan, `--test-threads=1` was used (verify in the log)
- [ ] Each sanitizer report has at least the first 20 lines of the trace recorded
- [ ] False positives (`std` traces with no user code in them) are noted but not promoted to findings

## Failure modes
- **Target unsupported:** record `SKIPPED — {SANITIZER} not supported on this target` in `phase3_dynamic_findings.md`
- **Build fails with `-Z` errors:** ensure nightly + rust-src installed
- **MSan std-rebuild fails first time:** retry once
- **Sanitizer + panic = strange output:** add `-C panic=abort`

## Coordination
Mail thread: `ub-exorcism-{RUN_ID}-phase3-sanitizer-{SANITIZER}`.
