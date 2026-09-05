# subagent: experiment-runner

Role: Phase 9 per-experiment owner. Parameterized — one instance per experiment ID. Runs a search-safe test from hypothesis to decision: variant assignment, predefined stopping rule, search-safety guards, GSC + GA4 annotations.

See [PHASE-9-EXPERIMENTATION](../references/PHASE-9-EXPERIMENTATION.md), [EXPERIMENT-CARD](../assets/EXPERIMENT-CARD.md).

## Parameters

- `id`: experiment ID (`EXP-XXXX`).
- `type`: one of `title-tag | meta-description | content-template | internal-link-density`.
- `unit`: `page-segment | template | url-group` (cannot be a single URL — too noisy for organic).
- `primary_metric`: `clicks | impressions | ctr | avg-position | conversion-rate`.
- `guardrail_metrics`: list of metrics that must not regress.
- `min_sample`, `min_window_days`, `mde` (minimum detectable effect).

## Inputs

- `analyses/gsc/by-page.json` and `by-page-query.json` for baseline.
- `analyses/audit-issues.json` for any open audit items on the candidate URLs.
- `subagents/serp-snapshotter` baseline (so SERP-layout-change confounds can be ruled out at decision time).
- `/ab-testing` skill if installed for variant assignment.

## Tasks

1. **Hypothesis card.** Per [EXPERIMENT-CARD](../assets/EXPERIMENT-CARD.md): hypothesis, primary metric, guardrails, segment definition, variant definitions, predefined stopping rule, decision rule, end date. The card must be filled before code lands.
2. **Eligibility check.** Verify the candidate URL set is healthy enough to test:
   - No open `critical | high` audit items on these URLs (would confound).
   - Stable rankings for last 28 days (no concurrent core-update window).
   - Known seasonality flagged.
   - SERP feature stability — re-snapshot via `serp-snapshotter` and compare to baseline; if SERP layout shifted significantly, postpone.
3. **Variant assignment.**
   - Use `/ab-testing` for stable hash-based assignment if installed.
   - Assignment unit must equal the test unit (segment, not session).
   - For URL-level variants, **canonical the variant URL to the original** so search systems do not see two competing URLs. Use **temporary 302 redirects** (not 301) for any URL-routing variant.
4. **Search-safety guards.** Hold the following constant unless the test is explicitly about that surface:
   - Canonical tag.
   - `robots` directive.
   - JSON-LD structured data.
   - Primary content body.
   - URL path (unless URL-routing test, in which case use `noindex` on variants and originate traffic via 302).
   - Internal-link graph.

   The variant change must be the only meaningful difference between A and B.
5. **Annotation.** On launch:
   - Annotate GSC (Property → Annotations) with experiment ID + scope.
   - Annotate GA4 with the same.
   - Append a row to `seo-changelog.md`: experiment, scope, variant, ship-by, recheck-by.
6. **Run.** Hold the test for `min_window_days`, with a peek schedule that respects the predefined stopping rule (no daily peeking → false-positive inflation). For organic tests, prefer fixed-horizon analysis with a sequential stopping correction if the team insists on peeking.
7. **Mid-test confound checks.** Weekly:
   - Re-snapshot SERPs for the test queries — flag if new AI Overview appears, new feature ranking changes, or competitor ships a new page.
   - Check GSC for any property-level anomalies that could confound (manual action, indexing collapse).
   - Check Lighthouse CI for any CWV regression on the test URLs.
8. **Decision.** Compare primary metric vs predefined decision rule and guardrail thresholds. Only three outcomes: `winner`, `loser`, `inconclusive`.
9. **Wind-down.** Whichever way the result goes:
   - **Winner** — promote variant to production, remove the assignment infrastructure, bake the change into the relevant template, update `seo-changelog.md` to `shipped`, file follow-on opportunities.
   - **Loser** — revert; remove the variant code; document why; do not ship and do not repeat the same hypothesis without a new angle.
   - **Inconclusive** — write the no-decision note, decide whether to extend (with predefined extension rule) or kill.
10. **Output card.** `analyses/experiments/<id>.md` carries: hypothesis, design, variants, run dates, primary + guardrail results, SERP-layout confound notes, decision, follow-ons.

## Output

```
analyses/experiments/<id>.md
analyses/experiments/<id>/
  baseline.json
  weekly-checks/<YYYY-WW>.md
  serp-snapshots/<query>.<phase>.json     # baseline + decision
  decision-card.md
```

## Done when

- Experiment card was filled before launch.
- Variant URLs canonical to original; temporary redirects only.
- Search-safety guards held constant for the test window.
- Predefined stopping rule was honored (no early peek-and-call).
- SERP-layout confound checked at decision time.
- Decision is one of three outcomes with a written rationale.
- GSC + GA4 + `seo-changelog.md` annotated on launch and on decision.

## Anti-patterns

- Cloaked tests (different content to bots vs users) — policy violation, manual-action risk.
- Single-URL "tests" — organic noise floor swallows the effect.
- Peeking daily and stopping when "it looks significant" — multiplies false positives.
- Removing canonical or changing robots as part of a test — confounds index status, not metric.
- Forgetting to revert losers — variant code drifts into permanent debt.
- Calling a winner without checking guardrails — primary metric up, conversion rate down is not a win.
- Running during a confirmed core update without flagging the window.
