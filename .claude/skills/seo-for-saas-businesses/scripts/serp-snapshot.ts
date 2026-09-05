#!/usr/bin/env bun
/**
 * serp-snapshot.ts — Snapshot Google SERPs for a list of queries via Playwright.
 *
 * For each query, opens a clean Chromium context (fresh profile, no GA cookies,
 * no prior history) and captures structured data:
 *   - top 10 organic results (rank, url, title, snippet)
 *   - AI Overview presence + cited URLs (if rendered for the geo)
 *   - People Also Ask (PAA) panel questions
 *   - Video, image, product, local, forum, news pack presence
 *   - Combined ad-block height (top sponsored results) in px
 *   - Featured-snippet/answer-box presence + URL
 *   - Knowledge panel presence
 *
 * Saves analyses/serps/<queryhash>.json + analyses/serps/<queryhash>.html
 * (rendered HTML snapshot for offline review). Aggregate index at _index.md.
 *
 * Usage:
 *   bun run scripts/serp-snapshot.ts \
 *     --queries analyses/seed-queries.json \
 *     --output analyses/serps/ \
 *     [--gl us] [--hl en] [--check-aio true] \
 *     [--user-agent "Mozilla/5.0 ..."] \
 *     [--concurrency 1]                 # serial recommended for SERPs
 *
 * Queries file shape:
 *   { "queries": [{ "q": "best invoicing software", "intent": "comparison" }, ...] }
 *
 * Jurisdiction caveats:
 *   - AI Overviews availability varies by country and account state. The script
 *     reports the rendered DOM as-is for the geo specified — absence does NOT
 *     mean Google never shows AIO for that query, only that it didn't this session.
 *   - Personalization is reduced (no cookies, no signed-in account) but not
 *     eliminated. IP-based geo can override --gl. Run from the relevant exit IP
 *     when measuring local intent.
 *   - Some SERP elements load lazily; the script waits for networkidle but Google
 *     may still A/B-test layouts. Compare runs with consistent UA/geo.
 *   - This is for diagnostic snapshotting. Do NOT use for high-volume rank tracking
 *     (use a paid SERP API for that — terms-of-service and CAPTCHA reasons).
 *
 * Exit codes: 0 success; 2 missing args; 5 if a CAPTCHA/consent wall blocked all queries.
 */

import { chromium } from "playwright";
import { createHash } from "node:crypto";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";

const args = parseArgs(Bun.argv.slice(2));
const queriesPath = args["--queries"];
const outDir = args["--output"] ?? "analyses/serps/";
const gl = args["--gl"] ?? "us";
const hl = args["--hl"] ?? "en";
const checkAio = (args["--check-aio"] ?? "true") === "true";
const ua =
  args["--user-agent"] ??
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";
const concurrency = Number(args["--concurrency"] ?? 1);

if (!queriesPath) {
  console.error("Required: --queries <path>");
  process.exit(2);
}

await mkdir(outDir, { recursive: true });

const queriesFile = JSON.parse(await Bun.file(queriesPath).text()) as {
  queries: Array<{ q: string; intent?: string }>;
};

const browser = await chromium.launch();
const indexLines: string[] = [
  `# SERP snapshots — ${new Date().toISOString()}`,
  `Geo: gl=${gl}  hl=${hl}  AIO check: ${checkAio}`,
  `UA: ${ua}`,
  ``,
  `| Query | Intent | Top1 | AIO | PAA | Video | Image | Product | Local | News | Ads(px) |`,
  `|-------|--------|------|-----|-----|-------|-------|---------|-------|------|---------|`,
];

let captchaBlocked = 0;
let i = 0;
async function next(): Promise<void> {
  if (i >= queriesFile.queries.length) return;
  const q = queriesFile.queries[i++];
  try {
    const r = await snapshot(q);
    if (r.captcha) captchaBlocked++;
    indexLines.push(
      `| ${q.q} | ${q.intent ?? ""} | ${r.organic[0]?.url ?? ""} | ${r.aio.present ? "Y" : "N"} | ${r.paa.length} | ${r.packs.video ? "Y" : "N"} | ${r.packs.image ? "Y" : "N"} | ${r.packs.product ? "Y" : "N"} | ${r.packs.local ? "Y" : "N"} | ${r.packs.news ? "Y" : "N"} | ${r.ads_px} |`,
    );
    process.stdout.write(`✓ ${q.q}\n`);
  } catch (err) {
    process.stdout.write(`✗ ${q.q} — ${(err as Error).message}\n`);
  }
  await next();
}
await Promise.all(Array.from({ length: concurrency }, () => next()));
await browser.close();

await Bun.write(join(outDir, "_index.md"), indexLines.join("\n") + "\n");
console.log(`SERP snapshots written to ${outDir}`);
if (captchaBlocked === queriesFile.queries.length) {
  console.error("Every query was blocked by a consent/CAPTCHA wall. Re-run from a different IP or solve manually.");
  process.exit(5);
}
process.exit(0);

