# QUESTION-ARCHETYPES.md — Question-Shape Taxonomy + Methodology Tuning

<!-- TOC: A1 Design-space exploration (deeper) | A2 Codebase weakness audit (deeper) | A3 Methodology distillation (deeper) | A4 Production incident root-cause (deeper) | A5 Comparison/benchmarking (deeper) | A6 Adversarial design audit (deeper) | A7 Decision under uncertainty (deeper) | A8 Resume/second-pass (deeper) | A9 Methodology drift check (deeper) | A10 First-principles synthesis (deeper) | How to extend the catalog -->

ARCHETYPE-START-PACKS.md focused on *configuration defaults* per archetype. This file goes deeper: for each archetype, the methodology-level tuning — which operators emphasize, which anti-patterns to anticipate, which sub-question to derive if the user's framing is too broad.

---

## A1 — Design-space exploration (deeper)

### Question shape
"What's the best <X> for <use case Y>?"

### Sub-question derivation
If user gives "what's the best X" without `Y`, derive sub-questions:
- **Workload-conditional sub-Q:** "What's the best X under workload class W₁ ... W_n, where W_i = {<concrete constraint>}?"
- **Goal-conditional sub-Q:** "What's the best X if we maximize metric M₁ vs M₂ vs M₃?"

The derivation is itself a Phase 1 framing exercise. Don't accept "best X" without conditions.

### Operator emphasis
- ⌂ (materialize): every candidate must come with concrete observable predictions per workload class
- ⟂ (transpose): pick small benchmark proxy, not full real workload
- ↑ (amplify): find the regime where candidates differ ≥10×
- ⊞ (scale): verify physics permits each candidate at target scale

### Phase 6 distillation form
"Best for W₁ is X; best for W₂ is Y; best for W₃ is Z. The boundaries are at <thresholds>." Workload-conditional answers are the typical convergence.

### Anti-patterns to anticipate
- Operator: "X is just better." (No workload condition → F-101)
- Investigator: "I read all the literature on X." (Not investigation; reading without falsifier probing → F-403)
- Adjudicator: "I prefer X." (Rhetoric → F-503)

---

## A2 — Codebase weakness audit (deeper)

### Question shape
"Where are the load-bearing weaknesses in <codebase>?"

### Sub-question derivation
If user asks about weakness without scope:
- **Subsystem sub-Q:** "Which subsystems have the most load-bearing weaknesses?"
- **Failure-mode sub-Q:** "What failure modes (correctness, performance, security, scale) have the most weaknesses?"
- **Layer sub-Q:** "At which layer (API, transport, storage, scheduling) are weaknesses concentrated?"

### Operator emphasis
- ⌂ (materialize): every weakness claim must cite `<file>:<line>`
- ✂ (exclusion): every weakness claim must specify `<observation>` that, if seen, kills it
- ⊞ (scale): every "scale" weakness must show actual math
- 🔧 (DIY): investigators write quick scripts in `deliverables/scripts/` to probe weaknesses

### Phase 6 distillation form
"Top-N weaknesses ranked by exploit-likelihood × blast-radius, each with falsifier-grade EV citing file:line."

### Anti-patterns to anticipate
- Investigator: "the architecture is bad" (no falsifier → F-303)
- Devil's-Advocate: hand-wavy security concerns (F-503)
- Audit: re-investigates rather than audits (AP-O07)

---

## A3 — Methodology distillation (deeper)

### Question shape
"Distill methodology of <expert/domain> from these <N> sources."

### Sub-question derivation
- **Operator-set sub-Q:** "What are the cognitive operators that <expert> repeatedly applies?"
- **Failure-mode sub-Q:** "When does the methodology NOT apply, per the corpus?"
- **Bayesian-substrate sub-Q:** "What prior weights does the methodology imply?"

