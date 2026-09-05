# INP-DEEP-DIVE

## TOC

Why INP, not FID · Targets and ranking-risk framing · Common SaaS marketing-page offenders · Component-level INP attribution · RSC and `use server` boundaries · Strategies in priority order · CrUX vs Lighthouse · Measurement loop · Tier depth selectors · Anti-patterns · Cross-links

Interaction-to-Next-Paint is now load-bearing. Google and web.dev define **<=200 ms p75** as `good`, **200-500 ms p75** as `needs improvement`, and **>500 ms p75** as `poor`; Google also says Core Web Vitals are used by ranking systems. Do **not** turn third-party correlation studies into fixed position-loss claims unless the exact estimate is source-logged or measured in a first-party experiment. The hidden offender on SaaS marketing pages is almost always a *dashboard-tier component pattern leaking into a marketing route*.

Phase mappings: Phase 3 (audit), Phase 6 (fix in code), Phase 8 (CrUX field tracking), Phase 12 (post-deploy verification), Phase 13 (compounding hunt for next regression).

## Why INP, not FID

INP measures the *worst-percentile* interaction latency across the entire session, not just the first input. This catches:

- The plan toggle on `/pricing` taking 380 ms because `react-hook-form` re-validates the whole form.
- The expand-all click on `/changelog` recomputing markdown for 4,000 entries.
- The chat-widget bubble appearing on hover because Drift only loads its bundle then.
- The cookie banner "Manage preferences" click that bootstraps the consent SDK and triggers a 600 ms layout pass.

FID would have missed all four. INP catches all four. (`confirmed`)

## Targets and ranking-risk framing

| Threshold | Status | Operational stance |
|---|---|---|
| < 150 ms p75 | Competitive | Top-3 templates should target this on commercial routes |
| <= 200 ms p75 | "Good" / baseline | Official good threshold; keep commercial templates here before chasing minor content tweaks |
| 200-500 ms p75 | "Needs improvement" | Quality, conversion, and competitive risk; prioritize when the page is commercial or striking distance |
| > 500 ms p75 | "Poor" | Release-blocker for priority pages; investigate component-level causes before content expansion |

The thresholds come from web.dev / Chrome team and are `confirmed` as of the last verification. Any position-impact size comes from property-specific experiments or third-party CrUX-correlated studies and is `hypothesis` until logged per [VERIFICATION-FIRST](VERIFICATION-FIRST.md).

## Common SaaS marketing-page offenders

| Offender | How it leaks | Fix |
|---|---|---|
| Chart library imported in marketing layout | Recharts / Visx / D3 bundled into `app/(marketing)/layout.tsx` because a single page used it | Move to a per-page dynamic import; never put dataviz in the shared layout |
| Marketing CRM widget (HubSpot, Marketo) | Loads on first paint; runs forms validation + cookie sync | Defer to first user intent (focus on form, not page load) |
| Consent banner (OneTrust, Cookiebot) | Boots a 200–800 KB script before everything else; blocks main thread on "Manage" click | Render shell server-side; lazy-load preference panel only when opened |
| Animated hero (Framer Motion / GSAP / Lottie) | Mounts a heavy animation engine for one decorative loop | CSS-only animation; or static SVG; or load on intersection only |
| Plan toggle with Zustand / Redux for two booleans | Heavy state library bootstraps for trivial UI state | `useState` or URL query state |
| Copy-to-clipboard with autoload language packs | Prism / Shiki loads every grammar before the page is interactive | Only load grammars actually used per page; Shiki bundled grammars |
| Pre-mounted Drift / Intercom / Crisp | Chat widget script loads on first paint | Defer until scroll past hero, or until idle (`requestIdleCallback`) |
| Live YouTube embed | Embeds 2–3 MB of player JS for an above-fold demo | Use `lite-youtube-embed` or static thumbnail with click-to-load |
| Hubspot / Marketo form embed | Iframe + parent script + tracking on every page | Self-host the form; post to the API directly |
| Cookie-locale auto-detection on every nav | Middleware-driven locale detection with synchronous geo lookup | Cache result; lazy-detect; do not block paint |
| Sentry / FullStory / Heap session-replay | Replays init synchronously and sends all interactions | Lazy-init after first paint; sample aggressively on marketing pages |
| Tag manager auto-load of every tag | GTM ships hundreds of KB on every nav | Server-side GTM; or strict tag whitelist on marketing routes |

