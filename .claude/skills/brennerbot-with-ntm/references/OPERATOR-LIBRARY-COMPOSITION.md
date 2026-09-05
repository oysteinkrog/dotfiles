# OPERATOR-LIBRARY-COMPOSITION.md — Composing the 15 Cognitive Operators

<!-- TOC: Why composition | Operator pairs | Operator chains | Phase-specific compositions | Per-archetype compositions | Composition anti-patterns | Worked examples | Mathematical structure | Operator emergence -->

Per OPERATORS.md, brennerbot's 15-operator algebra (◊ ⊘ 𝓛 ≡ ✂ ⟂ ↑ ⌂ 🔧 ⊞ 🤝 ΔE † ∿ ⊙) is more than a flat list. The operators *compose* — applying them in specific sequences or combinations produces effects that any single operator can't.

This file documents the canonical compositions and the composition discipline.

---

## Why composition

Single operators are insufficient. ✂ Exclusion-Test alone produces a slate of unfalsified claims; without 𝓛 Recode, the claims may be incoherent. ◊ Paradox-Hunt without ⊘ Level-Split surfaces only surface-level paradoxes; without ≡ Invariant-Extract, the paradoxes don't translate to testable claims.

Operator composition is the methodology's emergent power. Per Brenner's transcript:

> "I would propose; Crick would attack; we would reformulate; we would split; we would test."

This sequence is not arbitrary. Each step prepares the next. Composition is the *order of operations* of the methodology.

---

## Operator pairs (the 2-step combos)

The 15 operators have natural pairs:

### ◊ ↦ ⊘ (Paradox + Level-Split)

When a paradox arises, the resolution is often: the paradox holds at one level, dissolves at another.

Brenner exemplar: "How can a system be both deterministic AND sensitive to initial conditions?" (◊). Resolution: deterministic at the *equation* level; sensitive at the *trajectory* level. (⊘)

In brennerbot:
- Phase 1 framing surfaces a paradox (◊).
- Phase 3 Investigators apply ⊘ Level-Split to resolve.
- Result: a richer hypothesis slate that includes "the paradox dissolves when we frame at level X".

### 𝓛 ↦ ≡ (Recode + Invariant-Extract)

To recode is to restate in your own words. The act of restating surfaces invariants the original phrasing hid.

Brenner exemplar: "DNA stores information" (original) → "DNA preserves a sequence under replication" (recoded) → "the invariant is sequence preservation; the storage mechanism is incidental" (extract).

In brennerbot:
- Phase 6 distillation: each family recodes the question's claims.
- Cross-family meta-synthesis: invariants emerge from different recodings.
- Anti-F-601 silent averaging: distinct recodings preserve distinctness.

### ✂ ↦ † (Exclusion-Test + Theory-Kill)

Exclusion is the discipline; killing is the action. ✂ produces a falsifier-firing observation; † records the H state flip.

In brennerbot:
- Phase 4 Investigator runs ✂ probe.
- If falsifier fires: † by Adjudicator (per F-501 rotation rule).
- Per `MO-falsifier-fired.md`, the kill is bead-recorded.

### 🤝 ↦ ΔE (GAN + Exception-Quarantine)

The GAN produces critiques; some surface anomalies. ΔE quarantines anomalies that don't fit the main theory.

In brennerbot:
- Phase 4 GAN produces critiques.
- A critique that surfaces an anomaly cluster (per Brenner §110) → file as `anomaly` bead with ΔE quarantine.
- Don't patch the anomaly INTO the theory; keep separated. (Anti-patch behavior.)

### ⊞ ↦ 🔧 (Scale-Check + DIY)

Scale-checking with a calculation is theory; ⊞ → 🔧 is theory + practice. After a scale-physics calculation, run the actual experiment.

In brennerbot:
- Investigator computes "memory bandwidth saturates at 100GB/s" (⊞).
- DIY: run a microbenchmark to verify (🔧).
- Per MO-academic-replication, this is the standard for load-bearing scale claims.

### ⊕ ↦ ⌂ (Cross-Domain Import + Materialize)

Cross-domain patterns are abstract; ⌂ Materialize makes them specific to our regime.

In brennerbot:
- Investigator imports a queueing-theory pattern (⊕).
- Materialize: instantiate the pattern with our specific workload parameters (⌂).
- Per OC-013 OPERATOR-CARDS.md.

---

## Operator chains (3+ step combos)

### Investigation chain: ◊ → ⊘ → 𝓛 → ✂

