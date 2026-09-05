# TRIANGULATION.md — Multi-Model Triangulation Harness

<!-- TOC: Why triangulate | Triangulation discipline by phase | Calibrated triangulation prompts | Solo-tier triangulation degradation | Triangulation anti-patterns | Triangulation health metrics | When NOT to triangulate -->

The skill's most distinctive value comes from running multiple model families (cc, cod, gmi) in parallel and *forcing them to disagree*. This file documents the triangulation discipline.

Inherits patterns from `/multi-model-triangulation` skill but specialized for research synthesis.

---

## Why triangulate (the load-bearing reason)

Each frontier model has correlated training data, cultural priors, and prompt-style biases. A single-model session inherits those silently — which is why single-family sessions tend to converge on tacit consensus.

Multi-family triangulation surfaces:

- **Different operator biases.** cc tends to over-emphasize careful citation; cod tends to over-emphasize generation breadth; gmi tends to over-emphasize formal/mathematical framing. The disagreement register captures these.
- **Different blind spots.** Each model has training-distribution-correlated weak spots. Independent reads catch each other's misses.
- **Different prior weights.** Bayesian priors differ across families; meta-synthesis reveals which prior dominated and lets the operator weight accordingly.

The Phase 6 disagreement_register.md is *the* triangulation artifact. Phase 6 cannot exit without it.

---

## Triangulation discipline by phase

### Phase 1 (framing) — single-family OK

Triangulation isn't useful for Phase 1 framing. The question of record is one document; multiple framings would just produce confusion. Single agent (operator + user) writes it.

### Phase 2 (bootstrap) — assign for triangulation

The roster's model mix is locked at Phase 2. **Assignment rule:** for Squad tier, ensure ≥2 model families present. For Swarm tier, ensure all 3 (cc + cod + gmi).

If a model family is unavailable (rate-limited, not installed), record in `phase0_scope_decision.md § triangulation_degraded` and proceed with what's available — but expect Phase 6 disagreement_register to be thinner.

### Phase 3 (proposing) — divergent generation

Each Proposer pane (different family) generates hypotheses *independently* — they don't read each other's slates until Triage.

**Anti-pattern:** proposers chatting in `RS-...-INVEST-coord` thread before triage. The proposers' value comes from their *independent* generation; cross-coordination defeats triangulation. Block this in MO-03a.

### Phase 4 (investigating) — model-family rotation

Investigator panes work independently. The Devil's-Advocate pane MUST be a different family from the strongest-confidence Investigator (per ROSTER-PLANS.md role rotation rule). This forces a 🤝 GAN with cross-family discriminator.

**Anti-pattern:** all Investigators on cc; all Devil's-Advocates also on cc. Defeats the GAN. F-602 and F-501 both fire.

### Phase 5 (debating) — cross-family champions

Debate champions on the same H pair MUST be different families when possible. The adjudicator is a third family (rotating).

**Common practice:** if H-005 is cc-dominant (cc Investigator, cc supporting evidence), the cod or gmi Devil's-Advocate champions opposing-H. cc adjudicator on this debate would inherit cc's framing → use cod or gmi adjudicator instead.

### Phase 6 (distilling) — the load-bearing triangulation

This is where triangulation pays off. Each model family writes its own distillation independently:

```
distillations/by_cc.md   — cc's view (cc Synthesizer pane)
distillations/by_cod.md  — cod's view (cod Synthesizer pane)
distillations/by_gmi.md  — gmi's view (gmi Synthesizer pane)
```

Then the meta-synthesizer (different family from the dominant) reconciles:

- **Convergent kernel** — claims that appear in all 3 distillations → meta_synthesis.md § Convergent kernel
- **Pairwise disagreements** — claims where 2+ distillations differ → disagreement_register.md (≥(N choose 2) entries)
- **Open uncertainties** — claims that all 3 distillations agree they don't know

### Phase 7 (auditing) — fresh-family auditing

Phase 7 audit panes should NOT be the same family that wrote the per-family distillation in Phase 6 (per ROSTER-PLANS.md). If a pane wrote `by_cc.md`, its Phase 7 audit on `by_cc.md` is biased.

**Practice:** kill+respawn or rotate model families between Phase 6 and Phase 7.

### Phase 10 (drift check) — independent fresh agent

The drift auditor MUST be a *different process* than any swarm pane. Use the Agent tool to spawn a fresh `general-purpose` Agent. This is the deepest triangulation: a fresh family auditing the *methodology* of the entire prior session.

---

## Calibrated triangulation prompts

Mirror saas-billing's MULTI-MODEL-TRIANGULATION-PROMPTS.md but for research synthesis.

### When invoking `/multi-model-triangulation` directly

```
I need a third independent reconciliation of the per-family distillations in:
  - distillations/by_cc.md
  - distillations/by_cod.md
  - distillations/by_gmi.md

The meta_synthesizer pane has already produced meta_synthesis.md and disagreement_register.md.

Your job: produce an independent disagreement register from a fourth perspective. Compare your register to the meta_synthesizer's. Flag any disagreements the meta_synthesizer missed AND any disagreements that the meta_synthesizer fabricated.

Output: disagreement_register_triangulated.md with sections (Confirmed disagreements: meta got it right; Missed disagreements: meta should add; Fabricated disagreements: meta inflated).
```

