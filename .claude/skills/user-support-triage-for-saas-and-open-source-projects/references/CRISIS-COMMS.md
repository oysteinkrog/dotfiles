# Crisis Comms — When A Support Ticket Becomes A Media Event

Most tickets are private conversations. A small fraction become *public events* — viral X threads, HN front-page posts, news coverage, regulator inquiries. The discipline of crisis comms is not preventing these; it's making sure the response neither escalates them nor leaves real harm unaddressed. This file is the playbook.

> **Core insight:** in a crisis, the worst outcome is rarely "we said something imperfect." It is "we said nothing for 18 hours and then said something defensive." Speed of acknowledgement and discipline of message matter much more than eloquence.

This file extends `runbooks/HOSTILE-USER.md` (which handles individual hostility) and `runbooks/SECURITY-DISCLOSURE.md` (which handles embargoed cases). Crisis comms is what happens when the situation is *neither* embargoed *nor* private.

---

## The Five Crisis Shapes

Each has different optimal handling. Misclassifying them produces wrong responses.

| Shape | Trigger | First-hour priority |
|---|---|---|
| **Outage virality** | Mass downtime; users posting | Acknowledge on status page + product, fast |
| **Single-customer viral complaint** | One user posts; gets traction | Direct private contact + restrained public reply |
| **Bug-with-customer-impact-thread** | Someone documents a bug publicly with screenshots | Acknowledge specifically; ship the fix or workaround |
| **Press / journalist inquiry** | Reporter contacts via email / press@ / DM | Pause; loop in counsel + comms; do not freelance |
| **Regulator / legal inquiry** | Official letter or regulator email | Pause; counsel-led; nothing said publicly without coordination |

The five differ in *audience size and intent*. Outage virality is many customers wanting reassurance. Press inquiry is one journalist wanting a story. Regulator inquiry is the state wanting an answer. Treating any one as if it were another is a high-magnitude mistake.

---

## The 60/240/24 Cadence (Outage Virality)

For mass-event outages with public posting, the cadence is unforgiving:

```
T+0       Incident detected
T+15min   Initial status page post: "we're seeing X; investigating; next update in 15"
T+30min   Second update: scope (auth subsystem? API? specific endpoints?)
T+60min   Third update: cause direction (deploy? upstream? infra?)
T+240min  Fourth update or resolution
T+24h     Postmortem published (or "postmortem in progress; expected by [date]")
```

What matters is *cadence consistency* — even an "no new info; next update in 30 min" beats silence. Customers tolerate slow recovery; they do not tolerate being left in the dark.

The status page and an in-product banner share the same content; they should never disagree. An in-product green-light during a known outage is one of the worst trust withdrawals possible.

---

## The Holding Statement

For shapes 2-5, you almost always need to say *something* fast even before you have the full picture. The holding statement is for that.

```
HOLDING STATEMENT TEMPLATE (calibrate per shape)

We saw [public mention / report / inquiry] regarding [specific issue]
and we're looking into it now. We'll have more to share by [time —
hours not days]. If you're affected, contact [direct path].
```

A holding statement *says specifically what you saw* (not generic), *commits to a follow-up time* (not vague), and *gives affected people a direct path* (not the general queue). The most common failure is the bland version: "We've seen reports and are investigating. We take this seriously. We'll share more soon." This says nothing and reads as legal-templated. Customers and journalists both notice.

For each shape, the holding statement adapts:

### Single-customer viral complaint

> "Saw [specific tweet / post]. We're contacting [name] directly; we'll share what we find publicly with their permission. If anyone else has hit the same thing, contact me directly: [name]@[company]"

### Bug-with-customer-impact-thread

> "[Person] reported [specific bug] yesterday — confirming this is real, not user error. We have a workaround documented at [link]; permanent fix is shipping today/by [date]. If you've been affected, [credit/refund/contact path]."

### Press inquiry

> "We received your inquiry about [specific question] at [time]. Our [comms-lead] will get back with a substantive answer by [day]. If you're on deadline before then, [name] is your contact."

### Regulator / legal

