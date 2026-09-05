# 90-DAY-PLAN

## TOC

How to use this file · Mode-specific variants · T2 standard 90-day plan · T1 condensed plan · T3 expanded plan · T4 continuous program · Mode-specific schedule overrides · Rollover scenarios · Decision points · KPIs to track · Anti-patterns · Cross-links

Operationalized version of the canonical guide §23. A per-day schedule with deliverables, acceptance criteria, decision points, and rollover scenarios — calibrated by tier and mode. Use this when the user asks for a "90-day SEO plan" or when initiating any of the modes from the SKILL [MODE ROUTER](../SKILL.md#mode-router).

Phase mappings: this is the *scheduler view* of all 13 phases. Phases 1, 3, 5, 8 dominate days 1–14; phases 6, 4 dominate days 15–45; phases 7, 4 (continued), 9, 13 dominate days 46–90; phases 10–12 run continuously per release.

## How to use this file

1. Pick the tier (T1–T4) per [TIER-ROUTING](TIER-ROUTING.md).
2. Pick the mode per the SKILL [MODE ROUTER](../SKILL.md#mode-router).
3. Use the matching tier+mode plan below; T2 is the default mid-range.
4. Each day has: deliverable, acceptance criterion, owner, dependencies.
5. At each phase boundary, run the decision point: continue / re-plan / escalate.

## Mode-specific variants — high-level

| Mode | First 14 days emphasis | Days 15–45 emphasis | Days 46–90 emphasis |
|---|---|---|---|
| `greenfield-seo` | Full Phase 1 baseline; foundation; commercial briefs | Foundation PR; commercial drafts; first IA; observability | First content cluster; first link asset; experiments lite |
| `mature-site-audit` | Audit + log analysis + content inventory | Targeted fixes (audit-driven); cannibalization map; refreshes | New cluster; PR; experimentation |
| `traffic-drop-triage` | Diagnose-before-fix; segmentation; release-correlation | Roll back regressions; targeted fixes by segment | Recovery validation; refresh decay queue |
| `programmatic-launch-review` | Gate audit; data-source review; small batch | Stage 1 + Stage 2 launch; quality dashboard | Stage 3 / 4 with kill-switch ready |
| `migration` | Pre-launch URL map; redirect testing in staging | Launch + monitoring; daily 5xx check; sample inspection | Post-launch validation; backlinks updated; declare complete |
| `ai-visibility-pass` | AI-bot view audit; entity consistency; proof-library inventory | Extractable-passage rewrites; methodology pages; sameAs reciprocity | Citation tracking; refresh queue |
| `core-update-response` | Segment movement; helpful-content classifier audit | Prune unhelpful; refresh top decay candidates | Validate recovery; lock in process |
| `lifecycle-content` | Lifecycle inventory; gap analysis | Implementation guides + security pages | Migration + procurement + plan-comparison |

(`confirmed` shape; specific day counts adjust per tier.)

## T2 standard 90-day plan (default reference)

The T2 plan is the load-bearing reference. T1 compresses; T3/T4 add scope.

### Days 1–14: Audit (Phase 1 + 3)

| Day | Deliverable | Acceptance criterion |
|---|---|---|
| 1 | Intake checklist completed; project access; GSC + GA4 wired | All systems readable; baseline URLs identified |
| 2 | Prod + staging crawl via `scripts/crawl.ts`; raw vs rendered HTML diff | One row per URL; status, redirects, canonical, schema captured |
| 3 | GSC pull (16 mo); GA4 organic pull; manual actions check | Exports landed in `analyses/gsc/` and `analyses/ga4/` |
| 4 | CrUX field data + Lighthouse CI on representative URL set | `analyses/crux/` and `analyses/lighthouse/` populated |
| 5 | Template inventory by route group / data source | `analyses/template-inventory.md` complete |
| 6 | IA reverse-engineered from `app/` and nav scrape | `analyses/ia-current.md` complete |
| 7 | Seed-keyword rankings snapshot via `scripts/serp-snapshot.ts` | Baseline ranks captured per query |
| 8 | Indexability audit (noindex + soft-404 inventory + canonical mismatch + duplicate cluster) | Audit items in `analyses/audit-issues.json` |
| 9 | Crawlability audit (`robots.txt`, sitemap content vs canonical truth, redirect chains, status health) | Audit items added |
| 10 | Rendering audit (raw vs rendered HTML diff per template; RSC streaming completeness; AI-bot view) | Audit items added; AI-bot diff captured |
| 11 | Structured-data audit (per template; schema mirrors content; per-type Google support) | Audit items added |
| 12 | Internal-link graph health (orphan + redirect-through-internal + anchor distribution) | Audit items added |
| 13 | CWV per-component attribution (top 5 templates) | INP / LCP attribution captured per [INP-DEEP-DIVE](INP-DEEP-DIVE.md) |
| 14 | Audit summary + prioritized fix list; representative URL set; baseline KPIs | `analyses/audit-summary.md` ready; fixes scoped |

**Decision point (end of Day 14):**

- *Audit complete?* → continue to Days 15–45.
- *Audit reveals manual action / critical regression?* → switch to `traffic-drop-triage` mode immediately.
- *Audit reveals nothing actionable in 90 days?* → re-plan (likely T1 with reduced scope).

### Days 15–45: Foundation (Phase 6 + 4 + 5)

| Day range | Deliverable | Acceptance criterion |
|---|---|---|
| 15–17 | `seo/foundation` PR: `metadataBase`, `robots.ts`, `sitemap.ts`, redirect cleanups, canonical helper | PR merged; verified on staging |
| 18–22 | `seo/per-route-metadata` PR: `generateMetadata` on every public route + canonical alternates | Every public route has unique title + description + canonical |
| 23–25 | `seo/structured-data` PR: `Organization` + `WebSite` + `BreadcrumbList`; per-page schema for commercial templates | Schema validates; mirrors visible content |
| 26–28 | `seo/og-images` PR: dynamic OG/Twitter via `next/og` for top templates | Social preview verified per top template |
| 29–35 | `seo/perf-cwv` PR: image, font, RSC, INP fixes per Day 13 attribution | INP < 200 ms p75 on commercial templates (CrUX projection); Lighthouse CI green |
| 36–40 | `seo/internal-links` PR per IA plan; pillar↔cluster bidirectional; breadcrumbs sitewide | Orphan count → 0 on commercial pages; through-redirect internal links eliminated |
| 41–43 | First content cluster briefs + drafts (5–10 priority pages from Phase 4) | Briefs + drafts in `deliverables/briefs/` and `deliverables/drafts/` |
| 44–45 | Phase 10 fresh-eyes pass on shipped foundation; Phase 12 Playwright verification | Two clean fresh-eyes passes; verifier all-green |

**Decision point (end of Day 45):**

- *Foundation shipped + verified + first cluster drafted?* → continue to Days 46–90.
- *Foundation slipped (shipped late)?* → reduce Days 46–90 scope; do not chase ambitious cluster output.
- *Verification revealed regression?* → fix before continuing; re-run verifier.

### Days 46–90: Build assets (Phase 4 + 7 + 9 + 13)

| Day range | Deliverable | Acceptance criterion |
|---|---|---|
| 46–55 | First content cluster shipped (priority pages from Phase 4) | All cluster pages live; internal-link graph wired; briefs archived |
| 56–62 | First linkable asset (Phase 7) shipped: benchmark / calculator / dataset / definitive guide | Asset live with methodology page; outreach plan drafted |
| 63–66 | Refresh top 10 striking-distance pages (positions 4–15) | Refreshed; annotated in `seo-changelog.md`; recheck-by date logged |
| 67–70 | Refresh top 10 decay candidates from `analyses/content-inventory.md` | Refreshed; decay queue empty for now |
| 71–75 | Phase 9 lite: 1–2 title-tag / meta-description tests with stopping rules | Tests live; `analyses/experiments/<id>.md` per test |
| 76–80 | Outreach for the linkable asset: 30–50 targeted contacts; HARO / digital PR opportunities | Contact list seeded; first replies received |
| 81–85 | Lifecycle pages: implementation guide for top stack; security page upgrade; first migration guide | All three live; cross-linked from commercial pages |
| 86–88 | Phase 13 idea-wizard pass on live site + plan; compounding backlog | `deliverables/compounding-backlog.md` with ranked ideas |
| 89 | Phase 8 monthly executive cockpit: revenue / leads / branded vs non-branded / shipped vs refreshed vs merged vs removed / earned mentions / risks | `deliverables/monthly-exec-template.md` filled |
| 90 | Plan handoff: 90-day recap; KPIs vs baseline; recheck cadence; next-90-day proposal | Handoff document delivered; user can run program forward |

**Decision point (end of Day 90):**

- *KPIs trending positive (impressions + clicks + conversions on tracked clusters)?* → continue to next 90-day plan.
- *Specific cluster decayed?* → schedule cluster refresh in next plan.
- *Foundation regression resurfaced?* → re-audit; do not fast-forward.

## T1 condensed plan (1 week, not 90 days)

T1 is < 30 indexable URLs, < $1M ARR. Compress into a 7–10 day pass:

| Day | Deliverable |
|---|---|
| 1 | Intake + GSC + GA4 wiring |
| 2 | Crawl + audit (commercial pages only) |
| 3 | `seo/foundation` PR |
| 4 | `seo/per-route-metadata` PR |
| 5 | Schema + OG images for home / pricing / about / security |
| 6 | First commercial cluster brief + draft |
| 7 | Phase 12 verification + handoff |

T1 skips: programmatic; experiments; full Phase 7; lifecycle (beyond a single security page).

## T3 expanded plan (8–12 weeks initial + continuous)

T3 follows the T2 plan as a backbone but adds:

| Phase | T3 add |
|---|---|
| Phase 1 | Server-log analysis (Days 7–10); per-locale crawl if multi-region |
| Phase 3 | Per-template attribution dashboard; faceted-nav crawl-trap audit; complexity overlays |
| Phase 4 | 3+ content clusters in parallel; lifecycle content set; per-vertical pages |
| Phase 5 | Programmatic templates (gated per [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md)); first staged batch |
| Phase 7 | Multi-asset linkable-asset plan; per-vertical PR angles |
| Phase 8 | + AI-citation tracking (manual log); log-file weekly review |
| Phase 9 | 4–6 tests in parallel (titles, descriptions, content templates) |
| Phase 13 | Quarterly cadence locked in |

## T4 continuous program

T4 is not a 90-day plan; it's a continuous program with 90-day reviews:

| Cadence | Activity |
|---|---|
| Weekly | Phase 8 dashboard; alarms; release QA on representative URLs |
| Monthly | Phase 8 cockpit; per-segment trend; one Phase 9 readout |
| Quarterly | Phase 1 (light) re-baseline; Phase 3 spot audits; Phase 10 fresh-eyes; Phase 13 idea-wizard pass |
| Annual | Phase 1 deep re-baseline; structural IA review; international / locale program review |

## Mode-specific schedule overrides

### `traffic-drop-triage`

| Day range | Activity |
|---|---|
| 1–3 | Segmentation: when did the drop start, what segment, branded vs non-branded, by template, by country, by device |
| 4–7 | Cross-reference: deploys, content changes, robots / canonical / redirect changes, schema changes, CWV changes, core update windows; per [TRAFFIC-DROP-PLAYBOOK](TRAFFIC-DROP-PLAYBOOK.md) |
| 8–14 | Hypothesize, fix highest-confidence cause; do *not* ship sweeping changes pre-diagnosis |
| 15–45 | Validate fix; refresh remaining decayed pages; site-wide quality pass if helpful-content drag |
| 46–90 | Recovery monitoring; lock in process; document the cause and remediation in `seo-changelog.md` |

### `migration`

| Phase | Activity |
|---|---|
| T-30 to T-1 | Per [MIGRATION-CHECKLIST](MIGRATION-CHECKLIST.md): inventory, URL map, redirect testing in staging |
| Launch day | Deploy; sample redirect verification; sitemap submission; GSC change-of-address; annotate |
| T+1 to T+30 | Daily 5xx check for verified Googlebot; URL inspection on top 20 redirects; daily traffic monitoring |
| T+31 to T+90 | CrUX field-data delta review; GSC enhancement reports; sitemap submitted-vs-indexed delta; declare complete when criteria met |

### `programmatic-launch-review`

Cycle from [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md):

| Stage | Volume | Wait |
|---|---|---|
| 1 | 10–25 pages | 14 days |
| 2 | +100 pages | 14 days |
| 3 | +500 pages | 28 days |
| 4 | full rollout | — |

The 90 days fit a Stage 1 + 2 + 3 cycle; full rollout often slips to Day 90+.

## Rollover scenarios

What to do when phases run long:

| Slippage | Response |
|---|---|
| Days 1–14 audit slipped (Day 21+) | Compress Days 15–45: ship `seo/foundation` only; defer per-route metadata PR to next 90 days |
| Days 15–45 foundation slipped | Cut content cluster scope (1 cluster instead of 2); skip Phase 9 |
| Phase 12 verifier failing repeatedly | Stop; do not ship more PRs; fix the rendering / metadata / schema regression first |
| User priorities shift mid-plan | Re-plan from current day with clear `seo-changelog.md` annotation |
| Engineering capacity halved | Pivot to refresh + experimentation (less code-heavy); preserve foundation as the irreducible work |
| Regulatory / launch event added | Insert lifecycle pages + PR moments; re-baseline after |

## Decision points (cheat sheet)

| Boundary | Continue if | Re-plan if | Escalate if |
|---|---|---|---|
| End of Day 14 | Audit complete; fix list scoped | Audit incomplete or scope changed | Manual action / critical regression / core-update overlap detected |
| End of Day 45 | Foundation shipped + verified + first drafts | Foundation slipped | Verification revealed regression with no fix path |
| End of Day 90 | KPIs trending positive | Specific cluster decayed; foundation regression | Site-wide drop + helpful-content suspected |

## KPIs to track every plan (T2+)

| KPI | Baseline | 90-day target |
|---|---|---|
| Impressions on tracked clusters | Day 0 GSC | +20% (`hypothesis`; varies wildly by stage) |
| Clicks on tracked clusters | Day 0 GSC | +15% (`hypothesis`) |
| Branded vs non-branded split | Day 0 GA4 | Branded stable; non-branded growing |
| INP p75 commercial templates | Day 0 CrUX | < 200 ms p75 |
| Indexed-page count by sitemap segment | Day 0 GSC | Within 5% of canonical truth |
| Schema enhancement errors | Day 0 GSC | → 0 |
| Organic-to-trial conversion on top landing pages | Day 0 GA4 | Stable or improving |
| AI-Overview citation count (if tracked) | Day 0 manual | Track per `analyses/ai-citations.csv` |

(`hypothesis` for percentage targets; calibrate to actual baseline.)

## Anti-patterns

| Don't | Why | Do instead |
|---|---|---|
| Ship "Days 15–45 foundation" before Day 14 audit completes | Optimization theatre; you'll fix the wrong things | Audit gates the fix |
| Skip Phase 12 verification because "we tested in staging" | Production has different cache / CDN / headers | Always run prod verification |
| Plan 5 content clusters when foundation is broken | Builds on sand | Foundation first |
| Promise 30% organic lift in 90 days | Unrealistic; sets the user up for disappointment | Promise process; report results |
| Ship a programmatic template family in this 90-day window without [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md) gates | Site-wide reputation risk | Stage rollout per gates |
| Treat refresh as "update meta description" | Doesn't move ranking | Re-research, new evidence, internal-link refresh |
| Skip Phase 8 wiring because "we'll do analytics later" | Future traffic moves are unattributable | Wire on Day 1 |
| Ignore CrUX in favour of Lighthouse | Lab ≠ field; ranking signal is field | Both; CrUX is the source of truth |
| Run experiments before foundation | Variants exposed on broken substrate | Foundation first |
| Skip the seo-changelog.md | Future regressions impossible to attribute | Annotate every deploy |
| Plan 90 days without naming a human owner per phase | Slips quietly | Owner per phase + per cluster |
| Promise 90-day rankings on competitive head terms | Unrealistic | Measure striking-distance lift on targeted queries |

## Cross-links

- [TIER-ROUTING](TIER-ROUTING.md) — pick the tier first.
- [PHASE-DAG](PHASE-DAG.md) — full dependency graph.
- [PHASE-1-DISCOVERY](PHASE-1-DISCOVERY.md) through [PHASE-13-COMPOUNDING](PHASE-13-COMPOUNDING.md) — per-phase deep dives.
- [TRAFFIC-DROP-PLAYBOOK](TRAFFIC-DROP-PLAYBOOK.md) — `traffic-drop-triage` and `core-update-response` modes.
- [MIGRATION-CHECKLIST](MIGRATION-CHECKLIST.md) — `migration` mode.
- [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md) — `programmatic-launch-review` mode.
- [AI-VISIBILITY](AI-VISIBILITY.md) — `ai-visibility-pass` mode.
- [LIFECYCLE-CONTENT](LIFECYCLE-CONTENT.md) — `lifecycle-content` mode.
- [EDITORIAL-CALENDAR](EDITORIAL-CALENDAR.md) — schedule discipline beyond this 90-day window.
