# Measurement results

Every number here comes from a script in this directory and can be re-run.
Dates are 2026-08-30 and 2026-08-31.

## 1. Effect of the written guidance

The skill landed on 2026-08-27 as prose, in the skill file and in the global
CLAUDE.md, with the em-dash ban stated as a hard rule. To see whether that
changed anything, 16,165 assistant messages of 50 to 400 words were pulled from
the local session logs and scored by month.

| Window | n | median score | share containing an em dash | style tells per passage |
|---|---|---|---|---|
| May 2026 | 900 | 64.4 | 59.8% | 1.87 |
| June 2026 | 900 | 58.0 | 61.9% | 1.60 |
| July 2026 | 900 | 51.5 | 71.1% | 2.22 |
| 1 to 26 Aug, before the skill | 900 | 49.4 | 76.2% | 2.82 |
| 28 to 31 Aug, after the skill | 270 | 49.9 | 74.1% | 2.60 |

The em-dash rate did not move: 74.1% after versus 76.2% before, z = -0.72, which
is not significant. AUC for "after scores better than before" was 0.526, where
0.5 is chance.

Read it carefully. This is observational, the after window is three days and 270
passages, and the mix of tasks changes over time. But the em-dash rate is a
direct measure of a hard rule that was already written down, and it did not
change. That is the case for a gate rather than another paragraph of guidance.

## 2. Comparison with the classic readability formulas

Checked against the CLEAR corpus: 4,724 excerpts with continuous human
difficulty ratings, which ships every classic formula's score on the same text.
Spearman against the human rating, 900-excerpt sample, magnitudes compared
because some formulas score ease and some score difficulty.

| Measure | Spearman |
|---|---|
| plainlang reading cost | **0.535** |
| New Dale-Chall | 0.504 |
| SMOG | 0.463 |
| CAREC | 0.459 |
| Flesch Reading Ease | 0.452 |
| Flesch-Kincaid Grade Level | 0.441 |
| Automated Readability Index | 0.401 |

On OneStopEnglish, 189 news articles each rewritten by editors at three levels,
the model puts all three in the right order for 186 of 189 articles (98.4%,
sign test p = 3e-51). Median cost per 100 words: elementary 5.97, intermediate
8.97, advanced 12.33.

## 3. Overfitting to the in-house corpus

Three weight sets, same code:

| Weights | in-house AUC | CLEAR Spearman | OneStopEnglish ordering |
|---|---|---|---|
| hand-set defaults | 0.974 | 0.458 | 96.3% |
| fitted on the in-house corpus only | 0.976 | **0.341** | 93.7% |
| fitted on both at once | 0.974 | **0.535** | 98.4% |

The in-house-only fit gained 0.002 AUC on its own corpus and lost 0.117 of
agreement with human difficulty ratings. It had learned that inflated writing
uses passives and long sentences, which is a fact about the prompt that produced
the corpus, not about reading. The passive-voice weight is now capped low on
evidence grounds, since the published comprehension effect is small and applies
mainly to agentless passives.

## 4. Effect of the domain glossary

The obvious worry with exempting technical vocabulary is that it blunts the
detector. It does the opposite, because domain words are noise for the
distinction that matters.

| Glossary | terms | AUC | judge agreement | false alarm on repo prose |
|---|---|---|---|---|
| none | 0 | 0.955 | 0.631 | 59.4% |
| shipped list only | 1,712 | 0.967 | 0.656 | 40.6% |
| shipped plus per-repo list | 8,221 | 0.974 | 0.666 | 27.1% |

Returns flatten past about 7,000 terms. The per-repo list is generated from
words appearing at least 60 times in the repo's own docs with a Zipf frequency
below 3.3.

## 5. Source of the gating power

Threshold sweep on the eval set, after excluding text under 40 words because the
hook never scores it:

| | slop | plain rewrite | untouched repo prose | user's chat prose |
|---|---|---|---|---|
| has a hard-rule hit | 98.9% | 0.0% | 11.1% | 32.0% |
| refused at min score 34 | 100% | 1.1% | 7.8% | 36% |

Raising the score threshold buys almost nothing: the hard rules already stop
98.9% of inflated writing, and every extra point of threshold costs real repo
prose. The threshold is therefore set low, at 34, chosen as the highest value
that keeps score-driven refusals of real repo prose under 8%.

The 11.1% of repo prose with a hard-rule hit is almost entirely em dashes. Those
are true positives under the stated rule, not false alarms.

## 6. Final scorecard

Weights `data/weights.json`, glossary shipped plus this repo's, 86 passages that
clear the 40-word floor in all three registers, 150 chat messages.

| Metric | Value | Target |
|---|---|---|
| M1 separation, AUC plain vs slop | 0.999 | 0.95 |
| M2 judge agreement, Spearman | 0.706 | 0.60 |
| M3 false alarm on repo prose | 15.1% | 25% |
| M4 pair accuracy | 100% (p = 3e-26) | 95% |
| M6 slop caught by the gate | 100% | 95% |
| M7 external agreement, CLEAR | 0.535, ahead of every classic formula | on a par |
| M8 graded ordering, OneStopEnglish | 98.4% | 90% |

Median scores: plain rewrite 84.4, untouched repo prose 83.1, inflated rewrite
15.5.

**Treat M1 as a ceiling, not a claim.** The inflated variants were written to
order, so they carry the tells the rules look for. The honest number is the
natural-corpus test: real repo prose (median 82.8) against real unprompted
assistant chat prose from the session logs (median 38.8) separates at AUC 0.784,
n = 90 and 886. Some of that gap is genre rather than quality, because chat and
documentation do not read alike.

## 7. Per-rule precision and recall

The A/B corpus only exercises the rules the slop prompt happened to use, so each
rule also has hand-built cases: 308 positives, 430 near-misses, and 300
adversarial passages written by a separate pass told to make each rule misfire on
correct technical writing. `rulecheck.py` reports precision and recall per rule.

Two fixes came straight out of that harness and improved the em-dash rule from
0.78 to 1.00 precision:

- Text inside a quotation of three or more words is now exempt from every prose
  rule, because the skill puts quoted material out of scope. An em dash in a
  quoted Jira comment is the writer reporting, not writing.
- An en dash between digits is a range, not punctuation, so `pages 4-7` no
  longer fires.

Three rules had to move off the masked prose and onto the raw source, because
their evidence lives inside URLs and code-ish spans that the scorer blanks:
chatbot citation markup, tracking parameters, and unfilled placeholders. Before
that fix `tracking-url` scored 0 out of 6 on its own positives.

## 8. Value of each rule group

Leave-one-group-out on the eval corpus:

| Group switched off | change in objective | change in AUC | change in judge agreement |
|---|---|---|---|
| hard (em dash) | -0.48 | -0.025 | -0.048 |
| shapes (the banned-shapes table) | -0.34 | -0.013 | -0.045 |
| artifacts (chatbot residue) | 0.00 | 0.000 | 0.000 |
| extra (second-tier shapes) | -0.01 | 0.000 | -0.002 |
| mined (from other rule packs) | -0.01 | 0.000 | -0.001 |

The em-dash rule is the single largest contributor to the signal, and also the
single largest source of false alarms: switching it off would cut refusals of
repo prose by 9.4 points. That trade is the user's stated choice, so it stays.

The last three groups measure as worthless **on this corpus**, which does not
contain chatbot citation markup or the constructions they target. That is a gap
in the corpus, not evidence the rules are useless, which is what the hand-built
cases are for. They are kept at low cost and their value is reported from
`rulecheck.py` instead.
