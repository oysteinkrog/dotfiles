# EXEMPLARS.md — Quote Bank of World-Class Research Methodology Writeups

<!-- TOC: How to use | Brenner-tradition exemplars | Adjacent traditions | Modern multi-agent research patterns | What to import -->

Mirrors documentation-website's EXEMPLARS.md but for research methodology. Annotated quote bank from world-class research writeups. Each entry shows a *move* worth importing.

The skill's Track A pattern requires staying grounded in the source corpus (Brenner's transcript). This file extends that grounding with adjacent exemplars where the move generalizes.

---

## How to use this file

When writing a marching order, distillation, or evidence pack, scan here for relevant exemplars. Quote them sparingly — Brenner's corpus is the canonical source; these are extensions.

When extending the methodology, an exemplar from this file is one path to motivation: "here's how X did this elsewhere; we should adopt because of Y."

---

## Brenner-tradition exemplars

### Sydney Brenner — `complete_brenner_transcript.md`

The canonical source. See SOURCE-CORPUS.md for the operator-keyed quote bank from this corpus. Examples:

- §62 (seven-cycle log paper) — the gold standard for amplification (↑)
- §103 ("both could be wrong") — third-alternative discipline
- §147 (exclusion is always good) — ✂ Exclusion-Test loadbearer
- §229 (mistresses to be discarded) — † Theory-Kill discipline

### James Watson + Francis Crick (DNA structure papers)

> "It has not escaped our notice that the specific pairing we have postulated immediately suggests a possible copying mechanism for the genetic material." (Nature 1953)

**Move:** maximally restrained understatement letting the reader compute the implication. The paper's load-bearing claim sits in one sentence with no flourish. **Application:** distillations should follow this norm — a load-bearing claim earns one sentence; supporting argument is separate.

### Werner Heisenberg (uncertainty principle paper)

**Move:** introducing a constraint as a positive theory rather than a negative limitation. The "uncertainty principle" reframes "we cannot measure both X and Y precisely" as "the universe has this exact structure, with this exact bound." **Application:** when Phase 6 distillation surfaces an inability, frame it as a structural property, not a research failure.

### Claude Shannon (Mathematical Theory of Communication)

**Move:** ruthless dimensional reduction (𝓛 Recode) — communication is reframed entirely in terms of bits + channel capacity, stripping away domain semantics. **Application:** when a question seems irreducibly multi-dimensional, ask: what's the 1-dimensional encoding that captures the load-bearing information?

---

## Adjacent traditions

### Paul Erdős (mathematical method)

**Style:** "the simplest non-trivial example." Erdős would attack hard problems by finding the smallest N where the difficulty appeared, then climbing back up. **Application:** for design-space questions (A1), find the minimum-viable workload class where candidates differentiate; expand only if needed.

### Edsger Dijkstra (EWD essays)

**Style:** assertive, with explicit refusal to hedge. Each essay carries one load-bearing claim and defends it with no hedge words. **Application:** synthesizers should adopt this voice in distillations. Hedging is a failure mode (per F-CX in our anti-patterns); Dijkstra's voice is the antidote.

### Richard Feynman (lectures on physics)

**Style:** materialize first, formalize after. Feynman would give the answer in terms of physical intuition before introducing equations. **Application:** distillations lead with the intuitive claim; the formal derivation follows. Don't bury the load-bearing intuition in formalism.

### Donald Knuth (Concrete Mathematics, TAOCP)

**Style:** exhaustively complete with explicit cross-references. Knuth's books fully cite every prior result. **Application:** at T4+ tier, every load-bearing claim should be backed by a citation chain that's fully reconstructible. No "as is well known."

---

## Modern multi-agent research patterns

### Karl Popper (epistemology)

> "A theory which is not refutable by any conceivable event is non-scientific."

**Move:** falsifiability as the demarcation criterion. **Application:** every `H-*.falsifier` field is a Popper-test. A H without a falsifier isn't research; it's metaphysics.

### Imre Lakatos (research programmes)

