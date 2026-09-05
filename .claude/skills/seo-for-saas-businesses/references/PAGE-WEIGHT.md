# PAGE-WEIGHT

## TOC

Budgets per template · Pagination vs all-on-one · Summary on index, detail on detail · Hidden-text vs UX-hidden · Don't ship every record in initial HTML · Mobile rendering · Total transfer size budget · Main-thread JS budget · Tier depth selectors · Anti-patterns · Cross-links

Large HTML and main-thread JS budgets matter for crawl efficiency, mobile rendering, INP, and AI extractability. Common offenders: directory / marketplace / category / changelog / search-results / mega-listing pages that ship every record in initial HTML, "all-on-one" docs pages, infinite-scroll feeds rendered server-side. Progressive disclosure done right helps users *and* preserves crawl + AI access. Done wrong, it cloaks.

Phase mappings: Phase 3 (size audit per template), Phase 5 (pagination / category strategy), Phase 6 (implementation), Phase 8 (transfer-size + main-thread regression alarms).

## Budgets per template (T2+ baseline)

| Metric | Marketing page | Blog post | Docs page | Listing / category | Dashboard / app |
|---|---|---|---|---|---|
| HTML transfer (gzip) | < 50 KB | < 80 KB | < 80 KB | < 150 KB | n/a (auth-walled) |
| HTML uncompressed | < 200 KB | < 300 KB | < 300 KB | < 500 KB | n/a |
| JS transfer (per page) | < 100 KB | < 150 KB | < 150 KB | < 200 KB | n/a |
| Main-thread JS budget | < 200 ms compile/parse on mid-tier mobile | < 200 ms | < 250 ms | < 300 ms | n/a |
| Total page transfer | < 1 MB | < 1.5 MB | < 1.5 MB | < 2 MB | n/a |
| LCP image weight | < 200 KB | < 200 KB | < 200 KB | < 200 KB | n/a |

(`likely` — varies by stack; calibrate to your CrUX baseline. Treat as starting points, not rules.)

## Pagination vs all-on-one

| Listing size | Strategy |
|---|---|
| < 30 items | One page is fine |
| 30–500 items | Split into ≤ 30/page or use category subdivision |
| 500–10k items | Pagination + category subdivision; consider faceted nav (carefully) |
| > 10k items | Subdivide aggressively; consider not indexing every leaf |

Pagination signals (current Google guidance):

- Self-canonical per page: `/category?page=2` canonical to `/category?page=2`, **not** to page 1.
- Don't use deprecated `rel="prev"` / `rel="next"` (Google retired support; harmless but unused).
- Each paginated page has a unique title: `Title — page 2`.
- Don't `noindex` paginated pages; let them rank on their own merits if content is unique. But also don't expect them to rank — their job is to expose detail pages to crawlers.
- Internal links from paginated pages to detail pages (the actual indexing target) — that's the value.

(`confirmed` per `developers.google.com/search/docs/specialty/ecommerce/pagination-and-incremental-page-loading`.)

## Summary on index, detail on detail

Pattern:

```html
<!-- /integrations (index) -->
<article>
  <h1>Notion integration</h1>
  <p>Sync Notion databases to Acme; bi-directional, real-time, no schema mapping.</p>
  <a href="/integrations/notion">Read more</a>
</article>
```

```html
<!-- /integrations/notion (detail) -->
<article>
  <h1>Notion integration</h1>
  <p>Sync Notion databases to Acme; bi-directional, real-time, no schema mapping.</p>
  <h2>How it works</h2>
  <!-- 800 words of detail, screenshots, setup, troubleshooting -->
  <h2>Pricing</h2>
  <h2>FAQ</h2>
</article>
```

Each page satisfies a different intent. Index = "what's available, briefly." Detail = "how this one works."

## Hidden-text vs UX-hidden

The line between progressive disclosure (legitimate UX) and hidden text (cloaking) is whether the user can access it.

| Pattern | Status | Why |
|---|---|---|
| Tabs that show/hide on click, all in initial HTML | Fine | User-accessible; crawlers index all |
| Accordion sections all in initial HTML | Fine | Same |
| Footnotes that expand on click | Fine | Same |
| `display:none` content that only shows for crawlers | **Cloaking** | Hidden from users |
| Content rendered only after scroll-trigger via fetch | **Risk** | AI bots can't see it; Googlebot can; mismatch |
| Content behind login wall, indexed without `noindex` | **Risk** | First-click free is gone; cloaking-like |
| Keyword-stuffed text in `<noscript>` | **Cloaking** | Not equivalent to UX |
| Content visible only on mobile | OK if it's a real responsive design choice | Avoid different *content* per device |
| Tabs with content fetched only on tab click | Avoid | AI / crawler may miss tabs they don't render |

Rule of thumb: if a user with JS disabled can read the content (or click to reveal it without a fetch), it's UX-hidden. If only crawlers see it, or crawlers see something *different*, it's cloaking. (`confirmed`)

## Don't ship every record in initial HTML

Common mistake: directory pages with 1,000 listings rendered server-side. Result:

- 600 KB of HTML.
- Mobile parse time 1+ s.
- LCP candidate buried under 600 KB of DOM.
- AI bots receive everything but can't reason about saliency.

Better:

- Show top N (e.g. 20) on the index.
- Internal links to detail pages, plus pagination.
- Faceted-nav links if applicable, gated per [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md).
- Sitemap segments give crawlers the full inventory anyway.

