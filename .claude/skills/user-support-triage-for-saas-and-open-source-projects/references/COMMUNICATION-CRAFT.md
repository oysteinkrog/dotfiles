# Communication Craft

Voice (per `VOICE-CALIBRATION.md`) is *how* you sound. Communication craft is *what you say in delicate moments*. This file is a phrase-bank and structural guide for the situations that go wrong most often: apologies, declines, uncertainty, urgency, "we don't know yet", and conversations after a mistake.

## The Craft Stack

| Layer | Owns |
|---|---|
| Voice | Register / vocabulary / signature |
| Structure | Order of paragraphs |
| Craft (this file) | Specific phrasings that thread the needle |
| AI-tell remover | Final pass for slop |

## Apology — Real Vs Hollow

**Hollow** (banned):
- "We're sorry for the inconvenience."
- "We apologize for any frustration this may have caused."
- "Sorry you had a bad experience."

**Real** apology has three parts:
1. **Acknowledge specifics**: name what happened, in their words.
2. **Take responsibility**: no passive voice, no externalising.
3. **State what changes**: concrete next step or fix.

Pattern:

```
You're right — <specific thing>. That was on us.

<one-line root cause in plain language>.

<what we're doing now> + <what you can do next>.
```

Example:
> You're right — your $40 charge went through twice. That was on us; a webhook
> retry slipped past our idempotency guard. I've refunded the duplicate (should
> hit your card in 2-3 business days), and I've shipped a fix for the root
> cause this morning so it can't happen again. Reply if the refund doesn't
> appear by Thursday.

The structure works for $40 mistakes and for data loss. It doesn't work for "we apologize for any inconvenience."

## Declining Without Coldness

A "no" that lands well has:
- Direct yes/no in the first sentence
- Reason (specific, not policy-shield)
- An alternative when one exists

```
Short answer: we can't <thing> in this case.

Why: <specific reason>.

What we *can* do: <alternative, if any>.
```

Example (refund decline outside policy window):
> Short answer: we can't refund the annual plan now — purchase was 6 months
> ago, well past our 30-day window.
>
> What I *can* do: switch you to month-to-month at the next renewal, which
> drops your effective cost going forward. If that helps, say the word.

