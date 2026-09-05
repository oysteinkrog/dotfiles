# STRIKING-DISTANCE-PLAYBOOK

Pages in average position 4–15 with steady impressions are the highest-ROI lift work in SEO. They have *demonstrated* demand (Google is showing them), the page already meets *some* relevance bar, and small per-page interventions can move them into the top 3 where the click curve steepens.

This is the playbook: identify them, pick the smallest change first, and recheck on a deadline.

## Phase mapping

| Phase | Use this doc for |
|---|---|
| 1 — Discovery | Identify striking-distance candidates from GSC. |
| 4 — Content | Per-page rewrite briefs. |
| 6 — Implementation | Code-level changes (title, meta, internal link, schema). |
| 9 — Experimentation | Title / meta tests on top 5 candidates. |
| 13 — Compounding | Quarterly striking-distance pass. |

## Identification via GSC

Pull GSC Performance: last 28 days, page-level, with query, impression, position, CTR.

Filter rules:

| Rule | Threshold |
|---|---|
| Average position | between 4 and 15 |
| Impressions | ≥ 100 (T2), ≥ 500 (T3), ≥ 2000 (T4) |
| CTR | not abnormally high — pages already at peak CTR for their position have less to gain |
| Page is canonical owner of its query family | yes (per [CONTENT-INVENTORY-OPS](CONTENT-INVENTORY-OPS.md)) |
| Page is indexable, 200, server-rendered | yes |

```sql
-- Conceptual GSC export filter
SELECT page, query, impressions, clicks, position, ctr
FROM gsc_query_page
WHERE position BETWEEN 4 AND 15
  AND impressions >= 100
ORDER BY impressions DESC, position ASC
LIMIT 50;
```

The output is the *striking-distance candidate list*. Top 20 typically yields meaningful lift.

## Smallest-change-first ladder

For each candidate page, pick the smallest viable change. Stop when the change ships.

```
1. Title rewrite for intent + CTR
2. Meta description rewrite for CTR
3. One internal link from a high-authority page
4. Add a missing entity / subtopic / data point in body
5. Add three unique data points (AI Overview citation eligibility)
6. Schema correction (Offer, Article, BreadcrumbList — eligible types only)
7. H1 rewrite for query match (only if title rewrite insufficient)
8. New section addressing a related-questions / PAA query
9. Major rewrite (last resort)
```

Title and meta description are the highest-ROI changes for striking-distance work. They cost minutes; they often move position 5 to position 3 over 2–4 weeks. (`likely`, operator-observed.)

## Per-lever details

### 1. Title rewrite

Diagnose the SERP feature first via Operator ⌖ Intent-Format Match. If the SERP shows AIO + PAA, the title must do two jobs: match the query intent *and* earn a click despite the AIO summary above it.

Patterns:

| Intent | Title pattern |
|---|---|
| Comparison | `<Acme> vs <Competitor>: <specific differentiator> (2026)` |
| How-to | `How to <action> with <Acme>: <step count>-step guide` |
| Definition | `<Term>: definition, example, and how Acme handles it` |
| Pricing | `<Acme> pricing — plans, limits, and what's included` |
| Integration | `<Acme> + <Tool>: setup in <X> minutes (2026)` |
| Alternative | `<X> alternatives in 2026: <Acme> vs <list>` |

Length target: 50–60 characters; not under 35 unless intent is short. Avoid "The ultimate guide to" / "Everything you need to know about" — generic patterns lose to specific ones.

`anti-pattern`: shipping the same `<Page Name> | Acme` title pattern site-wide. Each template-driven page should produce a unique, specific, intent-matched title.

### 2. Meta description rewrite

Goal: highest CTR at the page's current position. The description is ad copy.

Pattern:

```
<lead with concrete outcome / number / benefit>. <evidence or specific feature>.
<one differentiator>. <call to action verb>.
```

Examples:

- Bad: `Acme is the best platform for compliance. Sign up today.`
- Better: `Acme connects to AWS, GCP, GitHub, and Okta to pull 47 SOC 2 evidence artifacts every 6 hours. Median time to Type II: 9 weeks. See pricing.`

Length: 150–160 chars (mobile-aware).

### 3. One internal link from authority

