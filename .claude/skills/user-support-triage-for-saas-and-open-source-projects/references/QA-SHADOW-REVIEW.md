# QA Shadow Review — Support Quality Without Queue Theater

Support quality cannot be inferred from "tickets closed." The work has to be
sampled, replayed, and coached. Shadow review is the lightweight discipline for
doing that without turning every reply into bureaucracy.

Use this when:

- the project has multiple support agents or tiers;
- owner edits on draft bundles keep finding the same mistakes;
- an auto-suggest or macro system is being introduced;
- high-risk categories need periodic proof that runbooks still work;
- customers are not complaining, but metrics suggest hidden effort or churn.

## Review Modes

| Mode | When | Sample | Reviewer |
|---|---|---:|---|
| Launch calibration | first two weeks of a new support system | 20-50% of replies | owner or support lead |
| Routine shadow review | stable queue | 5-10% random + all high-risk | senior support |
| New-agent review | onboarding / probation | 100% before send, then 20% async | assigned mentor |
| Incident retro review | outage / privacy / billing mistake | 100% of linked tickets | owner + incident lead |
| AI-assist review | model suggestions enabled | accepted, rejected, heavily edited samples | AI feature owner |

Do not let the reviewer only see "easy wins." Include no-reply closures,
internal notes, escalations, requests for information, refunds, and reopened
tickets.

## The Review Card

For each sampled ticket, write a compact review card:

```markdown
# Shadow Review - <ticket id>

- Reviewer:
- Agent:
- Category:
- Risk tier:
- Customer-visible send: yes/no
- Owner approval required: yes/no
- Owner approval captured: yes/no/not-needed

## Scores

| Dimension | Score | Evidence |
|---|---:|---|
| Orientation | 0-2 | Did the agent identify requester, channel, age, tier/segment, and risk? |
| Evidence | 0-2 | Did the reply/action cite actual logs, code, provider ids, or policy? |
| Policy fit | 0-2 | Did the action match 03-decision-matrix.md and 05-policies.md? |
| Voice/accessibility | 0-2 | Was the reply clear, human, locale/accessibility aware, and de-slopified? |
| Outcome loop | 0-2 | Did the session create KB/product/bug/loopback follow-up when warranted? |

## Notes

- What worked:
- What to coach:
- Runbook/template/policy update needed:
```

A perfect review is 10/10. Anything <=6 gets a coaching note. Any
confirmation-gate miss, privacy leak, unauthorized refund/credit, security
misroute, or crisis mishandling is a process incident even if the customer was
happy.

## Reviewer Checklist

- [ ] Read the full original inbound, not just the agent summary.
- [ ] Check whether the ticket had hidden high-risk signals: money, access,
      security, privacy, legal, public reputation, crisis, minors, abuse.
- [ ] Verify the chosen operator/runbook matches the signal.
- [ ] Verify evidence was real and current.
- [ ] Verify customer-visible text went through owner approval when required.
- [ ] Verify internal notes did not leak customer-visible assumptions.
- [ ] Verify the outcome record captured a value loop or explicit non-accretive
      disposition.
- [ ] If the same correction appears 3 times, propose a runbook/template update
      instead of only coaching individuals.

## Anti-Gaming Rules

- Random samples are chosen before agents know which tickets will be reviewed.
- High-risk categories are always eligible, even if "resolved."
- Closed-unresolved and reopened tickets are oversampled.
- Reviews score the system and the template, not just the individual.
- Reviewer feedback must include one concrete next behavior, not vague
  "improve empathy" or "be more careful."

## How It Plugs In

- [MULTI-TIER-SUPPORT-ORG.md](MULTI-TIER-SUPPORT-ORG.md) uses this for
  cross-tier calibration.
- [TRIAGE-SCOREBOARD.md](TRIAGE-SCOREBOARD.md) should track owner-edit rate,
  review rejection rate, and confirmation-gate violations.
- [POST-SEND-OUTCOME.md](POST-SEND-OUTCOME.md) is where repeated review themes
  become project improvements.
- The ticketing-system-side version (`AGENT-ONBOARDING-AND-COACHING.md` in
  `/user-support-ticketing-system-for-saas`) covers productized review queues.
