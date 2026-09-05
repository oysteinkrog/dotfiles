---
name: fresh-eyes
description: Phase 9 — three review prompts × ≥2 rounds, looking for bugs/regressions/inefficiencies in the recovered commits and harmonized syntheses. Termination rule — two consecutive clean rounds. Full test suite + linters + UBS green.
---

# Fresh Eyes Reviewer

Owns Phase 9. Three separate agents, each with one of the three exact prompts. Run them sequentially, not in parallel — each one fixes what the previous missed.

Why three rounds: Phase 8's harmonized-synthesis commits are *novel content the skill authored*. Cherry-picks and squash-merges are recovered-from-source and benefit from Phase 9 too, but harmonized syntheses are where Phase 9 earns its keep. Two clean rounds in a row is the explicit termination gate before Phase 10 (cleanup) may run.

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{RATIONALIZATION_BRANCH}` — branch with the keeper + harmonized commits

## Outputs

- `<workspace>/fresh_eyes_log.md` — per-round findings, fixes applied, intent-fidelity check for harmonized-synthesis commits, gate outcomes (test/typecheck/lint/UBS), `final_status` field, and Escalations section for blocking-unresolvable findings.
- **Side effects:** appends `fix: <issue> uncovered in fresh-eyes round <N>` follow-up commits on `{RATIONALIZATION_BRANCH}` for non-trivial findings. Pre-commit hooks run normally; never `--no-verify`. Never modifies canonical, the bundle, or any source branch.
- **Decision contract:** `fresh_eyes_log.md:final_status` is exactly `clean` (termination rule met — two consecutive clean rounds + gates green) or `escalated` (blocking finding requires user direction). Phase 10 cleanup-conductor refuses to start without `final_status: clean`.

## Workflow

Each round runs all three prompts in sequence. Then the main agent runs gates between rounds. Repeat until two consecutive rounds produce only trivial findings.

### Round prompt 1

> Carefully read over all of the new code you just wrote and other existing code you just modified with 'fresh eyes' looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover.

### Round prompt 2

> Sort of randomly explore the code files in this project, choosing code files to deeply investigate and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious bugs, problems, errors, silly mistakes. Comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in AGENTS.md.

### Round prompt 3

> Turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues. Diagnose underlying root causes using first-principle analysis. Don't restrict yourself to the latest commits — cast a wider net and go super deep.

## Between rounds

The main agent runs (read commands from `project_profile.json`):

```bash
{test_command}
{typecheck_command}
{lint_command}
ubs .   # if available
```

All must exit 0. Log each round + outcome to `<workspace>/fresh_eyes_log.md`.

## Termination rule

Two consecutive full rounds (all three prompts) produce only trivial findings (typo, wording polish, unused import) AND test + typecheck + lint + UBS all green.

## Critical rules

- **Scope is the rationalization branch's commits.** Do NOT modify canonical. Do NOT modify the bundle. Do NOT modify any source branch.
- **Real findings get fixed in place** via Edit tool. Don't queue them for "later". Each fix is a follow-up commit on the rationalization branch with a focused message ("fix: <issue> uncovered in fresh-eyes round <N>").
- **If the same finding appears 3 rounds in a row**, escalate to user as "blocking unresolvable" — let user decide: adapt, accept, or drop the keeper. Document in `fresh_eyes_log.md` under "Escalations".
- **Don't bypass pre-commit hooks** when committing fixes from review findings.
- **Don't disturb concurrent agents' working-tree state.** Per Axiom 12.
- **Don't use sed/awk on source files** — Edit tool only.
- **Don't delete files without express user permission.**
- **Don't run mass-delete primitives.**
- **Pay extra attention to harmonized-synthesis commits.** They are the novel-content the skill authored; the per-file variant matrix from `harmonization_plan.md` is the spec — re-read both alongside the synthesis commit to verify the synthesis actually preserved each variant's intended intent.

## Coordination

- File reservation: `paths=["**"]`, `exclusive=false` (read-mostly), `reason="branch-rationalization-phase9-round-<N>"`.
- Thread id: `branch-rationalization-<run-id>`.

## Quality gates

- [ ] At least 2 rounds executed
- [ ] Last 2 rounds produced only trivial findings
- [ ] Test / typecheck / lint / UBS green at end
- [ ] `fresh_eyes_log.md` documents each round's findings, fixes, and (for harmonized commits) intent-fidelity check
- [ ] No findings escalated as "blocking unresolvable" without user direction

## Exit criteria

Termination rule met; `fresh_eyes_log.md` shows `final_status: clean`; main agent proceeds to Phase 10 only after this gate.
