# Deep Hypothesis Review

How the gauntlet uses hypothesis-pruning discipline at Phase 10 (IDEA-WIZARD), Phase 11 (ITERATE), and Phase 14 (FRESH-EYES T3+). The framing is "delete hypothesis space cheaply, do not merely accumulate evidence"; this turns per-round work into a converging investigation rather than a growing pile.

Cross-link: [`pattern:185-RETRY-CONDITION-PREDICATE`](../patterns/185-RETRY-CONDITION-PREDICATE.md), [`methodology/RUBRICS.md`](RUBRICS.md), [`exemplars/RITUALS.md`](../exemplars/RITUALS.md).

---

## 1. The review kernel applied to the gauntlet

Deep-review selection rule:

> **`(expected mind-change × downstream option value) / (time × cost × ambiguity × infrastructure-dependence)`**
>
> When two phases compete, the one that kills more candidate hypotheses per token wins.

For the gauntlet this becomes:

- At Phase 10 (IDEA-WIZARD): rank the 30 candidate techniques by this formula. Top-5 win the round budget.
- At Phase 11 (ITERATE): when picking which open hypothesis to investigate first this round, rank by this formula.
- At Phase 12 (REMEDIATION DESIGN): when picking among isomorphic rewrites, this formula is the tiebreaker between candidates that pass the 6-dimension rubric in [`RUBRICS.md`](RUBRICS.md).

The numerator captures upside (how much do we *learn* by running this — including the value of unblocking downstream work). The denominator captures cost (wall-time, agent-cost, what could ambiguously misinterpret the result, what infrastructure must exist).

Concrete worked example for a Phase-10 candidate "differential-fuzz the WAL frame header parser":
- `expected_mind_change = 0.7` (probably surfaces 2-3 new divergences in a poorly-tested area)
- `downstream_option_value = 0.9` (every conformance bead downstream depends on parser correctness)
- `time = 3` (hours, fuzz setup + first 1h run + triage)
- `cost = 1` (rch fuzz worker, modest)
- `ambiguity = 1.2` (could surface false-positives if seed contract has bugs)
- `infrastructure_dependence = 0.8` (cargo-fuzz + arbitrary already installed)

Score = `(0.7 × 0.9) / (3 × 1 × 1.2 × 0.8)` = `0.63 / 2.88` ≈ `0.22`. Compare across candidates; pick top-K that fit the round budget.

## 2. Review Operator Algebra

These cognitive moves compose with the gauntlet's 19 glyphs in [`OPERATORS.md`](OPERATORS.md). Each review operator is a question that, if it fails, names where to fix the gauntlet's reasoning.