### Operator emphasis
- ≡ (invariant): the kernel is the invariants
- ⊘ (level-split): disagreements about *level* are common
- 🤝 (GAN): Phase 5 debates between distillation perspectives are critical

### Phase 6 distillation form
Mirrors this skill's own structure: corpus → quote bank → triangulated kernel → operator library → validators. The artifact is a Track A operationalization of the methodology.

### Anti-patterns to anticipate
- Synthesizer: averages distillations into bland consensus (F-601)
- Meta-synthesizer: dominates with one family (F-602)
- Drift: produces a methodology that diverges silently from the corpus (F-1002)

---

## A4 — Production incident root-cause (deeper)

### Question shape
"What is the root cause of <incident>?"

### Sub-question derivation
- **Causal-chain sub-Q:** "What was the immediate trigger?"
- **Layer sub-Q:** "Which subsystem did the trigger fire in?"
- **Repeatability sub-Q:** "Could this happen again under the same conditions?"

### Operator emphasis
- ⌂ (materialize, tight): falsifier from <30 min log scanning
- ✂ (exclusion, tight): "if log entry X is present, root cause is not Y"
- 🤝 GAN compressed: investigator + devil's-advocate paired

### Phase 6 distillation form
SKIPPED — incident-investigation mode skips Phase 6. INCIDENT-VERDICT.md is the output.

### Anti-patterns to anticipate
- Investigator: "could be A or B or C" (no falsifier-firing evidence → re-run)
- Operator: closes incident on rhetoric ("looks like A") without falsifier on B/C

---

## A5 — Comparison/benchmarking (deeper)

### Question shape
"Compare <X> and <Y> on <criteria C>."

### Sub-question derivation
- Force `C` to be specific. "Better" without `C` → F-101.
- Workload-conditional: "Compare on C across workload classes W₁..W_n."

### Operator emphasis
- ⟂: pick benchmark proxy per workload class
- ↑: find the regime where C differs ≥10×
- ⊞: verify benchmark conditions are physically realistic

### Critical guard
Force MO-03c-third-alternative.md early. Most "X vs Y" questions hide a Z that's better than both for some workload — make Z explicit.

### Phase 6 distillation form
Workload-conditional matrix. Per-workload winner cited with EV.

### Anti-patterns
- Comparison without C → F-101
- Comparison that ignores the third alternative → F-301
- Benchmarks at non-realistic scales → F-1002 in drift check

---

## A6 — Adversarial design audit (deeper)

### Question shape
"Find every way <design> could fail."

### Special framing
The Falsifier here is the ZERO-finding case: "the design has no load-bearing weaknesses" — i.e., we EXPECT to find weaknesses; failing to find any IS the falsifier-firing condition (the design is unusually robust, or the audit is shallow).

### Sub-question derivation
- **Adversary-class sub-Q:** "What adversary types?" (passive observer, active attacker, malicious insider, physical adversary, regulatory adversary)
- **Failure-class sub-Q:** "What failure classes?" (correctness, security, scale, regulatory, social)

### Operator emphasis
- ✂ (exclusion): exhaustive forbidden-pattern enumeration
- ΔE (anomaly): anomalies in design behavior are starting points for attacks
- ⊕ Cross-Domain (subsumed under ⊙): apply known attack patterns from adjacent domains
- Run TWO Devil's-Advocate panes (per ARCHETYPE-START-PACKS.md A6)
- Run `subagents/red-team.md` for novel attacks

### Phase 6 distillation form
Threat catalog: each threat with `attack:`, `precondition:`, `evidence_to_confirm:`, `severity:`, `recommended_remediation:`.

### Anti-patterns
- Devil's-Advocate kills everything rhetorically (F-501)
- Audit phase generates surface-only critiques (F-702)
- Threat catalog conflates "could happen in theory" with "could happen given these conditions"

---

## A7 — Decision under uncertainty (deeper)

### Question shape
"Should we do X or Y?"

