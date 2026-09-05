# OPERATORS — Cognitive Moves for SaaS SEO

Composable thinking moves applicable to any page, template, query family, or release. Each card has triggers, failure modes, and a prompt module suitable for handing to a subagent.

---

## § Crawl-Render Diff

**Trigger:** any audit; any release that changed routing or rendering; AI-citation pass.

**Question:** does the raw HTML for this URL contain the title, meta, canonical, primary content, and links the rendered HTML claims?

**Failure modes:**
- Pricing list rendered only after client hydration → AI bots cannot see plans.
- Schema injected via `useEffect` → invisible in raw HTML.
- Title set via `document.title` after route change → metadata drift.
- Consent banner replaces hero before LCP → broken LCP candidate.

**Prompt module:**
> Fetch URL with `curl -s -A "Mozilla/5.0..."` and save as `raw.html`. Render via Playwright at `networkidle` and save as `rendered.html`. Diff the two for: title, meta description, canonical, robots directive, h1, primary content blocks, primary internal links, JSON-LD blocks. Report: where do they disagree, and which agent (Googlebot / GPTBot / ClaudeBot) sees what?

---

## ⧉ Canonical-Cluster Coherence

**Trigger:** any duplicate finding; GSC "Google chose different canonical"; multi-locale pass.

**Question:** do internal links, sitemap, canonical tag, redirect chain, hreflang alternates, and parameter rules all point at the same preferred URL?

**Failure modes:**
- Internal links use mixed case while canonical is lowercase.
- Sitemap includes `/path/` while canonical is `/path`.
- Blog tag pages canonical to category but internal links go to tag.
- `hreflang` references a URL the destination canonicals away from.

**Prompt module:**
> For URL X (the declared canonical owner of query family Q), enumerate: internal links pointing to X (count, anchor distribution, source pages), sitemap inclusion, canonical tag value on X, redirect rules touching the URL space, `hreflang` alternates referencing X, parameter-handling rules. Report disagreements and propose one-PR remediation.

---

## ⌖ Intent-Format Match

**Trigger:** new page brief; striking-distance page review; SERP feature SERP audit.

**Question:** is the SERP for this query showing video / product / local / forum / answer / standard? Does the page format match what users expect?

**Failure modes:**
- Article competing for query that returns video pack.
- Product page competing for query that returns forum / discussion.
- Long-form guide competing for query showing AI Overview + 3 quick answers.

**Prompt module:**
> Capture the SERP for query Q via `scripts/serp-snapshot.ts`. Identify dominant features (AIO present? PAA? video? image? product? local? forum? news?). Compare to the planned page format. If mismatch, propose either reformat or alternative target query.

---

## ⊕ Striking-Distance Lift

**Trigger:** any GSC review with average position 4–15 + steady impressions.

**Question:** what is the smallest change that moves this page from position 4–15 to top 3?

**Common levers:**
- Title rewrite for intent and CTR.
- Meta-description rewrite (CTR primary metric).
- One internal link from a high-authority page on the site.
- One missing entity / subtopic added to body.
- Add three unique data points (AI Overview citation eligibility).
- Schema correction (e.g. add Offer / aggregateRating where eligible).

**Prompt module:**
> For the top-20 striking-distance pages from `analyses/gsc/`, propose the single highest-leverage change per page with hypothesis, tracking metric, recheck-by date.

---

## ⚑ Programmatic-Quality Gate

**Trigger:** any programmatic launch proposal.

**Question:** does each generated page have unique value, real data, a maintenance owner, and a kill switch? Or is this token-swap?

See [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md). Operator card just enumerates the eight gates.

---

## ⚒ INP Component Hunt

**Trigger:** INP regression; commercial template above 200 ms p75; PR review touching shared components.

**Question:** which component on this marketing page is leaking dashboard-tier interaction cost?

