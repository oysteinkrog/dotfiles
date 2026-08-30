---
name: plain-language
description: >-
  The standing rule for every word a person will read: chat replies, docs,
  artifacts, titles and headings, PR and commit messages, Jira, Slack, email,
  user-facing UI and error copy, code comments. Very clear and simple language,
  always, without losing technical precision. Bans slogans, aphorisms, inflated
  vocabulary, hype and padding. Also the authority on titles and copy where other
  skills overlap. Ships a scorer, `pl`, and a hook that gates writes, commits,
  pull requests, Jira, Slack, email and artifacts. Use before sending, publishing
  or handing over anything written for a person, and whenever drafting a title.
---

# Plain language

**Very clear and simple language at all times in output meant for human readers.**
This is a standing rule, set by Oystein. It is not one goal to trade off against
others, and it is not a style you switch on for formal documents.

Write so the reader understands on the first pass, without decoding anything.

Two halves. The register is below and you write in it from the start. The scorer
(`pl`) checks a draft before it reaches anyone, and a hook runs it for you.

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

<!-- plainlang: skip. This file quotes the banned constructions as examples, so
     the scorer would flag its own specification. This is the escape hatch
     working as intended: say why, in the file, where a reader can check it. -->

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
output, product copy that another skill or spec owns, and any wording the person
asking specifies themselves, which always wins.

## The scorer

`pl` scores a draft and points at the lines to fix.

```sh
pl check draft.md          # findings with line and column, exit 1 if the gate fails
pl score docs/*.md         # one line per file
pl explain draft.md        # where every point of cost went
echo "$BODY" | pl check -  # read from stdin
```

It reports a list of findings and a score out of 100. The gate fails on any hard-rule
violation, or when the score falls below the minimum in `data/weights.json`.

**Fix the findings. Never chase the score.** Read the findings, fix the ones you
agree with, leave the ones you think are wrong and say which and why, then stop.
Do not run it again to watch the number move.

This is not a style preference, it is a measured result. In a blind test, 24
notes were written three ways from the same facts: with no guidance, with this
skill, and with this skill plus five rounds of raising the score. Two blind judge
panels ranked the score-chasing version worst 39 times out of 48, and best once.
Its tool score was the highest of the three, and its clarity was the lowest.
Chasing the number made the writing worse in exactly the way the number cannot
see. What the agents did to raise it: stripped backticks off identifiers, dropped
a bead id out of a title, and chopped sentences into fragments. Every one of those
raises the score and costs the reader.

So treat the number as a thermometer, not a target. The findings are specific and
worth acting on; the number is only there to decide whether the gate opens.

### How the score works

Nothing is banned. Every word and every sentence spends from a budget, and the score
is what is left. A word costs more when it is rare, learned late, and abstract, using
published norms: Zipf frequency from SUBTLEX, age-of-acquisition ratings from
Kuperman et al. (2012), and concreteness ratings from Brysbaert et al. (2014).
Rarity is the gate on the other two, so "enough" is free (abstract but common) while
"paradigm" is not (abstract and rare).

Precision is free. A word costs nothing when it is in the glossary, an acronym, a
proper noun, a number, or inside code, a path, a URL or a quotation. The skill says to
keep the precise term and simplify the sentence around it, so the scorer does not
charge you for the term.

What costs extra is unearned difficulty: a hard word that has a plain synonym meaning
the same thing. Those get a multiplier, from a 366-entry list drawn from the federal
plain-language guidance. "Utilize" is expensive because "use" exists. "Latency" is
free because nothing shorter means it.

Sentences cost by length above about 20 words, by agentless passives, and by having
every sentence the same length. Headings cost when they read as a sentence rather
than a name, ask a question, or open on a participle.

### Domain terms

Put terms that should cost nothing in `<repo>/.plainlang/glossary.txt`, one per line.
The scorer walks up from the working directory to find it. Adding a domain glossary
measurably improves the tool rather than weakening it: on the eval corpus it raised
separation from 0.955 to 0.974 AUC and cut false alarms on real repo prose from 58% to
31%, because domain vocabulary is noise for the distinction that matters.

To regenerate one for a repo, take words that appear at least 60 times in its docs and
have a Zipf frequency below 3.3.

## What the hook covers

A hook runs the gate on anything about to reach a person: writes to `.md` and `.txt`,
commit messages, pull request bodies, Jira and Confluence text, Slack messages, email,
artifacts and artifact comment replies, and the reply you are about to send in chat.
A failing gate returns the findings and you fix the text and try again.

The hook skips code, config, generated files, localisation and resource files, product
strings, and anything shorter than 40 words. Off switches, in order:

- `PLAINLANG_OFF=1` turns everything off.
- `PLAINLANG_MODE=warn` reports without blocking.
- A `plainlang: skip` line in the text itself, for material that is genuinely out of
  scope. Say why when you use it.

## What the tool cannot do

It reads surfaces. It finds inflated words, banned shapes, heavy sentences and machine
residue. It cannot tell whether the text is true, whether it answers the question,
whether the argument holds, or whether the reader has the background to follow it.
A passage can score 95 and still be useless. The register rules above are the job; the
scorer is a check on the part of the job that a machine can see.

The measured limits, from the eval set: it separates plain from inflated writing at
0.98 AUC and agrees with blind judges at Spearman 0.69. On outside data it tracks
human difficulty ratings about as well as the best classic readability formula, and it
puts professionally graded texts in the right order 96% of the time. Per-rule
precision and recall are in `evals/`.

## Procedure

1. Draft in the register above.
2. Read every line back as the reader. Apply the test and the rules.
3. Sweep the banned-shapes table. They cluster in first and last lines of sections.
4. Check every title, heading, and pull quote in isolation.
5. Run `pl check` once. Fix the findings you agree with. Leave the ones you think
   are wrong and say which and why. Then stop.
6. Cut whatever survives that is not carrying meaning.

Three things never to do, because each raises the score and costs the reader:
remove backticks, identifiers, bead ids, versions, paths or issue keys; chop a
sentence into fragments to shorten it; make a title blander. A specific
identifier in a title is information, not filler.

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
- Product copy inside the application follows its own spec and localisation rules.
  Where a spec fixes the wording, the spec wins and this skill does not apply.

Do not compensate for a plain title by making the body flowery.

## Files

| Path | What it is |
|---|---|
| `tool/` | the scorer, a uv project with no runtime dependencies |
| `data/lexicon.tsv.gz` | 131,793 words with Zipf, age of acquisition, concreteness and prevalence |
| `data/simpler.tsv` | hard word to plain replacement, for the unearned-difficulty multiplier |
| `data/glossary.txt` | terms that cost nothing |
| `data/weights.json` | the fitted cost model and the gate threshold |
| `evals/` | the corpora, the metrics, the tuner and the rule tests |
| `hooks/` | the gate and the settings snippet that wires it in |
| `install.sh` | builds the virtualenv, installs `pl`, runs a self test |
