# WIRING-OBSERVABILITY

If the SaaS does not have GSC, Bing Webmaster, GA4, CrUX access, or Lighthouse CI in repo, wire them now. SEO without measurement is guesswork.

## Google Search Console

### Verification

Domain property is preferred over URL-prefix property — covers all subdomains and protocols.

```text
1. https://search.google.com/search-console → Add property → Domain
2. Enter: example.com
3. Add the TXT record to DNS (Cloudflare / Route 53 / Vercel)
4. Wait propagation; click Verify
```

### Sitemap submission

```text
Sitemaps → Add new sitemap → https://www.example.com/sitemap.xml
```

For sites with sitemap-index, submit the index URL; GSC discovers per-segment children.

### Bulk export to BigQuery (T3+)

`Settings → Bulk data export → Connect → choose project / dataset / region`. Provides 12 days of history including queries omitted from the UI tables. ≈$5/month for typical SaaS.

### Required reports (review weekly initially, monthly later)

- Coverage / Indexing
- Performance (16-month trailing)
- Sitemap status
- Page experience / CWV (mobile + desktop)
- Manual actions
- Enhancement reports per structured-data type
- Crawl stats (T3+)

## Bing Webmaster Tools

```text
1. https://www.bing.com/webmasters → Add site
2. Verify via XML file, meta tag, or DNS
3. Submit sitemap
4. (Optional) Import GSC properties to bootstrap
```

For most SaaS, Bing is < 5 % of organic; for some verticals (regulated, enterprise IT, sometimes B2B) it is 10–15 %. Worth the 30 minutes regardless.

## GA4

If GA4 is not present, use `/ga4` skill. Otherwise verify:

- [ ] Measurement ID set in env (`NEXT_PUBLIC_GA_ID`).
- [ ] `<GoogleAnalytics />` component mounted in `app/layout.tsx` after consent.
- [ ] Conversion events configured: `signup`, `trial_start`, `paid_conversion`, `demo_booked`, `lead_form_submit`.
- [ ] Custom dimensions for landing-page template, traffic source category.
- [ ] Cross-domain measurement set up if marketing/app split.
- [ ] Enhanced measurement: scroll, outbound clicks, file downloads, video, site search.

## CrUX (Chrome User Experience Report)

Free; provides field CWV data — the actual ranking signal.

API key: https://console.cloud.google.com/apis → Create project → Enable Chrome UX Report API → API key.

Per representative URL:

```bash
curl -X POST "https://chromeuxreport.googleapis.com/v1/records:queryRecord?key=$CRUX_KEY" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://www.example.com/pricing","formFactor":"PHONE"}' \
  | jq '.record.metrics.interaction_to_next_paint'
```

Save outputs under `analyses/crux/<date>/<urlhash>.json`. Track p75 INP / LCP / CLS over time.

If a URL has no CrUX entry, fall back to origin-level data (`origin` parameter instead of `url`).

## Lighthouse CI in repo

Add to GitHub Actions:

```yaml
# .github/workflows/lighthouse.yml
name: Lighthouse
on:
  pull_request:
    paths:
      - 'app/**'
      - 'next.config.*'
      - 'middleware.*'
jobs:
  lhci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: oven-sh/setup-bun@v2
      - run: bun install --frozen-lockfile
      - run: bun run build
      - run: bun run start &
      - run: bunx wait-on http://localhost:3000
      - run: bunx @lhci/cli@latest autorun
        env:
          LHCI_GITHUB_APP_TOKEN: ${{ secrets.LHCI_GITHUB_APP_TOKEN }}
```

`lighthouserc.json` — points at the representative URL set, asserts INP < 200 ms, LCP < 2.5 s, CLS < 0.1, normalized performance `score_0_1000 >= 900` mobile (raw LHCI API `minScore: 0.9`).

## Schema validation in CI

```yaml
# .github/workflows/schema.yml
name: Schema
on: pull_request
jobs:
  schema:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: oven-sh/setup-bun@v2
      - run: bun install --frozen-lockfile
      - run: bun run scripts/validate-schema.ts
```

`scripts/validate-schema.ts` fetches representative URLs, extracts JSON-LD, validates against schema.org, fails build on invalid.

## Rank tracker

Pick one and stick with it. Common: Ahrefs, Semrush, SE Ranking, Nightwatch, Mangools, Wincher (cheap), `/multi-model-triangulation` for ad-hoc.

If no budget, capture seed-keyword SERPs weekly via `scripts/serp-snapshot.ts` and store JSON for trend analysis.

## AI-citation tracking (manual / semi-automated)

Google Search Console includes AI Overviews / AI Mode traffic in Web performance data, but it does not expose a clean AI-only traffic or citation report. Use GSC for blended outcome trends and a separate citation log for source attribution.

- `scripts/serp-snapshot.ts` runs on seed queries weekly and stores SERP HTML / JSON for AI Overview or other answer-surface evidence.
- Capture which URLs are cited per platform per query, plus country, device, account state if known, screenshot / HTML path, and `last_checked`.
- Manual sample of Google AI Mode, ChatGPT, Claude, Perplexity for the same queries.
- Cross-reference referrers in GA4 / server logs for `chat.openai.com`, `chatgpt.com`, `perplexity.ai`, `claude.ai`, and other explicit AI referrers, but treat missing referrers as inconclusive.

Output: `analyses/ai-citations.csv` — date, query, platform, country, device, cited URL, position / citation slot, source evidence path, confidence.

Never label this as "AI traffic" unless the source is session/referrer data. Citation logs measure presence; GSC measures blended Search performance; referrers measure visits.

## Server log access (T3+)

Vercel: Project → Logs → Drains → Filter on `User-Agent contains "Googlebot|Bingbot|GPTBot|ClaudeBot|PerplexityBot"`.

Cloudflare: Logpush to R2 / S3 with verified-bot filter.

NGINX / self-hosted: standard combined log format; ensure `User-Agent` is captured.

Verify crawler identity (reverse-DNS forward-DNS check) before using log entries as evidence — user-agent strings are spoofable.

## Annotations

Two annotation streams:

1. `seo-changelog.md` in repo — every shipped change with date, scope, expected impact, recheck-by.
2. GA4 annotations + GSC custom comments — for traffic interpretation.

Without annotations, future traffic moves are unattributable.

## Skip conditions

Skip a layer only when:

- The user explicitly opts out (e.g. "we already use Plausible, don't add GA4").
- The data layer is genuinely irrelevant for the tier (T1 may skip log analysis).
- A specific compliance regime forbids it (rare).

Otherwise default to wiring everything.
