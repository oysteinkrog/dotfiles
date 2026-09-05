# FACETED-NAV

Filters, sorts, search URLs, and pagination on SaaS marketing sites (integrations directories, template galleries, customer-story search, blog tags). The category that quietly destroys crawl budget, dilutes signals, and creates duplicate content if left unmanaged.

## Phase mapping

| Phase | Use this doc for |
|---|---|
| 1 — Discovery | Inventory current filter / sort / pagination URLs; their crawlability. |
| 3 — Technical | Decide indexable / noindex / disallow per filter; URL design. |
| 5 — IA | Which filters deserve their own landing pages; cluster shape. |
| 6 — Implementation | Code-level URL design, internal-link discipline, parameter handling. |
| 12 — Verify | Verify Googlebot does not crawl combinatorial filter space. |

## Three categories of facet URLs

```
For each filter / sort / parameter:
│
├── Category A: indexable landing page
│   (high-demand, unique value, real query family)
│
├── Category B: noindex, follow
│   (some user value but no search demand; lets users browse, doesn't index)
│
└── Category C: disallow / not crawlable
    (combinatorial junk; sort orders; UI-only state)
```

## Decision: which filters deserve indexable landing pages?

Answer one of three signals affirmatively. Without an affirmative, the filter is *not* an indexable landing page.

| Signal | Threshold |
|---|---|
| Real search demand | ≥ 100 monthly impressions in GSC for the matching query family |
| Unique inventory worth indexing | ≥ 10 distinct, useful items behind the filter |
| Editorial / first-hand value worth crawling | The filter page has unique copy / data / curation, not just "items where field=X" |

If yes to any: Category A (build a dedicated, canonical, indexable landing page).
If no to all: Category B or C.

## URL design conventions

Distinguish indexable filters from non-indexable ones by URL shape:

| Type | URL pattern | Crawlable? | Indexable? |
|---|---|---|---|
| Indexable landing page | `/integrations/notion` | yes | yes |
| Indexable category | `/integrations/category/productivity` | yes | yes |
| Indexable hub | `/templates/marketing` | yes | yes |
| User-only filter (browseable, not indexed) | `/integrations?status=beta` | yes | noindex,follow |
| Sort order (UI-only state) | `/integrations?sort=popular` | no | n/a |
| Multi-filter combination | `/integrations?cat=productivity&status=beta&sort=popular` | no | n/a |
| Pagination beyond N pages | `/integrations?page=99` | no | n/a |

Rule of thumb: clean paths for indexable; query parameters for UI / non-indexable.

`anti-pattern`: same URL serves both indexable category and combinable filters; the URL `?` is the only difference. Crawlers find every combination.

## Internal-link discipline

Internal links determine what crawlers discover. The site's nav, sidebar, footer, and template-rendered links must promote *only* the canonical landing pages, not every filter combination.

Patterns:

| Element | Should link to |
|---|---|
| Footer "Browse by category" | Category landing pages (Category A) only |
| Sidebar facets on a listing page | Toggle the URL query param without crawlable `<a href>` (use button + JS that updates URL) — OR use clean URLs with `<a rel="nofollow">` for non-canonical filters |
| Sort dropdown | `<select>` with JS, or `<a>` with `rel="nofollow"` — never plain crawlable `<a>` |
| Pagination | `<a>` to page 1..N (numeric); `rel="next"`/`rel="prev"` ignored by Google but harmless |

`confirmed`: `rel="nofollow"` on internal links is *not* a perfect crawl barrier; Google may still follow. The robust solution is to not have a crawlable link or to disallow in robots.txt.

## Pagination patterns

`confirmed`: Google ignores `rel="next"`/`rel="prev"` (deprecated 2019). Each paginated page should be:

| Element | Value |
|---|---|
| `<title>` | Distinct per page (e.g. `Integrations — page 3`) or stable; not "Integrations — page 1" cloned |
| `<meta name="description">` | Same for all pages, or distinct |
| Canonical | **Self-canonical** to its own URL (`/integrations?page=3` → canonical `/integrations?page=3`) |
| `noindex` | Optional on deep pages (page > 5) when content is just "older items" |

`anti-pattern`: canonicalizing every paginated page to page 1 (`/integrations?page=N` → canonical `/integrations`). Google sees pages 2..N as duplicates of page 1; deeper items never index. (`confirmed` per Google docs.)

Three accepted patterns:

| Pattern | When |
|---|---|
| Self-canonical paginated | Deep listings with unique items per page (e.g. blog index) |
| View-all + canonical to view-all | Listing fits on one page + view-all is acceptable performance |
| Infinite scroll + crawlable URL fallback | Large listings; UX uses scroll, crawlers see paginated URLs |

For *infinite scroll*, ensure each pagination page is reachable via a crawlable URL (`/blog?page=2`). Render content server-side per page; the JS-driven scroll just smooths UX. Otherwise crawlers find only page 1's items.

## Parameter handling at the edge

For combinatorial query params that should not be crawled:

```
# robots.txt
User-agent: *
Disallow: /integrations?cat=*&status=*  # multi-filter
Disallow: /integrations?sort=*           # sort-only
Disallow: /integrations?utm_*=*          # UTM-only
```

`confirmed`: Google's `robots.txt` supports `*` and `$` (limited globbing). Be explicit; pattern-match testing in GSC's `robots.txt` tester before deploying.

Edge / middleware option: rewrite tracking-param-only URLs to the clean URL and 301; never serve dual versions.

