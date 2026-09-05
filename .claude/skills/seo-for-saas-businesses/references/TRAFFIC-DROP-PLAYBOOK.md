# TRAFFIC-DROP-PLAYBOOK

When organic traffic drops, resist rewriting the whole site immediately. Diagnose first.

## Step 1 — Confirm tracking did not break

Before assuming a real drop:

- [ ] GA4 still receiving events (check today vs yesterday vs same-day-last-week).
- [ ] GSC performance API returning data.
- [ ] Server logs show traffic patterns matching analytics.
- [ ] Consent banner or cookie change in the last 30 days?
- [ ] Tag Manager / GTM container change?
- [ ] Bot filter change in analytics?

A measurement bug looks identical to a real drop in a chart. Always check tracking first.

## Step 2 — Separate branded from non-branded

In GSC Performance:
- Filter queries containing brand name (and common misspellings).
- Plot branded vs non-branded clicks and impressions over the relevant window.

| Pattern | Diagnostic branch |
|---|---|
| Both down | Site-wide quality / spam policy / manual action / infrastructure |
| Branded down, non-branded up | Brand crisis, product issue, reputation event, autocomplete change |
| Non-branded down, branded up | Algorithm shift, content quality classifier, competitive loss, AI Overview compression |
| Branded up, non-branded up, but conversions down | Page-level UX / offer / pricing / form regression |
| Localized to one country | Locale routing change, country-specific SERP feature change, regional outage |
| Localized to one device | Mobile / desktop layout regression, mobile-only template breaking |
| Localized to one template | Template-level regression (the most common case) |

## Step 3 — Compare year over year

90-day window comparison can mask seasonality. Compare:
- 7 days before vs 7 days after (sharp).
- 28 days before vs 28 days after (medium).
- 90 days before vs 90 days after (broad).
- Same period last year (seasonality).

If the drop disappears at YoY, the cause is seasonal. Document and watch.

## Step 4 — Segment by page type, query, country, device, search appearance

Segment by:
- Page type (commercial / editorial / docs / programmatic).
- Query intent (commercial / informational / branded / non-branded).
- Country (US / UK / DE / IN…).
- Device (mobile / desktop / tablet).
- Search appearance (web / image / video / news / discover / AI Overview).

The drop is almost always concentrated. Find the segment.

## Step 5 — Decide which dimension dropped

| Dropped | What happened |
|---|---|
| Impressions | Indexation, ranking, query demand, SERP layout, or seasonality |
| Clicks but not impressions | CTR — snippet, SERP layout (more ads, more AI Overview compression), brand demand, intent shift |
| Rankings | Algorithm update, competitive movement, content quality classifier, technical regression |
| Conversions but not traffic | Page UX, offer change, form regression, analytics break |

## Step 6 — Search Console diagnostics

- [ ] Coverage report: any sudden change in `Excluded` or `Crawled, currently not indexed`?
- [ ] Sitemap status: errors? Submitted vs indexed delta?
- [ ] Manual actions: any received?
- [ ] Page Experience: any CWV regression?
- [ ] Enhancement reports: any spike in invalid items?

## Step 7 — Recent deployments / config changes

In `seo-changelog.md`, GA4 annotations, and git history:
- Routing changes?
- Rendering changes (SSR ↔ CSR ↔ RSC)?
- Robots / canonical changes?
- CMS changes?
- Outages?
- CDN / WAF / bot protection changes?
- Consent banner changes?

## Step 8 — SERP inspection for layout changes

Sample priority queries via `scripts/serp-snapshot.ts`. Compare to baseline:
- New SERP features (AI Overview, video, product, local)?
- New competitors in top 10?
- Ad density change?
- Intent shift visible (e.g. SERP now shows tools when it used to show articles)?

## Step 9 — Server logs for crawl anomalies

T3+ only:
- Verified Googlebot / Bingbot fetch volume vs baseline.
- 5xx / 4xx for crawlers.
- Blocked render-critical assets.
- Crawl traps activated by parameter or filter changes.

## Step 10 — Define a fix or monitoring plan by segment

The wrong fix slows recovery. A precise diagnosis is faster than a large rewrite.

| Drop pattern | First action |
|---|---|
| CTR drop with stable rankings | Snippet rewrite; SERP layout review; brand demand check |
| Impressions drop after release | Technical regression — Phase 3 audit on the affected segment |
| Rankings drop on one template | Quality / freshness / proof / format review on that template |
| Conversion drop with stable traffic | UX / offer / form / analytics |
| One-country drop | Locale routing review |
| Manual action received | Follow remediation in GSC; do not rewrite the site reactively |

## Core update specific (`core-update` mode)

When a confirmed broad core update overlaps the drop window:

1. **Mark the update window** in analytics and GSC annotations.
2. **Compare 7 / 28 / 90 days before/after** with year-over-year context.
3. **Segment by page type, query intent, brand/non-brand, country, device, search appearance.**
4. **Identify whether the drop is concentrated** in a template, topic cluster, freshness class, or competitor set.
5. **Inspect winners and losers in the same SERPs** for format, depth, proof, freshness, trust, media, tools, and user-satisfaction signals visible on the page.
6. **Check recent technical changes before attributing to content quality.**
7. **Improve weak page families systematically** — not scattered cosmetic edits.
8. **Track recovery by segment.** Don't wait for another broad update to learn whether users improved.

Core-update work should produce a quality roadmap, not a panic rewrite. The strongest response is: more useful, better evidenced, easier to navigate, more satisfying for the intent each page targets.

## Don't

- Rewrite the homepage hoping the drop reverses.
- Add `noindex` to "underperforming" pages without diagnosis.
- Disavow links reactively.
- Change the CMS during a drop investigation.
- Submit a reconsideration request without evidence of remediation.
- Accept "the algorithm changed, nothing to do" as a final answer — there is always a segment-level diagnosis.
