# WHAT-IF-COUNTERFACTUAL-EXPLORER.md — Counterfactual Reasoning at Session Scale

## Table of Contents

- Why counterfactuals
- The 4 counterfactual types
- The exploration protocol
- Per-counterfactual evidence requirements
- When to run a what-if
- Per-phase what-if integration
- Output: counterfactual_register
- Anti-patterns
- Cross-references

A live hypothesis answers "what is true?" A counterfactual asks **"what would be different if X?"** — and the structured exploration of counterfactuals is one of brennerbot's least-used but highest-leverage tools.

This file specifies the counterfactual exploration protocol, the 4 types of counterfactuals, the evidence requirements, and the integration with the artifact.

Mined from `/dp/brenner_bot/CHANGELOG.md` v0.2.0 § Implement What-If Scenario Explorer for counterfactual reasoning.

---

## Why counterfactuals

The Brenner method emphasizes *what would I see?* (per ⌂ Materialize). Counterfactuals extend this:

- *What would I see if H1 were true and H2 were false?*
- *What would I see if A1 (assumption) failed?*
- *What would the verdict be if EV-007 were retracted?*

Counterfactuals surface **brittleness**: if your verdict depends on one fragile assumption, the counterfactual exposes it. They also surface **resilience**: if H1 survives counterfactuals on A1, A2, A3, that's positive evidence for H1.

Without counterfactual reasoning:
- Verdicts feel certain but rest on un-stress-tested assumptions
- Phase 7 audit catches direct flaws but not "what if this assumption were different?"
- Cross-session reconciliation can't compare verdicts under different premise sets

---

## The 4 counterfactual types

### Type 1: Hypothesis counterfactual

> "What would the verdict be if H1 were definitively true?"
> "What would the verdict be if H1 were definitively false?"

For each surviving H, run the verdict assuming H is locked-true vs locked-false. The diff highlights which downstream conclusions actually depend on H.

### Type 2: Assumption counterfactual

> "What would the verdict be if A1 were falsified?"
> "What would the verdict be if A1 had a different value (e.g., diffusion 10× lower)?"

For each load-bearing assumption (per the assumption_ledger), explore the verdict under counterfactual values. This is **scale-physics counterfactual** — particularly valuable for assumptions tagged `type: scale_physics`.

### Type 3: Evidence counterfactual

> "What would the verdict be if EV-007 were retracted?"
> "What would the verdict be if EV-007 said the opposite?"

For each high-W EV (per EVIDENCE-WEIGHTING-TAXONOMY.md), run the verdict without it. Identifies single-EV-dependent verdicts.

### Type 4: Framing counterfactual

> "What would we conclude if the question of record were stated differently?"
> "What if we asked X instead of Y?"

For Phase 1 reframe scenarios. Per AE-1.* in PHASE-1-ANTI-EXAMPLES.md, framing-sensitive verdicts are flagged here.

---

## The exploration protocol

For each counterfactual:

1. **State the counterfactual** explicitly
2. **Lock the counterfactual condition** in the workspace state
3. **Re-run the relevant phase(s)** under the counterfactual
4. **Record the divergent verdict + reasoning trail**
5. **Compare to baseline verdict**
6. **File a counterfactual record** (CF-NNN bead)

```yaml
# CF-001 bead schema
id: CF-001
label: counterfactual
type: hypothesis | assumption | evidence | framing
target: H-001 | A-002 | EV-007 | RT
condition: <"H-001 is true" | "A-002 is falsified" | etc.>
divergent_verdict: <how verdict changes>
divergent_reasoning: <which Hs flip state, which tests fail, etc.>
brittleness_score: low | medium | high | critical
created_at: <ISO>
created_by: <agent identity>
```

`brittleness_score`:
- `low` — verdict robust to this counterfactual
- `medium` — verdict shifts modestly (e.g., confidence drops one level)
- `high` — verdict shifts significantly (different H wins)
- `critical` — verdict reverses entirely

---

## Per-counterfactual evidence requirements

| Counterfactual type | Evidence required to claim a divergent verdict |
|---------------------|------------------------------------------------|
| Type 1 (hypothesis) | Show how downstream chain (H → predictions → tests → assumptions) responds |
| Type 2 (assumption) | Show how H states change; calculate scale-physics differently |
| Type 3 (evidence) | Re-aggregate W per H without the EV; show new verdict |
| Type 4 (framing) | Re-derive ≥1 H under new framing; show whether prior Hs survive |

Type 2 (assumption) is most rigorous: scale-physics counterfactuals require explicit recalculation. Type 1-3 can use the W-axis approximation (per BAYESIAN-FRAMEWORK.md).

---

## When to run a what-if

Trigger conditions:

