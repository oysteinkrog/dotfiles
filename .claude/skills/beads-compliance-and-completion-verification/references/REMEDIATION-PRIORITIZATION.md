# REMEDIATION-PRIORITIZATION.md — How To Triage Phase 9 Output

<!-- TOC: Beyond threshold | Consequence weighting | Priority formula | Tier-by-impact | Stuck/yo-yo classification | Sloppy-session escalation | When to tombstone | Worked example -->

> The threshold (default 700) decides *whether* a bead is false-closed. This file decides *which one to remediate first*. With 30+ false-closed beads in a real audit, you can't tackle them all at once.

---

## Beyond the threshold: why prioritization matters

If 35 beads scored below 700, treating them as "all equal" wastes effort. Some are blocking critical user-facing functionality; others are dead code nobody touches. Prioritize so:

1. The first 5 beads remediated unblock the most downstream work.
2. P0/P1 false-closed beads are addressed before P3/P4.
3. Beads with severe theater (score < 250) get more priority than mild false-closed (500-699).
4. Beads that block the most other beads get dependency-aware prioritization.
5. Beads owned by the same agent get clustered (one conversation can fix several).

---

## Consequence weighting

Per the `⌂ CONSEQUENCE` operator: ask "if this bead is fictional, what user-visible / production-visible behavior is broken?"

| Consequence class | Description | Multiplier |
|-------------------|-------------|------------|
| **Critical user-facing** | Auth, billing, data integrity | ×2.0 |
| **User-facing feature** | Visible UI behavior, public API | ×1.5 |
| **Developer-facing** | CLI, internal API, tooling | ×1.0 |
| **Infrastructure** | Migrations, CI, deployment | ×1.3 |
| **Internal optimization** | Refactor, cleanup | ×0.7 |
| **Dead-code candidate** | No callers, no users | ×0.3 |

The auditor agent infers the consequence class from the bead body + `evidence.json#citations` (which files / modules are touched). If unclear, the orchestrator asks the user.

---

## Priority formula

```
priority_score = severity_score × consequence_multiplier × downstream_blockers + p0_p1_bonus
```

Where:
- `severity_score = 1000 - score` (worse audit score → higher remediation priority)
- `consequence_multiplier` from the table above
- `downstream_blockers` = number of open beads that depend on this one (clamp 1–10)
- `p0_p1_bonus` = +200 for P0, +100 for P1, 0 for P2+, -50 for P4

The remediator subagent computes this for every false-closed bead and orders the remediation list. Top 5 are surfaced in the executive summary.

---

## Tier-by-impact triage

For audits with > 20 false-closed beads, group by impact tier:

| Tier | Criteria | Action |
|------|----------|--------|
| **T0 — Fire** | Score < 250 AND consequence ≥ ×1.5 AND P0/P1 | Reopen with P0; halt feature work; dedicated agent |
| **T1 — High** | Score < 500 AND consequence ≥ ×1.0 AND P0/P1/P2 | Completion-debt bead with P1 priority; surface in next standup |
| **T2 — Medium** | Score 500-700 AND P2/P3 | Completion-debt bead at original priority; pick up with normal cadence |
| **T3 — Low** | Score < 700 AND consequence ≤ ×0.7 | Completion-debt bead at P4; backlog for slow weeks |
| **T4 — Defer** | Dead-code candidate (no callers) | Tombstone after one pass with no remediation |

The auditor subagent labels each remediation bead with its tier (`audit-tier-T0`, `audit-tier-T1`, etc.) so `bv --robot-triage --label audit-tier-T0` surfaces the fires.

---

## Stuck-bead classification

Beads on a "stuck trajectory" (`600 → 600 → 600` across passes) need different handling than freshly-flagged beads. After 3 passes with no movement:

| Stuck reason | Detection | Action |
|--------------|-----------|--------|
| **No assignee** | Remediation bead has no owner | Auto-assign per `closed_by_session` of original |
| **Blocked by another open bead** | Dep graph shows blocker still open | Recursively prioritize the blocker |
| **AC too vague** | `spec.json` has < 3 checklist items | Apply `/idea-wizard` ambition rounds to expand |
| **Original is unfix-as-scoped** | Cross-bead synthesis flags scope drift | Mark original as won't-fix-tombstone; create fresh bead |
| **Agent fatigue** | Same agent reopened 5+ times without closing | Reassign to a different agent |

---

## Sloppy-session escalation

When `cass_mining/patterns.md` identifies a session that batch-closed many false-closed beads:

1. **Tag every bead** closed by that session with `audit-suspect-session-<id>`.
2. **Apply -25 prior** to the score for those beads — `BLOCKING` until proven innocent.
3. **Surface in REPORT.md** under a new "Suspect sessions" subsection.
4. **Notify the operator** — if it's a human, talk to them; if it's a configured agent, retrain its prompt.

The detection is automatic via `anomaly-scan.sh` Pattern 20 (batch-close). The escalation is operational.

---

## When to tombstone instead of remediate

Some "false-closed" beads aren't worth remediating because the underlying work was never relevant. Tombstone (rather than create completion-debt) when:

- The bead's described feature was abandoned in design (look for cass evidence of "decided not to ship X").
- The bead's described file no longer exists (deleted in a later commit, no reference elsewhere).
- The bead duplicates another, more recent bead that *did* land properly.
- The bead's description is too thin to verify (`spec.json#coverage_gaps` includes "bead body too thin").

**Tombstone protocol:**
```bash
br update <bead-id> --status=tombstone \
  --notes="Tombstoned during audit pass <UTC>: <reason>. Not remediating because <justification>."
br sync --flush-only
```

The tombstoned bead remains in the bead graph (history) but doesn't count against future audits' false-closed totals.

---

## Worked example: 35 false-closed beads, what to remediate first

Audit pass on `frankensqlite` produced 35 false-closed beads. Distribution:
- 5 in T0 (Fire): score < 250, consequence ≥ ×1.5, P0/P1
- 8 in T1 (High): score < 500, consequence ≥ ×1.0, P0/P1/P2
- 15 in T2 (Medium): 500-700 score, P2/P3
- 5 in T3 (Low): consequence ≤ ×0.7
- 2 in T4 (Defer): dead-code candidates

**Recommended remediation order:**

1. **Week 1:** Reopen the 5 T0 fires. Dedicated agent. P0 priority.
2. **Week 2-3:** Create completion-debt beads for 8 T1 highs. Distribute across team.
3. **Sprint 4-6:** T2 mediums folded into normal sprint cadence.
4. **Slow weeks:** T3 lows.
5. **Pass 2 audit:** T4 candidates tombstoned if still no callers.

By Pass 4 (4 weeks later), the false-closed list should be < 10 beads — predominantly the T2/T3 carryover.

---

## Visualization

The dashboard (`dashboard.html`) includes a "Remediation backlog" widget showing tier counts, age (passes-since-flagged), and assignee distribution. See [METRICS-PIPELINE.md](METRICS-PIPELINE.md) for the Prometheus export of these counters.

---

## Anti-patterns in prioritization

| Don't | Why |
|-------|-----|
| Remediate in score-ascending order alone | Misses consequence weighting; you'd fix dead code before user-facing P0s |
| Remediate by P0/P1 alone | Misses score severity; a P0 at score 850 is healthier than a P3 at score 150 |
| Tombstone aggressively to "clean up" the list | Tombstones erase history; only tombstone with strong justification per the criteria above |
| Reassign stuck beads to a fresh random agent | Fresh agents often reproduce the same theater; fix the AC clarity first |
| Treat the false-closed list as "shame the agent who closed it" | The audit's purpose is graph truthfulness, not blame allocation |