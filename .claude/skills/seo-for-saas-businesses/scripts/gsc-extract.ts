#!/usr/bin/env bun
/**
 * gsc-extract.ts — Pull Google Search Console performance via the Search Console API.
 *
 * Outputs (under analyses/gsc/):
 *   - performance.csv             — per-URL+query rows (date-bucketed if requested)
 *   - per-page.csv                — aggregated per page (clicks/impressions/CTR/position)
 *   - per-query.csv               — aggregated per query
 *   - branded-vs-nonbranded.json  — split totals using --branded-pattern
 *   - striking-distance.json      — pages with avg position 4-15, impressions > N
 *   - winners-losers.json         — top winners & losers WoW (current vs prior period)
 *   - summary.md                  — human-readable overview
 *
 * API setup:
 *   1. In Google Cloud Console enable the "Google Search Console API" for a project.
 *   2. Either:
 *      a) Service account: create a service account JSON key, then in GSC UI add the
 *         service account email (xxx@yyy.iam.gserviceaccount.com) as a Restricted user
 *         on the property. Pass with --service-account <path>.
 *      b) OAuth: download an OAuth client (Desktop) JSON, run the script once with
 *         --oauth-client <path>; it will print a URL — visit it, paste the code back.
 *         A token cache is stored at ~/.config/seo-skill/gsc-token.json.
 *   3. siteUrl format must match GSC exactly:
 *      - URL property:    "https://www.example.com/"
 *      - Domain property: "sc-domain:example.com"
 *
 * Usage:
 *   bun run scripts/gsc-extract.ts \
 *     --site "sc-domain:example.com" \
 *     --service-account ~/.gcp/seo-sa.json \
 *     --start 2026-04-01 --end 2026-04-28 \
 *     [--branded-pattern "(?i)example|exmpl"] \
 *     [--min-impressions 100] \
 *     [--row-limit 25000] \
 *     [--output analyses/gsc/]
 *
 * Exit codes:
 *   0 success; 2 missing args; 3 API auth/permission error; 4 no rows returned.
 */

import { createHash } from "node:crypto";
import { mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const args = parseArgs(Bun.argv.slice(2));
const site = args["--site"];
const saPath = args["--service-account"];
const oauthClientPath = args["--oauth-client"];
const start = args["--start"];
const end = args["--end"];
const brandedPattern = args["--branded-pattern"] ?? "";
const minImpressions = Number(args["--min-impressions"] ?? 100);
const rowLimit = Math.min(Number(args["--row-limit"] ?? 25000), 25000);
const outDir = args["--output"] ?? "analyses/gsc/";
const timeout = Number(args["--timeout"] ?? 30000);

if (!site || !start || !end) {
  console.error(
    "Required: --site <siteUrl> --start YYYY-MM-DD --end YYYY-MM-DD",
  );
  console.error("Auth: --service-account <path> OR --oauth-client <path>");
  process.exit(2);
}
if (!saPath && !oauthClientPath) {
  console.error("Provide --service-account or --oauth-client.");
  process.exit(2);
}

await mkdir(outDir, { recursive: true });

// ---- auth ----
const accessToken = saPath
  ? await getServiceAccountToken(saPath)
  : await getOauthToken(oauthClientPath!);

// ---- API call helper ----
async function gsc(body: Record<string, any>) {
  const u = `https://searchconsole.googleapis.com/webmasters/v3/sites/${encodeURIComponent(site!)}/searchAnalytics/query`;
  const r = await fetch(u, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeout),
  });
  if (r.status === 401 || r.status === 403) {
    console.error(`GSC API auth/permission error ${r.status}: ${await r.text()}`);
    process.exit(3);
  }
  if (!r.ok) {
    console.error(`GSC API error ${r.status}: ${await r.text()}`);
    process.exit(3);
  }
  return r.json() as Promise<{ rows?: GscRow[] }>;
}

type GscRow = {
  keys: string[];
  clicks: number;
  impressions: number;
  ctr: number;
  position: number;
};

// ---- pull current period (page+query rows) ----
const current = await pullAll({
  startDate: start,
  endDate: end,
  dimensions: ["page", "query"],
  rowLimit,
  type: "web",
});
if (current.length === 0) {
  console.error("No rows returned for current period. Check site URL format and date range.");
  process.exit(4);
}

