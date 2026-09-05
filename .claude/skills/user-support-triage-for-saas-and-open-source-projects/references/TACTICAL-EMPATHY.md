# Tactical Empathy — Operationalized Conversational Patterns

`COMMUNICATION-CRAFT.md` provides templates for apologies, declines, and uncertainty. `CUSTOMER-PSYCHOLOGY.md` explains *why* certain phrasings work. This file is the *operator manual*: the small set of conversational moves, drawn from negotiation and clinical interviewing literature, that actually shift a difficult support conversation.

> **Core mechanic:** humans rarely change their position because of new information. They change position when they feel heard *first*, then can think clearly *second*. Tactical empathy is the discipline of doing those two steps in that order, deliberately, in writing.

These are not "tricks." They are observable, replicable patterns that work because they align with how people process social threat. Used dishonestly they read as manipulation. Used honestly they read as good support.

Use them only with a customer-benefiting intent: to understand, reduce effort, and make the next action legible. Do not use tactical empathy to pressure a customer into accepting an unfair policy, waive a right, ignore a security/legal issue, or stay in an unsafe conversation.

---

## The Five Moves

| Move | When | What it does | Operator that uses it |
|---|---|---|---|
| **Mirror** | Customer's last sentence is loaded / ambiguous / hostile | Buys time; signals listening; produces more info | 🪄 EMPATHIZE |
| **Label** | You can name the emotion or situation underneath | Defuses amygdala; produces "yes, exactly" | 🪄 EMPATHIZE |
| **Accusation Audit** | Customer is about to / already accused you of something | Pre-empts the worst frame; opens space for facts | 🪜 LADDER |
| **Calibrated Question** | Need information AND don't want to feel like an interrogation | Customer feels in control; you get the data | 🚦 PAUSE-SLA, ✉ DRAFT |
| **Strategic No** | Customer offered an unworkable solution | Lets them say "no" first; preserves dignity | ⚖ DECIDE, refund-decline |

---

## 1. Mirror

A mirror is a 1–3 word echo of the customer's last clause, often as a question. In writing it looks like restating the last part of their sentence with curiosity.

**Example** — customer writes:
> "I've been waiting EIGHT DAYS for a refund and nobody is doing anything!!!"

**Bad reply** (rushes to defend):
> "Hi, refunds typically take 5-10 business days, so you're still within window..."

**Mirror reply**:
> "Eight days, with no movement on it — that's not what we promised. Let me look at the refund right now and write back with the actual status, not a policy quote."

The mirror is *"eight days, with no movement on it"*. It signals: I read your message, I heard the time and the frustration, and I am not going to argue with the framing. Then it pivots to action.

**Format**:
```
[1-clause mirror of their words]  +  [your action, specific, named]
```

**Don'ts**:
- Don't mirror a slur or insult — that escalates.
- Don't add "I'm sorry to hear" before the mirror — it dilutes the listening signal.
- Don't mirror twice in one reply. One is calibration; two is parody.

---

## 2. Label

A label *names what's happening underneath* without claiming to share it. Format:

```
"It seems like..." OR "It sounds like..." OR "It looks like..."
  + [the situation, not the emotion-word]
  + [factual continuation]
```

**Wrong** (uses emotion word, makes a claim):
> "I can see how frustrated you are."

**Right** (labels the *situation*):
> "It looks like this is the third reply about the same bug, which is two more than you should have needed."

**Why it works**: the customer reads it and goes "*yes — finally — somebody noticed*." Their nervous system relaxes a notch and the next paragraph of your reply becomes legible to them. Without a label, even a correct fix can feel like another transactional reply.

**Calibration table**:

| Situation | Label |
|---|---|
| Repeated bug report | "Looks like this is the second time the same thing has come back. That's a different problem than the first one." |
| Refund delayed | "It seems like the refund timing has been the actual frustration here, not the original charge." |
| Feature decline | "It sounds like this would unblock something concrete on your side, not just be nice-to-have." |
| Hostile, escalating | "It looks like the previous reply read as a brush-off, even though it was meant as an answer." |
| Identity-threatened user (engineer) | "It looks like the support reply earlier conflated SSL with TLS, which is the kind of detail you were specifically trying to avoid." |

The label is a hypothesis, not a verdict. If the customer corrects it, that's *useful* — they're now telling you what was actually wrong, which is exactly what you wanted.