## Mobile rendering

Test specifically on:

- Slow 3G, 4× CPU throttle (Chrome DevTools).
- iPhone SE viewport (375 × 667) — common low-end.
- Pixel 4a / mid-tier Android (768 × 1024 viewport).

If the page has horizontal scroll, large layout shifts, or text that overlaps in any of these, the SEO impact is real. Mobile-first indexing has been default since 2023; mobile is the index. (`confirmed`)

## Total transfer size budget

CI gate:

```ts
// scripts/check-page-weight.ts
const REPRESENTATIVE = ["/", "/pricing", "/blog/post-x", "/integrations"];
const BUDGETS = { "/": 1024 * 1024, "/pricing": 1024 * 1024, /* ... */ };

for (const path of REPRESENTATIVE) {
  const har = await captureHar(`https://preview.example.com${path}`);
  const total = har.entries.reduce((sum, e) => sum + e.response.bodySize, 0);
  const budget = BUDGETS[path] ?? 1.5 * 1024 * 1024;
  if (total > budget) throw new Error(`${path}: ${total} > ${budget}`);
}
```

Run on preview deploy; PR fails on regression.

## Main-thread JS budget

Main-thread JS budget is the harder constraint. Tools:

- Lighthouse "Total Blocking Time" lab metric.
- Chrome DevTools Performance: total scripting + parsing time.
- `webpagetest.org` "Time to Interactive" + JavaScript breakdown.

Per-route JS chunk graph review is the practical control:

```bash
ANALYZE=true bun run build  # or npm run build with the bundle analyzer
```

Look for:

- Marketing chunk importing dashboard components (chart libraries, table libs).
- Single component that pulls in 200 KB of dependencies (date-fns whole import; lodash full).
- Polyfills shipped to all browsers when only IE11 needed them.
- Vendor chunks that split badly between routes.

Per [INP-DEEP-DIVE](INP-DEEP-DIVE.md), the same offenders that drive INP show up here. Same fixes: dynamic import, lazy mount on intersection, code-split per route group, kill the dependency.

## Tier depth selectors

| Tier | Page-weight scope |
|---|---|
| T1 | Manual review of homepage + pricing; obvious bloat fixes |
| T2 | Per-template budgets; CI gate on transfer size for representative URL set |
| T3 | + Main-thread budget; chunk-graph review per release; per-template alarms |
| T4 | + Per-locale + per-region budgets (CDN-region differences); continuous WebPageTest |

## Anti-patterns

| Don't | Why | Do instead |
|---|---|---|
| Ship every record in initial HTML for "SEO" | Bloat; INP / LCP / CLS regressions | Top N + pagination + sitemap inventory |
| `display: none` content for crawlers but not users | Cloaking; manual-action vector | Same content for everyone |
| Single-page-app for marketing routes | First paint blocked on JS bundle | RSC / SSR with progressive enhancement |
| Infinite scroll without pagination URLs | Crawlers can't reach deep items | Provide paginated URLs in HTML; use infinite scroll as enhancement |
| Compress every response with brotli but ship 2 MB of unminified JS | Wrong layer | Minify + tree-shake before compression |
| Polyfill IE11 in 2026 | Useless bytes | Target current evergreen browsers |
| `<script async>` for every script | Race conditions; ordering bugs | Specific strategies per script |
| Render the full changelog in HTML on every page | Bloat across all routes | Per-page `/changelog/<entry>` with index page summary |
| Tabs whose content is fetched on tab click | AI bots / crawlers may miss content | Render all tabs in HTML; show/hide via CSS |
| Heavy embeds (YouTube, Calendly, Figma) above fold | LCP and INP regression | Lite embed + click-to-load; or load below fold |
| `next/script strategy="beforeInteractive"` for non-critical scripts | Blocks page interactivity | Reserve for genuinely-critical (consent gate, auth bootstrap) |
| Inline 200 KB of CSS for "critical CSS" | First-paint optimization gone too far | Inline only above-fold CSS; rest is loaded normally |
| Mega-page docs ("everything in one URL") | Long, slow, hard to update; cannibalization-prone | One URL per query family |
| Cookie banner that ships 800 KB | INP + LCP regression | Self-host minimal banner; defer SDK to consent-action |
| Server-rendered comments thread (1,000 comments) | Bloat; the comment is rarely the search intent | Render summary; lazy-load full thread |

## Cross-links

- [INP-DEEP-DIVE](INP-DEEP-DIVE.md) — main-thread JS as INP contributor.
- [IMAGE-PERF-COOKBOOK](IMAGE-PERF-COOKBOOK.md) — image weight budgets.
- [NEXTJS-PATTERNS](NEXTJS-PATTERNS.md) — RSC, route groups, dynamic imports.
- [PHASE-3-TECHNICAL](PHASE-3-TECHNICAL.md) — page-weight as audit area.
- [PHASE-5-IA](PHASE-5-IA.md) — pagination + category subdivision.
- [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md) — faceted-nav crawl-trap risk.
- [UGC-AND-MARKETPLACE-SEO](UGC-AND-MARKETPLACE-SEO.md) — listing / directory page strategy.
- [DOCS-AND-SUPPORT-SEO](DOCS-AND-SUPPORT-SEO.md) — one-URL-per-query-family for docs.
