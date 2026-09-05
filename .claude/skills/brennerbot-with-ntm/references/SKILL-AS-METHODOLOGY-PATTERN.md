# SKILL-AS-METHODOLOGY-PATTERN.md — How brennerbot Itself Operationalizes Track-A

<!-- TOC: Why this meta-doc | The Track-A pattern recap | brennerbot's Stage-1 corpus | brennerbot's Stage-2 quote bank | brennerbot's Stage-3 triangulated kernel | brennerbot's Stage-4 operator library | brennerbot's Stage-5 validators | The reflexivity | Why this matters for new operators | Improving the skill via the same pattern | Composition with /sc and /operationalizing-expertise -->

Per `/operationalizing-expertise` Track-A pattern: corpus → quote bank → triangulated kernel → operator library → validators. This file is *meta-documentation* showing how brennerbot itself was built using exactly that pattern.

For agents who want to understand WHY the skill is structured this way (and HOW to extend it correctly), this is the rosetta stone.

---

## Why this meta-doc

The skill is large (67 references, 52 MOs, 45 scripts). Without understanding its shape, agents extending it are likely to:

- Add references that should be MOs
- Add scripts that should be subagents
- Reorganize indexes inconsistently
- Break the operator algebra by adding ad-hoc operators

This file shows the *organizing principle*. Once you see brennerbot itself as a Track-A instantiation, future contributions naturally land in the right place.

---

## The Track-A pattern recap

Per `/operationalizing-expertise`:

```
Stage 1: Source corpus    Identify authoritative sources of an expert's method
Stage 2: Quote bank       Extract verbatim quotes; tag by topic/operator/claim type
Stage 3: Triangulated     Distill ≥3 independent expert distillations
         kernel            Reconcile via disagreement register
Stage 4: Operator library  Codify the cognitive moves with trigger/recipe/validator/failure-mode
Stage 5: Validators        Mechanize the operator library into pass/fail checks
```

This pattern works for any methodology. Brennerbot used it on Brenner's research-method transcript.

---

## brennerbot's Stage-1 corpus

The source corpus that grounded this entire skill:

| Source | Type | Pinned at |
|--------|------|-----------|
| `/dp/brenner_bot/complete_brenner_transcript.md` | Sydney Brenner's transcript with method explanation | content-hashed at session-1 ingestion |
| `/dp/brenner_bot/quote_bank_restored_primitives.md` | Original quote bank from Brenner's work | content-hashed |
| `final_distillation_of_brenner_method_by_opus45.md` | Opus 4.5's distillation | content-hashed |
| `final_distillation_of_brenner_method_by_gpt_52_extra_high_reasoning.md` | GPT-5.2 Pro's distillation | content-hashed |
| `final_distillation_of_brenner_method_by_gemini3.md` | Gemini 3's distillation | content-hashed |

Per [SOURCE-CORPUS.md](SOURCE-CORPUS.md). All five sources are pinned with content-hashes; the skill cites them by hash.

---

## brennerbot's Stage-2 quote bank

The quote bank lives in:

| Artifact | Purpose |
|----------|---------|
| [EXEMPLARS.md](EXEMPLARS.md) | Curated quotes from Brenner-method literature with operator tags |
| [QUOTE-BANK-METHODOLOGY.md](QUOTE-BANK-METHODOLOGY.md) | The methodology for building/maintaining quote banks (per /operationalizing-expertise) |

Per QUOTE-BANK-METHODOLOGY.md, the brennerbot quote bank:
- Cross-references quotes from ≥3 sources per axiom
- Tags each quote by operator (◊ ⊘ 𝓛 ≡ ✂ …) it exemplifies
- Categorizes by claim type (axiom / heuristic / counterexample / methodology)

Per-session, operators ALSO build a per-session quote bank in `corpus/quote-bank.md`. The skill-level EXEMPLARS.md is the consolidation of patterns that proved useful across sessions.

---

## brennerbot's Stage-3 triangulated kernel

Three independent expert distillations (Opus 4.5 + GPT-5.2 Pro + Gemini 3) of the Brenner method were reconciled into:

| Artifact | Purpose |
|----------|---------|
| [KERNEL.md](KERNEL.md) | The triangulated kernel (axioms + 15 cognitive operators) |
| [DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md](DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md) | Where the three distillations diverged + how the disagreement was resolved |

The kernel comprises:

**Two foundational axioms** (all three distillations agreed):
1. "Reality has a generative grammar"
2. "To understand is to reconstruct"

