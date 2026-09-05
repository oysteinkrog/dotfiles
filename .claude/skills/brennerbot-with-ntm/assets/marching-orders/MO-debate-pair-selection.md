# MO-debate-pair-selection.md — Operator's Phase 5 Pair Selection

**Phase:** 5 (operator-side preparation; not dispatched to a pane)
**Operators activated:** 🤝 GAN (pair-selection rule)
**Parameters:** `<SESSION_ID>`

---

This is an *operator-side* prompt, not a pane dispatch. You (the orchestrator) use this checklist before invoking `generate-debate-pairs.sh` to ensure Phase 5 pairs are well-structured.

---

**Step 1 — List active hypotheses post-Phase 4.**

```bash
br list --label=hypothesis --status=open --json | \
  jq '.issues[]? | {id, confidence: (((.description // "") | capture("confidence: (?<confidence>\\w+)")? | .confidence) // "?"), supports: (((.description // "") | capture("supports: \\[(?<supports>[^\\]]*)\\]")? | .supports) // "")}'
```

You should see:
- Several `confidence:high` and `confidence:medium` Hs (the strongest candidates)
- Possibly a few `confidence:low` or `confidence:speculative` (third-alternatives, anomaly-spawned)

**Step 2 — Apply pair-selection rules.**

For each active H, identify its strongest rival:

- **Direct rival:** if H_a's falsifier and H_b's expected_evidence overlap on a specific observable, they're direct rivals
- **Coordinate rival:** if H_a and H_b disagree under the encoding 𝓛 chose, they're coordinate rivals
- **Third-alternative pairing:** if H_c is `origin:third_alternative`, pair it against whichever of H_a / H_b is currently highest-confidence

Avoid:
- Pairing H_a against itself in different framings (level-split missed; should have been caught at Phase 3 triage)
- Pairing two Hs that already agree (no signal from debate)
- Pairing Hs with no overlapping falsifier/evidence (debate has no decisive outcome possible)

**Step 3 — Select model-family pairings.**

For each pair, identify which pane should champion which side. Apply 🤝 GAN discipline:

- Champion of H_a should be DIFFERENT model family from champion of H_b (when possible)
- The Investigator who's been working on H_a most often should champion it (continuity)
- If the Investigator is the same family as H_b's champion → swap to a different pane

If insufficient model family diversity (e.g., Solo or Pair tier with one family), record this in `phase0_scope_decision.md § triangulation_degraded` and proceed with what's available.

**Step 4 — Select Adjudicators.**

For each debate, the Adjudicator MUST be:

- A different pane from both champions
- A different model family from the dominant champion (when possible)
- Different from any Adjudicator who ruled the most recent debate (rotation rule)

Keep an Adjudicator-rotation log in `phase0_scope_decision.md § adjudicator_rotation`.

**Step 5 — Generate pairs JSON.**

Use `scripts/generate-debate-pairs.sh` to produce the structured pair list. Override its output if needed based on Steps 2-4.

**Step 6 — Dispatch.**

For each pair:

```bash
./scripts/dispatch-marching-order.sh MO-05a-cross-exam \
  --PANE_N=<champion-A-pane> --H_I=<H-NNN-A> --H_J=<H-NNN-B> --SESSION_ID=<session> --ROUND=1 \
  --target-pane=<champion-A-pane> --target-session=<ntm-session>

# AND for the opposing champion:
./scripts/dispatch-marching-order.sh MO-05a-cross-exam \
  --PANE_N=<champion-B-pane> --H_I=<H-NNN-B> --H_J=<H-NNN-A> --SESSION_ID=<session> --ROUND=1 \
  --target-pane=<champion-B-pane> --target-session=<ntm-session>
```

(Note both panes get champion-of-their-H framing; from each pane's perspective, "their" H is H_I.)

**Step 7 — Wait for round 1 posts; then dispatch round 2.**

Adjudicator only enters at the end (after round 3). Don't dispatch MO-05b prematurely.

---

**Anti-patterns:**

- ✗ Pair every H against every other H (N choose 2 explosion). For N=5, that's 10 debates — too much. Pair each H with its strongest rival only.
- ✗ Pair without considering model-family diversity. Defeats 🤝 GAN.
- ✗ Reuse same Adjudicator across debates without tracking the rotation log.
- ✗ Skip the third-alternative pairing. If a third-alternative H exists, it MUST debate against the strongest of the binary.

**Ship-or-Surface SLA:** within 15 min, post the pair list to RS-...-ADJUDICATE thread for transparency.
