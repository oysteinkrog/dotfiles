# Active-Checkout Refactor Checklist (Phase 8.5)

For each authorized cluster/site refactor pass, the implementer agent walks this checklist. Print at the start of work; tick items as done. The filename is legacy; git worktrees are forbidden.

---

## Pre-work

- [ ] Cluster's bead chain identified (`br ready --json`).
- [ ] All beads' acceptance criteria read and understood.
- [ ] Active checkout confirmed with `git status --short`; unrelated user/peer edits identified and preserved.
- [ ] Optional ordinary branch created in the active checkout if the user/repo workflow wants PR-shaped work.
- [ ] File reservations acquired via MCP Agent Mail.
- [ ] No other agent is concurrently modifying the same files.

## Per-site implementation

For EACH site bead in the cluster:

- [ ] Plan at `audit/plans/site-<id>.md` read in full.
- [ ] Allocator identity preserved (per operator 📐).
- [ ] Panic-in-Drop traced (per operator 🔒).
- [ ] Async cancellation traced if async (per operator 🔁).
- [ ] Send/Sync audit done if impl-touching (per operator ⚖).
- [ ] Edit applied incrementally (no whole-file rewrites; per AGENTS.md).
- [ ] Equivalence test landed (or regression test for incident mode).
- [ ] Cargo.toml changes landed (features, dev-deps).
- [ ] Local acceptance criteria pass:
  - [ ] `cargo test -p <crate>` green.
  - [ ] `cargo +nightly miri test -p <crate>` green (or scoped to relevant tests if FFI-heavy).
  - [ ] `cargo +nightly geiger -p <crate>` shows expected delta.
- [ ] Commit message includes site-id + plan path + verification.
- [ ] Bead closed: `br close <bead-id>`.

## Per-cluster: after all sites land

- [ ] Cargo.toml's `[features] safe-only = []` added (if any (B) in cluster).
- [ ] `[target.'cfg(loom)'.dev-dependencies] loom = ...` added (if any concurrency-touching (C)).
- [ ] `fuzz/fuzz_targets/<target>.rs` scaffolded (if widened pub surface).
- [ ] Fresh-eyes review: 2 clean rounds via fresh-eyes-reviewer subagent.
- [ ] Toolchain harness: `bash <audit-dir>/verify.sh <project>` exits 0.

## Pre-existing UB triage

For each finding from the harness:

- [ ] Classified IN-SCOPE or OUT-OF-SCOPE per operator ⚑.
- [ ] IN-SCOPE: addressed in the plan; site re-implemented; harness rerun.
- [ ] OUT-OF-SCOPE: `pre-existing-ub-N` bead filed with reproduction.

## Pre-Closeout

- [ ] No files deleted (per AGENTS.md).
- [ ] No git worktrees used (`git worktree add` is forbidden).
- [ ] No destructive Git ops used (no `git reset --hard`, no `git clean -fd`).
- [ ] No silent allocator changes.
- [ ] No bundled unrelated changes.
- [ ] All cluster's beads closed.
- [ ] All file reservations released.
- [ ] `git status` shows only the cluster's expected files modified.

## PR or Direct Closeout

- [ ] If PR flow was requested: ordinary branch pushed to origin.
- [ ] If PR flow was requested: PR opened with `gh pr create`:
  - [ ] Title: `[cluster <R-NNN>] <one-line>`
  - [ ] Body: cluster plan summary + bead chain + verification results + pre-existing-UB list.
  - [ ] Reviewer: maintainer added.
- [ ] CI green on PR, or local/project gates green for direct-landing workflows.
- [ ] If CI fails: triage IN-SCOPE / OUT-OF-SCOPE; don't widen the cluster.

## Post-merge (if user merges)

- [ ] Verify-on-merged-main: `bash <audit-dir>/verify.sh <project>` (after pulling main).
- [ ] If green: cluster is complete.
- [ ] If failed: investigate; typically a merge-conflict resolution dropped a SAFETY comment.

## Cleanup

- [ ] AUDIT_SUMMARY.md updated with commit hashes or PR URLs.
- [ ] Beads' final status synced: `br sync --flush-only`; commit to audit repo.

---

## What this checklist forbids

- "Just fix this small thing while we're here."
- Renaming files as part of the refactor.
- Updating dep versions while touching Cargo.toml.
- Force-pushing the branch (even between reviews).
- Creating git worktrees or secondary checkout copies.
- Skipping the harness "because it'll be slow."
- Folding pre-existing UB into the cluster scope.
- Bundling multiple bead commits into one mega-commit.

---

## What this checklist requires

- ONE bead → ONE focused commit (or coherent multi-commit per the bead's scope).
- ALL acceptance criteria pass before `br close`.
- Fresh-eyes per cluster, before closeout.
- Harness green per cluster, before closeout.
- Diffs reviewable in isolation.

This is the discipline that makes the user trust the refactor is incremental and reversible.
