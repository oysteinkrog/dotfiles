# Observability Ladder

When to graduate from Phase 3's point-in-time probes to continuous
monitoring, and which rung makes sense at each workspace size.

## Rung 0: Phase 3 only (< 50 users)

- Weekly sweep + ad-hoc `health` + user reports on Mattermost UI.
- No dashboards, no alerting, no pager.
- Time cost: 30 min/week.

This is fine. Don't over-invest until the workspace size justifies it.

## Rung 1: add uptime monitoring (50-250 users)

- External uptime monitor hitting `/api/v4/system/ping` every 60 sec.
- Options: Uptime Robot (free), Better Stack, Cronitor.
- Alerts via email + push to ops Slack/Mattermost channel.
- Cost: $0-20/mo.

Catches total outages within 1-2 minutes, even if you're not looking.
Doesn't tell you *why*, just *that*.

## Rung 2: add external synthetic checks (250-500 users)

- Multi-step synthetic test: login → post a message → read it back.
  Runs every 5 min from 2-3 regions.
- Options: Better Stack, Checkly, Pingdom.
- Cost: $20-50/mo.

Catches subtle regressions (WebSocket broken but `/ping` returns 200)
that Rung 1 misses.

## Rung 3: metrics + dashboards (500-1000 users)

- Enable Mattermost's Prometheus metrics endpoint on port 8067.
- Scrape with Prometheus (self-hosted or Grafana Cloud).
- Dashboards for: connection count, post rate, WebSocket connections,
  DB query time.
- Alerts for SLO breaches.
- Cost: $0-50/mo depending on self-host vs Grafana Cloud.

Now you can see trends over hours instead of only the weekly snapshot.

## Rung 4: log aggregation (500+ users, compliance-driven)

- Ship `mattermost.log` + `nginx/access.log` + `auth.log` to Loki or
  Grafana Cloud Logs or ELK.
- Structured queries: error rate by plugin, failed login rate, 5xx rate.
- Retention driven by compliance (7 years for some regimes).
- Cost: $30-200/mo depending on volume and retention.

Needed when the audit / compliance function is real, not theoretical.

## Rung 5: tracing (very large scale)

- OpenTelemetry tracing from Mattermost + plugins + DB.
- Services: Grafana Tempo, Honeycomb, Datadog.
- Cost: $100-500+/mo.

Probably out of scope for single-host Mattermost. If you need this,
you've outgrown this skill; look at Mattermost Enterprise + HA.

## When to skip rungs

Jumping straight to Rung 3 because "we'll need it eventually" is a
common trap. Signals that you actually need a given rung:

- **Rung 1**: you've had >1 outage you didn't know about until a user reported it
- **Rung 2**: you've had >1 outage where `/ping` was green but users were affected
- **Rung 3**: you're making scaling decisions and the weekly health
  reports don't have enough granularity
- **Rung 4**: you're subject to audits requiring log evidence
- **Rung 5**: you're debugging performance issues Rung 3 can't narrow down

## Integration with Phase 3

These rungs are complementary, not replacements:

- Continuous monitoring pages on outages.
- Phase 3 ensures you can *restore* when the page fires.

The two work together: Rung 1-2 catches "is it up?", Phase 3 ensures
"can we recover if it's not?"

## Phase 3's role once you're at Rung 3+

- Still runs backups (no continuous monitoring replaces backups).
- Still runs restore-drills (no dashboard proves backups are valid).
- Still drives upgrades (metrics don't apply patches).
- Still does DR rehearsals.

Phase 3 keeps doing what it does; monitoring answers different questions.

## Cost example

A 500-user workspace on Rung 3:

- Phase 3 infra (AX52 + Postmark + R2): ~$90/mo
- Uptime Robot Pro: $7/mo
- Grafana Cloud free tier (Prometheus + Loki): $0/mo for light use
- **Total**: ~$97/mo

Compared to Slack's $75,000/year: still 98% cheaper.
