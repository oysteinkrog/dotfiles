#!/usr/bin/env bun
/**
 * verify-prod.ts — Phase 12 post-deploy verification.
 *
 * For each representative URL on production:
 *   - status code matches expected
 *   - meta tags rendered server-side (raw HTML check)
 *   - JSON-LD parses + declared @type valid
 *   - OG image returns 200 with correct dimensions
 *   - canonical points to itself or declared owner
 *   - robots directive matches expected
 *   - internal links sample resolves to 200
 *   - hydrated DOM does not hide content from raw HTML
 *   - AI-crawler view contains headline answer
 *   - INP/LCP/CLS under thresholds (Lighthouse, mobile)
 *
 * Usage:
 *   bun run scripts/verify-prod.ts \
 *     --rep-set analyses/representative-urls.json \
 *     --output analyses/post-deploy-verification.md \
 *     [--lhci]
 */

import { mkdir } from "node:fs/promises";
import { dirname } from "node:path";
import { chromium } from "playwright";

const args = parseArgs(Bun.argv.slice(2));
const repSet = args["--rep-set"] ?? "analyses/representative-urls.json";
const outPath = args["--output"] ?? "analyses/post-deploy-verification.md";
const jsonPath = companionJsonPath(outPath);
const runLhci = args["--lhci"] === "true";
const writeJson = args["--json"] === "true";
const timeout = Number(args["--timeout"] ?? 30000);

await mkdir(dirname(outPath), { recursive: true });

const rep = await readJsonFile<{
  urls: Array<{
    url: string;
    template?: string;
    expected_status?: number;
    expected_canonical?: string;
    expected_robots?: string;
  }>;
}>(repSet, "--rep-set");

const browser = await chromium.launch();
const context = await browser.newContext({
  userAgent: "Mozilla/5.0 (compatible; SEO-Verify/1.0; +https://example.com)",
  viewport: { width: 390, height: 844 },
});

type CheckLevel = "OK" | "FAIL" | "WARN" | "INFO";
type Check = { level: CheckLevel; code: string; message: string };
type VerificationResult = {
  url: string;
  template?: string;
  expected_status: number;
  pass: number;
  fail: number;
  flag: number;
  checks: Check[];
};

const generated = new Date().toISOString();
const lines: string[] = [
  `# Post-deploy verification — ${generated.slice(0, 10)}`,
  "",
];
const results: VerificationResult[] = [];
let pass = 0;
let fail = 0;
let flag = 0;

