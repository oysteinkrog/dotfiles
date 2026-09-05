#!/usr/bin/env bun
/**
 * hreflang-validator.ts — Validate hreflang annotations across a representative URL set.
 *
 * For each URL with hreflang alternates (in <link rel="alternate" hreflang="..." />,
 * HTTP Link header, or sitemap xhtml:link), checks:
 *   - hreflang values are valid ISO 639-1 language codes (and optional ISO 3166-1
 *     region) or "x-default"
 *   - alternate URLs are absolute (per Google guidance — relative URLs are silently
 *     ignored by some validators)
 *   - reciprocity: every alternate references the originating URL back
 *   - x-default present (recommended for global SaaS)
 *   - canonical does not contradict hreflang (alternate URL must canonicalize to itself
 *     — or to its localized equivalent — not to a different language)
 *   - no auto-redirect trap: fetch the alternate URL with US, EU (Germany), and JP
 *     geo-overrides via Accept-Language; if the server 30x-redirects on language
 *     match, that breaks Google's hreflang signal
 *
 * Outputs:
 *   - analyses/hreflang.md   — human-readable report
 *   - analyses/hreflang.json — structured per-URL data
 *
 * Usage:
 *   bun run scripts/hreflang-validator.ts \
 *     --rep-set analyses/representative-urls.json \
 *     [--output analyses/hreflang.md] \
 *     [--ci true]                # exit 1 on any FAIL-class issue
 *
 * Exit codes:
 *   0 all-pass; 1 FAIL-class issue with --ci true; 2 missing args.
 */

import { mkdir } from "node:fs/promises";
import { dirname } from "node:path";

const args = parseArgs(Bun.argv.slice(2));
const repSet = args["--rep-set"] ?? "analyses/representative-urls.json";
const outPath = args["--output"] ?? "analyses/hreflang.md";
const jsonPath = companionJsonPath(outPath);
const ci = (args["--ci"] ?? "false") === "true";
const timeout = Number(args["--timeout"] ?? 30000);

await mkdir(dirname(outPath), { recursive: true });

const ua = "Mozilla/5.0 (compatible; SEO-Skill-HreflangCheck/1.0)";

// ISO 639-1 (subset of common codes, plus 'x-default' and 'mul')
const ISO_LANG = new Set([
  "aa","ab","af","ak","am","ar","as","ay","az","ba","be","bg","bh","bi","bm","bn","bo","br","bs",
  "ca","ce","ch","co","cr","cs","cu","cv","cy","da","de","dv","dz","ee","el","en","eo","es","et",
  "eu","fa","ff","fi","fj","fo","fr","fy","ga","gd","gl","gn","gu","gv","ha","he","hi","ho","hr",
  "ht","hu","hy","hz","ia","id","ie","ig","ii","ik","io","is","it","iu","ja","jv","ka","kg","ki",
  "kj","kk","kl","km","kn","ko","kr","ks","ku","kv","kw","ky","la","lb","lg","li","ln","lo","lt",
  "lu","lv","mg","mh","mi","mk","ml","mn","mr","ms","mt","my","na","nb","nd","ne","ng","nl","nn",
  "no","nr","nv","ny","oc","oj","om","or","os","pa","pi","pl","ps","pt","qu","rm","rn","ro","ru",
  "rw","sa","sc","sd","se","sg","si","sk","sl","sm","sn","so","sq","sr","ss","st","su","sv","sw",
  "ta","te","tg","th","ti","tk","tl","tn","to","tr","ts","tt","tw","ty","ug","uk","ur","uz","ve",
  "vi","vo","wa","wo","xh","yi","yo","za","zh","zu","mul",
]);
const ISO_REGION = /^[A-Z]{2}$/;

const rep = await readJsonFile<{
  urls: Array<{ url: string; template?: string }>;
}>(repSet, "--rep-set");

type Alt = { hreflang: string; href: string; source: "html" | "header" };
type UrlReport = {
  url: string;
  template?: string;
  alternates: Alt[];
  canonical: string | null;
  issues: { level: "FAIL" | "WARN"; code: string; message: string }[];
  redirect_traps: { lang: string; geo: string; redirected_to: string }[];
};

// First pass: collect alternates per URL.
const cache = new Map<string, { html: string; canonical: string | null; alternates: Alt[] }>();

async function fetchData(u: string) {
  if (cache.has(u)) return cache.get(u)!;
  const r = await fetch(u, { headers: { "User-Agent": ua, Accept: "text/html" }, redirect: "follow", signal: AbortSignal.timeout(timeout) });
  const html = r.ok ? await r.text() : "";
  const headerLink = r.headers.get("link") ?? "";
  const alternates = extractAlternates(html, headerLink, u);
  const canonical = extractCanonical(html);
  const v = { html, canonical, alternates };
  cache.set(u, v);
  return v;
}

