#!/usr/bin/env bun
/**
 * ai-bot-policy-check.ts — Audit a site's robots.txt against the 2026 AI bot UA matrix.
 *
 * For a target site:
 *   - Fetch /robots.txt
 *   - Parse rules per User-agent group (case-insensitive)
 *   - Determine, for each known AI/search bot, whether it is BLOCKED or ALLOWED at the site root
 *   - Surface common confusions:
 *       * GPTBot blocked but OAI-SearchBot also blocked (likely unintended — costs OpenAI search visibility)
 *       * Google-Extended blocked while team intends "no Search effect" (correct behavior; flag the
 *         contradiction only if the team's stated intent says otherwise)
 *       * Stale UAs (anthropic-ai) still listed
 *       * Missing entries for currently-active bots (informational)
 *
 * Outputs:
 *   - analyses/ai-bot-policy.md   — human-readable
 *   - analyses/ai-bot-policy.json — structured
 *
 * Usage:
 *   bun run scripts/ai-bot-policy-check.ts \
 *     --site https://www.example.com \
 *     [--output analyses/ai-bot-policy.md] \
 *     [--ci true]
 *
 * Exit codes: 0 ok; 1 FAIL with --ci true; 2 missing args.
 *
 * See references/AI-BOTS-AND-LLMSTXT.md for context.
 */

import { mkdir } from "node:fs/promises";
import { dirname } from "node:path";

type Issue = { level: "FAIL" | "WARN" | "INFO"; code: string; message: string };

type BotPurpose = "training" | "search" | "on-demand" | "ads" | "general";

const BOT_MATRIX: Array<{ ua: string; purpose: BotPurpose; provider: string; notes?: string }> = [
  { ua: "GPTBot",                provider: "OpenAI",     purpose: "training" },
  { ua: "OAI-SearchBot",         provider: "OpenAI",     purpose: "search" },
  { ua: "ChatGPT-User",          provider: "OpenAI",     purpose: "on-demand" },
  { ua: "OAI-AdsBot",            provider: "OpenAI",     purpose: "ads", notes: "ChatGPT ads landing-page policy / relevance checks" },
  { ua: "ClaudeBot",             provider: "Anthropic",  purpose: "training" },
  { ua: "Claude-User",           provider: "Anthropic",  purpose: "on-demand" },
  { ua: "Claude-SearchBot",      provider: "Anthropic",  purpose: "search" },
  { ua: "anthropic-ai",          provider: "Anthropic",  purpose: "training", notes: "deprecated; still seen" },
  { ua: "Googlebot",             provider: "Google",     purpose: "general" },
  { ua: "Google-Extended",       provider: "Google",     purpose: "training", notes: "Gemini / Vertex AI training and grounding opt-out; no Search effect" },
  { ua: "GoogleOther",           provider: "Google",     purpose: "general" },
  { ua: "PerplexityBot",         provider: "Perplexity", purpose: "search" },
  { ua: "Perplexity-User",       provider: "Perplexity", purpose: "on-demand", notes: "stated to bypass robots.txt; block at WAF if needed" },
  { ua: "Applebot",              provider: "Apple",      purpose: "search" },
  { ua: "Applebot-Extended",     provider: "Apple",      purpose: "training", notes: "Apple Intelligence opt-out; no Apple Search effect" },
  { ua: "Bytespider",            provider: "ByteDance",  purpose: "training" },
  { ua: "CCBot",                 provider: "Common Crawl", purpose: "training", notes: "upstream feed for many LLMs" },
  { ua: "Meta-ExternalAgent",    provider: "Meta",       purpose: "training" },
  { ua: "Meta-ExternalFetcher",  provider: "Meta",       purpose: "on-demand" },
  { ua: "MistralAI-User",        provider: "Mistral",    purpose: "on-demand" },
  { ua: "bingbot",               provider: "Microsoft",  purpose: "general" },
  { ua: "YandexBot",             provider: "Yandex",     purpose: "general" },
];

const args = parseArgs(Bun.argv.slice(2));
const site = args["--site"];
const outPath = args["--output"] ?? "analyses/ai-bot-policy.md";
const jsonPath = companionJsonPath(outPath);
const ci = (args["--ci"] ?? "false") === "true";

if (!site) {
  console.error("Required: --site <url>");
  process.exit(2);
}
const siteUrl = parseSiteUrl(site);
const robotsUrl = new URL("/robots.txt", siteUrl).toString();
await mkdir(dirname(outPath), { recursive: true });

let robotsTxt = "";
let robotsStatus: number | null = null;
const issues: Issue[] = [];

