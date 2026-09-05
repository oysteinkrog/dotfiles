---
name: handoff-reporter
description: Phase 11 — emit the final handoff report (counts per verdict, recovered SHAs, harmonization summary, rationalization-branch tip, removed worktrees with disk freed, deleted branches, skipped, bundle path, recovery recipes verbatim, push instructions). File beads issue, update Mail thread, run bv triage. Skill never pushes.
---

# Handoff Reporter

Owns Phase 11. The user's wrap-up. Includes counts, recovered SHAs, harmonization summary, recovery recipes, push instructions, bundle lifecycle note. Skill **never pushes** — the user pushes when they choose.

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path
- `{RATIONALIZATION_BRANCH}` — branch with the keeper commits
- `{TRIAGE}`, `{APPLY_LOG}`, `{PARTIAL_SPLIT_LOG}`, `{CLEANUP_LOG}`, `{HARMONIZATION_PLAN}`

## Outputs

- `<workspace>/handoff_report.md` — final user-facing report: counts per verdict, recovered SHAs table, harmonization summary, conflict resolutions, superseded-during-apply flips, removed worktrees + disk freed, deleted branches, skipped branches, verbatim recovery recipes, push instructions, bundle lifecycle note, optional Bundle conformance / Bundle robustness sections.
- `<workspace>/post_run_bv_triage.json` — `bv --robot-triage` output if `bv` is available; feeds the "Newly unblocked beads" section.
- **Stderr / surfaced findings:** prints push instructions verbatim to user (skill never pushes); names the active worktree (auto-protected) and the manual removal command.
- **Side effects:** files a beads issue via `br create` if `br` is available (records issue id in report); sends Agent Mail thread update; releases file reservations. NEVER pushes, NEVER deletes the bundle, NEVER runs `git push --delete` (only emits `# DO NOT RUN AS-IS`-marked script when `--prepare-remote-list` was set). Runs `polish-bar-check.sh` as final sanity gate; failures escalate before declaring success.
- **Decision contract:** no machine-readable decision artifact; success = `handoff_report.md` complete + `polish-bar-check.sh` green + user told the push command. Phase 12 (idea-wizard-reviewer) is opt-in only and post-handoff.

## Workflow

### 1. Run `scripts/handoff-report.sh {PROJECT}`

Produces `<workspace>/handoff_report.md` with the structure shown in SKILL.md "What This Skill Produces":

```markdown
# Branch + Worktree Rationalization Report

Run started:  <UTC>
Run completed: <UTC>
Project: <basename> at <path>
Canonical: <name> @ <SHA>
Rationalization branch: <name> @ <SHA>  (NOT pushed)
Bundle: <BUNDLE>

## Counts

|Verdict|Count|
|---|---|
|protected-preserve|R|
|already-merged|X|
|superseded|Y|
|garbage|Z|
|novel-and-accretive|N|
|partially-novel|P|
|divergent-refactor (harmonized)|D|
|dirty-worktree-only|W|
|novel-but-stale (deferred)|S|
|conflict-skipped|C|

Total branches at run start: B
Total worktrees at run start: Wt
Branches deleted: Bd
Branches preserved: Bp
Worktrees removed: Wr  (disk freed: <bytes humanized>)
Worktrees preserved: Wp

## Recovered commits

(table, one row per applied keeper, by chronological order on the rationalization branch)

|new SHA|strategy|source branch(es)|files|message subject|
|---|---|---|---|---|
|abc1234|cherry-pick|feat/parser-hardening|3|recover wider grammar from feat/parser-hardening|
|def5678|harmonized-synthesis|agent-cleanup-pass-3 + feature/parse-hardening + wip/null-checks|2|harmonize src/redact.rs ...|
|...|

## Harmonization summary

(per-file: which branches contributed, which intents survived, which were dropped — pulled from harmonization_plan.md + apply_log.tsv)

## Conflict resolutions

(list, with paths to context.md files in conflicts/)

## Superseded-during-apply flips

(rows where Phase 5 said novel but Phase 8 re-fingerprint flipped them to already-on-rationalization-branch)

## Removed worktrees

|path|disk freed|reason|
|---|---|---|

## Deleted branches

|branch|bucket|reason|backed-up at|
|---|---|---|---|

## Skipped branches (need user direction)

|branch|verdict|why deferred|
|---|---|---|

## Recovery recipes (verbatim)

# Restore one branch from backup ref
git -C <project> branch <name> refs/branch-rationalization-backup/<slug>

# Restore one branch from the bundle (works even if .git was deleted, as long as
# the bundle survives)
git -C <project> fetch <BUNDLE>/object-bundle.pack '+refs/branch-rationalization-backup/<slug>:refs/heads/<name>'

# Restore one branch's content as a patch series
git -C <project> am <BUNDLE>/branches/<slug>/format-patch/*.patch

# Restore one branch's content as a single squashed diff (against merge-base)
git -C <project> apply --3way <BUNDLE>/branches/<slug>/diff-vs-merge-base.diff

# Restore a worktree's dirty state (staged + unstaged + untracked)
git -C <worktree-path> apply <BUNDLE>/worktrees/<sanitized-path>/staged.diff --cached
git -C <worktree-path> apply <BUNDLE>/worktrees/<sanitized-path>/unstaged.diff
tar --null -xzf <BUNDLE>/worktrees/<sanitized-path>/untracked.tar.gz \
  -C <worktree-path> \
  -T <BUNDLE>/worktrees/<sanitized-path>/.untracked.list

# List everything in the bundle
git -C <project> bundle list-heads <BUNDLE>/object-bundle.pack
git -C <project> bundle verify <BUNDLE>/object-bundle.pack

## Push instructions

The skill did NOT push. To land the recovered work, you push:

  git -C <project> push origin <RATIONALIZATION_BRANCH>
  # Then open a PR against <CANONICAL> for review

If a PR is the wrong workflow for this project, alternatives:
- merge locally with: git checkout <CANONICAL> && git merge --no-ff <RATIONALIZATION_BRANCH>
- cherry-pick selected commits from <RATIONALIZATION_BRANCH> onto <CANONICAL>

The active worktree (your CWD: <path>) was NOT removed by the skill. To remove
it yourself when ready: switch to a different working directory (any other
worktree of this repo, or anywhere outside it), then run:
  git -C <project> worktree remove <active-cwd-path>

## Remote cleanup

(if --prepare-remote-list was set, point at remote_cleanup_suggestions.sh and
warn `# DO NOT RUN AS-IS`. Otherwise note: "out of scope — handle manually if
desired.")

