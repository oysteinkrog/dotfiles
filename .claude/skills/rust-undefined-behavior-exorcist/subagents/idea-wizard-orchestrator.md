---
name: idea-wizard-orchestrator
description: Invokes /idea-wizard Phase 2 prompt for project-shaped UB-detection techniques; runs 2–3 independent rounds (different lenses); investigates ALL 30 ideas per round (not top-5). Phase 6.
---

# Idea-Wizard Orchestrator

**Invoke with `subagent_type=general-purpose`** — writes `phase6_idea_wizard_round_{ROUND}.md` and appends experiment blocks. `Explore` cannot Write/Edit.

Phase 6's owner. Drives `/idea-wizard` against the project to surface UB-detection techniques that the off-the-shelf taxonomy missed.

**KEY POLICY CHANGE (calibrated against field data):**
- **Run 2 independent rounds in Standard mode, 3 in Exhaustive.** Each round uses a different lens (STRUCTURAL / ADVERSARIAL / CROSS-SYSTEM) so the rounds don't redundantly mine the same shape.
- **Investigate ALL 30 ideas per round**, not just the top-5. Field evidence: a SHA-256 collision via NUL-injection in `HashFieldWriter` was found in an idea-wizard round whose top-5 by score did NOT contain it; the killer finding was at sum-score-rank #30. The post-Phase-1/2 static buckets had **not** caught it. Top-5 only would have missed it.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{ROUND_NUMBER}` of `{TOTAL_ROUNDS}` (2 for Standard, 3 for Exhaustive)
- `{LENS}` — STRUCTURAL (R1) / ADVERSARIAL (R2) / CROSS-SYSTEM (R3)

## Workflow
Use [Phase 6 idea-wizard-orchestrator prompt](../references/AGENT-PROMPTS.md#phase-6--idea-wizard-orchestrator-multi-round-investigate-all) verbatim — that prompt now encodes the multi-round + investigate-all policy and the lens-rotation schedule.

Read first:
- `{WORKSPACE}/phase4_unified_findings.md` (current)
- `{WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` (current state)
- `{WORKSPACE}/phase1_notes/*.md` for project-shape priors
- Every prior round's file in `{WORKSPACE}/phase6_idea_wizard_round_*.md` (do not re-propose ideas previous rounds already filed)

## Outputs
- `{WORKSPACE}/phase6_idea_wizard_round_{ROUND_NUMBER}.md` — 30 ideas with three-axis scores AND per-idea verdict (ALREADY_COVERED / NEW_EXP_PROMOTED / NEEDS_DEEPER_INVESTIGATION / NO_EVIDENCE / INAPPLICABLE)
- Net-new experiment blocks in `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md`, numbered `EXP-{ROUND}NN`
- On the FINAL round: `{WORKSPACE}/phase6_idea_wizard_rollup.md` consolidating all rounds' verdicts into one matrix

## Quality gates
- [ ] 30 techniques in this round's initial generation (not 25, not 31; 30 exactly so cross-round comparison is clean)
- [ ] Three-axis score (PROVABILITY / IMPACT / NOVELTY) on every idea, 1–5 each
- [ ] Every idea has a per-idea verdict — no "TBD"
- [ ] Lens for this round explicitly stated and distinct from prior rounds
- [ ] ≥1 net-new EXP block filed (or, on a late round when the field is truly mined out, a "Round-{N} verdict: no net-new — convergence-evidence" note)
- [ ] (Final round only) the rollup file exists and has one row per (round, idea-id)

## Failure modes
- **Generic techniques:** "run miri" / "add a clippy lint" — not project-shaped. Specifically target this project's content-hash / custom allocator / lock-free DS / etc.
- **Top-5 shortcut:** investigating only the top-5 by score is the failure mode this policy was designed to prevent. Walk all 30.
- **Lens collision:** if R1 STRUCTURAL and R2 ADVERSARIAL produce 25 overlapping ideas, the lens-rotation isn't doing its job. Re-prompt R2 with more adversarial framing.
- **All 30 marked "Already covered":** either the project has been mined thoroughly (good — record as evidence of convergence) or the wizard is being lazy (bad — re-prompt with more specificity and a different lens)

## Coordination
Mail thread: `ub-exorcism-{RUN_ID}-phase6-round{ROUND_NUMBER}-{LENS}`.
