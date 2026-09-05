# Customer Psychology — The Emotional Mechanics Underneath Every Ticket

Voice (`VOICE-CALIBRATION.md`) is *how* you sound. Communication craft (`COMMUNICATION-CRAFT.md`) is *what you say*. This file is *what's actually happening inside the customer's head* when they write the ticket — and what your reply has to do to that internal state. Every operator in `OPERATOR-LIBRARY.md` works better when you understand the psychology beneath it.

> **Core insight:** A support reply is rarely judged on its information content. It's judged on whether the person feels heard, respected, and safer about a future they had started to fear. Get those three right and the customer will forgive an imperfect technical answer. Get them wrong and a perfect technical answer still loses.

**Evidence boundary:** the tables below are operational heuristics, not clinical claims and not replacements for local data. Use them to draft, tag, and review replies; then let the project's outcome records, CSAT/NPS, churn reasons, and owner edits tune the defaults.

---

## The Rage Cycle (And Why "I Want To Speak To Your Manager" Is A Symptom)

Most hostile tickets aren't from hostile people — they're from ordinary people in stage 3 of a four-stage cycle:

| Stage | Internal state | Behaviour | Right response |
|---|---|---|---|
| 1. Friction | Mild annoyance ("hm, that's odd") | Self-help: refresh, retry, search FAQ | Self-service deflection via [KNOWLEDGE-BASE.md](KNOWLEDGE-BASE.md) and [KB-FEEDBACK-LOOP.md](KB-FEEDBACK-LOOP.md) |
| 2. Cost | "This is going to take time / money / make me look bad" | Files a ticket; tone is neutral-anxious | Acknowledge specifics + concrete next step |
| 3. Helplessness | "Nobody is listening / I'm being ignored / my time doesn't matter" | Tone escalates; follow-ups; threats | Name the emotion; collapse the timeline; remove obstacles |
| 4. Identity threat | "I look stupid / I'm being scammed / they think I'm lying" | Insults, public posts, demands for management | De-escalation ladder ([TACTICAL-EMPATHY.md](TACTICAL-EMPATHY.md)); never argue facts first |

**Implication:** When somebody writes "this is a SCAM and I'm calling my BANK," they are not (usually) reporting fraud. They are reporting that the previous 48 hours have made them feel powerless. Your reply must restore agency before it can deliver information. A correct answer that ignores the helplessness reads as proof of the helplessness.

**Diagnostic prompt** (paste into context when reading hostile tickets):
```
Before drafting, classify the rage stage:
  Stage 1 — friction
  Stage 2 — cost / consequence
  Stage 3 — helplessness ("nobody listens")
  Stage 4 — identity threat ("they think I'm a fool / liar / mark")

Then the reply must do, in order:
  Stage 1: deliver the answer cleanly
  Stage 2: name the cost, remove it, deliver the answer
  Stage 3: collapse the timeline ("I'm on this now"); single owner; ETA
  Stage 4: validate dignity FIRST ("you're not wrong to be frustrated"),
           then a fact, then a step, then ownership
```

---

## Trust As A Bank Account

Trust is not a state — it's a *running balance* the customer keeps in their head. Every interaction either deposits or withdraws. Treat the deltas below as a calibration heuristic until the project has its own support outcome data:

| Action | Approx delta |
|---|---|
| Promise kept on time | +1 |
| Specific apology with named root cause | +2 |
| Proactive heads-up before customer notices | +5 |
| Surprise refund / credit you weren't asked for | +3 |
| Acknowledged in <2h vs >24h | +1 (SLA-tier-dependent) |
| Generic "we apologize for any inconvenience" | -1 (yes, negative) |
| Promise missed, no proactive update | -3 |
| "It's working on our end" without verifying their setup | -3 |
| Public dismissal on Twitter/HN of a real bug | -10 |
| Repeat regression on a fix you said was permanent | -5 |
| Identity dismissal (treating expert user as novice) | -2 |
| "Our policy doesn't allow it" without exception path | -2 |

**Implication:** *You can't win a single interaction; you can only win the running balance.* A customer with a +20 balance from years of good service will tolerate one bad reply. A customer with a -3 balance reads even a friendly reply as suspicious. Onboarding the project's `08-voice.md` and `05-policies.md` exists to make those deposits intentional, not accidental.