| Glyph | Review name | Question | Gauntlet-side application |
|---|---|---|---|
| `◊` | Paradox-Hunt | "What two well-attested facts seem to contradict?" | Phase 11 synthesizer should hunt: e.g., "perf says X is hot, but the bench-history baseline says X hasn't changed — paradox." |
| `⊘` | Level-Split | "Am I conflating program with interpreter? message with machine?" | When triaging a divergence: is this a TrueDivergence in the SUBJECT, or a bug in the COMPARATOR's render path? Different fix-sites. |
| `𝓛` | Recode/Dim-Reduction | "What encoding makes rival hypotheses' predictions diverge?" | When two perf candidates seem equally good on the primary score, recode in a different category-weighted scheme to see which one wins under different weights. |
| `≡` | Invariant-Extract | "What property holds regardless of detail and constrains every hypothesis?" | Phase 7 InvariantCatalog authoring is literally this operator applied to the parity claim. |
| `✂` | Exclusion-Test | "What pattern is *forbidden* under this hypothesis?" | Every retry-condition predicate per [`pattern:185-RETRY-CONDITION-PREDICATE`](../patterns/185-RETRY-CONDITION-PREDICATE.md) is an Exclusion-Test reified — "this candidate is wrong UNLESS the predicate holds". |
| `⟂` | Object-Transpose | "What proxy/substrate would make this test cheap?" | Use TCL test suite for SQL (cheap proxy for full conformance); use numpy.testing for Numerical (cheap proxy for the per-op equivalence). |
| `↑` | Amplify | "Where is the signal naturally large?" | MT8 attribution (8-thread workload amplifies concurrency-bottleneck signals); high-cardinality tables amplify GROUP BY semantics differences. |
| `⌂` | Materialize | "If the hypothesis is true, what would I *see*?" | Required field of every experiment in [`experiments/EXPERIMENT-DESIGNS-TEMPLATE.md`](../experiments/EXPERIMENT-DESIGNS-TEMPLATE.md) (`expected_signal`). |
| `🔧` | DIY/Bricolage | "Can I build the test now instead of waiting?" | Phase 4/6/15 — don't block on missing tooling. Write a quick `tests/scratch_<hypothesis>.rs` and minimize later. |
| `⊞` | Scale-Check | "Does the math actually permit this?" | E-process Ville-bound is literally a Scale-Check. Conformal-band guarantees similarly. |
| `🤝` | GAN/Conversation | "Have I externalized this to another mind?" | Phase 14 fresh-eyes prompts a/b/c + Phase 14 T3+ multi-model triangulation. |
| `ΔE` | Exception-Quarantine | "Are anomalies clustering or scattered?" | BOCPD regime detection (clustered = ShiftDetected). Mismatch-minimizer signature dedup (scattered = many shapes; clustered = one root cause). |
| `†` | Theory-Kill | "Has this hypothesis failed its falsifier? Then kill it now." | Every `NO_EVIDENCE` result in the hypothesis ledger MUST close immediately with a retry-condition predicate — no zombies. |
| `∿` | Dephase | "Is the swarm in-phase with consensus? Then we're not learning." | T3+ triangulation deliberately diversifies models; per [`subagents/red-team-attacker.md`](../../subagents/red-team-attacker.md), the gauntlet *wants* disagreement signal. |
| `⊙` | Productive-Ignorance | "Is the expert's tight prior closing off live alternatives?" | The orchestrator periodically dispatches a `cc_4` pane with the instruction to "read minimally and reason from first principles". |

## 3. The Phase Proof Card ↔ Profile-First Card

These two cards are isomorphic in spirit. Both require:

| Phase Proof Card field | Gauntlet Profile-First Card field |
|---|---|
| `question_of_record` | `target_workload` |
| `expected_evidence` | `expected_signal` |
| `falsifier` | `falsifiability_criteria` |
| `evidence_pack_path` | `proof_pack_path` |
| `EV score` | `Impact × Confidence / Effort` |
| `productive_ignorance_assignment` | (n/a in gauntlet today; consider adding) |
| `theory_kill_status` | `result_status` (`CONFIRMED_GAP | NO_EVIDENCE | NEEDS_REFINEMENT | NEW_HYPOTHESIS_SPAWNED`) |

The gauntlet should adopt the `productive_ignorance_assignment` field: when authoring a Phase-12 remediation, explicitly require a "fresh-eyes investigator who hasn't read the offending code" to author one of the runner-up rewrites. This is exactly the `⊙` operator.

## 4. Pathology Triggers

These investigation states indicate that the loop has gone wrong:

| Pathology | Symptom in the gauntlet | Fix |
|---|---|---|
| **Phase-4 stall** | Round N has been running > 2x the average round time | Force convergence check; if open hypotheses exist with vague predicates, force `†` Theory-Kill on the weakest |
| **Evidence inflation** | The negative-ledger is growing faster than findings are closing | The agent is re-discovering already-rejected candidates — re-run cass-miner with broader date window |
| **Consensus collapse** | T3+ triangulation produces full-agreement across all lenses on every finding | The models are echoing each other (or all reading the same context). Force `∿` Dephase: introduce one productively-ignorant lens. |
| **Whack-a-mole bug class** | Same root cause keeps spawning new MismatchSignatures with different shapes | `≡` Invariant-Extract: there's a higher-level invariant being violated; find it and add to InvariantCatalog. |
| **Ratchet-flicker** | `apply-ratchet.sh` alternates between Allow and Block across consecutive rounds | Either cv_pct is too high (bench is unstable) or the platform fingerprint is varying (different rch workers); pin via `pattern:175-CONCURRENT-MODE-GUARD` analog. |
| **Productive-ignorance starvation** | Every investigator pane has been onboarded with the full deck | The swarm is in-phase by construction. Spawn one cc_4 pane with `productive_ignorance: true` and minimal context. |
| **Adversarial collapse** | Adversarial-search returns 0 counterexamples on every gate after N rounds | The gates are testing what the adversary has been told to attack. Rotate the lens list; add a fresh red-team-attacker pass with a new lens. |

