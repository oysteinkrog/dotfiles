# EXTENDED-PROJECT-TYPES.md — Research Domain Adjustments

<!-- TOC: How to use | Software engineering domains | Hardware / systems domains | Biology / chemistry / health | Social science | Policy / governance | Markets / economics | Pure mathematics | Multi-domain -->

The skill works across many research domains. This file documents domain-specific adjustments — which operators emphasize, which corpus types are typical, which failure modes are common per domain.

Mirrors documentation-website's PROJECT-TYPES.md and EXTENDED-PROJECT-TYPES.md.

---

## How to use this file

When framing a session, identify the domain. Apply the domain-specific adjustments alongside the archetype-specific ones (per QUESTION-ARCHETYPES.md). They compose.

---

## Software engineering — backend systems

**Typical archetypes:** A1 (design-space), A2 (codebase weakness), A6 (adversarial), A7 (decision)

**Operator emphasis:**
- ⊞ Scale-Check is dominant — backend decisions often hinge on bandwidth/latency/cost/throughput math
- ⌂ Materialize → cite specific file:line + commit SHA
- 🔧 DIY → spike scripts in `deliverables/scripts/` are encouraged

**Corpus typical:**
- Source code (with git pin)
- Issue tracker / ADR repo
- Benchmark literature
- Vendor documentation (volatile-source caveat per VERIFICATION-FIRST.md)

**Common failure modes:**
- F-303 (unfalsifiable: "scalability is bad" without specific metric)
- F-401 (evidence inflation: code review without falsifier-firing)
- F-407 (quickie misinterpreted: micro-benchmark vs production behavior)

---

## Software engineering — frontend / UX

**Typical archetypes:** A1, A7

**Operator emphasis:**
- ↑ Amplify is harder — UX outcomes are often subtle; force binary readouts via A/B tests when possible
- ⊘ Level-Split — separate "user perception" from "system behavior"; they're different roles

**Corpus typical:**
- Design system docs
- User research transcripts
- Heatmaps / analytics dashboards (volatile)
- Competitor analysis

**Common failure modes:**
- Vibes-based confidence ("users will love it") without falsifier
- Confusing "I think this is better" with "users measurably prefer this"

**Adjustment:** for UX questions, falsifier should reference specific user-observable behavior, not designer intuition.

---

## Hardware / systems

**Typical archetypes:** A1, A2, A6

**Operator emphasis:**
- ⊞ Scale-Check is critical (physics actually constrains)
- ⟂ Object-Transpose: simulation > FPGA prototype > real silicon
- 🔧 DIY: investigators may design custom benchmarks

**Corpus typical:**
- Datasheets
- Spice simulations
- Existing firmware
- Benchmark suites

**Common failure modes:**
- Confusing simulation behavior with real silicon (level-split missed)
- Scale assumptions broken at extreme conditions (temperature, voltage, frequency)

**Adjustment:** Phase 7 audit must include explicit "does this hold at corner conditions?" check.

---

## Biology / chemistry / health

