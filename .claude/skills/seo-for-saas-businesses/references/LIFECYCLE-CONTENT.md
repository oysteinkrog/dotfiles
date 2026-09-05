# LIFECYCLE-CONTENT

## TOC

Why lifecycle content compounds · Per-page-type briefs · Public vs gated decision · Measurement (Phase 8 wiring) · Maintenance triggers · Tier depth selectors · Anti-patterns · Cross-links

Search does not stop at acquisition. The highest-intent post-awareness queries — "migrate from <competitor>", "<product> SOC 2 evidence", "<product> deprovision API key", "<plan> vs <plan>", "<error> <product>" — convert *indirectly* by reducing sales friction, deflecting support, accelerating activation, and lowering churn. Treat them as revenue infrastructure, not auxiliary content.

Phase mappings: primarily Phase 4 (briefs + drafts), Phase 5 (IA — these pages need hub placement), Phase 6 (often touches docs, status, and changelog routes), Phase 8 (different KPIs than acquisition pages).

## Why lifecycle content compounds

| Lifecycle stage | Search intent shape | Page asset |
|---|---|---|
| Evaluation | "<product> SOC 2", "<product> HIPAA", "<product> security model" | Security/compliance hub + linked artifacts |
| Procurement | "<product> DPA", "<product> SLA", "<product> SBOM", "<product> security questionnaire" | Procurement / vendor-review pages |
| Implementation | "<product> setup <stack>", "<product> first integration", "implement <product> with <X>" | Implementation guides per major stack |
| Migration | "migrate from <competitor> to <product>", "<competitor> export to <product>" | Per-source migration guides |
| Activation | "<product> first <core action>", "<product> tutorial <use case>" | Activation guides + sample data |
| Expansion | "<plan> vs <plan>", "<feature> add-on <product>", "<product> seats limit" | Plan-comparison + capacity pages |
| Troubleshooting | "<exact error> <product>", "<product> integration failing" | Error-message pages, status, runbooks |
| Renewal / retention | "<product> changelog", "<product> roadmap", "<product> uptime" | Changelog, status history, roadmap |

Acquisition pages are first-touch. Lifecycle pages are *every other touch* before, during, and after the contract. They tend to age into long-tail evergreens with low keyword difficulty and high commercial intent.

## Per-page-type briefs

### Implementation guides

- **Reader:** technical buyer or developer mid-evaluation; or a new customer in week 1.
- **Must contain:** stack assumptions stated up front; prerequisites with versions; copy-paste commands; expected output blocks; failure-mode subsections; "next step" link to a working demo.
- **URL:** `/docs/implement/<stack>` or `/guides/<stack>-setup` — pick one and stick to it.
- **Refresh trigger:** any breaking SDK change; any auth flow change; quarterly screenshot review.
- **Confidence:** `confirmed` — these are pages users actively search for.

### Migration guides

- **Reader:** existing user of a competitor evaluating switching cost.
- **Must contain:** an honest mapping table (competitor concept ↔ your concept); export instructions for the source; import commands or import-tool link; a section on what *will not* migrate (ratings, lifetime metadata, etc.); a rollback plan.
- **URL:** `/migrate/<competitor>` (canonical owner) — never bury under `/blog/`.
- **Refresh trigger:** competitor exposes a new export format; your import tool changes; once per quarter for screenshots.
- **Anti-pattern:** AI-summarized "X vs Y" page presented as a migration guide. Without a real mapping table and tested commands, this is scaled-content abuse risk (`likely`).

### Security / SOC2 / HIPAA / ISO pages

- **Reader:** security reviewer or compliance officer; reads with a checklist.
- **Must contain:** auditor name + report date; control coverage list; subprocessor list with regions; encryption posture (in transit + at rest + key management); incident-response SLOs; data-residency options; a download path to the latest report (gated or ungated — see "Public vs gated" below).
- **URL:** `/security`, `/security/soc2`, `/security/hipaa`, `/security/iso27001`, `/security/subprocessors`, `/security/dpa`.
- **Schema:** `Organization` (root) + `Article` per artifact. Do not invent `aggregateRating`. See [SCHEMA-POLICY](SCHEMA-POLICY.md).
- **Refresh trigger:** every audit cycle; every subprocessor change; every region addition; named owner = security or legal.
- **Confidence:** `confirmed` — security pages are decisive in B2B procurement; their absence loses deals.

### Procurement / vendor-review pages

