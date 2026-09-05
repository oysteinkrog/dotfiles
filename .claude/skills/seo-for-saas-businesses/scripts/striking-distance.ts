#!/usr/bin/env bun
/**
 * striking-distance.ts — Identify and prioritize "striking distance" pages.
 *
 * Reads analyses/gsc/performance.csv (output of gsc-extract.ts) and:
 *   - Filters page+query rows to avg position 4-15 with impressions ≥ N
 *     (default 100/day × period; configurable)
 *   - Aggregates per page (weighted by impressions)
 *   - Computes potential lift = impressions × (CTR_at_position_3 - current_CTR),
 *     where CTR_at_position_3 uses a configurable curve. Default uses the
 *     2024 advancedwebranking.com aggregate curve clipped to non-branded.
 *   - Flags CTR < 60% of expected for current avg position (likely meta/title
 *     under-performance vs SERP slot)
 *   - Joins with analyses/content-inventory.md (if present) for owner/intent
 *   - Suggests recommended_action heuristically:
 *       * very low CTR for slot → title rewrite
 *       * decent CTR but title generic → meta rewrite
 *       * impressions ≥ 200 and pos 6-12 → internal link from authoritative pages
 *       * pages tagged comparison/review intent → add proof
 *       * pages with FAQPage candidates but no schema → schema fix
 *
 * Outputs:
 *   - analyses/striking-distance.md   — ranked table of opportunities
 *   - analyses/striking-distance.json — structured per-page rows
 *
 * Usage:
 *   bun run scripts/striking-distance.ts \
 *     [--gsc analyses/gsc/performance.csv] \
 *     [--inventory analyses/content-inventory.md] \
 *     [--output analyses/striking-distance.md] \
 *     [--min-position 4] [--max-position 15] \
 *     [--min-impressions 100] [--days 28] \
 *     [--ctr-curve nonbranded|branded|custom:0.30,0.15,0.10,...]
 *
 * Exit codes: 0 always (pure reporter); 2 missing inputs.
 */

import { mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname } from "node:path";

const args = parseArgs(Bun.argv.slice(2));
const gscPath = args["--gsc"] ?? "analyses/gsc/performance.csv";
const invPath = args["--inventory"] ?? "analyses/content-inventory.md";
const outPath = args["--output"] ?? "analyses/striking-distance.md";
const jsonPath = companionJsonPath(outPath);
const minPos = Number(args["--min-position"] ?? 4);
const maxPos = Number(args["--max-position"] ?? 15);
const minImp = Number(args["--min-impressions"] ?? 100);
const days = Number(args["--days"] ?? 28);
const curveArg = args["--ctr-curve"] ?? "nonbranded";

if (!existsSync(gscPath)) {
  console.error(`GSC performance CSV not found at ${gscPath}. Run gsc-extract.ts first.`);
  process.exit(2);
}

await mkdir(dirname(outPath), { recursive: true });

// ---- CTR curves (position 1..20) ----
const CURVES: Record<string, number[]> = {
  // AdvancedWebRanking 2024-aggregate (non-branded informational)
  nonbranded: [
    0.275, 0.155, 0.10, 0.073, 0.054, 0.041, 0.033, 0.028, 0.024, 0.022,
    0.018, 0.016, 0.014, 0.013, 0.012, 0.011, 0.010, 0.009, 0.008, 0.007,
  ],
  // Aggregated branded CTR (much higher in slot 1)
  branded: [
    0.55, 0.18, 0.10, 0.06, 0.04, 0.03, 0.025, 0.02, 0.018, 0.015,
    0.013, 0.011, 0.010, 0.009, 0.008, 0.007, 0.006, 0.005, 0.004, 0.003,
  ],
};

let curve: number[] = CURVES[curveArg];
if (!curve && curveArg.startsWith("custom:")) {
  curve = curveArg.slice(7).split(",").map(Number);
}
if (!curve) {
  console.error(`Unknown --ctr-curve "${curveArg}". Use nonbranded|branded|custom:c1,c2,...`);
  process.exit(2);
}

// ---- read GSC CSV ----
const csv = await Bun.file(gscPath).text();
const lines = csv.trim().split("\n");
const header = lines[0].split(",");
const colIdx = (n: string) => header.indexOf(n);
const PAGE = colIdx("page");
const QUERY = colIdx("query");
const CLICKS = colIdx("clicks");
const IMP = colIdx("impressions");
const CTR = colIdx("ctr");
const POS = colIdx("position");
if (PAGE < 0 || IMP < 0 || POS < 0) {
  console.error(`GSC CSV header missing expected columns; got: ${header.join(",")}`);
  process.exit(2);
}

