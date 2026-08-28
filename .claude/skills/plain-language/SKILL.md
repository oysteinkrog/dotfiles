---
name: plain-language
description: >-
  The standing rule for every word a person will read: chat replies, docs,
  artifacts, titles and headings, PR and commit messages, Jira, Slack, email,
  user-facing UI and error copy, code comments. Very clear and simple language,
  always, without losing technical precision. Bans slogans, aphorisms, inflated
  vocabulary, hype and padding. Also the authority on titles and copy where other
  skills overlap. Use before sending, publishing or handing over anything written
  for a person, and whenever drafting a title or heading.
---

# Plain language

**Very clear and simple language at all times in output meant for human readers.**
This is a standing rule, set by Oystein. It is not one goal to trade off against
others, and it is not a style you switch on for formal documents.

Write so the reader understands on the first pass, without decoding anything.

## The test

Read it back as the reader, who has no context you have and is not impressed by
effort. Ask:

- Do I know what this is about by the end of the first sentence?
- Is there a shorter, more common word doing the same job?
- Is any sentence here performing rather than informing?
- Did I drop a number, a unit, a constraint, a caveat, or an admission of
  uncertainty to make it read better?

If a line would fit on a poster, it is performing. Rewrite it as the plain fact or
requirement it is standing in for.

## Rules

1. **Lead with the answer.** State the conclusion, then support it. Never build to a
   reveal.
2. **Short, common words.** Wrong, not suboptimal. Use, not leverage or utilise. Ask,
   not solicit. Before, not prior to. Enough, not sufficient. Start, not commence.
   About, not approximately, unless precision matters.
3. **Never trade precision for simplicity.** Plain does not mean vague. Use the
   established domain term when it is the most precise word available, and define it
   once if the reader may not know it. Keep the numbers, units, versions, file paths,
   constraints, tradeoffs, caveats and stated uncertainty. Simplify the sentence
   around a technical term, never the term itself. If a shorter word changes the
   meaning, it is the wrong word. Length is not the target; a longer sentence that is
   exactly right beats a short one that is nearly right.
4. **One idea per sentence.** Prefer short sentences. Vary length so it does not read
   like a list, but never chain three clauses to sound thoughtful.
5. **Active voice, named actor.** "The phone clamps the frame rate", not "the frame
   rate is clamped".
6. **Concrete over abstract.** Real numbers, real names, real file paths. "62% of
   sessions", not "a significant proportion".
7. **Say what you mean about certainty.** "I don't know", "I did not check", "this is
   a guess". Do not hedge into vagueness and do not overstate.
8. **No slogans or aphorisms.** Anywhere: titles, headings, pull quotes, opening
   lines, closing lines. This is the failure that keeps recurring.
9. **No hype register.** Nothing is seamless, robust, comprehensive, powerful,
   elegant, or a game changer unless you are quoting someone.
10. **No em dashes.** Hard rule. Use a period, comma, colon, or parentheses.
11. **Cut padding.** Delete "it's worth noting that", "at its core", "in order to",
    "the fact that", "needless to say", "let's dive in", "here's why it matters".

## Banned shapes

These are the constructions that give the writing away. Each is banned as a
*rhetorical device*, not as a sentence shape. A real contrast, a list that genuinely
has three items, or a correction of a specific wrong belief is allowed. Ask whether
the shape is carrying information or performing; if you cannot say what it adds, cut
it.

| Shape | Avoid | Write |
|---|---|---|
| Declarative slogan | The Phone Stays Mounted | Phonecam Settings Brief |
| Aphorism | Every walk back is a defect | The user should not have to touch the phone mid-session |
| "Not X, it's Y" | Not a device, a sensor | The phone reports its own state |
| Rule of three | Faster, simpler and safer | Faster, and it removes one failure case |
| Negative parallelism | Not only X, but also Y | X. It also does Y. |
| Drama / stakes | 26.1 cannot break | Compatibility with 26.1 |
| Metaphor as label | What is built and what is fiction | What already exists, and what does not |
| Tease | The trap this avoids | Why we are not using these commands |
| Journey framing | Our path to remote control | Delivery phases |
| Vague attribution | Experts agree | The 2026-08-10 audit found |
| Gerund opener | Reimagining capture | Capture changes in 26.2 |

## Titles and headings

A title exists so the reader knows what the thing is before opening it. Read it alone,
with no context: if the reader cannot tell what the document is and what kind of
document it is, it has failed.

The real case that prompted this skill: an artifact named **"The Phone Stays Mounted"**
for what was simply a phonecam settings brief. Correct name: **"Phonecam Settings
Brief"**.

- Name it, don't pitch it. A noun phrase, usually two to five words.
- Specific enough to tell it apart from its neighbours. "Product Brief" alone fails.
- Including the document type (brief, plan, audit, runbook) is helpful, not filler.
- No colon or dash bolting an explainer onto the name.
- Headings say what the section covers. "Risks" beats "Risks we are carrying".
- Keep a published title stable. Readers find a page by its name.

## Where this applies

Everything a person reads: terminal replies and summaries, artifacts and documents,
titles and headings, PR titles and bodies, commit messages, Jira issues and comments,
Slack and email, README and docs prose, user-facing UI strings and error messages, and
code comments meant for a human.

Out of scope: code identifiers, quoted text, prescribed formats, machine-parsed
output, and any wording the person asking specifies themselves, which always wins.

## Procedure

1. Draft.
2. Read every line back as the reader. Apply the test and the rules.
3. Sweep the banned-shapes table. They cluster in first and last lines of sections.
4. Check every title, heading, and pull quote in isolation.
5. Cut whatever survives that is not carrying meaning.

## Precedence over other guidance

This skill is the single authority on wording, titles, headings and copy. Where any
other skill, template or house style says something different about how English should
read, this wins. Named cases:

- `artifact-design` and the other page-building skills own the visual side: layout,
  palette, type, components. Their advice on copy and titles is a summary of this
  skill and is not maintained here. Follow this skill for every word on the page, and
  follow them for how the page looks. In particular, a title names the document, and
  including the document type is helpful rather than filler.
- `humanizer` and `de-slopify` scrub tells out of a finished draft. This skill is the
  register you write in from the start, so it runs first and they run after. Do not
  treat `humanizer`'s "add soul" as licence for a slogan.
- `voice` matches one person's register and applies only when writing as that person.

Do not compensate for a plain title by making the body flowery.
