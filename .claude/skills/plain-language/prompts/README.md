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
- "No gerund openers" became "a title that opens with a verb form". This still
  misses the Norwegian action-noun title, and the fix is in progress.
- The padding list is marked as the English set, with an instruction to find the
  language's own.

Measured while writing it, on 3,190 Norwegian UI strings in this monorepo: 33
carry a dash, and 32 of those inherited it from an English source string that
already had one. Four are untranslated English. One dash in 3,190 was composed by
a Norwegian author. In this team's output the dash is an imported tell rather than
native punctuation.
