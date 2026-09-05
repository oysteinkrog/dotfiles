# Runbook: HOSTILE-USER

A user is abusive, harassing, threatening, or coordinating brigade attacks. Goal: protect your team's wellbeing, protect other customers, document for legal, and de-escalate when possible.

For L0-L2 conversations where there is still a real user problem to solve, use the `🪜 LADDER` operator and [TACTICAL-EMPATHY.md](../TACTICAL-EMPATHY.md). For L3+, the evidence/lock/escalation path below wins over conversational repair.

## Trigger Conditions (in escalating severity)

| Level | Behavior |
|---|---|
| **L0 — Frustrated** | Cursing in a ticket; venting. Not personal. |
| **L1 — Personal insults** | "You guys are idiots", "incompetent". Personal but not threatening. |
| **L2 — Pattern of abuse** | Multiple tickets, escalating tone; mocks individual agents by name. |
| **L3 — Targeted harassment** | Posts about specific agents on social media; finds their personal accounts. |
| **L4 — Threats** | Threats of physical violence, doxxing, "I know where you live", lawsuits-as-intimidation. |
| **L5 — Coordinated brigade** | Mob attack via social, multiple accounts pile on. |
| **L6 — Trust & safety** | Threats of violence, CSAM, terrorism, identity-based hate, regulator/press involvement. |

## Triage Decision

| Level | Action |
|---|---|
| L0 | Standard reply. Don't mirror tone; calm professional response. |
| L1 | Respond once professionally; if they repeat, see L2. |
| L2 | Single warning per [WARNING template]; document in customer record. |
| L3 | Lock the ticket; refuse further engagement until they apologize OR escalate to ban. |
| L4 | Permanent ban. Preserve all evidence. Notify counsel if specific threat. |
| L5 | Pause inbound from that vector; statement-of-no-engagement; document everything. |
| L6 | Trust & safety escalation; potentially law enforcement; counsel involved. |

## Evidence Preservation

Before acting at any level ≥ L2:

1. **Screenshot everything.** Browser screenshots > exports — hard to alter.
2. **Save raw messages with timestamps + IPs + user-agent.**
3. **Export from Discord/X/etc.** as JSON if possible.
4. **Note user metadata**: account ID, signup date, payment status, prior ticket history.
5. **Don't delete the offending messages** — preserve for at least 90 days, longer if law enforcement is possible.

## De-Escalation Templates

Before using any template, run the ladder check:

1. Is this a physical threat, doxxing, CSAM, terrorism/extremism, regulator/legal matter, or press inquiry? If yes, stop drafting and use `🛡 ESCALATE`.
2. Is the user angry but still trying to resolve a real issue? If yes, mirror/label once, then state the next action.
3. Is abuse repeated or targeted? Add the boundary; do not keep absorbing it.

### L0-RESPONSE — Frustrated User

Acknowledge feeling, address substance:
```
Sorry you're hitting friction with this. Let me dig in.

<substantive answer to their actual issue>

If you'd like to walk me through what you've tried, I'm here.
```

Don't:
- Match their tone ("understood, this is frustrating!")
- Apologize for things outside your control
- Promise more than you can deliver

### L1-RESPONSE — Personal Insults

Stay neutral, address substance:
```
<answer to the actual issue>

I'd rather we focus on solving your problem than the framing. Happy to
keep digging — what's the next step you want to try?
```

If they repeat the insults in their next message, escalate to L2.

### L2-WARNING — Pattern of Abuse

```
I want to keep helping you, but the tone of recent messages isn't
something we can engage with. Specifically: <one verbatim quote>.

If you can re-frame the issue without personal attacks, we're happy to
keep working on it. If the pattern continues, we'll have to pause your
account temporarily.
```

Document in their customer record: timestamp, summary, the specific quote.

### L3-LOCK / SUSPEND

```
This ticket is closed. We've paused your account access for <N> days.
You can still log in to view your data; you can't open new tickets or
interact with our team during the pause.

If you believe this is in error, reply to <appeals-email>. We'll review
within 5 business days.

We're not in a position to debate whether the pause is fair via this
ticket — that's what the appeal email is for.
```

Document: timestamp, the trigger message, the suspension duration, the appeal path.

### L4-PERMANENT BAN

```
Your account has been permanently terminated effective <DATE> for
violation of our Terms of Service (specifically: <clause>).

Your data export is available at <URL> for 30 days. After that, your
data will be deleted per our standard retention.

We will not engage further on this matter.
```

If they violated the law (threats, doxxing): consider law enforcement report. Counsel decides whether to prosecute.

## Brigade / Mass Attack Posture

When you're the target of a coordinated attack:

1. **Don't engage individually.** It feeds the cycle.
2. **One public statement.** Brief, calm, factual. No apology beyond "we hear you" if that fits; no defensive posture.
3. **Pause inbound from the vector.** If it's Twitter, mute notifications; if it's a forum, set tickets from that segment to manual review.
4. **Document everything** for potential later legal action.
5. **Support your team.** Take agents off the queue temporarily; they're under real attack, not just "difficult customers."

### BRIGADE-STATEMENT (one-time, public)

```
We've seen the criticism around <topic>. Here's what we know:

<2-3 sentences of fact>

We're <action being taken>. We'll have a longer update by <date>.

We won't be engaging individually with messages while we work through
this. If you have a specific question that's not part of the broader
conversation, please use <support channel> directly.
```

## Legal Triggers — When To Loop Counsel

- Specific physical threat ("I'll show up at your office")
- Doxxing of an employee (publishing home address, phone)
- Subpoena, DMCA, regulator letter
- Credible threat of class action
- Press inquiry about the user

For these, **stop replying** to the user and brief counsel within 24h. Counsel writes any further communication.

## Trust & Safety Escalation Path

If the project has T&S, hand off when:
- Threats of violence
- CSAM (immediate; report to NCMEC if US)
- Terrorism / coordinated extremism
- Identity-based hate at scale
- Election interference

If the project doesn't have T&S, the owner is T&S; brief them within the same business day.

## After-Action

For every L3+ incident:
- Customer record updated with severity, action taken, evidence pointer
- Internal team debrief; check on the agents who were involved
- If the user was banned, re-check the next time their email/IP shows up (block at signup)
- Aggregate metrics: count of L3+ incidents per quarter; trend = signal about product or community health

## Anti-Patterns

| Don't | Why |
|---|---|
| Mirror their tone | Escalates; un-professional |
| Get drawn into a public flame war | Always loses regardless of who's "right" |
| Apologize for things you didn't do | Creates a precedent + paper trail of admission |
| Reply at 11pm when angry | Sleep on it; email tomorrow with cooler head |
| Forget to document | Without evidence, you can't justify the ban if appealed |
| Ban without a documented warning trail | Appears arbitrary; legal exposure |
| Engage individually during a brigade | Multiplies exposure; team burns out |
| Take it personally | This is them, not you. Document and move on. |
| Refuse a legitimate appeal | If you can't show a clear pattern, lift the ban |

## Personal Wellbeing

This is the runbook category most likely to harm the agents who run it. Owner responsibilities:
- Rotate the queue; nobody handles hostile users for >2h continuously
- Sponsor mental-health support
- Acknowledge to the team that the agent did the right thing
- The user's anger is rarely about the agent personally
- If anybody on the team feels unsafe, the user goes to permanent ban regardless of "should we give one more chance"
