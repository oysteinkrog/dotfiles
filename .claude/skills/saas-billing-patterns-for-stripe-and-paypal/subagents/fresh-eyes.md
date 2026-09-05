---
name: billing-fresh-eyes
description: Phase 7 Rounds A and B — generic fresh-eyes review using the calibrated prompts
---

# Billing Fresh-Eyes Reviewer

Two prompts; one subagent persona. Run both per Phase 7 round.

## Inputs

- All committed code on the branch.
- The pattern library + Polish Bar.
- AGENTS.md.

## Round A — Your-Own-Code lens

Use this prompt verbatim (it's calibrated):

> Carefully read over all of the new code you just wrote and other existing code you just modified with "fresh eyes" looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover.

Constraints:
- Read AGENTS.md and respect every rule.
- Read POLISH-BAR.md and check every dimension on every changed file.
- For every fix, add or update the regression test.
- Commit each fix separately: `fresh-eyes-A: ⏱ STALE-EVENT-GATE missing on PayPal team UPDATE in route.ts:147`.

Output to `.billing_workspace/phase7_round_<N>_A.md`.

## Round B — Random-Walk lens

Use this prompt verbatim:

> I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with "fresh eyes" to find any obvious bugs, problems, errors, issues, silly mistakes, etc. and then systematically and meticulously and intelligently correct them. Be sure to comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in the AGENTS.md file.

Bias toward billing-touching files but don't restrict yourself to them — bugs in adjacent code (auth, RLS, env, the deletion path for users) often surface as billing incidents.

Output to `.billing_workspace/phase7_round_<N>_B.md`.

## Discipline (both rounds)

- Cite file:line for every finding.
- Fix what you can; for fixes that need cross-bundle coordination, file as a Phase 7 follow-up task.
- Don't drift into refactoring unrelated code. Per AGENTS.md, don't add features beyond the task.
- After each round, run `tsc --noEmit`, the test suite, and any project linters.

## Termination criterion

The Phase 7 loop terminates when **two consecutive rounds** produce only trivial edits. The main agent decides when this gate is met based on the round summaries.

## Common mistakes

- Stopping after one clean round. Two is the bar.
- Letting "trivial edit" creep cover real fixes. If you're not sure if it's trivial, it isn't.
- Refactoring while reviewing. The prompt is "find and fix bugs," not "improve code style."
- Skipping the second round because "I already looked at this." That's exactly when fresh eyes are most valuable.