**Common offenders on SaaS marketing routes:**
- Chart / graph library imported via shared layout.
- Marketing CRM widget (Drift, Intercom messenger, HubSpot).
- Consent banner (heavy IAB-TCF stack on first paint).
- Animated hero (Framer Motion / Lottie / GSAP) that runs main-thread on hover.
- Plan toggle on pricing page using a heavy state library.
- Copy-to-clipboard on code block using Prism + autoload language packs.

**Prompt module:**
> Profile URL X with Chrome DevTools Performance panel via Playwright. Capture INP at 95th percentile across 10 interactions: click hero CTA, hover plan card, toggle billing period, click FAQ accordion. Attribute time to component. Propose smallest change (lazy import, dynamic load, RSC, tree-shake).

---

## ⊠ Snippet Curation Pass

**Trigger:** Phase 3 metadata audit; pre-launch QA; striking-distance pass.

**Question:** is this template's title pattern intent-matched? Is the meta description ad-copy quality? Will the SERP CTR exceed 3 % at average position?

**Failure modes:**
- Title is `Acme - Pricing` (template-driven, no intent).
- Description is "We offer pricing for our SaaS product" (vague).
- Title length > 60 chars or < 30 chars without reason.
- All site descriptions read as if written by a marketing team checklist — "the leading platform for…"

**Prompt module:**
> For each template, propose three title and description variants: variant A (matches dominant SERP feature), variant B (highest specificity), variant C (CTR-optimized with curiosity but accurate). Document predicted CTR vs current; ship one as the canonical pattern.

---

## ⌬ AI-Citation Extractability

**Trigger:** Phase 4 brief; AI-visibility pass; new commercial page.

**Question:** are there self-contained, dated, sourced passages with three-plus unique data points an answer engine can quote without context?

**Pattern:** open with direct answer; include numeric data with units and dates; link sources; close with one concrete next step.

**Prompt module:**
> Review draft for the page. Identify each passage of 50–150 words. For each, emit `citation_extractability_score_0_1000`, with component subscores also normalized to `0-1000`: standalone, direct answer, three-plus numeric data points with dates, source links, concrete next step. Weight those components 200 / 200 / 250 / 200 / 150 when calculating the final `score_0_1000`. Pages with fewer than 3 passages scoring >=900 are not citation-ready.

---

## ⌭ Query Fan-Out Coverage

**Trigger:** AI-visibility pass; Phase 2 cluster mapping; Phase 4 commercial-page brief; Phase 13 compounding pass.

**Question:** if AI Mode or an answer engine decomposes this query into several supporting searches, does the page or cluster answer those proof questions with visible evidence?

**Common SaaS fan-out branches:**
- Pricing proof: public plan limits, usage examples, enterprise caveats.
- Security / procurement proof: SOC 2, DPA, SSO, data residency, status page, incident history.
- Migration friction: setup time, import/export paths, rollback, common failure modes.
- Integration details: exact platforms, auth methods, rate limits, screenshots.
- Comparative limitations: where this SaaS is weaker than alternatives, with honest fit guidance.
- Current product proof: dated screenshots, changelog, demo clips, live examples.
- Next-step action: trial, demo, docs, calculator, template, migration checklist.

**Prompt module:**
> For target query Q and canonical URL X, list the five to ten likely fan-out subqueries an answer engine would issue. Map each to existing page passages, support pages, schema, screenshots, and internal links. Mark gaps as `missing`, `weak`, or `covered`, then propose the smallest page or cluster edit that closes the highest-impact gap.

---

## ◫ AI Measurement Humility

**Trigger:** any AI-citation claim; dashboard build; executive reporting; compounding backlog EV estimate.

**Question:** is this claim based on first-party citation logs, GSC blended Web data, explicit AI referrers, server logs, or a third-party study — and is the uncertainty labelled correctly?

**Failure modes:**
- Calling GSC Web clicks "AI Overview traffic."
- Treating a single logged-in browser capture as stable citation share.
- Quoting a third-party AI-overlap percentage without source date, query set, or recheck date.
- Combining citation presence, sessions, and rankings into one unlabeled "AI score."