(The original domain of Brenner's method, though the skill is tool-agnostic.)

**Typical archetypes:** A1, A3, A4 (incident = adverse event), A5

**Operator emphasis:**
- ⌂ Materialize: "what experiment / observation"
- ✂ Exclusion-Test: forbidden patterns (Brenner's home turf)
- ⟂ Object-Transpose: model organism / cell line / in-silico
- ⊞ Scale-Check: physiological / molecular scale

**Corpus typical:**
- Peer-reviewed literature (with retraction-watching)
- Clinical trial data
- Lab notebooks
- Database queries (UniProt, GenBank, PubMed)

**Common failure modes:**
- Reproducibility crisis-type issues (single-source EV; no replication)
- p-hacking (post-hoc hypothesis re-framing) — mitigated by hypothesis-pre-registration mode
- Ethical considerations not flagged

**Adjustment:** prefer hypothesis-pre-registration mode for any T4+ biology session. Explicit ethical-review section in HANDBACK.md.

---

## Social science

**Typical archetypes:** A3 (methodology distillation), A5 (comparison), A7 (decision)

**Operator emphasis:**
- ⊘ Level-Split: individual vs aggregate behavior is THE common confusion
- 𝓛 Recode: framing matters enormously; multiple coordinate systems are usually informative
- ⊕ Cross-Domain (under ⊙): import patterns from adjacent fields liberally

**Corpus typical:**
- Survey data
- Ethnographic studies
- Historical records
- Cross-cultural comparisons

**Common failure modes:**
- WEIRD (Western, Educated, Industrialized, Rich, Democratic) sampling bias unflagged
- Causal claims from observational data without proper controls
- Replication across contexts assumed without testing

**Adjustment:** for social science, mandatory `assumption.type:methodological` bead documenting the sampling frame and known biases. Phase 7 audit verifies.

---

## Policy / governance

**Typical archetypes:** A7 (decision), A6 (adversarial — "what could go wrong with this policy")

**Operator emphasis:**
- ⊞ Scale-Check: policy implications across population sizes, time horizons
- 🤝 GAN: stakeholder dissent is the substrate
- ∿ Dephase: avoid in-phase consensus that policy will succeed

**Corpus typical:**
- Existing policy documents
- Implementation case studies (other jurisdictions)
- Stakeholder interview transcripts
- Cost-benefit analyses

**Common failure modes:**
- Goodhart's law (metric-gaming) unflagged
- Second-order effects ignored
- Reversibility under-analyzed (policies are sticky)

**Adjustment:** mandatory MO-emergency-stop.md-like decision-rule "what observation, if seen post-implementation, would trigger reversal?" — documented in DECISION-MEMO.md.

---

## Markets / economics

**Typical archetypes:** A1, A5, A7

**Operator emphasis:**
- ⊞ Scale-Check: arbitrage closes at scale; what works at small scale doesn't survive
- 𝓛 Recode: financial framing has many coordinate systems (price, volatility, liquidity, risk)
- 🤝 GAN: adversarial pricing / game-theoretic considerations

**Corpus typical:**
- Market data (volatile! per VERIFICATION-FIRST.md)
- Academic finance literature
- Regulatory filings
- Historical scenarios

**Common failure modes:**
- Survivorship bias in historical analysis
- Reflexivity (the analysis itself changes the market)
- Black swan tail risk under-weighted

**Adjustment:** living-review mode (per EXTENDED-OPERATING-MODES.md) is often appropriate for ongoing market questions.

---

## Pure mathematics / theoretical CS

**Typical archetypes:** A10 (first-principles), A3 (methodology distillation)

**Operator emphasis:**
- ≡ Invariant-Extract is the dominant operator (mathematical invariants)
- 𝓛 Recode: change of representation often unlocks the proof
- ⊙ Productive-Ignorance: novelty often comes from approaching with diffuse priors

**Corpus typical:**
- Theorems, proofs
- Counter-examples
- Open problems lists
- Reference monographs

**Common failure modes:**
- Hand-wavy proof sketches accepted as evidence (must cite full proof or specific known result)
- Generalization claimed beyond what's proved

**Adjustment:** for math, "evidence" means *proof*, not "I think this works". Phase 4 Investigators must produce verbatim theorem statements with rigorous citation.

---

## Machine learning / AI research

**Typical archetypes:** A1, A2, A5, A6

**Operator emphasis:**
- ⊞ Scale-Check: behavior at training-distribution vs out-of-distribution
- ⟂ Object-Transpose: small-scale proxy → full-scale (with caveats — proxies often mislead)
- ✂ Exclusion-Test: ablation studies as falsifier-probing

**Corpus typical:**
- Papers (volatile — preprints update)
- Benchmark leaderboards (volatile)
- Open-source models / code
- Internal training runs

**Common failure modes:**
- Cherry-picked benchmarks (Goodhart's-law for benchmarks)
- Generalization claims from a single training run
- Confusion between "model behavior" and "training procedure" (level-split)

**Adjustment:** for ML, mandatory `EV-*` for benchmark claims must include seed + hyperparameters. Reproducibility caveats in HANDBACK.md.

---

## Multi-domain

When a question spans multiple domains, apply the most-restrictive adjustments from each domain:

- Software + ML → both file:line citations AND seed/hyperparameter requirements
- Biology + Policy → both pre-registration AND ethical-review section
- Social science + Markets → both sampling-frame documentation AND volatile-source caveat

Multi-domain questions often warrant Swarm tier even if individual archetypes wouldn't, because triangulation across domain perspectives is valuable.

---

## Domain-specific corpus types

| Domain | Primary corpus type | Anchor scheme | Verification class |
|--------|---------------------|---------------|--------------------|
| Backend | source code repos | §-per-line-range | versioned |
| Frontend | design system + analytics | §-per-section + dashboard | mixed (frozen + live) |
| Hardware | datasheets + simulations | §-per-section | versioned |
| Biology | papers + databases | §-per-paragraph | mostly frozen + DB queries (live) |
| Social | papers + interview transcripts | §-per-section | frozen |
| Policy | policy docs + case studies | §-per-section | frozen + occasional updates |
| Markets | papers + market data | §-per-section + tickers | mixed (frozen academic + live data) |
| Math | theorems + texts | §-per-claim | frozen |
| ML | papers + benchmarks + repos | §-per-section + benchmark | mixed (volatile) |

Per CORPUS-CURATION.md (and corpus-curator.md subagent), the curator assigns the appropriate scheme + class.

---

## Adding new domains

When a session reveals a domain not above:

1. Document trigger phrasings (≥3)
2. List operator emphasis (which of the 15 are dominant)
3. List typical corpus types
4. List common failure modes (with F-### codes)
5. Recommend adjustments

Phase 10 drift-check should propose new domain entries when patterns emerge.

---

## Domain × archetype × tier

Most session configurations are: domain × archetype × tier. A T3 backend A1 design-space question has different defaults than a T3 social-science A3 methodology question.

The operator picks all three at Phase 0; the configurations compose. Conflict resolution:

- If domain says "use mode X" and archetype says "use mode Y", domain usually wins (domain is more about *substance*, archetype about *shape*).
- If archetype says "Squad tier" and domain says "Swarm tier", tier wins (tier reflects stakes).
- If multiple modes apply, run them sequentially (e.g., hypothesis-pre-registration first, then standard fresh-question for Phase 4+).

These are heuristics; the operator can override with documented reasoning.
