# QUOTE-BANK-METHODOLOGY.md — Building and Using Quote Banks (Track-A Pattern)

<!-- TOC: Why a quote bank | The Track-A pattern | Quote schema | Sourcing | Categorization | Anti-cherry-picking | Per-question quote bank | Operator-library mapping | Validators | Composition | Maintenance | Anti-patterns -->

Per /operationalizing-expertise: the load-bearing artifact in Track-A pattern is the **quote bank** — a curated set of verbatim quotes from authoritative sources, indexed by topic + operator + claim type. The quote bank powers the triangulated kernel and validates the operator library.

This file documents the methodology for building, using, and maintaining quote banks within brennerbot sessions.

---

## Why a quote bank

Brennerbot operates on EV-NNN beads with verbatim quotes. Without a quote bank methodology:

- Verbatim quotes scatter across many EVs without cross-referencing
- Multiple sessions on similar topics re-extract the same quotes (waste)
- Cross-session reconciliation can't tell whether two sessions used the same evidence
- The "triangulated kernel" emerges only at session end, not as a reusable artifact

With a quote bank:

- Quotes are categorized once and reused across sessions
- The kernel becomes auditable (which quotes support which claims?)
- Cross-session learning compounds (per CROSS-SESSION-LEARNING.md)
- New operators learn faster (existing quote bank is a corpus)

---

## The Track-A pattern

Per /operationalizing-expertise:

```
Source corpus → Quote bank → Triangulated kernel → Operator library → Validators
       ↓             ↓              ↓                    ↓                ↓
       Read       Extract       Distill            Codify         Verify
```

### Stage 1: Source corpus

Pin authoritative sources (papers, books, talks, code) with content hashes. Per SOURCE-CORPUS.md.

### Stage 2: Quote bank

For each load-bearing claim in the corpus, extract the verbatim quote that supports it. Tag with:
- Source ID + section anchor
- Operator(s) it exemplifies
- Claim type (axiom / heuristic / counterexample / methodology)

Stored in `corpus/quote-bank.md` (per workspace) and may be promoted to skill-level reference.

### Stage 3: Triangulated kernel

Cross-reference quotes from ≥3 sources for each major claim. Per Brenner's distillation methodology (per KERNEL.md), the kernel comprises only claims supported by ≥3 independent sources.

### Stage 4: Operator library

Per OPERATORS.md, each operator (◊ ⊘ 𝓛 ≡ ✂ ⟂ ↑ ⌂ 🔧 ⊞ 🤝 ΔE † ∿ ⊙) has trigger / recipe / failure mode. The quote bank evidences each operator with verbatim quotes from the source corpus.

### Stage 5: Validators

For each operator, derive a validator: what observable would prove the operator was correctly applied? These become the basis for `scripts/audit-bead-invariants.sh`, `scripts/check-rotation-rules.sh`, etc.

---

## Quote schema

Each quote in the quote bank:

```markdown
## Q-NNN: <one-line claim being evidenced>

**Source:** <source_id> (<title>; <author>; <year>)
**Section:** §<anchor> (<page or chapter>)
**Operator(s) exemplified:** ◊ <Paradox-Hunt> | ⊘ <Level-Split> | ...
**Claim type:** axiom | heuristic | counterexample | methodology

**Verbatim quote:**

> "<exact text from source>"

**Why this quote matters:**

<one-paragraph: what this quote evidences, what would refute it>

**Cross-references:**

- Q-NNN: same operator, different source (triangulation)
- Q-NNN: counterexample / refutation
- H-NNN (in current session): hypothesis this quote supports/refutes

**Provenance:**

- Extracted at: <ISO>
- Extracted by: <operator name or pane>
- Verified: <yes/no>
- Verified by: <pane> at <ISO>
- Hash of source at extraction: <sha256>
```

---

## Sourcing

### Where to extract quotes from