**The 15-operator cognitive algebra** (cross-distillation triangulation):
- ◊ Paradox-Hunt
- ⊘ Level-Split
- 𝓛 Recode
- ≡ Invariant-Extract
- ✂ Exclusion-Test
- ⟂ Object-Transpose
- ↑ Amplify
- ⌂ Materialize
- 🔧 DIY
- ⊞ Scale-Check
- 🤝 GAN
- ΔE Exception-Quarantine
- † Theory-Kill
- ∿ Dephase
- ⊙ Productive-Ignorance

Where the distillations disagreed (e.g., Opus vs Gemini on the role of GAN; GPT-5.2 vs others on whether ⊙ is a separate operator), the disagreement register documents the divergence and the chosen synthesis. This is anti-F-601 silent averaging; per QUOTE-BANK-METHODOLOGY.md.

---

## brennerbot's Stage-4 operator library

Each of the 15 cognitive operators is codified in:

| Artifact | Purpose |
|----------|---------|
| [OPERATORS.md](OPERATORS.md) | One card per operator: trigger / recipe / marching-order module / validator / failure mode |
| [OPERATOR-LIBRARY-COMPOSITION.md](OPERATOR-LIBRARY-COMPOSITION.md) | How operators compose (pairs, chains, per-archetype emphases) |
| [OPERATOR-CARDS.md](OPERATOR-CARDS.md) | Operator-cards (OC-001..031) for *operational* tactics (distinct from the cognitive operators) |

Each cognitive operator card has 5 elements (per Track-A Stage 4):

```
Operator: ✂ Exclusion-Test
Trigger:    when ≥2 active hypotheses compete for the same regime
Recipe:     design an experiment whose outcome distinguishes between them
            specifically; prefer falsifier-firing over confirming
Marching-order module: MO-04a-investigate.md, MO-04b-devils-advocate.md
Validator:  every active H has ≥1 falsifier-firing attempt per Phase 4 round
Failure mode: F-401 evidence accumulates without state changes
```

The operator library is the *executable form* of the kernel. References cite operators by their symbol; MOs invoke them by name; scripts validate them.

---

## brennerbot's Stage-5 validators

The validators mechanize the operator library:

| Artifact | Purpose |
|----------|---------|
| [VALIDATOR-DESIGN-PATTERNS.md](VALIDATOR-DESIGN-PATTERNS.md) | The 5 validator types (V1 structural / V2 quantitative / V3 discipline / V4 behavioral / V5 cross-session) |
| [scripts/audit-bead-invariants.sh](../scripts/audit-bead-invariants.sh) | V1 structural — bead schema correctness |
| [scripts/convergence-check.sh](../scripts/convergence-check.sh) | V2 quantitative — phase exit gates |
| [scripts/check-rotation-rules.sh](../scripts/check-rotation-rules.sh) | V3 discipline — adjudicator/champion rotation |
| [scripts/check-anchor-density.sh](../scripts/check-anchor-density.sh) | V4 behavioral — citation density |
| [scripts/drift-trend.sh](../scripts/drift-trend.sh) | V5 cross-session — methodology stability |
| [scripts/check-six-layer-validation.sh](../scripts/check-six-layer-validation.sh) | Aggregator running V1-V5 + V6 (external review) |

For operators that require *judgment* (not pure mechanics), subagents serve as judgment-mediated validators:

- [subagents/falsifier-grader.md](../subagents/falsifier-grader.md) — falsifier quality (operator ✂)
- [subagents/evidence-grader.md](../subagents/evidence-grader.md) — EV W axes
- [subagents/drift-auditor.md](../subagents/drift-auditor.md) — Phase 10 trajectory vs canonical

Together, the validators (mechanical) + subagents (judgment) cover all 15 operators with falsifier-equivalent checks.

---

## The reflexivity

Brennerbot is a Track-A instantiation. Its OWN methodology distillation (the kernel) was triangulated using the methodology it now encodes. This is reflexive:

- The kernel says "triangulate via ≥3 independent distillations"
- The kernel itself was built via 3 distillations (Opus + GPT-5.2 + Gemini)
- The disagreement register applies to the kernel-building process
- F-601 silent averaging was avoided in building this very skill

This isn't accidental — it's what /operationalizing-expertise does well. Track-A is self-applying: distilling a methodology of distillation, using the methodology of distillation.

---

## Why this matters for new operators

When you understand brennerbot is a Track-A instantiation, you can:

1. **Find any artifact by stage**: the kernel is in references/KERNEL.md; the operator library in references/OPERATORS.md; etc.
2. **Add new content correctly**: a new methodology insight goes in EXEMPLARS.md (Stage 2). A new operator goes in OPERATORS.md (Stage 4) only if it can't be reduced to existing 15. A new validator script goes in scripts/ (Stage 5) only if it mechanizes a specific operator.
3. **Avoid common pitfalls**: don't add ad-hoc operators (extend OPERATORS.md only after ≥3 sessions of evidence). Don't bypass the disagreement register (per /operationalizing-expertise + KERNEL.md).
4. **Reason about extensions**: when proposing a new MO, ask "which operator does this exemplify? Which validator confirms it was applied?" If the answers are clear, the extension fits. If not, the extension may be misshapen.