**Prompt module:**
> For each AI-visibility metric in the report, add `metric_source`, `sample_size`, `collection_method`, `last_checked`, and `confidence`. If the source is GSC, label it `blended_web`. If the source is manual captures, label it `sampled_citation_presence`. If the source is referrers, label it `session_referral`. Rewrite any overclaim as a hypothesis unless first-party evidence supports it.

---

## ⇲ Trust Surface Audit

**Trigger:** Phase 4 high-risk page; security / procurement / compliance page review; brand-demand workstream.

**Question:** are author bios, methodology pages, public methodology, dated reviews, screenshots, and corrections policy visible — or just claimed?

**Prompt module:**
> Inventory trust surfaces: author pages, editorial standards, corrections policy, methodology pages, dated reviews, customer logos with permission, screenshots with dates, security page, privacy page, status page, changelog. Report what is missing or stale; propose remediation per page type.

---

## ⊘ Soft-404 Sniff

**Trigger:** any GSC "soft 404" report; empty-state route review; release that changed error pages.

**Question:** does this 'page not found' or 'no results' route return 200? Is this empty-state shell silently inflating soft-404s?

**Common cases:**
- Custom 404 page returns 200 (must return 404).
- Search results page with zero results returns 200.
- Filtered category with zero items returns 200.
- Discontinued product page returns 200 with "this product is no longer available".

**Prompt module:**
> Crawl all routes that match patterns `/search`, `/browse`, `/category/*`, `/product/*`, `/404`, `/not-found`, `/error`. Verify status codes; for empty-state routes propose redirect-to-substitute, return-404, or `noindex,follow` based on intent.

---

## ⇆ Locale-Loop Check

**Trigger:** multi-locale site; `hreflang` audit; locale routing change.

**Question:** do `hreflang` alternates reference each other reciprocally? Are auto-redirects trapping crawlers in the wrong region?

**Prompt module:**
> For each priority page, list `hreflang` alternates declared on the page. Verify each alternate references back. Verify language and region codes are valid. Check `x-default` presence. Test with `Googlebot Smartphone` user agent from US, EU, JP IPs (or geo override) and confirm crawler can reach all alternates without redirect loops.

---

## ⌁ Release-Day Tripwire

**Trigger:** any PR touching routing, rendering, navigation, browser history, modals/overlays, design system, consent banners, affiliate/ad redirects, or CDN/edge config.

**Question:** did this release change a SEO-sensitive surface? Did the representative URL set get re-checked?

**Prompt module:**
> For PR diff, determine if any of these are touched: `app/layout.tsx`, `app/sitemap.ts`, `app/robots.ts`, middleware.ts, next.config.*, any opengraph-image.tsx, any generateMetadata, route-group changes, design-system primary components, consent banner, modal/overlay behavior, client router usage, `history.pushState` / `history.replaceState`, affiliate/ad redirect code. If yes, run `scripts/verify-prod.ts` against the staging URL set and run a Playwright Back-button check for representative flows; gate merge on green.

---

## ⌗ Branded-vs-Non-Branded Split

**Trigger:** any traffic-drop diagnosis; quarterly review.

**Question:** when traffic moved, did branded and non-branded move together or separately?

**Diagnostic implications:**
- Both down: site-wide quality / spam policy / manual action / infrastructure issue.
- Branded down, non-branded up: brand crisis, product issue, reputation event.
- Non-branded down, branded up: algorithm shift, content quality classifier, competitive loss.

**Prompt module:**
> From GSC, segment queries by branded (contains brand string and variants) vs non-branded. Plot impressions and clicks per segment over the 90 days surrounding the change. Report which segment moved and propose the diagnostic branch to follow.

---

## ⊞ Anti-Cannibalization Owner

**Trigger:** any new page brief; any cluster restructure.

**Question:** which URL owns this query family canonically? Does any other URL compete for it?

**Prompt module:**
> For query family Q, list URLs ranking on the site for it (top 10 GSC pages by clicks). Identify the canonical owner. For each non-owner ranking page, decide: support page (link to owner), merge into owner, differentiate intent (and update title / H1 / metadata accordingly), or noindex.

---

---

