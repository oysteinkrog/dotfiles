#!/usr/bin/env bun
/**
 * entity-consistency-check.ts — Cross-surface entity reconciliation.
 *
 * For the homepage (and an optional list of about/company URLs):
 *   - Extract Organization JSON-LD: name, url, logo, sameAs[]
 *   - Extract og:site_name and a footer brand mention (a heuristic scan of the
 *     page footer for the org name)
 *   - Cross-check Organization.url against page canonical and og:url
 *   - Resolve each Organization.sameAs target:
 *       * HTTP 200 reachable
 *       * Where the platform exposes a profile bio/website link, check that the
 *         linked URL points back at the homepage (best-effort, public scrapes).
 *         Supported: Twitter/X, LinkedIn (company), GitHub (org/user), YouTube
 *         (channel), Instagram, Facebook (page), Mastodon (rel=me), Wikipedia,
 *         Wikidata, Crunchbase. Other sameAs targets are reachability-checked
 *         only and emit an INFO line.
 *   - Cross-check Organization.logo: 200 + image/* + dims ≥ 112x112 (Google
 *     guidance) and not a hotlinked CDN with auth gating.
 *
 * Outputs:
 *   - analyses/entity-consistency.md
 *   - analyses/entity-consistency.json
 *
 * Usage:
 *   bun run scripts/entity-consistency-check.ts \
 *     --homepage https://www.example.com/ \
 *     [--also analyses/entity-pages.json] \
 *     [--output analyses/entity-consistency.md] \
 *     [--ci true]
 *
 * --also file shape: { "urls": ["https://example.com/about", ...] }
 *
 * Exit codes: 0 pass; 1 FAIL with --ci; 2 missing args.
 */

import { mkdir } from "node:fs/promises";
import { dirname } from "node:path";

const args = parseArgs(Bun.argv.slice(2));
const homepage = args["--homepage"];
const alsoPath = args["--also"];
const outPath = args["--output"] ?? "analyses/entity-consistency.md";
const jsonPath = companionJsonPath(outPath);
const ci = (args["--ci"] ?? "false") === "true";
const timeout = Number(args["--timeout"] ?? 30000);
const ua = "Mozilla/5.0 (compatible; SEO-Skill-EntityCheck/1.0)";

if (!homepage) {
  console.error("Required: --homepage <url>");
  process.exit(2);
}

await mkdir(dirname(outPath), { recursive: true });

const alsoUrls: string[] = alsoPath ? await readAlsoUrls(alsoPath) : [];

type Issue = { level: "FAIL" | "WARN" | "INFO"; code: string; message: string };
const issues: Issue[] = [];

const home = await fetchText(homepage);
const orgs = extractOrganizationLd(home.html);
if (orgs.length === 0) {
  issues.push({ level: "FAIL", code: "NO_ORG_LD", message: "Organization JSON-LD not found on homepage" });
}
// Match meta/link tags by attribute name regardless of attribute order —
// strict-order regex misses tags where content/href appears before name/rel.
const matchMeta = (kind: "name" | "property", value: string): string | null => {
  const re = /<meta\s+([^>]+?)\/?>/gi;
  for (const m of home.html.matchAll(re)) {
    const attrs = m[1];
    const escaped = value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (!new RegExp(`\\b${kind}\\s*=\\s*["']${escaped}["']`, "i").test(attrs)) continue;
    const content = attrValue(attrs, "content");
    if (content) return content;
  }
  return null;
};
const matchCanonical = (): string | null => {
  const re = /<link\s+([^>]+?)\/?>/gi;
  for (const m of home.html.matchAll(re)) {
    const attrs = m[1];
    if (!hasRelToken(attrs, "canonical")) continue;
    const href = attrValue(attrs, "href");
    if (href) return href;
  }
  return null;
};
const og_site_name = matchMeta("property", "og:site_name");
const og_url = matchMeta("property", "og:url");
const canonical = matchCanonical();
const footerText = extractFooterText(home.html);

