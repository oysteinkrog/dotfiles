# CROSS-SESSION-LEARNING.md — How Lessons Accumulate Across Sessions

<!-- TOC: The lifecycle | What persists | Lesson commitment protocol | Cross-session drift catalog | Cass archive convention | Operator calibration metrics | Anti-patterns -->

Mirrors documentation-website's LIFECYCLE.md and feedback-pipeline pattern. A single brennerbot session is the *unit*; the methodology *evolves* across many sessions. This file describes that evolution.

---

## The cross-session lifecycle

```
Session N → produces:
  - workspace artifacts (per-session, frozen)
  - DRIFT-CHECK.md (per-session, with Lessons section)
  - cass-indexed conversation history (auto)

Operator commits:
  - Lessons → references/ updates (skill repo)
  - Cross-session drift entries → references/CROSS-SESSION-DRIFT-CATALOG.md
  - Calibration metrics → references/OPERATOR-CALIBRATION-LOG.md

Session N+1 → starts with:
  - Updated references/ (knowledge accumulated)
  - cass-mineable history of session N
  - Higher-quality marching orders, operator cards, archetype start-packs
```

The skill *gets better* with each session. The user benefits from the operator's prior work.

---

## What persists across sessions

| Artifact | Per-session (workspace) | Cross-session (skill repo) |
|----------|-------------------------|----------------------------|
| Question of record | per-session | n/a |
| Hypothesis beads | per-session | n/a |
| Evidence packs | per-session | n/a |
| Distillations | per-session | n/a |
| HANDBACK.md | per-session | n/a |
| RESUME.md | per-session (frozen) | n/a |
| DRIFT-CHECK.md | per-session | aggregated into cross-session-drift-catalog |
| Operator cards | n/a | references/OPERATORS.md (updated by Phase 10 lessons) |
| Question archetypes | n/a | references/QUESTION-ARCHETYPES.md (extended by sessions surfacing new archetypes) |
| Failure codes | n/a | references/FAILURE-TABLE.md (extended by new failure modes) |
| Anti-patterns | n/a | references/ANTI-PATTERNS.md (extended by surfaced patterns) |
| Marching-order templates | n/a | assets/marching-orders/MO-*.md (extended by new operator moves) |
| Source corpus quote bank | n/a | references/SOURCE-CORPUS.md (extended with new §-anchors) |
| Calibration metrics | n/a | references/OPERATOR-CALIBRATION-LOG.md |

---

## Lesson commitment protocol

After Phase 10 produces `DRIFT-CHECK.md § Lessons`:

### Step 1 — Categorize each lesson

Each `L-NNN` entry maps to one of:

- **Operator extension** — new card needed in OPERATORS.md
- **Marching-order extension** — new MO template needed
- **Archetype discovery** — new question archetype to add
- **Failure-mode discovery** — new F-### code to document
- **Anti-pattern discovery** — new AP-* to document
- **Calibration update** — adjust an existing tier/threshold/parameter
- **Reference clarification** — fix a confusing or wrong passage in references/

### Step 2 — Apply the change to the skill

The operator (NOT the drift auditor — the human in charge) edits the relevant `references/` file. Use a small commit per lesson:

```bash
git add .claude/skills/brennerbot-with-ntm/references/<file>.md
git commit -m "lesson(L-001): <short description>; from <SESSION_ID>"
```

### Step 3 — Verify the change is consistent

Run `/sw validate` on the skill. Run `bash -n scripts/*.sh`. Ensure no broken cross-references.

### Step 4 — Mark the lesson committed

In the workspace's `DRIFT-CHECK.md`, append:

```markdown
### L-001 — <subject>
... existing content ...

**Committed:** YYYY-MM-DDTHH:MM:SSZ
**Skill commit:** <git sha of the skill repo commit>
```

This closes the loop: every L-NNN ends in either committed-to-skill OR explicitly-deferred-with-reason.

---

## Cross-session drift catalog

`references/CROSS-SESSION-DRIFT-CATALOG.md` (created on first commit) accumulates drift verdicts:

```markdown
# Cross-Session Drift Catalog

| Session ID | Date | Verdict | Top regression | Top improvement | Lessons committed |
|------------|------|---------|-----------------|-----------------|-------------------|
| RS-20260506-event-log | 2026-05-06 | convergent | (none) | (none) | 0 |
| RS-20260507-async-arch | 2026-05-07 | divergent-improvement | (none) | I-001 ⟂ replaced | 1 |
| RS-20260512-payment-incident | 2026-05-12 | divergent-regression | R-001 ⊞ skipped | (none) | 1 |
```