// ---- prior period for WoW comparison ----
const prior = await pullAll({
  ...priorPeriod(start, end),
  dimensions: ["page", "query"],
  rowLimit,
  type: "web",
});

// ---- write performance.csv ----
const perfHeader = "page,query,clicks,impressions,ctr,position\n";
const perfRows = current
  .map(
    (r) =>
      `${csv(r.keys[0])},${csv(r.keys[1])},${r.clicks},${r.impressions},${r.ctr.toFixed(4)},${r.position.toFixed(2)}`,
  )
  .join("\n");
await Bun.write(join(outDir, "performance.csv"), perfHeader + perfRows + "\n");

// ---- aggregate per-page ----
const perPage = aggregateBy(current, (r) => r.keys[0]);
const perPageCsv =
  "page,clicks,impressions,ctr,position\n" +
  perPage
    .map(
      (a) =>
        `${csv(a.key)},${a.clicks},${a.impressions},${a.ctr.toFixed(4)},${a.position.toFixed(2)}`,
    )
    .join("\n");
await Bun.write(join(outDir, "per-page.csv"), perPageCsv + "\n");

// ---- aggregate per-query ----
const perQuery = aggregateBy(current, (r) => r.keys[1]);
const perQueryCsv =
  "query,clicks,impressions,ctr,position\n" +
  perQuery
    .map(
      (a) =>
        `${csv(a.key)},${a.clicks},${a.impressions},${a.ctr.toFixed(4)},${a.position.toFixed(2)}`,
    )
    .join("\n");
await Bun.write(join(outDir, "per-query.csv"), perQueryCsv + "\n");

// ---- branded vs non-branded ----
const brandRe = brandedPattern ? new RegExp(brandedPattern.replace(/^\(\?i\)/, ""), "i") : null;
const branded = { clicks: 0, impressions: 0, queries: 0 };
const non = { clicks: 0, impressions: 0, queries: 0 };
for (const q of perQuery) {
  if (brandRe && brandRe.test(q.key)) {
    branded.clicks += q.clicks;
    branded.impressions += q.impressions;
    branded.queries++;
  } else {
    non.clicks += q.clicks;
    non.impressions += q.impressions;
    non.queries++;
  }
}
await Bun.write(
  join(outDir, "branded-vs-nonbranded.json"),
  JSON.stringify(
    { pattern: brandedPattern || null, branded, non_branded: non },
    null,
    2,
  ),
);

// ---- striking distance ----
const striking = perPage
  .filter(
    (p) => p.position >= 4 && p.position <= 15 && p.impressions >= minImpressions,
  )
  .map((p) => ({
    page: p.key,
    avg_position: Number(p.position.toFixed(2)),
    impressions: p.impressions,
    clicks: p.clicks,
    ctr: Number(p.ctr.toFixed(4)),
    expected_ctr_pos3: 0.1, // SERP-style heuristic; striking-distance.ts refines this
    potential_lift_clicks: Math.max(0, Math.round(p.impressions * (0.1 - p.ctr))),
  }))
  .sort((a, b) => b.potential_lift_clicks - a.potential_lift_clicks);
await Bun.write(
  join(outDir, "striking-distance.json"),
  JSON.stringify(striking, null, 2),
);

// ---- winners & losers WoW ----
const priorByKey = new Map<string, GscRow>();
for (const r of prior) priorByKey.set(`${r.keys[0]}|${r.keys[1]}`, r);
const deltas: Array<{
  page: string;
  query: string;
  clicks_delta: number;
  position_delta: number;
  impressions: number;
  prior_position: number;
  current_position: number;
}> = [];
for (const r of current) {
  const k = `${r.keys[0]}|${r.keys[1]}`;
  const p = priorByKey.get(k);
  if (!p) continue;
  deltas.push({
    page: r.keys[0],
    query: r.keys[1],
    clicks_delta: r.clicks - p.clicks,
    position_delta: p.position - r.position, // positive = improved
    impressions: r.impressions,
    prior_position: Number(p.position.toFixed(2)),
    current_position: Number(r.position.toFixed(2)),
  });
}
const winners = [...deltas].sort((a, b) => b.clicks_delta - a.clicks_delta).slice(0, 50);
const losers = [...deltas].sort((a, b) => a.clicks_delta - b.clicks_delta).slice(0, 50);
await Bun.write(
  join(outDir, "winners-losers.json"),
  JSON.stringify(
    { current_period: { start, end }, winners, losers },
    null,
    2,
  ),
);

