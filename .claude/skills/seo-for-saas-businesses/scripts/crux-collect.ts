#!/usr/bin/env bun
/**
 * crux-collect.ts — Collect Chrome User Experience Report (CrUX) field data.
 *
 * For each URL in the representative set:
 *   - Query CrUX API for the URL itself (record_type "url"). If the URL has
 *     insufficient real-user data, fall back to the origin (record_type "origin").
 *   - Pull p75 LCP, INP, CLS, TTFB, FCP for PHONE, DESKTOP, and ALL_FORM_FACTORS.
 *   - Save analyses/crux/<urlhash>.json with both URL-level and origin fallback.
 *   - Also write a roll-up CSV (analyses/crux/_summary.csv) and markdown digest.
 *
 * API setup:
 *   1. Enable "Chrome UX Report API" in Google Cloud Console.
 *   2. Create an API key. CrUX accepts unrestricted API keys.
 *   3. Pass via --key or env CRUX_KEY. Free quota is generous (per-key per-minute).
 *
 * Usage:
 *   bun run scripts/crux-collect.ts \
 *     --rep-set analyses/representative-urls.json \
 *     --key $CRUX_KEY \
 *     [--form-factor PHONE]            # restrict to one form factor (PHONE|DESKTOP|TABLET)
 *     [--output analyses/crux/]
 *
 * Exit codes:
 *   0 success; 2 missing args; 3 API key invalid; 4 zero successful fetches.
 */

import { createHash } from "node:crypto";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";

const args = parseArgs(Bun.argv.slice(2));
const repSet = args["--rep-set"] ?? "analyses/representative-urls.json";
const key = args["--key"] ?? process.env.CRUX_KEY ?? "";
const onlyFf = args["--form-factor"]; // optional
const outDir = args["--output"] ?? "analyses/crux/";
const timeout = Number(args["--timeout"] ?? 30000);

if (!key) {
  console.error("Required: --key <CRUX_API_KEY> (or env CRUX_KEY)");
  process.exit(2);
}

await mkdir(outDir, { recursive: true });

const rep = JSON.parse(await Bun.file(repSet).text()) as {
  urls: Array<{ url: string; template?: string; intent?: string }>;
};

const FORM_FACTORS = onlyFf ? [onlyFf] : ["PHONE", "DESKTOP", "ALL_FORM_FACTORS"];
const METRICS = [
  "largest_contentful_paint",
  "interaction_to_next_paint",
  "cumulative_layout_shift",
  "experimental_time_to_first_byte",
  "first_contentful_paint",
];

type FfReport = {
  form_factor: string;
  record_type: "url" | "origin" | "none";
  source_url: string;
  collection_period?: { firstDate: any; lastDate: any };
  metrics: Record<string, { p75: number | null; histogram?: any[] } | null>;
};

let totalOk = 0;
const summary: Array<{
  url: string;
  template?: string;
  form_factor: string;
  record_type: string;
  lcp_p75: number | null;
  inp_p75: number | null;
  cls_p75: number | null;
  ttfb_p75: number | null;
  fcp_p75: number | null;
}> = [];

