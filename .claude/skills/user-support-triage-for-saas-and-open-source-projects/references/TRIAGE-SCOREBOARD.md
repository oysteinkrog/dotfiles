# Triage Scoreboard — What To Actually Measure (And What Not To)

`METRICS-AND-DASHBOARDS.md` covers the canonical metrics (FRT, MTTR, CSAT, NPS). This file goes further: which of those are signal, which are noise, and which *additional* measurements actually drive better triage. The scoreboard is the quarterly artifact a project should be able to look at and make calibration decisions from.

> **Core insight:** every measured metric becomes a target, and every target gets gamed. The art is choosing metrics whose gaming is *aligned* with what you actually want, and refusing to publish metrics whose gaming is opposed.

---

## The Bad Metrics (Common; Discourage Them)

| Metric | Why it backfires |
|---|---|
| **Tickets closed / day** | Encourages "close to clear"; mass-close-without-resolution |
| **Time to first response** alone | Encourages auto-acknowledgement spam; metric goes green while real time-to-resolution stays bad |
| **Average satisfaction score** alone | Buried by inactive surveys; high CSAT can mask high-effort experiences |
| **Ticket volume** | Lower is "better" only if it's because of fewer bugs; can also mean customers gave up |
| **Reopen rate** | Low reopen rate can be customers giving up rather than satisfaction |
| **Backlog size** | Encourages wholesale closure of stale tickets to "clean up" |
| **Agent's average handle time** | Penalises careful tail-strategy work; rewards rushed-then-reopened |

If the project leadership only looks at any of these, the support function gets worse over time. The Goodhart effect: "when a measure becomes a target, it ceases to be a good measure."

---

## The Good Metrics (Lead With These)

### Outcome metrics (lagging, but real)

| Metric | What it tells you | Target shape |
|---|---|---|
| **First Contact Resolution (FCR)** | Were they helped without coming back? | Trending up over time |
| **Time-to-customer-action-required** | How long before WE were the bottleneck vs THEM | Capacity warning if low; theirs is OK |
| **CES (Customer Effort Score)** | How hard was it for the customer? | Lower than industry baseline |
| **Time-to-resolution by ticket class** | Median + P95; broken out by class so tail doesn't hide | P95 monotone non-increasing |
| **NPS detractor decay rate** | After theme is fixed, do detractors recover? | Recovery within 60-90d |
| **Silent-cohort retention delta** | Do customers reached proactively retain better? | Held-out control comparison |
| **Refund per active customer** | $ goodwill spent per customer-year | Stable or declining |
| **Issues→roadmap conversion rate** | Which support themes became roadmap? | >0; ratio is project-specific |

### Process metrics (leading; they should move)

| Metric | What it tells you |
|---|---|
| **Owner-edit rate on draft bundles** | How well-tuned the templates and operators are |
| **Confirmation-gate violation count** | Should be zero. Any non-zero is a process incident |
| **Sample-based-oversight rejection rate** | Quality of any auto-send classes |
| **Adapter-validation pass rate** | Are channels feeding clean data? |
| **Fire-drill pass rate** | Are runbooks aging well? |
| **Time from theme-detection to KB-article** | KB pipeline freshness |
| **Time from theme-detection to roadmap inclusion** | Product responsiveness |
| **Loopback notification rate** | Of fixes shipped, % announced to original reporters |
| **Tickets with red-flag misclassification** | Number found post-hoc; non-zero is concerning |

### Health metrics (about the function itself)

| Metric | What it tells you |
|---|---|
| **Owner approval queue P50 / P95** | Is the human bottleneck reasonable? |
| **Compounding-work hours actually spent** | The 70/20/10 budget — are we hitting the 10% reservation? |
| **Crisis-flagged ticket frequency** | How often does the agent encounter Pipeline W cases? |
| **Off-hours ticket volume per agent** | Burnout proxy for human triagers |
| **Tickets-per-active-customer-month** | Product-friction proxy |
| **Deflection ratio** (per `DEFLECTION-AND-SELF-SERVICE.md`) | KB / docs / inline-error effectiveness |

---

## The Scoreboard Itself (Suggested Layout)

A one-page weekly artifact:

```
[Project] — Support Scoreboard — Week of [YYYY-MM-DD]

┌────────────────────────────────────────────────────────────┐
│ THIS WEEK    │  vs LAST WEEK  │  vs 4-WEEK AVG │  TARGET    │
├────────────────────────────────────────────────────────────┤
│ Volume                                                     │
│   Open tickets       42       │   38   ▲       │ 45 ─       │
│   Closed             58       │   55   ▲       │ 60 ─       │
│   Backlog change    -16       │  -17   ─       │ <0 ✓       │
│                                                            │
│ Speed                                                      │
│   FRT P50           12 min    │  14    ▲       │ 30 ✓       │
│   FRT P95           4.3 hr    │  4.1   ▼       │ 8 ✓        │
│   TTR P50           2.1 hr    │  1.8   ▼       │ 4 ✓        │
│   TTR P95           38 hr     │  34    ▼       │ 48 ✓       │
│                                                            │
│ Quality                                                    │
│   FCR rate          78%       │  76%   ▲       │ 80         │
│   CES               2.3       │  2.4   ✓       │ <2.5       │
│   CSAT (responded)  4.6       │  4.5   ✓       │ >4.3       │
│   NPS detractors     3 new    │  2     ▼       │            │
│                                                            │
│ Process                                                    │
│   Owner edits       11 / 58   │  13/55 ▲       │ <30% ✓     │
│   Confirm-gate vios  0        │   0    ✓       │ 0          │
│   Loopback sent      4 / 6    │  3/4   ▲       │ ≥80%       │
│                                                            │
│ Compounding                                                │
│   KB articles new    2        │  1     ▲       │            │
│   Themes converged   1        │  0     ✓       │            │
│   Fire drills run    0        │  0                          │
│                                                            │
│ Risk                                                       │
│   Crisis-flagged     0        │  1     ▼       │            │
│   Fraud-flagged      2        │  1                          │
│   Legal-hold active  0        │  0                          │
└────────────────────────────────────────────────────────────┘

EXEC SUMMARY (3 sentences)
- Volume normal; backlog shrinking on schedule.
- Two fraud-flagged tickets this week (above baseline); review patterns.
- FCR up to 78% post-template-revision; positive sign on Q3 deflection bet.

NOTABLE
- Theme `webhooks-missing` converged across all VoC streams;
  recommend roadmap (CRX-431).
- Owner-edits trending down — templates are aging well.
```

