# EDITORIAL-CALENDAR

## TOC

What goes on the calendar · Per-vertical seasonality patterns · Editorial cadence per cluster · Pre-publication crawl/index lead time · Refresh vs new · Calendar tool integrations · Owner assignment · Annual report/benchmark cycles · PR moments · Tier depth selectors · Anti-patterns · Cross-links

An editorial calendar that follows real demand, real product cycles, and real-world deadlines — not a content quota. The calendar is the queue that feeds Phase 4 (briefs + drafts) and Phase 7 (digital PR moments). Without it, content drifts into "publish what's easy this week" and decay outpaces refresh.

Phase mappings: Phase 2 (clusters feed seasonal content), Phase 4 (briefs scheduled), Phase 7 (PR moments aligned to refresh windows), Phase 8 (refresh KPIs), Phase 13 (decay sweep).

## What goes on the calendar

| Source | Cadence | Example |
|---|---|---|
| Seasonal demand | Per-vertical | "Q4 budget season" → security-comparison, ROI calculators (B2B SaaS) |
| Product launches | Per release | Changelog, blog post, doc updates, customer email |
| Industry events | Per conference | RSA / KubeCon / SIGMOD / SaaStr — pre-event piece + on-event piece |
| Compliance / policy deadlines | Per regulation | EU AI Act phases, GDPR cookie deprecation, FedRAMP reauth |
| Annual report cycles | Yearly | "State of <industry> 2027" — original-data hook |
| Fiscal-year events | Per quarter | End-of-quarter pricing updates, renewal-driven content |
| PR moments | Per opportunity | Funding announcement, partnership, customer milestone |
| Refresh deadlines | Per page | Screenshot ages > 6 mo; price claim ages > 90 d; benchmark ages > 12 mo |
| Migration / decay queue | Continuous | Pages losing position; pages with outdated claims |

The calendar is **not** "12 blog posts per quarter." It's "the next four weeks of *committed* slots, each tied to a real driver."

## Per-vertical seasonality patterns

| Vertical | Peak demand windows | Implications |
|---|---|---|
| B2B SaaS (general) | Q4 (Oct–Dec budget season); end of each quarter; mid-Jan (planning) | Plan-comparison + ROI content peaks; refresh pricing pages early Q4 |
| Dev-tool SaaS | Conference cycles (KubeCon, AWS re:Invent, GitHub Universe); release windows | Tutorials and integration guides timed to platform announcements |
| Compliance / GRC | Audit cycles; SOC 2 Type II window starts (~Jan, ~Jul); regulation deadline announcements | Surge in "<regulation> compliance" queries 30–60 days before deadlines |
| HR / Payroll SaaS | Open enrollment (Oct–Dec); fiscal-year-end (Dec–Jan); back-to-school | Content on benefits / payroll-tax / new-year timed to enrollment |
| FinOps / Cloud cost | Quarterly close; annual reviews | Calculator and benchmark content; "vs reserved instances" comparisons |
| Marketing / Sales SaaS | Pipeline-review season (Q4 → Q1); new-fiscal-year planning | "How to plan <X> for <next year>" peaks Q4 |
| Education / EdTech | Aug–Sep (back to school); Jan (resolution) | Cohort-based content; new-feature launches timed to semesters |
| Healthcare SaaS | HIPAA-renewal cycles; insurance open-enrollment (Oct–Dec) | Compliance-driven content; provider-onboarding |
| Ecommerce-supporting SaaS | BFCM (Nov); Prime Day (Jul); back-to-school | Surge in "<scaling tool> for Black Friday" |
| Gov / Public Sector | Fiscal year (Oct in US federal); RFP cycles | Long lead times; procurement-pack updates timed to RFP windows |

(`likely` for vertical patterns; `confirmed` only after running the GSC seasonal slice on the actual property.)

## Editorial cadence per cluster

Different clusters need different cadences. A standard pattern for a SaaS with three pillar clusters:

| Cluster type | New content cadence | Refresh cadence | Owner |
|---|---|---|---|
| Pillar (e.g. `/category/<core-pillar>`) | Quarterly major refresh | Monthly date check | Senior content / SME |
| Cluster page (e.g. `/<pillar>/<sub>`) | One per month per cluster | Quarterly refresh | Cluster writer |
| Comparison (`/<product>-vs-<competitor>`) | As competitors emerge | Quarterly (competitor changes) | Marketing + SME |
| Integration (`/integrations/<partner>`) | When new integration ships | When partner API changes | DevRel |
| Migration (`/migrate/<source>`) | When new source supported | Quarterly (partner export changes) | DevRel |
| Lifecycle (security, procurement, plans) | When triggered (audit, regulation, pricing) | Quarterly review | Owner-team |
| Editorial (blog) | Weekly or bi-weekly | Annual sweep | Editorial |
| Changelog | Per release | n/a | Engineering |
| Status / incidents | As-it-happens | n/a (history is permanent) | SRE |

## Pre-publication crawl / index lead time

| Asset type | Lead time before peak demand | Why |
|---|---|---|
| New cluster page (no priors) | 4–8 weeks | Crawl, indexation, cluster signal accumulation |
| New comparison page | 2–4 weeks | Faster: adjacent to existing pillar |
| Refresh of an existing page | 1–2 weeks | Re-crawl + re-evaluation; faster on high-authority sites |
| Programmatic batch | 14+ days *per stage* | Per [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md) |
| Lifecycle page (security, compliance) | 2–4 weeks | Often picks up branded queries fast |
| Time-sensitive press / news | Same day | Fast indexation but consider GSC URL inspection |

(`likely` — varies by site authority and crawl rate. Verify against actual GSC indexation latency for the property.)

Don't publish a "Black Friday Acme guide" on November 28. Publish on October 1 and refresh October 25.

## Refresh vs new — decision

| Signal | Action |
|---|---|
| Existing page ranking p4–10 for the target query | **Refresh** (striking-distance lift; faster gains) |
| Existing page exists but on wrong intent | **Refresh** with a re-targeted brief, OR consolidate into a new page and 301 |
| Existing page on right intent but stale (> 12 mo without claim review) | **Refresh** with new evidence + dated review banner |
| No existing page; query family has stable demand | **New** (write the brief into the calendar) |
| No existing page; query is event-driven / trending | **New** with a refresh schedule already declared |
| Two existing pages cannibalize | **Consolidate** (merge + 301; Phase 5) |
| Existing page decayed and not recoverable | **Sunset** — 410 or 301 to closest replacement |

The 80/20 rule: in most mature SaaS programs, refreshing existing top-50-impression pages outperforms publishing new pages by ~3:1 on incremental clicks per hour invested. (`likely`, varies by program maturity.)

## Calendar tool integrations

