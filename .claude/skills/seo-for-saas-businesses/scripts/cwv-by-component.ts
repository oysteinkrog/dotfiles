#!/usr/bin/env bun
/**
 * cwv-by-component.ts — Component-level INP attribution.
 *
 * Loads each URL in Playwright (mobile profile by default), runs a scripted
 * sequence of interactions (click hero CTA, hover plan card, toggle billing
 * monthly/yearly, click FAQ accordion), and captures:
 *   - PerformanceObserver entries: 'long-animation-frame' (LoAF), 'longtask',
 *     'event' (Event Timing), 'element' (Element Timing).
 *   - Per-interaction INP: longest event duration that contains the click.
 *   - Maps each long animation frame to the CSS selector of the target via
 *     LoAF script attribution (when available) and the offending event target.
 *
 * Output:
 *   - analyses/cwv-attribution/<urlhash>.json — structured trace
 *   - analyses/cwv-attribution/<urlhash>.md   — human-readable report,
 *     headline = top 5 INP-leaking components, with the script URL/selector
 *     responsible for each long task.
 *
 * Usage:
 *   bun run scripts/cwv-by-component.ts \
 *     --rep-set analyses/representative-urls.json \
 *     [--output analyses/cwv-attribution/] \
 *     [--profile mobile|desktop]   (default mobile)
 *     [--cpu-throttle 4]           (CDP CPU throttle multiplier; default 4)
 *     [--network slow4g|fast3g|none]  (default slow4g)
 *     [--selectors analyses/component-selectors.json]
 *
 * --selectors file (optional) overrides the default per-template interaction map:
 *   {
 *     "hero_cta":    "[data-component=hero] [data-cta=primary], a.btn-hero",
 *     "plan_card":   "[data-component=pricing-plan]",
 *     "billing_toggle": "[data-component=billing-toggle]",
 *     "faq_item":    "[data-component=faq] details > summary"
 *   }
 *
 * Exit codes: 0 success; 2 missing args; 6 if any URL has > 5 interactions exceeding 200ms.
 */

import { chromium } from "playwright";
import { createHash } from "node:crypto";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";

const args = parseArgs(Bun.argv.slice(2));
const repSet = args["--rep-set"] ?? "analyses/representative-urls.json";
const outDir = args["--output"] ?? "analyses/cwv-attribution/";
const profile = args["--profile"] ?? "mobile";
const cpuThrottle = Number(args["--cpu-throttle"] ?? 4);
const network = args["--network"] ?? "slow4g";
const selectorsPath = args["--selectors"];

await mkdir(outDir, { recursive: true });

const DEFAULT_SELECTORS = {
  hero_cta: '[data-component="hero"] [data-cta="primary"], header a.btn, a[href*="signup"], button:has-text("Get started"), button:has-text("Start free")',
  plan_card: '[data-component="pricing-plan"], [class*="pricing"] [class*="card"]',
  billing_toggle: '[data-component="billing-toggle"], [role="switch"], button:has-text("Yearly"), button:has-text("Monthly")',
  faq_item: '[data-component="faq"] summary, details summary, [class*="faq"] [role="button"]',
} as const;

const selectors = selectorsPath
  ? { ...DEFAULT_SELECTORS, ...(JSON.parse(await Bun.file(selectorsPath).text())) }
  : DEFAULT_SELECTORS;

const rep = JSON.parse(await Bun.file(repSet).text()) as {
  urls: Array<{ url: string; template?: string }>;
};

const browser = await chromium.launch();

let badUrls = 0;
let failedUrls = 0;
for (const u of rep.urls) {
  const hash = createHash("sha1").update(u.url).digest("hex").slice(0, 12);
  try {
    const result = await profileOne(u.url);
    await Bun.write(join(outDir, `${hash}.json`), JSON.stringify(result, null, 2));
    await Bun.write(join(outDir, `${hash}.md`), renderMarkdown(u.url, u.template, result));
    if (result.interactions.filter((i) => i.duration > 200).length > 5) badUrls++;
    process.stdout.write(`✓ ${u.url} INP_max=${result.inp_max}ms longTasks=${result.long_tasks.length}\n`);
  } catch (err) {
    failedUrls++;
    process.stdout.write(`✗ ${u.url} — ${(err as Error).message}\n`);
  }
}

await browser.close();
process.exit(badUrls > 0 || failedUrls > 0 ? 6 : 0);

