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

| Measure | Spearman, 900-excerpt sample | Spearman, all 4,724 |
|---|---|---|
| plainlang reading cost | **0.535** | **0.628** |
| New Dale-Chall | 0.504 | 0.597 |
| SMOG | 0.463 | 0.572 |
| CAREC | 0.459 | 0.578 |
| Flesch Reading Ease | 0.452 | 0.559 |
| Flesch-Kincaid Grade Level | 0.441 | 0.547 |
| Automated Readability Index | 0.401 | 0.518 |

The right-hand column is the whole corpus and is the figure to quote. The sample
column is kept because the numbers elsewhere in this file were measured on it.
Every measure rises on the full corpus, and the ordering does not change: the
tool leads the best classic formula by 0.031 either way.

**This is an in-sample number and must not be called external validation.** The
shipped weights were fitted on the in-house corpus and CLEAR at once, as section
3 says two paragraphs down, so CLEAR is training data. The honest outside checks
are OneStopEnglish, which the tuner never saw, and the blind judge panels.

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
| M7 agreement with CLEAR ratings | 0.628 on all 4,724, ahead of every classic formula by 0.031; in-sample, see section 3 | on a par |
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

## 16. The audience-matched norm, and why it still lost

Section 13 rejected word prevalence because the version in the lexicon is normed
on native speakers and saturates. That was the right reason but the wrong dataset:
a **non-native** version exists from the same group, and it is the one norm here
that actually matches the readers.

Obtained: Brysbaert, Keuleers & Mandera (2021), *Studies in Second Language
Research*, OSF `gakre`, the `accuracy` column, 61,851 words. It is the share of
non-native respondents who recognise the word.

It has the dynamic range the native version lacks:

| word | non-native | native |
|---|---|---|
| use | 0.99 | 1.00 |
| utilize | 0.91 | 0.99 |
| paradigm | 0.86 | 0.93 |
| commence | 0.75 | 0.99 |
| seamless | 0.76 | 0.99 |
| latency | 0.70 | 0.92 |
| quantization | 0.56 | 0.59 |
| delve | 0.37 | 0.92 |

`delve` at 0.37 is exactly the kind of separation the native norm could not make.

**And it made the tool worse at every weight.** Exempt words stay free, so this is
the charge applied only to words the model already charges:

| Configuration | AUC | judge | CLEAR | L2 ordering | false alarm |
|---|---|---|---|---|---|
| shipped | 0.999 | 0.702 | 0.671 | 186/189 | 15.1% |
| non-native prevalence, k=0.5 | 0.999 | 0.691 | 0.660 | 186/189 | 17.4% |
| non-native prevalence, k=1.0 | 0.999 | 0.685 | 0.644 | 186/189 | 18.6% |
| non-native prevalence, k=2.0 | 0.997 | 0.661 | 0.609 | 187/189 | 23.3% |
| CEFR-J B2 and above, k=0.4 | 0.999 | 0.694 | 0.672 | 185/189 | 16.3% |
| CEFR-J B2 and above, k=1.0 | 0.999 | 0.682 | 0.670 | 185/189 | 18.6% |

**The reason is in the table above it.** `latency` 0.70, `quantization` 0.56: the
norm is measuring what non-native speakers *in general* know, and these readers
are domain experts who know those words in English and use them daily. The signal
cannot tell a technical term from an inflated one, so charging it hits precisely
the vocabulary the glossary exists to protect. At k=2.0 it buys one article of
learner-graded ordering for eight points of false alarm.

This is the report's own recommendation 7, which it flagged as its least-supported
item and inferred rather than measured: do not price your own domain's vocabulary
with general-population norms. It is now measured.

### A harness bug that nearly produced the wrong reason

The first run of this experiment added the prevalence charge to *every* word,
including glossary terms, acronyms and proper nouns that the model exempts. It
showed false alarms jumping to 46.5% at k=2.0 and would have supported the same
conclusion for a reason that was an artefact of my own test code. The corrected
harness only ever adds to a word the base model already charges. The conclusion
survived; the reason changed.

