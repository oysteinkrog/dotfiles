# Phantom Deletions

**Source axiom:** Axiom 24. Some `git status` rows ` D <path>` represent files the user wants RESTORED, not committed-as-deletion. Detecting these correctly is the difference between a successful cleanup and catastrophic destruction.

This document is sourced from the cass-mined frankenterm session (1,527 phantom deletions) and frankenterm-rch (1,524 phantom deletions), both Apr-27 2026.

---

## What is a phantom deletion?

A "phantom deletion" is a file that's:
- Tracked at HEAD (still in the index)
- Missing from the working tree
- The deletion was NOT intentional (no commit captures the intent)

`git status --porcelain` shows it as ` D <path>` (space then D — meaning unstaged deletion of a tracked file).

A naive cleanup that runs `git add -A` and commits would COMMIT the deletion, destroying the file from history's HEAD.

---

## How phantom deletions happen

| Cause | Example |
|-------|---------|
| `rm -rf <subdir>` outside git | User wanted to clear a build dir but `rm`'d a tracked source dir |
| `git checkout` of the wrong commit, then forgot to switch back | Working tree reverts to an old state where files were absent |
| Crashed sync tool (rsync, network drive, dropbox) deleting files mid-fetch | Files are absent from disk |
| `git reset --hard` to a parent commit, expecting later checkout | Forgot to checkout the desired ref |
| Submodule init failure leaving submodule subtree empty | `git status` shows the entire submodule as deleted |
| Concurrent agent's faulty cleanup operation | Another agent's bug deleted files; the user's repo is the casualty |

The most catastrophic real example (cass): an agent ran an extension test that accidentally `rm -rf`'d 5 entire crate subdirectories. The user's working tree showed 1,527 deletions. A naive cleanup would have committed those.

---

## Detection

The skill detects phantom deletions in Phase 1 / Phase 2 transition:

```bash
# Get all currently-deleted-but-tracked files
git status --porcelain | awk '$1 == "D" {print $2}' > /tmp/d_files.txt

# For each, check if the LAST commit was a deletion
phantom_count=0
while IFS= read -r path; do
    last_commit_op=$(git log -1 --pretty=format: --name-status -- "$path" | tail -1 | awk '{print $1}')
    if [[ "$last_commit_op" != "D" ]]; then
        # File is missing from working tree but its last commit didn't delete it
        echo "PHANTOM: $path"
        phantom_count=$((phantom_count + 1))
    fi
done < /tmp/d_files.txt

if [[ $phantom_count -gt 0 ]]; then
    echo "WARNING: $phantom_count phantom deletions detected"
fi
```

If phantom_count > 5, the skill HALTS and surfaces:

```
🚨 PHANTOM DELETIONS DETECTED

The repo's working tree is missing 1,527 files that ARE tracked at HEAD
and were not removed by any recent commit. This usually indicates:
  - Files were rm'd outside git (intentionally or accidentally)
  - A sync tool failed mid-operation
  - A crashed agent removed files

Before any cleanup can proceed, decide what these phantom-deleted files
should be:
  (a) Restore them — they belong in the working tree.
       Action: git checkout HEAD -- <paths>

  (b) Keep them removed — they were intentional manual deletions, just
      not yet staged.
       Action: git add -u <paths>; git commit -m "remove unused subtree"

  (c) Investigate per-subtree — some are intentional, some accidental.
       Action: surface a list per directory; user reviews each.

I recommend (a) Restore. The default cleanup flow assumes a stable
working tree, and 1500+ unintended deletions is too many to be
intentional. Restore first, then run the cleanup.

Phase progression is HALTED until you choose.
```

---

## Verdict: `restore-do-not-commit`

A new verdict (in addition to the seven main ones) for phantom deletion candidates:

| Verdict | When | Action |
|---------|------|--------|
| `restore-do-not-commit` | File is ` D <path>` AND last commit didn't delete it | `git checkout HEAD -- <path>` |

This verdict is recorded in `triage.tsv`:

```
id  verdict                  confidence  evidence                              proposed_action
099 restore-do-not-commit    0.95        smell=phantom-deletion;last-commit-op=M  git checkout HEAD -- crates/X/src/lib.rs
```

Confidence is high because the detection is unambiguous. The action is benign (restoration, not modification).

---

## Per-batch restore script

When phantom deletions are detected, the skill generates a restoration script:

```bash
#!/usr/bin/env bash
# restore-phantom-deletions.sh
# Source: phantom_deletions.tsv
set -euo pipefail

cd <project>

# Verify we're in the right state
git status --porcelain | awk '$1=="D" {print $2}' | wc -l  # should equal expected count

# Restore in batches (avoid command-line length issues)
git checkout HEAD -- crates/frankenterm-alloc
git checkout HEAD -- crates/frankenterm-core
git checkout HEAD -- crates/frankenterm-gui
git checkout HEAD -- crates/frankenterm-mux-server
git checkout HEAD -- crates/frankenterm-mux-server-impl

# Verify
git status --porcelain | grep -c '^ D'  # should be 0

echo "Phantom deletions restored. Resuming cleanup."
```

