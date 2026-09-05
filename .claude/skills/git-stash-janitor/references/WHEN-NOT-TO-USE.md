# When NOT to Use This Skill

This skill is overkill for some situations and inappropriate for others. Recognize them before invoking.

---

## NTU-1: Fewer than 5 stashes

**Symptom:** `git stash list | wc -l` returns 0–4.

**Why not:** the recovery-bundle infrastructure overhead doesn't pay off. A user with 3 stashes can `git stash list -v` and inspect them in 30 seconds.

**Better approach:**
```bash
git stash list -v   # human-readable, includes diff for each
# Or per-stash:
git stash show -p --binary stash@{N} | less
```

The skill can still be invoked on small repos, but Phase 0 should warn:

> You have 3 stashes. The skill's overhead (recovery bundle, fan-out triage)
> is calibrated for >10 stashes. For 3 stashes, manual inspection via
> `git stash list -v` is usually faster. Run anyway? (Default: no)

---

## NTU-2: Stash-as-clipboard workflow

**Symptom:** the user uses `git stash` as a copy-paste primitive between branches, repeatedly creating and applying short-lived stashes.

**Why not:** the workflow assumes stashes accumulate from neglect. If the user's workflow is to *intentionally* keep working stashes, triaging them out is destructive.

**Detection heuristic:** stash list ages skew young (median age < 1 day) AND the user creates new stashes during the run. If this pattern emerges:

> Your stash list looks like an active workflow — many recent stashes,
> short ages. Are you using stash as a clipboard between branches? If so,
> this skill will look like cleanup but might erase active work. Confirm
> you want to proceed.

---

## NTU-3: CI checkout

**Symptom:** the working directory is `/__w/<repo>/...` (GitHub Actions), `/cloudbuild/...` (Google Cloud Build), or similar CI paths AND has stashes.