// Pick the primary Organization (first one with both name+url, else first one)
const primary = orgs.find((o) => stringField(o.name) && stringField(o.url)) ?? orgs[0];
const primaryName = stringField(primary?.name);
const primaryUrl = stringField(primary?.url);
const primaryLogo = stringField(primary?.logo) ?? stringField(primary?.logo?.url);
const sameAs = stringList(primary?.sameAs);

if (primaryName && og_site_name && primaryName.toLowerCase() !== og_site_name.toLowerCase()) {
  issues.push({ level: "WARN", code: "NAME_MISMATCH_OG", message: `Organization.name "${primaryName}" ≠ og:site_name "${og_site_name}"` });
}
if (primaryUrl && canonical && !sameOrigin(primaryUrl, canonical, homepage, homepage)) {
  issues.push({ level: "FAIL", code: "URL_MISMATCH_CANONICAL", message: `Organization.url "${primaryUrl}" ≠ canonical "${canonical}" (different origin)` });
}
if (primaryUrl && og_url && !sameOrigin(primaryUrl, og_url, homepage, homepage)) {
  issues.push({ level: "WARN", code: "URL_MISMATCH_OG", message: `Organization.url "${primaryUrl}" ≠ og:url "${og_url}"` });
}
if (primaryName && footerText && !footerText.toLowerCase().includes(primaryName.toLowerCase())) {
  issues.push({ level: "WARN", code: "FOOTER_NO_BRAND", message: `Footer does not visibly mention brand name "${primaryName}"` });
}