async function profileOne(url: string) {
  const ctx = await browser.newContext(
    profile === "desktop"
      ? { viewport: { width: 1366, height: 900 } }
      : {
          viewport: { width: 390, height: 844 },
          deviceScaleFactor: 2,
          isMobile: true,
          hasTouch: true,
          userAgent:
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
        },
  );
  const page = await ctx.newPage();
  try {
  const cdp = await ctx.newCDPSession(page);
  if (cpuThrottle > 1) await cdp.send("Emulation.setCPUThrottlingRate", { rate: cpuThrottle });
  if (network === "slow4g") {
    await cdp.send("Network.emulateNetworkConditions", {
      offline: false,
      latency: 150,
      downloadThroughput: (1.6 * 1024 * 1024) / 8,
      uploadThroughput: (750 * 1024) / 8,
    });
  } else if (network === "fast3g") {
    await cdp.send("Network.emulateNetworkConditions", {
      offline: false,
      latency: 562,
      downloadThroughput: (1.6 * 1024 * 1024) / 8,
      uploadThroughput: (750 * 1024) / 8,
    });
  }

  await page.addInitScript(() => {
    (window as any).__perfBuffer = {
      loaf: [] as any[],
      longtasks: [] as any[],
      events: [] as any[],
      elements: [] as any[],
    };
    const supports = (PerformanceObserver as any).supportedEntryTypes ?? [];
    const observe = (type: string, sink: any[]) => {
      try {
        new PerformanceObserver((list) => {
          for (const e of list.getEntries()) sink.push(e.toJSON());
        }).observe({ type, buffered: true } as any);
      } catch {
        /* type not supported on this browser */
      }
    };
    if (supports.includes("long-animation-frame")) observe("long-animation-frame", (window as any).__perfBuffer.loaf);
    observe("longtask", (window as any).__perfBuffer.longtasks);
    observe("event", (window as any).__perfBuffer.events);
    if (supports.includes("element")) observe("element", (window as any).__perfBuffer.elements);
  });

  await page.goto(url, { waitUntil: "networkidle", timeout: 30000 });

  const interactions: Array<{
    label: string;
    selector: string;
    duration: number;
    target_outer_html: string;
    timestamp: number;
  }> = [];

  const tries: Array<[string, string]> = [
    ["hero_cta", selectors.hero_cta],
    ["plan_card", selectors.plan_card],
    ["billing_toggle", selectors.billing_toggle],
    ["faq_item", selectors.faq_item],
  ];

  for (const [label, sel] of tries) {
    // If a previous interaction caused navigation, subsequent locators will be
    // on a different page; skip rather than fail spuriously.
    if (page.url() !== url) {
      try {
        await page.goto(url, { waitUntil: "networkidle", timeout: 30000 });
      } catch {
        break;
      }
    }
    const loc = page.locator(sel).first();
    const exists = (await loc.count().catch(() => 0)) > 0;
    if (!exists) continue;
    // t0 must be in the page's time base (performance.now()), not Date.now(),
    // because PerformanceObserver entries (event timing) use DOMHighResTimeStamp
    // relative to navigationStart. Mixing time bases makes the filter below
    // always fail (epoch ms vs page-relative ms).
    const t0 = (await page.evaluate(() => performance.now()).catch(() => 0)) as number;
    const wallClock = Date.now();
    try {
      if (label === "plan_card") {
        await loc.hover({ timeout: 3000 });
      } else {
        await loc.scrollIntoViewIfNeeded({ timeout: 3000 });
        await loc.click({ timeout: 3000, trial: false });
      }
      // wait for any synchronous heavy work to land
      await page.waitForTimeout(300);
    } catch {
      continue;
    }
    const outer = await loc.evaluate((el) => (el as HTMLElement).outerHTML.slice(0, 200)).catch(() => "");
    const evts = (await page.evaluate(
      (since) =>
        ((window as any).__perfBuffer.events as any[]).filter(
          (e) => e.startTime + e.duration >= since && /click|pointer|touch|keydown/.test(e.name),
        ),
      t0,
    ).catch(() => [] as any[])) as any[];
    const dur = evts.reduce((m, e) => Math.max(m, e.duration), 0);
    interactions.push({
      label,
      selector: sel,
      duration: Math.round(dur),
      target_outer_html: outer,
      timestamp: wallClock,
    });
  }

  const buf = await page.evaluate(() => (window as any).__perfBuffer);

  // Group LoAFs by attributed script URL
  const loafByScript = new Map<string, { count: number; total_blocking: number; max_dur: number; samples: any[] }>();
  for (const f of buf.loaf ?? []) {
    const scripts: any[] = (f.scripts ?? []) as any[];
    for (const s of scripts) {
      const k = s.invokerType ? `${s.invokerType}:${s.sourceURL || s.invoker || "(inline)"}` : (s.sourceURL || s.name || "(inline)");
      const e = loafByScript.get(k) ?? { count: 0, total_blocking: 0, max_dur: 0, samples: [] };
      e.count++;
      e.total_blocking += Number(s.duration ?? 0);
      e.max_dur = Math.max(e.max_dur, Number(s.duration ?? 0));
      if (e.samples.length < 3) e.samples.push({ frame_dur: f.duration, script_dur: s.duration, function: s.functionName });
      loafByScript.set(k, e);
    }
  }
  const top_loaf_scripts = [...loafByScript.entries()]
    .map(([script, v]) => ({ script, ...v }))
    .sort((a, b) => b.total_blocking - a.total_blocking)
    .slice(0, 10);

  // INP_max
  const inp_max = (buf.events ?? [])
    .filter((e: any) => /click|pointer|touch|keydown/.test(e.name))
    .reduce((m: number, e: any) => Math.max(m, e.duration), 0);

  // Top INP-leaking components (group interactions by label & take longest)
  const byLabel = new Map<string, number>();
  for (const i of interactions) {
    byLabel.set(i.label, Math.max(byLabel.get(i.label) ?? 0, i.duration));
  }
  const top_components = [...byLabel.entries()]
    .map(([label, duration]) => ({ label, duration }))
    .sort((a, b) => b.duration - a.duration)
    .slice(0, 5);

  return {
    url,
    profile,
    cpu_throttle: cpuThrottle,
    network,
    captured_at: new Date().toISOString(),
    inp_max: Math.round(inp_max),
    long_tasks: buf.longtasks ?? [],
    long_animation_frames: buf.loaf ?? [],
    element_timing: buf.elements ?? [],
    interactions,
    top_components,
    top_loaf_scripts,
  };
  } finally {
    await page.close().catch(() => {});
    await ctx.close().catch(() => {});
  }
}

