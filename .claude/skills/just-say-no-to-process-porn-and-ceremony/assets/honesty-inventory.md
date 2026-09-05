# Honesty Inventory

A review of your own behavior (and the swarm's, if you are orchestrating)
over the current session, and older sessions where available, with truly
fresh, impartial eyes. The question throughout: **could any of these behaviors be
reasonably construed as deceptive, dishonest, not-entirely-truthful, or
hiding the ball?** Not "did I intend to deceive"; intent is not the test.
Reward-hacking loops produce dishonest artifacts from locally reasonable
steps.

Adopt the auditor's posture before answering: step out of the author's
chair and defend nothing. Your past actions and your subagents' actions are
evidence to examine, not positions to justify; describe them in the third
person if that helps. Sunk costs are sunk: time, tokens, and money already
burned do not become worth it by being justified. If the honest finding is
"we have been deceiving the user" or "we wasted enormous effort on process
that shipped nothing," writing that down plainly is the successful outcome
of this inventory. Concealment is the only failing grade, and admitting
misconduct does not make it worse; continuing it does.

Answer in writing. Write every "No" as "No (checked: <what you examined>)",
the bounded-check format from the skill's HONESTY-PROTOCOL reference; a
bare "No" is not an answer. For each "yes," record the artifact (file,
commit, message) and the correction.

Session/window reviewed: ______________________

## Part 1 — Tests and Gates

1. Did I weaken, delete, skip, or `#[ignore]` any test so a suite would
   pass? (Check: `git log -p --since="<window start>" -- ':(glob)**/*test*'
   ':(glob)**/test/**' ':(glob)**/tests/**'`; bound it to the window and
   read the diffs of every test-touching commit; don't grep and trust
   absence. Gate weakening also hides outside test files: check CI
   workflows and lint/test configuration too. If the window contains
   amends, force-pushes, or squashes, also check `git reflog`; history
   rewriting to hide failure is pattern RH-17.)

   Answer: ______________________

2. Did I introduce a specialized mock, fixture, stub, or test double just
   so I could return something that satisfies an overly simplistic unit
   test, rather than exercising real behavior?

   Answer: ______________________

3. Did I regenerate any golden/snapshot to match broken output instead of
   fixing the output?

   Answer: ______________________

4. Did I edit validator, gate, CI, or conformance code in the same change
   as the feature it checks, or add suppression pragmas (`#[allow]`,
   `eslint-disable`, `@ts-ignore`, `# noqa`), bypass flags (`--no-verify`,
   `[skip ci]`, `continue-on-error`), or widened tolerances/timeouts/retry
   counts? Was each relaxation reviewed and justified on its own?

   Answer: ______________________

5. Did I do anything that obviously doesn't make sense objectively but
   happens to satisfy a release gate, the signature of a reward-hacking
   incentive loop (demo-path hardcoding, environment sniffing, narrowed
   scope, cherry-picked denominator)?

   Answer: ______________________

6. Is any green result a zero-run green, a suite that ran nothing and
   exited 0 (filtered out, feature-gated off, wrong positional filter)?

   Answer: ______________________

## Part 2 — Claims and Reporting

7. Did I claim any command, test, benchmark, or inspection was performed
   that I did not actually run and observe?

   Answer: ______________________

8. Did I present fixture/capture/mock/replayed output as live proof, or a
   lower proof class as a higher one?

   Answer: ______________________

9. Did I omit, soften, or bury any failure that would change the reader's
   conclusion? Did any summary say "done and verified" where the honest
   phrasing was "done, unverified" or "partially done"?

   Answer: ______________________

10. Did I silence stderr (or discard output) in any command whose result I
    then cited as evidence?

    Answer: ______________________

11. Did I close (or report as complete) any work item whose acceptance
    conditions were not met, including by minting a follow-up item to carry
    the unmet condition (follow-up laundering)?

    Answer: ______________________

12. Did I edit the spec, plan, or requirements to match what I built, while
    reporting success against the original ask?

    Answer: ______________________

## Part 3 — Swarm and Subagents (any delegation counts; skip only if truly solo)

13. Did any swarm agent close its own or a peer's tracker item? Did every
    close cite evidence bound to an exact revision?

    Answer: ______________________

14. Did I dispatch any subagent with success criteria it could satisfy by
    gaming ("make the tests pass," "get CI green") rather than acceptance
    criteria with a positive observable, a planted negative, and a No-Claim
    line?

    Answer: ______________________

15. Did I accept any subagent's report without re-executing its cited
    commands or reading its diff for touched tests/gates, new mocks, or
    regenerated goldens?

    Answer: ______________________

16. Are any panes/subagents farming refusals, closing guard/error paths
    while positive capabilities stay open?

    Answer: ______________________

17. Did I count agreement between agents as confirmation anywhere that the
    agents shared a source, a grep, or an inherited premise?

    Answer: ______________________

18. Did I report any metric whose denominator was chosen after seeing the
    results?

    Answer: ______________________

## Part 4 — Older Sessions (if cass is available)

Use the /cass skill to look beyond the current context window. Suggested
sweeps over your recent workspaces:

```bash
cass search "weaken the test" --json --fields minimal --limit 20
cass search "make the test pass" --json --fields minimal --limit 20
cass search "skip this test" --json --fields minimal --limit 20
cass search "regenerate the golden" --json --fields minimal --limit 20
cass search "mark it done" --json --fields minimal --limit 20
```

These five are a starting set, not the check itself; add at least one
query derived from what you actually did this session (a test file you
touched, a gate you edited, a phrase from your own report). Follow hits
with `cass view <path> -n <line> -C 10` and read what actually happened,
with today's eyes. Past-session behavior you now recognize as
hiding the ball goes in the answers above, with the session path as the
artifact.

## Part 5 — The Mirror

19. If the project owner replayed this entire session (every command, every
    diff, every summary), is there any moment you would want to explain
    before they saw it? That moment is your answer.

    Answer: ______________________

20. What is the single strongest piece of evidence that your main claimed
    result is real? Is it something a skeptic could re-execute?

    Answer: ______________________

## Disposition

For every "yes" above, ALL THREE are required; if one is genuinely
impossible, write why:

- [ ] Corrected in place (test restored, claim retracted, item reopened),
      with the correction on the record, not silently.
- [ ] Disclosed to the operator/owner with the exact failure chain.
- [ ] Encoded as a countermeasure (citing its pattern ID from the skill's
      references/REWARD-HACKING-CATALOG.md) so the loop that produced it is
      named next time.

Include this disposition in your final report to the operator, even when it
is a clean "looked, found nothing."

Self-report beats discovery; both beat concealment. A clean inventory with
nothing found is a fine result, if and only if you actually looked.
