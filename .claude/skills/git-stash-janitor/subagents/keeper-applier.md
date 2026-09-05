---
name: keeper-applier
description: Phase 6 — apply each `novel-and-accretive` stash to the recovery branch (sequential), run quality gates per apply, escalate conflicts.
---

# Keeper Applier

Owns Phase 6. Sequential by definition (each apply changes the 3-way base for later applies). Runs quality gates **per apply**, not at the end.

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path
- `{RECOVERY_BRANCH}` — default `stash-recovery-<YYYY-MM-DD>`

## Workflow

1. **Setup once at phase start** — create the recovery branch only if it does not already exist:
   ```bash
   git -C {PROJECT} show-ref --verify --quiet refs/heads/{RECOVERY_BRANCH} \
     && git -C {PROJECT} checkout {RECOVERY_BRANCH} \
     || git -C {PROJECT} checkout -b {RECOVERY_BRANCH} origin/{primary-branch}
   ```
2. **For each `novel-and-accretive` row in `triage.tsv`, in chronological order (earliest stash date first)**:
   1. **WORKING-TREE-DRIFT** — operator `↺`. Snapshot `git status`; if files appeared from concurrent agents, record the drift and never stage unrelated paths.
   2. **RE-FINGERPRINT** — operator `⊞`. Re-run VERIFY-ON-MAIN against the recovery branch's HEAD (which has previous keepers applied). If fingerprint coverage now ≥ 0.8, mark `superseded-during-apply` and skip.
   3. **APPLY-3WAY** — operator `✧`. `git apply --3way --check <bundle>/diffs/<n>.diff`; if clean, apply. If reject, escalate (see below).
   4. **RECOVER** — operator `⊕`. Run `test`, `typecheck`, `lint`, `ubs` from `project_profile.json`. All must exit 0.
   5. **Stage + commit** only the paths touched by the bundle diff plus copied `stashed-untracked/{n}/` files, with a focused, why-explaining message. Template in `references/AGENT-PROMPTS.md § Phase 6`. NO `Co-Authored-By` unless user requests.
   6. Append to `apply_log.tsv`.
3. **On apply-check failure (conflict)**:
   - DO NOT force the apply.
   - Surface to user with: stash diff, current state of affected files, hypothesis (refactor / rename / file move), proposed Edit-tool resolution preserving the stash's INTENT (not surface form).
   - Wait for explicit OK.
   - On user OK: apply the resolution via Edit tool, run gates, commit. On user "skip": mark `conflict-skipped`.
   - Write conflict context to `<workspace>/conflicts/stash_<NNN>.context.md` so it survives compaction.

## Critical rules

- **Sequential only.** Two parallel keeper-appliers would race the working tree.
- **Never use `git stash pop` or `git stash apply`.** Always `git apply --3way` against the bundle's diff.
- **Never bypass pre-commit hooks** with `--no-verify`.
- **Never push.**
- **Never modify the primary branch** — keepers land on the recovery branch only.
- **Never disturb concurrent agents' working-tree changes.** Per AGENTS.md.

## Auto-generated commit message rewriting

`scripts/apply-keeper.sh` writes a generic auto-generated commit message. The keeper-applier subagent should **rewrite the commit message** before the recovery branch is pushed:

```bash
git -C {PROJECT} commit --amend  # ONLY on the recovery branch's tip, not yet pushed
```

The rewritten message follows the template in `references/AGENT-PROMPTS.md § Phase 6`:
- Present-tense verb (`recover`, `restore`)
- Cites the source stash and bundle diff path
- Explains the *why* in 2–4 sentences (drawn from triage evidence + a re-read of the diff)
- Does NOT include `Co-Authored-By` lines unless the user asks

## Coordination

- File reservation: `paths=["**"]` (whole repo), `exclusive=true`, `reason="stash-janitor-phase6"`, `ttl_seconds=7200`.
- Thread id: `stash-janitor-<run-id>`.

## Quality gates

- [ ] Every applied row has `gates_status=passed`
- [ ] Every commit message has been rewritten beyond the auto-generated template
- [ ] Every conflict has a `conflicts/stash_<NNN>.context.md`
- [ ] No commits authored on the primary branch
- [ ] No push occurred

## Exit criteria

Every `novel-and-accretive` row in `triage.tsv` has either `new_commit_sha`, `conflict-skipped`, or `superseded-during-apply` in `apply_log.tsv`. Quality gates green on the recovery branch tip.
