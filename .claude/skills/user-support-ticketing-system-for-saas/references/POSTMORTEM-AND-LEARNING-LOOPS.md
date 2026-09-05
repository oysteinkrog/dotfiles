# Postmortem And Learning Loops

Bad outcomes are inevitable; institutional learning from them isn't. The support system holds the *lived experience* of every customer-affecting failure — the trick is turning that experience into durable improvements rather than letting it dissipate.

This file is the methodology for postmortems specific to support, plus the systemic learning loops that compound them over time.

## What Triggers A Postmortem

Per-trigger, decide BEFORE the heat of the moment:

| Trigger | Postmortem? | Owner |
|---|---|---|
| SLA breach on enterprise P0 | Always | Support lead |
| ≥5 tickets clustered around the same root cause | Always | Engineering + support |
| Customer-visible privacy / billing leak | Always (legal-coordinated) | Owner + legal |
| Reopen rate > 10% on a category in a week | Always | Support lead |
| CSAT score ≤ 2 (out of 5) | Recommended | Assigned admin's lead |
| AI-assist produced incorrect customer-visible output | Always | AI feature owner |
| Cron failed silently > 30 min | Always | SRE / platform |
| Fewer than expected N? Nope | n/a | "Quiet" is rarely a mystery to investigate |

The bar should be low for triggering a postmortem; the bar should be high for skipping one.

## Blameless Framing

The first sentence of every postmortem template:

> *This is a blameless postmortem. We assume everyone involved acted reasonably given the information they had at the time. Our goal is to find the systemic gaps that allowed this to happen, not to assign individual fault.*

This isn't a polite fiction. The system that allowed the gap is what we're investigating. Naming individuals as "the cause" hides the systemic fix.

## The Template (Six Sections)

```
# Postmortem: <Short Descriptive Title>

**Date:** YYYY-MM-DD
**Authors:** <names>
**Status:** Draft | In Review | Final

---

## 1. Summary
Two-paragraph executive summary. What happened, who was affected,
how long it lasted, what the customer-facing impact was.

## 2. Timeline
Minute-by-minute reconstruction. Format: `HH:MM (UTC) - what happened`.
Include: when the issue started, when it was detected, when each
mitigation step happened, when it was fully resolved.

## 3. Root Cause
What underlying condition allowed this to happen? Use Five Whys
to drive past the surface symptom. Include code links, schema
references, configuration values.

## 4. Customer Impact
- Number of tickets created as a direct result
- Customers affected by name/segment
- Revenue at risk / refunds issued / contractual SLA breaches
- Trust impact (CSAT drop, public posts)

## 5. What Went Well
- Detection mechanism that caught it
- Response steps that worked smoothly
- Communication that landed correctly

## 6. Action Items
| # | Owner | Due | Description | Status |
|---|---|---|---|---|
| 1 | @alice | 2026-05-15 | Add cron heartbeat alert | Open |
| 2 | @bob | 2026-05-08 | Update runbook for X | Done |
```

Action items are **assigned, dated, and tracked**. Open items at the next monthly support review are escalated.

## Five Whys Drilling

Surface symptoms are rarely root causes. Drill:

```
Symptom: 47-hour SLA breach on enterprise P0 ticket.

Why? - Cron didn't fire SLA alert.
  Why? - Slack webhook timeout had no retry; cron crashed on first failure.
    Why? - We added the webhook last quarter without a retry policy.
      Why? - Webhook code copy-pasted from an internal-only example.
        Why? - We don't have a "before adding outbound HTTP" checklist.
```

Root cause: missing engineering checklist, not "the cron failed." Action item: write the checklist + apply to existing outbound HTTP.

## Specific Postmortem Patterns For Support

### Pattern 1 — The Slow-Cluster Postmortem

5+ tickets came in over 4 hours with the same underlying cause; we didn't notice until customer #6 escalated.

Investigate:
- Was the cluster detection cron running? When did it last fire?
- What was the similarity threshold? Did the tickets pass it?
- Was the alert delivered? To whom? Did they see it?
- How quickly after detection did the team take action?

