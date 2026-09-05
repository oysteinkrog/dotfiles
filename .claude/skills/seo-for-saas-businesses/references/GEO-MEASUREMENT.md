# GEO-MEASUREMENT — Generative Engine Optimization Metrics

> **Why this exists:** "Did we appear in an AI Overview?" is not a measurement. This reference defines the metrics that actually let you reason about LLM visibility, where to source them, and which are real vs aspirational. Google Search Console includes AI Overviews / AI Mode traffic in Web performance data, but does not expose a clean AI-only traffic or citation report. Measurement is the bottleneck, not the optimization.

---

## §1 — The metric stack

| Metric | Definition | How to source | Status |
|---|---|---|---|
| **Share of LLM Voice (SoLV)** | Across a defined query set, % of prompts where your brand/page is cited | Manual prompts at fixed cadence, or third-party tools (Profound, Otterly.ai, Goodie, AthenaHQ, BrightEdge GEO) | Workable today |
| **Citation latency** | Time from publish to first LLM citation | Per-engine: Perplexity ~24-72h, ChatGPT-browse live, Google AIO ~weeks | Workable, manual |
| **Retrieval frequency (server-side)** | Hits per URL per day from `OAI-SearchBot`, `Claude-SearchBot`, `PerplexityBot`, `Perplexity-User` | Server log parsing (CDN logs, app logs, Cloudflare logs) | Workable today |
| **Bot-share of crawl** | % of crawl requests by AI bots vs Googlebot | Same logs | Workable today |
| **AI-driven referral traffic** | Sessions with referrer matching `*.openai.com`, `*.perplexity.ai`, `bing.com/search?showconv=1`, `gemini.google.com` | GA4 referral report + custom segment | Workable; underestimates because most LLMs strip Referer |
| **Branded search delta after LLM mention** | Branded GSC clicks lift in 7-day window after a confirmed LLM citation | GSC + manual citation log | Workable |
| **Conversation-driven sign-ups** | Sign-ups marked as "from a chatbot" via on-site survey or referrer | First-party event + intake survey | Workable, low-precision |
| **AI feature traffic isolated from GSC Web** | Native AI-only GSC export | Not exposed separately; blended into Web performance today | NOT available as a separate segment |

---

## §2 — Define your query set

GEO measurement starts with a **fixed list of queries** representative of your customers' real prompts. 50-150 prompts, organized:

| Category | Example for project-management SaaS |
|---|---|
| Branded direct | "Acme PM pricing", "what is Acme PM" |
| Branded comparison | "Acme PM vs Asana", "is Acme better than Linear" |
| Generic informational | "best project management tool for distributed teams" |
| Generic commercial | "project management software with Gantt" |
| Lifecycle | "how to migrate from Asana to a new PM tool" |
| Procurement | "is Acme PM SOC 2 compliant", "Acme PM security review" |
| Long-tail informational | "how does sprint planning work" |

Save in `analyses/geo-query-set.json`:

```jsonc
{
  "version": 1,
  "owner_brand": "Acme PM",
  "competitors": ["Asana", "Linear", "Monday", "ClickUp", "Notion"],
  "queries": [
    { "id": "q-001", "prompt": "best project management software for remote teams",
      "category": "generic-commercial", "expect_brand_citation": true },
    ...
  ]
}
```

Refresh quarterly. Track which queries swing in or out of citing you.

---

## §3 — Manual SoLV measurement (week 1, no budget)

For each of the 6 major LLM surfaces, run the query set and record:

1. **Was your brand mentioned?** (binary)
2. **Was your URL cited?** (binary; some LLMs cite without linking)
3. **Position of citation** (rank in source list, if shown)
4. **Sentiment / framing** (positive / neutral / negative / dismissive)
5. **Snippet** (the exact words attributing your brand)
6. **Competitors cited above you** (rank order)

Surfaces to cover:
- Google AI Overviews (incognito, US English, no personalization)
- Google AI Mode (full conversational mode, March 2025+)
- ChatGPT (default model, browsing on)
- Claude (default model, web access on)
- Perplexity (default Pro mode if available)
- Bing Copilot (in Edge, no logged-in account)

Save runs to `analyses/geo-runs/<YYYY-MM-DD>.csv` per `assets/CITATION-TRACKING-CSV-SCHEMA.md`.

**Cadence:** weekly for the first 4 weeks, then biweekly. Establishing variance is half the value — most teams discover that LLM outputs swing 20-40% week-to-week even without site changes.

---

## §4 — Automated SoLV via API (when budget allows)

Wrappers exist for batch-querying:

```ts
// pseudocode for daily search-enabled ChatGPT and Claude runs
import OpenAI from "openai";
import Anthropic from "@anthropic-ai/sdk";

const openai = new OpenAI();
const anthropic = new Anthropic();

for (const q of querySet.queries) {
  const oa = await openai.chat.completions.create({
    model: "<current-search-enabled-model>",
    messages: [{ role: "user", content: q.prompt }],
    web_search_options: { search_context_size: "high" },
  });
  // record full response, citations array, mentions of {owner_brand, competitors}

  const an = await anthropic.messages.create({
    model: "<current-web-enabled-model>",
    tools: [{ type: "web_search_20250305", name: "web_search" }],
    max_tokens: 1024,
    messages: [{ role: "user", content: q.prompt }],
  });
  // same recording
}
```

Compute, per query and per surface:
- `brand_mentioned: bool`
- `brand_url_cited: bool`
- `citation_rank: int | null`
- `competitors_above_us: string[]`
- `response_text: string`

