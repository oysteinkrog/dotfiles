# DOCS-AND-SUPPORT-SEO

## TOC

What docs SEO actually is · Anatomy of a setup/how-to docs page · Error-message pages · Versioned docs canonicalization · Public vs private docs separation · Stack-specific patterns · Search-results / on-site search · Measurement · Tier depth selectors · Anti-patterns · Cross-links

Documentation and support pages are an SEO surface, an activation surface, and a deflection surface — usually simultaneously. They acquire users through long-tail technical queries, activate them through honest setup paths, and deflect support volume by answering the exact question the user typed in.

Phase mappings: Phase 1 (docs are often a separate property to crawl), Phase 3 (versioned-canonical audit, docs-search noindex policy), Phase 4 (per-page briefs for high-traffic docs), Phase 5 (cross-linking docs ↔ marketing ↔ status), Phase 6 (docs route group, version routing, search box noindex), Phase 8 (deflection KPI, activation KPI). Different from blog content; do not template them the same way.

## What docs SEO actually is

| Search query type | Page that should rank | Owner |
|---|---|---|
| `<product> setup <stack>` | `/docs/setup/<stack>` | Docs / DevRel |
| `<product> <feature>` | `/docs/<feature>` | Docs |
| `<exact error message>` | `/docs/errors/<code>` or `/docs/troubleshooting/<symptom>` | Support / Docs |
| `<product> API <endpoint>` | `/docs/api/<endpoint>` | API team |
| `<product> alternative to <feature>` | `/docs/<feature>#alternatives` or marketing comparison | Marketing |
| `how to <generic concept>` | Probably *not* a docs page; it's a blog post | Editorial |

Docs answers "how do I use this product"; the marketing site answers "should I use this product"; the blog answers "what is this concept". When boundaries blur, cannibalization follows. (`confirmed` — observed across multiple SaaS docs migrations)

## Anatomy of a setup / how-to docs page

```md
# Connect Acme to Snowflake

> Applies to: Acme Pro and Enterprise · Snowflake account with `ACCOUNTADMIN` access · Last verified 2026-04-30 against Snowflake 8.42

## Prerequisites
- Snowflake `ACCOUNTADMIN` role (or a role with `CREATE USER`, `GRANT`).
- A running Acme workspace on Pro or Enterprise.
- Network egress from your Snowflake account to `*.acme.com` on port 443.

## Steps

1. In Snowflake, create the read-only role:
   ```sql
   CREATE ROLE acme_reader;
   GRANT USAGE ON WAREHOUSE acme_wh TO ROLE acme_reader;
   GRANT USAGE ON DATABASE prod TO ROLE acme_reader;
   ```

2. In Acme, open **Settings → Connections → New → Snowflake**.
3. Paste the `account_locator` and the role name `acme_reader`.

## Expected output
A green `Connected` badge and a row count for the largest table within ~30 seconds. If you see a yellow `Partial`, Acme could reach Snowflake but the role lacks `SELECT` on at least one table — see [troubleshooting](#troubleshooting).

## Troubleshooting
- `Authentication failed`: verify the public key uploaded matches the private key in Acme; clock skew > 5 min triggers this.
- `Could not reach Snowflake`: check egress rules; Acme egresses from `52.x.x.x/24` (full list at [/docs/egress-ips](/docs/egress-ips)).

## Next steps
[Run your first query](/docs/queries/first) · [Schedule a sync](/docs/syncs/schedule)
```

Pattern checklist:

- [ ] Version / platform / plan / date callout in the **first 100 chars** of HTML.
- [ ] Prereqs listed before steps.
- [ ] Copy-paste blocks are valid (CI-tested where possible).
- [ ] "Expected output" section before troubleshooting.
- [ ] Troubleshooting links to the error-message pages.
- [ ] "Next step" link to the next docs page or status / support.

## Error-message pages

The error-message URL is the page that wins this query family. Build it deliberately.

```md
# `ACME_E_QUOTA_EXCEEDED` — Quota exceeded for the current plan

> Applies to: Acme Pro · Last verified 2026-04-30

## What it means
Acme stops accepting new sync requests for the current 24-hour window because the `requests_per_day` quota for your plan has been hit.

## Why it happens
- Plan limit reached (Pro: 10,000/day; Enterprise: configurable).
- Multiple integrations writing to the same workspace simultaneously.
- A misconfigured retry loop on the caller side.

## How to fix
1. Run `acme quota show` to see current vs limit.
2. If the limit has actually been hit, wait until UTC midnight or [upgrade to Enterprise](/pricing/enterprise).
3. If the limit is wrong, file a support ticket with the trace ID from the error response.

## Related
- [`ACME_E_RATE_LIMITED`](/docs/errors/ACME_E_RATE_LIMITED) — short-window rate limit (different from daily quota).
- [Plan limits](/pricing/limits)
```

