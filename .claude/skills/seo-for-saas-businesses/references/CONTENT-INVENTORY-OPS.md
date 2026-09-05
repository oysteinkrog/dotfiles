# CONTENT-INVENTORY-OPS

Building and maintaining `analyses/content-inventory.md` (and its CSV companion). The inventory is the source of truth for which URL exists, who owns it, what intent it serves, what state it's in, and what the next action is. Without it, Phase 4 content work, decay sweeps, and quarterly reviews all guess.

## Phase mapping

| Phase | Use this doc for |
|---|---|
| 1 — Discovery | Build initial inventory from sitemap + crawl + GSC. |
| 4 — Content | Per-row briefs, refresh triggers, decay flags. |
| 5 — IA | Cluster mapping, query-family ownership. |
| 8 — Analytics | GA4 / GSC export joins to update traffic + conversions. |
| 13 — Compounding | Quarterly review; merge / redirect / noindex / remove decisions. |

## CSV schema

`analyses/content-inventory.csv` (versioned in repo or in a single source-of-truth Sheets / Notion table that exports to CSV):

| Column | Type | Description |
|---|---|---|
| `url` | string | Canonical URL (no UTM, trailing slash matches site convention) |
| `type` | enum | `commercial` / `editorial` / `programmatic` / `legal` / `support` / `gated` |
| `template` | string | Which template renders it (e.g. `integration-detail`, `blog-post`) |
| `owner` | string | Named human accountable for the page |
| `intent` | enum | `informational` / `commercial-investigation` / `transactional` / `navigational` |
| `query_family` | string | Primary query family this URL owns (one canonical owner per family) |
| `funnel_role` | enum | `awareness` / `consideration` / `decision` / `retention` / `none` |
| `index_state` | enum | `indexed` / `noindex` / `disallowed` / `excluded` (per GSC) |
| `canonical` | string | The `<link rel="canonical">` value (often = `url`) |
| `last_update` | date | When content meaningfully changed (not deploy date) |
| `next_review` | date | Scheduled re-review (quarter-aligned for editorial; cadence-driven for programmatic) |
| `traffic_28d` | int | Clicks from organic over last 28 days (GSC) |
| `impressions_28d` | int | Impressions over last 28 days (GSC) |
| `position_avg` | float | Average position over 28 days |
| `conversions_28d` | int | Conversions attributed (GA4) |
| `links_internal` | int | Inbound internal links |
| `links_external` | int | Inbound external links (Ahrefs / Majestic / GSC) |
| `ai_cited` | string | Latest weekly citation status: `AIO,Perplexity,Claude` (see [CITATION-OPS](CITATION-OPS.md)) |
| `decay_flag` | bool | Triggered by decay rules (see below) |
| `action` | enum | `keep` / `refresh` / `merge` / `redirect` / `noindex` / `remove` / `rewrite` |
| `notes` | string | Free text |

## Building the initial inventory

Sources, joined on `url`:

1. **Sitemap.** Authoritative list of pages the team intends to index.
2. **Crawl.** What's actually reachable via internal links. Run `scripts/crawl.ts` from homepage; record canonicals and meta robots.
3. **GSC URL inspection (for top URLs).** Indexed / not / canonical-different / discovered-not-indexed.
4. **GSC `Pages` report export.** 16-month bulk indexing state.
5. **GA4 landing-page export, 28d.** Sessions, conversions per URL.
6. **GSC Performance export, 28d.** Clicks, impressions, position, top queries per URL.
7. **Ahrefs / Majestic / GSC Links report.** External inbound links per URL.

Join steps:

```sql
-- Conceptual: in BigQuery / DuckDB / pandas
SELECT
  COALESCE(s.url, c.url, gsc.url) AS url,
  s.lastmod AS sitemap_lastmod,
  c.canonical AS crawled_canonical,
  c.meta_robots,
  gsc.clicks_28d, gsc.impressions_28d, gsc.position_avg,
  ga4.conversions_28d, ga4.sessions_28d,
  links.internal_count, links.external_count
FROM sitemap s
FULL OUTER JOIN crawl c USING(url)
FULL OUTER JOIN gsc_pages gsc USING(url)
FULL OUTER JOIN ga4_landings ga4 USING(url)
FULL OUTER JOIN links USING(url);
```