| Tool | When | Notes |
|---|---|---|
| Notion | Default for content teams; flexible | Per-row: status, owner, cluster, slug, brief link, target date, refresh date, evidence sources |
| Linear / Jira | Engineering-adjacent teams; PR-tracked | Tie content task to the implementing PR; owner = writer + reviewer |
| Sheets / Airtable | Cross-functional teams; non-technical contributors | Easier filtering than Notion for large catalogs |
| GitHub Issues + projects | Repo-native programs (this skill's default) | Use `seo` label + project board; aligns with the rest of the SEO program |
| beads / br | When SEO is part of a larger agentic workflow | Per [beads-workflow](../../beads-workflow) |

The tool matters less than the **fields**. Required fields:

```
slug
cluster
target_query (primary)
intent (informational / commercial / transactional / navigational)
owner (named human)
brief_link
draft_link
status (planned / drafting / review / published / refreshing / sunset)
publish_target (date)
last_refreshed (date)
next_refresh_due (date)
evidence_sources (links)
linked_pr (GitHub URL or Linear ID)
seo_changelog_id
```

## Owner assignment

| Role | What they own |
|---|---|
| Cluster lead | All pages within a cluster; brief approval; refresh trigger |
| Subject-matter expert | Technical correctness; review-before-publish gate |
| Editor | Slop check; brand voice; schema correctness |
| Writer | Brief → draft per [PHASE-4-CONTENT](PHASE-4-CONTENT.md) |
| SEO reviewer | Cannibalization check; metadata; internal links |
| Distribution lead | Promotion plan; PR angle; partner outreach |

Every calendar row needs a named human in each role. "Marketing team" is not an owner.

## Annual report / benchmark cycles

Original-data hooks are the highest-leverage editorial asset. Plan them as multi-quarter projects:

| Quarter | Activity |
|---|---|
| Q1 | Define methodology; gather data; draft framework |
| Q2 | Continued data collection; validate with 2–3 industry contacts |
| Q3 | Analysis; visualizations; report writing |
| Q4 | Launch + PR push (timed to industry conference if applicable); land coverage |

Always include: dataset definition, methodology page (`/methodology/<report>`), download CTA, embeddable charts, year-over-year refresh plan. Refresh the *same URL* each year unless year-specificity is the search intent. (`confirmed` — see canonical guide §11.)

## PR moments

Plan PR-driven content windows:

| Trigger | Asset | Lead time |
|---|---|---|
| Funding announcement | Updated About page; PR; investor list update | 2 weeks |
| Major customer launch | Customer story; case study; logo wall update | 4 weeks (with permission cycle) |
| Product launch | Launch blog; updated pricing if relevant; demo asset | 4 weeks |
| Partnership / integration | Co-marketing post; docs page; partner directory listing | 4 weeks |
| Industry award / certification | Updated trust hub; press page; sameAs profile sync | 1 week |
| Original research release | Methodology page + report + visualizations + outreach | 8–12 weeks |

## Tier depth selectors

| Tier | Calendar scope |
|---|---|
| T1 | A 4-week rolling list; 2–4 commercial pages prioritized; manual ownership in a single Notion / Sheet |
| T2 | Quarterly calendar; per-cluster cadence; refresh + new mix; named owners per cluster |
| T3 | Continuous calendar across pillars; integration with release calendar; quarterly content audit; assigned editorial team |
| T4 | Multi-locale calendar; multi-product calendar; programmatic refresh queues; calendar-as-code in repo |

## Anti-patterns

| Don't | Why | Do instead |
|---|---|---|
| "Publish 12 pieces per quarter" without driver | Output theatre; decay outpaces production | Each slot tied to demand / release / event / refresh |
| Schedule "BFCM guide" on November 25 | No time for indexation; misses peak | Publish 6+ weeks before; refresh 2 weeks before |
| Create a new page each year ("X best Y of 2026") | Splits authority across N URLs | Refresh the durable URL unless year-specific is the intent |
| Mix new + refresh under one column "publish date" | Refreshes get prioritized away when output pressure is on | Separate columns; separate queues; separate KPIs |
| Calendar with no owner column | Slots silently slip; no accountability | Named human per slot |
| Refresh defined as "update meta description" | Doesn't move ranking; minimal user value | Re-research, new evidence, new internal links, new schema mirror |
| Programmatic + editorial on the same calendar | Programmatic moves in batches; editorial in slots; conflate the cadences | Separate calendars; share owner roster only |
| Calendar drift after Q1 | Goal-setting in January, vibes in April | Quarterly recommit; tie to OKRs; report attainment |
| One person owns everything | Bottleneck; high bus factor | Cluster-owner model |
| No calendar at all | Content production is reactive | Even a 4-week rolling list beats none |
| Editorial calendar with no link to the seo-changelog | Future traffic moves are unattributable | Each publish date annotated in `seo-changelog.md` and GSC |

## Cross-links

- [PHASE-2-KEYWORD](PHASE-2-KEYWORD.md) — clusters that feed the calendar.
- [PHASE-4-CONTENT](PHASE-4-CONTENT.md) — brief format for each calendar slot.
- [PHASE-7-AUTHORITY](PHASE-7-AUTHORITY.md) — PR moment alignment.
- [PHASE-8-ANALYTICS](PHASE-8-ANALYTICS.md) — refresh KPIs.
- [PHASE-13-COMPOUNDING](PHASE-13-COMPOUNDING.md) — decay sweep feeds calendar.
- [LIFECYCLE-CONTENT](LIFECYCLE-CONTENT.md) — lifecycle pages have their own refresh triggers.
- [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md) — programmatic launches are scheduled via gates, not calendar slots.
- [PROOF-LIBRARY-OPS](PROOF-LIBRARY-OPS.md) — evidence to source for each scheduled brief.
