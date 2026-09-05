# LIVING-DOCUMENTATION-PATTERNS.md — Long-Running Investigations

<!-- TOC: Why living docs | When to use | Living-review session structure | Cadence design | Stakeholder communication | Triggering refresh ticks | Drift handling across ticks | Promotion to canonical | Anti-patterns | Composition with regulatory monitoring -->

Per `living-review` mode in EXTENDED-OPERATING-MODES.md. Some questions are never fully closed:
- Tech stack choices (revisit annually as ecosystem evolves)
- Regulatory landscapes (refresh quarterly as rules change)
- Long-running architecture decisions (revisit as scale grows)
- Best-practices evolving fields (ML, web frameworks, security)

This file documents how to run brennerbot in living-review mode, where each "session" is a periodic refresh tick instead of a one-shot investigation.

---

## Why living docs

A standard brennerbot session produces a HANDBACK at a point-in-time. For evolving questions, the HANDBACK is stale within months.

Living-review pattern:
- Initial deep session (T3+) produces baseline answer
- Periodic refresh ticks (cadence: weekly / monthly / quarterly)
- Each tick is a Phase 4 + Phase 7 refresh against new evidence
- DELTA-HANDBACK.md per tick highlights what changed
- After 4-6 ticks, full re-run if methodology has drifted

This compounds the investment: the initial session's value is preserved AND extended over time.

---

## When to use

### Good fit

- **Tech-stack decisions** that depend on ecosystem (e.g., "stay with PostgreSQL or migrate to ScyllaDB?")
- **Regulatory monitoring** (e.g., "are we PCI-DSS compliant under current rules?")
- **Performance baselines** (e.g., "what's the load-bearing bottleneck in our hot path?")
- **Methodology questions** (e.g., "is metric M still the right SRE objective?")
- **Vendor evaluations** (e.g., "should we keep using vendor V or switch?")

### Bad fit

- **One-shot decisions** (e.g., "which database to use for this new project") — finalize and move on
- **Time-pressed incidents** — use incident-investigation mode instead
- **Strict deadlines** — living-review is for sustained, not bursty, work
- **Highly volatile domains** where tick cadence can't keep up — use ad-hoc fresh sessions instead

---

## Living-review session structure

```
Initial baseline (Phase 1-10): T3 fresh-question session
   ↓
Tick N=1 (Phase 4 + 7 refresh): typically 1-2h, smaller roster
   ↓
Tick N=2 (Phase 4 + 7 refresh): typically 1-2h
   ↓
... continues at cadence ...
   ↓
Periodic full re-run (e.g., yearly): T3+ session re-validating baseline
```

### Workspace layout for living-review

```
brennerbot_session_<topic>/
├── .brenner_workspace/
│   ├── phase0_scope_decision.md  # mode: living-review; cadence: quarterly
│   ├── tick_history.md           # log of each tick's deltas
│   └── ...
├── intake/
│   ├── question_of_record.md     # baseline question
│   └── question_evolution.md     # how question evolved across ticks
├── corpus/
│   ├── corpus_index.md
│   └── per_tick/
│       ├── tick-001-2026-04-01/  # snapshot per tick
│       └── tick-002-2026-07-01/
├── deliverables/
│   ├── BASELINE-HANDBACK.md      # initial baseline
│   ├── DELTA-HANDBACK-001.md     # per-tick deltas
│   └── DELTA-HANDBACK-002.md
├── audit-findings/
│   ├── per_tick/
│   │   ├── tick-001/
│   │   └── tick-002/
└── RESUME.md                     # always points to most recent tick
```

---

## Cadence design

### Cadence selection

