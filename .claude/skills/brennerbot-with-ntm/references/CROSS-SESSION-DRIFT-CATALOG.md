# CROSS-SESSION-DRIFT-CATALOG.md — Methodology Drift Across Sessions

This catalog is the skill-level rollup for Phase 10 drift checks. Add a row when a session's `DRIFT-CHECK.md` reveals a repeatable methodology pattern, regression, or improvement.

`scripts/drift-trend.sh --skill-dir=<skill-dir>` reads the table below, so keep the columns and verdict spelling stable.

| session | date | verdict | top regression | top improvement | lessons |
|---------|------|---------|----------------|-----------------|---------|

## Verdict Values

- `convergent` — the run followed the canonical Brennerbot method.
- `divergent-improvement` — the run changed the method and the change should be considered for promotion.
- `divergent-regression` — the run drifted in a way that degraded the method.
- `mixed` — the run contains both useful improvement and regression.

## Entry Rules

1. Cite the source workspace and `deliverables/DRIFT-CHECK.md`.
2. Name the specific operator, phase, or marching order involved.
3. Keep lessons actionable enough to update `OPERATORS.md`, `PHASES.md`, or a marching order.