(`confirmed` for offender identification; specific bundle sizes vary)

## Component-level INP attribution

The browser exposes the long-task / interaction data via the Performance API. `scripts/cwv-by-component.ts` (referenced in SKILL) instruments:

```ts
// scripts/cwv-by-component.ts (sketch)
import { onINP } from "web-vitals/attribution";

onINP((metric) => {
  const attr = metric.attribution;
  console.log({
    value: metric.value,
    eventType: attr.eventType,
    eventTarget: attr.eventTarget, // CSS selector of element clicked
    inputDelay: attr.inputDelay,
    processingDuration: attr.processingDuration,
    presentationDelay: attr.presentationDelay,
    longAnimationFrameEntries: attr.longAnimationFrameEntries,
  });
});
```

Read the breakdown:

- **Input delay** high → main thread was already busy when the click arrived; usually a rogue script (analytics, consent, marketing CRM).
- **Processing duration** high → handler is doing too much synchronously; usually heavy state library or unmemoized React render.
- **Presentation delay** high → the post-handler render or layout is expensive; usually layout thrash, missing CSS containment, or heavy animation.

The `eventTarget` selector tells you *which component* on which route. Cross-reference with the React component tree (DevTools React profiler with the same interaction recorded) to land on the file.

## RSC and `use server` boundaries

In Next.js 16 App Router, the cleanest INP wins come from leaving interaction-cheap surfaces as Server Components and isolating the interactive island:

```tsx
// app/pricing/page.tsx — RSC, no JS shipped except the toggle island
import { PlanToggleIsland } from "./PlanToggleIsland";

export default async function PricingPage({ searchParams }) {
  const billing = (await searchParams)?.billing ?? "monthly";
  const plans = await getPlans(billing);
  return (
    <>
      <h1>Pricing</h1>
      <PlanToggleIsland initial={billing} />
      <PlanGrid plans={plans} />
    </>
  );
}
```

```tsx
// app/pricing/PlanToggleIsland.tsx
"use client";
import { useRouter, useSearchParams } from "next/navigation";

export function PlanToggleIsland({ initial }: { initial: string }) {
  const router = useRouter();
  const params = useSearchParams();
  return (
    <button
      onClick={() => {
        const next = initial === "monthly" ? "yearly" : "monthly";
        const sp = new URLSearchParams(params);
        sp.set("billing", next);
        router.push(`?${sp}`);
      }}
    >
      Toggle
    </button>
  );
}
```

