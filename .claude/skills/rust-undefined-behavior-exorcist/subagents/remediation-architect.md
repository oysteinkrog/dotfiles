---
name: remediation-architect
description: Phase 8 — enumerates isomorphic rewrites for each CONFIRMED_UB finding, rubric-scores them, picks, records runners-up.
---

# Remediation Architect

**Invoke with `subagent_type=general-purpose`** — writes `phase8_remediation_plan.md`. `Explore` cannot.

Owns Phase 8. Reads the *final* unified findings and experiment designs; writes the remediation plan.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`

## Workflow
Use [Phase 8 remediation-architect prompt](../references/AGENT-PROMPTS.md#phase-8--remediation-architect) verbatim. Lean on [REMEDIATION-PATTERNS.md](../references/REMEDIATION-PATTERNS.md) for the playbook.

## Outputs
- `{WORKSPACE}/phase8_remediation_plan.md`, one section per CONFIRMED_UB finding, each containing:
  - Finding ref + UB shape match
  - Candidate rewrites (≥2 where applicable)
  - Rubric scores (5-axis, 0–4)
  - Chosen winner + rationale
  - Runners-up + tradeoffs
  - Cross-refs: proving experiment + future regression experiment
  - (For high-stakes findings) `## Triangulation` heading with `/multi-model-triangulation` output

## Quality gates
- [ ] Every CONFIRMED_UB finding has a remediation section
- [ ] Every remediation has ≥1 runner-up where applicable
- [ ] Rubric scores are quantitative on perf delta (benchmark when in 0–1 range)
- [ ] High-stakes findings (custom allocator / lock-free DS / FFI public API) have triangulation results
- [ ] Every remediation cross-references the regression experiment

## Failure modes
- **First-rewrite-that-compiles:** pick must be justified against runners-up on the rubric, not "this works"
- **Runners-up are strawmen:** record real, plausible alternatives — not "we could also just not fix it"
- **Missing perf benchmark:** if perf delta is in 0–1, you need a number

## Coordination
Mail thread: `ub-exorcism-{RUN_ID}-phase8`.
