# NEXTJS-PATTERNS

Current canonical patterns for SEO on Next.js 16 App Router. Verify against `nextjs.org/docs/app/api-reference` for the version actually in `package.json`.

## Root layout — site-wide foundation

```tsx
// app/layout.tsx
import type { Metadata } from "next";

export const metadata: Metadata = {
  metadataBase: new URL("https://www.example.com"),
  title: {
    default: "Acme — Description in 55–60 chars",
    template: "%s — Acme",
  },
  description: "150–160 char ad-copy-quality description. Lead with the outcome.",
  applicationName: "Acme",
  alternates: { canonical: "/" },
  openGraph: {
    type: "website",
    siteName: "Acme",
    locale: "en_US",
  },
  twitter: { card: "summary_large_image", site: "@acme" },
  robots: { index: true, follow: true },
  icons: { icon: "/favicon.ico", apple: "/apple-touch-icon.png" },
};
```

Notes:
- `metadataBase` is **required** for relative OG/Twitter image URLs to resolve. Missing it breaks social previews on every page.
- `title.template` only applies when child pages set `title` as a string. Pages that need a fully custom title use `title.absolute`.
- `alternates.canonical` at root sets the homepage canonical; per-route pages must override.

## Per-route metadata — static

```tsx
// app/pricing/page.tsx
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Pricing — plans, limits, and what's included",
  description: "Concrete useful description matching SERP intent.",
  alternates: { canonical: "/pricing" },
  openGraph: {
    title: "Acme Pricing",
    description: "...",
    url: "/pricing",
    images: [{ url: "/opengraph-image" }], // resolved against metadataBase
  },
};
```

## Per-route metadata — dynamic

```tsx
// app/integrations/[slug]/page.tsx
import type { Metadata } from "next";
import { getIntegration } from "@/lib/integrations";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const integration = await getIntegration(slug);
  if (!integration) {
    return { title: "Integration not found", robots: { index: false } };
  }
  return {
    title: `${integration.name} integration — connect ${integration.name} to Acme`,
    description: integration.shortDescription,
    alternates: { canonical: `/integrations/${slug}` },
    openGraph: {
      url: `/integrations/${slug}`,
      images: [{ url: `/integrations/${slug}/opengraph-image` }],
    },
  };
}
```

Notes:
- Fetches inside `generateMetadata` are memoized for the matching request — call them again inside the page component without re-fetching.
- For dynamically rendered pages, Next.js can stream metadata and inject it once `generateMetadata` resolves. The Next.js docs state Googlebot interprets streamed metadata, while HTML-limited bots get blocking metadata in `<head>`. Verify the installed Next.js version before relying on this behavior.
- `params` is a `Promise` in Next.js 16 — `await` it.
- For 404 cases, set `robots: { index: false }` rather than relying on the framework's not-found page metadata.

## Streaming metadata and `htmlLimitedBots`

Next.js 15.2+ can stream metadata: capable crawlers and browsers may receive metadata after the initial UI, while HTML-limited bots receive blocking metadata in `<head>`. Next.js 16 exposes `htmlLimitedBots` in `next.config.ts` for advanced overrides.

Default stance:

- Do not override `htmlLimitedBots` unless a measured crawler or social preview tool is missing critical metadata.
- If you override, remember it replaces Next.js's default list. Include any bot you still need to treat as HTML-limited.
- For conservative SEO launches, test both normal browser UA and representative bot UAs before and after changing the config.
- If a SaaS cannot tolerate streamed metadata for any crawler during launch week, temporarily use `htmlLimitedBots: /.*/`, then remove once Phase 12 proves the target bots handle the default.

Example targeted override:

```ts
// next.config.ts
import type { NextConfig } from "next";

const config: NextConfig = {
  htmlLimitedBots: /facebookexternalhit|Twitterbot|Slackbot|MyEnterpriseCrawler/,
};

export default config;
```

Verification:

```bash
curl -A "Twitterbot/1.0" -s https://www.example.com/pricing | rg '<meta|<title|canonical'
curl -A "Googlebot/2.1" -s https://www.example.com/pricing | rg '<meta|<title|canonical'
curl -A "OAI-SearchBot/1.0" -s https://www.example.com/pricing | rg '<meta|<title|canonical'
```

If metadata appears in `<body>` for normal browsers, that can be expected with streaming metadata. If it is missing from HTML-limited bot responses, treat as a release blocker.

## sitemap.ts

