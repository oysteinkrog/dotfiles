# CITATION-OPS

Operating manual for earning, tracking, and defending citations in AI Overview, AI Mode, ChatGPT (with browsing + web), Perplexity, and Claude. Builds on [AI-VISIBILITY](AI-VISIBILITY.md). Where AI-VISIBILITY says *what* matters, this document says *what to do, when, and how to measure*.

## Phase mapping

| Phase | Use this doc for |
|---|---|
| 1 — Discovery | Baseline citation share per priority page; current AI-bot policy. |
| 3 — Technical | Verify AI-bot view = Googlebot view; bot allow/block decisions in `app/robots.ts`. |
| 4 — Content | Passage-level rewrites that earn citation; entity reconciliation across surfaces. |
| 8 — Analytics | Weekly tracking workflow; referrer-log analysis; alerting. |
| 10 — Fresh-eyes | Citation-extractability scoring per priority page. |
| 12 — Verify | Post-deploy citation regression check. |
| 13 — Compounding | Quarterly citation surface review and rewrite ladder. |

## Measurement contract

Do not promise the user an AI Overview / AI Mode report that Google does not expose.

| Signal | What it can prove | What it cannot prove |
|---|---|---|
| GSC Performance, Web search type | Blended Search clicks / impressions / CTR / position, including AI features | Which exact AI feature cited which URL |
| Manual / browser SERP capture | Citation presence and visible cited URLs for a query at a time | Complete traffic volume or stable national/global share |
| GA4 + server referrers | Sessions from ChatGPT / Perplexity / Claude / Copilot-like referrers | Google AI Overview clicks as a distinct source |
| Logs by crawler UA | Crawl / fetch access by retrieval and training bots | Whether the bot used the content in an answer |
| First-party experiments | Directional lift for this property | Universal rank/citation formulas |

Every weekly citation report must show these as separate columns. Mixing them into one "AI traffic" number makes attribution look cleaner than it is.

## Per-platform citation patterns

`confidence: likely` for all rows except where flagged `confirmed`. Re-verify quarterly; the surfaces move.

| Platform | Bot(s) | Selection bias | Citation density | What works |
|---|---|---|---|---|
| Google AI Overview | Googlebot Smartphone (rendering) | Often anchored to organic authority, but exact top-10/citation relationship is volatile | 2-4 sources cited | Organic strength + 3+ unique data points + dated proof |
| Google AI Mode | Googlebot Smartphone | Wider source pool; favors *evidence diversity* over rank | 5–10 sources cited | Same as AI Overview but with *more* evidence types per page (table + numeric + dated quote + screenshot) |
| ChatGPT (web/browse) | `OAI-SearchBot` (retrieval), `GPTBot` (training; allow/block independently) | Long-context summarization; rewards completeness and headings | 1–4 sources cited | Self-contained sections, clean H2/H3 hierarchy, no JS-required content |
| Perplexity | `PerplexityBot` (retrieval), `Perplexity-User` (real-time) | Aggressive multi-source citation; favors recency and freshness | 5–10 sources | Dated content, original analysis, public datasets, status/changelog |
| Claude | `Claude-SearchBot` (search), `Claude-User` (user-initiated retrieval), `ClaudeBot` (training; allow/block independently) | Initial HTML only; rewards clear answer-first paragraphs | 1–3 sources | Direct answer at top of section; numeric data with units; no fluff |

`confirmed`: initial HTML is the safest cross-crawler contract. Exact JavaScript execution behavior is bot- and product-specific; verify live before treating a surface as render-capable.

## Bot allow/block decision tree

For each AI bot, decide *retrieval* and *training* independently. Defaults below; document the chosen stance in `seo-changelog.md` and mirror in `app/robots.ts` and the CDN edge.

```
For each AI bot:
  Is the bot a retrieval bot (powers live citations)?
    YES → does the SaaS want citations on that surface?
      YES → ALLOW (do not block in robots.txt; do not block at edge)
      NO  → BLOCK (lose citation surface; only choose if surface harms brand)
    NO (training / non-Search AI-control, e.g. GPTBot, Google-Extended, ClaudeBot, anthropic-ai)
      Does the SaaS want its content used in model training?
        YES → ALLOW
        NO  → BLOCK (does not affect retrieval citations from same vendor)
```

