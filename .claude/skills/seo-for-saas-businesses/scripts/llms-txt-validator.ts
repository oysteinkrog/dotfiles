#!/usr/bin/env bun
/**
 * llms-txt-validator.ts — Fetch and validate /llms.txt (and /llms-full.txt if present).
 *
 * Per https://llmstxt.org (Sep 2024). Format:
 *   # Title
 *   > One-line description (optional, blockquote)
 *   ## Section name
 *   - [Link title](https://...): optional context
 *
 * Validates:
 *   - file present + parses as Markdown with required H1 and at least one H2 section with links
 *   - every linked URL returns 2xx (HEAD; falls back to GET on 405/501)
 *   - every URL is absolute and on the same site origin (warn if external)
 *   - cross-checks robots.txt: warn if a URL listed here is effectively blocked for any active search / AI bot
 *   - if /llms-full.txt exists, fetches it and verifies it's plausibly Markdown (has H1)
 *
 * Output:
 *   - analyses/llms-txt.md   — human report
 *   - analyses/llms-txt.json — structured
 *
 * Usage:
 *   bun run scripts/llms-txt-validator.ts \
 *     --site https://www.example.com \
 *     [--output analyses/llms-txt.md] \
 *     [--check-robots true]    # default true
 *     [--ci true]
 *
 * Exit codes: 0 ok; 1 FAIL with --ci true; 2 missing args.
 */

import { mkdir } from "node:fs/promises";
import { dirname } from "node:path";

type Issue = { level: "FAIL" | "WARN" | "INFO"; code: string; message: string };
type Link = { title: string; url: string; context?: string; status: number | null; ok: boolean; same_origin: boolean };
type Section = { name: string; links: Link[] };

const args = parseArgs(Bun.argv.slice(2));
const site = args["--site"];
const outPath = args["--output"] ?? "analyses/llms-txt.md";
const jsonPath = companionJsonPath(outPath);
const ci = (args["--ci"] ?? "false") === "true";
const checkRobots = (args["--check-robots"] ?? "true") === "true";

if (!site) {
  console.error("Required: --site <url>");
  process.exit(2);
}

const siteUrl = parseSiteUrl(site);
await mkdir(dirname(outPath), { recursive: true });

const ua = "Mozilla/5.0 (compatible; SEO-Skill-LLMSTxt/1.0)";
const issues: Issue[] = [];

// 1. Fetch llms.txt
const llmsUrl = new URL("/llms.txt", siteUrl).toString();
const llmsRes = await fetch(llmsUrl, { headers: { "User-Agent": ua }, redirect: "follow", signal: AbortSignal.timeout(15000) }).catch(() => null);
const llmsPresent = !!llmsRes && llmsRes.ok;
if (!llmsPresent) {
  issues.push({
    level: "INFO",
    code: "NO_LLMS_TXT",
    message: `${llmsUrl} not present (status ${llmsRes?.status ?? "fetch-failed"}). llms.txt is optional but recommended for documentation sites.`,
  });
}
const llmsText = llmsPresent ? await llmsRes!.text() : "";

// 2. Parse llms.txt structure
let title: string | null = null;
let description: string | null = null;
const sections: Section[] = [];

if (llmsPresent) {
  const lines = llmsText.split(/\r?\n/);
  let currentSection: Section | null = null;
  for (const raw of lines) {
    const line = raw.trimEnd();
    if (!line.trim()) continue;
    const h1 = line.match(/^#\s+(.+)$/);
    const h2 = line.match(/^##\s+(.+)$/);
    const blockquote = line.match(/^>\s+(.+)$/);
    const linkLine = line.match(/^[-*]\s+\[([^\]]+)\]\(([^)]+)\)(?:\s*[:\-—]\s*(.*))?$/);
    if (h1) { title = h1[1]; continue; }
    if (h2) {
      currentSection = { name: h2[1], links: [] };
      sections.push(currentSection);
      continue;
    }
    if (blockquote && !description) { description = blockquote[1]; continue; }
    if (linkLine) {
      if (!currentSection) {
        // links before any H2 — accept under a default "Optional" section per spec
        currentSection = { name: "Optional", links: [] };
        sections.push(currentSection);
      }
      currentSection.links.push({
        title: linkLine[1],
        url: linkLine[2],
        context: linkLine[3]?.trim() || undefined,
        status: null,
        ok: false,
        same_origin: false,
      });
    }
  }
  const parsedLinkCount = sections.reduce((sum, section) => sum + section.links.length, 0);
  if (!title) issues.push({ level: "FAIL", code: "NO_TITLE", message: "llms.txt missing required H1 title." });
  if (parsedLinkCount === 0) issues.push({ level: "FAIL", code: "NO_SECTIONS", message: "llms.txt has no sections with links." });
}

