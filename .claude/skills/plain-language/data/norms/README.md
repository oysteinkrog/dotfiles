# Norm sources

These build `../lexicon.tsv.gz` through `plainlang.bake`. Nothing here is read at
scoring time.

| File | Source | Licence |
|---|---|---|
| `aoa.csv` | Kuperman, Stadthagen-Gonzalez & Brysbaert (2012), *Behavior Research Methods* 44(4). OSF `d7x6q`, `AoA_51715_words.xlsx`, column `AoA_Kup_lem`. | No explicit grant stated. Standard academic norm set, cite the paper. |
| `concreteness.csv` | Brysbaert, Warriner & Kuperman (2014), *Behavior Research Methods* 46. Via github.com/ArtsEngine/concreteness, column `Conc.M`, single words only. | No explicit grant stated. Cite the paper. |
| `evp_cefr.csv` | CEFR-J Vocabulary Profile v1.5, compiled by Yukio Tono, Tokyo University of Foreign Studies. github.com/openlanguageprofiles/olp-en-cefrj. A1 to B2 only. | Free for research and commercial use with attribution. |
| `voa_special_english.txt` | VOA Special English core word list, 1,477 words, via Simple English Wikipedia's copy. | Underlying list is US government work, public domain. |
| Zipf frequency | SUBTLEX-US through the `wordfreq` package, build-time only. | Apache 2.0. |

## Word prevalence is deliberately absent

Both versions were obtained, tested and removed:

- Native: Brysbaert, Mandera, McCormick & Keuleers (2019), OSF `g4xrt`.
- Non-native: Brysbaert, Keuleers & Mandera (2021), OSF `gakre`, column `accuracy`.

**Both are CC BY-NC-SA 4.0.** That is non-commercial, and share-alike would attach
to any file built from them, including `lexicon.tsv.gz`. This repository is public
and the skill is intended for company-wide use, so the licence is wrong on both
counts.

It also earned nothing. The native version saturates because it is normed on
native speakers. The non-native version has real spread (`delve` 0.37,
`quantization` 0.56, `latency` 0.70) but charges domain vocabulary the readers
know, because they are domain experts: at every weight it lowered judge agreement
and agreement with human difficulty ratings and raised false alarms, without
improving the learner-graded ordering. Numbers in `../../evals/RESULTS.md`
sections 13 and 16.

The prevalence columns stay in the code (`w_prev` in `weights.json`, the `prev`
field in `lexicon.py`) so the measurement can be repeated by anyone who obtains
the data themselves under its own licence.