### Licence

Both prevalence datasets are CC BY-NC-SA 4.0. Oystein ruled on 2026-08-31 that the
non-commercial clause does not bite on an internal engineering tool, so both files
are in the repository, redistributed verbatim with their licence text and
attribution in `data/norms/README.md`.

They stay out of `lexicon.tsv.gz` on the measurement above, not on the licence.
That has a side benefit worth naming: the shipped lexicon is a derived work, and
keeping this data out of it means no derived file carries the share-alike
obligation. Share-alike is about redistribution rather than commercial use, so it
is a separate question from the one that was ruled on.

The rebuilt lexicon is 126,777 words and 800 KiB, with no prevalence column.

Re-verified after the rebuild: separation 0.999, judge agreement 0.702, false
alarms 15.1%, learner-graded ordering 186/189, agreement with human difficulty
ratings 0.628 against Dale-Chall's 0.597 on all 4,724 excerpts, all 43 rules with
cases at precision 1.00.

### What was kept

`evp_cefr.csv`, the CEFR-J Vocabulary Profile (7,799 rows, A1 to B2, free for
commercial use with attribution) and `voa_special_english.txt` (1,477 words, US
government work, public domain). Neither is used by the model. They are kept
because they are cleanly licensed and are the obvious data for a future
learner-vocabulary experiment, and `data/norms/README.md` records every source and
licence.

## 17. Hook backtest on real session history

The rule tests say each pattern is precise on cases written for it. This says what
the gate does to real work. 84,340 tool calls and 9,238 final replies were pulled
from 2,500 session logs and replayed through the hook's own extraction and gate
logic. `evals/backtest_hook.py`.

### Bugs found first

**A crash that silently disabled the gate.** `_read_file_arg` built its pattern as
`-F|--file[= ]...`, and the alternation binds looser than the rest, so a bare `-F`
matched with no path captured and `Path(None)` raised. `awk -F,` is common, and the
guard fails open on any exception, so **every Bash command containing a bare `-F`
skipped the check entirely**. Fixed by wrapping the flag in its own group.

Worth noting how this hid: failing open is the right default for a guard, and it is
exactly what stopped this being visible. A hook that cannot break your session also
cannot tell you it is broken.

**CMake files scored as documents.** `PROSE_SUFFIXES` includes `.txt`, and
`CMakeLists.txt` ends in `.txt`. Its `#` comments were read as markdown headings, so
build files were refused for having slogan-shaped headings. Fixed two ways: a
name list for the well-known offenders, and a content check that treats a body as
code when at least a quarter of its substantive lines look like code. Verified not
to eat a real document that quotes a command.

### The tool-call path

| Tool | calls | carried text | refused | rate |
|---|---|---|---|---|
| Bash | 72,886 | 719 | 245 | 34.1% |
| Edit | 8,023 | 794 | 476 | 59.9% |
| Write | 1,629 | 474 | 358 | 75.5% |
| createJiraIssue | 180 | 180 | 38 | 21.1% |
| addCommentToJiraIssue | 172 | 161 | 55 | 34.2% |
| Artifact | 86 | 54 | 18 | 33.3% |
| Slack send / draft | 60 | 59 | 2 | 3.4% |
| **total** | **84,340** | **2,453** | **1,198** | **48.8%** |

Only 2.9% of tool calls carry text the gate looks at, and 1.42% of all tool calls
would have been refused.

### What the refusals are for

Refusals by cause, tool-call path:

| Cause | share |
|---|---|
| hard rule and low score together | 45.9% |
| em dash alone | 41.0% |
| short text, hard rule only | 6.5% |
| **low score only, no hard rule** | **6.5%** |
| another hard rule alone | 0.6% |

Stop path, 8,791 replies long enough to score, 69.6% sent back:

| Cause | share |
|---|---|
| hard rule and low score together | 62.7% |
| em dash alone | 35.6% |
| **low score only, no hard rule** | **1.6%** |
| another hard rule alone | 0.1% |

**93.5% of tool-call refusals and 98.4% of reply send-backs involve a hard rule**,
which for this corpus means an em dash. Those are true positives under the rule
Oystein reaffirmed on 2026-08-28. The score contributes 6.5% and 1.6%.

### Steady state, 9% not 70%

The 69.6% figure is high because history is full of the thing the rule bans. To
predict the steady state, em dashes in the same 8,791 replies were replaced with
the comma the skill tells you to use instead. Nothing else changed.

| Corpus | sent back | median score |
|---|---|---|
| history as written | 69.6% | 39 |
| the same text with em dashes replaced by commas | **9.0%** | **74** |

One mechanical substitution accounts for nearly the whole block rate. What remains
is 792 replies, 741 of them on score alone: the score failures that the hard rule
was previously masking.

So the honest forecast is about one reply in eleven getting sent back once the ban
is being followed, measured on text written before the register existed. Text
written with the skill should do better: in the end-to-end test, the arm that used
the skill had zero hard-rule hits.

Block rates already fell either side of the skill landing, on small samples:
tool calls 54.3% before to 39.0% after (n=210), replies 70.9% to 42.1% (n=401).

### Latency

Measured per invocation: 50 ms on the no-op path, 250 ms when it runs the scorer.
Across the same 2,500 sessions that is 1.6 s per session for the no-op path and
0.25 s for the scored path, so **about 1.9 seconds per session**. The no-op path
dominates because the hook is wired on every Bash call; it exits without invoking
the scorer unless it finds a commit message or a pull request body.

## 18. Em dash demoted, and what a hard rule now means

Oystein, 2026-08-31: *"em-dash is not that bad.. not sure if it should hard stop?
the goal here is to have humans actually understand things."*

Section 17 had just shown that em dash accounted for 93.5% of tool-call refusals
and 98.4% of reply send-backs. So the gate was almost entirely enforcing one rule,
and that rule contributes nothing to reading difficulty. It is not in the
reading-cost model at all, and the sweep below confirms it: agreement with human
difficulty ratings is flat at 0.626 whatever the em-dash cost.

An em dash marks writing as machine-made. It does not stand between a reader and
the meaning. Those are different goals, and the second one is now the stated one.

### The new definition of a hard rule

A hard rule is a **defect**: something objectively wrong in the text, whatever the
reader makes of the prose. Four survive:

| Rule | What it catches |
|---|---|
| `tool-artifact` | leaked chatbot citation markup: `oaicite`, `contentReference`, `turn0search3` |
| `tracking-url` | `utm_source=chatgpt.com` and friends left in a URL |
| `assistant-residue` | "As an AI language model", "as of my last update" |
| `unfilled-placeholder` | `[NAME]`, `[INSERT X]`, `Lorem ipsum` |

Demoted to priced warnings: `em-dash`, `not-x-its-y`, `not-only-but-also`. They
still cost budget and still appear as findings. Enough of them together takes the
score below the line, which is the intended mechanism: the score is the half
validated against how hard people actually find text to read.

### Pricing the em dash

Sweep at the shipped threshold of 34:

| em-dash cost | inflated text caught | plain rewrites blocked | repo prose blocked | judge agreement | CLEAR |
|---|---|---|---|---|---|
| 6.0 (the old near-veto) | 95.7% | 1.1% | 7.8% | 0.702 | 0.626 |
| **4.0 (shipped)** | **93.5%** | **1.1%** | **5.6%** | **0.697** | **0.626** |
| 2.5 | 88.2% | 1.1% | 4.4% | 0.691 | 0.626 |
| 1.5 | 77.4% | 1.1% | 4.4% | 0.683 | 0.626 |
| 0.0 | 64.5% | 1.1% | 4.4% | 0.662 | 0.626 |