// 3. Resolve each link
const siteOrigin = siteUrl.origin;
for (const sec of sections) {
  for (const link of sec.links) {
    // Absolute URL required per AI-BOTS-AND-LLMSTXT.md guidance
    if (!/^https?:\/\//i.test(link.url)) {
      issues.push({ level: "FAIL", code: "RELATIVE_URL", message: `Link "${link.title}" has relative href "${link.url}" — must be absolute.` });
      link.status = null; link.ok = false; link.same_origin = false;
      continue;
    }
    let linkOrigin: string;
    try { linkOrigin = new URL(link.url).origin; }
    catch { issues.push({ level: "FAIL", code: "BAD_URL", message: `Link "${link.title}" has invalid URL "${link.url}".` }); continue; }
    link.same_origin = linkOrigin === siteOrigin;
    if (!link.same_origin) {
      issues.push({ level: "WARN", code: "EXTERNAL_URL", message: `Link "${link.title}" points off-origin (${linkOrigin}) — most LLMs treat llms.txt as canonical-for-this-site only.` });
    }
    try {
      let r = await fetch(link.url, { method: "HEAD", headers: { "User-Agent": ua }, redirect: "follow", signal: AbortSignal.timeout(15000) });
      if (r.status === 405 || r.status === 501) {
        // some servers don't allow HEAD
        r = await fetch(link.url, { method: "GET", headers: { "User-Agent": ua }, redirect: "follow", signal: AbortSignal.timeout(15000) });
      }
      link.status = r.status;
      link.ok = r.ok;
      if (!r.ok) {
        issues.push({ level: "FAIL", code: "STALE_URL", message: `Link "${link.title}" → ${link.url} returned ${r.status}.` });
      }
    } catch (e) {
      link.status = null;
      link.ok = false;
      issues.push({ level: "FAIL", code: "FETCH_FAIL", message: `Link "${link.title}" → ${link.url}: ${(e as Error).message}` });
    }
  }
}

// 4. llms-full.txt sanity check
const fullUrl = new URL("/llms-full.txt", siteUrl).toString();
let llmsFullPresent = false;
let llmsFullStatus: number | null = null;
try {
  const r = await fetch(fullUrl, { headers: { "User-Agent": ua }, redirect: "follow", signal: AbortSignal.timeout(15000) });
  llmsFullStatus = r.status;
  llmsFullPresent = r.ok;
  if (r.ok) {
    const txt = await r.text();
    if (!/^#\s+/m.test(txt)) {
      issues.push({ level: "WARN", code: "LLMS_FULL_NO_H1", message: `${fullUrl} present but does not look like Markdown (no H1).` });
    }
  }
} catch {
  // not present is fine; emit INFO only if llms.txt exists
  if (llmsPresent) {
    issues.push({ level: "INFO", code: "NO_LLMS_FULL", message: `${fullUrl} not present (optional companion).` });
  }
}

// 5. Robots conflict check
if (checkRobots && llmsPresent && sections.length > 0) {
  try {
    const robotsRes = await fetch(new URL("/robots.txt", siteUrl).toString(), { headers: { "User-Agent": ua }, redirect: "follow", signal: AbortSignal.timeout(15000) });
    if (robotsRes.ok) {
      const robotsTxt = await robotsRes.text();
      const groups = parseRobots(robotsTxt);
      const bots = ["GPTBot", "OAI-SearchBot", "ClaudeBot", "Claude-SearchBot", "PerplexityBot"];
      for (const sec of sections) {
        for (const link of sec.links) {
          if (!link.same_origin) continue;
          const path = pathOf(link.url);
          for (const bot of bots) {
            if (decide(bot, path, groups) === "BLOCKED") {
              issues.push({
                level: "WARN",
                code: "ROBOTS_CONFLICT",
                message: `${path} is listed in llms.txt but blocked by robots.txt for ${bot}.`,
              });
            }
          }
        }
      }
    }
  } catch {
    // best-effort; robots fetch failure is the AI-bot script's concern
  }
}

// 6. Stable summary
const failCount = issues.filter((i) => i.level === "FAIL").length;
const warnCount = issues.filter((i) => i.level === "WARN").length;
const totalLinks = sections.reduce((s, sec) => s + sec.links.length, 0);
const okLinks = sections.reduce((s, sec) => s + sec.links.filter((l) => l.ok).length, 0);

await Bun.write(jsonPath, JSON.stringify({
  generated: new Date().toISOString(),
  site,
  llms_txt_present: llmsPresent,
  llms_txt_url: llmsUrl,
  llms_full_present: llmsFullPresent,
  llms_full_status: llmsFullStatus,
  title,
  description,
  sections,
  link_total: totalLinks,
  link_ok: okLinks,
  issues,
  fail_count: failCount,
  warn_count: warnCount,
}, null, 2));

