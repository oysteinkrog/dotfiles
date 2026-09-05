# EVALUATION-RUBRIC-14-CRITERIA.md — Per-Role Scoring with Weighted Criteria

<!-- TOC: Why a per-role rubric | The Universal criteria | Hypothesis Generator criteria | Test Designer criteria | Adversarial Critic criteria | Pass/Fail gates (disqualifiers) | The 7-Dimension session score | Per-criterion examples | Calibration loop | Anti-patterns | Cross-references -->

Per-pane contributions get evaluated against a 14-criterion rubric, weighted by role. Without consistent scoring, "good Phase 4 work" becomes "operator vibe." With it, sessions are comparable across operators, models, and time.

This file specifies the rubric, the role-specific criteria, the multipliers, and the disqualifying gates.

Mined from `/dp/brenner_bot/specs/evaluation_rubric_v0.1.md` and `/dp/brenner_bot/README.md § Scoring & Evaluation System`.

---

## Why a per-role rubric

Each role has a different optimization target:

- **Hypothesis Generator** maximizes hypothesis-space coverage and level-distinction quality
- **Test Designer** maximizes discriminative power and experimental feasibility
- **Adversarial Critic** maximizes severity of detected flaws and Brenner-quote groundedness

A unified rubric would over-weight some criteria for some roles. Per-role weighting (via *multipliers*) lets each role get scored on what *they* should optimize for.

The rubric values **discriminative power** over thoroughness. A single hypothesis that kills an alternative is worth more than ten "interesting observations." Scoring reflects this bias.

---

## The Universal criteria (all roles)

These apply to every contribution regardless of role.

### 1. Structural Correctness (0-3) — multiplier ×1.0

| Score | Criteria |
|-------|----------|
| 0 | Invalid JSON, missing required fields, or wrong operation type |
| 1 | Valid structure but wrong section or malformed payload |
| 2 | Correct structure with minor issues (missing optional fields) |
| 3 | Perfect compliance with delta_output_format spec |

**Automatic disqualifiers:**
- Invalid JSON syntax
- Missing `operation`, `section`, or `payload` fields
- Operation/section mismatch (e.g., KILL with no `target_id`)

### 2. Citation Compliance (0-3) — multiplier ×1.0

| Score | Criteria |
|-------|----------|
| 0 | Claims "Brenner said X" with no anchor or fake anchor |
| 1 | Uses anchors but inconsistently; mixes inference with claims |
| 2 | Correct anchor usage with minor omissions |
| 3 | All Brenner refs anchored (§n); inferences marked [inference] |

**Citation standards:**
- Direct quotes: `(§n)` required
- Paraphrases: `(§n)` required
- Synthesis across distillations: `[synthesis]` marker
- Agent's own reasoning: `[inference]` marker

### 3. Rationale Quality (0-3) — multiplier ×0.5

| Score | Criteria |
|-------|----------|
| 0 | Missing rationale or pure restatement of payload |
| 1 | Present but vague ("this is important") |
| 2 | Explains why, references operators, but incomplete |
| 3 | Clear why, which operators used, how it advances the session |

Good rationales include: which operator(s), why this advances the research thread, what alternatives it distinguishes.

---

## Hypothesis Generator (Codex) criteria — 19 points max

### 4. Level Separation (0-3) — multiplier ×1.5

Has the contributor applied ⊘ Level-Split correctly?

| Score | Criteria |
|-------|----------|
| 0 | Obvious level conflation (program/interpreter, cause/reason) |
| 1 | Some awareness but incomplete separation |
| 2 | Clear separation with minor blending |
| 3 | Crisp distinctions; mechanism + spec cleanly typed |

**Red flags:**
- "The gene tells the cell to..."
- "The organism decides to..."
- Confusing "won't" (chastity) with "can't" (impotence)

### 5. Third Alternative Presence (0-3) — multiplier ×2.0

Is a genuine third alternative included?

| Score | Criteria |
|-------|----------|
| 0 | No third alternative mentioned |
| 1 | "Both could be wrong" (placeholder, not specific) |
| 2 | Specific third alternative but derivative (special case of H1/H2) |
| 3 | Genuinely orthogonal third alternative that would invalidate both others |

Quality indicators:
- Different causal structure, not a blend
- Cross-domain transfer (⊕)
- Identifies a shared assumption that could be false

### 6. Paradox Exploitation (0-2, optional) — multiplier ×0.5

| Score | Criteria |
|-------|----------|
| 0 | Ignores contradictions or resolves prematurely |
| 1 | Notes paradox but doesn't derive hypothesis from it |
| 2 | Paradox motivates the hypothesis; missing rule identified |

