# PHASE 1 — DISCOVERY & BASELINE

Goal: produce the substrate every later phase reads from. Diagnose before prescribing.

## Outputs

| File | Owner |
|---|---|
| `analyses/baseline-summary.md` | orchestrator |
| `analyses/representative-urls.json` | orchestrator |
| `analyses/template-inventory.md` | orchestrator |
| `analyses/ia-current.md` | orchestrator |
| `analyses/crawl/<urlhash>.{raw,rendered}.html` | discovery-crawler |
| `analyses/crawl/<urlhash>.json` (status, redirects, canonical, schema, links) | discovery-crawler |
| `analyses/gsc/{performance,coverage,sitemaps,manual-actions,cwv,enhancements}.json` | gsc-extractor |
| `analyses/ga4/{landing-pages,conversion-paths,branded-vs-nonbranded}.json` | ga4-extractor |
| `analyses/crux/<urlhash>.json` | cwv-collector |
| `analyses/lighthouse/<urlhash>.json` | cwv-collector |
| `analyses/log-analysis.md` (T3+ only) | log-analyst |
| `analyses/serp-snapshots/<query>.json` | serp-snapshotter |
| `analyses/seo-changelog.md` (initial annotation) | orchestrator |

## Subagent fan-out

Spawn in a single message with multiple Agent calls:

```
Agent({ description: "production crawl",  subagent_type: "Explore", prompt: "<see subagents/discovery-crawler.md>" })
Agent({ description: "gsc extract",        subagent_type: "Explore", prompt: "<see subagents/gsc-extractor.md>" })
Agent({ description: "cwv collect",        subagent_type: "Explore", prompt: "<see subagents/cwv-collector.md>" })
Agent({ description: "log analysis",       subagent_type: "Explore", prompt: "<see subagents/log-analyst.md>" })
Agent({ description: "serp baselines",     subagent_type: "Explore", prompt: "<see subagents/serp-snapshotter.md>" })
```

## Crawl scope

For each tier, the representative URL set:

| Tier | URL set |
|---|---|
| T1 | homepage, pricing, signup, security, about, blog index, top 5 blog posts, 1 docs page |
| T2 | + product / use-case pages, comparison pages, integration index + 5 integration detail, top 20 blog posts, top 5 docs |
| T3 | + every template family × 3 representative pages, top 50 blog, top 20 docs, paginated examples, faceted nav examples, internal-search examples |
| T4 | + per-locale, per-segment, per-marketplace template; >300 representative URLs |

`scripts/crawl.ts` accepts `--rep-set <tier>` and emits per-URL JSON + raw + rendered HTML.

## What to look for

- **Template inventory**: from `app/`, identify route groups, dynamic routes (`[slug]`), parallel routes, locale segments.
- **IA reverse-engineering**: parse `<nav>`, `<footer>`, breadcrumbs, in-content links from the homepage and the top 3 navigation hubs.
- **Status code health**: any non-200 in the representative set is a flag.
- **Redirect chains**: any chain > 1 hop is a flag.
- **Canonical agreement**: declared canonical vs sitemap inclusion vs internal-link target.
- **Render parity**: title, meta, canonical, h1, primary content, links — all in raw HTML?
- **Schema presence and validity**: per template.
- **Image weight**: above-fold images and total page weight.
- **Console errors**: hydration mismatches, fetch failures, runtime errors.
- **Server timing**: TTFB, LCP, INP from CrUX (field) + Lighthouse (lab).
- **Branded vs non-branded split**: GSC last 90 days.
- **Top organic landing pages**: GA4 last 90 days, conversions per page.

## Baseline summary structure

```md
# Baseline summary

## What this site is
- Stack: <Next.js 16 / Astro / etc>
- Hosting: <Vercel / etc>
- Tier: <T1–T4>

## Surface area
- Indexable URLs (estimate from sitemap + crawl): <N>
- Template families: <list>
- Locales: <list>

## Current organic
- 90-day clicks (GSC): <N>
- 90-day impressions: <N>
- Branded share: <%>
- Top 10 organic landing pages: <list with clicks>

## CWV health (CrUX p75)
- LCP / INP / CLS per template: <table>

## Search Console state
- Coverage: <indexed / excluded breakdown>
- Manual actions: <none / list>
- Enhancement errors: <list>

## Known issues observed during crawl
- <bullet list of flags before Phase 3 deep audit>

## Next phase
- Recommend <mode> based on findings.
- Phase 2/3 fan-out plan with subagent counts.
```

## Anti-patterns

- Skipping the crawl because GSC "looks fine".
- Reading rendered HTML only — render parity bugs hide there.
- Treating CrUX field data and Lighthouse lab data as interchangeable. They are not.
- Building the representative URL set from sitemap alone — missed orphans and faceted nav.
- Skipping the IA reverse-engineering because "we know the IA". Verify.
