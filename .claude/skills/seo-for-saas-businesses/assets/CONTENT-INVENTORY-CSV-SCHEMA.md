# Content inventory CSV schema

Schema for `analyses/content-inventory.md` (or `.csv`) — the durable record of every indexable URL, its intent, its performance, and its disposition. Maintained continuously through Phase 4 and into maintenance mode. The decay queue, refresh cadence, and prune-before-publish gate ([PROGRAMMATIC-GATES](../references/PROGRAMMATIC-GATES.md)) all key off this file.

## Columns

| Column | Type | Required | Notes |
|---|---|---|---|
| `url` | absolute URL | yes | Canonical URL (post-redirect, post-trailing-slash policy). |
| `page_type` | enum | yes | `home | pricing | comparison | alternative | integration | use-case | industry | pillar | cluster | docs | changelog | blog | landing | legal | other` |
| `owner` | string | yes | Human name. Don't accept "the team". |
| `intent` | enum | yes | `informational | commercial | transactional | navigational` |
| `query_family` | string | yes | Canonical query family this page owns. Cross-check with `analyses/cannibalization-map.md`. |
| `funnel_role` | enum | yes | `awareness | evaluation | decision | post-purchase` |
| `index_state` | enum | yes | `index | noindex | canonical-to-other | blocked | unknown` |
| `canonical_target` | absolute URL | conditional | Required if `index_state = canonical-to-other`. |
| `last_substantive_update` | YYYY-MM-DD | yes | Last *substantive* content change, not template touch. |
| `next_review_date` | YYYY-MM-DD | yes | Per-template cadence: pricing 30d, comparison 60d, evergreen 180d. |
| `traffic_30d` | int | yes | GSC clicks last 30d. |
| `traffic_90d` | int | yes | GSC clicks last 90d. |
| `traffic_trend` | enum | yes | `growing | stable | decaying | new | dormant` |
| `conversions_90d` | int | yes | GA4 organic-attributed conversions last 90d. |
| `backlinks` | int | no | Total backlinks (Ahrefs / Semrush / GSC). |
| `referring_domains` | int | no | Unique referring domains. |
| `internal_link_count` | int | yes | Internal inbound links (from canonical pages only). |
| `source_proof_status` | enum | yes | `≥3 unique data points | <3 | none` per [AI-VISIBILITY](../references/AI-VISIBILITY.md). |
| `action` | enum | yes | `keep | refresh | merge | redirect | noindex | remove` |
| `notes` | string | no | Free text. Cite audit IDs, decision-card IDs, brief paths. |

## Example rows

```csv
url,page_type,owner,intent,query_family,funnel_role,index_state,canonical_target,last_substantive_update,next_review_date,traffic_30d,traffic_90d,traffic_trend,conversions_90d,backlinks,referring_domains,internal_link_count,source_proof_status,action,notes
https://example.com/pricing,pricing,Alice Chen,transactional,"<saas> pricing",decision,index,,2026-04-12,2026-05-12,4821,14502,growing,312,87,42,28,>=3,keep,DC-0042 ran title CTR test
https://example.com/integrations/slack,integration,Ben Park,commercial,"<saas> slack integration",evaluation,index,,2026-02-03,2026-08-03,612,1944,stable,18,12,9,11,>=3,keep,
https://example.com/blog/2022-state-of-x,blog,Dana Liu,informational,"state of x report",awareness,index,,2022-08-15,2026-05-15,89,201,decaying,1,140,76,3,<3,refresh,Pillar still ranking but data is stale; AUDIT-0231
https://example.com/blog/early-feature-spec,blog,Dana Liu,informational,"<deprecated feature> spec",awareness,index,,2021-03-04,,5,12,dormant,0,3,3,1,<3,redirect,Merge into /docs/<feature> per AUDIT-0245
https://example.com/compare/<saas>-vs-<retired-competitor>,comparison,Ben Park,commercial,"<saas> vs <competitor>",evaluation,index,,2024-11-09,,21,52,decaying,0,18,11,2,none,remove,Competitor sunset; 410 per MIGRATION-URL-MAP
```

## Generation

1. Crawl produces all canonical URLs (`analyses/crawl/`).
2. Join with GSC performance + GA4 landing-page exports.
3. Join with backlink export (Ahrefs / Semrush / GSC links report).
4. Owner + intent + query_family + funnel_role come from Phase 2 cluster work (`analyses/clusters/`).
5. Source-proof status assessed per page using [AI-VISIBILITY](../references/AI-VISIBILITY.md) heuristics.
6. Initial `action` is auto-suggested but every row needs human confirmation.

## Refresh cadence

- Weekly: refresh `traffic_30d`, `traffic_90d`, `traffic_trend`, `conversions_90d`, `internal_link_count`.
- Monthly: refresh `backlinks`, `referring_domains`, audit `next_review_date` against actual update activity.
- Quarterly: full re-categorization pass for `traffic_trend` + decay-queue review.

## Decay queue

Run the decay query each week:

> `traffic_trend = decaying OR dormant` AND `last_substantive_update > 180 days ago` AND `action NOT IN (refresh, redirect, remove)`

Each match opens a bead. Action chosen with the user; recheck-by date set.

## Anti-patterns

- **Bulk noindex without diagnosis.** Helpful Content System rewards pruning thoughtful pages and punishes panic-noindexing pages that earned links. Diagnose before disposing.
- **One row per URL with no canonical_target on canonicalized URLs.** Breaks the audit trail when canonicalization breaks.
- **`owner = team`** or `owner = SEO`. Owner is one human. If the page has no owner, flag in notes — that's the audit finding.
- **`source_proof_status = >=3` without listing the proofs.** The brief ([BRIEF-TEMPLATE](BRIEF-TEMPLATE.md)) lists the three data points; the inventory is the index.

## Cross-references

- [PHASE-4-CONTENT](../references/PHASE-4-CONTENT.md), [PROGRAMMATIC-GATES](../references/PROGRAMMATIC-GATES.md), [DELIVERABLES-INDEX](../references/DELIVERABLES-INDEX.md)
- [BRIEF-TEMPLATE](BRIEF-TEMPLATE.md), [SEASONALITY-CALENDAR-TEMPLATE](SEASONALITY-CALENDAR-TEMPLATE.md)