### Hypothesis Generator total

```
Universal (1+2+3):     (3×1.0) + (3×1.0) + (3×0.5) = 3.0 + 3.0 + 1.5 =  7.5
Role-specific (4+5+6): (3×1.5) + (3×2.0) + (2×0.5) = 4.5 + 6.0 + 1.0 = 11.5
Total max:                                                              19.0 points
```

Note: criterion 6 (Paradox Exploitation) has max 2 (not 3); other 5 criteria max 3.

---

## Test Designer (Opus) criteria — 21.5 points max

### 7. Discriminative Power (0-3) — multiplier ×2.0

Does the test actually distinguish hypotheses?

| Score | Criteria |
|-------|----------|
| 0 | Test outcomes are identical for all H |
| 1 | Test discriminates 2 of N H |
| 2 | Test discriminates well but lacks decisive forbidden-pattern |
| 3 | Test produces unique forbidden-pattern per H |

Per BRENNER-VOCABULARY.md: "Exclusion is always a tremendously good thing."

### 8. Potency Check Sufficiency (0-3) — multiplier ×2.0

Does the test distinguish "no effect" from "assay failed"?

| Score | Criteria |
|-------|----------|
| 0 | No potency check |
| 1 | Potency check exists but ambiguous |
| 2 | Potency check present, mostly clean |
| 3 | Crisp chastity-vs-impotence distinction; positive control specified |

### 9. Object Transposition Considered (0-2) — multiplier ×0.5

Has ⟂ Object-Transpose been applied?

| Score | Criteria |
|-------|----------|
| 0 | Single system; no consideration of cheaper proxies |
| 1 | One alternative considered |
| 2 | Multiple alternatives weighed; cheapest decisive system chosen |

### 10. Score Calibration Honesty (0-2) — multiplier ×0.5

Are likelihood-ratio / cost / speed estimates honest?

| Score | Criteria |
|-------|----------|
| 0 | Inflated likelihood; understated cost |
| 1 | Some honesty; some inflation |
| 2 | Calibrated; explicit uncertainty bounds |

---

## Adversarial Critic (Gemini) criteria — 25.5 points max (with KILL)

### 11. Scale Check Rigor (0-3) — multiplier ×1.5

"The imprisoned imagination" — physical-magnitude calculations.

| Score | Criteria |
|-------|----------|
| 0 | Hand-wave ("approximately") |
| 1 | Order-of-magnitude only |
| 2 | Detailed calculation; some uncertainty bounds |
| 3 | Full ⊞ Scale-Check with diffusion / packing / capacity limits |

### 12. Anomaly Quarantine Discipline (0-3) — multiplier ×1.5

Per ΔE Exception-Quarantine: don't let Occam's broom hide debt.

| Score | Criteria |
|-------|----------|
| 0 | Ignores anomalies or rationalizes away |
| 1 | Notes anomaly without quarantine |
| 2 | Quarantines but doesn't track for resolution |
| 3 | Quarantines + cluster analysis + resolution tracking |

### 13. Theory Kill Justification (0-3) — multiplier ×1.5

"When they go ugly, kill them."

| Score | Criteria |
|-------|----------|
| 0 | KILL without rationale (DISQUALIFIER) |
| 1 | KILL with vague reason ("doesn't work") |
| 2 | KILL with citation but unclear forbidden-pattern |
| 3 | KILL with specific forbidden-pattern + EV anchor |

### 14. Real Third Alternative Detection (0-3) — multiplier ×1.5

Per ⊕ Cross-Domain: is the critic suggesting genuinely orthogonal options?

| Score | Criteria |
|-------|----------|
| 0 | Doesn't probe alternatives |
| 1 | Suggests "neither" (placeholder) |
| 2 | Specific alternative but derivative |
| 3 | Genuinely orthogonal; cross-domain import |

---

## Pass/Fail gates (disqualifiers)

Some failures are **disqualifying** regardless of other scores:

| Gate | Trigger |
|------|---------|
| Invalid JSON in delta block | Universal fail |
| Fake `§n` anchor (doesn't exist in transcript) | Universal fail |
| Missing potency check in test design | Test Designer disqualifier |
| KILL without rationale in critique | Adversarial Critic disqualifier |
| Self-citation as evidence | Universal fail (per F-403) |

A disqualified contribution scores 0 regardless of other criteria. Per OPERATOR-CALIBRATION-LOG.md, repeated disqualifiers trigger Week-2 onboarding refresher.

---

## The 7-Dimension session score

Beyond per-contribution scoring, sessions get a **7-dimension aggregate**:

| Dimension | Max | What it measures |
|-----------|-----|--------------------|
| Paradox Grounding | 20 | Does the session start from a genuine puzzle? |
| Hypothesis Kill Rate | 20 | Are hypotheses being eliminated, not just accumulated? |
| Test Discriminability | 20 | Do tests actually distinguish? |
| Assumption Tracking | 15 | Are load-bearing assumptions explicit + tested? |
| Third Alternative Discovery | 15 | Are "both could be wrong" alternatives explored? |
| Experimental Feasibility | 10 | Are tests actually executable? |
| Adversarial Pressure | 20 | Has adversarial critique been applied? |
| **Total** | **120** | |

### Grades

| Grade | Threshold |
|-------|-----------|
| A | ≥90% (108/120) |
| B | ≥80% (96/120) |
| C | ≥70% (84/120) |
| D | ≥60% (72/120) |
| F | <60% (<72/120) |

For T3+ sessions: aim for B+; T4+ sessions need A.

CLI:

```bash
brenner score RS-... --json
brenner feedback RS-... --json   # generates improvement suggestions with Brenner quotes
brenner leaderboard --limit 10   # ranks recent sessions
```

---

## Per-criterion examples

### High-scoring Hypothesis Generator delta

```
Score: 18/19

Universal (perfect):
- Structural: 3/3 (clean delta block)
- Citation: 3/3 (anchors + [inference] markers)
- Rationale: 3/3 (specifies operators ⊘ + ⊕)

Role-specific (near-perfect):
- Level Separation: 3/3 (program-vs-interpreter distinct)
- Third Alternative: 3/3 (cross-domain orthogonal)
- Paradox Exploitation: 1/2 (notes paradox, partial mechanism)

Calculation: 9 × universal-mults + 7 × role-mults = ~18.0
```

### Low-scoring (disqualified) Adversarial Critic delta

```
Score: 0 (DISQUALIFIED)

Reason: KILL operation without rationale (gate violation)
Even if other criteria scored well, the disqualifier wins.

Operator action: re-attempt; cite forbidden-pattern + EV anchor
```

---

## Calibration loop

Per OPERATOR-CALIBRATION-LOG.md:

For each pane in each session:
1. Score per-contribution at Phase 7 (per `subagents/evidence-grader.md` extension)
2. Aggregate per-pane average
3. Track in OPERATOR-CALIBRATION-LOG.md
4. Quarterly: identify panes whose role-specific criteria score below 60% consistently
5. Coaching trigger D-Cal-6: re-train pane on role-specific criteria

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Apply Universal criteria to role-specific scoring (wrong multipliers) | Per-role multipliers are calibrated to role's optimization target |
| Skip the disqualifier check | A 16/19 with KILL-without-rationale is still 0 |
| Use 0-5 scoring instead of 0-3 | Adds noise without resolution |
| Score by intuition without citing the rubric | Inter-operator agreement collapses |
| Average per-contribution scores into "session score" without 7-dimension aggregate | The dimensions are different objects |
| Treat 90%+ as "good enough"; ignore why specific criteria scored low | The diagnostic value is in the breakdown |

---

## Composition with brennerbot

| Phase | Rubric activity |
|-------|-------------------|
| 3 | Score Hypothesis Generator deltas |
| 4 | Score Test Designer + Investigator deltas |
| 5 | Score Adversarial Critic deltas |
| 7 | Aggregate session-level 7-dimension score; emit grade |
| 9 | HANDBACK § Quality includes session grade |
| 10 | Trend analysis vs prior sessions; calibration update |

---

## Cross-references

- [OPERATOR-CALIBRATION-LOG.md](OPERATOR-CALIBRATION-LOG.md) — per-pane scoring trends
- [TRIBUNAL-AND-OBJECTION-REGISTER.md](TRIBUNAL-AND-OBJECTION-REGISTER.md) — adversarial critic gates
- [CITATION-PROVENANCE-RULES.md](CITATION-PROVENANCE-RULES.md) — anchor format rules
- [DELTA-PROTOCOL-FAIL-FAST.md](DELTA-PROTOCOL-FAIL-FAST.md) — JSON validity gate
- [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md](HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md) — KILL events scored against criterion 13
- [METRICS.md](METRICS.md) — session quality metrics
- /dp/brenner_bot/specs/evaluation_rubric_v0.1.md — rubric source
- /dp/brenner_bot/README.md § Scoring & Evaluation System — 7-dimension source