const md: string[] = [
  `# llms.txt validation — ${site}`,
  ``,
  `- llms.txt: ${llmsPresent ? `✅ present (${llmsUrl})` : `⚠ absent (${llmsUrl})`}`,
  `- llms-full.txt: ${llmsFullPresent ? `✅ present (${fullUrl})` : `— not present`}`,
  `- Title: ${title ?? "—"}`,
  `- Description: ${description ?? "—"}`,
  `- Links: ${okLinks} ok / ${totalLinks} total`,
  `- FAIL: ${failCount}   WARN: ${warnCount}`,
  ``,
];
if (sections.length > 0) {
  md.push(`## Sections`, ``);
  for (const sec of sections) {
    md.push(`### ${sec.name} (${sec.links.length})`);
    for (const l of sec.links) {
      md.push(`- ${formatLinkStatus(l)} [${l.title}](${l.url})${formatLinkMetadata(l)}`);
    }
    md.push(``);
  }
}
md.push(`## Issues`, ``);
if (issues.length === 0) md.push(`✅ No issues.`);
for (const i of issues) {
  md.push(`- ${issueIcon(i.level)} [${i.code}] ${i.message}`);
}
md.push(``, `See \`references/AI-BOTS-AND-LLMSTXT.md\` for context.`);

await Bun.write(outPath, md.join("\n"));
console.log(`llms.txt report at ${outPath}. FAIL=${failCount} WARN=${warnCount}`);
process.exit(ci && failCount > 0 ? 1 : 0);

// ---- helpers ----

type RobotGroup = { allow: string[]; disallow: string[] };

function companionJsonPath(path: string): string {
  return path.endsWith(".md") ? path.slice(0, -3) + ".json" : `${path}.json`;
}

function parseSiteUrl(value: string): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    console.error(`Invalid --site URL: ${value}`);
    process.exit(2);
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    console.error(`Invalid --site URL: ${value} (expected http or https)`);
    process.exit(2);
  }
  return url;
}

function formatLinkStatus(link: Link): string {
  return link.ok ? "✅" : "❌";
}

function formatLinkMetadata(link: Link): string {
  const parts: string[] = [];
  if (link.status !== null) parts.push(` (status ${link.status})`);
  if (link.context) parts.push(` — ${link.context}`);
  return parts.join("");
}

function issueIcon(level: Issue["level"]): string {
  if (level === "FAIL") return "❌";
  if (level === "WARN") return "⚠";
  return "ℹ";
}

function parseRobots(text: string): Record<string, RobotGroup> {
  const out: Record<string, RobotGroup> = {};
  let pendingUAs: string[] = [];
  let inRules = false;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.replace(/#.*$/, "").trim();
    if (!line) {
      pendingUAs = [];
      inRules = false;
      continue;
    }
    const m = line.match(/^([A-Za-z-]+)\s*:\s*(.+)$/);
    if (!m) continue;
    const directive = m[1].toLowerCase();
    const value = m[2].trim();
    if (directive === "user-agent") {
      if (inRules) pendingUAs = [];
      pendingUAs.push(value.toLowerCase());
      if (!out[value.toLowerCase()]) out[value.toLowerCase()] = { allow: [], disallow: [] };
      inRules = false;
    } else if (directive === "allow" || directive === "disallow") {
      inRules = true;
      for (const ua of pendingUAs) {
        if (!out[ua]) out[ua] = { allow: [], disallow: [] };
        if (directive === "allow") out[ua].allow.push(value);
        else out[ua].disallow.push(value);
      }
    }
  }
  return out;
}

function decide(ua: string, path: string, groups: Record<string, RobotGroup>): "BLOCKED" | "ALLOWED" | "UNSPECIFIED" {
  const key = ua.toLowerCase();
  const group = groups[key] ?? groups["*"];
  if (!group) return "UNSPECIFIED";
  const allowMatch = longestMatch(group.allow, path);
  const disallowMatch = longestMatch(group.disallow, path);
  if (disallowMatch === null && allowMatch === null) return "ALLOWED";
  if (disallowMatch === null) return "ALLOWED";
  if (allowMatch === null) return disallowMatch === "" ? "ALLOWED" : "BLOCKED";
  return allowMatch.length >= disallowMatch.length ? "ALLOWED" : "BLOCKED";
}

function longestMatch(rules: string[], path: string): string | null {
  let best: string | null = null;
  for (const rule of rules) {
    if (matchesGlob(rule, path)) {
      if (best === null || rule.length > best.length) best = rule;
    }
  }
  return best;
}

function pathOf(url: string): string {
  try { const u = new URL(url); return u.pathname + (u.search ?? ""); }
  catch { return url; }
}

function matchesGlob(pattern: string, path: string): boolean {
  if (pattern === "") return true;
  const hasEndAnchor = pattern.endsWith("$");
  const body = hasEndAnchor ? pattern.slice(0, -1) : pattern;
  const escaped = body.replace(/[.+?^${}()|[\]\\]/g, "\\$&");
  const withWildcards = escaped.replace(/\*/g, ".*");
  const src = hasEndAnchor ? `^${withWildcards}$` : `^${withWildcards}`;
  try { return new RegExp(src).test(path); }
  catch { return false; }
}

function parseArgs(argv: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (let j = 0; j < argv.length; j++) {
    const arg = argv[j];
    if (!arg.startsWith("--")) continue;
    const eq = arg.indexOf("=");
    if (eq > 2) { out[arg.slice(0, eq)] = arg.slice(eq + 1); continue; }
    const next = argv[j + 1];
    if (next === undefined || next.startsWith("--")) {
      out[arg] = "true";
    } else {
      out[arg] = next;
      j++;
    }
  }
  return out;
}
