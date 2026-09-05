#!/usr/bin/env bun
/**
 * redirect-chain-audit.ts — Walk every URL in a representative set or sitemap
 * and validate its redirect chain.
 *
 * Flags:
 *   - chains > 1 hop (each extra hop is wasted crawl budget + lost link equity)
 *   - redirect loops (A → B → A …)
 *   - mixed-protocol chains (http ↔ https)
 *   - mixed-host chains (www ↔ apex, marketing ↔ app)
 *   - redirect → redirect → final (intermediate hops should be eliminated)
 *   - redirect → 404 / 410 / 5xx
 *   - 302 used where 301 expected (root, www, http→https)
 *   - meta-refresh redirects in 200 responses (treated as soft redirect)
 *
 * Outputs:
 *   - analyses/redirect-chains.md   — human-readable report
 *   - analyses/redirect-chains.json — structured per-URL chain data
 *
 * Usage:
 *   bun run scripts/redirect-chain-audit.ts \
 *     --rep-set analyses/representative-urls.json \
 *     [--sitemap https://www.example.com/sitemap.xml] \
 *     [--output analyses/redirect-chains.md] \
 *     [--max-hops 5] \
 *     [--ci true]                # exit 1 if any chain > 1 hop
 *
 * Exit codes:
 *   0 all chains clean (or --ci false)
 *   1 in --ci true mode: at least one chain > 1 hop or loop
 *   2 missing args
 */

import { mkdir } from "node:fs/promises";
import { dirname } from "node:path";

const args = parseArgs(Bun.argv.slice(2));
const repSet = args["--rep-set"];
const sitemap = args["--sitemap"];
const outPath = args["--output"] ?? "analyses/redirect-chains.md";
const jsonPath = companionJsonPath(outPath);
const maxHops = Number(args["--max-hops"] ?? 5);
const ci = (args["--ci"] ?? "false") === "true";
const timeout = Number(args["--timeout"] ?? 15000);
const ua = "Mozilla/5.0 (compatible; SEO-Skill-RedirectAudit/1.0)";

if (!repSet && !sitemap) {
  console.error("Provide --rep-set <path> or --sitemap <url>");
  process.exit(2);
}

await mkdir(dirname(outPath), { recursive: true });

const urls: string[] = [];
if (repSet) {
  const r = await readJsonFile<{ urls: Array<{ url: string }> }>(repSet, "--rep-set");
  urls.push(...r.urls.map((u) => u.url));
}
if (sitemap) {
  const xml = await (await fetch(sitemap, { signal: AbortSignal.timeout(timeout) })).text();
  for (const m of xml.matchAll(/<loc>([^<]+)<\/loc>/g)) urls.push(m[1]);
}
const uniq = Array.from(new Set(urls));

type Hop = {
  url: string;
  status: number;
  location?: string;
  meta_refresh?: string;
};
type ChainResult = {
  start: string;
  hops: Hop[];
  final_status: number;
  final_url: string;
  issues: string[];
};

const results: ChainResult[] = [];
for (const u of uniq) {
  const r = await walk(u);
  results.push(r);
}

// summary stats
const stats = {
  total: results.length,
  clean: results.filter((r) => r.issues.length === 0).length,
  multi_hop: results.filter((r) => r.hops.length - 1 > 1).length,
  loops: results.filter((r) => r.issues.some((i) => i.startsWith("LOOP"))).length,
  mixed_protocol: results.filter((r) => r.issues.some((i) => i.startsWith("MIXED_PROTOCOL"))).length,
  mixed_host: results.filter((r) => r.issues.some((i) => i.startsWith("MIXED_HOST"))).length,
  redirect_to_4xx: results.filter((r) => r.issues.some((i) => i.startsWith("REDIRECT_TO_4XX"))).length,
  redirect_to_5xx: results.filter((r) => r.issues.some((i) => i.startsWith("REDIRECT_TO_5XX"))).length,
  meta_refresh: results.filter((r) => r.issues.some((i) => i.startsWith("META_REFRESH"))).length,
  s302_for_permanent: results.filter((r) => r.issues.some((i) => i.startsWith("302_NOT_301"))).length,
};