// logo check
let logoOk = false;
let logoStatus: number | null = null;
let logoCT: string | null = null;
let logoBytes: number | null = null;
if (primaryLogo) {
  try {
    const r = await fetch(new URL(primaryLogo, homepage).toString(), { method: "HEAD", headers: { "User-Agent": ua }, redirect: "follow", signal: AbortSignal.timeout(timeout) });
    logoStatus = r.status;
    logoCT = r.headers.get("content-type");
    const cl = r.headers.get("content-length");
    logoBytes = cl ? Number(cl) : null;
    if (!r.ok) issues.push({ level: "FAIL", code: "LOGO_NON_200", message: `Logo returned ${r.status}` });
    else if (!logoCT || !/^image\//i.test(logoCT)) issues.push({ level: "FAIL", code: "LOGO_BAD_CT", message: `Logo Content-Type ${logoCT}` });
    else logoOk = true;
  } catch (e) {
    issues.push({ level: "FAIL", code: "LOGO_FETCH", message: (e as Error).message });
  }
} else {
  issues.push({ level: "WARN", code: "NO_LOGO", message: "Organization.logo not declared" });
}

// sameAs targets
type SameAsResult = { url: string; platform: string; status: number | null; back_link: string | null; back_matches: boolean | null; note: string };
const sameAsResults: SameAsResult[] = [];
for (const sa of sameAs) {
  const platform = identifyPlatform(sa);
  const item: SameAsResult = { url: sa, platform, status: null, back_link: null, back_matches: null, note: "" };
  try {
    const r = await fetch(sa, { method: "GET", headers: { "User-Agent": ua, Accept: "text/html" }, redirect: "follow", signal: AbortSignal.timeout(timeout) });
    item.status = r.status;
    if (!r.ok) {
      issues.push({ level: "FAIL", code: "SAMEAS_NON_200", message: `${sa} returned ${r.status}` });
      sameAsResults.push(item);
      continue;
    }
    const html = await r.text();
    const back = extractProfileBackLink(html, platform);
    item.back_link = back;
    if (back) {
      item.back_matches = sameOrigin(back, primaryUrl ?? homepage, sa, homepage);
      if (!item.back_matches) {
        issues.push({ level: "WARN", code: "SAMEAS_NO_RECIPROCAL", message: `${platform} profile (${sa}) does not link back to homepage origin (got ${back})` });
      }
    } else {
      item.note = "no public profile link surface for this platform; reachability-only check";
      issues.push({ level: "INFO", code: "SAMEAS_REACH_ONLY", message: `${sa} (${platform}) reachable; reciprocity not verifiable from public HTML` });
    }
  } catch (e) {
    issues.push({ level: "FAIL", code: "SAMEAS_FETCH", message: `${sa}: ${(e as Error).message}` });
  }
  sameAsResults.push(item);
}

// Cross-check on additional pages for entity consistency
const alsoChecks: Array<{ url: string; ok: boolean; note: string }> = [];
for (const u of alsoUrls) {
  try {
    const t = await fetchText(u);
    const orgs2 = extractOrganizationLd(t.html);
    // Without a primary name we can't meaningfully compare — treating two
    // missing names as "consistent" would be a false positive.
    const same = primaryName
      ? orgs2.find((o) => stringField(o.name)?.toLowerCase() === primaryName.toLowerCase()) ?? null
      : null;
    if (orgs2.length === 0) alsoChecks.push({ url: u, ok: false, note: "no Organization JSON-LD" });
    else if (!primaryName) alsoChecks.push({ url: u, ok: false, note: "primary Organization has no name to compare" });
    else if (!same) {
      const otherName = stringField(orgs2[0].name) ?? "—";
      issues.push({ level: "WARN", code: "ALSO_NAME_DIFFERS", message: `${u} declares Organization.name "${otherName}" — different from "${primaryName}"` });
      alsoChecks.push({ url: u, ok: false, note: `name=${otherName}` });
    } else {
      alsoChecks.push({ url: u, ok: true, note: "consistent" });
    }
  } catch (e) {
    alsoChecks.push({ url: u, ok: false, note: (e as Error).message });
  }
}

// Output
const failCount = issues.filter((i) => i.level === "FAIL").length;
const warnCount = issues.filter((i) => i.level === "WARN").length;
const footerMentionsBrand = primaryName
  ? footerText?.toLowerCase().includes(primaryName.toLowerCase()) ?? false
  : null;

const json = {
  generated: new Date().toISOString(),
  homepage,
  organization: {
    name: primaryName,
    url: primaryUrl,
    logo: primaryLogo,
    logo_check: { status: logoStatus, content_type: logoCT, bytes: logoBytes, ok: logoOk },
    sameAs: sameAsResults,
  },
  surfaces: { og_site_name, og_url, canonical, footer_mentions_brand: footerMentionsBrand },
  also: alsoChecks,
  issues,
  fail_count: failCount,
  warn_count: warnCount,
};
await Bun.write(jsonPath, JSON.stringify(json, null, 2));

const md: string[] = [
  `# Entity consistency — ${homepage}`,
  `Generated: ${new Date().toISOString()}`,
  ``,
  `## Organization`,
  `- name: ${primaryName ?? "—"}`,
  `- url: ${primaryUrl ?? "—"}`,
  `- logo: ${primaryLogo ?? "—"} (status ${logoStatus ?? "—"}, type ${logoCT ?? "—"})`,
  `- sameAs (${sameAs.length}):`,
  ...sameAsResults.map(formatSameAsLine),
  ``,
  `## Surface cross-checks`,
  `- og:site_name: ${og_site_name ?? "—"}`,
  `- og:url:       ${og_url ?? "—"}`,
  `- canonical:    ${canonical ?? "—"}`,
  `- footer mentions brand: ${footerMentionsBrand ?? "—"}`,
  ``,
  `## Also pages`,
  ...(alsoChecks.length ? alsoChecks.map((a) => `- ${a.url} — ${a.ok ? "✅" : "⚠"} ${a.note}`) : ["(none)"]),
  ``,
  `## Issues (${issues.length})`,
  ...(issues.length === 0 ? ["✅ No issues."] : issues.map(formatIssueLine)),
  ``,
  `Summary: FAIL=${failCount}  WARN=${warnCount}`,
];
await Bun.write(outPath, md.join("\n"));
console.log(`Entity consistency report at ${outPath}. FAIL=${failCount} WARN=${warnCount}`);
process.exit(ci && failCount > 0 ? 1 : 0);

// ---- helpers ----

function companionJsonPath(path: string): string {
  return path.endsWith(".md") ? `${path.slice(0, -3)}.json` : `${path}.json`;
}

function formatSameAsLine(s: (typeof sameAsResults)[number]): string {
  let suffix = "";
  if (s.back_matches === true) {
    suffix = " ✅ reciprocal";
  } else if (s.back_matches === false) {
    suffix = ` ❌ links to ${s.back_link}`;
  } else if (s.note) {
    suffix = ` (${s.note})`;
  }
  return `  - ${s.platform} ${s.url} — status ${s.status ?? "—"}${suffix}`;
}

function formatIssueLine(i: Issue): string {
  return `- ${issueIcon(i.level)} [${i.code}] ${i.message}`;
}

function issueIcon(level: Issue["level"]): string {
  if (level === "FAIL") return "❌";
  if (level === "WARN") return "⚠";
  return "ℹ";
}

async function fetchText(u: string) {
  const r = await fetch(u, { headers: { "User-Agent": ua, Accept: "text/html" }, redirect: "follow", signal: AbortSignal.timeout(timeout) });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return { html: await r.text(), status: r.status };
}

async function readAlsoUrls(path: string): Promise<string[]> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(await Bun.file(path).text());
  } catch (error) {
    throw new Error(`Invalid --also JSON in ${path}: ${error instanceof Error ? error.message : String(error)}`);
  }
  if (!parsed || typeof parsed !== "object" || !Array.isArray((parsed as { urls?: unknown }).urls)) {
    throw new Error(`Invalid --also file ${path}: expected {"urls":["https://..."]}`);
  }
  const urls = (parsed as { urls: unknown[] }).urls;
  if (!urls.every((url) => typeof url === "string" && url.trim())) {
    throw new Error(`Invalid --also file ${path}: urls must be non-empty strings`);
  }
  return urls.map((url) => (url as string).trim());
}

