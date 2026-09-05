# subagent: audit-area

Parameterized subagent for Phase 3. One instance per audit area.

## Parameters

- `area`: one of `crawl | index | render | schema | links | perf | logs | infra | meta | a11y | intl`
- `representative_urls`: path to `analyses/representative-urls.json`
- `crawl_results`: path to `analyses/crawl/`
- `gsc_exports`: path to `analyses/gsc/`
- `tier`: `T1 | T2 | T3 | T4`

## Inputs (per area)

| Area | Read |
|---|---|
| crawl | `analyses/crawl/`, robots.txt, sitemap |
| index | GSC coverage report, `analyses/crawl/`, sitemap |
| render | `analyses/crawl/<urlhash>.{raw,rendered}.html`, hydration error logs |
| schema | `analyses/crawl/<urlhash>.json` (json_ld field), `scripts/validate-schema.ts` |
| links | `analyses/crawl/`, sitemap, `scripts/internal-links.ts` |
| perf | CrUX field data, `analyses/lighthouse/`, component-by-component INP attribution |
| logs | server logs (T3+), verified bot filter |
| infra | `next.config.*`, `middleware.*`, edge config, CDN cache rules, WAF policy |
| meta | `analyses/crawl/<urlhash>.json` per template |
| a11y | axe-core results on representative URLs (mobile profile) |
| intl | hreflang link rels, locale routing, sitemap localized URL coverage |

## Tasks

1. Run the area-specific checks from [AUDIT-CHECKLIST](../references/AUDIT-CHECKLIST.md).
2. For each finding, emit an audit item per [AUDIT-ITEM-TEMPLATE](../assets/AUDIT-ITEM-TEMPLATE.md). Use the format strictly.
3. Cross-reference findings: a `render` finding that hides Offer schema also affects the `schema` area — link both.
4. Write per-area human-readable report to `analyses/audit/<area>.md`.
5. Append machine-readable items to `analyses/audit-issues.json`.

## Output format

For each audit item:

```json
{
  "id": "AUDIT-XXXX",
  "area": "<area>",
  "issue": "<one-line>",
  "proof": "<reference>",
  "consequence": "<impact>",
  "remediation": "<concrete change>",
  "confidence": "confirmed | likely | hypothesis",
  "evidence_type": "official | first-hand | market-observed | hypothesis",
  "severity": "critical | high | medium | low",
  "effort": "hours | days | weeks",
  "owner": "<role>",
  "phase6_pr": "<pr-slug>",
  "expected_impact": "<measurable>",
  "tracking_plan": "<metric, source, window>",
  "rollback_path": "<how>",
  "recheck_by": "<YYYY-MM-DD>",
  "tier_relevance": "T1 | T2 | T3 | T4 | all"
}
```

## Done when

- Every check in [AUDIT-CHECKLIST](../references/AUDIT-CHECKLIST.md) for this area is marked pass / fail / unknown.
- All findings have proof reference (URL, screenshot path, GSC export path, log entry).
- All findings have severity earned (critical means indexing-blocking, manual-action-pending, or revenue-blocking right now).
- Items with insufficient evidence are written to `analyses/unknowns.md`, not silently graduated.

## Anti-patterns

- Marking everything `confirmed` because it sounds better.
- Calling easy fixes `critical`.
- Writing a finding without proof reference.
- Skipping the per-area report and only writing JSON.
- Recommending changes without measurable expected impact.
