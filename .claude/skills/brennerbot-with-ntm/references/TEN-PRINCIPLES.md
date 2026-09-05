# TEN-PRINCIPLES.md — The Brenner Method in Ten Principles

<!-- TOC: Why ten principles | The principles | Per-principle application in brennerbot | Per-principle anti-patterns | Composition with operators | When the principles disagree | Cross-references -->

A compact summary of the Brenner method, suitable for tick-time reference. When choosing between phases, dispatches, or recovery actions, the matching principle should win.

Mined from `/dp/brenner_bot/README.md § The Brenner Method: Ten Principles` and triangulated against the three expert distillations.

---

## Why ten principles

Operators benefit from a *short* canonical list they can hold in working memory during ticks. The 15-operator algebra in OPERATORS.md is comprehensive but heavy; the BRENNER-VOCABULARY.md is rich but broad. The Ten Principles are the *bare minimum* a brennerbot operator must internalize.

For new operators (per OPERATOR-ONBOARDING-CURRICULUM.md Week 1), memorize these. For experienced operators, they're a tick-time tiebreaker when phases compete.

---

## The principles

### 1. Enter problems as an outsider

> Embrace productive ignorance; émigrés make the best discoveries.

Experts have *overly tight* probability mass on known solutions. Outsiders distribute prior mass evenly across alternatives. Per ⊙ Productive-Ignorance operator and CONFIDENCE-SCORING.md.

**In brennerbot:** the ⊙ pane (productive-ignorance) deliberately *doesn't* read corpus. Its hypothesis emerges from first-principles, unconstrained by what the field already says. Per OC-005 in OPERATOR-CARDS.md. Often produces the third-alternative that wins (per EXEMPLAR-SESSION-WALKTHROUGH.md).

### 2. Reduce dimensionality

> Find the representation that transforms the problem into algebra.

3D problems become 1D when you find the right encoding. Continuous becomes discrete. High-dimensional becomes low-dimensional. Per 𝓛 Recode operator.

**In brennerbot:** Phase 3 hypothesis generation (MO-03a) explicitly asks panes "can you state this in lower-dimensional terms?" Per BRENNER-VOCABULARY.md "Dimensional reduction." When a hypothesis can't be reduced, suspect the framing is wrong.

### 3. Go digital

> Choose systems with qualitative differences; avoid statistics where possible.

Per the "seven-cycle log paper" test: if you can SEE the difference, it's significant. If you need statistics, the effect is too small or you're measuring the wrong thing.

**In brennerbot:** EV beads should produce digital handles when possible. Per CRITIQUE-CRAFT.md severity calibration: "marginal difference under controlled conditions" is `severity:moderate`; "qualitative regime change" is `severity:critical`.

### 4. Defer secondary problems (Don't Worry)

> Don't worry about mechanisms you can't yet see; assume they exist.

Per Brenner: "Don't worry about unwinding; assume an enzyme exists." Theory development proceeds *despite* missing pieces, but the missing pieces go on the assumption ledger.

**In brennerbot:** Phase 4 investigation routinely encounters "we'd need X to know" situations. The discipline: file as `A-NNN` assumption bead with `type: dont_worry; falsifier: <observable>` rather than blocking the investigation. Per BRENNER-VOCABULARY.md "Don't Worry hypothesis."

### 5. Materialize immediately

> Ask "what experiment would test this?" before theorizing further.

Per ⌂ Materialize operator. The compilation step from theory to decision procedure. Without materialization, theories drift into vapor.

**In brennerbot:** every H bead must have an `expected_evidence:` field — the materialized prediction. Per BEADS-SCHEMA.md. Without this field, the H is in pre-Phase-1 state (unframed).

### 6. Build what you need

> Crude apparatus that works beats elegant apparatus you're waiting for.

Per 🔧 DIY operator. The "infrastructure-economy" rule: low-tech tools you can deploy now beat high-tech tools that arrive next quarter.

**In brennerbot:** if a quickie pilot can be run with `bash` + `jq`, don't wait for the perfect dashboard. Per MO-quickie-pilot.md. Per /vibing-with-ntm OC-029 build-what-you-need.

### 7. Think out loud

> Ideas are 50% wrong the first time; conversation is a thinking technology.

Per the 🤝 GAN operator. The Crick-Brenner GAN: generation + adversarial discrimination is faster than internal monologue.

