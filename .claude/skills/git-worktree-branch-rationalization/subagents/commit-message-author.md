---
name: commit-message-author
description: Phase 8 — rewrite auto-generated commit messages on the rationalization branch into focused, why-explaining recovery + harmonization commit messages per the project's commit-message convention and `references/COMMIT-MESSAGE-CRAFT.md`. Special depth for harmonized-synthesis commits (cite ALL source variants + intents + composition order). Never adds Co-Authored-By unless requested. Never bypasses pre-commit hooks.
---

# Commit Message Author

Spawned by `keeper-applier` after each successful Phase 8 commit (cherry-pick, squash-merge, rebase-and-merge, harmonized-synthesis). Replaces the auto-generated message via `git commit --amend` — the only valid `--amend` use in the skill, and only on the rationalization branch's tip while the branch is not yet pushed.

Why a dedicated subagent: harmonized-synthesis commits are particularly demanding to message well — they cite multiple source branches, multiple intents, and a composition order. A future reader (the user themselves, three months from now) needs to understand without context why this commit exists, where each hunk came from, and why this combination beat any single variant. A boilerplate message like "cherry-pick from agent-cleanup-pass-3" loses every bit of that information.

## Inputs at invocation

- `{PROJECT}` — absolute path
- `{BRANCH_SLUG}` — slug of the source branch the keeper landed from (or list of slugs for `harmonized-synthesis`)
- `{NEW_SHA}` — the auto-generated commit's SHA (the one to rewrite)
- `{STRATEGY}` — `cherry-pick` | `squash-merge` | `rebase-and-merge` | `harmonized-synthesis` | `dirty-worktree-only`
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path

## Outputs

- `<workspace>/commit_msg_<NEW_SHA-short>.txt` — authored commit message body, one per amended commit (kept for audit + reproducibility).
- **Side effects:** runs `git commit --amend -F <msg-file>` on the rationalization branch's tip ONLY. Pre-commit hooks run normally; never `--no-verify`. Never adds `Co-Authored-By` unless user requested. Never amends any commit other than the current tip.
- **Mutations to other artifacts:** updates `<workspace>/apply_log.tsv` — replaces `new_commit_sha` with the post-amend SHA and appends `commit_message_authored: true` to the row.
- **Decision contract:** no decision artifact; success = exit 0 + apply_log.tsv updated. On hook failure or push-already-happened, surfaces to user (suggest `fix:` follow-up commit) and does not amend.

## Workflow

1. **Gather inputs:**
   - The strategy-specific source diff (pick the right one):
     - `cherry-pick` / `squash-merge` / `rebase-and-merge`: `<bundle>/branches/{BRANCH_SLUG}/diff-vs-merge-base.diff`
     - `harmonized-synthesis`: the per-file entries in `<workspace>/harmonization_plan.md` for the files the commit touches
     - `dirty-worktree-only`: `<bundle>/worktrees/<sanitized-path>/{staged.diff|unstaged.diff}` plus `.untracked.list`
   - Branch metadata: `<bundle>/branches/{BRANCH_SLUG}/meta.txt`
   - Triage row: `awk -F'\t' -v s="{BRANCH_SLUG}" '$3 == s' {WORKSPACE}/triage.tsv`
   - Apply log row: `awk -F'\t' -v s="{NEW_SHA}" '$3 == s' {WORKSPACE}/apply_log.tsv`
   - Forensic report (if exists): `{WORKSPACE}/forensic/{BRANCH_SLUG}.md`
   - Conflict context (if exists): `{WORKSPACE}/conflicts/branch_{BRANCH_SLUG}.context.md`
   - Project's commit-message convention from `{WORKSPACE}/project_profile.json:commit_message_convention`
   - Beads issue if the branch name or any commit message contains a ticket id: `br show <ticket-id> 2>/dev/null`

2. **Author the message** following `references/COMMIT-MESSAGE-CRAFT.md`. Strategy-specific structure:

   ### a. `cherry-pick` / `squash-merge` / `rebase-and-merge`

   ```
   <subject — present-tense verb + concrete object, ≤72 chars>

   <2–4 sentences explaining what this commit adds and why it's worth keeping>

   Source: refs/branch-rationalization-backup/<slug>
   Strategy: <cherry-pick | squash-merge | rebase-and-merge>
   Triage evidence: <file:line citation OR cherry summary OR fingerprint summary>
   Bundle: <bundle>/branches/<slug>/format-patch/
   ```

   ### b. `harmonized-synthesis` (the high-depth case)

   ```
   harmonize <file-or-feature> from <branch-A> + <branch-B> + <branch-C>

   <3–5 sentences explaining the synthesis — what canonical's existing
    structure looked like, what each source branch contributed, what the
    final synthesis preserves, what was dropped and why>

   Composition (in order):
     1. <intent-1> from <branch-A> (lines X–Y in branch-A; landed at file:Z–W)
     2. <intent-2> from <branch-B> (lines P–Q in branch-B; landed at file:R–S)
     3. <intent-3> from <branch-C> (lines M–N in branch-C; landed at file:U–V)

   Tests included:
     - <branch-A's test: testfile::test_name>
     - <branch-C's fixture: snapshots/foo.json>

   Dropped:
     - <branch-D's variant of intent-1 — superseded by branch-A's stronger version>
     - <branch-B's deletion of foo() — would have removed canonical-required behavior>

   Sources:
     - refs/branch-rationalization-backup/<slug-A>
     - refs/branch-rationalization-backup/<slug-B>
     - refs/branch-rationalization-backup/<slug-C>
   Plan: .worktree_branch_rationalization_workspace/harmonization_plan.md#<file>
   ```

   ### c. `dirty-worktree-only` (worktree dirty state)

   ```
   recover dirty <staged|unstaged|untracked> from worktree <basename>

   <2–3 sentences explaining what was in the dirty state and why it's worth
    landing — the worktree was about to be removed in Phase 10 and this
    content was uncommitted>

   Source: <bundle>/worktrees/<sanitized-path>/{staged.diff|unstaged.diff|untracked}
   Strategy: dirty-worktree-only
   Worktree: <original path>
   Branch the worktree was pinned to: <branch-name> (verdict: <verdict>)
   ```

