# Multi-Model Triangulation

For Phase 7 fresh-eyes (and Phase 9 staging-drill verification in Swarm tier), running the same review prompt across multiple models catches different classes of bug. Claude tends to miss the same things twice; an independent model often catches what we missed.

The prerequisite skill is `/multi-model-triangulation` (preferred). If it's not installed, hand-roll using the `codex` and `gemini` CLIs.

---

## When to triangulate

| Phase | Triangulate? | Why |
|-------|--------------|-----|
| 1 Archaeology | No | Different models read code differently; we don't need consensus on observation |
| 2 Coverage | No | Mechanical classification |
| 3 Risk | Sometimes | Useful for the executive summary on Critical/High classes |
| 4 Plan | No | Single planner per bundle is fine |
| 5 Implement | No | Continuity of context > consensus |
| 6 Harmonize | No | Same as Plan |
| 7 Fresh-eyes | **YES — primary** | Independent reads catch different bugs; this is where the value lives |
| 8 Tests | Sometimes | For the adversarial test suite, useful to brainstorm attack scenarios across models |
| 9 Staging drill | Sometimes | Useful for the post-drill report; multiple models propose different drills |
| 10 Runbooks | No | Single-author readability > consensus |

---

## Models in the panel

The standard panel:

| Model | Strength | Typical role |
|-------|----------|--------------|
| Claude (Opus 4.7 / Sonnet 4.6) | Long-context cross-file reasoning; pattern-matching against this skill | Primary; does Round A/B/C |
| Codex (GPT-5.5) | Strong on syntactic edge cases; comments closely on edge of types | Independent Round A/B/C |
| Gemini (3.x) | Strong on adversarial framing; finds attack vectors others miss | Independent Round C (security focus) |

You can swap in other models (Grok, DeepSeek, etc.) per the user's account access. The consensus rules are the same regardless of which models are in the panel.

---

## Consensus rules

For each finding any model emits, record `{ finding_id, models_that_flagged: [...], severity, file:line, fix_proposed, dissent_reason? }`.

| Vote | Disposition |
|------|-------------|
| 3/3 (or 3/n on a panel of 3+) | Ship the fix; assign to the bundle's implementer |
| 2/3 | Ship UNLESS the dissenter cites a concrete counter-example (e.g., "this WHERE clause is intentionally permissive because of bd-X") |
| 1/3 | Flag for human review; do NOT auto-fix |

Special case: a Critical (score-9) finding with even a single-model vote should be reviewed by a human, not auto-fixed.

---

## Hand-rolled triangulation (no skill installed)

If `/multi-model-triangulation` is missing but you have `codex` and `gemini` CLIs:

```bash
# Round C prompt (verbatim from AGENT-PROMPTS.md § Phase 7 Round C)
PROMPT=$(cat <<'EOF'
Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep!

Specific focus areas:
- Hijack defenses on every UPDATE...
[full prompt from AGENT-PROMPTS.md]

Output JSON to stdout: { findings: [{ severity, file, line, description, fix_proposed }] }
EOF
)

# Fan out
echo "$PROMPT" | codex -m o1 --json > .billing_workspace/phase7_round1_codex_C.json
echo "$PROMPT" | gemini --json > .billing_workspace/phase7_round1_gemini_C.json
# Claude already produced .billing_workspace/phase7_round_1_C.md from the inline run

# Reconcile manually:
./scripts/triangulate-merge.sh phase7_round1 > .billing_workspace/phase7_triangulation_round_1.md
```

The reconciler script (you'd write this if needed) parses the three JSON outputs and applies the consensus rules.

---

## Disagreement handling

When models disagree, the highest-leverage move is to **make the dissent explicit** rather than picking a winner.

Example output:

```markdown
### Finding T-12: 2/3 votes — Stripe webhook handler returns 500 on parsing error

- **Claude (flagged)**: src/app/api/stripe/webhook/route.ts:88 returns `NextResponse.json({...}, { status: 500 })` after `recordWebhookEvent` succeeded. Operator: ⤴ 200-ON-ERROR. Fix: change to `{ status: 200, outcome: "error_acknowledged" }`.
- **Codex (flagged)**: Same finding. Same fix.
- **Gemini (dissented)**: This handler is the legacy v0 webhook still receiving events from a deprecated Stripe API version. The 500 is intentional to surface the migration; reconciliation cron handles real events from the v1 endpoint.
- **Disposition**: Verify Gemini's claim. Read git blame on the handler; check Stripe Dashboard for v0 endpoint config. If Gemini is right (v0 deprecated), retire the v0 route with an explicit, user-approved forward change and preserve the audit trail. Do not delete files/routes without permission. If wrong, ship the 200-on-error change.

Action item: assigned to <user> for verification.
```

This is more useful than "2/3 said fix; we fixed it" — Gemini's dissent might be the actual right call.

---

## Cost discipline

- Triangulation is expensive (3x model calls). Reserve for Phase 7 review, not implementation.
- Cap per-round triangulation at ≤30min wall-time across the panel.
- Phase 7 typically runs 2–3 rounds; that's 6–9 model invocations total. Budget accordingly.

---

## Failure modes

- **All models say "looks great"** → low signal; either the code IS great or all models miss the same thing. Force a "find the worst three things" prompt as a tiebreaker.
- **Models disagree on severity** → ship the highest severity (be conservative).
- **Models propose contradictory fixes** → don't ship either; surface for human resolution.
- **One model returns garbage / hallucinated file paths** → drop that model's output for the round; note the issue in the triangulation log.
