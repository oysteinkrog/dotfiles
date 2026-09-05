# Active Checkout Patterns — Retired Git Worktree Convention

Legacy filename warning: this file used to recommend git worktrees for UB audits. That guidance is retired. The UB exorcist must not create, recommend, or clean up git worktrees.

Current rule:

- Run the audit in the active project checkout.
- Keep the audit workspace inside that checkout at `.ub-exorcism/<run-id>/`.
- For PR-shaped remediation, use an ordinary branch in the active checkout, for example `git switch -c ub-exorcism/<run-id>`.
- For historical tag/backport testing, use non-git archive snapshots under the audit workspace, not `git worktree`.
- Preserve all user and peer edits; never stash, reset, clean, or overwrite unrelated files.

---

## Why The Old Pattern Is Retired

Cass Q-301 captured a historical `origin=local, github=remote` convention and named verification directories. That memory is still useful for understanding why `origin` may not be the real upstream, but it must no longer be interpreted as permission to create worktrees.

The current implementation model is simpler and safer for this repo family:

```
<source>/
├── .ub-exorcism/<run-id>/          # all audit artifacts
├── .beads/                         # source repo issue graph, only after user-approved Phase 9 writes
└── <project files>                 # edited only after explicit remediation authorization
```

---

## Active-Checkout Branching

When the user authorizes source changes:

```bash
git -C "$SOURCE" status --short
git -C "$SOURCE" switch -c "ub-exorcism/$RUN_ID"   # only if PR-shaped work is desired
```

Then reserve the exact files with Agent Mail, apply incremental edits, run the phase gates, and commit only the authorized files.

Do not use the add/remove subcommands of Git's worktree feature.

---

## Remote Convention

Q-301 is still useful for remote selection. Some repos use:

- `origin` as a local mirror or machine-local synchronization remote.
- `github` as the actual remote for publishing.

Before pushing, check:

```bash
git -C "$SOURCE" remote -v
```

If both `origin` and `github` exist, prefer the actual network upstream the user/repo expects. Do not infer that `origin` is the public remote.

---

## Historical Tag Testing Without Worktrees

Backport and regression checks that need old tags should materialize archive snapshots inside the audit workspace:

```bash
SNAPSHOT="$WORKSPACE/tag-snapshots/$TAG"
mkdir -p "$SNAPSHOT"
git -C "$SOURCE" archive "$TAG" | tar -x -C "$SNAPSHOT"
```

The snapshot is not a git checkout and has no shared worktree state. It is an audit artifact. Do not auto-delete it; record its path in the matrix/report so the user can inspect or clean it up later.

---

## Multiple Agents

Multiple agents coordinate through Agent Mail reservations and bead ownership, not through separate worktrees.

Required pattern:

1. Partition scope in Phase 0.
2. Reserve exact artifact or source paths before editing.
3. Keep each subagent's write surface narrow.
4. If two agents need the same source file, serialize through the shared thread and reservation TTL.

---

## Cross-References

- cass Q-301 — historical remote/topology context, not a current worktree recommendation.
- [PHASES.md §Phase 0 Bootstrap](PHASES.md#phase-0-bootstrap--partition-515-min-main-agent-only) — active-checkout partitioning.
- [LIFECYCLE.md](LIFECYCLE.md) — post-audit maintenance without worktree retention.
- [RELEASE-FORWARD-ONLY.md](RELEASE-FORWARD-ONLY.md) — forward-only release workflow.