- **Reader:** vendor-management or finance reviewer.
- **Must contain:** legal entity name + jurisdiction; payment terms; W-9 / VAT / tax-form download; invoicing options; data-use clauses; insurance coverage; termination terms.
- **URL:** `/legal/vendor-info`, `/legal/dpa`, `/legal/msa`, `/security/security-questionnaire`.
- **Refresh trigger:** entity change; insurance renewal; quarterly review.

### Plan-comparison / upgrade pages

- **Reader:** existing user evaluating expansion *or* prospect choosing tier.
- **Must contain:** what is added at each tier (not what is removed); honest limits (seats, requests, throughput); typical upgrade triggers; a path to talk to sales for enterprise tiers.
- **URL:** `/pricing/<tier-name>` or `/pricing#compare` — match the canonical owner of the cluster (see [PHASE-5-IA](PHASE-5-IA.md)).
- **Schema:** `WebApplication` + `Offer` mirroring visible plan cards.

### Troubleshooting / error-message pages

- **Reader:** user in active failure state; will paste the exact error string into Google.
- **Must contain:** the exact error string verbatim in `<code>` and in the page heading; what triggered it; what to check; recovery commands; when to escalate. See [DOCS-AND-SUPPORT-SEO](DOCS-AND-SUPPORT-SEO.md) for the full pattern.
- **URL:** `/docs/errors/<error-code>` or `/docs/troubleshooting/<symptom>`.
- **Refresh trigger:** when error changes; when fix path changes; when new error introduced.

### Integration troubleshooting

- **Reader:** user mid-integration whose webhook / OAuth / sync just broke.
- **Must contain:** prereqs assumed; checklist of common causes (rate limit, scope drift, clock skew, expired token, quota); per-cause recovery; status link if integration affected by an incident.
- **URL:** `/docs/integrations/<partner>/troubleshooting` paired with `/integrations/<partner>` (the marketing page) — different intent, different canonical.

### Customer education hubs

- **Reader:** new or growing customer learning the platform.
- **Must contain:** curriculum-style sequence; per-module outcomes; estimated time; sample data downloads; certificate or completion record where applicable.
- **URL:** `/academy/<track>` or `/learn/<track>`.
- **Schema:** `Course` is currently supported and useful here (`likely` — verify per [SCHEMA-POLICY](SCHEMA-POLICY.md)).

### Status & changelog

- **Reader:** existing customer diagnosing a behaviour change OR a prospect evaluating reliability.
- **Status page:** must show current incident state, scheduled maintenance, and 90-day history. Public, no auth wall.
- **Changelog:** dated entries; user-impact framing not internal-version framing; canonical at `/changelog`; per-entry URL `/changelog/<slug>` if entries are long.
- **Refresh trigger:** every release; every incident.

## Public vs gated decision

| Asset | Default | Gate when |
|---|---|---|
| Security overview | Public | Never gate |
| SOC 2 / ISO report | Email-gated | Audit clause forbids public hosting (verify with auditor) |
| DPA template | Public | Never gate (procurement blocker if gated) |
| Subprocessor list | Public | Never gate |
| Status page | Public | Never gate |
| Changelog | Public | Never gate |
| HIPAA BAA | Email-gated or sales-gated | Always — BAA is signed, not downloaded |
| Implementation guide | Public | Public; the value is the path, not the secret |
| Migration guide | Public | Public; competitive lift |
| Security questionnaire (SIG / CAIQ) | Email-gated | Always — gate to capture procurement contact |
| Customer story | Public | Public unless customer asked otherwise |

Rule of thumb: if the asset answers a procurement-blocking question, *being absent is worse than being public*. Gating a DPA loses more deals than it captures leads.

## Measurement (Phase 8 wiring)

Lifecycle pages do not rank like blog posts and do not convert like pricing pages. KPIs:

| Page type | Primary KPI | Secondary | Anti-metric (don't optimize) |
|---|---|---|---|
| Implementation guide | Activation lift on cohort that read it | Time-to-first-value | Pageviews |
| Migration guide | Migrated-customer count assists | Sales-cycle compression | Bounce rate |
| Security page | Deal-progression assists | RFP / security-questionnaire deflection | Pageviews |
| Procurement page | Procurement-touch deflection | Days-to-close delta | Bounce rate |
| Plan-comparison | Upgrade conversion | Self-serve expansion rate | Time on page |
| Troubleshooting | Support ticket deflection | Self-resolve rate | Pageviews |
| Status / changelog | Customer-NPS retention proxy | Reduced support volume during incidents | Pageviews |
| Customer education | Activation curve slope | Feature adoption breadth | Pageviews |

Wire via GA4 with custom events: `lifecycle_pageview` with `lifecycle_type` parameter, joined to user / account ID via authenticated property. Cross-reference Support tool deflection metrics (Zendesk / Intercom / Frontapp). See [PHASE-8-ANALYTICS](PHASE-8-ANALYTICS.md) and `/ga4`.

## Maintenance triggers

| Trigger | Pages affected |
|---|---|
| Product release ships | Changelog (always); implementation guides for affected stack; troubleshooting if errors changed; plan-comparison if limits changed |
| New SOC 2 / ISO audit | Security hub; SOC 2 page; auditor name; report date |
| New subprocessor | Subprocessors list; DPA if scope changed |
| Regulation change (GDPR, CPRA, EU AI Act, etc.) | Privacy; DPA; security; sometimes pricing |
| Integration partner changes API | Integration troubleshooting; integration page; sometimes implementation guide |
| Competitor renames feature or changes export | Migration guide |
| Pricing change | Plan-comparison; upgrade pages; pricing schema; sales collateral |
| Incident resolved | Status page; root-cause writeup; sometimes implementation guide if root cause was customer-side |

Each owner is named, not "marketing." If no human is named, the trigger will be missed. (`confirmed`)

## Tier depth selectors

| Tier | Lifecycle scope |
|---|---|
| T1 | Security overview only; status (manual or vendored); minimal changelog |
| T2 | + Implementation guides for top 2 stacks; SOC 2 if achieved; first migration guide |
| T3 | Full set above + per-error troubleshooting + customer education hub + procurement pack |
| T4 | Continuous program; multi-locale lifecycle; per-vertical compliance pages (HIPAA, FedRAMP, etc.); academy with `Course` schema |

## Anti-patterns

| Don't | Why | Do instead |
|---|---|---|
| Bury security under `/about/security` two clicks deep | Procurement reviewers leave; Google can't find the canonical | Top-level `/security` linked from footer + nav; canonical there |
| Generate per-error pages from log scraping with no fix path | Scaled-content abuse risk; thin content | Hand-author the top 50; track via internal-search mining; expand only when a fix exists |
| LLM-summarize a competitor's docs into a "migration guide" | Slop + factual drift + scaled-content risk | Test the export yourself; document failure modes; show the mapping table |
| Gate the changelog | Customers can't self-diagnose; procurement loses confidence | Public changelog; sign-up only for email digest |
| Leave subprocessor list 14 months out of date | Compliance failure during audit; trust collapse on discovery | Owner = security; quarterly review trigger; date visible on page |
| One catch-all "Resources" hub | No canonical ownership per query family | Cluster owners per lifecycle type; hub-and-spoke per cluster |
| Treat lifecycle pages as "blog" | Wrong template, wrong canonical, wrong measurement | Their own route group + their own KPIs |
| Auto-noindex docs older than 12 months | Long-tail compounds here; cuts off cited pages | Refresh, redirect, or merge — never blanket noindex |
| Status page on a different subdomain with no link | Diagnostic friction during incident; brand-entity ambiguity for AI engines | Link from footer + nav; `sameAs` if vendored |
| Plan-comparison page with feature lists copied from sales deck | Doesn't match buyer language; misses search intent | Build from internal search + sales call transcripts; mirror visible plan cards |
| Migration guide that doesn't acknowledge what *won't* migrate | Loses procurement trust on first read | Be specific about gaps; offer a workaround or accept the loss |

## Cross-links

- [PHASE-4-CONTENT](PHASE-4-CONTENT.md) — brief format and proof requirements per page.
- [PHASE-5-IA](PHASE-5-IA.md) — where lifecycle pages sit in the hub-and-spoke graph.
- [PHASE-8-ANALYTICS](PHASE-8-ANALYTICS.md) — wiring lifecycle KPIs to GA4 + product analytics.
- [DOCS-AND-SUPPORT-SEO](DOCS-AND-SUPPORT-SEO.md) — error-message and troubleshooting patterns.
- [TRUST-INFRASTRUCTURE](TRUST-INFRASTRUCTURE.md) — author/reviewer/methodology requirements.
- [PROOF-LIBRARY-OPS](PROOF-LIBRARY-OPS.md) — reusable evidence underlying lifecycle pages.
- [HIGH-RISK-GATE](HIGH-RISK-GATE.md) — when lifecycle content (security, compliance, financial) needs the high-risk gate.