- **Phase 7 audit**: pre-publication-review for T4+ sessions runs Type 2 + Type 3 by default
- **Adversarial Critic discovery**: a critique of severity ≥ serious that targets an assumption → Type 2 counterfactual
- **Cross-session conflict**: two sessions reach divergent verdicts on the same question → Type 4 counterfactual to identify the framing diff
- **Pre-decision T4+**: before HANDBACK informs an irreversible decision → at least Type 2 across all `type: scale_physics` A's
- **Operator-initiated**: any time the operator senses brittleness ("this verdict feels fragile")

For T3 sessions: ≥1 counterfactual per session (typically Type 2 or Type 3).
For T4+: comprehensive counterfactual suite (≥3 per Type).

---

## Per-phase what-if integration

| Phase | What-if activity |
|-------|---------------------|
| 1 framing | (Optional) Type 4 sanity check |
| 3 hypothesis | (Optional) Type 1 thought experiments |
| 4 investigation | Type 3 emerges naturally as EVs are imported |
| 6 distillation | Distillations note counterfactual sensitivities |
| 7 audit | **Mandatory for T4+**: Type 2 + Type 3 across full slate |
| 8 freeze | Counterfactual register frozen + included in artifact |
| 9 handback | HANDBACK § Caveats lists `brittleness_score: high` counterfactuals |

---

## Output: counterfactual_register

A new section in the artifact (between § 6 Anomaly Register and § 7 Adversarial Critique):

```markdown
## 6.5 Counterfactual Register

### CF-001 — Type 2 Assumption Counterfactual

**Target:** A-002 (diffusion constant for morphogen)
**Condition:** Diffusion = 0.5 μm²/s instead of asserted 10 μm²/s
**Divergent verdict:** H-001 (gradient model) state would transition `validated` → `under_attack`; H-003 (timing model) state would transition `active` → `validated`
**Brittleness:** critical — verdict reverses
**Created by:** GreenValley
**Counterfactual evidence:** [external: FRAP measurements in tissue context, Ferrell 2019] suggests in-tissue diffusion may be 10-20× lower

### CF-002 — Type 3 Evidence Counterfactual
...
```

For HANDBACK: surface `brittleness: critical` and `brittleness: high` counterfactuals explicitly. The verdict + brittleness pair is more honest than verdict alone.

---

## Composition with brennerbot phases

The counterfactual register is *parallel* to the main artifact, not a replacement. The verdict in HANDBACK is the **base verdict** (what the evidence supports); the counterfactual register notes *under what assumptions the base verdict holds*.

Decision-makers downstream of HANDBACK get both:
- "We recommend H-001 with high confidence"
- "But: if A-002 were 10× off, we'd recommend H-003 instead. We have not directly verified A-002 — see CF-001."

This is the difference between *epistemic confidence in the verdict* and *robustness of the verdict to known unknowns*.

---

## Cross-session counterfactual aggregation

Per BRENNERBOT-AT-SCALE.md: track counterfactuals across sessions. Patterns:

- **Recurring brittleness on same assumption type** → that assumption needs better measurement protocol
- **Recurring framing-counterfactuals reverse the verdict** → the question class is inherently ambiguous; default to Type 4 in Phase 1
- **Operators consistently underestimate brittleness** → calibration coaching (D-Cal-8 in OPERATOR-CALIBRATION-LOG.md)

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip counterfactuals because "the verdict feels right" | Confidence without stress-test is overconfidence |
| Run only Type 1 (hypothesis) counterfactuals | Type 2 (assumption) catches more real brittleness |
| File counterfactuals without `brittleness_score` | Validator rejects |
| `brittleness: low` for every counterfactual | Sandbagging; per audit, recalibrate |
| Don't surface critical-brittleness in HANDBACK | Misleading; HANDBACK § Caveats must list |
| Counterfactual without evidence requirements (just speculation) | Must show how verdict actually changes |
| Skip Type 4 (framing) | Often the highest-leverage counterfactual |

---

## Cross-references

- `BAYESIAN-FRAMEWORK.md` — W-axis re-aggregation under counterfactual evidence
- `HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md` — H state transitions under counterfactuals
- `TRIBUNAL-AND-OBJECTION-REGISTER.md` — counterfactual-driven critiques
- `PHASE-1-ANTI-EXAMPLES.md` — framing-counterfactual triggers
- `HANDBACK-VOICE-GUIDE.md` — surfacing brittleness in caveats
- `BRENNERBOT-AT-SCALE.md` — cross-session aggregation
- `BRENNERBOT-DOCTOR-RUBRIC.md` — Pillar 4 (Convergence) considers brittleness
- /dp/brenner_bot/CHANGELOG.md v0.2.0 — feature implementation
