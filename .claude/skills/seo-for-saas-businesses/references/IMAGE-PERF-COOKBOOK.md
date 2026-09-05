# IMAGE-PERF-COOKBOOK

Concrete image patterns for SaaS marketing, blog, docs, and marketplace pages on Next.js 16. Images are the most common LCP candidate, the most common CLS source, and a frequent silent INP-via-decode offender. Get them right once and never think about them again.

Phase mappings: Phase 3 (per-template image audit), Phase 6 (`<Image>` wiring + sizes/priority), Phase 8 (CrUX LCP / CLS tracking), Phase 12 (post-deploy verification).

## Cardinal rules

| Rule | Why |
|---|---|
| Above-fold LCP image: `priority`, no `loading="lazy"` | Lazy-loading the LCP candidate is the #1 LCP regression in SaaS marketing |
| Always set `width` and `height` (or `fill` + sized container) | Prevents CLS from layout reflow when the image arrives |
| Use `sizes` whenever the image is responsive | Avoids serving 1920px to a 320px viewport |
| Prefer AVIF or WebP with sensible quality | 30–60% smaller than JPEG at perceptual parity (`confirmed`) |
| Self-host or use the Next.js / Vercel image loader | Third-party hot-linking adds a TLS handshake to LCP |
| One `priority` per page max | Multiple priority hints make the browser de-prioritize all of them |
| Decorative images: `alt=""` | Empty alt is the spec'd way to mark decorative; do not omit the attribute |

## Hero / LCP pattern

```tsx
// app/page.tsx — homepage hero
import Image from "next/image";
import heroImg from "@/public/hero.jpg"; // import for static analysis + width/height

export default function HomePage() {
  return (
    <section>
      <h1>Acme — connect every data source in 30 seconds</h1>
      <Image
        src={heroImg}
        alt="Acme dashboard showing 12 connected data sources and their last sync times"
        priority
        sizes="(max-width: 768px) 100vw, 1200px"
        placeholder="blur"
        // width/height inferred from static import
      />
    </section>
  );
}
```

Notes:

- `priority` injects `<link rel="preload" as="image">` and disables lazy.
- `placeholder="blur"` works automatically with static imports; for remote images pass `blurDataURL`.
- `alt` is descriptive — *what's in the image and why it matters*, not "Hero image".
- `sizes` matches the actual rendered max width.

## Card / grid pattern (below fold)

```tsx
// app/integrations/page.tsx — grid of integration cards
<Image
  src={integration.logo}
  alt={`${integration.name} logo`}
  width={64}
  height={64}
  sizes="64px" // fixed-size logo
  loading="lazy"
/>
```

For variable-sized cards in a grid:

```tsx
<Image
  src={card.thumbnail}
  alt={card.alt}
  width={400}
  height={225}
  sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 33vw"
  loading="lazy"
/>
```

Use `sizes` to express the *actual rendered size* across breakpoints; otherwise the browser picks the largest candidate from `srcset`.

## Background image — when to use `<Image>` vs CSS

| Use case | Choose |
|---|---|
| LCP-candidate hero | `<Image>` (so `priority` and preload work) |
| Decorative pattern with no semantic meaning | CSS `background-image` |
| Below-fold ambient | CSS `background-image` |
| Image that overlays text and needs `alt` | `<Image>` |
| Animated gradient | CSS gradient (no image at all) |

CSS background images do not get `srcset`, do not benefit from Next.js image optimization, and are not LCP candidates (they are paint, not content). Use them sparingly and only when the image carries no information.

## Responsive art direction (different image per breakpoint)

When the mobile and desktop hero are visually different (not just resized):

```tsx
<picture>
  <source media="(min-width: 768px)" srcSet="/hero-desktop.avif" type="image/avif" />
  <source media="(min-width: 768px)" srcSet="/hero-desktop.webp" type="image/webp" />
  <source media="(max-width: 767px)" srcSet="/hero-mobile.avif" type="image/avif" />
  <source media="(max-width: 767px)" srcSet="/hero-mobile.webp" type="image/webp" />
  <img src="/hero-desktop.jpg" alt="..." width={1200} height={600} fetchPriority="high" />
</picture>
```

