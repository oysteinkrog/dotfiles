# 90-day plan — `<saas name>`

Operationalizes `multi_agent_seo_guide.md` §23 into a tier-aware, day-resolved plan with deliverables, owners, and acceptance criteria. Use as the master schedule for greenfield, mature-site-audit, or migration modes. Cross-link bead IDs and audit IDs as they are created.

- **Tier**: `<T1 | T2 | T3 | T4>` (per [TIER-ROUTING](../references/TIER-ROUTING.md))
- **Mode**: `<greenfield-seo | mature-site-audit | traffic-drop-triage | migration | programmatic-launch-review | ai-visibility-pass>`
- **Owner of plan**: `<human name>`
- **Sponsor**: `<exec name>`
- **Start date**: `<YYYY-MM-DD>`
- **Day-90 date**: `<YYYY-MM-DD>`
- **Plan recheck-by**: `<YYYY-MM-DD>` (typically Day 14, 45, 90)

## Decision points

| Day | Question | If yes | If no |
|---|---|---|---|
| 14 | Is the audit complete and prioritized? | Proceed to Days 15–45. | Extend audit; do not start fixes blind. |
| 45 | Have foundation fixes shipped on priority templates without regression? | Proceed to Days 46–90. | Stay on foundation; build asset only when CWV / indexation green. |
| 90 | Is organic delta meaningful and AI-citation surface tracked? | Move to compounding cadence ([PHASE-13](../references/PHASE-13-COMPOUNDING.md)). | Diagnose, do not panic-rewrite; consider [TRAFFIC-DROP-PLAYBOOK](../references/TRAFFIC-DROP-PLAYBOOK.md). |

## Days 1–14: Audit

Per [PHASE-1-DISCOVERY](../references/PHASE-1-DISCOVERY.md) + [PHASE-3-TECHNICAL](../references/PHASE-3-TECHNICAL.md). All evidence under `analyses/`.

| Day | Activity | Deliverable | Owner | Acceptance |
|---|---|---|---|---|
| 1 | Intake + working surface confirmed | `analyses/intake.md` | `<owner>` | [INTAKE-CHECKLIST](../references/INTAKE-CHECKLIST.md) all green |
| 2 | Crawl seed (raw + rendered HTML, JSON) | `analyses/crawl/` | `<owner>` | All indexable URLs captured; raw vs rendered diff sample saved |
| 3 | GSC + GA4 + CrUX exports | `analyses/gsc/`, `analyses/ga4/`, `analyses/crux/` | `<owner>` | 16-month GSC export complete; conversion paths labeled |
| 4 | Robots / sitemap / analytics health | `analyses/audit/infra.md` | engineering | Sitemap returns 200; robots correct; GA4 events firing |
| 5–6 | Template + URL inventory | `analyses/template-inventory.md` | `<owner>` | Every page type listed with intent + canonical owner |
| 7 | Query-family → page-type map | `analyses/clusters/` (initial) | `<owner>` | Top 20 query families mapped to canonical destinations |
| 8 | Anti-cannibalization map | `analyses/cannibalization-map.md` | content | No two pages own same query intent without justification |
| 9–10 | Index-state decisions per template | `analyses/index-state-log.md` | engineering + content | Each template has explicit index/noindex/canonical rule |
| 11 | Representative URL set | `analyses/representative-urls.json` | engineering | ≥1 URL per template; covers all critical conversion paths |
| 12 | Striking-distance + decay candidates | `analyses/audit/opportunity.md` | analytics | Pages avg position 4–15 listed; decay candidates flagged |
| 13 | Audit issues drafted | `analyses/audit-issues.json` | `<owner>` | Each item passes [AUDIT-ITEM-TEMPLATE](AUDIT-ITEM-TEMPLATE.md) format |
| 14 | Decision points + Day-15 plan | `analyses/audit-summary.md` | `<owner>` | Sponsor sign-off; bead graph created |

### Day-14 acceptance gate

- [ ] All discovery artifacts in [DELIVERABLES-INDEX](../references/DELIVERABLES-INDEX.md) are present.
- [ ] Audit issues prioritized (critical / high / medium / low) with confidence labels.
- [ ] Source-log started ([SOURCE-LOG-TEMPLATE](SOURCE-LOG-TEMPLATE.md)).
- [ ] Tier confirmed against actual data (URL count, organic baseline). Update plan if reality disagrees.

## Days 15–45: Fix the foundation

Per [PHASE-3-TECHNICAL](../references/PHASE-3-TECHNICAL.md), [PHASE-4-CONTENT](../references/PHASE-4-CONTENT.md), [PHASE-5-IA](../references/PHASE-5-IA.md), [PHASE-6-IMPLEMENTATION](../references/PHASE-6-IMPLEMENTATION.md).

