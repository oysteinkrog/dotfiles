# GUIDE-RECONCILIATION

`multi_agent_seo_guide.md` is the canonical knowledge base. This document records where current evidence (verified from primary Google sources, framework docs, schema.org, and recent reputable studies) refines, contradicts, or sharpens guide claims. Where they conflict, **current evidence wins** and the discrepancy is logged.

Last reviewed: 2026-04-30.

Format: claim from guide → current evidence → action.

## INP / Core Web Vitals

- **Guide §6:** "Core Web Vitals are treated as user-experience and competitiveness baselines, not magic ranking levers."
- **Current evidence (web.dev + Google Search Central, reviewed 2026-04-30):** INP joined LCP and CLS as a primary CWV in March 2024, replacing FID. The official threshold is `good` at <=200 ms p75 and `poor` above 500 ms p75. Google says Core Web Vitals are used by ranking systems and can contribute to success when many helpful pages are available, but official docs do **not** support a deterministic "0.8 positions lost" or "2-4 positions lost" formula.
- **Action:** keep the guide's framing: CWV are competitiveness and UX baselines, not magic ranking levers. For commercial / striking-distance pages treat INP < 200 ms p75 as the baseline and < 150 ms p75 as a competitive target. Exact rank-impact estimates require a source-log entry with methodology and a quarterly recheck, or first-party experiment evidence.

## Helpful Content System

- **Guide §11:** quality and trust framing, no explicit treatment of the classifier as site-wide.
- **Current evidence (Google Search Central blog 2024-03 + clarifying posts 2024-05/2025):** Helpful Content System integrated into core in March 2024. The classifier is **site-wide**: a meaningful share of unhelpful content drags helpful pages on the same site. There is no separate "Helpful Content Update" anymore — every core update incorporates this signal.
- **Action:** [Phase 3](PHASE-3-TECHNICAL.md) and [Phase 4](PHASE-4-CONTENT.md) include a *prune-before-publish* gate. Programmatic launches must pass [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md) to avoid dragging the rest of the site.

## March 2024 spam policies

- **Guide §10 / §18:** correctly warns against scaled content, expired-domain abuse, and site-reputation abuse.
- **Current evidence:** all three policies are confirmed and actively enforced. Site reputation abuse enforcement live since 2024-05-05.
- **Action:** confirms the guide; explicit per-policy gates added to [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md) and [PHASE-7-AUTHORITY](PHASE-7-AUTHORITY.md).

## April 2026 back-button hijacking policy

- **Guide §6 / §10:** warns against deceptive UX patterns, but does not explicitly call out browser-history manipulation.
- **Current evidence (Google Search Central blog 2026-04-13 + spam policies page):** back-button hijacking is now an explicit malicious-practices spam-policy violation. Google defined it as interfering with browser navigation by manipulating history or similar behavior, and announced enforcement beginning 2026-06-15.
- **Action:** add a release QA tripwire anywhere the SaaS changes SPA routing, `history.pushState`, `history.replaceState`, modal/overlay flows, exit-intent flows, interstitials, ad/affiliate redirects, or consent flows. See [AUDIT-CHECKLIST](AUDIT-CHECKLIST.md), [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md), [PHASE-10-FRESH-EYES](PHASE-10-FRESH-EYES.md), and [PHASE-12-VERIFICATION](PHASE-12-VERIFICATION.md).

## AI Overviews / AI Mode

- **Guide §17:** treat answer engines as additional discovery surface; basics still matter.
- **Current evidence (B2B SaaS citation studies, early 2026; volatile market observations, not Google-official facts):**
  - AI Overviews and AI Mode share only ≈14 % of cited URLs — they are *separate citation surfaces*.
  - Citation-from-top-10 dropped from ≈76 % (mid-2025) to ≈38 % (early 2026) — the top-10 anchor is weakening.
  - ≈92 % of cited domains still rank in top 10 (domain-level correlation higher than URL-level).
  - Pages with three or more unique data points are ≈4 × more likely to be cited.
  - Cited pages get ≈35 % CTR uplift on AI-Overview SERPs vs non-cited competitors.
  - Different platforms (ChatGPT / Perplexity / AI Overviews) have different citation patterns and require platform-specific strategies.
