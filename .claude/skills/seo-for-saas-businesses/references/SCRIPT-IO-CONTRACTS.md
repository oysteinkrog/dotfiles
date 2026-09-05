# SCRIPT-IO-CONTRACTS — Stable JSON shapes per script

> **Why this exists:** an agent should know what fields to read from each script's output without opening the source. These shapes are stable; if you need to break one, bump a `version` field. Field names are `snake_case` for consistency with most analytics tooling.

## TOC

crawl · validate-schema · cwv-check · crux-collect · cwv-by-component · gsc-extract · striking-distance · redirect-chain-audit · hreflang-validator · og-image-audit · entity-consistency-check · ai-crawler-view · ai-bot-policy-check · llms-txt-validator · verify-prod · sitemap-audit · internal-links · serp-snapshot · `issues[]` conventions · adding a new script

Most scripts:
- accept `--output <path>` to redirect to the documented path
- log progress to stdout and write deterministic artifacts under `analyses/`
- expose exit codes in the usage header at the top of the script

Do not assume every script has the same flags. `--ci true` exists only on scripts that document it. Some scripts emit Markdown only, some emit JSON plus Markdown, and Lighthouse CI emits its own filesystem report directory. When in doubt, trust the script's usage header over this reference and update this contract if the script changes.

---

## crawl.ts → `analyses/crawl/_index.json` and per-URL `<hash>.json`

```jsonc
{
  "generated": "ISO-8601",
  "results": [
    {
      "url": "string",                 // requested URL
      "final_url": "string",           // after redirects
      "template": "string?",
      "intent": "string?",
      "status": 200,
      "redirect_chain": ["url", ...],  // includes original
      "headers": { "content-type": "...", ... },
      "raw":      { "title": "...", "description": "...", "canonical": "...",
                    "robots": "...", "h1": "...",
                    "og": { "title": "...", "description": "...",
                            "image": "...", "type": "..." },
                    "twitter_card": "...",
                    "json_ld": [{ "ok": true, "parsed": { /* ... */ } }, ...],
                    "json_ld_count": 0,
                    "internal_link_count": 0,
                    "html_path": "analyses/crawl/<hash>.raw.html" },
      "rendered": { /* same shape as raw, plus title_via_browser, html_path */ },
      "diff":     { "title": { "raw": "...", "rendered": "..." }, ... },
      "crawled_at": "ISO-8601"
    }
  ]
}
```

**Use cases:** `diff` is the SSR-vs-CSR diff (Axiom 4). Empty `diff` ⇒ raw = rendered ⇒ HTML-only crawlers see the same content. Non-empty `diff` ⇒ investigate.

---

## validate-schema.ts → `analyses/schema-validation.json`

```jsonc
{
  "generated": "ISO-8601",
  "fail_count": 0,
  "warn_count": 0,
  "results": [
    {
      "url": "string",
      "blocks": [{ "index": 0, "type": "Organization|Product|...", "ok": true }],
      "issues": [{ "level": "FAIL|WARN", "code": "...", "message": "..." }]
    }
  ]
}
```

---

## cwv-check.ts → `analyses/lighthouse/`

```jsonc
{
  "generated": "ISO-8601",
  "form_factor": "mobile|desktop",
  "results": [
    {
      "url": "string",
      "lab": { "lcp_ms": 0, "cls": 0, "tbt_ms": 0, "ttfb_ms": 0, "fcp_ms": 0,
               "performance_score_raw_0_1": 0, "performance_score_0_1000": 0 },
      "issues": [{ "level": "FAIL|WARN", "code": "...", "message": "..." }]
    }
  ]
}
```

---

## crux-collect.ts → `analyses/crux.json`

```jsonc
{
  "generated": "ISO-8601",
  "results": [
    {
      "url_or_origin": "string",
      "scope": "url|origin",
      "form_factor": "mobile|desktop|null",
      "metrics": {
        "lcp_p75_ms": 0, "inp_p75_ms": 0, "cls_p75": 0, "ttfb_p75_ms": 0
      },
      "buckets": { /* CrUX histograms */ },
      "issues": [{ "level": "FAIL|WARN", "code": "...", "message": "..." }]
    }
  ]
}
```

`scope: origin` means CrUX returned origin-level data because URL-level was unavailable — typical for low-traffic SaaS pages. Don't recommend page-level fixes from origin-level numbers without flagging the imprecision.

---

## cwv-by-component.ts → `analyses/cwv-attribution/<slug>.json`

