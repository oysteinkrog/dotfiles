# Status Page — Setup, Lifecycle, Comms

A public status page is a trust artifact. Done well, it deflects tickets during incidents and proves uptime claims. Done badly, it's a worse-than-nothing liability — green when customers are reporting outages, "all systems operational" with no support-response signal.

## When You Need One

- ≥ 100 paying customers (below this, individual outreach beats a status page)
- Any enterprise tier (procurement asks for it)
- API product (third-party integrations watch your status)
- Multi-system architecture where parts can fail independently

## What To Cover

A status page lists **components** (things that can be up or down independently). Pick 4-8 components, no more.

| Component | Probe | Why it's separate |
|---|---|---|
| API | Synthetic check on `/api/health` | Customers integrate against this |
| Web | Synthetic check on landing page | First impression / signups depend on it |
| Auth | Synthetic check on login + token refresh | Login outages have outsized impact |
| Database | Read + write probe | Often the silent failure root cause |
| Webhooks | Send + verify deliver loop | Webhook drops cause silent customer failures |
| Email | Send-and-receive against monitored mailbox | Auth/reset/notification delivery |
| Payments | Stripe/PayPal API health | Customer-visible if they hit checkout |
| **Support response** | FRT P90 vs target | THE key signal — see below |

The "Support response" component is the most-overlooked. Without it, you can show "all green" while the support queue is buried. Track it.

## The Support-Response Component

```
Support response
  ✓ Healthy: FRT P90 < 4h (target)
  ⚠ Degraded: FRT P90 4-12h
  ✗ Major: FRT P90 > 12h
```

This signal pulls from your ticketing dashboard. When it goes degraded:
- Auto-publish a "high volume" status note.
- Owner gets paged.

## Hosted Vs DIY

| Tool | When it fits | Cost |
|---|---|---|
| **Statuspage.io** (Atlassian) | Mid-market, mature; deep Atlassian integration | $$$ |
| **BetterStack (Better Uptime)** | Modern, cleaner UX | $$ |
| **Instatus** | Small teams, value-priced | $ |
| **Cachet** (self-hosted, OSS) | OSS projects, full control | $ |
| **Custom Next.js page** | Have engineering capacity, want control | engineering time |

If you have an admin dashboard already, a custom status page is ~2 days of work and avoids vendor lock-in.

## Lifecycle Of An Incident On The Status Page

### Stage 1 — Investigating (within 5 min of detection)

```
[Investigating] We're investigating reports of <symptom>. Customers may
experience <impact>. Updates within 30 minutes.

Components affected: API
Posted: <timestamp>
```

**Don't speculate on cause.** Just state what you've observed.

### Stage 2 — Identified (when root cause found)

```
[Identified] <Root cause in plain language>. We're deploying a fix.
ETA: <conservative estimate, with buffer>.

Components affected: API
Updated: <timestamp>
```

### Stage 3 — Monitoring (after fix deployed)

```
[Monitoring] Fix is deployed. Recovery confirmed for <X>% of probes.
We're watching for an hour to confirm full resolution.

Components affected: API
Updated: <timestamp>
```

### Stage 4 — Resolved (after monitoring period)

```
[Resolved] All systems operational. We'll publish a postmortem
within <72h>.

Components affected: API
Resolved: <timestamp>
Total duration: <duration>
```

### Stage 5 — Postmortem (linked from the resolved entry)

See [POST-INCIDENT-RETRO.md](POST-INCIDENT-RETRO.md).

## Comms Cadence

| Severity | Update frequency | Channel |
|---|---|---|
| **Major** (full outage, >50% users) | Every 15 min until resolved | Status page + email + X + product banner |
| **Partial** (degraded, some users) | Every 30 min until resolved | Status page + email |
| **Minor** (single feature, brief) | Initial + resolution | Status page only |

**Send updates even when nothing has changed.** Silence reads as "they don't know what's going on." A "still investigating, no new info" update is fine.

## Maintenance Windows

Schedule and announce ≥ 7 days in advance. Show on the status page:

```
Scheduled: Database upgrade — Tuesday 2026-05-04 02:00 UTC (2h window)
Impact: API will be read-only between 02:00-04:00 UTC.
```

If a maintenance overruns, transition to incident mode (treat as unplanned).

## Backchannel (For Enterprise)

Enterprise customers get more than the public page:
- Direct email to a designated point-of-contact within 5 min of incident.
- Slack/Teams channel for the duration.
- Postmortem shared 48-72h after resolution.

Document this in `05-policies.md` under enterprise SLA.

## Don't Lie

The single biggest status-page sin: leaving it green during an outage to avoid embarrassment.

- Customer trust survives an outage; it does NOT survive being lied to about an outage.
- Status pages get screenshotted and quoted for years.
- "All systems operational" while the queue floods will cost you customers.

If you can't show truth on a public page, take it private. But don't lie.

## Subscriptions

Let visitors subscribe to incident notifications:
- Email
- SMS (paid, often optional)
- Webhook (for ops teams)
- Atom/RSS feed
- Slack incoming webhook

Email + RSS is the minimum.

## Anti-Patterns

| Don't | Why |
|---|---|
| Hide the page behind login | Customers can't share; trust drops |
| Show only "API" — hide all the components that can fail | Pretends the system is simpler than it is |
| Auto-resolve status updates without monitoring period | Customers see "resolved" while still hitting errors |
| Stop updating once "identified" | Customer thinks you abandoned the issue |
| Use jargon on customer-facing copy | "Increased 5xx error rates" → "More errors than usual when loading the API" |
| Public postmortem includes vendor blame | Looks like buck-passing even when true |
| Skip the postmortem for "minor" incidents | Patterns matter; the next minor is bigger |
| Don't show the support-response component | Hides the symptom that customers feel most |

## Embedding On The Product

A small banner pulled from the status-page API, shown only when status ≠ green:

```jsx
{status !== 'operational' && (
  <Banner severity={status}>
    We're investigating an issue with {component}. Updates: {' '}
    <Link href="https://status.<project>.com">status.<project>.com</Link>
  </Banner>
)}
```

This deflects tickets faster than email — the customer sees the banner the moment they hit the broken feature.

## Internal Status Page

A second, internal-only status page with:
- All public components + their detailed metrics
- DB connection counts, queue depths, error rates per service
- Recent deploys
- On-call handoff log

This is for engineers and oncall, not customers. Don't conflate the two.

## Companion Refs

- [OUTAGE-COMMS.md](runbooks/OUTAGE-COMMS.md) — exact templates for incident announcements
- [POST-INCIDENT-RETRO.md](POST-INCIDENT-RETRO.md) — what comes after resolution
- [METRICS-AND-DASHBOARDS.md](METRICS-AND-DASHBOARDS.md) — the support-response signal
- `/admin-page-for-nextjs-sites` — building the internal status surface
