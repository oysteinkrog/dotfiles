# AI-BOTS-AND-LLMSTXT — Crawler Policy for the LLM Era

> **Why this exists:** SaaS sites in 2026 must distinguish *training* bots from *search-index* bots from *on-demand-browse* bots. Most teams accidentally block the wrong one and lose LLM citations. This reference is the canonical map.

---

## §1 — Bot user-agent matrix

Reverify against official provider docs before changing a production robots or WAF policy. Bot names and IP ranges drift; the durable rule is to separate training, search/index, user-initiated retrieval, and ads/compliance fetches.

| Provider | UA | Purpose | Block to opt out of... | Allow to enable... |
|---|---|---|---|---|
| OpenAI | `GPTBot` | Training | ChatGPT model training | (no direct end-user benefit) |
| OpenAI | `OAI-SearchBot` | OpenAI search index | OpenAI search corpus | citations in ChatGPT / OpenAI search answers |
| OpenAI | `ChatGPT-User` | On-demand browsing per user prompt | bypass-ability for end-user ChatGPT browsing | ChatGPT users browsing your site live |
| OpenAI | `OAI-AdsBot` | Ads / landing-page policy checks | ChatGPT ads page validation | ChatGPT ads eligibility / relevance |
| Anthropic | `ClaudeBot` | Training | Claude model training | (no direct end-user benefit) |
| Anthropic | `Claude-User` | User-initiated retrieval | live retrieval by Claude users | live retrieval by Claude users |
| Anthropic | `Claude-SearchBot` | Search index (added 2025) | Claude search corpus | citations in Claude responses |
| Anthropic | `anthropic-ai` | Legacy / observed in logs | legacy training corpus if still used | — |
| Google | `Googlebot` | Search & AI Overviews | classic Search ranking | classic Search ranking |
| Google | `Google-Extended` | Gemini / Vertex AI training and grounding control | Google AI model training / grounding uses (NO Search ranking effect) | (does not affect Search inclusion or ranking) |
| Google | `GoogleOther` | General-purpose | Google R&D crawls | Google R&D crawls |
| Perplexity | `PerplexityBot` | Index | Perplexity training/index | citations in Perplexity |
| Perplexity | `Perplexity-User` | On-demand (bypasses robots.txt by design — controversial) | (cannot fully block via robots.txt) | live user retrievals |
| Apple | `Applebot` | Search index (Spotlight, Siri) | Apple Search index | Apple Search results |
| Apple | `Applebot-Extended` | Apple Intelligence training opt-out | Apple Intelligence model training | (does not affect Apple Search) |
| ByteDance | `Bytespider` | TikTok / Doubao | aggressive scraping | TikTok-related visibility |
| Common Crawl | `CCBot` | Common Crawl corpus | upstream training data feed for many LLMs | (no direct benefit) |
| Meta | `Meta-ExternalAgent` | Meta AI training | Meta AI model training | — |
| Meta | `Meta-ExternalFetcher` | On-demand fetch | live retrieval | live retrieval |
| Mistral | `MistralAI-User` | On-demand | live retrieval | live retrieval |
| Yandex | `YandexBot` | Yandex search | Yandex Search | Yandex Search |
| Bing | `bingbot` | Bing search & Copilot | Bing & Copilot | Bing & Copilot |

**Critical inferences:**

1. **GPTBot ≠ OAI-SearchBot ≠ ChatGPT-User.** A SaaS can allow OpenAI search/index visibility while opting out of training. Be explicit.
2. **Google-Extended is not a Search opt-out.** Blocking it does NOT remove you from Google Search and is not a Search ranking signal. It controls documented Gemini / Vertex AI uses, so label it separately from Googlebot.
3. **Applebot-Extended is training-only too.** Same logic.
4. **Perplexity-User is on-demand and ignores robots.txt by Perplexity's stated policy.** Block at WAF/CDN if you must (Cloudflare AI Audit can do this); robots.txt alone won't stop it.

---

## §2 — Recommended robots.txt for a SaaS marketing/docs site

Goal: visibility in AI-search products (where customers find you) + opt out of training (protects unique content).

