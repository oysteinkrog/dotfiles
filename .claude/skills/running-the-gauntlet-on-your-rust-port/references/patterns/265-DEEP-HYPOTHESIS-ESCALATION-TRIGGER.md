# 265-DEEP-HYPOTHESIS-ESCALATION-TRIGGER

**Family:** Convergence + Orchestration. Glyph: see [`OPERATORS.md § Deep Review Operator Inheritance`](../methodology/OPERATORS.md) for the `△ Review-Score`, `⊚ Productive-Ignorance`, `† Theory-Kill`, `∿ Dephase` glyphs that the escalation often invokes.

**When to apply:** the gauntlet's main loop encounters a contested situation that ordinary Phase 11 iteration won't resolve. Specifically, ONE of the four trigger conditions per [`methodology/DEEP-HYPOTHESIS-REVIEW.md § 6`](../methodology/DEEP-HYPOTHESIS-REVIEW.md):

1. **Stall** — 3+ consecutive Phase 11 rounds with `new_findings >= clean_threshold` AND `open_hypothesis_count > 0` AND the open hypotheses have vague predicates resisting falsification.
2. **Tie-break** — Phase 12 has 2+ equally-scored remediation candidates (score within 1 point on the 30-point rubric).
3. **Gate-flaw** — adversarial-search surfaced a counterexample that reveals a GATE design flaw (not just a fix-the-subject bug; the gate itself was wrong).
4. **Adversarial-followup** — a specific question keeps getting re-asked across rounds without resolution AND has fewer than 3 candidate hypotheses (the swarm is stuck in a small hypothesis space).

## The pattern

```rust
/// Detection helper called by iteration-coordinator at the close of every Phase 11 round.
pub fn detect_deep_review_escalation_trigger(
    state: &ConvergenceTracker,
    open_hypotheses: &[OpenHypothesis],
    last_3_rounds: &[RoundSummary],
    phase12_candidates: &[RemediationCandidate],
    adversarial_findings: &[AdversarialFinding],
) -> Option<EscalationTrigger> {
    // Trigger 1: Stall
    if last_3_rounds.iter().all(|r| r.new_findings >= state.clean_threshold)
        && state.open_hypothesis_count > 0
        && !open_hypotheses.is_empty()
        && open_hypotheses.iter().any(|h| h.predicate_is_vague())
    {
        return Some(EscalationTrigger::Stall {
            stalled_rounds: 3,
            vague_hypothesis_ids: open_hypotheses.iter()
                .filter(|h| h.predicate_is_vague())
                .map(|h| h.id.clone())
                .collect(),
        });
    }

    // Trigger 2: Tie-break
    let top_score = phase12_candidates.iter().map(|c| c.universal_score).max();
    if let Some(top) = top_score {
        let tied: Vec<_> = phase12_candidates.iter()
            .filter(|c| c.universal_score >= top - 1)
            .collect();
        if tied.len() >= 2 {
            return Some(EscalationTrigger::TieBreak {
                candidate_ids: tied.iter().map(|c| c.id.clone()).collect(),
            });
        }
    }

    // Trigger 3: Gate-flaw
    if adversarial_findings.iter().any(|f| f.classification == AdversarialClassification::GateDesignFlaw) {
        return Some(EscalationTrigger::GateFlaw {
            finding_id: adversarial_findings.iter()
                .find(|f| f.classification == AdversarialClassification::GateDesignFlaw)
                .unwrap().id.clone(),
        });
    }

    // Trigger 4: Adversarial-followup
    if let Some(unresolved) = open_hypotheses.iter().find(|h| {
        h.reopen_count >= 3 && h.candidate_count < 3
    }) {
        return Some(EscalationTrigger::AdversarialFollowup {
            hypothesis_id: unresolved.id.clone(),
        });
    }

    None
}

#[derive(Debug, Clone)]
pub enum EscalationTrigger {
    Stall { stalled_rounds: usize, vague_hypothesis_ids: Vec<String> },
    TieBreak { candidate_ids: Vec<String> },
    GateFlaw { finding_id: String },
    AdversarialFollowup { hypothesis_id: String },
}
```

When `detect_deep_review_escalation_trigger` returns `Some(trigger)`, the orchestrator:

1. STOPS routine Phase 11 progression.
2. Requires USER AUTHORIZATION (an escalation burns 5+ panes × multi-hour budget — never self-authorize).
3. Dispatches `subagents/deep-hypothesis-reviewer.md` with the trigger details.
4. Waits for the review verdict (`RESOLVED | REOPENED | KILLED`).
5. Integrates the verdict back into the appropriate hypothesis ledger.
6. Resumes Phase 11 with the resolved state.

## Variants

### Per-trigger variant

- **Stall** dispatches a 5-pane review pipeline: proposer + 2 investigators + devil's-advocate + synthesizer.
- **Tie-break** dispatches a 3-pane design-review pipeline focused on adjudication.
- **Gate-flaw** dispatches a 6-pane incident-RCA pipeline.
- **Adversarial-followup** dispatches the squad pipeline with productive-ignorance roster bias (1 extra `⊚` pane).

### Per-pillar variant

The contested question's pillar (perf | conformance | surface | cross-pillar) determines which ledger receives the verdict. Cross-pillar escalations write to all three ledgers + the GAUNTLET_EXPERIMENT_DESIGNS.md master.

## Failure modes

- **Self-authorization** — orchestrator escalates without user signoff. NEVER allowed. Authorization is the cost-control gate; escalations are expensive.
- **Vague trigger description** — escalating with "the loop is stuck somewhere in conformance" wastes the review budget. The trigger MUST name a specific question, specific candidates, specific finding-ID, or specific hypothesis-ID.
- **Verdict never integrated** — review produces `RESOLVED` artifact at `<workspace>__deep_review/deliverables/ARTIFACT.md`, but the gauntlet's hypothesis ledger never picks it up. Hash with `subagents/deep-hypothesis-reviewer.md`'s integration step; verify via `<workspace>/phase11_deep_review_<trigger>.md` exists post-escalation.
- **Recursive escalation** — the review produces `REOPENED`, then the same trigger fires again next round. The 2nd escalation requires re-authorization (no auto-re-escalate). If 3rd escalation fires, the question is genuinely under-specified — fall back to user.
- **Premature escalation** — trigger fires on round 2 of a stall instead of round 3. The "3 consecutive rounds" rule is a guard against impatience; don't pre-empt it.

## Cross-references

- [`methodology/DEEP-HYPOTHESIS-REVIEW.md`](../methodology/DEEP-HYPOTHESIS-REVIEW.md) — full review kernel + operator algebra.
- [`subagents/deep-hypothesis-reviewer.md`](../../subagents/deep-hypothesis-reviewer.md) — the subagent that owns the escalation lifecycle.
- [`methodology/DECISION-TREES.md § DT-4 When to escalate to a deep review?`](../methodology/DECISION-TREES.md) — operator-facing decision tree.
- [`subagents/iteration-coordinator.md`](../../subagents/iteration-coordinator.md) — owns Phase 11; calls `detect_deep_review_escalation_trigger` at round close.
- [`pattern:270-PRODUCTIVE-IGNORANCE-INJECTION`](270-PRODUCTIVE-IGNORANCE-INJECTION.md) — the `⊚` operator the squad often uses.
- [`pattern:275-THEORY-KILL-IMMEDIATE-CLOSE`](275-THEORY-KILL-IMMEDIATE-CLOSE.md) — the `†` operator the squad invokes on refuted hypotheses.
