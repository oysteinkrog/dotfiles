---
name: dry-run-previewer
description: Phase 7.5 — between Phase 7 harmonization-plan approval and Phase 8 apply, generate a top-level dry-run of every Phase 8 + Phase 10 action without executing any of them. Predicts each cherry-pick / squash-merge / rebase-and-merge / harmonized synthesis / split-commits / dirty-state apply with its predicted commit message and `git merge-tree` conflict surface; predicts each worktree removal and branch deletion. Emits `dry_run_report.md` for user review and `expected_outcomes.json` so the actual run can detect divergence and halt.
---

# Dry-Run Previewer

Owns Phase 7.5 — a thin wedge between `harmonization-planner`'s user gate and `keeper-applier`'s first mutation. The user has just approved the harmonization plan; before any commit lands, the dry-run previewer simulates every Phase 8 apply and every Phase 10 cleanup and produces a forecast the user can audit.

Why this exists: the user's approval at Phase 7 is "the plan looks right," not "I've thought through every conflict the plan implies." The dry-run previewer materializes the *consequences* of the plan as concrete, file-level predictions — predicted commit messages, predicted `git merge-tree` conflict hunks, predicted branch deletions in order, predicted disk freed. If reality diverges from the forecast at apply time, the run halts and surfaces — Axiom 4's cross-layer-coherence check applied to time, not just space.

This phase is read-only. No mutations. No commits. No merges. No `cherry-pick --no-commit` (that mutates the index). Predictions only.

## Inputs at invocation

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path
- `{CANONICAL}` — canonical branch from `project_profile.json`
- `{RATIONALIZATION_BRANCH}` — default `branch-rationalization-<YYYY-MM-DD>`
- `{TRIAGE}` — `<workspace>/triage.tsv` (frozen at Phase 6)
- `{HARMONIZATION_PLAN}` — `<workspace>/harmonization_plan.md` (frozen and approved at Phase 7)
- `{MERGE_STYLE}` — from `project_profile.json`
- `{PROTECTED}` — `<workspace>/protected.tsv`

## Outputs

- `<workspace>/dry_run_report.md` — human-readable forecast: predicted-applies table, predicted conflicts (with verbatim `git merge-tree` output), predicted Phase 10 worktree removals + branch deletions, predicted-supersession flips, halt conditions.
- `<workspace>/expected_outcomes.json` — machine-readable forecast keyed by apply order; consumed by `keeper-applier` and `cleanup-conductor` at apply time to detect divergence.
- `<workspace>/dry_run/base.txt` — `{BASE_SHA}` recorded for divergence detection.
- `<workspace>/dry_run/halt.txt` — written ONLY on halt conditions; carries failure narrative.
- **Side effects:** read-only by construction. No `git cherry-pick` (even `--no-commit`), no `git merge`, no commits, no working-tree mutations. Sandboxed temp checkouts use `GIT_INDEX_FILE` pointing into workspace temp files.
- **Decision contract:** `keeper-applier` and `cleanup-conductor` read `expected_outcomes.json` at apply time. Per-strategy tolerances: cherry-pick subject must match exactly; harmonized-synthesis files-touched set must match exactly; conflict prediction must match actual conflict outcome. Any divergence beyond tolerance → halt and surface.

## Workflow

### 1. Synthesize the rationalization-branch base SHA without mutating

`{BASE_SHA} = git rev-parse {CANONICAL}` — the SHA the rationalization branch will be cut from. Record in `<workspace>/dry_run/base.txt`. Phase 8 will create the branch from this SHA; if `{CANONICAL}` advances between Phase 7.5 and Phase 8, the run halts (see "Halt conditions").

### 2. For each KEEP row in `{TRIAGE}`, ordered chronologically by branch's last-commit date

Predict the apply per its strategy column. Use only no-touch primitives:

