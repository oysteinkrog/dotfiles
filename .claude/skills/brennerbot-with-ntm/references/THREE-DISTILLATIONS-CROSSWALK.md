# THREE-DISTILLATIONS-CROSSWALK.md — Reading Opus, GPT, and Gemini Together

<!-- TOC: Why three distillations | The model-specific renderings | What survives translation (the invariants) | What appears uniquely per model | The crosswalk table | How to use them together | Triangulation discipline | Anti-patterns | Cross-references -->

The brennerbot project commissioned **three independent expert distillations** of the same Brenner transcripts: Claude Opus 4.5, GPT-5.2 Pro extra-high reasoning, and Gemini 3. Each model arrived at a different *rendering* of the same method.

The three renderings aren't competing answers; they're **complementary lenses**. The agreement between them is the methodology kernel; the differences expose what each model uniquely contributes.

This file specifies the crosswalk, the invariants, the unique contributions, and how to use them together.

Mined from `/dp/brenner_bot/README.md § The three distillations`.

---

## Why three distillations

A single model's distillation is suspect:

- **Hallucination risk** — the model may project structure that isn't there
- **Style bias** — Opus tends toward narrative coherence; GPT toward formalization; Gemini toward systems metaphors
- **Single-perspective** — one model can't see its own blind spots

Three independent distillations triangulate:

1. **What appears in all three** = the invariant kernel (high confidence)
2. **What appears only in two** = strong signal (medium confidence; one model may have missed it)
3. **What appears only in one** = unique contribution (treat as that model's lens, useful but not invariant)

This is itself a Brenner move: **discriminative testing applied to the method's own articulation**.

---

## The model-specific renderings

### Claude Opus 4.5: "Two Axioms → operator algebra → loop"

Primary file: `final_distillation_of_brenner_method_by_opus45.md`

- **Abstraction style**: Coherent mental architecture (axioms → derived moves → social technology → failure modes)
- **Best at**: A readable *theory of the method*; the "why" and the inner structure
- **Unique contributions**:
  - The "Two Axioms" framing (generative grammar + reconstruction)
  - Operator algebra with compositions
  - An actionable worksheet
  - Explicit failure modes section
- **Watch-outs**: Narrative coherence can feel stronger than the evidence; treat it as a map that requires §-anchored grounding

### GPT-5.2 Pro: "Objective function + rubrics + machine-checkable guardrails"

Primary file: `final_distillation_of_brenner_method_by_gpt_52_extra_high_reasoning.md`

- **Abstraction style**: Operationalization-first (define primitives precisely; define a loop; define a scoring rubric)
- **Best at**: Making the method executable (scoring experiments, structuring artifacts, defining guardrails)
- **Unique contributions**:
  - "Evidence per week" objective function
  - Next-experiment scoring rubric (0-3)
  - Explicit protocol artifacts (slates, tests, ledgers)
  - 12 hygiene rules suitable for a linter
  - Machine-checkable guardrails
- **Watch-outs**: The method can become over-formalized; treat the rubric as a decision aid, not a substitute for taste

### Gemini 3: "The Brenner Kernel" (decompilation + instruction set)

Primary file: `final_distillation_of_brenner_method_by_gemini3.md`

- **Abstraction style**: Computational metaphor + systems decomposition (root access, scheduler, drivers, debugging protocol)
- **Best at**: Reframing and memorability; "how would I implement this as an OS?" thinking — useful for UI and orchestration design
- **Unique contributions**:
  - The Kernel / instruction-set framing
  - Explicit "distributed cognition" motifs (Brenner-Crick as GAN)
  - A debugging-oriented lens
  - "Integer Biology" framing
  - "Monopoly Market of Ideas"
- **Watch-outs**: Metaphors can drift; keep the mapping anchored to verbatim primitives

---

## What survives translation (the invariants)

Concepts that appear in **all three** distillations with strong transcript grounding:

- **Dimensional reduction**: 3D → 1D as a core move
- **Digital handles**: Prefer yes/no over quantitative measurement
- **Forbidden patterns**: Exclusion beats accumulation
- **Third alternative**: "Both could be wrong"
- **Productive ignorance**: Fresh eyes as strategic asset
- **Don't Worry hypothesis**: Defer secondary mechanisms
- **Seven-cycle log paper**: Design for visible differences
- **Organism choice**: The experimental object as a design variable

These 8 concepts form the **invariant kernel**. Any new methodology iteration that loses one of these has drifted from Brenner.

---

## What appears uniquely (model-specific contributions)

### Opus only

- **"Gedanken organism" standard** — could you compute the animal from DNA?
- **Explicit failure modes** — "level confusion", "level skipping", "Occam's broom"
- **Conversation as distributed cognition** — Crick-Brenner GAN as cognitive technology

### GPT only

- **"Evidence per week" objective function** — the maximization target
- **0-3 scoring rubric** — per-pane evaluation criteria
- **12 guardrail rules** — hygiene rules suitable for a linter

### Gemini only

- **GAN metaphor for Brenner-Crick** — generator-discriminator loop
- **"Integer Biology" framing** — biology as discrete computation
- **"Monopoly Market of Ideas"** — consensus as monopoly to disrupt

---

## The crosswalk table

| Concept | Opus | GPT | Gemini |
|---------|------|-----|--------|
| Foundation | Two Axioms | One sentence + objective function | Root Access (ontological stance) |
| Operators | Operator algebra + compositions | Operator basis + loop + rubric | Instruction set |
| Execution | Brenner Loop | 9-step loop + worksheet | Debug protocol + scheduler |
| Quality | Failure modes section | 12 guardrails | Error handling (Occam's Broom, etc.) |
| Social | Conversation as technology | Conversation as hypothesis search | Brenner-Crick GAN |

Reading horizontally: each row is a *concept*; each cell is how that concept renders in each model. Reading vertically: each column is a *model's lens*; concepts are translated through that lens.

---

## How to use them together

### For new operators

1. **Start with Opus** for coherence and the "shape" of the method
2. **Use GPT** to turn the shape into executable protocol (artifacts + scoring + guardrails)
3. **Use Gemini** when you need reframing, alternate clustering, or systems metaphors for architecture
4. **Ground in transcripts**: When any claim matters, walk back to `complete_brenner_transcript.md` and cite `§n` anchors

### For brennerbot-with-ntm

The skill is **Track-A** (per QUOTE-BANK-METHODOLOGY.md): triangulate the kernel from all three. Where they agree, the operator algebra is solid (per OPERATORS.md). Where they disagree, the disagreement-register documents the choice (per DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md).

The brennerbot-with-ntm skill *itself* embodies all three lenses:

- **Opus's coherence** → the canonical 5-role roster + 10-phase structure (per ROSTER-PLANS.md + PHASES.md)
- **GPT's operationalization** → the 14-criterion rubric (per EVALUATION-RUBRIC-14-CRITERIA.md), 50+ lint rules (per ARTIFACT-LINTER-RULES.md), 7-dimension session score
- **Gemini's systems metaphors** → the multi-pane orchestration via ntm + Agent Mail (per BRENNER-GAN-MECHANICS.md)

### For per-archetype work

Different question archetypes lean on different distillations:

| Archetype | Distillation lens |
|-----------|-------------------|
| A1 design-space | Opus (coherence; mental architecture) |
| A2 codebase | GPT (executable; operationalize) |
| A3 methodology | All three (triangulate; this is what brenner_bot itself does) |
| A4 incident | GPT (rubrics; fast scoring) |
| A6 adversarial | Gemini (systems metaphors; attack-surface thinking) |

Per ARCHETYPE-START-PACKS.md: each archetype's start-pack hints at the dominant lens.

---

## Triangulation discipline

When the three distillations *agree*: high confidence, treat as invariant. When they *disagree*: pause and ground in transcripts.

Disagreement examples (from /dp/brenner_bot):

- **Opus emphasizes "Conversation as distributed cognition"** but Gemini frames it as **"Brenner-Crick GAN"** — these are the same thing under different metaphors. Reconciliation: BRENNER-GAN-MECHANICS.md uses Gemini's framing because it's more mechanistically precise; Opus's is the *interpretation*, Gemini's is the *implementation*.
- **GPT's "objective function"** is more explicit than Opus's "Brenner Loop" — both describe the same cycle, but GPT formalizes it as `Score(E) = (EIG × DL) / (Time × Cost × Ambiguity × Infrastructure-Dependence)`. Reconciliation: BAYESIAN-FRAMEWORK.md uses GPT's formula; Opus's is the *narrative*, GPT's is the *equation*.
- **Gemini's "Integer Biology"** has no Opus or GPT analog. Reconciliation: per QUOTE-BANK-METHODOLOGY.md, this is a Gemini-only contribution — useful framing, but not invariant.

The DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md tracks every divergence + the chosen synthesis.

---

## Per-distillation reading time

| Distillation | Length | Read time | When to read |
|--------------|--------|-----------|--------------|
| Opus 4.5 | 38KB / 654 lines | ~30 min | Onboarding (Week 1 per OPERATOR-ONBOARDING-CURRICULUM.md) |
| GPT-5.2 Pro | 26KB / 468 lines | ~25 min | Operationalization (Week 2) |
| Gemini 3 | 13KB / 248 lines | ~15 min | Systems thinking (Week 3) |

Don't try to read all three on the same day — let each settle. Per OPERATOR-ONBOARDING-CURRICULUM.md, spread across 3 weeks.

---

## What this skill (brennerbot-with-ntm) inherits

The brennerbot-with-ntm skill IS the synthesis of all three distillations:

- **Operator algebra** (15 ops) — Opus's algebra + Gemini's instruction set
- **The 14-criterion rubric** — GPT's rubric formalized
- **The 7-section artifact** — GPT's protocol artifacts
- **The 50+ lint rules** — GPT's guardrails
- **The 10-phase loop** — Opus's loop
- **The multi-pane orchestration** — Gemini's distributed cognition

When in doubt, the skill's choices favor:
1. Triangulated kernel (all three agree) > single-distillation novelty
2. GPT's machine-checkability > Opus's narrative coherence > Gemini's metaphor
3. Transcript grounding (§n) > distillation interpretation

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Read only one distillation | Loses triangulation; missing model's blind spots |
| Treat distillations as canonical (skip transcript) | Distillations are *interpretations*; transcript is canonical |
| Resolve disagreements by averaging | Often loses signal; document the disagreement instead |
| Use Gemini's metaphors as load-bearing claims | Per ANTI-ANALOGY-AND-PLAUSIBILITY.md: metaphors require disclaimer |
| Cite "Brenner said" via Opus's prose | Cite `§n` from transcript directly |
| Mix vocabulary from different distillations | Per BRENNER-VOCABULARY.md: use canonical terms |
| Ignore distillation watch-outs | Each model has documented blind spots |
| Add a fourth distillation casually | Triangulation works at 3; 4 adds noise without clarification |

---

## Cross-references

- [QUOTE-BANK-METHODOLOGY.md](QUOTE-BANK-METHODOLOGY.md) — Track-A corpus → quote bank → kernel
- [DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md](DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md) — every divergence + synthesis
- [BRENNER-VOCABULARY.md](BRENNER-VOCABULARY.md) — canonical vocabulary
- [BRENNER-GAN-MECHANICS.md](BRENNER-GAN-MECHANICS.md) — Gemini's GAN framing
- [BAYESIAN-FRAMEWORK.md](BAYESIAN-FRAMEWORK.md) — GPT's objective function
- [OPERATORS.md](OPERATORS.md) — synthesized algebra
- [ARCHETYPE-START-PACKS.md](ARCHETYPE-START-PACKS.md) — per-archetype lens
- [OPERATOR-ONBOARDING-CURRICULUM.md](OPERATOR-ONBOARDING-CURRICULUM.md) — 3-week distillation reading
- /dp/brenner_bot/final_distillation_of_brenner_method_by_opus45.md
- /dp/brenner_bot/final_distillation_of_brenner_method_by_gpt_52_extra_high_reasoning.md
- /dp/brenner_bot/final_distillation_of_brenner_method_by_gemini3.md
- /dp/brenner_bot/README.md § The three distillations — original crosswalk
