# KERNEL.md — The Triangulated Brenner Method

<!-- TOC: Two Axioms | Compact Loop | 15 Operators | Hot Tensions | Required Failure Modes | Bayesian Substrate | Objective Function | Source Anchors | Extending the Kernel -->

*This is the skill-internal kernel. It triangulates three independent expert distillations of the Brenner method (Opus 4.5, GPT-5.2 Pro, Gemini 3 Deep Think) against the primary source `complete_brenner_transcript.md` (236 numbered sections, `§n`-anchored). Where the distillations agree, the kernel inherits. Where they disagree, [DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md](DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md) records both readings and our chosen synthesis.*

---

## The Two Axioms

These are the load-bearing commitments. All operators, all marching orders, all beads schema invariants, all phase exit gates derive from them.

### Axiom 1 — Reality has a generative grammar

The world is not merely patterns and correlations. It is **produced by causal machinery** that operates on discoverable rules. Phenomena are *generated*, not just described. Genome is source code; development is execution; mutation is debugging; evolution is version control (von Neumann, §45–§46).

**Operational consequence:** Science is *reverse-engineering*. You are not looking for correlations; you are looking for the production rules.

### Axiom 2 — To understand is to be able to reconstruct

You have not explained a phenomenon until you can specify, *in principle*, how to **build it from primitives**. Description is not understanding. Prediction is not understanding. Only reconstruction is understanding.

> "What we'd like to do is to actually go and make a mouse, to build a mouse... a gedanken mouse." (§126)
> "A proper simulation must be done in the machine language of the object being simulated." (§147)

**Operational consequence (the Gedanken Standard):** Could you, given the inputs and initial conditions, *compute* the output? If not, you don't yet understand. Every research artifact in this skill must satisfy: "if this hypothesis is true, here is what I would *build* / *predict* / *forbid*."

---

## The Compact Loop (operationalized for an ntm swarm)

```
WHILE understanding incomplete:
    ◊  Hunt for paradoxes in current model            → Phase 1, 4
    ⊘  Check for level confusions                     → Phase 3 triage
    𝓛  Reduce dimensionality                          → Phase 3 hypothesis statement
    ⊞  Calculate scale; stay imprisoned in physics    → assumption_ledger / scale_physics
    ≡  Identify invariants                            → evidence-pack key_findings
    ⌂  Materialize: "what would I see if true?"       → mandatory expected_evidence on each H
    ✂  Derive forbidden patterns → exclusion test     → mandatory falsifier on each H
    ⟂  Transpose to optimal proxy/system              → choose corpus shard / code shard / experiment
    🔧 Build what you need                             → deliverables/scripts allowed
    ↑  Amplify signal                                 → digital handles, selection, dynamic range
    ⤴  Run the cheapest decisive experiment first    → MO-04 quickie before flagship   # scheduling rule (§99), NOT a 16th operator
    IF forbidden pattern observed:
        †  Kill model                                  → state: refuted
    ELIF unexpected anomaly:
        ΔE Quarantine                                  → anomaly bead; cluster check
    ELIF expected pattern observed:
        update model; reduce hypothesis space
    IF field industrializing:
        ∿  Dephase                                     → operator switches roster, MO-07 finds new paradox
```

> **Note on `⤴`.** The 15-operator basis is canonical. `⤴` ("quickie") is a *scheduling rule* drawn from Brenner §99 — when multiple amplifying tests are available, run the cheapest decisive one first — not a separate operator. It has no card in [OPERATORS.md](OPERATORS.md); its dedicated marching order is `MO-quickie-pilot.md`, which composes ⤴ with `↑ Amplify` and `⌂ Materialize`.

---

## The 15 Operators (mapped to ntm/beads/mail surfaces)

Full cards in [OPERATORS.md](OPERATORS.md). The summary mapping:

