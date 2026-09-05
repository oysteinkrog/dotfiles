# LOG-FILE-ANALYSIS

Server logs are the only source of truth for what bots actually fetched, when, with what status, and how long it took. GSC summarizes; logs prove. Useful for T3+ sites, traffic-drop diagnoses, and any programmatic launch.

## Phase mapping

| Phase | Use this doc for |
|---|---|
| 1 — Discovery | Bot crawl baseline; verified-bot share; crawl-waste candidates. |
| 3 — Technical | 5xx/4xx for verified bots; asset-fetch failures; crawl traps. |
| 12 — Verify | Post-deploy: did Googlebot re-crawl the changed URLs? AI bots see new content? |
| `traffic-drop-triage` | Did Googlebot stop crawling? Did 5xx spike for verified bots? |

## Verified bot identification

`confirmed`: User-Agent strings are forgeable. Real bots are identified by reverse + forward DNS lookup, not user agent alone.

| Bot | Verification method | Source |
|---|---|---|
| Googlebot | rDNS ends with `.googlebot.com` or `.google.com`; forward-DNS matches IP | Google official docs |
| Googlebot-Smartphone | same as Googlebot | Google official docs |
| Bingbot | rDNS ends with `.search.msn.com`; forward-DNS matches | Bing Webmaster |
| GPTBot | IP in OpenAI's published range; UA contains `GPTBot/X.Y` | OpenAI docs |
| OAI-SearchBot | IP in OpenAI ranges; UA contains `OAI-SearchBot/X.Y` | OpenAI docs |
| ChatGPT-User | IP in OpenAI ranges | OpenAI docs |
| ClaudeBot | IP in Anthropic ranges; UA `ClaudeBot/X.Y` | Anthropic docs |
| anthropic-ai | IP in Anthropic ranges | Anthropic docs |
| PerplexityBot | IP in Perplexity ranges; UA `PerplexityBot/X.Y` | Perplexity docs |
| Perplexity-User | IP in Perplexity ranges | Perplexity docs |

The IP ranges drift; refresh the verifier monthly.

### rDNS verification for Googlebot

```bash
# Pick an IP from the logs claiming to be Googlebot
host 66.249.66.1
# 1.66.249.66.in-addr.arpa domain name pointer crawl-66-249-66-1.googlebot.com.

host crawl-66-249-66-1.googlebot.com
# crawl-66-249-66-1.googlebot.com has address 66.249.66.1
```

Both must match for the request to be a real Googlebot. Any mismatch = spoof; treat the request as a low-quality bot or potential scraper.

### Verifier (TypeScript)

```ts
// scripts/verify-bot.ts
import { reverse } from "node:dns/promises";

const ALLOWLIST: Record<string, string[]> = {
  Googlebot: [".googlebot.com", ".google.com"],
  Bingbot: [".search.msn.com"],
  // GPTBot, ClaudeBot, Perplexity verified by IP-range, not rDNS
};

export async function verify(ip: string, claimedUA: string) {
  const host = (await reverse(ip).catch(() => []))[0];
  if (!host) return { verified: false, reason: "no rDNS" };
  const matches = Object.entries(ALLOWLIST).find(([, suffixes]) =>
    suffixes.some((s) => host.endsWith(s)),
  );
  if (!matches) return { verified: false, reason: `rDNS ${host} not in allowlist` };
  // Forward-DNS check
  const { lookup } = await import("node:dns/promises");
  const fwd = await lookup(host).catch(() => null);
  return { verified: fwd?.address === ip, host };
}
```

## Vercel log drains setup

Vercel emits logs to a configured drain (HTTP, Datadog, Logtail, S3). Steps:

1. Vercel Dashboard → Project → Settings → Log Drains → Add.
2. Type: HTTPS / Datadog / Axiom / Logtail / S3.
3. Filter: keep `request` events; optionally filter to status >= 400 + bot UAs.
4. Verify drain receiving sample.

For high-volume sites, ship to S3 → Athena or BigQuery for SQL analysis.

```sql
-- Athena schema for Vercel JSON logs
CREATE EXTERNAL TABLE IF NOT EXISTS vercel_logs (
  id string,
  timestamp bigint,
  level string,
  type string,
  request struct<
    method: string,
    path: string,
    host: string,
    headers: map<string,string>,
    referer: string,
    userAgent: string
  >,
  response struct<statusCode: int, durationMs: int>,
  ip string,
  region string
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://acme-vercel-logs/';
```