```jsonc
{
  "url": "string",
  "device": "mobile|desktop",
  "interactions": [
    { "label": "string", "selector": "string", "duration": 0,
      "target_outer_html": "string", "timestamp": 0 }
  ],
  "long_tasks": [{ "duration_ms": 0, "name": "string" }],
  "loaf": [{ "duration_ms": 0, "blocking_duration_ms": 0, "scripts": [...] }],
  "top_components": [{ "label": "string", "p95_duration_ms": 0, "n": 0 }]
}
```

---

## gsc-extract.ts → `analyses/gsc/`

```jsonc
{
  "generated": "ISO-8601",
  "property": "string",
  "date_range": { "start": "YYYY-MM-DD", "end": "YYYY-MM-DD" },
  "rows": [
    { "page": "url", "query": "string", "country": "string?", "device": "string?",
      "clicks": 0, "impressions": 0, "ctr": 0.0, "position": 0.0 }
  ],
  "summary": { "total_clicks": 0, "total_impressions": 0, "weighted_avg_position": 0.0 }
}
```

---

## striking-distance.ts → `analyses/striking-distance.json`

```jsonc
{
  "generated": "ISO-8601",
  "buckets": {
    "rank_2_3": [{ "url": "...", "query": "...", "clicks": 0, "impressions": 0,
                   "position": 0.0, "expected_ctr": 0.0, "potential_clicks_lift": 0,
                   "recommendation": "..." }, ...],
    "rank_4_10": [...],
    "rank_11_20": [...],
    "rank_21_30": [...],
    "rank_31_50": [...]
  }
}
```

`expected_ctr` uses the canonical CTR curve in `STRIKING-DISTANCE-PLAYBOOK.md`. `recommendation` is the playbook bucket name. Sort each bucket by `potential_clicks_lift` descending.

---

## redirect-chain-audit.ts → `analyses/redirect-chains.json`

```jsonc
{
  "generated": "ISO-8601",
  "results": [
    {
      "start_url": "string",
      "chain": [{ "url": "...", "status": 301, "method": "header|meta|js" }],
      "final_url": "string",
      "final_status": 200,
      "hops": 0,
      "issues": [{ "level": "FAIL|WARN", "code": "...", "message": "..." }]
    }
  ]
}
```

---

## hreflang-validator.ts → `analyses/hreflang.json`

```jsonc
{
  "generated": "ISO-8601",
  "fail_count": 0,
  "warn_count": 0,
  "reports": [
    {
      "url": "string",
      "alternates": [{ "hreflang": "en-US", "href": "url", "source": "html|header" }],
      "canonical": "string?",
      "issues": [{ "level": "FAIL|WARN", "code": "BAD_LANG|NO_RECIPROCAL|...", "message": "..." }],
      "redirect_traps": [{ "lang": "...", "geo": "...", "redirected_to": "..." }]
    }
  ]
}
```

---

## og-image-audit.ts → `analyses/og-images.json`

```jsonc
{
  "generated": "ISO-8601",
  "fail_count": 0,
  "warn_count": 0,
  "results": [
    {
      "url": "string",
      "og_image": "url?", "og_image_w": 1200, "og_image_h": 630,
      "twitter_card": "summary_large_image?",
      "twitter_image": "url?", "twitter_image_alt": "string?",
      "head_status": 200, "content_type": "image/png", "content_length": 0,
      "actual_w": 1200, "actual_h": 630,
      "issues": [{ "level": "FAIL|WARN", "code": "...", "message": "..." }]
    }
  ]
}
```

---

## entity-consistency-check.ts → `analyses/entity-consistency.json`

```jsonc
{
  "generated": "ISO-8601",
  "homepage": "url",
  "organization": {
    "name": "string?", "url": "string?", "logo": "string?",
    "logo_check": { "status": 200, "content_type": "image/...", "bytes": 0, "ok": true },
    "sameAs": [
      { "url": "...", "platform": "github|linkedin|twitter|...",
        "status": 200, "back_link": "string?", "back_matches": true,
        "note": "string" }
    ]
  },
  "surfaces": { "og_site_name": "...", "og_url": "...", "canonical": "...",
                "footer_mentions_brand": true },
  "also": [{ "url": "...", "ok": true, "note": "..." }],
  "issues": [{ "level": "FAIL|WARN|INFO", "code": "...", "message": "..." }],
  "fail_count": 0, "warn_count": 0
}
```

---

## ai-crawler-view.ts → `analyses/ai-crawler/_report.json` and per-bot `<slug>__<bot>.html`