| Glyph | Name | Source | Concrete artifact in this skill |
|-------|------|--------|---------------------------------|
| ◊ | Paradox-Hunt | §106, §95 | `intake/question_of_record.md § Paradox`; Phase 4 anomaly-spawned hypotheses |
| ⊘ | Level-Split | §45–§46, §105 | `H-*.category` enum forces (mechanistic / phenomenological / boundary / auxiliary / third_alternative); Phase 3 triage rule |
| 𝓛 | Recode/Dimensional-Reduction | §58, §147 | `H-*.statement` must specify the encoding ("in what coordinates do these hypotheses disagree?") |
| ≡ | Invariant-Extract | §109, §88–§89 | `EV-*.key_findings`; Phase 6 distillation kernel axioms |
| ✂ | Exclusion-Test | §147, §69 | Mandatory `H-*.falsifier:` field; bead invariant |
| ⟂ | Object-Transpose | §91, §145–§146, §221 | Phase 4 investigator MO chooses corpus/code/proxy; sub-question framing |
| ↑ | Amplify | §62, §94, §154 | `T-*.expected_signal` requires "across-the-room" magnitude; potency check is mandatory |
| ⌂ | Materialize | §66, §42 | Mandatory `H-*.expected_evidence:` field; investigator MO must specify what would be seen |
| 🔧 | DIY/Bricolage | §23, §51, §86 | Investigators may write `deliverables/scripts/*.sh` rather than block on missing tooling |
| ⊞ | Scale-Check | §66, §100 | Mandatory `assumption.type:scale_physics` entries with `calculation:` block |
| 🤝 | GAN/Conversation | §66, §167 (Brenner-Crick GAN) | Phase 5 cross-examination is the GAN substrate; debate threads are the artifact |
| ΔE | Exception-Quarantine | §110–§111 | `anomaly_register` section in `ARTIFACT.md`; clustering anomalies trigger Phase 4 reopen |
| † | Theory-Kill | §229 | `state: refuted` with mandatory `refuted_by:` pointer (underscore — the form `audit-bead-invariants.sh` greps for) |
| ∿ | Dephase | §143, §192, §210 | Phase 7 audit flag; Phase 10 drift-check rubric |
| ⊙ | Productive-Ignorance | §63, §192, §65, §200, §230 | Mandatory: ≥1 Proposer pane is told to read minimally and reason from first principles |

---

## The Hot Tensions (modes you must oscillate between)

Brenner was explicit (§229) that science demands contradictory traits. The skill enforces oscillation by *role assignment*, not by asking one pane to do both jobs.

| Generative Mode | Destructive Mode | Where in the skill |
|-----------------|------------------|---------------------|
| Imagination: generate many hypotheses | Focus: drive through walls to test one | Proposer role vs Investigator role |
| Passion: care deeply about ideas | Ruthlessness: kill ideas that fail | Investigator role vs Devil's-Advocate + Adjudicator |
| Ignorance: preserve fresh eyes | Learning: acquire cross-domain patterns | One Proposer with `⊙ productive-ignorance`; the rest with full corpus |
| Attachment: work on hard problems for years | Detachment: abandon instantly when wrong | `H-*` long-running vs `state: refuted` |
| Conversation: externalize half-formed thoughts | Solitude: bouncing-balls incubation | Mail threads vs per-pane evidence-pack work |
| Theory: let imagination go | Experiment: guard it by judgement and test | Proposer/Synthesizer vs Investigator/Devil's-Advocate |

---

## The Required Failure Modes (when this method does NOT apply)

Per Opus distillation §VIII (failure modes), this method has explicit limits. Phase 0 scope decision must check:

1. **Intractable grammar** — high-dimensional combinatorics, emergent properties, chaotic dynamics where exclusion tests cannot converge. Flag as `mode:incident-investigation` (compressed phases) or escalate.
2. **Inaccessible machine language** — primitives can't be observed/manipulated. Falsifiers will be too soft. Either reframe to a proxy (⟂) or abort.
3. **Fashion is correct** — "out of phase" assumes the crowd is wrong. Sometimes it isn't. Phase 10 drift-check explicitly examines whether out-of-phase positioning was actually warranted.
4. **Pathological contradictions** — unsustainable killing/attachment oscillation. Watch for: ≥3 consecutive rounds with no `state:` changes on `H-*` descriptions (paralysis) OR a Devil's-Advocate killing every hypothesis on rhetoric (rabid skepticism).
5. **Middle-game/coordination phase** — when the question requires *filling in details* across many people, you need conformity, which conflicts with productive-ignorance and dephase. Defer to an implementation skill (e.g., `/multi-agent-swarm-workflow`).

---

## The Bayesian Substrate (why the Brenner moves work)

