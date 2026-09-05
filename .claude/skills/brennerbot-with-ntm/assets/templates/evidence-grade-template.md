# Evidence Grade Report — <ISO>

**Graded by:** <name | evidence-grader subagent>
**Workspace:** <path>
**EVs graded:** <count>
**Mode:** <update | report-only>

---

## Aggregate distribution

| Strength | Count | % of total |
|----------|-------|-----------|
| strong (W ≥ 0.7) | N | N% |
| moderate (0.4–0.7) | N | N% |
| weak (0.2–0.4) | N | N% |
| too-weak (< 0.2) | N | N% |

---

## Per-EV grades

### EV-NNN — <one-line description>

**W axes:**

| Axis | Value | Justification |
|------|-------|---------------|
| W_source | 0.NN | <reason> |
| W_verification | 0.NN | <reason> |
| W_independence | 0.NN | <reason> |
| W_recency | 0.NN | <reason> |
| W_domain_fit | 0.NN | <reason> |

**W_composite:** 0.NN (<strength>)

**Bottleneck axis:** <axis>

**Recommended action:** <specific MO + reason>

**Cited by hypothesis:** <list of H-NNN this EV supports/refutes/informs>

---

### EV-NNN — <next>

(repeat for each)

---

## Recommended priority for promotion

(Top 5 EVs whose strengthening would most increase load-bearing claim coverage. Score by: (target_W - current_W) × downstream_H_count × H_priority.)

| Rank | EV ID | Current W | Target W | Bottleneck | Action | Estimated effort |
|------|-------|-----------|----------|-----------|--------|------------------|
| 1 | EV-NNN | 0.NN | 0.NN | <axis> | <MO> | <hours> |
| 2 | ... | ... | ... | ... | ... | ... |

---

## Cross-EV patterns

### Pattern 1: <one-line>

(e.g., "Many EVs are W_verification=0.6 because they were initial pins not yet re-verified. Bulk dispatch MO-evidence-verify on next round.")

### Pattern 2: <one-line>

(e.g., "All EVs cite paywalled sources (W_source ≤ 0.4); corpus selection needs re-evaluation.")

### Pattern 3: <one-line>

(e.g., "Recency drops for EVs older than 6 months in our domain; consider quarterly re-check cadence.")

---

## Methodology calibration observations

(Optional: are W axes being applied consistently across this session?)

- <observation 1>
- <observation 2>

(For example: "Investigator p1 (cc) is consistently rating W_recency higher than Investigator p3 (gmi) for the same source class. Recalibrate via per-axis table re-read.")

---

## Hypothesis-level impact

(For each H, summary of supporting evidence W aggregate.)

| H ID | Supporting W sum | Refuting W sum | Confidence verdict | Note |
|------|-------------------|----------------|--------------------|------|
| H-NNN | N.N | N.N | high/medium/low | <one-line> |
| ... | ... | ... | ... | ... |

If verdict differs from current `confidence:` field, flag for MO-evidence-promote or MO-confidence-downgrade.

---

## Phase-7 audit feed

This grade report feeds Phase 7 audit. Audit panes should:

1. Verify each EV's stated W_composite matches the axes
2. Spot-check the bottleneck-axis identification
3. Confirm the recommended-action mapping is reasonable

If audit finds inconsistencies: file `audit-finding` severity:medium-high.

---

## Cross-references

- EVIDENCE-WEIGHTING-TAXONOMY.md (the W rubric)
- subagents/evidence-grader.md (the workflow)
- scripts/score-ev.sh (the recompute tool)
- MO-evidence-promote.md (the promotion procedure)
- MO-confidence-downgrade.md (the downgrade procedure)
