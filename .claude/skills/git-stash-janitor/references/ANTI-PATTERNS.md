# Anti-Patterns — Specific Things Never to Do

Each anti-pattern is paired with: why it's wrong, the correct approach, and (where applicable) a worked example from the asupersync session.

---

## A1. Use `git format-patch -1` for the bundle's recovery diff

**The mistake:**
```bash
git format-patch -1 stash@{34} -o $BUNDLE/diffs/  # WRONG
```

**Why it's wrong:** a stash is a merge commit. `git format-patch -1 stash@{N}` is not the stash recovery diff and can emit a tiny, empty, or unrelated patch depending on the merge parents. It also never materializes untracked files.

**Worked example:** In the asupersync session, the agent first tried `git format-patch -1 stash@{34}` on a stash that contained a 120-line WIP. The format-patch was 0 lines (empty). `git stash show -p --binary stash@{34}` was 120 lines. The bundle would have been useless if format-patch output had been trusted.

**Correct approach:**
```bash
sha="$sha_from_inventory_tsv"
git stash show -p --binary "$sha" > "$BUNDLE/diffs/$N.diff"
```

The bundle's `README.md` must explicitly document this footgun for human readers.

---

## A2. Run `git stash pop` or `git stash apply` directly

**The mistake:**
```bash
git stash apply stash@{34}  # WRONG
git stash pop stash@{34}    # WRONGER (also drops on success)
```

**Why it's wrong:**
- On success: state is correct, but you bypassed the bundle's diff (so you can't verify what was applied vs. what was supposed to be applied).
- On conflict: working tree is dirty AND the stash is still in the list AND a half-applied state needs cleanup.
- `pop` additionally drops the stash on success, removing the safety net.

**Correct approach:**
```bash
git apply --3way --check $BUNDLE/diffs/$N.diff  # dry-run first
git apply --3way        $BUNDLE/diffs/$N.diff   # only on clean check
```

Operate on the bundle's diff, never on the stash directly. The stash itself is an immutable backup until Phase 9.

---

## A3. Run `git stash clear` (mass drop)

**The mistake:**
```bash
git stash clear  # WRONG — drops everything at once
```

