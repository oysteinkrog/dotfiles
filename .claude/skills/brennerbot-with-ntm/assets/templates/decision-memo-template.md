# Decision Memo — RS-<YYYYMMDD>-<slug>

**Decision date:** <YYYY-MM-DD>
**Question:** <verbatim from question_of_record.md>
**Decision-rule (from Phase 1):** <verbatim>

---

## Recommendation

**<one-sentence verdict>**

Reasoning ladder:

1. <load-bearing claim 1, with EV-NNN cite>
2. <load-bearing claim 2, with EV-NNN cite>
3. <synthesis>

---

## Reasoning

<1-2 paragraphs of detailed reasoning. Cite specific EV-NNN, T-NNN, and DEBATE-NNN for every empirical claim.>

---

## Key uncertainties

(Hypotheses that survived investigation but didn't reach confirmed state — what we don't know that could change the answer.)

- H-NNN (state: deferred): <one-line> — would change recommendation if <observation>
- H-NNN: <...>

---

## What would change the recommendation

The decision-rule falsifier (Brenner ✂):

- Specific observation A → switch to recommendation X
- Specific observation B → defer until <event>
- Specific observation C → escalate tier (return to brennerbot)

Operator: review these triggers periodically; if any fire, re-engage.

---

## Dissenting opinions

(Surfaced from disagreement_register.md per Talmudic discipline. Even when meta-synthesis chose one view, dissent is preserved here.)

### D-001 — <subject of disagreement>
- **Per cc:** <verbatim from by_cc.md>
- **Per cod:** <verbatim from by_cod.md>
- **Per gmi:** <verbatim from by_gmi.md>
- **Meta chose:** <which view, with reasoning>

(repeat per significant disagreement)

---

## Risk register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| <risk 1> | <low/med/high> | <low/med/high> | <specific> |
| <risk 2> | ... | ... | ... |
| <risk 3> | ... | ... | ... |

---

## Reversibility analysis

- **Reversibility class:** fully | partially | one-way
- **Recovery cost if wrong:** <hours | days | weeks | months>
- **Recovery procedure:** <step-by-step paragraph — if this happens, do this>
- **Decision deadline (when reversibility window closes):** <date>

---

## Confidence

Per CONFIDENCE-SCORING.md:

- **Recommendation confidence:** high | medium | low | speculative
- **Per-claim confidence in reasoning ladder:**
  - Claim 1: <level>
  - Claim 2: <level>
  - Claim 3: <level>
- **Operator calibration applied:** yes | no — note from OPERATOR-CALIBRATION-LOG.md if applicable

---

## Provenance

- **Workspace:** <WORKSPACE_PATH>
- **Session ID:** <RS-...>
- **Roster tier:** <T1-T5>
- **Wall time:** <H>h
- **Methodology compliance:**
  - Falsifier coverage: <N>/<M>
  - Third alternative: <yes | no>
  - Source corpus coverage: <N> §-anchors
  - Operator coverage: <N>/15

- **Phase 7 audit verdict:** converged at trio-round <N>
- **Phase 10 drift verdict:** <convergent | divergent-improvement | divergent-regression | mixed>

---

## Operator sign-off

- [ ] Memo reviewed
- [ ] Confidence calibration applied
- [ ] Dissent surfaced
- [ ] Reversibility verified
- [ ] Ready to act

**Operator:** <name>
**Date:** <ISO>

---

## User counter-sign

- [ ] User has read this memo
- [ ] User accepts reasoning chain OR specifies which claim they dispute
- [ ] User accepts reversibility analysis
- [ ] User authorizes the action

**User:** <name>
**Date:** <ISO>

---

*Decision memos at T3+ should not be acted on without operator + user sign-off. T5 decisions additionally require external review.*