---

## 3. Accusation Audit

If you can predict the worst thing the customer is going to think about your team, *say it first, in the lightest weight possible*. This pre-empts the frame.

**Pattern**:
```
"You're probably looking at this and thinking [worst frame]. Fair —
here's the actual situation: [facts]."
```

**Example** — refund delay because of an internal mistake:
> "If you're looking at this and thinking 'they lost my refund and now they're stalling,' I get why. Here's what actually happened: the refund was processed on the 12th but routed to a closed merchant ID. We caught it this morning. New refund issued just now; settlement should be 1-2 business days. You'll see two pending and one cleared on your statement."

The accusation audit takes the customer's worst thought, names it without flinching, and then walks past it with facts. The reply *cannot* be answered with "yes, you're stalling," because you've already conceded the appearance and shown the work.

**Don'ts**:
- Don't audit something the customer hasn't already implied — that's planting an accusation.
- Don't audit and then *defend*. The audit only works if the next paragraph is facts, not justifications.
- Don't audit and then ask for sympathy. ("I know this looks bad — please understand, my team has been overwhelmed...") That puts your burden on the customer, which is exactly backwards.

---

## 4. Calibrated Questions ("How / What" not "Why / Could")

When you need information from the customer, the question form determines whether they cooperate or stiffen. Calibrated questions are open-ended, framed as *how* or *what*, and require the customer to think through the situation rather than defend it.

| Don't ask | Do ask |
|---|---|
| "Why did you do that?" | "What were you trying to accomplish when this happened?" |
| "Could you send me the logs?" | "What information do you have from the failure that I could look at?" |
| "Did you try restarting?" | "What have you tried so far so I don't repeat what you did?" |
| "Are you using the latest version?" | "What version are you on, and how did you install it?" |
| "Why didn't you contact us sooner?" | "What was the situation that finally pushed you to write in?" |

**Why it works**: "Why" questions implicitly require justification, which feels like accusation. "How" / "What" questions ask the customer to describe a situation, which is much easier to answer truthfully and fully.

For 🚦 PAUSE-SLA replies (need user data to advance), use calibrated questions throughout the numbered ask. The reply gets shorter, the response rate goes up, and the answer is more useful.

---

## 5. Strategic No (Letting The Customer Say No First)

When you need to decline a request *and* keep the relationship, the cleanest path is sometimes to invite the customer to *say no* before you do.

**Example** — customer asks for a custom integration that's not on roadmap:
> "Quick question before I write something formal — would it be a deal-breaker if we built this as a webhook + your Zap rather than a native integration? It's not as polished, but you could be live in a week instead of waiting for the Q3 release."

If the customer says "yes, native or nothing," you've discovered the actual constraint and can decline cleanly. If they say "actually, webhook is fine," you've avoided the decline entirely.

The strategic-no pattern works for: feature requests with a partial-fit alternative, refund cases where a credit might satisfy, decline of a custom contract clause where a different clause would work, escalation requests where a written report might satisfy a "manager" demand.

---

## Composing The Five Moves: The Three-Layer Reply

The strongest hostile-de-escalation reply uses, in order:

```
1. ACCUSATION AUDIT  — name the worst frame, lightly
2. LABEL             — name what's actually happening
3. FACT + ACTION     — what's true and what you're doing about it
```

Optional fourth layer for paid / enterprise: a calibrated question to confirm the action solves their actual problem, not just the stated one.

**Worked example** — customer post on X: "@yourcompany has been GHOSTING me for 2 weeks. PAYING customer. Absolute SCAM."

Three-layer DM reply:
```
You're looking at two weeks of silence from a paying account and that
reads as deliberate. Fair conclusion from outside.       <- audit

What actually happened: the original ticket landed in a queue we'd
muted for spam during a deploy, and it never got reassigned. That's
on us, not on you for not following up.                  <- label

Refund for the most recent month is processed (txn ref XYZ; 1-2 biz
days), and I've put a manual flag on your account so any future
ticket bypasses the queue and routes straight to me. Reply here or
to support@ — same person on both ends.                  <- fact + action

If a refund isn't what would actually fix this for you (i.e., if
what you really need is the broken integration working), say so
and I'll switch to that.                                  <- calibrated Q
```

