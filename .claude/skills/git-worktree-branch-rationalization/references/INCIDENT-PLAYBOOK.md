# Incident Playbook — When Things Go Wrong Mid-Run

The playbook for the most common (and a few uncommon) incidents during a branch-and-worktree rationalization run. Each entry: **symptoms → immediate triage → recovery → prevention**.

Adapted from [git-stash-janitor's INCIDENT-PLAYBOOK.md](../../git-stash-janitor/references/INCIDENT-PLAYBOOK.md), with branch-and-worktree-specific incidents added (concurrent worktree modification, force-push detection, submodule init failure, LFS object missing, beads lock, agent-mail server unreachable, `git branch -d` refusal, etc.).

Cross-link to [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md) for byte-for-byte recovery of any removed/deleted entity. The recipes there cover R1–R15; the incidents here are the *triage* paths that lead to invoking those recipes.

---

## I1 — Phase 3 byte-equality OR bundle-round-trip mismatch

**Symptoms:**
```
verify-bundle.sh: MISMATCH: branch agent-cc-12-feat-parser
  live=def456abc... backup=789xyzdef...
*** GATE FAILURE ***
```

OR:

```
verify-bundle.sh: BUNDLE HEAD MISMATCH
  bundle list-heads enumerates: refs/branch-rationalization-backup/agent-cc-12, ...
  live backup namespace has:    refs/branch-rationalization-backup/agent-cc-12, agent-cc-13, ...
  (agent-cc-13 is missing from object-bundle.pack)
```

**Immediate triage:** HALT. Do NOT proceed to Phase 4 or beyond.

> **Why:** Per [SKILL.md Axiom 3](../SKILL.md#the-rationalization-kernel-universal-axioms): "An incorrect verdict is recoverable; an unrecorded removal is not." A bundle mismatch means the safety net is broken; the run is unsafe.

**Diagnosis:** the bundle's backup ref doesn't match the current `git rev-parse refs/heads/<name>` OR the object bundle is missing entries. Possible causes:
- A concurrent agent advanced a branch between Phase 2 (inventory) and Phase 3 (bundle creation)
- The backup ref was created from a different SHA (race condition between `git update-ref` calls)
- `git bundle create` stdin order is non-deterministic; the bundle missed a ref
- Filesystem corruption (rare; check `dmesg` for I/O errors)

**Recovery:**
1. Re-run Phase 2 (inventory) to capture current state. The `*.tsv` files get a `.prev` suffix and are replaced.
2. Re-run Phase 3 with `BUNDLE_OVERRIDE=<basename>-branch-worktree-archive-<DATE>-2/` so the mismatched bundle stays intact for forensics.
3. Re-run `verify-bundle.sh` until it passes.
4. If the same mismatch repeats: a concurrent agent is actively modifying refs. Increase the Mail reservation TTL on `.git/refs/heads/**` and ask the user to pause concurrent agents during Phase 2-3.

**Prevention:** Phase 0 advisory file reservation on `.git/refs/heads/**` and `.git/worktrees/**`. If concurrent agents are common, run with `exclusive=false, ttl_seconds=14400` reservations during Phases 2–3 (they're advisory; don't actually block).

---

## I2 — Concurrent agent modifies a worktree's working tree mid-Phase-8

**Symptoms:** during Phase 8, a `↺ WORKING-TREE-DRIFT` snapshot detects changes in a worktree the keeper-applier wasn't expecting:

```
↺ DRIFT DETECTED in /data/projects/foo-wt-cc-12 (since pre-apply-row-23):
  M src/parser.rs
  ?? new_test.rs
```

**Immediate triage:**
- Per [Axiom 12](../SKILL.md#the-rationalization-kernel-universal-axioms) and AGENTS.md "Note for Codex/GPT-5.5": treat the drift as if you made it. **Never** stash, revert, or overwrite.
- Capture the drift in `apply_log.tsv:pre_apply_drift`.
- Decide whether the apply that's about to run is affected.

**Diagnosis:** another agent is actively working in a worktree the rationalization run is also triaging. This is **normal** post-swarm cleanup. The user's hard-won lesson per [KEY-INSIGHTS.md §I-3](KEY-INSIGHTS.md): concurrent-agent drift is normal; the skill is drift-tolerant by design.

**Recovery:**
1. Re-snapshot the worktree's full state.
2. If the worktree is the source for the current row (`worktree-dirty-state` strategy): re-capture the dirty state into `<bundle>/worktrees/<wt_slug>-<timestamp>/` (a NEW subdirectory, not overwriting). Update the apply to reference the new captures.
3. If the worktree is unrelated to the current row: log the drift, continue.
4. **Never** force the apply through. **Never** disturb the drift.

**Prevention:** the After-Swarm Mode (per [KICKOFF-PROMPTS.md § After-Swarm Mode](KICKOFF-PROMPTS.md#after-swarm-mode-specialized-variant)) bakes drift expectation into every gate. Use it when concurrent agents are active.

---

## I3 — Cherry-pick conflict the user can't resolve

**Symptoms:** Phase 8 row triggers a cherry-pick; conflict markers appear; the user reads the proposed resolution and says "I don't know how to resolve this".

**Immediate triage:**
- Don't force the apply.
- Don't `git cherry-pick --skip` without user OK.
- Capture the conflict context.

**Diagnosis:** the branch's content can't be cleanly applied on top of the rationalization branch's current state. Common causes:
- A prior keeper changed the files this branch touches (RE-FINGERPRINT should have caught this; if it didn't, check whether the prior keeper's changes are subtle)
- The branch was authored against a much older canonical
- The branch and a prior keeper independently introduced incompatible refactors

**Recovery:**
1. Run `git cherry-pick --abort` to clean up the working tree.
2. Write the conflict context to `{WORKSPACE}/conflicts/branch_<slug>.context.md` so it survives compaction. Include:
   - The branch's full diff vs. its merge-base
   - The current state of the affected files on the rationalization branch
   - The conflict markers verbatim
   - A hypothesis for the conflict's root cause
3. Surface to user with three options:
   - **Skip:** mark `conflict-skipped`, continue. The branch's content remains in the bundle and backup ref; recover later if needed.
   - **Defer to Phase 7 harmonization:** if the file is touched by another branch in the triage, the conflict is actually a harmonization candidate — re-run Phase 7 for that file.
   - **Manual resolution by user:** the user resolves via the Edit tool or by inspecting on their own; the keeper-applier waits.
4. Per AGENTS.md "No Script-Based Changes": **never** use sed/awk/regex to "fix up" the conflict. Edit tool only.

**Prevention:** Phase 7 should catch most multi-branch collisions before they reach Phase 8. If a conflict appears in Phase 8 anyway, it's evidence Phase 7's colliding-file detection missed something — surface to the user as feedback for the next run.

---

## I4 — Pre-commit hook fails on a recovered commit

**Symptoms:** Phase 8 apply succeeds; staging succeeds; the commit fails:

```
husky > pre-commit (node v22.x)
✖ npm run lint:staged
  /src/parser.rs:152:8 — `parse_v3` is unused
*** PRE-COMMIT FAILED ***
```

**Immediate triage:** the pre-commit hook is the project's gate; per AGENTS.md, do not bypass with `--no-verify`. Per [ANTI-PATTERNS.md W14](ANTI-PATTERNS.md#w14-bypassing-pre-commit-hooks---no-verify): "If a hook fails, fix the underlying issue; if you can't, surface to user."

**Diagnosis:** the recovered code has an issue the project's hook catches but the per-apply gate command (`{lint_command}` in `project_profile.json`) didn't catch. Possible causes:
- Hook runs different / stricter checks than the gate command (e.g., `lint-staged` only checks staged files; `cargo clippy` runs project-wide)
- Hook runs additional formatters (e.g., prettier) that the gate command skipped
- Hook has a project-specific check (e.g., "no console.log" / "no TODO comments") that the gate doesn't run

**Recovery:**
1. Read the hook output. Identify the specific failure.
2. If it's a fixable issue (formatting, an unused import): use the Edit tool to fix the issue in the working tree, re-stage the affected files, retry the commit. Append to `apply_log.tsv:gates_status="hook-fixed-<reason>"`.
3. If the issue is in code from the source branch (not introduced by the apply): surface to user. Options:
   - Fix the issue and amend the commit (the source branch's content lives in the backup ref; amending is local to the rationalization branch)
   - Skip the row; mark `conflict-skipped`
4. **Never** bypass the hook with `--no-verify`. The user's gates exist for a reason.

**Prevention:** include the project's pre-commit hook commands in the per-apply gate command list (read `.husky/pre-commit`, `.lefthook.yml`, etc. during Phase 1 profiling). Run them BEFORE staging so failures are caught earlier.

---

## I5 — Rationalization branch deleted out-of-band mid-run

**Symptoms:** during Phase 8, a `git rev-parse refs/heads/branch-rationalization-2026-05-07` returns "unknown revision":

```
fatal: ambiguous argument 'refs/heads/branch-rationalization-2026-05-07':
unknown revision or path not in the working tree
```

**Immediate triage:** HALT Phase 8 immediately. Do NOT continue.

**Diagnosis:** the rationalization branch was deleted by something outside the skill — most likely:
- A concurrent agent ran a cleanup script that mass-deleted branches
- The user accidentally ran `git branch -D` on it
- A `git push --force` on the upstream tracking ref triggered a local prune

**Recovery:**
1. The applied keepers' commits are still in the reflog (until gc) AND in the local `.git/objects/` tree. The branch ref is just a label.
2. Recover the branch ref:
   ```
   # If apply_log.tsv records the latest applied SHA, use it directly
   latest_sha=$(awk -F'\t' 'NR > 1 && $3 != "(folded-into "*  {print $3}' apply_log.tsv | tail -1)
   git update-ref refs/heads/branch-rationalization-2026-05-07 "$latest_sha"
   ```
3. If `apply_log.tsv` doesn't have the latest SHA (e.g., the run was interrupted mid-apply): use `git reflog --all | grep branch-rationalization` to find the most recent tip.
4. Resume Phase 8 from the next row in `triage.tsv`.
5. Cross-link to [RECOVERY-RECIPES.md R7](RECOVERY-RECIPES.md#r7-the-rationalization-branch-was-deleted-before-i-pushed) for the full recipe.

**Prevention:** Phase 0 reserves `.git/refs/heads/**` advisory; the orchestrator should also detect the rationalization branch's tip every N applies and re-record in `apply_log.tsv`. Ask the user before Phase 0 whether any cleanup automation runs in the repo.

---

## I6 — Canonical's tip moved (force-push detected) mid-run

**Symptoms:** during Phase 8, `git rev-parse {CANONICAL}` returns a different SHA than at Phase 0. Either:

```
Phase 0 recorded canonical = abc123def
Phase 8 sees canonical    = 999fedcba   (different)
```

OR the merge-base between canonical and the rationalization branch suddenly shows zero commits in common (history was rewritten upstream).

**Immediate triage:** HALT. Do NOT continue Phase 8 or Phase 9.

**Diagnosis:** someone or something pushed to canonical with `--force` (or its equivalent) and the local canonical was updated. Possible causes:
- Upstream maintainer rebased canonical (rare on `main`; common on feature-branch flows)
- A CI process mis-fired and force-updated
- Another developer pushed `--force-with-lease` and won the race

**Recovery:**
1. Inspect the new canonical: `git log --oneline {CANONICAL}` vs. the recorded Phase 0 SHA. Has the branch been rewritten or just advanced?
   - **Just advanced** (new commits on top of old): the rationalization branch is still rebaseable onto the new canonical. Pause, run `git rebase {CANONICAL}` on the rationalization branch, re-run Phase 9 fresh-eyes from scratch on the rebased state, then continue.
   - **Rewritten** (commits replaced): the harmonization plan may be invalidated (the variants on the rationalization branch may now conflict with the new canonical's content). Surface to user; the user decides whether to:
     - Restart the run from Phase 1 against the new canonical (the bundle is reusable; the triage results may flip)
     - Pin to the old canonical SHA (`git checkout {old-sha}`) and proceed
     - Abort; the upstream rewrite is too disruptive
2. Update `project_profile.json:canonical_branch_sha_at_phase0` and the rationalization branch's record.
3. **Never** force-push the rationalization branch to "fix" the merge-base relationship. Per [Axiom 15](../SKILL.md#the-rationalization-kernel-universal-axioms): "Remote cleanup is out of scope by default."

**Prevention:** Phase 0 records canonical's SHA. Phase 8 re-checks before each apply. Phase 9 re-checks before round 1.

---

## I7 — Beads database lock OR agent-mail server unreachable

**Symptoms:**
- `br create` returns `database is locked`
- `agent_mail.send_message` returns connection refused / timeout / 503

**Immediate triage:** retry with exponential backoff (3 attempts: 5s, 10s, 20s).

**Diagnosis:**
- Beads: another `br` process has the SQLite lock. Common when the agent swarm is busy.
- Mail: server restart, network blip, or rate limit.

**Recovery:**
- **Beads:** if still locked after 3 retries, skip beads-issue creation. Record `beads_skipped: true; reason: locked` in `handoff_report.md` and in the workspace. The run still succeeds. The handoff report is the audit trail; beads is a convenience layer.
- **Mail:** if server is unreachable, fall back to running without coordination. Reservations were advisory; concurrent agents can still drift, but the skill is drift-tolerant per Axiom 12. Record `mail_unavailable: true` in `handoff_report.md`. **Never** block the run on Mail availability.

**Prevention:** none — these are infrastructure issues outside the skill's control. Skipping is fine; both layers are advisory.

---

## I8 — Disk full mid-bundle-build

**Symptoms:** `build-bundle.sh` fails partway with:

```
write error: No space left on device
```

OR `tar -czf` for an `untracked.tar.gz` fails with the same error.

**Immediate triage:**
1. Stop the script.
2. The partial bundle has incomplete diffs/format-patch/meta files. Some branches/worktrees may have only partial captures.
3. **DCG would block `rm -rf` even of the partial bundle.** Do not fight DCG; design around it (per [KEY-INSIGHTS.md §I-9](KEY-INSIGHTS.md): "DCG blocks `rm -rf`. The skill is designed never to need it.").

**Diagnosis:** the bundle exceeded available disk space. Per Phase 0 sizing estimate:

```
W = worktree count
B = branch count
estimated_branches_size = B * 200 KB    # average per-branch diff + format-patch
estimated_worktrees_size = sum(per-worktree dirty state size, across all worktrees)
total_estimated = estimated_branches_size + estimated_worktrees_size
```

A 213-branch + 47-worktree run with moderate dirty state typically needs 200–500 MB. A run with heavy LFS objects in worktrees can exceed 5 GB.

**Recovery:**
1. **Free disk space** without `rm -rf`. Use the `/sbh` skill if available (it handles disk-pressure defense). If `/sbh` is unavailable: ask the user to manually free space — DCG-allowed deletes (specific, named files via `git restore`, `mv` to /tmp, etc.) are fine; mass `rm -rf` is not.
2. Verify the partial bundle: which branches/worktrees are complete? Check `index.tsv` against `branches/<slug>/diff-vs-merge-base.diff` presence.
3. Resume with `BUNDLE_OVERRIDE=<basename>-branch-worktree-archive-<DATE>-2/` to build a FRESH bundle while preserving the partial one (the partial one is forensic evidence).
4. After the new bundle verifies clean: surface the disk situation to user with the partial bundle's location; user decides whether to manually `mv` the partial bundle out of the project parent directory (DCG-allowed since it's not a script-based delete).
5. **Never** `BUNDLE_REBUILD_IN_PLACE_OK=1` without explicit user approval. The partial bundle is not authoritative; mixing partial and complete artifacts breaks the safety story.

**Prevention:** Phase 0 estimates bundle size:
```bash
W=$(git -C {PROJECT} worktree list --porcelain | grep -c '^worktree ')
B=$(git -C {PROJECT} branch | wc -l)
size_branches_kb=$(($B * 200))
echo "Estimated branches bundle size: $((size_branches_kb / 1024)) MB"
echo "Worktree dirty state size depends on per-worktree disk usage; check with du -sh on each."
```

If estimated > 1 GB OR available disk < 2x estimated, ask user to confirm disk has room before proceeding.

---

## I9 — UBS unavailable when project_profile.json said it was

**Symptoms:** Phase 8 per-apply gate runs `ubs <changed-files>`; the command returns:

```
ubs: command not found
```

OR:

```
ubs: ConfigError: cannot find .ubsignore
```

**Immediate triage:** the gate result depends on whether UBS was actually used in CI vs. inferred from a `.ubsignore` file presence.

**Diagnosis:**
- Profile detection said `ubs_available: true` because `.ubsignore` exists, but the binary isn't installed in the current PATH.
- The `.ubsignore` is leftover from a prior project state; UBS isn't actually used now.

**Recovery:**
1. Update `project_profile.json:ubs_available = false` for this run. Record `ubs_skipped_reason: "not in PATH"` in the gate output.
2. Continue Phase 8 without UBS. The other gates (test + typecheck + lint) are still active.
3. Surface to user post-Phase-9: "UBS was expected to run on every apply per the profile, but `ubs` is not in PATH. The run completed without UBS coverage. Install UBS and re-run Phase 9 if you want UBS coverage on the keeper commits."

**Prevention:** Phase 1 profiling actually invokes `command -v ubs` instead of just checking for `.ubsignore`. Same for any tool the gate depends on.

---

## I10 — Submodule init failure during Phase 8 apply

**Symptoms:** Phase 8 apply succeeds at the file level; the per-apply gate runs; the test command fails with:

```
fatal: No url found for submodule path 'vendor/lib-foo' in .gitmodules
```

OR:

```
error: submodule 'vendor/lib-foo' has uncommitted changes
```

**Immediate triage:** the rationalization branch's working tree has the submodule entry in `.gitmodules` but the submodule isn't initialized.

**Diagnosis:**
- The source branch added a new submodule (or modified an existing one's commit pin), but `git cherry-pick` only updates the submodule pointer; it doesn't run `git submodule update --init`.
- The current rationalization branch's working tree may have a different submodule init state than the source branch had.

**Recovery:**
1. Initialize the submodule:
   ```
   git submodule update --init --recursive vendor/lib-foo
   ```
2. Re-run the gate command.
3. If the submodule URL is unreachable (network issue, repo moved, auth required): surface to user with the .gitmodules entry; user decides whether to fix the URL, skip this row, or remove the submodule from the synthesis.
4. If the submodule has uncommitted changes (locally): per [Axiom 12](../SKILL.md#the-rationalization-kernel-universal-axioms), don't disturb. Surface to user.

**Prevention:** Phase 1 profiling detects `submodules` in `project_profile.json`. Phase 2 inventory captures per-worktree submodule init state. Phase 8 keeper-applier checks submodule init state before each apply that touches `.gitmodules` and runs `git submodule update --init` proactively.

---

## I11 — LFS object missing mid-cherry-pick

**Symptoms:** Phase 8 apply attempts to cherry-pick a commit; the git operation succeeds; checkout of the file fails:

```
Downloading large file from LFS:  fixtures/big-corpus.tar.gz
fatal: Object lfs:hash:abc123... does not exist
```

OR the file checkouts as a pointer file (containing the LFS metadata only).

**Immediate triage:** the LFS object is referenced but not available locally and can't be fetched from the remote (auth, network, or the object was never pushed).

**Diagnosis:**
- The source branch had the LFS object locally; the rationalization branch's clone is from a different remote that doesn't have it.
- The object was never pushed to the LFS server.
- LFS auth changed (token expired).

**Recovery:**
1. `git lfs fetch origin <source-branch-name>` to attempt to fetch the object from the source branch's remote ref.
2. If unsuccessful: `git lfs fetch <bundle-url>` — but the bundle stores per-branch diffs, not LFS objects directly. Per [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md), LFS objects are referenced by hash; the actual binary lives at LFS server.
3. If the LFS object is irrecoverable: surface to user. Options:
   - Skip this row (`conflict-skipped`); the keeper isn't applied; the LFS reference doesn't land
   - Drop the LFS file from the synthesis (`git rm` it from the working tree before commit); the rationalization branch lands without that file
   - Wait until LFS auth / network is fixed and resume
4. Document in `apply_log.tsv:gates_status="lfs-missing-skipped"`.

**Prevention:** Phase 1 profiling detects `lfs_used` in `project_profile.json`. Phase 0 confirms LFS auth works (`git lfs ls-files | head -1`). If LFS auth is broken, surface to user before Phase 3.

---

## I12 — User authorizes Phase 10 with a phrase that doesn't include the literal commands

**Symptoms:** user types "yes" or "go ahead" instead of the verbatim phrase that quotes a literal command from the cleanup plan.

**Immediate triage:** authorization isn't specific enough per AGENTS.md "Mandatory explicit plan".

**Diagnosis:** the user is being terse, often because they trust the agent and want to move fast. Per [Axiom 14](../SKILL.md#the-rationalization-kernel-universal-axioms): "Authorization is per-plan, verbatim, recorded. If that file doesn't exist, the action did not happen."

**Recovery:**
1. REFUSE the cleanup. Re-ask with the specific template:
   ```
   To authorize, please paste this verbatim (or a phrase that quotes the
   literal commands):
     yes I understand and want to remove 44 worktrees and delete 181 branches
     per the plan above
   ```
2. If the user objects ("just trust me"), explain it's per AGENTS.md and the audit trail in `cleanup_authorization.txt` is the only thing that gives them recourse if regret happens.
3. If the user STILL objects: do not proceed. The user can run the cleanup commands manually if they prefer (the bundle and refs are intact for them; the cleanup plan is in `triage_decision.md`).

**Prevention:** the verbatim authorization template includes counts AND the literal command form. Users who haven't seen the pattern often default to "yes"; be patient and re-ask once.

---

## I13 — Phase 9 fresh-eyes never converges

**Symptoms:** rounds 1, 2, 3 all find substantive issues; the same finding repeats across rounds.

**Immediate triage:** after 3 rounds with the same finding, escalate.

**Diagnosis:** the agent isn't actually fixing the finding (just reporting it), OR the finding is unfixable (project rule the recovered code can't satisfy).

**Recovery:**
1. Surface the repeated finding to the user with: the finding text, the file:line, the proposed fixes from each round (if any), why each fix didn't take.
2. The user decides:
   - Adapt the recovered code to satisfy the rule (Edit tool)
   - Accept the warning (e.g., add `#[allow(...)]` or equivalent for that specific file/line)
   - Drop the keeper (revert the offending commit; mark `rolled-back-after-fresh-eyes` in `apply_log.tsv`)
3. Document the resolution in `fresh_eyes_log.md`.

**Prevention:** Phase 8 per-apply gates should catch most issues before Phase 9. If Phase 9 finds issues Phase 8 missed, that's evidence the gate command list in `project_profile.json` is incomplete — surface to user as feedback for next run.

---

## I14 — Cleanup runs on a worktree/branch that's already been removed externally

**Symptoms:** Phase 10 mid-execution; `drop-retire-confirmed.sh` reports:

```
REFUSED: worktree /data/projects/foo-wt-cc-12 not found
  (was in worktrees.tsv at Phase 2; gone now)
```

OR:

```
REFUSED: branch agent-cc-12-feat-parser does not exist
  (was in branches.tsv at Phase 2; gone now)
```

**Immediate triage:** HALT Phase 10. Do NOT proceed.

**Diagnosis:** a concurrent agent (or the user manually) removed/deleted the entry between Phase 2 inventory and Phase 10 execution. The cleanup plan is now stale.

**Recovery:**
1. Run `git worktree list --porcelain` and `git branch` to see current state.
2. Re-build `cleanup_plan.tsv` from the current state.
3. Re-authorize via `⚠ CONFIRM`. The original authorization is invalid (it covered a different plan).
4. The user re-types the verbatim authorization for the new plan.
5. Continue from the rebuilt plan.

**Prevention:** Phase 10 uses an exclusive Mail file reservation on `.git/refs/heads/**` and `.git/worktrees/**` during execution. The reservation should be acquired BEFORE building the plan, not before each removal/deletion.

---

## I15 — `git worktree remove` refuses because the worktree is dirty

**Symptoms:**
```
fatal: '/data/projects/foo-wt-cc-12' contains modified or untracked files,
use --force to delete it
```

**Immediate triage:** this is a feature, not a bug. Per [Axiom 11](../SKILL.md#the-rationalization-kernel-universal-axioms): "`git worktree remove` refuses on dirty worktrees — that refusal is a feature."

**Diagnosis:** the worktree has uncommitted work (staged, unstaged, or untracked).

**Recovery:**
1. Verify the dirty state is captured in the bundle:
   ```
   ls {BUNDLE}/worktrees/<wt_slug>/
   # Should contain: meta.txt, status.txt, staged.diff, unstaged.diff, [untracked.tar.gz]
   ```
2. If captured: surface to user.
   ```
   Worktree /data/projects/foo-wt-cc-12 is dirty:
     - 3 tracked files modified
     - 1 staged change
     - 2 untracked files
   The dirty state is captured in {BUNDLE}/worktrees/<wt_slug>/ (verified).
   To force-remove (the dirty state remains in the bundle):
     git worktree remove --force /data/projects/foo-wt-cc-12
   Or skip this worktree: it stays in the worktree list.
   ```
3. Wait for explicit user OK that the dirty state may be lost (it's still in the bundle).
4. **Never** `--force` without explicit user OK.
5. **Never** `rm -rf <worktree-path>` (DCG-blocked AND doesn't prune `.git/worktrees/<id>/`).

**Prevention:** Phase 10's verbatim authorization request explicitly flags every dirty worktree with its dirty-state summary. The user sees the magnitude of "what gets lost" before authorizing.

---

## I16 — `git branch -d` refuses because the branch isn't fully merged

**Symptoms:**
```
error: The branch 'agent-cc-77-feature' is not fully merged.
If you are sure you want to delete it, run 'git branch -D agent-cc-77-feature'.
```

**Immediate triage:** this is a feature, not a bug. Per [Axiom 8](../SKILL.md#the-rationalization-kernel-universal-axioms): "`git branch -d` over `git branch -D` whenever possible. Lowercase `-d` refuses to delete branches that are not fully merged into the current `HEAD`."

**Diagnosis:** the branch has commits that aren't on the current HEAD (the rationalization branch's tip). This usually means:
- The branch's verdict was `garbage` or `novel-but-stale-discardable` and was correctly classified as such — it's NOT applied to the rationalization branch
- The branch's content was supposed to be applied but the apply was skipped (`conflict-skipped`)
- The branch's content was applied but then rolled back

**Recovery:**
1. Re-check the verdict in `triage.tsv`. If `garbage` or `novel-but-stale-discardable` and the user explicitly OK'd dropping unmerged content: use `git branch -D <name>`.
2. If `applied-keeper` but the apply was skipped: this branch should NOT be deleted yet — it has unmerged content that the user might want. Surface to user.
3. If the user explicitly authorizes `-D` for an unmerged branch: record the override in `cleanup_log.tsv:override="user-explicit-D"`. The backup ref still exists; recovery is possible.

**Prevention:** the cleanup plan in Phase 10 separates `-d` (default for applied-keepers and superseded) from `-D` (only for garbage and user-acknowledged-discardable). Mixing them is forbidden by the script.

---

## I17 — User cancels the session mid-Phase 8

**Symptoms:** user types "stop" / "wait" / closes the session while keepers are being applied.

**Immediate triage:**
1. Stop applying the next keeper.
2. The current applied state is what's on the rationalization branch (committed already).
3. Save state: `apply_log.tsv` records what's done; future resume picks up from there.

**Diagnosis:** user changed their mind, hit a deadline, or saw something concerning.

**Recovery:**
- The user can re-run later; resume mode picks up where it left off (per [KICKOFF-PROMPTS.md § Resume Mode](KICKOFF-PROMPTS.md#resume-mode-interrupted-prior-run)).
- Or the user can explicitly authorize deleting the rationalization branch ref to discard the run entirely. The bundle and backup refs survive.

**Prevention:** none — user agency is the priority. The skill is resumable by design.

---

## I18 — Phase 1 project-profiler returns inconsistent results across runs

**Symptoms:** `canonical_branch` differs from a prior run's value (e.g., was `master`, now `main`).

**Immediate triage:** ask the user. Don't proceed with potentially-wrong canonical.

**Diagnosis:** the repo's canonical branch was renamed between runs (common transition: `master` → `main`).

**Recovery:**
1. Confirm the current canonical with the user verbatim.
2. Update `project_profile.json` to reflect the new value.
3. If a prior run's rationalization branch was based on the old canonical:
   - Rebase it onto the new canonical: `git rebase {NEW_CANONICAL} branch-rationalization-<DATE>`
   - OR cut a new rationalization branch from the new canonical and re-apply keepers
4. Re-run Phase 9 fresh-eyes from scratch on the rebased state.

**Prevention:** Phase 1 ALWAYS detects canonical fresh; no caching across runs (per [PHASES.md § Idempotence & Resumability](PHASES.md#idempotence--resumability)).

---

## I19 — Skill is invoked on a CI host

**Symptoms:** working dir is `/__w/<repo>/...` or `/home/runner/work/...`; worktree count or branch count is non-zero.

**Immediate triage:** Phase 0 detects via the working-dir prefix and refuses.

**Diagnosis:** CI host shouldn't have local worktrees or many local branches; their presence is evidence of something else wrong.

**Recovery:**
1. The user investigates why the CI host has accumulated worktrees/branches (broken hook, leftover from a debug session, CI cache misuse).
2. The skill does not run.

**Prevention:** documented in [WHEN-NOT-TO-USE.md](WHEN-NOT-TO-USE.md).

---

## I20 — General: agent makes a non-trivial decision unilaterally

**Symptoms:** any unauthorized destructive action — even one — that the agent took without explicit user approval. Examples:
- A `git branch -D` that wasn't in the cleanup plan
- A `git worktree remove --force` without explicit user OK on the dirty state
- A push that the skill is supposed to never do
- A bypass of pre-commit hooks via `--no-verify`
- A `git reset --hard` to "fix" a mid-apply state

**Immediate triage:** STOP THE RUN. This is the kernel-level invariant.

**Recovery:**
1. Surface what was done with full context (verbatim command + when + why).
2. Roll back if possible (per the operation):
   - For unauthorized branch deletion: `git branch <name> refs/branch-rationalization-backup/<slug>` per [RECOVERY-RECIPES.md R1](RECOVERY-RECIPES.md#r1-i-regret-deleting-a-branch).
   - For unauthorized worktree removal: per [RECOVERY-RECIPES.md R4](RECOVERY-RECIPES.md#r4-i-regret-removing-worktree-path).
   - For unauthorized push: surface; remote state changed; user decides.
3. Document the breach in `handoff_report.md` under a "Run integrity" section.
4. Don't continue until the user explicitly approves.

**Prevention:** every destructive action requires `⚠ CONFIRM`. Per AGENTS.md "Mandatory explicit plan", the verbatim authorization is non-negotiable.

This is the kernel-level invariant. If the agent ever finds itself "about to just do it", it should treat that impulse as a bug and surface instead.

---

## I21 — Force-push detected on a triaged branch (mid-run)

**Symptoms:** during Phase 5 or Phase 8, a triaged branch's `git rev-parse refs/heads/<name>` differs from the bundle's recorded SHA, AND `git rev-parse refs/branch-rationalization-backup/<slug>` matches the OLD SHA (so the bundle is consistent; only the live branch moved).

**Immediate triage:** the branch was force-pushed (or its upstream was, and the local was reset to track). The bundle's frozen SHA is the safe subject; the live SHA is the new state.

**Diagnosis:** common in agent-swarm aftermath where a swarm agent decides to rebase its branch.

**Recovery:**
1. The triage subject is the bundle's frozen SHA. The live branch's new commits are NOT in the bundle (they postdate Phase 3).
2. Surface to user: "branch X was force-pushed since Phase 3. The bundle has the pre-force-push SHA. The live branch has new content the bundle doesn't capture."
3. User decides:
   - **Re-bundle the branch:** add a new entry to the bundle with the live SHA (under a `<slug>-rerun` directory). Re-triage from the new content.
   - **Stick with the old SHA:** treat the branch as if the force-push didn't happen. The new content remains in the user's local but is not part of this run. (Recoverable from reflog later.)
   - **Skip:** mark the branch `triage-skipped-force-push-detected`. User addresses outside this run.
4. **Never** silently accept the force-push and re-fingerprint against the new SHA — the bundle's safety story would diverge from the live state.

**Prevention:** Phase 0 warning when reflog detects recent force-pushes (`git reflog --all | head -20 | grep "forced-update\|update by push"`).

---

## Cross-References

- Per-incident recovery recipes (R1–R15): [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md)
- Failure modes table (matches incidents to operator failures): [FAILURE-MODES.md](FAILURE-MODES.md)
- Anti-pattern catalogue (the things that lead to incidents): [ANTI-PATTERNS.md](ANTI-PATTERNS.md)
- Working-tree-state guidance for multi-worktree drift handling: [WORKTREE-STATE.md](WORKTREE-STATE.md)
- Bundle format that the recoveries depend on: [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md)
- The kernel axioms that incidents test: [SKILL.md § Kernel](../SKILL.md#the-rationalization-kernel-universal-axioms)