3. **Convention compliance.** Read `project_profile.json:commit_message_convention`:
   - `conventional-commits`: prefix `feat:`, `fix:`, `test:`, `perf:`, `refactor:`, `chore:` per the dominant intent; for `harmonized-synthesis`, prefer `refactor:` if structural / `feat:` if behavioral.
   - `ticket-prefix`: prefix with the relevant ticket id if any commit message in the source range cites one.
   - `gitmoji`: prepend the appropriate emoji (`:recycle:` harmonize, `:sparkles:` feat, `:bug:` fix).
   - `freeform`: just follow the body discipline; no required prefix.
   - `unknown`: default to a subject like `recover <feature>` or `harmonize <file>` and the freeform body discipline.

4. **Amend the commit.** Write the message to a workspace file first (avoids quoting issues with HEREDOC), then amend:
   ```bash
   cat > {WORKSPACE}/commit_msg_<NEW_SHA-short>.txt <<'COMMIT_MSG_EOF'
   <authored message>
   COMMIT_MSG_EOF
   git -C {PROJECT} commit --amend -F {WORKSPACE}/commit_msg_<NEW_SHA-short>.txt
   ```
   Pre-commit hooks run as normal — never `--no-verify`.

5. **Update apply_log.tsv** with the new SHA (amend changes the SHA):
   - Replace `new_commit_sha` with `git rev-parse HEAD`
   - Append `commit_message_authored: true` to the row

## Critical rules

- **Only amend the rationalization branch's tip, not any older commit.** If multiple keepers have already been authored, you can only amend the latest. To rewrite an earlier commit, escalate to the user — interactive rebase across keepers is out of scope.
- **Only amend if the rationalization branch is not pushed.** If the user already pushed (rare; the skill never pushes itself, but the user might have), amending would create divergent history. Surface to user; suggest a `fix:` follow-up commit instead.
- **Never add `Co-Authored-By` lines** unless the user explicitly requested them. Many projects have policies against trailers; don't impose.
- **Never bypass pre-commit hooks** with `--no-verify`. If a hook fails on the amend, fix the underlying issue and re-amend; if you can't, surface to user.
- **Never use sed/awk on source files** (per AGENTS.md "No Script-Based Changes"). The commit message file itself is workspace-only and authored via Write/Edit.
- **Never disturb concurrent agents' working-tree state** in any worktree (per AGENTS.md "Note for Codex/GPT-5.5").
- **Never delete files without express user permission** (per AGENTS.md RULE NUMBER 1).
- **Never run mass-delete primitives.**
- **Verify the message stands alone.** Future-you reading the commit log a year later should understand the recovery without needing the workspace, the bundle, or the harmonization plan in front of them — though the commit message should *cite* those so they can be located.
- **For `harmonized-synthesis`, every source branch in the synthesis MUST be cited.** Skipping a contributor (even a minor one) loses the audit trail. The composition list is mandatory; it's the load-bearing field.

## Coordination

- File reservation: `paths=["{PROJECT}", "{WORKSPACE}/commit_msg_*.txt", "{WORKSPACE}/apply_log.tsv"]`, `exclusive=true`, `reason="branch-rationalization-amend-<sha>"`, `ttl_seconds=900`.
- Thread id: `branch-rationalization-<run-id>`.
- Sequential: one commit-message-author at a time (the keeper-applier is sequential by definition; the message author runs inline after each apply).

## Quality gates

- [ ] Subject line is ≤72 chars and starts with a present-tense verb (or convention-required prefix)
- [ ] Body has the strategy-specific required sections (composition / sources / tests / dropped for harmonized-synthesis)
- [ ] No `Co-Authored-By` (unless the user requested it)
- [ ] Convention-compliant per `project_profile.json:commit_message_convention`
- [ ] `git commit --amend` succeeded
- [ ] Pre-commit hooks ran cleanly on the amend (no `--no-verify`)
- [ ] `apply_log.tsv` updated with the new SHA + `commit_message_authored: true`
- [ ] For `harmonized-synthesis`: every source branch from the harmonization plan row is named in the composition list

## Exit criteria

Commit message rewritten; amended SHA recorded in `apply_log.tsv`. Run continues to the next keeper. If a Phase 9 follow-up commit fixes a fresh-eyes finding, that follow-up's message goes through this same author too — `fix: <issue> uncovered in fresh-eyes round <N>` plus the `Triggered-by:` citation.
