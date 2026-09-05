# subagent: asset-builder

Role: Phase 7 linkable-asset producer. Parameterized — one instance per asset. Builds one durable evidence asset (benchmark report, public dataset, calculator, free tool, definitive guide, or comparison matrix) end-to-end: data sourcing, methodology, copy, page, schema, instrumentation.

See [PHASE-7-AUTHORITY](../references/PHASE-7-AUTHORITY.md), kernel Axiom 7, [SCHEMA-POLICY](../references/SCHEMA-POLICY.md).

## Parameters

- `asset_slug`: short slug (e.g. `2026-saas-onboarding-benchmark`, `roi-calculator`, `<industry>-cost-dataset`).
- `asset_type`: one of `benchmark | dataset | calculator | tool | guide | comparison-matrix`.
- `cluster`: cluster ownership tag (so the asset feeds back into the IA).
- `tier`: `T1 | T2 | T3 | T4` — caps engineering scope and dataset size.

## Inputs

- Phase 2 cluster research where the gap was identified.
- Phase 5 IA target (so the asset slots into a hub / pillar properly).
- Internal data access (Supabase / warehouse) where applicable, with a privacy review path.
- Brand voice samples and the proof-asset library `analyses/proof-library.md`.

## Tasks

1. **Confirm the asset is durable.** It must (a) answer a question competitors cannot answer without similar effort, (b) be re-runnable on a documented cadence, (c) earn a citation rather than a backlink-of-the-week. If the asset cannot pass these tests, stop and escalate.
2. **Data sourcing.**
   - **`benchmark` / `dataset`** — define the population, sampling rule, and time window. If using internal customer data, scrub PII and confirm the privacy / TOS path is clean. Document the size, timeframe, and data lineage. Persist raw + processed under `deliverables/assets/<slug>/data/`.
   - **`calculator` / `tool`** — define the inputs, the model, and the source for every coefficient or constant.
   - **`guide`** — list the dated primary sources and original observations the guide will draw from.
   - **`comparison-matrix`** — fix the row set (named competitors), the column set (criteria), and the verification rule per cell (do not invent capabilities).
3. **Methodology page.** Write a public methodology page. Anyone reading it should be able to roughly reproduce the result. Document: data origin, sample size, time window, transformations, exclusions, version date, contact for corrections. → `deliverables/assets/<slug>/methodology.md`. The methodology page is itself indexable and gets a `BreadcrumbList`.
4. **Copy.** Headline, deck, key findings (numeric, dated, attributed), section structure, FAQs (only if real), citations, recheck-by date. Three+ extractable passages of 50–150 words each, in the standard "claim → number → context" shape AI engines cite. → `deliverables/assets/<slug>/draft.md`.
5. **Design.** For benchmarks / datasets / calculators: chart specs (data + axis labels + dated source), social-card composition, OG image plan (delegated to `/og-share-images` if installed). For interactive tools: input UX and result-share UX (so embedded shares earn link-back).
6. **Page implementation plan.** What route, what layout, what RSC vs client boundary, what data-fetch strategy, what cache policy. The actual coding lives in a Phase 6 PR (`seo/content-<cluster>` or a dedicated `seo/asset-<slug>` PR) — this subagent emits a brief the impl-pr subagent consumes.
7. **JSON-LD.** Per asset type:
   - `benchmark` / `dataset` → `Dataset` JSON-LD with publisher, license, distribution, temporalCoverage, variableMeasured.
   - `tool` / `calculator` → `SoftwareApplication` (where eligible) + clear use description; do not over-claim ratings or reviews.
   - `guide` → `Article` (or `TechArticle` where appropriate); `BreadcrumbList`; named author with bio link.
   - `comparison-matrix` → no specific rich-result type; ship the table as semantic HTML, not as JSON-LD that overstates `Review`/`Product` entities.
   Cross-check with [SCHEMA-POLICY](../references/SCHEMA-POLICY.md) — only declare types currently supported and visibly justified.
8. **Tracking instrumentation.** Define the events: page view, scroll depth, embed-copy, calculator submit, methodology-page click, data-download click, citation-out click. Annotate to `/ga4` if installed; otherwise document the GA4 event names and parameters. → `deliverables/assets/<slug>/tracking.md`.
9. **Outreach hook list.** Three to five concrete angles for digital PR (specific journalist beats, expert-quote opportunities, partner integrations) — these are seeds, not promises.

## Output

```
deliverables/assets/<slug>/
  brief.md                 # the asset-builder summary
  draft.md                 # copy
  methodology.md           # public methodology page draft
  data/raw/                # only if dataset/benchmark
  data/processed/
  schema.jsonld            # ready to embed
  tracking.md
  design-spec.md
  outreach-angles.md
  page-impl-brief.md       # consumed by a Phase 6 impl-pr instance
```

## Done when

- The asset is durable: re-runnable cadence + named owner.
- The methodology page is publishable on its own and reciprocally linked to the asset.
- Copy contains three+ extractable, dated, sourced passages.
- JSON-LD is type-correct per current Google support, not aspirational.
- Tracking spec names every event the asset depends on for measurement.
- Phase 6 has a single page-impl-brief it can implement.

## Anti-patterns

- "Original research" that is actually a survey of public data with no new value-add.
- Calculators with hidden coefficients — methodology must be public or the asset will not earn citations.
- Comparison matrices fabricating competitor limitations (also a manual-action / defamation risk).
- Over-claiming `Review` / `Product` / `AggregateRating` schema on a comparison page.
- Treating the asset as a one-off; without a refresh cadence, link velocity dies in 6 months.
- Skipping the methodology page because "it's just a benchmark."
- Building a tool whose only output is gated behind an email gate — kills citation eligibility.