// ---- summary.md ----
const totalClicks = current.reduce((s, r) => s + r.clicks, 0);
const totalImpressions = current.reduce((s, r) => s + r.impressions, 0);
const md = [
  `# GSC extract — ${site}`,
  `Generated: ${new Date().toISOString()}`,
  `Period: ${start} → ${end}  (rows: ${current.length})`,
  ``,
  `## Totals`,
  `- Clicks: ${totalClicks.toLocaleString()}`,
  `- Impressions: ${totalImpressions.toLocaleString()}`,
  `- Avg CTR: ${(totalClicks / Math.max(totalImpressions, 1) * 100).toFixed(2)}%`,
  ``,
  `## Branded vs non-branded (pattern: ${brandedPattern || "(none)"})`,
  `- Branded clicks: ${branded.clicks} / impressions: ${branded.impressions} / unique queries: ${branded.queries}`,
  `- Non-branded clicks: ${non.clicks} / impressions: ${non.impressions} / unique queries: ${non.queries}`,
  ``,
  `## Striking distance (pos 4-15, impressions ≥ ${minImpressions})`,
  `Top 10 by potential lift:`,
  ...striking.slice(0, 10).map(
    (s, i) =>
      `${i + 1}. ${s.page} — pos ${s.avg_position}, ${s.impressions} imp, +${s.potential_lift_clicks} potential clicks`,
  ),
  ``,
  `## Top winners WoW (clicks delta)`,
  ...winners.slice(0, 10).map(
    (w, i) =>
      `${i + 1}. ${w.query} (${w.page}) +${w.clicks_delta} clicks, pos ${w.prior_position} → ${w.current_position}`,
  ),
  ``,
  `## Top losers WoW (clicks delta)`,
  ...losers.slice(0, 10).map(
    (w, i) =>
      `${i + 1}. ${w.query} (${w.page}) ${w.clicks_delta} clicks, pos ${w.prior_position} → ${w.current_position}`,
  ),
  ``,
  `Files written: performance.csv, per-page.csv, per-query.csv, branded-vs-nonbranded.json, striking-distance.json, winners-losers.json`,
];
await Bun.write(join(outDir, "summary.md"), md.join("\n"));

console.log(`GSC extract complete. ${current.length} rows. Output: ${outDir}`);
process.exit(0);

// ---------- helpers ----------

async function pullAll(body: Record<string, any>): Promise<GscRow[]> {
  const out: GscRow[] = [];
  let startRow = 0;
  while (true) {
    const data = await gsc({ ...body, startRow });
    const rows = data.rows ?? [];
    out.push(...rows);
    if (rows.length < (body.rowLimit ?? rowLimit)) break;
    startRow += rows.length;
    if (out.length >= rowLimit) break;
  }
  return out;
}

function aggregateBy(rows: GscRow[], keyFn: (r: GscRow) => string) {
  const map = new Map<
    string,
    { key: string; clicks: number; impressions: number; ctr: number; position: number; _w: number }
  >();
  for (const r of rows) {
    const k = keyFn(r);
    const e = map.get(k) ?? { key: k, clicks: 0, impressions: 0, ctr: 0, position: 0, _w: 0 };
    e.clicks += r.clicks;
    e.impressions += r.impressions;
    // weighted-by-impressions average position
    e.position = (e.position * e._w + r.position * r.impressions) / Math.max(e._w + r.impressions, 1);
    e._w += r.impressions;
    map.set(k, e);
  }
  for (const e of map.values()) {
    e.ctr = e.clicks / Math.max(e.impressions, 1);
  }
  return [...map.values()].sort((a, b) => b.impressions - a.impressions);
}

function priorPeriod(s: string, e: string) {
  const sd = new Date(s + "T00:00:00Z").getTime();
  const ed = new Date(e + "T00:00:00Z").getTime();
  const len = ed - sd;
  return {
    startDate: new Date(sd - len - 86400000).toISOString().slice(0, 10),
    endDate: new Date(sd - 86400000).toISOString().slice(0, 10),
  };
}

