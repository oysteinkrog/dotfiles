# subagent: gsc-extractor

Role: Phase 1 Google Search Console pull. Snapshot the truth of how Google currently sees the property — performance, coverage, sitemaps, manual actions, enhancements, CWV, crawl stats — into machine-readable exports the rest of the program reads.

See [PHASE-1-DISCOVERY](../references/PHASE-1-DISCOVERY.md), [WIRING-OBSERVABILITY](../references/WIRING-OBSERVABILITY.md), [TIER-ROUTING](../references/TIER-ROUTING.md).

## Inputs

- GSC property URL (domain property preferred over URL prefix).
- Auth: OAuth credentials for Search Console API, or a fallback path of CSV exports the user drops into `analyses/gsc/_raw/`.
- Tier (`T1 | T2 | T3 | T4`) — gates BigQuery bulk export and crawl-stats deep pull.
- Branded-term seed list (for branded vs non-branded split).

## Tasks

1. Verify property access. If the user is not verified, stop and route to [WIRING-OBSERVABILITY](../references/WIRING-OBSERVABILITY.md) before proceeding — do not invent baselines.
2. Pull **Performance** for the last 16 months (the API maximum) via `searchanalytics.query`. Run one query per dimension slice and persist each as a separate file:
   - `by-page.json` (dimensions: `page`)
   - `by-query.json` (dimensions: `query`)
   - `by-page-query.json` (dimensions: `page,query`)
   - `by-country.json` (dimensions: `country`)
   - `by-device.json` (dimensions: `device`)
   - `by-search-type.json` — one file per `searchType`: `web`, `image`, `video`, `news`, `discover`, `googleNews`.
   - `by-page-date.json` (dimensions: `page,date`) — for trend analysis.
3. Pull **Coverage / Index status** from `urlInspection.index.inspect` on representative URLs and the `sitemaps` API for sitemap-level coverage. Record indexed / excluded / error counts per status reason. Save to `coverage.json`.
4. Pull **Sitemaps** list via `sitemaps.list`: submitted URL, last-downloaded date, errors, warnings, contents counts. Save to `sitemaps.json`.
5. Pull **Manual Actions** via `urlInspection` and the security-issues / manual-actions surface (some signals only available in the GSC UI export — note in `manual-actions.md` if API-incomplete).
6. Pull **Enhancements** for every type Google currently exposes (Breadcrumbs, Sitelinks Searchbox status, Logos, Products, Video, Review snippets, Merchant listings, Practice problems, etc.). Per-type errors + warnings + valid counts → `enhancements/<type>.json`.
7. Pull **Core Web Vitals** report (mobile + desktop). Per-URL group: `good`, `needs improvement`, `poor` for LCP / INP / CLS. → `cwv-report.json`. Cross-check against `analyses/crux/` from `cwv-collector` later.
8. (T3+) Pull **Crawl Stats**: total crawl requests, average response time, host status, response codes, file types, bot type breakdown, purpose breakdown (refresh vs discovery). → `crawl-stats.json`.
9. (T4 or large T3) Provision **BigQuery bulk export** and confirm the daily dataset is landing — note the dataset name in `analyses/gsc/_meta.md`.
10. Compute derived datasets:
    - **Branded vs non-branded split** — partition `by-query.json` against the branded-term seed list (case-insensitive, allow common misspellings). Write `derived/branded-split.json` with clicks / impressions / CTR / position per partition + over time.
    - **Striking-distance pages** — pages in average position 4–15 with ≥ 50 impressions in the last 28 days. → `derived/striking-distance.csv`.
    - **Top winners / losers WoW** — pages with the largest absolute click delta last full week vs prior full week. → `derived/wow-winners-losers.csv`.
    - **CTR-vs-position outliers** — pages where CTR is > 1 SD below the average for their position bucket (snippet-curation candidates). → `derived/ctr-outliers.csv`.
11. Write `analyses/gsc/README.md` documenting every file, its dimensions, the date range, and the API endpoint or CSV source it came from.
12. Append every API call to `analyses/source-log.md` with timestamp + endpoint per [VERIFICATION-FIRST](../references/VERIFICATION-FIRST.md).

## Output

```
analyses/gsc/
  _meta.md
  _raw/                     # original CSVs if CSV-fallback path
  by-page.json
  by-query.json
  by-page-query.json
  by-country.json
  by-device.json
  by-search-type/{web,image,video,news,discover,googleNews}.json
  by-page-date.json
  coverage.json
  sitemaps.json
  manual-actions.md
  enhancements/<type>.json
  cwv-report.json
  crawl-stats.json          # T3+
  derived/
    branded-split.json
    striking-distance.csv
    wow-winners-losers.csv
    ctr-outliers.csv
  README.md
```

## Done when

- All 16 months of performance data are landed across the seven dimension slices, with row counts logged in `_meta.md`.
- Coverage and sitemaps reports are timestamped and parseable.
- Branded vs non-branded split sums to total clicks / impressions within ±0.5 % rounding error — divergence triggers a re-check of the branded-term list.
- Striking-distance, WoW-delta, and CTR-outlier CSVs are non-empty (or explicitly marked `n/a — too few impressions` with the threshold used).
- (T3+) Crawl-stats report includes per-bot-type breakdown.
- `README.md` lists every file, every endpoint, and every transformation applied.

## Anti-patterns

- Pulling only the last 90 days "to keep it tidy" — kills seasonality and core-update windows.
- Treating the URL-prefix property as equivalent to the domain property — they have different coverage scopes.
- Letting the branded list be a single brand string — capture misspellings, internal-product names, and the founder name when it gets branded queries.
- Computing striking distance over too short a window — a one-week burst is noise.
- Skipping the CSV-fallback path and stalling the whole program because the API integration is not wired yet.
- Reporting "no manual actions" without recording the timestamp the check ran.
