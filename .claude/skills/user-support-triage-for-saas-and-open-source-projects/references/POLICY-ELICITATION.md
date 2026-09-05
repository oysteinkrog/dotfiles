# Policy Elicitation (Onboarding Step 4)

The skill must never *assume* a policy. When the onboarding pass detects ambiguity, it surfaces a single batched prompt to the owner and waits for answers. Answers go into `<project>/.claude/support-triage/05-policies.md`.

## Why Batching Beats Per-Question Prompts

- Owners answer faster when they see the whole landscape
- Cross-question consistency surfaces (e.g. SLAs and refund windows are usually correlated)
- One round-trip vs N feels respectful of their time

## The Standard Batched Prompt

Adapt — only ask what wasn't already answered by code or existing docs.

```
🤔 ONBOARDING — POLICY DECISIONS NEEDED

I mapped your support surface but found ambiguity in these areas. Pick one
answer per item — happy to adjust later. We'll write your answers into
<project>/.claude/support-triage/05-policies.md so future sessions apply
them automatically.

═══════════════ 1. SLA TIERS ═══════════════
{{ if NO existing SLA in code }}
A) No SLA — best-effort responses
B) Single tier — {{ X }}h first response, {{ Y }}h resolution
C) Multi-tier — {{ enterprise / pro / individual }}, ranges shown below

   Common defaults:
                             First response   Resolution
     P0 (down/data loss)          1–4h             24h
     P1 (severe, blocking)        4–8h             48h
     P2 (normal)                 24h               72h
     P3 (low)                    48h              168h

═══════════════ 2. REFUND POLICY ═══════════════
A) Always refund within {{ N }} days of charge — no questions
B) Owner approves each refund — agent prepares, never executes
C) Decline refunds outside provider's automatic window
D) Pro-rated by usage   ({{ define formula }})

   Sub-questions:
   - Who can issue Stripe refunds?  {{ owner-only / any-admin }}
   - Cancel-and-refund vs cancel-only default?  {{ refund / cancel }}
   - Revoke access immediately or end-of-period?  {{ immediate / EOP }}

═══════════════ 3. ESCALATION PATHS ═══════════════
For each, who handles?
   - Security report (CVE, vuln)        →  {{ owner / security-team / private email }}
   - Billing disputes / chargebacks     →  {{ owner / finance / agent-with-approval }}
   - Hostile or abusive user            →  {{ lock-and-block / owner reviews / soft-decline }}
   - Legal / TOS violation              →  {{ owner / counsel }}
   - Outage / data loss                 →  {{ on-call rotation? }}

═══════════════ 4. STALE-CLOSE THRESHOLD (OSS Issues only) ═══════════════
A) Pre-2024 — close all
B) Pre-2025 — close all  (default)
C) ≥180 days no activity → close
D) Never auto-close

═══════════════ 5. PR ACCEPTANCE (OSS only) ═══════════════
A) Open to external PRs — review and merge if quality matches bar
B) Closed to external PRs — mine for ideas, close politely  (common for solo OSS)
C) Closed pending CLA  ({{ CLA URL }})

═══════════════ 6. FEATURE REQUESTS ═══════════════
A) Acknowledge + log to backlog (no commit)  (default)
B) Convert to {{ GitHub issue / Linear / beads }} for product planning
C) Discard after acknowledgement (we don't take feature requests through support)

═══════════════ 7. OUTBOUND VOICE ═══════════════
Default templates use a {{ warm / formal / terse }} register. Want anything
overridden? Sample lines from your existing replies that capture the voice
help — paste 3–5 if convenient.

═══════════════ 8. SEND-CONFIRMATION DEFAULT ═══════════════
A) Always show drafts before sending — we ask Y/n every time  (default)
B) Auto-send for low-stakes categories (REQUEST-INFO, COSMETIC, DUPLICATE),
   confirm only for billing/refund/code-bug
C) Auto-send everything (NOT RECOMMENDED — confidence-without-evidence risk)

═══════════════ 9. WORKING HOURS / TIMEZONE ═══════════════
SLA clocks run continuously by default (24/7). If you want business-hours-only:
   - Timezone: {{ TZ }}
   - Business hours: {{ start }} – {{ end }}, {{ days }}

═══════════════ 10. ANYTHING ELSE WE MISSED? ═══════════════
Free-form. E.g. "treat tickets from {{ enterprise customer }} as P0", or
"never reply Saturdays before 10am Pacific", or specific phrases to avoid.
```

## After Owner Answers

Write a clean `05-policies.md` with the answers. Include:

- Decision date
- Owner who confirmed (so future agents know whose call it was)
- Each answer in its final form
- Any caveats / edge cases the owner noted

```markdown
# Support Policies — <project>

Last reviewed: 2026-04-27 by <owner>.

## SLAs
- Tier: <single|multi|none>
- Deadlines: ...

## Refunds
- Default: <answer>
- Approver: <owner>
- Notes: ...

## Escalation Paths
- Security:  <handler> + <contact>
- Billing:   <handler>
- Hostile:   <playbook>
- ...

## Stale-Close (OSS)
- Cutoff: <date or "≥N days inactive">

## PR Policy (OSS)
- <accept | decline | CLA-required>

## Voice
- <register>
- Sample phrases the team uses: ...

## Send Confirmation
- <answer>

## Working Hours
- Timezone: <TZ>
- Hours: <range>  (or "24/7")

## Other Notes
- ...
```

Whenever a policy ambiguity surfaces during a future triage session, *re-run this prompt* (just for the missing dimensions) and update the file. Don't silently change policy.