`next/image` does not natively support art direction (different *images* per breakpoint, as opposed to different *sizes* of the same image). Drop to `<picture>` here. (`confirmed` per Next.js docs as of 16.x — verify if upgrading)

## CDN choices

| CDN | When | Notes |
|---|---|---|
| Vercel Image Optimization (default with `next/image`) | Default for Next.js on Vercel | Per-region cache; honours `formats` config (AVIF, WebP); rate limits on Hobby tier |
| Cloudflare R2 + Image Resizing | High-volume static asset hosting; cost matters | Configure `next.config.ts` `images.loader: "custom"` + a loader function pointing to Cloudflare Image Resizing |
| Cloudinary | Heavy art-direction needs; named transforms; existing investment | Custom loader; aggressive caching; watch the per-image cost |
| Self-hosted (S3 + image lambda) | Total control; specific encoding pipelines | Most engineering work; only justified at T4 scale |
| `imgix` / `bunny.net` / `imagekit` | Existing investment; vendor lock-in tradeoff | Custom loader works the same way |

Custom loader pattern:

```ts
// next.config.ts
const config = {
  images: {
    loader: "custom",
    loaderFile: "./image-loader.ts",
    formats: ["image/avif", "image/webp"],
  },
};
```

```ts
// image-loader.ts
export default function loader({ src, width, quality }) {
  const q = quality || 75;
  return `https://cdn.example.com/cdn-cgi/image/width=${width},quality=${q},format=auto/${src}`;
}
```

## Image-as-LCP debugging

When LCP is bad and the LCP candidate is an image:

| Symptom | Likely cause | Fix |
|---|---|---|
| LCP > 2.5 s, image is below fold but reported as LCP | Above-fold content is text-only and the image dominates after | Add a real LCP-eligible above-fold element, or pre-allocate the image's space to keep it as the candidate but accelerate it |
| LCP candidate is a 2 MB JPEG | No optimization | `<Image>` with format conversion + quality setting |
| LCP image arrives after every CSS file | Render-blocking CSS / fonts | Inline critical CSS; `font-display: swap`; preload the image |
| LCP image swaps mid-paint (low → high res) | Two `<img>` elements; or `placeholder="blur"` on a slow connection | Single image with proper sizes; or remove blur on slow connections |
| LCP delay correlated with consent banner | Banner mounts before main content | Render shell server-side; defer banner |
| LCP image lazy-loaded | `loading="lazy"` on what should be priority | Add `priority`; remove `loading="lazy"` |
| Image dimensions reflow as it loads | Missing `width`/`height` | Set both; CLS often drops to ~0 with this single fix |

## Image schema

For original visual evidence (product screenshots, charts, infographics) on AI-citation-worthy pages, include image schema so the resource is discoverable:

```json
{
  "@context": "https://schema.org",
  "@type": "ImageObject",
  "contentUrl": "https://www.example.com/og/dashboard-q1-2026.png",
  "license": "https://www.example.com/legal/image-license",
  "creditText": "Acme",
  "creator": {"@type": "Organization", "name": "Acme"},
  "datePublished": "2026-04-30"
}
```

Embed inside the `Article` schema's `image` array where applicable. See [SCHEMA-POLICY](SCHEMA-POLICY.md).

## OG / Twitter images

Different problem, different file. The OG image is a 1200×630 PNG used by social previews; it does not load on the page, so it does not affect LCP.

- Generated dynamically per route via `next/og` `ImageResponse`. See [NEXTJS-PATTERNS](NEXTJS-PATTERNS.md) and `/og-share-images`.
- Cache aggressively at the edge (`Cache-Control: public, max-age=3600, stale-while-revalidate=86400`).
- Verify in social-card debuggers (X / Slack / LinkedIn / Discord) post-deploy.

## Common bugs and fixes

| Bug | Symptom | Fix |
|---|---|---|
| Lazy-loading the LCP image | LCP > 4 s on mobile | Remove `loading="lazy"`; add `priority` |
| `srcset` with too-narrow `sizes` | Browser downloads largest candidate; LCP worse | Match `sizes` to actual rendered size |
| `decoding="async"` missed on large images | Decode blocks main thread before paint | `decoding="async"` (or `decoding="sync"` only for tiny critical images) |
| `fetchpriority="high"` on every image | Browser de-prioritizes everything | Reserve for the LCP candidate only |
| AVIF served to Safari < 16 with no fallback | Broken images | Configure both AVIF and WebP fallback; Next.js handles via `formats` |
| Image inside a `transform: scale()` parent | LCP element ignored by browser heuristics in some cases | Avoid CSS transform on LCP wrapper |
| `priority` + `loading="lazy"` both set | Confusing the browser; behaviour depends on browser | Pick one; `priority` for above-fold |
| `<img>` instead of `<Image>` outside Next.js | No optimization, no automatic `srcset` | Use the framework's image component (`<Image>` in Next.js, `<img>` with `srcset` otherwise) |
| Quality 100 by default | 4× the bytes for ~no perceptible improvement | `quality={75}` — or even 60 for backgrounds |
| Animated GIF | 5–20× the bytes of a video | Convert to MP4 or WebM; embed as autoplaying muted video |
| Hot-linking from an image host with no SLA | Random LCP spikes | Self-host or use a CDN with caching guarantees |
| `<picture>` inside Next.js `<Image>` | Both fight for the same job | Pick one — `<Image>` for resize variants, `<picture>` for art direction |

## Tier depth selectors

| Tier | Image work |
|---|---|
| T1 | Convert hero to `<Image>` with `priority` + `width`/`height`; AVIF/WebP via Next.js defaults |
| T2 | + `sizes` on every responsive image; CDN review; OG images dynamic per-route |
| T3 | + custom loader per CDN; per-template LCP attribution; image schema on AI-priority pages |
| T4 | + per-locale image variants; per-DPR pipelines; image-license metadata; CI gate on image weight per template |

## Anti-patterns

| Don't | Why | Do instead |
|---|---|---|
| Add `priority` to every visible image | Browser priority queue saturates; nothing prioritized | One `priority` per page, on the LCP candidate |
| Skip `width`/`height` to "save markup" | CLS regression on every load | Always set them (or `fill` with a sized parent) |
| Lazy-load the hero | LCP regression | `priority`, never lazy on the LCP candidate |
| Background image for a hero that contains the H1 | LCP candidate becomes the H1 text and the image weight is wasted on perceived performance | Use `<Image>` so the hero counts as LCP and gets preloaded |
| Decorative image with descriptive `alt` | Screen readers announce decoration as content | `alt=""` for decorative |
| Marketing-team-uploaded 8 MB PNG with no optimization step | Random LCP regressions from new content | CMS-side optimization; CI check on uploaded asset weight |
| Convert all PNGs to JPEGs blindly | PNG with transparency / sharp edges loses fidelity | AVIF/WebP keep both; convert by image type |
| Convert SVG icons to PNG | Loses scalability; bigger | SVG icons stay SVG; sprite or inline |
| Inline every SVG | Page weight bloat; main-thread parsing | Inline only critical icons; sprite sheet for the rest |
| `next/image` `unoptimized` | Disables the framework's whole purpose for that image | Only for SVG that already self-resizes |
| `quality={100}` | Bytes for no benefit | 60–75 for backgrounds; 80 for hero |
| Self-hosted GIF for animation | 5–20× the bytes of MP4 | Muted autoplaying video; or Lottie for vector animation |
| Image schema with broken `contentUrl` | Schema validation fails; no benefit | Validate post-publish; per Phase 12 |

## Cross-links

- [NEXTJS-PATTERNS](NEXTJS-PATTERNS.md) — full `<Image>` pattern in context.
- [INP-DEEP-DIVE](INP-DEEP-DIVE.md) — image decode and bitmap costs as INP contributors.
- [PAGE-WEIGHT](PAGE-WEIGHT.md) — total transfer-size budget per template.
- [PHASE-3-TECHNICAL](PHASE-3-TECHNICAL.md) — image audit per representative URL.
- [PHASE-12-VERIFICATION](PHASE-12-VERIFICATION.md) — post-deploy LCP verification.
- [SCHEMA-POLICY](SCHEMA-POLICY.md) — `ImageObject` and `Article.image` patterns.
