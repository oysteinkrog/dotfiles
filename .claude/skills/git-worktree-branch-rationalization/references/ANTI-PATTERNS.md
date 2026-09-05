# Anti-Patterns — Branch + Worktree Specific Things Never to Do

Each anti-pattern is paired with: the wrong action, why it fails, the right alternative, and a worked example.

This file is the branch/worktree-specific extension to the [stash-janitor sibling's ANTI-PATTERNS](../../git-stash-janitor/references/ANTI-PATTERNS.md). Many of the underlying disciplines (verbatim authorization, never deleting the bundle, never bypassing pre-commit hooks, never running scripts over source files) are inherited verbatim from there — those entries below are restated in branch/worktree language with cross-links. Where the stash-janitor convention does NOT generalize (most importantly: `git format-patch` IS valid for branches), this file flags the divergence explicitly.

---

## W1. Mass-delete primitives (`git branch | xargs git branch -D`)

**The mistake:**
```bash
git branch | grep -v '^\*' | grep -v 'main' | xargs -n 1 git branch -D    # WRONG
git for-each-ref refs/heads --format='%(refname:short)' \
  | xargs -I {} git branch -D {}                                          # WRONG
```

**Why it's wrong:**
- Bypasses verbatim authorization (per AGENTS.md "Mandatory explicit plan").
- The `grep`-based filter can fail to exclude protected branches if the protection list isn't in the grep pattern (and writing the right grep pattern is the same problem you're trying to avoid).
- No per-deletion logging; if the user later asks "why was `feature/redact-secrets` deleted", there's no record.
- A typo or shell-escape edge case can take out far more than intended.

**Why:** SKILL.md Axiom 10 — "Mass-delete primitives are forbidden."

**Correct approach:** iterate the cleanup list one entry at a time, restating the verbatim ref before each `git branch -d` / `-D`. The `scripts/drop-retire-confirmed.sh` materializes the list, requires the `confirm=YES_DELETE_BR_<slug>` flag per entry, and logs to `cleanup_log.tsv`.

**Worked example:** in the asupersync 47-worktree+213-branch scenario, the cleanup list had 173 branches across 5 verdict buckets. Running `xargs git branch -D` would have deleted them in one second with no audit trail and no chance to abort if a verdict was wrong. The correct path was 173 individual deletions, each logged, each restating `git branch -d <name>` (or `-D` with explicit user OK for the unmerged ones).

---

## W2. `rm -rf <worktree-path>` instead of `git worktree remove`

**The mistake:**
```bash
rm -rf /data/projects/foo--wt-3                              # WRONG
sudo rm -rf /data/projects/foo--wt-3                         # WRONGER
```

**Why it's wrong:**
- DCG blocks `rm -rf` per AGENTS.md "Irreversible Git & Filesystem Actions". Don't fight DCG.
- Even without DCG, `rm -rf` does NOT prune `.git/worktrees/<id>/` admin metadata. The worktree appears in `git worktree list` as "prunable" forever until you also run `git worktree prune`.
- `git worktree remove` refuses on dirty worktrees — that refusal is the safety net (see W6 below).

**Why:** SKILL.md Axiom 11 — "`rm -rf <worktree-path>` is forbidden; `git worktree remove` is the structured operation."

**Correct approach:**
```bash
# 1. Worktree's dirty state is already in the bundle (Phase 3).
# 2. Use the structured operation:
git worktree remove /data/projects/foo--wt-3                 # refuses if dirty
# 3. If dirty AND user has explicitly OK'd losing the dirty state:
git worktree remove --force /data/projects/foo--wt-3
# 4. Phase 10 follows up to clean residual metadata for any out-of-band-deleted ones:
git worktree prune
```

**Worked example:** an agent accidentally deleted a worktree directory with `rm -rf` (running outside DCG). `git worktree list` continued to show the entry for two months. When the user finally ran `git worktree prune`, they discovered three other worktrees had also been `rm -rf`'d at various points and were also "prunable". No telemetry on when each was lost. Running `git worktree remove` per Axiom 11 would have produced a per-removal log entry.

---

## W3. `git push --delete` on the user's behalf

**The mistake:**
```bash
git push --delete origin feature/redact-secrets              # WRONG
git push origin :feature/redact-secrets                       # WRONG (same thing)
git push --force origin :feature/redact-secrets              # WRONGEST
```

**Why it's wrong:**
- Remote operations are **irreversible** without remote reflog access (which most users don't have or don't know how to use).
- A push-delete on a shared remote can break a teammate's open PR, a CI job's clone, or a downstream tool's reference.
- The user's permission to clean up their *local* branches says nothing about their permission to mutate the *remote*.