function renderMarkdown(url: string, template: string | undefined, r: any): string {
  const lines: string[] = [];
  lines.push(`# CWV component attribution — ${url}`);
  if (template) lines.push(`Template: ${template}`);
  lines.push(`Profile: ${r.profile} · CPU x${r.cpu_throttle} · Network ${r.network}`);
  lines.push(`Captured: ${r.captured_at}`);
  lines.push(``, `## Headline`, ``);
  lines.push(`- INP (max event duration this session): **${r.inp_max} ms**`);
  lines.push(`- Long tasks (>50ms main-thread): **${r.long_tasks.length}**`);
  lines.push(`- Long animation frames: **${r.long_animation_frames.length}**`);
  lines.push(``, `## Top 5 INP-leaking components`, ``);
  if (r.top_components.length === 0) {
    lines.push(`(no interactions exceeded the noise floor)`);
  } else {
    lines.push(`| # | Component | Duration |`);
    lines.push(`|---|-----------|---------:|`);
    r.top_components.forEach((c: any, i: number) =>
      lines.push(`| ${i + 1} | ${c.label} | ${c.duration} ms |`),
    );
  }
  lines.push(``, `## Top scripts blocking the main thread (LoAF attribution)`, ``);
  if (r.top_loaf_scripts.length === 0) {
    lines.push(`(no LoAF data — browser may not support long-animation-frame, or no slow frames in this run)`);
  } else {
    lines.push(`| Script | Frames | Total ms | Max ms |`);
    lines.push(`|--------|-------:|---------:|-------:|`);
    for (const s of r.top_loaf_scripts) {
      lines.push(`| ${s.script} | ${s.count} | ${Math.round(s.total_blocking)} | ${Math.round(s.max_dur)} |`);
    }
  }
  lines.push(``, `## Interactions executed`, ``);
  for (const i of r.interactions) {
    lines.push(`- **${i.label}** (\`${i.selector}\`) — ${i.duration} ms`);
    lines.push(`  - Target: \`${(i.target_outer_html || "").replace(/\n/g, " ")}\``);
  }
  lines.push(``, `## Recommendations`, ``);
  for (const c of r.top_components) {
    if (c.duration > 200) lines.push(`- [${c.label}] >200ms INP — split JS handlers, defer hydration, or replace heavy library on this component.`);
    else if (c.duration > 100) lines.push(`- [${c.label}] 100-200ms — improve before launch (target <100ms).`);
  }
  return lines.join("\n") + "\n";
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