type Row = { page: string; query: string; clicks: number; impressions: number; ctr: number; position: number };
const rows: Row[] = [];
for (let i = 1; i < lines.length; i++) {
  const parts = parseCsvLine(lines[i]);
  if (parts.length < header.length) continue;
  const r: Row = {
    page: parts[PAGE],
    query: parts[QUERY],
    clicks: Number(parts[CLICKS] ?? 0),
    impressions: Number(parts[IMP] ?? 0),
    ctr: Number(parts[CTR] ?? 0),
    position: Number(parts[POS] ?? 0),
  };
  if (Number.isFinite(r.position)) rows.push(r);
}

// ---- aggregate per page ----
type PageAgg = {
  page: string;
  clicks: number;
  impressions: number;
  ctr: number;
  position: number;
  top_queries: Array<{ query: string; impressions: number; clicks: number; position: number }>;
};
const byPage = new Map<string, PageAgg>();
for (const r of rows) {
  const e = byPage.get(r.page) ?? {
    page: r.page,
    clicks: 0,
    impressions: 0,
    ctr: 0,
    position: 0,
    top_queries: [],
  };
  e.clicks += r.clicks;
  e.impressions += r.impressions;
  // weighted-by-impressions average position
  const w = e.impressions - r.impressions; // prior weight
  e.position = (e.position * w + r.position * r.impressions) / Math.max(e.impressions, 1);
  e.top_queries.push({ query: r.query, impressions: r.impressions, clicks: r.clicks, position: r.position });
  byPage.set(r.page, e);
}
for (const e of byPage.values()) {
  e.ctr = e.clicks / Math.max(e.impressions, 1);
  e.top_queries = e.top_queries.sort((a, b) => b.impressions - a.impressions).slice(0, 5);
}

// ---- threshold (impressions/day × period) ----
const impThreshold = minImp * Math.max(days, 1);

// ---- inventory join ----
const inventory = await loadInventory(invPath);

// ---- rank striking-distance candidates ----
type Out = {
  page: string;
  avg_position: number;
  impressions: number;
  clicks: number;
  ctr: number;
  expected_ctr: number;
  ctr_ratio: number;
  potential_lift_clicks: number;
  owner: string | null;
  intent: string | null;
  template: string | null;
  recommended_action: string;
  rationale: string;
  top_queries: PageAgg["top_queries"];
};

const candidates: Out[] = [];
for (const a of byPage.values()) {
  if (a.position < minPos || a.position > maxPos) continue;
  if (a.impressions < impThreshold) continue;

  const expected = expectedCtrAt(a.position, curve);
  const expectedAt3 = expectedCtrAt(3, curve);
  const ratio = expected > 0 ? a.ctr / expected : 0;
  const lift = Math.max(0, Math.round(a.impressions * (expectedAt3 - a.ctr)));

  const inv = inventory.get(a.page) ?? inventory.get(stripTrailingSlash(a.page)) ?? null;
  const intent = inv?.intent ?? null;
  const template = inv?.template ?? null;
  const owner = inv?.owner ?? null;

  const { action, rationale } = recommend({
    position: a.position,
    impressions: a.impressions,
    ctr: a.ctr,
    ratio,
    intent,
    template,
    top_queries: a.top_queries,
  });

  candidates.push({
    page: a.page,
    avg_position: round(a.position, 2),
    impressions: a.impressions,
    clicks: a.clicks,
    ctr: round(a.ctr, 4),
    expected_ctr: round(expected, 4),
    ctr_ratio: round(ratio, 2),
    potential_lift_clicks: lift,
    owner,
    intent,
    template,
    recommended_action: action,
    rationale,
    top_queries: a.top_queries,
  });
}
candidates.sort((a, b) => b.potential_lift_clicks - a.potential_lift_clicks);

const buckets = bucketCandidates(candidates);

await Bun.write(jsonPath, JSON.stringify({
  generated: new Date().toISOString(),
  inputs: { gscPath, invPath, curveArg, minPos, maxPos, impThreshold, days },
  count: candidates.length,
  buckets,
  candidates,
}, null, 2));