**Why:** SKILL.md Axiom 15 — "Remote cleanup is out of scope by default. The skill never runs `git push --delete`, `git push --force`, or any remote-mutating command."

**Correct approach:**
- Default: remote cleanup is `out-of-scope`. The skill emits no remote commands.
- Opt-in: `--prepare-remote-list` causes the skill to write a list of `git push --delete origin <branch>` commands to `cleanup_remote_suggested.sh`. The user runs that script themselves after reading it.
- The skill **never** executes the script. Cross-link to [FAILURE-MODES.md F19](FAILURE-MODES.md#f19-git-push-delete-runs-irreversibly).

**Worked example:** a user ran the skill and forgot to specify `--prepare-remote-list`. The skill cleaned up 173 local branches without touching the remote. The user later ran `git fetch --prune` and saw 173 `[gone]` tracking refs. They reviewed the list and ran `git push --delete` on each one *themselves* over the course of a week, after notifying the team. That's the right sequence.

---

## W4. Skipping the harmonization plan when ≥2 branches collide

**The mistake:** triage shows three branches all touching `src/util/logger.rs`. The agent picks the most-recently-authored one and discards the others.

**Why it's wrong:**
- Loses content from the other branches (defensive checks, tests, fixtures, type-narrowings).
- Reduces this skill to "stash-janitor for branches" — defeats the entire conceptual leap (per [SKILL.md](../SKILL.md), the third `>` block at the top).
- Per Axiom 1 — "Harmonize, don't pick."

**Why:** SKILL.md Axiom 1; [HARMONIZATION.md](HARMONIZATION.md) §1.

**Correct approach:** Phase 7 is **mandatory** whenever the triage shows file-level collisions. Build the variant matrix (HARMONIZATION.md §2), identify each variant's intent (HARMONIZATION.md §3), apply the synthesis principles (HARMONIZATION.md §4), surface the plan to the user for review (HARMONIZATION.md §6.3), then synthesize via the Edit tool (HARMONIZATION.md §6.1).

**Worked example:** in the asupersync session, three branches each added one defensive check to `src/util/logger.rs` (null-arg / length-cap / redact-secrets). Picking just `feature/redact-secrets` (the newest) would have lost the null-arg guard and the length cap. The harmonization synthesis combined all three guards in entry order and lifted all three test files. Cross-link to [HARMONIZATION.md §7](HARMONIZATION.md#7-worked-example--logger-harmonization-across-three-branches).

---

## W5. Landing keeper commits directly on canonical instead of the rationalization branch

**The mistake:**
```bash
git checkout main
git cherry-pick refs/branch-rationalization-backup/feature-redact-secrets   # WRONG
git push origin main                                                         # WRONGER (also see W3)
```

**Why it's wrong:**
- Even with rigorous verification, mass-applied recoveries deserve user review.
- Forces the user to review post-hoc instead of pre-merge.
- Can interfere with concurrent agents working on canonical's tip.
- Bypasses any branch-protection rules (required reviews, status checks) that gate `main` / `master`.
- Eliminates the user's ability to merge at their own pace, in their own merge style (squash vs. rebase vs. merge-commit).

**Why:** SKILL.md Axiom 6 — "Land on a rationalization branch, not on canonical."

**Correct approach:** Phase 8 cuts `branch-rationalization-<DATE>` from canonical's tip. All keeper commits and harmonized syntheses land there. The handoff report tells the user how to merge or cherry-pick from the rationalization branch onto canonical at their pace.

**Worked example:** a previous agent skipped Axiom 6 and applied 41 keeper commits directly to `main`. The user came back to find 41 unreviewed commits on the protected branch with `[skipped]` from the squash-merge protection rule, and a CI run that had been broken for three hours by a recovered keeper that didn't pass the project's tighter linting bar. Re-running the skill correctly: rationalization branch → user reviews → user merges three at a time after fresh-eyes review.

---

## W6. Assuming `main` is canonical

**The mistake:**
```bash
git checkout main                                            # WRONG — many projects use master/develop/trunk
canonical=main                                                # WRONG — hardcoded
git diff main..feature/foo                                   # WRONG — might not exist
```

**Why it's wrong:** Many projects use `master`, `develop`, `trunk`, `default`, `release/2.x`. Hardcoding `main` produces:
- "Branch not found" errors, OR
- Comparisons against the wrong base (giving wrong supersession evidence), OR
- A rationalization branch cut from a non-canonical tip.

**Why:** SKILL.md Axiom 5 — "`main` is not the universal default."

**Correct approach:** detect canonical in Phase 1 (`scripts/discover-project.sh`):

```bash
canonical=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
            | sed 's@^refs/remotes/origin/@@')
canonical=${canonical:-$(git config init.defaultBranch)}
canonical=${canonical:-$(git branch -a | grep -E 'remotes/origin/(main|master|develop|trunk|default)' | head -1)}
```

Write the result to `project_profile.json:canonical_branch`. Read from there in every later phase. Cross-link to [stash-janitor's ANTI-PATTERNS.md A5](../../git-stash-janitor/references/ANTI-PATTERNS.md#a5-assume-main-is-the-primary-branch).

**Worked example:** the asupersync repo uses `master` (not `main`). A previous agent ran `git checkout main`, hit "did not match any file(s) known to git", and aborted. The right path was `git symbolic-ref refs/remotes/origin/HEAD` returning `refs/remotes/origin/master` and using that throughout.

---

## W7. `git worktree prune` as a substitute for `git worktree remove`

**The mistake:**
```bash
# Trying to "clean up" worktrees:
git worktree prune                                           # WRONG (as a substitute)
```

**Why it's wrong:** `git worktree prune` only cleans **admin metadata** for worktrees whose directories were already deleted out-of-band (e.g., the user manually `rm -rf`'d them, or a build system cleaned them up). It does NOT remove the worktree directory itself. Using `prune` as a primary cleanup leaves the worktree directories on disk, occupying space, while merely cleaning the `.git/worktrees/<id>/` admin metadata.

**Why:** SKILL.md Axiom 9 — "Worktrees are removed first, branches second … Never run `git worktree prune` as a substitute for explicit `git worktree remove`."

**Correct approach:**
1. Use `git worktree remove <path>` to **structurally** remove a worktree (deletes the directory AND prunes the admin metadata).
2. Run `git worktree prune` AFTER as a follow-up to clean any residual admin metadata for worktrees deleted out-of-band by other actors.

```bash
# Phase 10 cleanup ordering:
git worktree remove /data/projects/foo--wt-3                 # structural removal
git worktree remove /data/projects/foo--wt-7                 # ...one at a time...
# ...
git worktree prune                                           # follow-up only
```

**Worked example:** an agent ran `git worktree prune` on a repo with 47 worktrees expecting it to clean them up. Result: 47 worktree directories still on disk (consuming 12 GiB), but `git worktree list` cleanly showed all 47 as still present (because their admin metadata wasn't actually stale — the directories really did exist). The agent had to follow up with 47 `git worktree remove` calls.

---

## W8. `git branch -D` when `-d` would have worked

**The mistake:**
```bash
git branch -D feature/redact-secrets                         # WRONG when -d would work
```

**Why it's wrong:** Lowercase `-d` is the **safety check**: it refuses to delete a branch that's not fully merged into the current `HEAD`. Uppercase `-D` bypasses that check. After Phase 8 lands every keeper onto the rationalization branch, every "applied-keeper" branch IS fully merged from the rationalization branch's perspective — `-d` will succeed cleanly. Using `-D` here:
- Skips the safety check that would catch a "this branch wasn't actually merged" bug.
- Hides classification errors (a branch the agent thought was an applied-keeper but actually wasn't).
- Is one step closer to a bad habit on unmerged-and-discardable branches.

**Why:** SKILL.md Axiom 8 — "`git branch -d` over `git branch -D` whenever possible."

**Correct approach:** the cleanup script tries `-d` first and only falls back to `-D` for entries explicitly tagged as `unmerged-discardable` in the cleanup plan.

```bash
# Phase 10 per-branch logic (in scripts/drop-retire-confirmed.sh):
if git branch -d "$branch" 2>/dev/null; then
  echo "deleted: $branch (merged)"
elif [[ "$verdict" == "unmerged-discardable" ]]; then
  git branch -D "$branch"
  echo "deleted: $branch (unmerged, user-acknowledged)"
else
  echo "REFUSED: $branch is unmerged but not tagged unmerged-discardable; halting"
  exit 1
fi
```

**Worked example:** an agent classified `feature/redact-secrets` as an applied-keeper (Phase 8 had landed its content on the rationalization branch). The agent ran `git branch -D feature/redact-secrets` and the deletion succeeded. Two days later, the user noticed that the rationalization branch's commit didn't actually include `redact_secrets()` — Phase 8's `apply-keeper.sh` had silently skipped that file (a path-include bug). With `-d`, git would have refused the deletion: "`feature/redact-secrets` is not fully merged" — exactly the error that would have surfaced the bug.

---

## W9. Deleting an "applied-keeper" branch before its commit lands on the rationalization branch

**The mistake:**
```bash
# WRONG — branch deleted before content is reachable elsewhere
git branch -d feature/redact-secrets
git checkout branch-rationalization-2026-05-07
git cherry-pick <sha>     # at this point sha is unreachable except via reflog
```

**Why it's wrong:**
- If the apply rolls back (gates fail, conflict surfaces, user aborts), the branch is gone and recovery requires the bundle's backup ref OR the reflog (within gc window) — neither of which is the *clean* path.
- Per Axiom 4, all five reversibility layers should tell the same story; deleting the live branch before the rationalization-branch commit lands creates a temporary window where reachability is *only* via the bundle.

**Why:** SKILL.md Phase 8 → Phase 9 → Phase 10 ordering; Axiom 13 (per-apply gates).

**Correct approach (the order is non-negotiable):**

1. Phase 8: apply the keeper onto the rationalization branch (cherry-pick / squash-merge / rebase-merge / harmonized-synthesis).
2. Phase 8: per-apply gates run; if they pass, the commit stands.
3. Phase 9: fresh-eyes review ≥2 clean rounds; full test suite green.
4. Phase 10: NOW delete the source branch (its content is on the rationalization branch AND in the backup ref AND in the bundle — three independent reachability paths).

**Worked example:** an agent deleted `feature/redact-secrets` immediately after `git cherry-pick`. The cherry-pick had a silent merge skip on one hunk. By the time the user reviewed the rationalization branch and noticed the missing hunk, the source branch was gone and the only recovery path was the bundle's `branches/feature-redact-secrets/diff-vs-merge-base.diff`. Recovery worked, but the "expected" recovery path (the backup ref → cherry-pick again) was complicated by needing to also re-create the live branch first. Don't generate that situation.

---

## W10. Skipping Phase 3 byte-equality + bundle-round-trip verification

**The mistake:** "I already created the backup refs and the bundle artifacts. The byte-equality check is just a sanity check; let's skip it to save time."

**Why it's wrong:**
- If the bundle's diff doesn't byte-match the live branch, the backup is **wrong**. The user thinks they have a recovery artifact and they don't.
- If `git bundle list-heads <bundle>/object-bundle.pack` doesn't list every backup ref, the bundle is corrupt or partial.
- A wrong bundle is **worse than no bundle** because the user trusts it.

**Why:** SKILL.md Axioms 3 + 4 — "Plan for irreversibility first, classification second" + "Beneficiary-style coherence: all five layers tell the same story."

**Correct approach:** Phase 3 is a **hard gate**. `scripts/verify-bundle.sh` runs:

```bash
# Per branch:
diff -q <(git diff --binary <merge-base> <branch>) "$BUNDLE/branches/<slug>/diff-vs-merge-base.diff" || halt

# Per worktree:
diff -q <(git -C <wt-path> diff --binary --cached) "$BUNDLE/worktrees/<sanitized>/staged.diff" || halt

# Bundle round-trip:
git bundle list-heads "$BUNDLE/object-bundle.pack" | sort > /tmp/bundle-heads.txt
git for-each-ref refs/branch-rationalization-backup --format='%(refname) %(objectname)' | sort > /tmp/live-heads.txt
diff -q /tmp/live-heads.txt /tmp/bundle-heads.txt || halt
```

Refuse to proceed if even one entry mismatches.

**Worked example:** in an early run, the agent had a bug where `build-bundle.sh` used `git diff` (no `--binary`) for one branch that contained a binary fixture. Phase 3 verification caught the mismatch (the live diff included the binary marker, the bundle didn't). Fixing the bug took 5 minutes; without Phase 3, the user would have lost the binary fixture in recovery and not noticed for weeks.

Cross-link to [stash-janitor's ANTI-PATTERNS.md A11](../../git-stash-janitor/references/ANTI-PATTERNS.md#a11-skip-phase-3-byte-equality-verification).

---

## W11. Script-based source mutation (sed/awk) for conflict resolution

**The mistake:**
```bash
sed -i 's/parse_v1/parse_v1_safe/g' src/parser.rs            # WRONG
awk '/fn log/{print; print "    if msg.is_empty() { return Err(...); }"; next}1' src/util/logger.rs    # WRONG
```

**Why it's wrong:** Per AGENTS.md "No Script-Based Changes":

> NEVER run a script that processes/changes code files in this repo. Brittle regex-based transformations create far more problems than they solve.

`sed` / `awk` / `tr` substitutions on source code:
- Don't understand syntax (will rename matches inside string literals, comments, doc-strings).
- Can produce malformed code (mismatched braces, broken UTF-8) that compiles intermittently.
- Are not reviewable as a diff in a meaningful way; the patch shows "every line where this regex hit", not "every change to semantics."
- Bypass the per-apply quality gates because the tool didn't understand what it was changing.

**Why:** AGENTS.md "No Script-Based Changes"; SKILL.md "The Polish Bar" → "Harmonization fidelity" ("synthesis is authored by the Edit tool"); HARMONIZATION.md §6.1.

**Correct approach:** harmonization synthesis and conflict resolution use the Edit tool, manually, on the rationalization branch. If a conflict appears across many files, surface to the user — don't try to automate a code transformation in the recovery path.

```
# Edit tool invocation, not sed:
Edit src/util/logger.rs
  old_string: "fn log(level: Level, msg: &str) -> Result<()> {\n    write_log_entry(level, msg)\n}"
  new_string: "fn log(level: Level, msg: &str) -> Result<()> {\n    if msg.is_empty() { return Err(LoggerError::EmptyMessage); }\n    write_log_entry(level, msg)\n}"
```

Cross-link to [stash-janitor's ANTI-PATTERNS.md A9](../../git-stash-janitor/references/ANTI-PATTERNS.md#a9-run-a-script-to-fix-up-conflicts).

**Worked example:** an agent tried to "harmonize" three branches' renames of `parse_v1` → `parse_v1_safe` / `parse_v1_checked` / `parse_v1_validated` with a single `sed -i`. The sed pattern hit every occurrence including ones in `tests/legacy_test.rs` (which intentionally referenced the old name to test backward compat) and ones in error messages (`"parse_v1 failed"`). The compile passed but two tests now had wrong assertions and one error message was nonsense. The right path was Edit-tool, file-by-file, with each rename reviewed in context.

---

## W12. Stashing/reverting/overwriting other agents' working-tree changes

**The mistake:**
```bash
git stash push -m "clean up before applying"                 # WRONG
git checkout -- src/parser.rs                                # WRONG
git restore .                                                # WRONG
git reset --hard HEAD                                        # WRONGEST (also see AGENTS.md "Forbidden")
```

**Why it's wrong:** Per AGENTS.md "Note for Codex/GPT-5.5":

> NEVER, under ANY CIRCUMSTANCE, stash, revert, overwrite, or otherwise disturb in ANY way the work of other agents. Just treat those changes identically to changes that you yourself made.

In a multi-agent environment, working-tree changes that "appeared" since you started are concurrent agents' legitimate work. Any of those commands destroys that work.

**Why:** SKILL.md Axiom 12 — "Concurrent agents' working-tree changes in any worktree are normal."

**Correct approach:** treat the changes as if you made them. Snapshot the state at Phase 0 (`wt_phase0.txt`); re-snapshot before each Phase 8 apply (`↺ WORKING-TREE-DRIFT` operator); proceed without disturbing the changes. The 3-way merge will handle context. If the apply conflicts with concurrent changes, surface to the user — don't auto-resolve.

Cross-link to [stash-janitor's ANTI-PATTERNS.md A8](../../git-stash-janitor/references/ANTI-PATTERNS.md#a8-stash-revert-or-overwrite-changes-from-concurrent-agents).

**Worked example:** an agent saw `Cargo.lock` modified during Phase 8 and ran `git checkout -- Cargo.lock` to "clean up before applying". Result: lost a teammate's `cargo update --package serde` which had been in flight for 20 minutes. The teammate's CI run had already kicked off and now produced inconsistent results. Always treat the change as if you made it.

---

## W13. Pushing the rationalization branch on the user's behalf

**The mistake:**
```bash
git push origin branch-rationalization-2026-05-07            # WRONG — user's call
git push -u origin branch-rationalization-2026-05-07         # WRONG (and -u sets upstream)
```

**Why it's wrong:** Like the documentation-website skill and the stash-janitor skill, deployment is the user's call. The skill stops at producing the rationalization branch locally. Reasons the user owns the push:
- They may want to inspect the commits first.
- They may want to rebase onto a different base.
- They may want to open a PR with custom reviewers.
- They may have policies about what gets pushed when (CI cost, branch-protection rules, release windows).

**Why:** SKILL.md Axiom 15 (remote operations are out of scope by default) and the SKILL.md "What This Skill Produces" list ("Pushes the rationalization branch — that's the user's call").

**Correct approach:** `handoff_report.md` prints the suggested command verbatim and stops:

```
Recommended push (run this yourself):

    git push -u origin branch-rationalization-2026-05-07
```

The skill records that command in the handoff report. It does not execute it. Cross-link to [stash-janitor's ANTI-PATTERNS.md A6](../../git-stash-janitor/references/ANTI-PATTERNS.md#a6-push-the-recovery-branch-on-the-users-behalf).

---

## W14. Bypassing pre-commit hooks (`--no-verify`)

**The mistake:**
```bash
git commit --no-verify -m "..."                              # WRONG
git -c hook.pre-commit.skip=true commit -m "..."             # WRONGER
```

**Why it's wrong:** The user's hooks are the project's quality gates. Bypassing them propagates exactly the kind of bugs the rest of the skill is trying to prevent.

**Why:** AGENTS.md general practice (the project bans `--no-verify` skips); SKILL.md "Polish Bar" dimension "Per-apply gates"; Axiom 13.

**Correct approach:** if a hook fails, surface the failure to the user. Either:
- Fix the underlying issue (typecheck error, lint error, format error). Re-stage. Create a NEW commit (not `--amend`, per the standard hook-failure protocol).
- Surface the conflict between the recovered content and the project's quality bar to the user.

If the user explicitly authorizes a `--no-verify` commit (rare), record the authorization text in `cleanup_authorization.txt` (or an analogous file for that phase). Cross-link to [stash-janitor's ANTI-PATTERNS.md A7](../../git-stash-janitor/references/ANTI-PATTERNS.md#a7-bypass-pre-commit-hooks).

**Worked example:** Phase 8 cherry-picked a keeper onto the rationalization branch. The repo's pre-commit hook ran `cargo fmt --check` and failed because the keeper's formatting predates a `rustfmt.toml` change. The right path: re-run `cargo fmt`, re-stage, commit again. The wrong path: `--no-verify`, which would have left the rationalization branch in a state where CI would later fail with a confusing "fmt diff" comment.

---

## W15. Auto-deleting a branch with `[gone]` upstream tracking

**The mistake:**
```bash
git branch -vv | grep ': gone]' | awk '{print $1}' \
  | xargs git branch -D                                       # WRONG
```

**Why it's wrong:** A branch with `[gone]` upstream tracking means the remote tracking ref no longer exists — the *upstream branch* was deleted on the remote. It does NOT mean the local branch's commits are gone. The local branch may have:
- Unique commits the upstream never saw (work-in-progress that was never pushed).
- Commits that were squash-merged onto canonical (recoverable signal — but verify with `git cherry -v`, not `[gone]`).
- A genuinely-merged-and-cleaned-up history (then it's fine to delete, but only after triage confirms).

`[gone]` is a **hint**, not a verdict. Auto-deleting on `[gone]` discards local work that wasn't pushed.

**Why:** SKILL.md Failure Modes table — "A branch with `[gone]` upstream tracking has unique commits."

**Correct approach:** `[gone]`-tracked branches are flagged in `branches.tsv:upstream_status` and triaged through the normal Phase 5 flow. The triage rubric examines:
- Does the branch have unique commits (`git log <branch> ^<canonical>` returns ≥1 commits)?
- Is its content already on canonical (`git cherry -v <canonical> <branch>` shows all `-`)?

The verdict comes from those checks, not from `[gone]`.

**Worked example:** a user ran `git branch -vv | grep gone | xargs git branch -D` after they thought they had pushed everything. They lost a 4-commit feature branch that had two unpushed local commits added the previous evening. `[gone]` was true (the original PR branch had been deleted after merge), but the unpushed commits were genuinely novel. Recovery required reflog within the gc window. The skill's triage flow would have classified the branch as `partially-novel` (the squash-merged commits = `superseded`, the unpushed commits = `novel-and-accretive`).

---

## W16. Force-removing a worktree without archiving its dirty state

**The mistake:**
```bash
git worktree remove --force /data/projects/foo--wt-3         # WRONG without archive
```

**Why it's wrong:** `--force` overrides the dirty-state safety check. Any uncommitted changes in the worktree are lost. The skill's recovery story (every removal is reversible) breaks unless the dirty state was captured *before* the force-removal.

**Why:** SKILL.md Axiom 11; Axiom 4 (coherence of all five reversibility layers).

**Correct approach:** Phase 3 captures `<bundle>/worktrees/<sanitized-path>/{staged.diff, unstaged.diff, .untracked.list, untracked.tar.gz, status.txt, meta.txt}` for **every** worktree, dirty or clean. Phase 10's removal:

```bash
# Per-worktree, in order:
# 1. Verify the dirty state is in the bundle.
[ -f "$BUNDLE/worktrees/<sanitized>/status.txt" ] || halt

# 2. Try clean removal first.
if git worktree remove "/data/projects/foo--wt-3"; then
  echo "removed: /data/projects/foo--wt-3 (clean)"
elif [[ "$verdict" == "force-with-user-ok" ]]; then
  # Verbatim authorization required for --force.
  git worktree remove --force "/data/projects/foo--wt-3"
  echo "removed: /data/projects/foo--wt-3 (forced; dirty state in bundle)"
else
  echo "REFUSED: /data/projects/foo--wt-3 is dirty; force not authorized; halting"
  exit 1
fi
```

**Worked example:** an agent ran `--force` on every worktree in a 47-worktree cleanup script. 12 of them had uncommitted defensive changes that the user had been planning to harvest the next day. The bundle had captured them, so recovery worked, but the "force without thinking about it" habit is exactly what the skill is designed to prevent. With Phase 3's bundle in place AND the per-worktree verbatim authorization, the force-removals would have been individually surfaced and the user would have had a chance to harvest first.

---

## W17. Removing the currently-active worktree (the user's CWD) from inside

**The mistake:**
```bash
# In the active worktree:
cd /data/projects/foo--wt-active
git worktree remove .                                        # WRONG — git refuses
git worktree remove "$PWD"                                   # WRONG — same thing
```

**Why it's wrong:** Git refuses to remove the currently-active worktree. Trying anyway produces "fatal: '.' is the main working tree" or "fatal: '<path>' is the working tree of HEAD" errors. The skill enforces this independently to avoid the failed attempt.

**Why:** SKILL.md Axiom 11 — "The currently-active worktree (the user's CWD) is NEVER removed by the skill; the user removes that one themselves from a different working directory after the run completes."

**Correct approach:**
- The active worktree is auto-protected (`protected.tsv:active=true`).
- The handoff report explicitly tells the user how to remove it after they're done with the rationalization branch:

```
The currently-active worktree (/data/projects/foo--wt-active) is NOT being removed
by this skill — git won't let it be removed from inside, and we don't want to.

To remove it yourself, switch to a different directory first:

    cd /data/projects/foo
    git worktree remove /data/projects/foo--wt-active
```

**Worked example:** an agent ran from inside `/data/projects/foo--wt-7` and tried to include that path in the cleanup list. Git refused with "fatal: '/data/projects/foo--wt-7' is the working tree of HEAD". The skill should never have generated that cleanup-list entry in the first place — Phase 4's protection logic auto-protects the active worktree.

---

## W18. Misapplying stash-janitor's "format-patch is wrong" rule to branches

**The mistake:** "I came from stash-janitor; I know `git format-patch -1 stash@{N}` is wrong as a recovery diff. So `git format-patch <merge-base>..<branch>` is also wrong, right?"

**Why it's wrong:** **The rule does NOT generalize.** Stashes are merge commits with weird parent semantics; their `format-patch` output is unreliable. Branches are normal commit chains; `git format-patch <merge-base>..<branch>` produces a clean, ordered, reproducible patch series that fully captures every commit.

The bundle's `branches/<slug>/format-patch/*.patch` files are part of the recovery story for branches and have **no analogue** for stashes (where only `git stash show -p --binary` works).

**Why:** SKILL.md Axiom 7 — "`git format-patch` IS valid for branches; it is NOT for stashes. … If you came from git-stash-janitor, do not generalize the 'format-patch is wrong' rule."

**Correct approach:** the bundle includes BOTH:
- `branches/<slug>/diff-vs-merge-base.diff` — the unified diff (works regardless of intermediate commits)
- `branches/<slug>/format-patch/*.patch` — the per-commit patch series (preserves commit messages, authors, dates)

For recovery, prefer `git am <bundle>/branches/<slug>/format-patch/*.patch` to preserve commit history; fall back to `git apply <bundle>/branches/<slug>/diff-vs-merge-base.diff` if the patches don't apply cleanly.

The bundle's `README.md` cross-links **both ways** to the stash-janitor convention so future readers don't reach the wrong conclusion. Cross-link to [FAILURE-MODES.md F1](FAILURE-MODES.md#f1-format-patch-is-valid-for-branches-not-for-stashes), and (the inverse direction) [stash-janitor's FAILURE-MODES.md F1](../../git-stash-janitor/references/FAILURE-MODES.md#f1-git-format-patch--1-stashn-is-not-the-stash-recovery-diff).

**Worked example:** an agent fresh from a stash-janitor run tried to be "safe" and skipped format-patch generation in the branch bundle. Recovery later required cherry-picking 47 commits from `agent-cleanup-pass-3`; without the format-patch series, every cherry-pick had to be done individually with `git diff <merge-base>..<branch>` filtered per commit — much harder than `git am 0001-...patch 0002-...patch …`. The format-patch series exists for a reason for branches.

---

## W19. Vague authorization for destructive cleanup

**The mistake:**
```
> Should I proceed with cleanup?
> User: yes go ahead
[skill removes 47 worktrees and deletes 173 branches]
```

**Why it's wrong:** "yes go ahead" is too vague to count as the AGENTS.md "Mandatory explicit plan" authorization. The user might not have read the plan. There's no record of *what* they authorized.

**Why:** SKILL.md Axiom 14 — "Authorization is per-plan, verbatim, recorded."

**Correct approach:** the `⚠ CONFIRM` operator's prompt module requires the user to paste a specific phrase that includes a literal command from the plan. The verbatim text is recorded in `cleanup_authorization.txt` with a UTC timestamp. Without that file, the action did not happen.

```
Please paste this verbatim to proceed:

    yes I understand and want to remove 47 worktrees and delete 173 branches per the plan above
```

If the user types something different, re-ask. If the user objects ("just trust me"), explain that the verbatim authorization is per AGENTS.md policy and is the only thing that gives them a paper trail of what they authorized.

Cross-link to [stash-janitor's ANTI-PATTERNS.md A20](../../git-stash-janitor/references/ANTI-PATTERNS.md#a20-authorize-destructive-cleanup-with-a-vague-phrase).

---

## W20. Letting workspace artifacts leak into commits

**The mistake:** running on a repo where `.worktree_branch_rationalization_workspace/` ends up staged or committed as part of recovered keeper commits.

**Why it's wrong:** The workspace contains run artifacts (`triage.tsv`, `apply_log.tsv`, `harmonization_plan.md`, `bundle_path.txt`) that shouldn't be committed. If they end up in `git add -A` during Phase 8 commits, they pollute the rationalization branch.

**Why:** general project hygiene; AGENTS.md's "Mandatory explicit plan" implicitly requires that what's committed is what was authorized.

**Correct approach:** every script that stages or audits working-tree state explicitly excludes `.worktree_branch_rationalization_workspace/` via pathspecs. Do not auto-edit `.git/info/exclude`; that mutates `.git/` and contradicts the skill's kernel. If a persistent local ignore is desired, ask the user first and add one idempotent line only after approval.

Cross-link to [stash-janitor's ANTI-PATTERNS.md A17](../../git-stash-janitor/references/ANTI-PATTERNS.md#a17-let-workspace-artifacts-leak-into-commits).

---

## W21. Auto-deleting the bundle after a successful run

**The mistake:**
```bash
rm -rf "$BUNDLE_PATH"                                        # WRONG
```

**Why it's wrong:**
- DCG blocks `rm -rf` per AGENTS.md. Don't fight DCG.
- Even if DCG didn't block, the bundle is the user's safety net for the *next* week of regret. The user should manage bundle lifecycle.
- Per Axiom 18, "Drop the bundle only at the user's pace."

**Why:** SKILL.md Axiom 18 — "DCG correctly blocks `rm -rf` on the bundle. The skill is *designed* never to need this command. Bundle deletion is a manual decision after the user is sure nothing was lost (typically 1–4 weeks)."

**Correct approach:** leave the bundle in place; document its location in the handoff report; let the user decide when to remove it. Cross-link to [stash-janitor's ANTI-PATTERNS.md A10](../../git-stash-janitor/references/ANTI-PATTERNS.md#a10-rm--rf-the-bundle-after-a-successful-run).

---

## Cross-links

- [stash-janitor's ANTI-PATTERNS.md](../../git-stash-janitor/references/ANTI-PATTERNS.md) — the sibling catalogue. Many disciplines (verbatim authorization, never-deleting-the-bundle, never-bypassing-hooks, no-script-based-changes, never-stashing-other-agents-work) are inherited verbatim.
- [HARMONIZATION.md](HARMONIZATION.md) — the methodology behind W4 (the harmonization plan is non-skippable when files collide).
- [FAILURE-MODES.md](FAILURE-MODES.md) — diagnostic playbook for every wrong-action symptom listed here.
- [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md) — how to undo most of the above wrong actions if they happened anyway.
- [SKILL.md](../SKILL.md) — the 19-axiom kernel that grounds every entry.
