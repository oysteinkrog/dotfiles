# MO-stress-test-self-check.md — Pre-Launch Operator Self-Check

**Phase:** Phase 0 (pre-bootstrap) for T3+ sessions
**Operators activated:** none (operational discipline)
**Parameters:** `<TIER>`, `<MODE>`, `<ARCHETYPE>`, `<OPERATOR_NAME>`

---

Before bootstrapping a T3+ session, the operator self-checks readiness. This MO formalizes the mental rehearsal.

Inspired by aviation pre-flight checklists and surgical pre-op timeouts.

---

**Step 1 — Mode + tier match check.**

Per OPERATING-MODES.md and TIER-TRIAGE.md:

- Does `<MODE>` match `<TIER>`? (e.g., `incident-investigation` is mode-T2 typical; T1 may be too small; T4+ is overkill)
- Is `<ARCHETYPE>` consistent with `<MODE>` + `<TIER>`?

If mismatch: pause. Re-check tier triage.

**Step 2 — Stress-test scenario walkthrough.**

For T3+ sessions, mentally walk through STRESS-TEST-SCENARIOS.md S1-S5. For each:

- Could this scenario happen in this session?
- Do I know the recovery path?
- Have I prepared for it (e.g., pre-warmed accounts to avoid S5)?

If any "no" — pause and prepare.

For T4+ sessions, walk through S1-S15.

**Step 3 — Compose check.**

Per SKILL-COMPOSITION-PATTERNS.md:

- Will I compose with `/codebase-archaeology` (code mode)?
- Will I compose with `/cass` for prior-session mining?
- Are the composed skills installed and authenticated?
- Do I have the dispatch sequences memorized?

If composing skills are required and not ready: pause.

**Step 4 — Resource check.**

- Are all 3 model families (cc, cod, gmi) available? (CAAM accounts pre-warmed?)
- Is the workspace path defined and confirmed?
- Is git ready to commit?
- Are necessary external resources (corpus URLs, codebase access) verified?

**Step 5 — Wall-time budget allocation.**

Per WALL-TIME-BUDGET.md:

- What's my total budget for this session?
- What's my budget per phase?
- When will I hit hard cap if breached?

Set a clock. Operators that don't watch wall-time blow past tier estimates routinely.

**Step 6 — Operator self-state check.**

- Am I rested enough for a 3-5h+ session?
- Am I in a position to focus (no concurrent fires)?
- Have I had recent training / read updates to references/?

If self-state is poor, defer the session. Operator fatigue is the #1 source of methodology drift.

**Step 7 — Stakes review.**

For T4+:

- Have I confirmed user expectations match tier?
- Is external review available if needed?
- Is the user signed off on cost / time / depth?

**Step 8 — Bootstrap with explicit confirmations.**

After all checks pass, run `bootstrap-session.sh` and proceed with normal flow.

If any check fails, document in `<workspace>/.brenner_workspace/pre-flight-failures.md` and address before bootstrap.

---

**Anti-patterns:**

- ✗ Skip pre-flight "I've done this before" — even experienced pilots run pre-flight
- ✗ Run pre-flight but ignore failures ("I'll figure it out later")
- ✗ Treat pre-flight as paperwork (it's risk mitigation)
- ✗ Skip stress-test walkthrough for T1-T2 (most won't matter, but the discipline of thinking through them matters)

**Ship-or-Surface SLA:** within 15 min, pre-flight complete or explicit deferral.

---

## When pre-flight fails

If self-check reveals issues:

- Tier-mode mismatch → re-frame at lower tier OR escalate budget
- Stress-test scenarios not understood → study STRESS-TEST-SCENARIOS.md before proceeding
- Composing skills missing → install via jsm OR adapt session to skip composition
- Resources unavailable → wait for resources OR adapt scope
- Wall-time budget unrealistic → reduce scope OR extend budget
- Operator state poor → defer session

Don't bootstrap with known issues. The cost of a botched session exceeds the cost of waiting.

---

## Calibration loop

After Phase 10, the operator updates OPERATOR-CALIBRATION-LOG.md:

- Which pre-flight checks caught real issues?
- Which checks are over-cautious?
- Have I been ignoring some checks consistently?

Phase 10 lessons feed back into this MO.