for (const u of rep.urls) {
  const hash = createHash("sha1").update(u.url).digest("hex").slice(0, 12);
  const reports: FfReport[] = [];

  for (const ff of FORM_FACTORS) {
    // try URL-level
    let body: any = {
      url: u.url,
      metrics: METRICS,
    };
    if (ff !== "ALL_FORM_FACTORS") body.formFactor = ff;
    let resp = await cruxQuery(body);

    let record_type: FfReport["record_type"] = "url";
    let source_url = u.url;
    if (!resp || resp.error?.code === 404) {
      // origin fallback
      const origin = new URL(u.url).origin + "/";
      body = { origin, metrics: METRICS };
      if (ff !== "ALL_FORM_FACTORS") body.formFactor = ff;
      resp = await cruxQuery(body);
      record_type = resp && !resp.error ? "origin" : "none";
      source_url = origin;
    }
    if (!resp || resp.error) {
      reports.push({
        form_factor: ff,
        record_type: "none",
        source_url,
        metrics: Object.fromEntries(METRICS.map((m) => [m, null])),
      });
      continue;
    }

    totalOk++;
    const rec = resp.record ?? {};
    const period = rec.collectionPeriod;
    const metrics: Record<string, any> = {};
    for (const m of METRICS) {
      const data = rec.metrics?.[m];
      if (!data) {
        metrics[m] = null;
        continue;
      }
      const p75 =
        data.percentiles?.p75 !== undefined
          ? Number(data.percentiles.p75)
          : null;
      metrics[m] = { p75, histogram: data.histogram };
    }
    reports.push({
      form_factor: ff,
      record_type,
      source_url,
      collection_period: period,
      metrics,
    });

    summary.push({
      url: u.url,
      template: u.template,
      form_factor: ff,
      record_type,
      lcp_p75: metrics.largest_contentful_paint?.p75 ?? null,
      inp_p75: metrics.interaction_to_next_paint?.p75 ?? null,
      cls_p75: metrics.cumulative_layout_shift?.p75 ?? null,
      ttfb_p75: metrics.experimental_time_to_first_byte?.p75 ?? null,
      fcp_p75: metrics.first_contentful_paint?.p75 ?? null,
    });
  }

  await Bun.write(
    join(outDir, `${hash}.json`),
    JSON.stringify(
      { url: u.url, template: u.template, intent: u.intent, fetched_at: new Date().toISOString(), reports },
      null,
      2,
    ),
  );
  process.stdout.write(`✓ ${u.url} (${reports.filter((r) => r.record_type !== "none").length}/${reports.length} ff)\n`);
}

// summary CSV
const csvHeader =
  "url,template,form_factor,record_type,lcp_p75_ms,inp_p75_ms,cls_p75,ttfb_p75_ms,fcp_p75_ms\n";
const csvRows = summary
  .map(
    (s) =>
      `${csv(s.url)},${csv(s.template ?? "")},${s.form_factor},${s.record_type},${n(s.lcp_p75)},${n(s.inp_p75)},${n(s.cls_p75)},${n(s.ttfb_p75)},${n(s.fcp_p75)}`,
  )
  .join("\n");
await Bun.write(join(outDir, "_summary.csv"), csvHeader + csvRows + "\n");

// markdown digest with thresholds (Core Web Vitals "Good" 2026)
const md = [
  `# CrUX field data — ${new Date().toISOString()}`,
  ``,
  `Thresholds (Good): LCP < 2500ms · INP < 200ms · CLS < 0.10 · TTFB < 800ms · FCP < 1800ms`,
  ``,
  `## URL × form-factor (${summary.length} rows)`,
  ``,
  `| URL | FF | type | LCP | INP | CLS | TTFB |`,
  `|-----|----|------|-----|-----|-----|------|`,
  ...summary.slice(0, 200).map((s) => {
    const flag = (v: number | null, t: number) =>
      v === null ? "—" : v > t ? `**${v}**` : `${v}`;
    return `| ${s.url} | ${s.form_factor} | ${s.record_type} | ${flag(s.lcp_p75, 2500)} | ${flag(s.inp_p75, 200)} | ${s.cls_p75 === null ? "—" : s.cls_p75 > 0.1 ? `**${s.cls_p75}**` : s.cls_p75} | ${flag(s.ttfb_p75, 800)} |`;
  }),
];
await Bun.write(join(outDir, "_summary.md"), md.join("\n") + "\n");

console.log(`CrUX collection complete. ${totalOk} successful queries.`);
if (totalOk === 0) process.exit(4);
process.exit(0);

async function cruxQuery(body: any): Promise<any | null> {
  const r = await fetch(
    `https://chromeuxreport.googleapis.com/v1/records:queryRecord?key=${encodeURIComponent(key)}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeout),
    },
  );
  if (r.status === 400 || r.status === 401 || r.status === 403) {
    const txt = await r.text();
    if (/API key/i.test(txt)) {
      console.error(`CrUX API key invalid/disabled: ${txt}`);
      process.exit(3);
    }
    return { error: { code: r.status, message: txt } };
  }
  if (r.status === 404) return { error: { code: 404 } };
  if (!r.ok) return { error: { code: r.status, message: await r.text() } };
  return r.json();
}

function csv(s: string) {
  if (s == null) return "";
  if (/[",\n]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
  return s;
}
function n(v: number | null) {
  return v === null ? "" : String(v);
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