Common root causes:
- Cluster detection threshold too high (didn't catch related but not-identical tickets)
- Alert went to a Slack channel nobody watches at that hour
- Detection detected, but no one ack'd; no escalation chain

### Pattern 2 — The Reply-To-Wrong-Customer Postmortem

Admin's reply went to the wrong customer (cross-thread mistake or mis-reassignment).

Investigate:
- What confirmation modal copy preceded the send? Did it show recipient?
- How did the wrong-recipient state arise (multi-tab confusion, URL-state desync)?
- What server-side validation could have caught it (e.g. ticket-id binding to active session)?

Common root causes:
- Confirmation modal didn't show explicit recipient name + email
- Multi-tab session state contamination
- Server trusted URL params alone

### Pattern 3 — The Silent-Diagnose Postmortem

Admin noted internally that they fixed an issue, but the customer never received the resolution email.

Investigate:
- Where in the codepath did the email-send fail? Network? Provider error? Wrong wire-up?
- Did the side-effect log capture the failure?
- How long was the gap between admin action and customer realization?

Common root causes:
- Email-send try-catch swallowed the error silently
- `after()` was used outside request scope; fallback didn't fire
- Fix path didn't go through the canonical mutation API

### Pattern 4 — The Refund-Misfire Postmortem

A refund was issued twice (or not at all when the UI claimed success).

Investigate:
- Was idempotency key used?
- Did the read-after-write verification run?
- What happened to the audit log entry?

Common root causes:
- Refund button without idempotency key → retry double-charged
- Stripe error swallowed → audit said "issued" but Stripe disagrees
- Customer hit "Refund" twice in 100ms → race condition

### Pattern 5 — The CSAT-Plummet Postmortem

A specific category's CSAT fell from 4.2 to 3.1 in a week.

Investigate:
- What changed? New admin? New macro? New UI? New product release?
- Sample 20 low-CSAT tickets; categorize the customer-perceived issues
- Did response-time SLA change? Reopen rate?

Common root causes:
- New admin not onboarded; reps using outdated macros
- A product release introduced a confusing flow; tickets surge with similar shape; macros don't fit
- An internal policy tightened (e.g. refund authority) without external messaging

## The Five Postmortem-Driven Loops

### Loop 1 — Action Items Land

Every action item from a postmortem creates a tracked engineering issue (Linear / GitHub / Jira). Linked back to the postmortem doc. Reviewed in next month's all-hands; un-shipped items get a re-up date.

### Loop 2 — Pattern Recognition Across Postmortems

Quarterly: aggregate root causes from all postmortems. Identify recurring categories ("cron silent failures: 4 in past quarter").

```
ROOT CAUSE TAXONOMY (last 90d, n=12 postmortems)
─────────────────────────────────────────────
- Silent failure on side effects (n=4) ⬅ recurring
- Missing audit row (n=2)
- Cluster detection lag (n=2)
- Refund idempotency gap (n=1)
- Email template error (n=1)
- Other (n=2)
```

The "n=4" is the systemic gap to invest in. Engineering allocates a quarter's worth of time fixing the root rather than the four leaves.

### Loop 3 — Runbook Updates

Every postmortem produces or updates a runbook entry. Future similar incidents → faster response. The runbook lives in [DIAGNOSTICS.md](DIAGNOSTICS.md) (or a project-specific extension).

### Loop 4 — Test Coverage

Bugs become tests. Every root-cause fix has:
- A unit / integration / E2E test that fails before the fix
- The test stays in CI forever; regressions caught immediately

### Loop 5 — Customer Communication

For high-impact incidents, share the postmortem (sanitized) with affected customers. Builds trust faster than silence. Template:

```
Subject: Update on [incident name]

Hi [name],

On [date] you may have experienced [impact]. We've investigated, fixed
the underlying issue, and want to share what happened and what we're
doing differently.

What happened:
[2-3 sentences in plain language]

What we're changing:
- [action item 1]
- [action item 2]

We're sorry for the disruption. If you have questions or need
additional info, reply to this message.

Thanks,
[support lead name]
```

Customer-facing version is always reviewed by support lead AND owner before sending. AI-drafted is a starting point; humans calibrate tone.

## CSAT-To-Coaching Loop

Low-CSAT tickets feed coaching:

```
For each CSAT ≤ 2 received this week:
  - Pull the conversation
  - Read the customer's specific complaint
  - Identify: was the problem tone? speed? accuracy? feature-gap?
  - If admin-attributable: coaching note for assigned admin (private)
  - If product-attributable: feature request to product
  - If process-attributable: postmortem candidate
```

Coaching notes are private (admin + their lead). Aggregated patterns may surface in team-wide training.

## The Postmortem Library

Every postmortem document persists. Searchable. Templated. New admins read the past 10 to onboard their judgment.

Storage: a `postmortems/` directory in the support handoff; or a Notion / wiki page. Index by:
- Date
- Trigger type
- Affected category
- Root cause taxonomy

## Customer-Visible Postmortem Communication Patterns

### "Premature Reassurance" Trap

Don't communicate before the postmortem reaches "Final." Premature "we've fixed it" before root cause is understood backfires when the next case proves you didn't.

### "Clinical" vs "Empathetic" Voice

Postmortems use clinical voice for engineers; customer-facing summaries use empathetic voice. Translate:

- ❌ Engineering: "The webhook handler did not implement exponential backoff retry, leading to a permanent failure on transient network errors."
- ✅ Customer: "The system that sends you updates didn't handle a temporary network glitch the way it should have. We've updated it to retry automatically."

## Anti-Patterns

| ✗ | Why |
|---|---|
| Postmortem with no action items | Performative; nothing changes |
| Action items without owners or dates | Diffuse responsibility; never done |
| Naming individuals as "the cause" | Drives blame culture; people hide future incidents |
| "Lessons learned" as the only output | No tracked changes; pattern repeats |
| Postmortem doc nobody reads | Process theater |
| Skipping postmortems for "small" customer-impact incidents | Pattern recognition impossible without quantity |
| Engineering-only postmortems on customer-facing failures | Misses customer-experience root causes |
| Customer-facing communication using engineering voice | Customer feels confused, not informed |
| No quarterly aggregation | Recurring root causes invisible |
| CSAT-feedback never reaching individual admins | Coaching loop broken |
| Postmortem reviewed weeks late | Action items stale; momentum lost |

## Wire Points Checklist

- [ ] Trigger criteria documented + agreed before incidents
- [ ] Postmortem template with six standard sections
- [ ] Blameless framing in every doc
- [ ] Five-whys drill on every postmortem
- [ ] Action items tracked in engineering tracker, linked back
- [ ] Quarterly root-cause aggregation produces investment recommendations
- [ ] Every fix has a test that would have caught it
- [ ] Runbook updates per postmortem ([DIAGNOSTICS.md](DIAGNOSTICS.md) extensions)
- [ ] Customer-facing communication template + review gate
- [ ] CSAT-to-coaching loop runs weekly
- [ ] Postmortem library searchable by trigger / category / root cause
- [ ] New-admin onboarding includes reading recent postmortems
- [ ] Action-item review at monthly all-hands; escalation for un-shipped items
- [ ] Storage in `postmortems/` (handoff dir) or wiki
