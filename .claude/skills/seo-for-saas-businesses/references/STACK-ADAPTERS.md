# STACK-ADAPTERS

[NEXTJS-PATTERNS](NEXTJS-PATTERNS.md) is the default. Translate per stack as below. The methodology and audit format do not change.

## Astro

| Surface | Astro equivalent |
|---|---|
| `metadataBase` + `<title>` template | `src/layouts/Layout.astro` with `import.meta.env.SITE` and slot-driven title |
| Per-page metadata | Frontmatter + `<head>` block in each `.astro` page |
| Dynamic metadata | Astro page `getStaticPaths` + `prerender` settings |
| `sitemap.ts` | `@astrojs/sitemap` integration; configure `customPages`, `filter`, and `serialize` |
| `robots.ts` | `public/robots.txt` static file (regenerate via build script if needed) |
| Structured data | JSON-LD in `.astro` `<script type="application/ld+json">` (no need for client component) |
| OG / Twitter images | `astro-og-canvas` or `@astrojs/image` + Satori |
| Redirects | `astro.config.mjs` `redirects` map |
| Performance | Astro is mostly islands; very few INP issues unless you add many React islands |

## Remix

| Surface | Remix equivalent |
|---|---|
| Per-page metadata | `meta` export from each route module |
| Dynamic metadata | `meta({ data, params })` |
| `sitemap.xml` / `robots.txt` | Resource routes (e.g. `app/routes/sitemap[.]xml.tsx` returning a Response) |
| Structured data | `<script type="application/ld+json">` in route component |
| OG / Twitter images | Satori-based resource route or static image |
| Redirects | Loader or middleware (Remix v3 supports proper middleware) |

## Rails

| Surface | Rails equivalent |
|---|---|
| Per-page metadata | View partial `_meta.html.erb`; controller variables for `@title`, `@description`, `@canonical` |
| `sitemap.xml` | `sitemap_generator` gem with daily cron OR rendered via controller for small sites |
| `robots.txt` | `public/robots.txt` |
| Structured data | View helper `json_ld_for(@page)` rendering `<script type="application/ld+json">` |
| OG / Twitter | View partial; image generation via `image_processing` or external Satori service |
| Redirects | `config/routes.rb` with `get '/old' => redirect('/new', status: 301)` |
| Performance | Turbo + Stimulus tend to be light; watch out for asset pipeline regressions |

## Django

| Surface | Django equivalent |
|---|---|
| Per-page metadata | Template inheritance (`base.html` block + per-template override) |
| `sitemap.xml` | `django.contrib.sitemaps` |
| `robots.txt` | `django-robots` or custom view |
| Structured data | Template tag rendering JSON-LD |
| Redirects | `django.contrib.redirects` or middleware |

## WordPress

| Surface | WordPress equivalent |
|---|---|
| Per-page metadata | Yoast / RankMath plugin manage title, description, canonical, OG, Twitter, schema |
| `sitemap.xml` | Yoast / RankMath generates |
| `robots.txt` | Yoast / RankMath generates from settings |
| Structured data | Yoast / RankMath base + theme hooks for custom types |
| OG images | Yoast / RankMath defaults; theme override for dynamic |
| Redirects | RankMath redirects manager or `Redirection` plugin |
| Performance | Theme + plugin landscape varies enormously; budget more time for performance audit |

## Static sites (11ty / Hugo / Jekyll)

| Surface | Equivalent |
|---|---|
| Per-page metadata | Front matter; layout `<head>` template |
| `sitemap.xml` | Plugin or template (e.g. Hugo's built-in sitemap) |
| `robots.txt` | Static file in publish root |
| Structured data | Template-rendered JSON-LD |
| OG / Twitter images | Build-time image generation pipeline |
| Redirects | Hosting layer (Netlify `_redirects`, Vercel `vercel.json`, Cloudflare `_redirects`) |

## Cross-stack invariants

Regardless of stack, the audit / verification scripts work the same way:

- `scripts/crawl.ts` reads URLs and reports raw HTML / rendered HTML / status / canonical / schema / links — stack-agnostic.
- `scripts/validate-schema.ts` validates extracted JSON-LD — stack-agnostic.
- `scripts/verify-prod.ts` Playwright-based — stack-agnostic.
- `scripts/cwv-check.ts` Lighthouse CI — stack-agnostic.
- `scripts/internal-links.ts` parses HTML — stack-agnostic.

Stack-specific adapters only matter for *implementation* in Phase 6. The audit (Phase 3) and verification (Phase 12) read the rendered output and don't care how it was produced.

## When the SaaS uses a stack not listed here

1. Find the equivalent surfaces for: per-page metadata, sitemap, robots, structured-data injection, redirects.
2. Translate the [NEXTJS-PATTERNS](NEXTJS-PATTERNS.md) translation matrix to the equivalent.
3. Document the mapping in `analyses/stack-adapter.md`.
4. Run the universal audit / verification scripts.
