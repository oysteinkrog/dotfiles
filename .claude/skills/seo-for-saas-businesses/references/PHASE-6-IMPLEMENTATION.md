# PHASE 6 — IMPLEMENTATION

Goal: translate audit findings + content briefs into shipped code, grouped into logically scoped PRs with tests, expected impact, and rollback paths.

## Default PR cadence (Next.js 16)

| PR | Scope | Phase 3 audit IDs |
|---|---|---|
| `seo/foundation` | `metadataBase`, `app/robots.ts`, `app/sitemap.ts`, redirect cleanups, canonical helper, `app/components/JsonLd.tsx` | foundation set |
| `seo/per-route-metadata` | `generateMetadata` on every public route + canonical alternates + OG/Twitter defaults | per-template meta items |
| `seo/structured-data` | Organization + WebSite (root), per-page schema (WebApplication / Product / Article / etc.), BreadcrumbList sitewide | schema items |
| `seo/og-images` | Dynamic OG/Twitter via `next/og` (use `/og-share-images`) | OG items |
| `seo/perf-cwv` | image, font, RSC, cache-components, deferred imports for INP/LCP/CLS regressions | perf items |
| `seo/internal-links` | Footer, breadcrumb, contextual links per IA plan | link items |
| `seo/content-<cluster>` | One per cluster from Phase 4 | content briefs |
| `seo/programmatic-<template>` | Gated, staged rollout per [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md) | programmatic items |

Each PR may pick up additional opportunistic fixes within scope. Don't grow PRs — ship a follow-up.

## Per-PR template

See [assets/PR-DESCRIPTION-TEMPLATE.md](../assets/PR-DESCRIPTION-TEMPLATE.md).

## Test plan per PR

| PR | Tests |
|---|---|
| `seo/foundation` | unit (sitemap returns canonical-only; robots disallows expected paths; JsonLd renders); Playwright (`/sitemap.xml` 200 + parses; `/robots.txt` 200) |
| `seo/per-route-metadata` | Playwright crawl across representative URLs; verify title, meta, canonical, OG present in raw HTML |
| `seo/structured-data` | `bun run scripts/validate-schema.ts` against representative URLs |
| `seo/og-images` | `scripts/verify-prod.ts --check og` per OG route; image dimensions + status |
| `seo/perf-cwv` | Lighthouse CI delta vs main; assert no regression on normalized perf `score_0_1000`; budget on INP/LCP |
| `seo/internal-links` | `scripts/internal-links.ts` orphans count; redirect-through-internal-link count |
| `seo/content-<cluster>` | Schema validates; AI-crawler view contains headline answer; slop-check passes |
| `seo/programmatic-<template>` | Sampled-page review pass; sitemap segment correct; kill-switch verified |

## Common implementation patterns

See [NEXTJS-PATTERNS](NEXTJS-PATTERNS.md) for code. Cross-stack adapters in [STACK-ADAPTERS](STACK-ADAPTERS.md).

## CWV regressions on marketing routes

Frequent culprits and fixes:

- **Chart library imported via shared layout** → move chart to dynamic import in only the routes that need it.
- **Marketing CRM widget on first paint** → defer until interaction or after LCP.
- **Consent banner blocks main thread** → lazy-mount after first paint; pre-allocate height to avoid CLS.
- **Animated hero** → static initial frame; opt-in animation on intersection.
- **Plan toggle uses heavy state library** → server-render default; URL query state for toggle.
- **Lazy-loaded LCP image** → `priority` (or non-lazy) for above-fold image.
- **Custom font loaded from CDN** → `next/font` with `display: "swap"` and self-hosted.
- **Dashboard fixtures imported during marketing build** → `'use server'` boundary; tree-shake.

## Per-PR safety rails

- **CODEOWNERS:** require approval from web/marketing for `app/(marketing)/`, security for `middleware.*`, platform for `next.config.*`.
- **Lighthouse CI gate:** PR cannot merge if INP, LCP, CLS, or normalized perf `score_0_1000` regress beyond budget.
- **Schema gate:** PR cannot merge if `scripts/validate-schema.ts` fails.
- **Build:** `bun run build` succeeds.
- **Type check:** `bun run typecheck` (or stack equivalent).

## Rollback paths

Every PR description ends with rollback. Default = `git revert <merge-sha>`. For programmatic PRs, the rollback also flips a config flag that:
1. Removes the template's URLs from sitemap.
2. Adds `noindex,follow` to all pages.
3. Optionally `301`s to the closest non-programmatic parent.

Test the rollback flag in staging before stage 1 launches.

## Annotation

After merge, append to `seo-changelog.md`:

```
## 2026-04-30 — seo/foundation merged
- Audit IDs: AUDIT-0023, AUDIT-0034, AUDIT-0078
- Expected impact: GSC sitemap coverage warnings clear; canonical signals consistent across cluster X
- Tracking metric: GSC coverage delta over 14 days; CrUX TTFB delta
- Recheck-by: 2026-05-14
- PR: <url>
```

Also annotate GSC and GA4 with the deploy timestamp.
