# Measuring the plain-language scorer

Every weight in the model is fitted against labelled data, and every rule is
measured against cases written to break it. This directory holds the data, the
metrics and the scripts.

## Goal metrics

| Metric | What it answers | Target |
|---|---|---|
| M1 separation | Can the score tell a plain rewrite from an inflated one? Reported as AUC over plain/slop pairs. | at least 0.95 |
| M2 judge agreement | Does the score track what a blind judge thinks? Spearman between score and (clarity minus AI smell). | at least 0.60 |
| M3 false alarm | How often does the gate stop writing that was already fine? Measured on untouched repo prose. | at most 25% |
| M4 pair accuracy | Share of passages where the plain rewrite outscores the inflated one. | at least 95% |
| M6 slop caught | Share of inflated rewrites the gate refuses. | at least 95% |
| M7 external agreement | Spearman against human difficulty ratings in the CLEAR corpus, next to the classic formulas. | on a par with the best formula |
| M8 graded ordering | Share of OneStopEnglish articles whose three editor-graded levels come out in the right order. | at least 90% |
| M9 rule precision | Per rule, share of hits that are real, on cases written to break it. | at least 0.95 |
| M10 rule recall | Per rule, share of real cases caught. | at least 0.70 |

M3 is weighted hardest in review, because over-strictness is the failure this
project exists to avoid. A gate that blocks good writing gets switched off, and
then it protects nothing.

## Data

| File | What it is | How it was made |
|---|---|---|
| `data/passages.json` | 96 real technical passages | Sampled from this repo's docs and commit bodies, English only, 40 to 260 words. |
| `data/variants.json` | each passage in three registers, plus two blind judge panels | 12 agents rewrote each passage plain and inflated, keeping a fact list. 24 judge runs then scored all three variants blind, with the register hidden behind rotated tag letters. |
| `data/human_writing.json` | 150 messages the user typed himself | Filtered from session logs. Used as a diagnostic, not a target: chat typing is not the register the skill governs. |
| `data/rule_cases.json` | 308 positives, 430 near-misses, 300 adversarial cases | Written per rule by agents, then attacked by a second pass told to make each rule misfire on correct technical writing. |
| `data/external/clear.csv` | 4,724 excerpts with continuous human difficulty ratings | The CLEAR corpus (Crossley et al. 2022). Ships every classic formula's score on the same text, so we can compare directly. |
| `data/external/onestop.jsonl` | 189 articles at three editor-graded levels | OneStopEnglish, CC BY-SA 4.0. |

The registers are named `plain`, `wild` and `slop`. `wild` is the untouched
original, which is the honest false-alarm sample: real writing nobody has
complained about.

## Scripts

```sh
python run.py                       # the scorecard
python run.py --tune --clear 250    # fit weights against both corpora at once
python threshold.py --budget 0.10   # pick the gate threshold from the ROC
python rulecheck.py                 # per-rule precision and recall
python rulecheck.py --show em-dash  # every miss and false alarm for one rule
python try_pattern.py em-dash '<regex>'   # try a candidate without editing rules.py
python ablate.py                    # per-rule hits by register
python ablate.py --groups           # does each rule group pay for itself
python validate_external.py         # CLEAR and OneStopEnglish
python backtest_hook.py --calls <toolcalls.json> --replies <replies.json>
python backtest_hook.py --calls ... --dump-blocked 40   # read what it refused
```

`backtest_hook.py` replays real historical tool calls and replies through the
hook's own extraction and gate logic, in process. It is the only test here that
measures what the gate costs rather than whether it is right, and it found two
bugs the rule tests could not: a crash on `awk -F,` that made the guard fail open
for every command containing a bare `-F`, and CMake files being scored as prose
because `CMakeLists.txt` ends in `.txt`.

Its input comes from a session-log extractor and is not committed: those files
hold the contents of real commits, documents and messages.

## How the fitting works

Weights are searched by hill climbing with a cooling step size. The objective is
threshold-free on purpose: separation, judge agreement and pair accuracy, plus
the external CLEAR correlation, plus soft terms that keep the score on a scale a
person can read. The gate threshold is chosen afterwards from the curve, by
fixing a false-alarm budget and taking the threshold that catches the most.

Two weights are capped on evidence rather than fitted freely. The passive-voice
penalty is capped low because the published comprehension effect is small and
conditional, and applies mainly to agentless passives. Without the cap the
search inflates it, because the inflated rewrites happen to use passives, which
is a fact about the corpus and not about reading.

Fitting only on the in-house corpus overfits. An earlier run reached 0.976 AUC
here while its agreement with human difficulty ratings on the CLEAR corpus fell
from 0.511 to 0.408. The external term in the objective is what stops that.
