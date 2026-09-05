# PHASE 8 — ANALYTICS, DASHBOARDS & REPORTING

Goal: one place to see organic health; weekly self-serve report; monthly exec cockpit; alerts for material movement.

## Wiring

See [WIRING-OBSERVABILITY](WIRING-OBSERVABILITY.md). Phase 8 assumes wiring is in place; this phase consumes the data and turns it into decisions.

## Dashboard widgets

Group by audience.

### Engineering / SEO operator weekly view

| Widget | Source | Refresh |
|---|---|---|
| Indexed-page count by sitemap segment | GSC | daily |
| Coverage warnings | GSC | on change |
| Manual actions | GSC | on change |
| Enhancement errors per type | GSC | daily |
| Sitemap submitted vs indexed delta | GSC | daily |
| INP / LCP / CLS p75 by template | CrUX | daily |
| Lighthouse CI delta on representative URLs | LHCI | per PR |
| Schema validation pass/fail | scripts/validate-schema.ts | per PR + nightly |
| Internal-link health (orphans, redirect-through count) | scripts/internal-links.ts | nightly |
| Crawl error spike (5xx, 4xx for verified bots) | server logs (T3+) | daily |

### Marketing / content view

| Widget | Source | Refresh |
|---|---|---|
| Impressions and clicks per cluster | GSC | weekly |
| CTR by template | GSC | weekly |
| Average position by cluster | GSC | weekly |
| Branded vs non-branded split | GSC | weekly |
| Top 10 winning / losing pages WoW | GSC | weekly |
| Organic-to-trial conversion by landing page | GA4 | weekly |
| AI citation presence / share-of-voice | analyses/ai-citations.csv + SERP snapshots | weekly |
| Striking-distance pages (avg pos 4–15) | GSC | weekly |

### Executive cockpit (monthly)

| Metric | Definition |
|---|---|
| Organic revenue / qualified leads / trials / demos | GA4 + CRM |
| Branded vs non-branded movement | GSC % delta |
| Top winning and losing page types | GSC by template |
| Indexation health | Sitemap submitted / indexed |
| Technical incidents or release risks | seo-changelog + GSC |
| Content shipped, refreshed, merged, removed | analyses/content-inventory.md |
| Links / mentions earned | beads / outreach tracker |
| Conversion movement by landing-page type | GA4 |
| AI visibility notes | Citation log + GSC Web caveat |
| Key risks and blockers | running list |
| Next month's highest-leverage work | top 3 prioritized |

## AI measurement contract

Keep AI visibility metrics separated by source; do not collapse them into one "AI traffic" number.

| Question | Best source | Caveat |
|---|---|---|
| Did organic demand move? | GSC Performance, Web search type | Includes AI feature traffic but does not expose a clean AI-only segment. |
| Was the SaaS cited in an answer surface? | `analyses/ai-citations.csv`, SERP snapshots, manual/browser captures | Sampled, query-set dependent, and volatile; store date, country, device, platform, query, cited URL, and screenshot / HTML path. |
| Did answer surfaces send sessions? | GA4 / PostHog / Plausible referrers and server logs | Referrers are incomplete and platform behavior changes. |
| Did a content edit plausibly move citations? | Citation log before/after plus GSC trend and annotation | Treat as `likely` unless sample size and controls support a stronger claim. |

Dashboard rule: every AI row must include `metric_source`, `sample_size`, `last_checked`, and `confidence`. If GSC is the source, label it `blended_web`, not `ai_only`.

## KPI targets

Set per tier; review every 90 days:

| Tier | INP p75 | Indexation rate | Org-to-trial CR | Branded share growth |
|---|---|---|---|---|
| T1 | < 200 ms commercial | > 90% of submitted | > baseline | establish |
| T2 | < 200 ms commercial | > 95% | > baseline + 20% | +10% YoY |
| T3 | < 150 ms commercial | > 95% | > baseline + 30% | +15% YoY |
| T4 | < 150 ms all marketing | > 98% | maintain | +20% YoY |

## Reporting cadence

### Weekly self-serve report

`deliverables/weekly-report-template.md`:

```md
# Week of <date>

## Top movers
- ↑ <page>: +<N>% clicks WoW. Likely cause: <hypothesis>.
- ↓ <page>: -<N>% clicks WoW. Likely cause: <hypothesis>.

## Indexation
- Submitted: <N>
- Indexed: <N>
- Delta this week: <±N>

## CWV health (representative URL p75)
- LCP / INP / CLS by template — show table

## Shipped this week
- <PR list with audit IDs>

## Next week
- <top priorities>

## Open issues
- <blockers>
```

### Monthly executive cockpit

`deliverables/monthly-exec-template.md` — see assets directory.

## Alerts

Set up alerting on:
- Manual action received → page immediate response.
- Indexation drop > 10% week-over-week → page within 24h.
- Top-50 commercial query position drop > 3 places → notify within 24h.
- Sitemap submission failure → notify within 6h.
- INP p75 > 200 ms on commercial template (CrUX) → notify within 24h.
- AI citation lost on tracked priority query → weekly digest, with platform and screenshot / HTML evidence.

## Annotations

Two streams:
1. `seo-changelog.md` in repo — every shipped change with date, scope, expected impact, recheck-by.
2. GA4 + GSC annotations — for traffic interpretation.

Without annotations, future traffic moves are unattributable. This is non-negotiable.

## Anti-patterns

- Vanity reporting (rank-tracker screenshots without context or decisions).
- Mixing GSC clicks and GA4 sessions in the same chart without explanation.
- Treating CrUX field data and Lighthouse lab data as interchangeable.
- Ignoring data caveats (consent, attribution, query anonymization).
- Treating GSC Web clicks as a directly segmentable AI Overview / AI Mode metric.
- Waiting until the monthly review to react to indexation drops.
- Reporting that does not drive decisions.
