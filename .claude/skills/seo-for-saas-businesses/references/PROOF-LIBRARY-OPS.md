# PROOF-LIBRARY-OPS

## TOC

What goes in the library · Per-asset metadata · Asset lifecycle · Reuse surfaces · Permission tracking · Methodology pages · AI-citation extractability · Tier depth selectors · Maintenance triggers · Anti-patterns · Cross-links

Most SaaS sites do not need more generic articles. They need public evidence only they can produce. The proof library is a *managed inventory of original assets* — screenshots, benchmarks, anonymized data, customer outcomes, methodology pages, screenshots, certifications, calculators, datasets — re-used across content, sales, PR, answer-engine citations, and conversion. Treated as inventory (not a folder of random PNGs) it compounds.

Phase mappings: Phase 1 (asset inventory baseline), Phase 4 (briefs require evidence per the three-data-point rule), Phase 7 (linkable assets are proof-library outputs), Phase 13 (compounding wins often = "we already have the evidence; build the page").

## What goes in the library

| Asset type | Why it matters | Reuse surfaces |
|---|---|---|
| Product screenshots | Visual proof of claims | Pricing, integration, comparison, blog, OG |
| Walkthrough videos | Setup, workflow, demo | Docs, blog, social, AI-citation video pages |
| Benchmark methodology + results | Original data for citation | Comparison, blog, PR, answer engines |
| Anonymized aggregate data | Internal product analytics, ICP-relevant | Blog, PR, original-data hooks |
| Customer stories with permission | Outcome proof; conversion | Case study, social, sales, PR |
| Implementation notes | Real per-customer detail (anonymized) | Blog, integration, migration |
| Changelog / release notes | Freshness signal; user-impact framing | Site, RSS, customer email |
| Uptime / incident history | Reliability evidence | Status, security, procurement |
| Public roadmaps | Trust + community | Marketing, sales, AI Mode citation |
| Compatibility / capability matrices | Evaluation-stage decisions | Comparison, integration, docs |
| Security / privacy / accessibility / procurement docs | Procurement-blocker artifacts | Security hub, sales, lifecycle pages |
| Independent reviews / awards / certifications | Trust externality | About, footer, OG, sameAs |
| Original templates / calculators / generators | Linkable assets; product-led SEO | Standalone tools; blog hooks |
| Public datasets | High-leverage citation magnets | Methodology pages; PR |

(`confirmed` — see canonical guide §14, "Proof and originality library")

## Per-asset metadata

Every asset has a row in the library. Required fields:

```yaml
id: proof-2026-q1-bench-rps
title: "Acme vs <competitor> p95 latency benchmark Q1 2026"
type: benchmark
source: scripts/bench/run-2026-04-01.json
owner: jane.doe@acme.com           # named human
date_captured: 2026-04-01
reuse_permissions: public          # public | internal | NDA-only | customer-named
claims_supported:                  # links to the page slugs whose claims it backs
  - /comparison/competitor
  - /pricing#performance
  - /blog/q1-2026-benchmark
refresh_trigger: quarterly         # or product-release / regulation / partner-change
next_refresh_due: 2026-07-01
location:                           # canonical location (R2 / repo / CMS)
  primary: r2://acme-proof/bench/q1-2026-rps.png
  variants:                         # crops, sizes, OG-ready, social
    - r2://acme-proof/bench/q1-2026-rps@og.png
methodology_link: /methodology/latency-bench
status: live                        # live | retired | superseded | embargoed
related_assets:
  - proof-2026-q1-throughput
notes: |
  Run on n2-standard-8; production tenant data sample (~1.2B rows).
  Methodology approved by SME 2026-03-25.
```

Store in `analyses/proof-library.yaml` (or a Notion DB; the structure beats the tool). Each row's `claims_supported` is the *forward index* — when an asset is updated, every page in `claims_supported` gets queued for refresh.

## Asset lifecycle

