# Multi-Model Triangulation Prompts (verbatim, per Phase + per failure class)

> **Where this comes from.** Extension of `TRIANGULATION.md`. The base file describes the harness; this file has the actual prompts to send to Codex / Gemini / Grok with the right context for billing reviews.

For Phase 7 (fresh-eyes) and Phase 9 (staging-drill verification) in Swarm tier. Each prompt is calibrated for a specific lens + a specific reviewer model.

---

## How to use

1. Pick the lens (A / B / C from `AGENT-PROMPTS.md`).
2. Pick the model (Codex / Gemini / Grok).
3. Send the matching prompt verbatim, substituting `<placeholders>`.
4. Each model emits structured findings; reconcile per consensus rules in `TRIANGULATION.md`.

---

## Codex prompts

### Codex Round A — your-own-code lens (billing)

```
You are reviewing recently-changed billing code in a SaaS project. Your task: find bugs, security issues, edge cases, and pattern violations in the diff between <BASE_REF> and HEAD.

Context:
- The project uses Stripe + PayPal for subscriptions (or one of them; check imports).
- The architecture follows references/patterns/00-NORTH-STAR.md (16 north-star principles).
- Critical operators (read /OPERATORS.md before reviewing):
  ⊙ Provider-Authority • ⊕ Layered-Defense • 🔒 Idempotent-Write • ⌖ Hijack-Cross-Check
  ⏱ Stale-Event-Gate • ⤴ 200-On-Error • ⛓ Analytics-Exclusion • 🪟 Provenance
  🗄 Intent-Then-Act • ⊞ Advisory-Lock • 🔁 Reconciliation-Backstop • ⚖ Human-In-Loop-Refund
  🔐 Secret-Custody • 🧪 Pin-The-Contract • 📐 Type-Derive-Not-Hard-Code
  🎚 Priority-Aware-Queue • 🪞 Bidirectional-Coverage

Specific things to check (these are the 38 known failure classes):
[Paste full list from /references/patterns/145-EXTENDED-FAILURE-CATALOG.md, themes 1-8]

Output JSON to stdout:
{
  "findings": [
    {
      "severity": "critical | high | medium | low",
      "operator": "⊙ | ⊕ | 🔒 | ...",
      "file": "src/...",
      "line": 42,
      "description": "...",
      "fix_proposed": "...",
      "failure_class": "F1.4 | F2.1 | ...",
      "confidence": "high | medium | low"
    }
  ]
}

Discipline:
- Cite file:line for every finding.
- Use the operator glyphs and failure-class IDs so cross-model reconciliation is possible.
- Mark confidence honestly; "low" findings are ones you're not sure about.
- Don't propose fixes for things you're not sure about; flag them for human review.
- Don't restrict to the diff; also walk imports + callers to find indirect bugs.
- AGENTS.md applies; never propose `git reset --hard` or destructive operations.
```

### Codex Round B — random-walk lens (billing)

```
[Same intro as Round A]

Your lens for THIS round: random-walk exploration. Don't focus on the diff. Pick 3-5 billing-touching files randomly; trace their imports + callers; find bugs in OLD code that may have lurked for months.

Bias toward files that:
- Handle webhooks
- Touch the subscriptions or payment_events tables
- Run as crons
- Send customer-facing emails
- Are imported by many other files (grep -r imports)

Output JSON same as Round A.

Discipline:
- For each file you explore, write down WHY you picked it (in the finding's `details.why_explored`).
- Don't ignore tests; tests reveal intent + sometimes have their own bugs.
- Look for: pattern drift (e.g., last_event_at WHERE missing on a NEW UPDATE site).
```

### Codex Round C — adversarial / security lens (billing)

```
[Same intro]

Your lens for THIS round: adversarial. You are an attacker. Walk every state-mutation path and ask: "If I had attacker control over <input>, could I exploit this?"

Specific attack scenarios to test against:
1. Hijack via metadata.user_id / custom_id (PayPal individual + team).
2. Replay attack via stale event (last_event_at miss).
3. 500-on-error → retry storm → duplicate side effects.
4. Account-mismatch on Stripe Connect / org events.
5. Cross-provider webhook payload confusion.
6. Refund without cache invalidation → access leak.
7. Auto-refund / auto-cancel trigger bombs.
8. Email-fallback hijack (gating by customerId IS NOT NULL).
9. Admin retry without age cutoff → revive cancelled customer.
10. Credential leakage (NEXT_PUBLIC_* with secrets; .env in git history).
11. RLS bypass (queries that don't filter by user_id under anon JWT).
12. Insider threat (admin self-target; admin without 4-eye).
13. Webhook signature failures spammed → cooldown bans Stripe IPs.
14. Cron concurrency without advisory lock → double-process.
15. SQL injection via JSONB operators (rare but check).

Output JSON same as Rounds A/B.

Discipline:
- For each finding, write a CONCRETE attack scenario in `details.attack_scenario`.
- Cast wide; don't restrict to recent commits.
- Don't propose fixes for things you'd want a human to verify (flag with confidence: low).
```

---

## Gemini prompts

### Gemini Round A — your-own-code lens (billing)

```
[Same intro as Codex Round A]

Same task. Same output format. Same discipline.

Gemini-specific note: leverage your strength in long-context reasoning. Read the FULL pattern bundles + the FULL diff before flagging. Cross-reference findings against the 16 north-star principles + the 21 operator cards.
```

