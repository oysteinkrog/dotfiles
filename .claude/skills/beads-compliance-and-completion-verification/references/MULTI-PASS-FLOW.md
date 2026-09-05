# MULTI-PASS-FLOW.md — Pass-Over-Pass Audit Workflow

<!-- TOC: The multi-pass arc | Per-pass goals (1-5+tripwire) | Ambition round (between passes) | Plan-space refinement | Score-trend interpretation | Pass-spacing | When to abandon a pass | Cross-pass diagnostic prompts | What "done" looks like -->

A single audit pass is rarely the end. The remediation work spawned by Phase 9 needs to land. The next pass verifies it landed correctly. Patterns this skill borrows from `/reality-check-for-project` (ambition rounds) and `/beads-workflow` (plan-space refinement) apply here.

> **Convergence is the goal**, not a single perfect pass. Plan for 3-5 passes spread over weeks; each pass tightens the feedback loop and the bead graph drifts closer to truthful.

---

## The multi-pass arc

```
Pass 1 (Onboarding)         → Discovery: find ~40-60% false-closed; lenient threshold (600)
   ↓ remediation work lands ↓
Pass 2 (Standard)           → Verify remediation; tighten threshold to 650
   ↓ ambition round ↓
Pass 3 (Standard)           → Continue verification; threshold 700 (canonical)
   ↓ plan-space refinement ↓
Pass 4 (Standard)           → Should converge or near-converge
   ↓ optional ↓
Pass 5 (Comprehensive)      → Final tightening with multi-model triangulation
   ↓ tripwire ↓
Tripwire (daily/weekly)     → Maintain converged state
```

---

## Per-pass goals

### Pass 1 — Discovery (Onboarding)

**Goal.** Find the project's specific theater patterns. Don't try to fix anything yet.

