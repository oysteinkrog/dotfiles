# advanced-methods-miner

> Phase 10 • Mine public literature, known systems techniques, and advanced mathematical tools for port-specific gauntlet ideas that match the current residual gaps.

## Inputs
- Phase 9 baseline outputs + Phase 10 idea-wizard output.
- The port's residual-gaps list (from `phase9_baseline_*.md` files).
- Project class.

## Deliverables
- `<workspace>/phase10_advanced_methods_round_<round>.md` with: candidate systems techniques filtered for relevance to the port, frontier-math suggestions relevant to the port, promotion decisions, and experiment-design entries appended to `GAUNTLET_EXPERIMENT_DESIGNS.md`.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase10-advanced-methods`
- **Reservations needed:** `tool://advanced-methods-mining` (TTL 60m), `tool://frontier-math-compilation` (TTL 60m).
- **Lane:** cross-cutting.

## Verbatim Prompt

Run the advanced-methods mining pass with the following framing:

> Apply a broad public catalog of systems techniques and research ideas to this port. The port is a Rust reimplementation of `<reference>` (`<class>` class). Focus on primitives matching the port's residual gaps: hotspots that exceed 0.1% MT8 self-time but resist the obvious optimizations; conformance divergence classes the metamorphic + property + fuzz layers can't bound; surface-coverage blind spots where the reference has decades of accumulated subtlety.

Capture the candidate list (full enumeration). For each candidate, score on a fixed rubric:
- **Hotspot match** — does the candidate target a real frame ≥ 0.1% in our baseline? (0–3)
- **Soundness** — is the primitive provably behavior-preserving? (0–3)
- **Implementation cost** — line-count + new-dependency estimate? (0–3, inverted)
- **Verification difficulty** — can we prove the rewrite is isomorphic with the existing oracle? (0–3)
Sum: ≥8 → promote; 5–7 → conditional (note in ledger); <5 → reject.

Then run the frontier-math compilation pass with this prompt:

> TRULY think even harder. Frontier models know far more mathematics than most projects ever ask for. Surface frontier-math compilations relevant to this port's gauntlet: where could anytime-valid sequential testing, conformal prediction, BOCPD, e-processes, submodular optimization, PAC-Bayes generalization bounds, Little's-Law + MPC, Lai-Robbins bandit lower bounds, or renewal-reward processes help the gauntlet detect a regression / refine a gate / tighten a ratchet / accelerate convergence?

Capture the frontier-math suggestions. For each, score on:
- **Math soundness** — is the theorem applicable here? (0–3)
- **Practical relevance** — does it help an actual gauntlet decision? (0–3)
- **Implementation cost** — how many lines + how much engineer-time? (0–3, inverted)
Sum: ≥6 → promote.

For every promoted candidate (from both invocations), append a full experiment-design entry to `GAUNTLET_EXPERIMENT_DESIGNS.md` using `../assets/experiment-design-template.md`. Mark `OPEN`; the iteration loop will resolve to `CONFIRMED_GAP | NO_EVIDENCE | NEEDS_REFINEMENT | NEW_HYPOTHESIS_SPAWNED`.

**Bias note:** systems-method mining tends to surface algorithmic primitives (database cracking, cooling, learned indexes, ARC, SSI, epoch-based reclamation). Frontier-math compilation tends to surface mathematical scaffolding (Ville's inequality, conformal bands, BOCPD, e-processes, PAC-Bayes, Azuma). Both are valuable; both should be searched every round.

Document everything in `phase10_advanced_methods_round_<round>.md`.

## Exit Criteria
- Advanced-methods candidate list captured.
- Frontier-math list captured.
- Every promoted candidate has an experiment-design entry in `GAUNTLET_EXPERIMENT_DESIGNS.md`.
- Conditional candidates recorded in the per-round markdown for re-evaluation in subsequent rounds.
- `phase10_advanced_methods_round_<round>.md` committed.

## References
- [PHASES.md § Phase 10](../references/PHASES.md)
- [exemplars/EXEMPLARS.md § skill→module mapping](../references/exemplars/EXEMPLARS.md)
- [methodology/OPERATORS.md § Experiment-Design](../references/methodology/OPERATORS.md)
- [experiments/EXPERIMENT-DESIGNS-TEMPLATE.md](../references/experiments/EXPERIMENT-DESIGNS-TEMPLATE.md)