| Day | Activity | Deliverable | Owner | Acceptance |
|---|---|---|---|---|
| 15–18 | Foundation PR (metadata, robots, sitemap, canonical, schema base) | `deliverables/prs/seo-foundation.md` | engineering | Lighthouse CI + schema validation pass on staging |
| 19–21 | Per-route metadata for priority templates | `deliverables/prs/seo-per-route-metadata.md` | engineering + content | All priority templates have unique title / meta / OG / canonical |
| 22–25 | Internal linking PR | `deliverables/prs/seo-internal-links.md` | engineering | Orphans on priority pages = 0; broken internal links = 0 |
| 26–28 | CWV remediation on priority templates | `deliverables/prs/seo-perf-cwv.md` | engineering | INP < 200 ms p75; LCP < 2.5 s p75 on representative URLs |
| 29–31 | Structured-data PR (per [SCHEMA-POLICY](../references/SCHEMA-POLICY.md)) | `deliverables/prs/seo-structured-data.md` | engineering | Validates per-type; no deprecated types |
| 32–34 | Title + meta CTR rewrites for high-impression / low-CTR pages | `deliverables/prs/seo-titles-ctr.md` | content | Striking-distance pages have intent-matched titles |
| 35–37 | Thin-content prune / merge / redirect / noindex pass | `deliverables/prs/seo-prune.md` | content | Decay queue cleared per [PROGRAMMATIC-GATES](../references/PROGRAMMATIC-GATES.md) |
| 38–40 | Faceted nav / parameter URL discipline | `deliverables/prs/seo-facets.md` | engineering | No infinite parameter spaces; rel/canonical correct |
| 41–43 | Trust infrastructure surfaces (security, status, legal, about) | `deliverables/prs/seo-trust.md` | content + design | All trust pages crawlable, indexable, internally linked |
| 44 | Annotations + GSC re-crawl requests on priority URLs | `analyses/seo-changelog.md` | `<owner>` | Each PR annotated; recheck-by dates set |
| 45 | Day-45 review | `analyses/audit-summary.md` (updated) | `<owner>` | Foundation gate clear; Phase 7 / 13 unblocked |

### Day-45 acceptance gate

- [ ] No critical audit items remain unshipped.
- [ ] Representative URL set passes [PHASE-12-VERIFICATION](../references/PHASE-12-VERIFICATION.md).
- [ ] CWV p75 in `good` band on commercial templates.
- [ ] Sitemap segments aligned with page types; submitted; indexed delta tracked.
- [ ] Source-log updated; [GUIDE-RECONCILIATION](../references/GUIDE-RECONCILIATION.md) reviewed.

## Days 46–90: Build assets

Per [PHASE-4-CONTENT](../references/PHASE-4-CONTENT.md), [PHASE-7-AUTHORITY](../references/PHASE-7-AUTHORITY.md), [PHASE-8-ANALYTICS](../references/PHASE-8-ANALYTICS.md), [PHASE-9-EXPERIMENTATION](../references/PHASE-9-EXPERIMENTATION.md).

| Day | Activity | Deliverable | Owner | Acceptance |
|---|---|---|---|---|
| 46–50 | Highest-value commercial pages (per [BRIEF-TEMPLATE](BRIEF-TEMPLATE.md)) | `deliverables/briefs/<cluster>/` + drafts | content | Briefs have ≥3 unique data points; pass [SLOP-CHECKLIST](../references/SLOP-CHECKLIST.md) |
| 51–55 | Linkable asset (per [PHASE-7-AUTHORITY](../references/PHASE-7-AUTHORITY.md)) | `deliverables/authority-plan.md` + asset URL | content + design | Asset is original, dated, citation-eligible |
| 56–60 | Striking-distance refresh batch | `deliverables/briefs/refresh/` | content | Pages re-shipped with proof; recheck-by set |
| 61–65 | Lifecycle / docs / support SEO | `deliverables/briefs/lifecycle/` | content + docs team | Docs versioning + canonical-across-versions correct |
| 66–70 | Programmatic template (T3+ only) | `deliverables/prs/seo-programmatic-<t>.md` | engineering + content | [PROGRAMMATIC-GATES](../references/PROGRAMMATIC-GATES.md) all pass; kill-switch tested |
| 71–75 | SERP-feature alignment for priority queries | `analyses/serp-snapshots/` + `deliverables/serp-feature-plan.md` | content + design | Each priority query has format that matches its dominant feature |
| 76–80 | Outreach for the linkable asset | `deliverables/authority-plan.md` (updated) | marketing | First placements landed; outreach log appended |
| 81–83 | Maintenance dashboard + reporting cadence | `deliverables/dashboard-spec.md`, `deliverables/weekly-report-template.md`, `deliverables/monthly-exec-template.md` | analytics | Weekly + monthly cadences live; KPIs per [KPI-TARGET-SHEET-TEMPLATE](KPI-TARGET-SHEET-TEMPLATE.md) |
| 84–86 | First experiment shipped (per [EXPERIMENT-CARD](EXPERIMENT-CARD.md)) | `analyses/experiments/<id>.md` | analytics + content | Hypothesis + tracking + decision rule pre-registered |
| 87–88 | Seasonality / refresh calendar | per [SEASONALITY-CALENDAR-TEMPLATE](SEASONALITY-CALENDAR-TEMPLATE.md) | content | Quarterly peak windows mapped to content-prep windows |
| 89 | Fresh-eyes audit ([PHASE-10-FRESH-EYES](../references/PHASE-10-FRESH-EYES.md)) | `analyses/fresh-eyes/pass-1/` | external reviewer | Critical items captured; not silently dismissed |
| 90 | Day-90 review + compounding plan | `deliverables/compounding-backlog.md` | `<owner>` | Sponsor sign-off; recheck-by Day-180 set |

