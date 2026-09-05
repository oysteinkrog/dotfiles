# FAILURE-MODE-ANALYTICS.md — Hypothesis-Outcome Pattern Detection

<!-- TOC: Why failure-mode analytics | The 5 outcome categories | The pattern catalog | Detection mechanisms | Cross-session aggregation | Calibration tracking integration | Per-pattern recovery | Anti-patterns | Cross-references -->

Beyond per-session "did this work?", brennerbot tracks **hypothesis-outcome patterns** across sessions to detect *systematic* failure modes — patterns of how operators, panes, or domain types fail.

This file specifies the analytics protocol, the pattern catalog, and the integration with calibration coaching.

Mined from `/dp/brenner_bot/CHANGELOG.md` v0.2.0 § Add failure mode analytics module to detect and track hypothesis outcome patterns.

---

## Why failure-mode analytics

Per-session metrics tell you "this session was good/bad." Failure-mode analytics tells you **what kind of failure tends to happen, by whom, in what context**:

- "Operator A's H-killed-by-assumption-undermined rate is 2× the pool average"
- "A4 (incident) archetype sessions consistently miss F-301 (false-binary)"
- "cod-family panes rank 3rd in falsifier quality but 1st in third-alternative discovery"

These patterns inform:
- **Coaching triggers** (per OPERATOR-CALIBRATION-LOG.md)
- **Methodology updates** (per METHODOLOGY-EVOLUTION-LOG.md)
- **Per-archetype refinements** (per ARCHETYPE-START-PACKS.md)

---

## The 5 outcome categories

Every hypothesis terminates in one of:

| Outcome | FSM state | Description |
|---------|-----------|-------------|
| `validated` | validated | Survived rigorous testing |
| `killed-by-test` | killed | Refuted by a discriminative test (T-NNN) |
| `killed-by-critique` | killed | Refuted by adversarial critique (C-NNN) |
| `killed-by-assumption-undermining` | killed | Killed because A-NNN was falsified |
| `dormant-at-freeze` | dormant | Parked; not investigated to verdict |

Plus the `refined-into-new-H` flow:

| Outcome | FSM state | Description |
|---------|-----------|-------------|
| `refined-into-validated` | refined → ... → validated | Refined; descendant validated |
| `refined-into-killed` | refined → ... → killed | Refined; descendant killed |
| `refined-incomplete` | refined → ... → dormant | Refinement chain not completed |

The **outcome distribution** per session/per operator/per archetype is a fingerprint.

---

## The pattern catalog

Cross-session analysis surfaces these patterns:

### Pattern P-1: Confirmation bias (`killed-by-critique` rate too low)

**Signature:** session has 0 critique-driven kills despite 3+ active critiques.
**Diagnosis:** F-403 (confirmation-only bias).
**Recovery:** mandate adversarial round per H; rotate Devil's-Advocate.

### Pattern P-2: Test-design weakness (`killed-by-test` rate too low)

**Signature:** kill_rate < 0.5 across multiple sessions.
**Diagnosis:** Tests are confirmatory, not discriminative.
**Recovery:** DISCRIMINATIVE-TEST-DESIGN.md 7-step protocol; per-pane scoring.

### Pattern P-3: Assumption-undermining cluster

**Signature:** ≥30% of kills are `killed-by-assumption-undermining` across recent sessions.
**Diagnosis:** Phase 1 framing is consistently picking shaky assumption foundations.
**Recovery:** apply ANTI-ANALOGY-AND-PLAUSIBILITY.md plausibility filter at Phase 1.

### Pattern P-4: Dormant-pile-up

**Signature:** ≥20% of H end up `dormant-at-freeze` across recent sessions.
**Diagnosis:** Sessions are over-scoped; can't investigate all proposed Hs.
**Recovery:** stricter Phase 3 triage; reduce per-session H slate to ≤4.

### Pattern P-5: Refinement loops

**Signature:** Average refinement-chain length > 3 (H → H' → H'' → H''').
**Diagnosis:** Hypotheses being patched rather than killed (Brenner principle 8 violation).
**Recovery:** When considering refinement, first ask "kill it instead?"

### Pattern P-6: Validation-rate mismatch

**Signature:** Validation rate at session-time differs from validation rate at +30-day follow-up.
**Diagnosis:** Premature validation; Phase 7 audit insufficient.
**Recovery:** mandatory robot-stress mode (per ROBOT-MODE-AUTONOMOUS-ORCHESTRATION.md) on validated H.

### Pattern P-7: Origin-bias

**Signature:** `origin: third_alternative` Hs are killed at 2× the rate of `origin: proposed` Hs.
**Diagnosis:** Third-alternative Hs are filed as token compliance, not real candidates.
**Recovery:** EVALUATION-RUBRIC-14-CRITERIA.md criterion 5; reject filler third-alternatives.

### Pattern P-8: Operator-bias

**Signature:** Operator A's H-validation rate is 2× the pool average.
**Diagnosis:** Operator A's adjudication is too lenient (or too strict — both are biases).
**Recovery:** rotate adjudicator (per OC-013); calibration coaching D-Cal-9.

### Pattern P-9: Archetype-specific failure

**Signature:** A6 (adversarial) sessions have 3× the audit-finding rate of A1 (design-space) sessions.
**Diagnosis:** Threat-cataloging archetype lacks structural rigor.
**Recovery:** ARCHETYPE-START-PACKS.md A6 update.

