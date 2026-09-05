# VERIFICATION-FIRST

Search policy, ranking systems, and SEO surfaces drift faster than this skill is updated. Any volatile claim must be checked against a live primary source before it ships into a recommendation.

## Volatile vs evergreen

| Evergreen (use this skill + the guide) | Volatile (verify live) |
|---|---|
| The kernel axioms | Specific CWV thresholds |
| The audit-item format | Specific ranking signal weights |
| The phase methodology | Whether a specific schema type is currently eligible for rich results |
| Cognitive operators | Whether a specific Google product (FAQ rich results, HowTo, Sitelinks Searchbox) is supported |
| Anti-pattern principles | Current spam-policy enforcement details |
| Stack adapter patterns (Next.js, Astro, Remix) | Current Next.js metadata API surface and signatures |
| AI visibility principle (initial-HTML matters for AI bots) | Specific AI Overview / AI Mode citation behaviour |
| Programmatic gates structure | Current `robots.txt` syntax for specific bots |
| Evidence-led SEO reasoning | Exact rank-delta, CTR-uplift, citation-overlap, or "X times more likely" figures |

## Mandatory verification triggers

Whenever a recommendation depends on one of these, verify against a primary source before publishing:

| Trigger | Primary source |
|---|---|
| CWV threshold or page-experience claim | https://web.dev/articles/inp, web.dev / Search Central |
| Helpful Content / scaled content / site reputation abuse / expired domain / back-button hijacking | https://developers.google.com/search/blog, https://developers.google.com/search/docs/essentials/spam-policies |
| Specific structured-data type eligibility | https://developers.google.com/search/docs/appearance/structured-data/<type> |
| Search Console feature, export, BigQuery | https://developers.google.com/search/docs/monitor-debug + Search Console release notes |
| AI Overview / AI Mode behaviour | Google Search Central blog posts dated within last 6 months + reputable third-party studies |
| Next.js metadata / sitemap / robots / `next/og` API | https://nextjs.org/docs/app/api-reference for the version in `package.json` |
| Vercel Cache Components / Edge Config behaviour | https://vercel.com/docs (subject to platform changes) |
| FTC endorsement / disclosure rules | https://www.ftc.gov/business-guidance/advertising-marketing/endorsements-influencers-reviews |
| Robots.txt specification edge cases | https://developers.google.com/search/docs/crawling-indexing/robots/robots_txt |

## Verification protocol

1. Open the primary source. Read the section that supports the claim.
2. Capture: source URL, retrieval date, the specific quote / fact supporting the claim.
3. Append to `analyses/source-log.md`:

```
[2026-04-30] INP threshold for `good`
- Source: https://web.dev/articles/inp
- Retrieved: 2026-04-30
- Quote: "INP measures the latency of all interactions a user has made with the page, and reports a single value… A page meets the recommended target if 75% of its interactions have an INP of 200 milliseconds or less."
- Used in: AUDIT-0123, AUDIT-0145
```

4. If the live source contradicts this skill or the guide, log the discrepancy in [GUIDE-RECONCILIATION](GUIDE-RECONCILIATION.md) under the relevant section. Update the recommendation. Do not silently downgrade or ignore.

## What "primary" means

| Acceptable as primary | Not primary |
|---|---|
| Google Search Central docs / blog | SEO blogs summarizing Google docs |
| web.dev (Google) | Vendor blog implementing CWV |
| schema.org | Schema.app blog summarizing schema.org |
| Next.js docs at the version in use | Medium articles on Next.js |
| FTC / EU regulator pages | News articles summarizing |
| Search Console / GA4 / Bing Webmaster docs | Agency case studies |
| Known reputable studies with methodology disclosed | Anecdote on social media |

A "study" is acceptable as evidence (`likely` confidence) if methodology, sample size, and dates are disclosed and at least one peer source corroborates the direction.

## Confidence labels

Pair every recommendation with a confidence label per [EVIDENCE-LABELS](EVIDENCE-LABELS.md). When the underlying evidence is `likely` or `hypothesis`, the recommendation inherits that label.

## Numerical volatility gate

Precise numbers are the easiest way for a good SEO skill to become stale. Before shipping any recommendation that uses a number like "0.8 positions", "2-4 positions", "14 % overlap", "35 % CTR uplift", or "4x more likely":

1. Log the source, methodology, sample size, query set, geography/device scope, retrieval date, and recheck-by in `analyses/source-log.md`.
2. Label the number `confirmed` only if it comes from a primary source or the target property's own controlled measurement. Most third-party SEO studies are `likely` at best.
3. If the method is missing or older than its recheck-by date, keep the qualitative operator and downgrade the number to `hypothesis`.
4. Never promote third-party correlation into a deterministic ranking rule. "CWV contributes to success" is a safer claim than "INP above 500 ms costs four positions" unless the latter is source-logged for this context.

## Quick-check commands

```bash
# Pull the current Next.js version in the target project
jq -r '.dependencies.next // .devDependencies.next' "$REPO/package.json"

# Pull the current Google search docs page (read-only)
curl -s "https://developers.google.com/search/docs/essentials/spam-policies" \
  | grep -oE '<title>.*</title>' | head -1

# Pull current INP threshold
curl -s "https://web.dev/articles/inp" \
  | grep -oE '200 milliseconds|200 ms'

# Confirm current Google spam-policy treatment of browser-history manipulation
curl -s "https://developers.google.com/search/docs/essentials/spam-policies" \
  | grep -oE 'Back button hijacking|Malicious practices'
```

These are smoke tests to confirm the source is reachable and current. Do not parse policy from grep output; read the page.

## When primary sources disagree with the guide

Current evidence wins. The discrepancy goes in [GUIDE-RECONCILIATION](GUIDE-RECONCILIATION.md) with retrieval date and source URL. Do not silently override the guide without the audit trail.
