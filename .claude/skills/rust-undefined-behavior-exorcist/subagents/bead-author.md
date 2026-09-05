---
name: bead-author
description: Phase 9 — converts phase8_remediation_plan.md into a polished bead graph via /beads-workflow; ensures every remediation has test+docs deps.
---

# Bead Author

**Invoke with `subagent_type=general-purpose`** — runs `br` mutations and writes `phase9_beads_log.md`.

Owns Phase 9. Invokes `/beads-workflow`'s exact plan-to-beads prompt against the remediation plan, then polishes 4–5 rounds.

> **Validation note (post-field-trial):** Use `br show <epic>` to list a parent epic's downstream children. `br dep tree <epic>` only shows what the bead is blocked-by (upstream blockers), not what it blocks (downstream dependents). See [VALIDATION.md §Phase 9](../references/VALIDATION.md#phase-9--beads-gates).

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`

## Workflow
Use [Phase 9 bead-author prompt](../references/AGENT-PROMPTS.md#phase-9--bead-author) verbatim. See [ORCHESTRATION.md §Beads Handoff](../references/ORCHESTRATION.md#beads-handoff-phase-9) for the exact `/beads-workflow` plan-to-beads and polish prompts.

## Outputs
- Beads in `{SOURCE_PATH}/.beads/` (managed by `br`)
- `{WORKSPACE}/phase9_beads_log.md` — round-by-round polish log
- Committed `.beads/` changes (with user permission)

## Quality gates after each polish round
- [ ] `br dep cycles` returns empty
- [ ] `bv --robot-insights | jq '.Cycles'` returns empty
- [ ] Every remediation bead has ≥1 test-bead dep
- [ ] Every remediation bead has ≥1 docs-bead dep
- [ ] No bead has empty description

## Failure modes
- **Polish flatlines after 1 round:** start a fresh session with the "Re-establish Context" prompt from `/beads-workflow`
- **Cycle detected:** read `br dep cycles` output; remove the wrong edge (see [TROUBLESHOOTING.md §Beads](../references/TROUBLESHOOTING.md#beads--br--bv))
- **Missing test/docs dep:** loop and re-run polish; this is a hard gate

## Coordination
Reservation: `path://{SOURCE_PATH}/.beads/` exclusive, TTL 3600s.
Mail thread: `ub-exorcism-{RUN_ID}-phase9`.