await Bun.write(jsonPath, JSON.stringify({
  generated: new Date().toISOString(),
  stats,
  results: results.map(toContractResult),
}, null, 2));

const md: string[] = [
  `# Redirect chain audit — ${new Date().toISOString()}`,
  ``,
  `## Summary`,
  `- URLs audited: ${stats.total}`,
  `- Clean (0 hops or 1-hop with no other issue): ${stats.clean}`,
  `- Multi-hop (>1 redirect): ${stats.multi_hop}`,
  `- Loops: ${stats.loops}`,
  `- Mixed-protocol chains: ${stats.mixed_protocol}`,
  `- Mixed-host chains: ${stats.mixed_host}`,
  `- Redirect → 4xx: ${stats.redirect_to_4xx}`,
  `- Redirect → 5xx: ${stats.redirect_to_5xx}`,
  `- Meta-refresh redirects: ${stats.meta_refresh}`,
  `- 302 used for permanent moves: ${stats.s302_for_permanent}`,
  ``,
  `## Issues`,
  ``,
];
for (const r of results.filter((x) => x.issues.length > 0).slice(0, 500)) {
  md.push(`### ${r.start}`);
  md.push(`- Final: HTTP ${r.final_status} → ${r.final_url}`);
  md.push(`- Hops:`);
  for (const h of r.hops) {
    md.push(`  - ${h.status} ${h.url}${h.location ? ` → ${h.location}` : ""}${h.meta_refresh ? ` (meta-refresh → ${h.meta_refresh})` : ""}`);
  }
  for (const i of r.issues) md.push(`  - ⚠ ${i}`);
  md.push(``);
}

await Bun.write(outPath, md.join("\n"));
console.log(`Redirect audit written to ${outPath}.`);

const failCi = ci && (stats.multi_hop > 0 || stats.loops > 0 || stats.redirect_to_4xx > 0 || stats.redirect_to_5xx > 0);
process.exit(failCi ? 1 : 0);

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

function toContractResult(result: ChainResult) {
  return {
    start_url: result.start,
    start: result.start,
    chain: result.hops.map((hop) => ({
      url: hop.url,
      status: hop.status,
      method: hop.meta_refresh ? "meta" : "header",
      ...(hop.location ? { location: hop.location } : {}),
      ...(hop.meta_refresh ? { location: hop.meta_refresh } : {}),
    })),
    raw_hops: result.hops,
    final_url: result.final_url,
    final_status: result.final_status,
    hops: result.hops.filter((hop) => hop.status >= 300 && hop.status < 400).length,
    issues: result.issues.map(toIssue),
    issue_messages: result.issues,
  };
}

function toIssue(message: string): { level: "FAIL" | "WARN"; code: string; message: string } {
  const code = message.split(/\s+/)[0]?.replace(/[^A-Z0-9_]/g, "_") || "ISSUE";
  const failCodes = new Set([
    "BAD_LOCATION",
    "EMPTY_LOCATION",
    "LOOP",
    "MAX_HOPS_EXCEEDED",
    "NETWORK_ERROR",
    "REDIRECT_TO_4XX",
    "REDIRECT_TO_5XX",
  ]);
  return {
    level: failCodes.has(code) ? "FAIL" : "WARN",
    code,
    message,
  };
}

