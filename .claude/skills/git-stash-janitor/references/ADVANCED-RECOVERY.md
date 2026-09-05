# Advanced Recovery — Edge Cases and Catastrophes

The basic recovery recipes (RECOVERY-RECIPES.md R1–R14) cover the common cases. This file is for the hard cases: gc-pruned stashes, force-push aftermath, lost recovery branches, multi-day debugging.

---

## AR1 — `git gc --prune=now` ran AFTER `git stash drop` AND `git update-ref -d`

**Symptom:** the user explicitly cleaned up backup refs (intentional or accidental), then ran aggressive gc. The stash's commit object is now gone from `.git/objects/`.

**Recovery options:**

1. **The bundle is your only hope.** `<bundle>/diffs/<NNN>.diff` is a textual representation; it doesn't depend on git objects.
   ```bash
   cd /path/to/project
   git apply --3way --check <bundle>/diffs/034.diff
   git apply --3way        <bundle>/diffs/034.diff
   git add -A && git commit -m "recover stash@{34} from bundle (post-gc)"
   ```

2. **If the bundle is also gone:** the work is unrecoverable. This is the only case the skill cannot save.

**Prevention:** keep the bundle. The skill never deletes it.

---

## AR2 — Force-push to origin orphaned the recovery branch

**Symptom:** the user pushed `stash-recovery-2026-05-06`; later, someone force-pushed to `origin/main`; the recovery branch's base is now disconnected.

**Recovery options:**

1. **The recovery commits still exist locally.** The branch ref `refs/heads/stash-recovery-2026-05-06` still resolves.
   ```bash
   git log stash-recovery-2026-05-06 --oneline | head
   ```

2. **Rebase onto the new main:**
   ```bash
   git checkout stash-recovery-2026-05-06
   git fetch origin
   git rebase --onto origin/main main stash-recovery-2026-05-06
   # The recovery commits are now reparented onto current origin/main
   ```

3. **If rebase fails (heavy conflicts because the new main went a different direction):**
   - For each recovery commit: cherry-pick onto a fresh branch off origin/main
   - Resolve conflicts as they come
   - The bundle's per-stash diffs are useful here as references

4. **If origin force-push happened before the recovery branch was pushed:**
   - The local recovery branch is fine
   - Don't push without rebasing first
   - Open the PR off the new origin/main

**Prevention:** push the recovery branch promptly after the run; treat force-pushes to primary as scope-changing events.

---

## AR3 — The recovery branch was deleted

**Symptom:** `git branch | grep stash-recovery` returns nothing.

**Recovery options:**

1. **Reflog has the commits:**
   ```bash
   git reflog --all | grep stash-recovery
   # ... finds entries like:
   # def987 HEAD@{42}: commit: recover defensive MySQL OK-packet ...
   ```

2. **Recreate the branch from the reflog:**
   ```bash
   git checkout -b stash-recovery-2026-05-06-restored def987
   # Or directly from the reflog entry that names the latest recovery commit:
   git checkout HEAD@{42}
   git checkout -b stash-recovery-2026-05-06-restored
   ```

3. **If reflog has expired:** the bundle has all the diffs; re-run Phase 6 to re-author the commits.

---

## AR4 — Bundle filesystem corruption

**Symptom:** `<bundle>/diffs/034.diff` is empty, partial, or unreadable.

**Recovery options:**

1. **Try alternative bundle copies.** The user may have multiple bundles from prior runs; check `/tmp/`, `~/Documents/`, etc.

2. **Re-derive from backup ref:**
   ```bash
   # If refs/stash-backup/034 is still in .git/refs/:
   git stash show -p --binary refs/stash-backup/034 > <bundle>/diffs/034.diff.regenerated
   ```

3. **If both are gone:** unrecoverable. Same as AR1.

---

## AR5 — Multiple runs collided

**Symptom:** two runs of the skill ran concurrently. Two bundle directories. Two recovery branches. Conflicting state.

**Recovery options:**

1. **Identify which run finished:** `cleanup_log.tsv` indicates Phase 9 ran. The other run did not.

2. **Reconcile the workspaces:** the run that finished has authoritative `inventory.tsv` and `triage.tsv`. The other run's artifacts are stale.

3. **Backup refs are repo-wide:** if both runs created `refs/stash-backup/*`, the second run's `git update-ref` overwrote the first's (since they share the same numbered names). Check via:
   ```bash
   git for-each-ref refs/stash-backup/ --format='%(refname:short) %(objectname:short) %(committerdate:relative)'
   ```
   The committerdate is the date of the *underlying stash commit*, not the ref creation. If two runs were on the same stash list, the SHAs match.

4. **Prevention:** advisory file reservation on `.git/**` via Agent Mail at Phase 0. A second run sees the lease and refuses to start (or asks the user explicitly).

---

## AR6 — `cleanup_log.tsv` is corrupted or partial

**Symptom:** Phase 9 was running; some drops happened; the log is partial.

**Recovery options:**

1. **The actual stash list is the source of truth.** Compare `git stash list` against `inventory.tsv`:
   ```bash
   git stash list | wc -l    # current count
   awk 'NR > 1' inventory.tsv | wc -l   # initial count
   ```
   The difference = number of stashes dropped so far.

2. **Build a corrected cleanup_plan.tsv** from the remaining inventory rows whose verdicts are drop-eligible.

3. **Re-run Phase 9** after the user re-authorizes (the original `cleanup_authorization.txt` covered the original plan; the corrected plan needs new authorization).

---

## AR7 — Stashes contain credentials or secrets

**Symptom:** during triage, the agent notices a stash contains an API key, password, or other secret.

**Recovery options:**

