# subagent: repair-spec-author (Phase 2, parallel by subsystem; SAME agent as Phase 1)

**Description.** For each failure mode in `{{subsystem}}.md`, write a Repair Spec: detector pseudocode, fixer pseudocode, preconditions, invariants, backup spec, inverse, idempotence proof sketch, fixture spec.

## Inputs

- `{{workspace}}/analysis/failure_modes/{{subsystem}}.md` (this agent wrote it in Phase 1)
- `../references/methodology/MUTATE-CHOKEPOINT.md` (READ FIRST)
- `../assets/repair-spec-template.md`

## Outputs

- One `{{workspace}}/analysis/repair_specs/{{fm_id}}.md` per failure mode
- One SKELETON pair `{{target}}/tests/doctor_fixtures/{{fm_id}}/{corrupt.sh, assert.sh}` per failure mode. **Skeleton contract (round-53):** Phase 5's `safety-harness-runner.md` cannot run without these — even though the rich fixtures are built in Phase 9 by `fixture-author.md`. The skeleton minimum is: `corrupt.sh <sandbox>` that produces the exact corrupted state described in the spec's `triggered_by_findings`; `assert.sh <sandbox>` that asserts the post-fix expected state matches. Both must be `chmod +x`. Phase 9 expands these with edge-case fixtures + golden artifacts; Phase 5 only needs the skeleton.

## Prompt

The full prompt is in [../references/methodology/AGENT-PROMPTS.md § repair-spec-author](../references/methodology/AGENT-PROMPTS.md#repair-spec-author-phase-2). Use verbatim.

## Critical rules

- Detector pseudocode is PURE. No mutate(), no writes.
- Fixer routes EVERY write through `mutate(path, op)`.
- Backup spec lists exact paths.
- Inverse defaults to `<tool> doctor undo <run-id>`. Special-case logic only when the fixer creates a file that didn't exist (then undo deletes via `Op::Rename` to quarantine).
- Idempotence proof: argue the post-fix detector returns None, so a second fix is a no-op.
- **Metamorphic relation (round-56):** every detector spec MUST include a "Metamorphic relations" section listing the relation(s) the detector preserves. The minimum is `detect(state) == detect(state)` after a NO-OP — i.e., two consecutive `<tool> doctor diagnose --only=<fm_id>` invocations against the same state must produce byte-identical `.findings` arrays (modulo per-run timestamps). Phase 5 verifies this via `scripts/verify-metamorphic.sh`. Stronger relations (e.g., `detect(state) == detect(commute(state))` for FMs whose state has documented symmetries) are encouraged but not required.

## Exit criteria

- One spec per FM in `{{subsystem}}`
- Each spec passes `python3 scripts/validate-spec.py {{workspace}}/analysis/repair_specs/<id>.md` (exit 0)

## Failure modes

- Spec author can't think of a fixer for a FM (e.g., the FM is "user's filesystem ran out of space"). That's fine — mark `currently_auto_fixed: no`, document the manual remediation, file as `manual_remediations` in `capabilities.json`. Doctor still **detects** it.
- Multiple FMs collapse to the same fixer. Merge them — share the `fm_id` is wrong here; instead, make one spec with multiple `triggered_by_findings:` entries.