async function snapshot(q: { q: string; intent?: string }) {
  const hash = createHash("sha1").update(q.q + "|" + gl + "|" + hl).digest("hex").slice(0, 12);
  const ctx = await browser.newContext({
    userAgent: ua,
    viewport: { width: 1280, height: 1800 },
    locale: hl,
    timezoneId: "America/New_York",
    extraHTTPHeaders: { "Accept-Language": `${hl},en;q=0.9` },
  });
  await ctx.clearCookies();
  const page = await ctx.newPage();
  try {

  const url = `https://www.google.com/search?q=${encodeURIComponent(q.q)}&gl=${gl}&hl=${hl}&num=20&pws=0`;
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
  // dismiss EU consent if shown (best-effort; skip if absent)
  try {
    const consent = page.locator('button:has-text("Accept all"), button:has-text("I agree"), button:has-text("Reject all")').first();
    if (await consent.isVisible({ timeout: 1500 }).catch(() => false)) {
      await consent.click({ timeout: 1500 }).catch(() => {});
      await page.waitForLoadState("networkidle", { timeout: 5000 }).catch(() => {});
    }
  } catch { /* ignore */ }
  await page.waitForLoadState("networkidle", { timeout: 15000 }).catch(() => {});

  const html = await page.content();
  await Bun.write(join(outDir, `${hash}.html`), html);

  const captcha = /unusual traffic|recaptcha|sorry\/index/i.test(html);

  // organic results: scrape via DOM
  const organic = await page.evaluate(() => {
    const rows: Array<{ rank: number; url: string; title: string; snippet: string }> = [];
    const blocks = document.querySelectorAll("div.g, div[data-snc], div.MjjYud");
    let rank = 0;
    for (const el of blocks as any) {
      const a = el.querySelector("a[href^='http']");
      const h3 = el.querySelector("h3");
      if (!a || !h3) continue;
      const href = a.getAttribute("href") || "";
      if (href.startsWith("https://www.google.com/")) continue;
      const snippetEl = el.querySelector("div[data-sncf], span.aCOpRe, div.VwiC3b") as HTMLElement | null;
      rank++;
      rows.push({
        rank,
        url: href,
        title: h3.textContent?.trim() || "",
        snippet: snippetEl?.textContent?.trim() || "",
      });
      if (rank >= 10) break;
    }
    return rows;
  }).catch(() => []);

  // PAA
  const paa = await page.evaluate(() => {
    const out: string[] = [];
    const sel = document.querySelectorAll('[data-initq], div[jsname="N760b"], div.related-question-pair span');
    for (const el of sel as any) {
      const t = el.textContent?.trim();
      if (t && t.length > 5 && t.length < 200) out.push(t);
    }
    return Array.from(new Set(out));
  }).catch(() => []);

  // AIO: heuristic by container roles + cited links
  const aio = checkAio
    ? await page.evaluate(() => {
        const labels = ["AI Overview", "Generative AI", "Search Labs"];
        const candidates = Array.from(document.querySelectorAll("div, section")) as HTMLElement[];
        for (const el of candidates) {
          const t = el.textContent?.slice(0, 120) || "";
          if (labels.some((l) => t.includes(l)) && el.querySelectorAll("a[href^='http']").length > 0) {
            const cited = Array.from(el.querySelectorAll("a[href^='http']")).map((a) => (a as HTMLAnchorElement).href);
            return { present: true, cited: Array.from(new Set(cited)).slice(0, 20) };
          }
        }
        return { present: false, cited: [] as string[] };
      }).catch(() => ({ present: false, cited: [] as string[] }))
    : { present: false, cited: [] as string[] };

  // Packs
  const packs = await page.evaluate(() => {
    const has = (sel: string) => !!document.querySelector(sel);
    return {
      video: has("g-scrolling-carousel video, div[aria-label*='Video' i], div[data-attrid*='video']"),
      image: has("g-section-with-header div[data-attrid*='image'], div[id='iur']"),
      product: has("div[aria-label*='shopping' i], g-scrolling-carousel a[href*='shopping.google']"),
      local: has("div[role='complementary'] [data-attrid*='local'], #lu_map"),
      forum: !!document.body.innerText.match(/Discussions and forums|From the (community|forums)/i),
      news: has("g-section-with-header[data-hveid] a[href*='news.google'], div[aria-label='Top stories']"),
    };
  }).catch(() => ({ video: false, image: false, product: false, local: false, forum: false, news: false }));

  // featured snippet / answer
  const featured = await page.evaluate(() => {
    const fs = document.querySelector("div.kp-blk, div.c2xzTb, div[data-attrid*='answer']");
    if (!fs) return { present: false, url: "" };
    const a = fs.querySelector("a[href^='http']") as HTMLAnchorElement | null;
    return { present: true, url: a?.href ?? "" };
  }).catch(() => ({ present: false, url: "" }));

  // ads block height
  const ads_px = await page.evaluate(() => {
    const adNodes = document.querySelectorAll(
      "div[data-text-ad], #tads, div[aria-label='Ads'], div[data-pcu]",
    );
    let total = 0;
    for (const n of adNodes as any) total += (n as HTMLElement).offsetHeight ?? 0;
    return total;
  }).catch(() => 0);

  // knowledge panel
  const knowledge = await page.evaluate(() => {
    return !!document.querySelector("div.kp-wholepage, div[data-hveid][data-attrid*='kc']");
  }).catch(() => false);

  const data = {
    query: q.q,
    intent: q.intent,
    geo: { gl, hl },
    captured_at: new Date().toISOString(),
    captcha_blocked: captcha,
    organic,
    paa,
    aio,
    packs,
    featured_snippet: featured,
    knowledge_panel: knowledge,
    ads_px,
  };
  await Bun.write(join(outDir, `${hash}.json`), JSON.stringify(data, null, 2));
  return { ...data, captcha };
  } finally {
    await page.close().catch(() => {});
    await ctx.close().catch(() => {});
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
