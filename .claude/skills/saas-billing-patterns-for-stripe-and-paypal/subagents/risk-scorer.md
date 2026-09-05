---
name: billing-risk-scorer
description: Phase 3 — scores every gap from the coverage matrix and writes the executive summary
---

# Billing Risk Scorer

Single agent (not bundle-parallel — scoring needs the cross-bundle picture). Reads the matrix; writes the scored gaps + executive summary.

## Inputs

- `.billing_workspace/phase2_coverage_matrix.md`
- `.billing_workspace/phase2_summary.md`
- `references/methodology/RISK-SCORING.md` (the rubric)

## Outputs

1. `.billing_workspace/phase3_risk_scored_gaps.md` — every `partial` or `missing` row with:
   - Pattern (file §section)
   - Score 1-9
   - Severity label (Critical | High | Medium | Low | Trivial)
   - One-sentence justification (exploitability × customer-impact × blast-radius + adjustments)
   - Fix-section reference (which pattern doc explains the fix)

2. `.billing_workspace/phase3_executive_summary.md` — ≤2 pages opening with:
   *"This billing system has X critical, Y high, Z medium gaps; the dominant theme is <pattern-cluster>."*
   Then top 5 risks with business impact, recommended next mode, blocking gates.

## Discipline

- Force a distribution: 0–5% Critical (9), 10–25% High (7-8), 35–50% Medium (5-6), 25–40% Low (3-4), 5–15% Trivial (1-2). If everything ends up `5`, you didn't score; you marked.
- Test scenarios in your head before scoring: replay, hijack, race, partial-success, network partition, secret rotation. The score should reflect what would happen under attack.
- Apply adjustments: +1 if money lost, +1 if attack unattended, +1 if silent failure, −1 if existing layer catches it, −1 if greenfield.
- Cap at 9, floor at 1.
- "Exists in codebase" ≠ "verifiably correct under attack."
- The executive summary is for a non-engineer (CTO / founder / head of platform). Prose, not tables. Money / hours / customer-trust units.

## Calibration anchors (use these to sanity-check)

| Score | Anchor |
|-------|--------|
| 9 | PayPal team hijack with no `subscription_id` cross-check |
| 8 | Synchronous cache invalidation on refund missing |
| 7 | `last_event_at` ordering missing |
| 6 | Cron without `pg_try_advisory_lock` on multi-isolate deploy |
| 5 | Analytics-exclusion missing on a new admin event publisher |
| 4 | Cache read missing `provenance` envelope |
| 3 | New email type without explicit priority branch |
| 2 | Function naming inconsistency across bundles |
| 1 | Comment removed during refactor |

## Common mistakes

- Scoring everything as 5 → no signal.
- Forgetting the +1 for unattended attacks (e.g., PayPal hijack is 9, not 8).
- Writing the executive summary in tables when the audience is non-technical. Use prose.
- Recommending the next mode based on engineering aesthetics rather than user goals. Re-read OPERATING-MODES.md.
