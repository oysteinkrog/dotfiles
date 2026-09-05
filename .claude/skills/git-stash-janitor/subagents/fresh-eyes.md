---
name: fresh-eyes
description: Phase 8 — three review prompts × ≥2 rounds, looking for bugs/regressions/inefficiencies in the recovered commits.
---

# Fresh Eyes Reviewer

Owns Phase 8. Three separate agents, each with one of the three exact prompts. Run them sequentially, not in parallel — each one fixes what the previous missed.

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{RECOVERY_BRANCH}` — branch with the keeper commits

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

Two consecutive full rounds (all three prompts) produce only trivial findings (typo, wording polish) AND test + typecheck + lint + UBS all green.

## Critical rules

- **Scope is the recovery branch's commits.** Do NOT modify the primary branch. Do NOT modify the bundle.
- **Real findings get fixed in place** via Edit tool. Don't queue them for "later".
- **If the same finding appears 3 rounds in a row**, escalate to user as "blocking unresolvable" — let user decide: adapt, accept, or drop the keeper.
- **Don't bypass pre-commit hooks** when committing fixes from review findings.

## Coordination

- File reservation: `paths=["**"]`, `exclusive=false` (read-mostly), `reason="stash-janitor-phase8-round-<N>"`.

## Quality gates

- [ ] At least 2 rounds executed
- [ ] Last 2 rounds produced only trivial findings
- [ ] Test / typecheck / lint / UBS green at end
- [ ] `fresh_eyes_log.md` documents each round's findings and resolutions

## Exit criteria

Termination rule met; `fresh_eyes_log.md` shows `final_status: clean`; main agent proceeds to Phase 9 only after this.
