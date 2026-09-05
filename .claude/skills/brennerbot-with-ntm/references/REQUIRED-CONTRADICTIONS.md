# REQUIRED-CONTRADICTIONS.md — The Six Oscillations the Operator Must Navigate

<!-- TOC: Why oscillations | The six pairs | How they map to operator behavior | Per-phase oscillation emphasis | Detection: when one pole is dominating | Recovery: how to re-balance | Anti-patterns | Cross-references -->

> "There are brilliant people that can never accomplish anything. And there are people that have no ideas but do things. And if only one could chimerise them — join them into one person — one would have a good scientist."
> — Sydney Brenner

The Brenner method demands *contradictory traits held in tension*. Not a single personality setting; not "balance"; **oscillation between modes**. An operator stuck on one pole produces consistent failure modes; an operator who oscillates correctly produces compounding insight.

Mined from `/dp/brenner_bot/README.md § The Required Contradictions`.

---

## Why oscillations

Brenner observed that brilliant theoretical work AND careful empirical work are necessary but insufficient *individually*. Theory without experiment is fan-fiction; experiment without theory is butterfly-collecting. The method requires moving deliberately between poles, not blending them.

For brennerbot operators: each oscillation has a *characteristic failure mode at each pole*. Recognize which pole you're on; deliberately move to the other.

---

## The six pairs

### 1. Imagination ↔ Focus

**Imagination pole:** generate possibilities; spread probability mass; entertain "what-if" scenarios; explore cross-domain analogies.
**Focus pole:** prune possibilities; concentrate effort on one path; commit; ignore distractions.

**Brenner exemplar:** "I'd think about a thing for an hour, generating wild possibilities, then commit to one experiment for the day."

**Failure modes:**
- Stuck on imagination → endless brainstorm, no commitment, Phase 4 doesn't start
- Stuck on focus → tunnel vision, missed third-alternatives, F-301 risk

**In brennerbot:** Phase 3 emphasizes imagination (generate ≥3 H including third-alternative); Phase 4 emphasizes focus (each Investigator owns one H). Phase 5 returns to imagination via cross-family debate.

### 2. Passion ↔ Ruthlessness

**Passion pole:** love your hypothesis; defend it; build it up; care about the outcome.
**Ruthlessness pole:** kill your hypothesis when evidence fires the falsifier; don't sunk-cost-fallacy; let go.

**Brenner exemplar:** "I loved that theory until I had to murder it."

**Failure modes:**
- Stuck on passion → F-501 (adjudicator refuses to kill), F-403 (only confirming evidence)
- Stuck on ruthlessness → kill Hs prematurely; never give them a fair test (F-705 audit-acceptance failure)

**In brennerbot:** the Investigator champions their H (passion); the Devil's-Advocate attacks it (ruthlessness); the Adjudicator decides which pole won. Per BRENNER-GAN-MECHANICS.md.

### 3. Ignorance ↔ Learning

**Ignorance pole:** approach problems as an outsider; spread priors; productive-ignorance.
**Learning pole:** absorb the literature; build expertise; know what's been tried.

**Brenner exemplar:** "I know enough about [domain] to be dangerous, but not so much that I think I know the answer."

**Failure modes:**
- Stuck on ignorance → reinvent the wheel; miss known constraints (F-102 corpus drift if you ignore prior work)
- Stuck on learning → expert prior collapse; ⊙ pane corruption; consensus capture (per AE-7.5, S8 in STRESS-TEST-SCENARIOS)

**In brennerbot:** different panes occupy different positions on this axis. The ⊙ pane stays IGNORANT; other panes LEARN from corpus. Both contribute different value. Per OC-005.

### 4. Attachment ↔ Detachment

**Attachment pole:** care deeply about the outcome; the question matters; the deliverable will affect real decisions.
**Detachment pole:** the verdict could go either way; you're indifferent to which hypothesis wins; truth-seeking vs truth-confirming.

