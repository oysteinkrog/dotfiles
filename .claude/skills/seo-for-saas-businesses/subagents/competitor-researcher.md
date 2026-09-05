# subagent: competitor-researcher

Role: Phase 2 per-competitor analysis. Parallelized — one instance per named competitor. Output is **evidence**, not opinion: their topology, their ranking pages, their proof assets, their schema, their cadence, their weaknesses.

See [PHASE-2-KEYWORD](../references/PHASE-2-KEYWORD.md), [SCHEMA-POLICY](../references/SCHEMA-POLICY.md).

## Parameters

- `competitor`: short slug (e.g. `acme`, `monday`, `notion`)
- `competitor_url`: production homepage
- `seed_queries`: path to a seed query list scoped to this competitor's overlap surface
- `tier`: `T1 | T2 | T3 | T4` (caps depth of crawl + screenshot count)

## Inputs

- `analyses/jtbd.md` (already authored by orchestrator).
- `analyses/representative-urls.json` for the host SaaS (used for overlap math).
- SEO-tool API access if available (`Ahrefs`, `Semrush`, `Sistrix`); otherwise SERP-sample fallback.
- Brand-name list for cannibalization checks against the host SaaS.

## Tasks

1. **Site crawl (sampled).** Crawl the competitor's marketing surface up to a tier-capped budget (T1: 50 URLs, T2: 200, T3: 1000, T4: 3000). Capture template family, route group, content depth, internal-link structure, and sitemap footprint. Persist a thin record per URL to `analyses/competitors/<competitor>/_crawl/`.
2. **Topology.** Reverse-engineer the pillar / cluster topology: which URLs serve as hubs, which feed into them, where the link concentration is. Produce a topology diagram (mermaid is fine) in `analyses/competitors/<competitor>.md`.
3. **Ranking-page list.** Pull their visible queries and ranking URLs via the SEO tool API. If unavailable, sample SERPs for `seed_queries` via `subagents/serp-snapshotter` and harvest competitor URLs that appear in the top 20. Annotate each: query, position, intent, SERP features captured. Capture **screenshots** for the top 25 ranking pages (Playwright, mobile + desktop). → `analyses/competitors/<competitor>/screenshots/`.
4. **Original-data assets.** Identify pages that publish original research, public datasets, benchmark numbers, calculators, free tools, comparison matrices — anything that earns links durably rather than re-stating common knowledge. Note the data type, the recency, and the link velocity (Ahrefs / Majestic referring-domain count if available). → `analyses/competitors/<competitor>/data-assets.md`.
5. **Schema usage.** Inventory their JSON-LD by template: `Organization`, `Product`, `SoftwareApplication`, `Article`, `BreadcrumbList`, `Review`, `Dataset`, `FAQPage` (rare and risky now), `HowTo` (deprecated but still used), `Course`, `JobPosting`. Per type: count, sample URLs, validity. Cross-reference with [SCHEMA-POLICY](../references/SCHEMA-POLICY.md). → `analyses/competitors/<competitor>/schema.md`.
6. **Comparison / alternative coverage.** Specifically catalog `<them>-vs-<us>`, `<them> alternatives`, `<them> pricing`, `<them> reviews`, `<them> integrations`. For each, note URL, position for the obvious query, presence of a captured-screenshot of the SERP they earn. This is the commercial-intent battleground.
7. **Content cadence.** From their blog / changelog / press / docs, infer publishing cadence over the last 12 months: posts per month, depth (word count / unique data points), refresh activity (republished dates). Note authorship structure (named experts vs anonymous). → cadence section in `analyses/competitors/<competitor>.md`.
8. **Weaknesses.** Concrete observations, not adjectives: missing schema on a template that warrants it, no canonical owner for a high-volume cluster, brittle internal-link structure, no proof asset on a commercial page, no methodology page on a benchmark, untranslated content for declared markets, slow LCP on the homepage, broken `hreflang` reciprocity, public roadmap disagreeing with their docs. Rank weaknesses by exploitability for the host SaaS.
9. **Cross-link to clusters.** Every weakness gets tagged with the host-SaaS cluster name(s) it could feed into, so `cluster-researcher` and `cluster-writer` can pull from this report directly.

## Output

```
analyses/competitors/<competitor>.md         # narrative report
analyses/competitors/<competitor>/
  _crawl/<urlhash>.json
  screenshots/<urlhash>.{mobile,desktop}.png
  data-assets.md
  schema.md
  ranking-pages.csv
```

The narrative report includes: topology, top-25 ranking-page table with screenshot refs, data-asset inventory, schema posture, comparison/alternative coverage, content cadence, ranked weaknesses cross-linked to host clusters.

## Done when

- Topology diagram exists and names hubs.
- Top-25 ranking-page list has query + position + screenshot path each.
- Data-asset inventory is non-empty or explicitly states "no original-data assets observed".
- Schema inventory cross-references SCHEMA-POLICY for risk per type.
- Weakness list is concrete (every item has a URL or template name) and cross-linked to host clusters.

## Anti-patterns

- "Their content is generic" — useless. Either name the template and quote a sentence, or drop the claim.
- Crawling tens of thousands of URLs because the budget allows it — sample by template family, do not re-index the competitor.
- Treating SERP-tool ranking lists as ground truth without spot-checking 5–10 SERPs live (rank trackers lag and personalize).
- Counting blog posts as a quality signal — count proof assets and methodology pages.
- Reporting `FAQPage` schema as "they have FAQ rich results" — verify current Google support per type.
- Skipping screenshots — visual evidence is the only thing the rest of the program will trust later.
