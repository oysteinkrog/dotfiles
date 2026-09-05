#!/usr/bin/env bun
/**
 * og-image-audit.ts — Audit Open Graph + Twitter share images per representative URL.
 *
 * For each URL:
 *   - Extract og:image, og:image:width, og:image:height, twitter:image,
 *     twitter:card, twitter:image:alt
 *   - HEAD the image: assert status 200, Content-Type starts with image/,
 *     Content-Length < 500 KB (Next.js next/og ImageResponse upper limit;
 *     larger images get re-encoded or dropped by some social cards)
 *   - GET the image bytes (capped at 1.5 MB) and decode header to verify actual
 *     pixel dimensions match og:image:width/height — Twitter & Facebook reject
 *     mismatched dims silently.
 *     Spec checks:
 *       * og:image: 1200x630 recommended (1.91:1)
 *       * twitter:card "summary_large_image": 1200x628 (rounds 1.91:1)
 *       * twitter:card "summary": 240x240 minimum, 1:1
 *   - Confirm og:image URL is absolute (relative URLs break LinkedIn/Slack scrapes).
 *
 * Outputs:
 *   - analyses/og-images.md   — human-readable report
 *   - analyses/og-images.json — structured data
 *
 * Usage:
 *   bun run scripts/og-image-audit.ts \
 *     --rep-set analyses/representative-urls.json \
 *     [--output analyses/og-images.md] \
 *     [--max-bytes 512000]    # default 500 KB Content-Length cap
 *     [--ci true]
 *
 * Exit codes: 0 pass; 1 FAIL with --ci true; 2 missing args.
 */

import { mkdir } from "node:fs/promises";
import { dirname } from "node:path";

const args = parseArgs(Bun.argv.slice(2));
const repSet = args["--rep-set"] ?? "analyses/representative-urls.json";
const outPath = args["--output"] ?? "analyses/og-images.md";
const jsonPath = companionJsonPath(outPath);
const maxBytes = Number(args["--max-bytes"] ?? 512000);
const ci = (args["--ci"] ?? "false") === "true";
const timeout = Number(args["--timeout"] ?? 30000);
const ua = "Mozilla/5.0 (compatible; SEO-Skill-OGAudit/1.0)";

await mkdir(dirname(outPath), { recursive: true });

const rep = await readJsonFile<{
  urls: Array<{ url: string; template?: string }>;
}>(repSet, "--rep-set");

type ImgCheck = {
  url: string;
  template?: string;
  og_image: string | null;
  og_image_w: number | null;
  og_image_h: number | null;
  twitter_card: string | null;
  twitter_image: string | null;
  twitter_image_alt: string | null;
  head_status: number | null;
  content_type: string | null;
  content_length: number | null;
  actual_w: number | null;
  actual_h: number | null;
  issues: { level: "FAIL" | "WARN"; code: string; message: string }[];
};

const results: ImgCheck[] = [];
for (const u of rep.urls) {
  const r = await audit(u.url, u.template);
  results.push(r);
  process.stdout.write(`${r.issues.some((i) => i.level === "FAIL") ? "✗" : "✓"} ${u.url}\n`);
}

const failCount = results.reduce((s, r) => s + r.issues.filter((i) => i.level === "FAIL").length, 0);
const warnCount = results.reduce((s, r) => s + r.issues.filter((i) => i.level === "WARN").length, 0);

await Bun.write(jsonPath, JSON.stringify({ generated: new Date().toISOString(), fail_count: failCount, warn_count: warnCount, results }, null, 2));

const md: string[] = [
  `# OG image audit — ${new Date().toISOString()}`,
  ``,
  `## Summary`,
  `- URLs audited: ${results.length}`,
  `- FAIL: ${failCount}   WARN: ${warnCount}`,
  ``,
  `| URL | OG image | Status | Type | Bytes | Actual WxH | Declared WxH | Twitter card |`,
  `|-----|----------|--------|------|------:|-----------:|-------------:|--------------|`,
];
for (const r of results) {
  md.push(
    `| ${r.url} | ${r.og_image ?? "—"} | ${r.head_status ?? "—"} | ${r.content_type ?? "—"} | ${r.content_length ?? "—"} | ${r.actual_w ?? "?"}x${r.actual_h ?? "?"} | ${r.og_image_w ?? "?"}x${r.og_image_h ?? "?"} | ${r.twitter_card ?? "—"} |`,
  );
}
md.push(``, `## Issues`, ``);
for (const r of results) {
  if (r.issues.length === 0) continue;
  md.push(`### ${r.url}`);
  for (const i of r.issues) md.push(`- ${i.level === "FAIL" ? "❌" : "⚠"} [${i.code}] ${i.message}`);
  md.push(``);
}

