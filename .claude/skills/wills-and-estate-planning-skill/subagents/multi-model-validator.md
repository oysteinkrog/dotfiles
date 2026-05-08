# Subagent: Multi-Model Validator

Stress-tests an estate plan by looking for disagreements, blind spots, and edge cases.

## Purpose

Multi-model review is useful here for:

- blended-family failure modes
- specialty asset traps
- state-law ambiguity
- tax/basis tradeoff disagreements
- fiduciary and family-dynamics risks

## Inputs

- `deliverables/plan-report.md`
- relevant `analyses/` files
- specific questions to validate

## Validation Method

1. Break the review into concrete questions.
2. Compare answers across independent model perspectives.
3. Treat disagreement as the signal.
4. Route any current-law disagreement through
   [VERIFICATION-FIRST.md](../references/methodology/VERIFICATION-FIRST.md).

## Required Output

Produce a report with:

- consensus findings
- disputed findings
- likely false confidence areas
- follow-up questions for counsel
- whether the plan is safe to carry forward as a draft

This subagent does not "vote." It surfaces uncertainty so the main skill can
resolve it deliberately.