```jsonc
{
  "generated": "ISO-8601",
  "report": [
    {
      "url": "string",
      "bot": "GPTBot|OAI-SearchBot|ChatGPT-User|ClaudeBot|Claude-SearchBot|Claude-User|anthropic-ai|PerplexityBot|Perplexity-User|Googlebot",
      "status": 200,
      "path": "analyses/ai-crawler/<slug>__<bot>.html",
      "has_title": true, "has_meta_description": true,
      "h1_count": 0, "h2_count": 0, "json_ld_count": 0,
      "text_length": 0,
      "contains_loading": false,
      "contains_javascript_required": false,
      "error": "string?"
    }
  ]
}
```

`text_length` is the visible text (HTML stripped) length. < 500 ≈ likely empty / SSR broken.

---

## ai-bot-policy-check.ts → `analyses/ai-bot-policy.json`

```jsonc
{
  "generated": "ISO-8601",
  "robots_txt_url": "string",
  "robots_txt_status": 200,
  "raw_length": 0,
  "bot_status": [
    { "bot": "GPTBot", "provider": "OpenAI", "purpose": "training",
      "policy": "BLOCKED|ALLOWED|UNSPECIFIED", "matched_group": "gptbot|null",
      "notes": "string?" }
  ],
  "issues": [{ "level": "FAIL|WARN|INFO", "code": "...", "message": "..." }],
  "fail_count": 0,
  "warn_count": 0
}
```

Use this before changing robots.txt, WAF bot rules, or AI crawler policies. WARN is usually a business decision; FAIL means the robots file itself could not be fetched.

---

## llms-txt-validator.ts → `analyses/llms-txt.json`

```jsonc
{
  "generated": "ISO-8601",
  "site": "https://www.example.com",
  "llms_txt_present": true,
  "llms_txt_url": "https://www.example.com/llms.txt",
  "llms_full_present": false,
  "llms_full_status": 404,
  "title": "string|null",
  "description": "string|null",
  "sections": [
    { "name": "Documentation",
      "links": [{ "title": "Quickstart", "url": "https://...", "status": 200,
                  "ok": true, "same_origin": true }] }
  ],
  "link_total": 0,
  "link_ok": 0,
  "issues": [{ "level": "FAIL|WARN|INFO", "code": "...", "message": "..." }],
  "fail_count": 0,
  "warn_count": 0
}
```

Absence of `llms.txt` is INFO, not FAIL. Broken listed URLs are FAIL.

---

## verify-prod.ts → `analyses/post-deploy-verification.md`

Markdown only by default; pass `--json` to also emit `.json`. Per-URL pass/fail/flag counters with line-item issues.

---

## sitemap-audit.ts → stdout, exit 0/1

Currently logs issues to stdout. To capture, pipe to a file: `bun run scripts/sitemap-audit.ts --sitemap https://... > analyses/sitemap-audit.txt`.

---

## internal-links.ts → `analyses/internal-links.json`

```jsonc
{
  "generated": "ISO-8601",
  "results": [
    {
      "page": "url",
      "outbound_internal": [{ "to": "url", "anchor": "string", "rel": "string?" }],
      "outbound_external": [{ "to": "url", "anchor": "string", "rel": "string?" }],
      "inbound_count": 0
    }
  ]
}
```

---

## serp-snapshot.ts → `analyses/serps/<query-slug>.json` and `.html`

```jsonc
{
  "query": "string",
  "captured_at": "ISO-8601",
  "country": "us|gb|...",
  "device": "mobile|desktop",
  "results": [{ "rank": 1, "title": "...", "url": "...", "snippet": "..." }],
  "features": { "ai_overview_present": true, "people_also_ask": [...],
                "knowledge_panel": false, "video_carousel": false }
}
```

Heuristic detection — confirm by looking at the saved HTML if a feature claim is decision-bearing.

---

## Conventions for ALL `issues[]` arrays

- `level`: `FAIL` (must fix), `WARN` (should investigate), `INFO` (note)
- `code`: stable identifier in SCREAMING_SNAKE_CASE; codes do not change once shipped
- `message`: human-readable, may contain URLs and offending values

Agents reading these can filter by `level === "FAIL"` for blocking issues, group by `code` for triage.

---

## Adding a new script

1. Pick output paths under `analyses/` per `ANALYSES-LAYOUT.md`.
2. Add a contract section here.
3. Use `issues[]` shape if you have validation findings.
4. Always emit JSON; humans read the `.md`, agents read the `.json`.
