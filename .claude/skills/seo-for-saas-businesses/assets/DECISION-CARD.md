# Decision card

```md
## DC-XXXX: <one-line decision>

- Hypothesis: If we <action>, then <metric> will move by <expected magnitude> within <window>.
- Why now: <reasoning grounded in evidence — audit ID(s), GSC export, SERP analysis, CrUX delta>
- Confidence: confirmed | likely | hypothesis
- Severity / priority: critical | high | medium | low
- Effort: hours | days | weeks
- Owner: <human name> (<role>)
- Ship-by: <date>
- Recheck-by: <date>

## Tracking plan
- Primary metric: <metric, source, window>
- Guardrail metrics: <metrics>
- Annotation: GSC + GA4 + seo-changelog.md

## Rollback
- Code: <how — typically `git revert <merge-sha>`>
- Config: <flag toggle if applicable>
- Time-to-rollback: <minutes / hours>

## Evidence
- <link to audit item, GSC export, screenshot path, log entry>

## Dependencies
- Blocks: <other DC ids>
- Blocked by: <other DC ids>

## Decision
- Approved by: <user>
- Date approved: <date>
- Notes: <anything specific>
```
