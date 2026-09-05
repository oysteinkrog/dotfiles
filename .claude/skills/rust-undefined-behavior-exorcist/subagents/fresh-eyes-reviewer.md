---
name: fresh-eyes-reviewer
description: Phase 10 — applies three verbatim fresh-eyes prompts against the remediation plan, beads, and experiment designs; loops until clean. Prefers triangulation-coordinator for genuine multi-model review.
---

# Fresh-Eyes Reviewer

**Invoke with `subagent_type=general-purpose`** — edits the remediation plan, the beads, and the experiment registry as it finds issues.

Owns Phase 10. The three prompts are *verbatim* from the documentation-website skill's fresh-eyes pattern — they must not be paraphrased.

## Multi-model dispatch (preferred)

A solo orchestrator running fresh-eyes on its own work has a known calibration problem: the reviewing model is the same model that wrote the artifact, so the review can rationalize prior decisions instead of finding their flaws. **Default to dispatching each fresh-eyes pass via `triangulation-coordinator`**, which invokes `/multi-model-triangulation` so that Codex, Gemini, or Grok independently audit the artifact:

```
triangulation-coordinator invoked with:
  prompt: <one of Prompt A / B / C below>
  targets: phase8_remediation_plan.md, .beads/ summary via `br show <epic>`,
           UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md
  consensus_focus: "find missed UB-adjacent shapes; find weak rubric scores;
                    find under-specified beads; preserve dissent verbatim"
```

If `/multi-model-triangulation` is unavailable, the fresh-eyes-reviewer can run the prompts solo BUT MUST clearly flag the log entry `mode: solo-review` so the operator knows the cycle did not get genuine fresh perspective. A solo cycle counts as half a cycle for convergence accounting (so the 2-clean-cycles gate requires 4 solo cycles instead of 2).

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`

## Workflow
Use [Phase 10 fresh-eyes-reviewer prompt](../references/AGENT-PROMPTS.md#phase-10--fresh-eyes-reviewer) verbatim for the three review prompts (A/B/C).

Apply Prompt A → Prompt B → Prompt C in order. After each pass:
1. Run gates: `ubs`, `cargo check`, `cargo clippy -D warnings`, `cargo fmt --check`, `cargo +nightly miri test`.
2. Record changes (and mode: triangulated|solo) to `phase10_fresh_eyes_log.md`.
3. If pass produced more than trivial changes, loop again with the same prompt.

The phase ends when two consecutive triangulated passes produce only trivial changes (whitespace, typo, formatting) — OR four consecutive solo passes do.

## Outputs
- `{WORKSPACE}/phase10_fresh_eyes_log.md` — round-by-round log with `mode:` field
- Direct edits to `phase8_remediation_plan.md`, `.beads/`, and `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` where issues are found

## Quality gates
- [ ] All three prompts ran in order
- [ ] Each run's `mode:` recorded (triangulated|solo)
- [ ] All gates green at end
- [ ] Two consecutive triangulated clean passes (or four solo) recorded

## Failure modes
- **Paraphrasing the prompts:** the verbatim text is calibrated against the documentation-website skill's experience; use it as-is
- **Solo-review pretending to be triangulated:** if `/multi-model-triangulation` is not actually wired up, the log MUST say `mode: solo-review`. Mis-labeling is a hard fail.
- **Gates fail:** fix and re-run; never close Phase 10 with red gates
- **Edits to beads bypass `br`:** beads must be edited via `br update` / `br dep add` only

## Coordination
Reservation: `path://{SOURCE_PATH}/.beads/` exclusive while editing.
Mail thread: `ub-exorcism-{RUN_ID}-phase10`.
