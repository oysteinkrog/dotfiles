# Failure Modes — Branch + Worktree Diagnostic Playbook

Every entry below is a known-quantity hazard from the asupersync 47-worktree+213-branch motivating session, from documented git internals, or from the sibling [stash-janitor's FAILURE-MODES](../../git-stash-janitor/references/FAILURE-MODES.md). Treat them as rails, not surprises.

This file is the long form of the SKILL.md "Failure Modes Table." Each entry has: **symptom**, **cause**, **what to do** (the fix), and where helpful, a **reproduction**, **diagnostic recipe**, or **worked example**.

---

## F1. `git format-patch` IS valid for branches, NOT for stashes

**Symptom:** an agent fresh from a stash-janitor run hesitates to use `git format-patch <merge-base>..<branch>` in the bundle, thinking it's the same footgun as `git format-patch -1 stash@{N}`.

**Cause:** the rule "format-patch is not the stash recovery diff" is **stash-specific** and does NOT generalize. Stashes are merge commits with weird parent semantics; their format-patch output is unreliable. Branches are normal commit chains; format-patch produces a clean, ordered patch series.

**What to do:** use `git format-patch <merge-base>..<branch>` freely for branches. The bundle includes a per-branch `format-patch/*.patch` series. The bundle's `README.md` cross-links **both ways** to the stash-janitor convention so future readers don't reach the wrong conclusion.

**Why:** SKILL.md Axiom 7. Cross-link to [stash-janitor's FAILURE-MODES F1](../../git-stash-janitor/references/FAILURE-MODES.md#f1-git-format-patch--1-stashn-is-not-the-stash-recovery-diff) for the inverse footgun.

**Diagnostic recipe (proves format-patch works for the branch in question):**
```bash
mb=$(git merge-base "$canonical" "$branch")
git format-patch "$mb..$branch" -o /tmp/branch-patches/
# Round-trip check on a fresh worktree:
git worktree add /tmp/branch-roundtrip "$mb"
git -C /tmp/branch-roundtrip am /tmp/branch-patches/*.patch
git -C /tmp/branch-roundtrip log --format='%H %s' "$mb..HEAD" | sort > /tmp/applied.txt
git log --format='%H %s' "$mb..$branch" | sort > /tmp/expected.txt
diff /tmp/applied.txt /tmp/expected.txt && echo OK || echo MISMATCH
git worktree remove --force /tmp/branch-roundtrip
```

---

## F2. `git branch -D <name>` reflog window

**Symptom:** the user changes their mind 60 days after the run, runs `git reflog` to find the deleted branch's tip, and the entries are gone.

**Cause:** Reflog gc window is finite. `gc.reflogExpire` defaults to 90 days; `gc.reflogExpireUnreachable` defaults to 30 days. After that window, unreachable commits are pruned.

**What to do:** the backup ref in `refs/branch-rationalization-backup/<slug>` AND the `git bundle` are the long-term safety nets; both survive reflog gc. Recovery from the backup ref:

```bash
git branch <name> refs/branch-rationalization-backup/<slug>
```

If both the backup ref and the bundle are lost, recovery within the gc window is via reflog:

```bash
git reflog --all --date=iso | grep <branch-name-pattern>
git branch <name> <sha-from-reflog>
```

Cross-link to [RECOVERY-RECIPES.md R5](RECOVERY-RECIPES.md#r5-the-whole-bundle-is-gone).

**Why:** standard git internals; SKILL.md Failure Modes table.

---

## F3. `git branch -d <name>` (lowercase) refuses to delete an unmerged branch

**Symptom:** `git branch -d feature/redact-secrets` fails with "the branch 'feature/redact-secrets' is not fully merged."

**Cause:** lowercase `-d` is a **built-in safety check**: it refuses to delete a branch whose tip is not reachable from the current `HEAD`.

**What to do:** this is a **feature**, not a bug. The refusal usually means one of:

1. The branch was supposed to be an "applied-keeper" but Phase 8 didn't actually land its content (a classification or apply bug). Investigate before forcing.
2. The branch is genuinely unmerged and the user has explicitly tagged it `unmerged-discardable` in `triage.tsv`. Then `-D` is appropriate.
3. The user is on the wrong checkout and from this branch's perspective, `feature/redact-secrets` IS merged. Switch to the rationalization branch first: `git switch branch-rationalization-<DATE>`.

**Why:** SKILL.md Axiom 8 — "`git branch -d` over `git branch -D` whenever possible."

**Diagnostic recipe (decide whether `-d` should have worked):**
```bash
# Are the branch's commits reachable from HEAD?
git merge-base --is-ancestor <branch> HEAD && echo "merged: -d should work" || echo "unmerged: investigate"

# What's on the branch that's not reachable from canonical?
git log --oneline <canonical>..<branch>

# Was its content reapplied via squash-merge or rebase-and-merge (no ancestry)?
git cherry -v <canonical> <branch>     # all minus signs = content is on canonical
```

---

## F4. `git worktree remove <path>` refuses on dirty worktrees

**Symptom:** `git worktree remove /data/projects/foo--wt-3` fails with "/data/projects/foo--wt-3 contains modified or untracked files, use --force to delete it."

**Cause:** built-in safety check. Removing a dirty worktree without archiving its dirty state would lose work.

**What to do:** Phase 3 has already archived the dirty state in `<bundle>/worktrees/<sanitized>/{staged.diff, unstaged.diff, .untracked.list, untracked.tar.gz}`. Verify that's present:

```bash
[ -f "$BUNDLE/worktrees/<sanitized>/status.txt" ] || halt "bundle missing for this wt"
```

Then `--force` is acceptable IF the user has explicitly OK'd losing the dirty state via verbatim authorization. Otherwise, surface to user — the dirty state may be valuable harvest material (HARMONIZATION.md §8.8).

**Why:** SKILL.md Axiom 11; Axiom 4.

**Diagnostic recipe:**
```bash
# What is the dirty state?
git -C <wt-path> status --porcelain=v2 -uall

# Is it captured in the bundle?
diff -q <(git -C <wt-path> diff --binary --cached) "$BUNDLE/worktrees/<sanitized>/staged.diff"
diff -q <(git -C <wt-path> diff --binary)         "$BUNDLE/worktrees/<sanitized>/unstaged.diff"
```

---

## F5. The currently-checked-out branch can't be deleted

**Symptom:** `git branch -d feature/foo` fails with "Cannot delete branch 'feature/foo' checked out at '<path>'."

**Cause:** git refuses to delete a branch that's checked out in any worktree (the active one OR a linked one).

**What to do:**
1. **If checked out in the active worktree:** switch to canonical or the rationalization branch first: `git switch <canonical>`. Then retry the delete.
2. **If checked out in a linked worktree:** that worktree must be removed (or its branch switched) FIRST. This is exactly Axiom 9's rule: worktrees are removed first, branches second. The cleanup script's worktree-first ordering handles this automatically.
3. **The active worktree's branch is auto-protected** by Phase 4; this case shouldn't arise via the skill's own cleanup plan, but it can arise if the user is running other commands.

**Why:** SKILL.md Axiom 9 — "Worktrees are removed first, branches second."

**Diagnostic recipe (find which worktree is holding the branch):**
```bash
git worktree list --porcelain | awk '
  /^worktree / {wt=$2}
  /^branch / {if ($2 == "refs/heads/'"$branch"'") print wt}
'
```

---

## F6. The currently-active worktree can't be removed from inside

**Symptom:** `git worktree remove .` (or `git worktree remove "$PWD"` from inside the active worktree) fails with "fatal: '.' is the working tree of HEAD."

**Cause:** git refuses to remove the worktree you're currently operating from. The skill enforces this independently.

**What to do:** the active worktree is auto-protected (`protected.tsv:active=true`). The handoff report tells the user how to remove it themselves after the skill's run completes:

```
The currently-active worktree (/data/projects/foo--wt-active) is NOT being removed
by this skill — git won't let it be removed from inside, and we don't want to.

To remove it yourself, switch to a different directory first:

    cd /data/projects/foo
    git worktree remove /data/projects/foo--wt-active
```

**Why:** SKILL.md Axiom 11; ANTI-PATTERNS W17.

---

## F7. A branch with `[gone]` upstream tracking has unique commits

**Symptom:** `git branch -vv` shows `feature/foo bdef123 [origin/feature/foo: gone] commit msg`. The user wants to auto-delete every `[gone]` branch.

**Cause:** `[gone]` means the **remote tracking ref** is gone (the upstream branch was deleted on the remote). It does NOT mean the local branch's commits are gone or already integrated.

**What to do:** treat `[gone]` as a hint, not a verdict. Triage normally:

```bash
# Does the local branch have unique commits?
git log --oneline <canonical>..<branch>

# Is its content already on canonical (squash-merge / rebase-merge detection)?
git cherry -v <canonical> <branch>
```

If `cherry -v` shows all `-` lines, classify as `already-merged`. If it shows `+` lines, the branch has unique content the upstream never saw (or the upstream had it but was rewritten); treat as `partially-novel` or `novel-and-accretive` per the rubric. **Never** auto-delete based on `[gone]` alone.

**Why:** SKILL.md Failure Modes table; ANTI-PATTERNS W15.

---

## F8. Submodule init state varies per worktree

**Symptom:** removing a worktree fails or leaves stale submodule state. Different worktrees have submodules cloned to different commits — or some have submodules cloned, others don't.

**Cause:** `git worktree add` does NOT auto-init submodules. Some worktrees have `git submodule update --init` run; others don't. `git worktree remove` cleans up the worktree directory and `.git/worktrees/<id>/` admin metadata, but submodule clones in `.git/modules/<submodule>/` are shared and survive removal.

**What to do:**
- Document the per-worktree submodule state in `worktrees.tsv:submodule_state` (one of `init`, `not-init`, `partial`, `n/a`). The inventory script captures this.
- Removal of the worktree leaves the submodule cache untouched; this is correct.
- If the user wants to reduce disk via submodule cleanup, that is a separate operation (`git submodule deinit`) and out of scope for this skill.

**Diagnostic recipe (per worktree):**
```bash
git -C <wt-path> submodule status 2>/dev/null | awk '{print $1, $2}'
# +<sha> <path> — submodule is initialized but at a different commit than expected
# -<sha> <path> — submodule is not initialized
#  <sha> <path> — submodule is initialized and at the expected commit
```

---

## F9. Locked worktrees on stale paths require `--porcelain` parsing

**Symptom:** `git worktree list` shows a worktree without a "(locked)" annotation in the human-readable format, but cleanup fails because the worktree is actually locked. Or the human-readable output omits a locked worktree on a stale path entirely.

**Cause:** `git worktree list`'s human-readable format is not stable across git versions and may omit the `locked` flag for stale paths. The `--porcelain` format always includes it.

**What to do:** always parse `--porcelain` and check the `locked` field explicitly. Never rely on the human-readable format for programmatic decisions.

**Why:** SKILL.md Failure Modes table; SKILL.md Axiom 9 ("Locked worktrees on stale paths require `--porcelain` parsing").

**Diagnostic recipe:**
```bash
git worktree list --porcelain | awk '
  BEGIN { wt=""; locked="no" }
  /^worktree / { if (wt) print wt, locked; wt=$2; locked="no" }
  /^locked/    { locked="yes" }
  END { if (wt) print wt, locked }
'
```

If a worktree is locked and the cleanup plan wants to remove it, surface to user — locks were placed for a reason (often: a worktree on a removable disk that's currently unmounted).

---

## F10. `git worktree prune` only cleans admin metadata; never a substitute for `remove`

**Symptom:** ran `git worktree prune` expecting it to clean up worktrees; the directories are still on disk.

**Cause:** `git worktree prune` removes `.git/worktrees/<id>/` admin metadata for worktrees whose **directories were already deleted out-of-band**. It does NOT remove the worktree directory itself.

**What to do:**
1. Use `git worktree remove <path>` for **structural** removal (deletes the directory AND prunes the admin metadata).
2. Run `git worktree prune` AFTER, as a follow-up to clean residual admin metadata for worktrees deleted out-of-band by other actors (e.g., a build system, a previous misuse of `rm -rf`).

**Why:** SKILL.md Axiom 9; ANTI-PATTERNS W7.

**Diagnostic recipe (find prunable entries):**
```bash
git worktree list --porcelain | awk '
  BEGIN { wt="" }
  /^worktree / { wt=$2 }
  /^prunable/ { print wt, "PRUNABLE" }
'
```

If you see `PRUNABLE` entries, those are admin-metadata stragglers from out-of-band deletions; `git worktree prune` is the right tool. Worktrees not flagged `PRUNABLE` need `git worktree remove`.

---

## F11. Cherry-picking a merge commit requires `-m 1`

**Symptom:** `git cherry-pick <merge-sha>` fails with "is a merge but no -m option was given."

**Cause:** merge commits have multiple parents. Without `-m`, git can't decide which parent's diff to apply.

**What to do:** use `-m 1` (apply the diff against the first parent — the mainline). Document the choice in the bundle's per-branch `meta.txt`. If `-m 2` is needed (rare; the second parent is the mainline in some workflows), the user explicitly OKs that choice.

```bash
git cherry-pick -m 1 <merge-sha>
```

**Why:** SKILL.md Failure Modes table.

**Diagnostic recipe:**
```bash
# Show the merge's parents:
git log -1 --format='%H %P' <sha>
# First parent is usually mainline. To verify, check which parent matches your canonical:
git merge-base --is-ancestor $(git rev-parse <sha>^1) <canonical> && echo "parent 1 is mainline"
git merge-base --is-ancestor $(git rev-parse <sha>^2) <canonical> && echo "parent 2 is mainline"
```

---

## F12. Cherry-picking a squash-merged commit produces "nothing to commit"

**Symptom:** `git cherry-pick <sha>` produces "The previous cherry-pick is now empty, possibly due to conflict resolution. … nothing to commit."

**Cause:** the commit's content was already squash-merged onto canonical. The diff against current HEAD is empty because patch-id matches.

**What to do:** classify as `already-merged` and skip. Recognize this **before** attempting the cherry-pick using `git cherry -v`:

```bash
git cherry -v <canonical> <branch>
# Output:
# - <sha1> commit msg     ← content is on canonical (patch-id match)
# + <sha2> commit msg     ← content is novel
```

If you're already mid-cherry-pick, `git cherry-pick --skip` continues without committing the empty pick.

**Why:** SKILL.md Axiom 17 — "`git cherry -v` is the canonical 'is this content already on canonical' check."

**Diagnostic recipe (per-branch decision):**
```bash
all_minus=$(git cherry -v <canonical> <branch> | grep -c '^-' || true)
all_plus=$(git cherry -v <canonical> <branch> | grep -c '^+' || true)

if [ "$all_plus" = 0 ]; then
  echo "verdict: already-merged"
elif [ "$all_minus" = 0 ]; then
  echo "verdict: novel candidate"
else
  echo "verdict: partially-novel ($all_plus novel, $all_minus already-merged)"
fi
```

---

## F13. `git rebase` of a branch whose upstream was force-pushed produces nonsense

**Symptom:** `git rebase <upstream> <branch>` produces a rebase output where commits are duplicated, attributed to wrong authors, or applied in the wrong order. The resulting branch tip's history is incoherent.

**Cause:** the upstream branch's history was rewritten (force-push). `git rebase` tries to replay the local commits onto the new upstream, but the divergence isn't a simple replay — it's a graph-rewrite that the rebase logic can't unwind cleanly.

**What to do:** before rebasing, inspect the upstream's reflog (if accessible) for force-push markers. Refuse to rebase if the upstream's commit history shows divergent rewrites.

```bash
# Check if the local branch's previous upstream tip is reachable:
git reflog show <branch> --date=iso | head -20

# If the upstream's history was rewritten, look for the "real" merge-base
# by finding the most recent common ancestor across reflog entries:
git merge-base <branch> <canonical>
git merge-base <branch> origin/<upstream-name>
```

If the merge-bases differ wildly from each other and from the reflog tip of `<branch>`, the upstream was rewritten. Surface to user; the right move is usually `git cherry-pick` of the genuinely-novel commits onto the rationalization branch, not a rebase.

**Why:** SKILL.md Failure Modes table.

---

## F14. Two branches collide on the same file with incompatible defensive checks

**Symptom:** `triage.tsv` shows three branches all touching `src/util/logger.rs` with `defensive` intent.

**Cause:** common in agent-swarm aftermath. Multiple agents independently hardened the same module.

**What to do:** **this is exactly when ◇ HARMONIZE applies.** Phase 7 builds the variant matrix; per-variant intent is identified; defensive checks compose (HARMONIZATION.md §4.2). Don't pick one and don't drop both.

**Why:** SKILL.md Axiom 1; HARMONIZATION.md §1.

Cross-link to [HARMONIZATION.md §7](HARMONIZATION.md#7-worked-example--logger-harmonization-across-three-branches) for the full worked example.

---

## F15. Working tree shows changes from other agents mid-run

**Symptom:** `git -C <wt-path> status` shows files modified that the skill didn't touch.

**Cause:** other agents working in the same repo (or in linked worktrees), per AGENTS.md "Note for Codex/GPT-5.5". This is the normal state in a multi-agent environment, not an error.

**What to do:** treat the changes as if you made them. Snapshot `git status` at Phase 0 (`wt_phase0.txt`) and re-snapshot before each Phase 8 apply (`↺ WORKING-TREE-DRIFT` operator). Never stash, revert, or overwrite. If the apply conflicts with concurrent changes, surface to the user — don't auto-resolve.

**Why:** SKILL.md Axiom 12. Cross-link to [stash-janitor's FAILURE-MODES F5](../../git-stash-janitor/references/FAILURE-MODES.md#f5-working-tree-shows-changes-from-concurrent-agents).

---

## F16. DCG blocks `rm -rf <bundle>/branches/`

**Symptom:** the skill or the user tries to clean up old bundle subdirectories and gets a DCG block.

**Cause:** DCG blocks `rm -rf` per AGENTS.md "Irreversible Git & Filesystem Actions", even on auxiliary directories.

**What to do:** the skill is **designed never to delete the bundle** — it's the user's safety net. If you find yourself wanting to clean up bundle contents:
- Don't.
- The bundle is intentionally kept until the user decides otherwise.
- If a Phase 8 apply produces a `.split.diff` you want to "clean up," just leave it in place — it's a useful audit trail.

**Why:** SKILL.md Axiom 18.

---

## F17. Two branches introduce the same fingerprint

**Symptom:** branch `agent-cleanup-pass-3` and branch `agent-cleanup-pass-5` both contain a function `redact_secrets`. Both have been classified `novel-and-accretive`. Phase 8 applies both and gets a duplicate-definition build error.

**Cause:** common when the branch list represents many parallel agent attempts at the same task.

**What to do:** during triage, mark all but the most recent as `superseded-by-newer-branch` if both have ≥80% fingerprint overlap. Only the most recent gets `novel-and-accretive`. Operator `⊞ RE-FINGERPRINT` (Phase 8, between applies) catches stragglers that flip after the first apply lands.

**Why:** SKILL.md Failure Modes table; Axiom 16.

**Diagnostic recipe:**
```bash
# Extract fingerprints (function names introduced) per branch:
for b in $(git branch --format='%(refname:short)'); do
  mb=$(git merge-base "$canonical" "$b")
  git diff "$mb..$b" -- '*.rs' | grep -E '^\+[[:space:]]*pub fn ' | sort -u > /tmp/fp-$b.txt
done

# Find pairs of branches with overlapping fingerprints:
for a in /tmp/fp-*.txt; do
  for b in /tmp/fp-*.txt; do
    [ "$a" \< "$b" ] || continue
    overlap=$(comm -12 "$a" "$b" | wc -l)
    [ "$overlap" -gt 0 ] && echo "$a vs $b: $overlap shared fingerprints"
  done
done
```

---

## F18. Branch count differs between two runs

**Symptom:** Phase 2 inventory says 213 branches; later you re-list and see 211.

**Cause:** a concurrent agent created or deleted a branch between snapshots.

**What to do:** the bundle's `index.tsv` is authoritative for *that snapshot point*. If a re-list disagrees:
- If branches were added: they're not in the bundle. Phase 10 cannot delete them. Tell the user.
- If branches were removed: they're already gone. The bundle still has the recovery artifacts.

If the count drops by >1 between phases, halt and ask the user — something might be wrong. Re-run Phase 2; never act on a stale inventory.

**Why:** SKILL.md Failure Modes table; Axiom 4.

---

## F19. `git push --delete origin <branch>` runs irreversibly

**Symptom:** the user (or a misconfigured skill run) ran `git push --delete origin <branch>`. The remote ref is gone.

**Cause:** remote operations are irreversible without remote reflog access (which most users don't have or don't know how to use).

**What to do:**
- **Out of scope by default.** SKILL.md Axiom 15. The skill never runs remote-mutating commands.
- If the user explicitly opts into remote cleanup with `--prepare-remote-list`, the skill emits a list of `git push --delete origin <branch>` commands; the user runs them themselves.
- **Recovery:** if remote reflog access is available (GitHub: `gh api repos/<owner>/<repo>/git/refs/heads/<branch>` for protected refs; GitLab: project audit log; self-hosted: depends on server config), the user can recover. Otherwise, the local backup ref + the bundle's diff/format-patch are the only recovery paths.

**Why:** SKILL.md Axiom 15.

---

## F20. Beads database lock during the run

**Symptom:** `br create` returns `database is locked` or similar.

**Cause:** a parallel `br` process holds the SQLite lock.

**What to do:** retry with backoff (3 attempts, 5 / 10 / 20 seconds). If still failing, skip the beads-issue creation; record `beads_skipped: true` in the handoff report. The run still succeeds.

**Why:** SKILL.md Failure Modes table. Cross-link to [stash-janitor's FAILURE-MODES F11](../../git-stash-janitor/references/FAILURE-MODES.md#f11-beads-database-unwritable-during-the-run).

---

## F21. Refusing to delete the canonical branch

**Symptom:** the cleanup plan accidentally lists the canonical branch (`main` / `master` / `develop`) in the deletion list. The skill refuses.

**Cause:** the canonical branch is auto-protected. Always.

**What to do:** the protection logic in Phase 4 auto-includes the canonical branch in `protected.tsv:protected=true`. The cleanup script verifies the cleanup-list intersection with `protected.tsv` is empty before executing. If the list somehow includes a protected branch, halt and surface — don't filter silently (the underlying logic bug needs investigation).

**Why:** SKILL.md Axiom 5; Polish Bar dimension "Order of cleanup" — "protected branches NEVER deleted."

**Diagnostic recipe:**
```bash
# Verify the cleanup list excludes protected items:
comm -12 \
  <(awk -F'\t' 'NR > 1 {print $1}' "$WS/cleanup_plan_branches.tsv" | sort -u) \
  <(awk -F'\t' 'NR > 1 && $2 == "true" {print $1}' "$WS/protected.tsv" | sort -u)
# Should produce zero lines. If non-empty, halt — the plan is broken.
```

---

## F22. Phase 8 commit fails because of a pre-commit hook

**Symptom:** `git commit` returns non-zero with a hook error (e.g., `husky: prettier check failed`, `pre-commit: rustfmt check failed`).

**Cause:** the recovered hunk doesn't match the project's current formatting / linting rules. The branch predates a tightening of the rules.

**What to do:** **never `--no-verify`.** Either:
- Re-run formatter (`cargo fmt`, `prettier --write`) on the affected files; if format changes don't break semantics, create a NEW commit (not `--amend`, per the standard hook-failure protocol).
- If the issue is structural (e.g., the linter forbids a pattern the branch uses), surface to the user; the recovered content may need a small adaptation.

Record the failure in `apply_log.tsv:gates_status = "hook-failed: <hook-name>"`.

**Why:** SKILL.md Axiom 13; ANTI-PATTERNS W14. Cross-link to [stash-janitor's FAILURE-MODES F15](../../git-stash-janitor/references/FAILURE-MODES.md#f15-phase-6-commit-fails-because-of-a-pre-commit-hook).

---

## F23. The rationalization branch already exists

**Symptom:** `git checkout -B branch-rationalization-2026-05-07 <canonical>` succeeds (because `-B` resets), but the user had unrelated work on the branch from a previous run.

**Cause:** running the skill twice on the same day, or resuming a run from a previous day.

**What to do:** Phase 0 (Up-Front Confirmations) detects this. If the branch exists:
- Ask the user whether to (a) extend it (resume the run), (b) rename + use a new branch (`branch-rationalization-2026-05-07-2`), (c) abort.
- **Never silently `-B` away existing work.**

**Why:** SKILL.md "Up-Front Confirmations" → "Resuming a prior run?" Cross-link to [stash-janitor's FAILURE-MODES F13](../../git-stash-janitor/references/FAILURE-MODES.md#f13-the-recovery-branch-already-exists).

---

## F24. The bundle directory already exists

**Symptom:** `<project-parent>/<basename>-branch-worktree-archive-<YYYY-MM-DD>/` already exists.

**Cause:** running the skill twice in the same day.

**What to do:** Phase 3's `build-bundle.sh` refuses to overwrite a non-empty bundle by default. Options:
- `BUNDLE_REUSE_OK=1` — verify byte-equality of existing artifacts and reuse only if they match.
- `BUNDLE_OVERRIDE=<basename>-branch-worktree-archive-<YYYY-MM-DD>-2/` — fresh bundle in a new directory.
- Abort if neither is acceptable.

In-place rebuild (`BUNDLE_REBUILD_IN_PLACE_OK=1`) requires explicit user approval.

**Why:** SKILL.md Axioms 3 + 4. Cross-link to [stash-janitor's FAILURE-MODES F14](../../git-stash-janitor/references/FAILURE-MODES.md#f14-the-bundle-directory-already-exists).

---

## F25. Same-name on canonical is not always supersession

**Symptom:** branch introduces `redact_secrets`; canonical also has `redact_secrets`. Naive triage marks the branch as `superseded`. But the two implementations have different signatures — branch's takes `(msg: &str) -> String`, canonical's takes `(msg: &str, patterns: &[Regex]) -> String`.

**Cause:** unrelated landing took the same name (or different agents converged on the same name independently).

**What to do:** the same-signature heuristic in [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md) catches most of these. When `same_signature=false` on >30% of sampled symbols, the verdict flips from `superseded` to either `partially-novel` or `divergent-refactor`, surfaced to user in Phase 6.

**Why:** SKILL.md Axiom 16; HARMONIZATION.md §3 (intent identification handles signature differences).

**Diagnostic recipe:**
```bash
# Per fingerprint symbol, compare signatures across canonical and branch:
fp="redact_secrets"
git grep -nE "fn $fp\\b" "$canonical" -- '*.rs' | head -3 > /tmp/canon-sig.txt
git grep -nE "fn $fp\\b" "$branch" -- '*.rs' | head -3 > /tmp/branch-sig.txt
diff /tmp/canon-sig.txt /tmp/branch-sig.txt
# Identical → likely superseded. Different → divergent or refactor; investigate.
```

---

## F26. Phase 9 fresh-eyes never converges (loops finding the same nit)

**Symptom:** round 4 finds the same lint warning round 3 found; the agent isn't actually fixing it.

**Cause:** the lint warning may be unfixable (a project rule the recovered code can't satisfy) or the agent is stuck.

**What to do:** Phase 9 termination rule is "two consecutive rounds with only trivial findings AND gates green." If the same finding appears three rounds in a row, surface to user as a "blocking unresolvable" — let the user decide whether to:
- Adapt the recovered code to fix it.
- Accept the lint warning (often via `#[allow(...)]` or equivalent).
- Drop the keeper.

**Why:** SKILL.md Phase 9 termination rule. Cross-link to [stash-janitor's FAILURE-MODES F19](../../git-stash-janitor/references/FAILURE-MODES.md#f19-phase-8-fresh-eyes-never-converges-loops-finding-the-same-nit).

---

## F27. The rationalization branch's tip diverges from canonical mid-run

**Symptom:** between Phase 0 and Phase 8, `<canonical>` advanced (a teammate or another agent landed commits). The rationalization branch's base is now stale.

**Cause:** other developers / agents working concurrently.

**What to do:** Phase 8 doesn't need to track canonical in real-time — the rationalization branch was created off canonical's tip at a specific snapshot, and that's fine. After handoff, the user rebases or merges the rationalization branch onto the latest canonical:

```bash
git fetch origin                                                    # update local refs
git switch <canonical>
git pull --ff-only                                                   # update local canonical
git rebase <canonical> branch-rationalization-<DATE>                # rebase onto latest
```

The handoff report includes this recipe verbatim. Cross-link to [stash-janitor's FAILURE-MODES F20](../../git-stash-janitor/references/FAILURE-MODES.md#f20-the-recovery-branch-tip-diverges-from-originprimary).

---

## F28. A worktree is on a path the skill can't write to

**Symptom:** `git -C /mnt/external-disk/foo--wt-9 status` returns "Permission denied" or "Read-only file system."

**Cause:** the worktree is on a removable disk that's read-only (mounted ro), on an NFS mount with restricted permissions, or on a directory the user no longer owns.

**What to do:**
- If read-only: `git worktree list --porcelain` should still return the entry (read-only access to the worktree's `.git/worktrees/<id>/` is enough for listing). The skill can capture the dirty state if the worktree is genuinely clean, or it must surface to the user that it can't capture.
- If permission-denied: the skill cannot capture the dirty state. The worktree gets `protected=true` in `protected.tsv` with reason `unwritable-path`. It is NOT included in any cleanup plan.

**Diagnostic recipe:**
```bash
git -C <wt-path> status --porcelain >/dev/null 2>&1
case $? in
  0)   echo "OK" ;;
  128) echo "PROTECTED: unable to access worktree" ;;
  *)   echo "PROTECTED: unknown error" ;;
esac
```

---

## F29. A worktree's `.git` admin directory is corrupt

**Symptom:** `git -C <wt-path> status` returns "fatal: not a git repository" or "fatal: this operation must be run in a work tree."

**Cause:** the worktree's `.git` file (which normally points at `.git/worktrees/<id>/`) is missing, malformed, or the linked admin directory is missing.

**What to do:**
- Capture the file contents (working tree is still on disk; it's just not a valid worktree from git's perspective). The "dirty state" capture for this worktree falls back to `tar -czf` of the entire directory, with a flag in `worktrees.tsv:state="orphan-worktree"`.
- Removal cannot use `git worktree remove`. The user manually `mv`s the directory to an archive location (the skill never does `rm -rf`); the skill then runs `git worktree prune` to clean the admin metadata for this entry.

**Diagnostic recipe:**
```bash
[ -e <wt-path>/.git ] || echo "ORPHAN: no .git file"
git -C <wt-path> rev-parse --show-toplevel 2>/dev/null || echo "ORPHAN: not a git worktree"
```

---

## F30. UBS not installed on this host

**Symptom:** `ubs <files>` returns `command not found`.

**Cause:** UBS is project-specific; not every project uses it.

**What to do:** `project_profile.json:ubs_available` should be `false` for projects without UBS. Phase 8's `⊕ RECOVER` operator skips UBS when not available. The skill should NEVER fail because UBS isn't installed. Cross-link to [stash-janitor's FAILURE-MODES F12](../../git-stash-janitor/references/FAILURE-MODES.md#f12-ubs-not-installed-on-this-host).

---

## F31. Phase 5 triage takes too long

**Symptom:** triage workers running for over 90 minutes on a 200-branch repo.

**Cause:** whole-repo grep on every fingerprint × every branch = O(N²) work.

**What to do:**
- Path-scoped grep first (`git grep -F <symbol> <branch> -- <expected_path>`).
- Cache `verify-on-canonical` results per-fingerprint within a batch.
- If many branches share fingerprints (common with parallel-agent attempts), dedupe the verify-on-canonical calls across the batch.
- For Comprehensive mode (200+ branches), spawn more workers (8–12 vs. 4–6).

**Why:** SKILL.md "Mode Variants"; Phase 5 parallelism model. Cross-link to [stash-janitor's FAILURE-MODES F18](../../git-stash-janitor/references/FAILURE-MODES.md#f18-phase-4-takes-too-long).

---

## F32. The user's authorization phrase doesn't include a literal command

**Symptom:** Phase 10 ⚠ CONFIRM gate, user types "yes proceed".

**Cause:** the user is being efficient but the authorization isn't specific enough per AGENTS.md "Mandatory explicit plan".

**What to do:** the operator's prompt module requires a phrase that includes a literal command. Re-ask with a specific template:

> Please paste this verbatim to proceed:
>
>     yes I understand and want to remove 47 worktrees and delete 173 branches per the plan above

If the user types something different, re-ask. If the user objects ("just trust me"), explain that the verbatim authorization is per AGENTS.md policy.

**Why:** SKILL.md Axiom 14. Cross-link to [stash-janitor's FAILURE-MODES F16](../../git-stash-janitor/references/FAILURE-MODES.md#f16-the-users-authorization-phrase-doesnt-include-a-literal-command).

---

## F33. The merge-base for a branch is unreachable

**Symptom:** `git merge-base <canonical> <branch>` returns nothing, or returns a SHA that's not in the current commit graph.

**Cause:**
- The branch was created from a now-deleted side branch and never had ancestry with canonical.
- A previous force-push rewrote canonical's history and the original merge-base was orphaned.
- `git gc` pruned the merge-base commit.

**What to do:**
- For format-patch / diff-vs-merge-base: pick a synthetic base (canonical's root commit, or the oldest reachable ancestor). The bundle's `meta.txt` records the chosen base AND notes that it's synthetic.
- For triage: a branch with no merge-base against canonical is a "fully-divergent" candidate. Treat as `divergent-refactor` and surface to user — auto-recovery is not safe.

**Diagnostic recipe:**
```bash
mb=$(git merge-base "$canonical" "$branch" 2>/dev/null)
if [ -z "$mb" ]; then
  echo "no merge-base; candidates:"
  git log --format='%H %s' "$branch" | tail -5  # oldest commits on branch
  echo "canonical root:"
  git log --format='%H' "$canonical" | tail -1
fi
```

---

## F34. A branch's commit is signed and the signing key isn't available locally

**Symptom:** `git cherry-pick <sha>` succeeds but produces an unsigned commit on the rationalization branch, even though the source commit was signed. Or pre-commit hook fails because the project requires signed commits.

**Cause:** signing happens at commit time, not at cherry-pick time. The cherry-pick author's signing key is what would be used for the new commit, not the original signer's.

**What to do:**
- Document the signing-loss in the apply log: `apply_log.tsv:notes="signature-not-preserved"`.
- The user reviewing the rationalization branch may want to re-sign the commits themselves before merging.
- If the project enforces signed commits via a pre-commit hook, the agent's git config must have a signing key set up; otherwise surface to user.

---

## Diagnostic Recipes — Quick Reference

| Question | Command |
|----------|---------|
| Is the canonical branch detected? | `cat $WS/project_profile.json \| jq -r .canonical_branch` |
| Is the bundle byte-equal to live state? | `bash scripts/verify-bundle.sh $BUNDLE_PATH` |
| Is a branch's content already on canonical? | `git cherry -v <canonical> <branch>` |
| Does a branch have unique commits? | `git log --oneline <canonical>..<branch>` |
| Is a worktree dirty? | `git -C <wt-path> status --porcelain=v2 -uall` |
| Is a worktree locked? | `git worktree list --porcelain \| awk -v wt=<wt-path> '/^worktree / {hit=($2==wt)} /^locked/ && hit {print "yes"; exit}'` |
| Is a branch checked out somewhere? | `git worktree list --porcelain \| awk '/^branch refs.heads.<name>/ {found=1} END {print found?"yes":"no"}'` |
| Are there prunable worktrees? | `git worktree list --porcelain \| grep prunable` |
| Is the merge-base reachable? | `git merge-base <canonical> <branch>` |
| Are signatures the same on a fingerprint? | `git grep -nE "fn <name>\b" <canonical>; git grep -nE "fn <name>\b" <branch>` |
| Is the bundle's index complete? | `wc -l $BUNDLE/index.tsv; ls $BUNDLE/branches/ \| wc -l; ls $BUNDLE/worktrees/ \| wc -l` |
| Was a destructive command authorized? | `cat $WS/cleanup_authorization.txt` (must exist; must include literal command) |

---

## Cross-References

- [SKILL.md](../SKILL.md) — the 19-axiom kernel; the "Failure Modes Table"
- [stash-janitor's FAILURE-MODES.md](../../git-stash-janitor/references/FAILURE-MODES.md) — the sibling catalogue, especially F1 (the inverse of F1 here), F11, F12, F15, F16, F18, F19, F20
- [ANTI-PATTERNS.md](ANTI-PATTERNS.md) — the wrong actions that produce these failure modes
- [HARMONIZATION.md](HARMONIZATION.md) — how to actually solve F14 (the harmonization-when-files-collide case)
- [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md) — how to undo every kind of removal/deletion when a failure mode produces lost content
