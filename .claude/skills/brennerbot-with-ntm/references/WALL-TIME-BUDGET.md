# WALL-TIME-BUDGET.md — Per-Phase, Per-Tier Time Discipline

<!-- TOC: Why budgets matter | Per-tier total budgets | Per-phase splits | Adjustments | Budget breach protocol -->

Mirrors saas-billing's wall-time discipline embedded in OPERATING-MODES.md. This file makes the budgets explicit — when the operator should pause and decide.

---

## Why wall-time budgets matter

A swarm without a wall-time budget runs forever in marginal-improvement mode. The user paid for X hours of compute; we owe a result, not endless polish.

Per Brenner's "evidence per week" objective function (per KERNEL.md): the value of an experiment is `(EIG × downstream_leverage) / (time × cost × ambiguity × infrastructure)`. Time is in the denominator. Honoring the budget IS the methodology.

---

## Per-tier total budgets

| Tier | Total budget | Hard cap (escalate beyond this) |
|------|--------------|----------------------------------|
| T1 (Curiosity) | 60 min | 90 min |
| T2 (Decision-supporting) | 3h | 5h |
| T3 (Strategic) | 5h | 8h |
| T4 (High-stakes) | full day (~8h) | 16h (multi-day) |
| T5 (Existential) | days (multi-session) | weeks (escalate review) |

Budgets are total *active* wall time. If the swarm runs unattended overnight while the operator sleeps, that's not active time.

---

## Per-phase splits (% of total budget)

These are starting points; can be adjusted with operator judgment.

| Phase | T1 | T2 | T3 | T4 | T5 |
|-------|----|----|----|----|----|
| 1 (framing) | 10% | 5% | 5% | 5% | 5% |
| 2 (bootstrap) | n/a (Solo) | 5% | 3% | 3% | 2% |
| 3 (propose+triage) | 15% | 10% | 8% | 7% | 5% |
| 4 (investigation) | 50% | 40% | 40% | 35% | 35% |
| 5 (debate) | 0% (inline) | 15% | 17% | 17% | 17% |
| 6 (distill) | 5% | 10% | 12% | 13% | 13% |
| 7 (audit) | 10% | 10% | 10% | 13% | 16% |
| 8 (freeze) | 5% | 3% | 3% | 3% | 3% |
| 9 (handback) | 5% | 2% | 2% | 2% | 2% |
| 10 (drift) | 0% (skip) | optional | mandatory | mandatory | mandatory |

For T1 (60 min): Phase 4 = 30 min; for T3 (5h): Phase 4 = 2h; for T4 (8h): Phase 4 = ~2.8h.

---

## Per-phase concrete budgets (T2 example, 3h total)

| Phase | Budget | Activity |
|-------|--------|----------|
| 1 | 9 min | Frame question; ingest minimal corpus |
| 2 | 9 min | Spawn Pair; onboarding ack |
| 3 | 18 min | 3 Hs; triage |
| 4 (rounds × 3) | 72 min | 3 × 24-min rounds |
| 5 | 27 min | Up to 2 debates × 13min |
| 6 | 18 min | Per-family + meta |
| 7 | 18 min | 2 trio-rounds × 9min |
| 8 | 5 min | Freeze |
| 9 | 4 min | HANDBACK |
| Total | 180 min (3h) | |

Phase 10 deferred (T2 default).

---

## Adjustments

### Adjustments by mode

- `incident-investigation`: compressed budgets (per OPERATING-MODES.md: 60 min total)
- `methodology-drift-check`: only Phase 10 (~30-60 min)
- `resume-session`: depends on `mode_to_resume` — typically 1-3h
- `living-review`: per-iteration budget ≤30 min; full re-pass quarterly

### Adjustments by archetype

