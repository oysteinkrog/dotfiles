# SOURCE-CORPUS.md — Track A Source Corpus + Quote Bank + Provenance

<!-- TOC: Source artifacts (read-only evidence) | Quote bank (operator-keyed) | Cross-distillation provenance | Provenance discipline | Extending the corpus | Source-coverage map | Verification-First Discipline -->

This skill IS a `/operationalizing-expertise` Track A artifact: corpus → quote bank → triangulated kernel → operator library → validators. This file is the provenance trail.

**Track A pattern:** every recommendation in this skill must trace back to one of the source artifacts below. When the skill makes a methodological claim, it cites a `§` anchor. When it changes a recommendation, it updates the trail.

---

## Source artifacts (read-only evidence)

| Artifact | Path | Anchor scheme | What it contains |
|----------|------|---------------|------------------|
| Primary transcript | `/dp/brenner_bot/complete_brenner_transcript.md` | `§n` (236 numbered sections) | The source corpus of Brenner's verbatim reflections on his method |
| Quote bank (restored) | `/dp/brenner_bot/quote_bank_restored_primitives.md` | `§n` matched to transcript | High-signal verbatim snippets keyed by anchor |
| Initial metaprompt | `/dp/brenner_bot/initial_metaprompt.md` | section headings | The seed prompt that produced the model distillations |
| GPT-5.2 metaprompt | `/dp/brenner_bot/metaprompt_by_gpt_52.md` | section headings | Refined metaprompt with operator-level taxonomy |
| Opus 4.5 distillation | `/dp/brenner_bot/final_distillation_of_brenner_method_by_opus45.md` | Part I-IX | 14-operator algebra + Bayesian framing + failure modes |
| GPT-5.2 distillation | `/dp/brenner_bot/final_distillation_of_brenner_method_by_gpt_52_extra_high_reasoning.md` | §n citations | 11-operator algebra + objective function + composition cheat-sheet |
| Gemini 3 distillation | `/dp/brenner_bot/final_distillation_of_brenner_method_by_gemini3.md` | section + §n | Ontology + search algorithm + GAN framing |
| brenner.ts CLI | `/dp/brenner_bot/brenner.ts` | function names | The TypeScript reference implementation (we don't port; we learn from the schema) |
| brenner.test.ts | `/dp/brenner_bot/brenner.test.ts` | test descriptions | Behavior assertions on the CLI we're reimplementing |
| Application essays | `/dp/brenner_bot/ANALYSIS_OF_USING_BRENNERBOT_FOR_BIO_INSPIRED_NANOCHAT*.md` | rounds | Worked-example applications of Brenner method to a research question |
| Specs | `/dp/brenner_bot/specs/` | filenames | Protocol specifications for hypothesis/evidence/etc |

---

## Quote bank (operator-keyed)

This is the working quote bank — verbatim transcript snippets, keyed by which operator they activate. It is *not* exhaustive; it's the high-signal subset most cited in our marching orders.

### ◊ Paradox-Hunt
- **§95** — "the paradox of the prodigious rate of protein synthesis. That is, you had to say, 'Well there could be a few new ribosomes made, they would have escaped your attention, but clearly these very few were capable of prodigious rates of function.'"
- **§106** — "You have to keep on coming back... how can these two things exist and not be explained, you know?"
- **§175** — "junk vs garbage" definitional cleanup as a way to dissolve a pseudo-paradox.

### ⊘ Level-Split
- **§45–§46** — "Schrödinger says the chromosomes contain the information to specify the future organism and the means to execute it and that's not true. The chromosomes contain the information to specify the future organisation and a description of the means to implement, but not the means themselves."
- **§50** — "in science as in life, it is important to distinguish between chastity and impotence. The outcome is the same, the reasons are fundamentally different."
- **§105** — "instructions separate from the machine."
- **§147** — "A proper simulation must be done in the machine language of the object being simulated."

### 𝓛 Recode/Dimensional-Reduction
- **§58** — "the reduction of biology to one dimension in terms of information that is the absolute crucial step... Biology... had been three-dimensional, and a lot of people wanted it four-dimensional. But the whole idea that you could reduce it to one dimension is a very powerful idea."
- **§229** — "Inversion" / "turning things upside down" as a deliberate reframing tactic.
- **§161** — "European plan vs American plan" as a coordinate choice (lineage vs neighborhood).
- **§197** — distinguishing digital metaphor from analogue computation with thresholds.

### ≡ Invariant-Extract
- **§109** — "the topology could, you could do these things at the kind of topological level."
- **§88–§89** — phase problem (combinatorial 2^N) requires phase-breaking trick rather than search.
- **§90** — mutational spectra as mechanism-typing instrument.
- **§134** — "We could give a topological proof of co-linearity – we wouldn't have to do any protein sequencing."

### ✂ Exclusion-Test (load-bearing)
- **§147** — "Exclusion is always a tremendously good thing in science."
- **§69** — "If the code was overlapping, then certain combinations of adjacent amino acids would be forbidden."
- **§103** — "We proposed three models... and someone said, 'I wish to propose two models: model A and model B... either model A is right or model B is right.' And I said, 'You've forgotten there's a third alternative.' He said, 'What's that?' I said, 'Both could be wrong.'"

### ⟂ Object-Transpose
- **§91** — "Once you've formulated a question, and if it's general enough, it means you can solve it in any biological system. So what you want to do is to find experimentally which is the best one to solve that problem... the choice of the experimental object remains one of the most important things to do in biology."
- **§145–§146** — "These could be fit well into the window of the electron microscope" → C. elegans.
- **§221** — Fugu "discount genome" as an organism-choice technology.

### ↑ Amplify
- **§62** — "We don't do any statistics... we do have one test. We plot our results on seven-cycle log paper—that is it goes over 10^7—and you hold the sheet at one end of the room, and you stand at the other end of the room, and if you can see a difference it's significant."
- **§94** — "this single protein accounted for 70% of all the protein synthesis of the cell."
- **§154** — selection for rare worm mutants via tracks on plates.

### ⌂ Materialize
- **§66** — "Always try... I've always tried to materialise the question in the form of: well, if it is like this, how would you go about doing anything about it?"
- **§42** — Schrödinger inscription: "Let the imagination go, guarding it by judgement and principle, but holding it in and directing it by experiment."
- **§198** — "I had invented something called HAL biology. HAL, that's H-A-L, it stood for Have A Look biology."

### 🔧 DIY/Bricolage
- **§23** — Building a Warburg manometer to measure oxygen uptake.
- **§51** — "This is something you can always do... it's open to you. There's no magic in this."
- **§86** — "negative staining took electron microscopy out of the hands of the elite and gave it to the people."
- **§37** — heliostat for dark-field microscopy.

### ⊞ Scale-Check
- **§66** — "Get the scale of everything right... Francis... that's one of the things that we tried very hard to do: was to stay imprisoned within the physical context of everything... the DNA in a bacterium is 1mm long. And it's in a bacterium that's 1μ. So the DNA has been folded up a thousand times."
- **§100** — "it is magnesium that stabilises this, and the caesium will compete with the magnesium... therefore the thing to do is to raise the magnesium." (Dominant-variable rescue.)

### 🤝 GAN/Conversation
- **§66** — "Never restrain yourself; say it, even if it is completely stupid and ridiculous and wrong, because just uttering it gets it out into the open. And someone else will pick up something from it."
- **§167** — "An idea usually forms in my mind, it's at least 50% wrong the first time it appears... this kind of ongoing conversation is so important to science."

### ΔE Exception-Quarantine
- **§110** — "All the exceptions, each of which cannot be explained by the coherent theory... we didn't conceal them; we put them in an appendix."
- **§111** — "It was the real house of cards theory; you had to buy everything... if you attacked any one part of it, the whole thing fell apart. So it was all or nothing theory."

### † Theory-Kill
- **§229** — "One should not fall in love with one's theories. They should be treated as mistresses to be discarded once the pleasure is over... When they go ugly, kill them. Get rid of them."

### ∿ Dephase
- **§143** — "The best thing in science is to work out of phase. That is, either half a wavelength ahead or half a wavelength behind. It doesn't matter. But if you're out of phase with the fashion you can do new things."
- **§192** — "Opening game... tremendous freedom of choice."
- **§210** — Heroic vs classical periods: routine work generates new important problems.

### ⊙ Productive-Ignorance
- **§63** — "Spreading ignorance rather than knowledge."
- **§192** — "Strong believer in the value of ignorance... when you know too much you're dangerous... deter originality."
- **§65** — "You can't... equip yourself with a theoretical apparatus for the future... The best thing to do a heroic voyage is just start. Don't... don't equip yourself."
- **§200** — "papers... that remove information from my head."
- **§230** — "Ignorant about the new field, knowledgeable about the old."

---

## Cross-distillation provenance

When the three distillations agree on a point, it inherits silently into the kernel. When they disagree, the disagreement is registered in [DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md](DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md) with our chosen synthesis.

| Provenance | Source | What inherits to skill |
|------------|--------|------------------------|
| Two-axiom framing | All 3 distillations | KERNEL.md axioms 1 + 2 |
| 15-operator algebra | Our synthesis (Opus 14 + GPT-5.2 ⊙ + 🤝 explicit) | OPERATORS.md |
| Bayesian objective function | Opus + GPT-5.2 (verbatim agreement) | KERNEL.md § Objective Function |
| Required failure modes | Opus Part VIII | KERNEL.md § Required Failure Modes |
| Composition cheat-sheet | GPT-5.2 + Opus operator-loop | OPERATORS.md § Composition Cheat-Sheet |
| Brenner-Crick GAN explicit framing | Gemini 3 §4.1 | OPERATORS.md 🤝 card; Phase 5 cross-exam |
| House-of-cards theory architecture | Opus + Gemini agreement | KERNEL.md § Bayesian Substrate; Phase 6 distillation rule |
| Don't-Worry hypothesis | All 3, framing differs | DISAGREEMENT-REGISTER D-002; allowed in Phase 4, audited in Phase 7 |
| Productive-ignorance role-binding | Our operationalization (synthesis) | ROSTER-PLANS.md role-binding rule |

---

## Provenance discipline

When this skill makes a recommendation:

1. **It must be traceable.** A recommendation without a `§`-anchor citation in the source corpus is potentially drift. Phase 10 drift-check enforces this.
2. **It must survive the kernel.** Recommendations that contradict the two axioms are rejected.
3. **It must be operationalized.** A claim that a Brenner principle "applies here" must come with: (a) which operator card, (b) which marching-order template, (c) which validator/audit script. Otherwise it's gnomic philosophy, not a skill.

---

## Extending the corpus

When a future drift-check session uncovers a new operator that should join the algebra:

1. Add a quote-bank entry above (verbatim source + `§`-anchor).
2. Add an operator card in [OPERATORS.md](OPERATORS.md).
3. Add a marching-order template that activates it.
4. Add a validator (script or bead invariant).
5. Update [DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md](DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md) if the new operator was implicit in one distillation but absent in others.

The corpus is read-only. **Don't edit the source artifacts.** Quote-bank entries are excerpts, not edits.

---

## Source-coverage map (Phase 10 drift-check input)

The drift auditor cross-checks: did this session apply operators across the full source corpus, or did it cluster around a few §-anchors?

| Coverage tier | Anchors hit | Verdict |
|---------------|-------------|---------|
| Saturating | ≥30 distinct §-anchors cited in evidence packs / distillations | Excellent — broad source engagement |
| Adequate | 15–29 | Normal |
| Thin | 6–14 | Flag for Phase 10 — possible operator concentration |
| Sparse | ≤5 | Likely regression — session ran on too narrow a slice |

Run `scripts/quote-bank-extract.sh` (Tier 2) to enumerate which `§`-anchors appeared in this session's evidence and distillation files.

---

## Verification-First Discipline

For any recommendation that depends on **volatile** information (current state of corpus, current state of a target codebase, current external benchmark), verify against the live source before treating it as final. Pinned content-hashes in `corpus/corpus_index.md` make verification cheap.

This mirrors the saas-billing skill's verification-first protocol applied to *research* corpora rather than provider catalogs.