## Cloudflare Logpush setup

For sites behind Cloudflare:

1. Cloudflare Dashboard → Analytics & Logs → Logpush → Create.
2. Dataset: `HTTP requests`.
3. Fields: include `ClientIP`, `EdgeStartTimestamp`, `RayID`, `EdgeResponseStatus`, `ClientRequestPath`, `ClientRequestUserAgent`, `ClientRequestReferer`, `EdgeResponseBytes`, `OriginResponseStatus`, `EdgeServerIP`.
4. Destination: R2, S3, GCS, BigQuery, Datadog, Splunk.

Cloudflare sees the WAF / rate-limit blocks Vercel never sees.

## NGINX log format (self-hosted reference)

```nginx
log_format seo_combined
  '$remote_addr - $remote_user [$time_iso8601] '
  '"$request" $status $body_bytes_sent '
  '"$http_referer" "$http_user_agent" '
  'rt=$request_time uct="$upstream_connect_time" urt=$upstream_response_time';

access_log /var/log/nginx/access.log seo_combined;
```

Ship via Filebeat / Vector / Promtail to wherever the SQL engine lives.

## Per-bot crawl rate

Daily / weekly counts per verified bot, per status class:

```sql
-- BigQuery / Athena
SELECT
  DATE(TIMESTAMP_MILLIS(timestamp)) AS day,
  CASE
    WHEN REGEXP_CONTAINS(request.userAgent, r'Googlebot/') THEN 'Googlebot'
    WHEN REGEXP_CONTAINS(request.userAgent, r'Googlebot-Smartphone') THEN 'Googlebot-Smartphone'
    WHEN REGEXP_CONTAINS(request.userAgent, r'bingbot') THEN 'Bingbot'
    WHEN REGEXP_CONTAINS(request.userAgent, r'GPTBot/') THEN 'GPTBot'
    WHEN REGEXP_CONTAINS(request.userAgent, r'OAI-SearchBot') THEN 'OAI-SearchBot'
    WHEN REGEXP_CONTAINS(request.userAgent, r'ClaudeBot') THEN 'ClaudeBot'
    WHEN REGEXP_CONTAINS(request.userAgent, r'PerplexityBot') THEN 'PerplexityBot'
    ELSE 'other'
  END AS bot,
  CASE
    WHEN response.statusCode BETWEEN 200 AND 299 THEN '2xx'
    WHEN response.statusCode BETWEEN 300 AND 399 THEN '3xx'
    WHEN response.statusCode BETWEEN 400 AND 499 THEN '4xx'
    WHEN response.statusCode BETWEEN 500 AND 599 THEN '5xx'
    ELSE 'other'
  END AS status_class,
  COUNT(*) AS hits,
  AVG(response.durationMs) AS avg_ms,
  APPROX_QUANTILES(response.durationMs, 100)[OFFSET(95)] AS p95_ms
FROM vercel_logs
WHERE timestamp > UNIX_MILLIS(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY))
  AND ip IN (SELECT ip FROM verified_bots)  -- pre-verified IP table
GROUP BY 1, 2, 3
ORDER BY 1 DESC, hits DESC;
```

Maintain a `verified_bots` table (IP → bot name) refreshed nightly via the verifier.

## What to look for

| Signal | What it means | Severity |
|---|---|---|
| Googlebot 5xx % > 1 % | Reliability issue Google sees as a stability signal | high |
| Googlebot fetches per day drop > 30 % vs prior 28-day avg | Possible site-wide issue (server, robots.txt, hosting) | high |
| Googlebot fetches a route 100× more than peers | Crawl trap (filter explosion, calendar pagination, search URL) | medium-high |
| AI bots fetch the priority pages | Citation eligibility intact | green |
| AI bots fetch zero priority pages over 7 days | Either blocked, unreachable, or tagged `noindex` | high |
| 4xx for verified bots | Broken internal link or stale sitemap entry | medium |
| 5xx + spike in `response.durationMs` p95 | Origin overloaded or slow query | high |
| Asset (CSS/JS) 4xx for Googlebot-Smartphone | Render impacted | high |

## Crawl-waste detection

"Crawl waste" = bot fetches that consume budget without value. Worth eliminating *only* on T3+ sites where crawl budget actually matters (`confirmed` per Google).