## ⊕⊕ Search-Surface Match

**Trigger:** any new page brief; any decay-candidate refresh.

**Question:** is this page format the format the SERP currently rewards for the target query?

**Failure modes:**
- Article competing where the SERP shows a video pack.
- Long guide where the SERP shows a 3-line answer + a tool widget.
- Comparison page where the SERP shows product cards and pricing tables.

**Prompt module:**
> Given the SERP capture for query Q (`analyses/serp-snapshots/Q.json`), classify the dominant feature mix. Map to the matrix in [PHASE-2-KEYWORD](PHASE-2-KEYWORD.md). If the planned page format does not match, propose the alternative format or a different target query that better fits the planned format.

---

## ⊞⊞ Page-Type Conformance

**Trigger:** any audit of a high-intent commercial page; any pricing/feature/integration page review.

**Question:** does this page exist in the form a buyer expects, complete with the standard furniture for its type?

**Pricing-page furniture:** plan tiers with what's included per tier; per-feature limits and overages; billing cycle; cancellation; FAQ tied to objections; security/SOC2 link; usage calculator if usage-priced; comparison-to-competitors-on-pricing where relevant; CTA per tier; for procurement: enterprise-sales link, security data-room link.

**Comparison-page furniture:** dated competitor claims with sources; clear criteria; honest "X is stronger here" sections; screenshots tied to claims; pricing caveats; update cadence visible.

**Feature-page furniture:** real screenshot above fold; what problem this solves; how it actually works (not buzzwords); concrete example with numbers; limitations; integration list; CTA tied to product-led trial.

**Prompt module:**
> Audit page X against the furniture inventory for its declared page type. Report missing or weak elements. Propose the smallest content change that closes the gap.

---

## ⌖⌖ Intent-Drift Detection

**Trigger:** any page with falling impressions on stable queries (intent shifted); any post-core-update review.

**Question:** has the SERP shifted intent between when this page was written and now?

**Failure modes:**
- "Best CRM for startups" used to show comparison articles; now shows product grids and pricing tables.
- "How to migrate to Postgres" used to show tutorials; now shows AI Overview + 3 forum links.
- Generic "SaaS pricing" used to show informational guides; now shows pricing-page directories.

**Prompt module:**
> Compare today's SERP for query Q against an SERP capture from N months ago (or against the structure assumed in the page brief). If intent shifted, classify the shift and propose: (a) reformat the page, (b) split into two pages with distinct intents, (c) deprioritize this query.

---

## ⌁⌁ Hidden Subdomain Surface

**Trigger:** any audit at T2+; any new product launch; any acquisition.

**Question:** what subdomain surfaces does this SaaS have, and are any of them silently leaking, polluting, or being missed?

