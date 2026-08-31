# Norm sources

These build `../lexicon.tsv.gz` through `plainlang.bake`. Nothing here is read at
scoring time.

| File | Source | Licence |
|---|---|---|
| `aoa.csv.gz` | Kuperman, Stadthagen-Gonzalez & Brysbaert (2012), *Behavior Research Methods* 44(4). OSF `d7x6q`, `AoA_51715_words.xlsx`, column `AoA_Kup_lem`. | No explicit grant stated. Standard academic norm set; cite the paper. |
| `concreteness.csv.gz` | Brysbaert, Warriner & Kuperman (2014), *Behavior Research Methods* 46. Via github.com/ArtsEngine/concreteness, column `Conc.M`, single words only. | No explicit grant stated. Cite the paper. |
| `prevalence.csv.gz` | Brysbaert, Mandera, McCormick & Keuleers (2019), *Behavior Research Methods*. OSF `g4xrt`, column `Pknown`: the share of **native** respondents who know the word. | CC BY-NC-SA 4.0, see `license_osf_gakre.txt`. |
| `prevalence_l2.csv.gz` | Brysbaert, Keuleers & Mandera (2021), *Studies in Second Language Research*. OSF `gakre`, column `accuracy`: the share of **non-native** respondents who recognise the word. | CC BY-NC-SA 4.0, see `license_osf_gakre.txt`. |
| `evp_cefr.csv` | CEFR-J Vocabulary Profile v1.5, compiled by Yukio Tono, Tokyo University of Foreign Studies. github.com/openlanguageprofiles/olp-en-cefrj. A1 to B2 only. | Free for research and commercial use with attribution. |
| `voa_special_english.txt` | VOA Special English core word list, 1,477 words, via Simple English Wikipedia's copy. | Underlying list is US government work, public domain. |
| Zipf frequency | SUBTLEX-US through the `wordfreq` package, build time only, not stored here. | Apache 2.0. |

## The two prevalence files are here, and are not in the lexicon

Both are redistributed verbatim, with their licence text alongside, and attributed
above. Oystein ruled on 2026-08-31 that the non-commercial clause does not bite on
an internal engineering tool.

They are excluded from `lexicon.tsv.gz` for a different reason: **neither earned a
place, and the non-native one made the tool measurably worse.**

- The native version saturates, because it is normed on native speakers.
  `utilize`, `commence`, `seamless` and `handset` all sit at 0.99.
- The non-native version has real spread (`delve` 0.37, `quantization` 0.56,
  `latency` 0.70) and still lowered judge agreement, lowered agreement with human
  difficulty ratings, and raised false alarms at every weight tried. It measures
  what non-native speakers in general know, and these readers are domain experts,
  so it charges the vocabulary the glossary exists to protect.

Numbers in `../../evals/RESULTS.md` sections 13 and 16. Keeping the files here
means that experiment can be re-run; keeping them out of the derived lexicon means
no derivative work carries the share-alike obligation, which is the clause the
ruling above does not speak to.

To try it again: set `w_prev` in `data/weights.json`, add the column back in
`bake.py`, and rebuild. The `prev` field already exists in `lexicon.py`.
