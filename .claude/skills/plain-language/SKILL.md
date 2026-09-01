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
10. **No em dashes.** Use a period, comma, colon, or parentheses. This is a tell,
    not a comprehension problem: it marks writing as machine-made. The scorer
    charges it and names it, and it does not stop a write.
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

`pl` is the optional launcher that `install.sh` puts on your PATH. Nothing else
needs it: the same scorer runs as
`PYTHONPATH=tool/src python3 -m plainlang.cli check -`, and that is how the hook
runs it.

It reports a list of findings and a score out of 100. The gate fails when the score
falls below the minimum in `data/weights.json`, or on a **defect**: chatbot citation
markup, a tracking parameter, chat-assistant boilerplate, or an unfilled `[NAME]`
placeholder. Those four are wrong whatever the reader makes of the prose.

Style is priced, not gated. An em dash, a slogan title, a hype word and a
significance tail all cost budget and all appear as findings, and none of them
stops a write on its own. Enough of them together will take the score below the
line, which is the point: the score is the part validated against how hard people
actually find text to read.

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

A fourth group did it the way this skill now says: one pass, fix the findings you
agree with, leave the rest, ignore the number. Two fresh judge panels picked that
group best 30 times out of 48, against 13 for no guidance and 5 for the skill
text alone. Its tool score was **lower** than the score-chasing group's. Across
24 notes it fixed 19 findings and deliberately kept 53, with a reason each time.

So the findings are the product and the number is a thermometer. Read the
findings, use judgement, and rejecting most of them is normal.

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

A hard word with a plain synonym gets that synonym shown as a suggested fix, from a
list drawn from the federal plain-language guidance. It is a suggestion, not a
surcharge. There used to be a cost multiplier on those words and it is gone: every
reader here has English as a second language, Norwegian or Brazilian Portuguese
first, and no controlled-language standard written for non-native readers penalises
a word for being Latinate. For a Portuguese reader "utilize" is a cognate of
*utilizar*, so it may be the easier word. Removing the multiplier changed no measured
metric. Twelve suggestions went with it, the ones that replaced a Latinate cognate
with a phrasal verb: `implement` to *carry out*, `ascertain` to *find out*, and ten
more. Details in `evals/RESULTS.md` section 15.

Sentences cost by length above about 20 words, by agentless passives, and by having
every sentence the same length. Headings cost when they read as a sentence rather
than a name, ask a question, or open on a participle.

### What gates and what only costs

Four defects stop a write: leaked chatbot citation markup, a tracking parameter in
a URL, chat-assistant boilerplate, and an unfilled `[NAME]` placeholder. They are
wrong whatever the reader makes of the prose.

Everything else is priced. An em dash costs 4 points, the same as the other strong
tells, and does not stop anything on its own. Measured on 84,340 real tool calls
and 8,791 real replies, that change cut refusals by 62% on writes and commits and
53% on chat replies, and took false alarms on real repo prose from 15.1% to 4.7%.

Nothing under 40 words is gated unless it contains a defect. A cost per hundred
words means nothing at fourteen words.

### Second-language readers

Every human reader here has English as a second language, Norwegian or Brazilian
Portuguese first. That was tested rather than assumed, using OneStopEnglish, whose
three levels are graded for English learners.

It changed less than expected. The model already orders learner-graded text
correctly for 186 of 189 articles. Two candidate additions were measured and both
lost: word prevalence normed on non-native speakers, and CEFR-graded vocabulary.
Both charge domain terms, because a general-population norm cannot tell `latency`
from `utilize`, and these readers are domain experts who know `latency`.

What it did change: nothing is charged for being a Latinate word any more. No
controlled-language standard written for non-native readers carries an Anglo-Saxon
preference, and for a Portuguese reader the Latinate word is usually the cognate
and so the easier one. Twelve suggestions that replaced a cognate with a phrasal
verb are gone.

The known gap: object relative clauses have the best-quantified second-language
penalty in the literature and need a parser this tool does not have.

### Domain terms

Put terms that should cost nothing in `<repo>/.plainlang/glossary.txt`, one per line.
The scorer walks up from the working directory to find it. 444 general technical terms
ship with the skill; this repo adds 6,938 of its own. Adding a domain glossary improves
the tool rather than weakening it: on the eval corpus it cuts false alarms on real repo
prose from 23.3% to 15.1% and raises judge agreement from 0.688 to 0.705, because domain
vocabulary is noise for the distinction that matters.

Adding or growing a glossary changes the score and the findings for the same
text. That is intended, not the tool going soft. The scorer finds
`.plainlang/glossary.txt` by walking up from the working directory (or from
`PLAINLANG_PROJECT` when set), so the same document scores higher inside a repo
that has a glossary than outside one. Domain terms stop being charged; nothing
else relaxes.

