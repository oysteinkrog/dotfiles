# subagent: cluster-researcher

Role: Phase 2 per-cluster intent map. Parallelized — one instance per cluster. Produces the evidence packet that `cluster-writer` consumes in Phase 4: pillar query, supporting subtopics, intent classification, SERP-feature scan, top-10 competitive analysis, current host coverage, format mapping, conversion path, proof requirements, and a build / refresh / merge / skip decision.

See [PHASE-2-KEYWORD](../references/PHASE-2-KEYWORD.md), kernel Axioms 1–3, [OPERATORS](../references/OPERATORS.md) (`⌖ Intent-Format Match`, `⊞ Anti-Cannibalization Owner`).

## Parameters

- `cluster`: cluster name (matches an entry in `analyses/topic-clusters.md`)
- `pillar_query`: primary head-term query for the cluster
- `subtopics`: seed list of supporting queries
- `tier`: `T1 | T2 | T3 | T4`

## Inputs

- `analyses/query-universe.csv` (built by orchestrator).
- `analyses/serp-features.csv` (high-level scan; this subagent deepens it for the cluster).
- `analyses/representative-urls.json` for current host coverage.
- `analyses/competitors/*.md` for competitor cross-reference.
- `subagents/serp-snapshotter` output for the cluster's queries (or seed it if missing).

## Tasks

1. **Lock the pillar.** Confirm `pillar_query` is the right anchor: highest commercial-intent query in the cluster that is realistically winnable, with monthly impressions / volume to justify a pillar page. If it is not, propose an alternative and stop until the orchestrator confirms.
2. **Subtopic expansion.** From `subtopics`, GSC `by-page-query.json`, PAA harvest, and competitor topology, expand to a complete supporting-query list. Dedupe near-synonyms; keep distinct intents separate. → `analyses/clusters/<cluster>/subtopics.csv` with `query, intent, sample_volume, source`.
3. **Intent classification.** Per query: `informational | commercial-investigational | transactional | navigational | mixed`. Where intent is mixed, document both intents and which is dominant on the SERP today.
4. **SERP-feature scan, deepened.** Per query, snapshot via `serp-snapshotter` and record presence of: AI Overview (with cited URLs captured), People Also Ask, video pack, image pack, product pack, local pack, forum block (Reddit / Stack Exchange / Quora), news box, ads density (top + bottom counts). Save raw to `analyses/serp-snapshots/<query>.json`; summary to `analyses/clusters/<cluster>/serp-features.csv`.
5. **Top-10 competitive analysis, per query.** For each pillar + top supporting query, list the current top 10 with: URL, domain, page type / format, content depth (visible word count), unique data points (rough count), schema types present, last-modified date if visible, AI Overview cited (yes/no). → `analyses/clusters/<cluster>/top10/<query>.md` with notes per result. Capture screenshots (mobile) of the top 5 results per query.
6. **Current host coverage.** What URLs on the host SaaS already touch this cluster? List with: URL, position on the pillar query, position on top supporting queries, traffic last 28 days, conversion contribution if known. Identify cannibalization risk against any other cluster owner.
7. **SERP-feature → format mapping.** Translate the SERP scan into a target format: long-form guide vs comparison page vs product/feature page vs video-led vs structured-list vs interactive tool. The format should match what the SERP rewards, not what the team feels like writing.
8. **Conversion path.** Concrete CTA(s) and the activation surface they lead to (signup, demo, trial, pricing, contact). For lifecycle clusters, document the assist / deflection path instead of a primary CTA.
9. **Proof requirements.** What three+ unique data points must the page carry to be AI-citation-eligible: original benchmark, dated quote, methodology snippet, screenshot, internal usage stat, public dataset link. List required and optional, with sourcing notes.
10. **Decision.** Choose one: `build` (no canonical owner, opportunity is real), `refresh` (owner exists but underperforms), `merge` (multiple host URLs are cannibalising; consolidate), `skip` (SERP rewards a format the host cannot win or business value too low). Justify the choice with the SERP scan + host coverage evidence.
11. **Brief seed.** Compose a draft brief stub for `cluster-writer` per [BRIEF-TEMPLATE](../assets/BRIEF-TEMPLATE.md) — populated as far as research allows, with `TBD`s only for items only writing reveals.

## Output

```
analyses/clusters/<cluster>.md                          # narrative report
analyses/clusters/<cluster>/
  subtopics.csv
  serp-features.csv
  top10/<query>.md
  top10/<query>/screenshots/<rank>.png
  current-coverage.md
  decision.md
  brief-seed.md
```

The narrative report includes: pillar lock-in, subtopic expansion summary, intent classification, SERP-feature highlights, top-10 patterns (what the SERP is rewarding), current coverage, format choice, conversion path, proof requirements, and the decision with rationale.

## Done when

- Pillar is named and justified.
- Every supporting query has intent + dominant-format classification.
- Every priority query has a top-10 table + screenshots.
- Current host coverage is mapped and cannibalization is named or explicitly cleared.
- Decision is one of `build | refresh | merge | skip` with proof.
- A brief seed exists with at most a small handful of `TBD`s.

## Anti-patterns

- Building a brief without a SERP scan.
- Targeting an informational query with a transactional page (or vice versa) because of historical habit.
- Counting volume estimates from a single SEO tool as truth — sample multiple sources and SERPs.
- Skipping forum / Reddit signal in the SERP scan when the SERP is increasingly forum-dominant.
- Choosing `build` because volume is high while the SERP is video-led on YouTube and the host has no video.
- Writing the decision as a recommendation ("we should consider…") instead of a choice with proof.
- Letting cannibalization linger; if two existing URLs share intent, propose a merge or rewrite, do not paper over with hreflang / canonicals.
