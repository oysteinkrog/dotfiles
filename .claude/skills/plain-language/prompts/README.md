# Paste-anywhere versions of this rule

Each file here is one self-contained prompt for the Claude chat web app, where
none of this skill's tooling exists: no skill loaded, no scorer, no hooks, no
guaranteed second turn. One paste, one answer.

They are compressions, so they lose things. What each one keeps is the register,
the banned shapes, the rule that precision beats brevity, and a report the reader
can check. What they cannot do is measure, so there is no score and no findings
list. That is the point of asking for the report instead.

| File | For |
|---|---|
| `slide-deck.md` | rewriting a slide deck, in any language |

## Languages other than English

`slide-deck.md` is language-agnostic, and the way it gets there is worth knowing
if you write another one. The English word list ("use, not leverage") does not
travel. What travels is the split underneath it: every language has an everyday
register and a formal or learned one that sounds more serious and reads worse. So
the prompt states the split, asks the model to name it by its local name
(Norwegian kansellistil, Portuguese burocratês), and asks for the list of swaps
it made. A named register is checkable by a native speaker; "formal versus
informal" is not.

Three rules had to be generalized rather than copied, and one of them was wrong
on the first attempt:

- The em-dash ban became "no dash between words", with exemptions listed by
  mechanical job: a range, a paired name, a minus sign on a number. The first
  attempt exempted "where that language's normal typography uses a dash", which
  is a clause a model can honestly cite to keep the tell, because Spraakraadet
  sanctions the tankestrek for exactly the banned use. The ban holds anyway: the
  convention permits the dash and never requires it, so a rewrite that removes it
  is never wrong Norwegian.
- "No gerund openers" became "a title that opens with a verb form", which catches
  a gerund or infinitive title cheaply and misses the Norwegian action-noun title
  entirely. "Innføring av nytt CRM-system" is a noun phrase of four words that
  names its topic and opens on no verb, so nothing fired, and the noun-phrase
  mandate positively endorsed it.

  A ban on the action noun is the wrong fix. In 2,425 title-shaped Norwegian
  strings in this monorepo, 147 open with one and 86 of those are legitimate
  one-word labels: Kalibrering, Visning, Trykkfordeling. The morphology is not the
  problem. Neither is activity against subject, since Kalibrering is also an
  activity.

  What separates them is fit. A workstream title fits every slide in its project
  equally well; a real title fits only its own slide. "Optimalisering av
  kundereisen" fits them all, "Kalibrering" fits the calibration slide. The prompt
  asks that question directly, and the noun-phrase mandate now says "naming the
  slide's content" so the cheap shape gate cannot pass a title before the fit test
  runs.
- The padding list is marked as the English set, with an instruction to find the
  language's own.

Measured while writing it, on 3,190 Norwegian UI strings in this monorepo: 33
carry a dash, and 32 of those inherited it from an English source string that
already had one. Four are untranslated English. One dash in 3,190 was composed by
a Norwegian author. In this team's output the dash is an imported tell rather than
native punctuation. Caveat worth carrying: this is translated UI text, not deck
prose written from scratch, so it measures the pipeline rather than how Norwegians
write. It does not change the rule, because removing a permitted dash is never
wrong Norwegian.

## Rules that leave no legal move

Three of the five failures a review found were the same shape, and it is the one to
watch for in any prompt of this kind. A rule set can leave the model no legal move,
and it will then pick one silently.

Given "Sammen skaper vi fremtiden, en kunde av gangen", the line is a banned shape
so it cannot stay, cutting is forbidden, and "keep every fact" says nothing when
there is no fact. The review's own run produced "Vi fortsetter aa levere til
kundene vaare", which nothing in the deck supports. Given "Undersokelser viser
at...", stripping the vague attribution and keeping the claim turns hearsay into
our own asserted finding, which is less true than the original.

Both are fixed by giving the model something it is allowed to write: "[no content:
slogan]" in the rewrite column for the first, and the gap marked as "ifolge
[hvilken undersokelse?]" for the second. An earlier fix of mine banned the third
option as well and made the trap worse.

This is the failure a reader working in a second language is least equipped to
catch, because a fabricated sentence in fluent Norwegian reads as fine.