4.0 puts it level with the other strong tells (`in-todays`, `testament`,
`broader-landscape` are all 4.0) instead of being the outlier at 6.0. Judge
agreement falling as the cost falls says the judges do react to em dashes, so it
is not free. CLEAR staying flat says it is not a reading-difficulty signal, so it
does not gate.

Read the 95.7% and 64.5% with care. The inflated variants were written to a prompt
that explicitly asked for em dashes, so how much of that corpus the em-dash rule
catches is partly a fact about my prompt. The backtest on real history is the
better guide.

### What it did to the scorecard

| Metric | before | after |
|---|---|---|
| separation, AUC | 0.999 | 0.997 |
| judge agreement | 0.702 | 0.697 |
| **false alarm on repo prose** | **15.1%** | **4.7%** |
| inflated text caught by the gate | 100% | 93.0% |
| the user's own chat prose refused | 29% | 13% |

**A third of the false alarms, for seven points of the catch rate**, and the catch
rate lost was the em-dash-driven part. This is the better trade for the stated
goal, and it is the direction the standing instruction not to be too strict
already pointed.

The threshold script reselected 34 independently after the change.

### A consequence worth stating

Short text is judged on defects alone, and there are no style defects any more. So
**nothing under 40 words is gated unless it contains leaked markup.** A 14-word
commit message with an em dash now goes through. That follows from the goal: a cost
per hundred words means nothing at fourteen words, and a fourteen-word line is
almost never why a reader fails to understand something. The pre-filter that used
to look for em dashes in short text now looks only for defect markers.

### The backtest, re-run

Same 84,340 tool calls and 8,791 replies, after the demotion:

| | before | after |
|---|---|---|
| tool calls refused | 1,198 (48.8% of text-carrying) | **451 (18.4%)** |
| share of all tool calls | 1.42% | **0.53%** |
| short text refused on a hard rule | 78 | **0** |
| replies sent back | 6,118 (69.6%) | **2,853 (32.5%)** |
| median reply score | 39 | **49** |

Refusals down 62% on the tool path and 53% on replies. The steady-state forecast,
the same replies with em dashes replaced by commas, is 8.6% and a median of 74,
essentially unchanged from before: the demotion cut the *transitional* cost of a
history full of em dashes, not the eventual rate.

### Two precision fixes this section forced out

Both were found by the tool refusing this file.

**A document that documents the defect rules tripped them.** Section 18 quotes
`utm_source=chatgpt.com` as an example of what `tracking-url` catches, and the
machine-residue rules run on the raw source so they can see inside URLs, which
means they also saw the example. Raw-surface rules now skip inline code spans as
well as fenced blocks: a marker in backticks is being quoted, a real leak appears
bare. Verified both ways.

**"the catch rate" is a measurement.** `why-it-matters` matched the bare noun in
"seven points of the catch rate". It now refuses to fire when the noun is followed
by rate, angle, block, word, clause or phrase.

## 19. The backtest number moves with the working directory

Section 17 reported a refusal count without saying which glossary produced it.
The same corpus, weights and rules give two different answers:

| Working directory | Project terms | Text-carrying calls | Refused | Rate | Replies sent back |
|---|---|---|---|---|---|
| `/c/WORK/desktop/master` | 6,938 | 2,361 | 452 | 19.1% | 2,853 of 8,948 (31.9%) |
| the skill directory, under `~/.dotfiles` | 0 | 2,360 | 876 | 37.1% | 4,218 of 8,948 (47.1%) |

`_discover_glossary()` in `model.py:154` walks up from the working directory
looking for `.plainlang/glossary.txt`. Both rows are the tool behaving as
designed, because per-repo domain terms are the point, and section 3 already
measured the effect: a domain glossary cuts false alarms on real repo prose from
23.3% to 15.1%. The defect was in the eval script, which printed neither the
working directory nor the glossary size, so two correct runs looked like one
measurement contradicting itself. `evals/backtest_hook.py` now prints the working
directory, the glossary size split by source, the weights file, `min_score`,
`max_errors` and the detector path before it reports anything.

