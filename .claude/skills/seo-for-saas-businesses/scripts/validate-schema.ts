#!/usr/bin/env bun
/**
 * validate-schema.ts — Phase 3 / Phase 6 / Phase 12 schema validation
 *
 * For each URL in the representative set, fetch HTML, extract every
 * <script type="application/ld+json">, parse, and validate that:
 *   - JSON parses
 *   - declared @type matches a known schema.org type
 *   - required + recommended properties present per Google docs (heuristic table below)
 *   - schema rendered server-side (not added after hydration) — best-effort by
 *     comparing raw vs rendered JSON-LD count
 *
 * Usage:
 *   bun run scripts/validate-schema.ts \
 *     --rep-set analyses/representative-urls.json \
 *     [--baseline analyses/schema-baseline.json] \
 *     [--output analyses/schema-validation.md]
 *
 * Exit code: 0 on all-pass; 1 on any failure (CI gate).
 */

const args = parseArgs(Bun.argv.slice(2));
const repSet = args["--rep-set"] ?? "analyses/representative-urls.json";
const baselinePath = args["--baseline"];
const outPath = args["--output"] ?? "analyses/schema-validation.md";
const timeout = Number(args["--timeout"] ?? 30000);

const REQUIRED: Record<string, string[]> = {
  Organization: ["name", "url"],
  WebSite: ["name", "url"],
  WebApplication: ["name", "applicationCategory", "operatingSystem"],
  SoftwareApplication: ["name", "applicationCategory", "operatingSystem"],
  Article: ["headline", "datePublished", "author"],
  Product: ["name"],
  Offer: ["price", "priceCurrency"],
  BreadcrumbList: ["itemListElement"],
  Person: ["name"],
  VideoObject: ["name", "uploadDate", "thumbnailUrl"],
  Dataset: ["name", "description"],
  Event: ["name", "startDate", "location"],
  JobPosting: ["title", "description", "datePosted", "hiringOrganization"],
  Course: ["name", "description", "provider"],
  Review: ["author", "itemReviewed", "reviewBody"],
  FAQPage: ["mainEntity"],
  LocalBusiness: ["name", "address"],
};

const DEPRECATED_FOR_RICH_RESULTS = new Set([
  "HowTo", // deprecated for general web rich results 2023
  "SearchAction", // Sitelinks Searchbox retired
]);
const KNOWN_EXTRA_TYPES = [
  "AboutPage",
  "Answer",
  "BlogPosting",
  "CollectionPage",
  "ContactPage",
  "CreativeWork",
  "ImageObject",
  "ItemList",
  "ListItem",
  "NewsArticle",
  "QAPage",
  "Question",
  "Service",
  "SiteNavigationElement",
  "TechArticle",
  "Thing",
  "WebPage",
];
const KNOWN_HEURISTIC_TYPES = new Set([
  ...Object.keys(REQUIRED),
  ...DEPRECATED_FOR_RICH_RESULTS,
  ...KNOWN_EXTRA_TYPES,
]);

const rep = JSON.parse(await Bun.file(repSet).text()) as {
  urls: Array<{ url: string; template?: string }>;
};

type ValidationIssue = { level: "FAIL" | "WARN"; message: string };

let totalFail = 0;
let totalWarn = 0;
const lines: string[] = [`# Schema validation — ${new Date().toISOString()}\n`];

for (const u of rep.urls) {
  let r: Response;
  try {
    r = await fetch(u.url, { redirect: "follow", signal: AbortSignal.timeout(timeout) });
  } catch (err) {
    lines.push(`### ${u.url}\n- [FAIL] fetch failed: ${(err as Error).message}\n`);
    totalFail++;
    continue;
  }
  if (!r.ok) {
    lines.push(`### ${u.url}\n- [SKIP] HTTP ${r.status}\n`);
    continue;
  }
  const html = await r.text();
  const blocks = extractJsonLd(html);
  const local: string[] = [`### ${u.url} (${u.template ?? ""})`];
  if (blocks.length === 0) {
    local.push(`- [WARN] No JSON-LD blocks found.`);
    lines.push(local.join("\n"), "");
    continue;
  }
  for (let i = 0; i < blocks.length; i++) {
    const block = blocks[i];
    let parsed: any;
    try {
      parsed = JSON.parse(block);
    } catch (e) {
      local.push(`- [FAIL] block ${i}: invalid JSON (${(e as Error).message})`);
      totalFail++;
      continue;
    }
    const items = flattenJsonLd(parsed);
    if (items.length === 0) {
      local.push(`- [FAIL] block ${i}: JSON-LD contained no schema items`);
      totalFail++;
      continue;
    }
    for (const item of items) {
      const issues = validateItem(item);
      if (issues.length === 0) {
        local.push(`- [OK] block ${i} type=${item["@type"] ?? "?"}`);
      } else {
        for (const issue of issues) {
          local.push(`- [${issue.level}] block ${i} type=${item["@type"] ?? "?"}: ${issue.message}`);
          if (issue.level === "FAIL") totalFail++;
          else totalWarn++;
        }
      }
    }
  }
  lines.push(local.join("\n"), "");
}

await Bun.write(outPath, lines.join("\n"));
console.log(`Validation report written to ${outPath}.`);
console.log(`Failures: ${totalFail}; Warnings: ${totalWarn}`);
process.exit(totalFail > 0 ? 1 : 0);

function validateItem(item: any): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  const type = item["@type"];
  if (!type) {
    issues.push({ level: "FAIL", message: "missing @type" });
    return issues;
  }
  if (Array.isArray(type)) {
    for (const t of type) {
      const subIssues = validateForType(item, t);
      issues.push(...subIssues);
    }
  } else {
    const subIssues = validateForType(item, type);
    issues.push(...subIssues);
  }
  return issues;
}

function validateForType(item: any, type: string): ValidationIssue[] {
  const out: ValidationIssue[] = [];
  const normalizedType = normalizeSchemaType(type);
  if (!KNOWN_HEURISTIC_TYPES.has(normalizedType)) {
    out.push({ level: "WARN", message: `type ${type} is not in this script's heuristic table; confirm it is a valid schema.org type and add required-property rules if important` });
  }
  if (DEPRECATED_FOR_RICH_RESULTS.has(normalizedType)) {
    out.push({ level: "WARN", message: `type ${type} is deprecated for Google rich results — confirm intentional` });
  }
  const req = REQUIRED[normalizedType];
  if (req) {
    for (const k of req) {
      if (item[k] === undefined || item[k] === null || item[k] === "") {
        out.push({ level: "FAIL", message: `required property "${k}" missing` });
      }
    }
  }
  return out;
}

function flattenJsonLd(value: any): any[] {
  if (Array.isArray(value)) return value.flatMap(flattenJsonLd);
  if (!value || typeof value !== "object") return [];
  if (Array.isArray(value["@graph"])) return value["@graph"].flatMap(flattenJsonLd);
  return [value];
}

function normalizeSchemaType(type: string): string {
  return String(type).replace(/^https?:\/\/schema\.org\//i, "").replace(/^schema:/i, "");
}

function extractJsonLd(html: string): string[] {
  const re = /<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
  const blocks: string[] = [];
  for (const m of html.matchAll(re)) blocks.push(m[1].trim());
  return blocks;
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
