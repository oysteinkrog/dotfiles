# OPERATOR-CALIBRATION-LOG.md — Per-Operator Calibration Tracking

<!-- TOC: Why a calibration log | What gets tracked | The log file format | Calibration metrics | Reading the log | When the log triggers coaching | Per-operator vs cross-operator views | Workflow integration | Anti-patterns | Cross-references -->

Operators have systematic biases. Without tracking, those biases compound silently across sessions. A formal calibration log makes biases visible and coachable — and lets operators improve over time.

This file describes the format, metrics, and workflow for `references/OPERATOR-CALIBRATION-LOG.md` (the *file* — singular per operator, but a class of logs across the operator pool).

Referenced by: CROSS-SESSION-LEARNING.md, WALL-TIME-BUDGET.md, FRAMING-WORKBOOK.md, SIX-LAYER-VALIDATION.md, CRITIQUE-CRAFT.md, CROSS-SESSION-DRIFT-CATALOG.md, DISCRIMINATIVE-TEST-DESIGN.md, ARTIFACT-LINTER-RULES.md, REQUIRED-CONTRADICTIONS.md.

---

## Why a calibration log

Operator quality emerges over many sessions, not within one. An operator who:

- Consistently overestimates their hypothesis-quality at Phase 1 → systematic Phase 7 audit-finding rate
- Tends toward Imagination pole (per REQUIRED-CONTRADICTIONS.md) → low Focus during Phase 4
- Writes vague falsifiers → Phase 5 debates devolve into rhetoric
- Underestimates wall-time budgets by 30% → quarterly budget overruns

...exhibits each pattern *consistently*, but only across sessions. The calibration log surfaces these patterns at quarterly review.

For T3+ stake operators, calibration tracking is mandatory (per OPERATOR-ONBOARDING-CURRICULUM.md). For T1-T2 operators, optional but encouraged.

---

## What gets tracked

The log captures per-session, per-operator metrics. Each session adds a row to:

```yaml
sessions:
  - session_id: RS-20260301-microservice-arch
    operator_id: opus-4.7
    tier: T3
    archetype: A1
    wall_time_estimated_min: 240
    wall_time_actual_min: 312
    phase_4_kill_rate: 0.4
    phase_4_add_rate: 0.6
    phase_4_round_count: 5
    phase_5_debate_rounds: 4
    phase_5_verdict_quality: medium
    audit_finding_count_high: 1
    audit_finding_count_medium: 3
    audit_finding_count_low: 8
    discriminative_test_count: 2
    discriminative_test_decisive_pct: 0.5
    falsifier_quality_avg: 0.75
    handback_word_count: 950
    drift_verdict: divergent_minor
    user_satisfaction: 0.85
```

This is YAML for readability; in practice, append-only JSONL.

---

## The log file format

`references/OPERATOR-CALIBRATION-LOG.md` is a markdown file with two sections:

### Section A: Per-session rows (machine-appended)

```markdown
## Per-Session Log

| date | session_id | tier | wall_actual/est | kill/add | falsifier_q | drift | satisfaction |
|------|------------|------|-----------------|----------|-------------|-------|--------------|
| 2026-03-01 | RS-...-microservice | T3 | 312/240 (1.30) | 0.40/0.60 | 0.75 | div_minor | 0.85 |
| 2026-03-08 | RS-...-auth-rewrite | T4 | 720/600 (1.20) | 0.55/0.45 | 0.82 | conv_full | 0.92 |
| ...
```

Updated manually at Phase 8 freeze for now. `scripts/append-calibration-row.sh` is a planned helper for one-row-per-session appends.

### Section B: Quarterly summary (machine-generated)

```markdown
## Q1 2026 Summary

- Sessions: 12
- T3+: 9 (75%)
- Wall-time variance: +18% (consistent overrun)
- Falsifier quality trend: improving (0.62 → 0.80 across quarter)
- Drift verdict distribution: 60% convergent, 30% div_minor, 10% div_major
- Top failure modes:
  1. F-403 (confirmation bias): 4 sessions
  2. F-103 (vague falsifier): 3 sessions
  3. F-501 (no kills in Phase 5): 2 sessions

**Coaching actions:** see calibration-coach.md report (latest: 2026-04-01)
```