// ---- markdown ----
const md: string[] = [
  `# Striking distance — ${new Date().toISOString()}`,
  ``,
  `Inputs: GSC=${gscPath} · inventory=${existsSync(invPath) ? invPath : "(none)"}`,
  `Filters: position ${minPos}–${maxPos}, impressions ≥ ${impThreshold} (${minImp}/day × ${days} days)`,
  `CTR curve: ${curveArg}`,
  ``,
  `## Top opportunities (ranked by potential lift)`,
  ``,
  `| # | Page | Pos | Imp | Clicks | CTR | Exp.CTR | Ratio | Lift | Action |`,
  `|--:|------|----:|----:|-------:|----:|--------:|------:|-----:|--------|`,
  ...candidates.slice(0, 50).map((c, i) =>
    `| ${i + 1} | ${c.page} | ${c.avg_position} | ${c.impressions} | ${c.clicks} | ${(c.ctr * 100).toFixed(1)}% | ${(c.expected_ctr * 100).toFixed(1)}% | ${c.ctr_ratio} | +${c.potential_lift_clicks} | ${c.recommended_action} |`,
  ),
  ``,
  `## Detail`,
  ``,
];
for (const c of candidates.slice(0, 100)) {
  md.push(`### ${c.page}`);
  md.push(`- pos ${c.avg_position} · ${c.impressions} imp · ${c.clicks} clicks · CTR ${(c.ctr * 100).toFixed(2)}% (expected ${(c.expected_ctr * 100).toFixed(2)}%)`);
  md.push(`- potential lift: **+${c.potential_lift_clicks} clicks**`);
  md.push(`- owner: ${c.owner ?? "—"} · intent: ${c.intent ?? "—"} · template: ${c.template ?? "—"}`);
  md.push(`- recommended_action: **${c.recommended_action}**`);
  md.push(`  - ${c.rationale}`);
  md.push(`- top queries:`);
  for (const q of c.top_queries) md.push(`  - "${q.query}" — pos ${q.position.toFixed(1)}, ${q.impressions} imp, ${q.clicks} clicks`);
  md.push(``);
}

await Bun.write(outPath, md.join("\n"));
console.log(`Striking-distance report at ${outPath}. Candidates: ${candidates.length}`);
process.exit(0);

// ---- helpers ----

function companionJsonPath(path: string): string {
  return path.endsWith(".md") ? `${path.slice(0, -3)}.json` : `${path}.json`;
}

function bucketCandidates(candidates: Out[]) {
  const buckets: Record<string, Array<{
    url: string;
    query: string;
    clicks: number;
    impressions: number;
    position: number;
    expected_ctr: number;
    potential_clicks_lift: number;
    recommendation: string;
  }>> = {
    rank_2_3: [],
    rank_4_10: [],
    rank_11_20: [],
    rank_21_30: [],
    rank_31_50: [],
  };
  for (const c of candidates) {
    const bucket = rankBucket(c.avg_position);
    if (!bucket) continue;
    const topQuery = c.top_queries[0]?.query ?? "";
    buckets[bucket].push({
      url: c.page,
      query: topQuery,
      clicks: c.clicks,
      impressions: c.impressions,
      position: c.avg_position,
      expected_ctr: c.expected_ctr,
      potential_clicks_lift: c.potential_lift_clicks,
      recommendation: c.recommended_action,
    });
  }
  for (const values of Object.values(buckets)) {
    values.sort((a, b) => b.potential_clicks_lift - a.potential_clicks_lift);
  }
  return buckets;
}

function rankBucket(position: number): string | null {
  if (position >= 2 && position < 4) return "rank_2_3";
  if (position >= 4 && position <= 10) return "rank_4_10";
  if (position >= 11 && position <= 20) return "rank_11_20";
  if (position >= 21 && position <= 30) return "rank_21_30";
  if (position >= 31 && position <= 50) return "rank_31_50";
  return null;
}

function parseCsvLine(line: string): string[] {
  const out: string[] = [];
  let cur = "";
  let inQ = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (inQ) {
      if (c === '"' && line[i + 1] === '"') { cur += '"'; i++; }
      else if (c === '"') inQ = false;
      else cur += c;
    } else {
      if (c === '"') inQ = true;
      else if (c === ",") { out.push(cur); cur = ""; }
      else cur += c;
    }
  }
  out.push(cur);
  return out;
}

function expectedCtrAt(pos: number, curve: number[]): number {
  if (pos <= 1) return curve[0];
  if (pos >= curve.length) return curve[curve.length - 1];
  const lo = Math.floor(pos) - 1;
  const hi = Math.ceil(pos) - 1;
  if (lo === hi) return curve[lo];
  const frac = pos - Math.floor(pos);
  return curve[lo] * (1 - frac) + curve[hi] * frac;
}

