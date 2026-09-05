# HREFLANG-COOKBOOK

Hreflang says *which page is for which language and region*. Done right, it consolidates signals across locales and prevents the wrong locale from outranking the right one. Done wrong, it wastes effort or worse — traps verified Googlebot in the wrong region and tanks all locales.

Only Google and Yandex use `hreflang` (`confirmed`). Bing uses `Content-Language` header + on-page heuristics; AI bots largely ignore it.

## Phase mapping

| Phase | Use this doc for |
|---|---|
| 1 — Discovery | Catalogue current `hreflang` implementation; reciprocity audit. |
| 3 — Technical | Validate language/region codes, `x-default`, reciprocity per priority page. |
| 5 — IA | Decide single-locale vs multi-locale; route structure. |
| 6 — Implementation | Add `hreflang` via App Router; sitemap entries; HTTP headers if PDF/non-HTML. |
| 12 — Verify | Post-deploy hreflang reciprocity check. |

## Decide before implementing

```
Does the SaaS have meaningful regional differentiation?
│
├── Different language (en/de/fr/es/ja) → hreflang yes
│
├── Same language, different country (en-US / en-GB / en-AU)
│   ├── Different pricing / currency / availability / legal? → hreflang yes
│   └── Otherwise → single locale; do not split
│
├── Same language, same country, separate pages for some other reason
│   └── Probably not hreflang; use canonical to consolidate
│
└── Site is single-locale → no hreflang
```

`anti-pattern`: launching `en-US`, `en-GB`, `en-CA`, `en-AU` with identical content. Cannibalization risk; pick one.

## Three implementation methods

| Method | Best for | Cost | Notes |
|---|---|---|---|
| HTML `<link rel="alternate" hreflang>` | HTML pages | low | Most common; per-page |
| HTTP `Link` header | PDFs, non-HTML, large sets | medium | Useful when HTML edits not feasible |
| XML sitemap `xhtml:link` | Many pages, sitewide management | high upfront, low ongoing | Maintains reciprocity centrally |

Pick *one* method per page. Mixing on the same page is allowed but error-prone.

### Method 1 — HTML `<link>` (App Router)

```tsx
// app/[locale]/pricing/page.tsx
import type { Metadata } from "next";

const LOCALES = [
  { code: "en-US", path: "/en/pricing" },
  { code: "en-GB", path: "/en-gb/pricing" },
  { code: "de-DE", path: "/de/pricing" },
  { code: "ja-JP", path: "/ja/pricing" },
] as const;

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const base = "https://www.example.com";
  return {
    alternates: {
      canonical: `${base}/${locale}/pricing`,
      languages: Object.fromEntries(
        LOCALES.map((l) => [l.code, `${base}${l.path}`]),
      ),
      // x-default
      // (Next.js Metadata API: pass via languages with the key "x-default")
    },
  };
}
```

This produces `<link rel="alternate" hreflang="en-US" href="https://www.example.com/en/pricing">` and one row per locale.

`x-default`: add a `"x-default": "https://www.example.com/en/pricing"` entry. Required when you have a language picker or chooser; signals the fallback.

### Method 2 — HTTP `Link` header (non-HTML)

```
Link: <https://www.example.com/whitepaper.pdf>; rel="alternate"; hreflang="en-US",
      <https://www.example.com/de/whitepaper.pdf>; rel="alternate"; hreflang="de-DE",
      <https://www.example.com/whitepaper.pdf>; rel="alternate"; hreflang="x-default"
```

Set on the response (Vercel headers, Cloudflare Workers, NGINX `add_header`).

### Method 3 — XML sitemap

```xml
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
        xmlns:xhtml="http://www.w3.org/1999/xhtml">
  <url>
    <loc>https://www.example.com/en/pricing</loc>
    <xhtml:link rel="alternate" hreflang="en-US" href="https://www.example.com/en/pricing"/>
    <xhtml:link rel="alternate" hreflang="de-DE" href="https://www.example.com/de/pricing"/>
    <xhtml:link rel="alternate" hreflang="x-default" href="https://www.example.com/en/pricing"/>
  </url>
  <url>
    <loc>https://www.example.com/de/pricing</loc>
    <xhtml:link rel="alternate" hreflang="en-US" href="https://www.example.com/en/pricing"/>
    <xhtml:link rel="alternate" hreflang="de-DE" href="https://www.example.com/de/pricing"/>
    <xhtml:link rel="alternate" hreflang="x-default" href="https://www.example.com/en/pricing"/>
  </url>
</urlset>
```

Each URL declares its own alternates including itself (self-reference required, `confirmed`).

## Language and region codes

`confirmed`: Google parses ISO 639-1 (language) and ISO 3166-1 alpha-2 (region). Use only these.

