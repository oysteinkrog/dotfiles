#!/usr/bin/env bun
/**
 * internal-links.ts — orphan + redirect-through-internal-link audit.
 *
 * Inputs:
 *   - analyses/representative-urls.json (or sitemap pulled in)
 *   - sitemap URL (default: <origin>/sitemap.xml)
 *
 * Walks every URL, extracts internal <a href>, builds a graph, and reports:
 *   - Orphan pages (in sitemap but no internal link target)
 *   - Internal links that hit a redirect (1 hop or more before 200)
 *   - Internal 4xx / 5xx targets
 *   - Anchor-text distribution per URL
 *
 * Usage:
 *   bun run scripts/internal-links.ts \
 *     --origin https://www.example.com \
 *     [--sitemap https://www.example.com/sitemap.xml] \
 *     [--output analyses/internal-links.md] \
 *     [--max 500]
 */

import { mkdir } from "node:fs/promises";
import { dirname } from "node:path";

const args = parseArgs(Bun.argv.slice(2));
const origin = args["--origin"] ?? "https://www.example.com";
const sitemap = args["--sitemap"] ?? `${origin}/sitemap.xml`;
const outPath = args["--output"] ?? "analyses/internal-links.md";
const jsonPath = companionJsonPath(outPath);
const max = Number(args["--max"] ?? 500);
const timeout = Number(args["--timeout"] ?? 30000);
const originUrl = new URL(origin);

await mkdir(dirname(outPath), { recursive: true });

const sitemapXml = await (await fetch(sitemap, { signal: AbortSignal.timeout(timeout) })).text();
const sitemapUrls = Array.from(
  sitemapXml.matchAll(/<loc>([^<]+)<\/loc>/g),
).map((m) => m[1]);
const indexable = new Set(sitemapUrls);

const visited = new Set<string>();
const inLinks = new Map<string, Array<{ from: string; anchor: string }>>();
const outboundInternal = new Map<string, Array<{ to: string; anchor: string; rel?: string }>>();
const outboundExternal = new Map<string, Array<{ to: string; anchor: string; rel?: string }>>();
const redirected = new Map<string, string>();
const broken = new Map<string, number>();

const queue = sitemapUrls.slice(0, max);
let i = 0;
while (i < queue.length) {
  const url = queue[i++];
  if (visited.has(url)) continue;
  visited.add(url);
  try {
    const r = await fetch(url, { redirect: "manual", signal: AbortSignal.timeout(timeout) });
    if (r.status >= 300 && r.status < 400) {
      const loc = r.headers.get("location") ?? "";
      redirected.set(url, loc);
      continue;
    }
    if (r.status >= 400) {
      broken.set(url, r.status);
      continue;
    }
    const html = await r.text();
    for (const m of html.matchAll(/<a\s+([^>]*?)href=["']([^"']+)["']([^>]*)>([\s\S]*?)<\/a>/g)) {
      const href = m[2];
      if (href.trim() === "" || href.startsWith("#")) continue;
      const attrs = `${m[1]} ${m[3]}`;
      const rel = attrValue(attrs, "rel") ?? undefined;
      const text = m[4].replace(/<[^>]+>/g, "").trim();
      let absUrl: URL;
      try {
        absUrl = new URL(href, url);
      } catch {
        continue;
      }
      if (absUrl.protocol !== "http:" && absUrl.protocol !== "https:") continue;
      if (absUrl.origin !== originUrl.origin) {
        pushOutbound(outboundExternal, url, { to: absUrl.toString(), anchor: text, rel });
        continue;
      }
      absUrl.hash = "";
      const abs = absUrl.toString();
      pushOutbound(outboundInternal, url, { to: abs, anchor: text, rel });
      if (!inLinks.has(abs)) inLinks.set(abs, []);
      inLinks.get(abs)!.push({ from: url, anchor: text });
    }
  } catch (e) {
    broken.set(url, -1);
  }
}