function round(n: number, d: number) {
  const m = 10 ** d;
  return Math.round(n * m) / m;
}

function stripTrailingSlash(u: string) {
  return u.endsWith("/") ? u.slice(0, -1) : u;
}

async function loadInventory(p: string): Promise<Map<string, { owner?: string; intent?: string; template?: string }>> {
  const out = new Map<string, { owner?: string; intent?: string; template?: string }>();
  if (!existsSync(p)) return out;
  const txt = await Bun.file(p).text();
  // Best-effort markdown table parser. Expected columns include URL/path, plus owner / intent / template if present.
  const tableLines = txt.split("\n").filter((l) => l.trim().startsWith("|"));
  if (tableLines.length < 2) return out;
  const header = tableLines[0].split("|").map((c) => c.trim().toLowerCase()).filter(Boolean);
  const urlIdx = header.findIndex((h) => /url|page|path/.test(h));
  const ownerIdx = header.findIndex((h) => /owner|author/.test(h));
  const intentIdx = header.findIndex((h) => /intent/.test(h));
  const tplIdx = header.findIndex((h) => /template/.test(h));
  if (urlIdx < 0) return out;
  for (const line of tableLines.slice(2)) {
    const cells = line.split("|").map((c) => c.trim());
    // first cell is empty due to leading |
    const offset = cells[0] === "" ? 1 : 0;
    const url = cells[urlIdx + offset];
    if (!url || /^-+$/.test(url)) continue;
    const m = url.match(/\((https?:\/\/[^)]+)\)/);
    const u = m?.[1] ?? url;
    out.set(u, {
      owner: ownerIdx >= 0 ? cells[ownerIdx + offset] : undefined,
      intent: intentIdx >= 0 ? cells[intentIdx + offset] : undefined,
      template: tplIdx >= 0 ? cells[tplIdx + offset] : undefined,
    });
    out.set(stripTrailingSlash(u), out.get(u)!);
  }
  return out;
}

function recommend(c: {
  position: number;
  impressions: number;
  ctr: number;
  ratio: number;
  intent: string | null;
  template: string | null;
  top_queries: Array<{ query: string; impressions: number; clicks: number; position: number }>;
}): { action: string; rationale: string } {
  const intent = (c.intent ?? "").toLowerCase();
  const template = (c.template ?? "").toLowerCase();
  // Very low CTR for slot — title is the bottleneck.
  if (c.ratio > 0 && c.ratio < 0.6) {
    return {
      action: "title rewrite",
      rationale: `CTR ${(c.ctr * 100).toFixed(1)}% is ${Math.round(c.ratio * 100)}% of expected at position ${c.position.toFixed(1)}; the SERP listing isn't earning the click.`,
    };
  }
  // Mid-range CTR but page is in mid SERP — better internal linking will lift position.
  if (c.position >= 6 && c.position <= 12 && c.impressions >= 200) {
    return {
      action: "internal link",
      rationale: `pos ${c.position.toFixed(1)} with ${c.impressions} imp — add internal links from higher-authority hub/cluster pages to lift to top 5.`,
    };
  }
  // Comparison/review/best-of intent without proof signals.
  if (/comparison|review|best|alternative|vs/.test(intent) || /comparison|review|alternative|vs/.test(template)) {
    return {
      action: "add proof",
      rationale: `intent="${c.intent}" — add side-by-side comparison, screenshots, source-of-truth quotes, and named author + last-reviewed date.`,
    };
  }
  // Mid CTR & generic title pattern → meta rewrite.
  if (c.ratio >= 0.6 && c.ratio < 0.9) {
    return {
      action: "meta rewrite",
      rationale: `CTR ${(c.ctr * 100).toFixed(1)}% is ${Math.round(c.ratio * 100)}% of expected — refresh meta description with a quantified benefit + clear CTA.`,
    };
  }
  // FAQ candidate detection: queries phrased as questions.
  const qShare = c.top_queries.filter((q) => /^(how|what|why|when|can|does|is|are|should|which)\b/i.test(q.query)).length;
  if (qShare >= 2) {
    return {
      action: "schema fix",
      rationale: `${qShare} top queries are question-phrased; ensure on-page FAQ block + valid FAQPage JSON-LD (or Article + Q&A markup if FAQ rich result is gated).`,
    };
  }
  return {
    action: "internal link",
    rationale: `default action — improve topical mesh: link from at least 3 high-traffic hub pages with descriptive anchor text.`,
  };
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
