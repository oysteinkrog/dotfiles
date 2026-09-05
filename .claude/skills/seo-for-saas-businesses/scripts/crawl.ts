#!/usr/bin/env bun
/**
 * crawl.ts — Phase 1 / Phase 3 production+staging crawl
 *
 * For each URL in the representative set:
 *   - Fetch raw HTML (no JS execution) and save under analyses/crawl/<urlhash>.raw.html
 *   - Render via Playwright at networkidle and save analyses/crawl/<urlhash>.rendered.html
 *   - Extract: status, redirect chain, canonical, robots directive, title, meta description,
 *     OG/Twitter tags, JSON-LD blocks, h1, internal links, image weights, response headers
 *   - Save analyses/crawl/<urlhash>.json
 *
 * Usage:
 *   bun run scripts/crawl.ts \
 *     --rep-set analyses/representative-urls.json \
 *     --output analyses/crawl/ \
 *     [--user-agent <ua>] [--concurrency 4] [--timeout 30000]
 *
 * The representative-urls.json shape:
 *   { "tier": "T2", "urls": [{ "url": "...", "template": "...", "intent": "..." }, ...] }
 *
 * Dependencies (assumed in target repo or available globally):
 *   - playwright
 *   - cheerio (or any HTML parser)
 *
 * On hosts where Playwright is heavyweight, only the rendered-HTML pass is gated by Playwright;
 * the raw-HTML pass uses native fetch and works in any Node/Bun environment.
 */