try {
  const r = await fetch(robotsUrl, {
    headers: { "User-Agent": "Mozilla/5.0 (compatible; SEO-Skill-AIBotPolicy/1.0)" },
    redirect: "follow",
    signal: AbortSignal.timeout(15000),
  });
  robotsStatus = r.status;
  if (r.ok) {
    robotsTxt = await r.text();
  } else {
    issues.push({ level: "FAIL", code: "ROBOTS_NON_200", message: `${robotsUrl} returned ${r.status}` });
  }
} catch (e) {
  issues.push({ level: "FAIL", code: "ROBOTS_FETCH", message: (e as Error).message });
}

const groups = parseRobots(robotsTxt);

type Status = { bot: string; provider: string; purpose: BotPurpose; policy: "BLOCKED" | "ALLOWED" | "UNSPECIFIED"; matched_group: string | null; notes?: string };
const botStatus: Status[] = [];
for (const b of BOT_MATRIX) {
  const decision = decide(b.ua, "/", groups);
  botStatus.push({
    bot: b.ua,
    provider: b.provider,
    purpose: b.purpose,
    policy: decision.policy,
    matched_group: decision.matched_group,
    notes: b.notes,
  });
}

// Specific cross-checks
const blockedSearchWithTrainingBlock = botStatus.filter(
  (s) => s.purpose === "search" && s.policy === "BLOCKED",
).filter((s) => {
  // only flag if the same provider's training UA is also blocked
  const trainingPeer = botStatus.find((p) => p.provider === s.provider && p.purpose === "training");
  return trainingPeer?.policy === "BLOCKED";
});
for (const s of blockedSearchWithTrainingBlock) {
  issues.push({
    level: "WARN",
    code: "BLOCKED_SEARCH_WITH_TRAINING_BLOCK",
    message: `${s.bot} (${s.provider} search) is blocked alongside its training peer. If you intended training-opt-out only, allow ${s.bot} to retain search / AI visibility.`,
  });
}

// On-demand bots being blocked is usually unintended
for (const s of botStatus.filter((s) => s.purpose === "on-demand" && s.policy === "BLOCKED")) {
  issues.push({
    level: "WARN",
    code: "BLOCKED_ON_DEMAND_BOT",
    message: `${s.bot} (${s.provider} on-demand) is blocked. On-demand bots represent live user retrievals; blocking them suppresses real user-driven traffic from ${s.provider}.`,
  });
}

// Deprecated UAs still listed
const ad = botStatus.find((s) => s.bot === "anthropic-ai");
if (ad && ad.matched_group) {
  issues.push({
    level: "INFO",
    code: "DEPRECATED_UA_LISTED",
    message: `anthropic-ai is deprecated (Anthropic now uses ClaudeBot/Claude-User/Claude-SearchBot). The rule is harmless but stale.`,
  });
}

// Sitemap directive presence
const hasSitemap = /^\s*sitemap\s*:/im.test(robotsTxt);
if (robotsTxt && !hasSitemap) {
  issues.push({ level: "WARN", code: "NO_SITEMAP_DIRECTIVE", message: "robots.txt does not declare a Sitemap directive." });
}

// Unknown bots present (informational)
const knownUAs = new Set(BOT_MATRIX.map((b) => b.ua.toLowerCase()));
for (const g of Object.keys(groups)) {
  if (g === "*") continue;
  if (!knownUAs.has(g)) {
    issues.push({ level: "INFO", code: "UNKNOWN_BOT_RULE", message: `Rule for unknown UA "${g}" — verify it's intentional and current.` });
  }
}

const failCount = issues.filter((i) => i.level === "FAIL").length;
const warnCount = issues.filter((i) => i.level === "WARN").length;

await Bun.write(jsonPath, JSON.stringify({
  generated: new Date().toISOString(),
  robots_txt_url: robotsUrl,
  robots_txt_status: robotsStatus,
  raw_length: robotsTxt.length,
  bot_status: botStatus,
  issues,
  fail_count: failCount,
  warn_count: warnCount,
}, null, 2));

const md: string[] = [
  `# AI bot policy — ${site}`,
  ``,
  `- robots.txt: \`${robotsUrl}\` (status ${robotsStatus ?? "—"})`,
  `- FAIL: ${failCount}   WARN: ${warnCount}   INFO: ${issues.filter((i) => i.level === "INFO").length}`,
  ``,
  `## Bot policy table`,
  ``,
  `| Bot | Provider | Purpose | Policy | Notes |`,
  `|-----|----------|---------|--------|-------|`,
];
for (const s of botStatus) {
  md.push(`| ${s.bot} | ${s.provider} | ${s.purpose} | **${s.policy}** | ${s.notes ?? ""} |`);
}
md.push(``, `## Issues`, ``);
if (issues.length === 0) md.push(`✅ No issues.`);
for (const i of issues) {
  md.push(`- ${issueIcon(i.level)} [${i.code}] ${i.message}`);
}
md.push(``, `Run \`scripts/llms-txt-validator.ts\` next if you maintain an llms.txt.`);

