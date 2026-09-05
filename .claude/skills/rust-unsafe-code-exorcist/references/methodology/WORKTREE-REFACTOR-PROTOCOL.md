# WORKTREE-REFACTOR-PROTOCOL.md — Phase 8.5 Active-Checkout Implementation

Legacy filename warning: this document used to describe a git-worktree flow. That flow is deprecated and forbidden. When the user authorizes `audit-and-refactor` mode (or its incident-shaped cousins), the audit transitions from "draft plans in the audit dir" to "land the plans in the project repo" in the active checkout or an ordinary branch in that checkout.

The protocol explicitly preserves AGENTS.md's discipline: no destructive rewrites, no file deletion without permission, incremental edits only, and no git worktrees.

---

## Phase 8.5 — the active-checkout refactor phase

Triggered ONLY after:
1. Phase 8 bead conversion completes successfully.
2. The user has explicitly authorized refactor execution (per `phase0_scope_decision.md § execution_authorization: refactor-on-approve`).
3. The orchestrator confirms the audit's `AUDIT_SUMMARY.md` has been read by the user.

---

## Step 1 — prepare the active checkout

```bash
# In the project repo. Inspect only; do not stash, reset, clean, or overwrite.
git -C <project> status --short

# Optional, only when the user/repo workflow wants a PR branch:
git -C <project> switch -c unsafe-exorcist/<cluster-id>
```

The active checkout is the staging area. Implementer agents work in `<project>`, not in a secondary checkout copy. If the repository already has peer edits, preserve them and limit your touched files to the authorized scope.

If the project has CI gates on branch names (e.g., `^pr/`, `^feat/`), adjust the branch name accordingly.

---

## Step 2 — per-cluster implementation

The orchestrator iterates through the bead graph in dependency order:

```bash
# Find unblocked beads
br ready --json | jq -r '.[] | .id'

# For each unblocked bead:
for bead in $UNBLOCKED; do
  br update "$bead" --status=in_progress
  # ... spawn implementer agent ...
  # implementer reads audit/plans/site-NNNN.md and lands the change in the active checkout
done
```

Each implementer agent:

1. **Reads** `<audit-dir>/audit/plans/site-NNNN.md`.
2. **Reserves** the file paths it will edit via MCP Agent Mail file_reservation_paths (see [ORCHESTRATION.md](ORCHESTRATION.md)).
3. **Implements** the plan in `<project>` only, using incremental manual edits.
4. **Runs** the per-site acceptance criteria from the bead.
5. **Closes** the bead: `br close <id>`.
6. **Releases** the file reservations.

---

## Step 3 — per-cluster fresh-eyes + harness

After all beads in a cluster close, the orchestrator spawns:

1. A `fresh-eyes-reviewer` agent against `<project>`. The three verbatim prompts apply to the actual landed code, not the planned code.
2. The toolchain harness against `<project>`: `bash <audit-dir>/verify.sh <project>`.

If either finds issues:
- IN-SCOPE finding → reopen the relevant bead; fix; re-run.
- OUT-OF-SCOPE finding → file `pre-existing-ub-N` bead; do NOT widen the cluster's scope.

---

## Step 4 — commit and optional PR

For each authorized cluster/site, produce a focused diff. Commit and open a PR only when the user's repo workflow calls for it:

```bash
git -C <project> add <exact files touched>
git -C <project> commit -m "[cluster R-NNN] <one-line>

Per <audit-dir>/audit/plans/cluster-R-NNN.md.

Sites refactored:
- site-NNNN: <one-line>
- site-MMMM: <one-line>

Verified:
- cargo +nightly miri test: green
- cargo +nightly careful test: green
- loom: green (where applicable)
- cargo fuzz: 60s/target, no findings
- cargo +nightly geiger: count decreased by <N>
- default + safe-only features: green"

git -C <project> push -u origin unsafe-exorcist/<cluster-id>
gh -R <repo> pr create --title "[cluster R-NNN] <title>" \
   --body "$(cat <audit-dir>/audit/plans/cluster-R-NNN.md)"
```

The user retains the merge button unless they explicitly instructed this session to land/push directly. Never force-push.

---

## Step 5 — CI matrix wiring

If the audit added `[features] safe-only` to any Cargo.toml, the CI matrix must include the new feature combination. The harness-builder produced `<audit-dir>/ci-matrix.yml`; the implementer copies it into the project repo via a separate PR (or as part of the cluster PR if scope-clean).