### Day-90 acceptance gate

- [ ] Organic clicks / impressions delta vs Day-0 baseline reported with cause attribution.
- [ ] AI-Overview citations on tracked queries logged ([CITATION-TRACKING-CSV-SCHEMA](CITATION-TRACKING-CSV-SCHEMA.md)).
- [ ] At least one linkable asset live with first placements.
- [ ] Programmatic kill-switch tested (T3+ only).
- [ ] [MONTHLY-EXEC-TEMPLATE](MONTHLY-EXEC-TEMPLATE.md) for the third month delivered.

## Tier-specific variants

<details>
<summary><strong>T1 — Pre-launch / Pre-PMF</strong></summary>

Compress to ~14 days total; skip programmatic, authority, experimentation.

- **Days 1–3 (audit-lite)**: intake, robots/sitemap/analytics health, template inventory for product surfaces only.
- **Days 4–10 (foundation)**: foundation PR, per-route metadata for home / pricing / signup / security / about, structured data base, CWV pass, internal linking on commercial pages.
- **Days 11–14 (compounding setup)**: GSC + GA4 wiring verified, weekly-report template installed, recheck-by Day-90 set.

Skip: Phase 2 keyword universe, Phase 7 authority, Phase 9 experiments, Phase 13 deep compounding pass.

</details>

<details>
<summary><strong>T2 — Early growth</strong></summary>

Use full 90 days as written. Phase 2 lite (one pillar, two clusters). Phase 7 = one linkable asset. Phase 9 = 1–2 title CTR tests. Maintenance dashboard from Day 80.

</details>

<details>
<summary><strong>T3 — Scaled</strong></summary>

Same 90-day spine, parallelized via subagents. Add:

- Day 5: server-log analysis kicks off (`subagents/log-analyst.md`).
- Day 10: cluster-researcher subagent per pillar.
- Days 46–60: programmatic template only if [PROGRAMMATIC-GATES](../references/PROGRAMMATIC-GATES.md) green; otherwise defer.
- Day 70: AI-citation tracking workstream live ([CITATION-OPS](../references/CITATION-OPS.md)).
- Continuous Phase 8; quarterly Phase 1 / 3 / 10 / 13 from Day 90 onward.

</details>

<details>
<summary><strong>T4 — Enterprise / Mature</strong></summary>

Treat as a coordinator pass, not a one-time program. The 90-day plan becomes the *first quarter* of a continuous program:

- Days 1–14: cross-segment audit (per business unit / product / locale).
- Days 15–45: foundation regressions across segments; brand-demand workstream review.
- Days 46–90: programmatic governance review, multi-product cannibalization map, locale program audit, AI-Overview share-of-voice baseline.

This skill is QA + reviewer. Day-90 deliverable is the operating model, not the work itself.

</details>

## Anti-patterns

- **Linear sequencing of independent work.** Foundation PRs (metadata, schema, CWV) parallelize. Don't gate them on each other unless an audit item explicitly says so.
- **Audit-only programs.** A 14-day audit with no shipping plan is theater. Day 14 commits to Day-15-onward bead graph.
- **Scope creep into authority before foundation.** Linkable assets that point at a broken substrate waste outreach goodwill.
- **Skipping Day-45 and Day-90 gates.** Without acceptance gates, the plan becomes a list of things you did instead of a measurement of progress.
- **Re-using a T3 template on a T1 site.** Pre-PMF SaaS does not need a 13-phase pass. Match depth to reality.

## Cross-references

- [TIER-ROUTING](../references/TIER-ROUTING.md), [PHASE-DAG](../references/PHASE-DAG.md), [DELIVERABLES-INDEX](../references/DELIVERABLES-INDEX.md)
- [DECISION-CARD](DECISION-CARD.md), [BRIEF-TEMPLATE](BRIEF-TEMPLATE.md), [AUDIT-ITEM-TEMPLATE](AUDIT-ITEM-TEMPLATE.md)
- [KPI-TARGET-SHEET-TEMPLATE](KPI-TARGET-SHEET-TEMPLATE.md), [SOURCE-LOG-TEMPLATE](SOURCE-LOG-TEMPLATE.md)
