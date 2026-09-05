# decision-memo-writer Subagent

**Role:** Phase 9 in archetype A7 (decision under uncertainty) — produce `deliverables/DECISION-MEMO.md`.

**Reads:** all artifacts (intake, beads, distillations, deliverables).

**Writes:** `deliverables/DECISION-MEMO.md`.

**Operators favored:** ≡ Invariant-Extract; ⊘ Level-Split (technical-vs-values split).

---

## Procedure

**Step 1 — Run the renderer script.**

```bash
./scripts/render-decision-memo.sh --workspace=<WORKSPACE>
```

This produces a skeleton `deliverables/DECISION-MEMO.md` with `<FILL IN>` markers.

**Step 2 — Fill in narrative sections.**

Per `assets/templates/decision-memo-template.md` (if not already filled by the script):

- **Reasoning** (1-2 paragraphs): why the recommendation; cite ≥3 EV-NNN
- **What would change the recommendation** (the decision-rule falsifier): list ≥3 specific observations
- **Risk register**: 3 risks with mitigations
- **Reversibility analysis**: explicit recovery plan if wrong
- **Confidence**: per CONFIDENCE-SCORING.md tags

**Step 3 — Surface dissent.**

Read `distillations/disagreement_register.md`. Any unresolved D-NNN entry that bears on the decision MUST appear in the "Dissenting opinions" section verbatim. Per Talmudic discipline (per EXEMPLARS.md): record minority opinions even when meta-synthesis chose one.

**Step 4 — Apply confidence calibration.**

For T3+ sessions: cross-reference OPERATOR-CALIBRATION-LOG.md if available. If the operator's historical `high-confidence` Hs survive next-session at <80%, downgrade this memo's confidence by one level.

**Step 5 — Verify no F-### codes apply.**

- F-901 (>1 page): decision memo CAN be longer than HANDBACK; up to 3 pages OK for T3+, 5 pages for T4+
- F-902 (open thread tags): every open H/AF must have next-action
- F-903 (no recommendation): the decision memo IS the recommendation; if uncertain, recommend `defer with information request`

**Step 6 — Operator review gate.**

Decision memos at T3+ require operator + user sign-off before acting. The memo includes a sign-off section:

```markdown
## Operator sign-off

- [ ] Memo reviewed
- [ ] Confidence calibration applied
- [ ] Dissent surfaced
- [ ] Reversibility verified
- [ ] Ready to act

Operator: <name>
Date: <ISO>
```

The user counter-signs separately.

---

**Anti-patterns:**

- ✗ Hedging in recommendation ("we think maybe") — pick a verdict; caveats separate
- ✗ Suppressing dissent because "meta-synthesis chose" — Talmudic preservation
- ✗ No reversibility analysis — biggest source of bad decisions
- ✗ No sign-off section — accountability is operator's last guard
- ✗ Skipping confidence calibration — over-confidence compounds across sessions

**Ship-or-Surface SLA:** within 60 min, memo drafted + ready for operator review.
