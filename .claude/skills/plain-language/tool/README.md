# plainlang

Scores English prose against the `plain-language` skill and reports what to fix.

```sh
pl check draft.md        # findings with line and column; exit 1 if the gate fails
pl score docs/*.md       # one line per file
pl explain draft.md      # where the cost went
pl json draft.md         # the full report
echo "$BODY" | pl check -
```

`pl` is the optional launcher `../install.sh` puts on your PATH. Nothing needs
it: scoring imports only the standard library, so the equivalent with no
install is `PYTHONPATH=src python3 -m plainlang.cli check -`, which is how the
hook calls it.

## What it measures

Three things, added together as a cost per 100 words, then mapped to a score out
of 100.

**Word cost.** A word costs more when it is rare, learned late in life, and
abstract. Rarity comes first: it gates the other two, so a common abstract word
like "enough" is free while a rare abstract one like "paradigm" is not. The
numbers come from published norms, baked into `data/lexicon.tsv.gz`:

| Source | What it gives | Coverage |
|---|---|---|
| SUBTLEX-US via `wordfreq` | Zipf frequency | 126,777 words |
| Kuperman, Stadthagen-Gonzalez & Brysbaert (2012) | age of acquisition, in years | 51,693 |
| Brysbaert, Warriner & Kuperman (2014) | concreteness, 1 to 5 | 37,055 |

The lexicon has a `prev` (word prevalence) column and it ships empty: both
prevalence norms were measured and made the tool worse. The data and the
numbers are in `../data/norms/README.md` and `../evals/RESULTS.md` sections 13
and 16.

Nothing is banned. A hard word is expensive, never impossible, so you can spend
budget on a word that earns it.

Precision is free. A word costs nothing if it is in a glossary, an acronym, a
proper noun, a number, or inside code, a path, a URL, or a quotation.

A hard word with a plain synonym gets that synonym shown as a suggested fix,
from `data/simpler.tsv`. It is a suggestion, not an extra charge: the cost
multiplier it used to carry was measured and removed (`../evals/RESULTS.md`
section 15).

**Sentence cost.** Length above about twenty words, agentless passives, and
sentences that never change length. Headings cost when they read as a sentence
rather than a name, ask a question, or open on a participle.

**Tells.** Pattern rules for the constructions the skill bans: em dashes,
"not X, it's Y", significance tails, hype vocabulary, chatbot residue. Each has
a cost. Three of them run on the raw source rather than the masked prose,
because their evidence lives inside URLs and code-ish spans.

## What gates and what only costs

Four defects stop a write: leaked chatbot citation markup, a tracking parameter in
a URL, chat-assistant boilerplate, and an unfilled `[NAME]` placeholder. They are
wrong whatever the reader makes of the prose.

Everything else is priced. An em dash costs 4 points, the same as the other strong
tells, and does not stop anything on its own. Measured on 84,340 real tool calls
and 8,791 real replies, that change cut refusals by 62% on writes and commits and
53% on chat replies, and took false alarms on real repo prose from 15.1% to 4.7%.

Nothing under 40 words is gated unless it contains a defect. A cost per hundred
words means nothing at fourteen words.

## Second-language readers

Every human reader here has English as a second language, Norwegian or Brazilian
Portuguese first. That was tested rather than assumed, using OneStopEnglish, whose
three levels are graded for English learners.

It changed less than expected. The model already orders learner-graded text
correctly for 186 of 189 articles. Two candidate additions were measured and both
lost: word prevalence normed on non-native speakers, and CEFR-graded vocabulary.
Both charge domain terms, because a general-population norm cannot tell `latency`
from `utilize`, and these readers are domain experts who know `latency`.