async function walk(start: string): Promise<ChainResult> {
  const hops: Hop[] = [];
  const issues: string[] = [];
  const seen = new Set<string>();
  let cur = start;
  let curStatus = 0;
  for (let h = 0; h <= maxHops; h++) {
    if (seen.has(cur)) {
      issues.push(`LOOP at ${cur}`);
      hops.push({ url: cur, status: -1 });
      break;
    }
    seen.add(cur);
    let res: Response;
    try {
      res = await fetch(cur, {
        method: "GET",
        redirect: "manual",
        headers: { "User-Agent": ua, Accept: "text/html" },
        signal: AbortSignal.timeout(timeout),
      });
    } catch (err) {
      issues.push(`NETWORK_ERROR ${cur}: ${(err as Error).message}`);
      hops.push({ url: cur, status: -1 });
      break;
    }
    curStatus = res.status;
    if (res.status >= 300 && res.status < 400) {
      const loc = res.headers.get("location") ?? "";
      let next = "";
      if (loc) {
        try {
          next = new URL(loc, cur).toString();
        } catch {
          issues.push(`BAD_LOCATION at ${cur}: ${loc}`);
          hops.push({ url: cur, status: res.status, location: loc });
          break;
        }
      }
      hops.push({ url: cur, status: res.status, location: next });
      // 302 vs 301 heuristic: root, http→https, www↔apex are "permanent" intent
      if (res.status === 302) {
        try {
          const a = new URL(cur);
          const b = next ? new URL(next) : null;
          if (b && (
            a.protocol !== b.protocol ||
            a.hostname.replace(/^www\./, "") === b.hostname.replace(/^www\./, "") && a.hostname !== b.hostname ||
            a.pathname === "/" && b.pathname === "/"
          )) {
            issues.push(`302_NOT_301 ${cur} → ${next} (use 301 for permanent moves)`);
          }
        } catch { /* ignore */ }
      }
      if (!next) {
        issues.push(`EMPTY_LOCATION at ${cur} (status ${res.status})`);
        break;
      }
      try {
        const a = new URL(cur);
        const b = new URL(next);
        if (a.protocol !== b.protocol) issues.push(`MIXED_PROTOCOL ${a.protocol} → ${b.protocol}`);
        if (a.hostname !== b.hostname) issues.push(`MIXED_HOST ${a.hostname} → ${b.hostname}`);
      } catch { /* ignore */ }
      cur = next;
      continue;
    }
    // 200 (or terminal)
    if (res.status === 200) {
      // check meta-refresh
      const html = await res.text().catch(() => "");
      const mr = extractMetaRefresh(html);
      if (mr) {
        const target = new URL(mr, cur).toString();
        hops.push({ url: cur, status: 200, meta_refresh: target });
        issues.push(`META_REFRESH at ${cur} → ${target} (use server-side 301 instead)`);
        cur = target;
        continue;
      }
    }
    hops.push({ url: cur, status: res.status });
    if (res.status >= 400 && res.status < 500) {
      if (hops.length > 1) issues.push(`REDIRECT_TO_4XX final ${res.status}`);
    } else if (res.status >= 500) {
      issues.push(`REDIRECT_TO_5XX final ${res.status}`);
    }
    break;
  }

  // chain length issue
  const numRedirects = hops.filter((h) => h.status >= 300 && h.status < 400).length;
  if (numRedirects > 1) issues.push(`MULTI_HOP ${numRedirects} redirects`);
  if (hops.length > maxHops) issues.push(`MAX_HOPS_EXCEEDED ${hops.length}`);

  return {
    start,
    hops,
    final_status: hops[hops.length - 1]?.status ?? 0,
    final_url: hops[hops.length - 1]?.url ?? start,
    issues,
  };
}

function extractMetaRefresh(html: string): string | null {
  const metaRe = /<meta\s+([^>]+?)\/?>/gi;
  for (const m of html.matchAll(metaRe)) {
    const attrs = m[1];
    if (attrValue(attrs, "http-equiv")?.toLowerCase() !== "refresh") continue;
    const content = attrValue(attrs, "content");
    const target = content?.match(/^\s*\d+\s*;\s*url=(.+?)\s*$/i)?.[1];
    if (target) return target.replace(/^["']|["']$/g, "");
  }
  return null;
}

function attrValue(attrs: string, name: string): string | null {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return attrs.match(new RegExp(`\\b${escaped}\\s*=\\s*["']([^"']*)["']`, "i"))?.[1] ?? null;
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