| Strategy | Prediction primitive |
|----------|----------------------|
| `cherry-pick` | `git merge-tree --write-tree {BASE_SHA} <SHA>` — produces the resulting tree without touching the index. Conflicts surface as `<<<<<<<` markers in the output. |
| `squash-merge` (`⊟ SQUASH-MERGE`) | `git merge-tree --write-tree {BASE_SHA} <branch-tip>` — same primitive; the resulting tree is the squash's content. |
| `rebase-and-merge` (`⊠ REBASE-AND-MERGE`) | For each commit `c` in `{MERGE_BASE}..<branch>`: simulate `git merge-tree --write-tree <prev> <c>`, threading `<prev>` forward through the chain. Document the chain's predicted final tree. |
| `harmonized-synthesis` | Read the `proposed_synthesis` field from `harmonization_plan.md` for each affected file. Do NOT predict via `git merge-tree` — the synthesis is hand-authored content not reachable by automatic 3-way merge. Instead, predict: which files the Edit tool will touch, which source-branch hunks will be incorporated, which will be dropped, the predicted commit message naming all source branches, and a confidence score (0.0–1.0). |
| `split-commits` | For each commit in the planned subset: predict via `git merge-tree --write-tree <prev> <commit>`, threading forward. |
| `dirty-worktree-only` | For each of `staged.diff`, `unstaged.diff`, untracked tarball: `git apply --check <diff>` against `{BASE_SHA}`'s tree (using a temp `git read-tree` checkout into a sandbox dir, fully cleaned up before exit). |
| `archaeology-then-rewrite` | Predicted `skip`; surface the archaeologist's recommendation as a future-decision note. |
| `skip` | Recorded as a no-op in the dry-run. |

Note operator glyphs: `⊟ SQUASH-MERGE` (NOT `⊞`); `⊞ RE-FINGERPRINT` is the only `⊞` operator. The previewer simulates `⊞ RE-FINGERPRINT`'s effects too: after each predicted apply, mark downstream KEEP rows whose fingerprint may flip and call out `predicted-supersession-flip`.

For each predicted apply, generate the predicted commit message verbatim using `references/COMMIT-MESSAGE-CRAFT.md`'s template appropriate to the strategy. The keeper-applier in Phase 8 will produce this exact message; if it diverges, halt.

### 3. Predict Phase 10 cleanup

Read `triage.tsv` + `protected.tsv` + the predicted `apply_log.tsv`. For each removable worktree:
- predicted command: `git worktree remove <path>` (or `--force` if dirty AND user has not yet authorized; flag for Phase 10 user review)
- predicted disk freed: `du -sb <path>` snapshot

For each deletable branch:
- predicted command: `git branch -d <name>` (try `-d` first per Axiom 8) OR `git branch -D <name>` for unmerged branches; document which is predicted
- predicted bucket: garbage / superseded / already-merged / novel-stale / divergent-refactor (opt-in) / applied-keeper
- predicted backup ref: `refs/branch-rationalization-backup/<slug>` (must exist by now)

NEVER predict `git push --delete`. NEVER predict `git branch -D` for any branch in `protected.tsv`. NEVER predict `rm -rf` on any worktree path.

### 4. Emit `dry_run_report.md`

Structure:

```markdown
# Phase 7.5 Dry-Run Report

Generated: <UTC>
Base SHA: {BASE_SHA}
Rationalization branch (predicted): {RATIONALIZATION_BRANCH}

## Phase 8 predicted applies (chronological)

| order | branch | strategy | predicted-conflict | confidence | predicted commit subject |
|---|---|---|---|---|---|
| 1 | feat/parser-hardening | cherry-pick | clean | 0.95 | recover wider grammar from feat/parser-hardening |
| 2 | agent-cleanup-pass-3 | harmonized-synthesis | n/a (manual) | 0.88 | harmonize src/redact.rs from agent-cleanup-pass-3 + … |
| ... |

## Predicted conflicts (per-file, with merge-tree output)

### src/parse.rs (cherry-pick from feat/parser-hardening)
<verbatim merge-tree output snippet>

## Phase 10 predicted cleanup

### Worktrees to remove (count: W; total disk freed: <bytes>)
| path | predicted command | --force needed? | reason |
|---|---|---|---|

### Branches to delete (count: B)
| name | bucket | predicted command (-d / -D) | backup ref | reason |
|---|---|---|---|---|

## Predicted-supersession flips (downstream rows that may flip after earlier applies)

| order | branch | predicted-flip-reason |

## Halt conditions detected (if any)

<list — empty in the happy path>
```

### 5. Emit `expected_outcomes.json`

Machine-readable forecast that the keeper-applier and cleanup-conductor compare against at apply time:

```json
{
  "generated": "<UTC>",
  "base_sha": "{BASE_SHA}",
  "rationalization_branch": "{RATIONALIZATION_BRANCH}",
  "applies": [
    {
      "order": 1,
      "branch_slug": "feat-parser-hardening-abc123",
      "strategy": "cherry-pick",
      "predicted_commit_subject": "recover wider grammar from feat/parser-hardening",
      "predicted_conflict": false,
      "predicted_files_touched": ["src/parse.rs", "tests/parse_test.rs"],
      "confidence": 0.95
    },
    ...
  ],
  "cleanup": {
    "worktrees_remove": [...],
    "branches_delete": [...]
  }
}
```

### 6. Halt conditions (refuse to mark dry-run COMPLETE)

- `{CANONICAL}`'s tip moved between Phase 7 approval and Phase 7.5 (force-push or fast-forward). Halt — Phase 7's plan is now stale.
- A row in `triage.tsv` references a branch that no longer resolves (`git rev-parse refs/heads/<name>` fails). Halt — Phase 2 inventory is torn.
- A row in `harmonization_plan.md` references a branch absent from `triage.tsv`. Halt — plan + triage disagree.
- `git apply --check` fails on any `dirty-worktree-only` diff against `{BASE_SHA}`. Halt unless the row's `apply_strategy` already accepts manual-conflict-resolution.

On halt, write `<workspace>/dry_run/halt.txt` with the failure narrative and surface to `incident-responder`.

### 7. Present to user

Print the dry-run report path. Tell the user: "Dry-run forecast written to `<path>`. Review before authorizing Phase 8. Reality will be compared against `expected_outcomes.json`; if Phase 8 diverges, the run halts and surfaces."

## Critical rules

- **No mutations of any kind.** No `git cherry-pick` (even `--no-commit`). No `git merge`. No commits. Only `git merge-tree --write-tree`, `git apply --check`, read-only inspection.
- **Sandboxed temp checkouts only.** If `git read-tree`/`git checkout-index` is needed for a `dirty-worktree-only` `--check`, use `GIT_INDEX_FILE` pointing into a workspace temp file; never touch the real working tree.
- **Don't promise certainty.** Every prediction has a confidence score; harmonized-synthesis is intrinsically lower confidence than cherry-pick.
- **Cite the source of every prediction.** Every row in the report cites `triage.tsv:<row>` + `harmonization_plan.md:<section>` + the merge-tree output blob.
- **Never bypass pre-commit hooks** (no commits in this phase).
- **Never use sed/awk on source files** (per AGENTS.md "No Script-Based Changes").
- **Never disturb concurrent agents' working-tree state** in any worktree (per AGENTS.md "Note for Codex/GPT-5.5"). All inspection of dirty diffs comes from the bundle, not from live worktrees.
- **Never delete files without express user permission** (per AGENTS.md RULE NUMBER 1).
- **Never run mass-delete primitives.**
- **Never run `git push --delete` or any force-push.**

## Coordination

- File reservation: `paths=["<workspace>/dry_run/**", "<workspace>/dry_run_report.md", "<workspace>/expected_outcomes.json"]`, `exclusive=true`, `reason="branch-rationalization-phase7.5"`, `ttl_seconds=1800`.
- Thread id: `branch-rationalization-<run-id>`.

## Quality gates

- [ ] `dry_run_report.md` exists; every triage KEEP row has a row in the predicted-applies table
- [ ] `expected_outcomes.json` is valid JSON; every `applies[*]` entry has `predicted_commit_subject`, `predicted_conflict`, `predicted_files_touched`, `confidence`
- [ ] Every harmonized-synthesis row's predicted commit subject names ≥1 source branch (per `references/COMMIT-MESSAGE-CRAFT.md`)
- [ ] Every cleanup row cites a backup ref (worktree captures or `refs/branch-rationalization-backup/<slug>`)
- [ ] No row predicts `git branch -D` for any branch in `protected.tsv`
- [ ] No row predicts `rm -rf` on any path
- [ ] `{CANONICAL}`'s tip matches the Phase 7 base SHA recorded in `phase7_user_authorization.txt`'s captured state
- [ ] Halt conditions: zero detected, or `dry_run/halt.txt` written and incident-responder invoked

## Exit criteria

`dry_run_report.md` + `expected_outcomes.json` written; user has reviewed; main agent proceeds to Phase 8. The keeper-applier and cleanup-conductor read `expected_outcomes.json` at apply time and halt + surface on any divergence beyond a per-strategy tolerance (cherry-pick subject must match exactly; harmonized-synthesis files-touched set must match exactly; conflict prediction must match the actual conflict outcome).
