---
name: billing-triangulator
description: Multi-model triangulation for Phase 7 fresh-eyes (and Phase 9 staging-drill verification in Swarm tier)
---

# Billing Triangulator

Coordinates multi-model code review. The same review prompt runs across Claude + Codex + Gemini; consensus rules decide what to ship.

## When to use

- Phase 7 Round D (preferred — independent reads catch different bugs).
- Phase 9 staging-drill verification (Swarm tier only).
- Phase 3 risk-scoring for Critical/High items (optional — useful for executive-summary calibration).

## Prerequisite

The `multi-model-triangulation` skill (preferred) or both `codex` and `gemini` CLIs installed.

If neither is available, write a one-line note in the round summary: "Triangulation skipped — no multi-model tooling available; single-model (Claude) review only."

## Per-round workflow

For each of the three lens prompts (A / B / C from `subagents/fresh-eyes.md` and `subagents/security-reviewer.md`):

1. Run the SAME prompt on each model. Use the verbatim text — the wording is calibrated.
2. Each model outputs structured JSON to its own file:
   - `.billing_workspace/phase7_round<N>_<lens>_claude.json`
   - `.billing_workspace/phase7_round<N>_<lens>_codex.json`
   - `.billing_workspace/phase7_round<N>_<lens>_gemini.json`
3. Reconcile per the consensus rules (below).
4. Output `.billing_workspace/phase7_triangulation_round_<N>.md`.

## Consensus rules

For each finding any model emits, record:
```json
{
  "finding_id": "T-12",
  "models_that_flagged": ["claude", "codex"],
  "models_that_dissented": ["gemini"],
  "severity": "high",
  "file": "src/app/api/stripe/webhook/route.ts",
  "line": 88,
  "fix_proposed": "...",
  "dissent_reason": "Gemini claims this is the legacy v0 endpoint; needs verification"
}
```

| Vote | Disposition |
|------|-------------|
| 3/3 (or N/N on a panel of N≥3) | Ship; assign to bundle implementer |
| 2/3 | Ship UNLESS dissenter cites a concrete counter-example |
| 1/3 | Flag for human review; do NOT auto-fix |

Special case: a Critical (score-9) finding with ANY model vote should be reviewed by a human, not auto-fixed.

## Disagreement handling

When models disagree, surface the dissent rather than picking a winner:

```markdown
### Finding T-12: 2/3 votes — Stripe webhook handler returns 500 on parsing error

- **Claude (flagged)**: src/app/api/stripe/webhook/route.ts:88 returns NextResponse.json({...}, { status: 500 }) after recordWebhookEvent succeeded. Operator: ⤴ 200-ON-ERROR. Fix: change to status: 200 with outcome: "error_acknowledged".
- **Codex (flagged)**: Same finding. Same fix.
- **Gemini (dissented)**: This handler is the legacy v0 webhook still receiving events from a deprecated Stripe API version. The 500 is intentional to surface the migration; reconciliation cron handles real events from the v1 endpoint.
- **Disposition**: Verify Gemini's claim. Read git blame on the handler; check Stripe Dashboard for v0 endpoint config. If Gemini is right, retire the v0 route with an explicit, user-approved forward change and preserve the audit trail. Do not delete files/routes without permission. If wrong, ship the 200-on-error change.

Action item: assigned to <user> for verification.
```

## Cost discipline

- Triangulation is 3× model calls. Reserve for Phase 7 review, not implementation.
- Cap per-round triangulation at ≤30min wall-time across the panel.
- Phase 7 typically runs 2–3 rounds; that's 6–9 model invocations total.

## Common mistakes

- All models say "looks great." Low signal; force a "find the worst three things" tiebreaker.
- Models disagree on severity → ship the highest (be conservative).
- Models propose contradictory fixes → don't ship either; surface for human resolution.
- One model returns garbage → drop that model's output for the round; note in log.
