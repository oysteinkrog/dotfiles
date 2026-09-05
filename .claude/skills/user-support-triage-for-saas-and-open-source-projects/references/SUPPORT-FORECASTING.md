# Support Forecasting & Capacity Planning

Triage volume is forecastable. Most teams treat it as weather (look out the window) when it should be treated as logistics (plan the inventory). This file is the math: how to forecast 30-day ticket volume, how to translate it into capacity, and how to instrument an "error budget for support" that catches systemic problems before they become 6-hour queues.

> **Core insight:** the queue is a buffer between inbound demand and triage capacity. When demand exceeds capacity for any sustained period, the buffer fills, customers wait longer, sentiment drops, and some leave. The math of buffer dynamics is the same here as in any operations problem.

---

## The Volume Forecast

### Inputs

```
Required for any forecast:
  Last 90 days of daily ticket counts (per channel)
  Last 90 days of weekday/weekend pattern
  Last 90 days of "spike" events (incidents, launches, changes)
  Active user count over time (DAU or MAU)
  Known upcoming events (launches, marketing, deploys, plan changes)
```

### A simple but reliable model

```python
# Pseudo-code; project's own forecast script lives in
# <project>/.claude/support-triage/scripts/forecast.py

# Baseline: rolling 28-day median of daily ticket count, weekday-adjusted
baseline = rolling_median(28, weekday_buckets=True)

# Trend: linear slope over last 90d / DAU; gives tickets-per-user-day
trend = linear_slope(tickets_per_day / DAU, window=90)

# Seasonality: same-day-of-week-of-month historical multiplier
seasonality = lookup(historical_dow_dom_multiplier)

# Known events: human-curated multipliers for launches/incidents
events = sum(known_event_impacts)

forecast = baseline * (1 + trend * days_ahead) * seasonality + events
```

This is not the most sophisticated forecast in the world (no Prophet, no ARIMA), and it doesn't need to be. The variance reduction from baseline → median × seasonality × event-adjustment is already 70-80% of what's possible.

### Forecast horizon

| Horizon | Use |
|---|---|
| 1-day | Today's headcount; "do we need to call in help?" |
| 7-day | Weekly capacity check; queue-zero target |
| 30-day | Hiring / contractor / on-call rotation planning |
| 90-day | Strategic — "is volume per user growing or shrinking?" |

The 90-day metric (tickets per user per month) is the most diagnostic. If it's *growing*, you have a quality problem (product is generating more friction per user); if it's *shrinking*, deflection is working.

---

## The Capacity Number

```
Capacity = (FTE-equivalents) * (hours per FTE per week) * (tickets per hour)
         - (compounding-work reservation)
         - (slack buffer)
```

Decoding each:

- **FTE-equivalents**: how many full-time-equivalents touch triage. Owner-half-time + a contractor + an agent-assisted owner doing 2x leverage all count fractionally.
- **Hours per FTE per week**: 30-32 max for triage-as-job; 10-15 max for triage-as-side-of-desk (the agentic owner case)
- **Tickets per hour**: project-specific; 6-15/hr for routine, 0.5-2/hr for tail. Average is mostly determined by the head/tail mix.
- **Compounding-work reservation**: 10-20% of capacity reserved for KB / runbook / theme synthesis. Skip this and the team is reactive forever.
- **Slack buffer**: 15-25% of capacity reserved as headroom. Without buffer, every spike is a crisis.

### The dangerous number: 100% utilisation

A queue that runs at 100% capacity has *infinite* expected wait time during any spike. Operations theory: utilisation must be <85% for waits to remain bounded under realistic variance. Most under-staffed support teams are running at 95-100% and feel surprised by the periodic backlog explosions.

If actual utilisation is >85% on a sustained basis, the response is one of:
- Increase capacity (hire / contractor / co-maintainer for OSS)
- Decrease demand (deflection / KB / product fix)
- Reduce per-ticket time (better templates / better tools / sample-based oversight on narrow cases)

It is *not* "everyone work harder." That fails predictably.

---

## The Queue As A Diagnostic

The queue's *shape* tells you what's wrong, not just how much:

| Shape | Meaning | Response |
|---|---|---|
| Steady ~20 tickets, all <2h old | Healthy steady-state | Maintain |
| Steady ~20 tickets but oldest is 3 days | Capacity OK; one stuck case | Triage the stuck case specifically |
| Growing trend over 14 days | Demand > capacity; structural | Capacity or demand intervention |
| Spike of 100 in 1 hour | Outage | Pipeline E + crisis comms |
| Bimodal: many <1h + many >7d | Routine clearing fast, complex stalling | Tail-strategy reinforcement; may need an owner/expert |
| 0 tickets for >24h on a normally-active project | Channel may be broken | Verify intake plumbing; not a celebration |

The last case is real and worth specifying: a channel that *should* have tickets but doesn't is either a product where everything's perfect (rare) or an intake pipe that's broken (much more likely). Always verify the intake when volume drops unexpectedly.

---

## SLAs As Error Budgets

SLA tiers in `05-policies.md` define commitments (e.g., "P2 first-response in 4 business hours"). Treat the SLA as an *error budget*:

```
Error budget = total tickets * (1 - SLA hit rate target)
             = e.g., 200 tickets/wk * (1 - 0.95) = 10 budgeted breaches/week
```

When breaches are well under budget, capacity is generous and you can:
- Take on more compounding work
- Tighten the SLA target (e.g., 95% → 97%)
- Reduce the safety buffer

When breaches approach budget, you're at the edge. Capacity intervention is needed before they exceed.

When breaches *exceed* budget, you have two options the same week:
1. Stop accepting new work for that tier (e.g., slow inbound through deflection / batching)
2. Borrow capacity from a different tier (cross-train; pull in engineering)

This frame avoids both panic ("we're behind!") and complacency ("we're fine, mostly"). It quantifies the buffer.

---

## Spike Recovery

Spike: queue suddenly grows 3-10x normal. Pattern:

```
[OPERATOR-LOCAL: Spike Recovery]
1) Confirm cause: outage? marketing event? launch? regulator letter?
2) Triage the spike volumetrically:
   - Are these all the same root cause?
     If yes → 🪧 BROADCAST + Pipeline E (one comms thread).
     If no → run categorisation pass first
3) Pull capacity:
   - Cancel non-urgent compounding work this week
   - If owner can pull engineer / contractor / co-maintainer, do so
   - If not, batch-template-reply the spike at the cost of personal touch
4) Track recovery:
   - Plot queue depth hour-by-hour
   - Inflection point (queue starts shrinking again) is your "we got it"
5) Post-spike retro:
   - Was the spike forecastable? Why didn't we see it coming?
   - Did our SLA error budget hold?
   - What structural change reduces future spike severity?
```

The most expensive thing during a spike is reacting per-ticket as if normal. Spikes need *bulk* responses, not individual responses. This is what the BROADCAST operator and Pipeline E are for.

---

## The Pre-Launch Forecast

When the project plans an event likely to drive support volume — feature launch, plan-change, pricing update, marketing push — pre-forecast:

```
[OPERATOR-LOCAL: Pre-Launch Forecast]
1) Estimate audience reached (subscribers? user base? viral coefficient?)
2) Estimate confusion / friction rate from the change (rough; e.g., 1-5%)
3) Compute expected ticket spike: audience * friction
4) Compare to 7-day capacity:
   - If spike < 0.5x capacity: routine; pre-stage templates
   - If spike 0.5-2x capacity: pre-stage capacity (warn team; pull help)
   - If spike >2x capacity: defer launch OR phase rollout
5) Pre-author the top 3 expected ticket replies as templates
6) Publish proactive content (blog, KB, in-app) BEFORE the launch
7) Stage status-page entry "in case of issues during launch"
```

A launch with no pre-staged support is a launch that will be remembered as buggy regardless of code quality. Conversely, a launch with pre-staged support and proactive content can materially reduce inbound volume; measure forecast vs actual instead of copying a universal percentage.

---

## Concrete Targets For Different Project Sizes

These are starting points, calibrated as rough operating heuristics rather than project-specific truth. Override based on actual volume, channel mix, tier commitments, and maintainer/team capacity.

| Project size | Tickets/day | Capacity target | Compounding reservation |
|---|---|---|---|
| Solo / OSS hobbyist | 0-5 | 30-min/day batch window | Sundays only |
| Solo founder / small SaaS | 5-30 | 1 hour/day; agent-assisted | 2 hours/week |
| Early-stage team (2-10 people) | 30-100 | 0.5 FTE-equivalent | 4 hours/week |
| Growth-stage SaaS | 100-500 | 2-4 FTE | 8 hours/week per FTE |
| Mature B2B SaaS | 500-2000 | 5-15 FTE + tiered escalation | 20% of capacity |
| Enterprise / SLA-bound | 2000+ | Per-tier dedicated capacity + on-call rotation | 25% of capacity |

The Solo/OSS row is where agentic leverage can matter most: a single human plus a well-governed triage agent can handle much more than the human alone, *if* the deflection / KB / template stack is solid and the autonomy boundaries are strict.

---

## How This File Plugs In

| Used by | How |
|---|---|
| 🔮 PREDICT operator | Forecasting + spike anticipation |
| 📐 EISENHOWER operator | Capacity allocation across quadrants |
| 10-metrics.md | Forecast vs actual; SLA error budget |
| 05-policies.md | Per-tier SLA targets become error budgets |
| METRICS-AND-DASHBOARDS.md | Capacity dashboards |
| ORCHESTRATOR-WORKFLOW.md Pipeline L (Mass-event) | Spike recovery |

---

## Cross-References

- [METRICS-AND-DASHBOARDS.md](METRICS-AND-DASHBOARDS.md) — operating metrics
- [PARETO-AND-LONG-TAIL.md](PARETO-AND-LONG-TAIL.md) — the 70/20/10 budget
- [DEFLECTION-AND-SELF-SERVICE.md](DEFLECTION-AND-SELF-SERVICE.md) — demand reduction
- [PROACTIVE-SUPPORT.md](PROACTIVE-SUPPORT.md) — pre-launch outreach
- [CRISIS-COMMS.md](CRISIS-COMMS.md) — spike comms during outages
