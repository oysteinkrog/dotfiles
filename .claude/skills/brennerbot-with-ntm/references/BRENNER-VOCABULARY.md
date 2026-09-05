# BRENNER-VOCABULARY.md — Unified Glossary of Brenner-Method Terms

<!-- TOC: Why a vocabulary | Core conceptual primitives | Extended vocabulary from distillations | How to use this glossary | Phase-by-phase vocabulary application | Anti-vocabulary (terms to avoid) | Cross-references -->

The Brenner method has a *specific* vocabulary that distinguishes it from generic "good science." The terms below are the operational primitives. Every MO, every audit-finding, every HANDBACK should land its claims in this vocabulary — agents who use the vocabulary fluently catch failure modes that vague-prose agents miss.

Mined from `/dp/brenner_bot/README.md § Working Vocabulary`, the GPT-5.2 metaprompt tags, and the three expert distillations.

---

## Why a vocabulary

Without it, operators say "the experiment is well-designed" — vague. With it, they say "the test produces a digital handle that fires the falsifier under regime W (per ✂)" — verifiable.

Three concrete benefits:

1. **Cross-pane communication compresses.** A distilled term carries 5-10× the information of an English paraphrase.
2. **Failure modes become categorizable.** "Theory in 'Don't Worry' deferral mode without scale-check" is faster to diagnose than "the team made an unwarranted assumption about a mechanism."
3. **Cross-session pattern detection works.** Tagging beads with vocabulary terms lets `/cass` and `/flywheel` cluster across sessions semantically.

---

## Core conceptual primitives

### Brenner move

A recurring reasoning pattern (e.g., hunt paradoxes, invert the problem, pick the experimental object). Each Brenner move maps to ≥1 operator in OPERATORS.md. The "move" is the verb; the operator is the formal name.

### Decision experiment

An observation designed to *eliminate whole families of explanations at once*. Anti-pattern: experiments that confirm one hypothesis without ruling out alternatives. Decision experiments score high on KL divergence between competing hypotheses.

### Digital handle

A readout that is *effectively yes/no*: robust to noise, high leverage. Examples: "growth or no-growth on selective medium" (vs gradient measurement), "binary signal at p99" (vs noisy mean). Per Brenner's "seven-cycle log paper" test.

### Representation change

Restating the problem in a domain where constraints are clearer (e.g., logic/topology vs chemistry; algorithm vs implementation). Often reduces dimensionality. Operator: 𝓛 Recode.

### Assumption ledger

Explicit list of load-bearing assumptions + tests that would break them. Distinct from a generic "list of assumptions" because each entry includes a falsifier. Per Brenner's "House of cards" check (below).

### Third alternative

The "both models are wrong" option. Systematic guard against false dichotomies (see PHASE-1-ANTI-EXAMPLES.md AE-1.8). Per Brenner §103. Mandatory in Phase 3 (per F-301).

### Falsifier

The specific observation that, if true, refutes the hypothesis. Distinct from "evidence that disagrees" — a falsifier is the *observable* whose presence/absence makes the hypothesis untenable. Per ✂ Exclusion-Test.

---

## Extended vocabulary (from the three distillations)

### Abundance trick

Bypassing purification by choosing a system where the target dominates the signal (e.g., 50-70% of synthesis). Brenner exemplar: choosing organisms in which the desired molecule is plentiful enough to be detected without separation. **Modern translation:** select benchmarks where the signal-to-noise is high *by design*; defer signal-extraction work until the proof-of-concept lands.

### Dimensional reduction

Collapsing 3D physical problems into 1D informational problems. Brenner exemplar: DNA reduces biology from spatial nightmare to algebra. **Modern translation:** ML/systems-design questions about millions of parameters/states can sometimes be reduced to a 1D question (one decision rule that implicitly determines the rest). When you can do this, do it.

### Don't Worry hypothesis

Assume required mechanisms exist; proceed with theory development. Brenner exemplar: "Don't worry about unwinding; assume an enzyme exists." The theory then *generates predictions* that constrain the enzyme. **Anti-pattern guard:** "Don't Worry" must be paired with explicit `assumption_ledger` entries, NOT used to handwave permanently.

### Forbidden pattern

An observation that *cannot occur* if a hypothesis is true. Brenner exemplar: adjacent amino acid pairs forbidden under overlapping triplet code. **In brennerbot:** the falsifier-equivalent. A good forbidden pattern is concrete enough that a single observed instance refutes the hypothesis.

### Gedanken organism (Reconstruction standard)

Could you *compute* the animal from DNA sequences alone? The reconstruction-grade test. **Modern translation for code:** could you regenerate the system's behavior from the spec alone? If yes, the spec captures the essence. If no, the spec is incomplete.

### Generative grammar

The production rules that generate phenomena. Brenner's first axiom: "Reality has a generative grammar" — phenomena aren't catalogs of facts, they're outputs of a generator. **Modern translation:** look for the rules; the data is a fingerprint of the rules, not the rules themselves.

### House of cards