| Bot | Role | Default for SaaS | Notes |
|---|---|---|---|
| `Googlebot` | Search + AI Overview render | ALLOW | Required for organic and AIO. |
| `Googlebot-Smartphone` | Mobile render | ALLOW | Same as above. |
| `Google-Extended` | Gemini / Vertex AI training and grounding control | Business decision | Blocking does not remove from Google Search or AI Overview today. `confirmed` per Google docs. |
| `Bingbot` | Bing search, Copilot | ALLOW | Bing/Copilot citation source. |
| `GPTBot` | OpenAI training | Often BLOCK | Does *not* power live ChatGPT browsing. |
| `OAI-SearchBot` | OpenAI retrieval (live ChatGPT search) | ALLOW if you want ChatGPT citations | Block this and ChatGPT cannot cite you. |
| `ChatGPT-User` | User-initiated ChatGPT browsing | ALLOW | Real-time fetch on user query. |
| `ClaudeBot` | Anthropic training | Often BLOCK | Does not power Claude user-directed retrieval by itself. |
| `Claude-SearchBot` | Anthropic search index | ALLOW if you want Claude search visibility | Current Anthropic search crawler. |
| `Claude-User` | User-initiated Claude retrieval | ALLOW | Real-time fetch on user query. |
| `anthropic-ai` | Older Anthropic training agent | Business decision | Largely retired but some operators still see hits. |
| `PerplexityBot` | Perplexity retrieval | ALLOW if you want Perplexity citations | Block kills Perplexity citations. |
| `Perplexity-User` | Perplexity real-time fetch | ALLOW | Real-time fetch on user query. |
| `Meta-ExternalAgent` | Meta crawler | Business decision | No clear retrieval surface yet. |
| `cohere-ai` | Cohere training | Business decision | Training only. |
| `Bytespider` | ByteDance | Often BLOCK | High-volume, low retrieval value. |
| `CCBot` | Common Crawl | Business decision | Indirectly powers many models. |

`anti-pattern`: blocking `Claude-SearchBot` or `Claude-User` while wanting Claude citations. Blocking `ClaudeBot` is a training-policy decision, not a complete Claude visibility opt-out.

## Weekly citation tracking workflow

Owner: SEO lead. 30–45 minutes/week for T2; ~2 hours/week for T3+.

### Step 0 — Record the measurement caveat

At the top of every citation summary, include:

```md
Measurement note: Google reports AI Overview / AI Mode traffic inside GSC Web performance, not as a separate citation export. Citation presence below comes from manual / instrumented captures. Referrer sessions cover non-Google AI surfaces where referrers are available.
```

### Step 1 — Sample priority queries (Monday)

Maintain `analyses/citation-queries.csv`:

| query | platform | priority_page | last_position | last_cited_url | last_check |
|---|---|---|---|---|---|
| `acme soc 2 evidence` | AIO,ChatGPT,Perplexity,Claude | /security/soc2 | 4 | /security/soc2 | 2026-04-22 |
| `notion acme integration` | AIO,Perplexity | /integrations/notion | 6 | /integrations/notion | 2026-04-22 |

T1: 5–10 queries. T2: 20–40. T3: 100–200. T4: hundreds, automated daily.

### Step 2 — Capture SERPs and AI surfaces

Run `scripts/serp-snapshot.ts --queries analyses/citation-queries.csv --out analyses/snapshots/`. The script captures:

- Google SERP HTML (AI Overview present? cited URLs? positions?).
- Google AI Mode response (separate session).
- ChatGPT with browsing (via API or instrumented browser).
- Perplexity (via API).
- Claude (via API with web search tool).

Store raw response + extracted citation URLs per query per platform per day.

For Google AI Mode / AI Overviews, also log the fan-out shape when visible:

| Field | Example |
|---|---|
| `fanout_topics_seen` | `pricing, migration, SOC 2, GitHub integration` |
| `missing_cluster_support` | `/security/soc2-evidence-list` absent; no pricing limits page |
| `next_content_move` | add migration proof page and link from comparison owner |

### Step 3 — Update `analyses/ai-citations.csv`

Append-only log. Schema:

```
date,query,platform,position_in_citation,cited_url,cited_passage,host_organic_rank
2026-04-22,acme soc 2 evidence,AIO,1,https://www.example.com/security/soc2,"Acme connects to AWS, GCP, GitHub, and Okta...",4
2026-04-22,acme soc 2 evidence,Perplexity,2,https://www.example.com/security/soc2,"...47 control-mapped artifacts on a 6-hour cadence",-
2026-04-22,notion acme integration,AIO,-,-,-,6
```

A `-` for `position_in_citation` means the page ranked but was not cited. This is the most diagnostic row in the file.

### Step 4 — Cross-reference referrer logs

Pull the previous week's GA4 + server logs filtered by referrer. Key referrers (`confidence: confirmed` for the host strings, `likely` for behavior):

| Surface | Referrer host(s) |
|---|---|
| ChatGPT | `chat.openai.com`, `chatgpt.com` |
| Perplexity | `perplexity.ai`, `www.perplexity.ai` |
| Claude | `claude.ai` |
| Google AI Overview | `google.com` (no special header; can't directly attribute today — `hypothesis`) |
| Bing Copilot | `bing.com`, `copilot.microsoft.com` |
| Gemini | `gemini.google.com` |

Filter GA4 (`Source / medium`) and Vercel/Cloudflare logs (`Referer` header). Append to `analyses/ai-referrer-traffic.csv`.

```sql
-- BigQuery / Vercel log analytics example
SELECT
  DATE(timestamp) AS day,
  REGEXP_EXTRACT(referer, r'https?://([^/]+)') AS referrer_host,
  request_path,
  COUNT(*) AS sessions
FROM logs
WHERE referer LIKE '%chat.openai.com%'
   OR referer LIKE '%chatgpt.com%'
   OR referer LIKE '%perplexity.ai%'
   OR referer LIKE '%claude.ai%'
   OR referer LIKE '%copilot.microsoft.com%'
   OR referer LIKE '%gemini.google.com%'
GROUP BY 1, 2, 3
ORDER BY 1 DESC, sessions DESC;
```

### Step 5 — Weekly summary

`analyses/citation-summary-YYYY-WW.md`:

```md
# Week 2026-W17 citation summary

## Movement
- /security/soc2: cited on AIO + Perplexity + Claude (3/4 surfaces). ChatGPT lost citation (position 1 → 0). `severity: medium`
- /integrations/notion: ranks #6 organic but no AIO citation. `severity: high` — striking distance.

## Referrer traffic (delta vs prior 7 days)
- ChatGPT: 142 sessions (+24%), 8 conversions (+33%)
- Perplexity: 87 sessions (+12%), 3 conversions (flat)
- Claude: 19 sessions (-5%), 1 conversion

## Action items
- /integrations/notion: add 3 unique data points + dated screenshot. Recheck 2026-W19. `confidence: likely`
- /security/soc2 ChatGPT loss: investigate raw-HTML diff between 2026-04-15 and 2026-04-22. `confidence: hypothesis`
```

### Step 6 — Alerting

Set up alerting on:

| Trigger | Severity |
|---|---|
| Priority page drops out of citation on any single surface for 2 consecutive weeks | high |
| Priority page drops out of citation on 2+ surfaces in same week | critical |
| Total AI referrer sessions drop > 30 % WoW | high |
| Referrer host changes (e.g. `chatgpt.com` replaces `chat.openai.com`) | low — investigate |

Wire to Slack / email; do not bury in dashboards.

## Passage-level rewrites that earn citations

Every priority section follows this pattern. See [AI-VISIBILITY](AI-VISIBILITY.md) for the underlying mechanics.

### Anatomy of a citation-earning passage

```md
## How does Acme handle SOC 2 evidence collection?

Acme connects to your AWS, GCP, GitHub, and Okta tenants via read-only OAuth
scopes and pulls 47 control-mapped artifacts on a 6-hour cadence. Evidence is
hashed (SHA-256), timestamped against TSA, and stored in a write-once audit
log. As of 2026-04, customers complete the SOC 2 Type II window in a median of
9 weeks (n=312 customers, vs an industry median of 6 months reported by
[Vanta 2025 customer benchmarks](https://www.vanta.com/...)).

[See the full list of 47 artifacts →](/security/soc2-evidence-list)
```

`citation_extractability_score_0_1000 = 1000`: stands alone, direct answer, three numeric data points with date and source, next-step link.

### Rewrite ladder per passage

Apply in order, smallest change first. Stop when `citation_extractability_score_0_1000 >= 900`.

| Score gap | Points at risk | Smallest change |
|---|---:|---|
| Missing direct answer | -200 | Move the answer sentence to the top of the section. |
| < 3 unique data points | -250 | Add one numeric data point with unit + date. |
| No source | -200 | Cite one external source with link. Internal source counts if dated and original. |
| Not standalone | -150 | Rewrite to remove "as discussed above" / "see the previous section" / "this means". |
| No next step | -100 | Add one outbound link to the closest concrete action. |
| Date stale (> 6 months) | -100 | Refresh data point + bump `dateModified` in schema. |

### Heading style for citation extractability

AI engines lean on H2/H3 to chunk pages. Optimize headings as questions or direct claims:

- Bad: `Our security architecture`
- Better: `How Acme handles SOC 2 evidence collection`
- Best: `How does Acme collect SOC 2 evidence?` (matches user query closely)

Do not write Q&A headings only to game schema. Use them when the section actually answers a question.

## Entity reconciliation across surfaces

AI engines reconcile your *entity* (company, product, founder, key feature) across multiple sources. Drift breaks citation.

### Per-entity audit

For each canonical entity, build a row:

| Entity | Canonical form | Variants seen | Source pages | Action |
|---|---|---|---|---|
| Company | `Acme` | `Acme Inc`, `acme`, `Acme.io` | homepage h1, footer, schema, X bio, LinkedIn, Crunchbase | Pick `Acme`; update LinkedIn + Crunchbase to `Acme`; keep `Acme Inc` only in legal footer |
| Product | `Acme Pro` | `acme-pro`, `AcmePro`, `Acme Professional` | pricing page, docs, CSS class names (irrelevant), changelog | Pick `Acme Pro`; rewrite changelog and docs |
| Founder | `Jane Doe, CEO and Co-founder` | `Jane Doe`, `Jane K. Doe`, `Jane Doe (CEO)` | about page, LinkedIn, Crunchbase, X, podcast bios | Pick one bio, propagate via `Person` schema with `sameAs` |
| Pricing claim | `$29/mo Starter` | `$29/month`, `from $29`, `29 USD/month` | pricing, schema, comparison pages | Pick `$29/month`; reflect identically in `Offer` schema |

Inconsistency creates citation ambiguity. Engines either cite the wrong page, cite a competitor's mention of you, or skip the entity entirely.

### `sameAs` reciprocity

Every profile linked from `Organization.sameAs` should link back to the canonical homepage. Audit quarterly:

| Profile | URL | Links back? | Display name matches? | Last verified |
|---|---|---|---|---|
| GitHub | `github.com/acme` | yes | yes | 2026-04 |
| X | `x.com/acme` | yes | yes | 2026-04 |
| LinkedIn | `linkedin.com/company/acme` | yes | uses `Acme Inc` — change to `Acme` | 2026-04 |
| Crunchbase | `crunchbase.com/organization/acme` | yes | yes | 2026-04 |
| ProductHunt | `producthunt.com/products/acme` | yes | yes | 2026-04 |

See [SCHEMA-COOKBOOK](SCHEMA-COOKBOOK.md) for the canonical `Organization` block.

## Per-tier depth

| Tier | Depth |
|---|---|
| T1 | 5–10 sample queries weekly; 1 platform (whichever surface drives traffic). Skip log filter. |
| T2 | 20–40 queries weekly; 3 platforms; manual referrer review. |
| T3 | 100+ queries; 5 platforms; automated SERP capture; logs piped to BigQuery. |
| T4 | Hundreds of queries; daily capture; share-of-voice tracking; alerting wired to incident channel. |

## Worked example — winning Claude citation on `/integrations/stripe`

Initial state (2026-04-15):
- Ranks #4 organic for `stripe acme integration`.
- AIO: cited (passage 1).
- ChatGPT: cited (passage 1).
- Perplexity: cited (passage 2).
- Claude: NOT cited.

Diagnosis:
1. Fetched URL with `curl -A "ClaudeBot/1.0"`; raw HTML contained title, h1, first paragraph, but the *setup steps* were rendered via `useEffect` after a feature flag check.
2. Claude's preferred citation pattern is direct-answer paragraphs. The page led with marketing copy, then the setup steps, then proof.
3. Pricing data point (`Stripe charges 2.9% + 30¢`) was correct on the page but undated.

Fix:
1. Move setup steps to Server Component (raw HTML now contains them).
2. Open page with H2 `How does Acme integrate with Stripe?` followed by 80-word direct answer.
3. Add `(as of 2026-04, see [Stripe pricing](https://stripe.com/pricing))` to the pricing claim.

Result (2026-04-29 recheck):
- AIO: still cited.
- Claude: cited at position 1.
- ChatGPT: cited.
- Perplexity: cited at position 1 (was 2).
- Organic position: #3 (was #4).
- Referrer sessions from `claude.ai` over 7 days: 23 (was 0).

Trade-offs: rewrite shipped in one PR with a `seo-changelog.md` entry. Recheck-by date was 14 days. No rollback needed.

## When to *block* an AI bot

Rare but valid:

- **Sensitive content surface.** Internal docs accidentally indexed; tactical block while you fix index discipline.
- **Citation-on-the-wrong-page.** A specific bot keeps citing your stale page; tactical rewrite is preferable, but block-then-redirect is a fallback.
- **High volume, no return.** A bot is fetching `/api/*` repeatedly without producing citations. Block via robots and at edge.

Do not block AI bots as a "we don't want to be in AI" stance unless leadership has signed off; you cede a discovery surface that you cannot get back without re-earning crawler trust over weeks.

## Anti-patterns

- Treating AI citation as a side effect of organic ranking — they decoupled (`confirmed`).
- Adding `llms.txt` as a citation tactic — no measurable lift (`likely`; see [GUIDE-RECONCILIATION](GUIDE-RECONCILIATION.md)).
- Blocking `GPTBot` and expecting ChatGPT citations to drop — `GPTBot` is training, not retrieval; blocking does not affect live citation. (`confirmed`)
- Allowing `OAI-SearchBot` but blocking it at the CDN/WAF — robots.txt and edge must agree.
- Stuffing 10 data points without dates, sources, or context — fails extractability.
- Hiding the answer behind a "click to expand" accordion that hydrates client-side.
- Auto-redirecting `ClaudeBot` based on geo-IP — the bot may not present a region, gets redirected somewhere unintended.
- Never measuring AI referrer traffic — citation gains are invisible without referrer tracking.
- Citing AI surfaces as "free traffic" — they convert differently; track conversions per source separately in GA4.

## Hypothesis log

| Claim | Confidence |
|---|---|
| Initial HTML is the safest cross-crawler citation contract | confirmed |
| Citation-from-top-10 dropped to ≈38% URL-level (early 2026) | likely |
| 3+ unique data points → 4× more likely to be cited | likely |
| Per-platform citation patterns differ meaningfully | likely |
| Blocking `OAI-SearchBot` removes ChatGPT citations | likely |
| Google AI Overview attribution via `Referer` is unreliable | hypothesis |
| Heading-as-question style improves Claude citation odds | hypothesis |

Mark recommendations downstream of `likely` / `hypothesis` claims accordingly per [EVIDENCE-LABELS](EVIDENCE-LABELS.md). Re-verify quarterly.

## Cross-references

- [AI-VISIBILITY](AI-VISIBILITY.md) — underlying citation mechanics.
- [GEO-MEASUREMENT](GEO-MEASUREMENT.md) — share-of-LLM-voice, citation latency, retrieval-frequency methodology.
- [AI-BOTS-AND-LLMSTXT](AI-BOTS-AND-LLMSTXT.md) — bot UA matrix and robots.txt patterns; allow search/on-demand bots before chasing citations.
- [AUTHORSHIP-AND-EEAT](AUTHORSHIP-AND-EEAT.md) — author + Organization entity surface; LLMs cite named-author technical content disproportionately.
- [SCHEMA-COOKBOOK](SCHEMA-COOKBOOK.md) — `Organization`, `Person`, `WebApplication` blocks for entity reconciliation.
- [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md) Gate 8 — programmatic templates and AI visibility.
- [OPERATORS](OPERATORS.md) ⌬ AI-Citation Extractability — passage-level operator card.
- [EVIDENCE-LABELS](EVIDENCE-LABELS.md) — confidence/severity grammar.
- [ANTI-PATTERNS](ANTI-PATTERNS.md) — full anti-pattern catalog.