URL-as-state moves work onto the server, eliminates client-state libs, and cuts INP because the toggle is a navigation event the framework already optimizes. (`confirmed` — Next.js team's recommended pattern for this case)

## Strategies in priority order

| Strategy | When | Cost |
|---|---|---|
| Dynamic import (`next/dynamic`) | Component is below-fold or not always needed | Small refactor |
| Lazy mount on intersection | Component only matters when user scrolls to it | `IntersectionObserver` + ref |
| Mount on user intent (hover / focus) | Form / chat widget / locale picker | Event listener + import |
| Defer to `requestIdleCallback` | Analytics, replay, marketing pixels | Schedule after idle |
| Move state to URL | Plan toggle, locale, filters | RSC + `useSearchParams` |
| Replace heavy lib with primitive | Framer Motion → CSS animation; Zustand → `useState` for trivial state | Refactor |
| Server-side GTM / consent | Tag manager / consent ships less to client | Infra (Vercel, GTM Server) |
| Code-split per route group | Marketing routes never need dashboard chunks | `app/(marketing)` vs `app/(app)` route groups; verify chunk graph |
| Ahead-of-time event handler attachment | Critical interactions (form submit) wired in static HTML | `next/script strategy="beforeInteractive"` for very specific cases |

## CrUX vs Lighthouse — field beats lab

Lighthouse runs in a controlled environment with deterministic CPU/network throttling. **CrUX is the actual ranking signal**: real user interactions across all devices and connections.

| When to use | Tool |
|---|---|
| Diagnosing a regression mid-PR | Lighthouse CI on the preview deploy |
| Validating a fix before deploy | Lighthouse CI + WebPageTest |
| Tracking ranking-grade INP | CrUX API (28-day rolling p75) |
| Investigating which interaction is slow on which device | Web Vitals Chrome extension or `web-vitals/attribution` in production |
| Per-component attribution | `scripts/cwv-by-component.ts` (Performance API) |

A page with Lighthouse `score_0_1000: 1000` (raw UI score 100) can still fail INP in CrUX if real users are on mid-tier Android devices clicking the consent banner. (`confirmed`)

## Measurement loop

1. **CrUX baseline** — fetch p75 INP for the representative URL set (Phase 1).
2. **Identify the worst template** — the chart-leaking one is usually the worst even if average INP looks fine.
3. **Capture interactions** — `web-vitals/attribution` in production for one week; build a histogram per component selector.
4. **Reproduce in a profile** — Chrome DevTools Performance with CPU 4× throttle on the slowest interaction; record.
5. **Identify the dominant cost** — input delay vs processing vs presentation.
6. **Apply the strategy** — pick from the table above.
7. **Measure with Lighthouse CI on preview** — confirm the lab number moved.
8. **Promote and watch CrUX** — the field number takes 28 days to fully reflect the change. Annotate in `seo-changelog.md`.
9. **Set a regression alarm** — Phase 8 dashboard alarm if any representative template's p75 INP crosses 200 ms.

## Tier depth selectors

| Tier | INP work |
|---|---|
| T1 | Lighthouse-only on the 5 commercial templates; fix obvious LCP offenders; INP not a blocker yet |
| T2 | CrUX baseline for top 20 URLs; component-level attribution for 1 worst-offending template; fix |
| T3 | Continuous CrUX; per-PR Lighthouse CI gate at 200 ms; per-template attribution; cwv-by-component in production |
| T4 | Per-release CWV regression dashboards; per-locale CrUX; per-device-class targeting; INP as a release gate |

## Anti-patterns

| Don't | Why | Do instead |
|---|---|---|
| "Optimize INP" by removing analytics | Breaks measurement; doesn't fix the root cause | Defer / sample / server-side GTM |
| Scroll-triggered "load everything now" hack | Just delays the cost; INP still bad once user interacts | Component-level lazy mounts |
| Add `will-change: transform` to every animated element | Promotes too many layers; memory pressure; main-thread cost | Targeted `will-change` only on actually-animating nodes |
| Replace Framer Motion sitewide without measuring | The cost may have been elsewhere; large refactor with no win | Profile first; replace where the data points |
| Trust Lighthouse `score_0_1000` as field INP | Lab and field can disagree by 100+ ms | CrUX / field data is the source of truth for CWV status; Lighthouse is a reproduction tool |
| Treat INP as one number for the site | Per-template variance is enormous (`/pricing` ≠ `/blog/post`) | Track per representative-URL-set element |
| Add `requestIdleCallback` and call it done | Browsers may never schedule it under load; fallback needed | Pair with timeout fallback or use `scheduler.postTask` where supported |
| Lazy-mount the LCP candidate | Trades INP improvement for LCP regression | Keep LCP candidate in static shell; lazy *below* it |
| `<Suspense>` everything | Streaming boundaries are not free; spinners hurt CLS and perceived performance | Suspense around legitimately deferrable subtrees only |
| Disable Sentry / Datadog session-replay site-wide | Loses production debug capability | Sample 0.1–1% on marketing; full on dashboard |
| One giant client component for the whole marketing page | Bundles ship; RSC benefits lost | Server components by default; islands only where interactive |
| Run consent SDK before paint | INP regression on every interaction post-banner | Block-aware consent gate; render shell, defer SDK to consent-needed event |
| Accept "vendor script blocks main thread" | Still costs you the ranking | Self-host where possible; otherwise `<script async>` + late init |

## Cross-links

- [NEXTJS-PATTERNS](NEXTJS-PATTERNS.md) — Next.js 16 cache components, RSC, image priority.
- [PHASE-3-TECHNICAL](PHASE-3-TECHNICAL.md) — INP as audit item; per-template attribution.
- [PHASE-8-ANALYTICS](PHASE-8-ANALYTICS.md) — CrUX wiring + Lighthouse CI in repo.
- [IMAGE-PERF-COOKBOOK](IMAGE-PERF-COOKBOOK.md) — LCP and CLS issues that often mask as INP.
- [PAGE-WEIGHT](PAGE-WEIGHT.md) — large HTML and main-thread JS budget.
- [TRAFFIC-DROP-PLAYBOOK](TRAFFIC-DROP-PLAYBOOK.md) — when CWV regressions cause traffic drops.
