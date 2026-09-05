# PHASE 9 — EXPERIMENTATION & ITERATION

Goal: hypothesis-driven, search-safe tests with predefined stopping rules.

## Test types

### Title-tag tests

Segment-split test, not cloaked variant. E.g. apply variant title across half of a cluster's pages; baseline title across the other half. Compare CTR over a controlled window.

### Meta-description tests

Same pattern. Primary metric: CTR.

### Content-template tests

For programmatic templates: variant A vs variant B applied to two sub-segments of comparable demand. Compare impressions, CTR, position, conversion.

### Internal-link density tests

For one cluster: shipping with N internal links per page vs N+5. Compare cluster impressions / clicks / position / conversion.

## Search-safe rules (from guide §20 + Google's experiment guidance)

- Use canonical tags on alternate test URLs pointing to the original.
- Use temporary redirects for variant URLs, not permanent.
- Keep primary content, canonicals, robots, and structured data stable unless the test is *explicitly about* those elements.
- End tests on schedule; remove variant scripts and revert metadata on losers.
- Use `/ab-testing` skill for the assignment infrastructure.
- Document every test in `analyses/experiments/<id>.md`; annotate GSC and analytics.

## Per-experiment card

```md
# Experiment: <id> — <short name>

## Hypothesis
If we change <X> on <segment>, then <metric> will move by <expected magnitude>.

## Why
<reasoning grounded in audit / GSC data / SERP analysis>

## Setup
- Segment A (control): <urls or rule>
- Segment B (variant): <urls or rule>
- Variant change: <exact diff>
- Random assignment: <user-level / page-level>
- Confounders: <release schedule, seasonality, etc>

## Metrics
- Primary: <CTR / clicks / conversions>
- Guardrail: <bounce rate, conversions, INP, time-on-page>
- Minimum sample: <impressions or sessions>
- Stopping rule: <statistical significance threshold; max duration>

## Annotations
- Start date: <date>
- End date: <date>
- GSC annotation: <text>
- GA4 annotation: <text>

## Decision rule
- If primary metric +X% with p < 0.05 and no guardrail regression → ship variant.
- If primary metric -X% → revert.
- If inconclusive → do not ship; note learnings.

## Result (filled in after end)
- Primary: <delta>
- Guardrail: <delta>
- Decision: <ship / revert / inconclusive>
- Lessons: <bullet>
```

## Pipeline

1. Backlog of experiment ideas (from Phase 3 metadata audit, Phase 8 striking-distance list, Phase 13 compounding ideation).
2. Prioritize by `experiment_priority_score_0_1000`, derived from expected lift, confidence, effort, and reversibility.
3. Run no more than one test per cluster simultaneously (avoid confounded analysis).
4. After end, revert losers; promote winners; document both in `seo-changelog.md`.

## Tooling

- `/ab-testing` skill for variant assignment infrastructure (Next.js 16 server-side + GA4/GTM event integration).
- GSC for position / impressions / CTR per URL or URL pattern.
- GA4 for conversion impact.
- `scripts/serp-snapshot.ts` for SERP-feature checks (in case a SERP layout change confounds the result).

## Anti-patterns

- Cloaking — showing different content to crawlers vs users to "test" rankings.
- Permanent redirects on test variants.
- Running concurrent tests on the same segment (confounded).
- No predefined stopping rule — peeking until "winning" appears.
- Shipping a winner across the whole site that was only tested on one segment.
- Not annotating GSC / GA4 — future traffic analyses can't attribute movement.
- Title tests that swap meaningfully different intents (then it's not a title test, it's a re-targeting).