```
# Allow search-grade crawlers — these drive citations + organic traffic
User-agent: Googlebot
Allow: /

User-agent: bingbot
Allow: /

User-agent: Applebot
Allow: /

User-agent: OAI-SearchBot
Allow: /

User-agent: ChatGPT-User
Allow: /

# Optional: only matters if buying ChatGPT ads
User-agent: OAI-AdsBot
Allow: /

User-agent: Claude-SearchBot
Allow: /

User-agent: Claude-User
Allow: /

User-agent: PerplexityBot
Allow: /

User-agent: Meta-ExternalFetcher
Allow: /

User-agent: MistralAI-User
Allow: /

# Opt out of training / non-Search AI uses where provider documentation supports it
User-agent: GPTBot
Disallow: /

User-agent: ClaudeBot
Disallow: /

User-agent: anthropic-ai
Disallow: /

User-agent: Google-Extended
Disallow: /

User-agent: Applebot-Extended
Disallow: /

User-agent: Meta-ExternalAgent
Disallow: /

User-agent: CCBot
Disallow: /

User-agent: Bytespider
Disallow: /

# Always: protect admin / auth surfaces
User-agent: *
Disallow: /admin
Disallow: /api
Disallow: /login
Disallow: /account

Sitemap: https://www.example.com/sitemap.xml
```

**Variants:**
- **Open-source / docs project:** allow all training bots (your content is public anyway, training amplifies your reach).
- **Premium content / proprietary research:** block all training bots, allow search/on-demand.
- **Commercial template / marketing:** the recommended config above.

---

## §3 — llms.txt (the proposal)