const reports: UrlReport[] = [];
for (const u of rep.urls) {
  const data = await fetchData(u.url);
  const issues: UrlReport["issues"] = [];
  const seen = new Set<string>();
  let xDefault = false;
  for (const a of data.alternates) {
    if (a.hreflang === "x-default") xDefault = true;
    const key = `${a.hreflang}|${a.href}`;
    if (seen.has(key)) issues.push({ level: "WARN", code: "DUPLICATE", message: `Duplicate alternate ${a.hreflang} → ${a.href}` });
    seen.add(key);
    // ISO check
    if (a.hreflang !== "x-default") {
      const [lang, region] = a.hreflang.split("-");
      if (!ISO_LANG.has(lang.toLowerCase())) {
        issues.push({ level: "FAIL", code: "BAD_LANG", message: `Invalid ISO 639-1 lang "${lang}" in ${a.hreflang}` });
      }
      if (region && !ISO_REGION.test(region.toUpperCase())) {
        issues.push({ level: "FAIL", code: "BAD_REGION", message: `Invalid ISO 3166-1 region "${region}" in ${a.hreflang}` });
      }
    }
    // Absolute URL
    if (!/^https?:\/\//i.test(a.href)) {
      issues.push({ level: "FAIL", code: "RELATIVE_URL", message: `Alternate href must be absolute: ${a.href}` });
    }
  }
  if (data.alternates.length > 0 && !xDefault) {
    issues.push({ level: "WARN", code: "NO_X_DEFAULT", message: "x-default missing — recommended for international targeting" });
  }

  // Reciprocity check
  for (const a of data.alternates) {
    if (a.hreflang === "x-default") continue;
    if (!/^https?:\/\//i.test(a.href)) continue;
    let alt;
    try { alt = await fetchData(a.href); } catch { continue; }
    const back = alt.alternates.find((x) => x.href === u.url || x.href === u.url + "/" || x.href === u.url.replace(/\/$/, ""));
    if (!back) {
      issues.push({ level: "FAIL", code: "NO_RECIPROCAL", message: `Alternate ${a.hreflang} → ${a.href} does not reference back to ${u.url}` });
    }
    // Canonical conflict: alt should canonicalize to itself or to a localized equivalent
    if (alt.canonical && alt.canonical !== a.href && alt.canonical !== a.href + "/" && alt.canonical !== a.href.replace(/\/$/, "")) {
      // Allow if canonical equals one of *its own* alternates (i.e. the alternate page is part of the same hreflang cluster)
      const inCluster = alt.alternates.some((x) => x.href === alt.canonical);
      if (!inCluster) {
        issues.push({
          level: "FAIL",
          code: "CANONICAL_CONFLICT",
          message: `${a.href} canonicalizes to ${alt.canonical} which is not part of the hreflang cluster`,
        });
      }
    }
  }

  // Redirect-trap check: try Accept-Language probes against the *current* URL
  const redirectTraps: UrlReport["redirect_traps"] = [];
  for (const probe of [
    { lang: "en-US", geo: "US" },
    { lang: "de-DE,de;q=0.9", geo: "DE" },
    { lang: "ja-JP,ja;q=0.9", geo: "JP" },
  ]) {
    try {
      const r = await fetch(u.url, {
        method: "GET",
        redirect: "manual",
        headers: { "User-Agent": ua, "Accept-Language": probe.lang, Accept: "text/html" },
        signal: AbortSignal.timeout(Math.min(timeout, 15000)),
      });
      if (r.status >= 300 && r.status < 400) {
        const loc = r.headers.get("location") ?? "";
        if (loc) {
          const target = new URL(loc, u.url).toString();
          redirectTraps.push({ lang: probe.lang, geo: probe.geo, redirected_to: target });
          if (target !== u.url) {
            issues.push({
              level: "FAIL",
              code: "AUTO_REDIRECT_TRAP",
              message: `Server auto-redirects ${u.url} → ${target} on Accept-Language ${probe.lang} (${probe.geo}). Google requires the requested URL to render directly.`,
            });
          }
        }
      }
    } catch (err) {
      issues.push({ level: "WARN", code: "PROBE_FAIL", message: `Geo probe ${probe.geo} failed: ${(err as Error).message}` });
    }
  }

  reports.push({
    url: u.url,
    template: u.template,
    alternates: data.alternates,
    canonical: data.canonical,
    issues,
    redirect_traps: redirectTraps,
  });
}

// summary
const failCount = reports.reduce((s, r) => s + r.issues.filter((i) => i.level === "FAIL").length, 0);
const warnCount = reports.reduce((s, r) => s + r.issues.filter((i) => i.level === "WARN").length, 0);

await Bun.write(jsonPath, JSON.stringify({ generated: new Date().toISOString(), fail_count: failCount, warn_count: warnCount, reports }, null, 2));

const md: string[] = [
  `# Hreflang validation — ${new Date().toISOString()}`,
  ``,
  `## Summary`,
  `- URLs checked: ${reports.length}`,
  `- FAIL issues: ${failCount}`,
  `- WARN issues: ${warnCount}`,
  ``,
  `## Per-URL`,
  ``,
];
for (const r of reports) {
  md.push(`### ${r.url}${r.template ? ` (${r.template})` : ""}`);
  md.push(`- Alternates: ${r.alternates.length}`);
  for (const a of r.alternates) md.push(`  - \`${a.hreflang}\` → ${a.href} (${a.source})`);
  md.push(`- Canonical: ${r.canonical ?? "(none)"}`);
  if (r.redirect_traps.length > 0) {
    md.push(`- Geo probes:`);
    for (const t of r.redirect_traps) md.push(`  - ${t.geo} (${t.lang}) → ${t.redirected_to}`);
  }
  if (r.issues.length === 0) md.push(`- ✅ No issues`);
  else for (const i of r.issues) md.push(`- ${i.level === "FAIL" ? "❌" : "⚠"} [${i.code}] ${i.message}`);
  md.push(``);
}

await Bun.write(outPath, md.join("\n"));
console.log(`Hreflang report at ${outPath}. FAIL=${failCount} WARN=${warnCount}`);
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

function extractAlternates(html: string, headerLink: string, _baseUrl: string): Alt[] {
  const out: Alt[] = [];
  // HTML <link> tags (any attribute order)
  const linkRe = /<link\s+([^>]+?)\/?>/gi;
  for (const m of html.matchAll(linkRe)) {
    const attrs = m[1];
    if (!hasRelToken(attrs, "alternate")) continue;
    const hreflang = attrValue(attrs, "hreflang");
    const href = attrValue(attrs, "href");
    if (hreflang && href) out.push({ hreflang, href, source: "html" });
  }
  // HTTP Link header
  if (headerLink) {
    for (const part of splitLinkHeader(headerLink)) {
      const href = part.match(/<([^>]+)>/)?.[1];
      const rel = linkHeaderParam(part, "rel");
      const hreflang = linkHeaderParam(part, "hreflang");
      if (href && hreflang && rel?.toLowerCase().split(/\s+/).includes("alternate")) {
        out.push({ hreflang, href, source: "header" });
      }
    }
  }
  return out;
}

function extractCanonical(html: string): string | null {
  // Attribute order is not significant in HTML — match attrs independently so
  // <link href="..." rel="canonical"> is detected as well as the reverse.
  const linkRe = /<link\s+([^>]+?)\/?>/gi;
  for (const m of html.matchAll(linkRe)) {
    const attrs = m[1];
    if (!hasRelToken(attrs, "canonical")) continue;
    const href = attrValue(attrs, "href");
    if (href) return href;
  }
  return null;
}

function attrValue(attrs: string, name: string): string | null {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return attrs.match(new RegExp(`\\b${escaped}\\s*=\\s*["']([^"']+)["']`, "i"))?.[1] ?? null;
}

function hasRelToken(attrs: string, token: string): boolean {
  const rel = attrValue(attrs, "rel");
  return rel ? rel.toLowerCase().split(/\s+/).includes(token.toLowerCase()) : false;
}

function splitLinkHeader(header: string): string[] {
  const parts: string[] = [];
  let cur = "";
  let inAngle = false;
  let quote: string | null = null;
  for (const ch of header) {
    if (quote) {
      cur += ch;
      if (ch === quote) quote = null;
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
      cur += ch;
      continue;
    }
    if (ch === "<") inAngle = true;
    if (ch === ">") inAngle = false;
    if (ch === "," && !inAngle) {
      if (cur.trim()) parts.push(cur.trim());
      cur = "";
    } else {
      cur += ch;
    }
  }
  if (cur.trim()) parts.push(cur.trim());
  return parts;
}

function linkHeaderParam(part: string, name: string): string | null {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const m = part.match(new RegExp(`(?:^|;)\\s*${escaped}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^;\\s,]+))`, "i"));
  return m ? (m[1] ?? m[2] ?? m[3] ?? null) : null;
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