**Tier 1 (highest authority):**
- Original primary sources (papers by the work's authors)
- Verified machine-checked formal proofs
- Your own measurements under controlled conditions

**Tier 2 (high authority):**
- Peer-reviewed surveys/textbooks by domain experts
- Reference implementations by the original authors
- Reproduced experiments with documented protocol

**Tier 3 (medium authority):**
- Engineering blogs from major companies (Netflix, Google, Stripe)
- Industry whitepapers
- Conference talks by domain experts

**Tier 4 (lower authority):**
- Single-author engineering blogs
- Stack Overflow answers
- Forum threads

(Per EVIDENCE-WEIGHTING-TAXONOMY.md, this maps to W_source.)

### What to extract

Extract a quote when:
- It states a load-bearing axiom or heuristic concisely
- It provides a counterexample to a common belief
- It documents a methodology with specific procedure
- It cites a constraint or limit explicitly

DON'T extract when:
- The quote is rhetoric without evidence
- The quote is a citation to a paper you haven't read
- The quote restates common knowledge
- The quote is a fig-leaf hedge ("some studies suggest...")

### Quote length

- **Short quotes (1-3 sentences)**: prefer for axiom-class claims
- **Medium quotes (1 paragraph)**: for heuristic-class claims with reasoning
- **Long quotes (multi-paragraph)**: for methodology-class claims with procedure

Don't quote longer than necessary; the operator brain budget is finite.

---

## Categorization

### By operator

Per OPERATORS.md's 15 operators. Each quote tagged with which operator(s) it exemplifies.

Example:
```
Q-014: "The first thing to do is to find a counterexample. If there isn't one, the theory is too vague."
- Operator: ✂ Exclusion-Test
- Source: Brenner transcript §147
- Claim type: heuristic
```

### By claim type

- **Axiom**: foundational principle (e.g., "Reality has a generative grammar")
- **Heuristic**: practical guidance (e.g., "Run a small experiment yourself")
- **Counterexample**: case that refutes a common belief
- **Methodology**: specific procedure

### By domain

For domain-specific quote banks (e.g., distributed systems, ML, biology):

```
corpus/quote-bank/
├── general/         # cross-domain
├── distributed-systems/
├── ml/
├── biology/
└── ...
```

---

## Anti-cherry-picking

A common failure: extract only quotes that support your prior conclusion.

### Defense

1. **Mandate cross-references**: each quote MUST cite ≥1 quote that disagrees or qualifies it (or note "no disagreement found in corpus" with explicit search).

2. **Audit by adversarial pane**: per Phase 7, an adversarial pane reviews the quote bank: did the extractor cherry-pick? Is the disagreement register thin?

3. **Coverage check**: for each operator, the quote bank should have quotes from ≥3 independent sources. If one source dominates, extract more from others to balance.

4. **Inverse search**: for each axiom, explicitly search the corpus for counterexamples. Document what you find OR document the absence.

---

## Per-question quote bank

For T2+ sessions, build a per-session quote bank in `corpus/quote-bank.md`:

```markdown
# Quote Bank — RS-2026-05-12-checkout-latency

## Pinned sources

| Source ID | Title | Author | Year | Hash |
|-----------|-------|--------|------|------|
| S-001 | "Latency is everywhere" | Vogels | 2018 | sha256:... |
| S-002 | Patel et al. 2024 perf paper | Patel | 2024 | sha256:... |

## Quotes by operator

### ⊞ Scale-Check
- Q-001 (per S-001 §3): "Latency at scale is dominated by tail behavior, not mean."
- Q-002 (per S-002 §5): "p99 grows super-linearly with QPS past saturation point."

### ✂ Exclusion-Test
- Q-003 (per S-001 §7): "If your hypothesis explains why p50 is fast but doesn't explain why p99 is slow, your hypothesis is incomplete."

## Per-H mapping

- H-001 (DB connection pool): supported by Q-002 (saturation behavior).
- H-002 (downstream latency): supported by Q-001 (tail vs mean distinction).
- H-003 (GC pause): refuted by lack of counterexample (no quote supports the dominance claim).
```

Update as Phase 4 surfaces new evidence.

---

## Operator-library mapping

Per OPERATORS.md, each operator has 5 elements: trigger / recipe / marching-order module / validator / failure mode. The quote bank evidences each.

Example for ✂ Exclusion-Test:

| Element | Quote bank entry |
|---------|------------------|
| Trigger | Q-014 (Brenner §147): "The first thing to do is find a counterexample." |
| Recipe | Q-022 (Crick 1965): "Design experiments that distinguish between hypotheses, not those that confirm one." |
| Marching-order module | Q-031 (Popper §54): "Test the hypothesis by attempting to refute it." |
| Validator | Q-038 (own measurement): "If we can't observe X under condition Y, hypothesis Z is false." |
| Failure mode | Q-040 (Brenner §229): "When confirmation evidence accumulates without refutation evidence, suspect bias." |

This mapping makes the operator library *self-evidencing*. Each operator card cites the quotes that justify it.

---

## Validators

Per /operationalizing-expertise stage 5, derive validators from the operator library:

For ✂ Exclusion-Test, the validator is:
- "Every active H has ≥1 attempted falsifier-firing investigation per Phase 4 round." (mechanizable check)

Per `scripts/audit-bead-invariants.sh`, this becomes:
```bash
for h in $(active_h); do
    if [ "$(falsifier_attempts $h)" -lt 1 ]; then
        violation "F-401: $h missing falsifier attempt"
    fi
done
```

For other operators (◊ Paradox-Hunt, ⊞ Scale-Check, etc.), similar validators are derived. The full list:

| Operator | Validator | Mechanized via |
|----------|-----------|----------------|
| ◊ Paradox-Hunt | Phase 1 question_of_record has non-empty Paradox section | `scripts/phase-readiness.sh --phase=1` |
| ⊘ Level-Split | At least 1 H has level-split origin tag in Phase 3 slate | `audit-bead-invariants.sh --check=phase3_exit` |
| 𝓛 Recode | Synthesizers re-state claims in own words; meta-synth has ≥1 recode | `disagreement-register-lint.sh` |
| ≡ Invariant-Extract | Per-H invariants documented; auditable | bead description schema |
| ✂ Exclusion-Test | Falsifier-firing attempt per H per round | `audit-bead-invariants.sh` |
| ⟂ Object-Transpose | Cross-domain ⊕ import documented in Phase 3 | `phase0_scope_decision.md § cross_domain_imports` |
| ↑ Amplify | High-priority Hs get more investigation rounds | bead priority schema |
| ⌂ Materialize | Hypothetical scenarios become specific test cases | EV bead schema |
| 🔧 DIY | Replication attempted for load-bearing claims | MO-academic-replication |
| ⊞ Scale-Check | Each scale-physics assumption has explicit calculation | bead `assumption_type:scale_physics` |
| 🤝 GAN | Cross-family champions in Phase 5 | `check-rotation-rules.sh` Rule 1+2 |
| ΔE Exception-Quarantine | Anomalies tracked in anomaly_register | bead label `anomaly` |
| † Theory-Kill | Adjudicator kill rate > 0% (per F-501) | session metric |
| ∿ Dephase | Phase 7 audit explicitly checks consensus capture | OC-008 OPERATOR-CARDS |
| ⊙ Productive-Ignorance | One pane operates without corpus access | OC-005 OPERATOR-CARDS |

Each validator is derived from the operator's quote-bank evidence.

---

## Composition with other patterns

### With KERNEL.md

The triangulated kernel cites quotes from ≥3 sources per axiom. Quote bank → kernel:

```
Axiom: "Reality has a generative grammar"
- Q-001 (Brenner transcript §10): "The brain reconstructs the sensory world..."
- Q-014 (Crick 1959): "Genetic information is generative, not selective..."
- Q-027 (Chomsky 1965): "Language is generative, not stored..."
```

### With Phase 6

Per-family distillations cite quotes; meta-synthesis reconciles which quotes are load-bearing across families. The disagreement register surfaces *quote weighting* disagreements.

### With CROSS-SESSION-LEARNING.md

Quote banks are session-level by default. After ≥3 sessions reuse the same quotes, promote to skill-level reference (e.g., add to EXEMPLARS.md).

### With operationalizing-expertise

Track-A explicitly: corpus → quote bank → kernel → operators → validators. Brennerbot's `corpus/`, `corpus/quote-bank.md`, `references/KERNEL.md`, `references/OPERATORS.md`, and `scripts/audit-*.sh` map directly to this pipeline.

---

## Maintenance

### Per-session

At Phase 8 freeze, the per-session quote bank is committed. At Phase 10 drift check, identify quotes that:
- Earned their keep (cited multiple times) → candidates for skill-level promotion
- Failed to be cited (deadweight) → demote or remove from session quote bank

### Cross-session

Quarterly review:
- Which quotes are referenced across many sessions? → promote to skill EXEMPLARS.md
- Which sources are cited frequently? → consider as recurring corpus pin
- Which quotes were later proven wrong? → annotate with retraction note

### Versioning

Quote bank entries include extraction date + source hash. If the source content changes (per VERIFICATION-FIRST.md), the quote may no longer be accurate. Schedule re-verification.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Cite paraphrases as if verbatim | Anti-Brenner; defeats reproducibility |
| Cherry-pick supporting quotes only | Bias compounds across sessions |
| Quote without source-id + section | Un-verifiable |
| Quote without "why this matters" | Reader doesn't know what to do with it |
| Long quotes (multi-page) | Operator brain budget; extract the crux |
| Stale quotes from outdated sources | Periodically re-verify volatile sources |
| Single-source kernel claims | Triangulation requires ≥3 sources |

---

## Operator self-test

When extracting a quote, ask:
1. Did I actually read the source, or just see the citation elsewhere?
2. Does the quote say what I want it to say, or am I projecting?
3. Did I extract counter-quotes too, or only confirming?
4. Is the source authoritative for THIS claim (not just generally)?

If any "no" or "uncertain", investigate further before adding to quote bank.

---

## Cross-references

- /operationalizing-expertise (the Track-A pattern this implements)
- KERNEL.md (the triangulated kernel built from the quote bank)
- OPERATORS.md (the operator library evidenced by quotes)
- SOURCE-CORPUS.md (the source corpus pinned for quotes)
- EVIDENCE-WEIGHTING-TAXONOMY.md (W_source corresponds to authority tiers above)
- CROSS-SESSION-LEARNING.md (cross-session quote promotion)
- EXEMPLARS.md (skill-level promoted quotes)
