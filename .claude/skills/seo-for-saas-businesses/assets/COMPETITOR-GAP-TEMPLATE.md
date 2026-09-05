# Competitor gap — `<competitor name>`

Per-competitor profile produced by the Phase 2 competitor-researcher subagent. One file per competitor under `analyses/competitors/<name>.md`. Goal: identify durable structural gaps, not surface-level differences. Cite evidence and date everything; competitor sites change.

- **Competitor**: `<name>`
- **Primary URL**: `<absolute URL>`
- **Captured**: `<YYYY-MM-DD>` by `<owner>`
- **Recheck-by**: `<YYYY-MM-DD>`
- **ICP overlap with us**: `low | medium | high` (justify in notes)
- **Stage**: `<pre-launch | pre-PMF | growth | scale | mature>`
- **Estimated organic clicks/month**: `<n>` (source: `<tool, confidence>`)

## Pillar topology

The shape of their site, top-down. List 3–7 pillars they actually operate.

| Pillar | Cluster pages count | Owner page (if visible) | Strength notes |
|---|---|---|---|
| `<pillar>` | `<n>` | `<URL>` | `<depth, freshness, internal-link strength>` |
| `<pillar>` | `<n>` | `<URL>` | `<…>` |
| … | | | |

## Top 20 ranking pages

Pulled from a third-party rank tool or GSC overlap. Annotate the *kind* of page each is.

| # | URL | Query family | Page type | Position estimate | Format / data signal |
|---|---|---|---|---|---|
| 1 | `<URL>` | `<query family>` | `<comparison | pillar | landing | docs | blog | integration | etc.>` | `<n>` | `<original data | template | thin>` |
| … | | | | | |

## Original-data assets

What proprietary data, benchmark, dataset, or research do they publish? List explicitly.

- `<asset name>` — `<URL>` — `<type: benchmark | dataset | survey | tool>` — `<dated YYYY-MM-DD>` — `<update cadence>`
- …

If they have none, note that as a gap *we can fill*.

## Comparison + alternative coverage

| Page | URL | Stance | Quality |
|---|---|---|---|
| `<competitor> vs <us>` | `<URL or "missing">` | `<advocacy | neutral | hostile>` | `<thin | balanced | proof-rich>` |
| `<competitor> alternatives` | `<URL or "missing">` | — | — |
| `<competitor> vs <other competitor>` | `<URL>` | — | — |

## Schema usage

Which structured-data types they ship and where. Cross-check against [SCHEMA-POLICY](../references/SCHEMA-POLICY.md).

| Page type | Schema types observed | Validates? | Notes |
|---|---|---|---|
| pricing | `<types>` | yes/no | `<deprecated types? misuse?>` |
| comparison | `<types>` | yes/no | |
| docs | `<types>` | yes/no | |
| pillar | `<types>` | yes/no | |

## Content cadence

- New pages last 90 days: `<n>`
- Refreshed pages last 90 days: `<n>` (source: `<archive.org diff sample | tool>`)
- Estimated content team size: `<n>`
- Notable recent shipped clusters: `<list>`

## Weak points (what they don't do well)

- `<weakness>` — `<evidence URL or screenshot path>`
- `<weakness>` — `<…>`
- `<weakness>` — `<…>`

## Link asset gaps

What linkable assets they *don't* have that we could ship.

- `<asset idea>` — `<why winnable>` — `<estimated outreach surface>`
- …

## Integration / directory presence

| Surface | Present? | Notes |
|---|---|---|
| G2 / Capterra / TrustRadius | yes/no | Review count + recency |
| Public roadmap / changelog | yes/no | Update cadence |
| Status page (with history) | yes/no | Index state |
| Public API docs | yes/no | Versioned? |
| Integration directory | yes/no | Listing count |
| Open-source repos | yes/no | Stars / activity |
| Marketplace listings (AWS / GCP / Azure / Vercel / Stripe / Slack / etc.) | yes/no | List |
| Conference / talk presence | yes/no | Last 12 months |

## AI-citation share (sample)

For 5–10 priority queries, log who AI Overviews / ChatGPT / Perplexity / Claude cite. Capture in [CITATION-TRACKING-CSV-SCHEMA](CITATION-TRACKING-CSV-SCHEMA.md) and summarize here:

| Query | AIO cites them? | AIO cites us? | ChatGPT cites them? | Perplexity cites them? |
|---|---|---|---|---|
| `<query>` | yes/no | yes/no | yes/no | yes/no |
| … | | | | |

## Net assessment

- **Durable gaps we can close in 90 days**: `<list>`
- **Gaps that require >90 days or product changes**: `<list>`
- **Gaps not worth closing** (different ICP / wrong intent): `<list>`
- **Confidence**: `confirmed | likely | hypothesis`
- **Linked decisions**: `<DC-####, DC-####>`

## Example (compressed)

```md
Competitor: <competitor> | Captured 2026-04-12 | ICP overlap: high

Pillars:
- "API monitoring" — 38 cluster pages — owner /api-monitoring
- "Synthetic checks" — 21 cluster — owner /synthetic-monitoring
- "Status pages" — thin (4 pages)

Top 20: dominated by /vs/<competitor>-vs-<rival> comparison templates and a /best-<category> evergreen.
Original data: 2025 API uptime benchmark (n=4500 endpoints, monthly refresh) — durable moat.
Comparison coverage: full — vs every named competitor including us. Stance hostile, proof thin.
Schema: WebApplication on pricing, BreadcrumbList sitewide, FAQPage on docs (not eligible per SCHEMA-POLICY).
Cadence: ~14 new pages / 30d, ~25 refreshes / 30d.

Weak points:
- No status-page pillar despite shipping a status-page product (huge gap).
- AIO citations skewing to their docs, not their marketing site.

Gaps to close in 90d:
- Ship our own dated benchmark (uptime + latency) per BRIEF-TEMPLATE.
- Publish status-page pillar (their omission, our product strength).
- Counter-comparisons /<us>-vs-<competitor> with proof from their own benchmark methodology.

Recheck-by: 2026-07-12.
```

## Anti-patterns

- **"Competitor X is doing Y, we should do Y."** Copy-without-fit produces commodity pages. The brief justifies *why we should* given ICP, intent, and proof.
- **Static one-shot scrape.** Without a recheck-by date, the analysis goes stale and the gap closes silently.
- **Confusing rank-tracker overlap with SERP overlap.** Two sites can rank for the same query family yet sit on different SERP features. Use [SERP-FEATURE-SCAN-TEMPLATE](SERP-FEATURE-SCAN-TEMPLATE.md).
- **Trusting domain-rating proxies as authority.** Authority is referring-domain quality + topical relevance + brand demand. DR is a coarse signal, not a target.

## Cross-references

- [PHASE-2-KEYWORD](../references/PHASE-2-KEYWORD.md), [AI-VISIBILITY](../references/AI-VISIBILITY.md), [SCHEMA-POLICY](../references/SCHEMA-POLICY.md)
- [SERP-FEATURE-SCAN-TEMPLATE](SERP-FEATURE-SCAN-TEMPLATE.md), [BRIEF-TEMPLATE](BRIEF-TEMPLATE.md), [CITATION-TRACKING-CSV-SCHEMA](CITATION-TRACKING-CSV-SCHEMA.md)
