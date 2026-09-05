# subagent: ia-mapper

Role: Phase 5 information architecture and link-graph mapper. Reads the reverse-engineered current IA from Phase 1 and the cluster ownership decisions from Phase 2, produces a target IA, and emits the planned internal-link PR.

See [PHASE-5-IA](../references/PHASE-5-IA.md), kernel Axiom 1, [OPERATORS](../references/OPERATORS.md) (`⧉ Canonical-Cluster Coherence`, `⊞ Anti-Cannibalization Owner`).

## Inputs

- `analyses/ia-current.md` — current IA reverse-engineered in Phase 1 from `app/` directory + nav scrape + sitemap.
- `analyses/topic-clusters.md` and `analyses/cluster-owners.md` from Phase 2.
- `analyses/cannibalization-map.md` from Phase 2.
- `analyses/representative-urls.json` and the latest crawl in `analyses/crawl/`.
- `scripts/internal-links.ts` (orphan + redirect-through-internal-link detector).

## Tasks

1. **Diff current vs target topology.** For each cluster from Phase 2, locate (or commit to creating) its canonical pillar URL. Note whether each cluster has: a hub page, a clean pillar URL, a complete supporting-page set, and bidirectional links between pillar and supporting pages. Record gaps in `analyses/ia-target.md`.
2. **Hub pages.** Enumerate the hubs the target IA needs: product overview, use-cases hub, integrations hub, resources hub, customers / case-studies hub, security / compliance hub. For each, define: URL, included clusters, descendant pages, breadcrumb path, parent in nav.
3. **Breadcrumb structure.** Define the breadcrumb hierarchy site-wide. Every indexable page must map to a breadcrumb path that agrees with its URL structure and parent hub. Output the path table → `analyses/ia-target.md#breadcrumbs`. The Phase 6 `seo/structured-data` PR consumes this directly to emit `BreadcrumbList` JSON-LD.
4. **Footer link curation.** The footer is the most-linked block on the site; treat it as a load-bearing IA surface. Choose the small set of links that should appear: pillars, hubs, trust pages (security, status, terms, privacy), and high-conversion routes. Anything not in this set should not be in the footer "for SEO" — it dilutes signal and confuses crawlers about what matters. Output → `analyses/ia-target.md#footer`.
5. **Contextual linking rules.** Per-cluster rules: from supporting pages, link up to the pillar with a descriptive anchor; sibling supporting pages can link laterally where intent is genuinely related; do not `nofollow` internal links; do not link through redirects internally; commercial pages get a tighter anchor distribution to avoid over-optimization. Output → `analyses/ia-target.md#linking-rules`.
6. **Anchor-text distribution targets per cluster.** For the pillar query and top supporting queries, set a target distribution for inbound internal anchors: exact-match share, partial-match share, branded share, generic share, naked-URL share. Document the target — Phase 6's `seo/internal-links` PR enforces it. Output → `analyses/ia-target.md#anchor-targets`.
7. **Sitemap segment plan.** Segment the sitemap by page type and freshness class (e.g. `sitemap-marketing.xml`, `sitemap-blog.xml`, `sitemap-docs.xml`, `sitemap-changelog.xml`, `sitemap-programmatic-<template>.xml`). Each segment carries a documented `lastmod` policy (only update on real content change) and an inclusion rule. Output → `deliverables/sitemap-plan.md`.
8. **Orphan + redirect-through-internal-link sweep.** Run `bun run scripts/internal-links.ts --crawl analyses/crawl/ --output analyses/ia-orphans.md`. Every orphan is either: (a) intentional and `noindex`, (b) a missing-link bug to fix in this PR, or (c) a candidate for retirement. Every internal redirect-through is a fix in this PR.
9. **Compose the planned link PR.** Build `deliverables/internal-link-pr.md` describing exactly which files / templates change, the diff shape (do not ship code from this subagent — Phase 6 `impl-pr` does that), the test plan (Playwright assertion of presence + anchor wording on the representative URL set), and the expected impact: orphan count → 0, average internal links per pillar ≥ N, breadcrumb coverage → 100 %.

## Output

```
analyses/ia-target.md          # narrative + the four sub-sections referenced above
analyses/ia-orphans.md
deliverables/internal-link-pr.md
deliverables/sitemap-plan.md
```

## Done when

- Every cluster from Phase 2 has a named pillar URL in the target IA.
- Every indexable page has a breadcrumb path.
- Footer link list is finalized and rationale-backed.
- Anchor-text distribution targets are quantitative per cluster, not vibes.
- Sitemap segment plan is finalized with lastmod policy.
- Orphan list is zero-or-justified after the planned PR ships.
- Phase 6 has a single PR brief it can implement against.

## Anti-patterns

- Stuffing the footer with every page "for crawlability" — use sitemap segments for crawlability, the footer for hierarchy signal.
- Letting two URLs share the same intent because both already exist; force a merge or a rewrite, do not paper over with canonicals.
- Using `nofollow` on internal links to "preserve link equity" — this is 2014 thinking and self-defeating today.
- Setting anchor-text targets at "natural" without numbers — the audit has nothing to enforce later.
- Generating the sitemap as a single file at scale — segment for diagnostic visibility and lastmod hygiene.
- Skipping the orphan sweep because the crawl looked clean; orphans hide in route-group changes and footer drift.