| Stage | What happens | Owner |
|---|---|---|
| Proposed | Idea entered; methodology drafted; resourcing decided | Cluster lead |
| In production | Data collection / capture / negotiation in progress | Asset owner |
| Reviewed | SME has signed off on methodology / accuracy | SME |
| Live | Embedded in pages; tracked in `claims_supported` | Asset owner |
| Refresh due | `next_refresh_due` reached | Asset owner |
| Superseded | Newer asset replaces; old asset 410 or kept as historical | Asset owner |
| Retired | No longer accurate; removed from pages; archived | Asset owner |

## Reuse surfaces

Each asset is intentionally re-used across surfaces:

| Asset | Content | Sales | PR | Answer engines | Conversion |
|---|---|---|---|---|---|
| Q1 latency benchmark | Comparison page, blog | Deck slide, RFP response | Press release, partner co-marketing | Cited via `/comparison/<x>` | Hero of pricing page |
| Customer story (named) | Case study | Slack channel, sales call | Quote in press | Cited as outcome evidence | Testimonial block on home |
| SOC 2 Type II report | Security hub | RFP response | n/a | Cited in compliance answers | Procurement deflection |
| Public dataset | Methodology page | Educational asset | Linkable hook | High citation magnet | Brand recall |
| Pricing calculator | Blog embed | Quoting tool | Original-tool PR | Cited as "the tool" | Mid-funnel conversion |

The proof library makes "build the page" a 1-day task because the evidence already exists. Without it, every new page is a 2-week excavation.

## Permission tracking (often forgotten)

Customer logos, testimonials, screenshots showing identifiable usage, named case studies, performance comparisons mentioning competitors — all need explicit permission. Track separately:

```yaml
permission:
  customer: AcmeCo (Jane Smith, VP Eng)
  granted_date: 2026-03-15
  granted_for:
    - "use of name and logo on /customers/acmeco"
    - "use of named quote attributed to Jane Smith"
    - "use of anonymized usage screenshot"
  expiry: 2027-03-15      # or "indefinite" — explicit
  signed_artifact: legal/permissions/acmeco-2026-03-15.pdf
  contact_for_renewal: jane.smith@acmeco.com
```

If permission expires: the asset moves to `embargoed` until renewed; all pages in `claims_supported` get a refresh ticket.

For competitor mentions in benchmarks: screenshot the competitor's public docs / pricing on the *date you captured*, store the screenshot in the library, and cite it. Do not paraphrase a competitor's claim without a dated source. (`confirmed` — limits scaled-content / inaccurate-comparison risk.)

## Methodology pages

Every quantitative claim should map to a public methodology page:

```
/methodology/latency-bench
/methodology/uptime-calculation
/methodology/cost-savings-survey
/methodology/q1-2026-state-of-data
```

A methodology page contains: dataset definition, sample, time window, environment, exclusions, reproducibility steps, and a citation block. AI engines cite methodology pages disproportionately because they are the primary source. (`likely` — observed across multiple benchmark publications)

## AI-citation extractability

For AI-citation eligibility, asset content must be in the *initial HTML* of any page that uses it (per [AI-VISIBILITY](AI-VISIBILITY.md)). That means:

- Numbers in `<p>` or `<table>`, not `<canvas>` charts (or both — chart for humans, table for crawlers).
- Dates / versions / methodology links visible.
- Source attribution visible inline, not buried in footnotes.

```html
<figure>
  <table>
    <caption>p95 query latency, Q1 2026 (lower is better)</caption>
    <thead><tr><th>Tool</th><th>p95 (ms)</th></tr></thead>
    <tbody>
      <tr><td>Acme</td><td>47</td></tr>
      <tr><td>Competitor A</td><td>112</td></tr>
      <tr><td>Competitor B</td><td>198</td></tr>
    </tbody>
  </table>
  <figcaption>
    Source: <a href="/methodology/latency-bench">Acme latency methodology</a>;
    captured 2026-04-01 on a 1.2 B-row production dataset.
  </figcaption>
  <img src="/proof/bench-q1-2026.png" alt="Bar chart of p95 query latency by tool, Q1 2026" />
</figure>
```

