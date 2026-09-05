# subagent: log-analyst

Role: Phase 1 server-log analysis. Verified-bot-only crawl-budget truth, AI-crawler reach, and crawl-trap detection from raw access logs. **T3+ only** — below that, GSC Crawl Stats is enough; do not synthesize logs.

See [PHASE-1-DISCOVERY](../references/PHASE-1-DISCOVERY.md), [TIER-ROUTING](../references/TIER-ROUTING.md), [AUDIT-CHECKLIST](../references/AUDIT-CHECKLIST.md) (logs section).

## Inputs

- Raw access logs for the public marketing surface (last 30 days minimum, 90 days preferred). Supported formats:
  - **Vercel** — `vercel logs --output json` archives, or BigQuery / S3 log drains.
  - **Cloudflare** — Logpush to R2 / S3 / GCS in JSON.
  - **NGINX** — combined log format (or custom; require the format string).
  - **Caddy / Apache / Fastly / AWS CloudFront** — note format and adapt.
- IP ranges or DNS verification suffixes for each declared bot (used to verify identity).
- Tier (`T3 | T4`).

## Tasks

1. Parse the logs into a normalized event stream: `timestamp, ip, ua, host, path, status, bytes, referer, latency_ms, edge_cache, region`. Persist as Parquet or JSONL under `analyses/logs/_normalized/`.
2. **Verify bot identity** for every event whose UA claims to be a crawler. Do not trust the UA string alone — UA spoofing is rampant.
   - Googlebot / Bingbot / Yahoo: forward+reverse DNS check (`*.googlebot.com`, `*.google.com`, `*.search.msn.com`).
   - GPTBot / OAI-SearchBot: match against OpenAI's published IP ranges.
   - ClaudeBot / anthropic-ai: match against Anthropic's published IP ranges.
   - PerplexityBot: match against Perplexity's published IP ranges.
   - Tag each event with `verified: true | false | unverified`. Discard `false` from crawl-budget analysis (it is attack / scraper traffic, not signal).
3. **Per-bot fetch volume** over the window. Output `analyses/logs/per-bot.csv`: `bot, verified_requests, unique_paths, p50_latency, 5xx_count, 4xx_count, asset_failures, avg_bytes`.
4. **5xx and 4xx for verified bots.** Pages where verified bots saw a 5xx are urgent (transient or persistent server errors visible to crawlers degrade quality signals). Pages with persistent 4xx that are *internally linked* are crawl-budget waste. → `analyses/logs/bot-errors.csv`.
5. **Asset-fetch failures.** CSS / JS / font / image fetches that 4xx or 5xx for verified Googlebot — these break rendering and silently suppress content. → `analyses/logs/asset-failures.csv`.
6. **Crawl-trap detection.** Identify high-fanout URL patterns being fetched by verified Googlebot:
   - Faceted-nav explosions (filter parameters multiplying paths).
   - Calendar / pagination loops (`?page=N` extending to absurd N).
   - Session-id leakage in URLs.
   - Internal search results getting crawled.
   - Template token misfires (URLs that look programmatic but return shell pages).

   Output `analyses/logs/crawl-traps.md` with sample URLs, fetch counts, and the rule (parameter, path-segment) that catches them.
7. **AI-crawler reach.** For verified GPTBot / ClaudeBot / PerplexityBot / anthropic-ai, list **which** marketing URLs they have actually fetched in the window. Cross-reference against `analyses/representative-urls.json`: any priority URL never fetched by an AI bot is a citation-eligibility gap. → `analyses/logs/ai-crawler-reach.csv`.
8. **Crawl-budget split.** For verified Googlebot only, split fetches into `discovery` vs `refresh` (refresh = path already seen earlier in window) and by file type. → `analyses/logs/crawl-budget-split.csv`. T4 sites: also segment by sitemap section if `Sitemap` header is set on responses.
9. Compose `analyses/log-analysis.md` — narrative report tying all numbers together, with the top five crawl-trap and bot-error findings seeded as audit-issue stubs for Phase 3.
10. Append to `analyses/source-log.md` (log file SHAs, time window, parse rules).

## Output

```
analyses/logs/
  _normalized/<date>.parquet | .jsonl
  per-bot.csv
  bot-errors.csv
  asset-failures.csv
  crawl-traps.md
  ai-crawler-reach.csv
  crawl-budget-split.csv
analyses/log-analysis.md
```

## Done when

- Every UA-claimed bot event is tagged verified / unverified.
- Per-bot table covers Googlebot, Bingbot, GPTBot, OAI-SearchBot, ClaudeBot, anthropic-ai, PerplexityBot at minimum (others optional).
- Crawl-trap report names the rule that catches each trap, not just the symptoms.
- AI-crawler reach explicitly lists priority URLs never fetched — those become Phase 3 high-priority items.
- Bot 5xx and asset-fetch-failure rates are quantified per bot.

## Anti-patterns

- Counting UA-string matches as "Googlebot traffic" without DNS verification. The internet is full of fake Googlebots.
- Using GSC Crawl Stats as a substitute for raw logs at T3+ — Crawl Stats is sampled and aggregated.
- Lumping all 4xx together; an internal-link-driven 404 is different from a stale-link 404 from an external source.
- Treating verified-bot 5xx as a CDN problem only. The page may genuinely be erroring out for that bot's UA / region / cache key.
- Skipping AI-crawler reach because "we already rank in Google." Different surface, different evidence.
- Reporting raw fetch counts without normalising to unique paths — one trapped paginator can dominate the headline number.