Theory with interlocking mutual constraints. If N predictions each have probability p, all N true has probability p^N. **Modern translation:** strong theories make MANY linked predictions whose joint probability is tiny under noise. Per BAYESIAN-FRAMEWORK.md.

### Imprisoned imagination

Staying within physical/scale constraints. "DNA is 1mm long in a 1μm bacterium, folded 1000×." **Modern translation:** every architectural argument should respect the calculation. ⊞ Scale-Check is the operator.

### Machine language

The operational vocabulary the system actually uses. For development biology: cells, divisions, recognition proteins — NOT gradients or differential equations. **Modern translation for code:** describe the system in *its* primitives (HTTP requests, queries, locks), not in *abstract* primitives (information flow, entropy).

### Materialization

Translating theory to "what would I see if this were true?" Per ⌂ Materialize. The compile-from-story to decision-procedure step.

### Occam's broom

The junk swept under the carpet to keep a theory tidy. "Count this, not entities." **Anti-pattern detection:** if your theory's explanatory simplicity comes from ignoring data, the simplicity is fake.

### Out of phase

Misaligned with (or deliberately avoiding) scientific fashion; "half a wavelength ahead or behind." **Modern translation:** when consensus collapses on one answer, check if you're in the herd or out of phase. Per ∿ Dephase.

### Productive ignorance

Fresh eyes unconstrained by expert priors. Experts have *overly tight* probability mass on known solutions; novices spread mass thinner. Per ⊙ in OPERATORS.md.

### Seven-cycle log paper

Brenner's test for qualitative, visible differences: "hold at one end of room, stand at other; if you can see the difference, it's significant." **Modern translation:** prefer effect sizes that don't need statistics. If your effect requires N=10000 and t-tests, you may be measuring something that won't generalize.

### Topological proof

Deducing structure from invariants rather than molecular details. Brenner exemplar: the triplet code from frameshift algebra. **Modern translation:** when you can constrain the answer using invariants (conservation laws, type signatures, algebraic constraints), trust those over phenomenology.

### Chastity vs impotence

Same outcome (no offspring), fundamentally different reasons. A diagnostic for *causal typing*. **Modern translation in brennerbot:** when two hypotheses predict the same observable, design the discriminator that separates them by mechanism, not by outcome.

### Anti-analogy

Reject "logical but non-natural" theories: when a metaphor seems too clean, it's probably misleading. Brenner exemplar: "Computation is not a perfect metaphor for cells; cells do strong analogue computation too." **Modern translation:** be suspicious of metaphors that work *too* well. Test that the load-bearing analogy is observable, not just suggestive.

### Plausibility filter

A constraint based on physics/scale that prunes hypothesis space *before* experimenting. Anti-pattern: "let's run all the experiments and see." With plausibility filtering, you cut hypothesis space from 1000 to 5 before any experiment.

---

## Domain-specific vocabulary

These are Brenner-domain (biology) but generalize:

### Quickie / pilot experiment

A cheap rapid probe before the flagship investigation. Per `MO-quickie-pilot.md`. Brenner ran "quickies" to de-risk the flagship: spend 30 min instead of 3 hours.

### Dominant-variable rescue

When the physical system is dominated by one parameter, push that parameter hard to make the discriminator obvious. **Modern translation:** find the load-bearing variable; vary it; ignore everything else first.

### Initiation vs continuation

The control point identification: is the regulator at *initiation* of a process or its *continuation*? Brenner exemplar: gene expression often has separate controls for "starting transcription" vs "elongating it." **Modern translation in code:** debugging often comes down to "did the operation start?" vs "did the operation continue?". Different bugs.

### Genetic dissection

Mutate the system to show what's required. Modern translation: ablation studies in ML; chaos engineering in distributed systems.

### Self-assembly

Components that organize themselves given local rules. Brenner exemplar: phage capsids self-assembling from subunits. **Modern translation:** systems where local rules produce global structure (gossip protocols, CRDT design, market-making).

### Special exemplar

A particular instance whose details unlock general understanding. Brenner exemplar: C. elegans as the "special exemplar" for development. **Modern translation:** the canonical test case that illuminates the general method (the "Hello World" but for non-trivial systems).

### Construction vs function

Describe HOW it's built (construction) vs WHAT it does (function). Brenner: "Don't be fooled by function; the construction is the explanation." **Modern translation:** systems documentation often describes function (what an API returns); brennerbot demands construction (how it's implemented, what invariants are preserved).

---

## Inversion + word play

### Inversion

Take the obvious problem, flip it. "If the obvious interpretation is wrong, what's the inverse?" Brenner exemplar: viewing nucleic acid as the encoder of protein, NOT the substrate.

### Puns and word play

Brenner used wordplay as a thinking technology. Modern translation: rename the problem; if you can't, you don't yet understand it.

### Open the box

When a system is opaque, *open the box* — find the grammar that generates its observable phenomena. Anti-pattern: treating the system as a sealed unit and only describing its outputs.

---

## How to use this glossary

### During Phase 1 framing