> Almost always *no public statement*. The acknowledgement goes privately to the regulator/lawyer; counsel coordinates timing of any public follow-up.

---

## The Single-Customer Viral Pattern

Most "viral complaints" are one customer with a real issue posting publicly. Two failure modes to avoid:

### Failure mode: defensive public reply

```
WRONG (real reply patterns to avoid):
"Hi @user, sorry you had this experience. Our records show that
your account is in good standing and the issue you mention has
been resolved. Please DM us if you have further concerns."

Why wrong:
- "Sorry you had this experience" reads as not believing them
- "Our records show" weaponises asymmetric data
- "Has been resolved" without acknowledging what was wrong
- Sends them back to the queue they already tried
```

### Failure mode: over-correction in public

```
WRONG (over-share):
"Hi @user, you're absolutely right and we're so sorry. We've
issued a full refund and given you 6 months free and our CEO
will personally call you. Anyone else affected, please let us
know and we'll do the same."

Why wrong:
- Trains customers that public posting > private reporting
- Anchors the compensation level publicly for future cases
- Reads as PR-driven, not customer-driven
```

### Right: separate public and private

```
PUBLIC (short, restrained):
"Saw this — that's a real problem and we should not have
shipped it that way. I'm DM'ing you now to fix it. Replying
publicly so anyone else hitting the same thing knows we know."

PRIVATE (real handling):
[Standard pipeline B/C — refund, root-cause, named contact,
COMPENSATION-CALCULUS-banded compensation, the works]

PUBLIC FOLLOW-UP (after resolution, with permission):
"Update on [name]'s issue: rooted in [one-line cause]; refund
done; structural fix shipping [date]. Thanks for the report."
```

The split keeps public statements short and honest, while private handling can be expensive and bespoke. Public over-corrections create incentive problems for future cases; private over-corrections do not.

---

## Press And Journalist Inquiries

A reporter contacting you is a Tier-4 action ([AI-AUTO-RESPONSE-GOVERNANCE.md](AI-AUTO-RESPONSE-GOVERNANCE.md)) — never agent-led, never freelanced.

### The discipline

1. **Acknowledge receipt within 4 hours** even if substantive answer is days away. Silence is its own story.
2. **Loop in legal/comms before substance.** A response that's defensible internally is much harder than a response that sounds good.
3. **Stay in writing.** Phone calls feel friendly but produce quotes you can't see in advance. Default to email/written.
4. **One spokesperson.** Rotating responders create contradictions.
5. **Stay on the question they asked.** "What I think you're really asking about is..." is a rhetorical trap; answer the actual question or decline to answer specific parts.
6. **Don't speculate.** "We don't have that information yet" is fine. "I think it might be..." is dangerous.
7. **Follow up after publication.** If the article gets it wrong, polite correction goes to the reporter, not the comments. If it gets it right, a thank-you preserves the relationship for next time.

### The wrong answers

- "No comment." Reads as guilt; almost never the right move.
- Answer-by-deflection. ("Well, what about X?") Reporters do not appreciate dodge-and-pivot.
- Off-the-record after the fact. Doesn't work.
- Multi-paragraph defensive narrative. The journalist's space for your reply is finite; long answers get edited unfavourably.

### The right answers

- "Here's what happened, in order." Then *short*, *specific*, *factual*.
- "We're confirming X, can't speak to Y yet, will follow up by [date]." Honest about what you don't know.
- "Yes" or "no" when those are the actual answers, with one supporting sentence.

---

## Regulator / Legal

For inquiries from a regulator or a legal counterparty:

- **Pause everything else customer-facing on this topic.** Public statements while a regulator inquiry is open are routinely cited.
- **Counsel-led from the first response.** Even the acknowledgement is reviewed.
- **Document everything.** Every internal message, draft, decision, and meeting on the topic is potentially discoverable.
- **Preserve evidence.** Use [SUPPORT-EVIDENCE-ARTIFACTS.md](SUPPORT-EVIDENCE-ARTIFACTS.md) for evidence packs, approvals, sends, verification records, and restricted-access handoffs.
- **Limit access.** The fewer people see the inquiry, the cleaner the privilege story.
- **No internal Slack venting.** Logs persist; emotional commentary on a regulator inquiry is the worst kind of discovery.

