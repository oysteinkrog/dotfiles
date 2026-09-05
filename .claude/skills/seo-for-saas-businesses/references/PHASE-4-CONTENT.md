# PHASE 4 — ON-PAGE & CONTENT PRODUCTION

Goal: per-page brief + draft (or rewrite) that earns the SERP it targets, satisfies AI-citation eligibility, and avoids slop.

## Inputs

- Phase 2 cluster ownership map.
- Phase 3 metadata audit findings per template.
- SERP samples per query (`analyses/serp-snapshots/`).
- Trust assets inventory (Phase 7-pre).

## Per-page deliverable

```md
# <page slug>

## Brief
- Intent: <informational | commercial | transactional | navigational>
- Audience: <named ICP>
- Canonical URL: <url>
- Owner: <human name>
- Refresh cadence: <quarterly / on-product-change / etc>
- Page type: <pillar / cluster / pricing / comparison / integration / docs / etc>
- Primary entity: <named entity>
- Supporting entities: <list>
- Three-plus unique data points (citation eligibility):
  1. <data point with source/date>
  2. <data point with source/date>
  3. <data point with source/date>
- SERP analysis: <dominant features; what format wins>
- Internal links in: <list>
- Internal links out: <list>
- Schema type: <WebApplication / Article / Product / etc>
- Conversion goal: <primary CTA>
- Recheck-by: <date>

## Title + meta
- Title: <55–60 chars; intent-matched>
- Meta description: <150–160 chars; ad-copy quality; lead with outcome>
- H1: <matches title intent; not identical>

## Outline
- H2: ...
  - Direct answer (≤60 words, citation-eligible)
  - Depth
- H2: ...
- ...
- Final next-step CTA

## Draft
[full draft here, with inline citations and source links]

## QA
- [ ] Slop-check passed (`/de-slopify` or [SLOP-CHECKLIST](SLOP-CHECKLIST.md))
- [ ] All factual claims sourced
- [ ] Confidence labels per claim
- [ ] At least three unique data points visible without JS
- [ ] Brand voice fits
- [ ] If high-risk topic: [HIGH-RISK-GATE](HIGH-RISK-GATE.md) passed
```

## Brief-first

Never draft before the brief exists and the user (or owner) signs off. Briefs catch:

- Wrong page type for the query (article when SERP wants product / video / forum).
- Missing proof requirements.
- Cannibalization risk against an existing canonical owner.
- Conversion-path gaps (no clear CTA).
- Schema type misalignment (e.g. picking `Article` for a tool page).

## Per-cluster, not per-page, agent

The same agent that researched a cluster in Phase 2 writes its content in Phase 4. This preserves intent fidelity, avoids context loss between research and drafting, and produces consistent voice within a cluster.

`subagents/cluster-writer.md` runs once per cluster with the full Phase 2 cluster map and Phase 3 audit slice as context.

## SERP-format alignment

Match the asset to the dominant SERP feature for the target query (see [OPERATORS.md](OPERATORS.md) ⌖):

| SERP feature | Asset requirement |
|---|---|
| AI Overview present | Self-contained passages with three-plus unique data points |
| PAA present | H2 questions worded like the PAA examples; 60-word direct answers under each |
| Video pack | Embedded video + transcript; `VideoObject` schema |
| Image pack | Original screenshots/diagrams; descriptive alt; crawlable image URLs |
| Product / merchant | Accurate price/availability; `WebApplication`+`Offer` or `Product`; merchant-feed agreement |
| Local pack | Real local presence; LocalBusiness schema; service-area details |
| Forum / discussion | First-hand experience; named author; community signals |
| Featured snippet | One direct paragraph or step-list near the matching H2 |

## High-risk topics

Financial advice, legal claims, security architecture, health, compliance, employment, housing, civic decisions — all require [HIGH-RISK-GATE](HIGH-RISK-GATE.md) before indexable. Common in SaaS: anything compliance / SOC 2 / HIPAA / financial / legal-tech / healthcare-tech / fintech.

## AI citation pre-flight

For each page, run:

```bash
bun run scripts/ai-crawler-view.ts --url https://www.example.com/<slug> --as GPTBot
```

If the initial HTML does not contain the headline answer + at least three unique data points, the page is not citation-ready. Either fix rendering or restructure content.

## Anti-slop

Use `/de-slopify` if installed, otherwise [SLOP-CHECKLIST](SLOP-CHECKLIST.md). Common slop patterns to remove:

- "In today's fast-paced digital landscape…"
- Stacked superlatives ("game-changing", "revolutionary", "cutting-edge").
- Hedging ladders ("can be", "may help", "might offer").
- Three-of-a-kind generic adjectives ("efficient, scalable, reliable").
- Conclusion paragraphs that restate the introduction.
- "It's worth noting that…" filler.
- Bullet lists where every item starts with the same verb-of-the-month.
- "Whether you're X or Y, this guide will…"

## Content decay

Every page has a refresh cadence and a refresh trigger. Common triggers:

- Pricing changes.
- UI screenshots stale (UI redesign).
- Competitor change.
- New product feature.
- New regulation or compliance update.
- Annual benchmark cycle.
- Quote / source aging beyond 18 months.

Refresh updates the page, not just the date. Faking freshness is a documented anti-pattern.

## Output to Phase 6

Each completed brief + draft becomes one bead / GitHub issue tied to the Phase 6 PR `seo/content-<cluster>`.