The user reviews this script before running. The skill produces it but does not execute (per AGENTS.md "Mandatory explicit plan").

After restoration, the cleanup proceeds normally.

---

## Per-subtree audit

When phantom deletions span multiple top-level subtrees, the skill groups them:

```markdown
## Phantom deletions by subtree

| Subtree | Count | Sample paths | Last commit op for sample |
|---------|------:|--------------|---------------------------|
| crates/frankenterm-alloc/ | 12 | src/lib.rs, src/freelist.rs, ... | M (modify) |
| crates/frankenterm-core/ | 87 | src/buffer.rs, src/diff.rs, ... | M (modify) |
| crates/frankenterm-gui/ | 145 | src/widget.rs, ... | M (modify) |
| ...                                                     |
| Total: 5 subtrees, 1527 files | | | |

All 1527 phantom deletions span 5 crate subdirectories.
None of the missing files were deleted by recent commits.

Recommended action: `git checkout HEAD -- <subtree-list>` per subtree.
This restores the working tree to match HEAD without committing anything.
```

---

## When phantom deletions are intentional

Sometimes phantom deletions ARE the user's intent — they ran `rm` on a deprecated subdir and just haven't staged the deletion yet. To distinguish:

1. **Number**: 1500+ deletions are almost certainly accidental. 1-5 are usually intentional.
2. **Pattern**: do they cluster around a single subdir (intentional cleanup) or scatter across the repo (accidental rm-rf)?
3. **Recent activity**: did the user recently say "I'm removing the legacy subtree"?

The skill's detection threshold is 5+ phantom deletions to halt. Below 5, it just surfaces them in the Phase 5 plan with verdict `surface-to-user` and lets the user decide.

---

## Restoration as a separate phase

For large phantom-deletion incidents, restoration is treated as a separate "Phase -1" before the cleanup begins:

```
Phase -1: Phantom-deletion restoration (when triggered)
Phase 0: routine pre-flight
Phase 1: project profile
...
```

Phase -1 runs the restoration script + verifies the working tree matches HEAD + records the restoration in `phantom_deletion_recovery.md` for the audit trail.

---

## Documenting the source of phantom deletions

When phantom deletions are detected, the skill investigates the cause:

1. Check `git reflog` for recent unusual operations (`git reset --hard`, `git checkout` to old commits).
2. Check shell history if available (`atuin export`, `~/.bash_history`).
3. Check ntm panes if active (other agents running concurrent operations).
4. Surface findings in `phantom_deletion_diagnostic.md`:

```markdown
## Phantom deletion diagnostic — repo-janitor-2026-05-08

**Detected:** 1,527 phantom deletions across 5 crate subdirs
**Repo:** /data/projects/frankenterm

**Reflog inspection:**
HEAD@{0}: <last manual operation>
HEAD@{1}: HEAD~1 reset (this is the suspect)
HEAD@{2}: ...

**Probable cause:** A `git reset --hard HEAD~1` was run by an agent at <ts>;
the agent's session was interrupted before it could re-checkout the desired
state. The resulting working tree is the "old" state without the recent
commits' files.

**Recommendation:** restore via `git checkout HEAD -- <subtrees>` to bring
the working tree back to HEAD's state.

**Risk:** if the user actually wanted the reset (pre-commit recovery),
restoring would undo their intent. CONFIRM with user before restoration.
```

The diagnostic is saved in `<workspace>/phantom_deletion_diagnostic.md`.

---

## DCG interaction

DCG blocks `git reset --hard`, so the most common cause of phantom deletions in this user's setup is *not* an agent's `git reset` — it's `rm -rf` (which DCG also blocks for tracked dirs, BUT only for the `rm -rf <root-or-home>` patterns; `rm -rf crates/somecrate` is allowed).

This means the user's environment has a layer of protection against the most catastrophic phantom-deletion sources, but `rm -rf <subdir>` outside git is still possible. The skill should detect via the working-tree-vs-HEAD diff regardless of cause.

---

## When phantom deletions overlap with cleanup candidates

Edge case: a file is BOTH phantom-deleted AND would otherwise be a cleanup candidate (e.g., a `.bak` file the user `rm`'d but the smell rule says "delete-and-gitignore").

The skill resolves this in favor of restoration first, then cleanup:
1. Restore the file via `git checkout HEAD -- <path>`.
2. Re-run inventory; the file is now present again.
3. Apply the cleanup rule (delete + gitignore).

This is two operations vs. one, but it preserves the audit trail (the deletion is now in a focused commit with a focused message, not silently committed alongside other changes).

---

## Cross-references

- INCIDENT-PLAYBOOK.md should add a "Phantom deletion incident response" section pointing here.
- FAILURE-MODES.md should include phantom deletions as F-something.
- ANTI-PATTERNS.md should add "naive `git add -A` in the presence of phantom deletions" as an anti-pattern.
- WORKED-EXAMPLES.md should include the frankenterm 1,527-deletion incident.

This is one of the highest-stakes failure modes; defensive code against it is non-negotiable.
