# KPI target sheet — `<saas name>`

Per-tier KPI targets used by Phase 8 to set what "good" looks like. Drives the weekly + monthly reports and the Day-90 review. Targets are *bounded ranges*, not single numbers — single numbers invite optimization toward the metric and away from the underlying outcome.

- **Tier**: `<T1 | T2 | T3 | T4>` (per [TIER-ROUTING](../references/TIER-ROUTING.md))
- **Owner**: `<analytics owner>`
- **Sponsor**: `<exec>`
- **Baseline date**: `<YYYY-MM-DD>`
- **Recheck cadence**: targets re-baselined every quarter; outcomes reviewed weekly + monthly

## Sheet structure

One row per metric. Targets are deltas from baseline unless absolute thresholds (CWV) apply.

| Metric | Baseline | 30-day target | 90-day target | 180-day target | Primary source | Owner | Recheck cadence |
|---|---|---|---|---|---|---|---|

## Generic metric rows (apply to all tiers)

| Metric | Baseline | 30-day | 90-day | 180-day | Primary source | Owner | Recheck |
|---|---|---|---|---|---|---|---|
| Indexed-page count by sitemap segment | `<n per segment>` | hold or +5 % per segment with intent to grow | +10–20 % | +20–40 % | GSC `Indexed pages` per sitemap | `<owner>` | weekly |
| Total clicks (GSC) | `<n>` | +0 to +10 % (foundation period) | +15–35 % | +40–80 % | GSC | `<owner>` | weekly |
| Total impressions (GSC) | `<n>` | +5–15 % | +20–40 % | +50–100 % | GSC | `<owner>` | weekly |
| Branded share (clicks) | `<%>` | hold (don't cannibalize brand) | hold | hold | GSC, `branded` filter | `<owner>` | monthly |
| Organic-to-trial CR | `<%>` | hold | +5–15 % rel. | +15–30 % rel. | GA4 + product analytics | `<owner>` | monthly |
| INP p75 by template | `<ms>` | < 200 ms commercial templates | < 200 ms all priority templates | < 150 ms commercial templates | CrUX + Lighthouse CI | engineering | weekly |
| LCP p75 by template | `<ms>` | < 2.5 s commercial | < 2.5 s all priority | < 2.0 s commercial | CrUX | engineering | weekly |
| CLS p75 by template | `<n>` | < 0.10 all priority | < 0.10 all | < 0.08 commercial | CrUX | engineering | weekly |
| GSC enhancement-error count | `<n>` | -50 % | 0 critical | 0 | GSC enhancements | engineering | weekly |
| AI-Overview citation count (tracked queries) | `<n>` | establish baseline | +20–50 % vs baseline | +50–100 % | `analyses/ai-citations.csv` | content + analytics | weekly |
| Referring domains delta (90d) | `<n>` | +0 to +5 | +10–25 | +30–60 | Ahrefs / Semrush / GSC links | marketing | monthly |

## Tier-calibrated overlays

T1 has thinner data; later-tier targets get more aggressive on AI visibility, multi-region, and programmatic gates.

<details>
<summary><strong>T1 — Pre-launch / Pre-PMF</strong></summary>

- Skip AIO citations until URL count > 20.
- Total clicks 90-day target: any positive YoY growth — magnitudes are noise at this volume.
- INP < 200 ms p75 on home + pricing within 30 days; commercial templates within 90 days.
- Indexed-page count: 100 % of submitted (e.g. 8/8) by Day 30.
- Skip referring-domains target.

</details>

<details>
<summary><strong>T2 — Early growth</strong></summary>

Generic table applies. Additionally:

- AI-Overview citations: target 1–3 cited URLs across tracked queries by Day 90.
- Referring domains: +5–15 unique by Day 90 (one linkable asset).
- Programmatic templates: not yet — focus on cluster depth.

</details>

<details>
<summary><strong>T3 — Scaled</strong></summary>

Generic table applies, with these additions:

| Metric | 30-day | 90-day | 180-day | Source |
|---|---|---|---|---|
| Programmatic indexed share | hold | <programmatic class="" indexed=""> ≤ 60 % of total | hold or grow with conv-bearing pages only | sitemap by segment |
| Server-log Googlebot fetches per priority template | establish | +20 % weekly fetches on priority templates | maintain | log analysis |
| AI-citation share-of-voice on top 50 queries | establish | 10–25 % | 25–40 % | `analyses/ai-citations.csv` |
| Lifecycle-page conversion attribution | establish | docs / status / security pages drive `<n>` trials/month | grow with cohort | GA4 + product |

Programmatic kill-switch test passed within 30 days of any programmatic launch.

</details>

<details>
<summary><strong>T4 — Enterprise / Mature</strong></summary>

| Metric | 30-day | 90-day | 180-day | Source |
|---|---|---|---|---|
| Impressions YoY by segment | no segment in sustained decline | no segment YoY < -5 % | every segment YoY ≥ +5 % | GSC + analytics |
| AI-Overview share-of-voice across major platforms | establish multi-platform | 25–40 % share on category | 40–55 % | `analyses/ai-citations.csv` |
| International / locale share | hold | grow per active locale | per-locale YoY ≥ +5 % | GSC by country |
| Multi-product cannibalization incidents | log | 0 unresolved > 30d | 0 unresolved > 14d | cannibalization map |
| Brand-demand index (branded query volume) | establish | +5–10 % | +10–20 % | GSC + Trends |

This skill operates as coordinator/QA. Targets per business unit / locale rather than aggregate.

</details>

## Reading the sheet

- **Hit the 30-day target** = foundation work didn't regress; refresh delta is showing up.
- **Miss the 30-day target** = check `seo-changelog.md` for shipped changes; verify GSC + GA4 export integrity; check for indexation drop or core-update overlap before concluding "the work didn't work".
- **Hit the 90-day target** = compounding cadence; move into [PHASE-13-COMPOUNDING](../references/PHASE-13-COMPOUNDING.md).
- **Miss the 90-day target without diagnosis** = trigger [TRAFFIC-DROP-PLAYBOOK](../references/TRAFFIC-DROP-PLAYBOOK.md) before iterating.

## Annotation policy

Every materially shipped change ([PR-DESCRIPTION-TEMPLATE](PR-DESCRIPTION-TEMPLATE.md)) gets annotated in GSC + GA4 + `seo-changelog.md` with the recheck-by date. Without annotations the KPI delta cannot be attributed to anything specific and the sheet becomes decoration.

## Anti-patterns

- **Optimizing for one metric without the guardrail.** Shipping aggressive titles can move CTR but tank conversions; ship paired metrics.
- **Single-number targets.** Use ranges. "Clicks +25 %" optimizes the metric. "Clicks +15–35 % with branded share held and INP unchanged" optimizes the program.
- **Comparing absolute clicks across seasons.** Seasonality + year-over-year ([SEASONALITY-CALENDAR-TEMPLATE](SEASONALITY-CALENDAR-TEMPLATE.md)). YoY > MoM for any cyclical metric.
- **Setting AI-citation targets without the citation log running.** Build the surface before measuring it ([CITATION-TRACKING-CSV-SCHEMA](CITATION-TRACKING-CSV-SCHEMA.md)).
- **Targeting domain-rating / domain-authority numbers.** They're third-party proxies, not Google signals. Use referring-domain quality + topical relevance instead.
- **Not re-baselining at quarter boundaries.** A 90-day target that becomes the new baseline forever ratchets up against a moving denominator.

## Cross-references

- [TIER-ROUTING](../references/TIER-ROUTING.md), [PHASE-8-ANALYTICS](../references/PHASE-8-ANALYTICS.md), [WIRING-OBSERVABILITY](../references/WIRING-OBSERVABILITY.md)
- [MONTHLY-EXEC-TEMPLATE](MONTHLY-EXEC-TEMPLATE.md), [WEEKLY-REPORT-TEMPLATE](WEEKLY-REPORT-TEMPLATE.md), [90-DAY-PLAN-TEMPLATE](90-DAY-PLAN-TEMPLATE.md)