**Settings.**
- Threshold: 600 (lenient — first-pass numbers will be ugly)
- Mode: `onboarding`
- Policy: `report-only` (don't flood the bead graph with debt beads on first pass)
- CASS mining: required

**Output review.**
- Read `passes/<UTC>/cass_mining/patterns.md` carefully — these become tunings to `rubric.md` for Pass 2.
- Read the false-closed list. Don't act on it yet; just understand the shape.
- Note worst offenders by `closed_by_session` — these agents/sessions need attention.

**Anti-pattern.** Flooding the bead graph with 60+ completion-debt beads on Pass 1. The user can't act on that volume; they'll abandon the audit.

---

### Pass 2 — Verification + remediation start

**Goal.** Now that we know the patterns, create remediation beads for the highest-priority false-closed.

**Settings.**
- Threshold: 650
- Mode: `standard`
- Policy: `completion-debt`
- Apply project-specific patterns from Pass 1's cass_mining/patterns.md (folded into rubric.md)

**Output review.**
- Compare to Pass 1: how many of the same false-closed beads are still flagged? (Hopefully fewer if anyone has been working on them.)
- Triage the new completion-debt beads in `bv` — assign priorities, surface the high-impact ones to active agents.
- Apply the **ambition round** to the remediation beads (see below).

---

### Pass 3 — Standard cadence begins

**Goal.** Continue verification; threshold at canonical 700.

**Settings.**
- Threshold: 700
- Mode: `standard`
- Policy: `completion-debt`

**Output review.**
- Trends.md should show downward false-closed count.
- Beads that scored low in Pass 1/2 but are still low in Pass 3 → escalate. Either the remediation isn't being picked up, or the rubric is wrong.

---

### Pass 4 — Convergence approach

**Goal.** Converge.

**Settings.**
- Threshold: 700
- Mode: `standard`

**Output review.**
- `convergence.json#is_converged` should be true OR very close.
- If not converged, identify the specific blockers:
  - Beads with persistent low scores → human investigation needed.
  - Beads with high score variance → rubric inconsistency; tighten.

---

### Pass 5 — Comprehensive (optional, high-stakes)

**Goal.** Final cross-validation with multi-model triangulation.

**Settings.**
- Mode: `comprehensive`
- Triangulation enabled (Claude + Codex + Gemini score in parallel)

**Output review.**
- `convergence.json#triangulation_consensus` should show all models agreed within ±50 on every spot-checked bead.
- Disagreements indicate ambiguous rubric language; document and tighten for next epoch.

---

### Steady-state — Tripwire

After convergence, the audit becomes a *tripwire* (see `CI-TRIPWIRE.md`). Daily/weekly automatic re-verification. Any regression triggers human attention.

---

## The ambition round (between passes)

Borrowed from `/reality-check-for-project`. After Phase 9 remediation, BEFORE the next pass, apply the ambition round to the newly-created completion-debt beads:

### Ambition prompt — Round 1

```
Look at the completion-debt beads created by the most recent audit pass
(label=audit-debt,audit-pass-<YYYY-MM-DD>). For each bead:

That's a decent start, but the missing-items list barely scratches the surface.
What ELSE is needed to truly satisfy the original bead's intent? Surely there
are edge cases, integration concerns, observability hooks, and downstream
consumers we haven't accounted for. Revise the bead in-place to make it MUCH,
MUCH more comprehensive.

DO NOT OVERSIMPLIFY. DO NOT LOSE ANY ITEMS from the original audit findings.
This is plan-space refinement — it's cheap to be exhaustive here.
```

### Ambition prompt — Round 2

```
That's better, but STILL incomplete. Think about:
- What other beads silently depended on this one being correct?
- What user-visible behavior is broken in the meantime?
- What's the observability that would have caught this earlier?

Add those concerns to the completion-debt beads. Revise in-place.
```

### Ambition prompt — Round 3 (domain-specific)

```
Now think harder. For each completion-debt bead, what testing techniques
from /testing-fuzzing, /testing-conformance-harnesses, /testing-metamorphic,
/testing-golden-artifacts would catch the original gap if applied? Add those
testing requirements to the bead.
```

---

## Plan-space refinement (between Pass N and Pass N+1)

Borrowed from `/beads-workflow`. After ambition rounds, apply the polish prompt 4-5 times:

```
Reread AGENTS.md so it's still fresh in your mind. Check over each
completion-debt bead super carefully — is it self-contained? Are the
acceptance criteria specific enough? Could anything cause a future
implementer to need to consult the audit dir?

DO NOT OVERSIMPLIFY. DO NOT LOSE ANY FEATURES OR FUNCTIONALITY.

Make sure each bead includes:
- Explicit file paths for the implementation
- Explicit test names that must exist
- Explicit acceptance criteria (verbatim from the audit's missing-items list)
- Explicit dependencies on upstream beads
- Verification commands the next implementer can copy-paste

Use only the `br` cli tool for changes. Use ultrathink.
```

Iterate until the polish prompt finds nothing to change.

---

## Score-trend interpretation

The `trends.md` table accumulates one row per bead per pass. A bead's trajectory tells a story:

| Trajectory | Story |
|------------|-------|
| 600 → 950 → 985 | Healthy: remediation landed, near-perfect now |
| 600 → 600 → 600 | Stuck: no one is picking up the remediation bead |
| 600 → 720 → 680 | Regression: code drift; the original lost ground |
| 600 → 900 → 600 | Yo-yo: unstable code; the bead is tugged by frequent changes |
| 600 → ? (missing) | Tombstoned or orphaned: investigate why the bead disappeared |
| 950 → 600 | Catastrophic: a recent commit broke a previously-verified bead |

The orchestrator emits per-trajectory annotations in REPORT.md so the user can quickly spot stuck or yo-yo beads.

---

## Pass-spacing recommendations

| Project pace | Recommended spacing |
|--------------|---------------------|
| 1+ beads closed per day | Pass every 1-2 weeks |
| ~5 beads closed per week | Pass every 3-4 weeks |
| Steady-state (1-2 closed/week) | Pass monthly + tripwire daily |
| Maintenance (no new closes) | Pass quarterly + tripwire weekly |

Don't pass too frequently — the remediation beads need time to be picked up and worked. A pass every day on a slow-moving project just produces identical reports.

---

## When to abandon a pass

Sometimes a pass produces clearly-broken results (e.g., 100% of beads scored 0). Causes:

- The project's test suite is broken on HEAD (Phase 4 always FAIL).
- The bead store was just rebuilt (so all beads have fresh `closed_at` timestamps with no git history).
- The audit dir was checked out at a stale commit.

If you spot this, **don't commit the pass**. Delete the `passes/<UTC>/` dir, fix the underlying issue, re-bootstrap. The audit dir's history must remain trustworthy — committing a known-broken pass corrupts trends.

(Note: this is the **only** case where deleting a pass dir is acceptable, and the user must explicitly authorize it given AGENTS.md's "no file deletion" rule.)

---

## Cross-pass diagnostic prompts

After 3+ passes, ask the orchestrator:

```
Look at trends.md for this project. For beads with trajectory "600 → 600 → 600"
(stuck), investigate WHY. Possibilities:
1. Remediation bead exists but has no assignee.
2. Remediation bead is blocked by another open bead.
3. Remediation bead's acceptance criteria are too vague.
4. The original bead is unfix-able as currently scoped (needs re-design).

For each stuck bead, propose one of:
(a) Assign + give marching orders to a specific agent.
(b) Resolve the blocker.
(c) Tighten the AC.
(d) Mark the original as won't-fix and tombstone the remediation bead.
```

This prompt turns trends.md into actionable triage.

---

## What "done" looks like (multi-pass perspective)

The audit is "done" — really done — when:

1. Two consecutive passes are converged (per `CONVERGENCE-CRITERIA.md`).
2. False-closed rate is < 5% of total closed beads.
3. No bead is "stuck" (every flagged bead has either landed remediation OR been explicitly won't-fix-tombstoned).
4. Tripwire has been running for ≥ 1 month with zero regressions.
5. The project's `rubric.md#tunings` table has been stable for ≥ 1 month.

At that point, the audit moves to maintenance mode (tripwire only, no human review unless a fire is raised).
