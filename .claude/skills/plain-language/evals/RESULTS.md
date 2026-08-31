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

Measured on the shipped configuration: fitted weights, the 444-term curated list
that ships with the skill, and this repo's own 6,891-term generated list.

| Glossary | terms | AUC | judge agreement | false alarm on repo prose |
|---|---|---|---|---|
| none | 0 | 0.998 | 0.688 | 23.3% |
| shipped list only | 444 | 0.999 | 0.691 | 19.8% |
| shipped plus per-repo | 7,197 | 0.999 | 0.705 | **15.1%** |

The per-repo list is generated from words appearing at least 60 times in the
repo's own docs with a Zipf frequency below 3.3:
`python evals/build_corpus.py --repo . --glossary`.

**The first version of this experiment reported much larger effects**, and the
difference is worth recording. Run on hand-set weights against a 1,712-term
draft glossary, it showed 0.955 to 0.974 AUC and 59.4% down to 27.1% false
alarms. Two things changed after it: the weights were fitted, and the shipped
list was rebuilt as 444 hand-checked terms instead of 1,712 mined ones. Fitted
weights absorb much of what the glossary was doing, so the glossary's marginal
effect is now smaller. The direction is the same in both runs and on every
metric, and the glossary still cuts false alarms by a third, but the large
numbers belonged to the untuned configuration and should not be quoted for the
shipped one.

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

## 12. The findings help; the number is what hurt

A fourth arm was run to separate the two: skill text plus **one** checker pass,
fixing the findings the writer agreed with, leaving the ones it thought were
wrong, and never looking at the number. Judged blind against arms A and B by two
fresh panels.

| Arm | tool score | clarity | AI smell | fidelity | title | best | worst |
|---|---|---|---|---|---|---|---|
| A no guidance | 72.0 | 7.50 | 4.17 | 9.58 | **8.27** | 13 | 27 |
| B skill text only | 83.3 | 8.54 | 4.00 | 9.52 | 6.33 | 5 | 13 |
| D skill + findings, number ignored | 82.0 | **8.54** | **3.83** | 9.35 | 8.00 | **30** | **8** |

48 best-of-three votes. D over A: 30 to 13, p = 0.014. D over B: 30 to 5,
p = 2e-05.

D carries a **lower** tool score than the score-chasing arm (82.0 against 84.9)
and than the skill-only arm, and it is the one people want. Across 24 notes it
fixed 19 findings and deliberately kept 53, with a reason each time: "viable" is
the spec's own word in open question 5, "variance" is the statistical term the
peer-review result is stated in, the title-case hit comes from an identifier.
Roughly three quarters of the findings were rejected on judgement, and that is
the intended use.

Two caveats. The judge panels differ between the two experiments, so A's and B's
absolute numbers move between the tables; only the comparisons inside one
experiment are sound. And both experiments use the same 24 fact lists.

Put the two results together and the design falls out of the evidence:

- **The findings are the product.** Each one names a specific thing to look at,
  and a writer with judgement gets a real gain from reading them.
- **The number is a thermometer.** It exists to decide whether the gate opens.
  Optimised, it drives out exactly the specifics that make writing useful.
- **The right instruction is "run it once".** Not "until it passes", and never
  "until the score stops improving".

## 13. Second-language readers

Learned after the model was fitted. The writers and readers are Norwegian and
Brazilian Portuguese first-language speakers. The obvious question is whether the
cost model needs a different set of norms.

**OneStopEnglish is the right corpus to answer it.** Its three levels are graded
for English *learners*, not native readers, so it is the closest thing here to L2
ground truth. Tested on 189 articles at all three levels:

| Configuration | all three in the right order |
|---|---|
| shipped model | **186/189** |
| plus word prevalence, weight 1.0 | 186/189 |
| plus word prevalence, weight 2.0 | 185/189 |
| plus a learner core-vocabulary free pass (NGSL, 2,801 words) | 186/189 |
| plus both | 186/189 |
| with age of acquisition removed | 184/189 |
| with concreteness removed | 185/189 |