Aggregate to `analyses/solv-<date>.json`:

```jsonc
{
  "generated": "ISO-8601",
  "surface": "chatgpt|claude|perplexity|aio|aimode|copilot",
  "query_count": 100,
  "brand_mentioned_count": 47,
  "brand_url_cited_count": 31,
  "share_of_voice_pct": 47.0,
  "share_of_citations_pct": 31.0,
  "median_citation_rank": 3,
  "competitor_share": { "Asana": 0.62, "Linear": 0.58, "Monday": 0.41 },
  "queries": [/* per-query rows */]
}
```

---

## §5 — Server-side retrieval frequency

Every time `OAI-SearchBot`, `Claude-SearchBot`, `PerplexityBot`, or `Perplexity-User` hits a URL, that URL is in the candidate retrieval pool for some user prompt — strong leading indicator.

Parse CDN/access logs (one request per row) to:
- `analyses/retrieval-frequency.json` per URL: `{url, bot, requests_per_day, last_seen_at}`
- `analyses/retrieval-by-template.json`: aggregate by URL template family

Cloudflare AI Audit dashboard exposes this without log parsing if you're on Cloudflare. AWS WAF and Akamai have analogous offerings.

**Heuristic:** URLs with rising retrieval-frequency are gaining LLM eligibility; URLs whose retrieval drops to zero have either been deindexed by the LLM or no longer match relevant prompts.

---

## §6 — Citation latency study

For each new content publication:

1. Mark publish date.
2. Daily run of relevant prompts on each surface.
3. Record first day the URL is cited.

Example priors to calibrate against after you collect first-party data (varies wildly; do not promise these as SLA):

| Surface | Median first-citation | Notes |
|---|---|---|
| Perplexity | 1-3 days | Fastest; aggressive freshness |
| ChatGPT browsing | live (when retrieval triggers) | Ephemeral; depends on per-user prompt |
| Bing Copilot | 2-7 days | Tracks Bing index lag |
| Google AIO | 2-6 weeks | Tracks Google index + ranking lag |
| Claude | 3-10 days | Improved through 2025 |

If your latency is 2-3x the median, your retrieval-frequency is probably the bottleneck — not the content quality.

---

## §7 — Branded search lift after a confirmed LLM citation

When you confirm a citation in (say) Perplexity Pages with high reach, expect a measurable branded-search bump. Quantify:

1. Day-of-citation marker.
2. 7-day baseline branded clicks (GSC, queries containing brand).
3. 7-day post-citation branded clicks.
4. Lift % and confidence interval.

Track in `analyses/citation-impact.csv`:

```csv
date,citation_url,surface,reach_estimate,branded_baseline,branded_post,lift_pct
2026-04-15,https://www.perplexity.ai/page/...,perplexity,~10000,820,1190,+45.1%
```

Lift > +20% sustained > 14 days is a high-leverage citation; double down on similar content.

---

## §8 — What does NOT work

- Treating OpenAI search / ChatGPT browsing like Google search. Different retrieval pool, different ranking signals.
- Treating one citation as a trend. LLM outputs are stochastic week-over-week; collect ≥4 data points before drawing conclusions.
- Using "AI Overview impressions" as a separate GSC metric — AI feature traffic is blended into Web performance today; citations still require a separate log.
- Assuming user-agent strings in logs are honest. Verify high-volume bot UAs by reverse DNS.
- Citing a published "study" claiming "X% of queries trigger AIO" — these are point-in-time snapshots from particular query sets, often not generalizable. Always log methodology + date in `assets/SOURCE-LOG-TEMPLATE.md`.

---

## §9 — Reporting cadence

| Cadence | Artifact |
|---|---|
| Daily (automated only) | API SoLV runs |
| Weekly | Manual SoLV spot-check (~10 prompts) |
| Biweekly | Citation-tracking CSV update |
| Monthly | `analyses/reports/geo-<month>.md` — SoLV trend, citation count, retrieval-frequency change, citation-impact wins |
| Quarterly | Query-set refresh; competitor list update |

Wire into `assets/MONTHLY-EXEC-TEMPLATE.md` as a dedicated GEO section.

---

## §10 — Decision rules

| If... | Then... |
|---|---|
| SoLV < 10% across all surfaces | Phase-1 problem: substrate (run `ai-crawler-view.ts`); content is not retrievable |
| SoLV high in Perplexity, low in AIO | Likely: Google retrieval / citation eligibility issue (trust, freshness, schema, indexability) — see `TRUST-INFRASTRUCTURE.md`, `AI-VISIBILITY.md`, and `SCHEMA-POLICY.md` |
| SoLV high but citation rank consistently below competitors | Outrank-the-citation problem: passage extractability + uniqueness — see `CITATION-OPS.md` |
| Branded search lift ≈ 0 from confirmed citations | Citation reach is low or your brand isn't recognizable; consider trust-signal pass — see `TRUST-INFRASTRUCTURE.md` |
| Retrieval frequency dropping URL-by-URL | Content decay or recently deindexed; cross-check `gsc-extract.ts` and run `crawl.ts` for canonical/robots issues |

---

## §11 — Future scripts (placeholders, build when budget exists)

- `scripts/share-of-llm-voice.ts` — daily API run across 50-150 prompts on 4 LLM surfaces; write `analyses/solv-<date>.json`
- `scripts/retrieval-frequency.ts` — parse CDN logs, aggregate by URL × bot
- `scripts/citation-latency.ts` — track-publish-date → first-citation polling

These are documented here so an agent knows the contract before implementing.
