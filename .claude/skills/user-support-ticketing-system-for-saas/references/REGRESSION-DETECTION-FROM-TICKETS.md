# Regression Detection From Tickets

A spike in similar tickets is the earliest, most-reliable signal that a deploy broke something. By the time the on-call dashboard pages, your customers have been complaining for 30 minutes. The ticket queue is the front line of regression detection — wire it up.

## The Asymmetry

Engineering monitors:
- Error rates, latency, saturation
- Synthetic checks
- Trace samples
- Logs

These miss:
- Wrong-but-valid responses ("the data looks weird")
- UX regressions ("the button does nothing")
- Hidden config drift ("emails stopped going out")
- Non-fatal silent failures ("export ran but file is empty")

Tickets catch all of those because customers *experience* the regression even when the system reports OK.

## The Velocity Sentinel

Track ticket-arrival rate per category and per topic:

```ts
async function detectRegressionSpikes() {
  const window = 60 * 60 * 1000;     // 1 hour
  const baseline = await getRollingMedian("ticket_arrival_rate", { lookbackDays: 14 });
  const current = await getRecentTicketRate({ window });

  const categories = await groupByCategory(current);
  for (const [category, rate] of Object.entries(categories)) {
    const baseRate = baseline.byCategory[category] ?? 1;
    const ratio = rate / baseRate;
    if (ratio > SPIKE_THRESHOLD && rate >= MIN_VOLUME) {
      await triggerRegressionAlert({ category, rate, baseRate, ratio });
    }
  }
}
```

Tunables:
- **SPIKE_THRESHOLD**: 3.0 (3× normal volume)
- **MIN_VOLUME**: 5 tickets/hour (avoid alerting on 1→3 noise)
- Decision window: 1h with 7-day baseline; revisit weekly

## Topic Clustering

Categories are coarse. Use embedding-based clustering to find sub-topics within a category:

```ts
async function clusterRecentTickets(windowHours = 4): Promise<TicketCluster[]> {
  const recent = await getTicketsInWindow({ hours: windowHours });
  if (recent.length < 5) return [];

  const embeddings = await Promise.all(
    recent.map(t => embedText(`${t.subject}\n${t.description.slice(0, 800)}`))
  );

  // DBSCAN or HDBSCAN clustering on embeddings
  const clusters = hdbscan(embeddings, { minClusterSize: 3, minSimilarity: 0.78 });

  return clusters.map(c => ({
    tickets: c.indices.map(i => recent[i]),
    centroid: c.centroid,
    coherence: c.coherence,
    representativeQuote: extractQuote(c.indices.map(i => recent[i])),
  }));
}
```

A cluster of 5 similar tickets in 30 minutes is a strong regression signal even if no individual ticket alone is unusual.

## Correlate To Deploys

Link each detected spike to recent code/config changes:

```ts
async function attributeSpikeToDeploy(spike: RegressionSpike): Promise<DeployCorrelation> {
  const recentDeploys = await getDeploys({
    sinceTimestamp: subtractMinutes(spike.firstTicketAt, 60),
    untilTimestamp: spike.firstTicketAt,
  });

  return {
    spike,
    candidateDeploys: recentDeploys,
    likelyDeployId: scoreDeploysAgainstSpike(spike, recentDeploys)[0]?.id,
    confidence: ...,
  };
}
```

Output to engineering:

```
🚨 LIKELY REGRESSION DETECTED

Topic: "export silently produces empty file"
Tickets: 12 in past 30 min (baseline: 0.5/30 min)
First ticket: 14:32 UTC

Candidate deploys (most likely first):
  1. acme/api @ ed3f4a7 — "refactor export pipeline" (deployed 14:18)
  2. acme/web @ a91c5d0 — "tweak download button" (deployed 14:20)

Sample customer reports:
  • "I clicked export and got an empty CSV"
  • "Export download has 0 rows but my dashboard shows 200+"
  • "Just tried the export — file is empty"

[Open candidate deploy in repo] [Acknowledge] [Roll back] [False positive]
```

## Suppression Of False Positives