**Brenner exemplar:** "If you don't care about the outcome, you won't push hard enough. If you care too much, you'll fool yourself about which one is right."

**Failure modes:**
- Stuck on attachment → motivated reasoning, F-403 (only confirming evidence)
- Stuck on detachment → low energy, sessions don't converge, "good enough" verdicts

**In brennerbot:** the operator should be ATTACHED to question-quality (Phase 1 framing rigor) but DETACHED from which H wins. Per HANDBACK-VOICE-GUIDE.md (verdict-first; let evidence decide).

### 5. Conversation ↔ Solitude

**Conversation pole:** talk through ideas; find your blind spots via others; debate refines hypotheses.
**Solitude pole:** think alone; uninterrupted reasoning; deep work.

**Brenner exemplar:** "Crick and I argued for hours every day. Then I went home and thought about it for hours alone. Both."

**Failure modes:**
- Stuck on conversation → groupthink, drift, no individual depth
- Stuck on solitude → blind spots persist, F-501 (adjudicator can't see what champion missed)

**In brennerbot:** Phase 4 is largely solitary (Investigators dive into corpus); Phase 5 is conversational (debate); Phase 6 is mixed (per-family solitary, then cross-family conversation). Per BRENNER-GAN-MECHANICS.md.

### 6. Theory ↔ Experiment

**Theory pole:** generate predictions; build models; reason from first principles.
**Experiment pole:** observe; collect data; test predictions; let reality push back.

**Brenner exemplar:** "Theory tells you what experiment to do. Experiment tells you what theory to refine."

**Failure modes:**
- Stuck on theory → fan-fiction; H without falsifier (F-103)
- Stuck on experiment → butterfly collecting; no synthesis (F-601 silent averaging in distillation)

**In brennerbot:** Phase 3 is theoretical (hypothesis generation); Phase 4 is experimental (evidence packs); Phase 6 is theoretical again (synthesis). The phases enforce the oscillation.

---

## How they map to operator behavior

| Oscillation | Operator behavior at left pole | Operator behavior at right pole |
|-------------|-------------------------------|--------------------------------|
| Imagination ↔ Focus | dispatches MO-cross-domain-import | dispatches MO-04a-investigate (single H per pane) |
| Passion ↔ Ruthlessness | files supporting EVs aggressively | applies † Theory-Kill on falsifier-fired Hs |
| Ignorance ↔ Learning | ⊙ pane onboarding restricts file access | corpus-curator subagent ingests sources |
| Attachment ↔ Detachment | tightens Phase 1 framing | accepts Phase 5 verdict regardless of prior |
| Conversation ↔ Solitude | dispatches MO-05a cross-exam | dispatches MO-04a (solitary investigation) |
| Theory ↔ Experiment | Phase 3 hypothesis generation | Phase 4 evidence collection |

The operator's job is to *recognize which pole is currently dominant* and deliberately move to the other when needed.

---

## Per-phase oscillation emphasis

| Phase | Primary oscillation | Pole emphasized |
|-------|--------------------|--------------------|
| 1 framing | Attachment ↔ Detachment | Attachment to question quality |
| 3 hypotheses | Imagination ↔ Focus | Imagination |
| 4 investigation | Theory ↔ Experiment | Experiment |
| 5 debate | Conversation ↔ Solitude | Conversation |
| 6 distillation | Theory ↔ Experiment | Theory |
| 7 audit | Passion ↔ Ruthlessness | Ruthlessness |
| 9 handback | Attachment ↔ Detachment | Detachment (let evidence speak) |

A session that's emphasized only one pole (e.g., all imagination, no focus) will have predictable failure modes.

---

## Detection: when one pole is dominating

Signs the operator is stuck on a pole:

| Stuck pole | Symptoms | Recovery |
|------------|----------|----------|
| Imagination | Phase 4 hasn't started after 3 ticks | Force MO-04a-investigate dispatch with single H assignment |
| Focus | Slate has 1 H; no third-alternative | Dispatch MO-03c; force-spawn ⊙ pane if needed |
| Passion | F-403 fires (only supporting EVs) | Mode-flip Investigator to Devil's-Advocate |
| Ruthlessness | All Hs killed in Phase 5; nothing survives | Reframe at Phase 1 — question may be malformed (per AE-1.2) |
| Ignorance | Hs cite no prior work; reinventing | Add corpus-curator pane or expand corpus pinning |
| Learning | All Hs match consensus; no novelty | Add ⊙ pane; force MO-cross-domain-import |
| Attachment | Operator dismisses Phase 5 verdict | Pause; review evidence; if can't accept, the framing was attached to a prior |
| Detachment | Operator doesn't care which H wins | Re-engage; if genuinely indifferent, downgrade tier (the question may be T1 curiosity) |
| Conversation | Phase 4 is endless debate; no individual depth | Force solitary investigation rounds |
| Solitude | Phase 5 debates produce no debate | Cross-family champion mandate (OC-014) |
| Theory | Phase 4 has 0 EVs after multiple rounds | Force quickie pilot dispatch |
| Experiment | Phase 6 produces no synthesis (just data dump) | Force MO-06b meta-synthesis with explicit theory frame |

Each row has a specific MO/recovery — not just "balance better."

---

## Recovery: how to re-balance

When you notice you've been on one pole too long (per OBSERVABILITY.md tick cadence):

1. **Identify which pole** (per the table above)
2. **Apply the recovery dispatch** specific to that pole
3. **Re-tick after recovery** — pane state may have shifted

This is NOT "be more balanced." It's specifically: detect → name → switch poles via concrete dispatch.

Per OPERATOR-CALIBRATION-LOG.md: track which oscillation each operator most often gets stuck on. Different operators have different default poles.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| "Just be balanced" — vague platitude | Brenner method is *oscillation*, not blend |
| Refuse to switch poles "I'm in flow" | Single-pole sessions have predictable failure modes |
| Treat the operator's job as *one* pole | All six oscillations are the operator's responsibility |
| Single pane occupies all poles | Different panes are designed for different poles (⊙ ignorance, Investigator focus, etc.) |
| Phase 7 audit by same pane that did Phase 4 | Same operator; same pole; F-705 |
| Skip imagination because "we have hypotheses already" | Each phase needs imagination at its threshold |
| Skip ruthlessness because "we don't want to lose progress" | Sunk-cost fallacy; per Brenner principle 8 (kill theories early) |
| Operator solitude with no swarm input | The skill is *multi-pane*; solitary operating defeats the design |

---

## When you can't oscillate

Sometimes external constraints force you to one pole:

- **Wall-time pressure** → forced focus (Phase 4 single-H investigation)
- **Solo tier** → forced solitude (no debate possible)
- **Single-family roster** → forced focus (cross-family unavailable)

In each case: document the constraint in `phase0_scope_decision.md § oscillation_constraints`. The HANDBACK should note which oscillation was suppressed by external factor.

This is honesty: the methodology has limits when oscillations can't run.

---

## Cross-references

- [TEN-PRINCIPLES.md](TEN-PRINCIPLES.md) — the principles, several of which embody oscillations
- [BRENNER-GAN-MECHANICS.md](BRENNER-GAN-MECHANICS.md) — Conversation ↔ Solitude in formal GAN structure
- [BRENNER-VOCABULARY.md](BRENNER-VOCABULARY.md) — productive ignorance, Don't Worry, etc.
- [OPERATOR-CALIBRATION-LOG.md](OPERATOR-CALIBRATION-LOG.md) — track per-operator pole tendencies
- [OPERATOR-CARDS.md](OPERATOR-CARDS.md) — specific recovery dispatches
- /dp/brenner_bot/README.md § The Required Contradictions — original source
