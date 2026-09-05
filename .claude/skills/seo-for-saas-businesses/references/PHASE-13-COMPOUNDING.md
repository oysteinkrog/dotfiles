# PHASE 13 — COMPOUNDING WINS

Goal: a fresh agent reviews the live site and the SEO plan looking for high-leverage moves prior phases missed.

## When

- After Phase 12 verifies the program shipped clean.
- Quarterly thereafter on T3+ programs.

## Use `/idea-wizard` (preferred) or fallback prompt

```
Agent({
  description: "compounding wins ideation",
  subagent_type: "Explore",
  prompt: "<see subagents/compounding-ideator.md>"
})
```

## Sweep dimensions

### Programmatic opportunities the dataset already supports

- Inventory the data already in the SaaS (integrations, customer logos with permission, locations, product features, templates, examples, public benchmarks, anonymized customer outcomes).
- For each: is there a candidate template family with real per-page differentiation? Run through [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md) before recommending.

### Missing schema types

- `Course` for an academy / certification program.
- `Dataset` only for a real public benchmark, research output, or downloadable/queryable dataset; track as Dataset Search / entity clarity unless current Google docs confirm a richer Search surface for the use case.
- `Event` for live webinars, conferences, user groups.
- `JobPosting` on careers pages.
- `HowTo` only after checking the current docs for the target region / vertical; do not treat it as a generic rich-result tactic.
- `Review` only on real, visible, moderated review surfaces.
- `BreadcrumbList` on any page that has visible breadcrumbs and is missing schema.

### Fresh ranking-system signals

Read Google Search Central blog within last 90 days. Any new signal, change, or guidance? Add to `analyses/source-log.md` with date and propose program adjustment.

### Content-decay candidates

From `analyses/content-inventory.md` cross-referenced with GSC position trend:
- Pages that ranked top 3 a year ago and are now 5–15.
- Pages with stale screenshots, prices, claims, or examples.
- Pages with broken outbound sources.
- Pages cannibalized by newer content.

For each, decide: refresh, merge, redirect, noindex, or remove.

### Competitive moats

Linkable-asset gaps competitors have not filled:
- Original-data category nobody has surveyed in the last 18 months.
- Free tool that solves a narrow problem the SaaS is uniquely positioned to provide.
- Definitive guide for a query family with weak top-10 results.

### AI Overview / ChatGPT / Perplexity citation gaps

For priority queries where the SaaS is *not* cited but a competitor is:
- What does the cited page have that the SaaS's page lacks? (3+ unique data points; better passage extractability; better entity consistency; specific schema; better source / author signals.)
- Smallest edit to win citation?
- Was the answer assembled from query fan-out? List the likely subqueries: pricing proof, security / compliance proof, migration friction, integrations, limitations, screenshots / demos, and next-step action.
- Is the current metric source honest? GSC Web data can show blended search movement; citation presence still needs a manual / semi-automated log.

### Underutilized search surfaces

- Image search: are crawlable, original images present on priority pages?
- Video search: any concept that benefits from a 2-minute walkthrough?
- News / Top Stories: is there a live-events angle?
- Discover: any feature-rich, story-strong content that could be eligible?

## Output

`deliverables/compounding-backlog.md` — prioritized backlog with EV estimate, effort, owner.

```md
# Compounding backlog (2026-Q2)

## High-leverage (ship next quarter)

### CW-001: Add `Course` schema to academy
- EV: +2k organic clicks/mo (likely)
- Effort: hours
- Owner: engineering
- Hypothesis: academy pages currently have no schema; competitors with `Course` get rich results
- Tracking: GSC enhancement report; impressions on academy pages

### CW-002: Refresh top-10 declining cluster (cluster X)
- EV: recover ~30% of lost clicks within 90 days (likely)
- Effort: weeks (per-page rewrites)
- Owner: cluster-X writer
- Hypothesis: pages in cluster X decayed because product UI changed; screenshots and feature descriptions stale
- Tracking: position trend; clicks delta

### CW-003: Build "SaaS pricing benchmark" linkable asset
- EV: 20 referring domains over 6 months (hypothesis)
- Effort: weeks (data + design + outreach)
- Owner: marketing + data
- Hypothesis: query family is high-volume; no recent original-data piece in top 10

## Medium-leverage (next quarter or two)
...

## Low-leverage / experimental
...
```

The user can `/schedule` background agents to evaluate progress in 60 / 90 / 180 days.

## Anti-patterns

- Rebuilding work prior phases already covered.
- Recommending programmatic templates without running [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md).
- Recommending stale tactics (HowTo rich results, FAQ commercial-page schema, exact-match domains, etc.).
- Estimating AI-citation lift from GSC Web data alone.
- Recommending `llms.txt` or AI-only markup as the core AI-visibility strategy instead of extractable evidence and crawlable text.
- Treating the backlog as a set of "must-do"s instead of an EV-ranked menu the user picks from.
- Not estimating EV — without it, the backlog is just a list.
