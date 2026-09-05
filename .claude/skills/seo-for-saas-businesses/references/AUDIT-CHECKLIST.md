# AUDIT-CHECKLIST

Per-area checks for Phase 3. Reference for `subagents/audit-area.md`.

## Crawlability (`area=crawl`)

- [ ] `/robots.txt` returns 200; valid syntax; references sitemap; does not block CSS/JS/images required for rendering.
- [ ] `/sitemap.xml` returns 200; parses; only canonical indexable URLs; URL count < 50k per file; total uncompressed < 50 MB per file.
- [ ] No redirect chains > 1 hop in the representative URL set.
- [ ] One canonical host (`www` or apex); 301 from the other.
- [ ] HTTPS only; no mixed content; HSTS header.
- [ ] All representative URLs return expected status (200 indexable; 301 legacy redirects; 404/410 known-removed).
- [ ] No 5xx for verified Googlebot in the last 7 days (logs T3+).
- [ ] No `x-robots-tag` header conflicts with the page's robots meta.
- [ ] Vary / Cache-Control headers consistent with content (do not serve stale metadata after release).
- [ ] Edge / CDN does not strip `Cache-Control` or override `Content-Type`.

## Indexability (`area=index`)

- [ ] Every indexable page has self-canonical (or canonical to declared owner).
- [ ] No accidental `noindex` on routes intended to rank.
- [ ] No `noindex` and `disallow` on the same URL (Google can't see directive if disallowed).
- [ ] Soft-404 hunt: empty-state, no-results, discontinued-product routes.
- [ ] Parameter handling: filters, sorts, tracking parameters do not generate indexable variants without intent.
- [ ] GSC `crawled, currently not indexed` items reviewed; quality / duplication / canonical / link weight diagnosed.
- [ ] GSC `discovered, currently not indexed` items reviewed; discovery / sitemap / internal links diagnosed.
- [ ] GSC `duplicate, Google chose different canonical` clusters reviewed.

## Rendering (`area=render`)

- [ ] Raw HTML for representative URLs contains: title, meta description, canonical, robots directive, primary content, primary headings, primary internal links, JSON-LD.
- [ ] Rendered HTML does not contradict raw HTML on these elements.
- [ ] No client-only critical content (gated behind `useEffect` / lazy hydrate).
- [ ] Route-change metadata updates correctly (no stale title from previous route).
- [ ] AI crawlers (`GPTBot`, `ClaudeBot`, `PerplexityBot`) see the same primary content as Googlebot.
- [ ] Suspense streaming boundaries do not strand citation-eligible content.
- [ ] Browser Back returns to the previous page after SPA navigations, modals, overlays, filters, consent flows, and exit-intent flows; no deceptive history insertion.

## Schema (`area=schema`)

- [ ] Each template's declared schema types validate against schema.org current types.
- [ ] Required + recommended properties present per Google docs for each type.
- [ ] Schema mirrors visible page content (no fake reviews, fake awards, fake authors).
- [ ] Schema rendered server-side (not via `useEffect`).
- [ ] No deprecated rich-result reliance (`HowTo`, `Sitelinks Searchbox`, broad commercial `FAQPage`).
- [ ] GSC enhancement reports reviewed; recent invalid-item spikes investigated.
- [ ] Per-page price / availability / rating in schema matches visible page and merchant feed.

## Internal links (`area=links`)

- [ ] Orphan pages flagged (indexable URL not linked from elsewhere).
- [ ] No internal links through redirects (audit via `scripts/internal-links.ts`).
- [ ] No `nofollow` on standard internal navigation.
- [ ] Anchor distribution per cluster reasonable (not over-optimized exact-match).
- [ ] Footer link count reasonable (not a link dump).
- [ ] Important links in crawlable HTML, not only in scripts/buttons/search widgets.

## Performance (`area=perf`)

- [ ] CrUX p75 INP < 200 ms on commercial templates (T1/T2 baseline; T3/T4 < 150 ms).
- [ ] CrUX p75 LCP < 2.5 s.
- [ ] CrUX p75 CLS < 0.1.
- [ ] LCP image not lazy-loaded.
- [ ] No render-blocking JS / CSS for marketing routes.
- [ ] Web font: `display: swap`; subsetted; preloaded if above fold.
- [ ] Consent banner does not block main thread or cause CLS.
- [ ] Lighthouse perf `score_0_1000 >= 900` (raw LHCI API `minScore: 0.9`) on representative URLs.

## Logs (`area=logs`, T3+)

- [ ] Verified Googlebot fetch volume per template within expected range.
- [ ] No 5xx / 4xx spikes for verified bots.
- [ ] No render-critical asset (CSS/JS/image/API) returning non-200 to verified bots.
- [ ] No parameter / filter / search URLs creating crawl traps.
- [ ] AI crawler (GPTBot, ClaudeBot, PerplexityBot, anthropic-ai) policy matches `robots.txt`.

## Infrastructure (`area=infra`)

- [ ] CDN cache rules don't serve stale metadata after release.
- [ ] Edge redirects match `next.config.ts` redirects.
- [ ] WAF / bot protection does not challenge verified search crawlers.
- [ ] WAF doesn't block CSS/JS/image/API resources for crawlers.
- [ ] Geo-routing: `x-default` present; verified crawlers reach all locales.
- [ ] Staging / preview / branch deployments noindex or access-controlled.
- [ ] Server errors and TLS failures monitored separately from app errors.
- [ ] Navigation scripts, edge redirects, ad/affiliate redirects, and middleware do not interfere with browser-history expectations or trap users on Back.

## Metadata (`area=meta`)

- [ ] Every public route exports `metadata` or `generateMetadata`.
- [ ] `metadataBase` set in root layout.
- [ ] Title pattern intent-matched; 30–60 char target.
- [ ] Description pattern ad-copy-quality; 150–160 chars.
- [ ] Canonical alternates set per route.
- [ ] OG: title, description, URL, type, image; image absolute URL or resolved against `metadataBase`.
- [ ] Twitter card type per template.
- [ ] Fallback values when page data is missing (don't ship empty title or description).
- [ ] Metadata generated from page data (don't drift from page content).

## Accessibility (`area=a11y`)

- [ ] Text size readable on mobile.
- [ ] Color contrast passes WCAG AA targets.
- [ ] Visible focus states on all interactive elements.
- [ ] Forms have labels and error messages.
- [ ] Heading hierarchy logical.
- [ ] Images have descriptive alt or empty alt for decorative.
- [ ] Touch targets ≥ 44×44 px on mobile.
- [ ] Charts / status do not rely on color alone.
- [ ] Modals / menus / accordions usable via keyboard.

## International (`area=intl`)

- [ ] Each localized page has self-referencing alternate.
- [ ] Alternates reciprocal where the relationship should exist.
- [ ] Language and region codes valid.
- [ ] `x-default` set for selector or fallback.
- [ ] Localized pages contain meaningful localized content (not just translated headers).
- [ ] Auto-redirects don't trap verified crawlers in one locale.
- [ ] Currency / availability / legal claims aligned with target region.