| Brenner Move | Bayesian Operation | Skill artifact |
|--------------|---------------------|----------------|
| Enumerate 3+ models before experimenting | Maintain explicit prior distribution | Phase 3 hypothesis slate ≥3 |
| Hunt paradoxes | Find high-probability contradictions in posterior | Phase 1 `Paradox` field |
| "Both could be wrong" | Reserve mass for model misspecification | mandatory `origin:third_alternative` |
| Design for forbidden patterns | Maximize expected KL divergence | mandatory `falsifier:` |
| Seven-cycle log paper | Choose experiments with extreme likelihood ratios | `T-*.expected_signal` magnitude |
| Choose organism for decisive test | Modify data-generating process | Investigator's choice of proxy (⟂) |
| House of cards | Interlocking constraints (posterior ~ product of likelihoods) | Phase 6 distillation interlocks claims |
| Exception quarantine | Mixture-component anomalies | `anomaly_register` |
| Don't-Worry hypothesis | Marginalize over latent mechanisms | Allowed in early Phase 4; flagged in Phase 7 audit |
| Kill theories early | Aggressive posterior updating | `†` operator + `state: refuted` |
| Scale/physics constraints | Strong physical priors | `assumption.type:scale_physics` |
| Productive ignorance | Recognize when expert priors are too tight | Roster-assignment rule for one Proposer |

---

## Objective Function (what every operator move maximizes)

```
                Expected Information Gain × Downstream Option Value
Score(move) = ─────────────────────────────────────────────────────
              Time × Cost × Ambiguity × Infrastructure-Dependence
```

Reframings that shrink the denominator (DIY, dimensional reduction, choosing the right proxy) often beat brute-force experiments that grow the numerator. **Always prefer the move that drops a denominator term by an order of magnitude over one that doubles the numerator.** This is the implicit ranking used by `MO-04` investigator marching orders.

---

## Source Anchors (where the kernel lives in the corpus)

The full quote bank is at `/dp/brenner_bot/quote_bank_restored_primitives.md` (160KB; verbatim §-anchored). When this skill cites a §-anchor, it means the quote bank's anchor by that number. Key anchors clustered by operator:

- `◊ Paradox-Hunt` — §95 (prodigious protein synthesis paradox), §106 (mRNA paradox), §175 (junk vs garbage)
- `⊘ Level-Split` — §45–§46 (von Neumann), §105 (instructions separate from machine), §147 (proper simulation), §50 (chastity vs impotence)
- `𝓛 Recode` — §58 (3D→1D), §229 (inversion), §161 (lineage vs neighborhood), §205 (analogue vs digital)
- `≡ Invariant-Extract` — §109 (frame-shift triplet code), §88–§89 (phase problem), §90 (mutational spectra)
- `✂ Exclusion-Test` — §147, §69 (overlapping code excluded by adjacent-pair forbidden patterns)
- `⟂ Object-Transpose` — §91 (choice of experimental object), §145–§146 (EM window forces nematodes), §221 (Fugu)
- `↑ Amplify` — §62 (seven-cycle log paper, Boolean primitives), §94 (single protein 70%), §154 (selection on plates)
- `⌂ Materialize` — §66 (materialize the question), §42 (let imagination go but direct it)
- `🔧 DIY` — §23 (Warburg manometer), §51 (no magic), §86 (negative staining democratized EM)
- `⊞ Scale-Check` — §66 (imprisoned in physics), §100 (magnesium vs caesium dominant variable)
- `🤝 Conversation` — §66 (never restrain yourself), §167 (50% wrong first time)
- `ΔE Exception-Quarantine` — §110–§111 (appendix; house of cards)
- `† Theory-Kill` — §229 (mistresses to be discarded; when ugly, kill)
- `∿ Dephase` — §143 (out of phase), §192 (opening game), §210 (heroic vs classical)
- `⊙ Productive-Ignorance` — §63, §192 (value of ignorance), §65 (don't equip yourself), §200 (papers that remove information), §230 (transit ignorance)

---

## How to Extend the Kernel

When this skill is run repeatedly and Phase 10 drift-check surfaces a *new* operator that should join the algebra:

1. Propose the operator (glyph, name, source-anchor, action) in `references/OPERATORS.md`.
2. Add a marching-order module that activates it (`assets/marching-orders/MO-X-<name>.md`).
3. Add a beads-schema validator that enforces it (`scripts/audit-bead-invariants.sh`).
4. Update [DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md](DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md) if the new operator was implicit in one distillation but absent in others.

The kernel evolves; the axioms do not.
