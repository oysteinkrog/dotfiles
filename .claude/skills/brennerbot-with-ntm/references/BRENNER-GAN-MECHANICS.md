# BRENNER-GAN-MECHANICS.md — The Crick-Brenner Generator-Discriminator Discipline

<!-- TOC: Why GAN | The classical Brenner-Crick GAN | Bot-era adaptation | Generator pane mechanics | Discriminator pane mechanics | Why families must differ | GAN failure modes | Recovery patterns | Worked examples | Composition with operators -->

Per the Gemini distillation §4.1 of the brenner_bot transcript: Brenner's collaboration with Crick functioned as a generative-adversarial discipline — Brenner generated theories, Crick discriminated against them. The arrangement was not collegial debate; it was specifically constructed adversarial probing.

This pattern is one of brennerbot's load-bearing mechanisms. This file documents how to apply, monitor, and recover the GAN discipline in a multi-pane setup.

---

## Why GAN

A single mind has blind spots. A peer-collaboration without enforced adversarial discipline collapses into mutual reinforcement. The GAN discipline forces:

- Generator (Investigator pane): produce hypotheses with mechanism + falsifier
- Discriminator (Devil's-Advocate / cross-family Investigator): attack the strongest version of each hypothesis

The output of the loop is hypotheses that survived adversarial probing. A confirmed H is one that the GAN couldn't kill within the session's budget.

Without GAN discipline, brennerbot reduces to "swarm vote" which is anti-Brenner. With GAN, the swarm produces evidence-grounded verdicts.

---

## The classical Brenner-Crick GAN

Per Brenner's transcript:

> "Crick would generate the wildest possible interpretations of an observation. I would then exclude them, one by one, until what remained was either definitively true or definitively unfalsifiable."

(Paraphrased from the transcript; cite per SOURCE-CORPUS.md.)

Key features:

1. **Cognitive distinctness**: Crick and Brenner had different mental models, training, and intuitions. They didn't agree by default.

2. **Adversarial-not-personal**: The discipline was explicitly about ideas, not personalities. Brenner respected Crick AND aggressively attacked Crick's hypotheses.

3. **Falsifier-first**: Each generated hypothesis came with an explicit falsifier (the observation that would prove it wrong). The discriminator's job was to find that observation OR prove it inaccessible within the experimental budget.

4. **Productive disagreement**: Their debates produced sharper hypotheses, not softened compromises. (Anti-F-601 silent averaging.)

---

## Bot-era adaptation

Brennerbot maps this to multi-pane:

```
Generator role: Investigator pane (per MO-04a-investigate.md)
Discriminator role: Devil's-Advocate pane (per MO-04b-devils-advocate.md)
                    AND cross-family Investigator (per MO-cross-family-debate.md)
Adjudicator role: Phase 5 Adjudicator (per MO-05b-adjudicate.md)
```

The GAN runs primarily in Phase 4 (per-H investigation) and Phase 5 (debate). The Adjudicator is a third role that decides the GAN's outcome.

### Cognitive distinctness via model family

Brennerbot enforces distinctness via **model family**:

- Generator pane: family A (e.g., cc)
- Discriminator pane: family B (e.g., gmi)
- Adjudicator pane: family C (or B, but rotated)

Per OC-014 (OPERATOR-CARDS.md), champions of a debate must be from different families. The model-family difference produces cognitive distinctness analogous to Brenner-vs-Crick training difference.

When only one family is available (Solo tier), the GAN degrades. Mark in `phase0_scope_decision.md § triangulation_degraded`.

---

## Generator pane mechanics

Per MO-04a-investigate.md, the Investigator (generator):

1. Reads the H bead's `claim`, `mechanism`, `falsifier`.
2. Searches corpus for evidence (verbatim quotes).
3. Files EV-NNN with verbatim quotes + provenance.
4. Updates the H bead state if falsifier-firing evidence found.

### Generator quality criteria

- Does the generator produce ≥1 specific claim with a clear mechanism?
- Is the falsifier observable in <1h of investigation?
- Does the generator cite verbatim quotes (not paraphrases)?

Per CRITIQUE-CRAFT.md, low-quality generators produce vague hypotheses that the discriminator can't usefully attack.

---

## Discriminator pane mechanics

Per MO-04b-devils-advocate.md, the Devil's-Advocate (discriminator):

1. Reads the generator's evidence pack.
2. Identifies systematic blind spots in the generator's evidence (per CRITIQUE-CRAFT.md citation density).
3. Applies its family's distinctive lens (different cognitive style).
4. Files ≥1 critique (`C-*` bead) with severity calibrated.
5. If counter-evidence found, files EV-NNN with `refutes:[H-NNN]`.

### Discriminator quality criteria

- Did the discriminator attack the **strongest** version of the H (steelman)?
- Does the critique cite specific EVs from the evidence pack?
- Is the severity calibrated (not inflated)?
- Did the family-distinctive lens surface anything the same-family critique would have missed?

### Family-distinctive lenses

Per MO-cross-family-debate.md:

- **cc strength**: careful citation reading; spots misinterpretation, missed quote context
- **cod strength**: broad pattern matching; spots domain analogues, parallels with adjacent fields
- **gmi strength**: formal/mathematical framing; spots scale-physics issues, edge cases in proofs

These are tendencies, not absolutes. Operators can encourage any pane to apply any lens; but the family's *default* tendency is what the GAN exploits.

---

## Why families must differ

If generator and discriminator are same family:

- Both panes share training data → likely share blind spots
- Both panes share interpretive defaults → less likely to surface counter-evidence
- The "discriminator" produces critiques that confirm the generator's framing

Per F-504 (same-family champions), this collapses the GAN. Per Phase 6 distillation, the disagreement register would be thin (F-601 silent averaging).

The cross-family rule is enforced via:

- OC-014 (champion pairing must be cross-family)
- OC-019 (Phase 7 audit panes must include cross-family)
- `scripts/check-rotation-rules.sh` Rule 4 (audit family diversity)

---

## GAN failure modes

### F-GAN-1: Generator inflation (proposes unfalsifiable Hs)

**Symptom:** Investigator produces 5+ hypotheses, all with falsifiers like "if the system breaks, hypothesis is wrong" (vague).

**Recovery:**
- Run `subagents/falsifier-grader.md` on each H.
- Reject Hs with grade Poor; force re-write or deprecate.

### F-GAN-2: Discriminator capture (devil's-advocate becomes apologist)

**Symptom:** Devil's-Advocate critiques are mild, severity:minor only, never load-bearing.

**Recovery:**
- Apply `MO-mode-flip-investigator-to-advocate.md` (force-flip)
- If pane consistently underwhelms, swap to different family pane

### F-GAN-3: Adjudicator capture (rubber-stamp)

**Symptom:** Adjudicator never kills any H (per F-501).

**Recovery:**
- Rotate Adjudicator (per OC-015)
- Verify Adjudicator's family ≠ generator's family
- Apply † Theory-Kill operator explicitly

### F-GAN-4: GAN convergence too fast

**Symptom:** Phase 4 round 1 converges with 0 Hs killed; all confirmed.

**Recovery:**
- Suspect F-403 (confirmation bias)
- Run additional cross-family debate via MO-cross-family-debate.md
- If still no kills: Hs were too easy / falsifier was too lenient → return to Phase 1

### F-GAN-5: GAN never converges (all Hs killed)

**Symptom:** Phase 4 round N kills all hypotheses; nothing survives.

**Recovery:**
- Question framing was wrong (per AE-1.* in PHASE-1-ANTI-EXAMPLES.md)
- Return to Phase 1; sharpen scope or paradox
- The "answer" might be: "the question is malformed"

### F-GAN-6: Cognitive monoculture (all panes same family)

**Symptom:** `scripts/list-distinct-model-families.sh` returns only one family.

**Recovery:**
- Solo/Pair tier with one family is methodologically degraded
- Document in scope_decision; flag in HANDBACK
- For T3+, defer until additional family available

---

## Recovery patterns

For each GAN failure mode, the recovery pattern follows three steps:

1. **Detect**: explicit metric or symptom recognition
2. **Stabilize**: pause swarm; document in session-logs
3. **Recover**: apply specific MO + (if needed) tier escalation

### Recovery-Pattern-A: Mode flip (most common)

Apply `MO-mode-flip-investigator-to-advocate.md`:

```
Pane <N> has been proposing too many supporting EVs and too few refuting EVs.
Flip role: from this round forward, you are explicitly the Devil's-Advocate.
Your task: find counter-evidence to the strongest claim. If you can't, file
that as itself an observation (per ⊙ Productive-Ignorance).
```

This flip is reversible at next round. Often reveals false-confidence.

### Recovery-Pattern-B: Cross-family escalation

When same-family GAN fails: add one fresh pane in a different family and retire the old pane from new assignments.

```bash
# Add a Gemini pane to replace a failed Claude-family investigation lane.
ntm add <session> --gmi=1 --prompt="Take over pane 3's H/EV assignments; read session-logs/respawn-3-<ISO>.md first."
```

Then re-dispatch the affected H investigation. Often surfaces missed evidence.

### Recovery-Pattern-C: Falsifier-grader hard reset

When too many Hs have weak falsifiers:

1. Run `subagents/falsifier-grader.md` on all active H.
2. Triage: keep only Hs with grade Acceptable or better.
3. Demote weak Hs to "deferred" with explicit reason.
4. Continue Phase 4 with reduced slate.

This often un-stuck Phase 4 convergence.

---

## Worked examples

### Example 1: Healthy GAN

**Setup:** Investigation of database query plan regression.

- p1 (cc) Investigator: "Query plan changed at 14:18 deploy; load-bearing optimizer change."
- p2 (gmi) Devil's-Advocate: "Cite plan-cache hit rate drop and pg_stat_statements diff."
- p1 files EV-014 (plan diff before/after deploy, verbatim from pg_stat_statements).
- p2 files EV-018 (counter: same plan was used in staging without regression).
- p3 (cod) Adjudicator weighs: EV-014 W=0.85; EV-018 W=0.6 (staging != prod scale).
- Verdict: H confirmed with caveat (re-verify scale assumption).

**GAN succeeded:** discriminator surfaced staging-vs-prod gap; adjudicator weighted appropriately.

### Example 2: Failing GAN, recovered

**Setup:** Investigation of authentication latency.

- p1 (cc) Investigator: "JWT validation is slow; recommend caching."
- p2 (cc) Devil's-Advocate: "Yes, JWT validation is slow; agree caching is needed."

**Detection:** Same-family champions (F-504). Discriminator confirmed instead of attacked.

**Recovery:** Apply Pattern-B (cross-family escalation):
- Kill p2; respawn as gmi.
- Re-dispatch H investigation with cross-family probe.

**Outcome:** New p2 (gmi) surfaces "JWT validation only contributes 5ms; the actual bottleneck is database session lookup at 80ms." H reframed; investigation continues.

---

## Composition with operators

Per OPERATORS.md, the GAN integrates with:

- ◊ Paradox-Hunt: Generator looks for paradoxes; Discriminator tests if they're real or apparent
- ⊘ Level-Split: Generator proposes at one level; Discriminator probes lower or higher levels
- 𝓛 Recode: Both Generator and Discriminator may recode the H to surface ambiguity
- ✂ Exclusion-Test: Discriminator's primary tool for falsifier-firing
- 🤝 GAN: this is the integration point — operators 𝓛/✂/⊘ are deployed within the GAN structure
- † Theory-Kill: when Discriminator successfully kills an H, the kill is recorded
- ⊙ Productive-Ignorance: a special pane that participates in the GAN without reading corpus

The GAN is the *substrate* on which operators run.

---

## GAN telemetry

Track per session:

- **Generator productivity**: Hs proposed per round
- **Discriminator productivity**: critiques (C-*) filed per round
- **Falsifier-firing rate**: % of investigations that fire a falsifier
- **Cross-family ratio**: % of debates with cross-family champions
- **Adjudicator kill rate**: % of debates resulting in H state flip

Healthy session targets:

- Generator productivity: 1-2 Hs per round per Investigator
- Discriminator productivity: 1-2 C-* per H per round
- Falsifier-firing rate: 30-50% (per OC-009)
- Cross-family ratio: ≥80% for T3+
- Adjudicator kill rate: 30-50% (per F-501 calibration)

Per OPERATOR-CALIBRATION-LOG.md, track per-operator drift over time.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Run GAN with same-family panes | Defeats the load-bearing mechanism |
| Treat Devil's-Advocate as "balance" not "attack" | Mild critiques don't kill weak Hs |
| Adjudicator that splits the difference between champions | Should pick a winner based on evidence, not compromise |
| Skip falsifier-grader on confirmed Hs | F-303 silent drift catches you eventually |
| Mode-flip without explicit dispatch | Operator memory drifts; document the flip |
| Treat GAN as Phase 4 only | Phase 5 debates and Phase 7 audits are also GAN-mediated |

---

## When the GAN can't run

For very small T1 questions (Solo tier, single pane):

- Mode-flip the pane between rounds: round 1 = generator, round 2 = discriminator
- Operator manually applies the GAN structure
- HANDBACK explicitly notes: "single-pane GAN; degraded; not equivalent to multi-pane"

For sessions where one family is unavailable:

- Run with degraded GAN (2 families instead of 3)
- Document the gap
- For T4+: defer the session until full triangulation possible

---

## Cross-references

- OPERATORS.md (the cognitive operators that run within GAN)
- ROSTER-PLANS.md (per-tier roster including GAN role assignments)
- MO-cross-family-debate.md (forced cross-family adversarial probing)
- MO-mode-flip-investigator-to-advocate.md (recovery from F-GAN-2)
- subagents/falsifier-grader.md (falsifier quality grading)
- OPERATOR-CARDS.md OC-014 + OC-015 (champion + adjudicator cross-family rules)
- The Brenner transcript (per SOURCE-CORPUS.md) — original GAN exemplar
