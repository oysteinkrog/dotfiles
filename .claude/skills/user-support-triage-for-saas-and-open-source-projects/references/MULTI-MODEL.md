# Multi-Model Triangulation For Hard Triage Cases

When stakes are high and ambiguity is real, run the case through multiple AI models and reconcile their outputs. Used by the 🪞 SECOND-OPINION operator.

## When To Use

- Refund > $X (project default: $200)
- Security-flavored cases that aren't obvious
- Legal-threat language ("class action", "regulator")
- Data-loss with disputed timeline
- A pattern that "feels off" but you can't articulate why
- An owner has flagged a recurring class of mistake to triple-check
- Your initial draft has high confidence but you've been wrong on similar before

Cost is small (~$0.10 per case at current API prices). Don't reach for it on every ticket — but on the 1 in 50 hard ones, it pays for itself in one avoided wrong call.

## With `/multi-model-triangulation` Skill (If Installed)

```bash
# Bundle the case
cat > /tmp/case.md <<EOF
TICKET: <id>
USER: <handle> (tier=<tier>)
SUBJECT: <subject>

USER MESSAGE (verbatim):
<message>

OUR INVESTIGATION:
- <repro result>
- <version pin>
- <correlation findings>

PROPOSED ACTION:
<proposed action + reasoning>

QUESTION:
What am I missing? Is the proposed action right? What's the
worst-case outcome if I'm wrong?
EOF

# Triangulate
triangulate "$(cat /tmp/case.md)" \
  --models codex,gemini,grok \
  --output /tmp/triangulation.md
```

The skill returns each model's response separately, then a synthesis. Read all four. If 2+ models flag the same risk you missed, reconsider.

## Without the Skill (Fallback)

You can still get the value with a structured manual pass:

### Approach 1 — Persona Rotation (Single-Model)

Re-read the ticket as five different personas, in order:

1. **Literal reader**: "What does the customer literally say?"
2. **Skeptical reviewer**: "What's the most uncharitable read?"
3. **Junior agent**: "What would I do if I'd been here 1 week?"
4. **Senior agent**: "What pattern have I seen before that this matches?"
5. **Adversarial counsel**: "If this becomes a lawsuit, how does my reply look in discovery?"

For each, write 2-3 sentences. If any persona surfaces a concern your draft doesn't address, fix the draft.

### Approach 2 — The 5-Question Pre-Send Check

Force the questions explicitly:

1. "What's the most uncharitable interpretation?"
2. "What would a hostile reviewer say about my action?"
3. "What 3 facts could change my mind, and have I checked them?"
4. "What's the worst-case outcome if I'm wrong?"
5. "Re-read the ticket as if I've never seen it. Does my draft address what's actually written?"

If any question surfaces a gap, fix before sending.

### Approach 3 — Steelman Sandbox

Spend 5 minutes writing the BEST possible case for the customer's position (even if you disagree). If your steelman is more compelling than your draft, your draft is wrong.

## Reconciling Multi-Model Output

If you ran `/multi-model-triangulation`, you get 3-4 model responses + a synthesis. How to reconcile:

| Pattern | Action |
|---|---|
| All 3-4 models agree with proposed action | High confidence; proceed |
| 2+ models flag the same risk you missed | Reconsider; update the draft to address the risk |
| Models disagree on the right action | Read carefully; pick the action with the smallest worst-case downside |
| Models surface a NEW dimension (e.g., "is this a GDPR question?") | Route to that runbook; don't ship the original draft |
| Synthesis says "the question is wrong" | Step back; the case may need different categorization |

## When Models Don't Help

Multi-model triangulation has failure modes:

- **All models trained on similar data** → all agree, all wrong (groupthink in distribution)
- **The case is too short** → models pattern-match without enough context; provide more
- **The case is too specific** → models can't transfer; rely on operator-driven decision matrix
- **The owner has unique context** → no model can replicate "we tried that with customer X last quarter and it backfired"

When models don't help, escalate to the owner directly with the case + your reasoning + the synthesis.

## Cost / Latency Budget

- Per-case cost: ~$0.10 (3 model calls + synthesis)
- Per-case latency: ~30-60 seconds
- Use sparingly: ≤5% of triaged tickets
- Budget per session: ~$2 (if hard cases were 10-20% of session)

## Examples

### Example 1: Refund Edge Case

```
PROPOSED: Decline refund — outside 30-day window.

Triangulation flagged:
- Codex: "Customer cites EU residency; UK CRA Article 16(m) may
   apply if performance hadn't started before they noticed the
   defect. Have you confirmed when 'performance started' in your
   ToS?"
- Gemini: "Same — also note the customer mentioned 'I cancelled
   immediately upon discovery' — that's the language of statutory
   withdrawal rights, not voluntary cancellation."
- Grok: "Decline is technically defensible but optically poor. ROI
   on a $40 refund + retain customer >> ROI on holding the line."

REVISED: Issue refund + cite specific ToS clause for clarity. Cost
$40; avoid $1500 chargeback risk + EU regulator complaint.
```

### Example 2: Security DM

```
PROPOSED: Standard SECURITY-ACK + 72h reproduction window.

Triangulation flagged:
- Codex: "The PoC code includes a working SSRF chain. CVSS likely
   9.0+. Don't wait 72h to engage; ack within 4h with severity
   acknowledgment."
- Gemini: "Reporter handle has prior CVEs against major vendors;
   they're a known good actor. Treat seriously and offer their
   preferred encrypted channel."
- Grok: "SSRF + cloud creds = potentially CRITICAL. Brief owner
   immediately, prep emergency patch path."

REVISED: 4h ack instead of 24h; brief owner now; reserve emergency
deploy slot.
```

## Validators

After running multi-model triangulation:
- [ ] All 3+ model responses read in full
- [ ] Risks not in original draft are addressed in revised draft
- [ ] Synthesis read; any "the question is wrong" flags are heeded
- [ ] At least 2 substantive changes from original draft (or explicit "no changes needed; high confidence")
- [ ] Output committed to `<workspace>/triangulation-<ticket-id>.md` for audit

## Companion Skills

- `/multi-model-triangulation` — the official triangulation skill (preferred)
- `/dueling-idea-wizards` — adversarial generation pattern (overlaps with persona rotation)
- `/modes-of-reasoning-project-analysis` — multi-perspective project analysis (broader scope)
- `/code-review-gemini-swarm-with-ntm` — code review variant (use when triage involves a code change)