The catalog feeds OPERATOR-CALIBRATION-LOG.md (next section). Patterns in drift verdicts surface methodology issues:

- Persistent `divergent-regression` on the same operator → that operator's marching-order template needs strengthening
- Persistent `divergent-improvement` proposing the same replacement → consider promoting it to canonical
- Drift catalog with no entries after many sessions → either methodology is stable OR drift checks aren't surfacing real drift (suspect the latter)

---

## Cass archive convention

After Phase 8 freeze, the workspace's session-logs/ are cass-indexed automatically (assuming `cass` is configured). Future cass-mining (per CASS-MINING-RECIPES.md) can find this session.

To make a session more discoverable, the operator can:

1. Run `MO-cass-archive-current.md` (Tier-3 MO) at end-of-session — this writes a cass-friendly summary to `<workspace>/cass-summary.md` with explicit keyword tags
2. Tag the session with archetype + tier + verdict in the summary
3. Cross-link to related prior sessions

The summary format mirrors what a future cass query would want: terse, keyword-rich, with verbatim links to the most-cited evidence.

---

## Operator calibration metrics

`references/OPERATOR-CALIBRATION-LOG.md` (created on first commit) tracks the operator's own calibration:

```markdown
# Operator Calibration Log

## Confidence calibration

| Time period | High-confidence Hs that survived next session | Medium-confidence | Low-confidence | Notes |
|-------------|------------------------------------------------|-------------------|----------------|-------|
| Q1 2026 | 8/10 (80%) | 5/10 (50%) | 2/10 (20%) | Calibration looks OK |
| Q2 2026 | 9/10 (90%) | 6/10 (60%) | 1/10 (10%) | Slightly under-confident — could push more Hs to confirmed |

## Phase 4 wall-time calibration

| Tier | Estimated | Actual median | Variance | Notes |
|------|-----------|---------------|----------|-------|
| T2 | 1h | 1.5h | 50% | Consistently exceed Pair tier estimate by 50% |
| T3 | 3h | 3.2h | 7% | On target |

## Operator-bias indicators

| Bias | Sessions affected | Mitigation |
|------|-------------------|------------|
| Family-favoritism (cc) | 3/12 (25%) | Force more cod/gmi adjudicators |
| Premature convergence (Phase 7) | 2/12 (17%) | Increase trio-round minimum from 2 to 3 for T3+ |
```

This is the operator looking at *themselves*. Phase 10 drift-check feeds this log; the calibration log feeds future tier defaults and roster rules.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Drift verdict committed but lessons never applied | The skill stagnates; same regressions repeat |
| Apply lessons by editing existing reference passages without recording the change | Lost causality; can't track which session led to which improvement |
| Apply many lessons in a single commit | Hard to revert if a lesson turns out to be wrong |
| Ignore persistent drift patterns ("we know about that, it's fine") | Drift becomes invisible technical debt in the methodology |
| Calibration log without sample size | "Confidence is 80%" with N=2 is anecdote, not calibration |
| Treat cass archive as automatic without operator-tagged summary | Future sessions can't easily find what's relevant |
| Commit lessons but never re-test calibration | The lessons might be wrong; test against future sessions |

---

## When to skip cross-session learning

For T1 (curiosity) sessions, skipping the lesson-commit protocol is fine — the methodology investment isn't worth it for one-off questions.

For T2+, skip only if:

- The Phase 10 drift-check verdict is `convergent` AND
- No new archetypes / failure modes / operator extensions surfaced AND
- The operator has run ≥10 prior sessions on similar archetypes (calibration is stable)

In all other cases, commit lessons. The methodology compounds; skipping is leaving money on the table.

---

## Cross-session triangulation (T5 special case)

For T5 (existential) decisions, multiple brennerbot sessions on the SAME question, each at a different time / by different operators / with different rosters, may be warranted. The decision memo should reference all sessions and explain agreement/disagreement.

This is heavyweight — only justified for genuinely irreversible high-stakes decisions. Most questions don't need it.

For T5 multi-session triangulation:

- Each session's RESUME.md is preserved
- A meta-DRIFT-CHECK.md compares trajectory across sessions
- The decision memo cites all of them and surfaces dissent across sessions

This is the closest brennerbot gets to formal multi-perspective triangulation. The cost is high; the alternative (one-shot Solo decision on existential matter) is higher.
