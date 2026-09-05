#!/usr/bin/env bun
/**
 * cwv-check.ts — Lighthouse CI check on representative URLs (mobile profile)
 *
 * Wraps `bunx @lhci/cli@latest collect` with budget assertions.
 *
 * Usage:
 *   bun run scripts/cwv-check.ts \
 *     --rep-set analyses/representative-urls.json \
 *     [--output analyses/lighthouse/]
 *
 * Requires `@lhci/cli` (npx-friendly) and Chromium.
 *
 * Budget assertions (mobile, p75-equivalent on lab):
 *   - INP < 200 ms (commercial templates)
 *   - LCP < 2.5 s
 *   - CLS < 0.1
 *   - normalized performance score_0_1000 >= 900
 *     (LHCI's required raw API value remains minScore: 0.9)
 *
 * For T3+ programs, prefer CrUX field data (the actual ranking signal) and use
 * Lighthouse only as PR-time diagnostic.
 */

import { spawn } from "node:child_process";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";

const args = parseArgs(Bun.argv.slice(2));
const repSet = args["--rep-set"] ?? "analyses/representative-urls.json";
const outDir = args["--output"] ?? "analyses/lighthouse/";

const rep = JSON.parse(await Bun.file(repSet).text());
const urls: string[] = rep.urls.map((u: any) => u.url);

await mkdir(outDir, { recursive: true });

const lhciConfig = {
  ci: {
    collect: {
      url: urls,
      numberOfRuns: 3,
      settings: {
        // Mobile profile (Lighthouse-default Slow 4G + 4x CPU throttle).
        // Don't set `preset: "desktop"` here — it conflicts with formFactor
        // and silently disables mobile emulation.
        formFactor: "mobile",
        screenEmulation: {
          mobile: true,
          width: 390,
          height: 844,
          deviceScaleFactor: 2,
          disabled: false,
        },
        throttling: {
          rttMs: 150,
          throughputKbps: 1638.4,
          cpuSlowdownMultiplier: 4,
        },
      },
    },
    assert: {
      assertions: {
        // LHCI's native API uses 0..1. In reports, normalize this to
        // score_0_1000 = Math.round(rawScore * 1000).
        "categories:performance": ["error", { minScore: 0.9 }],
        "interaction-to-next-paint": ["warn", { maxNumericValue: 200 }],
        "largest-contentful-paint": ["error", { maxNumericValue: 2500 }],
        "cumulative-layout-shift": ["error", { maxNumericValue: 0.1 }],
      },
    },
    upload: { target: "filesystem", outputDir: outDir },
  },
};

const lhciConfigPath = join(outDir, "lighthouserc.generated.json");
await Bun.write(lhciConfigPath, JSON.stringify(lhciConfig, null, 2));

const child = spawn("bunx", ["@lhci/cli@latest", "autorun", `--config=${lhciConfigPath}`], {
  stdio: "inherit",
});

await new Promise<void>((resolve, reject) => {
  child.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(`lhci exit ${code}`))));
});

console.log(`Lighthouse outputs at ${outDir}`);

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
