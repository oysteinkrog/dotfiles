# Voice-of-Customer Loop — Turning Tickets Into Roadmap Fuel

`KB-FEEDBACK-LOOP.md` covers the support→docs path: tickets that should become KB articles. This file covers the support→**product** path: themes that should become roadmap items, NPS verbatims that should become hypotheses, and sentiment shifts that should become alarms. The two loops feed off the same raw input but diverge in audience, cadence, and decision criteria.

> **Core insight:** every ticket is two pieces of information: the resolution the user needs *now*, and a signal about what's broken at a system level. Triage handles the first; VoC mining surfaces the second. Without the second loop, the same theme gets handled hundreds of times before someone notices it should have been a roadmap item six months ago.

---

## The Five VoC Streams

Most teams under-invest in VoC because they treat support tickets as the only stream. Five distinct streams should feed the loop:

| Stream | Cadence | Signal type | Owner |
|---|---|---|---|
| **Open tickets** (closed in last 30d) | Weekly | Recurring problems, friction points | Triage agent |
| **NPS verbatims** | Per survey wave | Aspirational and structural complaints | Founder / PM |
| **Cancellation reasons** | Per cancel | Dealbreakers; the "last straw" | Founder / RetEng |
| **Sales-lost reasons** | Per lost deal | Missing-feature or competitor-strength signal | Sales / PM |
| **Public mentions** (X, HN, Reddit, GH discussions) | Daily scrape | Volume / sentiment / virality | Triage agent |

Each stream answers a different question. Tickets answer *"what hurts customers we kept?"* NPS verbatims answer *"what would make happy customers happier?"* Cancellation reasons answer *"what made them leave?"* Sales-lost answers *"what made them never come?"* Public mentions answer *"what does the market think?"* Roadmap from one stream alone is biased. Roadmap from all five converges.

---

## The Theme Mining Cycle

Cadence: weekly for tickets + public mentions; per-event for NPS / cancel / sales-lost; monthly for synthesis.

### Step 1 — Tag with consistent vocabulary

Every closed ticket gets 1-3 *theme tags* before close, drawn from a controlled vocabulary in `<project>/.claude/support-triage/vocabularies/themes.md`. The vocabulary is owner-approved and grows slowly.

Example controlled vocabulary (a real one runs ~30-60 themes):
```
auth.oauth-flow         billing.duplicate-charge      perf.cold-start
auth.password-reset     billing.invoice-format        perf.dashboard-slow
auth.sso-misconfig      billing.proration             perf.export-timeout
onboarding.first-import bugs.regression-from-X.Y      docs.api-reference
onboarding.cli-install  bugs.race-condition            docs.example-gap
onboarding.team-invite  bugs.silent-failure            docs.kb-stale
ux.confusing-CTA        feature-request.bulk-edit      ux.error-message
ux.empty-state          feature-request.export-csv     ux.notifications
ux.unclear-status       feature-request.webhooks       ux.mobile
integrations.webhook    integrations.zapier            integrations.api-rate
```

Discipline matters: a theme that exists in the vocabulary should be *named the same way every time*. The 🏷 TAG-CONSISTENCY operator enforces this at close-time. If the project has no vocabulary yet, propose tags in the outcome record; do not silently invent permanent categories mid-session.

### Step 2 — Weekly rollup

Generate a count by theme over the last 30/60/90 days and the trend:

```
THEME                        30d  60d  90d  trend
billing.duplicate-charge     12    8    7   ▲▲▲   <- accelerating
auth.sso-misconfig            9   11   10   ─    <- steady
perf.export-timeout          17   12    9   ▲▲   <- accelerating
ux.confusing-CTA              4    5    6   ─
docs.api-reference            3    7    8   ▼    <- decelerating (KB fix shipped)
feature-request.webhooks     22   24   23   ─    <- mature, real demand
```

Two patterns earn attention:
- **Accelerating themes** with rising 30d count — something changed (regression, new user cohort, new edge case). Investigate before it becomes an outage.
- **Steady high-volume themes** — even if they're "known," once they pass the project's owner-approved attention threshold they're paying for fix attention now.

### Step 3 — Triangulate against other streams

A theme is much more roadmap-worthy when it shows up in *multiple* streams:

| Theme | Tickets | NPS | Cancel reasons | Sales-lost | Public | Score |
|---|---|---|---|---|---|---|
| webhooks-missing | 22/30d | 3 mentions | 2 cancels | 4 deals lost | 1 HN | **CONVERGED — top of roadmap** |
| ux.empty-state | 4/30d | 0 | 0 | 0 | 0 | Single-stream — fix in docs/UX, not roadmap |
| perf.export-timeout | 17/30d | 1 | 1 | 0 | 1 | Triangulated — engineering priority |
| feature-request.bulk-edit | 8/30d | 1 | 0 | 0 | 0 | Single-stream — defer or quick-win only |

