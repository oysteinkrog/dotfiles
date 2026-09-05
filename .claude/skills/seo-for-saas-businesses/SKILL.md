---
name: seo-for-saas-businesses
description: >-
  Multi-phase SEO + GEO program for SaaS sites. Use when auditing technical
  SEO, Core Web Vitals, AI Overview citations, schema, hreflang, programmatic
  templates, or shipping SEO PRs.
---

<!-- TOC: Quick Start | Mode Router | Kernel | Operators | Tier Triage | 13 Phases | Reconciliation | Anti-Patterns | References -->

# SEO for SaaS Businesses — A Multi-Phase Operating Program

## Table of Contents

[QUICK START](#quick-start) · [MODE ROUTER](#mode-router) · [SAAS-SEO KERNEL](#the-saas-seo-kernel--universal-axioms) · [VERIFICATION-FIRST](#verification-first-overlay) · [COGNITIVE OPERATORS](#cognitive-operators--seo-thinking-moves) · [TIER TRIAGE](#tier-triage--route-depth-to-stage) · [Phase 1 — Discovery](#phase-1--discovery--baseline) · [Phase 2 — Keyword](#phase-2--keyword--intent-research) · [Phase 3 — Technical Audit](#phase-3--technical-seo-audit) · [Phase 4 — Content](#phase-4--on-page--content-production) · [Phase 5 — IA](#phase-5--information-architecture--internal-linking) · [Phase 6 — Implementation](#phase-6--implementation-in-the-saas-codebase) · [Phase 7 — Authority](#phase-7--off-page--authority-strategy) · [Phase 8 — Analytics](#phase-8--analytics-dashboards--reporting) · [Phase 9 — Experimentation](#phase-9--experimentation--iteration) · [Phase 10 — Fresh-Eyes](#phase-10--fresh-eyes-review--qa) · [Phase 11 — Deploy](#phase-11--deployment--verification) · [Phase 12 — Live Verification](#phase-12--live-site-playwright-verification) · [Phase 13 — Compounding](#phase-13--idea-wizard-pass-for-compounding-wins) · [DELIVERABLE TEMPLATES](#deliverable-templates) · [GUIDE RECONCILIATION](#reconciling-the-guide-with-current-evidence) · [ANTI-PATTERNS](#anti-patterns) · [SAFE-CHANGES MANDATE](#safe-changes-mandate) · [SIBLING SKILLS](#integrations-with-sibling-skills) · [PRECEDENCE & SAFETY](#precedence--safety-rules) · [QUALITY DISCIPLINE](#quality-discipline) · [REFERENCES](#reference-index) · [SELF-VALIDATION](#self-validation) · [META-NOTE](#meta-note)

> **Core Insight:** Most SaaS SEO fails not because the team picked the wrong keywords, but because the *site itself silently suppresses its own pages* — server-rendered metadata that disagrees with rendered metadata, canonical clusters fighting each other, programmatic templates crossing the scaled-content tripwire, INP regressions hidden inside dashboard components leaking into marketing routes, RSC streams that resolve fine for Googlebot but ship empty HTML to GPTBot. Win this layer first. Keywords are the easy part once the substrate is honest.

> **Scope:** Universal white-hat SEO program for SaaS web properties under 2026 Google policy (helpful content as a site-wide signal in core, March 2024 spam policies plus the 2026 back-button-hijacking malicious-practices policy, AI Overviews and AI Mode as separate citation surfaces with Google-reported traffic blended into Search Console Web data, INP as a primary CWV with `good` at <=200 ms and `poor` above 500 ms). Default stack: Next.js 16 App Router + Vercel + Supabase + Cloudflare DNS, but the methodology is stack-agnostic — substitute the equivalent metadata API, sitemap generator, edge redirect layer, and analytics integration for Astro / Remix / Rails / Django / WordPress / static-site stacks.

> **Mandatory framing:** This skill produces a **defensible SEO program with repo-grade deliverables** — PRs, content briefs, tracked issues, dashboards, change annotations — not a list of generic tips. Every recommendation carries a hypothesis, an expected impact, a tracking plan, and a rollback path. Every claim is labelled `confirmed | likely | hypothesis` (see [EVIDENCE-LABELS](references/EVIDENCE-LABELS.md)). The canonical knowledge base is `multi_agent_seo_guide.md` at the repo root, reconciled with current evidence per [GUIDE-RECONCILIATION](references/GUIDE-RECONCILIATION.md).

> **Score convention:** every skill-owned score is `0` worst to `1000` best. Do not introduce 0-1, 0-4, 0-10, 0-100, letter-grade, or percentage scores for prioritization, content quality, citation readiness, authority, experiments, or QA. If a third-party tool exposes a native score (for example Lighthouse's raw `0-1` API or `0-100` UI), label it as `raw` and report the normalized `score_0_1000` alongside it.

---

## QUICK START

1. **Onboard the target.** Confirm the project location, the public production URL, the staging URL if any, and which analytics / Search Console properties already exist. Use [INTAKE-CHECKLIST](references/INTAKE-CHECKLIST.md). If GSC, Bing Webmaster Tools, GA4, or a rank tracker is missing, offer to wire it now — see [WIRING-OBSERVABILITY](references/WIRING-OBSERVABILITY.md).
2. **Pick a working surface.** Default = a branch on the existing repo with one PR per phase. Alternatives: a sibling directory `<repo>__seo_pass` initialised as a worktree, or direct commits if explicitly authorised. See [WORKING-SURFACE](references/WORKING-SURFACE.md). Confirm with the user before writing.
3. **Pick a primary mode** from the [MODE ROUTER](#mode-router) below.
4. **Run discovery first.** Even on `traffic-drop-triage` and `programmatic-launch-review` modes, do not prescribe before [Phase 1](#phase-1--discovery--baseline) baselines exist. Diagnose before rewriting.
5. **Execute phases in dependency order.** Phases 2–5 can fan out in parallel after Phase 1; Phase 6 (implementation) gates on the audit; Phases 7–9 run after Phase 6 ships; Phases 10–13 close the loop.
6. **For every recommendation, emit a [DECISION CARD](assets/DECISION-CARD.md):** hypothesis, expected impact, tracking plan, rollback path, owner, ship-by, recheck-by.

For token-cheap routing during an actual engagement, read [AGENT-QUICKREF](references/AGENT-QUICKREF.md) first; it maps common user intents to the exact references and scripts to load. Use [ANALYSES-LAYOUT](references/ANALYSES-LAYOUT.md) and [SCRIPT-IO-CONTRACTS](references/SCRIPT-IO-CONTRACTS.md) when resuming another agent's run or wiring dashboards against script outputs.

If a referenced sibling skill (`/bun`, `/og-share-images`, `/de-slopify`, `/idea-wizard`, `/ab-testing`, `/vercel`, `/gh-cli`, `/ubs`, `/ga4`, `/supabase`, `/ux-audit`, `/vercel:next-cache-components`) is not installed, install via `jsm install <skill>` if `jsm` is authenticated; otherwise note the gap in `analyses/skill-availability.md` and continue with manual fallback.

---

## MODE ROUTER

| Mode | Use when | Must finish with |
|---|---|---|
| `greenfield-seo` | New SaaS, no SEO program, < 50 indexable pages | Full Phase 1–11 pass + 90-day plan |
| `mature-site-audit` | Existing program, > 500 indexed pages, organic traffic > 0 | Audit-driven phases 1, 3, 5, 8 + targeted fixes in 6 |
| `traffic-drop-triage` | Sudden organic decline, post-deploy regression, post-core-update drop | Phase 1 (focused) + [TRAFFIC-DROP-PLAYBOOK](references/TRAFFIC-DROP-PLAYBOOK.md) before any Phase 6 work |
| `programmatic-launch-review` | About to ship a large template family (locations, integrations, comparisons, templates) | [PROGRAMMATIC-GATES](references/PROGRAMMATIC-GATES.md) + small-batch staged rollout |
| `migration` | Domain change, framework rewrite, URL restructure, design-system swap | [MIGRATION-CHECKLIST](references/MIGRATION-CHECKLIST.md) + redirect map + post-launch monitoring |
| `ai-visibility-pass` | User wants AI Overview / ChatGPT / Perplexity citation lift | Citation audit + extractable-passage rewrites + entity consistency pass |
| `core-update-response` | A confirmed broad core update overlaps the drop window | [CORE-UPDATE-PLAYBOOK](references/TRAFFIC-DROP-PLAYBOOK.md#core-update-specific-core-update-mode) — segmentation before rewrite |
| `lifecycle-content` | Acquisition is fine; activation, expansion, or retention need search-driven help | Lifecycle page set: implementation, migration, security, procurement, troubleshooting |
| `maintenance` | Quarterly upkeep, content decay sweep, link health pass | Content-inventory refresh + decay queue + structured-data revalidation |

The mode is the *primary* lens. Most engagements still touch all phases — the mode decides which phases get the deepest investment and which can be a checkpoint.

---

## THE SAAS-SEO KERNEL — Universal Axioms

<!-- SEO_KERNEL_START v1.0 -->

These axioms are default truths. If an edge case appears to break one, document why before treating it as an exception.

**Axiom 0 — Search systems cannot reward what they cannot crawl, render, canonicalize, or index.** Foundation comes first; keyword strategy without a clean substrate is theatre. Every program starts with a crawl + render diff, not a brainstorm.

**Axiom 1 — One coherent story must be told by every signal.** Internal links, sitemap, canonical tag, redirect rules, `hreflang`, structured data, Open Graph, and rendered HTML must agree about which URL owns which intent. Disagreement is the most common quiet ranking suppressor.

**Axiom 2 — Helpful content is a site-wide classifier signal, integrated into core.** Since March 2024 there is no separate "Helpful Content Update" — it is a continuously evaluated signal that drags every page on a site if a meaningful share is unhelpful. Thirty thin programmatic pages can quietly suppress seventy good ones. Prune ruthlessly before publishing more.

**Axiom 3 — Programmatic SEO must clear the scaled-content-abuse tripwire.** Pages that exist primarily to capture search traffic without unique value are abuse, regardless of how they were authored — automation or humans. The bar is real per-page value, real underlying data, and a maintenance contract. Token-swap doorways will get the whole template family demoted.

**Axiom 4 — Critical metadata must be present in raw HTML.** Title, meta description, canonical, robots directive, primary heading, primary content, and primary structured data must be in the initial response. Googlebot can render JavaScript after crawl, and Next.js streaming metadata is interpreted by bots that execute JavaScript and inspect the DOM, but HTML-limited bots and many answer-engine retrieval fetchers should be treated as raw-HTML consumers unless the target property's own fetch/render tests prove otherwise. Stream what improves UX; do not stream away the content or metadata that must be crawled, cited, or shared.

**Axiom 5 — INP is now load-bearing, but not a fixed rank-loss formula.** Google uses Core Web Vitals in ranking systems, and official thresholds define `good` INP at <=200 ms and `poor` above 500 ms. Treat failing INP as a competitive quality and conversion risk, not as a guaranteed "N positions lost" claim unless a source-logged study or first-party experiment supports that estimate for this property. The hidden offender on SaaS marketing pages is usually a heavy dashboard component pattern leaking into a hero or pricing page (chart libraries, marketing-CRM widgets, consent banners that block main thread).

**Axiom 6 — Schema mirrors visible content. Always.** Structured data that claims awards, ratings, FAQs, reviews, or expert review the page does not visibly contain is a manual-action vector. `FAQPage` rich results are no longer a broad commercial tactic; `HowTo` rich results are deprecated; `Sitelinks Searchbox` is retired. Plan around what is *currently supported*, not what 2019 blogs still recommend.

**Axiom 7 — AI Overviews and AI Mode are separate surfaces, but not separate SEO rulebooks.** Google says no special AI file, AI-only markup, or special schema is required; pages must satisfy normal Search technical requirements, be snippet-eligible, expose important content textually, and provide helpful, original value. Third-party citation studies are useful but volatile; log their source, methodology, date, query set, and recheck-by before using specific percentages. The durable operator is evidence extractability: pages with dated, source-backed, self-contained passages and multiple unique data points are better candidates for citation than generic summaries. Win citation by being the *evidence source*, not by being a clean summary of competitors.

**Axiom 7b — Query fan-out changes content planning.** AI Mode and AI Overviews may issue multiple related searches across subtopics and data sources before composing a response. For SaaS pages, this means a priority page should cover the user's main query plus the adjacent proof questions an answer engine will fan out to: pricing proof, security proof, migration friction, integration details, current screenshots, comparative limitations, and next-step actions. Do not stuff; build answerable subtopics with visible evidence.

**Axiom 8 — Branded demand is moat.** Branded queries do not save you from a core update, but they reduce dependence on generic informational traffic and survive AI Overview compression best. Pricing, comparison, security, alternatives, refund, and changelog pages are revenue infrastructure — not "SEO content."

**Axiom 9 — Lifecycle content has compounding returns.** Implementation guides, migration docs, security/procurement pages, and troubleshooting articles convert indirectly via reduced sales friction, support deflection, faster activation, and lower churn. Measure them with assists, deflection, activation, and retention — not just first-touch organic.

**Axiom 10 — Every change is annotated.** Search Console annotations, GA4 events, and a `seo-changelog.md` in the repo. Future you will thank present you when traffic moves and you need to know whether to attribute it to a redirect, an algo update, a content refresh, a price change, or a CDN config edit.

**Axiom 11 — Plans atrophy on contact with releases.** SaaS releases ship SEO regressions through ordinary product work — consent banners, route-group changes, design-system swaps, locale routing, RSC component restructures. Add SEO release QA on a representative URL set; do not rely on the SEO team noticing in the dashboard a week later.

**Axiom 12 — The substrate must agree with itself.** Internal links, sitemap, canonical tag, redirect rules, `hreflang` alternates, JSON-LD, OG tags, robots directive, and rendered HTML must converge on the same canonical URL for each query family. The single most common quiet ranking suppressor on SaaS sites is a cluster where these signals disagree — Google clusters then picks the wrong canonical, or doesn't index at all. Phase 3 audits canonical clusters before anything else.

**Axiom 13 — Lifecycle content compounds.** Implementation guides, migration docs, security/SOC2/HIPAA pages, procurement / vendor-review pages, troubleshooting articles, integration docs, customer-education hubs — these convert indirectly via reduced sales friction, support deflection, faster activation, and lower churn. Measure them with assists, deflection, activation, retention. T2+ programs that ignore lifecycle content leave the highest-CR landing pages unbuilt.

**Axiom 14 — Branded demand is the durable moat.** A SaaS that builds branded demand survives algorithm volatility. Pricing, security, comparison, refund/cancellation, status, changelog, integrations, customer stories, careers, about, partner — these are revenue infrastructure, not "SEO content." When a core update wipes out generic informational pages, branded queries keep converting at near-baseline within 7-14 days. Make every priority page reachable from a branded entry point.

**Axiom 15 — Programmatic templates either compound or poison.** Real per-page differentiation + maintenance contract + staged rollout + kill switch = compounds. Token-swap doorways = scaled-content-abuse demotion that drags every other page on the site via the helpful-content classifier. The bar is unique value per page, not unique strings. Run [PROGRAMMATIC-GATES](references/PROGRAMMATIC-GATES.md) before launch every time, including incremental expansions of existing template families.

<!-- SEO_KERNEL_END v1.0 -->

---

## VERIFICATION-FIRST OVERLAY

This skill follows a verification-first model for any claim that drifts with Google policy, Search Console feature changes, schema documentation, CWV thresholds, or framework-specific SEO surface changes.

- **Evergreen methodology** comes from the kernel, operators, mode router, and `multi_agent_seo_guide.md`.
- **Volatile signals** must be checked against live primary sources before they ship into a recommendation. See [VERIFICATION-FIRST](references/VERIFICATION-FIRST.md).
- **Audit trail required:** every live-source check belongs in `analyses/source-log.md` with date, source URL, and the specific claim it supports.
- **Numerical volatility guard:** exact rank-delta, CTR-uplift, citation-overlap, and "X times more likely" figures are never kernel facts. If they are not source-logged with methodology and a recheck date, downgrade them to `hypothesis` or remove the number from the downstream recommendation.

Mandatory verification triggers:

- Any CWV threshold or page-experience claim → check `https://web.dev/articles/inp` and Google Search Central pages dated within the last 12 months.
- Any Google policy claim (helpful content, scaled content, site reputation abuse, expired domains, malicious practices / back-button hijacking, AI snapshot citation behaviour) → check `developers.google.com/search/blog` and `developers.google.com/search/docs/essentials/spam-policies`.
- Any structured-data eligibility claim → check `developers.google.com/search/docs/appearance/structured-data` for the specific type.
- Any Next.js metadata / sitemap / robots / `next/og` API claim → check `nextjs.org/docs/app/api-reference` for the version actually used.

The reconciliation table between `multi_agent_seo_guide.md` and current evidence is in [GUIDE-RECONCILIATION](references/GUIDE-RECONCILIATION.md). Where the guide and current evidence disagree, **current evidence wins** and the discrepancy is logged.

---

## COGNITIVE OPERATORS — SEO Thinking Moves

Composable moves applicable to any page, template, query family, or release. See [OPERATORS](references/OPERATORS.md) for the full card library with triggers, failure modes, and prompt modules.

- **§ Crawl-Render Diff** — "Does the raw HTML for this URL contain the title, meta, canonical, primary content, and links the rendered HTML claims?"
- **⧉ Canonical-Cluster Coherence** — "Do internal links, sitemap, canonical tag, redirect chain, `hreflang` alternates, and parameter rules all point at the same preferred URL for this query family?"
- **⌖ Intent-Format Match** — "Is the SERP for this query showing video / product / local / forum / answer / standard? Does the page format match what users actually expect?"
- **⊕ Striking-Distance Lift** — "Is this page in average position 4–15 with steady impressions? What is the smallest change that moves it to top 3?"
- **⚑ Programmatic-Quality Gate** — "Does each generated page have unique value, real data, a maintenance owner, and a kill switch? Or is this a token-swap doorway dressed as a template?"
- **⚒ INP Component Hunt** — "Which component on this marketing page is leaking dashboard-tier interaction cost? Chart lib? Consent banner? Marketing CRM widget?"
- **⊠ Snippet Curation Pass** — "Is this template's title pattern intent-matched? Is the meta description ad-copy quality? Will the SERP CTR exceed 3 % at average position?"
- **⌬ AI-Citation Extractability** — "Are there self-contained, dated, sourced passages with three or more unique data points that an answer engine can quote without context?"
- **⌭ Query Fan-Out Coverage** — "If AI Mode decomposes this query into five related searches, does this page or cluster contain the supporting proof pages it will need?"
- **◫ AI Measurement Humility** — "Is this claim based on first-party citation logs, GSC blended Web data, or a volatile third-party study? Are we reporting the uncertainty correctly?"
- **⇲ Trust Surface Audit** — "Are author bios, methodology pages, public methodology, dated reviews, screenshots, and corrections policy visible — or just claimed?"
- **⊘ Soft-404 Sniff** — "Does this 'page not found' or 'no results' route return 200? Is this empty-state shell silently inflating soft-404s in GSC?"
- **⇆ Locale-Loop Check** — "Do `hreflang` alternates reference each other reciprocally? Are auto-redirects trapping crawlers in the wrong region?"
- **⌁ Release-Day Tripwire** — "Did this release change routing, rendering, consent banners, navigation, or the design system? Did the representative URL set get re-checked?"
- **⌗ Branded-vs-Non-Branded Split** — "When traffic moved, did branded and non-branded move together or separately? They have different diagnostic implications."
- **⊞ Anti-Cannibalization Owner** — "Which URL owns this query family canonically? Does any other URL compete for it under a different intent?"

---

## TIER TRIAGE — Route Depth to Stage

Calibrate the program to where the SaaS actually is. A pre-product-market-fit company should not invest in a 200-page programmatic locations template. A scaled multi-product company should not stop at "fix metadata on the homepage."

| Tier | Profile | Indexable URLs | Organic baseline | Primary investment |
|---|---|---|---|---|
| **T1 — Pre-launch / pre-PMF** | < 20 employees, < $1M ARR, < 6 mo since launch | < 30 | minimal | Phases 1, 3 (lite), 4 (commercial pages only), 6 (foundation), 8 (wire observability) |
| **T2 — Early growth** | $1M–$10M ARR, finding ICP | 30–300 | growing | Add Phases 2, 5, 7 (start), 9 (lite), 11–13 |
| **T3 — Scaled** | $10M–$100M ARR, multi-product or multi-segment | 300–5000 | meaningful share of pipeline | Full 13-phase pass, parallel agents, programmatic where justified, log analysis on |
| **T4 — Enterprise / mature** | $100M+ ARR, multi-region, multi-locale, large content team | 5000+ | a primary growth channel | Continuous program: monthly Phase 8 + quarterly 1, 3, 10, 13; programmatic governance; international + locale program |

Complexity overlays (bump up regardless of revenue): multi-region / `hreflang`, marketplace UGC, ecommerce-style merchant feeds, regulated vertical (health/finance/legal), large doc/support corpus, long-tail integrations or templates business.

See [TIER-ROUTING](references/TIER-ROUTING.md) for full routing logic and depth selectors per phase.

---

## THE 13-PHASE PROGRAM

Each phase produces concrete artifacts under `analyses/`, `deliverables/`, or as PRs against the SaaS repo. Phases 2–5 fan out via subagents on per-cluster, per-template, or per-data-source slices. Use [PHASE-DAG](references/PHASE-DAG.md) for the full dependency graph.

### Phase 1 — Discovery & Baseline

**Goal:** know the substrate before prescribing.

**Inputs:** project root, prod URL, staging URL, GSC, GA4, log files (if any), seed keyword list (if any).

**Activities (parallelizable per data source):**

- Crawl prod + staging via Playwright (`scripts/crawl.ts`); capture raw HTML, rendered HTML, status, redirect chains, canonical, robots directive, structured data, internal/outbound links, image weights.
- Pull GSC performance (16 mo), coverage, sitemaps, manual actions, CWV report → `analyses/gsc/` JSON exports.
- Pull GA4 organic landing-page report, conversion paths, branded vs non-branded split → `analyses/ga4/`.
- Snapshot CWV field data via CrUX API for representative templates → `analyses/crux/`.
- Snapshot lab CWV via Lighthouse CI for the representative URL set → `analyses/lighthouse/`.
- Inventory page templates by route group / data source → `analyses/template-inventory.md`.
- Reverse-engineer current information architecture from `app/` directory + nav scrape → `analyses/ia-current.md`.
- (T3+) Pull server logs for verified Googlebot, Bingbot, GPTBot, ClaudeBot, PerplexityBot, anthropic-ai → `analyses/log-analysis.md`.
- Snapshot rankings for seed keywords (CTR-weighted) — use rank-tracker subscription if available, otherwise capture SERPs via Playwright on a clean profile.

**Deliverables:** `analyses/baseline-summary.md`, `analyses/representative-urls.json`, `analyses/seo-changelog.md` (initial annotation: program start).

**Subagents:** see `subagents/discovery-crawler.md`, `subagents/gsc-extractor.md`, `subagents/cwv-collector.md`, `subagents/log-analyst.md`. Spawn in parallel.

Full instructions: [PHASE-1-DISCOVERY](references/PHASE-1-DISCOVERY.md).

### Phase 2 — Keyword & Intent Research

**Goal:** the target query universe with intent classification, SERP-feature mapping, and pillar/cluster topology.

**Activities (parallelizable per competitor and per cluster):**

- Build the JTBD inventory from product surface area + ICP + sales transcripts (if any) → `analyses/jtbd.md`.
- Competitor gap analysis vs 3–5 named competitors → `analyses/competitors/<name>.md`.
- Query candidate list: branded + non-branded × informational / commercial / transactional / navigational → `analyses/query-universe.csv`.
- SERP feature scan per query: AI Overview presence, PAA, video, image pack, local, product, forum, news → `analyses/serp-features.csv`.
- Cluster into pillar + cluster topic maps; assign canonical owner URL per cluster → `analyses/topic-clusters.md`.
- Anti-cannibalization map (existing + planned) → `analyses/cannibalization-map.md`.
- Map each cluster to existing or planned page in the SaaS — never publish before a canonical owner exists.

**Deliverables:** `analyses/query-universe.csv`, `analyses/topic-clusters.md`, `analyses/cluster-owners.md`.

Full instructions: [PHASE-2-KEYWORD](references/PHASE-2-KEYWORD.md).

### Phase 3 — Technical SEO Audit

**Goal:** prioritized issue list with severity, effort, and expected impact — using the audit-item format from `multi_agent_seo_guide.md` §3.

**Activities (parallelizable per audit area):**

- Crawlability: `robots.txt` validity, sitemap content vs canonical truth, redirect chains, status-code health, Vary/Cache headers.
- Indexability: noindex audit, soft-404 inventory, duplicate/cluster mismatches, parameter handling, faceted-nav crawl traps.
- Rendering: raw vs rendered HTML diff per template, RSC streaming completeness, hydration mismatches, JS-only content, link-only-on-click anti-patterns.
- Structured data coverage and validity per template; agreement with visible content; current Google support per type.
- Internal link graph health: orphans, redirected internal links, anchor distribution, link concentration.
- INP/LCP/CLS regressions tied to specific components (use `scripts/cwv-by-component.ts`).
- Log-file crawl-budget analysis (T3+).
- Infrastructure: CDN cache rules, WAF / bot protection vs verified crawlers, edge redirect agreement, staging leak check.
- Metadata curation gaps per template (title pattern, description pattern, canonical, OG/Twitter, fallbacks).

**Output format (every audit item):**

```
Issue:        <concise defect>
Proof:        <URL, element, screenshot path, GSC export ref>
Consequence:  <crawl/index/CTR/rank/UX/conversion impact>
Remediation:  <concrete code/content change>
Confidence:   confirmed | likely | hypothesis
Severity:     critical | high | medium | low
Effort:       hours | days | weeks
Owner:        engineering | content | design | product | analytics | legal
Phase 6 PR:   <pr-slug>
```

**Deliverables:** `analyses/audit-issues.json` (machine-readable), `analyses/audit-summary.md` (human report), `analyses/representative-urls.json` (refined).

Full instructions: [PHASE-3-TECHNICAL](references/PHASE-3-TECHNICAL.md). See [AUDIT-CHECKLIST](references/AUDIT-CHECKLIST.md) for the full check inventory.

### Phase 4 — On-Page & Content Production

**Goal:** for each priority page, ship a brief + draft (or rewrite) that earns the SERP it targets.

**Per page deliverable:** title, meta description, H1, slug, schema type + JSON-LD, internal links in/out, content brief with intent / entities / supporting subtopics / proof requirements / word-count guidance / originality requirements, and either a rewrite of existing copy or a full new draft. Same agent that researched the cluster writes its content (`subagents/cluster-writer.md`).

**Quality gates:**

- All factual claims have a source link in the brief; `confirmed | likely | hypothesis` label per claim.
- At least three unique data points per page (research, screenshots, internal benchmark, dated quote, original analysis) — required for AI Overview citation eligibility.
- Slop-pattern check via `/de-slopify` (if installed) or [SLOP-CHECKLIST](references/SLOP-CHECKLIST.md).
- High-risk content gate (financial, legal, security, health) → [HIGH-RISK-GATE](references/HIGH-RISK-GATE.md) before indexable.

**Deliverables:** `deliverables/briefs/<cluster>/<page>.md`, `deliverables/drafts/<cluster>/<page>.md`.

Full instructions: [PHASE-4-CONTENT](references/PHASE-4-CONTENT.md). Brief template in [BRIEF-TEMPLATE](assets/BRIEF-TEMPLATE.md).

Phase 4 can be re-run repeatedly until marginal gains shrink; treat each cluster as an independent backlog.

### Phase 5 — Information Architecture & Internal Linking

**Goal:** turn isolated pages into a graph search systems and users can navigate.

**Activities:**

- Pillar/cluster topology with bidirectional links pillar ↔ cluster pages.
- Breadcrumb structure + `BreadcrumbList` schema sitewide.
- Hub pages for product surface, use cases, integrations, and resources.
- Contextual linking rules — descriptive anchors, no `nofollow` on internal, no through-redirect links.
- Anchor-text distribution targets per cluster (avoid over-optimization on commercial pages).
- Programmatic templates: only where the dataset has real per-page differentiation; gate via [PROGRAMMATIC-GATES](references/PROGRAMMATIC-GATES.md).
- Sitemap topology: split by page type and freshness class; keep `lastmod` honest; segment for diagnostic visibility.

**Deliverables:** `analyses/ia-target.md`, `deliverables/internal-link-pr.md` (the planned PR), `deliverables/sitemap-plan.md`.

Full instructions: [PHASE-5-IA](references/PHASE-5-IA.md).

### Phase 6 — Implementation in the SaaS Codebase

**Goal:** translate the audit + content into actual code changes, landed as logically grouped PRs with test plans.

**Translation matrix (Next.js 16 App Router default):**

| Audit finding | Code surface |
|---|---|
| Per-route metadata | `app/<route>/page.tsx` `export const metadata` or `generateMetadata({ params })` |
| Site-wide canonical / OG defaults | `app/layout.tsx` `metadata.metadataBase` + `alternates.canonical` per route |
| Sitemap | `app/sitemap.ts` (or split: `app/sitemap.ts` + per-segment sitemaps) |
| Robots | `app/robots.ts` |
| Structured data | `<script type="application/ld+json">` rendered by RSC component, never injected from useEffect |
| OG / Twitter image | `app/<route>/opengraph-image.tsx` and `twitter-image.tsx` via `next/og` `ImageResponse` (use `/og-share-images`) |
| Redirects | `next.config.ts` `redirects()` for stable rules; middleware for dynamic; edge for host/protocol/locale |
| Performance | RSC where possible; `<Image>` with width/height; no LCP image lazy-loaded; Cache Components on Next 16 (`/vercel:next-cache-components`) |
| Content gating that affects indexability | Public marketing routes must server-render content; auth-gated content uses `noindex` + access control, not robots-only |
| Internal linking PRs | Often touches `app/components/Footer.tsx`, breadcrumb component, hub-page components, and per-cluster MDX/CMS content |
| Supabase RLS / data-driven pages | Verify SSR fetch path runs with appropriate role; never expose personal data via public pages |

**Default PR cadence (one per logical group):**

1. `seo/foundation`: `metadataBase`, `robots.ts`, `sitemap.ts`, redirect cleanups, canonical helper.
2. `seo/per-route-metadata`: `generateMetadata` on every public route + canonical alternates.
3. `seo/structured-data`: Organization/WebSite/SoftwareApplication or WebApplication on relevant pages, BreadcrumbList sitewide.
4. `seo/og-images`: dynamic OG/Twitter via `next/og`.
5. `seo/perf-cwv`: image, font, RSC, cache-components fixes for INP/LCP/CLS regressions identified in Phase 3.
6. `seo/internal-links`: link-graph PR per IA plan.
7. `seo/content-<cluster>`: one PR per cluster from Phase 4.
8. `seo/programmatic-<template>`: gated, staged rollout per template family.

**Per PR:** test plan (unit + Playwright SSR check + Lighthouse CI delta), expected impact, rollback path, recheck-by date, GSC annotation.

Full instructions: [PHASE-6-IMPLEMENTATION](references/PHASE-6-IMPLEMENTATION.md). Next.js patterns in [NEXTJS-PATTERNS](references/NEXTJS-PATTERNS.md). Stack adapters in [STACK-ADAPTERS](references/STACK-ADAPTERS.md).

### Phase 7 — Off-Page & Authority Strategy

**Goal:** earned links and citations from genuinely useful assets — no PBNs, no paid links presented as editorial, no automated outreach spam.

**Activities:**

- Linkable-asset ideation tied to product evidence (benchmark, calculator, public dataset, free tool, definitive guide, comparison matrix).
- Digital PR angle inventory: original-data hooks, expert commentary opportunities, industry-event windows.
- Outreach lists: HARO/Qwoted-style, integration partner directories, complementary-tool audiences.
- Brand mention reclamation (unlinked mentions → link request via author / press contact).
- Third-party platform discoverability: GitHub, product directories, integration marketplaces, app stores, review sites — current screenshots, current copy, current category fit.
- Realistic 90-day plan tracked in beads or GitHub issues with owners and ship dates.

**Deliverables:** `deliverables/authority-plan.md`, beads issues per asset and per outreach campaign.

Full instructions: [PHASE-7-AUTHORITY](references/PHASE-7-AUTHORITY.md).

### Phase 8 — Analytics, Dashboards & Reporting

**Goal:** one place to see indexed-page count, impressions, clicks, CTR, average position, conversions per cluster, INP/LCP percentiles, schema coverage, internal-link health.

**Wiring (default):**

- GSC domain property verified; sitemap submitted; bulk export to BigQuery enabled if T3+.
- Bing Webmaster Tools verified; sitemap submitted.
- GA4 with conversion events for signup, trial, demo, paid, onboarding completion (`/ga4` skill).
- (Optional, common) PostHog or Plausible already present — wire into the same dashboard rather than replacing.
- CrUX API + Lighthouse CI in repo (PR-time CWV regression checks per representative URL).
- Schema validation in CI (`scripts/validate-schema.ts` against the representative URL set).
- Internal-link health cron (orphan detection + redirect-through-internal-link detection).

**KPI targets (define per tier):** indexed-page count by sitemap group, impressions and clicks per cluster (4–12-week trend), CTR by template, average position by cluster, branded-vs-non-branded split, organic-to-trial conversion by landing page, INP/LCP/CLS p75 by template, GSC enhancement-error count, AI citation presence / share-of-voice from manual or semi-automated logs. Treat GSC Web performance as a blended outcome metric, not a direct AI-citation report.

**Reporting cadence:** weekly self-serve report template; monthly executive cockpit (revenue / leads / branded vs non-branded / shipped vs refreshed vs merged vs removed / earned mentions / risks).

**Deliverables:** `deliverables/dashboard-spec.md`, `deliverables/weekly-report-template.md`, `deliverables/monthly-exec-template.md`.

Full instructions: [PHASE-8-ANALYTICS](references/PHASE-8-ANALYTICS.md).

### Phase 9 — Experimentation & Iteration

**Goal:** test hypothesis-driven changes with stopping rules, not vibes.

**Test types (search-safe):**

- Title-tag tests (segment-split, not cloaked variants).
- Meta-description tests (CTR primary metric).
- Content-template tests (segment-split).
- Internal-link density tests (group of templates A vs B).

**Rules (from guide §20 + current Google guidance):**

- Use canonical tags on alternate test URLs pointing to the original; use temporary redirects for variant URLs.
- Keep primary content, canonicals, robots, and structured data stable unless the test is explicitly about those.
- Predefine stopping rule and minimum sample size before launch.
- End tests on schedule; remove variant scripts and revert metadata on losers.
- Document every test in `analyses/experiments/<id>.md`; annotate GSC and analytics.
- Use `/ab-testing` skill for the assignment infrastructure if not already in place.

**Deliverables:** `analyses/experiments/`, `deliverables/experimentation-runbook.md`.

Full instructions: [PHASE-9-EXPERIMENTATION](references/PHASE-9-EXPERIMENTATION.md).

### Phase 10 — Fresh-Eyes Review & QA

**Goal:** independent verification before deploy.

**The three fresh-eyes prompts (run as separate subagents on Phases 4–8 outputs):**

1. *Bug-hunt the new code* — `subagents/fresh-eyes-bughunt.md`. Review the code changes shipped in Phase 6 PRs as if you had not seen them before. Flag rendering-mode mistakes, route-group regressions, structured-data drift, edge-redirect ordering, CWV regressions.
2. *Randomly trace files for issues* — `subagents/fresh-eyes-trace.md`. Sample N files from the diff and trace them end-to-end (server, network, render, CWV) for any defect that obviously matters but was missed.
3. *Review fellow agents' work* — `subagents/fresh-eyes-cross-review.md`. Each cluster writer reviews another cluster's draft for factual accuracy, brand-voice fit, slop patterns, and hidden cannibalization.

**Tooling:** typecheck, lint, build, `/ubs`, `bun test` (or stack equivalent).

**Iteration rule:** two clean passes in a row before Phase 11.

Full instructions: [PHASE-10-FRESH-EYES](references/PHASE-10-FRESH-EYES.md).

### Phase 11 — Deployment & Verification

**Goal:** ship the PRs and reset baselines correctly.

**Activities:**

- Vercel deploy via `/vercel` skill or self-hosted target; ensure preview URL Lighthouse CI green vs main before promote.
- GSC: validate property, submit updated sitemaps, request indexing for highest-priority new URLs (rate-limited, do not abuse).
- Bing Webmaster: re-submit sitemap.
- Rank tracker baseline reset on the day of deploy with annotation.
- `/gh-cli` skill for PR flow, milestones, and post-deploy ticket triage.
- Annotate `seo-changelog.md` and GA4 with the deploy timestamp and the PR scope.

Full instructions: [PHASE-11-DEPLOY](references/PHASE-11-DEPLOY.md).

### Phase 12 — Live-Site Playwright Verification

**Goal:** confirm what shipped is actually visible to crawlers.

**Per representative URL on prod:**

- Meta tags rendered server-side (raw HTML check, no JS execution).
- JSON-LD validates against schema.org for declared types.
- OG/Twitter images return 200 with correct dimensions and weight.
- Sitemap reachable, parseable, and contains only canonical indexable URLs.
- `robots.txt` parses and references the sitemap.
- Canonical tags consistent with the IA plan; redirect chains have one hop max.
- No hydration-driven content invisible to crawlers (compare raw HTML to rendered DOM at network-idle).
- INP and LCP under thresholds via Lighthouse CI on representative pages (mobile profile).
- AI-crawler view: fetch with `User-Agent: GPTBot` and `User-Agent: ClaudeBot` and confirm primary content is in initial HTML.

**Tooling:** `scripts/verify-prod.ts` (Playwright), `scripts/validate-schema.ts`, `scripts/cwv-check.ts`.

**Output:** `analyses/post-deploy-verification.md` — pass/fail per check, with raw evidence paths.

Full instructions: [PHASE-12-VERIFICATION](references/PHASE-12-VERIFICATION.md).

### Phase 13 — Idea Wizard Pass for Compounding Wins

**Goal:** fresh agent reviews the live site and the SEO plan looking for high-leverage moves the prior phases missed.

**Use `/idea-wizard` if installed.** Sweep dimensions:

- Programmatic opportunities the current dataset already supports but no template exists.
- Missing schema types (e.g., `Course` for an academy, `Dataset` for a real public benchmark or downloadable/queryable dataset, `Event` for live webinars, `JobPosting` for a careers page, `HowTo` only after a current-docs check confirms the target surface still benefits).
- Fresh ranking-system signals (whatever is hot in current Google Search Central blog within 90 days).
- Content-decay candidates due for refresh (use `analyses/content-inventory.md` × position drift × claim-staleness flags).
- Competitive moats worth building (linkable-asset gaps competitors have not filled).
- AI Overview / AI Mode / ChatGPT / Perplexity citation gaps where a small extractable-passage edit or query fan-out support page could earn citations.
- Query fan-out gaps: proof questions an answer engine is likely to issue around pricing, security, migration, integrations, limitations, screenshots, and next-step actions.

**Output:** `deliverables/compounding-backlog.md` — prioritized list with EV estimate, effort, owner; user can `/schedule` background agents for the long-tail items.

Full instructions: [PHASE-13-COMPOUNDING](references/PHASE-13-COMPOUNDING.md).

---

## DELIVERABLE TEMPLATES

Every phase emits the same shape of artifact:

- **Audit items:** Issue / Proof / Consequence / Remediation / Confidence / Severity / Effort / Owner / Phase 6 PR.
- **Page briefs:** intent, audience, canonical URL, primary entity, supporting entities, three-plus unique data points, internal links in/out, schema type, conversion goal, refresh cadence, slop-check pass, brand-voice notes, success metric, recheck-by date.
- **Decision cards:** hypothesis, expected impact, tracking plan, rollback path, owner, ship-by, recheck-by. See [DECISION-CARD](assets/DECISION-CARD.md).
- **Experiment cards:** hypothesis, primary metric, guardrail metrics, segment split, minimum sample, stopping rule, end date, decision rule.
- **PR descriptions:** summary, audit issues addressed (IDs), test plan, expected impact, rollback, recheck-by, GSC annotation note.

Each artifact carries a `confidence` label and the evidence it is based on. Items that cannot be confirmed go to the **unknowns queue** (`analyses/unknowns.md`) and either expire into a confirmed finding or get closed out — they do not silently graduate to recommendations.

See [DELIVERABLES-INDEX](references/DELIVERABLES-INDEX.md).

---

## RECONCILING THE GUIDE WITH CURRENT EVIDENCE

The canonical knowledge is `multi_agent_seo_guide.md`. Where current evidence (verified per [VERIFICATION-FIRST](references/VERIFICATION-FIRST.md)) refines or contradicts the guide, this skill takes the current evidence position. The full table is in [GUIDE-RECONCILIATION](references/GUIDE-RECONCILIATION.md). Notable deltas as of the `last_reviewed` date in this skill:

- **INP threshold weight:** the guide treats CWV as competitiveness baselines rather than magic ranking levers. Current official evidence confirms the thresholds (`good` INP <= 200 ms, `poor` > 500 ms) and says CWV are used by ranking systems, but it does **not** support a fixed rank-loss formula. Treat INP < 200 ms p75 as a *baseline* and < 150 ms p75 as a *competitive target* on commercial templates; use exact position-impact estimates only when source-logged for the target market or measured in first-party experiments.
- **AI Overview citation correlation:** the guide notes AI answer engines as an additional surface. Current practice: plan AI visibility as a separate workstream with its own evidence assets. Use early-2026 citation-overlap percentages, "3+ unique data points" multipliers, and CTR-uplift numbers only as `likely` or `hypothesis` claims with a source-log entry and quarterly recheck.
- **AI features measurement:** current Google guidance says AI Overviews and AI Mode traffic is included in Search Console Performance under the Web search type, but not exposed as a clean citation report. Treat GSC as a blended outcome metric, and maintain manual / semi-automated citation logs for source attribution.
- **AI optimization files / markup:** current Google guidance says no machine-readable AI text file or special schema is required for AI features. `llms.txt` may be a documentation convenience; it is not a ranking or citation lever.
- **Helpful Content System:** the guide describes E-E-A-T-style trust signals. Current evidence: since March 2024 the helpful content classifier is integrated into core ranking and operates as a *site-wide* signal that drags helpful pages on a site with too much unhelpful content. Prune before publishing.
- **Site reputation abuse:** confirmed enforcement starting May 5, 2024. Third-party content hosted on a primary domain mainly to exploit host signals is now a documented spam policy. The guide flags this; current evidence confirms it is actively enforced.
- **Back-button hijacking:** Google announced this as an explicit malicious-practices spam-policy violation in April 2026, with enforcement beginning June 15, 2026. Any release touching SPA navigation, overlays, modals, exit-intent flows, pushState/replaceState, or ad/affiliate redirects gets a browser-history QA check.
- **`llms.txt`:** the guide treats it as a low-cost convenience without proven ranking value. Current evidence: a 300k-domain analysis found no statistically significant correlation with AI citation; major AI companies have not committed to acting on the file. Treat as optional documentation; do not invest as a ranking tactic.
- **`HowTo`, `FAQPage`, `Sitelinks Searchbox`:** confirmed deprecated/restricted as the guide states. Do not plan rich-result strategy around them.
- **AI crawler JS rendering:** Googlebot renders JS after crawl. HTML-limited bots and answer-engine retrieval fetchers vary, so the operational stance is to make citation-critical content present in raw HTML, then verify with `scripts/ai-crawler-view.ts` and live fetches for the target bots.

Conflicts found later are appended to `analyses/source-log.md` with date, source URL, and the specific change to the recommendation.

---

## ANTI-PATTERNS

| Don't | Why | Do instead |
|---|---|---|
| Ship a programmatic template family in one batch | Scaled-content-abuse tripwire; whole template demoted | Staged rollout per [PROGRAMMATIC-GATES](references/PROGRAMMATIC-GATES.md); kill switch ready |
| Add `FAQPage` schema to commercial pages for rich results | Largely deprecated commercial use; risks misuse signal | Only on real, visibly-rendered FAQs that match Google's current eligibility |
| Inject JSON-LD from `useEffect` on the client | Crawlers / AI bots may not see it; raw HTML is the truth | Render JSON-LD from a Server Component; verify in raw HTML |
| Lazy-load the LCP image | Tanks LCP; common in carousel patterns | `priority` (or non-lazy) for above-fold; lazy below-fold |
| Canonical every paginated page to page 1 | Strands content; conflicts with current guidance | Self-referencing canonical per page; let pagination cascade naturally |
| Block CSS / JS / API in `robots.txt` | Breaks rendering; suppresses content discovery | Allow render-critical resources; `noindex` only what is sensitive |
| Use `noindex` to "save crawl budget" on huge URL spaces | Google still has to fetch each page to see the directive | Prevent generation, block via `robots.txt`, or canonicalize at the source |
| Redirect retired pages to the homepage | Soft-404 behaviour; bad UX | `404`/`410` if no replacement; redirect only to a real substitute |
| Treat AI-Overview citation as guaranteed by ranking | Decoupled surfaces; exact overlap figures are volatile and query-set dependent | Evidence-led extractable-passage strategy with three-plus unique data points per page |
| Treat AI Mode / AI Overview traffic in GSC as directly segmentable | Google blends AI feature data into the Web search type today | Pair GSC trend analysis with `analyses/ai-citations.csv`, SERP snapshots, and referrer logs |
| Add `llms.txt` or AI-only schema and call it an AI SEO strategy | Google says no special AI text files or markup are needed for AI features | Make important content textual, crawlable, indexable, snippet-eligible, and evidence-rich |
| Add CWV "fixes" without measuring component cost | Optimization theatre, often regressions elsewhere | Component-level INP/LCP attribution, then targeted fix; verify in CrUX field data |
| Author content with one big LLM dump | Slop patterns, factual drift, scaled-content risk | Brief → research → draft with proof requirements → human owner → slop-check |
| Index internal search results | Doorway risk; thin pages | Curated-only landing pages; `noindex` general results |
| Use `hreflang` to deduplicate near-identical English pages | `hreflang` is for genuinely localized content | Consolidate or differentiate; do not paper over with annotations |
| Force a redirect to user's region without `x-default` | Crawler trap; users can't reach other versions | `x-default` selector; do not auto-redirect verified crawlers |
| Manipulate browser history so Back does not return to the previous page | Explicit Google malicious-practices spam-policy violation; breaks user trust | Keep Back-button behavior native; test pushState/replaceState, modals, overlays, and redirects in Phase 10/12 |
| Skip GSC annotations | Future traffic moves are unattributable | Annotate every deploy, refresh, and content merge |
| Run experiments without canonicals to original | Index dilution + soft cannibalization | Variant URLs `canonical` to original; temporary redirects only |
| "Optimize for INP" by removing analytics | Breaks measurement, doesn't fix root cause | Profile, defer, code-split; keep analytics consent-aware |
| Treat metadata as a one-time setup | Drift from page on every release | Generate metadata from structured page data; CI check the rep URL set |
| Build a 200-page locations template with no local proof | Doorway pattern; demoted on next core update | Build only where there is real local presence, inventory, or service |
| Buy links / participate in PBN / mass guest post | Manual action risk; no durable value | Linkable-asset strategy + earned digital PR |
| Wait for the SEO team to notice a regression in GSC | Days-to-weeks lag; SEO debt compounds | SEO release QA on representative URLs in CI |

Full anti-pattern catalog: [ANTI-PATTERNS](references/ANTI-PATTERNS.md).

---

## SAFE-CHANGES MANDATE

This skill writes content, briefs, audits, dashboards, and code PRs against the SaaS repo. It does **not**:

- Push to production without explicit user authorization (`/vercel:deploy prod` is user-initiated).
- `git push --force` or `git reset --hard`.
- Submit to GSC / Bing using credentials not provided by the user in-session.
- Modify Stripe / billing / RLS without `/security-audit-for-saas` co-review.
- Ship programmatic template families without a kill switch and staged rollout.
- Auto-respond to manual actions or DMCA notices.

Confirm working surface, branch, and PR strategy with the user *before* writing. Default = a feature branch on the SaaS repo with one PR per logical group. Alternative = sibling worktree if user requests isolation.

---

## INTEGRATIONS WITH SIBLING SKILLS

| Need | Skill |
|---|---|
| Generate dynamic OG/Twitter images | `/og-share-images` |
| Slop-pattern review on drafts | `/de-slopify` |
| A/B testing infrastructure | `/ab-testing` |
| GA4 event wiring | `/ga4` |
| Vercel deploy + env + cache components | `/vercel`, `/vercel:next-cache-components`, `/vercel:deployments-cicd` |
| Supabase RLS / data-driven page review | `/supabase`, `/supabase:supabase-postgres-best-practices` |
| GitHub PR flow | `/gh-cli` |
| Bug scanning Phase 10 | `/ubs` |
| UX review (accessibility, mobile) | `/ux-audit` |
| Compounding-wins ideation Phase 13 | `/idea-wizard` |
| Issue tracking | `/beads-br`, `/beads-bv`, `/beads-workflow` |
| Schedule recurring SEO maintenance | `/schedule` |

If a referenced skill is missing, check `jsm` availability with `jsm --version`; if installed and authenticated, run `jsm install <skill>`. Otherwise note the missing skill in `analyses/skill-availability.md` and use the manual fallback documented in the relevant phase reference.

---

## PRECEDENCE & SAFETY RULES

- **Conflicts:** current Google evidence > `multi_agent_seo_guide.md` > common SEO blogs. Conflicts logged in `analyses/source-log.md`.
- **Confidence labels** are mandatory on every recommendation. `confirmed | likely | hypothesis`. Do not publish `hypothesis` claims as facts.
- **Severity** must be earned: `critical` means indexing-blocking, manual-action-pending, or revenue-blocking right now. Easy fixes are not automatically critical.
- **Unknowns:** items with insufficient evidence go to `analyses/unknowns.md` with a verification path. They do not graduate to recommendations without evidence.
- **Annotations:** every shipped change is annotated in GSC + GA4 + `seo-changelog.md`.

---

## QUALITY DISCIPLINE

The program is complete only when:

- The substrate is honest: raw HTML matches rendered HTML for representative URLs; canonical clusters agree; sitemaps contain canonical indexable URLs only; redirects are one-hop.
- Every priority page has a brief, an owner, a refresh cadence, and a visible conversion path.
- The IA tells one story across nav, footer, breadcrumbs, sitemap, internal links, and structured data.
- Performance is competitive: INP p75 < 200 ms on commercial templates; LCP p75 < 2.5 s; CLS p75 < 0.1.
- Observability runs without manual intervention: GSC + GA4 + CrUX + Lighthouse CI in repo.
- Two clean fresh-eyes passes have completed.
- Post-deploy Playwright verification passes on representative URLs.
- A 90-day plan with KPIs, checkpoints, and a recheck cadence is in the user's hands.

---

## REFERENCE INDEX

### Methodology

| Topic | File |
|---|---|
| Intake checklist | [INTAKE-CHECKLIST](references/INTAKE-CHECKLIST.md) |
| Agent quick reference | [AGENT-QUICKREF](references/AGENT-QUICKREF.md) |
| Wiring observability | [WIRING-OBSERVABILITY](references/WIRING-OBSERVABILITY.md) |
| Working surface decision | [WORKING-SURFACE](references/WORKING-SURFACE.md) |
| Verification-first protocol | [VERIFICATION-FIRST](references/VERIFICATION-FIRST.md) |
| Guide ↔ current-evidence reconciliation | [GUIDE-RECONCILIATION](references/GUIDE-RECONCILIATION.md) |
| Evidence labels | [EVIDENCE-LABELS](references/EVIDENCE-LABELS.md) |
| Tier routing | [TIER-ROUTING](references/TIER-ROUTING.md) |
| Cognitive operators | [OPERATORS](references/OPERATORS.md) |
| Phase dependency graph | [PHASE-DAG](references/PHASE-DAG.md) |
| 90-day plan (operationalized) | [90-DAY-PLAN](references/90-DAY-PLAN.md) |
| Analyses output layout | [ANALYSES-LAYOUT](references/ANALYSES-LAYOUT.md) |
| Script I/O contracts | [SCRIPT-IO-CONTRACTS](references/SCRIPT-IO-CONTRACTS.md) |

### Phases (deep dives)

| Phase | File |
|---|---|
| 1 — Discovery & Baseline | [PHASE-1-DISCOVERY](references/PHASE-1-DISCOVERY.md) |
| 2 — Keyword & Intent | [PHASE-2-KEYWORD](references/PHASE-2-KEYWORD.md) |
| 3 — Technical Audit | [PHASE-3-TECHNICAL](references/PHASE-3-TECHNICAL.md) |
| 4 — Content Production | [PHASE-4-CONTENT](references/PHASE-4-CONTENT.md) |
| 5 — IA & Internal Linking | [PHASE-5-IA](references/PHASE-5-IA.md) |
| 6 — Implementation | [PHASE-6-IMPLEMENTATION](references/PHASE-6-IMPLEMENTATION.md) |
| 7 — Authority | [PHASE-7-AUTHORITY](references/PHASE-7-AUTHORITY.md) |
| 8 — Analytics & Reporting | [PHASE-8-ANALYTICS](references/PHASE-8-ANALYTICS.md) |
| 9 — Experimentation | [PHASE-9-EXPERIMENTATION](references/PHASE-9-EXPERIMENTATION.md) |
| 10 — Fresh-Eyes Review | [PHASE-10-FRESH-EYES](references/PHASE-10-FRESH-EYES.md) |
| 11 — Deploy & Verify | [PHASE-11-DEPLOY](references/PHASE-11-DEPLOY.md) |
| 12 — Live Verification | [PHASE-12-VERIFICATION](references/PHASE-12-VERIFICATION.md) |
| 13 — Compounding Wins | [PHASE-13-COMPOUNDING](references/PHASE-13-COMPOUNDING.md) |

### Implementation references — by topic

#### AI / GEO visibility

| Topic | File |
|---|---|
| AI-visibility playbook | [AI-VISIBILITY](references/AI-VISIBILITY.md) |
| AI-citation operations (per-platform) | [CITATION-OPS](references/CITATION-OPS.md) |
| GEO / AI-visibility measurement | [GEO-MEASUREMENT](references/GEO-MEASUREMENT.md) |
| AI bot and `llms.txt` policy | [AI-BOTS-AND-LLMSTXT](references/AI-BOTS-AND-LLMSTXT.md) |

#### Schema & structured data

| Topic | File |
|---|---|
| Schema policy & per-type guidance | [SCHEMA-POLICY](references/SCHEMA-POLICY.md) |
| Schema cookbook (copy-paste JSON-LD) | [SCHEMA-COOKBOOK](references/SCHEMA-COOKBOOK.md) |

#### URL, redirects, i18n, migration

| Topic | File |
|---|---|
| Redirect / 410 / noindex decision tree | [REDIRECT-PLAYBOOK](references/REDIRECT-PLAYBOOK.md) |
| `hreflang` / i18n cookbook | [HREFLANG-COOKBOOK](references/HREFLANG-COOKBOOK.md) |
| Migration checklist | [MIGRATION-CHECKLIST](references/MIGRATION-CHECKLIST.md) |

#### Performance & rendering

| Topic | File |
|---|---|
| INP component-level deep dive | [INP-DEEP-DIVE](references/INP-DEEP-DIVE.md) |
| Image performance cookbook | [IMAGE-PERF-COOKBOOK](references/IMAGE-PERF-COOKBOOK.md) |
| Page weight & progressive disclosure | [PAGE-WEIGHT](references/PAGE-WEIGHT.md) |

#### Stack patterns

| Topic | File |
|---|---|
| Next.js App Router SEO patterns | [NEXTJS-PATTERNS](references/NEXTJS-PATTERNS.md) |
| Stack adapters (Astro / Remix / Rails / WP) | [STACK-ADAPTERS](references/STACK-ADAPTERS.md) |

#### Crawl, indexing, privacy

| Topic | File |
|---|---|
| Crawl-budget reality | [CRAWL-BUDGET](references/CRAWL-BUDGET.md) |
| Faceted nav / filters / pagination | [FACETED-NAV](references/FACETED-NAV.md) |
| Log-file analysis (verified bots) | [LOG-FILE-ANALYSIS](references/LOG-FILE-ANALYSIS.md) |
| Consent + analytics + privacy | [CONSENT-AND-ANALYTICS](references/CONSENT-AND-ANALYTICS.md) |

#### Content & editorial

| Topic | File |
|---|---|
| Content-inventory operations | [CONTENT-INVENTORY-OPS](references/CONTENT-INVENTORY-OPS.md) |
| Editorial calendar & seasonality | [EDITORIAL-CALENDAR](references/EDITORIAL-CALENDAR.md) |
| Proof library operations | [PROOF-LIBRARY-OPS](references/PROOF-LIBRARY-OPS.md) |
| Branded demand operations | [BRANDED-DEMAND](references/BRANDED-DEMAND.md) |
| Product-led SEO (tools / generators / calculators) | [PRODUCT-LED-SEO](references/PRODUCT-LED-SEO.md) |

#### Trust, authority, accessibility

| Topic | File |
|---|---|
| Trust infrastructure | [TRUST-INFRASTRUCTURE](references/TRUST-INFRASTRUCTURE.md) |
| Authorship & E-E-A-T entity surface | [AUTHORSHIP-AND-EEAT](references/AUTHORSHIP-AND-EEAT.md) |
| Accessibility as SEO-adjacent revenue | [ACCESSIBILITY-AS-SEO](references/ACCESSIBILITY-AS-SEO.md) |
| High-risk content gate | [HIGH-RISK-GATE](references/HIGH-RISK-GATE.md) |

#### Vertical playbooks

| Topic | File |
|---|---|
| Lifecycle content (impl / migration / security / docs) | [LIFECYCLE-CONTENT](references/LIFECYCLE-CONTENT.md) |
| Documentation & support SEO | [DOCS-AND-SUPPORT-SEO](references/DOCS-AND-SUPPORT-SEO.md) |
| Merchant feed alignment (marketplaces) | [MERCHANT-FEED-ALIGNMENT](references/MERCHANT-FEED-ALIGNMENT.md) |
| UGC + marketplace SEO | [UGC-AND-MARKETPLACE-SEO](references/UGC-AND-MARKETPLACE-SEO.md) |

#### Tactical playbooks & gates

| Topic | File |
|---|---|
| Audit checklist (full) | [AUDIT-CHECKLIST](references/AUDIT-CHECKLIST.md) |
| Programmatic gates | [PROGRAMMATIC-GATES](references/PROGRAMMATIC-GATES.md) |
| Traffic-drop / core-update playbook | [TRAFFIC-DROP-PLAYBOOK](references/TRAFFIC-DROP-PLAYBOOK.md) |
| Striking-distance lift playbook | [STRIKING-DISTANCE-PLAYBOOK](references/STRIKING-DISTANCE-PLAYBOOK.md) |

#### Quality, anti-patterns, meta

| Topic | File |
|---|---|
| Slop checklist | [SLOP-CHECKLIST](references/SLOP-CHECKLIST.md) |
| Anti-patterns catalog | [ANTI-PATTERNS](references/ANTI-PATTERNS.md) |
| Deliverables index | [DELIVERABLES-INDEX](references/DELIVERABLES-INDEX.md) |

### Subagents (19 total — fan out for parallel execution)

| Subagent | Purpose | Phase |
|---|---|---|
| `subagents/discovery-crawler.md` | Prod + staging crawl, raw vs rendered HTML diff | 1 |
| `subagents/gsc-extractor.md` | Search Console pull (16mo perf, coverage, sitemaps, manual actions, CWV) | 1 |
| `subagents/cwv-collector.md` | CrUX field data + Lighthouse lab, INP component-attribution where needed | 1 |
| `subagents/log-analyst.md` | Server-log analysis with verified-bot identification (T3+) | 1 |
| `subagents/serp-snapshotter.md` | Capture SERPs for seed keywords with AIO presence + features | 1, 9, 13 |
| `subagents/competitor-researcher.md` | Per-competitor gap analysis (one instance per competitor) | 2 |
| `subagents/cluster-researcher.md` | Per-cluster intent map + SERP feature scan (one per cluster) | 2 |
| `subagents/audit-area.md` | Per-area technical audit, parameterized by area | 3 |
| `subagents/cluster-writer.md` | Per-cluster brief + draft (same agent that researched in Phase 2) | 4 |
| `subagents/ia-mapper.md` | Information architecture + link-graph mapper | 5 |
| `subagents/impl-pr.md` | Per-PR implementer, parameterized by PR slug | 6 |
| `subagents/asset-builder.md` | Linkable-asset producer (one per asset) | 7 |
| `subagents/dashboard-wirer.md` | Observability + dashboard wiring | 8 |
| `subagents/experiment-runner.md` | Per-experiment owner with stopping rule + annotations | 9 |
| `subagents/fresh-eyes-bughunt.md` | Independent diff review with no prior context | 10 |
| `subagents/fresh-eyes-trace.md` | Sample N files, trace end-to-end | 10 |
| `subagents/fresh-eyes-cross-review.md` | Cluster-writer cross-review of another cluster's content | 10 |
| `subagents/prod-verifier.md` | Phase 12 Playwright verifier (also AI-bot view) | 12 |
| `subagents/compounding-ideator.md` | Idea-wizard sweep for high-leverage misses | 13 |

### Scripts (18 total — all `chmod +x`, Bun + Playwright)

| Script | Purpose |
|---|---|
| `scripts/crawl.ts` | Prod + staging crawl: status, redirect chains (relative-resolved), raw vs rendered HTML diff, canonical, schema, links |
| `scripts/sitemap-audit.ts` | Sitemap parse + canonical-truth + indexability + status-code agreement |
| `scripts/internal-links.ts` | Orphan + redirect-through-internal-link detector + anchor distribution |
| `scripts/redirect-chain-audit.ts` | Per-URL chain walk; flags > 1 hop, loops, mixed-protocol/host, meta-refresh; CI gate |
| `scripts/validate-schema.ts` | JSON-LD validation against schema.org for declared types; CI gate |
| `scripts/cwv-check.ts` | Lighthouse CI mobile profile (no preset/formFactor conflict); per-template assertions |
| `scripts/cwv-by-component.ts` | Per-component INP attribution via Performance Observer + LoAF; top 5 offenders |
| `scripts/crux-collect.ts` | CrUX API per URL with origin fallback; field LCP/INP/CLS/TTFB/FCP p75 |
| `scripts/verify-prod.ts` | Phase 12 post-deploy verifier (status, meta, canonical, OG image, schema, render diff) |
| `scripts/ai-crawler-view.ts` | Fetch as OpenAI / Anthropic / Perplexity / Google crawler and user-retrieval agents; snapshot initial HTML |
| `scripts/serp-snapshot.ts` | Clean-Chromium SERP capture: organic, AIO + cited URLs, PAA, video/image/product/local/forum, ad density |
| `scripts/gsc-extract.ts` | Search Console API pull (svc-account JWT or OAuth-installed); page+query, branded vs non-branded, WoW winners/losers, striking-distance |
| `scripts/striking-distance.ts` | Reads GSC + content inventory; rank by potential lift; per-row recommended action |
| `scripts/og-image-audit.ts` | Native image-header decoder; status, dimensions, weight (< 500KB), absolute URL; CI gate |
| `scripts/hreflang-validator.ts` | Reciprocity, ISO codes, x-default, canonical conflict, geo-redirect-trap detection |
| `scripts/entity-consistency-check.ts` | Organization JSON-LD ↔ OG site_name ↔ footer brand ↔ sameAs reciprocity (GitHub, X, LinkedIn, etc.) |
| `scripts/ai-bot-policy-check.ts` | Audit `/robots.txt` against the 2026 AI bot UA matrix; flag training-vs-search confusion, deprecated UAs, missing sitemap directive |
| `scripts/llms-txt-validator.ts` | Fetch + parse `/llms.txt` and `/llms-full.txt`; verify links, flag stale URLs, cross-check against robots.txt |

### Assets (16 total — markdown templates with placeholder fields)

| Asset | Use |
|---|---|
| `assets/DECISION-CARD.md` | Per-recommendation card with hypothesis / impact / tracking / rollback |
| `assets/BRIEF-TEMPLATE.md` | Per-page content brief (intent, audience, 3+ data points, schema, conversion) |
| `assets/AUDIT-ITEM-TEMPLATE.md` | Per-issue audit row (JSON + markdown formats) |
| `assets/PR-DESCRIPTION-TEMPLATE.md` | Per-PR description for Phase 6 |
| `assets/EXPERIMENT-CARD.md` | Per-experiment plan with stopping rule + decision rule |
| `assets/MONTHLY-EXEC-TEMPLATE.md` | Monthly executive cockpit |
| `assets/WEEKLY-REPORT-TEMPLATE.md` | Weekly self-serve report |
| `assets/90-DAY-PLAN-TEMPLATE.md` | Tier-aware 90-day plan with per-day deliverables and acceptance criteria |
| `assets/CONTENT-INVENTORY-CSV-SCHEMA.md` | CSV schema for `analyses/content-inventory.md` (or .csv) |
| `assets/SERP-FEATURE-SCAN-TEMPLATE.md` | Per-query SERP feature inventory (AIO / PAA / video / image / product / local / forum / news / ads) |
| `assets/COMPETITOR-GAP-TEMPLATE.md` | Per-competitor gap analysis structure |
| `assets/CITATION-TRACKING-CSV-SCHEMA.md` | CSV schema for AI Overview / ChatGPT / Perplexity / Claude citation log |
| `assets/SEASONALITY-CALENDAR-TEMPLATE.md` | Quarterly seasonality calendar per cluster with content-prep windows |
| `assets/MIGRATION-URL-MAP-TEMPLATE.md` | URL-map CSV schema + pre/post-launch checklists |
| `assets/KPI-TARGET-SHEET-TEMPLATE.md` | Per-tier (T1-T4) KPI targets with primary source per metric |
| `assets/SOURCE-LOG-TEMPLATE.md` | `analyses/source-log.md` per-claim audit trail per VERIFICATION-FIRST protocol |

---

## SELF-VALIDATION

Trigger checks (Haiku canary): asking "run an SEO audit on this Next.js SaaS at /data/projects/<x>", "fix our Core Web Vitals for the marketing pages", "we got hit by the latest core update — diagnose", "build a programmatic comparison page template safely", and "audit our schema before launch" should all activate this skill.

---

## META-NOTE

This skill exceeds the 200-line guideline because it operationalizes a 2,289-line canonical knowledge base across 13 dependent-but-parallelizable phases with stack-aware implementation. Depth lives in `references/` — the body is a router. The exception is justified the same way `wills-and-estate-planning-skill` and `tax-return-preparation-and-advice-generic` are: when the methodology is multi-mode, multi-phase, and produces dozens of distinct artifacts, a thin body cannot route correctly without surfacing the kernel, operators, modes, tier triage, and phase contracts.