**In brennerbot:** Phase 5 cross-examination IS this principle. Per BRENNER-GAN-MECHANICS.md. Phase 5 is not optional; thinking-out-loud catches errors that panes wouldn't catch alone.

### 8. Stay imprisoned in physics

> Calculate scale; respect mechanism; filter impossible cartoons.

Per ⊞ Scale-Check operator. Architectural arguments without scale-physics calculation are speculation. The "imprisoned imagination" rule: the answer must obey physics.

**In brennerbot:** every assumption bead with `type:scale_physics` MUST have an explicit calculation. Per Phase 7 audit OC-021 + AE-7.7. Without scale-physics, distillation is fan-fiction.

### 9. Distinguish information from implementation

> Separate the program from the interpreter (von Neumann's insight).

Per ⊘ Level-Split operator. Confusing levels is the most common methodology failure (per F-301 false-binary detection).

**In brennerbot:** Phase 3 third-alternative discipline often surfaces as "we conflated levels — H-001 is at level L1, H-005 is at level L2, the answer depends on which level the question is at." Per OC-006 in OPERATOR-CARDS.md.

### 10. Play with words and inversions

> Puns and inversions train mental flexibility.

Per Brenner's own practice: linguistic play surfaces conceptual fixedness. "What if the obvious interpretation is wrong?"

**In brennerbot:** the third-alternative MO (MO-03c) explicitly asks "what's the inversion of H-001?" If you can't articulate the inversion, you don't yet understand H-001.

---

## Per-principle application in brennerbot

| # | Principle | Phase most active | MO that exemplifies | Operator |
|---|-----------|-------------------|---------------------|----------|
| 1 | Outsider entry | 3 (Phase 3 ⊙ pane) | MO-03c (third-alternative) | ⊙ |
| 2 | Reduce dimensionality | 3, 6 (distillation) | MO-06b meta-synthesis | 𝓛 |
| 3 | Go digital | 4 (evidence packs) | MO-04c evidence-pack | ⌂ + ⊞ |
| 4 | Don't Worry | 4 (assumption ledger) | (no MO; bead schema) | (assumption-typed) |
| 5 | Materialize | 1, 4 | MO-01 (falsifier in framing); MO-04a | ⌂ |
| 6 | DIY | 4 (quickie probes) | MO-quickie-pilot | 🔧 |
| 7 | Think out loud | 5 (debate) | MO-05a cross-exam | 🤝 |
| 8 | Imprisoned in physics | 4, 7 | (every scale_physics A-bead) | ⊞ |
| 9 | Information vs implementation | 3 (third alt), 6 (recode) | MO-03c, MO-06a | ⊘ |
| 10 | Words / inversions | 3, 4 | MO-03c, MO-cross-domain-import | (composes with ⊕ + ⊘) |

---

## Per-principle anti-patterns

### #1 anti-pattern: hire-the-expert

Letting the corpus / consensus dominate. Per F-403 confirmation bias. Mitigation: ⊙ pane.

### #2 anti-pattern: complexification

Adding dimensions to "be complete" rather than reducing. Per the F-302 hypothesis-duplication risk. Mitigation: explicit "what's the lower-dim version?" check.

### #3 anti-pattern: marginal-effect chasing

Designing experiments that need 10000 samples to detect 2% effects. Per AE-1.2 (unfalsifiable in PHASE-1-ANTI-EXAMPLES.md). Mitigation: prefer digital handles or skip the question.

### #4 anti-pattern: Don't-Worry abuse

Using "Don't Worry" to handwave permanently instead of as a deferral mechanism. Per audit-finding rubric: every Don't-Worry must have a corresponding assumption ledger entry.

### #5 anti-pattern: theory-without-test

Long theoretical arguments without "what would I see?" Per F-103 (no falsifier). Mitigation: refuse to advance Phase 1 without falsifier.

### #6 anti-pattern: infrastructure-blocking

"We can't investigate until X is built." Per ⊞ Scale-Check + 🔧 DIY: the answer often comes from the crude tool. Mitigation: MO-quickie-pilot.

### #7 anti-pattern: solitary-genius

Refusing to debate hypotheses; "I'll figure it out." Per F-501 (adjudicator never kills). Mitigation: 🤝 GAN must be enforced.

### #8 anti-pattern: hand-wave-physics

"Approximately X, give or take an order of magnitude." Per AE-7.7 in PHASE-7-ANTI-EXAMPLES.md. Mitigation: every scale-physics assumption gets explicit calculation.

### #9 anti-pattern: level-confusion

Conflating gene-and-behavior, message-and-machine, regulation-and-structure. Per F-301. Mitigation: ⊘ Level-Split applied early.

### #10 anti-pattern: literal-thinking

Refusing to invert or rename. "The obvious interpretation must be right." Per AE-1.5 (confirmation-seeking). Mitigation: MO-03c is mandatory.

---

## Composition with operators

The Ten Principles distill to operators (per the table above). When you internalize the principles, the operators come naturally:

```
Principle 1 (Outsider) ↔ ⊙ Productive-Ignorance
Principle 2 (Reduce)   ↔ 𝓛 Recode + ≡ Invariant-Extract
Principle 3 (Digital)  ↔ ✂ Exclusion-Test (digital handles)
Principle 4 (Defer)    ↔ (assumption-ledger discipline; ΔE Quarantine)
Principle 5 (Material.) ↔ ⌂ Materialize
Principle 6 (DIY)      ↔ 🔧 DIY
Principle 7 (Talk)     ↔ 🤝 GAN
Principle 8 (Physics)  ↔ ⊞ Scale-Check
Principle 9 (Levels)   ↔ ⊘ Level-Split
Principle 10 (Inverse) ↔ ◊ Paradox-Hunt + ⊕ Cross-Domain Import
```

10 principles × 13 operators (excluding ↑ Amplify and ∿ Dephase which are *meta-operators* about HOW to apply).

---

## When the principles disagree

Tick-time conflicts between principles surface regularly:

- **#3 (digital) vs #2 (reduce dimensionality)** — sometimes digital handles require higher-dimensional thinking. Resolution: dimensionality reduction wins in framing; digital handles win in test design.
- **#4 (Don't Worry) vs #5 (Materialize)** — Don't Worry defers; Materialize demands "what would I see?" Resolution: Don't Worry the missing piece, but materialize the testable consequences AROUND the missing piece.
- **#1 (outsider) vs #8 (imprisoned in physics)** — outsiders often violate physics through inexperience. Resolution: ⊙ pane is exempt from corpus-reading but NOT from scale-physics calculation. Per MO-02 onboarding for ⊙ panes.
- **#7 (talk it out) vs operator's wall-time budget** — debate burns time. Resolution: WALL-TIME-BUDGET T3 phase 5 ≤17%. If hitting that cap, force adjudicator decision per MO-debate-deadlock-resolution.

When in doubt, the One Rule (per SKILL.md) governs: maximize *(expected mind-change × downstream option value) / (time × cost × ambiguity × infrastructure-dependence)*.

---

## Stress-testing your understanding

For each principle, can you state:
1. The Brenner exemplar from the transcripts (per SOURCE-CORPUS.md)?
2. The operator(s) it maps to?
3. The phase(s) where it's most active?
4. The anti-pattern that violates it?
5. A concrete brennerbot mechanism that enforces it?

If you can answer all five for each principle, you're operating at OPERATOR-ONBOARDING-CURRICULUM.md Week 4 fluency.

---

## Cross-references

- [OPERATORS.md](OPERATORS.md) — the 15-operator formal algebra
- [BRENNER-VOCABULARY.md](BRENNER-VOCABULARY.md) — the broader vocabulary
- [REQUIRED-CONTRADICTIONS.md](REQUIRED-CONTRADICTIONS.md) — the meta-discipline of oscillation
- [BAYESIAN-FRAMEWORK.md](BAYESIAN-FRAMEWORK.md) — the implicit probability framework
- [PHASES.md](PHASES.md) — phase-by-phase deep dive
- [PHASE-1-ANTI-EXAMPLES.md](PHASE-1-ANTI-EXAMPLES.md) and [PHASE-7-ANTI-EXAMPLES.md](PHASE-7-ANTI-EXAMPLES.md) — concrete failure modes
- [OPERATOR-ONBOARDING-CURRICULUM.md](OPERATOR-ONBOARDING-CURRICULUM.md) — Week 1 reading list (these principles)
- /dp/brenner_bot/README.md § The Brenner Method: Ten Principles — original source