- **Action:** AI visibility is a *separate workstream*, not a side effect of organic. See [AI-VISIBILITY](AI-VISIBILITY.md). Treat these numeric estimates as `likely` only when the methodology, query set, source, and recheck-by date are logged. The durable rule is source-backed extractability: every priority page needs multiple unique data points (research, screenshots, internal benchmark, dated quote, original analysis) visible in initial HTML.

## Schema policy

- **Guide §16:** policy summary correct; calls out `HowTo` deprecated, `Sitelinks Searchbox` retired, `FAQPage` rich results limited to authoritative gov/health.
- **Current evidence (Google Search Central / structured-data documentation 2026):** confirmed.
- **Action:** [SCHEMA-POLICY](SCHEMA-POLICY.md) reinforces. For SaaS pricing/feature pages prefer `WebApplication` over `SoftwareApplication` (closer match for cloud products); `Product` + `Offer` for plan pages; `BreadcrumbList` sitewide; `Organization` + `WebSite` on the homepage.

## RSC streaming + JS rendering

- **Guide §6 (rendering diagnostics) + Agent Perspective 12:** correctly emphasizes raw vs rendered HTML diff.
- **Current evidence (Google JavaScript SEO docs + Next.js metadata docs, reviewed 2026-04-30):** Googlebot can render JavaScript after crawl. Next.js streaming metadata is interpreted correctly by bots that execute JavaScript and inspect the full DOM, while HTML-limited bots keep metadata blocking in `<head>`.
- **Critical addendum:** answer-engine retrieval bots and AI crawlers vary. Do not assume JavaScript execution unless the bot's docs and the target site's own fetch/render probes prove it.
- **Action:** raw-HTML fidelity is the cross-crawler contract. [Phase 12](PHASE-12-VERIFICATION.md) verifies Googlebot render and AI/retrieval-bot initial HTML separately. Stream what is dynamic, but ensure title / meta / canonical / primary content / primary structured data / primary links are in the initial response.

## llms.txt

- **Guide §17:** "consider `llms.txt` as a low-cost documentation convenience, not a proven ranking factor."
- **Current evidence (300k-domain analysis 2026-Q1, AI bot logs):** no statistically significant correlation between `llms.txt` presence and AI citation. Among the top-50 most AI-cited domains, 1 has `llms.txt`. AI bots fetch `llms.txt` < 0.1 % of total AI crawler hits. No major AI vendor has publicly committed to act on it.
- **Action:** confirms the guide. Treat as optional documentation. Do not invest as a ranking tactic.

## Crawl budget

- **Guide §6:** crawl budget mostly matters for large, fast-changing, or technically complex sites.
- **Current evidence:** unchanged.
- **Action:** confirms. T1/T2 sites skip log-file analysis; T3+ engage subagents/log-analyst.md.

## Faceted nav and parameter URLs

- **Guide §10:** correct treatment.
- **Current evidence:** unchanged.
- **Action:** confirms.

## Outdated tactics the guide rejects

- Keyword density targets, keyword meta tag, exact-match domains, paginate-all-canonical-to-page-1, schema for ranking lift, deprecated rich results — current evidence confirms all.

## Confidence levels

| Claim | Confidence |
|---|---|
| INP <=200ms and >500ms thresholds | confirmed (web.dev / Google official) |
| INP position-drop magnitudes | hypothesis unless source-logged; likely only with disclosed methodology |
| Helpful Content as site-wide classifier in core | confirmed (Google official) |
| March 2024 spam policies enforcement | confirmed (Google official + observed enforcement) |
| Back-button hijacking as malicious-practices violation | confirmed (Google official; enforcement announced for 2026-06-15) |
| AI Overview ↔ AI Mode citation overlap ≈14 % | likely (single multi-vendor analysis) |
| AI bot non-JS rendering | likely as an operational default; confirm per bot/property |
| Googlebot JavaScript rendering | confirmed (Google official) |
| Next.js streaming metadata support for Googlebot and HTML-limited bots | confirmed (Next.js docs) |
| llms.txt no-correlation | likely (one large study, weak prior) |
| Schema deprecations (HowTo, Sitelinks Searchbox, broad FAQ) | confirmed (Google official) |

When current evidence is `likely` rather than `confirmed`, mark recommendations downstream of it as `likely` too. Do not propagate uncertainty as certainty.
