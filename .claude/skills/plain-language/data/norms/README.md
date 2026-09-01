# Norm sources and word lists

The files here build `../lexicon.tsv.gz` through `plainlang.bake`, or exist so
an experiment recorded in `../../evals/RESULTS.md` can be re-run. Nothing in
this directory or in `../wordlists/` is read at scoring time. One file,
`../wordlists/ngsl.txt`, is read when a weight that ships off is turned on;
every other row below says exactly what reads it, and says plainly when the
answer is nothing.

## Files in this directory

| File | What it is | Licence | What reads it |
|---|---|---|---|
| `aoa.csv.gz` | Age of acquisition. Kuperman, Stadthagen-Gonzalez & Brysbaert (2012), *Behavior Research Methods* 44(4). OSF `d7x6q`, `AoA_51715_words.xlsx`, column `AoA_Kup_lem`. | No explicit grant stated. Standard academic norm set; cite the paper. | `tool/src/plainlang/bake.py`, at lexicon rebuild only. |
| `concreteness.csv.gz` | Concreteness ratings. Brysbaert, Warriner & Kuperman (2014), *Behavior Research Methods* 46. Via github.com/ArtsEngine/concreteness, column `Conc.M`, single words only. | No explicit grant stated. Cite the paper. | `tool/src/plainlang/bake.py`, at lexicon rebuild only. |
| `prevalence.csv.gz` | Word prevalence, normed on **native** speakers. Brysbaert, Mandera, McCormick & Keuleers (2019), *Behavior Research Methods*. OSF `g4xrt`, column `Pknown`. | CC BY-NC-SA 4.0, see `license_osf_gakre.txt`. | Nothing at build or scoring time. Kept on purpose so the experiment in RESULTS.md section 13 can be re-run: `bake.py` keeps its column read as a comment, and `w_prev` defaults to 0. |
| `prevalence_l2.csv.gz` | Word prevalence, normed on **non-native** speakers. Brysbaert, Keuleers & Mandera (2021), *Studies in Second Language Research*. OSF `gakre`, column `accuracy`. | CC BY-NC-SA 4.0, see `license_osf_gakre.txt`. | Nothing. Kept on purpose: RESULTS.md section 16 measured it, rejected it, and keeping the file means that measurement can be repeated. |
| `evp_cefr.csv` | CEFR-J Vocabulary Profile v1.5, 7,799 rows, A1 to B2. Compiled by Yukio Tono, Tokyo University of Foreign Studies. github.com/openlanguageprofiles/olp-en-cefrj. | Free for research and commercial use with attribution. | Nothing. Kept on purpose: RESULTS.md sections 13 and 16 measured CEFR-graded vocabulary and rejected it, and this file makes the experiment repeatable. |
| `voa_special_english.txt` | VOA Special English core word list, 1,477 words, via Simple English Wikipedia's copy. | Underlying list is US government work, public domain. | Nothing. Kept with `evp_cefr.csv` as clean data for a future learner-vocabulary experiment (RESULTS.md section 16, "What was kept"). |
| `license_osf_gakre.txt` | The CC BY-NC-SA 4.0 licence text for the two prevalence files. | n/a | People, not code. |
| Zipf frequency (not a file here) | SUBTLEX-US, through the `wordfreq` package at bake time. Not stored in this directory. | Apache 2.0. | `tool/src/plainlang/bake.py`, at lexicon rebuild only. |

## Files in `../wordlists/`

That directory has no README of its own, so its inventory lives here.

| File | What it is | Licence | What reads it |
|---|---|---|---|
| `ngsl.txt` | New General Service List, 2,801 words. Browne, Culligan & Phillips. | CC BY 3.0, with attribution. | `tool/src/plainlang/model.py` (`_load_wordset`), only when `w_core_free` is true, and it ships false. RESULTS.md section 13 measured the learner core-vocabulary free pass as neutral on every metric. Kept so the experiment can be re-run by setting `w_core_free` in `../weights.json`. |

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

## Removed on 2026-09-01

Five files were deleted after tracing every file in `.` and `../wordlists/`
against every `.py`, `.sh`, `.md`, `.json` and `.toml` in the skill. Nothing read
any of them, and no experiment in `../../evals/RESULTS.md` used any of them.

| File | Size | Where to get it again |
|---|---|---|
| `raw_cefrj_vocabulary_profile.csv` | 225 KB | github.com/openlanguageprofiles/olp-en-cefrj. Download scratch; `evp_cefr.csv` is the cut-down file the experiments used. |
| `raw_voa_special_english_wikitext.txt` | 136 KB | Simple English Wikipedia, the VOA Special English word list page. Download scratch; `voa_special_english.txt` is the extracted list. |
| `../wordlists/awl.txt` | 4.7 KB | Academic Word List, Coxhead (2000), victoria.ac.nz. |
| `../wordlists/basic_english_850.txt` | 5.3 KB | Ogden's Basic English, public domain, many copies online. |
| `../wordlists/dale_chall_3000.txt` | 18.7 KB | Dale-Chall familiar-word list, Chall & Dale (1995). Note that the Dale-Chall figure in RESULTS.md never came from this file: it is CLEAR's own pre-scored column. |

Reproduce the trace with, for each name:

```sh
grep -rIl 'dale_chall_3000' . --include='*.py' --include='*.sh' \
  --include='*.md' --include='*.json' --include='*.toml' | grep -v '\.venv\|evals/data'
```
