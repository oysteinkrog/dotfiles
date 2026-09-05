# Calibration Report — <Operator>

**Reviewer:** <name | calibration-coach subagent>
**Period covered:** <start-ISO> through <end-ISO>
**Sessions reviewed:** <count>

---

## Summary

<2-3 sentence overall calibration assessment>

---

## Per-session calibration metrics

| Session ID | Tier | Confidence:high count | Confirmed:high accurate? | Audit downgrades | Falsifier-firing rate |
|------------|------|----------------------|--------------------------|-------------------|----------------------|
| RS-... | T<N> | N | <yes/partial/no> | N | N% |
| ... | ... | ... | ... | ... | ... |

---

## Drift pattern detected

**Primary pattern:** <D-Cal-1 (overconfidence) | D-Cal-2 (underconfidence) | D-Cal-3 (slow recalibration) | D-Cal-4 (inconsistent W) | D-Cal-5 (confirmation bias residue) | none>

**Pattern description:**

<one paragraph: what specifically is drifting>

**Frequency:** <how often this pattern fires; out of how many opportunities>

---

## Specific examples

### Example 1: <session ID> — <one-line summary>

- Bead: H-NNN: "<title>"
- Operator's confidence claim: <high | medium | low>
- W_composite at the time: <value>
- Subsequent outcome: <refuted at Phase 7 | confirmed at Phase 7 | reconciled later>
- Drift type: <D-Cal-N>
- Specific lesson: <one-line>

### Example 2: <session ID> — <one-line summary>

(repeat as needed)

---

## Calibration exercises

### Exercise 1: <one-line>

- **Goal:** <what the operator should learn>
- **Procedure:** <steps>
- **Expected duration:** <time>
- **Reference:** <which references/ file to re-read>

### Exercise 2: <one-line>

(repeat)

---

## Re-coaching cadence

- Next review: <ISO>
- Frequency: <weekly | bi-weekly | monthly>
- Duration: <ongoing | until specific metric is met>

---

## Improvement criteria

You'll know calibration is improved when:

- <specific measurable metric 1>
- <specific measurable metric 2>
- <specific measurable metric 3>

---

## Buddy review recommendation

For severe drift (D-Cal-1 with frequency >30%, or D-Cal-5 detected): recommend buddy review of next N sessions.

- [ ] Buddy assigned: <name>
- [ ] Sessions to review: N
- [ ] Buddy review report due: <ISO>

For moderate drift: optional buddy review.

For no drift: no buddy review needed.

---

## Cross-session impact

(Optional: did this drift affect any high-stakes verdicts? If yes, list and recommend reconciliation per RECONCILIATION-OF-PRIOR-SESSIONS.md.)

- <session ID>: <impact assessment>

---

## Methodology lessons

(If this calibration drift surfaces a methodology gap rather than just operator-specific drift, file as Phase 10 lesson candidate.)

- <lesson 1>
- <lesson 2>

---

## Sign-off

- [ ] Operator has read this report
- [ ] Operator has scheduled the recommended exercises
- [ ] Operator has shared with buddy (if applicable)
- [ ] OPERATOR-CALIBRATION-LOG.md updated with this review's date

---

## Cross-references

- OPERATOR-CALIBRATION-LOG.md (the running log)
- EVIDENCE-WEIGHTING-TAXONOMY.md (W axes)
- CONFIDENCE-SCORING.md (the rubric)
- OPERATOR-ONBOARDING-CURRICULUM.md (buddy system)
- subagents/calibration-coach.md (the coaching workflow)