```ts
// app/sitemap.ts
import type { MetadataRoute } from "next";
import { listPublicSlugs } from "@/lib/cms";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const base = "https://www.example.com";
  const staticPages = ["", "/pricing", "/about", "/security", "/changelog"].map(
    (path) => ({
      url: `${base}${path}`,
      lastModified: new Date(),
      changeFrequency: "weekly" as const,
      // Native sitemap priority is a third-party 0.0-1.0 field, not a
      // skill-owned score_0_1000.
      priority: path === "" ? 1 : 0.8,
    }),
  );
  const integrations = (await listPublicSlugs("integrations")).map((slug) => ({
    url: `${base}/integrations/${slug}`,
    lastModified: new Date(),
    changeFrequency: "monthly" as const,
    priority: 0.6,
  }));
  return [...staticPages, ...integrations];
}
```

For large sites, split into multiple sitemap files via the sitemap-index pattern: `app/sitemap.ts` returns the index; `app/(marketing)/sitemap.ts`, `app/(docs)/sitemap.ts` etc. return per-segment sitemaps. Keep each under 50k URLs and 50 MB uncompressed.

Operational rules:
- Include only canonical, indexable URLs.
- `lastModified` updated only when the page changed *meaningfully*. Don't fake freshness with `new Date()` on every build.
- Remove redirected, noindexed, gated, or 404 URLs.

## robots.ts

```ts
// app/robots.ts
import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: ["/"],
        disallow: ["/api/", "/admin/", "/account/", "/dashboard/"],
      },
      // Optional AI-bot policy — document the decision in seo-changelog.md
      // { userAgent: "GPTBot", disallow: ["/"] },
      // { userAgent: "ClaudeBot", disallow: ["/"] },
    ],
    sitemap: "https://www.example.com/sitemap.xml",
    host: "https://www.example.com",
  };
}
```

Notes:
- Don't block CSS, JS, image, or API resources required for rendering.
- AI-bot policy is a business decision, not a default. Document it.
- Crawler rules in `robots.txt` *do not* remove already-indexed pages — use `noindex` for that and keep the page crawlable.

## Structured data — JSON-LD

Render JSON-LD from a Server Component, never via `useEffect`:

```tsx
// app/components/JsonLd.tsx
export function JsonLd({ data }: { data: object }) {
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(data) }}
    />
  );
}
```

```tsx
// app/layout.tsx — site-wide Organization + WebSite
import { JsonLd } from "@/app/components/JsonLd";

export default function RootLayout({ children }: { children: React.ReactNode }) {
  const organization = {
    "@context": "https://schema.org",
    "@type": "Organization",
    name: "Acme",
    url: "https://www.example.com",
    logo: "https://www.example.com/logo.png",
    sameAs: [
      "https://github.com/acme",
      "https://x.com/acme",
      "https://www.linkedin.com/company/acme",
    ],
  };
  const website = {
    "@context": "https://schema.org",
    "@type": "WebSite",
    name: "Acme",
    url: "https://www.example.com",
  };
  return (
    <html lang="en">
      <body>
        <JsonLd data={organization} />
        <JsonLd data={website} />
        {children}
      </body>
    </html>
  );
}
```

Per-page schema (e.g. pricing as `WebApplication` + `Offer`):

```tsx
// app/pricing/page.tsx
const webApplication = {
  "@context": "https://schema.org",
  "@type": "WebApplication",
  name: "Acme",
  applicationCategory: "BusinessApplication",
  operatingSystem: "Any (web-based)",
  offers: [
    { "@type": "Offer", name: "Starter", price: "29", priceCurrency: "USD",
      priceSpecification: {
        "@type": "UnitPriceSpecification", price: "29", priceCurrency: "USD",
        unitText: "MONTH" } },
    { "@type": "Offer", name: "Pro", price: "99", priceCurrency: "USD",
      priceSpecification: {
        "@type": "UnitPriceSpecification", price: "99", priceCurrency: "USD",
        unitText: "MONTH" } },
  ],
};
```

Rules:
- Schema must mirror visible content. Don't claim aggregateRating without real, visible reviews.
- Validate every template after change via `scripts/validate-schema.ts`.
- For SaaS prefer `WebApplication` over `SoftwareApplication` (more accurate for cloud).
- `BreadcrumbList` on every breadcrumbed page.

## Dynamic OG / Twitter images