**For triage**: if the reply will withdraw (denial, decline, missed SLA, complicated answer), pair it with a deposit (proactive disclosure, named owner, calibrated apology, follow-up commitment). Never withdraw and withdraw in the same reply.

---

## Name-It-To-Tame-It

In practice, affect labeling often helps people move from threat response back toward problem-solving: when the reply names the specific situation accurately, the customer can stop fighting to be understood. This is the core mechanic behind "I can hear how frustrating this is" actually working when said correctly.

**Wrong** (all of these are anti-patterns; banned across the skill):
- "I understand how you feel." (presumptuous, ungrounded, generic)
- "That sounds frustrating." (bot-flavored)
- "I apologize for the inconvenience." (named the wrong thing — the inconvenience, not the feeling)

**Right** — the feeling is named *specifically*, *briefly*, *without claiming to share it*:
- "Losing two hours of work to a sync bug right before a deadline — that's a brutal way to find out about it."
- "Three replies in and we still haven't fixed the root cause. That's a fair thing to be angry about."
- "Charged twice and the first refund hasn't shown up yet. I'd be watching my statement, too."

**The structure**:
```
[name the SPECIFIC situation, not the emotion-word]
  + [one short, factual reason a reasonable person would feel this way]
  + [the action you are taking, with a name and an ETA].
```

Names attached to emotions in customer service writing rule: **never use the emotion word itself if you can name the situation that produces it**. Saying "I see you're frustrated" tells the customer their feeling is being inventoried. Saying "two hours lost the day before a board meeting" tells them you understood *what they lost*.

For details on the labeling/mirroring patterns underneath this, see [TACTICAL-EMPATHY.md](TACTICAL-EMPATHY.md).

---

## Primacy, Recency, And The "Last Sentence Rule"

