# subagent: cwv-collector

Role: Phase 1 Core Web Vitals snapshot. Reconcile **field data** (CrUX) and **lab data** (Lighthouse) against the same representative URL set so Phase 3 can attribute regressions to specific components rather than guess.

See [PHASE-1-DISCOVERY](../references/PHASE-1-DISCOVERY.md), kernel Axiom 5, [NEXTJS-PATTERNS](../references/NEXTJS-PATTERNS.md).

## Inputs

- `analyses/representative-urls.json` — one URL per template family.
- CrUX API key (or PSI API key as fallback; PSI wraps CrUX with lab augmentation).
- Tier (`T1 | T2 | T3 | T4`) — gates the depth of component-attribution work.
- `scripts/cwv-check.ts` (Lighthouse runner) and `scripts/cwv-by-component.ts` (component INP attribution).

## Tasks

1. **CrUX field data, per URL.** For each URL in the representative set, call the CrUX History API (28-day rolling, 6 collection periods if available) and the current-snapshot endpoint. Persist:
   - `analyses/crux/<urlhash>.history.json` — phone + desktop, LCP / INP / CLS / TTFB / FCP percentiles + good / NI / poor distribution.
   - `analyses/crux/<urlhash>.snapshot.json` — most recent period.
2. **CrUX origin fallback.** Many SaaS URLs do not have URL-level entries (insufficient traffic). For each URL with no entry, fall back to the **origin-level** record and tag the file `source: "origin"`. If origin also has no record, write `source: "none"` and downgrade any later confidence claims for that URL accordingly.
3. **Lighthouse mobile profile, per URL.** Run `bun run scripts/cwv-check.ts --rep-set <path> --profile mobile --emulate "Moto G Power" --throttle 4G --runs 3 --output analyses/lighthouse/`. Median of three. Persist full Lighthouse JSON + a normalized summary row per URL.
4. **Lighthouse desktop profile.** Same, `--profile desktop`, for templates that index desktop-first (docs, dashboards). Persist alongside.
5. **Component-attribution INP.** For every template whose CrUX **p75 INP > 200 ms** (or origin > 200 ms when URL data is missing), run `bun run scripts/cwv-by-component.ts --url <url> --interactions <list> --output analyses/cwv-attribution/<urlhash>.json`. The script drives Playwright through realistic interactions (open menu, click CTA, expand FAQ, dismiss consent banner) and bins the long-task time by source frame, script URL, and React component (via the `__REACT_DEVTOOLS_GLOBAL_HOOK__` mark + perf entry correlation).
6. **Reconcile lab vs field.** Build `analyses/cwv-summary.md` with one row per representative URL:

```
URL | template | CrUX LCP p75 | CrUX INP p75 | CrUX CLS p75 | LH LCP | LH TBT | LH CLS | source(field) | INP-leading-component | confidence
```

   - When lab and field disagree by > 30 %, flag the URL — usually means lab device profile mis-matches real-user mix, or interactions captured in lab are not representative.
7. Mark every URL whose **INP p75 > 200 ms** as a Phase 3 priority and seed an audit-issue stub.
8. Append API + Lighthouse runs to `analyses/source-log.md`.

## Output

```
analyses/crux/
  <urlhash>.history.json
  <urlhash>.snapshot.json
analyses/lighthouse/
  <urlhash>.mobile.json
  <urlhash>.mobile.summary.json
  <urlhash>.desktop.json          # where applicable
analyses/cwv-attribution/
  <urlhash>.json                  # only for INP > 200 ms templates
analyses/cwv-summary.md
```

## Done when

- Every representative URL has a CrUX entry tagged `source: "url" | "origin" | "none"`.
- Every representative URL has a 3-run-median Lighthouse mobile run.
- Every template with field INP p75 > 200 ms has a component-attribution file naming the leading culprit (chart lib, consent banner, marketing-CRM widget, hydration cost on a hero, third-party script).
- `cwv-summary.md` flags every lab/field disagreement > 30 %.
- The summary distinguishes a baseline target (INP < 200 ms p75) from a competitive target (INP < 150 ms p75 on commercial templates).

## Anti-patterns

- Quoting Lighthouse `score_0_1000` as "the INP" — Lighthouse reports TBT in the lab; INP is field-only.
- Using URL-level CrUX without checking it actually has data — many SaaS marketing pages will silently fall through to origin.
- Running Lighthouse desktop on a mobile-traffic site and reporting it as the headline number.
- Attributing INP to "React" generically without binning long tasks to a specific component or script URL.
- Skipping the consent banner in the interaction script — it is frequently the dominant INP contributor on EU traffic.
- Not capturing TTFB — slow TTFB silently caps LCP, and the fix lives in cache rules / data fetch, not the page.