The operational number is the first row, 452 refusals and 0.54% of all 84,340
tool calls, because the hook runs with the working directory of the session it is
gating, which is the monorepo.

**The detector half makes no difference.** Running the same corpus through the
superseded `hooks/plain-language-guard.py` and through `hooks/plain-language-detect.py`
gives identical results: 2,361 considered, 452 refused, 180 skipped as not
English, 2,853 replies sent back. The two files share their text-extraction code
exactly, which an AST comparison of every top-level function and constant
confirms; they differ only in how they reach the scorer, in process rather than
through a subprocess. So the numbers in section 17 and 18 are unaffected by the
restructuring.

**Every eval script now prints its own configuration.** Patching only the
backtest was not enough. One command after writing this section I ran the
scorecard from the skill directory instead of the monorepo and read 8.0% where the
real figure is 3.4%, and spent a while hunting a regression that did not exist.
`run.py` and `validate_external.py` print the working directory, the glossary size
split by source, `min_score` and `max_errors` before any result, the same as
`backtest_hook.py`. The two readings, same code, one command apart:

| | from the monorepo | from the skill directory |
|---|---|---|
| project glossary terms | 6,938 | 0 |
| M1 separation | 0.998 | 0.997 |
| M2 judge agreement | 0.709 | 0.693 |
| M3 false alarm on repo prose | 3.4% | 8.0% |
| M6 slop caught | 93.2% | 96.6% |
| CLEAR, all 4,724 | 0.628 | 0.637 |

Quote the left column. It is the configuration the hook runs in, because the hook
inherits the working directory of the session it is gating.

The CLEAR row is worth noticing on its own: the tool scores slightly BETTER on
CLEAR without the domain glossary, 0.637 against 0.628. That is the expected
direction and a small check on the glossary doing what it claims. CLEAR is
general-audience text rated by general readers, so a monorepo glossary exempts
words that really are hard for those readers. The glossary is there to stop
charging this team for vocabulary this team knows, which is a different job.

**One figure from section 17 does not reproduce.** That run reported 2,453
text-carrying calls and 451 refusals against the same corpus file. Re-running it
four ways, with each detector and from each working directory, never reproduces
2,453; the extraction path is identical in both detectors and the corpus file has
not changed since. The 452/2,361 figures above are the ones to use. Nothing in
the conclusions moves: the refusal rate is about 19% of text-carrying calls and
about half a percent of all calls either way.

## 20. Adversarial audit of the scorer, and eight fixes

Two Fable agents were given the code and told to break it with text nobody had
written for it. The scorer audit returned 12 confirmed defects. I reproduced each
one myself before acting on it, which mattered: one of the two worst was
overstated and one proposed fix was wrong.

### The eight defects

**The language test was a gate bypass in both directions.** This was the worst of
them, because a document called not English is scored not at all: the report comes
back 100 out of 100 with no findings.

Direction one, real English being waved through. A changelog of eight
`- Fixed force plate reconnect crash after USB unplug` bullets has an English
function-word share of 0.000, because terse lines carry no function words at all.
Norwegian prose scores 0.000 on the same test. So the changelog was declared not
English and never checked.

Direction two, one quoted paragraph exempting a whole file. The test measured the
share of Latin characters across the document, so appending a paragraph of Chinese
to an inflated English passage took it from 4.4 and a failed gate to 100 and no
findings. The share fell to 0.683, under the 0.85 threshold.

The audit reported this as "any document quoting a paragraph of CJK is silently
exempt". That is not quite true and the correction is worth recording: it depends
on the ratio. My first attempt to reproduce it failed, because a shorter quotation
left the share above the threshold. It takes roughly a paragraph against a
paragraph.

