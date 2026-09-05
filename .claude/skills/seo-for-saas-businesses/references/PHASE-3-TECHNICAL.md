# PHASE 3 — TECHNICAL SEO AUDIT

Goal: a prioritized issue list — Issue / Proof / Consequence / Remediation / Confidence / Severity / Effort / Owner / Phase 6 PR — with severity earned, not assumed.

## Inputs

- `analyses/baseline-summary.md` and `analyses/representative-urls.json` from Phase 1.
- Production crawl output (`scripts/crawl.ts`) — raw HTML, rendered HTML, status, redirect chain, canonical, schema, links per URL.
- GSC coverage, sitemap status, manual actions, enhancement reports.
- CrUX field data; Lighthouse lab data.
- Server logs (T3+).

## Audit areas (parallelize via `subagents/audit-area.md`)

| Area | Subagent param | Primary checks |
|---|---|---|
| crawlability | `area=crawl` | robots.txt validity, sitemap presence + content, status-code health, redirect chains, redirect loops, host/protocol canonicalization, Vary/Cache headers, response weight |
| indexability | `area=index` | noindex audit, soft-404 hunt, duplicate clusters, parameter handling, `crawled, currently not indexed`, `discovered, currently not indexed` |
| rendering | `area=render` | raw vs rendered HTML diff, RSC streaming completeness, hydration mismatches, JS-only content, click-only links, route-change metadata |
| schema | `area=schema` | per-template structured-data validity vs schema.org, agreement with visible content, current Google support per type, enhancement-error trends |
| internal-links | `area=links` | orphans, redirected internal links, anchor distribution, link concentration, footer-link sanity |
| performance | `area=perf` | INP/LCP/CLS by template (CrUX p75 + Lighthouse), per-component INP attribution, font/image/main-thread offenders |
| logs | `area=logs` (T3+) | verified-bot fetch volume, 4xx/5xx for crawlers, asset-fetch failures, parameter-explosion crawl traps |
| infrastructure | `area=infra` | CDN cache rules vs metadata, WAF/bot protection vs verified crawlers, edge-redirect agreement, staging leak check |
| metadata | `area=meta` | per-template title pattern, description pattern, canonical, OG/Twitter, fallback values, drift from page data |
| accessibility | `area=a11y` | WCAG basics (contrast, labels, focus, semantic HTML, mobile readability) — defects are conversion + procurement risks |
| international | `area=intl` | `hreflang` reciprocity, locale routing, currency/availability/legal localization |

Each subagent emits items to `analyses/audit-issues.json` (machine-readable) and a per-area human report under `analyses/audit/<area>.md`.

## Issue format

```
{
  "id": "AUDIT-0123",
  "area": "render",
  "issue": "Pricing page renders plan list only after client-side hydration; raw HTML contains skeleton.",
  "proof": "raw HTML at analyses/crawl/pricing.raw.html line 412 vs rendered analyses/crawl/pricing.rendered.html line 412",
  "consequence": "Plan names, prices, and offer schema invisible to AI crawlers; potential GSC 'duplicate without canonical' for variant URLs.",
  "remediation": "Move plan fetch to Server Component; render plan list and JSON-LD Offer in initial HTML.",
  "confidence": "confirmed",
  "severity": "high",
  "effort": "hours",
  "owner": "engineering",
  "phase6_pr": "seo/pricing-rsc",
  "expected_impact": "+ AI Overview citation eligibility, fix offer schema, possible CTR improvement",
  "tracking_plan": "GSC enhancement report; AI Overview manual log; CrUX TTFB delta",
  "rollback_path": "Revert PR; pricing page reverts to current shape",
  "recheck_by": "2026-05-21"
}
```

## Severity rules

| Severity | Use only when |
|---|---|
| critical | Indexing blocked, manual action pending, primary content not rendered, host/protocol canonical broken, staging or PII leaking publicly |
| high | Template-level issue affecting many high-value pages or commercial paths; INP > 500 ms p75 on commercial templates; canonical mismatch on top traffic pages |
| medium | Meaningful improvement opportunity; the page still works; not blocking commerce or conversion |
| low | Cleanup, polish, monitoring, documentation work |

Easy fixes are not automatically critical. A 30-minute fix to a footer link is `low`.

## Confidence rules

| Confidence | Use when |
|---|---|
| confirmed | Directly visible in raw HTML, crawl, GSC, analytics, screenshot, or log |
| likely | Strong evidence, one source missing or stale |
| hypothesis | Plausible; needs measurement, crawl, or test before publishing as fact |

Items with `hypothesis` go to `analyses/unknowns.md` with a verification path.

## Prioritization rule

The action plan is sorted by `priority_score_0_1000` (`0` worst, `1000` best). Compute it from severity, expected impact, and effort, with `confidence` as a gate: `hypothesis` items can enter the unknowns queue but do not ship as fixes until verified.

## Common findings on SaaS sites

- Marketing pages importing dashboard-tier JS via shared component (chart lib, marketing-CRM widget, mock-data fixtures).
- `app/(app)/layout.tsx` mistakenly inheriting `noindex` from parent — kills app login routes (intended) but also hits a public route in a sibling.
- `metadataBase` missing in root layout → broken OG image previews on every page.
- Pricing JSON-LD offers list disagrees with rendered prices because schema imports a snapshot the design system replaced.
- Subdomain canonicalization fights between `www.example.com`, `example.com`, and a Vercel preview URL escaping into the index.
- Status / changelog pages never indexed because they're noindex by template default and never specifically opted in.
- `robots.txt` blocks `/api/` (correct) but also blocks an `/api/og` route used for OG image generation, breaking social previews.
- Self-canonical to lower-cased URL while internal links use mixed case — Google clusters but picks the wrong canonical.
- Consent banner mounts before LCP image; CLS regression on first paint.
- Search results page indexable, generating thin pages.
- Auto-redirect to user's locale on `/` traps Googlebot in `/en/` and never lets it reach `/de/`.

## Output

- `analyses/audit-issues.json`
- `analyses/audit-summary.md`
- `analyses/representative-urls.json` refined (any new URLs surfaced by area work)
- A flag list of items to escalate to [HIGH-RISK-GATE](HIGH-RISK-GATE.md), [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md), or [TRAFFIC-DROP-PLAYBOOK](TRAFFIC-DROP-PLAYBOOK.md) if scoped beyond ordinary fixes.