```
DOMAIN VOLATILITY                | CADENCE     | Triggers
---------------------------------|-------------|-------------------------------
Frontier AI / ML capabilities    | Monthly     | New model release, paper, benchmark
Web frameworks / standards       | Quarterly   | Major version release, browser update
Cloud / SaaS infra patterns      | Quarterly   | Major provider feature, pricing change
Distributed systems theory       | Annual      | New CAP / consistency results
Database internals               | Annual      | Major engine release, paper
Foundational CS / algorithms     | 3-5 years   | Major textbook, algorithm publication
Regulatory / compliance          | Quarterly   | Rule changes, enforcement actions
Security threats / CVEs          | Monthly     | Critical CVE in our stack
Performance baselines            | Per-deploy  | Or weekly during change-heavy periods
```

Match cadence to volatility. Per CADENCE selection, document in scope_decision.

### Cadence drift detection

Sometimes the cadence we picked is wrong:
- **Too frequent**: ticks consistently produce no deltas → cadence too aggressive; widen
- **Too infrequent**: ticks consistently produce big surprises → cadence too lax; tighten
- **Erratic**: some ticks tiny, some huge → underlying domain has multiple cadence regimes; consider sub-tracking

Per Phase 10 drift check (per tick), evaluate whether cadence needs adjustment.

---

## Stakeholder communication

Living-review questions usually involve stakeholders who care:
- Engineering team (tech-stack)
- Compliance team (regulatory)
- Leadership (strategic)
- Customers (vendor evaluations)

### Per-tick brief

Each tick produces a DELTA-HANDBACK.md ≤30 lines:

```
# DELTA-HANDBACK — <topic> — Tick N

**Tick date:** <ISO>
**Cadence:** <weekly|monthly|quarterly|annual>
**Verdict change:** <NO change | minor refinement | major shift | re-evaluate>

## What changed since last tick

- <evidence change 1: e.g., "PostgreSQL 17 released; benchmark shows X%">
- <evidence change 2>
- <evidence change 3>

## H state changes

- H-001: confirmed → confirmed (unchanged)
- H-005: deferred → confirmed (new EV-NNN supporting)
- H-008 (NEW): proposed; under investigation

## Action items (delta)

- <item 1>
- <item 2>

## Confidence in baseline verdict

<unchanged | confidence raised | confidence lowered | flipped>

## Next tick

<date>
```

This brief is what stakeholders read; the full audit/distillation lives in the workspace.

### Annual full re-run brief

When the annual full re-run completes, produce a YEAR-IN-REVIEW.md:

```
# Year in Review — <topic>

## Baseline verdict (initial)
<one-line>

## Verdict evolution
- Tick 1 (Q1): unchanged
- Tick 2 (Q2): unchanged
- Tick 3 (Q3): minor refinement (per delta-003)
- Tick 4 (Q4): major shift (per delta-004)

## Major events
- <event 1>: triggered tick N
- <event 2>: confirmed shift

## Verdict at year end
<one-line; possibly different from baseline>

## Methodology lessons
- <lesson 1>
- <lesson 2>

## Recommendation for next year
<continue at same cadence | adjust cadence | retire question>
```

This communicates the long-term value of the living-review.

---

## Triggering refresh ticks

### Cadence-driven (default)

Per `assets/ntm-pipelines/brennerbot-living-review.yaml` (round-4 pipeline; spec outline — operator-driven, not executable under canonical ntm). Schedule via cron or `/loop` skill:

```
loop quarterly run-tick on workspace_X
```

Or operator manually invokes when cadence reaches.

### Event-driven (interrupt cadence)

Some events warrant unscheduled ticks:
- New regulatory release
- Critical CVE in our stack
- Major paper / benchmark / model release
- Customer-impacting incident in the relevant domain

Operator notes the event in `tick_history.md` and runs an immediate tick. The cadence resets from the unscheduled tick.

### Composition with optional /loop and /schedule

```bash
# Schedule a quarterly tick if /schedule is available:
/schedule cron "0 0 1 */3 *" "run brennerbot living-review tick on /workspaces/topic-X"

# Or run once at a specific time:
/schedule once "2026-08-01 09:00" "run brennerbot living-review tick"
```

