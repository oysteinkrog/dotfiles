# OPERATORS.md — The Cognitive Operator Library

<!-- TOC: Card Schema | ◊ Paradox-Hunt | ⊘ Level-Split | 𝓛 Recode/Dimensional-Reduction | ≡ Invariant-Extract | ✂ Exclusion-Test | ⟂ Object-Transpose | ↑ Amplify | ⌂ Materialize | 🔧 DIY/Bricolage | ⊞ Scale-Check | 🤝 GAN/Conversation | ΔE Exception-Quarantine | † Theory-Kill | ∿ Dephase | ⊙ Productive-Ignorance | Composition Cheat-Sheet | Operator Anti-Patterns -->

15 named cognitive moves, each as a card with `{trigger, recipe, marching-order module, validator, failure mode}`. Adapted from the three distillations and traced back to source `§`-anchors. The card structure follows the pattern from `/operationalizing-expertise` Track A.

When in doubt during a phase, scan the **Composition Cheat-Sheet** at the bottom — it prescribes which operators to apply in what order at each phase.

---

## Card Schema

```yaml
operator:
  glyph: <unicode glyph>
  name: <Title-Case-Name>
  source: <§-anchors from corpus>
  trigger:    "<the question whose 'no' makes this operator fire>"
  recipe:     "<3-7 line procedure for applying it>"
  module:     "<MO-NN-name.md template that ships the operator into a marching order>"
  validator:  "<scripts/audit-*.sh check or bead invariant that confirms it landed>"
  failure:    "<the F-### code that fires when this operator is missing>"
  artifact:   "<which file/bead-field the operator writes to>"
```

---

## ◊ Paradox-Hunt

- **Source:** §95 (prodigious protein synthesis), §106 (mRNA paradox), §175 (junk vs garbage definitional cleanup)
- **Trigger:** "What two well-attested facts seem to contradict each other in this question?"
- **Recipe:**
  1. Read the question of record. Identify ≥2 well-attested facts that *seem* to be in tension.
  2. Phrase the tension as: "If A is true, then B should be impossible. But B is observed. So either A is wrong, B is misobserved, or there's a hidden mechanism."
  3. The hidden mechanism is the next bead: file as a `H-*` with `origin:anomaly_spawned`.
  4. If no paradox can be found, the question is too vague. Force it through `MO-01-frame-question.md` again.
- **Module:** `MO-01-frame-question.md` § Paradox section; `MO-04a-investigate.md` step 3.
- **Validator:** `intake/question_of_record.md` must have a non-empty `## Paradox` section. Phase 1 cannot exit without it.
- **Failure:** F-101 (question too broad).
- **Artifact:** `intake/question_of_record.md`; `H-*.parent` link to the paradox bead.

---

## ⊘ Level-Split

- **Source:** §45–§46 (von Neumann program/interpreter), §105 (instructions separate from machine), §147 (proper vs improper simulation), §50 (chastity vs impotence).
- **Trigger:** "Am I conflating program with interpreter? Specification with execution? Mapping with stored text? 'Won't' with 'can't'?"
- **Recipe:**
  1. For each candidate hypothesis, decompose into `{program, interpreter, message, machine}` roles.
  2. Identify which role the hypothesis is making a claim about.
  3. If two hypotheses make the same claim at different roles, they are not actually rivals — split them.
  4. Add `H-*.category` from {mechanistic / phenomenological / boundary / auxiliary / third_alternative}.
- **Module:** `MO-03b-triage.md` step 4.
- **Validator:** `scripts/audit-bead-invariants.sh § level_split_check` — every `H-*` has a `category:` field.
- **Failure:** F-302 (hypothesis duplication; was actually two roles).
- **Artifact:** `H-*.category`.

---

## 𝓛 Recode/Dimensional-Reduction

- **Source:** §58 (3D→1D biology), §229 (inversion), §161 (lineage vs neighborhood), §205 (analogue vs digital).
- **Trigger:** "What encoding makes the rival hypotheses' predictions visibly diverge?"
- **Recipe:**
  1. State each hypothesis in two encodings (e.g. behavioral vs structural; analogue vs digital; spatial vs sequence).
  2. Pick the encoding where the predictions are most clearly distinct.
  3. If no encoding separates them, the hypotheses may be the same hypothesis — apply ⊘ Level-Split.