What it did change: nothing is charged for being a Latinate word any more. There
used to be a cost multiplier on words with a plain synonym, and it is gone. No
controlled-language standard written for non-native readers penalises a word for
being Latinate, and for a Portuguese reader the Latinate word is usually the
cognate and so the easier one: "utilize" is a cognate of *utilizar*. Removing the
multiplier changed no measured metric. Twelve suggestions went with it, the ones
that replaced a Latinate cognate with a phrasal verb: `implement` to *carry out*,
`ascertain` to *find out*, and ten more. Details in `../evals/RESULTS.md` section 15.

The known gap: object relative clauses have the best-quantified second-language
penalty in the literature and need a parser this tool does not have.

## Domain terms

Put terms that should cost nothing in `<repo>/.plainlang/glossary.txt`, one per line.
The scorer walks up from the working directory to find it, or from
`PLAINLANG_PROJECT` when set. 444 general technical terms ship with the skill in
`../data/glossary.txt`; this repo adds 6,938 of its own. Adding a domain
glossary improves the tool rather than weakening it: on the eval corpus it cuts
false alarms on real repo prose from 23.3% to 15.1% and raises judge agreement from
0.688 to 0.705, because domain vocabulary is noise for the distinction that matters.

Adding or growing a glossary changes the score and the findings for the same
text. That is intended, not the tool going soft. The same document scores higher
inside a repo that has a glossary than outside one. Domain terms stop being
charged; nothing else relaxes.

To regenerate one for a repo, from the skill directory:

```sh
python evals/build_corpus.py --repo <repo> --glossary
```

That keeps words appearing at least 60 times in the repo's own docs whose Zipf
frequency is below 3.3.

## How the gate runs

There is no install step, no virtualenv, no pip, no network. The scorer imports
only the Python standard library, so the hook runs it with bare `python3`
(3.12 or newer) and a `PYTHONPATH`. `../selftest.sh` checks this by importing the
scorer with bare python3, outside any virtualenv. It works on a fresh clone.
The earlier design needed an installed launcher, which meant the gate silently
did nothing on any machine where nobody ran the installer, and a guard that
quietly stops working is worse than no guard.

The gate is wired in two places at once: `~/.claude/settings.json` and the host
repository's `.claude/settings.json`. Both point, through one-line forwarder
scripts, at the same `../hooks/plain-language-guard.sh`. When both fire on the same
text, a short-lived decision cache keyed on the payload replays the first result
instead of scoring twice.

`plain-language-guard.sh` only finds a python3 and the skill; all the logic is
in `plain-language-detect.py`, and `plain-language-guard.test.py` holds its 32
cases. A SessionStart hook, `plain-language-health.sh`, proves once per session
that the gate can refuse bad text and pass good text, and prints a warning when
it cannot. That check exists because the gate fails open on error, and a guard
that fails open silently looks exactly like a guard that is working.

## Layout

```
src/plainlang/
  segment.py   markdown-aware splitting; blanks code, links, paths, front matter
  lexicon.py   the baked norm table, loaded lazily so a hook pays ~40 ms
  rules.py     the pattern rules, in five groups
  model.py     the cost model and the document scorer
  cli.py       the pl command
  bake.py      rebuilds data/lexicon.tsv.gz from data/norms/
tests/         44 tests: segmentation, word cost, every rule group, gate behaviour
```

## Rebuilding the lexicon

Only needed when a norm file changes.

```sh
uv run --extra bake python -m plainlang.bake \
  --norms ../data/norms --out ../data/lexicon.tsv.gz
```

`wordfreq` lives in the optional `bake` extra and is a build-time dependency
only. Scoring uses the standard library; `../selftest.sh` checks this by
importing the scorer with bare python3, outside any virtualenv.

## Retuning

The weights in `data/weights.json` are fitted, not chosen. See `../evals/`.

```sh
python ../evals/run.py                       # the scorecard
python ../evals/run.py --tune --clear 250    # fit against both corpora
python ../evals/threshold.py --budget 0.10   # pick the gate threshold
python ../evals/rulecheck.py                 # per-rule precision and recall
python ../evals/ablate.py --groups           # does each rule group pay for itself
python ../evals/validate_external.py         # CLEAR and OneStopEnglish
```
