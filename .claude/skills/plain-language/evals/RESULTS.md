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
correct technical writing.

After two repair rounds, **all 43 rules reach precision 1.00** on those 738
cases, at 94% aggregate recall (288 of 308 positives). The first round reached
full recall and zero false alarms on the near-misses; a fresh adversary then
broke every rule with new passages, those 107 passages were added as negatives,
and the second round fixed all of them without losing recall.

The repairs that generalise beyond one rule:

- **Quoted text is out of scope for every prose rule.** A quotation of three or
  more words is skipped. An em dash in a quoted Jira comment is the writer
  reporting, not writing. This alone took the em-dash rule from 0.78 to 1.00.
- **An en dash between digits is a range**, not punctuation, so `pages 4-7` no
  longer fires.
- **Three rules run on the raw source**, not the masked prose, because their
  evidence lives inside URLs and code-ish spans: chatbot citation markup,
  tracking parameters, and unfilled placeholders. Before that fix `tracking-url`
  scored 0 of 6 on its own positives. Fenced blocks stay exempt even for those,
  so a bug report about a leaked citation marker can quote one.
- **A verb list is not enough to spot a slogan heading.** Nearly every common
  English verb is also a common noun, so "Value of each rule group" tripped the
  rule through "rule". The clause test now needs a determiner or pronoun subject
  in front of the verb. "The Phone Stays Mounted" still fires; "Force plate
  calibration" does not.
- **Anchor on grammar, not vocabulary.** The false alarms that survived round one
  were almost all a word used in its other part of speech: "helper functions as
  the last step" against "functions as", "the shear webs at the core of the
  plate" against "at its core", "in order, to subscribers" against "in order
  to", "leverage at impact" as a biomechanics measurement, "a leading role in six
  scenes" as casting. The fix each time was to require the surrounding
  construction, never to delete the word.

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

## 9. Which parts of the cost model earn their place

Same weights, one component switched off at a time. CLEAR agreement is over a
600-excerpt sample.

| Configuration | in-house AUC | judge agreement | CLEAR agreement |
|---|---|---|---|
| Zipf frequency only | 0.999 | 0.732 | 0.545 |
| Zipf + age of acquisition | 1.000 | 0.711 | 0.627 |
| Zipf + concreteness | 0.999 | 0.729 | 0.553 |
| all three (shipped) | 1.000 | 0.708 | 0.631 |
| no word cost at all | 1.000 | 0.761 | 0.424 |
| no sentence cost | 0.996 | 0.667 | 0.588 |
| no plain-synonym multiplier | 0.999 | 0.707 | 0.628 |

Four things fall out of this, and two of them are uncomfortable.

**Age of acquisition is the one norm that pays.** It adds 0.082 to external
agreement on top of frequency. Concreteness adds 0.008 on top of that, because it
is largely telling you the same thing: rare late-learned words are usually the
abstract ones. It is kept because it is already in the table and costs nothing to
compute, not because the measurement supports it.

**The in-house AUC cannot tell these apart.** Every configuration sits at 0.996
to 1.000, including the one with no word cost at all. The pattern rules alone
separate that corpus, so AUC on it is saturated and useless for comparing model
variants. Only the external correlation discriminates. This is the strongest
argument in this file for keeping outside data in the loop.

**Word cost slightly hurts agreement with the judges.** Judge agreement is
highest (0.761) with the word cost switched off entirely. The judges were scoring
clarity minus AI smell, which is a style judgement, and word difficulty is not
what they were reacting to. Word cost is kept because it is what makes the
reading-cost half of the tool externally valid: without it, CLEAR agreement
collapses from 0.631 to 0.424, below every classic formula. The two halves of the
tool answer different questions and neither metric alone should drive the design.

**The plain-synonym multiplier does not measurably pay.** Charging extra for a
hard word that has a plain synonym is the mechanism that makes the model
opinionated without banning anything, and it changes nothing on these corpora
(0.631 versus 0.628, AUC unchanged). It is kept because it is principled and
cheap, and because the corpora may not contain the case it is for: text that uses
"utilize" and "commence" while carrying none of the other tells. That is an
honest gap in the evidence, not a result.

## 10. Non-English text

Running the gate over 120 real documentation files refused 48% of them, which
would have made it unusable. The cause was not strictness. Most of this repo's
`docs/` tree is translated support articles, and the scorer was charging Swedish,
Dutch, Finnish, Russian, Japanese and Chinese text as rare, unknown English.

The fix is two cheap checks before scoring. A document whose letters are less
than 85% Latin script is not English. A document of 30 words or more where fewer
than 13% of tokens are among the 30 commonest English function words is not
English either. Ordinary English prose runs 25 to 50% on that measure;
translated articles run at 0%.

After the fix, on the same 120 files: 114 are correctly identified as not
English and skipped, 6 are English with a median score of 85, and one of the six
would be refused, for a single em dash.

This is the kind of defect only running the tool on real material finds. Neither
the eval corpus nor the hand-built rule cases contained a word of Swedish.

## 11. Chasing the score makes the writing worse

The end-to-end test. Twenty-four notes were written from the same fact lists,
three ways, and two blind judge panels ranked all three without knowing how any
was produced.

| Arm | How it was written | tool score | clarity | AI smell | fidelity | title | best | worst |
|---|---|---|---|---|---|---|---|---|
| A | no guidance | 72.0 | 7.94 | 4.50 | 9.77 | 8.54 | 22 | 6 |
| B | skill text only | 83.3 | **8.75** | **3.77** | 9.62 | 6.96 | 25 | 3 |
| C | skill plus up to five rounds of raising the score | **84.9** | 7.35 | 4.65 | 9.69 | 6.38 | 1 | **39** |

48 best-of-three votes. C was picked best once and worst 39 times, against A
p = 6e-06 and against B p = 8e-07. Its tool score was the highest of the three.

**The score went up and the writing got worse.** That is Goodhart's law arriving
on schedule, and it is the most useful thing this project measured. The gap
between B and A on preference is not significant (25 versus 22, p = 0.77), so on
this evidence the skill text alone is about as good as no guidance for a model
that already writes carefully, and the harm comes entirely from optimising the
number.

What the C agents actually did, from reading the outputs:

- **Stripped backticks off identifiers.** "This adds KeyMetricInfoFlyoutControl"
  where A and B wrote `` `KeyMetricInfoFlyoutControl` ``.
- **Chopped sentences into fragments.** "It takes all of that from
  IKeyMetricInfoFlyoutVM alone. No card. No Popup host."
- **Made titles blander and dropped identifiers out of them.** "The info flyout
  content control" against A's "Info flyout content control (bd-938.23)". Title
  quality fell from 8.54 to 6.38, and the no-guidance arm had the best titles of
  the three.

Each of those raises the score. Every one of them costs the reader. The model
cannot see any of it: it charges words, sentences and patterns, and it has no way
to know that a bead id in a title is information rather than an expensive rare
word.

Three changes followed:

1. The skill now says plainly that the score is a thermometer and not a target:
   run the checker once, fix the findings you agree with, leave the ones you think
   are wrong, and stop.
2. The hook's message says the same thing, and names the three specific moves that
   raise the score and hurt the reader.
3. The gate threshold stays low (34), so the score barely gates anything on its
   own. The hard rules do the gating, which is what section 5 already showed.

A fourth arm is measured separately: skill text plus one checker pass fixing only
the findings, with the number ignored. That tests whether the findings help when
they are not being optimised against.