await Bun.write(outPath, md.join("\n"));
console.log(`OG image report at ${outPath}. FAIL=${failCount} WARN=${warnCount}`);
process.exit(ci && failCount > 0 ? 1 : 0);

function companionJsonPath(path: string): string {
  return path.endsWith(".md") ? `${path.slice(0, -3)}.json` : `${path}.json`;
}

async function readJsonFile<T>(path: string, label: string): Promise<T> {
  try {
    return JSON.parse(await Bun.file(path).text()) as T;
  } catch (err) {
    console.error(`Could not read ${label} JSON at ${path}: ${(err as Error).message}`);
    process.exit(2);
  }
}

async function audit(pageUrl: string, template?: string): Promise<ImgCheck> {
  const issues: ImgCheck["issues"] = [];
  const out: ImgCheck = {
    url: pageUrl,
    template,
    og_image: null,
    og_image_w: null,
    og_image_h: null,
    twitter_card: null,
    twitter_image: null,
    twitter_image_alt: null,
    head_status: null,
    content_type: null,
    content_length: null,
    actual_w: null,
    actual_h: null,
    issues,
  };
  let html = "";
  try {
    const r = await fetch(pageUrl, { headers: { "User-Agent": ua, Accept: "text/html" }, redirect: "follow", signal: AbortSignal.timeout(timeout) });
    if (!r.ok) {
      issues.push({ level: "FAIL", code: "PAGE_FETCH", message: `Page returned ${r.status}` });
      return out;
    }
    html = await r.text();
  } catch (e) {
    issues.push({ level: "FAIL", code: "PAGE_FETCH", message: (e as Error).message });
    return out;
  }
  // Match meta tags by attribute name regardless of attribute order
  // (some frameworks/CMSes emit content="..." before property/name, and the
  // strict-order regex would silently fail to find them).
  const getMeta = (kind: "property" | "name", value: string): string | null => {
    const re = /<meta\s+([^>]+?)\/?>/gi;
    for (const m of html.matchAll(re)) {
      const attrs = m[1];
      const escaped = value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const keyMatch = new RegExp(`\\b${kind}\\s*=\\s*["']${escaped}["']`, "i").test(attrs);
      if (!keyMatch) continue;
      const content = attrValue(attrs, "content");
      if (content) return content;
    }
    return null;
  };
  const ogImage = getMeta("property", "og:image");
  const ogW = getMeta("property", "og:image:width");
  const ogH = getMeta("property", "og:image:height");
  const twCard = getMeta("name", "twitter:card");
  const twImage = getMeta("name", "twitter:image");
  const twAlt = getMeta("name", "twitter:image:alt");
  out.og_image = ogImage;
  out.og_image_w = parsePositiveInt(ogW);
  out.og_image_h = parsePositiveInt(ogH);
  out.twitter_card = twCard;
  out.twitter_image = twImage;
  out.twitter_image_alt = twAlt;
  if (ogW && out.og_image_w === null) {
    issues.push({ level: "WARN", code: "BAD_DECLARED_WIDTH", message: `og:image:width is not a positive integer: "${ogW}"` });
  }
  if (ogH && out.og_image_h === null) {
    issues.push({ level: "WARN", code: "BAD_DECLARED_HEIGHT", message: `og:image:height is not a positive integer: "${ogH}"` });
  }

  if (!ogImage) {
    issues.push({ level: "FAIL", code: "NO_OG_IMAGE", message: "og:image missing" });
    return out;
  }
  if (!/^https?:\/\//i.test(ogImage)) {
    issues.push({ level: "FAIL", code: "RELATIVE_OG_IMAGE", message: `og:image must be absolute (got "${ogImage}")` });
  }
  const imgUrl = (() => {
    try { return new URL(ogImage, pageUrl).toString(); } catch { return ogImage; }
  })();

  // HEAD
  let headRes: Response | null = null;
  try {
    headRes = await fetch(imgUrl, { method: "HEAD", headers: { "User-Agent": ua }, redirect: "follow", signal: AbortSignal.timeout(timeout) });
  } catch (e) {
    issues.push({ level: "FAIL", code: "IMG_HEAD", message: (e as Error).message });
  }
  if (headRes) {
    out.head_status = headRes.status;
    out.content_type = headRes.headers.get("content-type") ?? null;
    const lenHdr = headRes.headers.get("content-length");
    out.content_length = lenHdr ? Number(lenHdr) : null;
    if (!headRes.ok) {
      issues.push({ level: "FAIL", code: "IMG_NON_200", message: `Image returned ${headRes.status}` });
    } else {
      if (!out.content_type || !/^image\//i.test(out.content_type)) {
        issues.push({ level: "FAIL", code: "BAD_CONTENT_TYPE", message: `Expected image/*, got ${out.content_type ?? "(none)"}` });
      }
      if (out.content_length !== null && out.content_length > maxBytes) {
        issues.push({
          level: "FAIL",
          code: "OVER_SIZE_LIMIT",
          message: `Image is ${out.content_length} bytes (limit ${maxBytes}) — Next.js next/og caps ImageResponse near 500KB; large images get downsampled or rejected by some scrapers.`,
        });
      }
    }
  }

  // GET (capped) for dimension verification
  if (headRes?.ok) {
    try {
      const r = await fetch(imgUrl, { headers: { "User-Agent": ua, Range: `bytes=0-${Math.min(maxBytes * 3, 1572864)}` }, redirect: "follow", signal: AbortSignal.timeout(timeout) });
      const buf = new Uint8Array(await r.arrayBuffer());
      const dims = decodeImageDims(buf, out.content_type ?? "");
      if (dims) {
        out.actual_w = dims.w;
        out.actual_h = dims.h;
        if (out.og_image_w !== null && out.og_image_w !== dims.w) {
          issues.push({ level: "WARN", code: "WIDTH_MISMATCH", message: `og:image:width=${out.og_image_w} but actual=${dims.w}` });
        }
        if (out.og_image_h !== null && out.og_image_h !== dims.h) {
          issues.push({ level: "WARN", code: "HEIGHT_MISMATCH", message: `og:image:height=${out.og_image_h} but actual=${dims.h}` });
        }
        // Aspect / size requirements per card type.
        if (twCard === "summary_large_image" || !twCard) {
          // OG default
          if (dims.w < 1200 || dims.h < 628) {
            issues.push({
              level: "FAIL",
              code: "SIZE_BELOW_SPEC",
              message: `OG/Twitter summary_large_image expects ≥ 1200x630 (got ${dims.w}x${dims.h})`,
            });
          }
          const ratio = dims.w / dims.h;
          if (ratio < 1.85 || ratio > 1.96) {
            issues.push({
              level: "WARN",
              code: "RATIO_OFF",
              message: `Aspect ratio ${ratio.toFixed(2)} is outside 1.91:1 ± tolerance`,
            });
          }
        } else if (twCard === "summary") {
          if (dims.w < 240 || dims.h < 240) {
            issues.push({ level: "FAIL", code: "SIZE_BELOW_SPEC", message: `twitter:card summary expects ≥ 240x240 (got ${dims.w}x${dims.h})` });
          }
          if (dims.w !== dims.h) {
            issues.push({ level: "WARN", code: "RATIO_OFF", message: `twitter:card summary expects 1:1 (got ${dims.w}x${dims.h})` });
          }
        }
      } else {
        issues.push({ level: "WARN", code: "DIM_DECODE_FAILED", message: `Could not decode image dimensions for ${out.content_type ?? "?"}` });
      }
    } catch (e) {
      issues.push({ level: "WARN", code: "IMG_GET", message: (e as Error).message });
    }
  }

  // Twitter image fallback
  if (!twImage && twCard) {
    issues.push({ level: "WARN", code: "NO_TWITTER_IMAGE", message: `twitter:card="${twCard}" but no twitter:image; OG fallback used` });
  }
  if (!twAlt && twImage) {
    issues.push({ level: "WARN", code: "NO_TWITTER_ALT", message: "twitter:image:alt missing (a11y + click-through)" });
  }

  return out;
}

