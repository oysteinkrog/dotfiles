#!/usr/bin/env bun
/**
 * sitemap-audit.ts — verify sitemap content vs canonical truth.
 *
 * For each URL in the sitemap:
 *   - HEAD request returns 200
 *   - canonical tag (from a sample full GET) is self-referencing or pointing to a URL also in the sitemap
 *   - robots directive is index,follow (or empty/default)
 *   - URL is not gated, login-required, or noindexed
 *
 * Usage:
 *   bun run scripts/sitemap-audit.ts --sitemap https://www.example.com/sitemap.xml
 */

const args = parseArgs(Bun.argv.slice(2));
const sitemap = args["--sitemap"];
const timeout = Number(args["--timeout"] ?? 30000);
if (!sitemap) {
  console.error("Provide --sitemap <url>");
  process.exit(2);
}

const xml = await (await fetch(sitemap, { signal: AbortSignal.timeout(timeout) })).text();
const urls = Array.from(xml.matchAll(/<loc>([^<]+)<\/loc>/g)).map((m) => m[1]);

console.log(`Sitemap contains ${urls.length} URLs.`);
const issues: string[] = [];

for (const u of urls) {
  let r: Response;
  try {
    r = await fetch(u, { redirect: "manual", signal: AbortSignal.timeout(timeout) });
  } catch (err) {
    issues.push(`${u} → fetch failed: ${(err as Error).message}`);
    continue;
  }
  if (r.status >= 300 && r.status < 400) {
    issues.push(`${u} → redirect to ${r.headers.get("location")}`);
    continue;
  }
  if (r.status !== 200) {
    issues.push(`${u} → status ${r.status}`);
    continue;
  }
  const html = await r.text();
  const canonical = matchCanonical(html);
  if (canonical && canonical !== u && !urls.includes(canonical)) {
    issues.push(`${u} canonical points to ${canonical} (not in sitemap)`);
  }
  const robots = matchMeta(html, "name", "robots");
  if (robots && /noindex/i.test(robots)) {
    issues.push(`${u} has robots="${robots}"`);
  }
}

if (issues.length === 0) {
  console.log("Sitemap audit: all URLs canonical-aligned and indexable.");
  process.exit(0);
} else {
  console.log(`Issues:`);
  for (const i of issues) console.log(`  ${i}`);
  process.exit(1);
}

// Match meta/link tags by attribute name regardless of attribute order —
// strict-order regex misses tags where content/href appears before name/rel.
function matchMeta(html: string, kind: "name" | "property", value: string): string | null {
  const re = /<meta\s+([^>]+?)\/?>/gi;
  for (const m of html.matchAll(re)) {
    const attrs = m[1];
    const escaped = value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (!new RegExp(`\\b${kind}\\s*=\\s*["']${escaped}["']`, "i").test(attrs)) continue;
    const content = attrValue(attrs, "content");
    if (content !== null) return content;
  }
  return null;
}
function matchCanonical(html: string): string | null {
  const re = /<link\s+([^>]+?)\/?>/gi;
  for (const m of html.matchAll(re)) {
    const attrs = m[1];
    if (!hasRelToken(attrs, "canonical")) continue;
    const href = attrValue(attrs, "href");
    if (href) return href;
  }
  return null;
}

function attrValue(attrs: string, name: string): string | null {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return attrs.match(new RegExp(`\\b${escaped}\\s*=\\s*["']([^"']*)["']`, "i"))?.[1] ?? null;
}

function hasRelToken(attrs: string, token: string): boolean {
  const rel = attrValue(attrs, "rel");
  return rel ? rel.toLowerCase().split(/\s+/).includes(token.toLowerCase()) : false;
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