**Why not:** a CI host should have zero stashes. If it has any, the stashes are evidence of:
- A misconfigured cleanup step (the CI didn't reset between runs)
- A bug in a custom CI script
- Infrastructure drift

The right move is to investigate the cause, not triage the symptom.

**Detection heuristic:** working dir matches a CI path pattern AND no human user is logged in.

---

## NTU-4: Mid-merge / Mid-rebase / Mid-cherry-pick

**Symptom:** `git status` shows:
- `interactive rebase in progress`
- `unmerged paths`
- `cherry-pick in progress`
- `revert in progress`

**Why not:** the skill needs a clean checkout state to snapshot from. Mid-operation states have ambiguous semantics and risk corrupting the in-progress operation.

**Better approach:** finish the operation first.

```bash
# Resume the rebase:
git rebase --continue
# Or abort:
git rebase --abort
# Then run the skill.
```

Phase 0 detects this and refuses to start.

---

## NTU-5: Detached HEAD with no recovery branch base

**Symptom:** `git status` shows `HEAD detached at <sha>`, no obvious primary branch to land keepers onto.

**Why not:** the skill needs a target branch for the recovery commits. Detached HEAD has no implicit target.

**Better approach:** check out the primary branch first:

```bash
git checkout <primary>
# Then run the skill.
```

Phase 0 detects this and asks the user to fix it before proceeding.

---

## NTU-6: Bare repository

**Symptom:** the project is a bare repo (`<project>/HEAD` exists but no working tree).

**Why not:** the skill needs a working tree to apply diffs into. Bare repos don't have one.

**Better approach:** clone the bare repo into a working directory; run the skill against the clone.

Phase 0 detects this via `git rev-parse --is-bare-repository` and refuses.

---

## NTU-7: Submodule with stashes

**Symptom:** the `.git` is actually `.git: gitdir: ...`, indicating a submodule.

**Why not:** stashes in submodules are recoverable, but the skill's recovery branch logic assumes the project's main repo. Operating against a submodule directly can cause confusion about which repo's primary branch is the target.

**Better approach:** decide whether the stashes belong to the parent repo or the submodule, then operate against the appropriate one explicitly.

The skill can be invoked against a submodule, but Phase 0 surfaces:

> This is a submodule under <parent-repo>. The skill will operate against
> the submodule's primary branch (<submodule-primary>), not the parent's.
> Confirm this is what you want.

---

## NTU-8: Repository with no commits yet

**Symptom:** `git log` returns "no commits yet" / "fatal: your current branch '<x>' does not have any commits yet".

**Why not:** stashes need a base to compare against. A repo with no commits and stashes is a pathological state (which technically can't happen via normal git workflows, but might via direct `.git/refs/stash` manipulation).

**Better approach:** investigate how the stashes got there; the skill can't safely operate.

---

## NTU-9: Repository with no remote

**Symptom:** `git remote -v` returns empty.

**Why not:** the skill works without a remote, but several features degrade:
- Primary branch detection (no `origin/HEAD` to query)
- Push instructions in the handoff (nothing to push to)
- Recovery branch base (no `origin/<primary>` — must use local `<primary>`)

**Better approach:** the skill can run; Phase 0 warns:

> No remote configured. The recovery branch will be based on local
> `<primary-branch>` instead of `origin/<primary-branch>`. The handoff
> will include local-only instructions (no `git push` step).

This is a degraded but acceptable mode.

---

## NTU-10: Unauthorized access to the project

**Symptom:** the user explicitly told the agent NOT to operate on this project (in CLAUDE.md, AGENTS.md, conversational context).

**Why not:** authorization is a hard rule.

**Better approach:** ask for explicit authorization. Refuse to proceed without it.

---

## NTU-11: Stashes that are explicitly labeled "do not triage"

**Symptom:** stash messages contain `KEEP`, `DO NOT TRIAGE`, `pinned`, or similar.

**Why not:** the user has explicitly tagged these as out-of-scope.

**Better approach:** the triage rubric should treat these as `pinned` — never auto-classify or auto-drop. Phase 5 surfaces them with verdict `pinned-by-message` and skips Phase 9 for them.

---

## NTU-12: Mass-stash from a known good operation

**Symptom:** the project just had a major operation (release prep, monorepo split, mass refactor) that intentionally generated many stashes for archival.

**Why not:** these stashes are intentional records, not WIP residue.

**Better approach:** ask the user about the recent history. If they confirm "those are intentional", the skill should not run; the bundle creation can still happen as a backup, but Phase 4+ should not.

---

## NTU-13: Ephemeral / disposable repo

**Symptom:** the user explicitly says "this is a throwaway clone" or the path matches `/tmp/...`.

**Why not:** the skill's recovery bundle adds disk + complexity for no value if the user is about to delete the entire clone anyway.

**Better approach:**

```bash
# For a throwaway clone, just inspect manually:
git stash list
# If anything is interesting, cherry-pick or apply from the original.
# Otherwise: rm the clone.
```

Phase 0 detects `/tmp/...` paths and warns:

> Target path is under /tmp/. The skill creates a recovery bundle at
> /tmp/<basename>-stash-archive-<DATE>/, which is also ephemeral. If you
> truly want to triage stashes from a throwaway clone, this is fine, but
> consider whether the original repo (where the stashes come from) is
> what you should be operating on.

---

## NTU-14: Git config explicitly disabling stashes

**Symptom:** `git config --get stash.useBuiltin` is `false` (legacy setting), or `git config --get core.useBuiltinFsmonitor` is in an unusual state. Or git is older than 2.10.

**Why not:** modern git APIs (`git stash show -p --binary`, `git apply --3way`, `git update-ref`) work consistently from git 2.20+. Older versions have subtle differences.

**Better approach:** check `git --version`. If <2.20, surface a warning; recommend upgrading git first.

---

## NTU-15: Stashes hold sensitive secrets the user wants pruned, not archived

**Symptom:** the user says "I have stashes that contain accidentally-committed API keys; help me NUKE them."

**Why not:** this skill creates a *recovery bundle* that contains every stash's content. If the goal is to PURGE secrets, the bundle works against the goal — it's a permanent archive.

**Better approach:** for secret-purging, use the BFG repo cleaner or `git filter-repo` to rewrite history. Then drop the stashes. Then rotate the credentials.

The skill explicitly does not support secret-purging. If the user mentions this goal, redirect them.

---

## NTU-16: The user just wants to understand WHAT'S in the stashes

**Symptom:** the user asks "what's in my stashes?" but doesn't want triage or cleanup.

**Better approach:** run only Phases 1, 2, 3 (`output_mode=triage-only` ends after Phase 5 with the decision table; you can stop earlier by setting a custom mode). The triage_decision.md is the answer.

This is a valid skill invocation in `triage-only` mode — but Phase 5+ should not run, and no destructive actions should be authorized.

---

## NTU-17: Repository on a read-only filesystem

**Symptom:** writing to `<project>/.git/` fails with EROFS or similar.

**Why not:** the skill needs to write `refs/stash-backup/*` and `.stash_janitor_workspace/`.

**Better approach:** copy the repo to a writable filesystem first, or remount read-write.

---

## Decision Table

| Condition | Action |
|-----------|--------|
| <5 stashes | Warn; default to manual inspection |
| Stash-as-clipboard workflow detected | Confirm with user before proceeding |
| CI checkout | Refuse; investigate root cause |
| Mid-merge/rebase/cherry-pick | Refuse; finish operation first |
| Detached HEAD | Ask user to checkout primary first |
| Bare repo | Refuse; ask for working clone |
| Submodule | Confirm scope (parent vs. submodule) |
| No commits | Refuse |
| No remote | Warn; degraded mode |
| Unauthorized | Refuse |
| Stashes labeled `KEEP` / `pinned` | Skip those; triage rest |
| Mass-stash from known-good operation | Ask user; default to no-run |
| Ephemeral clone (`/tmp/`) | Warn |
| Old git (<2.20) | Warn; recommend upgrade |
| Goal is secret-purging | Redirect to BFG / filter-repo |
| Goal is "what's in there" | Run in `triage-only` mode |
| Read-only filesystem | Refuse |
