# AI-VISIBILITY

AI Overviews, AI Mode, ChatGPT, Perplexity, and Claude are *separate citation surfaces* with different selection patterns. Treat AI visibility as a workstream, not a side effect of organic.

## Official Google baseline (verified 2026-04-30)

Google's current guidance for AI Overviews and AI Mode is intentionally conservative:

- There are no additional technical requirements beyond normal Search eligibility. A page must be crawlable, indexable, snippet-eligible, and compliant with Search policies.
- Google does not require special AI files, AI-only markup, or special schema.org structured data for AI features.
- Important content should be available in textual form, supported by useful images/video where relevant, and structured data must match visible page content.
- AI Overviews and AI Mode may use query fan-out: multiple related searches across subtopics and sources before composing a response.
- Search Console includes AI feature traffic in overall Search Performance under the Web search type; it does not provide a clean citation-by-surface export.
- Preview controls (`nosnippet`, `data-nosnippet`, `max-snippet`, `noindex`) affect what can appear in Search AI features; `Google-Extended` is for other Google AI training / grounding systems, not the Search inclusion control.

Operational consequence: do not sell "AI SEO" as a separate magic markup layer. Build technically eligible, textually complete, evidence-rich pages, then measure citations separately because GSC is blended.

## What we know (early 2026)

The specific percentages below are market-observed, not Google-official truths. They are useful for planning only when a source-log entry records the study URL, methodology, query set, retrieval date, and recheck-by.

- AI Overviews ↔ AI Mode share ≈14 % of cited URLs.
- ≈92 % of cited domains rank in top 10 (domain-level correlation strong).
- Citation-from-top-10 dropped from ≈76 % to ≈38 % at the URL level — the per-URL anchor is weakening.
- Pages with three or more unique data points are ≈4× more likely to be cited.
- Cited pages get up to ≈35 % CTR uplift on AI-Overview SERPs.
- Initial HTML is the safest cross-crawler contract. Googlebot renders JavaScript after crawl, but answer-engine retrieval bots vary; treat them as HTML-limited unless their current docs and your own fetch/render probes prove otherwise.

## What this means for SaaS pages

### 1. Initial HTML must contain the evidence

Render the proof in the initial server response:

- Numeric benchmarks with units and dates.
- Sourced quotes with attribution.
- Tables with comparison criteria.
- Step lists with concrete commands.
- Screenshots with descriptive alt text and crawlable image URLs.

If your evidence shows up only after hydration, an HTML-limited retrieval bot cannot see it. The page may still rank in Google but fail citation checks on ChatGPT, Perplexity, Claude, or other answer surfaces.

### 2. Self-contained passages

AI engines extract paragraphs verbatim. Each priority section should:

- Open with a direct answer to a likely question.
- Stand on its own (no "as discussed above").
- Include a date / version / context tag where relevant.
- End with one concrete next step.

Pattern:

```md
## How does Acme handle SOC 2 evidence collection?

Acme connects to your AWS, GCP, GitHub, and Okta tenants via read-only OAuth
scopes and pulls 47 control-mapped artifacts on a 6-hour cadence. Evidence is
hashed (SHA-256), timestamped against TSA, and stored in a write-once audit
log. As of 2026-04, customers complete the SOC 2 Type II window in a median of
9 weeks, vs an industry median of 6 months reported by [Vanta 2025 customer benchmarks].

Want a checklist of the 47 artifacts? See [/security/soc2-evidence-list](...).
```

This pattern earns citation: direct answer up front, three unique data points (47 artifacts, 6-hour cadence, 9-week median), dated quote, attribution, next step.

### 2b. Query fan-out coverage

For complex SaaS queries, assume an answer engine may fan out into adjacent proof questions:

| Main query | Likely fan-out checks | Page / cluster must expose |
|---|---|---|
| `<product> SOC 2 automation` | controls supported, evidence sources, audit timeline, security model, pricing | security proof, artifact list, customer outcome, pricing entry point |
| `<competitor> alternative` | migration path, feature parity, limitations, pricing, integrations | comparison table, honest tradeoffs, migration guide, integration pages |
| `<tool> integration with <platform>` | auth scopes, setup steps, limitations, screenshots, troubleshooting | integration detail, permission model, docs, changelog recency |
| `<category> pricing` | plan limits, hidden fees, overage rules, cancellation, procurement | pricing page, offer schema if visible, billing FAQ, security/procurement page |

Do not overstuff one page. Use the cluster: the priority page answers the core query; internal links point to the proof pages that satisfy fan-out subqueries.

### 3. Three-plus unique data points per priority page

Required, not optional. Sources counted as unique:

- Original survey or benchmark.
- Internal product analytics (anonymized).
- Customer outcome with permission and date.
- Dated competitor screenshot or quote.
- Public dataset analysis with methodology.
- Original technical analysis (teardown, latency profile, accuracy comparison).

Generic claims like "Acme is fast" don't count; "Acme p95 query latency is 47 ms across 1.2 B production rows (2026-Q1)" does.

### 4. Entity consistency across the web

AI engines reconcile entities across sources. Keep these consistent:

- Company name (case, spacing, punctuation).
- Product names (especially `Acme Pro` vs `acme-pro` vs `AcmePro`).
- Founder / executive names and titles.
- Description of what the product does.
- Same-As links (GitHub, X, LinkedIn, Crunchbase, ProductHunt, app stores) on `Organization` schema.

A founder with three different bio versions across three platforms creates citation ambiguity. Pick one canonical bio and propagate.