The triage skill's role here is *only* to recognize the shape, escalate immediately to owner + counsel, and stop drafting customer-facing replies on related topics until cleared. Pipeline U (compliance / regulated industry) handles this explicitly.

---

## The "Don't Make It Worse" Rules

Cumulative wisdom from public crisis-comms case studies. These are negative rules — what *not* to do.

| Don't | Why |
|---|---|
| Don't delete posts | Always discovered; deletion becomes the story |
| Don't argue in replies | Each reply is a new tweet a journalist quotes |
| Don't ban / mute the original poster | Confirms helplessness narrative |
| Don't reply with another company's name as comparison | Cross-PR risk; reads as petty |
| Don't quote your own marketing copy | Tone-deaf in a crisis |
| Don't announce internal restructuring as the response | Customers don't care about your org chart |
| Don't promise things you can't deliver in the timeline implied | Adds another crisis at the deadline |
| Don't use legal language in public unless legally required | "We strongly contest" reads worse than "we don't agree, here's why" |
| Don't go silent assuming it'll blow over | The 18-hour gap becomes the story |
| Don't reach out to influencers to defend you | Astroturfing is recognized and amplifies |

---

## After The Crisis

Once the immediate event resolves, three follow-ups matter:

### The postmortem

Public, written, factual, structural. Format:

```
1. What happened (timeline; specific times; specific systems)
2. Customer impact (counts, durations, what specifically broke)
3. Root cause (technical, plain language)
4. What we did to fix the immediate issue
5. What we're changing structurally so it can't recur
6. Compensation given (if applicable)
7. Open questions / things we're still investigating
```

A good postmortem creates *more* trust than the absence of the incident would have. A bad one (vague, defensive, blame-shifting) creates less trust than the incident itself.

### The personal follow-up

Affected customers get a personal email — not the postmortem alone. Format from `PROACTIVE-SUPPORT.md` incident-driven outreach.

### The internal retro

Per `POST-INCIDENT-RETRO.md`, the team's own retrospective. Add a comms-specific layer:
- *Did our holding statement go out within target time?*
- *Did our cadence hold?*
- *Did we contradict ourselves between status page / X / direct customer reply?*
- *Did we go off-script under pressure?*
- *What's a structural change in the comms playbook?*

---

## How This File Plugs In

| Used by | How |
|---|---|
| 🛡 ESCALATE operator | Crisis-shape recognition |
| 🪧 BROADCAST operator | Status-page + product banner discipline |
| Pipeline E (Outage) | Imports cadence rules |
| Pipeline T (Press inquiry) | Imports journalist patterns |
| Pipeline U (Compliance / regulator) | Imports legal-led patterns |
| 05-policies.md | Project's named comms-lead and counsel |
| HOSTILE-USER.md | Single-customer viral cases |

---

## Cross-References

- [runbooks/HOSTILE-USER.md](runbooks/HOSTILE-USER.md) — individual hostile cases
- [runbooks/SECURITY-DISCLOSURE.md](runbooks/SECURITY-DISCLOSURE.md) — embargoed cases
- [runbooks/OUTAGE-COMMS.md](runbooks/OUTAGE-COMMS.md) — outage-specific
- [PROACTIVE-SUPPORT.md](PROACTIVE-SUPPORT.md) — affected-customer follow-up
- [SUPPORT-EVIDENCE-ARTIFACTS.md](SUPPORT-EVIDENCE-ARTIFACTS.md) — evidence packs, approvals, sends, verification records
- [POST-INCIDENT-RETRO.md](POST-INCIDENT-RETRO.md) — internal retro template
- [STATUS-PAGE.md](STATUS-PAGE.md) — status-page mechanics
- [AI-AUTO-RESPONSE-GOVERNANCE.md](AI-AUTO-RESPONSE-GOVERNANCE.md) §T4