- A1 design-space: more Phase 4, less Phase 6 (workload-conditional answers don't need exhaustive distillation)
- A2 codebase: more Phase 1 (archaeology), more Phase 4 (file-level investigation)
- A3 methodology: more Phase 6 (the synthesis IS the deliverable)
- A6 adversarial: more Phase 4 (devil's-advocate-heavy), more Phase 7 (red-team)
- A7 decision: more Phase 3 (decision-rule framing critical)

### Adjustments by complexity overlay

Each present overlay adds ~20% budget:
- Multi-stakeholder
- Time-sensitive
- Adversarial
- Multi-domain
- Source-volatile
- Reversibility-asymmetric
- Novelty
- Verification expensive

A T3 question with 2 overlays = T3 budget × 1.4 ≈ 7h instead of 5h.

---

## Budget breach protocol

When a phase exceeds its budget:

### Soft breach (≤30% over)

1. The operator notes the breach in `session-logs/round-N.md`
2. Continue but accelerate — drop optional sub-steps
3. Phase 10 lesson if pattern repeats: "Phase X consistently runs N% over"

### Hard breach (>50% over OR per-tier hard cap exceeded)

1. PAUSE. The swarm shouldn't keep running while the operator is uncertain.
2. Decide: escalate tier (with user notification), accept incomplete (truncate the phase), or reframe (back to Phase 1).
3. Document the decision in `phase0_scope_decision.md § budget_breaches:`
4. Phase 10 drift-check examines: was the breach justified?

### Tier-cap breach (any tier, beyond hard cap)

This is a serious signal. Don't keep going. Either:

- The question is genuinely larger than the tier indicated → escalate (re-tier with user)
- The methodology is producing low yield → reframe or abort
- Operator burnout / context saturation → break / handoff

Continuing past the tier-cap is anti-Brenner — at this point, the rounds are producing prose, not knowledge.

---

## Sub-budget discipline (Phase 4 rounds)

Phase 4 has multiple rounds within its phase budget. Per round:

- T1: 1 round × full Phase 4 budget (~30 min)
- T2: 3 rounds × 24 min
- T3: 4 rounds × 30 min
- T4: 6 rounds × 1h
- T5: 6 rounds × 2h

Each round must end with `convergence-check.sh --phase=4`. If kill_rate < add_rate AND no rounds remaining in budget → escalate.

---

## Wall-time anti-patterns

| ✗ | Why |
|---|-----|
| No budget set; "we'll see how long it takes" | Open-ended runs always overrun; the user paid for X but got 3X |
| Budget set but never measured | Blame "compute speed" or "complexity" without per-phase data |
| Budget breach silently extends | The user's expectation of cost was X; they got 2X; they didn't authorize it |
| Padding budget upward "to be safe" | T3 budget at T4 levels is wasteful; methodology should match question |
| Skipping Phase 7 / 8 to save time when budget is breached | The methodology violations cost more than time savings |
| No tracking which phases consistently overrun | Can't calibrate budgets in OPERATOR-CALIBRATION-LOG.md without per-phase wall data |

---

## Operator self-prompt at budget pressure

```
We're 80% through the Phase 4 budget for this tier. Status check:
- Convergence: <CONVERGED / not yet>
- Falsifier coverage: <N>/<M> Hs probed
- Active Hs remaining: <N>

Decision options:
  (a) Accept current state; exit Phase 4 even if not converged. Document in phase4_complete.flag.
  (b) Extend Phase 4 by 30%; re-evaluate at 110% budget. Soft breach; document.
  (c) Escalate tier (T2 → T3); user notification + budget increase.
  (d) Reframe: the question is broader than the tier indicated; back to Phase 1.

Pick one and document the choice.
```

This prompt should fire automatically when phase-readiness.sh reports phase incomplete AND budget >80%.

---

## Cross-session calibration

OPERATOR-CALIBRATION-LOG.md tracks actual vs estimated wall time per phase per tier. After ~10 sessions:

- Persistent overrun → reset that phase's percentage allocation
- Persistent underrun → consider tighter caps (less polish time, more rounds within Phase 4)
- High variance → tier mismatch is happening; re-examine tier assessment heuristics

Phase 10 drift-check should periodically incorporate calibration data into recommendations for OPERATING-MODES.md and TIER-TRIAGE.md updates.
