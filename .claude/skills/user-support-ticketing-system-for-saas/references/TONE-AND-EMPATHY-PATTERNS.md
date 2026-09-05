# Tone And Empathy Patterns

`/de-slopify` removes AI tells. This file is the *positive* layer above it: how to write replies that feel human, warm, and competent without slipping into corporate-speak, false-empathy, or condescension. It's the "what to do" companion to "what to avoid."

## The Three Modes

A reply lives in one of three tonal modes; pick the right one for the moment:

1. **Acknowledge** — the customer needs to feel heard
2. **Diagnose** — the customer needs to understand what's happening
3. **Resolve** — the customer needs the outcome

Most replies do all three; getting their order and weight right is the craft.

```
Customer is angry  →  Acknowledge first (heavy), Diagnose light, Resolve specific
Customer is confused → Acknowledge brief, Diagnose heavy, Resolve clear
Customer is patient → Acknowledge brief, Resolve mainly
```

## The Five Empathy Moves

### 1. Mirror The Specific

Generic empathy ("I understand this is frustrating") sounds canned. Specific empathy ("That export error you got at 3pm — totally get how that derailed your afternoon") lands.

```
❌ "I understand this is frustrating."
✅ "Spending an hour debugging only to find it was an export bug — that's the worst kind of stuck."
```

The specific reference proves you read what they wrote.

### 2. Name The Stakes

Customers' stakes feel invisible to the team. Naming them shows you see why this matters:

```
❌ "We'll look into this."
✅ "I know you've got that client demo Monday, so I'm going to escalate this directly to engineering and stay on it until we've got an answer for you by Friday."
```

The Friday deadline isn't real promise; it's *acknowledgment of their timeline*. Then you actually have to deliver.

### 3. Apologize Once, Specifically

Multiple "sorrys" feel performative. One *specific* apology lands:

```
❌ "We're sorry. We apologize for the inconvenience. Sorry again for the trouble."
✅ "I'm sorry the export tool failed silently — that's exactly the kind of thing that should never happen, and I'm fixing it now."
```

Apologize for the *specific failure*, not the general fact of customer-pain.

### 4. Use The Customer's Words

Echo their phrasing back. If they said "weird," say "weird." If they said "broken," say "broken." Don't translate into corporate-speak:

```
Customer: "The thing where it just hangs forever is broken."
❌ "The intermittent unresponsive state has been escalated for investigation."
✅ "Yeah, the hang-forever bug is real — engineering's tracking it."
```

Mirroring vocabulary signals listening. Translating signals distance.

### 5. Specific Next Step Ownership

Vague accountability ("we'll get back to you") is anxiety. Specific accountability ("I'll personally email you by Thursday with an update — even if it's just 'still investigating'") is reassurance.

```
❌ "We'll be in touch with updates."
✅ "I'll email you Thursday at the latest. If you don't see anything from me by 4pm Thursday, please reply to this thread — that's a sign something dropped on my end."
```

The "if you don't hear from me, ping me" *gives the customer agency*. They aren't passively waiting.

## The Six Tonal Anti-Patterns

### 1. The False Empathy

```
❌ "Your concern is very important to us."
✅ Skip this entirely. Empathy is shown by what you do, not what you say.
```

If you find yourself writing "very important to us," delete the sentence.

### 2. The Passive Voice Of Avoidance

```
❌ "An error was encountered while processing your request."
✅ "We hit an error on your request" or "Our system errored out on your request."
```

Passive voice obscures responsibility. Active voice owns it.

### 3. The Process-Over-Person

```
❌ "Your ticket has been escalated to our Tier 2 team for further investigation per our standard escalation protocol."
✅ "I've sent this to our engineering lead. She's the one who'd know."
```

Customers don't care about your process names. They care about who's looking at it.

### 4. The Asymmetric Time

```
❌ "Please allow up to 7-10 business days for resolution."
✅ "I'll know more by Wednesday. If it's bigger than I think, I'll email you Friday with what we've found."
```

"Allow up to" feels bureaucratic. Concrete dates feel respectful.

### 5. The False Equivalence

```
❌ "We understand both sides of this."
```

The customer was wronged. There aren't two sides. Don't both-sides them.

```
✅ "You're right that this shouldn't have happened. Here's what we're doing about it..."
```

### 6. The Robotic Sign-Off

```
❌ "Best, The Acme Team"  or  "Sincerely, Customer Support"
✅ "— Jane (your support contact today)"
```

Sign with your name. Customers want to talk to a human; show them they are.

## Tonal Calibration By Customer State

### Angry / Frustrated

- Acknowledge specific stakes immediately
- Apologize once, specifically
- Take ownership without excuses
- Concrete next step + deadline
- *Don't* explain technical detail until they're calmer

```
"You're right — paying for a tool that loses your work is unacceptable.
I'm pulling your data from our backups right now. I'll have your project
restored within 2 hours, and I'll email you the moment it's done.
After that's safe, I'll explain what went wrong and what we're doing
to prevent it. The recovery comes first."
```

### Confused / Lost

- Validate that it's confusing (not their fault)
- Walk through one step at a time
- Use their vocabulary
- Offer a screen-share / video / KB link

```
"Honestly, this part of the UI confuses lots of people — it's not you.
Here's the simplest path:
1. Click the gear icon in the top-right
2. Look for 'Export'
3. Pick CSV
If that gear icon isn't where I described, screenshot what you see and
I'll walk you through it from there."
```

