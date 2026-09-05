# EVIDENCE-LABELS

Every recommendation, audit item, and claim carries a confidence + evidence label. The reader should be able to see at a glance how much weight to give a finding.

## Score convention

All skill-owned scores use the same scale:

| Score | Meaning |
|---:|---|
| `0` | worst possible outcome / no value / must reject |
| `250` | weak |
| `500` | acceptable but not strong |
| `750` | strong |
| `1000` | best possible outcome / ship-ready |

Use `score_0_1000` in machine-readable artifacts. If a third-party tool has a native score, preserve it as `raw_<tool>_score` and add the normalized score beside it. Examples: Lighthouse raw API `0.9` → `score_0_1000: 900`; Lighthouse UI `100` → `score_0_1000: 1000`.

## Confidence (how sure are we?)

| Label | Use when |
|---|---|
| `confirmed` | Issue or fact is directly visible in HTML, crawl output, GSC, analytics, screenshots, or logs; or the claim is documented in a Google primary source. |
| `likely` | Strong evidence points to it but one source is missing, stale, or single-vendor. |
| `hypothesis` | Plausible but not verified. Needs measurement, crawl, or test before publishing. |

## Evidence type (what kind of source?)

| Label | Use it for |
|---|---|
| `official` | Search-engine documentation, platform docs, standards, laws, policies, or government sources. |
| `expert-reviewed` | Reviewed by a named person with relevant credentials or deep practical experience. |
| `first-hand` | Based on actual product use, customer evidence, tests, experiments, support logs, or original research. |
| `market-observed` | Based on SERP analysis, Search Console data, competitor data, analytics, or trend data. |
| `hypothesis` | Plausible but not verified. |

## Severity (how urgent?)

| Label | Use when |
|---|---|
| `critical` | Indexing blocked, manual action pending, primary content not rendered, host/protocol broken, staging or PII leaking publicly, manual action received |
| `high` | Template-level issue affecting many high-value pages or commercial paths; INP > 500 ms p75 on commercial templates; canonical mismatch on top traffic pages |
| `medium` | Meaningful improvement opportunity; the page still works |
| `low` | Cleanup, polish, monitoring, documentation work |

Easy fixes are not automatically critical. A 30-minute fix to a footer link is `low`.

## Combining

Audit item example:

```
AUDIT-0145
issue:       Schema injected via useEffect; raw HTML contains no JSON-LD
proof:       analyses/crawl/pricing.raw.html shows 0 LD blocks; rendered shows 2
consequence: AI bots cannot see Offer schema; possible eligibility loss for product rich results
remediation: Move JSON-LD to Server Component
confidence:  confirmed
evidence:    first-hand (crawl output)
severity:    high
effort:      hours
owner:       engineering
```

## Inheritance

When a recommendation is downstream of evidence labelled `likely` or `hypothesis`, the recommendation cannot be more confident than its source. Mark accordingly. Do not promote `hypothesis` to `confirmed` without verification.

## Anti-patterns

- Marking everything `confirmed` because it sounds better.
- Marking obvious facts as `hypothesis` to dodge accountability.
- Using `critical` for easy fixes to escalate prioritization.
- Citing "industry consensus" as `official`.
- Skipping the source citation for `confirmed` items.

## Visible to user

Every deliverable (briefs, audit items, decision cards, PRs) shows the labels. Users can filter, sort, and decide which findings to ship and which to verify further.