### Per-lens prompts (when one family critiques another's distillation)

```
You are a <reviewing_family> pane reviewing a <reviewed_family> pane's distillation at distillations/by_<reviewed_family>.md.

Apply ✂ Exclusion-Test from your model family's perspective:
- Where does <reviewed_family> claim something that, from <reviewing_family>'s prior, is forbidden?
- Where does <reviewed_family> assume something that <reviewing_family> would not assume?
- Where does <reviewed_family>'s framing reveal a known model-family blind spot?

Output: critique-of-<reviewed_family>-from-<reviewing_family>.md with each item cited at <file:line> in by_<reviewed_family>.md.

This critique feeds the disagreement register. Don't be gentle — model-family criticism is the substrate of triangulation. If you have nothing to say, ⊙ Productive-Ignorance has failed and we need a different reviewer.
```

### Per-failure-class prompts (apply when a specific F-### fires)

For F-601 (silent averaging):

```
The meta_synthesis output appears to average rather than choose. Re-write meta_synthesis.md with these rules:

1. Every paragraph that combines per-family views MUST cite ≥2 specific lines from per-family distillations.
2. Every disagreement must declare a winner OR mark as "unresolved — needs Phase 4 reopen on H-NNN".
3. No paragraph may use words like "broadly", "generally", "tends to" without cited evidence.

If after this you still cannot produce ≥(N choose 2) disagreement entries, the per-family distillations are too thin — re-run MO-06a with explicit "produce ≥3 invariants and ≥3 disagreements with peers" directive.
```

For F-602 (single-family dominance):

```
The meta_synthesis cites by_<dominant>.md ≥80% of the time. Reweight:

1. For each invariant in meta_synthesis.md, find the equivalent in by_<other_1>.md and by_<other_2>.md. Cite all three.
2. If only one family has the invariant, mark it "single-family-claim — requires verification".
3. Specifically: hunt for invariants in by_<other_1>.md and by_<other_2>.md that meta_synthesis omitted.

This MAY shrink the convergent kernel and grow the disagreement register. That's correct behavior.
```

---

## Solo-tier triangulation degradation

Solo tier (1 pane, 1 model family) cannot triangulate. The disagreement_register.md is empty. Two mitigations:

### Kill+respawn for "fake triangulation"

Run Phase 6 once with the Solo pane, save by_<family>.md, kill the pane, respawn fresh on a different model family if available, run Phase 6 again, save by_<family_2>.md. The disagreement register can now have ≥1 entry.

This is *worse* than real triangulation (the second pane has no Phase 4 context fresh in mind — it has to read evidence packs from scratch) but better than no triangulation.

### Time-shifted self-triangulation

If only one model family available: run Phase 6 once, save, sleep ≥1 hour (model state in cache may shift slightly), run Phase 6 again with a different prompt framing ("write the distillation as if you were the strongest critic of your own prior reading"). Compare.

This is the weakest form. Flag explicitly in `phase0_scope_decision.md § triangulation_degraded:` and Phase 10 drift check.

---

## Triangulation anti-patterns

| ✗ | Why |
|---|-----|
| Run Phase 6 with only one family → "we don't need triangulation here" | Defeats the load-bearing reason for the methodology; degrades to single-perspective analysis |
| Have model families coordinate before Phase 6 | Their value is independent perspectives; cross-pollination silently averages |
| Treat the meta-synthesizer's choice as truth | The meta-synth is one more perspective; the operator's job is to verify the chosen synthesis |
| Skip Phase 7 audit because Phase 6 produced disagreement register | Audit catches when meta-synth itself drifted (F-1001 type for Phase 6) |
| Allow rate-limit on one family to silently de-triangulate | Record explicitly; consider waiting for the family to recover before Phase 6 |
| Use the same operator-as-pane for all model families | The model family does the bias; the same operator reasoning across families just reproduces the operator's bias 3x |

---

## Triangulation health metrics

| Metric | Healthy | Red flag |
|--------|---------|----------|
| (M-601) Disagreement entries | ≥(N choose 2) | 0 |
| (M-602) Family-citation balance | within 2× | one family >5× another |
| Per-pane evidence-pack overlap | <50% (independent reads) | >80% (likely cross-pollinated) |
| Adjudicator-family vs winner-family correlation | independent | strong correlation (F-502) |

Per [METRICS.md](METRICS.md) for full computation formulas.

---

## When NOT to triangulate

| Situation | Why skip |
|-----------|----------|
| Solo tier (one family available) | Cannot — see degradation modes above |
| Incident-investigation compressed mode | Time pressure dominates; one family is fine for 60-min triage |
| Drift-check mode (Phase 10) | Triangulation is *between* prior session output and canonical method, not between model families |
| Pre-Phase-1 framing | Question of record is single-author by design |

For everything else, triangulate. The cost (≥3× compute) is the price of methodology rigor.
