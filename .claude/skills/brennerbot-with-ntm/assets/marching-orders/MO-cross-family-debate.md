# MO-cross-family-debate.md — Force Cross-Family Adversarial Probing

**Phase:** 4 (rescue from F-403 confirmation bias) or 5 (debate setup)
**Operators activated:** 🤝 GAN, ✂ Exclusion-Test
**Parameters:** `<H_ID>`, `<CHAMPION_PANE>`, `<CHAMPION_FAMILY>`, `<CHALLENGER_PANE>`, `<CHALLENGER_FAMILY>`, `<SESSION_ID>`

---

When a hypothesis has been investigated only by one model family AND has only supporting EVs, the standard Devil's-Advocate may not surface real counter-evidence (per F-501 anti-pattern). This MO forces a *different family* to probe.

Per Brenner-Crick GAN discipline (per Gemini distillation §4.1) — the discriminator must be cognitively distinct from the generator.

---

**Step 1 — Verify family difference.**

The challenger pane must be from `<CHALLENGER_FAMILY>` (different from `<CHAMPION_FAMILY>`).

If both panes are same family (e.g., due to gmi unavailability), abort and document in `phase0_scope_decision.md § triangulation_degraded`.

**Step 2 — Brief the challenger.**

Dispatch to challenger pane:

```text
You are pane <CHALLENGER_PANE> (model family <CHALLENGER_FAMILY>). Your task: probe <H_ID> with cross-family adversarial framing.

H-target: <H_ID>
Champion: <CHAMPION_PANE> (model family <CHAMPION_FAMILY>)
Champion's evidence pack: evidence/packs/EV-pack-<H_ID>.md
Champion's confidence: <confidence>

Cross-family discipline:
1. Read EV-pack-<H_ID>.md noting *what evidence types* the champion gathered
2. Identify systematic blind spots in those evidence types (e.g., "champion only cited papers; missed code repos that contradict")
3. Apply your family's distinctive lens:
   - cc strength: careful citation reading; spot misinterpretation
   - cod strength: broad pattern matching; spot domain analogues
   - gmi strength: formal/mathematical framing; spot scale-physics issues

4. File ≥1 critique (`C-*` bead) with:
   - severity calibrated per CRITIQUE-CRAFT.md
   - evidence_to_confirm field non-empty
   - your family's distinctive framing surfaced

5. If you find counter-evidence, file as `EV-*.refutes:[<H_ID>]`

6. Post to `<SESSION_ID>-<H_ID>` thread:

   Subject: [<SESSION_ID>-<H_ID>] Cross-family probe by <CHALLENGER_FAMILY>
   Body:
     Champion family: <CHAMPION_FAMILY>
     Challenger family: <CHALLENGER_FAMILY>
     Cross-family blind spots identified: <list>
     Critiques filed: <C-NNN, ...>
     Counter-evidence filed: <EV-NNN, ...> (or "none found")
     Verdict: <H stands stronger | H weakens | H falsifier fired>

This is NOT just standard devil's-advocate — it's specifically a cross-family probe.
The value comes from the family difference, not from generic adversarial framing.
```

**Step 3 — Wait for challenger output.**

Operator monitors via `tick.sh`. Expected wall time: 30-45 min.

**Step 4 — Adjudicator review.**

The adjudicator (per OC-015 in OPERATOR-CARDS.md, must be a third family) reads:

- Champion's evidence pack
- Challenger's critiques
- Compares: did the cross-family probe surface anything the same-family probe would have missed?

**Step 5 — Document the cross-family contribution.**

In `phase0_scope_decision.md § cross_family_debates`:

```yaml
- h: <H_ID>
  champion_family: <CHAMPION_FAMILY>
  challenger_family: <CHALLENGER_FAMILY>
  surfaced_findings: <list of distinct findings vs same-family probe>
  cross_family_value_score: <high | medium | low>
```

If cross_family_value_score is consistently low, the cross-family probe isn't paying off — possibly because the challenger family has the same blind spot. Phase 10 lesson candidate.

---

**Anti-patterns:**

- ✗ Use this MO when both panes are same family (defeats purpose)
- ✗ Skip the family-distinctive lens step (challenger acts like generic devil's-advocate)
- ✗ Treat cross-family critique as automatically more valid (it's still evidence-grounded; quality matters)
- ✗ Skip the adjudicator review (cross-family findings need cross-family verification)

**Ship-or-Surface SLA:** within 45 min, challenger files critiques + posts to thread.
