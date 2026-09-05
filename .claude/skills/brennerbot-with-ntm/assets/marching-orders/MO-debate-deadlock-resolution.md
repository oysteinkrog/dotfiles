# MO-debate-deadlock-resolution.md — When Adversarial Debate Doesn't Converge

**Phase:** 5 (debate)
**Operators activated:** ⊘ Level-Split, ⊕ Cross-Domain Import, 𝓛 Recode, ⊙ Productive-Ignorance
**Parameters:** `<DEBATE_BEAD_ID>`, `<H_PAIR>` (the two Hs in dispute), `<SESSION_ID>`

---

Sometimes a Phase 5 cross-examination debate doesn't converge: champions exchange evidence; neither flips H state; the debate continues past expected wall-time. This MO formalizes the deadlock-resolution procedure.

Without it, deadlocked debates burn budget and produce no decision.

---

**Step 1 — Detect deadlock.**

Deadlock indicators:
- Debate has gone ≥3 rounds with no H state change
- Both champions cite same EVs but interpret differently
- Adjudicator has refused to rule for ≥2 rounds
- Wall-time on this debate exceeds 1.5× tier estimate

If any indicators fire, this MO applies.

**Step 2 — Diagnose deadlock type.**

### D1: Genuine equipoise

Both Hs are equally well-supported by current evidence; neither dominates. Per CONFIDENCE-SCORING.md, both should be at `medium` confidence.

### D2: Interpretation disagreement

Both Hs reference same EVs but interpret W_domain_fit or W_recency differently. The disagreement is about weights, not facts.

### D3: Cross-level conflict

One H operates at level L1, the other at level L2 (per ⊘ Level-Split). The debate is comparing apples to oranges.

### D4: Missing evidence

Both Hs would have stronger support given EV that doesn't yet exist. Phase 4 reopen needed.

### D5: Unfalsifiable Hs

Neither H has a falsifier sharp enough to fire. Phase 1 framing was inadequate.

### D6: Adjudicator reluctance

Adjudicator (per F-501) is rubber-stamping rather than ruling. Replace adjudicator.

**Step 3 — Apply diagnosis-specific recovery.**

### D1 (genuine equipoise) recovery

Both Hs stay viable but unresolved: mark them `state: deferred` with `confidence: medium`. Document the equipoise in disagreement_register.md as a deliberate split. The HANDBACK explicitly notes "verdict is split — caller must pick based on additional context."

### D2 (interpretation disagreement) recovery

Force the champions to make their W axes explicit:

```
Champion A: "I weight EV-018 with W_domain_fit = 0.85"
Champion B: "I weight EV-018 with W_domain_fit = 0.5"
```

The Adjudicator is now choosing between the two W estimates, which is more tractable than choosing between Hs. This often unlocks the debate.

If champions can't articulate the W difference: the disagreement is rhetorical, not substantive (per F-503). One champion must produce specific evidence for their W estimate.

### D3 (cross-level) recovery

Per ⊘ Level-Split: both Hs may be correct at their respective levels. The debate isn't about which is right; it's about which level is operational for our question.

Reframe: "Under regime R, which level applies?" → both Hs may apply under different sub-regimes. Document via ⊘ split.

If genuinely competing at the same level: continue debate with sharper falsifier per H.

### D4 (missing evidence) recovery

Pause the debate. Dispatch:

```
MO-04a-investigate.md with specific target: "Find evidence that distinguishes the two hypotheses in <H_PAIR> under regime R, by [specific date]."
```

After Phase 4 reopens, return to the debate with new evidence.

### D5 (unfalsifiable) recovery

Run `subagents/falsifier-grader.md` on both Hs:

If both grade Poor: return to Phase 1 framing. The question may need refining.

If one grades Poor, the other Acceptable: advance the better-falsifier H; mark the weaker as `state: deferred`.

### D6 (adjudicator reluctance) recovery

Per F-501: rotate adjudicator. The new adjudicator is from a third family (not either champion's family).

If three consecutive adjudicators all rubber-stamp: the debate genuinely has no clear winner; treat as D1 (equipoise).

**Step 4 — Document the resolution.**

```bash
debate_id="<DEBATE_BEAD_ID>"
br update "$debate_id" --description="$(br show "$debate_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""' \
    | awk '1; END { print "## Deadlock resolution"; print "- type: <D1-D6>"; print "- recovery: <action taken>"; print "- outcome: <H state changes>"; print "- timestamp: <TIMESTAMP_UTC>"; }')"
```

**Step 5 — Phase 7 audit check.**

Phase 7 audit verifies:
- Was the deadlock genuinely resolved, or just papered over?
- Did the methodology fix the structural issue (e.g., insufficient framing in D5)?
- Are there cross-session lessons (per Phase 10)?

**Step 6 — Phase 10 lesson candidate.**

If the deadlock revealed a methodology gap, file as Phase 10 lesson:

- D1 (genuine equipoise) is fine; not a gap
- D2 should have been caught earlier (improve W discipline)
- D3 should have been caught at Phase 3 (improve ⊘ application)
- D4 should have been caught in Phase 4 round 1 (improve falsifier targeting)
- D5 should have been caught in Phase 1 (improve framing)
- D6 is operational (improve adjudicator selection)

---

**Anti-patterns:**

- ✗ Continue deadlocked debate beyond budget without diagnosis
- ✗ Pick a winner arbitrarily to "make a decision"
- ✗ Average the two Hs (anti-Brenner; F-601)
- ✗ Defer all open debates to Phase 7 (audit isn't a debate-resolver)
- ✗ Skip the diagnosis step (apply random recovery)
- ✗ Resolve deadlock without documenting

**Ship-or-Surface SLA:** within 60 min from deadlock detection, diagnosis + recovery applied + outcome documented.

---

## Wall-time consideration

Deadlocks are cost-intensive. For T2-T3 sessions, hard-cap deadlock resolution at 60 min; if not resolved, mark as D1 (equipoise) and move to Phase 6 with caveat.

For T4+ sessions, deadlock resolution can take longer; budget more.

---

## Composition with other patterns

- Per OC-016 (OPERATOR-CARDS.md): force evidence-grounded adjudication
- Per F-501: adjudicator rotation rule
- Per F-503: rhetoric-vs-evidence test
- Per /multi-model-triangulation: third-family adjudicator
- Per CRITIQUE-CRAFT.md: severity calibration

---

## Cross-references

- ROSTER-PLANS.md (adjudicator rotation rules)
- FAILURE-TABLE.md (F-501, F-503)
- subagents/falsifier-grader.md (per D5 recovery)
- OPERATOR-CARDS.md OC-014 + OC-015 (cross-family rules)
- BRENNER-GAN-MECHANICS.md (deadlock as GAN convergence failure)