```tsx
// app/integrations/[slug]/opengraph-image.tsx
import { ImageResponse } from "next/og";
import { getIntegration } from "@/lib/integrations";

export const runtime = "edge";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function Image({ params }: { params: { slug: string } }) {
  const integration = await getIntegration(params.slug);
  return new ImageResponse(
    (
      <div style={{ /* layout */ }}>
        <h1>{integration?.name ?? "Integration"} × Acme</h1>
        <p>{integration?.shortDescription}</p>
      </div>
    ),
    size,
  );
}
```

Notes:
- Bundle limit ≈500 KB total (fonts + JSX + helpers). Loading a heavy font kills it.
- Cache aggressively: `Cache-Control: public, max-age=3600, stale-while-revalidate=86400`.
- See `/og-share-images` for full layout patterns.
- Generate `twitter-image.tsx` separately if Twitter card differs.

## Redirects

`next.config.ts` for static, repo-known redirects:

```ts
const config = {
  async redirects() {
    return [
      { source: "/old-blog/:slug", destination: "/blog/:slug", permanent: true },
      { source: "/sign-up", destination: "/signup", permanent: true },
    ];
  },
};
```

Middleware for dynamic / per-request redirects (e.g. host canonicalization, locale negotiation, auth-required routes). Keep the middleware matcher narrow — it runs on every request.

Edge config (Vercel) for high-volume host/protocol/locale rules where `next.config` would be cumbersome.

Rules:
- One canonical host (with or without `www`); `301` from the other.
- HTTPS everywhere, no mixed content.
- `301` for permanent moves; `302` only for genuinely temporary.
- One-hop redirects only — chain audit in [Phase 3](PHASE-3-TECHNICAL.md).
- After migrations, crawl old URL set to confirm correct destinations.

## Performance — INP / LCP / CLS

- **LCP image:** `<Image src priority width height />` for above-fold; never lazy-load.
- **Fonts:** `next/font` with `display: "swap"` and self-hosted via the framework.
- **JS:** keep marketing pages free of dashboard-tier JS. Don't import the chart library in `app/(marketing)/layout.tsx`.
- **Consent banner:** non-blocking, no layout shift, no main-thread block on mount.
- **Cache Components (Next 16+):** `use cache` directive, `cacheLife`, `cacheTag`, PPR; see `/vercel:next-cache-components`.
- **Streaming:** stream below-fold sections via Suspense; keep the LCP candidate in the static shell.

CWV measurement:
- CrUX API for field data (the actual ranking signal).
- Lighthouse CI for lab data — used as diagnostic, not as the field-data substitute.
- `scripts/cwv-by-component.ts` attributes INP to specific component patterns when a regression appears.

## Internationalization

- One `hreflang` implementation method (HTML `<link rel="alternate" hreflang>` is most common in Next.js).
- Use `app/[locale]/...` route group with `generateStaticParams` for locales the team can maintain.
- Each localized page references itself + alternates.
- `x-default` for the language selector / fallback.
- Don't auto-redirect verified search crawlers or block users from reaching other locales.
- See [STACK-ADAPTERS](STACK-ADAPTERS.md) for non-Next.js stacks.

## Common Next.js SEO bugs

| Bug | Symptom | Fix |
|---|---|---|
| `metadataBase` missing | OG images show as relative URLs and break preview | Set in root layout |
| `generateMetadata` is `async` but `params` not awaited | Build error or undefined slug at runtime | `await params` |
| `htmlLimitedBots` override drops default HTML-limited crawlers | Social previews / enterprise crawlers miss title, canonical, OG | Avoid override; or include every required bot and verify with curl |
| JSON-LD injected from `useEffect` | Crawler / AI bot misses it | Render from Server Component |
| Pricing page `useState` for plan toggle blocks INP | INP regression on pricing | Server-render default; URL query state for toggle |
| `app/sitemap.ts` includes draft / preview URLs | GSC coverage warnings | Filter to `published` in the data fetch |
| Middleware runs on `/_next/...` and image routes | Performance regression, sometimes redirect loops | Restrict matcher: `["/((?!_next|api|.*\\..*).*)"]` |
| Locale redirect on root traps Googlebot | `/` redirects to `/en` always | `x-default`, no auto-redirect for verified crawlers |
| `priority` on every image | LCP candidate competes with siblings | One `priority` per page; rest lazy-load |
| Consent banner mounts before main content | LCP regression + CLS | Lazy mount banner after first paint; pre-allocate height |
| `next/og` exceeds 500 KB | Cryptic deploy error | Drop heavy fonts; subset; remove SVG-as-component |
