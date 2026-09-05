# SKILL-COMPOSITION-PATTERNS.md — Composing brennerbot with Other Skills

<!-- TOC: Why composition | Pattern: brennerbot + codebase-archaeology | + multi-pass-bug-hunting | + flywheel | + alien-graveyard | + cass + cm | + multi-model-triangulation | + dueling-idea-wizards | + lean-formal-feedback-loop | + alien-artifact-coding | Composition anti-patterns | Adding new patterns -->

brennerbot is a methodology layer over a multi-agent swarm. Its full power emerges when composed with adjacent skills that handle specific parts of the workflow.

This file documents the canonical compositions, when each is appropriate, and how to dispatch.

---

## Why composition

brennerbot's load-bearing value is the methodology (operator algebra, falsifier discipline, triangulated distillation). Other skills handle specific competencies — codebase exploration, bug hunting, idea generation, alien-CS-pattern application, formal verification.

A pure brennerbot session reproduces these competencies awkwardly. A composed session leverages the specialist skill at the appropriate phase.

---

## Pattern: brennerbot + /codebase-archaeology

**When:** code-investigation mode (Phase 1 needs codebase understanding).

**Composition:**

```
Phase 1 (brennerbot)
  → Operator dispatches /codebase-archaeology against <TARGET_REPO>
  → Output: target_inventory.md (architecture summary, top-N most-touched files, subsystem breakdown)
  → File output as corpus source S-001
  → Operator dispatches /codebase-report
  → Output: detailed architecture document
  → File as S-002
  → Phase 1 framing now has corpus baseline; operator drafts question of record

Phase 4 (brennerbot)
  → Investigators have codebase context
  → File:line citations are concrete (per OC-005 in OPERATOR-CARDS.md? — no, that's another card)
  → Each EV cites <file>:<line> + commit SHA
```

**Pre-condition:** /codebase-archaeology installed; target repo accessible.

**Dispatch:**
```bash
# Brennerbot operator (Phase 1):
Skill({skill: "codebase-archaeology", args: "explore <TARGET_REPO> for architecture-audit purposes"})
Skill({skill: "codebase-report", args: "<TARGET_REPO>"})
# Then proceed with brennerbot Phase 1 framing using outputs as corpus
```

**Anti-patterns:**
- Skip /codebase-archaeology; have brennerbot Investigators redo the work — wasteful
- Use /codebase-archaeology output as Phase 4 evidence directly without Phase 1 framing — bypasses methodology

---

## Pattern: brennerbot + /multi-pass-bug-hunting

**When:** Phase 7 audit on code in `deliverables/scripts/` (or A6 archetype).

**Composition:**

```
Phase 7 trio-round 1 (brennerbot fresh-eyes audit)
  → Audit panes file audit-findings on deliverables/

After trio-round 1:
  → Operator runs /multi-pass-bug-hunting on deliverables/scripts/*
  → /multi-pass-bug-hunting's audit-fix-rescan cycle catches additional issues
  → Each finding from /multi-pass-bug-hunting filed as audit-finding bead

Phase 7 trio-round 2 (brennerbot)
  → Verify fixes from /multi-pass-bug-hunting
  → File any remaining audit-findings
```

**Pre-condition:** /multi-pass-bug-hunting installed; code in deliverables/.

**Anti-pattern:** running /multi-pass-bug-hunting before brennerbot's first trio-round — pre-empts the methodology operator algebra.

---

## Pattern: brennerbot + /flywheel

**When:** Phase 0 / Phase 10 — mining the user's session history for relevant prior work.

**Composition:**

```
Phase 0 (pre-bootstrap, brennerbot)
  → Operator dispatches /flywheel "mine prior brennerbot sessions on <TOPIC>"
  → /flywheel scans cass + workspaces for related sessions
  → Output: list of prior workspaces, drift verdicts, persistent regressions

  → Operator decides: is this a resume-session or a fresh-question?
  → If prior session exists with verdict close to current question: recommend resume mode
  → Otherwise: fresh-question with informed cass-mining (per CASS-MINING-RECIPES.md)

Phase 10 (drift-check, brennerbot)
  → /flywheel reads CROSS-SESSION-DRIFT-CATALOG.md
  → Identifies patterns across sessions
  → Output feeds Phase 10 lesson recommendations
```

**Pre-condition:** /flywheel installed; cass indexed.

---

## Pattern: brennerbot + /alien-graveyard

**When:** Phase 4 / Phase 6 for system-design questions where buried CS breakthroughs apply.

**Composition:**

```
Phase 4 (brennerbot, design-space archetype A1)
  → Investigators reaching for novel patterns
  → Operator dispatches /alien-graveyard with current question context
  → /alien-graveyard surfaces relevant buried CS techniques (e.g., Reed-Solomon for our reliability question)
  → Each surfaced technique becomes a candidate H if relevant

Phase 6 (brennerbot)
  → Distillation considers /alien-graveyard candidates alongside organic Hs
  → Some imports may displace consensus answers
```