Outputs:

- URLs in sitemap but not in crawl → broken internal link path.
- URLs in crawl but not in sitemap → either should be added or shouldn't be crawlable.
- URLs in GSC but not in sitemap nor crawl → orphan / leaked URL.
- URLs in sitemap with `noindex` → contradiction; fix.
- URLs canonical to elsewhere → not the canonical owner; might still be in sitemap (anti-pattern).

Each contradiction becomes a row in `analyses/inventory-issues.md`.

## Refresh triggers

Per row, define what triggers a refresh:

| Trigger | Applies to | Cadence |
|---|---|---|
| Quarterly review | All editorial | Every 90 days |
| Product release affects this page | Commercial | On release |
| Pricing change | Pricing-adjacent | On change |
| Source data updated (e.g. benchmark refresh) | Editorial with dated data | On data refresh |
| External event (e.g. competitor launch) | Comparison pages | On event |
| Decay flag triggered (see below) | All | When triggered |
| Query family lost top-3 position | Striking-distance page | Within 14 days |

## Decay flags

A page is "decaying" when it's losing relevance, traffic, or authority. Auto-flag rules:

| Rule | Threshold |
|---|---|
| Impressions down ≥ 30 % vs trailing 90 days | flag |
| Position dropped ≥ 5 places over 28 days | flag |
| `dateModified` > 365 days for time-sensitive content (pricing, integrations, comparison) | flag |
| `dateModified` > 730 days for evergreen content | flag |
| AI citation lost across all platforms over 4 consecutive weeks | flag |
| Conversion rate down > 50 % | flag |
| Internal link count fell below 3 | flag (orphaning risk) |
| External link count fell sharply (lost links) | flag |

Decay flags don't auto-action. They surface in the next review for triage.

## Per-row decision tree

For each decay-flagged or low-performing page:

```
Does this URL still serve a real user need?
│
├── No → Decision: remove
│   │
│   ├── Has ≥ 1 backlink or ≥ 100 historical clicks → 301 to closest live page
│   └── No backlinks, low traffic → 410 or noindex
│
└── Yes
    │
    ├── Is this URL the canonical owner for its query family?
    │   ├── No → Decision: merge into the canonical owner; 301
    │   │
    │   └── Yes — continue
    │
    ├── Can refreshing the page recover the loss?
    │   ├── Yes → Decision: refresh (rewrite + re-date)
    │   └── No — the demand has shifted
    │
    └── Is the demand still real but the page format wrong?
        ├── Yes → Decision: rewrite for new format
        └── No → Decision: noindex,follow (keep for users; remove from index)
```

## Quarterly review cadence

Owner: SEO lead + content lead. ~4 hours per quarter for T2; ~2 days for T3.

Steps:

1. **Refresh exports.** Pull 28-day GSC + GA4 + crawl + GSC URL inspection for top 100 URLs.
2. **Update inventory CSV.** Re-run the join; update `traffic_28d`, `impressions_28d`, `position_avg`, `conversions_28d`, `index_state`, `canonical`, `last_update` fields.
3. **Run decay flag rules.** Auto-flag.
4. **Triage flags.** Per-row decision tree; record in `action` column.
5. **Schedule actions.** Refreshes go to next sprint; merges and removes go to migration backlog.
6. **Identify wins.** Pages climbing positions: what changed? Pattern-extract for replication.
7. **Identify cluster issues.** Cannibalization, orphaning, intent drift.
8. **Document in `analyses/inventory-review-YYYY-Q.md`.**

## Integration with GSC + GA4

GSC API pulls per URL:

```bash
# Bulk URL query data export
# Search Console → Performance → Pages → Export → CSV (16 months)
```

GA4 pull (BigQuery export):