**Neither candidate change earns its place.** Word prevalence (Brysbaert et al.
2019, the share of people who report knowing a word) sounded like the most
L2-relevant norm available. It is not, for a measurable reason: it is normed on
native speakers and saturates. Of the words in the shipped lexicon that have a
value, almost all ordinary vocabulary sits between 0.92 and 1.00, so it separates
"words native speakers do not know" from everything else and little more.
`utilize` is 0.99, `commence` 0.99, `seamless` 0.99, `handset` 0.99. Only
genuinely obscure terms move (`quantization`, 0.59). Adding it also raised false
alarms from 15.1% to 17.4% and cost judge agreement, which is the wrong direction
for this audience.

The learner core-vocabulary pass is neutral on every metric. Both are implemented
and shipped switched off (`w_prev`, `w_core_free` in `data/weights.json`), so the
measurement can be repeated rather than taken on trust.

**Age of acquisition transfers, which was not obvious.** It is normed on native
speakers, so it might not have described learner difficulty at all. Removing it
costs two articles on the L2-graded ordering (186 to 184) and 0.082 of agreement
with human difficulty ratings (section 9). It stays.

**Both halves of the cost carry L2 signal, and they are complementary.** Word cost
alone orders 179 of 189; sentence cost alone 169; together 186.

**The sentence-length threshold is already right for this audience, and the
published cap is too loose.** Sweeping it against the learner-graded ordering:

| free sentence length | all three ordered |
|---|---|
| 10 words | 186/189 |
| 12 | 186/189 |
| **14 (shipped)** | **186/189** |
| 18 | 185/189 |
| 22 | 184/189 |
| 26 | 183/189 |

The fitted value of 14 sits on the plateau. The UK GDS guidance caps sentences at
25 words; on this corpus 26 costs three articles against 14. The tuner reached 14
from the in-house corpus and the CLEAR ratings alone, without seeing
OneStopEnglish, so this is independent agreement rather than a circular fit.

**What the L2 fact does change** is not the word-cost norms but the rule set and
the register guidance: idioms and phrasal verbs are the best-evidenced L2 reading
difficulty and there is no detector for them, and the plain-English preference for
short Anglo-Saxon words over Latinate ones is not audience-neutral when half the
readers speak a Romance language. Both are handled in section 14.

## 14. What editors actually do when they simplify for learners

The Latinate question is the one that worried me most. Plain-English guidance
prefers the short Anglo-Saxon word: use over utilize, help over facilitate. For a
Romance-language reader that is backwards, because the Latinate word is a cognate
of their own (*utilizar*, *facilitar*), so it may be the easier one. Half this
team reads Portuguese as a first language and half Norwegian, and the two pull in
opposite directions.

OneStopEnglish answers it without any new data. Professional editors rewrote the
same 189 articles at three learner levels, so what they removed on the way down is
evidence about what they believe makes text hard for learners.

Medians per 100 words, and a paired direction test across all 189 articles:

| Feature | elementary | intermediate | advanced | elementary below advanced |
|---|---|---|---|---|
| rare words (Zipf below 3.5) | 3.16 | 3.53 | 4.50 | 174/189, p = 2e-35 |
| Latinate-suffixed words | 1.76 | 2.29 | 2.48 | 151/189, p = 4e-17 |
| phrasal verbs | 0.53 | 0.59 | 0.65 | 112/187, p = 0.008 |

**The plain-English preference survives.** Editors simplifying for learners strip
Latinate words, strongly and consistently. That is direct evidence against the
worry that the cognate effect reverses the guidance for this audience. Two honest
limits: this shows what editors do, not what readers measurably find easier, and
OneStopEnglish is a British ELT resource with a mixed-L1 learner population, so it
cannot isolate the Portuguese-L1 subgroup. It is the best evidence available here,
not proof.

**Rare words are the workhorse**, which is what the frequency term already
carries.