```sql
-- Top 100 most-crawled paths by Googlebot, last 7 days
SELECT request.path, COUNT(*) AS hits
FROM vercel_logs
WHERE timestamp > UNIX_MILLIS(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY))
  AND REGEXP_CONTAINS(request.userAgent, r'Googlebot/')
GROUP BY request.path
ORDER BY hits DESC
LIMIT 100;
```

Inspect the list. Common waste:

| Pattern | Cause | Fix |
|---|---|---|
| `/blog?utm_source=...` | UTM in internal links | Strip UTM from internal links; canonical to clean URL |
| `/search?q=...` | Crawlable site search | `Disallow: /search` in robots.txt; noindex |
| `/integrations?category=...&sort=...` | Faceted nav | See [FACETED-NAV](FACETED-NAV.md) |
| `/blog/page/47/` | Deep pagination | Limit pagination depth; canonical to category |
| `/calendar/2017/03/` | Calendar pagination | `Disallow: /calendar/` |
| `/api/internal/...` | Bot fetching API endpoint | Exclude from sitemap; `Disallow: /api/` |

## 5xx / 4xx for verified bots

Per-status-code investigation:

```sql
-- Top 50 paths returning 5xx to Googlebot, last 7 days
SELECT request.path, response.statusCode, COUNT(*) AS hits, AVG(response.durationMs) AS avg_ms
FROM vercel_logs
WHERE timestamp > UNIX_MILLIS(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY))
  AND REGEXP_CONTAINS(request.userAgent, r'Googlebot/')
  AND response.statusCode >= 500
GROUP BY 1, 2
ORDER BY hits DESC
LIMIT 50;
```

For each row:

1. Reproduce manually (`curl` with Googlebot UA from US IP).
2. Check origin logs / function logs for the same request ID.
3. Categorize: timeout, exception, infra, rate-limit, edge config bug.
4. Fix or ratelimit-allowlist verified bots.

`anti-pattern`: rate-limiting verified Googlebot. The bot retries; chronic 429 = stop crawling.

## Asset-fetch failures

Googlebot needs CSS/JS to render. CSS/JS 4xx for Googlebot-Smartphone breaks render-as-Googlebot.

```sql
-- 4xx assets for Googlebot, last 7 days
SELECT request.path, response.statusCode, COUNT(*) AS hits
FROM vercel_logs
WHERE timestamp > UNIX_MILLIS(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY))
  AND REGEXP_CONTAINS(request.userAgent, r'Googlebot-Smartphone')
  AND response.statusCode BETWEEN 400 AND 499
  AND REGEXP_CONTAINS(request.path, r'\.(css|js|woff2?|png|jpg|svg)$')
GROUP BY 1, 2
ORDER BY hits DESC;
```

Common causes:

- Stale referenced asset hash after deploy (cache); add long-cached fingerprinted asset URLs.
- `_next/static/*` blocked by mis-scoped middleware.
- 404 on a font referenced in CSS that no longer exists.

## Crawl trap detection

A *crawl trap* is a URL pattern that generates near-infinite unique URLs from finite content. Classic patterns:

| Pattern | Example |
|---|---|
| Filter explosion | `/integrations?category=A&sort=X&page=2&...` (every combination) |
| Calendar pagination | `/blog/2003/12/` going back to year 0 |
| Search URLs | `/search?q=<anything>` indexed |
| Session ID in URL | `/page;jsessionid=abc123` |
| Tracking params | `/blog?utm_*=...` |
| Infinite redirects | `/page` → `/page/` → `/page` (loop) |

Detection:

```sql
-- Paths with > 1000 unique query-string variants, last 7 days
SELECT
  REGEXP_EXTRACT(request.path, r'^([^?]+)') AS base_path,
  COUNT(DISTINCT request.path) AS unique_urls,
  COUNT(*) AS total_hits
FROM vercel_logs
WHERE timestamp > UNIX_MILLIS(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY))
  AND REGEXP_CONTAINS(request.userAgent, r'Googlebot/')
GROUP BY 1
HAVING COUNT(DISTINCT request.path) > 1000
ORDER BY unique_urls DESC;
```

For each result, decide: `Disallow:` in robots, `noindex` on the page, parameter handling at the edge, or fix the internal link source.

## Crawl coverage check (post-deploy)

For every release that changed routing or content of a priority page:

1. Identify the changed URLs (from `seo-changelog.md`).
2. Check that Googlebot fetched them within 7 days post-deploy.
3. Check that AI bots fetched them within 14 days.
4. If not, file a beads / GSC URL inspection request.