Use vocabulary to compress the question of record. Instead of:
> "We want to understand the cause-effect relationship between memory pressure and tail latency."

Write:
> "Hunt paradoxes around the apparent decoupling of memory pressure (continuous variable) and tail latency (digital handle). Apply ⊘ Level-Split between *initiation* (when pressure begins) and *continuation* (when latency degrades) regimes. House-of-cards check on the assumption ledger: which load-bearing assumptions about memory hierarchy persist across instances?"

### During Phase 4 investigation

Per OPERATOR-CARDS.md: when filing an EV, tag it with the vocabulary terms it exemplifies. The bead's `tags:` field accepts: `forbidden-pattern`, `digital-handle`, `dimensional-reduction`, `dont-worry`, etc.

### During Phase 7 audit

Audit panes scan the artifact for:
- "Don't Worry" used without a corresponding assumption ledger entry → audit-finding
- Theory described in operator-internal language without machine-language grounding → audit-finding
- Hypothesis with no forbidden pattern → audit-finding (F-103-class)
- Effect sizes requiring statistics for visibility → questionable digital-handle quality

### During Phase 9 HANDBACK

The HANDBACK should use vocabulary terms; per HANDBACK-VOICE-GUIDE.md, vocabulary-fluent prose compresses better.

### During Phase 10 drift

Drift auditor checks: did vocabulary fluency increase across the session? Sessions where evidence packs use ≥5 vocabulary terms have lower drift verdicts than sessions where panes use generic prose.

---

## Phase-by-phase vocabulary application

| Phase | Vocabulary terms most active |
|-------|-----------------------------|
| 1 framing | paradox, third alternative, decision experiment, digital handle, falsifier |
| 3 hypotheses | productive ignorance, ⊕ cross-domain import, third alternative, anti-analogy |
| 4 investigation | forbidden pattern, dimensional reduction, dominant-variable rescue, quickie pilot, House of cards |
| 5 debate | chastity-vs-impotence, theory-kill, falsifier-fired |
| 6 distillation | machine language, generative grammar, gedanken organism, topological proof |
| 7 audit | Occam's broom, plausibility filter, Don't Worry abuse, anti-analogy |
| 9 handback | inversion, materialization, construction-vs-function (for HANDBACK reasoning) |

---

## Anti-vocabulary (terms to avoid)

The Brenner method specifically rejects:

- **"Best practice"** — implies one optimum; Brenner method admits multiple correct answers under different regimes
- **"It seems"** / **"perhaps"** — hedging without evidence; per HANDBACK-VOICE-GUIDE.md
- **"All things considered"** — vague aggregation
- **"In some sense"** — weasel phrase; specify the sense
- **"More or less"** — quantify or omit
- **"Looking holistically"** — opposite of Brenner; he reduced and split, didn't aggregate
- **"Holistic methodology"** — also opposite; Brenner method is *reductive* (find the load-bearing factor)

A pane that reaches for these phrases is signaling lack of grounding. Per Red-Flag Phrases in SKILL.md.

---

## Composition with operators

| Vocabulary term | Maps to operator(s) |
|-----------------|----------------------|
| Decision experiment | ✂ Exclusion-Test, ⌂ Materialize |
| Digital handle | ✂ + ⌂ + ⊞ Scale-Check |
| Representation change | 𝓛 Recode |
| Assumption ledger | ≡ Invariant-Extract + ⊞ Scale-Check |
| Third alternative | ⊘ Level-Split + ⊕ Cross-Domain |
| Don't Worry | (defers to assumption ledger; no operator) |
| Forbidden pattern | ✂ Exclusion-Test |
| Gedanken organism | ⌂ Materialize + ≡ Invariant-Extract |
| House of cards | 🤝 GAN + ⊞ Scale-Check (joint-prediction probabilities) |
| Productive ignorance | ⊙ |
| Out of phase | ∿ Dephase |
| Quickie pilot | 🔧 DIY + ✂ |
| Dominant-variable | ⊞ + ↑ Amplify |
| Anti-analogy | ∿ Dephase + ◊ Paradox-Hunt |

The vocabulary IS the operator algebra in concrete, applied form.

---

## Cross-references

- [OPERATORS.md](OPERATORS.md) — formal operator algebra
- [OPERATOR-LIBRARY-COMPOSITION.md](OPERATOR-LIBRARY-COMPOSITION.md) — how operators compose
- [TEN-PRINCIPLES.md](TEN-PRINCIPLES.md) — compact summary of the method
- [BAYESIAN-FRAMEWORK.md](BAYESIAN-FRAMEWORK.md) — Brenner's implicit Bayesianism
- [REQUIRED-CONTRADICTIONS.md](REQUIRED-CONTRADICTIONS.md) — the operator's required oscillations
- [QUOTE-BANK-METHODOLOGY.md](QUOTE-BANK-METHODOLOGY.md) — how this vocabulary anchors back to verbatim quotes
- /dp/brenner_bot/README.md § Working Vocabulary — original source
- /dp/brenner_bot/specs/operator_library_v0.1.md — formal operator definitions
