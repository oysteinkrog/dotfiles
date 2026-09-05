# CASS Mining for Billing Patterns

If the user has [`/cass`](../../../cass/SKILL.md) installed and indexed, their own past agent sessions are a powerful corpus. Real-world prompts, real-world bugs, real-world fixes that didn't make it into commits.

This file shows how to mine that corpus for billing-relevant patterns and feed them into Phase 1 / Phase 4 / Phase 10.

---

## When to mine

| Mode | When mining helps |
|------|-------------------|
| `audit-only` | Mine before Phase 1; surfaces incidents that don't appear in commits / beads. |
| `audit-and-fix` | Same as audit-only; also during Phase 4 to reuse prior plan structures. |
| `harden-incident` | First action of Phase 0 — the incident may have been partially debugged in a prior session you can pick up from. |
| `add-feature` | Mine for prior implementation discussions of related features. |
| `greenfield` | Less useful — no prior billing sessions for this project. |
| `migration` | Mine for prior provider integration sessions. |
| `compliance-pass` | Mine for prior security-audit sessions. |

---

## Discipline

Per `/cass` SKILL.md:
- NEVER run bare `cass` (TUI). Always use `--robot` or `--json`.
- stdout is data; stderr is diagnostics; exit 0 = success.
- Use `--days N` to bound time window.
- Use `--agent` to filter by agent (Claude Code / Codex / Cursor / Gemini / ChatGPT).
- Start with `cass status --json` and `cass capabilities --json`; a stale index is usable evidence, but the artifact must say it was stale.
- If a recent-window query returns zero, retry one broader query without `--days` before concluding the pattern is absent.

---

## Recipe 1 — Find prior billing-incident discussions

```bash
# Triple-charge incidents
cass search "duplicate charge" --robot --limit 20 > .billing_workspace/cass_duplicate_charge.jsonl

# Hijack class
cass search "PayPal hijack" --robot --limit 20 > .billing_workspace/cass_paypal_hijack.jsonl
cass search "subscription_id WHERE" --robot --limit 20 > .billing_workspace/cass_team_hijack.jsonl

# Stale-event class
cass search "last_event_at" --robot --limit 20 > .billing_workspace/cass_stale_event.jsonl

# Refund class
cass search "refund webhook" --robot --limit 20 > .billing_workspace/cass_refund.jsonl
cass search "synchronous cache invalidation" --robot --limit 20

# Pool exhaustion
cass search "pool exhaustion" --robot --limit 20
cass search "pause resume race" --robot --limit 20

# Webhook 200-on-error
cass search "webhook 500 retry storm" --robot --limit 20

# Email failsafe
cass search "OPS_FAILSAFE_EMAIL" --robot --limit 20

# Dunning
cass search "dunning ladder" --robot --limit 20
cass search "wasEmailDeliveredSince" --robot --limit 20
```

Append findings to `.billing_workspace/phase0_cass_mining_results.md`:

```markdown
## CASS finding: <pattern>
- session_path: /path/to/session.jsonl
- date: 2026-...
- summary: <what the prior session was about>
- relevant excerpt: <quote ≤ 5 lines>
- relevance: <which Phase 1 bundle / Phase 4 task this informs>
```

---

## Recipe 2 — Find working prompts the user has used before

If the user previously did billing work successfully with a specific prompt structure, reuse it.

```bash
# Find prompts that produced billing fixes
cass search "implement Stripe webhook" --robot --limit 10
cass search "audit billing" --robot --limit 10
cass search "verify-as-write" --robot --limit 10
```

Look for the user's voice — phrasing that matches how they frame requests. Use that voice in subagent prompts (it's usually more effective than the generic prompts in AGENT-PROMPTS.md).

---

## Recipe 3 — Mine for environment / stack hints