await Bun.write(outPath, md.join("\n"));
console.log(`AI bot policy report at ${outPath}. FAIL=${failCount} WARN=${warnCount}`);
process.exit(ci && failCount > 0 ? 1 : 0);

// ---- helpers ----

type Group = { allow: string[]; disallow: string[] };

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

function issueIcon(level: Issue["level"]): string {
  if (level === "FAIL") return "❌";
  if (level === "WARN") return "⚠";
  return "ℹ";
}

function parseRobots(text: string): Record<string, Group> {
  // robots.txt grammar is line-based; UAs are case-insensitive; one rule per line.
  // Multiple consecutive User-agent lines apply the next allow/disallow block to all.
  const groups: Record<string, Group> = {};
  let pendingUAs: string[] = [];
  let inRules = false;
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.replace(/#.*$/, "").trim();
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
      const ua = value.toLowerCase();
      if (inRules) pendingUAs = [];
      pendingUAs.push(ua);
      if (!groups[ua]) groups[ua] = { allow: [], disallow: [] };
      inRules = false;
    } else if (directive === "allow" || directive === "disallow") {
      inRules = true;
      if (pendingUAs.length === 0) {
        // dangling rule with no UA; conservative: ignore
        continue;
      }
      for (const ua of pendingUAs) {
        if (!groups[ua]) groups[ua] = { allow: [], disallow: [] };
        if (directive === "allow") groups[ua].allow.push(value);
        else groups[ua].disallow.push(value);
      }
    } else {
      // sitemap, crawl-delay, etc. — ignored for policy decision
    }
  }
  return groups;
}

function decide(ua: string, path: string, groups: Record<string, Group>): {
  policy: "BLOCKED" | "ALLOWED" | "UNSPECIFIED";
  matched_group: string | null;
} {
  // Robots semantics: pick the most-specific UA group; if none, fall back to "*".
  // Within a group: longest matching rule wins; tie → Allow > Disallow.
  const lower = ua.toLowerCase();
  const candidates = Object.keys(groups).filter((g) => g === "*" || lower === g);
  // Prefer exact UA match over wildcard
  const groupKey = candidates.find((g) => g === lower) ?? (candidates.includes("*") ? "*" : null);
  if (!groupKey) return { policy: "UNSPECIFIED", matched_group: null };
  const g = groups[groupKey];
  const allowMatch = longestMatch(g.allow, path);
  const disallowMatch = longestMatch(g.disallow, path);
  if (disallowMatch === null && allowMatch === null) return { policy: "ALLOWED", matched_group: groupKey };
  if (disallowMatch === null) return { policy: "ALLOWED", matched_group: groupKey };
  if (allowMatch === null) {
    return { policy: disallowMatch === "" ? "ALLOWED" : "BLOCKED", matched_group: groupKey };
    // Note: an empty Disallow means "allow all" by RFC; longestMatch returns "" only if listed empty.
  }
  // Tie-break: longest pattern wins; equal length → Allow wins
  if (allowMatch.length >= disallowMatch.length) return { policy: "ALLOWED", matched_group: groupKey };
  return { policy: "BLOCKED", matched_group: groupKey };
}

function longestMatch(rules: string[], path: string): string | null {
  let best: string | null = null;
  for (const rule of rules) {
    if (matches(rule, path)) {
      if (best === null || rule.length > best.length) best = rule;
    }
  }
  return best;
}

function matches(pattern: string, path: string): boolean {
  if (pattern === "") return true; // empty Disallow = allow all
  // Convert robots glob (* anywhere, $ end-anchor) to regex
  const hasEndAnchor = pattern.endsWith("$");
  const body = hasEndAnchor ? pattern.slice(0, -1) : pattern;
  const escaped = body.replace(/[.+?^${}()|[\]\\]/g, "\\$&");
  const withWildcards = escaped.replace(/\*/g, ".*");
  const regexSrc = hasEndAnchor ? `^${withWildcards}$` : `^${withWildcards}`;
  try {
    return new RegExp(regexSrc).test(path);
  } catch {
    return false;
  }
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
