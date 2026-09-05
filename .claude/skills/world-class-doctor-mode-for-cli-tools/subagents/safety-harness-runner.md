# subagent: safety-harness-runner (Phase 5)

**Description.** For every fixer, run the five safety tests (reversibility, idempotence, crash-recovery, concurrency, detector metamorphic repeatability). Failures here are blocking.

## Inputs

- `{{target}}` — target repo (with the new `<tool> doctor` already implemented)
- `{{workspace}}/safety_harness.jsonl` (appended to)
- `tests/doctor_fixtures/<fm_id>/{corrupt.sh, assert.sh}` — fixture set per FM. **Phase ordering note (round-53 triangulation):** these fixtures are formally "built in Phase 9" by `subagents/fixture-author.md`, but Phase 5 cannot run without them. The skill resolves this by having `subagents/repair-spec-author.md` (Phase 2) emit a SKELETON pair (`corrupt.sh` that produces the corrupted state described in the FM's repair spec, `assert.sh` that asserts the expected post-fix state). Phase 9's fixture-author.md then EXPANDS those skeletons with edge-case fixtures + golden artifacts. If `corrupt.sh` is missing when Phase 5 starts, the harness exits 1 with a clear message — that is the signal that Phase 2 didn't emit the skeleton. See [PHASES.md § Phase 2 outputs](../references/methodology/PHASES.md) for the skeleton contract.

## Outputs

- `{{workspace}}/safety_harness.jsonl`
- `{{workspace}}/safety_harness_report.md`

## Prompt

Full prompt in [../references/methodology/AGENT-PROMPTS.md § safety-harness-runner](../references/methodology/AGENT-PROMPTS.md#safety-harness-runner-phase-5). Use verbatim.

## The five tests

For every `fm_id` in `<tool> doctor capabilities --json::fixers[].id`:

Each verify-*.sh script signature is `<script> <fm_id> [<tool>] [<fixture_root>]`. The `<tool>` arg is required: pass it as arg 2 OR set `TOOL=<tool>` in the environment (the script exits 64 with a usage message if neither). Recommended: export `TOOL` once at the start of the harness loop.

```bash
export TOOL=<tool>     # used by all five verify-*.sh invocations below
```

1. **Reversibility.** `scripts/verify-undo.sh fm-<id>` — corrupt → fix → assert healthy → undo → cmp-strict.
2. **Idempotence.** `scripts/verify-idempotence.sh fm-<id>` — fix; fix; assert second is no-op.
3. **Crash-recovery.** `scripts/verify-crash-recovery.sh fm-<id>` — kill at K = {1, 5, 25, 125} ms; next run completes or aborts cleanly.
4. **Concurrency.** `scripts/verify-concurrency.sh fm-<id>` — two simultaneous `--fix`; one wins, other refuses with exit 5.
5. **Detector metamorphic repeatability.** `scripts/verify-metamorphic.sh fm-<id>` — two consecutive diagnose runs against the same corrupted state emit equivalent finding sets.

## Exit criteria

- Every fixer passes all five tests.
- `safety_harness.jsonl` has 5 × N rows with `exit_code: 0`.

## Failure modes (HARD STOP)

Any test failure stops the phase. Open a P0 bead, assign to the spec author, re-enter Phase 4 with the proposed fix.

- Reversibility fail → fixer is touching bytes outside its diff range. Reduce diff range.
- Idempotence fail → detector is dirty (mutating a side channel). Make detector pure.
- Crash-recovery fail → atomic write violation (write + rename across FS, or write without rename). Use `tempfile + persist()` / `os.replace` pattern.
- Concurrency fail → no advisory lock at `mutate()` entry. Acquire lock before any read.
- Metamorphic repeatability fail → detector is non-deterministic or stateful. Remove hidden state, timestamps, unstable ordering, or side effects from the finding path.

## Optional extensions

If the testing-* skills are installed, layer them in:

- [testing-fuzzing](../../testing-fuzzing/SKILL.md) — fault-inject into `mutate()` chokepoint.
- [testing-metamorphic](../../testing-metamorphic/SKILL.md) — derive deeper property tests such as `fix(corrupt(x)) ≡ x`.
- [testing-conformance-harnesses](../../testing-conformance-harnesses/SKILL.md) — round-trip backup/restore against a golden corpus.

These are bonus rounds; the five core tests are the gate.