1. **DO NOT include the secret in any commit message, log, or report.**

2. **Surface to user:**
   > Stash@{N} appears to contain a secret (looks like an API key on line X).
   > I won't include this in any artifact, but I want to flag it before
   > proceeding. How would you like to handle it?
   > - Recover the non-secret hunks only (split-apply)
   > - Skip this stash; treat as `unknown` for triage
   > - Drop without recovery (the bundle still contains it; consider scrubbing
   >   the bundle separately)

3. **The bundle still contains the secret** in its diff file. The user must decide bundle handling separately.

4. **If the goal is secret-PURGING from history**, this skill is the wrong tool — see WHEN-NOT-TO-USE.md NTU-15.

---

## AR8 — Lost backup refs because git-gc auto-pruned

**Symptom:** the user ran `git gc` (without `--prune=now`) but the backup refs were pruned anyway.

**Why this can happen:** if a backup ref was DELETED via `git update-ref -d` (e.g., by a different tool), then auto-gc may eventually prune the unreachable commit. Default gc settings are conservative (90 days), but the user may have customized.

**Recovery:** the bundle is the only fallback. AR1.

---

## AR9 — The recovery branch's commits depend on each other in a way that prevents partial cherry-picking

**Symptom:** the user wants to cherry-pick only some of the recovery commits but they have textual dependencies (later commits modify code introduced by earlier commits).

**Recovery:**

1. The dependency is informational, not enforced. You CAN cherry-pick out of order, but conflicts are likely.

2. The cleanest approach is to rebase + interactive cherry-pick:
   ```bash
   git checkout main
   git checkout -b new-branch
   git rebase -i stash-recovery-2026-05-06
   # In the editor, drop the commits you don't want; keep the rest
   ```

3. If a commit you want depends on a commit you don't, you'll need to manually adapt — there's no clean answer.

---

## AR10 — Recovery commits broke main after merge

**Symptom:** the user merged the recovery branch; CI is now broken.

**Recovery:**

1. **First diagnose:** which commit broke it? `git bisect` or look at the diff against the last green commit.

2. **Revert path A — surgical:**
   ```bash
   git revert <bad-commit-sha>
   ```
   This creates a new commit that undoes the bad one. The recovery story stays intact (the original recovery commit is in history; the revert is a normal forward operation).

3. **Revert path B — wholesale:**
   ```bash
   git revert --no-edit <merge-commit-sha> -m 1
   ```
   Reverts the entire merge. Use only if multiple commits broke things.

4. **Backup refs are still in place.** If you want to retry recovery with a different approach, the bundle is unchanged; re-run Phase 6 with adjusted triage.

---

## AR11 — DCG starts blocking new things mid-run

**Symptom:** a DCG hook was updated; commands the skill expects to run are now blocked.

**Recovery:**

1. **Don't fight DCG.** Per the skill's design philosophy, DCG-blocked operations should be unnecessary.

2. **If a previously-allowed command is now blocked**, surface to user:
   > A command I was about to run was blocked by DCG (rule: <rule>). The
   > command was: <command>. This wasn't expected — either DCG was updated
   > or the skill has a bug. Please advise.

3. **Always have a non-DCG-dependent fallback.** E.g., for `rm -rf`, use `mv`.

---

## AR12 — User changes their mind about an authorized drop after Phase 9

**Symptom:** Phase 9 dropped 50 stashes; the user realizes one of them had useful content they wanted to recover.

**Recovery:**

1. **`refs/stash-backup/<NNN>` still exists** for that stash.
   ```bash
   git cherry-pick -m 1 refs/stash-backup/047
   # If index.tsv says has_untracked=true, also copy stashed-untracked/047/.
   ```

2. **Or apply via the bundle:**
   ```bash
   git apply --3way <bundle>/diffs/047.diff
   git add -A && git commit -m "recover stash@{47} after-the-fact"
   ```

3. **The skill's design assumes regret is normal.** That's why the four-layer reversibility chain exists. AR12 is the *expected* aftermath of every successful run.

---

## AR13 — Recovered keeper shipped to production; turned out to be wrong

**Symptom:** weeks after the run, a recovered commit causes a production incident.

**Recovery:**

1. **Surgical revert** as in AR10.

2. **Skill feedback:** add the case to `references/FAILURE-MODES.md` so future runs catch the pattern. The case is: "the rubric classified X as `novel-and-accretive`; it was actually a partial fix that needed companion changes that were also stashed but classified differently."

3. **Don't blame the skill alone.** Phase 8 fresh-eyes had ≥2 clean rounds; Phase 6 ran gates. The bug bypassed all of them. Update the gates or the rubric.

---

## AR14 — Skill output references files outside the skill's blast radius

**Symptom:** the handoff report mentions a file the skill never touched (e.g., a sibling repo).

**Recovery:**

1. **Investigate.** The skill's scope is one repo. References to other paths are bugs in the report or the user's misunderstanding.

2. **The handoff template should be self-contained.** Re-emit if there are stale or wrong references.

---

## When to escalate

The skill's recovery options are designed to make most catastrophes recoverable. The cases that are NOT recoverable:

- **AR1 + AR4 simultaneously**: bundle and refs both gone, gc pruned the commits
- **Filesystem catastrophe**: disk loss, OS reinstall without backups
- **Git internal corruption**: `.git/` is mangled and `git fsck` reports errors

For these, escalate to:
- The user's backup system (off-skill)
- Forensic git tooling (`git fsck`, `git reflog --all`)
- A senior engineer who knows the codebase well enough to reconstruct from memory

The skill never claims to recover from disk loss. It claims to make every drop reversible *while the bundle and refs are intact*.