The convergence test prevents loud-customer bias and helps the team distinguish *vocal-minority* requests from *broad* needs.

### Step 4 — Hypothesis writing

A theme isn't actionable until it's a *hypothesis*. The hypothesis names the user, the job, and what they'd be able to do that they currently can't:

> **Theme:** webhooks-missing
> **Hypothesis:** SMB ops users (10–100 employees) trying to sync ticket events into Slack/Linear/PagerDuty currently can't, so they email us asking for Zapier templates. With first-class webhooks, time-to-first-integration drops from "support back-and-forth" to "self-serve in 15 min", which removes a known cancellation cause and a known sales-objection.
> **Verifiable signal post-ship:** webhook-missing theme drops below 5/30d within 60 days; Zapier-asking tickets stop appearing.

Without this format, themes become a wish-list. With it, they become testable bets.

### Step 5 — Loopback notification

When the roadmap ships a fix that resolves a theme, **the customers who reported under that theme get a personal notification** (see `🔁 LOOPBACK` operator). This is the highest-leverage trust deposit you can make — a single email saying "you mentioned this 6 months ago; we shipped it; here's how to use it" turns a support interaction into a marketing moment and a retention boost.

This is the loop closure that most teams skip and is the largest reason VoC mining fails to land. The customer who reported the bug doesn't see the fix; they see the next bug.

---

## NPS Verbatim Mining

Numerical NPS is noisy and survives mostly as a vanity metric. *Verbatims* are where the value is.

### Detractor verbatims (0-6)

A detractor verbatim is a *gift* — a customer about to churn telling you why. Treat each as a near-miss in safety terms.

```
[OPERATOR-LOCAL: NPS Detractor Mining]
For each detractor verbatim:
1) Tag against the theme vocabulary
2) Look up the customer's account: tier, age, last-login, ticket history
3) Decide: outreach (band 12+ on COMPENSATION-CALCULUS) or theme-only?
4) If outreach: Pipeline R (NPS Detractor) in ORCHESTRATOR-WORKFLOW.md
5) If theme-only: increment theme count; close the loop with a "thanks; we hear you" reply
```

### Passive verbatims (7-8)

The passive zone is *almost-promoter* territory. Verbatims here often name a single rough edge that, if smoothed, would convert them. Worth aggregating into a "passive friction" list and treating as a 3-month polish backlog.

### Promoter verbatims (9-10)

Promoter verbatims are marketing fuel and product-validation. Apply the **💎 KEEPER** operator: with consent, save the best for case studies, social proof, and onboarding copy. Match the customer's exact words; paraphrasing dilutes.

---

## Cancellation Reasons

The cancellation flow should ask one open question — *"what would have changed your mind?"* — and one structured one (closed-list reasons). The open answer is the gold; treat it as an NPS detractor verbatim.

A useful cancellation cohort table to maintain:

```
Reason category      30d  Avg LTV at cancel  Avg time-to-cancel
price                 8        $240              4.2 mo
missing feature      14        $880              7.8 mo   <- attention
won't work for X      6        $190              2.1 mo
better competitor     3       $1240             11.2 mo   <- attention
quality / bugs        9        $610              5.4 mo   <- attention
team change           4        $420              8.7 mo
```

The "missing feature" and "better competitor" rows often justify roadmap line items by themselves. The "team change" row almost never does — it's noise.

---

## Sales-Lost Reasons

Run-of-funnel data is missing for most early-stage projects but invaluable when present. Two diagnostic questions to ask the lost prospect (or capture from sales calls):

1. *"What were you using before / are you using now?"* → competitor mapping
2. *"What would have had to be true for us to be the obvious answer?"* → missing-feature mapping

Map findings to themes with the same vocabulary as tickets. A "missing webhooks" feature request that shows up in 4 lost deals is roadmap; the same showing up only in one pre-sales chat is not.

---

## Public Mentions

Daily scrape (or Slack-bot watch) for project name + variants on:
- X (Twitter)
- Hacker News
- Reddit (project subreddit + relevant tech subs)
- GitHub Discussions
- LinkedIn (less critical for early stage)

Three classes of mention:

| Class | Action |
|---|---|
| Product praise | 💎 KEEPER (with permission) |
| Constructive criticism with details | Add to theme tags; respond if appropriate |
| Hostile or viral negative | 🪧 BROADCAST or owner-led private outreach (per HOSTILE-USER runbook) |

For viral negative mentions specifically, the *non-action* of staying silent often costs more than a measured public reply. For incident-related public mentions, route through [STATUS-PAGE.md](STATUS-PAGE.md) and [runbooks/OUTAGE-COMMS.md](runbooks/OUTAGE-COMMS.md). For abusive or targeted public mentions, route through [runbooks/HOSTILE-USER.md](runbooks/HOSTILE-USER.md). Do not create a second public-comms doctrine in this file.