| Code | Meaning |
|---|---|
| `en` | English (any region) |
| `en-US` | English, United States |
| `en-GB` | English, United Kingdom |
| `en-001` | English, world (use sparingly) |
| `de` | German (any region) |
| `de-DE` | German, Germany |
| `de-AT` | German, Austria |
| `pt-BR` | Portuguese, Brazil (different from `pt-PT`) |
| `zh-Hans` | Chinese, Simplified script |
| `zh-Hant` | Chinese, Traditional script |
| `x-default` | Fallback / language picker |

`anti-pattern`: `hreflang="EN"` (case is fine but spec is lowercase), `hreflang="us"` (region without language), `hreflang="en-uk"` (`UK` is not a valid ISO region; use `GB`).

## `x-default` rules

| Scenario | `x-default` value |
|---|---|
| Language picker on `/` that does not redirect | `/` |
| Default language is `en-US`; chooser at top of page | `https://www.example.com/en/...` |
| Auto-detection page redirects users | The fallback URL (rare; auto-redirect is anti-pattern) |
| Single-language site | Don't add `x-default` (no need) |

## Reciprocity audit

`hreflang` is reciprocal. If `A` declares `B` as alternate, `B` must declare `A`. Otherwise Google ignores the declaration (`confirmed`).

`scripts/hreflang-audit.ts`:

```ts
async function audit(urls: string[]) {
  const map = new Map<string, Set<string>>();
  for (const url of urls) {
    const html = await (await fetch(url)).text();
    const alternates = [...html.matchAll(/<link[^>]+hreflang=["']([^"']+)["'][^>]+href=["']([^"']+)["']/g)]
      .map((m) => m[2]);
    map.set(url, new Set(alternates));
  }
  for (const [url, alts] of map) {
    for (const alt of alts) {
      if (alt === url) continue;
      const back = map.get(alt);
      if (!back || !back.has(url)) {
        console.log(`MISSING RECIPROCAL: ${url} → ${alt}`);
      }
    }
  }
}
```

Threshold:

| State | Severity |
|---|---|
| All declarations reciprocal | green |
| 1–5% missing (typical drift) | medium |
| > 5% missing | high — Google ignores most of the cluster |
| Self-reference missing | high |
| Invalid language/region code | high |

## Locale routing on Next.js

Recommended structure:

```
app/
├── [locale]/
│   ├── layout.tsx
│   ├── page.tsx
│   ├── pricing/
│   │   └── page.tsx
│   ├── integrations/
│   │   ├── page.tsx
│   │   └── [slug]/
│   │       └── page.tsx
│   └── ...
└── layout.tsx       # root: html lang="en" or dynamic
```

```tsx
// app/[locale]/layout.tsx
import type { Metadata } from "next";

export async function generateStaticParams() {
  return [{ locale: "en" }, { locale: "de" }, { locale: "ja" }];
}

export default async function LocaleLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  return <html lang={locale}>{children}</html>;
}
```

Notes:

- `generateStaticParams` enumerates the locales the team can maintain. Don't ship locales without translation owners.
- `<html lang>` should match the locale. Avoid `lang="en"` on a `/de/...` page.
- For `Date`/`Number` formatting, use `Intl` with the `locale` from params.

## Geo-redirect anti-patterns

`anti-pattern` (`confirmed` per Google docs):

```ts
// DO NOT DO THIS
if (req.headers.get("x-vercel-ip-country") === "DE") {
  return NextResponse.redirect("/de" + req.nextUrl.pathname, 302);
}
```

Why: Googlebot Smartphone usually crawls from US IPs. The redirect traps the crawler at `/de/...`, treats `/de` as the canonical for everything, and breaks `en-US` indexing. Multiply by every locale and you have lost search across all locales.

What to do instead:

- Show a *banner* offering the alternate locale ("Looking for German? `de`").
- Let users click to switch; remember their choice in a cookie.
- Do not redirect verified search crawlers; if you geo-redirect users, exempt verified Googlebot/Bingbot/AI bots by user agent + reverse DNS.

## Currency / availability / legal alignment

Same-language regional split is justified only if the page genuinely differs. Audit per locale:

| Field | en-US | en-GB | en-AU |
|---|---|---|---|
| Currency | USD | GBP | AUD |
| VAT / tax included? | no | yes | yes |
| Pricing tier limits | unchanged | unchanged | unchanged |
| Compliance disclosures | CCPA | UK GDPR + ICO | Privacy Act 1988 |
| Phone support hours | 9am–6pm ET | 9am–6pm GMT | 9am–6pm AEST |
| Customer logos | US | UK + EU | AU + NZ |

If the rows are mostly identical, do not split — `hreflang` will not help; canonical to one URL.

## Partial-rollout strategies

You don't have to launch all locales at once.

| Strategy | When |
|---|---|
| Single canonical, no `hreflang` | All locales identical; site is single-language |
| Subset of pages translated | Translate top 20 commercial pages first; declare `hreflang` only on translated pages |
| New locale launch | Add new locale's URLs to all pages' `hreflang` clusters in same PR; otherwise reciprocity breaks |