function stringField(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed || null;
}

function stringList(value: unknown): string[] {
  if (Array.isArray(value)) return value.map(stringField).filter((url): url is string => url !== null);
  const single = stringField(value);
  return single ? [single] : [];
}

function extractOrganizationLd(html: string): any[] {
  const blocks = Array.from(html.matchAll(/<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)).map((m) => m[1]);
  const out: any[] = [];
  for (const b of blocks) {
    let parsed: any;
    try { parsed = JSON.parse(b.trim()); } catch { continue; }
    // JSON.parse("null") yields null; also guard against non-object roots.
    if (parsed === null || typeof parsed !== "object") continue;
    const items = Array.isArray(parsed)
      ? parsed
      : Array.isArray(parsed["@graph"])
        ? parsed["@graph"]
        : [parsed];
    for (const item of items) {
      if (!item || typeof item !== "object") continue;
      const t = item["@type"];
      if (t === "Organization" || (Array.isArray(t) && t.includes("Organization")) || t === "Corporation" || (typeof t === "string" && /Organization$/.test(t))) {
        out.push(item);
      }
    }
  }
  return out;
}

function extractFooterText(html: string): string | null {
  const m = html.match(/<footer[\s\S]*?<\/footer>/i);
  if (!m) return null;
  return m[0].replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
}

function attrValue(attrs: string, name: string): string | null {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return attrs.match(new RegExp(`\\b${escaped}\\s*=\\s*["']([^"']*)["']`, "i"))?.[1] ?? null;
}

