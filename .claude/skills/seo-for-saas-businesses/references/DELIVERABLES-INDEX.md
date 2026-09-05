# DELIVERABLES-INDEX

## TOC

Naming conventions · Lifecycle · Gitignore decision · Mode-specific deliverables · Audit-trail invariant

Directory layout the program produces. All paths relative to the SaaS repo root unless `analyses/` and `deliverables/` are configured to live elsewhere per [WORKING-SURFACE](WORKING-SURFACE.md).

```
analyses/
├── intake.md
├── skill-availability.md
├── source-log.md                                  # verification-first audit trail
├── seo-changelog.md                               # every shipped change annotated
├── baseline-summary.md                            # Phase 1
├── representative-urls.json                       # Phase 1, refined in Phase 3
├── template-inventory.md                          # Phase 1
├── ia-current.md                                  # Phase 1
├── ia-target.md                                   # Phase 5
├── crawl/                                         # Phase 1 raw + rendered HTML + JSON
│   ├── <urlhash>.raw.html
│   ├── <urlhash>.rendered.html
│   └── <urlhash>.json
├── gsc/                                           # Phase 1
│   ├── performance.json
│   ├── coverage.json
│   ├── sitemaps.json
│   ├── manual-actions.json
│   ├── cwv.json
│   └── enhancements.json
├── ga4/
│   ├── landing-pages.json
│   ├── conversion-paths.json
│   └── branded-vs-nonbranded.json
├── crux/<urlhash>.json
├── lighthouse/<urlhash>.json
├── log-analysis.md                                # T3+ only
├── serp-snapshots/<query>.json
├── jtbd.md                                        # Phase 2
├── competitors/<name>.md                          # Phase 2
├── clusters/<cluster>.md                          # Phase 2
├── query-universe.csv
├── topic-clusters.md
├── cluster-owners.md
├── cannibalization-map.md
├── audit-issues.json                              # Phase 3 machine-readable
├── audit-summary.md                               # Phase 3 human report
├── audit/<area>.md                                # Phase 3 per-area reports
├── content-inventory.md                           # Phase 4 + maintenance
├── ai-citations.csv                               # Phase 8 manual log
├── experiments/<id>.md                            # Phase 9
├── fresh-eyes/                                    # Phase 10
│   ├── pass-1/
│   ├── pass-2/
│   └── summary.md
├── post-deploy-verification.md                    # Phase 12
├── unknowns.md                                    # items with insufficient evidence
└── anti-patterns.md                               # documented anti-pattern requests / decisions

deliverables/
├── briefs/<cluster>/<page>.md                     # Phase 4
├── drafts/<cluster>/<page>.md                     # Phase 4
├── internal-link-pr.md                            # Phase 5
├── sitemap-plan.md                                # Phase 5
├── authority-plan.md                              # Phase 7
├── dashboard-spec.md                              # Phase 8
├── weekly-report-template.md                      # Phase 8
├── monthly-exec-template.md                       # Phase 8
├── experimentation-runbook.md                     # Phase 9
├── compounding-backlog.md                         # Phase 13
└── prs/                                           # Phase 6 PR descriptions
    ├── seo-foundation.md
    ├── seo-per-route-metadata.md
    ├── seo-structured-data.md
    ├── seo-og-images.md
    ├── seo-perf-cwv.md
    ├── seo-internal-links.md
    ├── seo-content-<cluster>.md
    └── seo-programmatic-<template>.md
```

## Naming conventions

- `audit-issues.json` follows the schema in [PHASE-3-TECHNICAL](PHASE-3-TECHNICAL.md). IDs are sequential (`AUDIT-0001` …) and stable.
- Bead / GitHub issue IDs link back to audit IDs in their description.
- PR slugs use `seo/<group>` prefix.
- `seo-changelog.md` entries are one section per shipped change.

## Lifecycle

- `analyses/` is for evidence and ongoing diagnosis. Append-only most of the time; explicit edits when an item moves status (e.g. `unknowns.md` → confirmed → moved to `audit-issues.json`).
- `deliverables/` is for ready-to-ship artifacts. PR descriptions, briefs, drafts, dashboards.
- The `seo-changelog.md` is the historical record. Never rewrite past entries; corrections go as new entries.

## Gitignore decision

Default: `analyses/` and `deliverables/` committed to the repo (so they're shared and reviewed alongside code).

Alternative: `analyses/` gitignored if it grows beyond reasonable git size (e.g. `analyses/crawl/` with hundreds of MB of HTML); `deliverables/` always committed.

Confirm during [INTAKE-CHECKLIST](INTAKE-CHECKLIST.md).

## Mode-specific deliverables

| Mode | Most-emphasized deliverables |
|---|---|
| `greenfield-seo` | All — full first-pass set |
| `mature-site-audit` | `audit-summary.md`, prioritized PR list, no new-content briefs |
| `traffic-drop-triage` | `analyses/traffic-drop/` workspace; minimal PRs until diagnosis complete |
| `programmatic-launch-review` | `analyses/programmatic-gates.md`, `deliverables/prs/seo-programmatic-<t>.md`, kill-switch test artifacts |
| `migration` | `analyses/migration/url-map.csv`, `deliverables/prs/migration.md`, post-launch monitoring plan |
| `ai-visibility-pass` | `analyses/ai-citations.csv`, citation-eligibility audits per priority page |
| `core-update-response` | `analyses/core-update/`, segmented diagnosis, quality roadmap (not panic rewrite) |
| `lifecycle-content` | `deliverables/briefs/lifecycle/` (implementation, migration, security, procurement, troubleshooting) |
| `maintenance` | `analyses/content-inventory.md` updated, decay queue, schema revalidation pass |

## Audit-trail invariant

Every recommendation in any deliverable has a path back to its evidence in `analyses/`. The reader can always find the screenshot, log, GSC export, or Playwright trace that produced the recommendation.