---

## The Monthly VoC Synthesis

Once per month, the triage owner produces a one-page VoC synthesis that combines all five streams. Format:

```
[Project] VoC Synthesis — [YYYY-MM]

TOP 5 THEMES (by triangulated score)
1. webhooks-missing       <- converged across all 5 streams; recommend roadmap
2. perf.export-timeout    <- accelerating in tickets; one cancel; engineering this sprint
3. billing.duplicate-charge <- declining post-fix; close-the-loop emails to affected users
4. auth.sso-misconfig     <- steady; KB article gap (not roadmap)
5. ux.empty-state         <- low volume but high CES impact

CHURN-DRIVING THEMES (cancellation evidence)
- missing webhooks (2 cancels, $X LTV at risk going forward)
- bug regression (1 cancel; structural fix shipped)

NPS DELTA: +3 over month (-1 detractor, +4 promoters)
Detractor primary themes: webhooks-missing, billing.duplicate-charge, perf.export-timeout

RECOMMENDED ACTIONS
- Roadmap: First-class webhooks (CRX-431; targeting Q3)
- Engineering: perf.export-timeout deep-dive (ENG-217; this sprint)
- Docs: SSO troubleshooting expansion (KB-44; this week)
- Marketing: case-study with [keeper customer] on webhook workaround → eventual fix

CHANGES TO WATCH NEXT MONTH
- webhooks-missing should drop after CRX-431 ships in Q3
- perf.export-timeout should drop within 30 days of ENG-217
```

This document goes to the founder / PM / engineering lead. Without it, themes get re-discovered every quarter; with it, the team converges on what's actually broken.

---

## The Rule of Three

A heuristic from established support orgs: *"if three customers ask the same thing, it's a system signal."*

Mechanically:
- **3+ tickets / 7d on the same theme** → KB article candidate (`KB-FEEDBACK-LOOP.md`)
- **3+ tickets / 30d on the same theme** → docs / UX gap (sprint-level fix)
- **3+ themes / 90d converging on the same root** → roadmap candidate (quarter-level)
- **3+ users from same cohort cancelling for same reason** → emergency review

The rule of three protects against single-customer roadmap capture (one loud user gets the team to build the wrong thing) and against single-customer churn-flailing (one cancel and the team panics).

---

## Minimal Instrumentation Contract

VoC does not require a large data warehouse. It does require a few stable fields or export columns so future agents can avoid rereading every ticket from scratch:

| Field | Where | Purpose |
|---|---|---|
| `theme_tags[]` | ticket/outcome record | Controlled vocabulary for trends |
| `persona_tag` | ticket/outcome record | Register/audience calibration |
| `source_stream` | ticket, NPS, cancel, sales-lost, public | Prevents one stream from dominating |
| `sentiment_or_stage` | outcome record | Rage-cycle / detractor / promoter context |
| `loopback_needed` | outcome/theme record | Customers who should hear when fixed |
| `loopback_sent_at` | outcome/theme record | Prevents duplicate follow-up |
| `keeper_consent` | testimonial/verbatim record | Public vs internal-only evidence |

For a custom SaaS ticketing system, these can be columns, JSON fields, or analytics events. For GitHub/OSS, they can be labels plus outcome records. For third-party helpdesks, they can be custom fields. The representation is local; the semantics should stay stable.

---

## How This File Plugs In

| Used by | How |
|---|---|
| 🏷 TAG-CONSISTENCY operator | Theme vocabulary discipline |
| 📈 OUTCOME records | Theme tags exported to weekly rollup |
| 🧬 EVOLVE operator | Triangulated themes promote to product proposals |
| 🔁 LOOPBACK operator | Notifications when themes get fixed |
| Pipeline R (NPS Detractor) | NPS verbatim mining |
| Pipeline V (VoC Mining) | Monthly synthesis |
| 10-metrics.md | Theme-count dashboards |
| 09-knowledge-base.md | Themes that become KB articles |

---

## Cross-References

- [KB-FEEDBACK-LOOP.md](KB-FEEDBACK-LOOP.md) — the docs-side loop
- [METRICS-AND-DASHBOARDS.md](METRICS-AND-DASHBOARDS.md) — theme-count dashboards
- [KNOWLEDGE-BASE.md](KNOWLEDGE-BASE.md) — KB ROI and deflection surface
- [STATUS-PAGE.md](STATUS-PAGE.md) and [runbooks/OUTAGE-COMMS.md](runbooks/OUTAGE-COMMS.md) — incident-related outreach when themes get fixed
- [runbooks/HOSTILE-USER.md](runbooks/HOSTILE-USER.md) — abusive or targeted public mentions
