# Post-Incident Retro

After every incident — outage, data loss, security event, hostile-user spiral, or pattern of related tickets — run a blameless retro. The goal isn't to assign fault; it's to ensure the next incident is preventable, less severe, or better-handled.

## When To Retro

| Trigger | Within |
|---|---|
| Public outage | 72 hours |
| Data loss (any size) | 7 days |
| Security disclosure | 14 days (after fix shipped) |
| Hostile-user public-thread spiral | 7 days |
| Refund > $X (project default: $500) | 7 days |
| 3+ tickets on same root cause within 14 days | 14 days |
| Recurring class of mistake from agent | 14 days |
| SLA breach > 50% in a single week | 7 days |

If in doubt, retro it. The marginal cost of a retro that wasn't strictly necessary is small; the cost of skipping a needed retro is large.

## Blameless Retro Format

```markdown
# Retro — <event title> — <date>

## Summary (1 paragraph)
What happened, in plain language. No jargon. Could be read by a board
member.

## Timeline (UTC)
- HH:MM — <event>
- HH:MM — <detection>
- HH:MM — <triage>
- HH:MM — <mitigation start>
- HH:MM — <mitigation effective>
- HH:MM — <full resolution>
- HH:MM — <comms sent>

## Impact
- Customers affected: <count + tier breakdown>
- Tickets generated: <count>
- Revenue impact: <if applicable>
- Trust impact: <social mentions, churn signal, NPS detractor count>
- SLA breaches: <count>

## What Went Well
At least 3 items. The retro is an honest accounting, not just a list of
mistakes. Examples:
- Detection was 2 minutes after first error
- The runbook was followed without ambiguity
- Status page was updated within 5 minutes

## What Went Wrong
At least 3 items. Specific. Blameless ("the alert didn't fire" not
"Alice missed it").
- Alert threshold was set higher than the SLO required
- Runbook had a stale step referring to a removed CLI flag
- We learned about the issue from Twitter, not monitoring

## Root Cause(s)
Use the Five Whys. Stop when you hit something you can change.

Why did the API return 500s? — Database returned a timeout.
Why did the database time out? — Connection pool was exhausted.
Why was the pool exhausted? — A long-running cron held connections.
Why didn't we catch the cron? — No alert on connection-pool depth.
Why no alert? — We never anticipated this failure mode.

→ Root cause: missing alert on connection-pool depth + cron not using a
   pool-bounded connection.

## Contributing Factors (not root cause but made it worse)
- Status page didn't auto-update from monitoring
- Owner was traveling; secondary on-call was unfamiliar with the cron

## Action Items (≤ 5, with owners + due dates)
- [ ] Add `db_pool_depth > 80%` alert — owner: <name> — due: <date>
- [ ] Refactor cron to use bounded connection — owner: — due:
- [ ] Add status-page automation from PagerDuty — owner: — due:
- [ ] Train secondary on-call on cron architecture — owner: — due:
- [ ] Update runbook with this scenario — owner: — due:

## Customer Comms
- Status page: <link>
- Email to affected: <sent yyyy-mm-dd, n recipients>
- Postmortem published: <link, if public>
- Comp / credit issued: <total>

## Public Postmortem
<link if published, or "internal-only because <reason>">

## Reviewers
- <name> (incident commander)
- <name> (eng lead)
- <name> (owner)

## Status
- [ ] All action items have owners
- [ ] All action items have due dates
- [ ] All action items are tracked in <issue tracker>
```

## Five Whys: Avoid Rabbit Holes

The Five Whys can over-fit ("why did the developer write the bug? — they're tired"). Stay in process / system / signal territory:

| Good "why" | Bad "why" |
|---|---|
| Why didn't the alert fire? | Why didn't the developer notice? |
| Why isn't this scenario in the runbook? | Why didn't the agent think harder? |
| Why was the deploy unblocked? | Why did Alice approve the PR? |

Stop the Whys when you hit:
- Missing instrumentation
- Process gap
- Outdated documentation
- Architectural choice that needs revisiting
- A genuine "we couldn't have anticipated this" (rare but real)

Don't stop at "human error." That's almost never the actionable layer.

## Blameless Language

| Avoid | Prefer |
|---|---|
| "Alice deployed broken code" | "The deploy was approved without the regression check we now know we needed" |
| "Bob missed the alert" | "The alert routing didn't reach the on-call who was awake at the time" |
| "The team didn't follow the runbook" | "The runbook had a step that didn't match the current system state" |
| "The customer was confused" | "The error message didn't communicate what the customer needed to do" |

Names go in the action-item ownership column, not in the root-cause narrative.

## Public Vs Internal Postmortem

A **public postmortem** can be a trust-builder:
- Shows you're serious.
- Shows the system you're holding to.
- Quoted positively for years.

But not all retros should be public:

| Public when | Internal-only when |
|---|---|
| Customers were impacted | Single-customer issue |
| Trust-recovery is in play | Internal-only outage (e.g., admin tool) |
| You want to set an industry tone | Sensitive vendor involvement |
| Action items are commitments to customers | Security details that haven't been mitigated yet |

Public postmortem template:

```markdown
# What happened on <date>

## Summary
<1 paragraph plain-language>

## What you experienced
<from customer perspective>

## What we did to resolve it
<chronological, plain language>

## Why this happened
<root cause, plain language>

## What we're doing to prevent recurrence
<action items, with timelines>

## If you were affected
- <how to claim credit, if any>
- <where to ask further questions>

— <owner name>
```

## Anti-Patterns

| Don't | Why |
|---|---|
| Skip the retro because the incident was small | Patterns surface across small incidents — the next one is bigger |
| Action items without owners + dates | They will not get done |
| 20 action items | None will get done; pick top 5 |
| Use the retro to assign blame | Discourages future honest reporting |
| Run the retro with only engineering | Support sees what eng misses; include them |
| Publish the retro and never review action items | Customer remembers; "we said we'd fix X — did we?" |
| Skip "what went well" | Demoralizing AND you stop reproducing what worked |
| Write the retro in real-time during the incident | Distracts from resolution |

## Closing The Loop

Action items should be tracked in your issue tracker (br/Linear/GitHub Issues), not just buried in the retro doc. A weekly check on overdue retro action items is a high-leverage habit.

Quarterly: re-read the last quarter's retros. Are the same root causes recurring? That's a meta-signal — fix the meta-process.

## Companion Refs

- [STATUS-PAGE.md](STATUS-PAGE.md) — public comms during the incident
- [OUTAGE-COMMS.md](runbooks/OUTAGE-COMMS.md) — message templates
- [METRICS-AND-DASHBOARDS.md](METRICS-AND-DASHBOARDS.md) — measuring the impact
- [FAILURE-MODES.md](FAILURE-MODES.md) — the catalog this might add to