The user's prior sessions often reveal:
- Real env var names (might differ from this skill's defaults).
- Project-specific helper names (e.g., `recordWebhookEventV2` instead of `recordWebhookEvent`).
- Decisions the team has already made (e.g., "we don't use PayPal" → mark all PayPal patterns `n/a`).

```bash
cass search "STRIPE_PRICE" --robot --limit 20
cass search "PAYPAL_PLAN" --robot --limit 20
cass search "RESEND_API_KEY" --robot --limit 20
cass search "we decided" --robot --days 365 --limit 30   # accumulated decisions
```

These feed `phase0_stack.json` enrichment beyond what `discover-stack.sh` finds from package.json.

---

## Recipe 4 — Mine for bug-class recurrences

If the same bug class shows up across multiple sessions, that's a signal:
- The pattern bundle should call it out explicitly.
- A drift-guard test is missing.
- The runbook should make it findable.

```bash
# Look for repeated complaints
cass search "stripe webhook stuck" --robot --days 365 --limit 30
cass search "paypal hijack" --robot --days 365 --limit 30
cass search "deleted user still charged" --robot --days 365 --limit 30
```

If you see ≥3 sessions with the same class, file as a "recurring pattern; needs systemic fix" item in Phase 4.

---

## Recipe 5 — Mine for prior partial implementations

The user may have started a billing feature months ago and abandoned it. Pick up from there.

```bash
cass search "team plans" --robot --limit 15
cass search "pause resume" --robot --limit 15
cass search "MRR snapshot" --robot --limit 15
```

If a session shows substantial prior work on a feature you're now adding, read that session in detail before drafting Phase 4. You may save days.

---

## Recipe 6 — Mine for cass capabilities you didn't know about

```bash
cass capabilities --json
cass robot-docs guide
```

cass evolves; new search filters may help.

---

## Recipe 7 — Mine prior scope decisions before widening the run

Run this before adding optional bundles, widening an `add-feature` request into `audit-and-fix`, or treating generic process work as part of the billing run. The goal is to find prior billing decisions that should make a bundle `required`, `included`, or `n/a`.

```bash
cass status --json > .billing_workspace/cass_status.json
cass capabilities --json > .billing_workspace/cass_capabilities.json

# Current-project billing scope decisions
cass search "we decided billing n/a Stripe PayPal teams usage marketplace tax compliance" --robot --days 365 --limit 30
cass search "phase0_scope_decision billing included skipped bundles" --robot --days 365 --limit 30
cass search "do not build billing feature out of scope" --robot --days 365 --limit 20

# Feature-specific decisions
cass search "team plans not planned billing" --robot --limit 20
cass search "no PayPal billing policy" --robot --limit 20
cass search "usage based billing deferred" --robot --limit 20
cass search "SOC2 billing evidence pack" --robot --limit 20
```

Distill findings into `.billing_workspace/phase0_scope_decision.md`:

```markdown
# Billing Scope Decisions From CASS

## Prior decisions found
- Decision: "No PayPal this quarter"
  - Evidence: <session path / result id>
  - Effect: mark PayPal-specific rows n/a for this run

## Optional bundle triggers found
- B80 Teams — activated by prior "team plans launch" session
- B120 Compliance — skipped; no audit window found

## Non-findings and caveats
- No marketplace/Connect sessions found. This is not proof of absence; current code still decides.
```

Feed these findings into `SCOPE-TRIAGE.md` and `OPERATING-MODES.md`. If orchestration itself is the bottleneck in a T4+ billing swarm, use `NTM-SWARM-ORCHESTRATION.md`; do not duplicate generic agent-management notes in the billing scope artifact.

---

## Output format

All mining produces a single artifact: `.billing_workspace/phase0_cass_mining_results.md`. Format:

```markdown
# CASS Mining Results

Generated: 2026-05-04T23:00:00Z
Project: <PROJECT_PATH>
Time window: --days 365
Total sessions reviewed: 47

## Themes (most informative findings)

### Theme A: Triple-charge attempts
- 3 prior sessions discussed this class.
- Session 1 (2025-11-15): user attempted a fix without the cross-provider probe. Fix is in commit `abc123` but missing the probe.
- Session 2 (2026-01-20): user added the integrity audit cron. Working.
- Session 3 (2026-04-02): another duplicate charge incident; postmortem says "we still don't have the customer-reuse step."

→ Phase 4 task: implement customer reuse in checkout (B30); add cross-provider probe (B30).

### Theme B: <next theme>

## Prompts to reuse
- "Implement Stripe webhook with 200-on-error" — worked well in session 2025-11-15; reuse for B40 implementer.
- "Add real-DB integration test for the refund handler" — worked well in session 2026-04-02; reuse for B60 test writer.

## Decisions already made (from prior sessions)
- Team plans NOT planned (per session 2025-09-10) → mark B80 patterns n/a.
- Resend is the email provider → already detected by discover-stack but cass confirms.
- Single Stripe account, no Connect → STRIPE_ACCOUNT_ID account-mismatch check is n/a.

## Recurring bug classes (signal for systemic fix)
- Class X: 4 occurrences in 12 months → propose a drift-guard.
```

---

## What NOT to do

- **Don't dump raw cass JSONL into the workspace.** It's noisy. Distill to themes.
- **Don't trust cass over current code.** A session from 6 months ago may discuss code that's been refactored. Always cross-reference with `git log` / current files.
- **Don't paraphrase user voice.** If the user said "we will NEVER do trials," capture that exactly — it's a policy commitment.
- **Don't search for secrets.** If a prior session discussed `STRIPE_SECRET_KEY` value, that's a leak; redact in your output.
- **Don't assume cass is comprehensive.** It only covers indexed sessions; offline / private work may not be there.

---

## Integration with the phase loop

| Phase | Use cass mining for |
|-------|---------------------|
| Phase 0 | Stack enrichment, decision discovery, theme extraction |
| Phase 1 | Bundle archaeology — surface prior known issues per bundle |
| Phase 3 | Risk scoring — recurring bug classes get higher severity |
| Phase 4 | Plan reuse — prior task structures that worked |
| Phase 7 | Fresh-eyes — search for "we tried this before; here's why it failed" |
| Phase 10 | Runbook authoring — prior incident threads that should be runbooks |
| T4+ Swarm kickoff | NTM/Codex/Claude failure modes, account limits, pane liveness, reservation conflicts |

---

## When cass is missing

Inline fallback: ask the user for:
- Their last 5 billing-incident postmortems (if they have postmortems).
- Their bead/issue history filtered by `billing` / `stripe` / `paypal` labels.
- Their support tickets filtered by `payment` / `subscription` / `refund`.
- Their git log filtered by `^(stripe|paypal|webhook|subscription|invoice|refund|dunning|mrr)` in commit messages.

These give you 80% of what cass would surface.
