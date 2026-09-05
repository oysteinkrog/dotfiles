# Stash Smells — Taxonomy of Common Stash Categories

A "stash smell" is a recognizable category that lets you predict the verdict before fingerprinting. The triage rubric uses these as priors; users can override.

---

## Smell 1: `wip-<ticket>` — Almost Always Superseded

**Pattern:** Message starts with `wip-` followed by a ticket id (`BACK-1234`, `JIRA-567`, `proj-42`, etc.) Often followed by a short feature description.

**Why it appears:** Agent commits WIP via `git stash push -m "wip-BACK-1234"` while interrupted; later, another (or the same) agent finishes the work cleanly and lands it via PR.

**Default verdict:** `superseded` (when fingerprint resolves on primary) — most common — or `novel-and-accretive` (rare, when nobody finished the work).

**Asupersync data:** 94 of 127 stashes; 89 superseded, 1 novel (the OK-packet defensive guard), 4 superseded-by-newer-stash.

**Caveat:** when 5+ `wip-<same-ticket>` stashes exist, only the most recent has any chance of being the canonical WIP. Treat the rest as `superseded-by-newer-stash`.

---

## Smell 2: `pre-<refactor>-stash` — Often a Deliberate Save Before Risky Operation

**Pattern:** Message includes `pre-`, `before-`, `safety-`, e.g., `pre-deadlock-fix`, `before-tokio-bump`, `safety-pre-clippy-cleanup`.

**Why it appears:** Developer (or careful agent) saves working state before doing something they fear might lose work. After the operation succeeds, the save sits unused.

**Default verdict:** `superseded` if the operation succeeded (the polished version landed on main); `garbage` if the operation produced something that diverged from this save's content.

**Asupersync data:** 9 stashes; all superseded.

**Heuristic:** if the date of the save is ≥2 weeks old AND `git log --since=<save-date>` shows commits matching the save's intent, it's superseded.

---

## Smell 3: `autostash` — Almost Always Recoverable From Reflog

**Pattern:** Message is exactly `autostash` (or `WIP on <branch>: <sha> autostash`).

**Why it appears:** `git pull --rebase` or `git rebase --autostash` automatically stashes uncommitted changes, applies them after the rebase, then drops the stash. If the rebase fails midway, the autostash is left behind.

**Default verdict:** `garbage` — the rebase reflog has the canonical outcome. The autostash entry is the failed-or-abandoned half-state.