```sql
SELECT
  page_location AS url,
  COUNT(DISTINCT session_id) AS sessions_28d,
  COUNTIF(event_name = 'sign_up') AS signups_28d,
  COUNTIF(event_name = 'purchase') AS purchases_28d
FROM `project.dataset.events_*`
WHERE _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY))
  AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name IN ('page_view', 'sign_up', 'purchase')
GROUP BY url;
```

Caveats:

- GSC clicks are query-attributed and lossy at ≤ 5-impression cells (anonymized).
- GA4 conversions depend on consent state.
- Diff GSC clicks and GA4 sessions; expect drift.

## Per-tier depth

| Tier | Depth |
|---|---|
| T1 | Manual list of 5–10 commercial URLs in `analyses/content-inventory.md`; quarterly review. |
| T2 | CSV with up to ~300 rows; semi-automated refresh; quarterly review. |
| T3 | Full join pipeline (crawl + GSC + GA4 + links + AI citation); programmatic templates inventoried separately; per-template owner. |
| T4 | Continuous inventory in a database; per-template SLAs; per-quarter board-level review. |

## Worked example — quarterly review on T2 site

State (2026-Q1 review):
- 240 URLs in inventory.
- 18 decay-flagged.

Triage:

| URL | Flag | Decision | Reason |
|---|---|---|---|
| `/blog/notion-integration-2024` | dateModified > 365d | refresh | High impressions, dropped position |
| `/blog/legacy-pricing-2023` | dateModified > 365d, low traffic | redirect → /pricing | Outdated content, transactional intent |
| `/blog/ceo-letter-q4-2023` | low traffic, dateModified > 365d | noindex,follow | Historical value for users; no SEO value |
| `/integrations/legacy-zapier-v1` | impressions -45% | redirect → /integrations/zapier | Newer Zapier integration page exists |
| `/blog/comparison-vs-acmealternative` | position -7 | refresh | Competitor changed pricing; data stale |
| `/blog/seo-gaming-spam-2022` | low traffic, low intent fit | remove (410) | Off-topic for current product |
| `/use-cases/<empty>` | empty content | rewrite | Discovered orphan with template error |

Actions:
- 5 refreshes scheduled in Phase 4 backlog.
- 3 redirects added to `next.config.ts` next PR.
- 1 noindex applied via metadata.
- 1 410 (custom route).
- 1 rewrite scheduled.

Documented in `analyses/inventory-review-2026-Q1.md`.

## Anti-patterns

- "Inventory" as a one-time spreadsheet that never updates.
- Adding columns without owners.
- `last_update` set to deploy date (meaningless freshness).
- Refresh triggers without an owner who responds.
- Decay flags without action thresholds.
- Quarterly review skipped because "we have other priorities."
- Removing pages without a backlink-check (lose external authority unnecessarily).
- Bulk delete based only on traffic — ignores conversion and brand value.
- Treating commercial and programmatic in the same review (different SLAs, different owners).
- Inventory + redirect map drift (URL marked `removed` in inventory but no 301 in next.config).

## Cross-references

- [PHASE-1-DISCOVERY](PHASE-1-DISCOVERY.md) — initial baseline.
- [PHASE-4-CONTENT](PHASE-4-CONTENT.md) — refresh briefs.
- [PHASE-13-COMPOUNDING](PHASE-13-COMPOUNDING.md) — quarterly review cadence.
- [STRIKING-DISTANCE-PLAYBOOK](STRIKING-DISTANCE-PLAYBOOK.md) — position-4–15 page decisions.
- [REDIRECT-PLAYBOOK](REDIRECT-PLAYBOOK.md) — merge / remove decisions.
- [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md) — programmatic-template inventory.
- [CITATION-OPS](CITATION-OPS.md) — `ai_cited` column.
- [WIRING-OBSERVABILITY](WIRING-OBSERVABILITY.md) — measurement sources.
- [ANTI-PATTERNS](ANTI-PATTERNS.md) — full catalog.
- [EVIDENCE-LABELS](EVIDENCE-LABELS.md) — confidence/severity grammar.