---

## Drift handling across ticks

### Methodology drift detection

Per CROSS-SESSION-DRIFT-CATALOG.md, track:
- Per-tick drift verdict (convergent / divergent-recoverable / divergent-regression)
- 3+ consecutive same-verdict → persistent regression; reopen baseline session

If methodology drift is detected in a tick:
1. Document in DELTA-HANDBACK
2. Run mini-Phase-10 lesson commitment
3. Apply lesson to subsequent ticks

### Verdict drift detection

Sometimes the verdict shifts:
- Confidence drops over consecutive ticks → load-bearing assumption may be wrong
- Major shift between ticks → reframe-and-rebaseline is needed

In either case:
- Document in YEAR-IN-REVIEW
- Consider full re-run at next cadence boundary

### Question drift detection

Sometimes the question itself evolves (per `intake/question_evolution.md`):
- New sub-questions surface
- Original framing becomes too narrow
- Stakeholders' decision-rule changes

When question drifts:
- Don't silently change the baseline question
- Document the evolution in `question_evolution.md`
- Decide: adjust the current living-review OR fork to a new living-review with the new question

---

## Promotion to canonical

After 3-5 ticks, evaluate whether the living-review's findings deserve canonical status:

- **Stable verdict (no change in 3+ ticks)**: promote the baseline verdict to canonical reference; reduce cadence
- **Persistent question (always evolving)**: maintain living-review indefinitely
- **Resolved question (verdict became obvious)**: terminate living-review with final HANDBACK

Per CROSS-SESSION-LEARNING.md, document the promotion in skill repo's references/.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Initial baseline at T1 (curiosity) | Living-review needs T3+ baseline; otherwise drift compounds errors |
| Skip cadence selection | Cadence too tight burns budget; too lax misses signal |
| Skip per-tick drift check | Methodology drift compounds invisibly |
| Skip question_evolution.md updates | Future re-runs lose the "why we changed scope" trail |
| Re-run baseline session every tick | Wastes effort; tick is supposed to be Phase 4 + 7 refresh |
| Run living-review on one-shot question | Use fresh-question mode instead |
| Track ticks in operator's head | Use tick_history.md for posterity |
| Skip Phase 10 lesson commitment per tick | Cross-session learning compounds slowly without commitment |

---

## Composition with regulatory monitoring

For regulatory living-reviews specifically:

- Compose with /reporting-sensitive-encrypted-gh-issues for handling regulated data
- Compose with /security-audit-for-saas for periodic security baseline
- Compose with /tax-return-preparation-and-advice for tax-regime monitoring (if applicable)

Per SKILL-COMPOSITION-PATTERNS.md, document the composition.

---

## Composition with /flywheel for cross-topic patterns

Per /flywheel, a long-running operator builds intuition across many living-reviews. /flywheel can:

- Mine across living-review tick histories
- Surface patterns ("when X event happens, all our Q-class living-reviews should refresh")
- Promote patterns to canonical methodology

After 6+ months of running multiple living-reviews, /flywheel produces meta-lessons.

---

## Operator self-test

Before launching a living-review:

1. Is this question genuinely persistent (3+ ticks of value), or one-shot?
2. Is the cadence aligned with domain volatility?
3. Are stakeholders OK with periodic-not-instant updates?
4. Is the workspace setup for accumulating tick history?
5. Do I have the operator-attention budget for ongoing maintenance?

If any "no", reconsider whether living-review is the right mode.

---

## Cross-references

- EXTENDED-OPERATING-MODES.md (`living-review` mode)
- assets/ntm-pipelines/brennerbot-living-review.yaml (the pipeline)
- VERIFICATION-FIRST.md (per-tick re-verification)
- CROSS-SESSION-LEARNING.md (per-tick lesson commitment)
- `/loop` or `/schedule` if available; otherwise CronCreate or shell cron for cadence automation