for (const target of inLinks.keys()) {
  if (visited.has(target) || redirected.has(target) || broken.has(target)) continue;
  const check = await checkTarget(target);
  if (check.redirectsTo) redirected.set(target, check.redirectsTo);
  if (check.status >= 400 || check.status < 0) broken.set(target, check.status);
}

const orphans = sitemapUrls.filter((u) => !inLinks.has(u));

const linksThroughRedirect: Array<{ from: string; href: string; redirectsTo: string }> = [];
for (const [target, ls] of inLinks) {
  if (redirected.has(target)) {
    for (const l of ls) {
      linksThroughRedirect.push({ from: l.from, href: target, redirectsTo: redirected.get(target)! });
    }
  }
}

const generated = new Date().toISOString();
const summary = {
  sitemap_urls: sitemapUrls.length,
  urls_visited: visited.size,
  orphan_pages: orphans.length,
  internal_links_through_redirect: linksThroughRedirect.length,
  broken_internal_targets: broken.size,
};
const results = sitemapUrls.map((page) => ({
  page,
  outbound_internal: outboundInternal.get(page) ?? [],
  outbound_external: outboundExternal.get(page) ?? [],
  inbound_count: inLinks.get(page)?.length ?? 0,
}));
await Bun.write(jsonPath, JSON.stringify({
  generated,
  origin: originUrl.toString(),
  sitemap,
  summary,
  results,
  orphans,
  links_through_redirect: linksThroughRedirect,
  broken_internal_targets: Array.from(broken, ([url, status]) => ({ url, status })),
}, null, 2));

const lines = [
  `# Internal links audit — ${generated}`,
  ``,
  `## Summary`,
  `- Sitemap URLs: ${summary.sitemap_urls}`,
  `- URLs visited: ${summary.urls_visited}`,
  `- Orphan pages (in sitemap, no internal links): ${summary.orphan_pages}`,
  `- Internal links through redirect: ${summary.internal_links_through_redirect}`,
  `- Broken internal targets (4xx/5xx): ${summary.broken_internal_targets}`,
  ``,
  `## Orphans`,
];
for (const o of orphans) lines.push(`- ${o}`);

lines.push(``, `## Internal links through redirect`);
for (const l of linksThroughRedirect.slice(0, 100)) {
  lines.push(`- ${l.from} → ${l.href} (redirects to ${l.redirectsTo})`);
}

lines.push(``, `## Broken internal targets`);
for (const [u, s] of broken) lines.push(`- ${u} (status ${s})`);

await Bun.write(outPath, lines.join("\n"));
console.log(`Report at ${outPath}; JSON at ${jsonPath}.`);

function companionJsonPath(path: string): string {
  return path.endsWith(".md") ? `${path.slice(0, -3)}.json` : `${path}.json`;
}

function pushOutbound(
  map: Map<string, Array<{ to: string; anchor: string; rel?: string }>>,
  from: string,
  link: { to: string; anchor: string; rel?: string },
) {
  if (!map.has(from)) map.set(from, []);
  map.get(from)!.push(link);
}

function attrValue(attrs: string, name: string): string | null {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return attrs.match(new RegExp(`\\b${escaped}\\s*=\\s*["']([^"']*)["']`, "i"))?.[1] ?? null;
}

async function checkTarget(url: string): Promise<{ status: number; redirectsTo: string | null }> {
  try {
    let r = await fetch(url, { method: "HEAD", redirect: "manual", signal: AbortSignal.timeout(timeout) });
    if (r.status === 405 || r.status === 501) {
      r = await fetch(url, { method: "GET", redirect: "manual", signal: AbortSignal.timeout(timeout) });
    }
    if (r.status >= 300 && r.status < 400) {
      const loc = r.headers.get("location");
      return { status: r.status, redirectsTo: loc ? new URL(loc, url).toString() : "" };
    }
    return { status: r.status, redirectsTo: null };
  } catch {
    return { status: -1, redirectsTo: null };
  }
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