Avoid:
- "Unfortunately, our policy doesn't allow..." (hides behind policy)
- "We totally understand, but..." (implies you don't)
- "I wish we could..." (you can; you've decided not to)

Don't bury the no. The customer knows their own request — leading with anything else feels evasive.

## Uncertainty — "We Don't Know Yet"

The hardest reply to write is "I don't have an answer for you yet." Default failure modes: pretend you have an answer; promise a timeline you can't keep; go silent.

The right reply:
1. State what you know.
2. State what you don't know.
3. Commit to a *check-in time*, not a *resolution time*.

```
What I know: <fact>, <fact>.
What I don't know yet: <specific question>.
What I'm doing: <next step>.
I'll check back at <specific time>, even if I don't have an answer.
```

Example:
> Here's where we are:
>
> What I know: the error you saw at 14:32 UTC came from our webhook handler.
> Same handler is fine right now.
>
> What I don't know yet: whether other payment events were affected.
>
> What I'm doing: pulling the full payment audit log for the past 4 hours.
>
> I'll write back by 17:00 UTC with what I find — even if it's "still
> investigating."

Crucial: send the 17:00 UTC update. Customer trust comes from kept micro-promises, not big resolutions.

## Urgency — Without Panicking The Customer

When you suspect data loss or a security issue, you'll feel urgency. The customer shouldn't.

Don't write:
- "URGENT — please check immediately!!"
- "We need your help right away to avoid catastrophic data loss"

Write:
- "We've found something we want to investigate quickly. Could you confirm <X> when you have a minute?"
- "Heads-up — we may have a small issue affecting your account. Reading the data now; I'll have a clearer answer in ~30 min."

Calm voice signals competence. Urgent voice signals you're flailing.

## "Stop, We Made A Mistake"

When you sent something wrong, told the customer something incorrect, or acted on bad data:

```
Quick correction on <thread/topic>:

<what we said earlier> — that was wrong.
<what's actually true>.
<what we did wrong + what we did to recover>.

Sorry for the back-and-forth.
```

Example:
> Quick correction on yesterday's reply:
>
> I said your subscription was active. It's not — it lapsed Tuesday. I had a
> stale view of our billing data and didn't double-check. The lapse is a
> separate issue I'll handle today; I'll restore service first, then sort
> out the billing.
>
> Sorry for the back-and-forth.

Sting through. Don't soften it; the customer already noticed the inconsistency, and softening reads as gaslighting.

## Replying To Hostility (Without Mirroring)

Stay factual, short, and warm-bordering-on-formal. NEVER mirror their tone.

Example (customer wrote a profanity-laden complaint):

> I hear you — this has been frustrating. Let me focus on the issue:
>
> <one-paragraph factual response to the underlying problem>.
>
> If the fix above doesn't resolve it, reply and I'll dig further. We won't
> match the language you used, but that doesn't change that I want to get
> this fixed for you.

The "we won't match the language" line works because it acknowledges the mode-shift without lecturing. Use it sparingly; once is enough.

## "We're Killing The Feature You Love"

```
Heads-up: we're sunsetting <feature> on <date>.

Why: <plain-language reason>.

What you can do:
- <export option / migration path>
- <alternative we recommend>

We know this isn't what you want to hear from us, especially because <feature>
has been a core part of your workflow.
```

Don't:
- Bury the date
- Frame it as a "transition" or "evolution" — say "we're killing it"
- Pretend the alternative is just as good if it isn't

## Long-Thread Recovery

When a thread has 10+ back-and-forths and the customer is frustrated:

```
Let me reset on this so we're not talking past each other.

Here's what I understand:
- <bullet>
- <bullet>
- <bullet>

Here's what I think the next step is:
<one specific action>.

Did I miss anything?
```

This works because customers rarely think the agent is *listening*. Reflecting back what you've heard is more important than the answer in this moment.

## "I Don't Know What You Mean"

Don't ask 5 questions. Ask one specific one.

Bad: "Could you clarify what you mean by 'doesn't work'? What's the error? Which browser? Which user account? When did it start?"

Good: "I'm not sure I'm picturing the issue. Can you screenshot the page where you see the problem?"

Screenshot > description > more questions. Always.

## The Right Length

| Situation | Words |
|---|---|
| Routine fix sent | 50-100 |
| Investigation update (no answer yet) | 30-80 |
| Refund grant | 60-120 |
| Refund decline | 100-150 (longer to explain) |
| Apology for our mistake | 80-150 |
| Security disclosure ack | 100-200 |
| Public-facing outage | 150-300 |
| Postmortem (customer-facing) | 300-500 |

Going over by 50% = consider trimming. Going over by 2x = always trim. Long replies feel defensive.

## Words And Phrases To Strike

Beyond the AI-tells in `VOICE-CALIBRATION.md`:

| Strike | Why |
|---|---|
| "going forward" | corporate filler |
| "circle back" | also corporate filler |
| "at this time" | "now" or omit |
| "as a courtesy" | implies you're owed something; you're not |
| "in good faith" | doth protest too much |
| "pursuant to our policy" | nobody talks like that |
| "we appreciate your understanding" | telegraph: "we're not changing our mind" |
| "kindly note" | passive-aggressive |
| "feedback noted" | "we heard you and won't act" |
| "as I mentioned earlier" | even if true, condescending |
| "to be clear" (preceded by repetition) | implies prior obscurity was the customer's fault |

## Words That Build Trust

| Phrase | Why |
|---|---|
| "You're right" (when they are) | radical; rare from companies |
| "I made a mistake" | first person, not "we as a team..." |
| "I don't know yet" | + commit to a check-in |
| "Here's what I'd do in your shoes" | shows you took their perspective |
| "That's a fair point" | even when you can't act on it |
| "Specifically: <fact>" | citations beat hand-waving |
| "We'll fix this by <date>" | + actually do |

## Reading Order

For high-stakes replies, draft in this order:
1. The action (what we did / will do)
2. The reason (why)
3. The acknowledgment (what they experienced)
4. The opener / context

Then reverse and place: opener, acknowledgment, action, reason. The middle gets to the point fastest.

## When To Pick Up The Phone

For paid customers, escalating to a call is sometimes the right craft choice:
- Refund > $1000
- Public-facing complaint that's escalating
- Long thread (10+ replies) and they're getting angrier
- Cancellation that you suspect is rooted in support quality

Offer the call by name and time:
> Want to hop on a call? I have 30 min open Wednesday at 14:00 UTC; if that
> doesn't work, reply with what does.

Don't say "let me know when works for you" — they'll never reply.

## Edits Before Sending

Five-second pass before send:
1. Does the first sentence match the last sentence? (consistent message)
2. Did you cite at least one specific?
3. Is there a clear next step (theirs or ours)?
4. Voice match per `08-voice.md` (the project's generated voice profile; see `VOICE-CALIBRATION.md` for how it's produced)?
5. AI-tells removed?
6. **`/de-slopify` ran clean?** — mandatory; non-negotiable

If any "no", redraft the offending part.

## `/de-slopify` Is Mandatory

Every reply this file shapes is going to a real customer. Customers can spot AI-generated phrasing — the kind that tests "professional" but feels like ChatGPT default voice. **Run `/de-slopify` as the last step before send, every single time.**

Even when:
- The reply is short
- It's "obvious" / boilerplate
- You're confident the voice match was clean
- The customer is friendly / forgiving
- You're under time pressure

There is no "exception" tier. Slop ships when we say "this one is fine without the pass" and the customer notices anyway. See `VOICE-CALIBRATION.md` for what `/de-slopify` catches that this file's craft rules don't.

## Companion Refs

- [VOICE-CALIBRATION.md](VOICE-CALIBRATION.md) — register / banned phrases / sample lines
- [RESPONSE-TEMPLATES.md](RESPONSE-TEMPLATES.md) — high-frequency templates
- [runbooks/](runbooks/) — category-specific drafts
- `/de-slopify` — final pass for AI-tells