Each candidate gets *one* new internal link from a high-authority page (high backlinks, high traffic, topically related).

Identify "authority" pages via:

- Top 10 pages by clicks (GSC).
- Top 10 by external backlinks (Ahrefs / Majestic).
- Homepage / pricing if topically aligned.

Link format:

- Anchor text descriptive but not exact-match-stuffed.
- Placed in body text, not footer.
- One link per candidate page (not 5 from the same source — looks staged).

`anti-pattern`: anchor text monoculture (every link to the candidate uses the same phrase).

### 4. Add missing entity / subtopic

Use Operator ⌬ AI-Citation Extractability. Identify:

- Subtopics in PAA / "People also ask" not addressed on the page.
- Entities Google's NLP would expect (related products, related concepts).
- Concrete answers to question-form queries.

Add as a new H2 section, 80–200 words, with at least one data point.

### 5. Add three unique data points

For pages that should be AI-cited but aren't. See [AI-VISIBILITY](AI-VISIBILITY.md) and [CITATION-OPS](CITATION-OPS.md) for the citation pattern.

### 6. Schema correction

Audit per page in [SCHEMA-COOKBOOK](SCHEMA-COOKBOOK.md). Common low-effort fixes:

| Page | Add / fix |
|---|---|
| Pricing page | `WebApplication` + `Offer` blocks; ensure schema price = visible price |
| Comparison page | `Article` with author + dateModified |
| Integration detail | `WebApplication` + `BreadcrumbList` |
| Customer story | `Article` with author + datePublished |

Don't add schema features Google has retired (HowTo, Sitelinks Searchbox, broad FAQPage). Don't fake `aggregateRating`.

### 7+ — heavier interventions

Reserve for pages where 1–6 don't move the needle within 28 days. By then the operator should have signal that the page's content itself is misaligned with the query family.

## Per-page recheck-by dates

Every striking-distance change ships with a recheck-by date.

| Change type | Recheck-by |
|---|---|
| Title / meta description | 14 days (CTR shows fast); 28 days for position |
| Internal link | 28 days |
| Body content addition | 28 days |
| Schema correction | 14 days for GSC validation; 28 days for ranking |
| Major rewrite | 56 days |

Track in `analyses/striking-distance.csv`:

| url | query | position_pre | change_type | shipped_date | recheck_by | position_post | ctr_post | decision |
|---|---|---|---|---|---|---|---|---|
| `/blog/notion-integration` | `notion api integration` | 6 | title rewrite | 2026-04-15 | 2026-05-13 | 3 | +0.8 % | keep |
| `/integrations/stripe` | `stripe connect integration` | 8 | + internal link from /pricing | 2026-04-15 | 2026-05-13 | 5 | flat | escalate |
| `/blog/soc2-checklist` | `soc 2 evidence list` | 11 | + 3 data points + schema | 2026-04-15 | 2026-05-13 | 7 | +1.1 % | continue |

## Avoiding cannibalization while lifting

When you boost a striking-distance page, make sure no other URL is competing for the same query.

Operator ⊞ Anti-Cannibalization Owner per page:

```
For query family Q:
  - List every URL on the site ranking in top 20 for Q.
  - Pick the canonical owner.
  - For each non-owner: support (link to owner), merge (301), differentiate (rewrite to own a different intent), or noindex.
```

`anti-pattern`: lifting a striking-distance page while a competitor URL on the same site is one slot above. Lift moves the wrong page.

## Statistical thresholds — when to expect movement

`likely`, operator-observed:

| Pre-position | Time to expect signal | Time to declare success/failure |
|---|---|---|
| 4–7 | 7–14 days | 28 days |
| 8–11 | 14–21 days | 35 days |
| 12–15 | 21–35 days | 56 days |

If no movement after the success/failure threshold, escalate to next ladder rung.

False signals to ignore:

- Day-1 position bump after re-crawl. Often resets within a week.
- Position improvement without click improvement. Could be query mix shifting.
- Position improvement on a single query while the cluster as a whole declined.

## Per-tier depth

| Tier | Depth |
|---|---|
| T1 | Skip; not enough URLs / queries to have a striking-distance pool. |
| T2 | Top 5 candidates per quarter; ladder rungs 1–3 only; manual recheck. |
| T3 | Top 20–50 candidates per quarter; full ladder; per-template patterns extracted. |
| T4 | Continuous; striking-distance dashboard; per-cluster owners; CTR-uplift A/B tests on titles. |

