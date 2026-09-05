# Mirror Backup Drill

The mirror backup is Layer 4 of the recovery chain (per SAFETY-MODEL.md). It's only used in the secret-leak playbook and any other history-rewriting flow. This reference walks through creating, verifying, and restoring from a mirror backup.

---

## When to create a mirror backup

| Scenario | Mirror needed? |
|----------|----------------|
| Routine `full` mode cleanup (moves + deletes + gitignore) | No (Layers 1–3 cover) |
| `harden-secret-leak` mode (about to run `git filter-repo`) | **YES** |
| Any other history-rewriting operation (`git rebase` on shared branch, `git reset --hard` to a known-good ref) | YES if the user is uncertain |
| Multi-repo batch run with secret-leak escalation in any repo | YES per affected repo |
| Pre-emptive backup before a known-risky operation | Always YES |

The skill creates the mirror automatically when entering `harden-secret-leak` mode (Step 1 of the playbook).

---

## How to create

```bash
BACKUP_TS=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_PATH=/tmp/<repo>-backup-$BACKUP_TS.git
git clone --mirror . "$BACKUP_PATH"
du -sh "$BACKUP_PATH"
echo "BACKUP_PATH=$BACKUP_PATH"
```

`--mirror` clones every ref (branches, tags, notes, stash, reflog) AS BARE refs. This captures everything `git filter-repo` could rewrite.

The skill records the backup path in:

```
<workspace>/mirror_backups.tsv
```

format: `created_at | path | size | reason | original_repo_sha`

---

## How to verify

After creating, verify the backup is complete:

```bash
# Count refs
git --git-dir=$BACKUP_PATH for-each-ref | wc -l

# Compare to the live repo
cd <project>
git for-each-ref | wc -l
```

The two counts should match (or the mirror should have ≥ live count, since it includes things like `refs/stash` that may exist).

```bash
# Verify a specific commit is reachable
git --git-dir=$BACKUP_PATH log --oneline <important-sha>
```

Any commit reachable from the live repo's refs should be reachable from the mirror.

```bash
# Verify a specific file's content
git --git-dir=$BACKUP_PATH show <branch>:<path> | sha256sum
git -C <project> show <branch>:<path> | sha256sum
```

The two should match.

---

## How to restore

### Full restore (original is gone or completely broken)

```bash
# Restore as a new working tree
mkdir /tmp/<repo>-restore
cd /tmp/<repo>-restore
git clone $BACKUP_PATH .
git remote rename origin backup-mirror
git remote add origin <original-remote-url>
git fetch origin --tags
git checkout main
```

Now the restored tree is a working clone with the original remote.

### Surgical restore (cherry-pick from mirror)

```bash
cd <project>

# Add the mirror as a remote
git remote add backup-mirror $BACKUP_PATH
git fetch backup-mirror

# Find the commit you need to restore from
git log backup-mirror/main --oneline | grep "<the change>"

# Cherry-pick
git cherry-pick <sha-from-mirror>
```

### Force-restore origin (if filter-repo went wrong)

```bash
cd <project>

# Reset local to mirror's main
git remote add backup-mirror $BACKUP_PATH
git fetch backup-mirror
git reset --hard backup-mirror/main

# Force-with-lease push to origin
git push --force-with-lease origin main
git push --force-with-lease origin main:master  # if mirror branch
```

This UNDOES a filter-repo. **Only use if the rewrite caused worse problems than the leak you were trying to fix.** Document the decision; this is rarely the right call.

---

## How to verify a restored state

After any restore:

```bash
# Verify HEAD matches what you expected
git rev-parse HEAD
git log --oneline -5

# Verify build still works
<test_command>
<typecheck_command>
<build_command>

# Verify you have what you wanted
git log --oneline | grep "<expected-message>"
git log --diff-filter=A -- <expected-file>
```

Don't trust a restore until the build passes on it.

---

## Lifetime

| Stage | What to do with the mirror |
|-------|----------------------------|
| Just after creation | Keep in `/tmp/<repo>-backup-<TS>.git` |
| Filter-repo just completed | Keep — this is your undo button |
| Force-with-lease push to origin completed | Keep for at least 24 hours; verify origin clean first |
| 24h+ after origin push, no issues found | Move to durable storage (e.g., `~/Backups/`) |
| 1+ week with no issues | User can delete (their decision) |

The skill never auto-deletes the mirror.

---

## When the mirror backup itself is corrupted

Rare but possible (disk failure, /tmp got cleaned). Verification:

```bash
git --git-dir=$BACKUP_PATH fsck
```

If `fsck` reports errors:
- Don't use the mirror for restore.
- Surface the corruption to the user.
- Possibilities: original repo on disk; `git reflog` entries; the user's other clones (each clone is a partial backup).

---

## Mirror vs. snapshot

| | Mirror | Snapshot |
|---|--------|---------|
| Format | bare git repo | tar archive of working tree + .git |
| Captures | every ref + every reachable commit | working tree at one moment |
| Size | typically small (delta-compressed) | typically larger (uncompressed) |
| Restore | `git clone` from mirror | `tar xf` then maybe `git fsck` |
| When to use | history-rewriting recovery | "I want a snapshot before this risky thing" |

The mirror is preferred. Snapshot is a fallback if the user can't run `git clone --mirror` (rare).

---

## Quick checklist for `harden-secret-leak` Step 1

- [ ] Create mirror: `git clone --mirror . /tmp/<repo>-backup-<TS>.git`
- [ ] Verify ref count: `git --git-dir=/tmp/<repo>-backup-<TS>.git for-each-ref | wc -l`
- [ ] Record path in `<workspace>/mirror_backups.tsv`
- [ ] Verify backup with `git fsck`: `git --git-dir=/tmp/<repo>-backup-<TS>.git fsck` (should report 0 errors)
- [ ] Note size: `du -sh /tmp/<repo>-backup-<TS>.git`

Only after all 5 boxes can Step 2 (verify origin sync) proceed.

---

## What if the user doesn't have /tmp space?

If `/tmp` is full or limited:

```bash
# Use ~/Backups/ instead
mkdir -p ~/Backups
BACKUP_PATH=~/Backups/<repo>-backup-$BACKUP_TS.git
git clone --mirror . "$BACKUP_PATH"
```

Or any other persistent path. The skill's default is `/tmp/` because it's universal; the user can override.

---

## Why mirror, not just snapshot

A working-tree snapshot loses:
- Tags (annotated and lightweight)
- Branches not currently checked out
- Notes
- Reflog (for recovering accidentally-deleted branches)
- Dangling commits

A mirror captures all of these. For a history-rewriting operation, you need the full picture, not just the current branch.

---

## When to skip the mirror

Never. If you're about to run `git filter-repo` or any history-rewriting command, the mirror is mandatory. The skill enforces this in `harden-secret-leak` mode by checking `<workspace>/mirror_backups.tsv` before proceeding to filter-repo.

If you're tempted to skip "to save time": rotate keys instead. The user's decision to rotate is not delayed by the mirror creation (5 seconds vs. the hours-to-days for key rotation).