Standard Phase 4 investigation:
1. ◊ Identify the paradox (why is this hard?)
2. ⊘ Split into levels
3. 𝓛 Recode each level
4. ✂ Test each recoded level

This chain is the per-H investigation default. Per MO-04a-investigate.md.

### Distillation chain: 𝓛 → ≡ → ⊘ → ↑

Phase 6 distillation per family:
1. 𝓛 Recode the corpus claims
2. ≡ Extract invariants from recodings
3. ⊘ Split invariants by level (which apply at workload class W; which at W')
4. ↑ Amplify the invariants that hold across levels

Per MO-06a-distill.md.

### Audit chain: ∿ → ✂ → † → ΔE

Phase 7 audit:
1. ∿ Dephase: did we reproduce a consensus prior?
2. ✂ Re-verify: do load-bearing EVs still fire their falsifiers?
3. † If audit reveals a confirmed H is actually unsupported: kill it
4. ΔE Quarantine new anomalies surfaced by audit

Per MO-07a-fresh-eyes.md and OC-019 OPERATOR-CARDS.md.

### GAN chain: 🤝 → ✂ → 𝓛 → 🤝 (recursive)

Phase 5 debate:
1. 🤝 Generator proposes; Discriminator attacks
2. ✂ Discriminator's attack is falsifier-firing or not
3. 𝓛 Generator recodes to address attack
4. 🤝 Repeat until convergence

The recursion bottoms out at: H state flip (kill) OR survives-with-stronger-evidence.

---

## Phase-specific compositions

### Phase 1: ◊ → ≡

- ◊ Identify the question's paradox
- ≡ Extract the invariants the question depends on
- Output: question_of_record.md with non-empty Paradox section

### Phase 2: (no operators; just bootstrap)

### Phase 3: ◊ → ⊘ → ⊙

- ◊ Each Proposer hunts for paradoxes in the question
- ⊘ Surface alternatives at different levels
- ⊙ One pane operates without corpus access (productive ignorance) — surfaces first-principles alternative

### Phase 4: 🤝 → (◊ ⊘ 𝓛 ✂) → ΔE

- 🤝 GAN structure for each H
- The (◊ ⊘ 𝓛 ✂) inner chain runs per investigation
- ΔE absorbs anomalies that don't fit

### Phase 5: 🤝 → † (or maintain)

- Adjudicator runs the GAN to its conclusion
- Outcome: kill (†) or maintain (with evidence)

### Phase 6: 𝓛 → ≡ → ⊕ → ↑

- Per-family 𝓛 + ≡ produces distillation
- Cross-family ⊕ surfaces convergent kernel
- ↑ Amplify the convergent claims

### Phase 7: ∿ → ✂ → ⊞ → 𝓛

- ∿ Dephase from consensus capture
- ✂ Re-verify falsifiers
- ⊞ Re-check scale assumptions
- 𝓛 Re-state findings to surface inconsistencies

### Phase 8-10: (administrative; few operators)

---

## Per-archetype compositions

Per QUESTION-ARCHETYPES.md A1-A10:

### A1 design-space

Heavy use of: ⊕ ⊞ 🔧 ⊘
- Cross-domain imports (⊕)
- Scale-check on each candidate (⊞)
- DIY benchmarks (🔧)
- Level-split for hybrid designs (⊘)

### A2 codebase

Heavy use of: ⊘ ≡ 𝓛
- Level-split (interface vs implementation, layer hierarchy)
- Invariant-extract (what does this code preserve?)
- Recode (paraphrase function purpose; surfaces misuse)

### A3 methodology

Heavy use of: 𝓛 ≡ ⊕ †
- Recode papers' claims
- Extract invariants
- Cross-domain imports
- Theory-kill on failed claims

### A4 incident

Heavy use of: ⊘ ◊ ✂ ΔE
- Level-split (network / app / DB / human)
- Paradox-hunt (what assumption broke?)
- Exclusion-test
- Anomaly quarantine

### A5 distillation

Heavy use of: 𝓛 ≡ ↑
- Recode + extract + amplify

### A6 adversarial

Heavy use of: 🤝 ◊ ⊕ 🤝 (recursive)
- GAN heavy
- Paradox-hunt for attack patterns
- Cross-domain attack imports

### A7 decision

Heavy use of: ✂ ⊞ ⌂
- Exclusion-test each option
- Scale-check at decision horizons
- Materialize specific consequences

### A8 verification

Heavy use of: ✂ ≡ 🔧
- Each claim has explicit falsifier
- Invariants extracted
- DIY measurements

### A9 scaling

Heavy use of: ⊞ ⊘ 🔧
- Scale-physics-heavy
- Level-split per scale regime
- DIY at multiple scales

### A10 first-principles

Heavy use of: ⊙ ◊ ≡
- Productive-ignorance (one pane reads only the question)
- Paradox-hunt
- Invariant-extract from scratch

---

## Composition anti-patterns

| ✗ | Why |
|---|-----|
| Apply ✂ without 𝓛 first | Tests claims that may be incoherent (waste) |
| Apply † without ✂ | Killing without falsifier evidence (rhetoric) |
| Apply ⊕ without ⌂ | Imports abstract patterns; doesn't apply them to our regime |
| Apply 🤝 without family-distinctness | F-504 same-family champions (defeats GAN) |
| Apply ⊞ without 🔧 | Scale theory without empirical check |
| Apply ↑ without ≡ | Amplifies surface phrasing, not invariants |
| Apply ◊ without ⊘ | Surface paradoxes that don't resolve |

---

## Mathematical structure

The 15 operators form a partial order under composition:

```
Lower (more concrete) ──→ Higher (more abstract)

◊ Paradox  ←  ⊘ Level  ←  𝓛 Recode  ←  ≡ Invariant
                                          ↓
                          ↑ Amplify  →  ⌂ Materialize
                                         ↓
                                       🔧 DIY
```

```
✂ Exclusion  →  † Theory-Kill
🤝 GAN       →  ✂ + 𝓛 (per round)
ΔE Quarantine ⊥ † (orthogonal: anomalies aren't refuting theory)
∿ Dephase    ⊥ † (orthogonal: dephase questions assumption, not claims)
⊙ Productive-Ignorance ⊥ all (specifically violates corpus-grounding)
```

This structure suggests:
- Concrete operators (◊ ⊘ 𝓛) prepare data for abstract operators (≡ ↑ ⌂)
- Test operators (✂ †) work on prepared claims
- Discipline operators (🤝 ΔE ∿ ⊙) constrain the methodology

---

## Operator emergence (when to invent new operators)

The 15 operators distill the existing literature (Brenner transcript, peer methodologies, /operationalizing-expertise). New operators may emerge:

- When ≥3 sessions surface a recurring pattern that none of the 15 cleanly capture
- When a new domain (e.g., game theory) introduces operators (e.g., Backward Induction) that don't reduce to the 15

If you encounter a candidate new operator:

1. Document the pattern across 3+ sessions
2. Try to reduce to existing 15-operator algebra
3. If irreducible: propose to OPERATORS.md as a new operator with: trigger, recipe, marching-order module, validator, failure mode (per /operationalizing-expertise)
4. Test in subsequent sessions
5. Promote to canonical after 3+ sessions of stable use

The algebra is not closed; it can grow. But the bar is high (≥3 sessions of unique value).

---

## Worked examples

### Example: investigating "why is our system slow"

Phase 1 framing applies ◊ ≡:
- ◊ Paradox: "It was fast yesterday and slow today; nothing obvious changed."
- ≡ Invariant: "Workload class hasn't changed; deploy at 14:18 is the only event."

Phase 4 investigation applies 🤝 → (◊ ⊘ 𝓛 ✂):
- 🤝 Investigator p1 (cc): "Deploy introduced new code path." Devil's-Advocate p2 (gmi): "Code path looks identical to prior deploy; what specifically?"
- ◊ Sub-paradox: "Code path identical, but slow today; time-of-day not regular."
- ⊘ Level-split: "App level: identical. Storage level: different (new index)."
- 𝓛 Recode: "The new index is fast in isolation but slow under our specific query pattern."
- ✂ Test: benchmark old vs new index under our query pattern.

Phase 5 adjudication applies † (kill old hypothesis "code change") and maintain new ("index change").

Phase 7 audit applies ∿:
- ∿ Dephase: "Did we reproduce a consensus answer (`it's the deploy`)? Or genuinely test it? We did genuinely test."

This worked example shows the composition as a directed sequence.

---

## Cross-references

- OPERATORS.md (the 15 individual cards)
- KERNEL.md (the axioms that operators apply)
- QUESTION-ARCHETYPES.md (per-archetype operator emphases)
- /operationalizing-expertise (the Track-A pattern that built the operator library)
- BRENNER-GAN-MECHANICS.md (the 🤝 deep dive)
- The Brenner transcript (per SOURCE-CORPUS.md) — composition exemplars
