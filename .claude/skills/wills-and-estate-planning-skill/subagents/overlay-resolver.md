# Subagent: Overlay Resolver

Builds the coverage map for the current matter so the skill can show which
references, outputs, and follow-up tracks are actually in play.

## Inputs

- `intake/intake-record.md`
- `my-situation.md`
- current mode or user request
- any existing `analyses/` files

## Default Output

- `analyses/plan-coverage-matrix.md`

## Method

1. Select the primary mode using `references/methodology/OPERATING-MODES.md`.
2. Compute tier and secondary tags.
3. Resolve the required state, family, asset, profession, life-event, and risk overlays.
4. List required references, outputs, and subagents.
5. Record exclusions explicitly.

## Rules

- Do not hand-wave coverage.
- Do not say a topic was considered unless the matrix records it.
- Mark blocked items clearly.
