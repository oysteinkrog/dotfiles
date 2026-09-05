# Audit item

```json
{
  "id": "AUDIT-XXXX",
  "area": "crawl | index | render | schema | links | perf | logs | infra | meta | a11y | intl",
  "issue": "<concise defect>",
  "proof": "<URL, element, screenshot path, GSC export ref>",
  "consequence": "<crawl/index/CTR/rank/UX/conversion impact>",
  "remediation": "<concrete code/content change>",
  "confidence": "confirmed | likely | hypothesis",
  "evidence_type": "official | expert-reviewed | first-hand | market-observed | hypothesis",
  "severity": "critical | high | medium | low",
  "effort": "hours | days | weeks",
  "owner": "engineering | content | design | product | analytics | legal",
  "phase6_pr": "<pr-slug>",
  "expected_impact": "<measurable outcome with magnitude>",
  "tracking_plan": "<source, metric, window>",
  "rollback_path": "<how to revert>",
  "recheck_by": "<YYYY-MM-DD>",
  "blocks": ["AUDIT-####"],
  "blocked_by": ["AUDIT-####"],
  "tier_relevance": "T1 | T2 | T3 | T4 | all"
}
```

## Markdown (human-readable)

```md
### AUDIT-XXXX — <one-line>

- **Area**: <area>
- **Confidence**: `confirmed | likely | hypothesis`
- **Severity**: `critical | high | medium | low`
- **Effort**: hours | days | weeks
- **Owner**: <role>
- **Phase 6 PR**: `seo/<slug>`

#### Proof
<URL, element, screenshot, export reference>

#### Consequence
<impact>

#### Remediation
<concrete change>

#### Expected impact
<measurable outcome>

#### Tracking
<metric, source, window>

#### Rollback
<how>

#### Recheck-by
<date>
```
