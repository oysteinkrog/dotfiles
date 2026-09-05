# DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md — Where the Three Source Distillations Diverge

<!-- TOC: How disagreement identified | D-001 number of operators | D-002 Don't Worry status | D-003 House of cards | D-004 Productive Ignorance | D-005 Wordplay | D-006 Conversation/GAN | D-007 Out of phase | D-008 Operator order | D-009 Failure modes | D-010 Bayesian framing | D-011 Heroic vs classical | D-012 Cross-domain x ignorance | Extending -->

This skill triangulates `final_distillation_of_brenner_method_by_opus45.md`, `final_distillation_of_brenner_method_by_gpt_52_extra_high_reasoning.md`, and `final_distillation_of_brenner_method_by_gemini3.md` against the primary corpus.

Where they agree, [KERNEL.md](KERNEL.md) inherits silently. Where they disagree, this file records both readings and our chosen synthesis.

This is not just internal documentation — it's the *meta* application of the same Phase 6 disagreement-register principle that the skill itself enforces.

---

## How disagreement is identified

For each operator, axiom, or concept that one distillation surfaces, check:

- Did the other two distillations name it?
- If named, do they describe the same trigger / recipe / failure mode?
- If different, where exactly?

The disagreements we found:

---

## D-001: Number of operators in the algebra

**Opus 4.5 distillation:** 14 named operators (⊘ Level-Split, 𝓛 Recode, ≡ Invariant-Extract, ✂ Exclusion-Test, ⟂ Object-Transpose, ↑ Amplify, ⊕ Cross-Domain, ◊ Paradox-Hunt, ΔE Exception-Quarantine, ∿ Dephase, † Theory-Kill, ⌂ Materialize, 🔧 DIY, ⊞ Scale-Check).

**GPT-5.2 distillation:** 11 named operators (⊘, 𝓛, ⧉ ≈ ⌂, ≡, ✂, ⟂, ↑, ⇓ Democratize-Tools, ΔE, ∿, ⊙ Unentrain ≈ Productive-Ignorance).

**Gemini 3 distillation:** doesn't formalize the same way — uses prose ("Brenner Instruction Set") with 8 actions + 3 ontological priors.

