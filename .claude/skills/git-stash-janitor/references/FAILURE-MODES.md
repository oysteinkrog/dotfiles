# Failure Modes — Diagnostic Playbook

Every entry below was learned the hard way during the motivating asupersync 127-stash session, or anticipated from related git internals.

---

## F1. `git format-patch -1 stash@{N}` is not the stash recovery diff

**Symptom:** the bundle's `diffs/N.diff` is empty or much smaller than the stash; `git stash show --stat stash@{N}` shows hundreds of lines but the diff is 0–10 lines.

**Cause:** a stash commit's first parent is HEAD, second parent is the index commit, and the stash object is a merge commit. `git format-patch -1 stash@{N}` is not the `git stash show -p --binary` recovery diff; depending on the merge parents it can be empty, tiny, or unrelated to the working-tree content.

**Fix:** use `git stash show -p --binary stash@{N}` for live tracked/index inspection. During bundle build, use the stable `sha` captured in `inventory.tsv`; if `<sha>^3` exists, materialize those untracked files separately with `git archive <sha>^3`. `--binary` is required for tracked binary payloads; untracked files still live in the third parent and are not included in the patch. Document the footgun in the bundle's README.md.

**Reproduction:**
```bash
git stash push -m "test" -- some_file.rs    # creates stash@{0}
git format-patch -1 stash@{0} -o /tmp/wrong/  # might be empty
git stash show -p --binary stash@{0} > /tmp/right.diff  # full tracked/index content
```

---

## F2. `git stash apply` / `git stash pop` dirties the tree on conflict

**Symptom:** mid-Phase 6, an apply fails; `git status` shows unmerged paths AND `git stash list` still has the stash AND there's a `.rej` file.

**Cause:** `git stash apply` mutates state directly. On conflict, the working tree is left dirty and the stash is still in the list, requiring manual cleanup before the next operation.

**Fix:** never use `git stash apply` / `git stash pop` in this skill. Use `git apply --3way <bundle>/diffs/N.diff` instead. On `--check` failure, the working tree is untouched.

**Recovery if accidentally invoked:**
```bash
git status --porcelain=v2
# Identify the exact paths changed by the accidental apply.
# If a verified bundle diff exists, try reversing only that diff:
git apply -R --3way <bundle>/diffs/NNN.diff
# If that fails, undo only the affected files with explicit user approval.
```

---

## F3. Stash indexes shift after each drop

**Symptom:** Phase 9 drops 5 stashes, but the result has different content gone than expected. The user sees "I told you to drop stash@{34}, but stash@{30} is gone."

**Cause:** `git stash drop stash@{0}` shifts what was `stash@{1}` to become `stash@{0}`. If you drop in `0, 1, 2, ...` order, you're dropping completely different content than intended.

**Fix:** drop **highest index first** within each verdict bucket. The Phase 9 cleanup plan (`cleanup_plan.tsv`) materializes this order before executing.

**Verification:** before each drop, re-resolve the current ref's message against `inventory.tsv`. If the message doesn't match, the list has shifted unexpectedly — halt.

---

## F4. Stash content's line numbers no longer match main

**Symptom:** `git apply --3way --check` fails with "patch does not apply"; the affected file still exists on main but at a very different state.

**Cause:** the stash predates a refactor. Main moved by hundreds of lines. The 3-way merge attempts to find moved context, but if the surrounding code is too different, it gives up.

**Fix:** never force the apply. Surface to the user with:
- The stash's diff
- The current state of the affected files
- A hypothesis (function rename, file move, paradigm shift)
- A proposed manual resolution preserving the stash's *intent* (not its surface form)

If user OKs: apply the resolution via the Edit tool. If user says "drop", mark as `conflict-skipped`.

**Worked example:** asupersync session, stash@{34}. Stash modified `src/mysql/protocol.rs` with `if let Ok(payload_len) = ... { ... } else if ... { ... }`. Main had refactored that to `match` syntax. The 3-way apply succeeded textually but produced syntactically-broken code (an `if let` inside a `match` arm). The agent re-read the affected file, manually ported the stash's intent (the OK-packet length cap) into the new `match` structure via Edit, then re-ran gates.

---

## F5. Working tree shows changes from concurrent agents

**Symptom:** `git status` shows files modified that you didn't touch this run.

**Cause:** other agents working in the same repo (per AGENTS.md "Note for Codex/GPT-5.5"). This is the normal state in a multi-agent environment, not an error.

**Fix:** treat the changes as if you made them. Never stash, revert, or overwrite. Operator `↺ WORKING-TREE-DRIFT` snapshots the state and proceeds. If the apply conflicts with concurrent changes, surface to the user — don't auto-resolve.

