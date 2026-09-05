# MO-incident-compressed.md — Single-Pane Compressed Incident Investigation

**Mode:** incident-investigation (per OPERATING-MODES.md)
**Phase:** all (compressed; runs Phase 1+3+5-with-inline-investigation+7 only)
**Wall time:** ≤60 min
**Operators activated:** ⌂ Materialize (tight), ✂ Exclusion-Test (tight), 🤝 GAN compressed
**Parameters:** `<INCIDENT_DESCRIPTION>` (1-paragraph), `<TIME_BUDGET_MINUTES>` (default 60), `<SESSION_ID>`

---

You are the lead investigator for an incident under time pressure. Standard 10-phase loop is compressed into four phase flags; Phase 4 investigation happens inline inside the Phase 5 adjudication loop, and methodology distillation is skipped. The deliverable is `INCIDENT-VERDICT.md`, not the full HANDBACK + DRIFT.

This MO is dispatched in incident-investigation mode (Pair tier roster). You operate as both Investigator and Devil's-Advocate of yourself, with a paired devil's-advocate pane providing live counter-evidence.

---

**Step 1 (≤5 min) — Compressed Phase 1: framing.**

Read `<INCIDENT_DESCRIPTION>`. Frame in 5 lines:

```markdown
## Question
What is the root cause of <INCIDENT_DESCRIPTION>?

## Falsifier
If observation O is found in available logs/dashboards/metrics within 30 min of search, the candidate cause C is either confirmed (O matches) or refuted (O missing).

## Scope
- Time window: <14:00-14:23 UTC | etc>
- Affected: <which services / customers / systems>
- Logs/dashboards available: <list>

## Out of scope
- Long-term post-mortem (separate session, separate mode)
- Customer communication (separate workstream)
```

Save to `intake/question_of_record.md`. File `Q-001` bead.

**Step 2 (≤10 min) — Compressed Phase 3: hypotheses.**

Brainstorm 2-4 candidate root causes. MUST include:

- Most likely cause (based on prior incidents / standard patterns for this system)
- Second-most likely cause (different mechanism)
- Third alternative ("both could be wrong; the real cause is Z" — per Brenner §103)
- Optional 4th: user/operator error (often dismissed prematurely)

Each H gets a `falsifier:` answerable from immediately observable logs.

File 3-4 `H-*` beads.

**Step 3 (≤30 min) — Compressed Phase 4 (inline with Phase 5): probe each H.**

Work through hypotheses in parallel with the devil's-advocate pane:

For each H:

- Run the falsifier check (specific log query / dashboard view / metric inspection)
- File `EV-*` with verbatim log line / metric reading
- Mark H state immediately:
  - Falsifier fired → `state: refuted` with `refuted_by: <EV-NNN>`
  - Expected evidence found → `state: confirmed` (preliminary)
  - Inconclusive → `state: active` (continue)

Devil's-advocate pane (paired) probes confirmed Hs for counter-evidence. If counter-evidence found, demote to active or refuted.

Real-time updates in `RS-...-H-NNN` threads.

**Step 4 (≤10 min) — Compressed Phase 7: fresh-eyes audit.**

For the surviving confirmed H, ask:

1. Could the cited EV be misread? (re-verify the log line literally)
2. Is the falsifier actually decidable from current observable state? (per ✂ discipline)
3. Did we test alternatives sufficiently before confirming this one? (apply ∿ Dephase: are we just inheriting the standard pattern?)

If any answer is "no", demote to `state: active` and continue investigating.

If all clean, the H stands as the verdict.

**Step 5 (≤5 min) — Write INCIDENT-VERDICT.md.**

```markdown
# Incident Verdict — <SESSION_ID>

**Incident:** <INCIDENT_DESCRIPTION>
**Time window:** <window>
**Investigation duration:** ~<minutes> min
**Confidence:** <high | medium | low>

## Verdict

**Root cause:** <one sentence>

## Evidence

- **Confirmed via:**
  - EV-NNN: <verbatim log line / metric reading> (source: <log path>:line<N>)
  - EV-NNN: <...>

- **Killed alternatives:**
  - H-NNN: <claim> — refuted by EV-NNN (verbatim: "<quote>")
  - H-NNN: <claim> — refuted by EV-NNN

## Causal chain

1. <step 1: trigger>
2. <step 2: propagation>
3. <step 3: customer impact>

## Recommended remediation

**Immediate (within 1h):** <action>
**Short-term (within 24h):** <action>
**Long-term (post-mortem):** <action>

## Open questions deferred to post-mortem

- <question 1>
- <question 2>

## Verifier

This verdict produced by brennerbot incident-investigation mode in ~<minutes> min. For deeper post-mortem (5-whys, contributing factors, action items), run a `post-mortem-formalization` mode session within 24h.

---

**Operator:** <operator name>
**Timestamp:** <ISO-8601>
```

**Step 6 — Commit and ship.**

```bash
br sync --flush-only
git add deliverables/INCIDENT-VERDICT.md evidence/ .beads/ .brenner_workspace/
git status
git commit -m "Incident verdict: <one-line root cause>"
```

Mark `phase_1_complete.flag`, `phase_3_complete.flag`, `phase_5_complete.flag`, `phase_7_complete.flag`. Note: Phase 2/4/6/8/9/10 deliberately not marked complete (they were skipped/compressed-inline per incident mode).

Send to user:

```
Incident verdict: <one-sentence>
Confidence: <level>
Full report: deliverables/INCIDENT-VERDICT.md
Recommended remediation: <list>
Post-mortem-formalization session recommended within 24h.
```

---

**Anti-patterns:**

- ✗ Skip the third alternative (per Brenner §103) — incidents often have a third-cause story
- ✗ Confirm an H without trying to fire its falsifier
- ✗ Skip Phase 7 because "we're under time pressure" — Phase 7 is the difference between "verdict" and "guess"
- ✗ Pad the verdict with hedging — be definite; provide caveats separately
- ✗ Skip recommended remediation — the verdict's value is the action it enables
- ✗ Skip post-mortem-formalization recommendation — incident response is incomplete without it

**Ship-or-Surface SLA:** ≤60 min total. If at 50 min you don't have a confirmed verdict, escalate to user: "I have N candidate causes still open; do you want to extend, accept partial, or reframe?"
