# Metrics + Dashboards

What to measure, what to act on, what to ignore. Onboarding step writes a `10-metrics.md` for the project; this is the framework.

## What To Measure

### Quality / SLA
- **First Response Time (FRT)** — Time from ticket creation to first non-system reply. Median (P50) + tail (P90, P95). Per-tier.
- **Mean Time To Resolve (MTTR)** — Time from creation to `resolved` status. Median per priority.
- **First Contact Resolution (FCR)** — % of tickets resolved with one reply (no back-and-forth).
- **SLA breach rate** — % of tickets exceeding their SLA. Per-tier.
- **Time-in-status** — How long tickets sit in each status. Spot bottlenecks (e.g., "ticket sits in `awaiting_customer` for 14 days median" = process problem).

### Volume / Demand
- **Ticket volume by category** — Trend over time. Spike = bug or product regression.
- **Ticket volume per active customer** — Volume / MAU. Rising = degrading product experience.
- **Channel mix** — Where are tickets coming from? Shift from in-app to X-DM = the in-app form is broken or hard to find.
- **Self-serve deflection** — KB views resolving without a ticket. (KB views with 0 follow-up ticket within 7 days from same user.)

### Customer Experience
- **CSAT (Customer Satisfaction)** — Post-resolution 1-5 survey. Act on <4 with a follow-up.
- **NPS (Net Promoter Score)** — Quarterly 0-10 "would you recommend?". %Promoters - %Detractors. Detractor follow-up = highest leverage.
- **Touches-to-resolve** — How many back-and-forth messages per ticket. >3 = process problem.
- **Re-open rate** — % of tickets re-opened within 30 days. >5% = closing prematurely.

### Agent Health
- **Tickets per agent per day** — Capacity check.
- **Time-on-hostile-user-tickets per agent** — Burnout signal; rotate.
- **Macro reuse %** — Higher = more efficient; too high (>70%) = personalization issues.

## What To Act On (Vs Just Watch)

| Metric | Act when... | Action |
|---|---|---|
| **FRT P90** | Trending up 2 weeks running | Add capacity; OR find process bottleneck |
| **CSAT detractor verbatims** | Any new ones | Direct follow-up call from owner |
| **SLA breach rate by tier** | >5% on paid tier | Escalate; review staffing model |
| **Volume in single category spiking** | 2x baseline in a day | Likely a bug — check git log + status page |
| **Self-serve deflection trending down** | 2 weeks running | KB is stale; refresh top-N articles |
| **Touches-to-resolve P50** | >3 | Macros / templates not specific enough |
| **Re-open rate** | >5% | Closing prematurely; reinforce verify-before-close in voice |
| **NPS trending down** | Quarter over quarter | Survey detractors directly; product call |

Don't act on volume in isolation — it's confounded by customer growth.

## What To Ignore

- **Aggregate ticket volume without context** — Could be growth (good) or product regression (bad). Always normalize.
- **MTTR without priority breakdown** — A P3 taking 14 days to resolve is fine; a P0 taking 4h might not be.
- **Mean** — Use median + P90. Mean is dragged by outliers.
- **NPS as a single number** — The verbatim comments are the signal; the score is just a rollup.

## Dashboards (What To Build)

### Triage Operator Dashboard

What an agent sees during a triage session:

```
─────────────────── OPEN ──────────────────
Open: 17  | Acknowledged: 4  | In Progress: 7  | Awaiting Customer: 3

⚠ SLA: 2 breached, 4 at risk (within 2h)
🔥 Hot: 3 tickets >24h with no agent reply

─────────────── BY PRIORITY ───────────────
P0: 0  | P1: 2  | P2: 12  | P3: 3

────────────── BY CATEGORY ──────────────
billing: 5  | auth: 4  | bug: 3  | content: 2  | other: 3

────────────── THIS SESSION ──────────────
Resolved: 0
Replied:  0
Beads:    0
```

### Owner / Weekly Dashboard

Weekly review:

```
WEEK 17 (April 21-27)

Volume:        87 tickets (vs 92 last week, vs 78 4-week-avg)
FRT P50:       2.1h (target: <4h) ✓
FRT P90:       9.4h (target: <24h) ✓
MTTR P50:      28h (target: <72h) ✓
SLA breaches:  2 (2.3%)
CSAT (responses): 4.2 / 5 (n=32)
NPS:           +28 (n=18, this week)

By category trend:
billing  ▆▅▄▅▆▇█  ▲ new spike — investigate
auth     ▃▂▃▂▂▁  ▼
bug      ▅▄▃▄▃▂  ▼
content  ▂▂▃▂▂▂  =

Detractor verbatims (3 this week, all reviewed):
  "..."
  "..."

Action items:
  - billing spike: check webhook health
  - schedule call with detractor #2
```

### Status Page Public

What customers see:

```
All Systems Operational

┌─────────────────┬───────────┬──────────────┐
│ API             │ ✓ Operational │ 99.99% (90d) │
│ Web             │ ✓ Operational │ 99.97% (90d) │
│ CLI Auth        │ ✓ Operational │ 99.95% (90d) │
│ Webhooks        │ ✓ Operational │ 99.91% (90d) │
│ Support response│ ✓ Healthy     │ FRT P90: 4h  │
└─────────────────┴───────────┴──────────────┘
```

The "support response" row is critical — without it, you can show "all green" while the support queue is buried.

## Setting Up

Most projects use:
- **Native admin dashboard** — `/admin/support/dashboard` (custom DB ticketing, see `/admin-page-for-nextjs-sites`)
- **Grafana** — pulled from Postgres / metrics export
- **Mixpanel / PostHog** — ticket events as analytics events
- **Status page** — Statuspage.io / BetterStack / Instatus (covered in [STATUS-PAGE.md](STATUS-PAGE.md))

## Survey Cadence

| Survey | Trigger | Target response rate |
|---|---|---|
| **CSAT** | Immediately after `resolved` status | 20-30% |
| **NPS** | Quarterly, sampled 20% of MAU | 5-15% |
| **Onboarding NPS** | 7 days after first activation | 30%+ |
| **Cancellation survey** | At cancel-flow | 40-60% |

## Anti-Patterns

| Don't | Why |
|---|---|
| Optimize agents on FRT alone | They'll send useless "looking" replies to stop the clock |
| Set MTTR target without priority breakdown | P3s drag MTTR; agents close P0s prematurely to "balance" |
| Average CSAT and ignore verbatims | The score hides the signal |
| Vanity metrics dashboards | Looks impressive; doesn't drive action |
| Public-facing dashboards with no support-response row | Status page lies about customer experience |
| Closing tickets early to game MTTR | Re-open rate spikes; trust erodes |

## Companion Refs

- [STATUS-PAGE.md](STATUS-PAGE.md) — public status page setup
- [POST-INCIDENT-RETRO.md](POST-INCIDENT-RETRO.md) — what to retro on
- [KB-FEEDBACK-LOOP.md](KB-FEEDBACK-LOOP.md) — turning ticket data into KB articles
- `/saas-customer-analytics` — the broader analytics framework