## Worked example — striking-distance pass on T2 site

State (2026-04-01):
- 240 URLs in inventory.
- Pulled GSC export, filtered to position 4–15, impressions ≥ 100.
- 18 candidates.

Top 5 selected:

| URL | Query family | Position | Impressions | Issue |
|---|---|---|---|---|
| `/blog/notion-integration` | notion api integration | 6 | 1,820 | Title was generic |
| `/integrations/stripe` | stripe connect integration | 8 | 920 | No internal link from pricing or homepage |
| `/blog/soc2-checklist-2024` | soc 2 evidence list | 11 | 1,450 | Outdated; missing data points |
| `/use-cases/devops` | acme for devops | 9 | 480 | No schema; orphan from main IA |
| `/comparison/vs-competitor` | acme vs competitor | 7 | 720 | Missing 2026 pricing data |

Changes shipped:

| URL | Change | Recheck |
|---|---|---|
| `/blog/notion-integration` | Title: `Notion API integration with Acme: 5-minute setup (2026)` | 2026-05-13 |
| `/integrations/stripe` | Internal link from `/pricing` and `/integrations` (anchor: `Stripe Connect integration`) | 2026-05-13 |
| `/blog/soc2-checklist-2024` | Renamed to `soc2-checklist-2026`, refreshed data, added 3 data points, updated schema dateModified | 2026-05-13 |
| `/use-cases/devops` | Added internal links from homepage and `/integrations`; added schema | 2026-05-13 |
| `/comparison/vs-competitor` | Updated competitor pricing to 2026 numbers, added dated screenshot | 2026-05-13 |

Result (recheck 2026-05-13):

- `/blog/notion-integration`: 6 → 3. CTR up 0.8 %. Decision: keep.
- `/integrations/stripe`: 8 → 5. CTR flat. Decision: continue (try title next).
- `/blog/soc2-checklist-2026`: 11 → 6. CTR up 1.1 %. Decision: continue.
- `/use-cases/devops`: 9 → 7. Marginal. Decision: try ladder rung 4.
- `/comparison/vs-competitor`: 7 → 4. CTR up 1.8 %. Decision: keep.

Total clicks gained over 28 days post-recheck: ~620 (vs 280 baseline for these 5 pages). Documented in `seo-changelog.md`.

## Anti-patterns

- Boosting a striking-distance page that's not the canonical owner of its query family.
- Anchor text monoculture across new internal links.
- Title rewrite without CTR baseline; can't tell if change helped.
- Multiple changes shipped at once; can't attribute lift.
- "Updated 2026" date stamp without real content change.
- Stuffing keywords in title to "match the query better".
- Internal link insertion as "SEO links" — placement and relevance must serve users.
- Skipping the recheck-by date; striking-distance work that isn't measured doesn't compound.
- Ignoring cannibalization — the wrong URL gets lifted.
- Spending engineering effort on rung 9 (major rewrite) before trying rungs 1–6.
- Treating the 4–15 band as a static fishing pool — re-pull every quarter; the candidates change.

## Cross-references

- [PHASE-2-KEYWORD](PHASE-2-KEYWORD.md) — query family ownership.
- [PHASE-4-CONTENT](PHASE-4-CONTENT.md) — rewrite briefs.
- [PHASE-9-EXPERIMENTATION](PHASE-9-EXPERIMENTATION.md) — title/meta tests.
- [CONTENT-INVENTORY-OPS](CONTENT-INVENTORY-OPS.md) — canonical owner check.
- [CITATION-OPS](CITATION-OPS.md) — 3+ unique data points pattern.
- [SCHEMA-COOKBOOK](SCHEMA-COOKBOOK.md) — schema correction reference.
- [OPERATORS](OPERATORS.md) ⊕ Striking-Distance Lift, ⊞ Anti-Cannibalization, ⌖ Intent-Format Match, ⊠ Snippet Curation Pass.
- [ANTI-PATTERNS](ANTI-PATTERNS.md) — full catalog.
- [EVIDENCE-LABELS](EVIDENCE-LABELS.md) — confidence/severity grammar.
