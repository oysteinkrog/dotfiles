---
name: soak-runner
description: Phase 11 (Exhaustive only) — dispatches long-running fuzz / Miri / loom campaigns via rch and tracks them.
---

# Soak Runner

**Invoke with `subagent_type=general-purpose`** — pulls artifacts back and edits the campaign block.

One per campaign in `phase11_soak_designs.md`. Long-running by design; always offload via `rch`.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{CAMPAIGN_ID}` — campaign identifier from `phase11_soak_designs.md`

## Workflow
Use [Phase 11 soak-runner prompt](../references/AGENT-PROMPTS.md#phase-11--soak-runner-exhaustive-only) verbatim.

## Typical campaigns

| Campaign | Wall-time | Command |
|---|---|---|
| 24h fuzz | 24h | `cargo +nightly fuzz run {TARGET} -- -max_total_time=86400` |
| Full-suite Miri matrix | hours-days | `for cfg in default tree strict alignment; do MIRIFLAGS=... cargo +nightly miri test; done` |
| 10⁴ loom iters | hours | `RUSTFLAGS="--cfg loom" cargo +nightly test --release {PRIMITIVE}_loom` (model with 10⁴ inner iters) |
| 10⁵ shuttle | hours | `shuttle::check_random(model, 100_000)` |

## Outputs
- Updated campaign block in `phase11_soak_designs.md` with verdict + raw output reference
- Pulled artifacts in `{WORKSPACE}/phase11_artifacts/{CAMPAIGN_ID}/`

## Quality gates
- [ ] `rch` job tag matches `ub-exorcism-{RUN_ID}-{CAMPAIGN_ID}`
- [ ] Artifacts pulled back to local
- [ ] Verdict recorded in `phase11_soak_designs.md`

## Failure modes
- **Locally launched instead of via rch:** burns the user's machine; offload via `rch exec --`
- **No periodic poll:** the orchestrator needs status; poll every 30 min via `rch status`
- **New UB found but not looped back:** Phase 11 findings must be added to `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` and trigger a Phase 8 re-entry

## Coordination
Mail thread: `ub-exorcism-{RUN_ID}-phase11-{CAMPAIGN_ID}` (long-lived; days).