Operational rule: never ship a partial new locale. Either the locale's pages all declare correct `hreflang` to all peers, or none of them do.

## Validation tools

- Google Search Console > International Targeting (legacy, still useful as of 2026 for cluster errors).
- `hreflang.org` validator (third-party; unofficial).
- `scripts/hreflang-audit.ts` reciprocity check (CI gate).
- Manual spot check via raw HTML curl per representative URL.

## When NOT to use hreflang

- Single-language site.
- Same-language same-region duplicate pages — use canonical.
- A/B test variants — never. `hreflang` is for languages, not experiments.
- Print versions / mobile alternates — those use other mechanisms (`rel="alternate" media`).
- One-off translated landing pages without a real locale family — consolidate.

## Per-tier depth

| Tier | Depth |
|---|---|
| T1 | Single locale; no `hreflang`. |
| T2 | If multi-locale: HTML method only; `x-default` on every page; reciprocity audit per release. |
| T3 | Sitemap method for high page counts; CI gate on reciprocity; locale-aware middleware for banner only. |
| T4 | Multiple locales, regional differentiation; per-locale content owners; quarterly cluster audit; locale-specific schema (currency, availability). |

## Worked example — adding `de-DE` to an `en-US` site

State 2026-04-15:
- Site is `en-US` only.
- Top 20 commercial pages translated to German by the content team.
- Routes: `/`, `/pricing`, `/security`, `/integrations`, `/integrations/[slug]` (×40), 14 blog posts.

Migration:

1. Restructure routes into `app/[locale]/...` with `en` as default. Set up `generateStaticParams` returning `["en", "de"]`.
2. Add 301 from `/pricing` → `/en/pricing` etc. (See [REDIRECT-PLAYBOOK](REDIRECT-PLAYBOOK.md).)
3. Localize hardcoded URLs in components (e.g. internal links to `/pricing` become locale-aware).
4. Set `<html lang>` from the route param.
5. Add `alternates.languages` in `generateMetadata` of every page; include `x-default = en` URL.
6. Generate per-locale sitemaps: `/sitemap-en.xml`, `/sitemap-de.xml`. Index sitemap references both.
7. Submit both sitemaps in GSC. Monitor `International Targeting` weekly for two weeks.
8. Add language picker in footer; cookie-based persistence; no auto-redirect.

Validation (T+0):

```bash
curl -s https://www.example.com/en/pricing | grep -i hreflang
# <link rel="alternate" hreflang="en-US" href="https://www.example.com/en/pricing">
# <link rel="alternate" hreflang="de-DE" href="https://www.example.com/de/pricing">
# <link rel="alternate" hreflang="x-default" href="https://www.example.com/en/pricing">
```

Run reciprocity audit; expect 100% green.

Validation (T+30):

- GSC International Targeting: no errors.
- `de-DE` clicks emerging in GSC for German queries.
- `en-US` clicks unchanged or up (reciprocal consolidation often helps).

Rollback:

- Drop `hreflang` declarations from `generateMetadata`. Keep route structure (no need to revert routes).
- Old sitemap restored (single).
- 301s reverted in `next.config.ts`.

## Anti-patterns

- Auto-redirecting based on IP geolocation.
- `hreflang` declared on a page whose alternate canonicalizes elsewhere.
- Missing self-reference (the page must declare itself in its own alternates list).
- `hreflang="UK"` instead of `hreflang="en-GB"`.
- Mixing methods (HTML + sitemap declaring different sets).
- `hreflang` for A/B test variants.
- Identical content under multiple locales.
- Missing `x-default` when a language picker exists.
- Stale `hreflang` after URL changes (each URL change must update all peers' alternates).
- `hreflang` on `noindex` page (Google ignores; remove or remove `noindex`).
- `hreflang` from `en-GB` to `en-US` page that is `noindex` for region.

## Cross-references

- [NEXTJS-PATTERNS](NEXTJS-PATTERNS.md) — Internationalization section.
- [REDIRECT-PLAYBOOK](REDIRECT-PLAYBOOK.md) — locale split scenarios.
- [SCHEMA-COOKBOOK](SCHEMA-COOKBOOK.md) — locale-specific currency / availability in `Offer`.
- [STACK-ADAPTERS](STACK-ADAPTERS.md) — non-Next.js stacks.
- [PHASE-3-TECHNICAL](PHASE-3-TECHNICAL.md) — international targeting audit step.
- [PHASE-12-VERIFICATION](PHASE-12-VERIFICATION.md) — post-deploy reciprocity check.
- [OPERATORS](OPERATORS.md) ⇆ Locale-Loop Check.
- [ANTI-PATTERNS](ANTI-PATTERNS.md) — locale-specific anti-patterns.
