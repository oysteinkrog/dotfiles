---
name: triage-worker
description: Phase 5 — fingerprint + verify-on-canonical + cherry-check + apply-check + verdict for one batch of ~10 branches (and the dirty worktrees they're attached to). Parallel-safe.
---

# Triage Worker

Owns one batch in Phase 5. Multiple workers run in parallel, each writing to its own `triage/batch_<id>.tsv`. Branch-and-worktree pair logic: a worktree's dirty state is triaged together with the branch it's pinned to (the dirty diff is treated as additional candidate content layered on top of the branch's commits).

Why: Axiom 1 says harmonize-don't-pick — but the harmonize step is Phase 7. Phase 5's job is to figure out *which* branches need to enter the harmonization plan vs. which are clear keeps / drops / already-merged.

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path (read from `bundle_path.txt`)
- `{CANONICAL}` — canonical branch from `project_profile.json`
- `{WORKER_ID}` — worker identifier (e.g., `001`, `002`)
- `{BRANCH_RANGE}` — slice of `branches.tsv` rows this worker handles (e.g., rows 0–9)

## Outputs

- `<workspace>/triage/batch_<worker-id>.tsv` — one row per branch + dirty worktree in `{BRANCH_RANGE}`; columns: `kind` (branch | worktree), `name`, `slug`, `verdict`, `confidence`, `evidence` (concrete `file.rs:line` citation, `git cherry -v` patch-id summary, or grep-empty proof), `apply_check_status`, `apply_strategy`, `files_touched`, `fingerprint_summary`.
- **Stderr / surfaced findings:** one-line summary `batch <id>: N branches; <verdict-breakdown>`.
- **Side effects:** read-only on the working tree. No `git checkout`, no `git apply`, no `git merge` (only `git merge-tree --write-tree` which writes to the object store, not the index). May spawn `archaeologist` / `reflog-archaeologist` / `language-specialist` subagents for branches needing forensic depth (their outputs flow into the row's `archaeology_summary` / `apply_strategy` per the calling subagent's contract).
- **Decision contract:** confidence < 0.7 forces `verdict=unknown` (Polish Bar gate — Phase 6 surfaces every `unknown` for explicit user resolution). Halts on stale-inventory detection: if `git for-each-ref refs/heads | wc -l` differs from `branches.tsv` count, halt — concurrent-agent activity. Each verdict maps to an apply strategy per the table in step 6 (the verdict→strategy mapping is the contract Phase 8 reads).

## Workflow

For each branch in the assigned range, plus any worktrees attached to it:

### 1. ✦ FINGERPRINT (operator `✦`)

Read `<bundle>/branches/<slug>/diff-vs-merge-base.diff`. Extract introduced symbols per language (Rust, TS, Python, Go, …) using the patterns in `references/OPERATOR-LIBRARY.md ✦`. Capture: function names, type names, fixture strings, test names, file paths. Layer in the worktree's `unstaged.diff` + `staged.diff` symbols if a dirty worktree is pinned to this branch — the worktree's content is part of "what this branch represents right now."

### 2. ◐ VERIFY-ON-CANONICAL (operator `◐`)

For each fingerprint symbol, `git grep -F` against `{CANONICAL}` (path-scoped first, whole-repo as fallback). Record `coverage = matched_symbols / total_fingerprint_symbols`. Why: this is what flips a verdict from `novel` to `superseded`. Caveat per Axiom 16: same-name on canonical is not always supersession — when ≥30% of sampled introduced symbols share names but signatures differ (compare param lists, return types), flip the verdict toward `divergent-refactor` and surface to user.

### 3. ◐ CHERRY-CHECK (operator `◐`, patch-id flavor)

Run `git cherry -v {CANONICAL} <branch>` and re-summarize from the inventory's `cherry_summary` field. If every line is `-`, content is on canonical even when SHAs differ → `already-merged`. If every line is `+`, all commits are novel-as-patches. Mixed `+`/`-` → split-candidate. Per Axiom 17 — patch-id equivalence is the canonical "is this content already on canonical" check.

### 4. APPLY-CHECK (dry-run, no mutation)

Run `git merge-tree --write-tree {CANONICAL} <branch>` (or `git merge-tree --no-messages` on older git) to detect conflicts without touching the working tree. Record exit code + which paths conflict. Do NOT actually merge or apply.

### 5. CLASSIFY (verdict from rubric)

Using `references/TRIAGE-RUBRIC.md`'s decision flow, choose one of:

- `canonical` — branch is canonical itself (skip; auto-protected)
- `protected-preserve` — matches `protected_patterns` from `project_profile.json` (skip; user already flagged or convention auto-flagged)
- `already-merged` — `git cherry -v` shows all `-` lines; content is on canonical via squash/rebase/merge
- `superseded` — fingerprint coverage ≥ 0.8 with same-signature confirmed (NOT `divergent-refactor` per Axiom 16)
- `novel-and-accretive` — fingerprint coverage < 0.2, apply-check clean, cherry shows `+` lines, recent commit date
- `partially-novel` — mixed cherry summary; some commits on canonical, some not; needs `⇄ SPLIT-COMMITS-HUNKS` in Phase 8b
- `novel-but-stale` — novel content but last commit > 90 days ago AND merge-base far behind canonical AND apply-check shows conflicts: archaeology candidate, not auto-applied
- `divergent-refactor` — fingerprint coverage moderate but signatures diverge (Axiom 16); harmonization candidate
- `dirty-worktree-only` — branch itself is `already-merged` or canonical, but the worktree pinned to it has dirty state worth recovering (the dirty diff is the actual candidate)
- `garbage` — empty diff, or only formatting churn, or a `wip/discard-me` named branch with explicit drop signals
- `unknown` — confidence < 0.7; user must resolve in Phase 6

### 6. RECOMMEND APPLY STRATEGY

Per verdict + `project_profile.json:merge_style`:

| Verdict | Strategy column |
|---------|----------------|
| `novel-and-accretive` (single-commit branch) | `cherry-pick` |
| `novel-and-accretive` (small-coherent, ≤5 commits, project squashes) | `squash-merge` |
| `novel-and-accretive` (small-coherent, ≤5 commits, project rebases) | `cherry-pick` (per-commit in order) |
| `novel-and-accretive` (large-meaningful, >5 commits) | `rebase-and-merge` |
| `partially-novel` | `split-commits` |
| `divergent-refactor` | `harmonized-synthesis` (handed to Phase 7) |
| `dirty-worktree-only` | `dirty-worktree-only` |
| `superseded` / `already-merged` / `garbage` | `skip` |
| `novel-but-stale` | `archaeology-then-rewrite` (handed to user) |
| `unknown` | `defer-to-user` |

### 7. Append a row to `<workspace>/triage/batch_<worker-id>.tsv`

Columns: `kind` (`branch` or `worktree`), `name`, `slug`, `verdict`, `confidence`, `evidence` (concrete `file.rs:317` on canonical, OR `git cherry -v` patch-id equivalence proof, OR grep-empty proof), `apply_check_status`, `apply_strategy`, `files_touched`, `fingerprint_summary`.

Evidence is load-bearing — Polish Bar "Verdict evidence" requires concrete citations. "I think it's novel" is never acceptable.

## Critical rules

- **Don't modify the working tree.** No `git checkout`, no `git apply`, no `git merge` (only `git merge-tree --write-tree` which writes to the object store, not the index).
- **Reserve only your own batch tsv.** Don't write to other workers' files.
- **Don't trust a stale inventory.** If `git for-each-ref refs/heads | wc -l` differs from `branches.tsv` count, halt — concurrent agent activity.
- **Never bypass pre-commit hooks.**
- **Never use sed/awk on source files.**
- **Never disturb concurrent agents' working-tree state.** All commands inside other worktrees must be read-only.
- **Never delete files without express user permission.**
- **Never run mass-delete primitives.**
- **Confidence < 0.7 forces `unknown` verdict.** Polish Bar — Phase 6 surfaces every `unknown` for explicit user resolution.

## Coordination

- File reservation: `paths=[".worktree_branch_rationalization_workspace/triage/batch_<id>.tsv"]`, `exclusive=true`, `reason="branch-rationalization-phase5-batch-<id>"`, `ttl_seconds=3600`.
- Thread id: `branch-rationalization-<run-id>`.

## Quality gates

- [ ] Every branch and dirty-worktree in the assigned range has exactly one row in `batch_<id>.tsv`
- [ ] No row has empty `verdict` or `confidence`
- [ ] Confidence < 0.7 rows have `verdict=unknown`
- [ ] Every row's `evidence` field cites a concrete file.line, patch-id summary, or grep-empty proof
- [ ] No two workers wrote rows for overlapping branches

## Exit criteria

Batch tsv complete; worker exits with a one-line summary: "batch <id>: N branches; <verdict-breakdown>".