function parsePositiveInt(value: string | null): number | null {
  if (!value) return null;
  const n = Number(value.trim());
  return Number.isFinite(n) && n > 0 ? Math.round(n) : null;
}

function attrValue(attrs: string, name: string): string | null {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return attrs.match(new RegExp(`\\b${escaped}\\s*=\\s*["']([^"']*)["']`, "i"))?.[1] ?? null;
}

/**
 * Decode width/height from common image headers (PNG, JPEG, WebP, GIF, SVG, AVIF best-effort).
 */
function decodeImageDims(b: Uint8Array, mime: string): { w: number; h: number } | null {
  if (b.length < 16) return null;
  // PNG
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) {
    // unsigned 32-bit (>>> 0) so widths > 2^31 don't go negative
    const w = ((b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19]) >>> 0;
    const h = ((b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23]) >>> 0;
    return { w, h };
  }
  // GIF
  if (b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46) {
    return { w: b[6] | (b[7] << 8), h: b[8] | (b[9] << 8) };
  }
  // JPEG
  if (b[0] === 0xff && b[1] === 0xd8) {
    let i = 2;
    while (i < b.length) {
      if (b[i] !== 0xff) return null;
      while (i < b.length && b[i] === 0xff) i++;
      if (i >= b.length) return null;
      const marker = b[i++];
      if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
        // SOFn
        if (i + 6 >= b.length) return null;
        const h = (b[i + 3] << 8) | b[i + 4];
        const w = (b[i + 5] << 8) | b[i + 6];
        return { w, h };
      }
      if (i + 1 >= b.length) return null;
      const segLen = (b[i] << 8) | b[i + 1];
      if (segLen < 2) return null;
      i += segLen;
    }
    return null;
  }
  // WebP (RIFF....WEBPVP8 / VP8L / VP8X)
  if (b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 && b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50) {
    const tag = String.fromCharCode(b[12], b[13], b[14], b[15]);
    if (tag === "VP8 ") {
      if (b.length < 30) return null;
      const w = ((b[27] << 8) | b[26]) & 0x3fff;
      const h = ((b[29] << 8) | b[28]) & 0x3fff;
      return { w, h };
    }
    if (tag === "VP8L") {
      if (b.length < 25) return null;
      const w = 1 + (((b[22] & 0x3f) << 8) | b[21]);
      const h = 1 + (((b[24] & 0x0f) << 10) | (b[23] << 2) | ((b[22] & 0xc0) >> 6));
      return { w, h };
    }
    if (tag === "VP8X") {
      if (b.length < 30) return null;
      const w = 1 + (b[24] | (b[25] << 8) | (b[26] << 16));
      const h = 1 + (b[27] | (b[28] << 8) | (b[29] << 16));
      return { w, h };
    }
  }
  // SVG (text)
  if (mime.includes("svg") || (b[0] === 0x3c)) {
    const txt = new TextDecoder().decode(b.subarray(0, Math.min(b.length, 4096)));
    const w = Number(txt.match(/\bwidth\s*=\s*["']\s*(\d+(?:\.\d+)?)\s*(?:px)?\s*["']/i)?.[1]);
    const h = Number(txt.match(/\bheight\s*=\s*["']\s*(\d+(?:\.\d+)?)\s*(?:px)?\s*["']/i)?.[1]);
    if (w && h) return { w: Math.round(w), h: Math.round(h) };
    const viewBox = txt.match(/\bviewBox\s*=\s*["']\s*-?\d+(?:\.\d+)?\s+-?\d+(?:\.\d+)?\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s*["']/i);
    if (viewBox) {
      return { w: Math.round(Number(viewBox[1])), h: Math.round(Number(viewBox[2])) };
    }
  }
  return null;
}

function parseArgs(argv: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (let j = 0; j < argv.length; j++) {
    const arg = argv[j];
    if (!arg.startsWith("--")) continue;
    const equals = arg.indexOf("=");
    if (equals > 2) {
      out[arg.slice(0, equals)] = arg.slice(equals + 1);
      continue;
    }
    const next = argv.at(j + 1);
    if (next === undefined || next.startsWith("--")) {
      out[arg] = "true";
    } else {
      out[arg] = next;
      j++;
    }
  }
  return out;
}