### Patient / Waiting

- Brief acknowledgment
- Direct resolution
- Check that it landed

```
"All set — I've reset your password and sent the new link to your inbox.
Try logging in and let me know if it works."
```

### Power User / Technical

- Skip the apologies; get to the technical
- Use their terminology back
- Cite specifics (commit, error code, log line)

```
"Yeah, that's a regression in the new export pipeline.
Repro confirmed in 2.4.1. PR open: github.com/acme/web/pull/5421.
Workaround: pass `?legacy=true` query param. Fix lands tomorrow."
```

### First-Time / New Customer

- Warmer opening
- Don't assume product familiarity
- Offer next-step guidance beyond their immediate question

```
"Welcome! Happy to help. To do the export you're asking about:
1. ...
2. ...
And while you're getting set up, you might also want to try [related
useful feature] — it pairs nicely with what you're doing."
```

## Cross-Cultural Tone Notes

Per [INTERNATIONALIZATION-AND-LOCALIZATION.md](INTERNATIONALIZATION-AND-LOCALIZATION.md), default formality varies by locale. Specifics:

- **US English**: Casual is fine. First names from the start.
- **UK English**: Slightly more reserved. "Hi" not "Hey."
- **German**: Formal. Use "Sie" form. Last names + title until invited otherwise.
- **Japanese**: Highly formal (敬語). Native-speaker review essential. Apologies more frequent.
- **French**: Default to "vous" form. Formal greetings.
- **Brazilian Portuguese**: Warm and personal. First names.

## The 4-Sentence Reply (For Volume Handling)

When responding to many tickets, a 4-sentence shape works for ~60% of cases:

```
Sentence 1: Mirror the specific issue (proves you read it)
Sentence 2: State what you've done or are doing
Sentence 3: Tell them what to expect next + deadline
Sentence 4: Invite reply if anything changes
```

```
"Got it — your invoice for March doesn't match what you were
billed. I've pulled your billing history and can see the discrepancy
(thanks for the screenshot — that helped). I'm requesting a $42
refund now; you should see it back on your card in 3-5 business
days. If anything looks off when it lands, just hit reply."
```

Tight, specific, actionable. Scales without feeling formulaic.

## When To Send No Reply (Yet)

Sometimes the right move is silence — when:

- Customer is venting and a reply would interrupt their thought
- Engineering is actively fixing; an "investigating" reply would invite "any updates yet?" pings
- The right answer requires coordination you don't have yet

Use the `acknowledged` status without sending. Internal note documents the decision. *Don't* let it sit in this state more than a few hours; either reply or escalate.

## Templates That Work And Why

### "We caused this; we'll fix this; here's how"

```
Hi [Name],

You're right — [specific failure description] shouldn't have happened.
Here's what we found and what we're doing:

[1-2 specific factual sentences about cause]

[Specific action being taken, who, by when]

I'll email you [specific date/time] with an update.

[Your name]
```

Use for: bug-induced data loss, billing errors, missed deliverables.

### "Here's how + here's why + here's bonus"

```
Hi [Name],

To do [thing they asked]: [concrete steps].

That [behavior] is because [brief why].

Worth knowing: [bonus tip relevant to their workflow].

[Your name]
```

Use for: feature questions, "how do I" tickets.

### "Not yet, here's the path"

```
Hi [Name],

We don't [feature they want] today. I get why that's frustrating —
[specific use case from their message].

The closest thing we have is [workaround]. It's not perfect, but
[honest assessment of how close].

I've added your request to our roadmap notes — [PM name] reviews
those weekly. Can't promise a date, but you'll be on the list.

[Your name]
```

Use for: feature requests where the answer is "not now."

## Anti-Patterns

| ✗ | Why |
|---|---|
| Multiple apologies | Performative; reads as scripted |
| "Your concern is important to us" | Empty filler; deletes itself if removed |
| Process-name jargon (Tier 2, Level 3) | Customers don't have your org chart |
| Passive voice on responsibility | Avoids ownership |
| Generic empathy ("I understand") | Doesn't prove you read |
| Both-sidesing customer fault | Insulting when customer was actually wronged |
| Sign-off with "The Team" | Customer wants to know who's on it |
| Time vague ("soon", "shortly", "as soon as possible") | Builds anxiety; concrete dates land |
| Translating customer's vocabulary into "proper" terms | Signals distance |
| Long replies for short questions | Reads as obfuscation |
| Short replies for serious failures | Reads as dismissive |
| Apology that becomes the whole reply | They want resolution, not a poem about how sorry you are |
| Using the customer's full first + last name when they signed first-name-only | Robotic |

## Wire Points Checklist

- [ ] Tone canon documented in `08-voice.md` (handoff to triage skill)
- [ ] AI-draft prompt instructs in tonal moves (mirror, stake-naming, ownership)
- [ ] `/de-slopify` rules tuned for the team's voice
- [ ] Saved replies / macros use first names + concrete dates
- [ ] No template uses "important to us" or "best, the team"
- [ ] Customer state inferred (angry / confused / patient / technical) from signal heuristics; suggest tonal mode
- [ ] Per-locale tone defaults applied
- [ ] Sign-off includes admin first name (or pseudonym for privacy-sensitive teams)
- [ ] Exemplary library curated for tonal range