The chart image is for humans. The `<table>` and `<figcaption>` are for AI engines and screen readers. Both come from the same proof-library asset.

## Tier depth selectors

| Tier | Proof library scope |
|---|---|
| T1 | A README and a single shared drive folder; 5–10 evergreen screenshots; SME-reviewed |
| T2 | Structured library with metadata (Notion / YAML); per-asset owner; first benchmark + first customer story |
| T3 | Forward index `claims_supported` enforced; CI check that no page claims data without a library row; quarterly methodology page audit |
| T4 | Versioned proof-library-as-code; per-locale variants; permission expiry alarms; integration with CMS for embed-by-id |

## Maintenance triggers

| Trigger | Effect |
|---|---|
| `next_refresh_due` reached | Asset queued; pages in `claims_supported` queued for refresh |
| Customer permission expires | Asset → `embargoed`; refresh tickets emitted |
| Product release changes screenshot accuracy | Affected screenshots queued; refresh blog and pricing |
| Competitor screenshot stale (> 90 d) | Re-capture before next comparison page publish |
| Methodology found incorrect | Asset retired; superseded asset linked; transparent correction note added per [TRUST-INFRASTRUCTURE](TRUST-INFRASTRUCTURE.md) |
| New audit / certification | Add asset; update Trust hub; update `Organization` schema sameAs / award |

## Anti-patterns

| Don't | Why | Do instead |
|---|---|---|
| One Google Drive folder with everything | No metadata; assets get lost; permissions implicit | Structured library with metadata |
| Reuse a customer logo without written permission | Legal exposure; trust collapse on discovery | Permission record per customer + per use |
| Cite a competitor screenshot from "earlier this year" with no date | Asserts a current claim with stale evidence; risk of inaccuracy | Date-captured visible; refresh on quarterly cadence |
| Generate a screenshot via "fake data" | Marketing slop risk; AI engines cite real data over fake | Use anonymized real data with consent |
| Methodology buried in a CSV nobody reads | Untraceable; cannot defend the claim | A real methodology page per quantitative claim |
| Asset with no `claims_supported` field | When asset is updated, no idea which pages need refresh | Forward index mandatory |
| Asset with no owner | No one refreshes; asset ages into wrong | Named human per asset |
| Customer testimonial in a 90s video on YouTube only | Crawlers / AI bots can't see it | Transcript on the page; embed video; both visible in HTML |
| Stop refreshing screenshots after launch | Pages quietly age; user trust drops; AI bots over-emphasize the latest quote elsewhere | Quarterly screenshot review on commercial templates |
| Lock benchmarks behind a "request the report" form | Earned-citation signal weakens; AI bots can't cite | Public methodology page; "request raw data" optional |
| Use screenshots that show real PII | Privacy violation; brand risk | Anonymized data with consent |
| Build proof library only for marketing | Lose the largest reuse surface (sales, support, AI engines) | Cross-functional from day one |
| Hold a customer logo wall with logos you don't have permission for | Legal exposure | Permission per logo; logo wall as a system |
| AI-generate a "case study" for a fictitious customer | Egregious slop; brand-defining bad-faith | Real customers with permission, or synthetic but clearly labelled "illustrative" |

## Cross-links

- [AI-VISIBILITY](AI-VISIBILITY.md) — three-data-point rule; initial HTML requirement.
- [PHASE-4-CONTENT](PHASE-4-CONTENT.md) — proof requirements per brief.
- [PHASE-7-AUTHORITY](PHASE-7-AUTHORITY.md) — linkable assets are proof-library outputs.
- [TRUST-INFRASTRUCTURE](TRUST-INFRASTRUCTURE.md) — methodology, corrections, author bios.
- [LIFECYCLE-CONTENT](LIFECYCLE-CONTENT.md) — security / procurement assets are proof.
- [EDITORIAL-CALENDAR](EDITORIAL-CALENDAR.md) — refresh triggers feed the calendar.
- [HIGH-RISK-GATE](HIGH-RISK-GATE.md) — high-risk content requires source citations from the library.
