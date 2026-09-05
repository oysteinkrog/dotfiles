---
name: og-share-images
description: >-
  Next.js OG/Twitter share images with next/og ImageResponse and Satori.
  Use when building OG images, Twitter cards, social previews, or share images.
---

# OG Share Images for Next.js

| File | Dimensions | Platforms |
|------|-----------|-----------|
| `opengraph-image.tsx` | 1200x630 | Facebook, LinkedIn, iMessage, Telegram |
| `twitter-image.tsx` | 1200x600 | Twitter/X |

Place in route directory (e.g., `app/about/opengraph-image.tsx`).

## The Two Things That Break OG Images

### 1. Explicit metadata overrides file convention

**Do NOT define `openGraph.images` or `twitter.images` in page metadata.** Next.js auto-detects `opengraph-image.tsx` files and generates `<meta>` tags with cache-busting hashes. Explicit metadata kills this:

```tsx
// BAD — breaks cache-busting, twitter-image endpoint, and dimension tags
export const metadata: Metadata = {
  openGraph: { images: [{ url: "/writing/post/opengraph-image" }] },
  twitter: { images: ["/writing/post/opengraph-image"] },
};

// GOOD — omit openGraph/twitter entirely; top-level title+description is enough
export const metadata: Metadata = {
  title: "Post Title",
  description: "Post description",
};
```

Even `openGraph: { title, description }` without `images` can prevent Next.js from merging file-convention image tags. Safest: omit `openGraph` and `twitter` entirely.

### 2. Satori crashes silently

`next/og` uses Satori (not a browser). Violations return HTTP 200 with **0-byte empty body**. No error logs.

**Banned (silent crash):**
1. `.map()` inside `<svg>` — write each element explicitly
2. `<polygon>` — use `<path d="M50 5 L90 27...Z">` instead
3. `<text>`, `textAnchor` — use positioned `<div>` overlays
4. `strokeDasharray` — unreliable, often crashes
5. `<g transform="...">` — position elements individually
6. `<br />` — use separate `<div>` elements
7. WebP images — PNG/JPEG only (`TypeError: u2 is not iterable`)
8. HTML entities — `&apos;` renders literally; use `{"it's"}`
9. `conic-gradient` — only `linear-gradient` and `radial-gradient`
10. CSS classes, Tailwind — inline styles only

**Required:**
- `display: "flex"` on EVERY element (`<div>`, `<span>`, `<h1>`, etc.)
- `viewBox` + explicit `width`/`height` on all `<svg>` elements
- `filter` only on SVG root, not child elements

**Safe SVG:** `<circle>`, `<rect>`, `<path>`, `<line>`, `<defs>`, `<linearGradient>`, `<stop>`

**Polygon → Path:** `<polygon points="50,5 90,27 90,73">` → `<path d="M50 5 L90 27 L90 73 Z">`

## Workflow

- [ ] Create `app/<route>/opengraph-image.tsx` (1200x630) and `twitter-image.tsx` (1200x600)
- [ ] Use only Satori-safe elements (see rules above)
- [ ] Remove any explicit `openGraph`/`twitter` from page metadata
- [ ] `bun run build` — verify `ƒ` (dynamic) next to image routes
- [ ] `curl -sw "SIZE: %{size_download}\n" -o /dev/null <url>/opengraph-image` — must be >0
- [ ] Check meta tags have cache-bust hashes: `curl -s <url> | grep 'og:image'`

## Quick Start

```tsx
import { ImageResponse } from "next/og";

export const runtime = "edge";
export const alt = "Page Title";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function Image() {
  return new ImageResponse(
    (<div style={{
      height: "100%", width: "100%", display: "flex",
      flexDirection: "column", alignItems: "center", justifyContent: "center",
      background: "linear-gradient(145deg, #0a0a12 0%, #0f1218 50%, #0a0a12 100%)",
      fontFamily: "system-ui, -apple-system, sans-serif",
    }}>
      <h1 style={{ fontSize: 64, color: "#fff", margin: 0, display: "flex" }}>
        Title
      </h1>
    </div>),
    { ...size }
  );
}
```

## Common Issues

| Issue | Fix |
|-------|-----|
| 0-byte response | Satori crash — check banned list above |
| Gradient text invisible | Need `backgroundClip: "text"` AND `color: "transparent"` |
| Platforms show stale image | [Debugging guide](references/debugging.md) — platform refresh tools |
| No cache-bust hash in `og:image` URL | Remove explicit `openGraph`/`twitter` from metadata |
| Twitter uses OG image not twitter-image | Remove explicit `twitter.images`; let file convention work |
| Colors wrong | Use hex colors, not CSS variables or `oklch()` |
| `TypeError: u2 is not iterable` | WebP image — convert to PNG/JPEG |

## Reference Index

- [Design patterns](references/patterns.md) — gradients, orbs, SVG icons, color palettes, complete visual examples
- [Debugging & verification](references/debugging.md) — curl checks, meta tag validation, platform refresh