Updated quarterly by `subagents/calibration-coach.md`.

---

## Calibration metrics

| Metric | Source | What it measures |
|--------|--------|---------------------|
| `wall_actual / wall_estimated` | per-phase scripts | Time-budget calibration (1.0 = perfectly calibrated) |
| `kill_rate / add_rate` | scripts/convergence-check.sh | Phase 4 discriminative-test quality |
| `falsifier_quality_avg` | subagents/falsifier-grader.md | Mean 5-axis grade across H beads |
| `audit_finding_count_high` | scripts/audit-bead-invariants.sh | Phase 7 quality (lower = better) |
| `discriminative_test_decisive_pct` | per Phase 5 verdicts | % of tests that produced state transitions |
| `drift_verdict` | scripts/drift-check.sh | Phase 10 trajectory vs canonical (convergent_full/minor/div_minor/div_major) |
| `handback_word_count` | `wc -w deliverables/HANDBACK.md` after MO-09-handback | HANDBACK length (<=200 words ideal) |
| `user_satisfaction` | post-session prompt | 0-1 scale; collected by operator query, or via `/loop` when that slash tool is available |

Each metric has *target ranges* per OPERATOR-ONBOARDING-CURRICULUM.md weeks 1-4.

---

## Reading the log

### Per-session

Open the log; locate the session row. The columns expose:

- **wall_actual/est ratio** — was this session well-budgeted? Operators consistently above 1.2 over-commit.
- **kill/add ratio** — was Phase 4 discriminative? Below 0.5 suggests confirmation bias.
- **falsifier_q** — were Phase 1 falsifiers crisp? Below 0.6 suggests Phase 1 framing is the bottleneck.
- **drift** — did the methodology hold? `div_major` triggers Phase 10 reopening.
- **satisfaction** — did the user get value? Below 0.7 triggers HANDBACK voice review.

### Per-quarter

Open the Quarterly Summary. The summary highlights:

- *Trends* — improving, stable, regressing
- *Repeat failure modes* — F-codes that fired ≥3× across the quarter
- *Comparative percentile* — operator vs operator pool

---

## When the log triggers coaching

Per `subagents/calibration-coach.md`, calibration triggers coaching when:

- **D-Cal-1**: Wall-time variance > 1.3 across ≥5 sessions → re-baseline budgets
- **D-Cal-2**: kill_rate < 0.5 across ≥5 sessions → discriminative-test-design coaching
- **D-Cal-3**: Falsifier quality < 0.6 average → falsifier-writing workshop
- **D-Cal-4**: drift verdict `div_major` ≥ 2 in a quarter → methodology reset
- **D-Cal-5**: Audit-finding count high ≥ 3 in a session → rework, not just lessons

Each diagnosis routes to specific coaching content in OPERATOR-ONBOARDING-CURRICULUM.md.

---

## Per-operator vs cross-operator views

For organizations running brennerbot at scale (per BRENNERBOT-AT-SCALE.md):

### Per-operator log

`references/OPERATOR-CALIBRATION-LOG.md` lives in the *operator's* configuration. Private; tracks *that* operator's calibration.

### Cross-operator dashboard

For the operator pool (10+ operators), aggregate views surface:

- Operator A: above-average kill_rate, below-average wall-time
- Operator B: above-average satisfaction, weak falsifier quality
- Operator C: improving across all axes

Aggregation lives in `metrics/` directory at organizational level; not in the per-operator log.

---

## Workflow integration

### At Phase 8 freeze

Until `scripts/append-calibration-row.sh` exists, the operator appends this row manually from `scripts/dump-session-report.sh` output. The planned helper will compute:

- `wall_actual` from session-logs/ timestamps
- `kill_rate / add_rate` from per-phase metrics
- `falsifier_quality_avg` from subagents/falsifier-grader.md output
- `audit_finding_count_*` from `br list --label=audit-finding`
- `drift_verdict` from `scripts/drift-check.sh` output