### Pattern P-10: Model-family gap

**Signature:** cc-only sessions have 2× the assumption-undermining rate of cc+cod sessions.
**Diagnosis:** Single-model sessions miss assumption-fragility because the model has consistent biases.
**Recovery:** mandate ≥2 model families for T3+ (per TRIANGULATION.md).

---

## Detection mechanisms

```bash
brenner analytics failure-modes --since 30days --json
```

Output:

```json
{
  "since": "2026-04-06",
  "sessions": 14,
  "outcome_distribution": {
    "validated": 23,
    "killed-by-test": 31,
    "killed-by-critique": 4,         // ← anomalously low
    "killed-by-assumption-undermining": 18,  // ← anomalously high
    "dormant-at-freeze": 12
  },
  "patterns_detected": [
    { "pattern": "P-1", "severity": "high", "evidence": "killed-by-critique rate is 8% (pool avg 22%)" },
    { "pattern": "P-3", "severity": "medium", "evidence": "assumption-undermining rate is 38% (pool avg 18%)" }
  ],
  "recommended_actions": [
    "Mandate adversarial round per H in next 5 sessions (P-1)",
    "Apply plausibility filter at Phase 1 (P-3)"
  ]
}
```

For organizations: `brenner analytics --pool-aggregate` runs across all operators; surfaces pool-level patterns.

---

## Cross-session aggregation

The failure-mode analytics module reads:
- `outcomes` from each frozen session's beads
- `audit-findings` from Phase 7 of each session
- `OPERATOR-CALIBRATION-LOG.md` for per-operator trends

It writes:
- `metrics/failure-mode-analytics-quarterly.json` — trend report
- `metrics/pattern-detections.jsonl` — append-only log of detected patterns
- Updates to OPERATOR-CALIBRATION-LOG.md when patterns affect specific operators

Per BRENNERBOT-AT-SCALE.md: quarterly review of failure-mode analytics is the basis for METHODOLOGY-EVOLUTION-LOG.md updates.

---

## Calibration tracking integration

Patterns at the operator level feed OPERATOR-CALIBRATION-LOG.md:

| Pattern | Coaching trigger |
|---------|--------------------|
| P-1 (no critique-kills) | D-Cal-1: re-train Adversarial Critic discipline |
| P-2 (low kill_rate) | D-Cal-2: discriminative-test-design coaching |
| P-3 (assumption-clusters) | D-Cal-3: Phase 1 framing rigor |
| P-4 (dormant-pile-up) | D-Cal-4: scope discipline |
| P-5 (refinement-loops) | D-Cal-5: kill-vs-refine judgment |
| P-7 (origin-bias) | D-Cal-7: third-alternative quality |
| P-8 (operator-bias) | D-Cal-9: adjudicator-rotation discipline |
| P-10 (model-family-gap) | D-Cal-10: triangulation discipline |

(D-Cal codes extend the original D-Cal-1..5 from OPERATOR-CALIBRATION-LOG.md.)

---

## Per-pattern recovery

For each detected pattern, the analytics module suggests a recovery action. The operator is *expected* to act on it within N sessions:

```
Pattern P-1 detected (severity: high) on 2026-05-01
Recommended action: mandate adversarial round per H in next 5 sessions
Status: monitoring (5 sessions to evaluate)
```

After 5 follow-up sessions, the analytics module re-evaluates:

- If P-1 persists → escalate severity; trigger more aggressive coaching
- If P-1 resolves → log success; close pattern
- If P-1 partially resolves → document partial progress

This makes failure-mode analytics actionable, not just descriptive.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Run analytics on <10 sessions | Statistical noise; need ≥10 for stability |
| Treat all patterns as equally severe | Severity matters; P-1 + P-3 simultaneously is critical |
| Skip recovery actions | Pattern persists; operator's calibration regresses |
| Compare individual operators punitively | Coaching, not evaluation; per OPERATOR-CALIBRATION-LOG.md privacy |
| Ignore P-9 (archetype-specific) | Often points to start-pack improvements |
| Ignore P-10 (model-family-gap) | Often resolves with triangulation; cheap fix |
| Aggregate across operators without privacy controls | Per BRENNERBOT-AT-SCALE.md operator-confidentiality rules |
| Detect patterns but never close them | Patterns must resolve; persistent open patterns are themselves a meta-pattern |

---

## Cross-references

- [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md](HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md) — outcome categories tied to terminal states
- [TRIBUNAL-AND-OBJECTION-REGISTER.md](TRIBUNAL-AND-OBJECTION-REGISTER.md) — critique-driven kills
- [OPERATOR-CALIBRATION-LOG.md](OPERATOR-CALIBRATION-LOG.md) — per-operator trend integration
- [METHODOLOGY-EVOLUTION-LOG.md](METHODOLOGY-EVOLUTION-LOG.md) — quarterly methodology updates from analytics
- [ARCHETYPE-START-PACKS.md](ARCHETYPE-START-PACKS.md) — per-archetype refinements
- [BRENNERBOT-AT-SCALE.md](BRENNERBOT-AT-SCALE.md) — pool-level analytics
- [CROSS-SESSION-LEARNING.md](CROSS-SESSION-LEARNING.md) — lessons feed back into skill
- /dp/brenner_bot/CHANGELOG.md v0.2.0 § Failure mode analytics — feature source