import { chromium } from "playwright";
import { mkdir, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";

type Url = { url: string; template?: string; intent?: string };

const args = parseArgs(Bun.argv.slice(2));
const repSet = args["--rep-set"] ?? "analyses/representative-urls.json";
const outDir = args["--output"] ?? "analyses/crawl/";
const ua =
  args["--user-agent"] ??
  "Mozilla/5.0 (compatible; SEO-Skill-Crawler/1.0; +https://example.com)";
const concurrency = Number(args["--concurrency"] ?? 4);
const timeout = Number(args["--timeout"] ?? 30000);

const repPath = join(process.cwd(), repSet);
if (!existsSync(repPath)) {
  console.error(`Representative URL set not found at ${repPath}`);
  process.exit(2);
}
const rep = JSON.parse(await Bun.file(repPath).text()) as { urls: Url[] };

await mkdir(outDir, { recursive: true });

const browser = await chromium.launch();
const context = await browser.newContext({ userAgent: ua });

let inFlight = 0;
let i = 0;
const results: any[] = [];

async function next(): Promise<void> {
  if (i >= rep.urls.length) return;
  const u = rep.urls[i++];
  inFlight++;
  try {
    const r = await crawlOne(u);
    results.push(r);
    process.stdout.write(`✓ ${u.url}\n`);
  } catch (err) {
    process.stdout.write(`✗ ${u.url} — ${(err as Error).message}\n`);
    results.push({ url: u.url, error: (err as Error).message });
  } finally {
    inFlight--;
    await next();
  }
}

await Promise.all(Array.from({ length: concurrency }, () => next()));
await context.close();
await browser.close();

await writeFile(
  join(outDir, "_index.json"),
  JSON.stringify({ generated: new Date().toISOString(), results }, null, 2),
);
console.log(`\n${results.length} URLs crawled. Index at ${outDir}_index.json`);

async function crawlOne(u: Url) {
  const hash = createHash("sha1").update(u.url).digest("hex").slice(0, 12);
  const rawPath = join(outDir, `${hash}.raw.html`);
  const renderedPath = join(outDir, `${hash}.rendered.html`);
  const jsonPath = join(outDir, `${hash}.json`);

  // --- raw HTML (no JS) ---
  const rawRes = await fetch(u.url, {
    redirect: "manual",
    headers: { "User-Agent": ua, Accept: "text/html" },
    signal: AbortSignal.timeout(timeout),
  });
  const redirectChain: string[] = [u.url];
  let cur = rawRes;
  let curUrl = u.url;
  while (cur.status >= 300 && cur.status < 400) {
    const loc = cur.headers.get("location");
    if (!loc) break;
    // Resolve relative Location against the URL we just fetched.
    const next = new URL(loc, curUrl).toString();
    redirectChain.push(next);
    if (redirectChain.length > 10) break;
    curUrl = next;
    cur = await fetch(next, {
      redirect: "manual",
      headers: { "User-Agent": ua, Accept: "text/html" },
      signal: AbortSignal.timeout(timeout),
    });
  }
  const finalUrl = redirectChain[redirectChain.length - 1];
  const rawHtml = await cur.text();
  await writeFile(rawPath, rawHtml);

  const rawHeaders = Object.fromEntries(cur.headers.entries());

  // --- rendered HTML (JS) ---
  const page = await context.newPage();
  let renderedHtml = "";
  let renderedTitle = "";
  try {
    await page.goto(u.url, { waitUntil: "networkidle", timeout });
    renderedHtml = await page.content();
    renderedTitle = await page.title();
    await writeFile(renderedPath, renderedHtml);
  } finally {
    await page.close();
  }

  // --- extract ---
  const meta = extract(rawHtml);
  const renderedMeta = extract(renderedHtml);

  const data = {
    url: u.url,
    final_url: finalUrl,
    template: u.template,
    intent: u.intent,
    status: cur.status,
    redirect_chain: redirectChain,
    headers: rawHeaders,
    raw: { ...meta, html_path: rawPath },
    rendered: { ...renderedMeta, title_via_browser: renderedTitle, html_path: renderedPath },
    diff: diffMeta(meta, renderedMeta),
    crawled_at: new Date().toISOString(),
  };

  await writeFile(jsonPath, JSON.stringify(data, null, 2));
  return data;
}

function extract(html: string) {
  const get = (re: RegExp) => html.match(re)?.[1] ?? null;
  const all = (re: RegExp): string[] => {
    const out: string[] = [];
    for (const m of html.matchAll(re)) out.push(m[1]);
    return out;
  };
  // Match meta/link tags by attribute name regardless of attribute order —
  // some frameworks emit content="..." before name/property and the strict
  // regex would silently miss them.
  const getMeta = (kind: "name" | "property", value: string): string | null => {
    const re = /<meta\s+([^>]+?)\/?>/gi;
    for (const m of html.matchAll(re)) {
      const attrs = m[1];
      const escaped = value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      if (!new RegExp(`\\b${kind}\\s*=\\s*["']${escaped}["']`, "i").test(attrs)) continue;
      const content = attrValue(attrs, "content");
      if (content !== null) return content;
    }
    return null;
  };
  const getLink = (rel: string): string | null => {
    const re = /<link\s+([^>]+?)\/?>/gi;
    for (const m of html.matchAll(re)) {
      const attrs = m[1];
      if (!hasRelToken(attrs, rel)) continue;
      const href = attrValue(attrs, "href");
      if (href !== null) return href;
    }
    return null;
  };
  const title = get(/<title[^>]*>([^<]*)<\/title>/i);
  const description = getMeta("name", "description");
  const canonical = getLink("canonical");
  const robots = getMeta("name", "robots");
  const h1 = get(/<h1[^>]*>([^<]*)<\/h1>/i);
  const ogTitle = getMeta("property", "og:title");
  const ogDescription = getMeta("property", "og:description");
  const ogImage = getMeta("property", "og:image");
  const ogType = getMeta("property", "og:type");
  const twitterCard = getMeta("name", "twitter:card");
  const jsonLdBlocks = all(
    /<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi,
  );
  const internalLinks = all(/href=["']([^"'#]*)["']/g).filter(
    (h) => h.startsWith("/") || h.includes("://"),
  );
  return {
    title,
    description,
    canonical,
    robots,
    h1,
    og: { title: ogTitle, description: ogDescription, image: ogImage, type: ogType },
    twitter_card: twitterCard,
    json_ld: jsonLdBlocks.map((b) => {
      try { return { ok: true, parsed: JSON.parse(b.trim()) }; }
      catch { return { ok: false, raw: b.slice(0, 256) }; }
    }),
    json_ld_count: jsonLdBlocks.length,
    internal_link_count: internalLinks.length,
  };
}

function attrValue(attrs: string, name: string): string | null {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return attrs.match(new RegExp(`\\b${escaped}\\s*=\\s*["']([^"']*)["']`, "i"))?.[1] ?? null;
}

function hasRelToken(attrs: string, token: string): boolean {
  const rel = attrValue(attrs, "rel");
  return rel ? rel.toLowerCase().split(/\s+/).includes(token.toLowerCase()) : false;
}

function diffMeta(raw: any, rendered: any) {
  const diff: Record<string, any> = {};
  for (const k of ["title", "description", "canonical", "robots", "h1"]) {
    if (raw[k] !== rendered[k]) diff[k] = { raw: raw[k], rendered: rendered[k] };
  }
  if (raw.json_ld_count !== rendered.json_ld_count) {
    diff.json_ld_count = { raw: raw.json_ld_count, rendered: rendered.json_ld_count };
  }
  return diff;
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