To regenerate one for a repo:

```sh
python evals/build_corpus.py --repo . --glossary
```

That keeps words appearing at least 60 times in the repo's own docs whose Zipf
frequency is below 3.3.

## What the hook covers

A hook runs the gate on anything about to reach a person: writes to prose files
(`.md`, `.txt`, `.rst`, `.adoc`),
commit messages, pull request bodies, Jira and Confluence text, Slack messages and
canvases, Zendesk support replies, email (through the Gmail tools or the `gog` CLI),
artifacts and artifact comment replies, and the reply you are about to send in chat.
A failing gate hands back the findings; fix them and try again.

The hook skips code, config, generated files, localisation and resource files, and
product strings. Text that is not English is detected and skipped, so translated
documentation is never charged for not being English. Below 40 words the score means
nothing, so short text passes unless it carries one of the four defects: a
fourteen-word commit message with an em dash goes through. Off switches, in order:

- `PLAINLANG_OFF=1` turns everything off.
- `PLAINLANG_MODE=warn` reports without blocking.
- A `plainlang: skip` line in the text itself, for material that is genuinely out of
  scope. Say why when you use it.

### How the gate runs

There is no install step, no virtualenv, no pip, no network. The scorer imports
only the Python standard library, so the hook runs it with bare `python3`
(3.12 or newer) and a `PYTHONPATH`. `selftest.sh` checks this by importing the
scorer with bare python3, outside any virtualenv. It works on a fresh clone.
The earlier design needed an installed launcher, which meant the gate silently
did nothing on any machine where nobody ran the installer, and a guard that
quietly stops working is worse than no guard.

The gate is wired in two places at once: `~/.claude/settings.json` and the host
repository's `.claude/settings.json`. Both point, through one-line forwarder
scripts, at the same `hooks/plain-language-guard.sh`. When both fire on the same
text, a short-lived decision cache keyed on the payload replays the first result
instead of scoring twice.

`plain-language-guard.sh` only finds a python3 and the skill; all the logic is
in `plain-language-detect.py`, and `plain-language-guard.test.py` holds its 32
cases. A SessionStart hook, `plain-language-health.sh`, proves once per session
that the gate can refuse bad text and pass good text, and prints a warning when
it cannot. That check exists because the gate fails open on error, and a guard
that fails open silently looks exactly like a guard that is working.

`bash selftest.sh` proves the whole thing works on the current machine.

## What the tool cannot do

It reads surfaces. It finds inflated words, banned shapes, heavy sentences and machine
residue. It cannot tell whether the text is true, whether it answers the question,
whether the argument holds, or whether the reader has the background to follow it.
A passage can score 95 and still be useless. The register rules above are the job; the
scorer is a check on the part of the job that a machine can see.

The measured limits. On the eval set it separates plain from inflated writing at 0.997
AUC and agrees with blind judges at Spearman 0.697, but treat that as a ceiling: the
inflated variants were written to order. The honest figure is real repo prose against
real unprompted assistant prose, which separates at 0.784. On outside data the reading
cost tracks human difficulty ratings at Spearman 0.53, ahead of every classic
readability formula, and it puts editor-graded texts in the right order for 186 of 189
articles. The 43 pattern rules with hand-built cases all reach precision 1.00 on them:
308 positives, 430 near-misses, and 407 adversarial passages written to make the rules
misfire. Five of the 48 rules have no cases yet. Method and numbers in
`evals/RESULTS.md`.

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
| `tool/` | the scorer; scoring imports only the standard library |
| `data/lexicon.tsv.gz` | 126,777 words with Zipf frequency, age of acquisition and concreteness |
| `data/norms/` | the sources the lexicon is baked from; nothing here is read at scoring time |
| `data/simpler.tsv` | hard word to plain replacement, shown as suggestions |
| `data/glossary.txt` | 444 terms that cost nothing |
| `data/weights.json` | the fitted cost model and the gate threshold |
| `evals/` | the corpora, the metrics, the tuner and the rule tests |
| `hooks/` | the guard wrapper, the detector holding the logic, the SessionStart health check, 32 hook tests, and the settings snippet |
| `selftest.sh` | proves the gate works on this machine; safe to run any time |
| `install.sh` | optional: puts a `pl` launcher on your PATH and runs the self test. The gate does not need it |
| `sync-to-monorepo.sh` | dotfiles copy only: pushes the skill into a repository that carries its own copy |
| `stage-in-repo.sh` | dotfiles copy only: stages the computed file list in a repo that gitignores `.claude`, because `git add -f` on the directory also stages the virtualenv and caches |