Appended as a new row to Section A.

### Quarterly

`subagents/calibration-coach.md` runs (manually triggered):

1. Reads Section A rows from the past quarter
2. Computes summary metrics
3. Generates Section B summary
4. Routes coaching diagnoses (D-Cal-1..5) to specific actions
5. Emits `assets/templates/calibration-report-template.md` instance

The report goes to the operator + (if applicable) the operator's mentor.

### At new-session bootstrap

The operator should review their calibration log entries from the past 30 days. Recent patterns (e.g., D-Cal-2 firing in 3 of 5 sessions) inform Phase 1 framing discipline for the new session.

Per OPERATOR-ONBOARDING-CURRICULUM.md Week 4 fluency: weekly calibration review is part of the discipline.

---

## What NOT to track

The calibration log is for *systematic patterns*, not single-session events:

- ✗ "Pane crashed at tick 17" — tactical event; goes in session-logs/, not calibration log
- ✗ "User changed their mind about scope" — single event
- ✗ "Operator was tired" — not a methodology calibration item

The log captures behaviors that *recur* across sessions. Single events stay in session logs.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip the log "I know my calibration" | Calibration is the *gap* between perception and outcome — perception is unreliable |
| Manually edit Section A rows | Auto-appended; manual edits break aggregation |
| Compare operator A vs operator B punitively | Different operators handle different question shapes; comparison is informational |
| Track only failures | Track successes too — what's working is also signal |
| Trigger coaching on a single session | D-Cal-1..5 require ≥5 sessions; single-session noise |
| Hide the log | Per-operator privacy is fine; *opacity* prevents coaching |
| Trust quarterly summary without spot-checking | Aggregation can hide tail outcomes; review individual rows for context |
| Use the log for performance reviews | The log's purpose is *coaching*, not evaluation; performance reviews use separate metrics |

---

## Privacy + access

For organizations:

- The per-operator log is **personal**. Operators control whether to share.
- Quarterly summaries can be aggregated (anonymized) for cross-operator dashboards.
- Coaching reports go to the operator + their explicit mentor only.

Don't conflate calibration with performance evaluation. Calibration is a *learning tool*.

---

## Schema versioning

The log schema versioned via Section A's first table column. Adding a column = schema bump:

- v1: date, session_id, tier, wall_actual/est, kill/add, falsifier_q, drift, satisfaction
- v2: + discriminative_test_decisive_pct, audit_finding_count_high (when DISCRIMINATIVE-TEST-DESIGN.md added)

Schema changes documented in METHODOLOGY-EVOLUTION-LOG.md.

---

## Cross-references

- [CROSS-SESSION-LEARNING.md](CROSS-SESSION-LEARNING.md) — how calibration feeds into cross-session lessons
- [OPERATOR-ONBOARDING-CURRICULUM.md](OPERATOR-ONBOARDING-CURRICULUM.md) — Week 1-4 calibration targets
- [WALL-TIME-BUDGET.md](WALL-TIME-BUDGET.md) — wall-time variance bands
- [FRAMING-WORKBOOK.md](FRAMING-WORKBOOK.md) — falsifier_quality scoring
- [DISCRIMINATIVE-TEST-DESIGN.md](DISCRIMINATIVE-TEST-DESIGN.md) — kill_rate quality
- [REQUIRED-CONTRADICTIONS.md](REQUIRED-CONTRADICTIONS.md) — track which oscillation pole the operator gets stuck on
- [BRENNERBOT-AT-SCALE.md](BRENNERBOT-AT-SCALE.md) — cross-operator aggregation
- `scripts/append-calibration-row.sh` — log-row writer (Tier-7 future addition; currently the row is appended manually at Phase 8 freeze using session-logs/ data)
- [subagents/calibration-coach.md](../subagents/calibration-coach.md) — quarterly coaching subagent
- [assets/templates/calibration-report-template.md](../assets/templates/calibration-report-template.md) — report format
