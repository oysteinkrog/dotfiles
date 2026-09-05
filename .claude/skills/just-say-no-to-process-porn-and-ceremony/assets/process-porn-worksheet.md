# Process-Porn Worksheet

> The question this worksheet answers: **am I engaging in process porn and
> useless ceremony?**

Fill this out before creating any process artifact, or whenever a session
feels busy but ships nothing. Short truthful answers beat polished ones;
a worksheet filled out to look good is itself process porn. Answer with
zero ego: if the artifact you were excited to build turns out to be
ceremony, parking it is the win, not the loss.

Artifact or activity under examination: ______________________
Date/session: ______________________

## Part 1 — The Boundary Test

**Does running code branch on this artifact?**

- YES → it is product runtime state; building it is feature work. Record
  the verdict as FEATURE and stop here; Parts 2–4 do not apply.
- NO → only humans and status reports read it. It is process; continue to
  Part 2.

Code written or modified in order to make this answer YES does not count;
manufacturing a consumer to dodge the gate is itself the pathology (pattern
SM-10 in the skill's references/REWARD-HACKING-CATALOG.md).

## Part 2 — The Creation Gate (four questions)

Answer all four. Any blank or hand-waved answer means the artifact does not
get created (or gets parked now). An explicit operator request satisfies
Q1–Q3 (record the request as provenance), but Q4 must still be answered.

1. **Consumer.** Who or what reads this? Name the specific person, agent,
   or code path. "Future maintainers" and "the record" are not consumers.

   Answer: ______________________

2. **Gate.** What named feature or capability cannot ship without it?

   Answer: ______________________

3. **Observed defect class.** What defect that actually happened (not one
   you can imagine) does this prevent or catch? Cite the incident.

   Answer: ______________________

4. **Deletion condition.** When does this artifact get retired? An artifact
   with no retirement condition is permanent overhead.

   Answer: ______________________

## Part 3 — Integrity-Control Exception

A minimal crash-recovery file or provenance snapshot may not change a
decision, but may preserve the evidence needed to finish one. It is
legitimate only if the answers go the right way on ALL four: Q1 names a
concrete failure mode, Q2 is yes, Q3 is yes, and Q4 is no. Merely having
an answer is not passing.

1. What concrete evidence-loss, corruption, self-certification, or
   unrecoverable-failure mode does it prevent? ______________________
2. Is it required at this run's actual scale and risk? ______________________
3. Is it the smallest reliable artifact or check that does the job? ______________________
4. Is there a cheaper way to get the same protection? ______________________

## Part 4 — Opportunity Cost

1. What is the highest-priority ready capability item right now?

   Answer: ______________________

2. Would an hour spent on that item deliver more user-visible value than
   this artifact? (If yes, and Part 2 wasn't airtight: go do that instead.)

   Answer: ______________________

## Verdict

- [ ] FEATURE: running code branches on it (Part 1); build it as normal
      work.
- [ ] LEGITIMATE GATE: all four Part 2 answers are concrete; build the
      minimum version, record the deletion condition where it will be seen.
- [ ] INTEGRITY CONTROL: passes Part 3; build the minimal version only.
- [ ] CEREMONY: park it, note in the work item why it was stopped, and
      claim the highest-priority ready capability item.

## Red Flags While Filling This Out

- You wrote a paragraph where a sentence would do (justification inflation).
- The "consumer" is a report that itself has no consumer (ceremony chains).
- Your consumer/gate answers are copied from a stock self-justification
  (e.g., "the operator's report" / "my done-declaration") rather than
  argued for this specific artifact.
- The defect class is speculative ("could happen", "best practice").
- This is your second-or-later process artifact this session while the
  capability count has not moved. That is the meta-trap; stop entirely.