## Bundle lifecycle

The recovery bundle at <BUNDLE> stays in place. Recommended retention: 1–4
weeks while you verify nothing was lost. Delete only after you're sure (and
then by hand, not via the skill — DCG correctly blocks rm -rf on the bundle).
```

### 2. Augment with cross-references

Read `apply_log.tsv` + `partial_split_log.tsv` + `harmonization_plan.md` + `cleanup_log.tsv` to fill the tables above with full content. Verify every recovered SHA is reachable on `{RATIONALIZATION_BRANCH}` via `git log --oneline {RATIONALIZATION_BRANCH}`.

### 3. File a beads issue (if `br` is available)

```bash
br create \
  --title "branch + worktree rationalization on <basename> (<W> worktrees, <B> branches → <Bp> preserved + rationalization branch)" \
  --type=task \
  --priority=4 \
  --json
# Then update with --status=closed --reason "..." once written
```

Link the issue id back into the report. If `br` is unavailable, skip and record `beads_skipped: true` in the report.

### 4. Update Agent Mail thread (if available)

```
send_message(
  thread_id=<beads-id or branch-rationalization-<run-id>>,
  subject="[<beads-id>] Completed: branch + worktree rationalization on <basename>",
  body=<one-paragraph summary with rationalization-branch SHA + bundle path>
)
release_file_reservations(...)
```

If unavailable, skip; record in the report.

### 5. bv triage — if available

```bash
bv --robot-triage > <workspace>/post_run_bv_triage.json
```

If the recovered commits unblocked any beads issues, append a "Newly unblocked beads" section to the report.

### 6. Print push instructions to user verbatim

```
Branch + worktree rationalization complete.

  Worktrees: <Wr> removed, <Wp> preserved (disk freed: <bytes>)
  Branches:  <Bd> deleted, <Bp> preserved
  Recovered commits on <RATIONALIZATION_BRANCH>: <Nk>
              (including <Hk> harmonized syntheses)

To land the recovered work:

  git push origin <RATIONALIZATION_BRANCH>
  # Then open a PR against <CANONICAL> for review

Bundle path: <BUNDLE>  (left in place; you manage lifecycle)
Beads issue: <id or "skipped">
Report: <workspace>/handoff_report.md

Active worktree (your CWD): <path> — NOT removed (auto-protected). To remove
it yourself when ready, switch to a different working directory and run:
  git -C <project> worktree remove <active-cwd-path>
```

## Critical rules

- **Never push.** Print the command; the user pushes (Axioms 15 + 6).
- **Never delete the bundle.** Note its path; user manages lifecycle (Axiom 18).
- **Never run `git push --delete`** — even with `--prepare-remote-list`, only emit a script header-marked `# DO NOT RUN AS-IS`; the user runs it themselves (Axiom 15).
- **If `br` or Agent Mail are unavailable**, skip those steps and record in the report.
- **Run `polish-bar-check.sh`** as a final sanity check. If any dimension fails, escalate before declaring success.
- **Never bypass pre-commit hooks** (no commits in this phase).
- **Never use sed/awk on source files.**
- **Never disturb concurrent agents' working-tree state.**
- **Never delete files without express user permission.**
- **Never run mass-delete primitives.**

## Coordination

- File reservation: `paths=[".worktree_branch_rationalization_workspace/handoff_report.md"]`, `exclusive=true`, `reason="branch-rationalization-phase11"`.

## Quality gates

- [ ] `handoff_report.md` exists with all sections filled
- [ ] Every recovered keeper-commit listed with SHA + strategy + source branch(es) + files + message subject
- [ ] Harmonization summary names which branches contributed and which intents survived
- [ ] Recovery recipes are verbatim shell commands (no placeholders that need substitution beyond the bundle path)
- [ ] Push command is printed (not executed)
- [ ] Active-worktree-removal instructions are printed for the user's CWD
- [ ] Beads issue filed (or `beads_skipped` recorded)
- [ ] `polish-bar-check.sh` passes

## Exit criteria

Report emitted; user told the push command + active-worktree-removal command; main agent declares run complete. Phase 12 (optional self-improvement notes) may follow if the user opted in.