### Sub-question derivation
- **Decision-rule sub-Q:** "What observation would change the recommended choice?"
- **Time-horizon sub-Q:** "Decide for what horizon (<1 month, 1-12 months, >12 months)?"
- **Reversibility sub-Q:** "Reversible if wrong, or one-way?"

### Operator emphasis
- ⊘ (level-split): "should we" is often two questions (technical: can we? values: should we?)
- ◊ (paradox-hunt): the decision is hard precisely because there's a tension
- ↑ (amplify): find the regime where the choice clearly matters

### Phase 9 form
Decision memo: recommendation, reasoning, key uncertainties, what-would-change-the-recommendation, dissenting opinions surfaced from disagreement_register.md.

### Anti-patterns
- Decision-rule absent → F-101 variant
- Memo without dissents → F-601 (silent averaging)
- Recommendation without time-horizon scope

---

## A8 — Resume/second-pass (deeper)

### Question shape
"Resume <session>" or "Run another pass on <workspace>."

### Special framing
Question of record is FROZEN per RESUME.md. Phase 1 is skipped. The "second pass" is *not* a new framing — it's the same question with fresh evidence.

### Operator emphasis
- ∿ Dephase (was first pass in-phase with consensus that didn't deserve it?)
- ΔE (anomalies quarantined in pass 1 may now cluster)
- Rotate model families if possible — fresh perspective

### Phase 9 form
Updated HANDBACK.md with diff vs prior pass: what changed, what stabilized, what's newly open.

### Anti-patterns
- Treat resume as new session (skip Phase 1 reset; honor the frozen QoR)
- Don't rotate model families (pass 2 inherits pass 1's blind spots)
- Re-create Agent Mail threads with new IDs (AP-O10)

---

## A9 — Methodology drift check (deeper)

### Question shape
"How did our last session diverge from canonical Brenner?"

### Sub-question derivation
- **Operator-coverage sub-Q:** "Which operators fired? Which didn't?"
- **Phase-ordering sub-Q:** "Was canonical phase order followed?"
- **Invariant-compliance sub-Q:** "Did mandatory invariants hold?"

### Operator emphasis
- ∿ Dephase (was the session in-phase with prior session framings?)
- ◊ Paradox-Hunt (between intended trajectory and actual)

### Phase 9 form
DRIFT-CHECK.md only. No HANDBACK.md needed.

### Anti-patterns
- Audit by swarm pane (AP-O11) — must be fresh general-purpose Agent
- Rationalize drift as improvement without Replacement Test (F-1001)
- Skip lessons step (F-1003)

---

## A10 — First-principles synthesis (deeper)

### Question shape
"What does first-principles say about <X>?"

### Special framing
Corpus is DELIBERATELY MINIMAL — only the question of record. Hypothesis space comes from panes' first-principles reasoning.

### Operator emphasis
- ⊙ Productive-Ignorance (the load-bearing operator)
- ⊞ Scale-Check (first-principles claims must hold up to scale)
- 𝓛 Recode (finding the right encoding is the move)

### Roster
Pair to Squad, with strong productive-ignorance — designate ≥2 panes as ⊙ panes (very unusual; most archetypes designate 1).

### Phase 6 form
"From <small set of axioms>, the following claims follow: <list>. The argument structure is: <chain>."

### Anti-patterns
- Panes secretly read corpus despite ⊙ assignment
- First-principles claims that violate scale-check (vapor reasoning)

---

## How to extend the catalog

When a session reveals a new archetype not above:

1. Document the question shape with ≥3 trigger phrasings
2. Document sub-question derivation rules
3. Document operator emphasis (which of the 15)
4. Document the typical Phase 6 / 9 distillation form
5. Document anti-patterns specific to this shape
6. Add an entry to ARCHETYPE-START-PACKS.md with default configuration

Phase 10 drift-check often surfaces new archetypes. Each new archetype represents a stable pattern of *question shape* that warrants calibrated start.