Pattern checklist:

- [ ] Page H1 contains the **exact error string**, code-formatted.
- [ ] URL slug matches the error code: `/docs/errors/ACME_E_QUOTA_EXCEEDED`.
- [ ] Triage path: meaning → cause → fix → escalate.
- [ ] Link back to plan / pricing pages where relevant (commercial intent capture).
- [ ] Linked from the error response itself (in-product) and from the API docs.

This is the single highest deflection-per-page asset on a SaaS docs site. (`likely` — strong support-team-reported signal across multiple deployments)

## Versioned docs canonicalization

If your product has multiple supported versions (API v1, v2; SDK 4.x, 5.x; on-prem 2024.1, 2025.1, etc.):

| Version state | URL pattern | Canonical | Robots |
|---|---|---|---|
| Current (default) | `/docs/<page>` (no version in URL) | self | `index,follow` |
| Current (alternate URL with version) | `/docs/v2/<page>` | `/docs/<page>` | `index,follow` (canonical points to default) |
| Previous, still supported | `/docs/v1/<page>` | self | `index,follow` |
| Deprecated | `/docs/v0/<page>` | self with deprecation banner; or 301 to v1 if exact equivalent | `noindex,follow` once support window closes |
| Removed | n/a | n/a | `410 Gone` (preferred) or `301` to closest replacement |

Anti-pattern: canonicaling all versions to "latest". Users searching for `v1.4 quirks` get sent to `v3.0` which doesn't have those quirks. Loses both ranking and trust. (`confirmed`)

Switcher UX: visible version dropdown, version + date in a sidebar callout, clear "this version is deprecated as of <date>" banner where applicable.

## Public vs private docs separation

| Doc | Default | Why |
|---|---|---|
| Setup / how-to / API reference / errors | Public | Acquisition + activation + deflection |
| Account-specific dashboards in docs | Private (auth-walled) | Personal data; no SEO value |
| Internal runbooks | Private (often a separate site) | Not user-facing |
| Beta / unannounced features | Private until launch | Avoid leak indexing |
| Customer-specific tenant docs | Per-tenant private subdomain | Not indexable |

If a docs CMS (Mintlify, Nextra, GitBook, ReadMe.com) exposes "preview" URLs with content, robots-block them at the host level — many sites have leaked unreleased features through indexed preview branches. (`confirmed`)

## Stack-specific patterns

| Stack | SEO-relevant features | Watch out for |
|---|---|---|
| Mintlify | SSR, sitemap, search included; per-page `description` frontmatter; OpenGraph | Live-search component sometimes ships JS-only; verify search-results page is `noindex` |
| Nextra (Next.js) | Full Next.js metadata API; MDX with frontmatter | App Router `generateMetadata` per route; default theme has no `OpenGraph` defaults — set in root layout |
| Docusaurus | Sitemap plugin; `@docusaurus/plugin-sitemap`; SSR | Versioned docs noindex defaults differ across versions; check `noIndex` flag |
| GitBook | Hosted SEO defaults; sitemap auto | Limited control over canonical / structured data; consider self-hosting if SEO is load-bearing |
| ReadMe.com | Hosted; structured data baked in | Harder to add custom JSON-LD; subdomain reputation separate from main domain |
| Custom (Markdoc / MDX in Next.js) | Full control; standard Next.js patterns | All the responsibility — set canonical, OG, JSON-LD, sitemap segmentation explicitly |

For Markdoc / MDX in a Next.js docs site, mirror [NEXTJS-PATTERNS](NEXTJS-PATTERNS.md): one segment-level `sitemap.ts`, `generateMetadata` per route from frontmatter, server-rendered `Article` JSON-LD, breadcrumbs, version sidebar.

```tsx
// app/docs/[...slug]/page.tsx
export async function generateMetadata({ params }): Promise<Metadata> {
  const { slug } = await params;
  const doc = await loadDoc(slug.join("/"));
  return {
    title: `${doc.frontmatter.title} — Acme docs`,
    description: doc.frontmatter.description,
    alternates: { canonical: `/docs/${slug.join("/")}` },
    openGraph: { type: "article", url: `/docs/${slug.join("/")}` },
  };
}
```

## Search-results / on-site search

The on-site search results URL (e.g. `/docs/search?q=...`) must be `noindex`. Do not let infinite query strings into the index. Either:

- Render the search UI in a way that does not produce indexable URLs (client-side only with `noindex` meta on the route), or
- Set `X-Robots-Tag: noindex` on the route at the edge.

Mine the search log (Phase 1 input) for unmet demand. See [PHASE-1-DISCOVERY](PHASE-1-DISCOVERY.md) and the canonical guide §19 on-site search mining.

## Measurement

| Metric | Source | Cadence |
|---|---|---|
| Docs organic landing → trial / signup conversion | GA4 + product | Weekly |
| Time-to-first-action on cohort that hit a setup doc | Product analytics | Weekly |
| Support ticket volume per error code (vs error-page CTR) | Support tool | Weekly |
| Pageview deflection on top error-message pages | GSC + support | Monthly |
| Stale-content count (unverified > 90 days, version-mismatch) | `analyses/content-inventory.md` | Monthly |
| Failed-search rate on docs site | Docs analytics | Weekly |
| Schema validity per template | `scripts/validate-schema.ts` | CI |

KPI shape: docs sites trade *pageviews* for *outcomes*. A drop in pageviews while activation rate rises is a *good* docs deploy.

## Tier depth selectors

| Tier | Docs scope |
|---|---|
| T1 | A single getting-started page; no error-message pages yet |
| T2 | Setup per top stack; first 10 error-message pages from highest support-ticket queries |
| T3 | Full docs (setup, feature, API, errors, troubleshooting, changelog cross-link); versioned canonicalization; on-site search noindex |
| T4 | Multi-locale docs; multi-version with deprecation pipeline; per-product docs spaces; in-CI doc-build SEO checks |

## Anti-patterns

| Don't | Why | Do instead |
|---|---|---|
| Hide setup paths behind login walls | Crawlers can't see them; activation suffers | Public until configuration begins |
| Rely on the docs platform's defaults for canonical / OG | Drift, missing, or wrong on dynamic pages | Set explicitly per route |
| Canonical all versions to "latest" | Strands valid v1.4 queries; hurts trust | Self-canonical per supported version; deprecate explicitly |
| Index `/docs/search?q=...` | Doorway risk; thin pages | `noindex` the search route |
| Generate error pages from log scraping with no fix | Scaled-content abuse | Hand-author against actual fix paths; expand only with new fixes |
| Bury the date / version in the footer | AI extraction misses it; users don't trust freshness | Date / version callout in first 100 chars |
| Single `/docs` flat URL with anchor jumps for everything | Each anchor cannot rank independently | One URL per query family |
| Leave deprecated docs without a banner | User follows obsolete steps; trust collapse | "Deprecated as of <date>; see <new path>" |
| 301 deprecated docs to "latest" instead of the correct successor | Sends users to non-equivalent pages | 301 only to actual equivalents; otherwise keep with banner or 410 |
| `noindex` *all* old versions blanket | Cuts off long-tail queries that still convert | Only `noindex` past the formal support window |
| Auto-translate docs without review | Slop + technical-error compounding | Locale program with human review per [STACK-ADAPTERS](STACK-ADAPTERS.md) |
| Live-search widget that loads on docs landing | INP regression and main-thread cost | Mount on intersection or hover; see [INP-DEEP-DIVE](INP-DEEP-DIVE.md) |
| Render API reference from `useEffect` against an OpenAPI spec | AI bots see empty page | SSG or RSC the API reference; see [AI-VISIBILITY](AI-VISIBILITY.md) |
| Block AI bots site-wide on docs subdomain | Loses citation in ChatGPT / Perplexity / Claude for the exact technical questions you want them to cite | Decide per [AI-VISIBILITY](AI-VISIBILITY.md), document in changelog |

## Cross-links

- [LIFECYCLE-CONTENT](LIFECYCLE-CONTENT.md) — docs is the technical lifecycle surface.
- [NEXTJS-PATTERNS](NEXTJS-PATTERNS.md) — metadata, sitemap, JSON-LD patterns.
- [SCHEMA-POLICY](SCHEMA-POLICY.md) — `Article` for tutorials; do not use `HowTo` for rich results.
- [INP-DEEP-DIVE](INP-DEEP-DIVE.md) — search widgets and live-code playgrounds are common offenders.
- [AI-VISIBILITY](AI-VISIBILITY.md) — initial HTML and crawler policy.
- [PHASE-1-DISCOVERY](PHASE-1-DISCOVERY.md) — including docs in baseline crawl.
- [PROOF-LIBRARY-OPS](PROOF-LIBRARY-OPS.md) — screenshots and benchmarks reused across docs.
