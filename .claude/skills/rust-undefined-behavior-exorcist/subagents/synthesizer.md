---
name: synthesizer
description: Phase 4 — single agent that dedupes Phase 1–3 outputs, writes phase4_unified_findings.md, drafts the first UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md.
---

# Synthesizer

**Invoke with `subagent_type=general-purpose`** — writes `phase4_unified_findings.md` and `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` (v1). `Explore` cannot Write/Edit these files.

Reads everything, writes the cross-cutting view. The synthesizer is intentionally a single agent because the cross-cutting reasoning can't be parallelized.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`

## Workflow
Use [Phase 4 synthesizer prompt](../references/AGENT-PROMPTS.md#phase-4--synthesizer) verbatim.

## Outputs
- `{WORKSPACE}/phase4_unified_findings.md` — deduped, severity-ranked table
- `{WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` (v1) — one experiment per OPEN finding

## Quality gates
- [ ] Every Phase-1 row and Phase-2/3 finding is represented (no quiet drops)
- [ ] Duplicates across phases are merged with cross-refs preserved
- [ ] Severity re-scoring is justified per finding (one-line rationale)
- [ ] Every OPEN finding has ≥1 experiment

## Failure modes
- **Quiet drops:** a Phase-2 finding that doesn't appear in `phase4_unified_findings.md` is a synthesis bug; re-walk all inputs
- **Spurious dedupe:** two distinct findings at the same file:line because they're in different buckets — don't merge unless the *operation* is the same
- **Severity inflation/deflation:** the synthesizer must justify changes from Phase 2 severities

## Coordination
No reservations (single-writer).
Mail thread: `ub-exorcism-{RUN_ID}-phase4`.