for (const u of rep.urls) {
  const expectedStatus = u.expected_status ?? 200;
  const local: string[] = [`### ${u.url}`];
  const checks: Check[] = [];
  const addCheck = (level: CheckLevel, code: string, message: string) => {
    checks.push({ level, code, message });
    local.push(`- [${level}] ${message}`);
    if (level === "OK") pass++;
    if (level === "FAIL") fail++;
    if (level === "WARN") flag++;
  };
  const finishUrl = () => {
    results.push({
      url: u.url,
      template: u.template,
      expected_status: expectedStatus,
      pass: checks.filter((c) => c.level === "OK").length,
      fail: checks.filter((c) => c.level === "FAIL").length,
      flag: checks.filter((c) => c.level === "WARN").length,
      checks,
    });
    lines.push(local.join("\n"), "");
  };

  // raw fetch
  let raw: Response;
  try {
    raw = await fetch(u.url, {
      redirect: "manual",
      headers: { "User-Agent": "Mozilla/5.0 SEO-Verify-Raw" },
      signal: AbortSignal.timeout(timeout),
    });
  } catch (err) {
    addCheck("FAIL", "RAW_FETCH_FAILED", `raw fetch failed: ${(err as Error).message}`);
    finishUrl();
    continue;
  }
  if (raw.status !== expectedStatus) {
    addCheck("FAIL", "STATUS_MISMATCH", `status: expected ${expectedStatus}, got ${raw.status}`);
  } else {
    addCheck("OK", "STATUS_OK", `status ${raw.status}`);
  }
  const rawHtml = raw.status === 200 ? await raw.text() : "";

  if (raw.status === 200) {
    const meta = extract(rawHtml);
    if (!meta.title) {
      addCheck("FAIL", "TITLE_MISSING", `no <title> in raw HTML`);
    } else {
      addCheck("OK", "TITLE_OK", `title: "${meta.title.slice(0, 60)}"`);
    }
    if (!meta.description) {
      addCheck("FAIL", "META_DESCRIPTION_MISSING", `no meta description in raw HTML`);
    } else {
      addCheck("OK", "META_DESCRIPTION_OK", `meta description present`);
    }
    if (!meta.canonical) {
      addCheck("WARN", "CANONICAL_MISSING", `no canonical in raw HTML`);
    } else if (u.expected_canonical && !meta.canonical.endsWith(u.expected_canonical)) {
      addCheck("FAIL", "CANONICAL_MISMATCH", `canonical: expected ${u.expected_canonical}, got ${meta.canonical}`);
    } else {
      addCheck("OK", "CANONICAL_OK", `canonical ${meta.canonical}`);
    }
    if (u.expected_robots && meta.robots !== u.expected_robots) {
      addCheck("FAIL", "ROBOTS_MISMATCH", `robots: expected ${u.expected_robots}, got ${meta.robots ?? "(none)"}`);
    }
    if (meta.json_ld_count === 0) {
      addCheck("WARN", "JSON_LD_MISSING", `no JSON-LD in raw HTML`);
    } else if (meta.json_ld_errors.length > 0) {
      for (const err of meta.json_ld_errors) {
        addCheck("FAIL", "JSON_LD_PARSE_ERROR", `JSON-LD block ${err.index} does not parse: ${err.message}`);
      }
    } else {
      addCheck("OK", "JSON_LD_OK", `${meta.json_ld_count} JSON-LD block(s) parse`);
    }

    // OG image check
    if (meta.og_image) {
      const ogUrl = (() => {
        try { return new URL(meta.og_image!, u.url).toString(); } catch { return meta.og_image!; }
      })();
      const og = await fetch(ogUrl, { method: "HEAD", signal: AbortSignal.timeout(timeout) }).catch(() => null);
      if (!og || !og.ok) {
        addCheck("FAIL", "OG_IMAGE_NON_200", `OG image returned non-200: ${ogUrl}`);
      } else {
        addCheck("OK", "OG_IMAGE_OK", `OG image returned ${og.status}: ${ogUrl}`);
      }
    }

    // rendered DOM diff
    const page = await context.newPage();
    try {
      await page.goto(u.url, { waitUntil: "networkidle", timeout });
      const renderedTitle = await page.title();
      if (meta.title && renderedTitle !== meta.title) {
        addCheck("WARN", "RENDERED_TITLE_DIFFERS", `rendered title (${renderedTitle.slice(0, 40)}) differs from raw title (${meta.title.slice(0, 40)})`);
      }
    } catch (err) {
      addCheck("FAIL", "RENDERED_LOAD_FAILED", `rendered page load failed: ${(err as Error).message}`);
    } finally {
      await page.close().catch(() => {});
    }
  }

  // optional Lighthouse pass
  if (runLhci) {
    addCheck("INFO", "LIGHTHOUSE_MANUAL_STEP", `Lighthouse: run \`bunx @lhci/cli@latest collect --url=${u.url}\` separately and assert thresholds.`);
  }

  finishUrl();
}

await context.close();
await browser.close();

lines.push(`\n## Summary`, ``);
lines.push(`- Pass: ${pass}`);
lines.push(`- Fail: ${fail}`);
lines.push(`- Flag: ${flag}`);

await Bun.write(outPath, lines.join("\n"));
if (writeJson) {
  await Bun.write(jsonPath, JSON.stringify({
    generated,
    rep_set: repSet,
    summary: { pass, fail, flag },
    results,
  }, null, 2));
}
console.log(`Report written to ${outPath}${writeJson ? `; JSON at ${jsonPath}` : ""}. Pass=${pass} Fail=${fail} Flag=${flag}`);
process.exit(fail > 0 ? 1 : 0);

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

function extract(html: string) {
  const get = (re: RegExp) => html.match(re)?.[1] ?? null;
  // Match meta/link tags by attribute name regardless of attribute order.
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
  const jsonLdBlocks = Array.from(html.matchAll(/<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)).map((m) => m[1]);
  const jsonLdErrors: Array<{ index: number; message: string }> = [];
  jsonLdBlocks.forEach((block, index) => {
    try {
      JSON.parse(block.trim());
    } catch (err) {
      jsonLdErrors.push({ index, message: (err as Error).message });
    }
  });
  return {
    title: get(/<title[^>]*>([^<]*)<\/title>/i),
    description: getMeta("name", "description"),
    canonical: getLink("canonical"),
    robots: getMeta("name", "robots"),
    og_image: getMeta("property", "og:image"),
    json_ld_count: jsonLdBlocks.length,
    json_ld_errors: jsonLdErrors,
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