**Move:** distinguishing the "hard core" (load-bearing claims you defend at all costs) from the "protective belt" (auxiliary hypotheses you'll modify under pressure). **Application:** Phase 6 distillation should explicitly identify the hard core (kernel invariants) vs the protective belt (peripheral claims that can be updated without rebuilding everything).

### Thomas Kuhn (paradigm shifts)

**Move:** when anomalies cluster systematically, suspect the paradigm, not the data. **Application:** ΔE Exception-Quarantine card; when ≥2 anomalies share a feature, spawn an `origin:anomaly_spawned` H — possibly a paradigm shift hidden in plain sight.

### Larry Wasserman (frequentist vs Bayesian)

**Move:** explicit declaration of one's epistemic framework. Wasserman insists on stating prior assumptions before reaching conclusions. **Application:** Phase 6 distillation must include a Bayesian-substrate section per OPERATORS.md. Treating this as optional is anti-Brenner (per our integration of Bayes substrate with the kernel).

---

## Multi-perspective triangulation exemplars

### Talmudic study tradition

**Move:** rabbis recorded majority AND minority opinions side-by-side. The Talmud doesn't average; it preserves dissent. **Application:** Phase 6 disagreement_register.md is structurally Talmudic — record the cc reading + cod reading + gmi reading even when meta-synthesis chooses one.

### Three-strand arguments (legal practice)

**Move:** good legal argument presents three independent reasons each sufficient on its own. **Application:** for `confidence:high` Hs, prefer ≥3 independent supporting EVs (per CONFIDENCE-SCORING.md). Single-EV high-confidence is brittle.

### Adversarial collaboration (psychology)

**Move:** two researchers with opposing predictions agree on a methodology that would settle their dispute, then run it together. **Application:** Phase 5 cross-examination is a structured adversarial collaboration; champions agree on the falsifier criteria up front, then debate within those rules.

---

## Quality patterns from technical writing

### Concrete-before-abstract (Strunk & White; Dijkstra)

**Move:** lead with the specific example; abstract pattern follows. **Application:** distillations open with a concrete instance ("Brenner's seven-cycle log paper test on phage plaques") then generalize ("amplify signals where possible").

### "Not, but" structure (Antony Jay, "Information is Not Knowledge")

**Move:** explicitly state what you're NOT claiming alongside what you are. **Application:** Phase 9 HANDBACK.md should include "What we did NOT establish" — bounds the recommendation.

### Numbered-list discipline (USMC orders, IETF RFCs)

**Move:** every numbered point has exactly one claim. **Application:** marching orders use numbered steps with one verb per step. Distillations break compound claims into separate items.

### Citation-density target (academic style)

**Move:** ≥1 citation per claim of empirical fact. **Application:** evidence packs require verbatim citations; distillations cite ≥1 EV per claim. Vibes-only claims fail audit.

---

## What NOT to import

Some traditions don't translate to brennerbot:

- **Lone-genius mystique** — anti-collaborative; we run swarms, not individuals
- **Ipse dixit authority** — "X is true because I said so" — anti-Brenner
- **Endless caveats / hedging** — opposite of †-Theory-Kill discipline
- **Footnote sprawl** — load-bearing content in footnotes hides accountability
- **Performative complexity** — making things sound harder than they are; opposite of HAL biology (§198)

When in doubt, prefer Brenner's voice over any of the above.

---

## Adding new exemplars

When a session reveals a useful exemplar from outside the existing catalog:

1. Quote the exemplar verbatim (with attribution)
2. Name the **move** (the cognitive pattern)
3. Specify the **application** (where in brennerbot the move is used)
4. File as Phase 10 lesson if Phase 10 ran

Phase 10 drift-check should periodically scan for exemplar imports and assess: were they useful? Drop those that didn't generalize.

---

## Integration with the operator algebra

Each major exemplar maps to one or more of our 15 operators. Recommended cross-reference:

| Exemplar tradition | Primary operator(s) |
|---------------------|---------------------|
| Brenner | All 15 (the source) |
| Watson-Crick | ⌂ Materialize, ≡ Invariant-Extract |
| Heisenberg | 𝓛 Recode |
| Shannon | 𝓛 Recode (extreme) |
| Erdős | ⟂ Object-Transpose, ↑ Amplify |
| Dijkstra | †, ✂ |
| Feynman | ⌂ Materialize, 🔧 DIY |
| Knuth | ⊞ Scale-Check (citation density) |
| Popper | ✂ Exclusion-Test |
| Lakatos | ⊘ Level-Split (hard core vs belt) |
| Kuhn | ΔE Exception-Quarantine, ◊ Paradox-Hunt |
| Wasserman | Bayesian substrate (cross-cuts) |
| Talmudic | 🤝 GAN, disagreement-register discipline |
| Adversarial collaboration | 🤝 GAN |

A distillation that cites multiple exemplars whose primary operators differ has fired multiple operators — which is a healthy sign per Phase 10's operator-coverage check.
