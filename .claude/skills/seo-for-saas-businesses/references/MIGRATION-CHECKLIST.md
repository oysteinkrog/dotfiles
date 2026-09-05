# MIGRATION-CHECKLIST

Migrations are where SEO programs lose years of accumulated value. Use this when changing domain, framework, URL structure, navigation, or design system.

## Pre-launch (T-30 days minimum)

### Inventory the old site

- [ ] Crawl the old site (`scripts/crawl.ts`) — every URL, status, redirect chain, canonical, schema, title, description, internal/external link counts, content hash.
- [ ] Export GSC: 16 months of impressions/clicks per page; coverage; manual actions; sitemap; CWV.
- [ ] Export GA4: top organic landing pages, conversions, branded vs non-branded.
- [ ] Export backlinks (Ahrefs / Semrush / GSC links report) — at minimum, top 1000 by referring-domain authority.
- [ ] Export top ranking queries per page.
- [ ] Snapshot CrUX field data per template.

Save under `analyses/migration/old-site/`.

### Map old URLs to new URLs

For every valuable old URL, decide:

| Old URL fate | New URL behaviour |
|---|---|
| Direct equivalent on new site | 301 to the equivalent |
| Merged into a new combined page | 301 to the merged destination |
| Removed permanently with no replacement | 410 (or 404 if 410 isn't supported) |
| Removed but useful in archive form | Keep crawlable; explain status; link to current alternative |
| Useful to existing users but not as search result | Keep at the same URL with `noindex,follow` |

**Don't redirect retired pages to the homepage.** That behaves like a soft 404 for users and search systems.

Output: `analyses/migration/url-map.csv` — `old_url, new_url, status_code, reason, owner, test_status`.

### Preserve title / heading / canonical / schema patterns where possible

If new URLs simply have new metadata patterns, you may be diagnosing both URL changes and content changes if traffic moves. Try to preserve where you can.

### Test redirects in staging

- [ ] Crawl staging with the redirect map applied.
- [ ] Verify every old URL hits the new URL in one hop.
- [ ] Verify destinations return 200 with correct canonical.
- [ ] Verify no redirect loops.
- [ ] Verify HTTPS preservation.

### Sitemaps prepared

- [ ] New sitemap at `app/sitemap.ts` (or split index).
- [ ] Old sitemap remains accessible at the old URL until decommissioning to give Google time to re-crawl old URLs through the redirects.

### GSC change-of-address (if domain change)

- [ ] Both old and new domain verified in GSC.
- [ ] Submit change-of-address tool in GSC for the old property pointing at the new property.

### Annotation

- [ ] `seo-changelog.md` entry prepared with launch date, URL-map summary, expected impact, recheck-by.

## Launch day

- [ ] Deploy.
- [ ] Verify a sample of redirects in production immediately.
- [ ] Submit new sitemap in GSC.
- [ ] Resubmit Bing sitemap.
- [ ] Annotate GSC + GA4 with launch timestamp.
- [ ] Begin daily monitoring of: GSC coverage, traffic, conversions, server logs (5xx for crawlers), CrUX field data.

## Post-launch (next 30 days)

- [ ] Daily: GSC URL inspection on top 20 redirected URLs; verify Google fetched and recognized the redirect.
- [ ] Daily: 5xx / 4xx spike check for verified Googlebot.
- [ ] Weekly: traffic comparison vs pre-launch baseline by segment.
- [ ] Weekly: top losing pages diagnosed by segment.
- [ ] Monitor backlink targets — emails to top referring sites notifying URL change can speed updates.

## Post-launch (30–90 days)

- [ ] CrUX field data delta: should be at least neutral; investigate regressions.
- [ ] GSC enhancement reports: any new errors after migration?
- [ ] Sitemap submitted vs indexed delta — should approach pre-launch baseline.
- [ ] Branded vs non-branded recovery curve — branded should be near-baseline within 14 days; non-branded may take longer.

## When to declare the migration complete

- [ ] Indexed page count within 5 % of pre-launch.
- [ ] Organic traffic within 10 % of pre-launch baseline (after seasonality).
- [ ] No outstanding redirect / canonical / schema regressions.
- [ ] All beads / tickets closed.
- [ ] Old URLs have been crawled at least once in the new state by Googlebot.

## Common migration regressions

- All-to-homepage redirects (soft-404 storm).
- Lost canonical signals (new canonical patterns disagree with redirects).
- Lost internal link structure (new IA breaks pillar/cluster relationships).
- New CMS strips structured data.
- New CMS injects different metadata generation logic.
- Locale routing changes break `hreflang` reciprocity.
- New CDN cache rules serve stale metadata.
- New WAF challenges verified search crawlers.
- New consent banner regresses CWV / hides primary content.
- Decommissioned subdomain (e.g. blog moved from `blog.example.com` to `example.com/blog`) without DNS-level redirects.
- Old sitemap not redirected — Google keeps trying to crawl URLs at the old location for weeks.
- Both new and old URLs indexed for a window — duplicate cluster confusion.

## When to separate variables

If a redesign changes both URL structure *and* presentation, split the changes if possible. Diagnosing a traffic drop is much harder when multiple major variables changed simultaneously.