This format is opinionated. Each project tunes the metrics shown; the *structure* matters more than which specific metrics make the cut.

---

## What The Scoreboard Should Cause

A scoreboard that nobody acts on is theater. The artifact has to drive decisions. A useful test: each metric has a documented "what we do if it goes red" answer.

| Metric goes red | Action |
|---|---|
| Backlog growing | Capacity intervention or demand intervention |
| TTR P95 sliding | Tail-strategy reinforcement; pull in engineering |
| Owner-edit rate climbing | Template / voice retraining; revisit `08-voice.md` |
| Confirmation-gate violation | Process incident; postmortem; revisit guardrails |
| Refund $ trending up | Compensation calculus calibration |
| Theme not converging despite shipped fix | Possibly didn't ship the right fix; reopen 5-WHY |
| Crisis-flag rate climbing | Possibly worsening real-world conditions, possibly mis-classification |
| Fraud-flag rate climbing | Possibly real fraud wave, possibly classifier drift |
| Compounding hours under reservation | Schedule intervention; protect the 10% |

Without these "if-red" actions, the scoreboard is a pretty number. With them, it's an operating loop.

---

## The Anti-Goodhart Discipline

Some metrics will be gamed if published. Tactics for resilience:

- **Pair every speed metric with a quality metric.** FRT alone gets gamed; FRT × FCR doesn't.
- **Audit a random sample by hand monthly.** The metric says 78% FCR; the 30 hand-audited tickets confirm or contest the number.
- **Look at the *shape* of distributions, not just averages.** Bimodal TTR with rapid head + crawling tail looks like decent average TTR but is actually a problem.
- **Compare to held-out control where possible.** Especially for proactive outreach: the cohort *not* contacted is the comparison.
- **Don't tie compensation to vanity metrics.** Tying anything to ticket-close-count rapidly destroys quality.
- **Publish quality metrics by named owner, not blamelessly.** Accountability without blame; ownership without scapegoating.

---

## CSAT Trap And How To Escape It

CSAT survey-response bias is severe. The customers who respond to "rate this support interaction" skew either very satisfied or very dissatisfied. The "indifferent middle" — the largest cohort — usually doesn't respond. So a 4.6 CSAT can hide a large band of "okay, I guess" experiences that quietly churn.

Tactics:

1. **Track survey response rate alongside score.** A high CSAT with low response rate is unreliable.
2. **CES (Customer Effort Score) is more predictive.** Easier to answer; less skewed.
3. **Look at lapsed-survey customers.** Who didn't respond? What's their retention?
4. **Read free-text verbatims, not just scores.** The text is the signal.
5. **Don't trumpet aggregate CSAT in marketing.** It's hostage to a small responsive cohort.

---

## Cohorts Worth Slicing

Aggregate metrics hide patterns. Useful slices:

| Slice | Reveals |
|---|---|
| New customers (<30d) | Onboarding friction |
| Trial users | Activation pain |
| Enterprise vs SMB vs free | Tier-specific gaps |
| Power users (top decile usage) | Edge-case bug discovery |
| Churned users last 90d | Hindsight on what we missed |
| By theme tag | Theme-specific TTR, CSAT, etc. |
| By region / locale | Locale-specific issues |
| By plan tier | Tier-blind issues / SLA-tier accuracy |
| By last-deploy version | Regression-correlated |

The default scoreboard should expose 1-2 useful slices; the rest are queryable on demand.

---

## How This File Plugs In

| Used by | How |
|---|---|
| 10-metrics.md | Project-specific instantiation |
| METRICS-AND-DASHBOARDS.md | Implementation; this file is the strategy |
| Pipeline V (VoC mining) | Imports the theme/cohort metrics |
| OBSERVABILITY-DRIVEN-TRIAGE.md | Joins triage metrics with telemetry |
| 📈 OUTCOME records | Feed the scoreboard's process metrics |

---

## Cross-References

- [METRICS-AND-DASHBOARDS.md](METRICS-AND-DASHBOARDS.md) — implementation
- [OBSERVABILITY-DRIVEN-TRIAGE.md](OBSERVABILITY-DRIVEN-TRIAGE.md) — telemetry joins
- [SUPPORT-FORECASTING.md](SUPPORT-FORECASTING.md) — capacity vs volume
- [PARETO-AND-LONG-TAIL.md](PARETO-AND-LONG-TAIL.md) — cohort allocation
- [VOICE-OF-CUSTOMER-LOOP.md](VOICE-OF-CUSTOMER-LOOP.md) — theme metrics
