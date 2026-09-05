# Submodule Handling

Submodules add a layer of complexity the skill must handle carefully. The cass-mined `/data/projects/rust/` cleanup (Apr-27 2026) demonstrated 8 dirty submodule paths with a mix of pointer rewinds and `-dirty` markers. Naive auto-staging would have committed destructive rewinds.

This reference codifies submodule classification.

---

## Submodule status semantics

`git submodule status` outputs one of:

| Prefix | Meaning |
|--------|---------|
| (none) | Submodule is checked out at the recorded commit |
| `+` | Submodule is checked out at a DIFFERENT commit than recorded (pointer change) |
| `-` | Submodule has not been initialized |
| `U` | Submodule has merge conflicts |

`git diff --submodule=log` shows commits the submodule has moved through.

`git diff --submodule=short` shows the SHA delta.

---

## Classifying submodule changes

A `+` (pointer-changed) submodule can be:

| Type | Description | Safe to commit? |
|------|-------------|-----------------|
| Fast-forward | Submodule moved forward to a newer commit | Usually YES (intentional update) |
| Rewind | Submodule moved BACKWARD to an older commit | NO (would silently undo upstream updates) |
| Diverged | Submodule moved to an unrelated branch | NO (unclear intent) |
| Dirty | Submodule pointer changed AND working tree inside has uncommitted changes | NO (the working tree state can't be committed cleanly) |

`git diff --submodule=log` reveals the type:

```
$ git diff --submodule=log
Submodule path-to-sub abc123..def456 (rewind):
  > Some old commit
  < Some newer commit that's now being lost
```

The `(rewind)` marker indicates a backward move. The `<` lines show commits being LOST if this is committed.

`(dirty)` suffix in `git diff --submodule=short` indicates uncommitted work inside the submodule:

```
$ git diff --submodule=short
-Subproject commit abc123
+Subproject commit def456-dirty
```

The `-dirty` is the red flag.

---

## Detection in the skill

Phase 1 enumerates submodules and Phase 2 examines their state:

```bash
# Phase 1: enumerate
git submodule status > .repo_janitor_workspace/submodule_status.txt

# Phase 2: classify each
git diff --submodule=log > .repo_janitor_workspace/submodule_diff_log.txt
git diff --submodule=short > .repo_janitor_workspace/submodule_diff_short.txt
```

The skill flags any `(rewind)` or `-dirty` markers in `submodule_warnings.tsv`:

```
submodule_path                    issue        action
crates/frankenterm-vendor         rewind       skip; require user override
crates/frankenterm-core/python    dirty        skip; require user override + cleanup inside submodule first
external/lz4                      ok           proceed with parent-repo cleanup; submodule out of scope
```

---

## Per-submodule verdicts

| Verdict | When | Action |
|---------|------|--------|
| `submodule-skip` (default) | Submodule subtree is not part of cleanup scope | Phase 2 inventory excludes the subtree |
| `submodule-skip-because-rewind` | Pointer change is a rewind; user policy unclear | Halt; surface to user |
| `submodule-skip-because-dirty` | Submodule has uncommitted work inside | Halt; surface to user; recommend `cd <subtree>; git status` |
| `submodule-process-separately` | User wants to clean inside the submodule | Spawn a separate skill instance scoped to the submodule path |

---

## What the skill DOES NOT do for submodules

- Doesn't traverse INTO submodule subtrees for the inventory walk
- Doesn't try to run REFERENCE-GREP from the parent repo into a submodule subtree
- Doesn't auto-stage submodule pointer changes
- Doesn't auto-commit `(dirty)` submodule states
- Doesn't try to update submodules

The submodule subtree's git history is its own; mixing concerns leads to bad commits.

---

## Per-submodule cleanup workflow

If the user wants to clean inside a submodule:

```bash
# Spawn a separate skill instance scoped to the submodule
cd /data/projects/parent-repo/crates/submodule-name
/git-repo-janitor mode=full
# Run the full cleanup inside the submodule
# Push the submodule's recovery branch separately
# Then come back to the parent repo and update the submodule pointer
```

The skill never automatically chains the parent + submodule runs.

---

## Submodule pointer commit policy

If the parent repo's only "uncommitted change" is a submodule pointer update, the skill:

1. Verifies the new pointer is forward of the recorded one (no rewind).
2. Verifies the new pointer's commit is reachable on the submodule's tracked branch (no random commit).
3. If both pass, surfaces "the only change is the submodule pointer; should I commit it?"
4. If the user says yes, commits with message: `chore: update <submodule-name> pointer (forward to <new-sha>)`
5. The commit message lists the submodule's commits being added (from `git diff --submodule=log`).

If checks fail (rewind or random commit), the skill refuses to auto-commit and surfaces:

```
The submodule <name> pointer changed:
  Recorded: abc123
  Current:  def456 (rewind)

This would LOSE the following submodule commits if I commit it:
  > <commit 1 message>
  > <commit 2 message>

I cannot auto-commit a rewind. You can:
  (a) Reset the submodule pointer: cd <subtree>; git checkout abc123
  (b) Confirm the rewind is intentional and override
  (c) Investigate why the pointer rewound (likely an `git reset` somewhere)
```

---

## Common submodule edge cases

### Edge case 1: submodule with shallow=true

`.gitmodules` has `submodule.<name>.shallow = true`. The submodule was initialized shallow. `git filter-repo` in the parent (or in the submodule) can lose history that the shallow clone never had.

Detection: `cat .gitmodules | grep shallow`.

Skill behavior: warn the user; recommend converting to a full clone before any history-rewriting operation.

### Edge case 2: submodule with file-only protocol

`protocol.file.allow` defaults to `user` (or `never` in some configurations). Submodule init from a local-file path may be blocked.

Detection: `git config --get protocol.file.allow`.

Skill behavior: surface as a soft warning during Phase 1.

### Edge case 3: submodule with .gitmodules-only changes

`.gitmodules` was edited (a submodule was added or removed) but the submodule subtree wasn't initialized/deinitialized to match.

Detection: `git status --short` shows `M .gitmodules` AND `git submodule status` shows mismatches.

Skill behavior: surface as a Phase 0 warning; recommend `git submodule sync && git submodule update --init` first.

### Edge case 4: submodule path conflict with cleanup candidate

A file at `<submodule-path>/foo.bak` looks like a cleanup candidate (editor-backup smell), but it's INSIDE a submodule.

Detection: the inventory walk should skip submodule subtrees entirely.

Skill behavior: never include submodule-internal files in `candidates.tsv`. The user runs the skill inside the submodule separately.

### Edge case 5: vendor directories tracked as plain dirs (no submodule)

Sometimes `vendor/` or `third_party/` contains code from another repo, but tracked as plain files (not a submodule). These should be in `protected_globs` to prevent the skill from touching them.

Detection: heuristic — directories at root with names like `vendor/`, `third_party/`, `external/`, `deps/`.

Skill behavior: add to protected_globs at Phase 1 with `notes: "vendor directory; not a submodule but treat as out-of-scope"`.

---

## Submodule integration with batch mode

For a batch run across many repos, submodule handling is per-repo:

1. Phase 1 detects submodules per-repo.
2. The repo's submodule warnings go in `<repo>/.repo_janitor_workspace/submodule_warnings.tsv`.
3. Repos with `(rewind)` or `(dirty)` submodule states are flagged but NOT skipped automatically — the user decides whether to skip the whole repo.
4. The batch handoff lists submodule warnings prominently.

---

## Summary checklist for handling a repo with submodules

- [ ] Phase 0: `git-doctor.sh` detects `.gitmodules`; warns.
- [ ] Phase 1: enumerate submodules; capture `submodule_status.txt`, `submodule_diff_log.txt`, `submodule_diff_short.txt`.
- [ ] Phase 1: detect `(rewind)`, `(dirty)`, shallow=true, etc.; emit `submodule_warnings.tsv`.
- [ ] Phase 2: inventory excludes submodule subtrees.
- [ ] Phase 4 / Phase 5: any submodule-internal "candidates" are filtered out.
- [ ] Phase 6 / Phase 7 / Phase 8: refuse to commit submodule pointer changes that are rewind or dirty.
- [ ] Phase 10: handoff lists submodule status; recommends per-submodule skill runs if user wants to clean those.

---

## What the user sees

```
[Phase 1] Submodule warnings detected:
  - crates/frankenterm-vendor: REWIND (would lose 3 commits if committed)
  - crates/frankenterm-core/python: DIRTY (uncommitted changes inside)
  - external/lz4: OK (no changes)

The skill will NOT touch the submodule subtrees during this run.
The 2 problematic submodules will be flagged in the handoff but
will not be auto-committed.

If you want to clean inside a submodule:
  cd <submodule-path>
  /git-repo-janitor mode=full
  # Push the submodule's recovery branch separately
```

This is the right framing — submodules are independent; treat them so.