`llms.txt` (https://llmstxt.org, Sep 2024) is a Markdown file at `/llms.txt` that lists canonical URLs and high-priority pages for LLMs. Treat it as a publishing convention, not a Google ranking or AI-citation requirement. If a provider later confirms support, source-log that provider-specific behavior before upgrading the recommendation.

**Worth publishing for:**
- Documentation sites (low-cost, future-proofing, signals intent).
- Product reference pages where you want a particular canonical surface to be the LLM-cited one.

**Format:**
```markdown
# Acme SaaS

> A workflow automation platform for distributed teams.

## Documentation

- [Quickstart](https://docs.acme.com/quickstart): set up in 5 minutes
- [API reference](https://docs.acme.com/api): REST & GraphQL endpoints
- [SDK guides](https://docs.acme.com/sdks): TypeScript, Python, Go, Ruby

## Pricing & plans

- [Pricing](https://acme.com/pricing): Free, Team, Enterprise tiers

## Optional

- [Changelog](https://acme.com/changelog): release history
- [Status](https://status.acme.com): uptime
```

A companion `/llms-full.txt` may inline the actual content of canonical pages (Markdown). Useful when your site is JS-heavy and HTML-only LLMs would otherwise miss the content.

**Gotchas:**
- LLMs do NOT respect this for paywalled content; if you publish a URL here, assume it's training fodder.
- Stale URLs in `llms.txt` are worse than no `llms.txt`. Keep it CI-validated.
- Do not include URLs you `Disallow` in robots.txt — that's contradictory.

Validate with `scripts/llms-txt-validator.ts` after every site change: it fetches `/llms.txt`, follows every linked URL, confirms no robots contradiction, and checks basic structure. Manual review is still required for whether the listed pages are the right canonical surfaces.

---

## §4 — security.txt (RFC 9116)

Adjacent trust signal. Place at `/.well-known/security.txt`:

```
Contact: mailto:security@example.com
Expires: 2027-01-01T00:00:00Z
Preferred-Languages: en
Canonical: https://www.example.com/.well-known/security.txt
Policy: https://www.example.com/security/policy
Hiring: https://www.example.com/careers
```

Increases trust signals for both crawlers and security-conscious visitors. Mandatory for fintech / healthtech SaaS.

---

## §5 — IndexNow

Bing, Yandex, Seznam, Naver, Yep participate. Google does NOT (still). Use IndexNow to push fresh URLs to Bing/Copilot for SaaS targeting enterprise IT (Bing's hidden-share-of-voice play).

Cloudflare's auto-IndexNow (free, in dashboard) is the easiest setup. Otherwise:

```bash
curl 'https://www.bing.com/indexnow' \
  -H 'Content-Type: application/json' \
  --data '{
    "host": "www.example.com",
    "key": "<32-char hex key, also published at /<key>.txt>",
    "keyLocation": "https://www.example.com/<key>.txt",
    "urlList": ["https://www.example.com/blog/new-post"]
  }'
```

Worth wiring for: SaaS with frequent content velocity (blog, changelog, status, jobs). Skip if static.

---

## §6 — Cloudflare AI Audit (and equivalents)

Cloudflare AI Audit (GA mid-2025) provides per-bot request volumes and one-click block/allow rules. AWS WAF and Akamai have analogous offerings. Use these to:
- Verify your robots.txt is actually being honored (it's a request, not a contract).
- Detect impostor bots (UA spoofing as Googlebot).
- Rate-limit aggressive bots (Bytespider, Perplexity-User).
- Build a per-bot-citation dashboard (with share-of-LLM-voice data — see `GEO-MEASUREMENT.md`).

---

## §7 — Decision rules

Use these as defaults; override with explicit business reasoning:

| Question | Default |
|---|---|
| Should we block training bots? | Yes for proprietary marketing/research; no for docs/open-source |
| Should we block search-index bots? | Never |
| Should we block on-demand browsers (ChatGPT-User, Claude-User, Perplexity-User)? | Never — they're user-initiated traffic |
| Should we publish llms.txt? | Yes for docs sites; optional for marketing |
| Should we publish security.txt? | Always |
| Should we wire IndexNow? | Yes if Bing matters (B2B enterprise) or content velocity is high |
| Should we use Cloudflare AI Audit? | Yes if on Cloudflare; offers visibility regardless of policy |

---

## §8 — Script: `ai-bot-policy-check.ts`

Audits a site's robots.txt against the bot matrix above, flagging:
- Common confusion: `GPTBot` blocked but `OAI-SearchBot` also blocked (probably unintended)
- `Google-Extended Disallow: /` AND a comment claiming "we still want Search" (no effect on Search, but flag the contradiction)
- Missing entries for currently-active bots
- Stale entries for deprecated UAs (`anthropic-ai`)

**Output:** `analyses/ai-bot-policy.json`

```jsonc
{
  "generated": "ISO-8601",
  "robots_txt_url": "string",
  "robots_txt_status": 200,
  "rules": [
    { "user_agent": "GPTBot", "disallow": ["/"], "allow": [], "matched": true }
  ],
  "bot_status": [
    { "bot": "GPTBot",          "purpose": "training",  "policy": "BLOCKED",  "intended": true,  "concern": null },
    { "bot": "OAI-SearchBot",   "purpose": "search",    "policy": "BLOCKED",  "intended": false, "concern": "blocked_search_with_training" },
    { "bot": "ChatGPT-User",    "purpose": "on-demand", "policy": "ALLOWED",  "intended": true,  "concern": null }
  ],
  "issues": [
    { "level": "WARN", "code": "BLOCKED_SEARCH_BOT_WITH_TRAINING_BLOCK",
      "message": "OAI-SearchBot is blocked alongside GPTBot. If you intended to opt out of training only, allow OAI-SearchBot to retain OpenAI search visibility." }
  ]
}
```

---

## §9 — Script: `llms-txt-validator.ts`

Fetches `/llms.txt` (and `/llms-full.txt` if present), validates the structure, and pings each linked URL.

**Output:** `analyses/llms-txt.json`

```jsonc
{
  "generated": "ISO-8601",
  "llms_txt_present": true,
  "llms_txt_url": "https://www.example.com/llms.txt",
  "title": "Acme SaaS",
  "description": "...",
  "sections": [
    { "name": "Documentation", "links": [{ "url": "...", "title": "...", "status": 200 }] }
  ],
  "issues": [
    { "level": "FAIL", "code": "STALE_URL", "message": "/quickstart returned 404 — remove or update" },
    { "level": "WARN", "code": "ROBOTS_CONFLICT", "message": "/api is listed in llms.txt but Disallow'd in robots.txt" }
  ]
}
```

---

## §10 — Anti-patterns specific to AI bots

1. **Don't User-Agent-sniff to serve different content to bots.** Cloaking is a manual-action vector and detectable.
2. **Don't rate-limit Googlebot.** Use Search Console's crawl-rate setting.
3. **Don't add `noindex` to docs hoping LLMs will skip them — `noindex` is a Search instruction, not a training instruction.** Use robots.txt for the bot you actually mean.
4. **Don't trust `User-Agent` strings in your logs without verifying via reverse DNS.** Real Googlebot reverse-resolves to `*.googlebot.com`. Spoofers don't.
5. **Don't publish `llms.txt` and forget it.** It rots faster than `sitemap.xml`. Validate in CI.

---

## §11 — Maintenance contract

- Re-run `ai-bot-policy-check.ts` whenever robots.txt, WAF rules, CDN bot rules, or AI crawler guidance changes.
- Re-run `llms-txt-validator.ts` weekly or on every content release if the target publishes one.
- Review the bot matrix here quarterly — providers add new UAs constantly. Document any change in `seo-changelog.md`.