**Pre-condition:** /alien-graveyard installed.

**Pattern fit:** A1 (design-space), A6 (adversarial — alien attacks), T4+.

---

## Pattern: brennerbot + /cass + /cass-memory

**When:** any session where prior agent context is potentially relevant.

**Composition:**

```
Phase 0 / 1 (brennerbot)
  → `cm context "<TOPIC>" --json` via `/cass-memory` → relevant rules, antipatterns, history
  → /cass search "<TOPIC>" --robot --limit 10 → prior sessions
  → Both feed into question_of_record.md § Provenance

Phase 4 (brennerbot)
  → Investigators may /cass search additional queries during investigation
  → `cm context "investigation pattern for <archetype>" --json` via `/cass-memory` → procedural memory

Phase 9 (brennerbot)
  → After HANDBACK: `cm playbook add "<lesson>"` via `/cass-memory` to enrich memory
  → /cass automatically indexes the session
```

**Pre-condition:** `/cass` and `/cass-memory` installed; cass indexed.

**Pattern fit:** all archetypes; especially valuable for repeat-domain operators.

---

## Pattern: brennerbot + /multi-model-triangulation

**When:** Phase 6 needs a third independent reconciliation beyond the meta-synthesizer pane.

**Composition:**

```
Phase 6b (brennerbot meta-synthesis)
  → Meta-synthesizer pane drafts meta_synthesis.md
  → /disagreement-register-lint passes

Phase 6c (brennerbot, optional)
  → Operator dispatches /multi-model-triangulation
  → Inputs: distillations/by_*.md + meta_synthesis.md + disagreement_register.md
  → Output: independent third reconciliation (e.g., disagreement_register_triangulated.md)
  → Operator compares: did /multi-model-triangulation surface any disagreement the meta-synthesizer missed?
  → If yes: file additional disagreements; possibly re-run Phase 6b

Phase 7 (brennerbot)
  → Audit covers both meta_synthesis.md AND disagreement_register_triangulated.md
```

**Pre-condition:** /multi-model-triangulation installed; T3+ tier.

**Anti-pattern:** treating /multi-model-triangulation output as authoritative — it's a third opinion, not the truth.

---

## Pattern: brennerbot + /dueling-idea-wizards

**When:** Phase 3 hypothesis generation needs adversarial breadth.

**Composition:**

```
Phase 3a (brennerbot proposers)
  → Each proposer files initial Hs

After Phase 3a:
  → Operator dispatches /dueling-idea-wizards
  → /dueling-idea-wizards runs two opposing-perspective idea generators
  → Output: list of additional adversarial Hs (often the "what would the opposite be?" framing)
  → Each surviving idea-wizard H becomes a Phase 3 proposed bead with origin:adversarial

Phase 3b (brennerbot triage)
  → Triage merges duplicates, ranks
  → Adversarial Hs often serve as third-alternatives
```

**Pre-condition:** /dueling-idea-wizards installed.

**Pattern fit:** A6 (adversarial), questions where consensus capture is suspected.

---

## Pattern: brennerbot + /lean-formal-feedback-loop

**When:** Phase 4 / Phase 7 for questions involving formal correctness claims (math, security, protocol).

**Composition:**

```
Phase 4 (brennerbot)
  → Investigator filing a formal-correctness claim (e.g., "this protocol is secure under <model>")
  → Operator dispatches /lean-formal-feedback-loop
  → /lean-formal-feedback-loop attempts a Lean proof of the claim
  → Output: proof verification status (proved | counter-example | unknown)
  → File as EV with verified:true (proof) or refutes (counter-example)

Phase 7 (brennerbot audit)
  → Audit checks: did formal-correctness claims have associated proof attempts?
  → Unverified formal claims are downgraded
```

**Pre-condition:** /lean-formal-feedback-loop installed; question involves formalizable claims.

**Pattern fit:** T4+ formal-verification questions; A3 (methodology) when distilling formal methods.

---

## Pattern: brennerbot + /alien-artifact-coding

**When:** session needs frontier-model advanced math support (formal guarantees, statistical rigor).

**Composition:**

```
Phase 1 (brennerbot, T4+ session)
  → Question framing requires formal-grade claims (e.g., "calibrated tail-risk bounds")
  → Operator pre-warns: this question fits /alien-artifact-coding scope

Phase 4 (brennerbot)
  → Investigators may dispatch /alien-artifact-coding for specific formal claims
  → /alien-artifact-coding produces practical artifacts (proofs, calibrated bounds, etc)
  → File as EV with strong formal-verification provenance

Phase 6 (brennerbot)
  → Distillation incorporates formal claims with appropriate confidence
```

**Pre-condition:** /alien-artifact-coding installed; question scope requires formal rigor.

**Pattern fit:** T4-T5 sessions in math, statistics, formal verification, security.

---

## Pattern: brennerbot + /vibing-with-ntm

**When:** always (this is essentially mandatory).

**Composition:**