- **Module:** `MO-03a-propose.md` § Recode step.
- **Validator:** `H-*.statement` must include a `## Coordinates` block specifying the encoding.
- **Failure:** F-302 (hypotheses don't disagree under chosen encoding → really the same).
- **Artifact:** `H-*.statement`.

---

## ≡ Invariant-Extract

- **Source:** §109 (frame-shift topology), §88–§89 (phase problem), §90 (mutational spectra).
- **Trigger:** "What property must hold regardless of detail?"
- **Recipe:**
  1. While reading evidence, ask: "what would still be true if the implementation details changed?"
  2. Promote candidate invariants into the per-hypothesis evidence pack as `key_findings`.
  3. Phase 6 distillation must list ≥3 invariants per surviving hypothesis.
- **Module:** `MO-04a-investigate.md` step 5; `MO-06a-distill.md` step 2.
- **Validator:** `EV-*.key_findings` non-empty for every `verified` evidence record.
- **Failure:** F-401 (evidence count grows without H state changes — investigators are accumulating, not extracting).
- **Artifact:** `EV-*.key_findings[]`.

---

## ✂ Exclusion-Test (the load-bearing operator)

- **Source:** §147 (exclusion always tremendously good), §69 (overlapping code via forbidden adjacent pairs).
- **Trigger:** "What pattern is *forbidden* if this hypothesis is true?"
- **Recipe:**
  1. For every `H-*`, write a `falsifier:` block: "if observed, the hypothesis is dead."
  2. The falsifier must be observable (not "if math broke") and decidable (not "if it became philosophically wrong").
  3. Investigator (Phase 4) must run at least one query that *could* return the falsifier; if it never could, the falsifier is fake.
- **Module:** `MO-03a-propose.md` mandatory `falsifier:` field; `MO-04a-investigate.md` step 7 forbidden-pattern probe.
- **Validator:** `scripts/audit-bead-invariants.sh § every_H_has_falsifier`.
- **Failure:** F-103, F-303, F-403.
- **Artifact:** `H-*.falsifier`.

---

## ⟂ Object-Transpose

- **Source:** §91 (choice of experimental object), §145–§146 (EM window → nematodes), §221 (Fugu discount genome).
- **Trigger:** "What proxy/substrate would make the decisive test cheap?"
- **Recipe:**
  1. List 3–5 candidate proxies for the phenomenon (corpus shards, code shards, miniature analogues, prior-art systems).
  2. For each, score `(decisive-test-cost-savings) × (signal-clarity)`.
  3. Pick the highest-scoring proxy. Investigator works *there* first.
- **Module:** `MO-04a-investigate.md` step 4.
- **Validator:** Phase 4 evidence packs must cite at least one proxy by name in `methodology:`.
- **Failure:** F-401 if proxy choice is unstated and investigator is grinding through the most expensive surface first.
- **Artifact:** `EV-pack-H-NNN.md § Methodology § Proxy choice`.

---

## ↑ Amplify

- **Source:** §62 (seven-cycle log paper, Boolean primitives), §94 (single protein 70%), §154 (selection on plates).
- **Trigger:** "Where is the signal naturally large, digital, or selective?"
- **Recipe:**
  1. Prefer evidence sources with high contrast: yes/no readouts, presence/absence, ≥10× magnitude differences.
  2. If only continuous data is available, find a threshold where the data goes binary.
  3. Reject "subtle effects need statistics" framings — refactor to find a regime where the effect is qualitative.
- **Module:** `MO-04a-investigate.md` step 6; `T-*.expected_signal` field.
- **Validator:** `T-*.expected_signal` magnitude must be `≥10×` or `binary`. `T-*` with unspecified magnitude is rejected.
- **Failure:** F-404 (test missing potency check) often co-fires here.
- **Artifact:** `T-*.expected_signal`.

---

## ⌂ Materialize

- **Source:** §66 (materialize the question), §42 (let imagination go but direct it).
- **Trigger:** "If this hypothesis is true, what would I *see*?"
- **Recipe:**
  1. For every `H-*`, write the `expected_evidence:` field as a concrete observable: a section of corpus, a code path, a benchmark result, a behavioral signal.
  2. The materialized observable must be reachable in <1 hour of investigator work — otherwise apply ⟂ to find a cheaper proxy.
  3. Phase 4 investigator's *first* output is a verbatim quote / file path / bench output that confirms or denies the materialized signal.
- **Module:** `MO-03a-propose.md` mandatory `expected_evidence:` field; `MO-04a-investigate.md` step 1.
- **Validator:** `scripts/audit-bead-invariants.sh § every_H_has_expected_evidence`.
- **Failure:** F-103, F-401.
- **Artifact:** `H-*.expected_evidence`.

---

## 🔧 DIY/Bricolage

- **Source:** §23 (Warburg manometer), §51 ("no magic in this"), §86 (negative staining democratized EM).
- **Trigger:** "Can I build the test now instead of waiting for ideal tooling?"
- **Recipe:**
  1. If a query, comparison, or measurement would take >1 hour to wait for "the right tool", write a quick script in `deliverables/scripts/` that approximates it.
  2. The DIY artifact is not the answer; it's a way to start the loop.
  3. If the DIY script outputs surprising results, escalate to a real tool in the next round.
- **Module:** `MO-04a-investigate.md` step 9.
- **Validator:** No bead invariant; this is permissive — the failure mode is *not* applying it (waiting forever).
- **Failure:** Soft failure: "investigator stuck waiting for the perfect tool" → reapply MO-04a step 9.
- **Artifact:** `deliverables/scripts/*`.

---

## ⊞ Scale-Check (mandatory at Phase 7)

- **Source:** §66 (imprisoned in physics), §100 (magnesium vs caesium dominant variable).
- **Trigger:** "Does the math/physics actually permit this?"
- **Recipe:**
  1. For every load-bearing hypothesis, identify its scale-physics assumption (e.g. memory, bandwidth, latency, energy, entropy budget).
  2. Write the assumption as a bead `assumption.type:scale_physics` with a `calculation:` block.
  3. Phase 7 audit verifies the math.
- **Module:** `MO-04c-evidence-pack.md § Scale check`; `MO-07a-fresh-eyes.md` step 4.
- **Validator:** `scripts/audit-bead-invariants.sh § every_scale_physics_assumption_has_calculation`.
- **Failure:** F-1002 (drift check missing baseline anchor often co-fires here).
- **Artifact:** `assumption.calculation`.

---

## 🤝 GAN/Conversation (Brenner-Crick)

- **Source:** §66 (never restrain yourself), §167 (50% wrong first time, conversation as ongoing).
- **Trigger:** "Have I externalized this hypothesis to another mind?"
- **Recipe:**
  1. Phase 5 cross-examination *is* the GAN. Generator (Proposer/Investigator) speaks; Discriminator (Devil's-Advocate) cuts.
  2. Pair every H with at least one Devil's-Advocate from a different model family.
  3. Debate threads (`RS-...-DEBATE-<H_I>-vs-<H_J>` — bead IDs interpolated, e.g. `RS-...-DEBATE-H-001-vs-H-002`) are the externalized cognition. Adjudicator scores at the end of each round.
- **Module:** `MO-05a-cross-exam.md`.
- **Validator:** Every active `H-*` exiting Phase 5 must have a `DEBATE-*` bead with at least one round on record.
- **Failure:** F-501 (adjudicator never kills) often signals the GAN is unbalanced.
- **Artifact:** Agent Mail thread `RS-...-DEBATE-*`; bead `DEBATE-*`.

---

## ΔE Exception-Quarantine

- **Source:** §110–§111 (anomaly appendix; house of cards).
- **Trigger:** "Are anomalies clustering or scattered?"
- **Recipe:**
  1. New observations that don't fit current hypotheses go into `anomaly_register` as bead `anomaly`, not silently into the main theory.
  2. Each round, count clusters: if ≥2 anomalies share a feature, they are revealing a missing rule. Spawn a new `H-*` with `origin:anomaly_spawned` and link it to the cluster.
  3. Scattered anomalies stay quarantined; they are unrelated noise.
- **Module:** `MO-04a-investigate.md` step 8; `MO-07a-fresh-eyes.md` step 5.
- **Validator:** `anomaly_register.md` exists and has structured entries; cluster check runs each round.
- **Failure:** F-402 (contradictory evidence loop) often means anomalies were patched into the main theory.
- **Artifact:** `anomaly_register.md`; bead `anomaly`.

---

## † Theory-Kill

- **Source:** §229 ("mistresses to be discarded"; "when they go ugly, kill them").
- **Trigger:** "Has this hypothesis failed its falsifier? Then kill it now."
- **Recipe:**
  1. The moment a falsifier fires, flip the H description to `state: refuted` and add `refuted_by: <EV-* or T-*>` field (underscore — `audit-bead-invariants.sh` greps the underscore form).
  2. No grace period. No "let's see if more evidence comes in." A failed falsifier is a kill.
  3. The killed hypothesis stays in the artifact (for Phase 7 audit traceability) — it is *labeled killed*, not deleted.
- **Module:** `MO-05b-adjudicate.md` step 3.
- **Validator:** Every `state: refuted` H has non-empty `refuted_by:`.
- **Failure:** F-501 (adjudicator never kills); F-702 (audit reopens settled questions on rhetoric).
- **Artifact:** `state: refuted`, `refuted_by:`.

---

## ∿ Dephase

- **Source:** §143 (out of phase), §192 (opening game), §210 (heroic vs classical).
- **Trigger:** "Is the swarm thinking like the consensus? Then we're not learning."
- **Recipe:**
  1. Phase 7 audit asks: "is our top-confidence hypothesis the same one a domain expert would name first?"
  2. If yes, that's a yellow flag — verify the hypothesis isn't just inheriting the consensus prior.
  3. If consensus *is* correct, that's fine — but the audit must explicitly cite *why* (not just "it's intuitive").
- **Module:** `MO-07a-fresh-eyes.md` step 6; `MO-10-drift-check.md` rubric line 5.
- **Validator:** Phase 7 audit log must address: "did our top H reproduce a consensus prior, and did we verify why?"
- **Failure:** F-1001 (drift rationalized as improvement).
- **Artifact:** `session-logs/round-N-audit.md`.

---

## ⊙ Productive-Ignorance (the role-assignment operator)

- **Source:** §63, §192 (value of ignorance), §65 (don't equip yourself), §200 (papers that remove information), §230 (transit ignorance).
- **Trigger:** "Are expert tight priors closing off live alternatives?"
- **Recipe:**
  1. At Phase 2 onboarding, designate at least one Proposer pane as the "ignorance pane": its briefing reads only the question of record, not the corpus.
  2. The ignorance pane proposes hypotheses from first principles only.
  3. Triage (Phase 3b) compares ignorance-pane hypotheses to corpus-informed ones; surviving ignorance hypotheses are gold.
- **Module:** `MO-02-onboarding.md § Productive-Ignorance variant`.
- **Validator:** `phase0_scope_decision.md` records which pane has the productive-ignorance role.
- **Failure:** F-602 (single model family's distillation dominates) often means productive-ignorance role was skipped.
- **Artifact:** `phase0_scope_decision.md`.

---

## Composition Cheat-Sheet

(per-phase operator order)

When entering a phase, apply operators in this order. Skip an operator only with a recorded reason in `session-logs/round-N.md`.

| Phase | Operators (in order) | Why this order |
|-------|----------------------|----------------|
| 1 Framing | ◊ Paradox-Hunt → ⌂ Materialize → ✂ Exclusion-Test | First find the contradiction, then specify what would be seen, then what would forbid the hypothesis |
| 2 Bootstrap | ⊙ Productive-Ignorance | Role-assignment is the only operator move at this phase |
| 3 Propose | 𝓛 Recode → ⊘ Level-Split → ⌂ Materialize → ✂ Exclusion-Test (third-alternative guard) | Generate in the right encoding, then sort by role, then materialize observables, then enforce falsifiers (and inject the third alternative) |
| 4 Investigate | ⟂ Object-Transpose → ↑ Amplify → ⌂ Materialize → ⊞ Scale-Check → ≡ Invariant-Extract → ΔE Quarantine → 🔧 DIY (when blocked) | Pick cheap proxy, find amplified signal, look for what was predicted, scale-check claims, extract invariants, quarantine surprises, build when blocked |
| 5 Debate | 🤝 GAN/Conversation → † Theory-Kill | Run the structured GAN; the moment a falsifier fires, kill |
| 6 Distill | ≡ Invariant-Extract → ⊘ Level-Split (across distillations) | Find what survives across model-family distillations; level-split disagreements |
| 7 Audit | ⊞ Scale-Check → ∿ Dephase → ✂ Exclusion-Test (re-verify) | Verify the math; check we're not just inheriting consensus; re-verify falsifiers |
| 8 Freeze | (none — this is mechanical) | |
| 9 Handback | ≡ Invariant-Extract (one final pass) | The handback is the kernel-level summary |
| 10 Drift | ∿ Dephase → ◊ Paradox-Hunt (between trajectory and method) | Was our trajectory in phase or out? Did we surface paradoxes between actual-vs-intended? |

---

## Operator Anti-Patterns

| ✗ Misapplication | What goes wrong |
|------------------|-----------------|
| Apply ✂ Exclusion-Test late (Phase 5) | By Phase 5 you've invested in the hypothesis; you'll soft-falsify rather than kill |
| Apply ⊞ Scale-Check only at audit | Scale errors discovered at Phase 7 mean Phases 4–6 ran on impossible foundations |
| Apply 🤝 GAN with same model family on both sides | The Discriminator inherits the Generator's blind spots; no real cross-examination |
| Apply ⌂ Materialize without ⟂ | You'll commit to the most expensive surface first |
| Apply † Theory-Kill on rhetoric | Reverses Brenner's actual stance — kills only on falsifier-fired evidence |
| Apply ⊙ Productive-Ignorance to every pane | Becomes "wing it" — at least one pane must have full corpus access |
| Apply ΔE Exception-Quarantine to suppress kill-evidence | Anomaly register is for surprises *outside* current H, not for evidence against current H |

When you see one of these, escalate to `MO-mode-flip-*.md` to re-bind the affected pane's role.