```bash
cp <audit-dir>/ci-matrix.yml <project>/.github/workflows/soundness.yml
```

The CI PR is its own thing — typically the user wants it visible separately so they can verify the matrix before code changes land.

---

## Step 6 — verify-on-merged-main

After PRs merge, or after direct landing on the active branch, the orchestrator's final step:

```bash
# Inspect first. Do not switch branches or pull over dirty user/peer work.
git -C <project> status --short

# Continue only when the status output is empty, or after the user explicitly
# approves handling the dirty files. Never stash, reset, clean, or overwrite.
git -C <project> fetch origin
git -C <project> switch main
git -C <project> pull --rebase
bash <audit-dir>/verify.sh <project>
```

This runs the harness against `origin/main` (the post-merge state). If the active checkout is dirty, stop before `switch`/`pull`, report the exact dirty paths, and ask the user how they want verification isolated. If everything is still green, the refactor is complete.

If something fails on `main` that didn't fail before merge, the orchestrator opens a follow-up bug bead — typically a merge conflict resolution accidentally dropped a SAFETY comment or a feature-flag combination.

---

## File reservation discipline

The active checkout may be shared between implementer agents. To prevent two agents from clobbering each other:

```
file_reservation_paths(
    project_key="<project>",
    agent_name="<implementer-for-site-NNNN>",
    paths=["src/path/to/file.rs", "src/other/file.rs"],
    ttl_seconds=3600,
    exclusive=true,
    reason="beads-<id>"
)
```

If TWO sites in the SAME cluster touch the SAME file, the implementer agents coordinate via Agent Mail thread `unsafe-exorcist-<run-id>-cluster-<R-NNN>-shared-file-<slug>`.

If a coordination request arrives, the second implementer waits for the first to release before proceeding. The orchestrator monitors the thread; if a deadlock arises (rare), it serializes the work by closing one of the file reservations and re-spawning that implementer with a "wait-for-A-to-finish" instruction.

---

## What the implementer agent MUST NOT do

- **MUST NOT create or use git worktrees.** No `git worktree add`, no `<audit-dir>/worktrees/`, no sibling checkout copies.
- **MUST NOT land directly on `main` unless the user explicitly asked for direct landing.** Prefer an ordinary branch in the active checkout for PR-shaped work.
- **MUST NOT use destructive Git ops.** No `git reset --hard`, no `git clean -fd`. Per AGENTS.md.
- **MUST NOT delete files** without explicit per-file permission. Per AGENTS.md Rule 1.
- **MUST NOT widen scope.** A cluster bead's scope is fixed; pre-existing UB outside scope gets a separate bead.
- **MUST NOT batch unrelated changes.** One bead → one focused commit. Multiple beads can share a PR if they're in the same cluster.
- **MUST NOT skip the harness.** Each bead must pass its acceptance criteria via the harness before `br close`.
- **MUST NOT skip the fresh-eyes review.** Two clean rounds per cluster.

---

## Anti-patterns

- **"Just fix this small thing while we're here."** No — that's a separate bead.
- **Force-pushing the branch to clean up history.** No — squash on merge if the maintainer prefers; never force-push during review.
- **Renaming files as part of the refactor.** Risky; file moves break blame and confuse reviewers. Defer renames to a separate cleanup PR.
- **Migrating the test layout in the same PR as the refactor.** Don't combine. Tests in their original location; cluster's PR adds new tests adjacent.

---

## Rollback protocol

If a cluster PR turns out to be wrong AFTER merge:

1. `git revert <merge-commit-sha>` to back out — preferred over `reset --hard`. Per AGENTS.md.
2. Reopen the cluster's beads via `br update <id> --status=open --reason "reverted post-merge: <issue>"`.
3. Investigate, refine plans, re-run Phase 5+ for the affected cluster.
4. New PR.

The audit's git history shows the revert + the re-fix, which is healthier than a hidden hard-reset.

---

## Acceptance signal for Phase 8.5

The phase completes when:

1. Every user-authorized cluster/site has a verified active-checkout diff, commit, or PR according to the user's repo workflow.
2. Every PR or direct commit is green on the project's verification gates (matching what verify.sh predicted).
3. The user has the merge button when PR flow was requested.
4. `pre-existing-ub-N` beads are filed for every finding outside scope.
5. The audit's `AUDIT_SUMMARY.md` is updated with commit hashes or PR URLs.

After the user merges, the orchestrator runs Step 6 (verify-on-merged-main) to confirm the post-merge state is sound.
