# Voice Calibration

How to make replies sound like the team, not like an LLM. Used by the 🎙 VOICE-MATCH operator.

## Why This Matters

Customers can spot AI replies. The cost: support feels impersonal even when the substance is correct. A reply that sounds like the team builds rapport; one that sounds like a chatbot erodes it.

The cheapest fix is matching an existing voice signature, not inventing one.

## Voice Analysis (During Onboarding)

The `subagents/voice-analyst.md` subagent reads 5+ historical replies and writes `08-voice.md`. Here's what to extract:

### Register

Pick one and stick with it:

| Register | When to use | Sample feel |
|---|---|---|
| **Warm-casual** | Early-stage, B2C, individual creators | "Hey! Thanks for the report — looking now." |
| **Professional-friendly** | B2B mid-market | "Thanks for reaching out. Looking into this now." |
| **Formal** | Enterprise, regulated industries | "Thank you for your report. We are investigating." |
| **Terse-technical** | Developer tools, infrastructure | "Confirmed. Fix in #1234, deploying." |

If historical replies mix registers → flag it during onboarding; pick one.

### Opener

What's the first sentence pattern?

```
Common openers (warm-casual):
- "Thanks for the report!"
- "Hey [name] —"
- "Got it, looking now."

Common openers (professional):
- "Thanks for reaching out about <topic>."
- "Hi <name>, thanks for the note."

Common openers (formal):
- "Thank you for your report."

Common openers (terse-technical):
- "Confirmed."
- "Looking now."
- (just dive in with the answer)
```

### Closer

What's the last sentence pattern?

```
Common closers:
- "Let us know if anything else comes up."
- "Reply if you hit anything else."
- "Happy to help further."
- (no closer — just sign-off)
```

### Banned Phrases (AI-Tells)

These are patterns LLMs over-use. They don't always sound bad — but their frequency in AI output creates a "uncanny valley" effect. Strike them aggressively:

| Banned | Replace with |
|---|---|
| "I'd be happy to help" | (delete; just help) |
| "Unfortunately," | "We can't [...]" or just say it |
| "I appreciate your patience" | (delete) |
| "Please don't hesitate to reach out" | "Reply if you need anything." |
| "I understand your frustration" | (acknowledge specific frustration or skip) |
| "Let me know if you have any questions!" | (delete; obviously) |
| "Thanks for bringing this to our attention" | "Thanks for the report." |
| "We value your business" | (delete forever) |
| em-dash overuse — like — this | comma or period |
| "delve into" | "look at" |
| "navigate the complexities of" | (just delete) |
| "kindly" | "please" |
| "leverage" (as a verb) | "use" |
| "robust solution" | (delete) |
| "best practices" (without specifics) | name the practice |
| Multiple emojis 😊👍✨ | one emoji max, or zero |

### Sentence Rhythm

LLM output tends to: long, balanced sentences with parallel structure.

Real human writing tends to: short. Then occasionally a longer sentence. Then short again.

```
LLM-shape:
"We've investigated the issue and identified the root cause, which we
are now actively addressing. Once the fix is deployed, we will follow
up to confirm resolution and ensure your continued satisfaction."

Human-shape:
"Looked at it. Found the bug. Deploying the fix now — should be live in
~30 min. I'll ping back to confirm."
```

### Specific-Details Bias

LLM replies are usually too abstract. Real replies cite:
- A specific commit SHA
- A specific timestamp
- A specific log line / error
- A specific file:line in the code

Force at least one specific in every reply. If you can't, you haven't investigated enough.

### Sign-off

| Style | Example |
|---|---|
| First-name only | "— Maria" |
| Team | "— the <project> team" |
| Initials | "— jd" |
| No sign-off | (just the body) |
| Owner-only for high-stakes | "— <owner first name>" |

## Putting It Together: Sample `08-voice.md`

After analysis, the file looks like:

```markdown
# Voice — <project>

## Register
Warm-casual. Borderline-friendly without being overly familiar. We say
"hey" not "hi", "looking now" not "investigating".

## Opener (90% of replies)
- "Thanks for the report — looking now."
- "Hey [name], got it."

## Closer (most replies)
- "Reply if anything else comes up."
- (no closer — just the sign-off)

## Banned phrases (don't use)
- "Unfortunately"
- "I'd be happy to help"
- "Please don't hesitate"
- em-dashes for emphasis (parentheses or commas instead)

## Sample lines (drop in or paraphrase)
- "Confirmed in <commit>. Deploying."
- "Yeah that's a known one — fixed in vX.Y.Z, can you upgrade?"
- "Pulling logs now. Will follow up within the hour."
- "We saw this with another customer last week. Same root cause."

## Sign-off
First name. Owner uses their own first name; team members sign with their first name or the project-approved team sign-off.

## When to break character
- Security disclosures: more formal ("Thank you for the responsible disclosure...")
- Legal threats: counsel writes; we don't reply
- Hostile users: still warm but don't mirror their hostility (see HOSTILE-USER runbook)
```

## AI-Tell Remover Pass

After drafting, run this checklist mechanically before owner review:

- [ ] No "Unfortunately"
- [ ] No "I'd be happy to help"
- [ ] No "Please don't hesitate"
- [ ] No em-dashes for emphasis (use comma/period or parentheses)
- [ ] No "Let me know if you have any questions!"
- [ ] No "I understand your frustration"
- [ ] No "I appreciate your patience"
- [ ] No "Thanks for bringing this to our attention" → "Thanks for the report"
- [ ] No vague "best practices" without naming them
- [ ] No "delve" anywhere
- [ ] No "leverage" as a verb
- [ ] No "kindly" — say "please" or omit
- [ ] At least one ticket-specific detail (SHA, timestamp, file:line, error message)
- [ ] Sentence-length variation (don't all be 15-25 words)
- [ ] Length matches register (warm-casual: 60-150 words; formal: 120-250)
- [ ] Sign-off matches `08-voice.md`

If you wrote a reply and 4+ of these flag, redraft from scratch.

## `/de-slopify` Is A Mandatory Pre-Send Pass

**Every customer-facing reply MUST run through `/de-slopify` before it leaves the system.** This is not optional. The AI-tell remover checklist above is the floor; `/de-slopify` is the ceiling, and customers can spot AI-generated text from a mile away — losing trust we can't get back.

Workflow:

1. Agent drafts reply.
2. Voice-match check against `08-voice.md` (manual pass).
3. AI-tell remover checklist (manual pass).
4. **Run through `/de-slopify`** — this is the final automated gate.
5. Owner-review (per `✓ CONFIRM` operator).
6. Send.

If `/de-slopify` is not installed, the SKILL.md bootstrap installs it via `jsm install de-slopify`. Skipping this step is on the same severity tier as skipping `✓ CONFIRM` — it's how trust erodes.

`/de-slopify` catches the patterns this file lists, plus:
- AI-tells beyond the static list (model-trend keywords)
- Marketing-speak that creeps in unconsciously
- Over-formatted bullet lists where prose is better
- Emoji overuse
- "We're excited to..." opener variants
- Sentence-rhythm uniformity (the LLM-shape problem)
- Uncritical em-dash use
- Filler phrases that read fine in isolation but stack into slop in aggregate

The skill is the difference between "sounds like a real human at a real company" and "this customer is now considering switching to a competitor that doesn't reply with ChatGPT defaults." Treat it that way.

## Failure Mode: Over-Polish

There's such a thing as too-careful voice-matching. If every reply is calibrated to perfection, customers can sense it (especially on a long thread). Some imperfection is OK — typos in casual register, late-night terseness, occasional "haha" if the project's culture supports it.

The goal is "sounds like a real person who happens to know the product cold," not "sounds machine-buffed."

## Failure Mode: Voice Drift

Over time, voice drifts as the team grows / the agent rotates. Re-run voice analysis quarterly. If `08-voice.md` is older than 6 months, it's stale.

## Companion Skills

- `/de-slopify` — explicit AI-tell removal pass.
- `/readme-writing` — has its own voice section that overlaps.
- `/idea-wizard` — when feature-request replies need a "smaller version".