Memory of a support interaction is shaped almost entirely by:
1. The first line of the first reply (primacy).
2. The final state (recency — the customer's last interaction with you).
3. The peak emotional moment, positive or negative (peak-end rule).

**For drafting**:
- **Open with substance, not greeting padding.** "Hey there!" wastes the primacy slot. Compare:
  > Hey there! Thanks so much for reaching out 👋 We totally hear you...
  vs
  > You're right — your $40 charge ran twice. I've refunded the duplicate. Details below.
- **Close with the customer's next action**, not your sign-off. "Reply if the refund doesn't appear by Thursday" is a useful last line; "Have a great day!" is a wasted one.
- **Engineer one positive peak**. If the resolution is mundane, the peak is the apology specificity, the proactive disclosure of an unrelated improvement, or the named human signing off. If the resolution is excellent, *let it be the peak* — don't dilute with marketing CTA.

---

## The Apology Spectrum

`COMMUNICATION-CRAFT.md` covers structure ("acknowledge → responsibility → next step"). This file covers *calibration*. The same incident demands different apology weight for different recipients:

| Situation | Apology weight | Example |
|---|---|---|
| Cosmetic UI bug on free tier | Light | "Yeah, we see the off-by-one in the dashboard counter — fix is in the next release." |
| Paid user blocked for >1h | Medium | "You're right, this is broken for you and shouldn't be. I've fixed your account manually; root-cause patch lands today." |
| Data loss (one user) | Heavy | "We lost three of your folders. That's on us — a delete query missed a filter. Restore from last night's backup is in progress; ETA 2h. I'll write back when it lands." |
| Data loss (cohort) | Heavy + structural | Heavy as above, **plus** a public or owner-approved postmortem within the promised window, **plus** outreach to silent affected users via [POST-INCIDENT-RETRO.md](POST-INCIDENT-RETRO.md), [STATUS-PAGE.md](STATUS-PAGE.md), and [VOICE-OF-CUSTOMER-LOOP.md](VOICE-OF-CUSTOMER-LOOP.md) |
| Security disclosure handled badly | Heavy + accountability | Public acknowledgement, named accountability, structural change visible to the disclosing researcher |

**Calibration failure modes** (real, repeated):
- *Over-apologizing for cosmetic bugs* — reads as either insincere or that the company runs scared. Engineers especially distrust.
- *Under-apologizing for data loss* — "We're sorry for any inconvenience this may have caused regarding your missing folders" is not just bad PR, it's a trust withdrawal of -10 because the customer reads it as a refusal to acknowledge magnitude.
- *Apologizing without naming the specific harm* — "Sorry for the trouble" instead of "Sorry your invoice was duplicated and we charged your card twice".

---

## Identity, Face, And Why Engineers File Different Tickets Than Marketers

Customer ticket tone correlates strongly with what the customer is *afraid the ticket will reveal about them*:

| Persona | Identity stake | Ticket tone signature | Reply must |
|---|---|---|---|
| Engineer / power user | "Don't think I'm a noob" | Terse, version-cited, hostile if condescended to | Match terse register; assume competence; cite SHA / version / endpoint |
| Manager / decision-maker | "Don't make me look bad to my CFO / CEO" | Polished, references the team, asks for ETAs | Provide ETA in writing; offer status-page or email-cc to their stakeholder |
| Solo founder / SMB | "I can't afford this to fail; I have no IT team" | Anxious, asks how-to as well as bug-fix, gratitude when helped | Slow down, name what was already correct, give a small extra ("by the way, you might also want to...") |
| Enterprise procurement | "Compliance / audit / contract" | Formal, references SLA / contract / regulator | Formal register; cite clause numbers; loop in account exec or owner |
| Hobbyist / open-source user | "I want to be a good citizen / not waste your time" | Apologetic, includes repro, offers to PR | Thank for the repro; offer the contribution path; give credit |

**For onboarding** ([POLICY-ELICITATION.md](POLICY-ELICITATION.md)): elicit the project's primary persona mix and add one line per persona to `08-voice.md`. The voice is generally consistent; the *register shift* per persona is what makes replies land.

**For triage**: ★ ORIENT should add a one-word persona tag (`engineer | manager | solo | enterprise | hobbyist | unknown`) to every item. The tag changes the template choice in ⚖ DECIDE and the register in 🎙 VOICE-MATCH.

---

## The Effort Asymmetry

Customer-effort research is directionally consistent on a brutal asymmetry:

> Reducing customer effort usually predicts loyalty more strongly than delighting the customer. Use the project's own reopen rate, reply count, and CSAT/NPS verbatims to confirm the size of the effect locally.

What "effort" means in support:
- Number of replies before resolution (target: ≤2 for routine; ≤4 for complex)
- Whether the customer had to repeat information across replies
- Whether the customer had to switch channels (email → chat → phone)
- Whether the customer had to chase you for status updates
- Whether the customer had to interpret your reply (jargon, ambiguity)
- Whether the resolution required them to do work that should have been yours (re-uploading, re-authenticating, re-explaining)

**Implication:** Every reply should be tested by *the customer's effort cost*, not your effort. Combining three short questions into one well-asked question that gets all three answered at once saves the customer two reply-cycles. This is what 🪧 BROADCAST and 🚦 PAUSE-SLA are protecting against on the macro level, and what ✉ DRAFT's "numbered ask" pattern protects against on the micro level.

A useful rewrite test:
```
[OPERATOR addendum: ✉ DRAFT — effort pass]
1) Count the questions/asks the customer must complete to advance.
2) For each, ask: could it be answered/done by us with information we already have?
3) Combine remaining asks into a single numbered list at the end of the reply.
4) If the count >3, you are pushing your work onto them. Reduce or split.
```

---

## The Silent Cohort

For every customer who writes a ticket about a bug, the actual affected population is much larger:

- **Starter heuristic:** the "iceberg" rule — 1 ticket often represents a larger silent cohort on a product with meaningful active usage
- **B2B / enterprise:** ratios skew lower (1:5–1:20) because there's a procurement contact who reports
- **Developer tools / CLIs:** ratios skew higher (1:50–1:500) because devs work around things and don't file
- **OSS:** ratios are unknown — the people who file issues are the small minority who'll tolerate process

**Implication:** when ⊕ CORRELATE finds 3 tickets with the same fingerprint, treat it as evidence of a cohort issue, not merely 3 isolated users. This re-prioritizes the bead, may justify a status-page entry, and should feed the loopback/outreach path in [VOICE-OF-CUSTOMER-LOOP.md](VOICE-OF-CUSTOMER-LOOP.md).

For customer-facing language, this is the difference between:
- Wrong (treats the ticket as the population): "We've fixed the issue you reported."
- Right (acknowledges the cohort): "This was affecting more users than just you — your report was the one that caught it. Fix is rolling out now."

The second framing makes the customer who reported feel useful (a deposit) AND signals operational maturity to power users reading along.

---

## Anchoring & Concession Mechanics

Every refund / compensation conversation has an anchor — the first number that enters the discussion. Customers do not refund-shop in a vacuum; their expectation is shaped by:
1. What they paid (most powerful anchor)
2. What they think the harm was worth (next strongest)
3. What other companies they've dealt with offered for similar harms (recency bias)
4. The tone of your first reply (calm + ownership shifts expectations downward; defensive shifts them upward)

**Practical patterns**:
- **Lead with the largest defensible offer.** A free month + apology that you offer first is worth more (in CSAT) than the same offer extracted after three rounds.
- **Don't offer a menu.** "I can refund the duplicate charge OR comp a month — which do you prefer?" puts the customer in the position of having to negotiate. Unless the choice genuinely matters to them, just pick the right one and offer it.
- **The credit > refund preference**, when relevant. A $20 credit is worth more to you (deferred LTV) and often equally to them (no card-statement-watching), but only when the customer's complaint is about the service, not about wanting their money back. Read the ticket for the difference.

For the full goodwill economics math, see [COMPENSATION-CALCULUS.md](COMPENSATION-CALCULUS.md).

---

## The Maintainer's Bandwidth (OSS-Specific)

For OSS triage, the customer-psychology vector flips: the user files an issue, but the *maintainer's* psychology determines whether the project survives the long arc. Maintainer-side burnout signals:

| Signal | Meaning | Intervention |
|---|---|---|
| Issue queue >100 unread for >2 weeks | Cognitive overload, not laziness | Mass-triage with stale-bot + clear contribution policy |
| Maintainer using "I'll get to it" with no plan | Promise debt accumulating | Change to "this is in the no-soon column; PRs welcome" |
| Snippy or curt replies that don't match prior tone | Compassion fatigue | Take a maintenance week / reduce scope |
| All replies on weekends | Work bleeding into life | Set automated office-hours reply |
| Refusing to merge any external PRs | Defensive fortress mode | Document the actual contribution policy honestly; see [OSS-MAINTAINER-PROTECTION.md](OSS-MAINTAINER-PROTECTION.md) |

**Critical:** for OSS, if the project's policy is "no community contributions," that should be stated *up front* and warmly, not discovered by drive-by contributors after they've spent two weekends on a PR. Honest decline early is far less damaging than ignored-then-rejected.

---

## How To Use This File

This file informs *all* of:
- 🪄 EMPATHIZE operator (`OPERATOR-LIBRARY.md`)
- 🪜 LADDER operator (de-escalation)
- 🎁 GOODWILL operator (compensation calculus inputs)
- 📈 OUTCOME records (the "what could have been said better" dimension)
- 08-voice.md per-project register (during onboarding)
- The hostile-user runbook
- The post-incident-retro template
- All draft-bundler subagent passes

Triage agents should read it in full at least once during onboarding, then reference specific sections (rage cycle, name-it-to-tame-it, identity table) as needed during drafting.

---

## Cross-References

- [TACTICAL-EMPATHY.md](TACTICAL-EMPATHY.md) — operationalized phrasings
- [COMMUNICATION-CRAFT.md](COMMUNICATION-CRAFT.md) — apology / decline / uncertainty templates
- [VOICE-CALIBRATION.md](VOICE-CALIBRATION.md) — register and brand voice
- [COMPENSATION-CALCULUS.md](COMPENSATION-CALCULUS.md) — goodwill economics
- [VOICE-OF-CUSTOMER-LOOP.md](VOICE-OF-CUSTOMER-LOOP.md) — silent-cohort and loopback outreach
- [KB-FEEDBACK-LOOP.md](KB-FEEDBACK-LOOP.md) — self-service and docs loop
- [OSS-MAINTAINER-PROTECTION.md](OSS-MAINTAINER-PROTECTION.md) — maintainer-side psychology
- [runbooks/HOSTILE-USER.md](runbooks/HOSTILE-USER.md) — ladder applied to hostile cases
