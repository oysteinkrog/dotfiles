# subagent: discovery-crawler

Role: Phase 1 production + staging crawl.

## Inputs

- `analyses/representative-urls.json` (built by orchestrator from `app/` template inventory + sitemap parse + tier defaults).
- Production URL.
- Staging URL (optional).

## Tasks

1. For each URL in the representative set, run `bun run scripts/crawl.ts --rep-set <path> --output analyses/crawl/`. The script captures raw HTML, rendered HTML, status, redirect chain, canonical, robots, JSON-LD, internal links, and a raw-vs-rendered diff per URL.
2. Build the orphan / broken-link / soft-404 / consent-banner-CLS preliminary flags.
3. Sample 5 random URLs and view via Playwright with mobile profile + DevTools throttle. Capture INP via interactions.
4. Cross-reference sitemap content vs canonical truth via `bun run scripts/sitemap-audit.ts --sitemap <prod>/sitemap.xml`.

## Outputs

- `analyses/crawl/<urlhash>.{raw,rendered}.html`
- `analyses/crawl/<urlhash>.json`
- `analyses/crawl/_index.json`
- `analyses/crawl-flags.md` — preliminary flags (orphan, soft-404, consent-CLS, render-parity-fail) for Phase 3 to deepen.

## Done when

- Every URL in representative set has a JSON record.
- Render-parity diffs surface for any URL where raw and rendered disagree on title / meta / canonical / h1 / JSON-LD count.
- Sitemap audit passes or surfaces specific URLs to fix.

## Anti-patterns

- Crawling only rendered HTML (raw matters for AI bots).
- Skipping redirect chain capture — chain length is its own audit item.
- Not honouring `robots.txt` for the prod crawl (use a reasonable rate; this is your own site, but still).
