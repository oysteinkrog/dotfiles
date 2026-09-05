# Question of Record — RS-<YYYYMMDD>-<slug>

## Question
<one sentence — the research question>

## Paradox
<2-3 sentences identifying the contradiction or open question that motivates this research.
Per ◊ Paradox-Hunt: "If A is true, then B should be impossible. But B is observed. So either A is wrong, B is misobserved, or there's a hidden mechanism."
If you cannot identify a paradox, the question is too vague — return to MO-01-frame-question.md.>

## Falsifier
<what observation O, if seen, would prove (a) the question is malformed OR (b) is already answered.
Must be: observable (not "if math broke"), decidable (not "if it became philosophically wrong"), reachable in the session's wall-time budget.>

## Scope
<bullet list of what's IN scope; ≤8 bullets>

- ...
- ...

## Out of Scope
<equally important — prevents Phase 4 drift>

- ...
- ...

## Mode
<fresh-question | code-investigation | corpus-distillation | resume-session | methodology-drift-check | incident-investigation>

## Provenance
<where the question came from — user ask, prior session, paradox in corpus, incident, etc.>

## Stakes
<2-3 sentences: what action depends on the answer; how would different verdicts change downstream actions>

## Initial paradox bead

H-000 (origin: anomaly_spawned, state: proposed):

```yaml
claim: <restate the paradox as a claim>
mechanism: <the hidden mechanism the paradox suggests>
falsifier: <what would prove the paradox is illusory>
expected_evidence: <what would confirm the hidden mechanism>
category: phenomenological
origin: anomaly_spawned
confidence: speculative
parent: Q-001
session: RS-<YYYYMMDD>-<slug>
```

---

## Self-test

Before exiting Phase 1, verify:

1. [ ] Could a hostile reader misread "Out of Scope"? If yes, sharpen.
2. [ ] Is the falsifier observable in <1 hour by an investigator?
3. [ ] Could two reasonable people disagree on what "Scope" means?
4. [ ] Does the paradox actually motivate the question, or is it post-hoc?
5. [ ] What action changes if the answer is X vs Y vs Z?

If any of (1)–(5) fails, return to MO-01-frame-question.md and tighten.