**Our synthesis (KERNEL.md):** 15 operators. Combines Opus's set with GPT-5.2's `⊙ Productive-Ignorance` and `🤝 GAN/Conversation` (which Opus describes verbally but doesn't glyph). We merge `⇓ Democratize-Tools` into `🔧 DIY/Bricolage` because they target the same operational move (build/share what you need).

**Why this synthesis:** The 15-operator algebra is wider and lets us write more specific marching-order modules. The cost is a longer card library (manageable). The benefit is no missed move at Phase-loop dispatch time.

---

## D-002: Status of "Don't Worry hypothesis"

**Opus 4.5:** Treats "Don't Worry" (§57) as a first-class methodological move under Strategic Problem Deferral (Part III, §III.2). Recipe: assume mechanisms exist when blocked on secondary problems.

**GPT-5.2:** Lists "Don't Worry" as a guardrail (§6 Epistemic Hygiene #5). Same recipe but classified as discipline, not operator.

**Gemini 3:** Calls it "the 'Don't Worry' API" and describes it as `try {} catch { TODO }` semantics. Closest to a first-class operator.

**Our synthesis:** Don't Worry is **allowed in Phase 4 early rounds, audited at Phase 7**. Specifically:

- Investigators may file `assumption.type:methodological` with `status:unchecked` and `load_description: "Don't worry — assumed Y exists; proceed with X"` while focused on the primary mechanism.
- Phase 7 fresh-eyes audit explicitly lists every `unchecked` assumption and asks: "Did Phase 4 actually verify this?"
- An `unchecked` assumption that survives Phase 7 audit becomes a `Don't Worry — flagged for next session`, not a hidden gotcha.

**Why this synthesis:** Don't Worry is a real research move (you cannot block on every secondary mechanism), but it's also a real failure mode (silent technical debt that breaks at scale). Make it explicit + auditable.

---

## D-003: Treatment of "House of cards" theory architecture

**Opus 4.5:** Strong endorsement (Part III §III.3). Theories that interlock have multiplicative evidential weight (p^N for N independent predictions). The whole-or-nothing structure is a *feature*.

**GPT-5.2:** Mentioned only as anchor (§110–§111). Not operationalized.

**Gemini 3:** Strong endorsement (§3.2 Occam's Broom + house of cards). Interlocked theories are *high-bandwidth signals*; anomalies are *noise*.

**Our synthesis:** Phase 6 distillations should aim for house-of-cards structure (mutually-constraining claims), but the Phase 7 audit rubric must explicitly check: "Are we relying on house-of-cards interlocking to compensate for thin evidence on individual claims?" House-of-cards is great when evidence per claim is independent; it's overconfidence when evidence per claim is correlated. The Phase 7 audit checks for correlation.

---

## D-004: "Productive Ignorance" — operator vs cultural disposition

**Opus 4.5:** Calls it `productive ignorance` and treats it as cultural/strategic (Part II "Epistemology of Productive Ignorance"). Not in the operator algebra.

**GPT-5.2:** Glyphs it `⊙ Unentrain` and includes in operator basis (§3 ⊙). Recipe: keep priors broad; resist expert entrainment.

**Gemini 3:** Calls it `Prior Management System` (§6.1). Treats as *Bayesian* meta-strategy, not operator.

**Our synthesis:** Treat as operator `⊙ Productive-Ignorance` and *operationalize* via role assignment: at least one Proposer pane is told to read minimally and reason from first principles. This converts a cultural disposition into a concrete role-binding rule (per ROSTER-PLANS.md).

**Why this synthesis:** Without a concrete operationalization, `productive ignorance` is fortune-cookie philosophy. The role-binding rule makes it testable: "Did pane N actually read minimally?" Yes/no.

---

## D-005: How "wordplay" / inversion fits into the method

**Opus 4.5:** Strong inclusion (Part IV "Wordplay as Cognitive Tool"). Quotes "chastity vs impotence" inversion as paradigm of wordplay-as-thinking.

**GPT-5.2:** Lists "inversion" as an action under `𝓛 Recode` (§3 𝓛, anchor §229). Treats wordplay as a tactic for representation change, not a separate operator.

**Gemini 3:** Strong inclusion (§4.2 "Wordplay as Cognitive Debugging"). Treats as cognitive tool with brain-elasticity rationale.

**Our synthesis:** Subsume wordplay under `𝓛 Recode/Dimensional-Reduction`. The MO-03a-propose.md template includes "try inversions" as a sub-step within the Recode section. Don't promote wordplay to its own operator — that fragments the algebra.

---

## D-006: Status of "Conversation" / Brenner-Crick GAN

**Opus 4.5:** Strong inclusion (Part IV "Conversational Science"). Treats as social technology.

**GPT-5.2:** Inclusion (§5 cognitive substrate). Treats as conversation-as-search.

**Gemini 3:** Glyph-level inclusion as `Brenner-Crick GAN` (§4.1). Most explicit operationalization.

**Our synthesis:** Promote to operator `🤝 GAN/Conversation` — Phase 5 cross-examination *is* the GAN. This is one of our additions beyond Opus's 14 — see D-001.

---

## D-007: "Out of phase" — career strategy vs operator

**Opus 4.5:** "Working out of phase" is career-level (Part IV). Not Phase-loop level.

**GPT-5.2:** Glyphs `∿ Dephase` as operator (§3). Phase-loop level.

**Gemini 3:** "Out of Phase Oscillations" (§6.2) — career-level / scheduler-level.

**Our synthesis:** Operator `∿ Dephase` applies at Phase 7 audit (consensus check) and Phase 10 drift-check (was the session in-phase?). This is a methodology-level use, not career-level. Keep career-level interpretation as a footnote in OPERATORS.md.

---

## D-008: Order of priority among the operators

**Opus 4.5:** Orders by Generative Loop (Paradox → Level-Split → Reduce → Materialize → Exclude → ...). Sequential.

**GPT-5.2:** Orders by composition (`⊘ → 𝓛 → ≡ → ✂` is the "signature move"). Same sequence, different framing.

**Gemini 3:** Doesn't sequence; presents as parallel actions.

**Our synthesis:** [OPERATORS.md § Composition cheat-sheet](OPERATORS.md#composition-cheat-sheet) sequences by phase (which operators apply at which phase). This integrates both Opus's Generative Loop and GPT-5.2's signature composition into a phase-keyed table.

---

## D-009: Failure modes of the method

**Opus 4.5:** Explicit Part VIII "Failure Modes" with 5 cases (intractable grammar, inaccessible primitives, fashion is right, pathological contradictions, middle-game).

**GPT-5.2:** Implicit; doesn't enumerate failures.

**Gemini 3:** Implicit; one-line caution.

**Our synthesis:** Inherit Opus's Part VIII directly into [KERNEL.md § The Required Failure Modes](KERNEL.md#the-required-failure-modes-when-this-method-does-not-apply). Add it to the Phase 0 scope-decision discipline.

---

## D-010: Bayesian framing weight

**Opus 4.5:** Strong Bayesian frame (Part VII "The Bayesian Structure"). Maps every operator to a Bayesian operation.

**GPT-5.2:** Strong Bayesian frame (§1 "evidence per week"; explicit objective function).

**Gemini 3:** Light Bayesian frame (informal mentions of "Tight Priors" / "Diffuse Priors").

**Our synthesis:** [KERNEL.md § The Bayesian Substrate](KERNEL.md#the-bayesian-substrate-why-the-brenner-moves-work) inherits the Bayesian frame from Opus + GPT-5.2. The objective function (numerator/denominator score) comes verbatim from GPT-5.2 and Opus (they agree exactly here). This grounds operator choice in Bayesian decision theory rather than vibes.

---

## D-011: Status of "Heroic vs classical" periods

**Opus 4.5:** Mentioned in Glossary (§210) but not Phase-loop level.

**GPT-5.2:** Mentioned in Glossary (§210) and tied to `∿ Dephase`.

**Gemini 3:** Not mentioned.

**Our synthesis:** Not promoted to operator. Phase 10 drift-check rubric line: "Is the question in opening-game (high information per move) or middle-game (filling-in)?" Different phase emphasis applies.

---

## D-012: How `⊕ Cross-Domain` interacts with `⊙ Productive-Ignorance`

**Opus 4.5:** Treats `⊕ Cross-Domain` as a source of `⊙ Productive-Ignorance` insight (cross-domain pattern matching is *enabled* by being unencumbered by expert priors).

**GPT-5.2:** Treats them as one move (`⊙ Unentrain`).

**Gemini 3:** Doesn't separate them.

**Our synthesis:** Subsume `⊕ Cross-Domain` under `⊙ Productive-Ignorance` for our 15-operator algebra. The role-binding rule for the ignorance pane includes: "you may *also* import patterns from unrelated fields." This collapses two moves into one, simplifying the operator algebra without losing the methodological content.

---

## How to extend this register

When a new application of the skill produces a Phase 10 drift-check that names a NEW disagreement (operator that should be added, axiom that should be sharpened), file it here as `D-NNN` with:

1. Which distillations agreed/disagreed on the issue
2. Our chosen synthesis
3. Why this synthesis (rationale)
4. Which `references/` file changed as a result

This file is the *meta* application of the same disagreement-register principle that the skill enforces at Phase 6. Phase 10 drift-check should compare the *actual* trajectory against this register's choices — did our synthesis hold up?

---

## Audit query

```bash
# Are all of D-001..D-012 referenced somewhere in references/?
for D in $(grep -oE '^## D-[0-9]+' DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md); do
  N=${D#*D-}
  grep -l "D-${N}" ../references/ || echo "Orphan: $D"
done
```

If a `D-NNN` becomes orphaned (no references file uses it), either remove the entry or use it.
