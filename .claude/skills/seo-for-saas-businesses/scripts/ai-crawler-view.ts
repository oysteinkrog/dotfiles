#!/usr/bin/env bun
/**
 * ai-crawler-view.ts — fetch as AI/search crawler and snapshot initial HTML.
 *
 * Many AI/search crawler retrieval paths are HTML-first or HTML-only even when
 * a later rendering system exists. This script confirms that citation-eligible
 * content (headline answer + 3+ unique data points) is present in raw HTML for
 * each priority URL.
 *
 * Usage:
 *   bun run scripts/ai-crawler-view.ts \
 *     --url https://www.example.com/security \
 *     --as GPTBot|OAI-SearchBot|ChatGPT-User|Claude-SearchBot|Claude-User|PerplexityBot|all \
 *     [--output analyses/ai-crawler/]
 *
 *   bun run scripts/ai-crawler-view.ts \
 *     --rep-set analyses/representative-urls.json \
 *     --as all
 */

import { mkdir } from "node:fs/promises";
import { join } from "node:path";

const UAS: Record<string, string> = {
  GPTBot: "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko); compatible; GPTBot/1.0; +https://openai.com/gptbot",
  "OAI-SearchBot": "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko); compatible; OAI-SearchBot/1.0; +https://openai.com/searchbot",
  "ChatGPT-User": "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko); compatible; ChatGPT-User/1.0; +https://openai.com/bot",
  ClaudeBot: "Mozilla/5.0 (compatible; ClaudeBot/1.0; +claudebot@anthropic.com)",
  "Claude-SearchBot": "Claude-SearchBot",
  "Claude-User": "Claude-User",
  "anthropic-ai": "anthropic-ai",
  PerplexityBot: "Mozilla/5.0 (compatible; PerplexityBot/1.0; +https://perplexity.ai/perplexitybot)",
  "Perplexity-User": "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; Perplexity-User/1.0; +https://perplexity.ai/perplexity-user)",
  Googlebot: "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
};

type RepresentativeUrl = { url?: string };
type RepresentativeUrlSet = { urls?: unknown[] };

const args = parseArgs(Bun.argv.slice(2));
const single = args["--url"];
const repSet = args["--rep-set"];
const asArg = args["--as"] ?? "all";
const outDir = args["--output"] ?? "analyses/ai-crawler/";

const bots = asArg === "all" ? Object.keys(UAS) : asArg.split(",").map((s) => s.trim()).filter(Boolean);
const unknownBots = bots.filter((bot) => !UAS[bot]);
if (bots.length === 0 || unknownBots.length > 0) {
  console.error(`Unknown bot(s): ${unknownBots.join(", ") || "(none provided)"}`);
  console.error(`Known bots: ${Object.keys(UAS).join(", ")}`);
  process.exit(2);
}

const urls: string[] = [];
if (single) {
  try {
    addUrl(urls, single, "--url");
  } catch (err) {
    console.error((err as Error).message);
    process.exit(2);
  }
}
if (repSet) {
  try {
    const r = JSON.parse(await Bun.file(repSet).text()) as RepresentativeUrlSet;
    if (!Array.isArray(r.urls)) throw new Error("missing urls[] array");
    for (const entry of r.urls) {
      const url = representativeUrl(entry);
      if (url) addUrl(urls, url, repSet);
    }
  } catch (err) {
    console.error(`Failed to read representative URL set ${repSet}: ${(err as Error).message}`);
    process.exit(2);
  }
}
if (urls.length === 0) {
  console.error("Provide --url <u> or --rep-set <path>");
  process.exit(2);
}

await mkdir(outDir, { recursive: true });

type ReportRow = {
  url: string;
  bot: string;
  status: number;
  path: string;
  has_title: boolean;
  has_meta_description: boolean;
  h1_count: number;
  h2_count: number;
  json_ld_count: number;
  text_length: number;
  contains_loading: boolean;
  contains_javascript_required: boolean;
  error?: string;
};

const report: ReportRow[] = [];
for (const url of urls) {
  for (const bot of bots) {
    const ua = UAS[bot];
    if (!ua) {
      console.error(`Unknown bot: ${bot}`);
      continue;
    }
    try {
      const r = await fetch(url, {
        redirect: "follow",
        headers: { "User-Agent": ua, Accept: "text/html" },
        signal: AbortSignal.timeout(30000),
      });
      const html = await r.text();
      const stats = analyze(html);
      const path = join(outDir, `${slug(url)}__${bot}.html`);
      await Bun.write(path, html);
      report.push({
        url,
        bot,
        status: r.status,
        path,
        ...stats,
      });
      const ok = stats.has_title && stats.h1_count >= 1 && stats.text_length > 500;
      console.log(`${ok ? "✓" : "✗"} ${url} as ${bot} status=${r.status} text=${stats.text_length}b ld=${stats.json_ld_count}`);
    } catch (e) {
      const message = (e as Error).message;
      report.push({
        url,
        bot,
        status: 0,
        path: "",
        has_title: false,
        has_meta_description: false,
        h1_count: 0,
        h2_count: 0,
        json_ld_count: 0,
        text_length: 0,
        contains_loading: false,
        contains_javascript_required: false,
        error: message,
      });
      console.log(`✗ ${url} as ${bot} — ${message}`);
    }
  }
}

await Bun.write(join(outDir, "_report.json"), JSON.stringify({
  generated: new Date().toISOString(),
  report,
}, null, 2));

function analyze(html: string) {
  const extractableHtml = stripNonContentElements(html);
  const text = extractableHtml.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
  return {
    has_title: /<title[^>]*>[^<]+<\/title>/i.test(html),
    has_meta_description: hasMetaDescription(html),
    h1_count: (html.match(/<h1\b/gi) ?? []).length,
    h2_count: (html.match(/<h2\b/gi) ?? []).length,
    json_ld_count: (html.match(/<script[^>]*type=["']application\/ld\+json["']/gi) ?? []).length,
    text_length: text.length,
    contains_loading: /loading\.{3}|skeleton/i.test(text.slice(0, 2000)),
    contains_javascript_required: /requires javascript|enable javascript/i.test(text.slice(0, 2000)),
  };
}

function stripNonContentElements(html: string): string {
  return html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<template\b[^>]*>[\s\S]*?<\/template>/gi, " ");
}

function hasMetaDescription(html: string): boolean {
  const re = /<meta\s+([^>]+?)\/?>/gi;
  for (const m of html.matchAll(re)) {
    const attrs = m[1];
    if (!/\bname\s*=\s*["']description["']/i.test(attrs)) continue;
    // Don't return on the first match if its content is empty — a later
    // <meta name="description"> with real content still counts as present.
    if (attrs.match(/\bcontent\s*=\s*["']([^"']*)["']/i)?.[1]?.trim()) return true;
  }
  return false;
}

function representativeUrl(entry: unknown): string | null {
  if (!entry || typeof entry !== "object" || !("url" in entry)) return null;
  const url = (entry as RepresentativeUrl).url;
  return typeof url === "string" && url ? url : null;
}

function addUrl(out: string[], value: string, source: string): void {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error(`invalid URL in ${source}: ${value}`);
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error(`invalid URL scheme in ${source}: ${value} (expected http or https)`);
  }
  out.push(url.toString());
}

function slug(url: string): string {
  return url.replace(/^https?:\/\//, "").replace(/[^\w]+/g, "_").slice(0, 80);
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