### Gemini Round C — adversarial (billing)

```
[Same intro + Round C attacker mindset]

Gemini-specific note: you're known for finding novel attack vectors others miss. Don't restrict to the listed 15 scenarios; SUGGEST new attack scenarios you can think of. Mark them with `confidence: low` if speculative; `medium` if plausible; `high` if you can construct a concrete reproduction.

Also check for:
- Race conditions between concurrent webhooks for the same subscription.
- Time-of-check-to-time-of-use (TOCTOU) bugs in admin flows.
- Privilege-escalation paths through nested API calls.
- Information leakage via timing differences (constant-time check?).
- Logging that exposes sensitive fields (PII, tokens) without redaction.
- Side-channel attacks via cache hit/miss timing on auth checks.
```

---

## Grok prompts

### Grok Round A — your-own-code lens (billing)

```
[Same intro]

Grok-specific note: you tend to surface "this looks weird; here's why" findings that other models miss because they were trained on textbook patterns. Trust your intuition; flag anything that LOOKS wrong even if you can't articulate exactly why. Mark with `confidence: low`.
```

---

## Reconciliation prompt

After all three models report, reconcile:

```
You are a code-review reconciliation engine. Your input is N JSON files, one per model, each with a `findings` array.

Task: deduplicate findings + apply consensus rules.

Consensus rules:
- 3/3 agree on a finding (same file:line ± 5 lines, same operator/class) → ship; severity = max of three.
- 2/3 agree → ship UNLESS the third explicitly DISSENTS (not just absent).
- 1/3 only → flag for human review.
- ANY model finds a `severity: critical` → escalate to human regardless of consensus.

For dissents: capture the dissent_reason in the output.

Output JSON to .billing_workspace/phase7_triangulation_round_<N>.md:
{
  "round": <N>,
  "findings": [
    {
      "consensus": "3/3 | 2/3 | 1/3",
      "models_that_flagged": ["claude", "codex"],
      "models_that_dissented": ["gemini"],
      "dissent_reason": "...",
      "disposition": "ship | flag_for_human | dissent_review",
      "finding": { ... merged ... }
    }
  ]
}
```

---

## Per-failure-class triangulation prompts

For Phase 9 staging-drill verification, prompt each model to ATTEMPT a specific attack scenario.

### Triangulate F2.1 — PayPal individual hijack drill

```
[Same intro as Round C]

Specific drill: attempt the PayPal individual hijack scenario.

1. Pick a "victim" user with userId = 11111111-1111-1111-1111-111111111111 (test fixture alice).
2. Construct a PayPal webhook payload with custom_id = '11111111-1111-1111-1111-111111111111' and a payer_id you control (test fixture).
3. Sign the payload with the staging webhook secret.
4. POST to staging /api/paypal/webhook.

Expected outcome:
- 200 response with outcome = 'rejected_user_id_mismatch' (or equivalent).
- abuse_signals row written with signal = 'paypal_user_id_mismatch'.
- Victim's user row UNCHANGED.

Verify by querying the staging DB after the drill.

Output: { "drill_status": "PASS | FAIL", "details": { ... } }

If FAIL: explain WHAT happened and WHY it's a containment failure.
```

### Triangulate F2.2 — PayPal team hijack drill

```
[Same intro]

Specific drill: PayPal team hijack scenario.

1. Pick a "victim" org with id = aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.
2. Construct a BILLING.SUBSCRIPTION.CANCELLED payload with resource.id = a sub_id YOU created (your test sub).
3. Set custom_id = victim org id.
4. Sign + POST to staging.

Expected outcome:
- 200 response with outcome = 'rejected_subscription_id_mismatch'.
- abuse_signals row.
- Victim org row UNCHANGED.

[Same output format]
```

### Triangulate F1.4 — 200-on-error drill

```
[Same intro]

Specific drill: webhook 200-on-error.

1. Construct a webhook payload that will TRIGGER an error in the handler (e.g., reference a customer_id that doesn't exist in DB).
2. Sign + POST.

Expected outcome:
- 200 response (NOT 500).
- payment_events row recorded with last_error populated.
- Reconciliation cron will retry.

[Same output format]
```

(Add per-class drills for all 38 classes for a Swarm-tier full triangulation.)

---

## Cost discipline

- Per-round triangulation = 3 models × 3 lenses (A/B/C) = 9 model invocations.
- Plus per-class drills for Phase 9 = N classes × 3 models = 3N invocations.
- For T4 Swarm tier with 38 classes: 9 + 38 × 3 = 123 invocations per Phase-7-round + Phase-9.
- Budget: $X per round depending on model pricing.

Cap per-round total at 30 minutes wall-time. If individual models exceed, drop them for the round.

---

## Common triangulation mistakes

- **Single model, no triangulation.** Same blind spots persist; same bugs ship.
- **Models reach different conclusions; pick favorite.** Bias. Use consensus rules.
- **Ignore "low confidence" findings.** Some are real; just need verification.
- **Don't capture dissent_reason.** Future engineer can't tell why one model said no.
- **Triangulate every PR.** Cost explodes; reserve for high-risk changes.
- **Models all positive ("looks great").** Force a "find the worst three things" tiebreaker.
- **Per-class drill skipped because "we already have a unit test."** Drills expose integration bugs unit tests miss.