**Why it's wrong:**
- DCG may not block this (it's a stash op, not `rm -rf`), so the human safety net is just the bundle.
- If any stash later turns out to have been classified wrong, recovery is per-stash through the bundle. That works, but it's operationally noisy compared to surgical drops.
- The user can't audit per-stash before each drop.
- Per AGENTS.md "Mandatory explicit plan", a single `git stash clear` doesn't enumerate what's being destroyed.

**Correct approach:** drop individually with `git stash drop stash@{N}`, one per row in the cleanup plan, restating the verbatim command before each.

---

## A4. Drop stashes lowest-index first

**The mistake:**
```bash
for n in 0 1 2 3 ... 126; do
  git stash drop "stash@{$n}"  # WRONG — every drop shifts indexes
done
```

**Why it's wrong:** Stash indexes are stack positions. After `git stash drop stash@{0}`, what was `stash@{1}` becomes `stash@{0}`. So the next iteration drops the wrong stash.

**Correct approach:** drop **highest index first** within each verdict bucket. The Phase 9 cleanup plan materializes this order before executing.

```bash
# Build the plan (highest index first per bucket):
for n in $(awk -F'\t' '$2=="garbage" {print $1}' triage.tsv | sort -rn); do
  echo "git stash drop stash@{$n}"
done
```

---

## A5. Assume `main` is the primary branch

**The mistake:**
```bash
git checkout main           # WRONG — many projects use master/develop/trunk
git diff main..stash@{34}   # WRONG — might fail or compare to wrong branch
```

**Why it's wrong:** Many projects use `master`, `develop`, `trunk`, or `default`. Hardcoding `main` produces wrong supersession evidence and wrong recovery-branch base.

**Correct approach:** detect the primary branch in Phase 1 (`scripts/discover-project.sh`):

```bash
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
  | sed 's@^refs/remotes/origin/@@' \
  || git config init.defaultBranch \
  || (git branch -a | grep -E 'remotes/origin/(main|master|develop|trunk|default)' | head -1)
```

Write the result to `project_profile.json:primary_branch` and read from there.

---

## A6. Push the recovery branch on the user's behalf

**The mistake:**
```bash
git push origin stash-recovery-2026-05-06  # WRONG — user's call
```

**Why it's wrong:** Like the documentation-website skill, deployment is the user's call. Even when everything passed, the user owns the push:

- They may want to inspect the commits first.
- They may want to rebase onto a different base.
- They may want to open a PR with custom reviewers.
- They may have policies about what gets pushed when.

**Correct approach:** print the suggested command verbatim in the handoff report, then stop:

```
git push origin stash-recovery-2026-05-06
```

Note the command in `handoff_report.md`. Do not execute it.

---

## A7. Bypass pre-commit hooks

**The mistake:**
```bash
git commit --no-verify -m "..."  # WRONG — hook exists for a reason
```

**Why it's wrong:** The user's hooks are the project's quality gates. Bypassing them propagates exactly the kind of bugs the rest of the skill is trying to prevent. Per AGENTS.md general practice, never `--no-verify`.

**Correct approach:** if a hook fails, surface the failure to the user. Either:
- Fix the underlying issue (typecheck error, lint error, format error)
- Surface the conflict between the stash's content and the project's quality bar to the user

If the user explicitly authorizes a `--no-verify` commit (rare), record the authorization text.

---

## A8. Stash, revert, or overwrite changes from concurrent agents

**The mistake:**
```bash
git stash push -m "clean up before applying recovery"  # WRONG
git checkout -- src/parser.rs                          # WRONG
git restore .                                          # WRONG
```

**Why it's wrong:** Per AGENTS.md "Note for Codex/GPT-5.5", concurrent agents are doing legitimate work in the same checkout. Disturbing their state destroys their work.

**Correct approach:** treat working-tree changes that appeared during the run as if you made them. Snapshot the state before each Phase 6 apply (operator `↺ WORKING-TREE-DRIFT`) and proceed without disturbing the changes. The 3-way merge will handle context. If the apply conflicts with concurrent changes, surface to the user — don't auto-resolve.

---

## A9. Run a script to "fix up" conflicts

**The mistake:**
```bash
sed -i 's/if let Some(x) = y/if let Some(x) = y.clone()/' src/parser.rs  # WRONG
```

**Why it's wrong:** Per AGENTS.md "No Script-Based Changes": brittle regex transformations create more problems than they solve.

**Correct approach:** manual conflict resolution via the Edit tool only. If the conflict is across many files, surface to the user; don't try to automate a code transformation in the recovery path.

---

## A10. `rm -rf` the bundle after a successful run

**The mistake:**
```bash
rm -rf $BUNDLE  # WRONG — DCG blocks; also destroys the safety net
```

**Why it's wrong:**
- DCG blocks `rm -rf` (per AGENTS.md). Trying to bypass DCG is itself a violation.
- Even if DCG didn't block, the bundle is the user's safety net for the *next* week of regret. The user should manage bundle lifecycle.
- The skill's job ends at handoff. Cleanup of the bundle is a separate (manual) decision.

**Correct approach:** leave the bundle in place; document its location in the handoff report; let the user decide when to remove it.

---

## A11. Skip Phase 3 byte-equality verification

**The mistake:** "I already created the bundle artifacts; let's skip the verify step to save time."

**Why it's wrong:** If the bundle's diff doesn't match the live stash byte-for-byte, the entire recovery story is broken. A wrong diff is worse than no diff — the user thinks they have a backup but doesn't.

**Correct approach:** Phase 3 is a hard gate. Run `verify-bundle.sh`; refuse to proceed on any mismatch.

---

## A12. Land keeper commits directly on the primary branch

**The mistake:**
```bash
git checkout main
git apply --3way $BUNDLE/diffs/34.diff
git commit ...
git push origin main  # WRONG (also: push, see A6)
```

**Why it's wrong:** Even with rigorous verification, mass-applied recovered commits deserve user review. Landing directly on the primary branch:
- Forces the user to review post-hoc instead of pre-merge
- Can interfere with concurrent agents who based their work on the primary branch's tip
- Bypasses any branch-protection rules (required reviews, status checks)

**Correct approach:** create a `stash-recovery-<DATE>` branch off the primary; land keeper commits there; let the user merge or cherry-pick onto the primary.

---

## A13. Use `git apply --include=<path>` for hunk-level filtering

**The mistake:**
```bash
git apply --include=src/parser.rs $BUNDLE/diffs/47.diff  # WRONG for partial-novel
```

**Why it's wrong:** `--include` is path-level, not hunk-level. If a stash has multiple hunks in the same file (some superseded, some novel), `--include` keeps all of them.

**Correct approach:** create a split copy of the diff, dropping the superseded hunks. Use the Edit tool for semantic/manual splits; use `scripts/partial-split.sh` only for exact hunk-number filtering after the triage row names the hunks to keep. Apply the smaller diff. The split-apply operator `⇄ SPLIT-HUNKS` documents this.

---

## A14. Treat `git stash list` count as authoritative across runs

**The mistake:** "I inventoried 127 stashes earlier; let's use that count for Phase 9."

**Why it's wrong:** Concurrent agents can create or drop stashes between snapshots. The count from a 30-minute-old inventory may be stale.

**Correct approach:** before each Phase 9 drop, re-resolve the current ref's message against `inventory.tsv`. If the message doesn't match, the list has shifted — halt and ask the user.

---

## A15. Trust the rubric blindly when confidence < 0.7

**The mistake:** auto-applying a verdict with confidence 0.62 because the pipeline produced a number.

**Why it's wrong:** Confidence < 0.7 means the rubric isn't sure. The Phase 5 user-facing table exists exactly for these cases.

**Correct approach:** any verdict with confidence < 0.7 surfaces in Phase 5 as `unknown` and forces a user decision. Confidence < 0.6 forces `unknown` regardless of which rubric branch fired.

---

## A16. Skip the working-tree snapshot at run start

**The mistake:** "The repo's clean, no need to snapshot."

**Why it's wrong:** The repo may *not* be clean by Phase 6, even if it was at Phase 0 — concurrent agents work fast. Without a snapshot, you can't tell which working-tree changes were yours.

**Correct approach:** snapshot at Phase 0 (`wt_phase0.txt`) and re-snapshot before each Phase 6 apply (`wt_pre_apply_<N>.txt`). The diff between them tells you what concurrent agents did.

---

## A17. Let workspace artifacts leak into commits

**The mistake:** running on a repo where `.stash_janitor_workspace/` ends up staged or committed as part of recovered keeper commits.

**Why it's wrong:** The workspace contains run artifacts that shouldn't be committed. If they end up in `git add -A` during Phase 6 commits, they pollute the recovery branch.

**Correct approach:** every script that stages or audits working-tree state must explicitly exclude `.stash_janitor_workspace/` via pathspecs. Do not auto-edit `.git/info/exclude`; that directly mutates `.git/` and contradicts the skill's kernel. If a persistent local ignore is desired, ask the user first and add one idempotent line only after approval.

---

## A18. Author commits with `Co-Authored-By` lines without asking

**The mistake:** automatically tacking on `Co-Authored-By: Claude` to every recovery commit.

**Why it's wrong:** Many projects have specific commit-message conventions (Conventional Commits, ticket-id prefixes); adding `Co-Authored-By` may collide with project policy. The user owns commit style.

**Correct approach:** the default Phase 6 commit message has no `Co-Authored-By` line. If the user explicitly asks for one (e.g., "include co-author trailers"), add it.

---

## A19. Run the full test suite only at the end of Phase 6

**The mistake:** apply 5 keepers, then run `cargo test` once at the end.

**Why it's wrong:** if test fails, you don't know which keeper caused it. Compounding errors are much harder to debug than per-keeper failures.

**Correct approach:** the `⊕ RECOVER` operator runs gates after every successful apply. The `apply_log.tsv:gates_status` column proves it.

---

## A20. Authorize destructive cleanup with a vague phrase

**The mistake:**
```
> Should I proceed with cleanup?
> User: yes go ahead
[skill drops 124 stashes]
```

**Why it's wrong:** "yes go ahead" is too vague to count as the AGENTS.md "Mandatory explicit plan" authorization. The user might not have read the plan.

**Correct approach:** the `⚠ CONFIRM` operator's prompt module requires the user to paste a specific phrase that includes a literal command from the plan. The verbatim text is recorded in `cleanup_authorization.txt`. Without that file, the action did not happen.