**The suggested fix for direction one did not work.** The audit proposed backing
the function-word test with a lexicon hit rate, on the reasoning that "the
changelog's tokens are ~100% lexicon hits, Swedish's are not". Measured, every
language tested hit 1.000, because `Lexicon.lookup` returns a `Norms` object with
`None` fields for an unknown word rather than returning `None`. The discriminator
that does work is the share of tokens carrying an English Zipf frequency:

| Sample | function-word share | Zipf-known share |
|---|---|---|
| English changelog, 8 terse bullets | 0.000 | 1.000 |
| English bullets, 2 words each | 0.000 | 1.000 |
| English headings only | 0.000 | 1.000 |
| English prose | 0.394 | 1.000 |
| Norwegian | 0.000 | 0.485 |
| Swedish | 0.000 | 0.515 |
| Portuguese | 0.061 | 0.606 |
| German | 0.061 | 0.667 |
| Norwegian, terse bullets | 0.053 | 0.316 |

English is 1.000 in every shape tried. The threshold is 0.85, which is `min_known_share`
in `weights.json`, and a document is now called not English only when both tests
fail. For non-Latin script, `segment.py` masks runs of 12 or more non-Latin letters
the way it masks code, so the English half of a mixed document is scored and only
a document with nothing left after masking is reported as another language. Twelve
is the floor so that a micro sign in a tolerance or a name with a diacritic stays
ordinary prose.

**A hard rule blocked this repository's own commit convention.** `unfilled-placeholder`
is one of the four rules that fail the gate at any length and any score.
"Commit bodies use the form Fixes: DESKTOP-XXXX so Jira links the issue" tripped
it, and that sentence is describing what `CLAUDE.md` tells everyone to write. The
trailer branch now needs a trailer position, line start or after a sentence end,
and needs to end its line. A real unfilled trailer still gates, in a bare line, a
bullet or a quote.

**A markdown blockquote was charged to the person quoting it.** The skill puts
quoted material out of scope and `"..."` quotations were already exempt, but `>`
blocks were not. `block_kind == "quote"` was computed in `segment.py` and read by
nothing. A three-sentence report quoting a vendor's marketing email scored 3.3 with
findings for `robust-hype` and `promo-adjectives`, on the vendor's words. It now
scores 94.3 with none, while writing the same sentences yourself still scores 2.9
with six findings.

**Four-space indentation hid a nested list.** CommonMark nests bullets and
continues list paragraphs at four spaces, and the indented-code mask took all of
it. An inflated paragraph written as a sub-bullet scored 100 with no findings. The
mask now requires the line not to start with a list marker. Fixing it also caught
a second bug in the same pattern: it matched exactly four spaces, so the deeper
line of a two-line indented code block was never masked at all.

**Fences had to be exactly three backticks.** Four is how you quote a block that
itself contains three, and the inner code leaked out and was scored as writing. The
pattern now takes three or more, requires the closer to be at least as long, and
follows CommonMark in running an unclosed fence to end of file.

**Bullets were charged for flat rhythm.** `uniform-rhythm` fires when sentence
length variance collapses. Bullets are parallel by design, so a ten-item release
note of two-word bullets scored 4 out of 100 on a measure that cannot apply to it.
List items are now left out of the rhythm measure. Paragraphs of one length are
still charged.

**Short text got a grade the gate ignored.** The rate is cost per 100 words, so one
hard word in a 21-word release note reads as 32 per 100 and the score reads as an F.
The hook has always applied a 40-word floor and judged short text on the four defect
rules alone. The scorer now carries that floor as `min_scored_words`, `Report.scorable`
reports it, and `pl check` no longer fails what the hook allows. It says
"too short to score, 21 words of 40 needed" instead of printing a letter grade.

