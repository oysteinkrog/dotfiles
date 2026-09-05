# TIER-ROUTING

Calibrate program depth to where the SaaS actually is. Mismatched tier = wasted effort or skipped fundamentals.

## Tier inputs

| Input | Source |
|---|---|
| ARR | User; Stripe / billing |
| Indexable URL count | `analyses/template-inventory.md` from Phase 1 |
| Organic traffic baseline | GSC last-90-day clicks |
| Team size | User |
| Stage | User (pre-launch / pre-PMF / growth / scale / mature) |
| Multi-region? | User |
| Multi-product? | User |
| UGC / marketplace? | User |
| Regulated vertical? | User |

## Tier definitions

### T1 — Pre-launch / Pre-PMF

| Trait | Value |
|---|---|
| ARR | < $1M |
| URLs | < 30 |
| Organic | minimal |
| Team | < 20 |

**Investment:** Phase 1 (lite — focus on product surfaces only), Phase 3 (lite — metadata, sitemap, robots, redirects only), Phase 4 (commercial pages: home, pricing, signup, security, about), Phase 6 (foundation PR), Phase 8 (wire GSC + GA4). Skip Phase 2 keyword universe; skip programmatic templates; skip Phase 7; skip Phase 9.

**Time budget:** 1 week.

**Exit criteria:** clean substrate, 5–10 commercial pages with intent-matched metadata, observability wired, IA documented for next stage.

### T2 — Early growth

| Trait | Value |
|---|---|
| ARR | $1M–$10M |
| URLs | 30–300 |
| Organic | growing, single-digit % of pipeline |
| Team | 20–80 |

**Investment:** full Phases 1, 3, 5, 6, 8, 11, 12. Phase 2 lite (one pillar, two clusters). Phase 4 prioritized to commercial + first content cluster. Phase 7 starts (one linkable asset). Phase 9 lite (1–2 title tests). Phase 13 once.

**Time budget:** 4–6 weeks initial pass + monthly Phase 8 review.

**Exit criteria:** organic share growing month-over-month, branded-vs-non-branded split tracked, INP < 200 ms p75 on commercial templates, schema validates on representative URLs, sitemap segments aligned with page types.

### T3 — Scaled

| Trait | Value |
|---|---|
| ARR | $10M–$100M |
| URLs | 300–5000 |
| Organic | meaningful pipeline contribution |
| Team | 80–500 |

**Investment:** full 13-phase pass with parallel subagents. Programmatic templates if and only if [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md) pass. Server-log analysis on. Lifecycle content (Phase 4 + dedicated docs/support pass). Cross-team coordination via beads.

**Time budget:** 8–12 weeks initial pass + continuous Phase 8 + quarterly Phase 1, 3, 10, 13.

**Exit criteria:** organic primary growth channel by some metric (lead, trial, demo, signup), AI-Overview citation tracked, log-file analysis weekly, programmatic templates contributing without dragging the rest of the site.

### T4 — Enterprise / Mature

| Trait | Value |
|---|---|
| ARR | $100M+ |
| URLs | 5000+ |
| Organic | primary growth channel |
| Team | 500+, dedicated SEO team |

**Investment:** continuous program. Monthly Phase 8 cockpit. Quarterly Phases 1, 3, 10, 13. Ongoing Phases 4, 5, 6, 7, 9 in parallel. International / locale program. Programmatic governance and a kill-switch dashboard. Brand-demand workstream. Multi-product cannibalization map.

**Time budget:** dedicated team; this skill is a coordinator and quality reviewer, not a one-time pass.

**Exit criteria:** impressions and clicks growing year-over-year by segment; no segment in sustained decline; CWV passing for representative URL set; organic conversion rate within target band; AI-Overview share-of-voice tracked across major platforms.

## Complexity overlays (bump tier up regardless of revenue)

| Overlay | Effect |
|---|---|
| Multi-region / `hreflang` | +1 tier complexity in Phase 3, 5, 12 |
| UGC / marketplace inventory | +1 tier in Phase 3 (index discipline) and Phase 6 |
| Ecommerce-style merchant feeds | +1 tier; add merchant-feed agreement audit |
| Regulated vertical (health, finance, legal) | +1 tier; mandatory High-Risk Gate; named expert reviewers |
| Large doc / support corpus | +1 tier; add docs versioning + canonical-across-versions |
| Long-tail integrations / templates business | +1 tier; mandatory Programmatic Gates with kill switch |
| Concurrent migration / framework rewrite | +1 tier; engage Migration Checklist |
| Recent core-update overlap | escalate to traffic-drop-triage mode |

## Phase depth selectors

For each phase, the tier sets a *depth selector* that the corresponding phase reference uses:

| Phase | T1 | T2 | T3 | T4 |
|---|---|---|---|---|
| 1 — Discovery | lite | full | full + logs | continuous |
| 2 — Keyword | skip | one pillar | full universe | continuous |
| 3 — Technical | metadata-only | full | full + logs | continuous |
| 4 — Content | commercial | + first cluster | + lifecycle | continuous |
| 5 — IA | basic | full | + programmatic | continuous |
| 6 — Implementation | foundation PR | full | + programmatic | continuous |
| 7 — Authority | skip | one asset | full plan | continuous |
| 8 — Analytics | wire only | + dashboard | + log analysis | + AI citation tracking |
| 9 — Experimentation | skip | 1–2 tests | full | continuous |
| 10 — Fresh-eyes | once | per phase | per phase | per release |
| 11 — Deploy | once | per PR | per PR | per PR |
| 12 — Verify | once | per deploy | per deploy | per deploy |
| 13 — Compounding | once | once | quarterly | quarterly |
