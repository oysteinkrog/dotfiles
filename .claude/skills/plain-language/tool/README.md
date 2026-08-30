# plainlang

Scores English prose against the `plain-language` skill and reports what to fix.

```sh
pl check draft.md        # findings with line and column; exit 1 if the gate fails
pl score docs/*.md       # one line per file
pl explain draft.md      # where the cost went
pl json draft.md         # the full report
echo "$BODY" | pl check -
```

## What it measures

Three things, added together as a cost per 100 words, then mapped to a score out
of 100.

**Word cost.** A word costs more when it is rare, learned late in life, and
abstract. Rarity comes first: it gates the other two, so a common abstract word
like "enough" is free while a rare abstract one like "paradigm" is not. The
numbers come from published norms, baked into `data/lexicon.tsv.gz`:

| Source | What it gives | Coverage |
|---|---|---|
| SUBTLEX-US via `wordfreq` | Zipf frequency | 131,793 words |
| Kuperman, Stadthagen-Gonzalez & Brysbaert (2012) | age of acquisition, in years | 51,694 |
| Brysbaert, Warriner & Kuperman (2014) | concreteness, 1 to 5 | 37,057 |
| Brysbaert, Mandera, McCormick & Keuleers (2019) | prevalence, share who know the word | 61,852 |

Nothing is banned. A hard word is expensive, never impossible, so you can spend
budget on a word that earns it.

Precision is free. A word costs nothing if it is in a glossary, an acronym, a
proper noun, a number, or inside code, a path, a URL, or a quotation.

What costs extra is unearned difficulty. If a hard word has a plain synonym that
means the same thing, it gets a multiplier, from `data/simpler.tsv`.

**Sentence cost.** Length above about twenty words, agentless passives, and
sentences that never change length.

**Tells.** Pattern rules for the constructions the skill bans: em dashes,
"not X, it's Y", significance tails, hype vocabulary, chatbot residue. Each has
a cost. Three of them run on the raw source rather than the masked prose,
because their evidence lives inside URLs and code-ish spans.

## Layout

```
src/plainlang/
  segment.py   markdown-aware splitting; blanks code, links, paths, front matter
  lexicon.py   the baked norm table, loaded lazily so a hook pays ~40 ms
  rules.py     the pattern rules, in four groups
  model.py     the cost model and the document scorer
  cli.py       the pl command
  bake.py      rebuilds data/lexicon.tsv.gz from data/norms/
tests/         39 tests: segmentation, word cost, every rule group, gate behaviour
```

## Rebuilding the lexicon

Only needed when a norm file changes.

```sh
uv run --with wordfreq python -m plainlang.bake \
  --norms ../data/norms --out ../data/lexicon.tsv.gz
```

`wordfreq` is a build-time dependency only. Scoring uses the standard library.

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
