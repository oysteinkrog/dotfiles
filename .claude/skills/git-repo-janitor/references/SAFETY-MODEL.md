# Safety Model — Every Destructive Action's Reversibility Chain

Every destructive operation the skill performs has a documented recovery path. This is the chain.

---

## Principle: irreversibility is paid for in advance

Before any destructive action runs, the skill builds the recovery infrastructure. The recovery story has to outlive the run.

```
                    ┌─────────────────────────────┐
                    │  Phase 3 BUNDLE (the gate)  │
                    │                             │
                    │  - working-tree-copies/     │ byte-identical
                    │  - meta/<id>.txt            │ provenance
                    │  - index.tsv                │ everything-by-id
                    │  - gitignore-before.txt     │ pre-run state
                    │  - reference-graph.json     │ what referenced what
                    │  - README.md                │ recovery recipes
                    │                             │
                    │  + refs/repo-janitor-backup/│ git-internal undo
                    │     <DATE>-pre-cleanup      │
                    │                             │
                    │  byte-equality VERIFIED     │ SHA-256 per file
                    └─────────────┬───────────────┘
                                  │
            ┌─────────────────────┼─────────────────────┐
            ▼                     ▼                     ▼
      Phase 6 MOVES          Phase 7 DELETES       Phase 8 GITIGNORE
      (reversible via        (reversible via       (reversible via
       git revert            git revert OR          git revert OR
       OR bundle copy        bundle copy +         simple file edit)
       + reference-graph     git checkout)
       reverse rewrite)
```

---

## Layer 1 — `refs/repo-janitor-backup/<DATE>-pre-cleanup`

A ref pointing at the primary-branch HEAD before any cleanup commit lands. Survives `gc` (refs are GC roots). Created in Phase 3 step 6:

```bash
git update-ref refs/repo-janitor-backup/$(date -u +%Y-%m-%d)-pre-cleanup HEAD
```

**To recover any file from before the cleanup:**
```bash
git checkout refs/repo-janitor-backup/<DATE>-pre-cleanup -- <path>
```

**Lifetime:** Forever. The skill never deletes this ref. The user can clean up backup refs via `git update-ref -d refs/repo-janitor-backup/<DATE>-pre-cleanup` once they're confident.

---

## Layer 2 — The persistent bundle

Outside the repo, byte-identical copies + index + meta + reference graph + README. Layer 2 covers Layer 1's blind spots:

- A force-push that orphaned commits (Layer 1 ref still points at the orphan, but bundle is independent of git's object store).
- A `git gc --prune=now` (rare, but a panicked user might run it).
- Sharing the recovery state via `tar`.

**To recover from the bundle:**
```bash
# Single file
cp <bundle>/working-tree-copies/<path> <project>/<path>
git add <path>
git commit -m "restore: <path> from cleanup bundle"

# Whole bundle as a tarball (e.g., to share with a teammate)
tar czf <bundle>.tar.gz <bundle>
```

**Lifetime:** User-managed. The skill never deletes the bundle (DCG would block it anyway; the skill is designed never to need that command).

---

## Layer 3 — The git history itself

Every Phase 6/7/8 mutation is a normal commit. To undo any single commit:

```bash
git revert <sha>
```

To undo a range of cleanup commits:
```bash
git revert --no-commit <first-sha>..HEAD
git commit -m "revert: cleanup run <DATE>"
```

To roll back to pre-cleanup using Layer 1:
```bash
git reset --hard refs/repo-janitor-backup/<DATE>-pre-cleanup
# DANGEROUS — only the user runs this; skill never recommends it because
# any uncommitted Phase 6 working-tree changes would be lost.
```

**Lifetime:** Forever (until `git gc --prune=now` reaps unreferenced objects). Layer 1's backup ref keeps everything reachable.

---

## Layer 4 — The `mirror` backup (only for filter-repo / secret-leak runs)

Only used for the secret-leak playbook. Mirror clones include every ref the skill might not normally see (tags, notes, stashes, dangling commits).

```bash
BACKUP_TS=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_PATH=/tmp/<repo>-backup-$BACKUP_TS.git
git clone --mirror . "$BACKUP_PATH"
```

**To recover from the mirror:**
```bash
git clone "$BACKUP_PATH" /tmp/<repo>-restore
cd /tmp/<repo>-restore
# inspect; cherry-pick what you need back into the live repo
```

**Lifetime:** Skill leaves it in `/tmp/`; user moves to a more durable location after confirming the rewrite landed cleanly.

---

## Per-mutation recovery recipes

### Phase 6 move recovery

| What you want | How |
|---------------|-----|
| Undo a single move | `git revert <move-commit-sha>` |
| Undo all moves | `git revert <first-move-sha>..<last-move-sha>` (range) |
| Move file back to root | `git mv <new-path> <old-path>`, fix references via `reference_rewrite_log.tsv` (reverse), commit |
| Restore the file at the old path while keeping the new one | `cp <bundle>/working-tree-copies/<path> <project>/<old-path>; git add <old-path>; git commit -m "restore old path alongside new"` |

### Phase 7 delete recovery

| What you want | How |
|---------------|-----|
| Undo a delete | `git revert <delete-commit-sha>` (cleanest) |
| Restore one file from before | `git checkout refs/repo-janitor-backup/<DATE>-pre-cleanup -- <path>; git add <path>; git commit -m "restore <path>"` |
| Restore one file from the bundle | `cp <bundle>/working-tree-copies/<path> <project>/<path>; git add; git commit` |
| Restore but keep file `.gitignore`d | restore, then `git rm --cached <path>` (keep on disk, untrack), commit |

### Phase 8 gitignore recovery

| What you want | How |
|---------------|-----|
| Undo a `.gitignore` change | `git revert <gitignore-commit-sha>` |
| Remove one specific rule | Edit `.gitignore`, remove the line, commit |
| Restore tracking of a file untracked by `git rm --cached` | Either `git checkout <pre-untrack-sha> -- <path>; git add <path>` OR `git revert <gitignore-commit-sha>` (which will re-add the file to the index) |

---

## Per-mutation rollback flags

If a Phase 6 commit's gates fail, the skill can roll back automatically:

```bash
# Inside apply-move.sh, after a failed gate run:
git restore --staged <files>
git restore <files>
# (the failed move is now uncommitted; the skill marks it conflict-skipped
#  and continues with the next move)
```

Phase 7 deletes don't auto-rollback — they require explicit user confirmation per batch, and the gates run AFTER the commit (so a gate failure surfaces immediately and the user manually decides).

---

## What the skill NEVER recommends

| ✗ Action | Why | What to do instead |
|----------|-----|-------------------|
| `git reset --hard <pre-cleanup-sha>` | Loses all post-cleanup work, even unrelated work from concurrent agents | `git revert <range>` |
| `git clean -fd` | Removes untracked files (which may be other agents' in-progress work) | The skill never needs to clean untracked content; it operates only on tracked + bundle |
| `rm -rf <bundle>` | Loses Layer 2 recovery | Leave the bundle; user manages lifecycle |
| `git push --force` (without `--with-lease`) | Can clobber a teammate's push that arrived between fetch and push | `git push --force-with-lease` (only used in secret-leak flow) |
| `git stash` (anything) | The skill operates on the working tree, not on stashes; stashing concurrent agents' work is forbidden per AGENTS.md | Treat concurrent agents' working-tree changes as committed-by-you |
| `git update-ref -d refs/repo-janitor-backup/...` | Removes Layer 1 backup | Leave backup refs forever; user manages |
| Any command that deletes commits without first creating a backup | Loses the recovery chain | Mirror backup first (Layer 4) |

---

## Auditability

After any run, the user can audit the full recovery chain:

```bash
# Layer 1 — backup ref still exists
git show-ref refs/repo-janitor-backup/

# Layer 2 — bundle path
cat .repo_janitor_workspace/bundle_path.txt
ls -la <bundle>/

# Layer 3 — git history of cleanup commits
git log --oneline repo-janitor-<DATE>

# Mutation log (every move, delete, gitignore-add with metadata)
cat .repo_janitor_workspace/apply_log.tsv
cat .repo_janitor_workspace/reference_rewrite_log.tsv

# Authorization records (one per gated phase)
cat .repo_janitor_workspace/cleanup_authorization.txt
```

If any of these are missing, the run did not actually execute the corresponding phase.

---

## Why "the user owns deployment"

The skill never:
- Pushes the recovery branch.
- Merges the recovery branch into the primary branch.
- Deletes any backup ref or bundle.
- Force-pushes (except in the secret-leak playbook, and only after explicit verbatim authorization).

This boundary is deliberate. The user knows their team's review conventions, branch protections, CI cost considerations, and rollback tolerances. The skill produces auditable, reversible artifacts and stops.

The handoff report (`handoff_report.md`) tells the user every command they should run next, but never runs them. This is the same boundary `documentation-website-for-software-project` and `git-stash-janitor` use, and it's the right one.