Note what is *not* in the reply:
- No "we apologize for any inconvenience"
- No "please understand, our team has been..."
- No "if you'd like, you could try..."
- No emoji, no exclamation points
- No threat, no defensiveness, no contractual language

---

## De-Escalation Ladder

The ladder decides how much empathy, boundary, and escalation to use. It complements, and never overrides, [runbooks/HOSTILE-USER.md](runbooks/HOSTILE-USER.md).

| Level | Signal | Reply shape | Boundary |
|---|---|---|---|
| L0 | Frustrated but not personal | Mirror or label once, then solve | None |
| L1 | Personal insult but still discussing the issue | Short label + answer + "let's keep this on the issue" | Soft boundary |
| L2 | Repeated personal attacks or multi-channel pressure | Accusation audit + one warning + owner-visible record | Formal warning |
| L3 | Targeted harassment, public pile-on, staff naming | No debate; preserve evidence; owner-led response or lock | Lock/suspend path |
| L4+ | Threats, doxxing, CSAM, terrorism, regulator/legal/press | Tactical empathy stops; use 🛡 ESCALATE | Counsel/T&S/owner |

**Prompt shortcut**:
```
Before drafting, choose L0-L4+.
If L0-L2: use one empathy move, one fact, one action, one boundary if needed.
If L3: preserve evidence and route to owner before any public reply.
If L4+: stop customer drafting; use the escalation runbook.
```

This keeps the skill from confusing "de-escalate" with "absorb abuse." The goal is to solve solvable pain while protecting the team.

---

## Anti-Patterns Specific To Tactical Empathy

| Anti-pattern | Why it fails | Fix |
|---|---|---|
| Stacking labels ("It seems like... it sounds like... it looks like...") | Reads as therapy-bot | One label per reply, max two |
| Mirror followed by argument | Cancels the mirror | Mirror, then *action*, never mirror then "but" |
| Accusation audit that's just a humblebrag ("You probably think we're slow — well actually we ship 4x a day...") | Negates the audit | Audit must concede before pivoting; never re-defend |
| Calibrated question that's actually a leading question | Customer feels manipulated | Genuinely-curious tone test: would you ask this if the answer didn't matter to you? |
| Empathy operators on a routine bug | Over-applied, reads as performative | Empathy is for stage-3+ tickets; stage 1-2 just want the answer |

---

## When NOT To Use Tactical Empathy

These moves are for emotionally-loaded conversations. For routine tickets, they're overhead and can read as condescending.

| Ticket | Right register |
|---|---|
| "What's my invoice URL?" | Direct answer; no empathy moves needed |
| "How do I install on Windows?" | Step-by-step; no empathy moves |
| "I'm getting a 500 from /api/foo" | Investigate; cite repro; no labeling needed |
| "I'm a developer; quick API question" | Match terse register; assume competence |
| Hostile / escalating / paid customer who feels unheard | All five moves available |
| Refund decline | Audit + label + decline |
| Data loss reply | Audit + label + heavy apology + concrete recovery |

---

## How To Practice

Tactical empathy is observable in writing — you can review your past replies and see whether you used these moves at the right moments. Two practice loops:

1. **Pre-send self-review**. After drafting and before ✓ CONFIRM:
   ```
   - Did I mirror or label anywhere this reply needed it?
   - Did I open with substance or with greeting padding?
   - Could a hostile reader read this as defensive? If yes, rewrite.
   - Are my questions "why" or "how"?
   ```
2. **Post-send retro on hostile cases**. As part of `📈 OUTCOME` for any ticket that hit stage 3+, log which moves were used, and which moves *would have* helped that you missed. Patterns emerge.

---

## How This File Plugs In

| Operator | Uses |
|---|---|
| 🪄 EMPATHIZE | Mirror, Label |
| 🪜 LADDER | Accusation Audit, Label |
| 🚦 PAUSE-SLA | Calibrated Questions |
| ⚖ DECIDE | Strategic No |
| ✉ DRAFT | All five, conditionally |

For the rage-cycle and trust-mechanics that *underpin* these moves, see [CUSTOMER-PSYCHOLOGY.md](CUSTOMER-PSYCHOLOGY.md). For the structural templates the moves slot into (apology, decline, uncertainty), see [COMMUNICATION-CRAFT.md](COMMUNICATION-CRAFT.md).