```sql
-- Did Googlebot crawl /pricing in the last 7 days?
SELECT
  DATE(TIMESTAMP_MILLIS(timestamp)) AS day,
  response.statusCode,
  COUNT(*) AS hits
FROM vercel_logs
WHERE timestamp > UNIX_MILLIS(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY))
  AND request.path = '/pricing'
  AND REGEXP_CONTAINS(request.userAgent, r'Googlebot/')
GROUP BY 1, 2
ORDER BY 1 DESC;
```

## Operational dashboards (T3+)

Suggested SQL-backed dashboards refreshed every 6 hours:

| Dashboard | Cards |
|---|---|
| Bot health | Verified bot fetches/day; 5xx %; p95 latency per bot |
| Crawl coverage | Sitemap URL count vs Googlebot-fetched URL count over 28 days |
| Crawl waste | Top 100 paths by Googlebot hits; soft-404 candidates; query-string variants |
| AI bot citation eligibility | Per-priority-page fetch count per AI bot, last 14 days |
| Error budget | Hourly 5xx for any verified bot; pager threshold > 1 % over 1 h |

## Per-tier depth

| Tier | Depth |
|---|---|
| T1 | None — GSC + Vercel basic logs sufficient. |
| T2 | Vercel log drain to Logtail / Axiom; weekly crawl-waste glance. |
| T3 | BigQuery / Athena; verified-bot table; alerting on 5xx; quarterly crawl-trap sweep. |
| T4 | Real-time bot-health dashboard; per-template fetch budgets; per-deploy crawl-coverage check. |

## Worked example — phantom traffic drop

Symptom (2026-04-01): organic clicks down 18 % over 7 days, no GSC manual action, no algorithm update reported.

Diagnosis:

1. Pulled Googlebot fetches/day per [LOG-FILE-ANALYSIS](LOG-FILE-ANALYSIS.md) query above.
2. Googlebot fetches were down 73 % over the same 7 days. Bingbot, ClaudeBot, PerplexityBot unchanged.
3. Fetched `/robots.txt` as Googlebot; OK.
4. Top 4xx paths for Googlebot showed 100 % of `/api/og/*` returning 503.
5. `/api/og/*` is the OG image dynamic route. Edge function had hit a runtime memory limit.
6. The OG image is referenced from `<meta property="og:image">` on every page; Google was treating the resource failure as a render-blocking signal.

Fix:

1. Increased OG function memory; capped image generation timeout.
2. Pre-generated OG images for top 100 pages as static `/og/<slug>.png`.
3. Added 5xx alert on the `/api/og/*` route.

Recovery:

- Googlebot fetches/day returned to baseline within 4 days.
- Organic clicks recovered over 14 days.
- Documented the pattern in [ANTI-PATTERNS](ANTI-PATTERNS.md): "OG image function failure can present as organic-traffic drop."

## Anti-patterns

- Trusting User-Agent strings without rDNS verification.
- Rate-limiting verified Googlebot.
- Logging only edge events (Cloudflare) or only origin events (Vercel) when both are needed.
- Ignoring 4xx on assets — Googlebot needs CSS/JS to render.
- Aggregating bot data across all bots into one number.
- Crawl-budget worry on a 200-URL site.
- Blocking AI bots and then asking why citations dropped.
- Building a crawl-waste dashboard without acting on the top entries.
- "We have 100 % uptime" without bot-specific 5xx tracking.
- Letting `Bytespider` and other low-value bots eat 50 % of fetches.

## Cross-references

- [PHASE-1-DISCOVERY](PHASE-1-DISCOVERY.md) — bot baseline.
- [PHASE-3-TECHNICAL](PHASE-3-TECHNICAL.md) — server/render audit.
- [PHASE-12-VERIFICATION](PHASE-12-VERIFICATION.md) — post-deploy crawl-coverage check.
- [TRAFFIC-DROP-PLAYBOOK](TRAFFIC-DROP-PLAYBOOK.md) — log-led diagnosis.
- [FACETED-NAV](FACETED-NAV.md) — filter / parameter URLs.
- [CRAWL-BUDGET](CRAWL-BUDGET.md) — when crawl budget actually matters.
- [CITATION-OPS](CITATION-OPS.md) — AI-bot fetch tracking.
- [ANTI-PATTERNS](ANTI-PATTERNS.md) — full catalog.
- [EVIDENCE-LABELS](EVIDENCE-LABELS.md) — confidence/severity grammar.
