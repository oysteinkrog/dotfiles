# Runbook: OUTAGE-COMMS

A production incident is happening. Customer comms is one part of the response. Goal: tell customers what they need to know, when they need to know it, without overcommitting.

## Trigger Conditions

- Status-page incident opened (statuspage.io / BetterStack / Instatus)
- Multiple inbound tickets reporting the same symptom in <30 minutes
- An on-call engineer says "we have an outage"
- A regional / provider-level event affects you (AWS / GCP / Vercel)
- A security incident requiring customer notification (separate from SECURITY-DISCLOSURE)

## The Three Audiences

Every outage update goes to three audiences with different needs:

1. **Customers actively affected** — need: am I in this? When fixed?
2. **Customers not affected** — need: should I worry? Status-page tells them.
3. **Internal / leadership / press** — need: what's the truthful, tightly-bounded summary?

## Status-Page Lifecycle

Standard four states (statuspage.io, Atlassian Statuspage, BetterStack, Instatus all share):

```
🔍 Investigating ─────► ⚠ Identified ─────► 🔧 Monitoring ─────► ✅ Resolved
```

**Investigating** — we know something's wrong; root cause unknown.
**Identified** — we know what's broken; deploying a fix or working with provider.
**Monitoring** — fix is live; watching to confirm.
**Resolved** — confirmed stable.

Don't skip stages. Customers calibrate expectations to where you are.

## First 15 Minutes (Initial Comms)

Open the status page incident WITHIN 15 MINUTES of detection. The cost of a false-positive incident is much lower than the cost of customers panicking with no signal.

### INITIAL-INVESTIGATING (status page)

```
Investigating: <symptom from customer perspective>

We're seeing <observable symptom, e.g., "elevated 5xx errors on the API">
since <timestamp>. We're investigating now; will update by <timestamp+30min>.

Affected: <best guess: e.g., "all customers on the EU region" or "TBD —
investigating">.
```

Tone notes:
- Short. No speculation about cause.
- Concrete time for next update.
- "Affected" can be "TBD" if you don't know yet.

### INITIAL-INTERNAL (Slack / war-room channel)

Different from public:

```
🚨 INCIDENT — sev-<1|2|3>

Symptom: <observable>
Detection: <how we noticed>
Customer impact: <best guess>
Owner: <eng-on-call>
Comms owner: <person>
War room: <link>

Status page: <link to incident>
```

## During The Incident

Update the status page every 30 minutes minimum, even if there's nothing new to report ("still investigating"). Silence is louder than acknowledgment of slow progress.

### INVESTIGATING-UPDATE

```
Update: still investigating. We've ruled out <X> and are looking at
<Y>. Customer-facing impact remains <symptom>.

Next update: <timestamp+30min>.
```

### IDENTIFIED-UPDATE

```
Identified: <one-sentence root cause, customer-friendly>.

Mitigation: <what we're doing>.
ETA to fix: <timestamp> (target).

Next update: <timestamp+30min>.
```

Customer-friendly cause = "a database failover didn't complete cleanly" not "k8s StatefulSet replica lag exceeded HPA threshold".

### MONITORING-UPDATE

```
Monitoring: fix deployed at <timestamp>. Initial signal looks healthy
(<one metric, e.g., "5xx rate back to baseline").

We'll continue monitoring for the next <window> before marking resolved.
```

### RESOLVED

```
Resolved: <symptom> recovered at <timestamp>. Total customer-facing impact
window: <duration>.

What happened: <2-3 sentences, customer-friendly>.

What we're doing to prevent recurrence: <one sentence; postmortem will
have detail>.

Sorry for the disruption. A full postmortem will be posted within <N>
business days.
```

## Replying To Inbound Tickets During An Outage

Customers will open tickets. Don't try to handle them individually until the incident is resolved — instead, mass-reply with a status-page link.

### OUTAGE-INBOUND-AUTO-ACK

```
We're aware of and actively investigating the issue you described. Live
updates: <status-page-URL>.

We'll close this ticket once the incident is resolved; if you still see
the problem after that, please reply and we'll investigate your
specific case.

Thanks for the report — it helps us measure scope.
```