---

## Improving the skill via the same pattern

Phase 10 lessons commit back to references/. The Track-A pattern continues:

```
Session 1 produces a Phase 10 lesson L-001
   ↓
L-001 cites a methodology gap, e.g., "scale-physics not re-verified at Phase 7"
   ↓
Update operator library: OPERATORS.md ⊞ Scale-Check card adds explicit Phase 7 re-verification step
   ↓
Update validator: scripts/check-six-layer-validation.sh adds a check for scale-physics re-verification
   ↓
Session 2 inherits the improvement
```

This is the pattern of methodology evolution. Per CROSS-SESSION-LEARNING.md.

For dramatic methodology revisions:

1. Treat the revision as its own brennerbot question
2. Run a short (T2) brennerbot session on "should we change OPERATORS.md ⊞ Scale-Check card to require Phase 7 re-verification?"
3. The session's HANDBACK informs the actual change

This is methodology bootstrapping itself.

---

## Composition with /sc and /operationalizing-expertise

The two skills relate:

- **/operationalizing-expertise** is the upstream methodology that brennerbot inherits from — it defines Track-A.
- **/sc** is the sibling tool that instantiates Track-A into a Claude Code `.claude/skills/*` directory. It produces the file layout, the SKILL.md spine, the references/.

Both apply to brennerbot:
- /operationalizing-expertise produced the methodology (kernel + operators + validators)
- /sc produced the skill structure (SKILL.md spine, references/, scripts/, MOs)

When a new contributor wants to extend brennerbot, they should:

1. Identify which Track-A stage their contribution affects
2. Check `/operationalizing-expertise` for stage-specific guidance
3. Use `/sc` for any structural changes (new references, new MOs)
4. Apply the methodology recursively (Phase 10 lesson loop)

---

## Worked example: how a new operator joins the algebra

Hypothetical: a new operator "🔄 Recursion-Detection" is proposed (recognizes when an investigation is going in circles).

Per the Track-A discipline:

1. **Stage 1 (corpus)**: collect ≥3 sessions where the issue surfaced; pin them
2. **Stage 2 (quote bank)**: extract specific in-session evidence of the recursion pattern
3. **Stage 3 (kernel)**: per /operationalizing-expertise, propose the new operator with disagreement-register entries
4. **Stage 4 (operator library)**: write the OPERATORS.md card with trigger/recipe/MO-module/validator/failure-mode
5. **Stage 5 (validator)**: write a script that detects recursion patterns in bead history

After ≥3 sessions of stable use, the operator is canonical. Bar is high (per OPERATORS.md "operator emergence" section).

This procedure prevents ad-hoc operator inflation (per /operationalizing-expertise discipline).

---

## Reference summary

The Track-A stages mapped to brennerbot artifacts:

```
Stage 1 (corpus):     SOURCE-CORPUS.md + corpus/ingested/* (pinned with hashes)
Stage 2 (quote bank): EXEMPLARS.md + per-session corpus/quote-bank.md
Stage 3 (kernel):     KERNEL.md + DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md
Stage 4 (operators):  OPERATORS.md + OPERATOR-LIBRARY-COMPOSITION.md + OPERATOR-CARDS.md
Stage 5 (validators): VALIDATOR-DESIGN-PATTERNS.md + scripts/check-*.sh + audit-*.sh
                      + subagents/*-grader.md + drift-auditor.md
```

When extending the skill, your contribution should land in the appropriate artifact for its stage.

---

## Cross-references

- [/operationalizing-expertise](../../operationalizing-expertise/SKILL.md) — the upstream methodology defining Track-A
- [/sc](../../sc/SKILL.md) — sibling tool that turns an existing CLI/codebase into a `.claude/skills/*` directory
- [KERNEL.md](KERNEL.md) — the triangulated kernel
- [QUOTE-BANK-METHODOLOGY.md](QUOTE-BANK-METHODOLOGY.md) — Stage 2 deep dive
- [VALIDATOR-DESIGN-PATTERNS.md](VALIDATOR-DESIGN-PATTERNS.md) — Stage 5 deep dive
- [METHODOLOGY-EVOLUTION-LOG.md](METHODOLOGY-EVOLUTION-LOG.md) — track the methodology evolving via Track-A
- [CROSS-SESSION-LEARNING.md](CROSS-SESSION-LEARNING.md) — Phase 10 lesson commitment loop
