# Experiment card

```md
# Experiment EXP-XXXX — <short name>

## Hypothesis
If we change <X> on <segment>, then <metric> will move by <expected magnitude>.

## Why
<reasoning grounded in audit / GSC data / SERP analysis>

## Setup

- Control segment A: <urls or rule>
- Variant segment B: <urls or rule>
- Variant change: <exact diff>
- Random assignment: <user-level / page-level>
- Confounders to monitor: <release schedule, seasonality, etc.>

## Search-safety guards

- [ ] Variant URLs (if any) `canonical` to original.
- [ ] Variant URL redirects (if any) are temporary, not permanent.
- [ ] Primary content, robots, structured data stable (unless test is *about* those).
- [ ] Documented in `analyses/experiments/EXP-XXXX.md`.
- [ ] GSC + GA4 annotations added.

## Metrics

- Primary: <CTR / clicks / conversions>
- Guardrail: <bounce, conversions, INP, time-on-page, complaint rate>
- Minimum sample: <impressions or sessions>
- Stopping rule: <statistical threshold; max duration>
- Statistical method: <test type; significance threshold>

## Schedule

- Start: <date>
- End: <date or stopping condition>
- Owner: <human name>

## Decision rule

- If primary metric +X% with p < 0.05 and no guardrail regression → ship variant.
- If primary metric -X% → revert.
- If inconclusive → do not ship; note learnings.

## Result (filled in after end)

- Primary: <delta with CI>
- Guardrail: <delta>
- Decision: <ship / revert / inconclusive>
- Lessons: <bullet>
- Next experiment: <link to next experiment card if applicable>
```