```
Throughout brennerbot session:
  → /vibing-with-ntm provides operator-loop tactics for swarm tending
  → /vibing-with-ntm OC-001 (rate-limit probe), OC-026 (pid audit), OC-016 (convergence triple-check) etc.
  → brennerbot delegates ALL pane-state recovery to /vibing-with-ntm

Specifically:
  → Stuck pane (any phase): /vibing-with-ntm OC-003 stuck-pane ladder
  → Rate limited: /vibing-with-ntm OC-002 rotate
  → Saturated context: /vibing-with-ntm OC-009 + brennerbot's MO-context-saturated-rotation
  → Cross-session contention: /vibing-with-ntm OC-031
```

This is so deeply intertwined that brennerbot SKILL.md explicitly defers all pane-state issues to /vibing-with-ntm.

---

## Pattern: brennerbot + /idea-wizard

**When:** Phase 3 for breadth, especially when proposers risk anchoring on consensus.

**Composition:**

```
Phase 3a (brennerbot, per MO-03a-propose.md)
  → Proposer pane invokes idea-wizard (via subagents/idea-generator.md)
  → /idea-wizard expands hypothesis space; ≥10 candidates
  → Proposer filters for falsifiability (per CRITIQUE-CRAFT.md severity)
  → Files surviving candidates as H beads
```

**Pre-condition:** /idea-wizard installed.

**Pattern fit:** all archetypes when generation breadth matters.

---

## Pattern: brennerbot + /reality-check-for-project

**When:** code-investigation mode where target has README/plan claims.

**Composition:**

```
Phase 1 (brennerbot, code-investigation)
  → /reality-check-for-project runs against target
  → Output: claimed features vs actual state
  → File as corpus source S-XXX with anchor scheme

Phase 7 (brennerbot audit)
  → Cross-reference: did Phase 4 evidence packs cite the reality-check findings?
  → If gaps: audit-finding
```

**Pre-condition:** /reality-check-for-project installed; target has documented claims.

**Pattern fit:** A2 codebase weakness audit.

---

## Pattern: brennerbot + /modes-of-reasoning-project-analysis

**When:** Phase 6 distillation for theory-heavy questions.

**Composition:**

```
Phase 6 (brennerbot)
  → Synthesizers produce per-family distillations
  → Operator dispatches /modes-of-reasoning-project-analysis
  → Output: lens-by-lens analysis (symbolic vs neural, fast vs deep, etc)
  → Each lens informs disagreement_register entries
```

**Pre-condition:** /modes-of-reasoning-project-analysis installed; question is theory-heavy.

**Pattern fit:** A3 methodology distillation, A10 first-principles.

---

## Pattern: brennerbot + /testing-* skills (metamorphic, fuzzing, conformance, golden, no-mocks)

**When:** Phase 9 deliverables include code or specifications.

**Composition:**

```
Post-Phase-7 (brennerbot)
  → For code in deliverables/scripts/:
    - /testing-fuzzing for robustness probes
    - /testing-conformance-harnesses for spec compliance
    - /testing-golden-artifacts for snapshot regression tests
  → Each test failure becomes audit-finding

Phase 9 (brennerbot)
  → HANDBACK includes test coverage attestation
```

**Pre-condition:** appropriate /testing-* skill installed; code present in deliverables.

---

## Composition anti-patterns

| ✗ | Why |
|---|-----|
| Compose every available skill "to be thorough" | Burns context; each skill costs token + dispatch overhead |
| Skip composition for T1-T2 questions | Most compositions assume T3+ stakes; T1-T2 may not justify the overhead |
| Compose adversarial skills (red-team, alien-graveyard) at Phase 1 framing | Adversarial belongs at Phase 7 audit, not framing |
| Compose without explicit decision-rule | Per CASS-MINING-RECIPES.md discipline: every external skill dispatch needs a decision rule |
| Treat composed skill output as truth | Each composed skill is one perspective; brennerbot's methodology is the integration layer |
| Bypass brennerbot's Phase 1 to "save time" with composed skills | Skipping framing produces unsound sessions even with elite tooling |

---

## Adding new composition patterns

When a session reveals a useful new composition:

1. Document the trigger condition (when this composition applies)
2. Document the dispatch sequence
3. Document the pre-conditions
4. Document the anti-patterns
5. Add as a Phase 10 lesson; commit to this file

The catalog grows as operators discover compositions. After ≥3 sessions using the same composition, it's promotable to canonical (per CROSS-SESSION-LEARNING.md).

---

## When brennerbot is NOT the right tool

Some questions are fully answered by composition without brennerbot:

- "Find bugs in this code" → /multi-pass-bug-hunting + /ubs alone
- "Just give me ideas" → /idea-wizard alone
- "What's our session history on X" → /cass alone

brennerbot adds value when the question requires *triangulated falsifiable investigation* — that's specifically when the methodology (axioms, operators, phase loop) is load-bearing.

When in doubt: T1-T2 questions often fit composition-only; T3+ usually warrants brennerbot. Defer to TIER-TRIAGE.md.