**`title-case-heading` fired on any three plain words.** This one was found by
running the gate on this section. `_r` applies `re.I` by default, so `[A-Z][a-z]+`
matched lowercase words too and the rule reported every ordinary sentence-case
heading of three or more words as Title Case. "What it costs on real history" and
"Defects reported and not yet fixed", both headings below, were flagged. It is
compiled case-sensitively now. Fixing that exposed a second bug in the same
pattern: `[a-z]+` needs two characters, so a one-letter word ended the run and
"Why The Capture Lifecycle Needs A Second Pass" was missed. With `[a-z]*` the rule
reaches 7 of 7 on its own cases, up from 6, and an all-caps acronym heading still
does not match.

The rule's precision was already reported as 1.00 on 18 hand-built cases. It was
firing on most of this document's headings at the same time. The lesson is the one
this file keeps relearning: cases written for a rule cannot tell you what the rule
does to text nobody wrote for it.

### The A/B against the committed code

| Metric | before | after | |
|---|---|---|---|
| M1 separation, AUC plain vs slop | 0.997 | 0.998 | better |
| M2 judge agreement, Spearman | 0.697 | 0.709 | better |
| M3 false alarm on real repo prose | 4.7%, n=86 | 3.4%, n=88 | better |
| M4 pair accuracy | 100% | 100% | held |
| M6 slop caught by the gate | 93.0% | 93.2% | better |
| CLEAR, all 4,724 excerpts | 0.628 | 0.628 | unchanged |
| OneStopEnglish, all three in order | 186/189 | 186/189 | unchanged |

The control was the committed version of `model.py`, `segment.py`, `rules.py` and
`cli.py` in a scratch copy, run against the same corpora in the same working
directory, so the glossary and the weights were identical.

M3's denominator grew from 86 to 88 because two repo passages that the language
bug had been skipping are now scored, and the false-alarm rate fell anyway.

### What it costs on real history

Replaying the same 84,340 historical tool calls:

| | before | after |
|---|---|---|
| refused | 452, 19.1% of text-carrying calls | 517, 21.9% |
| share of all tool calls | 0.54% | 0.61% |
| skipped as not English | 180 | 23 |
| chat replies sent back | 2,853, 31.9% | 2,940, 32.9% |

157 items stop being silently exempt and 65 more are refused, so about 41% of the
newly-checked text fails, against 19% overall. That is the expected direction: what
the language bug was exempting was mostly short commit messages carrying an em dash.

### Regression tests

Twenty-six tests were added, taking the suite from 44 to 70. Eighteen of them fail
against the committed code, which is how I know they test something. Two of those
twelve fail on the old code only because they read `known_share` and `latin_share`
from the stats dict, which the old code does not report; the other ten catch real
behaviour. The eight that pass on both are the other-direction guards, the cases a
fix could break: writing hype yourself still fails, genuinely flat prose still
fires, a real unfilled trailer still gates, real indented code is still masked, and
a document wholly in another script is still skipped.

### Defects reported and not yet fixed

From the same audit, reproduced but left for now, with the reason:

- `PASSIVE` charges a copula followed by any word ending in `-en`, so "the port is
  open", "the build is green" and "he is often late" are charged. The `-ed` half is
  sound. The fix is to replace the open-ended pattern with the irregular-participle
  list the regex already carries.
- `"..."` quotations lose their exemption when hard-wrapped across a line, because
  the pattern excludes newlines.
- `QUESTION_HEAD` flags any heading whose first word collides with an auxiliary, so
  "CAN bus wiring" and "Do not use in production" read as questions.
- A possessive escapes all lexical cost: "paradigm" costs 1.95 and "paradigm's"
  costs 0.
- The em-dash rule charges correct en-dash typography in "Oslo-Bergen" and
  "May-June" ranges when written with an en dash.
- A UTF-8 BOM defeats heading detection, so the skill's own canonical example
  heading escapes the rule when the file carries one.
- The `of course,` branch of `needless-to-say` is unreachable: it ends in `\b`
  after a comma, which cannot match before a space.

Lazy and full lexicon loading were checked for divergence and found identical:
same score, rate and findings on eight real documents, and 0 mismatches on a
4,000-word lookup sweep. That mattered because the hook uses one and the evals use
the other.