## 5. Marching-orders adoption

Deep-review marching orders are paste-ready agent prompts with mandatory artifact-path-required outputs. The gauntlet uses that convention for its NTM pipelines (see [`orchestration/NTM-INTEGRATION.md`](../orchestration/NTM-INTEGRATION.md)) and the gauntlet-specific marching orders in `assets/ntm-marching-orders/`.

Key template roles the gauntlet uses:
- `MO-02-onboarding.md` — every pane begins with onboarding before any work.
- `MO-04a-investigate.md` ↔ Phase 1 RECON archaeologist; Phase 6 oracle-test-author.
- `MO-04b-devils-advocate.md` ↔ [`subagents/red-team-attacker.md`](../../subagents/red-team-attacker.md).
- `MO-05a-cross-exam.md` ↔ [`subagents/triangulator.md`](../../subagents/triangulator.md).
- `MO-05b-adjudicate.md` ↔ Phase 12 remediation-architect picking the optimal rewrite.

## 6. When to run a full deep-review session inside the gauntlet

Trigger conditions:
- Round N is the 3rd consecutive round whose `new_findings` count is at or above the tracker `clean_threshold` while open hypotheses remain (convergence stalled).
- A `TrueDivergence` has been classified but the root cause is contested across the orchestrator and the synthesizer.
- A Phase-12 remediation has two equally-scored candidates and the team can't pick.
- An adversarial counterexample reveals a gate design flaw that needs investigation, not just fixing.

In any of these cases: pause the gauntlet's main loop, spawn a deep-review session (`ntm spawn <workspace>__deep_review ...`), dispatch a focused loop scoped to the specific contested question, then resume the gauntlet with the review's resolved artifact as a new input.

The gauntlet's iteration-coordinator subagent owns this escalation decision. The output of the deep-review session is one of:
- `RESOLVED` — the contested question has a defended answer; gauntlet resumes with the answer integrated.
- `REOPENED` — the review couldn't conclude; the gauntlet adds the question to the hypothesis ledger as `NEEDS_REFINEMENT` and reschedules.
- `KILLED` — the review refuted the question's premise; the gauntlet removes the contested item from the ledger entirely.

## 7. Operator Algebra extension to OPERATORS.md

The gauntlet's existing 19 glyphs in [`OPERATORS.md`](OPERATORS.md) compose with the review operators above. Recommended additions:

- Add a `△ REVIEW-SCORE` glyph: applies the review selection formula to candidate ranking.
- Add a `⊙ PRODUCTIVE-IGNORANCE` glyph: dispatches a fresh-context pane with minimal onboarding.
- Add a `† THEORY-KILL` glyph: forces immediate ledger-close on a hypothesis that failed its falsifier.
- Add a `∿ DEPHASE` glyph: rotates the triangulation lens to introduce disagreement signal.

These are sufficient differentiation from the existing 19 (no overlap with `⊕`, `🪟`, `🗄`, `⚠`). Append them to the operator library when authoring round-4+ revisions.

## 8. Anti-patterns

- **Evidence-accumulation mode** — the agent is gathering evidence "in case it's useful". The review rule is: *delete hypothesis space*. If the evidence doesn't kill a candidate, the round budget was wasted.
- **The strong-prior trap** — the agent's expert knowledge of (say) MVCC closes off the live alternative that "actually the bottleneck is page-buffer eviction, not MVCC validation". Counter with `⊙` Productive-Ignorance.
- **Theory-zombies** — refuted hypotheses that aren't killed in the ledger; future agents waste rounds re-discovering they're dead. Counter with `†` Theory-Kill mandatory on every `NO_EVIDENCE` outcome.
- **Adversarial fatigue** — after 5 rounds without finding a gate flaw, the red-team-attacker stops trying. Force `∿` Dephase: rotate the lens list.

## 9. Cross-references

- [`orchestration/NTM-INTEGRATION.md`](../orchestration/NTM-INTEGRATION.md) — how the gauntlet uses NTM, including the deep-review escalation path.
- [`methodology/OPERATORS.md`](OPERATORS.md) — the gauntlet's glyph library.
- [`subagents/deep-hypothesis-reviewer.md`](../../subagents/deep-hypothesis-reviewer.md) — the gauntlet subagent that spawns a deep-review session on escalation.