```ts
// middleware.ts
const TRACKING_PARAMS = ["utm_source", "utm_medium", "utm_campaign", "gclid", "fbclid"];

export function middleware(req: NextRequest) {
  const url = new URL(req.url);
  const hasTracking = TRACKING_PARAMS.some((p) => url.searchParams.has(p));
  if (hasTracking) {
    TRACKING_PARAMS.forEach((p) => url.searchParams.delete(p));
    return NextResponse.redirect(url, 301);
  }
}
```

Beware: stripping UTMs at the edge breaks paid attribution unless GA4 tagged the click before redirect. Either preserve client-side parsing before stripping, or strip only the bot-class user agents.

## Search URLs

Site-internal search results pages are almost always Category C.

```
# robots.txt
User-agent: *
Disallow: /search
```

Plus on the page:

```html
<meta name="robots" content="noindex,follow">
```

Both belt and suspenders: robots disallows fetching; in-page noindex catches the case where a backlink points at a search URL despite robots disallowance.

## Anti-cannibalization

If a filter URL ranks for the same query family as a canonical landing page, you have a cannibalization. Triage via Operator ⊞ Anti-Cannibalization Owner:

```
For query family "Notion + acme integration":
  Canonical owner:        /integrations/notion
  Competing filter URL:   /integrations?cat=notion

  Action:
    1. 301 the competing URL to the canonical owner OR
    2. noindex the filter URL OR
    3. Block crawl of the filter URL
```

Default: block crawl + 301.

## Worked example — integrations directory

State (2026-04-01):
- 240 integrations.
- Each has filters: `category` (8 values), `status` (active/beta/deprecated), `pricing` (free/paid).
- Sort: `popular`, `recent`, `alphabetical`.
- Pagination: 24 per page → up to 10 pages.
- Site nav exposes all combinations as crawlable links.

Crawl trap analysis (Operator §):
- Theoretical unique URLs: 8 × 3 × 3 × 10 = 720 query-string variants per category page.
- Across all categories: ~5,760 URLs from 240 items. Googlebot was fetching 4,200/day.
- GSC: "Duplicate, Google chose different canonical" cluster of ~600 URLs.

Decisions:

| URL | Decision | Reason |
|---|---|---|
| `/integrations` | Category A (indexable) | Hub for `acme integrations` query family |
| `/integrations/category/<slug>` (8 pages) | Category A | Real demand: `acme productivity integrations`, etc. |
| `/integrations/<slug>` (240 pages) | Category A | Each integration unique, demand exists per integration |
| `/integrations?status=beta` | Category B (noindex,follow) | UI value, no search demand |
| `/integrations?sort=*` | Category C (disallow) | UI state |
| `/integrations?cat=*&status=*&sort=*` | Category C (disallow) | Combinatorial junk |
| `/integrations?page=2..10` | Category A (self-canonical) | Listing pagination |
| `/integrations?page=11+` | Category B (noindex,follow) | Deep listing low value |

Implementation:

1. Sort dropdown: `<button>` + JS, no `<a>`.
2. Sidebar `status` toggle: `<a href="/integrations?status=beta" rel="nofollow">` plus robots disallow plus on-page `noindex,follow`.
3. Category links: `<a href="/integrations/category/<slug>">` clean; canonical to self.
4. Footer "Browse by category" lists category URLs only.
5. `robots.txt` adds disallow for `?sort=`, `?cat=*&status=*`, `?utm_*=*`.
6. Sitemap includes only Category A URLs.

Result (28 days):
- Googlebot fetches: 4,200/day → 1,600/day on the integrations subtree.
- Indexed URLs in GSC: 248 (was 612 with mostly-duplicate clusters).
- Organic clicks on integrations subtree: +18 % (signal consolidation).

## Per-tier depth

| Tier | Depth |
|---|---|
| T1 | Single integration list at `/integrations`; no filters; no pagination. |
| T2 | Category landing pages; user-only filters + noindex + sort behind JS. |
| T3 | + log-led crawl-trap detection; quarterly facet decision review; per-template owner. |
| T4 | + per-region facet handling; programmatic governance with kill switch. |

## Anti-patterns

- Footer with every filter combination linked.
- `<a>` for sort orders.
- `rel="nofollow"` as the only crawl barrier.
- `noindex` to "save crawl budget" without removing crawlable links.
- Canonicalizing every paginated page to page 1.
- Infinite scroll without a crawlable URL fallback.
- Robots `Disallow:` *and* `noindex` on the same URL — Google can't see the noindex if it can't fetch.
- Indexable category page with content rendered client-side from filter state.
- Same URL serves both indexable category and combinable filter set.
- Sitemap includes filter URLs.
- UTM-tagged internal links (poison the canonical clusters).
- User-search results page indexed.
- Calendar archive (`/blog/2017/03/page/4`) crawlable to year 0.

## Cross-references

- [LOG-FILE-ANALYSIS](LOG-FILE-ANALYSIS.md) — crawl-trap detection.
- [CRAWL-BUDGET](CRAWL-BUDGET.md) — when budget actually matters.
- [REDIRECT-PLAYBOOK](REDIRECT-PLAYBOOK.md) — UTM-strip 301; cannibalization 301.
- [PHASE-3-TECHNICAL](PHASE-3-TECHNICAL.md) — facet/parameter audit step.
- [PHASE-5-IA](PHASE-5-IA.md) — IA decisions for facets.
- [OPERATORS](OPERATORS.md) ⊞ Anti-Cannibalization Owner.
- [ANTI-PATTERNS](ANTI-PATTERNS.md) — full catalog.
- [EVIDENCE-LABELS](EVIDENCE-LABELS.md) — confidence/severity grammar.