function csv(s: string) {
  if (s == null) return "";
  if (/[",\n]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
  return s;
}

async function getServiceAccountToken(path: string): Promise<string> {
  const sa = JSON.parse(await Bun.file(path).text());
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/webmasters.readonly",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  );
  const signingInput = `${header}.${claim}`;
  const sig = await signRs256(signingInput, sa.private_key);
  const jwt = `${signingInput}.${sig}`;
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }).toString(),
    signal: AbortSignal.timeout(timeout),
  });
  if (!r.ok) {
    console.error(`Service account token exchange failed: ${r.status} ${await r.text()}`);
    process.exit(3);
  }
  const j = (await r.json()) as { access_token: string };
  return j.access_token;
}

async function signRs256(input: string, pem: string): Promise<string> {
  const der = pemToDer(pem);
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(input),
  );
  return b64urlBytes(new Uint8Array(sig));
}

function pemToDer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s+/g, "");
  const bin = atob(body);
  const buf = new Uint8Array(bin.length);
  for (let k = 0; k < bin.length; k++) buf[k] = bin.charCodeAt(k);
  return buf.buffer;
}

function b64url(s: string) {
  return b64urlBytes(new TextEncoder().encode(s));
}
function b64urlBytes(b: Uint8Array) {
  let s = "";
  for (let k = 0; k < b.length; k++) s += String.fromCharCode(b[k]);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function getOauthToken(clientPath: string): Promise<string> {
  const cfgDir = join(homedir(), ".config", "seo-skill");
  await mkdir(cfgDir, { recursive: true });
  const cachePath = join(cfgDir, "gsc-token.json");
  const client = JSON.parse(await Bun.file(clientPath).text());
  const installed = client.installed ?? client.web;
  if (!installed) {
    console.error("OAuth client JSON missing 'installed' or 'web' section.");
    process.exit(3);
  }
  if (existsSync(cachePath)) {
    const cached = JSON.parse(await Bun.file(cachePath).text());
    if (cached.expires_at && cached.expires_at > Date.now() + 60000) {
      return cached.access_token;
    }
    if (cached.refresh_token) {
      const r = await fetch("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          client_id: installed.client_id,
          client_secret: installed.client_secret,
          refresh_token: cached.refresh_token,
          grant_type: "refresh_token",
        }).toString(),
        signal: AbortSignal.timeout(timeout),
      });
      if (r.ok) {
        const j = (await r.json()) as any;
        const out = {
          access_token: j.access_token,
          refresh_token: cached.refresh_token,
          expires_at: Date.now() + (j.expires_in - 60) * 1000,
        };
        await Bun.write(cachePath, JSON.stringify(out, null, 2));
        return out.access_token;
      }
    }
  }
  // first-time interactive
  const redirect = "urn:ietf:wg:oauth:2.0:oob";
  const authUrl =
    `https://accounts.google.com/o/oauth2/v2/auth?` +
    new URLSearchParams({
      client_id: installed.client_id,
      redirect_uri: redirect,
      response_type: "code",
      scope: "https://www.googleapis.com/auth/webmasters.readonly",
      access_type: "offline",
      prompt: "consent",
    }).toString();
  console.log("\nOpen this URL in a browser, approve, then paste the code:\n");
  console.log(authUrl + "\n");
  process.stdout.write("Code: ");
  const code = (await readStdinLine()).trim();
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: installed.client_id,
      client_secret: installed.client_secret,
      redirect_uri: redirect,
      grant_type: "authorization_code",
    }).toString(),
    signal: AbortSignal.timeout(timeout),
  });
  if (!r.ok) {
    console.error(`OAuth token exchange failed: ${r.status} ${await r.text()}`);
    process.exit(3);
  }
  const j = (await r.json()) as any;
  const out = {
    access_token: j.access_token,
    refresh_token: j.refresh_token,
    expires_at: Date.now() + (j.expires_in - 60) * 1000,
  };
  await Bun.write(cachePath, JSON.stringify(out, null, 2));
  return out.access_token;
}

async function readStdinLine(): Promise<string> {
  const decoder = new TextDecoder();
  let acc = "";
  for await (const chunk of (Bun.stdin as any).stream()) {
    acc += decoder.decode(chunk);
    if (acc.includes("\n")) return acc.split("\n")[0];
  }
  return acc;
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
