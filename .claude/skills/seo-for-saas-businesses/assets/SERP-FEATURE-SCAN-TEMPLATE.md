# SERP feature scan — `<query>`

Per-priority-query snapshot of the live search-results page. Output by Phase 2 cluster-researcher subagent before drafting briefs. The page format you build follows from what the SERP actually rewards. Save under `analyses/serp-snapshots/<query>.json` (machine) or as markdown next to it (human-readable).

Volatile per [VERIFICATION-FIRST](../references/VERIFICATION-FIRST.md). Re-scan before publish if the snapshot is older than 30 days for commercial queries or 90 days for informational queries.

## Header

- **Query**: `<exact query string>`
- **Locale**: `<en-US | en-GB | …>` + device `<desktop | mobile>`
- **Captured**: `<YYYY-MM-DD HH:MM TZ>` (logged in [SOURCE-LOG-TEMPLATE](SOURCE-LOG-TEMPLATE.md))
- **Captured by**: `<human or subagent name>`
- **Monthly volume**: `<n>` (source: `<GSC clicks proxy | tool>`)
- **Volume confidence**: `confirmed | likely | hypothesis`
- **Our current ranking**: `<position or "not in top 100">`
- **Our current URL**: `<URL or none>`

## SERP composition

| Feature | Present | Position(s) | Notes |
|---|---|---|---|
| AI Overview | yes/no | top | `<presence + scroll fraction>` |
| AI Overview citation pattern | — | — | `<docs / news / forum / blog / .gov — observed pattern>` |
| People Also Ask | yes/no | `<position>` | `<n>` questions visible without expand |
| Featured snippet | yes/no | top | `<paragraph | list | table>` |
| Video pack | yes/no | `<position>` | YouTube? Other host? |
| Image pack | yes/no | `<position>` | Domains pulling images |
| Product results | yes/no | `<position>` | Merchant feed? |
| Local pack (3-pack) | yes/no | `<position>` | Geo-relevant? |
| Site links searchbox | yes/no | brand only | retired surface, but log if observed |
| Forum / discussion (Reddit, Stack Overflow, Quora) | yes/no | `<position>` | Which subreddits / threads |
| News / Top Stories | yes/no | `<position>` | Recency bias? |
| Knowledge panel | yes/no | right rail | Entity present? |
| Sitelinks under top result | yes/no | top | What gets surfaced |
| Ad density (top) | `<n>` ads | — | Above first organic |
| Ad density (bottom) | `<n>` ads | — | Below organic 10 |

## AI Overview detail

- **Cited URLs (in order shown)**:
  1. `<URL>` — `<domain authority signal>` — `<passage cited>`
  2. `<URL>` — …
  3. …
- **Citation pattern observation**: `<docs-heavy | publisher-heavy | forum-heavy | mixed | gov/health-only>`
- **Our URL cited?**: yes/no
- **Our URL in top-10?**: yes/no
- **Note**: per [GUIDE-RECONCILIATION](../references/GUIDE-RECONCILIATION.md), AIO citation overlap with organic ranking is volatile and should be measured per query set. Don't assume top-10 = cited.

## PAA top questions

1. `<question>` — `<expanded answer host domain>`
2. `<question>` — `<host>`
3. `<question>` — `<host>`
4. `<question>` — `<host>`

## Top 10 organic

| # | URL | Title | Page type | Format observation | Original-data signal? | Schema visible? | Notes |
|---|---|---|---|---|---|---|---|
| 1 | `<URL>` | `<title>` | `<type>` | `<table | comparison | how-to | listicle | docs | demo>` | yes/no | `<types>` | `<freshness, depth, brand>` |
| 2 | … | | | | | | |
| … | | | | | | | |

## Competitor coverage on this query

| Competitor | URL | Page type | Format | Original data | Internal link strength |
|---|---|---|---|---|---|
| `<name>` | `<URL>` | `<type>` | `<format>` | yes/no | `<low | med | high>` |

## Implications for the brief

- **Format the page must be**: `<table | comparison | how-to | listicle | docs | mixed>`
- **AIO eligibility tactic**: `<≥3 unique data points required (per AI-VISIBILITY) | structured FAQ | publisher partnership>`
- **PAA cluster opportunity**: `<list of supporting H2s grounded in PAA>`
- **Striking-distance status**: `<yes | no>` + rationale
- **Refusal note**: if SERP is dominated by gov/health/publisher and SaaS sites are absent, log a refusal-to-pursue and pick a different query. Do not chase queries the SERP rejects.

## Example (filled)

```md
- Query: "best <category> tool for <ICP>"
- Locale: en-US, desktop
- Captured: 2026-04-29 14:22 PT
- Monthly volume: ~4900 (likely; tool-derived)
- Our position: 11; URL: https://example.com/best-<category>

| Feature | Present | Notes |
| AI Overview | yes | Cites G2 list, Reddit thread, our /alternatives/<competitor> |
| PAA | yes | "Is <category> tool worth it" / "<category> tool for small teams" |
| Video pack | no | — |
| Forum | yes | r/<icp> thread #2 organic |

Top 1: g2.com/categories/<cat> — listicle, no original data
Top 2: reddit.com/r/<icp>/...
Top 3: example-competitor.com/best-<category>-tools — comparison table, dated 2026, ≥3 unique data points

Implication: brief should ship as a comparison/listicle hybrid with a 2026-dated benchmark and a Reddit-friendly FAQ.
```

## Anti-patterns

- **Scraping rank-tracker JSON without looking at the SERP.** Tools miss AIO citations, PAA expansions, and ad density. The human (or vision-enabled subagent) opens the SERP.
- **One scan, never re-scan.** SERPs change. Re-scan on Phase 12 verification and before each substantive page refresh.
- **Pursuing a query whose SERP is gov/health/publisher-only.** Different surface; don't pretend you can win it as a SaaS.
- **Treating "AI Overview cites a URL" as proof the URL ranks.** AIO citation correlates more with domain-level authority and on-page proof density ([GUIDE-RECONCILIATION](../references/GUIDE-RECONCILIATION.md)), not URL rank.

## Cross-references

- [PHASE-2-KEYWORD](../references/PHASE-2-KEYWORD.md), [AI-VISIBILITY](../references/AI-VISIBILITY.md), [CITATION-OPS](../references/CITATION-OPS.md)
- [BRIEF-TEMPLATE](BRIEF-TEMPLATE.md), [COMPETITOR-GAP-TEMPLATE](COMPETITOR-GAP-TEMPLATE.md), [CITATION-TRACKING-CSV-SCHEMA](CITATION-TRACKING-CSV-SCHEMA.md)