**Common SaaS subdomains:**
- `app.example.com` — usually noindex, but sometimes a public dashboard slips
- `blog.example.com` — content (sometimes split from `example.com/blog` for legacy reasons)
- `docs.example.com` — documentation
- `status.example.com` — status / incidents
- `support.example.com` or `help.example.com` — support docs
- `careers.example.com` — careers / job listings
- `community.example.com` — UGC forum
- `changelog.example.com` — release notes
- `developers.example.com` — API docs
- Acquired-product subdomains (often forgotten and indexed without coordination)
- Marketing-tool subdomains (`go.example.com`, `try.example.com`, `learn.example.com`)
- Email tool subdomains (`email.example.com` — usually shouldn't be indexable)

**Prompt module:**
> Enumerate all subdomains via DNS (`dig`/`dnsdumpster`) and certificate transparency (`crt.sh`). For each, confirm: indexable? in sitemap? canonical points where? Schema declared? Any silently leaking PII? Any orphan from an acquisition?

---

## ⊠⊠ Title CTR Forensics

**Trigger:** any page with avg position < 5 and CTR < 5%; any title-test setup.

**Question:** why is the CTR low for this position, and what's the smallest title change that fixes it?

**Diagnostic ladder:**
1. Compare title length to SERP-rendered length (Google may truncate).
2. Compare title intent to query intent (informational title on commercial query?).
3. Look for SERP-feature compression (AIO, ads, knowledge panel pushing title down).
4. Check whether brand position helps or hurts (front-loaded brand can hurt for commercial queries; back-loaded brand often outperforms).
5. Test power words sparingly — be specific over hyped.
6. Verify `og:title` and `twitter:title` agree (Google rarely uses these but inconsistencies hint at template drift).

**Prompt module:**
> For URL X, query Q, position P, current CTR C. Capture SERP. Compare expected CTR-at-position-P (from open click curves like Sistrix) to actual. Diagnose the gap. Propose three title variants A/B/C with predicted CTR rationale.

---

## ⊘⊘ Empty-State Indexability

**Trigger:** any audit that touches search routes, filter/no-results routes, account-required routes, expired-product routes.

**Question:** does this empty-state route correctly signal its emptiness to search?

**Common patterns:**
- `/search?q=foo` with no results → should `noindex,follow` and return 200 (or 404 if "search" isn't a feature).
- `/category/foo` with zero products → noindex + parent canonical, OR redirect to substitute, OR 404.
- `/products/discontinued-item` → 410 with explainer + link to substitute, OR 301 to closest substitute.
- `/account` (logged-out) → should not be reachable from public crawl path; if it is, `noindex` + `Disallow` in robots.
- `/_dev`, `/_preview`, `/_test` → never indexable; access-controlled or DNS-fenced.

**Prompt module:**
> Enumerate likely empty-state routes (regex on app routes + sitemap diff). For each, fetch with no-cookies and confirm correct status code, robots directive, canonical, and visible explainer text.

---

## ⌬⌬ AI-Crawler Bot Diff

**Trigger:** any AI-visibility pass; any RSC streaming change; any consent-banner change; any release that added Suspense boundaries to commercial routes.

**Question:** what does GPTBot vs ClaudeBot vs PerplexityBot vs Googlebot see on this URL — and does the AI bot view contain enough citation-eligible content?

**Diagnostic flow:**
1. `bun run scripts/ai-crawler-view.ts --url <X> --as all`
2. Compare initial-HTML body word counts across user agents.
3. Compare JSON-LD presence count.
4. Check for `Loading...` / skeleton / "Enable JavaScript" placeholder text.
5. Verify the headline-answer paragraph is in initial HTML for AI bots.
6. Verify three-plus unique data points per page are in initial HTML.

**Prompt module:**
> For each priority page from the AI-visibility plan, run the AI-crawler diff. Flag any page where AI-bot view contains less content than Googlebot view, or where citation-eligible content is missing from initial HTML. Propose the smallest rendering change (move from streamed to static shell; render JSON-LD server-side; etc.).

---

## ⊕⊞ Cluster-Cohesion Index

**Trigger:** Phase 5 IA review; any cluster restructure or merge proposal.

**Question:** does this cluster behave as a unit — pillar receiving authority, cluster pages linking back, sibling cross-links genuine, no internal-link orphans within the set?

**Measure:**
- Pillar inbound links from cluster pages: count, anchor distribution, crawl-depth.
- Cluster pages linking back to pillar (yes/no per page).
- Sibling cross-links: count and whether genuinely useful (vs decorative).
- Cluster orphans (cluster pages with zero inbound links from sister cluster pages or pillar).
- Cross-cluster bleed (cluster page linking heavily into a different cluster's pillar).

**Prompt module:**
> Build the link graph for cluster X (pillar + N cluster pages). Report cohesion metrics. Flag orphans, missing back-links to pillar, and any page linking more to outside-cluster pages than to its own cluster.

---

## ⌗⌗ Conversion-Adjusted Performance

**Trigger:** any monthly executive cockpit review; any traffic-drop diagnosis; any cluster ROI debate.

**Question:** which segments are growing/shrinking on the metrics that matter — not just clicks?

**Segments to compute monthly:**
- Organic-attributed signups / trials / paid-conversions per cluster.
- Per-cluster CR (conversion rate) trend.
- Per-cluster blended CAC if attribution allows (LTV likely too noisy without cohort data).
- Branded-vs-non-branded CR delta.
- Top 10 highest-conversion-per-click landing pages (often docs/security/comparison).
- Bottom 10 traffic-but-no-conversion landing pages (refresh or noindex candidates).

**Prompt module:**
> For each cluster: clicks delta, impressions delta, conversion delta, CR delta WoW/MoM/QoQ. Surface clusters where clicks rose but conversions fell (intent shift?), conversions rose despite click drops (better landing-page UX or lower-intent-but-higher-quality), and clusters with stable both (mature/baseline).

---

## ⚒⚒ Component-Level Cost Audit

**Trigger:** any INP regression on a marketing route; any new shared component proposal; any design-system swap.

**Question:** which component on this template costs the most INP/LCP/CLS/main-thread time, and what is the smallest fix?

**Common SaaS marketing-route offenders, ranked roughly:**
1. Marketing-CRM widget (Drift / Intercom / HubSpot tracker / Marketo) on first paint.
2. Consent banner / cookie banner (especially IAB-TCF stack).
3. Animation library mounted at root (Framer Motion / GSAP / Lottie).
4. Chart library imported in a shared layout.
5. Plan-toggle / pricing-toggle with heavy state library.
6. Code-block syntax highlighter with autoload language packs.
7. Sticky CTA / nav with `position: sticky` triggering paint.
8. Above-fold autoplay video.
9. Heavy hero gradient computed on the main thread.
10. Custom font loaded from external CDN, not preloaded.

**Prompt module:**
> Profile representative URL X. Capture INP across 10 interactions. For each long task > 50ms, attribute to component (selector + module path). Rank by impact. Propose the smallest fix per top-3 component (lazy import / dynamic / RSC / move-to-edge / drop entirely).

---

## ⊞⌬ Entity-Reconciliation Check

**Trigger:** any AI-visibility pass; any rebrand; any acquisition; quarterly trust review.

**Question:** does this SaaS present as one coherent entity across every surface a search/AI engine would reconcile?

**Surfaces:**
- Homepage `Organization` JSON-LD (name, url, logo, description, sameAs[]).
- `WebSite` JSON-LD on homepage.
- OG `og:site_name` on every page.
- Footer brand mention text.
- Twitter / X bio + display name + handle.
- LinkedIn company name + tagline + headquarters.
- GitHub org name + bio + URL.
- Crunchbase entry.
- Wikipedia entry (if exists).
- App-store / marketplace listings.
- Founder personal pages (LinkedIn, GitHub, X).
- Press kit page on the SaaS site.

**Prompt module:**
> For Organization X, fetch Organization JSON-LD on homepage. List sameAs[] entries. For each, fetch the target and verify reciprocity, name match, description coherence. Output `analyses/entity-consistency.md` with a normalized name vocabulary and any inconsistencies.

---

## Operator selection by phase

| Phase | Primary operators |
|---|---|
| 1 — Discovery | §, ⌗, ⊘, ⌁⌁ |
| 2 — Keyword | ⌖, ⊞, ⊕⊕, ⌖⌖, ⌭ |
| 3 — Technical | §, ⧉, ⊘, ⇆, ⌁, ⊘⊘, ⌁⌁ |
| 4 — Content | ⌖, ⌬, ⌭, ⇲, ⊞⊞, ⊠⊠ |
| 5 — IA | ⧉, ⊞, ⊕⊞ |
| 6 — Implementation | §, ⚒, ⌁, ⚒⚒ |
| 7 — Authority | ⇲, ⊞⌬ |
| 8 — Analytics | ⌗, ⌗⌗, ◫ |
| 9 — Experimentation | ⊕, ⊠, ⊠⊠ |
| 10 — Fresh-eyes | §, ⌬, ⊘, ⌬⌬ |
| 12 — Verify | §, ⧉, ⌬⌬, ⊞⌬ |
| 13 — Compounding | ⊕, ⊞, ⚑, ⌖⌖, ⌭, ◫ |