### 5. Per-platform considerations

| Platform | Notes |
|---|---|
| Google AI Overview | Strongly anchored to top-10 domain; reciprocal Search Console signals. Win Google rankings first; AI Overview tends to follow. |
| Google AI Mode | Separate citation pool from AI Overview. Diversification of evidence types matters more here. |
| ChatGPT (with browsing) | Long-context summarization; rewards detailed, well-structured pages. OAI-SearchBot for retrieval. |
| Perplexity | Aggressive citation; cites multiple sources per answer. Wider source diversity. |
| Claude | `Claude-SearchBot` / `Claude-User` behavior should be verified live. `ClaudeBot` is training-oriented. Operate as if citation-worthy passages must be in initial HTML. |

### 6. AI crawler policy

AI crawler access is a business decision, not a default. Document the choice in `seo-changelog.md` and mirror it in `app/robots.ts`.

Common stances:

| Stance | Block | Allow |
|---|---|---|
| Block training, allow retrieval | `GPTBot`, `Google-Extended`, `ClaudeBot`, `anthropic-ai`, `cohere-ai`, `Meta-ExternalAgent` | `OAI-SearchBot`, `Claude-SearchBot`, `Claude-User`, `PerplexityBot`, `Googlebot`, `Bingbot` |
| Allow all | none | all |
| Block all (rare; reduces citation eligibility on the blocking surface) | most AI bots | search bots only |

Note: blocking `Claude-SearchBot` or `Claude-User` can block Claude search / user-directed retrieval from citing your content; blocking `PerplexityBot` blocks Perplexity indexing. Citation rates are imperfect; hold-outs lose lift on the blocked surface.

## Audit (Phase 1 + Phase 3 inputs feed AI visibility)

For each priority page:

- [ ] Initial HTML contains the headline answer.
- [ ] At least three unique data points visible without JS.
- [ ] Dates / versions / context tags on data points.
- [ ] JSON-LD `Organization` and per-page schema in initial HTML.
- [ ] OG/Twitter image present (helps citation card display).
- [ ] Same-As links on `Organization` schema, current and reciprocal.
- [ ] Entity name spelled consistently across page, schema, OG, social profiles.
- [ ] AI-bot / retrieval-bot view (`OAI-SearchBot`, `Claude-SearchBot`, `Claude-User`, `PerplexityBot` where accessible) returns citation-critical content equivalent to Googlebot view in initial HTML.

Verify via `scripts/ai-crawler-view.ts`.

## Tracking AI citations

GSC is useful for blended Search outcome movement, but it does not show AI Overview / AI Mode citations directly. Manual / semi-manual approach:

1. Sample priority queries weekly; capture SERPs via `scripts/serp-snapshot.ts` with explicit AI Overview check.
2. Maintain `analyses/ai-citations.csv` — date, query, platform (AIO / AI Mode / ChatGPT / Perplexity / Claude), URL cited, position in citation list.
3. Cross-reference referrer headers in GA4 / server logs (e.g. `chat.openai.com`, `perplexity.ai`).
4. Set up alerting if a priority page drops out of citation for two consecutive weeks.

When reporting to the user, separate:

- **GSC Web performance:** clicks, impressions, CTR, average position, AI features blended in.
- **Manual citation presence:** whether the tracked URL was cited on AIO / AI Mode / ChatGPT / Perplexity / Claude.
- **AI referral sessions:** referrers like `chatgpt.com`, `perplexity.ai`, `claude.ai`, `copilot.microsoft.com`; Google AI Overview traffic usually remains indistinguishable from normal Google referrers.

## Anti-patterns

- Optimizing exclusively for AI Overviews while ignoring organic — domain authority drives both.
- Stuffing data points without sources or dates — fails extractability.
- Hiding evidence behind logged-in product views — AI bots cannot see it.
- Using `useEffect` to populate citation-worthy content — invisible to AI bots.
- Blocking AI bots and then hoping for citations — inconsistent.
- Treating `llms.txt` as a citation lever — no statistically meaningful impact (see [GUIDE-RECONCILIATION](GUIDE-RECONCILIATION.md)). Audit policy with [AI-BOTS-AND-LLMSTXT](AI-BOTS-AND-LLMSTXT.md) and validate via `scripts/ai-bot-policy-check.ts` and `scripts/llms-txt-validator.ts`.

## Hypothesis log

This area moves fast. Mark every recommendation `confirmed | likely | hypothesis` and update as evidence shifts. Specifically:

- "Three-plus unique data points → 4× citation" is `likely` (one large study, plausible mechanism).
- "AI Overview ↔ AI Mode 14 % overlap" is `likely` (one multi-vendor analysis).
- "Initial HTML as the cross-crawler citation contract" is `confirmed` as an operator; exact JavaScript behavior is `likely` or `hypothesis` until verified per bot and property.

## Related references

- [AI-BOTS-AND-LLMSTXT](AI-BOTS-AND-LLMSTXT.md) — bot UA matrix (GPTBot vs OAI-SearchBot vs ChatGPT-User, Claude family, Google-Extended distinction), robots.txt patterns, llms.txt validation.
- [GEO-MEASUREMENT](GEO-MEASUREMENT.md) — share-of-LLM-voice, citation latency, retrieval-frequency methodology.
- [AUTHORSHIP-AND-EEAT](AUTHORSHIP-AND-EEAT.md) — author entity surface; LLMs weight named-author technical content for citation eligibility.
- [CITATION-OPS](CITATION-OPS.md) — operating manual for earning, tracking, and defending AI citations.