Spikes happen for non-regression reasons too:

| Cause | Detection | Action |
|---|---|---|
| Marketing send | Volume spike across all categories | Suppress alert |
| Status-page incident already filed | `linked_to_incident` exists | Don't double-alert |
| Customer education event ("download limits hit") | Topic cluster matches known pattern | Tag as known |
| New feature launch | Recent product changelog entry matches keywords | Reduce severity |
| Time-of-week pattern (Mondays) | DOW-adjusted baseline | Alert against DOW baseline |

```ts
async function shouldSuppressSpike(spike: RegressionSpike): Promise<{ suppress: boolean; reason?: string }> {
  if (await hasActiveIncidentForTopic(spike.topic)) return { suppress: true, reason: "already_known_incident" };
  if (await marketingSendActive(spike.windowStart, spike.windowEnd)) return { suppress: true, reason: "marketing_volume" };
  if (await isWithinNewFeatureLaunchWindow(spike.topic, spike.windowStart)) {
    return { suppress: false, reason: "new_feature_questions", severity: "info" };
  }
  return { suppress: false };
}
```

## The "First Five" Pattern

For very rare regressions, even 5 tickets is significant. Watch for "5 in 30 min on a topic that gets 0/day":

```sql
WITH ticket_topics AS (
  SELECT
    id,
    topic_cluster_id,
    created_at,
    DATE_TRUNC('day', created_at) AS day
  FROM tickets_with_clusters
  WHERE created_at > NOW() - INTERVAL '30 minutes'
),
historical_baseline AS (
  SELECT
    topic_cluster_id,
    AVG(daily_count) AS avg_per_day
  FROM (
    SELECT topic_cluster_id, DATE_TRUNC('day', created_at) AS day, COUNT(*) AS daily_count
    FROM tickets_with_clusters
    WHERE created_at BETWEEN NOW() - INTERVAL '30 days' AND NOW() - INTERVAL '30 minutes'
    GROUP BY topic_cluster_id, day
  )
  GROUP BY topic_cluster_id
)
SELECT
  rt.topic_cluster_id,
  COUNT(*) AS recent_count,
  hb.avg_per_day,
  COUNT(*) / NULLIF(hb.avg_per_day / 48.0, 0) AS rate_ratio  -- 30 min vs daily
FROM ticket_topics rt
LEFT JOIN historical_baseline hb USING (topic_cluster_id)
GROUP BY rt.topic_cluster_id, hb.avg_per_day
HAVING COUNT(*) >= 5 AND (hb.avg_per_day < 1 OR hb.avg_per_day IS NULL);
```

This catches "we never had this kind of ticket before, suddenly we have 5" — the strongest possible signal.

## Per-Surface Regression Maps

Tag tickets by which surface the customer was on:

```ts
const surfaceHints = {
  "from settings page": "settings",
  "settings menu": "settings",
  "billing tab": "billing",
  "checkout": "checkout",
  "in the dashboard": "dashboard",
  "mobile app": "mobile_app",
  "ios": "mobile_ios",
  "android": "mobile_android",
};

function inferSurface(ticketText: string): string | null {
  const lower = ticketText.toLowerCase();
  for (const [hint, surface] of Object.entries(surfaceHints)) {
    if (lower.includes(hint)) return surface;
  }
  return null;
}
```

A spike on `checkout` is much more urgent than the same spike on `dashboard` because revenue stops. Wire severity to surface:

```ts
const SURFACE_SEVERITY: Record<string, AlertSeverity> = {
  checkout: "p0",          // money path
  billing: "p0",
  signup: "p1",
  login: "p1",
  dashboard: "p2",
  settings: "p2",
  documentation: "p3",
};
```

## Engineering Hand-Off

When a regression is confirmed:

1. **Auto-create engineering issue** with linked tickets, timeline, sample quotes (per [TICKET-LINKING-AND-RELATIONSHIPS.md](TICKET-LINKING-AND-RELATIONSHIPS.md))
2. **Suggest rollback** if a candidate deploy is identified with high confidence
3. **Open status-page incident** if customer impact is broad (per [STATUS-PAGE-INTEGRATION.md](STATUS-PAGE-INTEGRATION.md))
4. **Update linked tickets** with system note: "Engineering investigating — fix in flight"
5. **Trigger war-room** if severity p0/p1 and impact wide (per [WAR-ROOM-INCIDENT-MODE.md](WAR-ROOM-INCIDENT-MODE.md))

## Severity Heuristic

```ts
function regressionSeverity(spike: RegressionSpike): "p0" | "p1" | "p2" | "p3" {
  const surfaceSev = SURFACE_SEVERITY[spike.surface] ?? "p3";
  const volumeSev = spike.ticketsPerHour >= 50 ? "p0"
                  : spike.ticketsPerHour >= 20 ? "p1"
                  : spike.ticketsPerHour >= 5  ? "p2"
                  : "p3";
  const enterpriseHit = spike.affectsEnterpriseCustomers ? "p1" : "p3";
  return [surfaceSev, volumeSev, enterpriseHit].sort(severityOrder)[0];
}
```

A small spike on the checkout surface affecting an enterprise customer is p0 even with low volume.

## Daily Regression Review

The ticket-detection system runs continuously, but a daily 15-min review keeps the org honest:

```
DAILY REGRESSION REVIEW — 2026-04-27 09:30 UTC
─────────────────────────────────────────────────

Yesterday: 3 detected spikes, all confirmed
  • 14:32 — Empty export (deploy ed3f4a7) — rolled back at 14:48 — 18 affected
  • 22:15 — Login fail on Safari 17 (config drift) — fixed at 23:02 — 8 affected
  • 23:50 — False positive: marketing send

This morning so far: 1 spike pending review
  • 08:42 — "billing email not received" — 6 tickets — investigating
```

Repeat regressions, missed detections, and false-positive rate are the metrics for tuning the system.

## Post-Detection Tagging

Every confirmed regression gets a backfilled tag on its tickets:

```ts
{
  themeTags: ["regression"],
  regressionId: "REG-2026-04-27-001",
  regressionConfirmedAt: ...,
  regressionResolvedAt: ...,
  rootCauseDeploy: "ed3f4a7",
}
```

This enables learning: per [POSTMORTEM-AND-LEARNING-LOOPS.md](POSTMORTEM-AND-LEARNING-LOOPS.md), regression patterns inform code review focus, test coverage gaps, and pre-deploy gates.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Threshold-only on raw counts | High-volume products always look noisy; ratio matters |
| No baseline = false alarms | Friday afternoon at the same volume as Monday morning |
| Alerting on every cluster | Alert fatigue; on-call mutes; misses real regression |
| No deploy correlation | Engineer wastes time guessing what changed |
| Ignoring the "first five" pattern | Rare-topic regressions slip past volume gates |
| Same severity for checkout vs help-page | Money-path regression treated as routine |
| Not back-tagging tickets | Can't compute regression-percent of total volume |
| Detection runs daily not hourly | 23h regression window before alarm |
| Suppression rules opaque | Marketing send gets blamed; no visibility |
| No false-positive feedback | Same false patterns trigger week after week |

## Wire Points Checklist

- [ ] Cron job hourly detecting category- and topic-level spikes
- [ ] Topic clustering on embeddings with rolling 14-day baseline
- [ ] Deploy correlation (CD pipeline metadata available)
- [ ] Suppression rules: incidents, marketing sends, new launches, DOW
- [ ] Per-surface severity mapping
- [ ] First-five pattern (rare-topic alarm)
- [ ] Auto-engineering-issue with linked tickets and quotes
- [ ] Status-page integration on broad impact
- [ ] War-room trigger on p0/p1 + wide impact
- [ ] Daily regression review report
- [ ] Back-tagging of confirmed regressions
- [ ] False-positive feedback loop (one-click "false positive")
- [ ] Test: 5 similar tickets in 30 min → spike detected
- [ ] Test: marketing send → suppressed
- [ ] Test: deploy at T-15min before spike → correlation surfaced