Do NOT:
- Promise a personal follow-up to every ticket (won't scale)
- Reply with "we don't know yet, sorry" repeatedly (status page does this; tickets shouldn't)
- Apologize for things outside your control (provider outage)

### OUTAGE-INBOUND-AFTER-RESOLVED

For tickets opened during the outage that the customer has not closed themselves:

```
Update: the incident affecting <symptom> resolved at <timestamp>. Total
duration: <window>.

If you're still seeing the problem, please reply with details — the
incident was widespread and you may have been affected by a related
edge case.

If the problem is gone, no action needed; we'll close this ticket.
Postmortem at <link> in <N> business days.
```

## Postmortem (Within 5 Business Days)

A blameless postmortem is a customer-comms artifact AND an internal-improvement artifact.

### Public Postmortem Format

```markdown
# Incident: <symptom> — <date>

## Summary

<2-3 sentences>

## Timeline (UTC)

- HH:MM — <event>
- HH:MM — <event>
- ...

## Customer impact

- <region / segment / feature affected>
- <duration>
- <approximate # of users affected, if known>

## Root cause

<2-3 paragraphs, technical but accessible>

## What went well

- <thing>
- <thing>

## What didn't

- <thing>
- <thing>

## What we're doing

- [ ] <action item> — owner: <name> — by: <date>
- [ ] <action item> — owner: <name> — by: <date>

## Acknowledgments

Thanks to <names / customers> who reported and helped us debug.
```

Don't:
- Blame individuals
- Hide the root cause
- Promise unfundable preventive measures
- Skip the "what went well" section (it's not corporate filler — it's signal)

## Severity Guide

| Sev | Definition | Comms cadence |
|---|---|---|
| **Sev-1** | Production down for all users; data loss possible; security incident | Status page every 15 min; email to all affected within 1h; internal exec brief every 30 min |
| **Sev-2** | Significant subset down (region / feature); workaround possible | Status page every 30 min; postmortem within 5 days |
| **Sev-3** | Minor / single-feature; most customers unaffected | Status page open; postmortem only if pattern |
| **Sev-4** | Cosmetic / single-customer | Direct ticket reply; no status page |

## Direct Email To Affected Customers (Sev-1, Sev-2)

If the impact was substantial (e.g., data unreachable for >1h, security exposure), mass email is appropriate. Tone:

```
Subject: <project> — Incident affecting <thing> on <date>

Hi <name>,

We had an incident on <date> affecting <thing>. You may have noticed
<symptom>.

What happened: <2 sentences>.
What we did: <1 sentence>.
What you need to do: <usually nothing; if action needed, this is the time>.
What we're doing to prevent it: <1 sentence>.

Full postmortem: <link>.

Sorry for the disruption — and thank you for your patience.
```

Tone:
- "We" not "the team" — assume responsibility.
- Specific times, specific symptoms.
- No marketing speak.
- Sign with a real human (founder / VP eng), not "the team".

## Status-Page Comms Don'ts

| Don't | Why |
|---|---|
| Open the incident only after it's resolved | Customers needed signal during the outage |
| Use "all green" while support queue is 6h backed up | Status page should reflect customer experience, not just server uptime |
| Update status before war-room agrees | Public-private contradictions destroy trust |
| Use jargon ("503s", "HPA throttling") | Customers don't know what those mean |
| Skip "investigating" → straight to "identified" | If wrong, you re-traumatize the audience |
| Promise an ETA you'll miss | Better "we don't have an ETA yet; updating in 30 min" |
| Mark "resolved" when monitoring is still ongoing | Premature resolution = re-incident likelihood |

## Companion Refs

- [SECURITY-DISCLOSURE.md](SECURITY-DISCLOSURE.md) — for outages caused by security incidents
- [DATA-LOSS.md](DATA-LOSS.md) — for outages with corrupted/lost customer data
- [POST-INCIDENT-RETRO.md](../POST-INCIDENT-RETRO.md) — internal retro process
- [STATUS-PAGE.md](../STATUS-PAGE.md) — choosing + setting up a status page