---

## F6. DCG blocks `rm -rf <bundle>/patches/`

**Symptom:** the skill tries to clean up old patches and gets a DCG block.

**Cause:** dcg blocks `rm -rf`, even on auxiliary directories.

**Fix:** the skill is *designed* never to need `rm -rf`. Bundle lifecycle is the user's responsibility. If you find yourself wanting to delete bundle contents:
- Don't.
- The bundle is intentionally kept until the user decides otherwise.
- If a Phase 7 split-apply produces a `.split.diff` you want to "clean up", just leave it in place — it's a useful audit trail.

---

## F7. Stash@{N}'s parent SHA isn't reachable

**Symptom:** `git rev-parse stash@{N}^` succeeds, but `git log stash@{N}^` reports the SHA is unreachable from any branch.

**Cause:** the branch the stash was made on has been deleted. The stash itself is still valid (commit objects don't disappear until garbage collection); the diff-vs-parent works fine.

**Fix:** record the orphan-parent fact in `meta/N.txt`. The recovery diff is unaffected. The Phase 9 drop is also unaffected.

**Note:** if `git gc` ran between the stash creation and now, the parent commit might actually be gone. In that case, `git stash show -p --binary` may fail because the stash object's parent is missing. Treat that as a bundle gate failure and preserve the backup ref for manual investigation.

---

## F8. Symbol exists on main but with different semantics

**Symptom:** fingerprint says `lock_until` is on main at `src/mutex.rs:317`. Reading both: the stash's version takes `Instant`; main's version takes `Duration`.

**Cause:** unrelated landing took the same name. The two functions are *not* equivalent.

**Fix:** the same-signature heuristic in TRIAGE-RUBRIC catches most of these. When same_signature=false on >30% of sampled symbols, the verdict flips from `superseded` to either `partially-novel` (if some hunks still apply) or `novel-but-stale` (if the surface drift is too big). Surface the divergence to the user in Phase 5.

---

## F9. Two stashes introduce the same fingerprint

**Symptom:** stash@{12} and stash@{47} both contain a function `parse_ok_packet_safe`. Both are marked novel-and-accretive. Phase 6 applies both and gets a duplicate-definition build error.

**Cause:** common when the stash list represents many parallel agent attempts at the same task.

**Fix:** during triage, mark all but the most recent as `superseded-by-newer-stash` if both have ≥80% fingerprint overlap. Only the most recent gets `novel-and-accretive`. Operator `⊞ RE-FINGERPRINT` (Phase 6, between applies) catches stragglers that flip after the first apply lands.

---

## F10. `git stash list` count differs between two runs

**Symptom:** Phase 2 inventory says 127 stashes; later you re-list and see 126.

**Cause:** a concurrent agent created or dropped a stash between snapshots.

**Fix:** the bundle's `index.tsv` is authoritative for *that snapshot point*. If a re-list disagrees:
- If a stash was added: it's not in the bundle. Phase 9 cannot drop it. Tell the user.
- If a stash was dropped: it's already gone. The bundle still has the recovery artifacts.

If the count drops by >1 between phases, halt and ask the user — something might be wrong.

---

## F11. Beads database unwritable during the run

**Symptom:** `br create` returns `database is locked` or similar.

**Cause:** a parallel `br` process holds the SQLite lock.

**Fix:** retry with backoff (3 attempts, 5 / 10 / 20 seconds). If still failing, skip the beads-issue creation; record `beads_skipped: true` in the handoff report. The run still succeeds.

---

## F12. UBS not installed on this host

**Symptom:** `ubs <files>` returns `command not found`.

**Cause:** UBS is project-specific; not every project uses it.

**Fix:** `project_profile.json:ubs_available` should be `false` for projects without UBS. Phase 6's `⊕ RECOVER` operator skips UBS when not available. The skill should NEVER fail because UBS isn't installed.

---

## F13. The recovery branch already exists

**Symptom:** `git checkout -B stash-recovery-2026-05-06 origin/main` succeeds (because `-B` resets), but the user had unrelated work on the branch from a previous run.

**Cause:** running the skill twice on the same day, or resuming a run from a previous day.

**Fix:** Phase 0 (Up-Front Confirmations) detects this. If the branch exists:
- Ask the user whether to (a) extend it (resume), (b) rename + use new branch, (c) abort.
- Never silently `-B` away existing work.

---

## F14. The bundle directory already exists

**Symptom:** `<project-parent>/<basename>-stash-archive-<YYYY-MM-DD>/` already exists.

**Cause:** running the skill twice in the same day.

**Fix:** Phase 3 detects this. `build-bundle.sh` refuses to overwrite a non-empty bundle by default. Use `BUNDLE_REUSE_OK=1` to verify and reuse only if byte-equality passes; use `BUNDLE_OVERRIDE=<basename>-stash-archive-<YYYY-MM-DD>-2/` for a fresh bundle; abort if neither is acceptable. In-place rebuild requires `BUNDLE_REBUILD_IN_PLACE_OK=1` and explicit user approval.

---

## F15. Phase 6 commit fails because of a pre-commit hook

**Symptom:** `git commit` returns non-zero with a hook error (e.g., `husky: prettier check failed`).

**Cause:** the recovered hunk doesn't match project formatting / linting rules. The stash predates a tightening of the rules.

**Fix:** never `--no-verify`. Either:
- Re-run formatter (`cargo fmt`, `prettier --write`) on the affected files; if format changes don't break semantics, commit again.
- If the issue is structural (e.g., the linter forbids a pattern the stash uses), surface to the user; the stash may need a small adaptation before recovering.

Record the failure in `apply_log.tsv:gates_status = "hook-failed: <hook-name>"`.

---

## F16. The user's authorization phrase doesn't include a literal command

**Symptom:** Phase 9 ⚠ CONFIRM gate, user types "yes proceed".

**Cause:** the user is being efficient but the authorization isn't specific enough per AGENTS.md "Mandatory explicit plan".

**Fix:** the operator's prompt module requires a phrase that includes a literal command. Re-ask with a specific template:

> Please paste this verbatim to proceed:
>
>     yes I understand and want to drop all 124 stashes per the plan above

If the user types something different, re-ask. If the user objects ("just trust me"), explain that the verbatim authorization is per AGENTS.md policy and is the only thing that gives them a paper trail of what they authorized.

---

## F17. The stash uses a binary file format

**Symptom:** without `--binary`, the stash diff is mostly `Binary files differ` lines and `git apply --3way --check` fails with "cannot apply binary patch ... without full index line".

**Cause:** stashes can contain binary changes (images, generated files, lockfiles).

**Fix:**
- Phase 3 must build the bundle with `git stash show -p --binary`; otherwise tracked binary changes are not recoverable from `diffs/<NNN>.diff`.
- Phase 4 fingerprinting can't extract symbols from binary. Fall back to file-existence check + size delta + extension-based heuristics.
- If the file is a generated artifact (`Cargo.lock`, `package-lock.json`, `pnpm-lock.yaml`), treat as `garbage` (lockfiles regenerate; restoring an old one is anti-pattern).
- If the file is genuine content (e.g., a test fixture image), surface to user — let them decide whether to recover.

---

## F18. Phase 4 takes too long

**Symptom:** triage workers running for over an hour on a 200-stash repo.

**Cause:** whole-repo grep on every fingerprint × every stash = O(N²) work.

**Fix:**
- Path-scoped grep first (`git grep -F <symbol> <branch> -- <expected_path>`).
- Cache `verify-on-main` results per-fingerprint within a batch.
- If many stashes share fingerprints (common with parallel-agent attempts), dedupe the verify-on-main calls across the batch.
- For Comprehensive mode (>80 stashes), spawn more workers (5+ vs. 2–4).

---

## F19. Phase 8 fresh-eyes never converges (loops finding the same nit)

**Symptom:** round 4 finds the same lint warning round 3 found; the agent isn't actually fixing it.

**Cause:** the lint warning may be unfixable (a project rule the recovered code can't satisfy) or the agent is stuck.

**Fix:** Phase 8 termination rule is "two consecutive rounds with only trivial findings AND gates green". If the same finding appears three rounds in a row, surface to user as a "blocking unresolvable" — let the user decide whether to:
- Adapt the recovered code to fix it
- Accept the lint warning (often via `#[allow(...)]` or equivalent)
- Drop the keeper

---

## F20. The recovery branch's tip diverges from origin/<primary>

**Symptom:** between Phase 0 and Phase 6, `origin/<primary>` advanced (a teammate pushed). The recovery branch's base is stale.

**Cause:** other developers / agents working concurrently.

**Fix:** Phase 6 doesn't need to track origin in real-time — the recovery branch was created off `origin/<primary>` at a specific snapshot, and that's fine. After handoff, the user rebases or merges the recovery branch onto the latest primary. The handoff report's recovery recipe explicitly tells the user to:

```bash
git pull --rebase origin <primary-branch>      # update local primary
git rebase <primary-branch> stash-recovery-... # rebase recovery onto latest
```
