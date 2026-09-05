# MO-confidence-downgrade.md — Formal Procedure to Downgrade an H's Confidence

**Phase:** 4 (per-round) or 7 (audit)
**Operators activated:** ✂ Exclusion-Test, † Theory-Kill (partial)
**Parameters:** `<H_ID>`, `<DOWNGRADE_REASON>`, `<NEW_CONFIDENCE>`, `<SESSION_ID>`

---

Per CONFIDENCE-SCORING.md and EVIDENCE-WEIGHTING-TAXONOMY.md, an H's confidence is computed from supporting + refuting evidence weights. If new evidence (or recalibrated weights) reduces the support, the H's confidence should be downgraded explicitly — not silently.

This MO is the procedure for downgrading without losing audit trail.

---

**Step 1 — Identify the trigger.**

A confidence downgrade is triggered by:

- New refuting EV with significant W_composite (e.g., ≥0.5)
- Existing supporting EV's W reduced (e.g., source retraction, regime mismatch surfaced)
- Independent verification fails for a previously-verified EV
- Phase 7 audit catches a load-bearing assumption that's wrong
- Cross-session reconciliation reveals a flawed earlier conclusion
- Falsifier softening detected (per F-303)

For each trigger, document specifically what changed.

**Step 2 — Compute new W aggregate.**

```bash
# Re-compute support_score and refute_score after the trigger event:
support_score = sum(W_supporting_i)  # using updated W_composite values
refute_score  = sum(W_refuting_i)
```

Per CONFIDENCE-SCORING.md:
- support_score / refute_score ratio determines confidence

If the ratio drops:
- ≥2× → confirmed
- ≥1× → active / medium confidence
- <1× → refuted

**Step 3 — Compare current to target.**

```
Current confidence: <high/medium/low>
Computed: <high/medium/low>
Drop: <Y/N>
Magnitude: <delta in ratio>
```

If drop is real, proceed to downgrade.

**Step 4 — File downgrade event.**

Update the H bead:

```bash
h_ref="<H_ID>"
h_id="$(br list --all --json | jq -r --arg ref "$h_ref" '.issues[]? | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":"))) | .id' | head -1)"
[ -n "$h_id" ] || { echo "No bead found for public ref: $h_ref" >&2; exit 1; }
br update "$h_id" --description="$(br show "$h_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""' \
    | sed -E 's/confidence: <old>/confidence: <new>/' \
    | awk '1; END { print "## Confidence history"; print "- <TIMESTAMP_UTC>: downgraded from <old> to <new>; reason: <DOWNGRADE_REASON>; trigger: <specific>"; }')"
```

**Step 5 — Cascade impact.**

If the downgraded H was load-bearing for the session's verdict:

- Update HANDBACK to reflect new confidence
- May require Phase 4 reopen (if downgrade significant enough)
- May require Phase 5 re-adjudication (if H state changes)

If the downgraded H was a contributing factor (incident-investigation mode):
- Update post-mortem report
- Re-rank contributing factors

If the downgraded H informed downstream Hs (per related_h links):
- Notify those Hs' Investigators
- Re-evaluate their state given the changed parent

**Step 6 — Adjudicator review (T3+).**

For T3+ sessions, the downgrade requires adjudicator review:

- Was the trigger event real (specific evidence)?
- Was the W re-computation correct?
- Is the new confidence appropriate?

If adjudicator disagrees: the downgrade is contested; file as DEBATE-* bead per Phase 5 protocol.

**Step 7 — Cross-session impact.**

If this H was cited in prior sessions (per /cass + /flywheel):

- Document in `analyses/cross-session-impact.md`
- For prior verdicts that depended on the now-downgraded H: file RECONCILIATION-MEMO per RECONCILIATION-OF-PRIOR-SESSIONS.md
- Update CROSS-SESSION-DRIFT-CATALOG.md

**Step 8 — Phase 10 lesson candidate.**

If the downgrade reveals a methodology gap (e.g., we should have caught this earlier), file as Phase 10 lesson:

```yaml
# In deliverables/DRIFT-CHECK.md
lessons:
  - id: L-NNN
    description: <one-line>
    methodology_gap: <which Phase / operator / failure mode>
    recommendation: <update to references/ or to validators>
```

---

**Anti-patterns:**

- ✗ Silently lower W without filing downgrade event
- ✗ Skip cascade impact analysis (downstream Hs become silently inconsistent)
- ✗ Skip adjudicator review (operator self-downgrade = unaccountable)
- ✗ Apply across all Hs in batch without per-H justification
- ✗ Use as a way to "make the verdict softer" rather than honest evidence-grounded change

**Ship-or-Surface SLA:** within 30-60 min per H (depends on cascade depth).

---

## Anti-pattern: confidence laundering

A common anti-Brenner move: reduce confidence on a high-stakes claim by *removing* unfavorable EVs (not adding refuting EVs). This is rationalization, not honest downgrade.

Per ANTI-PATTERNS.md: confidence updates must be *additive* — new evidence weighted, then composite W recomputed. Never delete supporting EVs to "rebalance".

---

## Per-mode considerations

### Mode: incident-investigation

Confidence downgrades during incident-investigation may indicate:
- Original triage was wrong (file as Phase 10 lesson)
- New evidence surfaced after triage (legitimate downgrade)

Document specifically.

### Mode: post-mortem-formalization

Common during post-mortem: initial 5-whys layer is downgraded as deeper investigation finds different causes. This is expected; document via standard procedure.

### Mode: living-review

Per-tick downgrades suggest the question's domain is volatile. Per LIVING-DOCUMENTATION-PATTERNS.md, increase tick cadence if downgrades are frequent.

---

## Cross-references

- CONFIDENCE-SCORING.md (the rubric)
- EVIDENCE-WEIGHTING-TAXONOMY.md (W axes and composite)
- MO-evidence-promote.md (the inverse operation)
- ANTI-PATTERNS.md (confidence laundering anti-pattern)
- RECONCILIATION-OF-PRIOR-SESSIONS.md (cross-session impact)
- CROSS-SESSION-LEARNING.md (lesson commitment)