**Asupersync data:** 12 stashes; all garbage (reflog showed clean rebases for all of them; the stash entries were left over from a `git rebase --abort` that didn't pop the autostash).

**Recovery if the user regrets:** `git reflog show <branch>` then cherry-pick the relevant commit. The autostash content is also captured in the bundle, so it's recoverable that way too.

---

## Smell 4: `temp-pre-push` — Almost Always Garbage

**Pattern:** Message is `temp-pre-push`, `pre-push-stash`, or similar.

**Why it appears:** Paranoid agent saves working state before `git push`. After the push, the save is redundant.

**Default verdict:** `garbage` — push succeeded means the content (or its evolution) is on the remote. If push failed, the user would still have the working tree.

**Asupersync data:** 3 stashes; all garbage.

**Caveat:** if the push happened on a branch that was later deleted, the content might NOT be on the remote anymore. Check `git log <branch>` before classifying garbage.

---

## Smell 5: `other-agent-broken` — Always Garbage (Explicitly Labeled)

**Pattern:** Message is exactly `other-agent-broken`, `<agent-name>-broken`, or `do-not-restore`.

**Why it appears:** Agent explicitly labels a stash as known-broken-state when picking up after a partner agent's incomplete work. Saved for forensic purposes only.

**Default verdict:** `garbage`.

**Asupersync data:** 8 stashes; all garbage.

---

## Smell 6: `full-tree-reset-stash` — Almost Always Garbage

**Pattern:** Message is `full-tree-reset-stash`, `reset-bail-out`, `panic-stash`, or similar.

**Why it appears:** Agent ran `git stash; git reset --hard` (the latter blocked by DCG, but the stash succeeded) when in trouble. The stash is the abandoned state.

**Default verdict:** `garbage`.

**Asupersync data:** 1 stash; garbage.

**Caveat:** rarely, the abandoned state had something useful that the polished re-attempt missed. Always check the fingerprint before dropping. In the asupersync case the fingerprint was empty (the stash was just the working tree at panic time, not new content).

---

## Smell 7: `branch-tip-stash` — Often Recoverable From `git reflog` for the Branch

**Pattern:** Message is `WIP on <deleted-branch>: <sha> ...`.

**Why it appears:** Stash was made on a branch that was later deleted. The stash itself survives (commit objects don't disappear), but the branch context is gone.

**Default verdict:** depends on whether the branch was merged before deletion:
- **Merged**: the content is on main; stash is `superseded`.
- **Discarded**: the content was abandoned; stash is `garbage`. Check `git reflog` for the branch — if the last reflog entry is `branch deleted` rather than `merge`, the user explicitly threw the work away.
- **Unknown**: surface to user.

**Asupersync data:** 0 stashes (asupersync has trunk-based development).

---

## Smell 8: `WIP on (no branch)` — Detached HEAD Stash

**Pattern:** Message is `WIP on (no branch): <sha> ...`.

**Why it appears:** Stash made while in detached HEAD state — usually during a rebase or after `git checkout <sha>`.

**Default verdict:** depends on fingerprint analysis.

**Caveat:** the parent SHA is the detached commit; if it's not on any branch and `git gc` ran, the parent might be unreachable. The stash content itself is still applyable.

---

## Smell 9: Empty Stashes (No Diff)

**Pattern:** `git stash show --stat` returns empty.

**Why it appears:** A common cause is `git stash push -- nonexistent-file` succeeding because the staging area happened to have content but the working tree didn't. Or `git stash --keep-index` on an empty working tree.

**Default verdict:** `garbage`. There's nothing to recover.

**Asupersync data:** 0 stashes.

---

## Smell 10: Doubly-Stashed Stash

**Pattern:** Message starts with `WIP on stash@{...}` or includes literal `stash@`.

**Why it appears:** Agent stashed something, then ran `git stash` again without realizing the stash list already had the same content. Rare; usually a debugging artifact.

**Default verdict:** typically duplicates an earlier stash; mark `superseded-by-earlier-stash`.

---

## Smell 11: Stashes with Untracked Files (`git stash -u`)

**Pattern:** `git rev-parse stash@{N}^3` succeeds (the stash has a third parent for untracked files).

**Why it matters:** the bundle must materialize untracked files separately:
```bash
sha="$sha_from_inventory_tsv"
git archive --format=tar "${sha}^3" | tar -x -C "$BUNDLE/stashed-untracked/$N/"
```

If the bundle skips this, the recovery story is incomplete. Untracked-files stashes often contain new test fixtures, scaffolded files, or experiment scripts that weren't yet `git add`-ed.

**Verdict bias:** untracked-files stashes are slightly more likely to be `novel-and-accretive` than tracked-only stashes (because new test fixtures don't get superseded as readily).

---

## Smell 12: Lockfile-Only Stashes

**Pattern:** Diff is exclusively in `Cargo.lock`, `package-lock.json`, `pnpm-lock.yaml`, `Gemfile.lock`, `poetry.lock`, etc.

**Why it appears:** Some users stash lockfile changes when the underlying manifest is unstable.

**Default verdict:** `garbage`. Lockfiles regenerate from the manifest. Restoring an old lockfile is an anti-pattern (you'd be pinning to old transitive deps that may have known CVEs).

**Caveat:** if the manifest has *also* drifted, the user may want the lockfile state for forensics. Surface to user.

---

## Smell 13: License/.gitignore-Only Stashes

**Pattern:** Diff is exclusively in `LICENSE`, `LICENCE`, `.gitignore`, `COPYING`, etc.

**Why it appears:** Often left behind by agents that did a license update on a deleted branch, or accidentally staged a license change while focused on something else.

**Default verdict:** depends on direction:
- License *added*: surface to user; might be intentional.
- License *changed* or *reverted*: usually garbage if the polished change landed on main.
- `.gitignore` additions: usually superseded if the polished landing already added them; garbage if they reference paths that no longer exist.

**Asupersync data:** 0 stashes (the user mentioned `LICENSE`-revert stashes from deleted branches as a category, but the asupersync run didn't have any).

---

## Smell 14: `.beads/.br_history/`-Only Stashes

**Pattern:** Diff is exclusively under `.beads/` or `.br_history/`.

**Why it appears:** The beads sync workflow involves `br sync --flush-only` then `git add .beads/`. If an agent stashed before syncing, they may have a stash that's just the beads state.

**Default verdict:** `garbage`. The current beads database is the authoritative state; restoring an old `.beads/` would corrupt the dependency graph.

---

## Smell 15: Test-Fixture-Only Stashes

**Pattern:** Diff is exclusively under `tests/fixtures/`, `tests/snapshots/`, `__snapshots__/`, or similar.

**Why it appears:** Agent updated test fixtures but didn't commit them; later, the polished test added different fixtures.

**Default verdict:** `partially-novel` is common — some fixtures may be canonical (matching the polished tests), others were experimental.

**Caveat:** binary fixtures (PNG, WebP, parquet) need careful handling. Phase 4 fingerprinting can't extract symbols from binary; fall back to file-existence + size delta.

---

## Smell 16: Generated-Code Stashes

**Pattern:** Diff is exclusively in `target/`, `dist/`, `build/`, `node_modules/`, `__pycache__/`, etc. — paths that are usually `.gitignore`d but somehow ended up in a stash.

**Why it appears:** Misconfigured `.gitignore` at stash time; or a `git stash -u` captured generated artifacts.

**Default verdict:** `garbage`. Never recover generated artifacts; they regenerate.

---

## Smell 17: Single-Hunk Surgical Stashes

**Pattern:** `git stash show --stat` shows 1 file, 1–10 lines.

**Why it appears:** Developer (or careful agent) stashes a small WIP fix to come back to.

**Default verdict:** triage normally — these are often genuinely useful. Single-hunk surgical stashes have the highest yield rate of `novel-and-accretive` per stash, even if they're a small fraction of a large stash list.

**Asupersync data:** stash@{34} — the OK-packet length cap — was a single-hunk surgical stash. The 1 keeper out of 127 was this category.

---

## Smell 18: Massive (>1000-line) Stashes

**Pattern:** `git stash show --stat` shows 50+ files, thousands of lines.

**Why it appears:** Mid-flight refactor that got abandoned, or a paste-mistake stash.

**Default verdict:** almost always `superseded` (the refactor landed in pieces) or `novel-but-stale` (the refactor was abandoned and the codebase moved past it). Manual inspection required if novel.

**Caveat:** never auto-apply a >1000-line stash even if the rubric says `novel-and-accretive`. Surface to user.

---

## Smell 19: Old Stashes (>30 days)

**Pattern:** Date is more than 30 days ago.

**Why it appears:** Forgotten work.

**Default verdict:** time-based bias toward `novel-but-stale` — the surrounding code has likely drifted significantly. Apply-check is more likely to fail.

**Caveat:** age alone isn't a verdict. A 6-month-old stash with a 5-line defensive guard might still apply cleanly; an 8-day-old stash that conflicts with a recent refactor might already be stale.

---

## Smell 20: Zero-Stash Repos

**Pattern:** `git stash list | wc -l` returns 0.

**Verdict:** the skill should still produce `project_profile.json`, an empty `inventory.tsv`, and an empty bundle (so the run is idempotent), then short-circuit to "nothing to do" in the handoff.

---

## Using Smells in Triage

The Phase 4 triage worker uses smell detection as a fast prior. The decision flow is:

```
1. Smell match → seed prior verdict (with confidence ~0.7)
2. Run FINGERPRINT
3. Run VERIFY-ON-MAIN
4. If signals agree with prior: confirm verdict, raise confidence
5. If signals disagree with prior: trust the signals, lower confidence,
   surface to user in Phase 5 even if confidence ≥ 0.7
```

Smell-prior + signal agreement = high confidence. Smell-prior + signal disagreement = surface to user.