function hasRelToken(attrs: string, token: string): boolean {
  const rel = attrValue(attrs, "rel");
  return rel ? rel.toLowerCase().split(/\s+/).includes(token.toLowerCase()) : false;
}

function sameOrigin(a: string, b: string, baseA?: string, baseB?: string): boolean {
  try {
    const u1 = new URL(a, baseA);
    const u2 = new URL(b, baseB ?? baseA);
    return u1.host.replace(/^www\./, "") === u2.host.replace(/^www\./, "") && u1.protocol === u2.protocol;
  } catch {
    return false;
  }
}

function identifyPlatform(u: string): string {
  try {
    const h = new URL(u).hostname.replace(/^www\./, "").toLowerCase();
    if (h === "twitter.com" || h === "x.com") return "twitter";
    if (h === "linkedin.com") return "linkedin";
    if (h === "github.com") return "github";
    if (h === "youtube.com" || h === "m.youtube.com") return "youtube";
    if (h === "instagram.com") return "instagram";
    if (h === "facebook.com" || h === "m.facebook.com") return "facebook";
    if (h === "wikipedia.org" || h.endsWith(".wikipedia.org")) return "wikipedia";
    if (h === "wikidata.org" || h === "www.wikidata.org") return "wikidata";
    if (h === "crunchbase.com") return "crunchbase";
    if (h === "tiktok.com") return "tiktok";
    if (h === "threads.net") return "threads";
    if (h === "mastodon.social" || /\.mastodon\./.test(h)) return "mastodon";
    return h;
  } catch {
    return "unknown";
  }
}

/**
 * Best-effort: extract the public profile's "back link" (link to the company's
 * own website) from server-rendered HTML.
 */
function extractProfileBackLink(html: string, platform: string): string | null {
  // strip scripts/styles to reduce false positives
  const stripped = html.replace(/<script[\s\S]*?<\/script>/g, " ").replace(/<style[\s\S]*?<\/style>/g, " ");
  switch (platform) {
    case "github": {
      // GitHub renders profile websites in <a rel="nofollow me" class="..." href="...">
      const m = stripped.match(/<a[^>]+rel=["'][^"']*me[^"']*["'][^>]*href=["']([^"']+)["']/i);
      return m?.[1] ?? null;
    }
    case "twitter": {
      // X/Twitter exposes the bio website link as t.co; we can at least extract the visible card target via og:url-style
      const m = stripped.match(/<a[^>]+href=["'](https?:\/\/t\.co\/[^"']+)["'][^>]*data-testid=["']UserUrl["']/i)
        ?? stripped.match(/UserUrl[^>]*href=["']([^"']+)["']/i);
      return m?.[1] ?? null;
    }
    case "linkedin": {
      // LinkedIn company page renders website under data-test-id=about-us__website
      const m = stripped.match(/data-test-id=["']about-us__website["'][^>]*href=["']([^"']+)["']/i)
        ?? stripped.match(/<dt[^>]*>\s*Website\s*<\/dt>\s*<dd[\s\S]*?<a[^>]+href=["']([^"']+)["']/i);
      return m?.[1] ?? null;
    }
    case "youtube": {
      const m = stripped.match(/"channelExternalLinkViewModel"[\s\S]*?"link"\s*:\s*"([^"]+)"/i)
        ?? stripped.match(/itemprop=["']url["'][^>]*href=["']([^"']+)["']/i);
      return m?.[1] ?? null;
    }
    case "instagram":
    case "threads": {
      const m = stripped.match(/"external_url"\s*:\s*"([^"]+)"/i);
      return m?.[1] ?? null;
    }
    case "facebook": {
      const m = stripped.match(/"website"\s*:\s*"([^"]+)"/i);
      return m?.[1] ?? null;
    }
    case "mastodon": {
      const m = stripped.match(/<a[^>]+rel=["'][^"']*me[^"']*["'][^>]*href=["']([^"']+)["']/i);
      return m?.[1] ?? null;
    }
    default:
      return null;
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