**Phrasal verbs get no rule, on the measurement.** The direction is right and
learner-simplified text does use slightly fewer, but the effect is about half the
size of the other two, and my detector has visible false positives ("started
about", "give on" are verb-plus-preposition coincidences, not phrasal verbs).
Technical English also depends on them: set up, roll back, log in, check out. A
rule built on a detector this noisy, against an effect this small, would cost more
in false alarms than it earns. Recorded as a measured decision, not an oversight.

An earlier run of this experiment reported a median of 0.00 phrasal verbs at every
level. That was a broken detector, not a finding: the pattern required the verb and
particle to be adjacent, so it missed every "set the flag up". Worth writing down,
because a zero from a detector is the shape a real absence takes.

## 15. Correction to section 14, and the resulting changes

Section 14 concluded from the OneStopEnglish editors that "the plain-English
preference survives". **That inference was wrong, and the reason is worth
recording.**

A research pass afterwards found Thrush (2001, *Technical Communication*), which
tested the plain-English Germanic-over-Latinate rule directly across first-language
groups. European-language readers scored much higher on the Latinate originals than
Asian-language readers, and French speakers given a straight choice preferred the
Latin-derived word over its Germanic synonym. It also found that **no controlled
language standard written for non-native readers carries an Anglo-Saxon preference
at all**: not ASD-STE100, not VOA Special English, not ISO 24495 or 24620. The rule
appears only in general-audience Plain English Campaign guidance.

The flaw in my experiment: it measured what British ELT editors *do*, and British
ELT house style is downstream of the same convention. So the result cannot separate
"editors strip Latinate words because it helps learners" from "editors strip
Latinate words because their style guide says to". It looked like evidence for the
convention and was partly an echo of it. The 151-of-189 figure stands as a fact
about editors; it is not evidence about comprehension.

### The measurable consequence

The model carried a Latinate penalty in three places. Every removal was measured
first, on all four metrics at once:

| Configuration | AUC | judge | CLEAR | L2 ordering | false alarm |
|---|---|---|---|---|---|
| shipped before | 0.999 | 0.703 | 0.673 | 186/189 | 15.1% |
| drop the 12 phrasal-verb suggestions | 0.999 | 0.704 | 0.673 | 186/189 | 15.1% |
| drop all 100 Latinate suggestions | 0.999 | 0.702 | 0.672 | 186/189 | 15.1% |
| drop the unearned-difficulty multiplier | 0.999 | 0.703 | 0.671 | 186/189 | 15.1% |
| drop the Latinate charge on unknown words | 0.999 | 0.703 | 0.673 | 186/189 | 15.1% |

**Every option is identical to three decimal places.** The Latinate machinery was
doing nothing measurable, so removing it costs nothing and aligns the model with
the only evidence that speaks to this audience. Now shipped:

- `w_latinate` is 0. An unknown word is no longer charged for a Latinate suffix.
- `unearned_mult` is 1.0 and `unearned_floor` is 0. A word is no longer charged
  extra merely for having a plainer synonym. The synonym is still shown as a
  suggestion when the word is charged on frequency grounds, so the advice survives
  without the etymology penalty.
- Twelve suggestions are deleted from `simpler.tsv`, the ones whose replacement was
  a phrasal verb: `accelerate` to *speed up*, `implement` to *carry out*,
  `ascertain` to *find out*, `establish` to *set up*, `collaborate` to *work with*,
  `prioritise` to *focus on*, and six more. Those Latinate originals are
  transparent cognates in Portuguese, and phrasal verbs are a documented
  second-language difficulty, so the suggestion made the text harder for the real
  audience. This is the one place where the two problems compounded.

### Rules tried and removed

Recorded so nobody adds them back by reasoning from the literature alone.

| Rule | precision | why it went |
|---|---|---|
| `false-friend` (actually / eventually / actual) | 0.80 | The entire effect was the single word "actually", 17 of 20 hits, and its real problem is padding rather than false friendship. "eventually" never fired. Restricting to sentence-initial position dropped it to zero hits. |
| `double-negation` | 0.58 | Fired on plain rewrites almost as often as on inflated ones, so it does not discriminate. |

Both are below the 0.95 precision every other rule is held to. The reasoning is
kept as a comment in `rules.py` next to where they were.

### What is still not addressed

- **Object relative clauses** have the best-quantified second-language penalty in
  the literature (one study reports 91% comprehension on subject relatives against
  46% on object relatives). Detecting them needs a parser, and this tool has none.
  This is the largest known gap.
- **Non-native word prevalence.** The prevalence norm in the lexicon is the
  native-speaker one, which is why it saturates (section 13). A separate
  non-native dataset exists from the same group, correlating about r = .85 with the
  native ranking, and the 15% where they disagree is exactly where it would earn
  its weight. Not yet obtained, so not yet tested.
- **Per-first-language cognate discounts** were recommended and are not
  implemented. They would need a Portuguese and a Norwegian cognate list, and no
  way to measure the benefit with the corpora here.
