# Reflog Deep Dive — Forensic Reconstruction Beyond Timeline Reconstruction

[TIMELINE-RECONSTRUCTION.md](TIMELINE-RECONSTRUCTION.md) covers the standard forensic flow — how to reconstruct *intent* for `novel-but-stale` and `divergent-refactor` rows by combining git history with cass mining, beads issues, and `gh` PR data. This file goes deeper into one specific tool: the **reflog**. The reflog is git's most underused forensic instrument. It's the only durable record of what *actually happened* — every ref update, in order, with timestamps, regardless of whether the ref still exists.

> **Why a separate reference?** Timeline reconstruction is multi-source. The reflog deserves its own deep dive because (a) it has nuanced semantics (per-ref vs `HEAD@{N}` vs `git log -g`), (b) its gc window has subtle interactions with the bundle, and (c) most agents under-use it. Many `novel-but-stale` and `divergent-refactor` verdicts can be *flipped* by a single reflog query — the cost-benefit is high.

The skill consults the reflog at three points: Phase 0.5 (sanity check, fsck for lost-found), Phase 5 (per-branch forensic enrichment for ambiguous rows), and Phase 11 (handoff includes a "you can recover from reflog if needed" note for branches deleted within the gc window).

---

## 1. Reflog Basics

Every ref-update is logged at the time of the operation:

```
.git/logs/HEAD                          ← updates to HEAD (checkouts, commits, resets)
.git/logs/refs/heads/<branch>           ← updates to that branch's tip
.git/logs/refs/remotes/origin/<branch>  ← updates to that remote tracking ref
.git/logs/refs/stash                    ← stash push/drop
```

A reflog entry has six fields:

```
<old-sha> <new-sha> <author> <timestamp> +/-tz<tab><action>: <message>

abc123def 7e8a9b0c1 Alice <alice@example.com> 1714680000 +0000	commit: implement defensive null check
abc123def 0000000000 Alice <alice@example.com> 1714680300 +0000	branch -D: deleted feat/defensive-null
```

The timestamp is Unix epoch in the local timezone of the operation; the action is one of:

| Action | What it means |
|---|---|
| `commit` / `commit (initial)` | A new commit was made |
| `commit (amend)` | The HEAD commit was amended |
| `merge <ref>` | A merge commit was created |
| `rebase` / `rebase (start)` / `rebase (continue)` / `rebase (finish)` | Rebase phases |
| `rebase -i (squash)` / `rebase -i (fixup)` / `rebase -i (drop)` | Interactive rebase actions |
| `cherry-pick` | A cherry-pick |
| `revert` | A revert commit |
| `checkout: moving from <a> to <b>` | A checkout |
| `branch: Created from <ref>` | A branch was created |
| `branch: Reset to <ref>` | `git branch -f` or `git update-ref` |
| `pull` / `pull --rebase` | A pull |
| `push` (in the destination's reflog only) | A push landed |
| `reset` / `reset: moving to <ref>` | A reset |
| `update-ref -m '<msg>'` | An explicit ref update |
| `stash@{N}: ...` | Stash push (`WIP on <branch>`) or stash apply |

Per [Pro Git §10.4](https://git-scm.com/book/en/v2/Git-Internals-Maintenance-and-Data-Recovery), the reflog is the **canonical** durable record of ref operations. Branches deleted via `git branch -d` or `-D` survive in the reflog of the branch (gone if the branch ref is deleted) AND in `HEAD`'s reflog (still present until gc).

---

## 2. The Reflog GC Window

`git gc` (and the auto-gc that runs after many operations) prunes the reflog according to two settings:

| Setting | Default | What it prunes |
|---|---|---|
| `gc.reflogExpire` | `90.days` | Reachable reflog entries (i.e., the SHAs they point at are still in the object graph) |
| `gc.reflogExpireUnreachable` | `30.days` | Unreachable reflog entries (the SHAs they point at are no longer reachable from any ref) |

Per-ref overrides exist: `gc.reflogExpireBranch.<name>` etc. Some users set these aggressively low (some CI systems use `1.day`).

**Practical implications for the skill.**

- A branch deleted yesterday: its commits are still in the reflog (HEAD's reflog, the deleted-branch's now-gone reflog file, AND the object store).
- A branch deleted 31 days ago: HEAD's reflog still references it, but `gc.reflogExpireUnreachable=30.days` may have purged it; the commits may be unreachable and gc-eligible.
- A branch deleted 91 days ago: even reachable entries (referenced by another extant ref) may be expired.

The bundle survives all of these — a backup ref is a *reachable* ref, so its commits are reachable, so they're protected from gc-prune for `gc.reflogExpire` (90 days default). Per [Axiom 3](../SKILL.md#the-rationalization-kernel-universal-axioms): "plan for irreversibility first" — the bundle is the long-term safety net; the reflog is the short-term one.

---

## 3. Finding Lost Commits

When a branch is deleted *outside* the skill's bundle (CA-2 in [CONCURRENT-AGENT-FAILURE-MODES.md](CONCURRENT-AGENT-FAILURE-MODES.md)), the commits may be unreachable. Two tools find them:

### 3.1 `git fsck --unreachable --no-reflogs`

Reports objects not reachable from any ref OR reflog. Pure unreachable.

```bash
$ git fsck --unreachable --no-reflogs
unreachable commit 7e8a9b0c1d2e3f4...
unreachable blob 1a2b3c4d5e6f7g...
```

### 3.2 `git fsck --lost-found`

Writes unreachable commits to `.git/lost-found/commit/` and trees/blobs to `.git/lost-found/{tree,blob}/`:

```bash
$ git fsck --lost-found
$ ls .git/lost-found/commit/
7e8a9b0c1d2e3f4...
$ git show 7e8a9b0c1d2e3f4
commit 7e8a9b0c1d2e3f4...
Author: ...
Date:   ...
    feat: defensive null check
...
```

### 3.3 The skill's lost-found check

At Phase 0.5 and Phase 11, the skill runs:

```bash
git -C "$PROJECT" fsck --lost-found 2>&1 | grep -E '^dangling commit' > "$WS/lost_found.txt"
```

If `lost_found.txt` is non-empty AND any of those SHAs match `branches.tsv`'s SHAs (i.e., a branch from the inventory has a dangling parent commit):

```
LOST-FOUND CHECK:
  4 dangling commits found in lost-found.
  Of those, 2 are referenced by branches in branches.tsv (probably from before this run).
  This is informational; the bundle covers branches that exist NOW. Pre-existing dangling
  commits are recoverable via:
    git cherry-pick <sha>   # if you know what they were
    git log -g <branch>      # to see the reflog history
```

The skill does NOT auto-recover dangling commits — that's a forensic exercise the user drives.

---

## 4. Reconstructing a Branch's Full History

For a branch `feat/defensive-null-check`:

### 4.1 The reflog file (current branch state)

```bash
git -C "$PROJECT" reflog show feat/defensive-null-check
```

Shows every update to the branch's ref *while the branch existed* — commits, resets, rebases, force-pushes.

### 4.2 The full reflog'd history (commits + reflog actions)

```bash
git -C "$PROJECT" log -g feat/defensive-null-check
```

The `-g` flag treats the reflog as a commit walker. Shows each reflog entry as a commit-style record, including the action that produced it.

```
commit 7e8a9b0c1...
Reflog: feat/defensive-null-check@{0} (Alice <alice@example.com>)
Reflog message: commit (amend): tighten null guard
Author: Alice
Date:   2026-04-30 14:22:00 +0000

    feat: defensive null guard

commit 6d5e4f3a2...
Reflog: feat/defensive-null-check@{1} (Alice <alice@example.com>)
Reflog message: commit: defensive null guard
Author: Alice
Date:   2026-04-30 14:00:00 +0000

    feat: defensive null guard
```

This shows that the agent committed at 14:00 and amended 22 minutes later — useful forensic data.

### 4.3 HEAD's reflog (operations across branches)

```bash
git -C "$PROJECT" reflog show HEAD --date=iso
```

Shows the user's checkout history, which can establish *when* a branch was created or last touched even after it's been deleted.

---

## 5. Detecting Force-Pushes

A force-push rewrites a branch's history; the reflog records it. Detection:

```bash
git -C "$PROJECT" reflog show <branch> | head -5

7e8a9b0... HEAD@{0}: commit: feature complete
6d5e4f3... HEAD@{1}: commit: WIP
abc1234... HEAD@{2}: branch: Reset to origin/<branch>     ← force-push pulled in
0000000... HEAD@{3}: commit: prior work
```

The "Reset to" entry where the new SHA is **not** a descendant of the prior SHA indicates a force-push:

```bash
git -C "$PROJECT" merge-base --is-ancestor 0000000 abc1234
echo $?     # 1 = NOT an ancestor → force-push
```

The skill flags such branches in `branches.tsv:upstream_status` as `force-pushed-recently`. Triage handles them carefully — the local branch's commits may not be on origin, even if `git status` says "up to date."

---

## 6. Detecting Interactive Rebases

`git rebase -i` produces distinctive reflog entries:

```bash
git -C "$PROJECT" reflog show <branch>

abc1234... <branch>@{0}: rebase (finish): returning to refs/heads/<branch>
def5678... <branch>@{1}: rebase (pick): commit msg
ghi9012... <branch>@{2}: rebase (squash): commit msg
jkl3456... <branch>@{3}: rebase (drop): old commit msg          ← this commit was dropped
mno7890... <branch>@{4}: rebase (start): checkout HEAD~3
```

Forensic value:

- `rebase (drop)` entries reveal commits the agent **deliberately discarded** — those commits' content was likely unwanted. If a `divergent-refactor` row's reflog shows several `rebase (drop)` entries, the dropped commits are *evidence* of the agent's intent: they decided this code shouldn't ship. Don't try to recover dropped content unless the user explicitly asks.
- `rebase (squash)` / `rebase (fixup)` entries show that the agent combined commits — useful when you're trying to understand whether the branch's net diff is "the original commits" or "the squashed result."

---

## 7. Detecting Cherry-Pick Chains

Cherry-picks show in the reflog as `cherry-pick:` entries. Cross-referencing with the bundle's `commits.tsv` for branches:

```bash
git -C "$PROJECT" reflog show <branch> | grep cherry-pick

abc1234... <branch>@{2}: cherry-pick: feat: defensive null guard       ← cherry-picked
def5678... <branch>@{3}: cherry-pick: feat: length cap                 ← cherry-picked
```

If branch A's reflog shows that its commits were cherry-picked from branch B (the cherry-pick message preserves B's original commit message, often), then A is the **source** of B's content, not a duplicate. The triage verdict for A is **`superseded`** (one of the canonical 11 — branch A's content IS on canonical, just via B), with `applied-keeper-elsewhere` recorded in the evidence column as the *forensic-finding label* explaining HOW it became superseded. `applied-keeper-elsewhere` is NOT a separate verdict — the canonical taxonomy is the 11 in [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md); this label is metadata on the verdict.

The skill does this cross-reference at Phase 5:

```python
# pseudo-code for the triage worker
for branch in branches:
    reflog = git_reflog(branch)
    cherry_picks = parse_cherry_pick_entries(reflog)
    for cp in cherry_picks:
        original_branch = find_branch_with_message(cp.message, exclude=branch)
        if original_branch:
            mark_branch_relationship(branch, original_branch, "cherry-picked-from")
```

---

## 8. Reflog Mining as Triage Augmentation

The skill's most novel use of the reflog is **flipping verdicts** based on temporal evidence.

### 8.1 The "superseded vs. source" flip

A branch's `cherry_minus` count being high (per `git cherry -v`) is *normally* evidence that the branch is `superseded` — its content is on canonical. But the reflog can tell the story differently.

**Scenario.** Branch `agent-redact-pass-2` has `cherry_minus=8` (8 of its commits' patches match commits on canonical). Default verdict: `superseded`.

But check the reflog:

```bash
git log -g agent-redact-pass-2 --format='%H %gd %gs %ci'

7e8a9b0... agent-redact-pass-2@{0} commit: pass 2 finalized        2026-03-15
6d5e4f3... agent-redact-pass-2@{1} commit: redact regex tuned      2026-03-12
5c4d3e2... agent-redact-pass-2@{2} commit: redact for stripe       2026-03-10
4b3c2d1... agent-redact-pass-2@{3} branch: Created from main       2026-03-10
```

Now check canonical's history:

```bash
git log --oneline canonical -- src/util/logger.rs | head

abcdef0 (HEAD) feat: redact stripe keys                     2026-03-20  ← later than the branch
1234567 fix: typo                                            2026-03-18
```

The branch was created and committed-on **before** canonical's matching commits. `git cherry -v` matches by patch-id, not by timestamp; `cherry_minus=8` says "patch-id-equivalent commits exist on canonical." The reflog says "but the branch's commits came FIRST."

The branch is the **source**, not a duplicate of canonical. The canonical commits were probably squash-merged from this branch (or a successor) via PR. The verdict stays `superseded` (the canonical 11 are unchanged), but the row is annotated with the forensic-finding label `applied-keeper-elsewhere` to record HOW it became superseded — branch A was the *source* of the content, not a re-derivation. The cleanup decision is still "drop the branch" (its content is on canonical), but the apply log credits A as the origin so attribution stays correct.

The skill's triage worker performs this temporal check when `cherry_minus >= 3` AND confidence is below 0.95:

```python
def temporal_verdict_flip(branch):
    branch_first_commit_date = reflog_branch_creation_date(branch)
    matching_canonical_commits = cherry_minus_matches(branch)
    canonical_first_match_date = min(c.author_date for c in matching_canonical_commits)
    if branch_first_commit_date < canonical_first_match_date:
        # branch was the SOURCE — verdict stays `superseded` (canonical taxonomy unchanged),
        # but the row gets a forensic-finding label so attribution is preserved.
        return ("superseded", forensic_finding="applied-keeper-elsewhere")
    else:
        # branch came after; content was already on canonical
        return ("superseded", forensic_finding=None)
```

This single check has high accuracy and prevents the most common mis-classification ("source" labeled as "superseded").

### 8.2 The "divergent-refactor with intent" flip

A `divergent-refactor` row is one where the branch's signature diverges from canonical (Axiom 16). The default action is to surface to user. But the reflog can sharpen the surfacing.

**Scenario.** Branch `feature/connection-redesign` shows divergent-refactor: function `connect()` on the branch has signature `(Url, TlsConfig) -> Result<Conn>`; on canonical it's `(Url) -> Result<Conn>`.

Reflog inspection:

```bash
git log -g feature/connection-redesign --format='%H %gs %ci'

abc... commit: forced TLS in connect signature
def... commit: TLS optional via builder
ghi... rebase (drop): pre-TLS signature variant
jkl... commit: initial connect refactor
```

The `rebase (drop)` entry reveals the agent considered an alternative signature and dropped it. The current signature is the deliberate choice. This is rich evidence the agent had reasons; the surface-to-user message can be more focused:

```
divergent-refactor: feature/connection-redesign

The branch's connect() signature differs from canonical's. The reflog shows the
agent considered and dropped a 'pre-TLS signature variant' before settling on
'TLS optional via builder'. This appears intentional, not accidental.

Options:
  (a) Adopt as a refactor (rebase to canonical's import sites)
  (b) Skip and document the design tension in branches.tsv
  (c) Cherry-pick only the test additions; skip the signature change
```

The reflog turned a generic "surface to user" into a focused, evidence-backed surfacing.

---

## 9. Worked Example — The `agent-redact-pass-2` Branch

A concrete walkthrough of reflog forensics on a real(ish) scenario.

### 9.1 Setup

The user has branch `agent-redact-pass-2` flagged for triage. Initial Phase 5 worker output:

```
agent-redact-pass-2:
  cherry_plus: 0
  cherry_minus: 5
  signatures: redact_secrets/3, _redact_in_place/1
  → default verdict: superseded
```

5 of the branch's commits patch-match commits on canonical. Looks superseded.

### 9.2 Reflog inspection

```bash
$ git log -g agent-redact-pass-2 --format='%H %gd %gs %ci %an'

7e8a9b0c... agent-redact-pass-2@{0}   commit: redact_secrets v3                2026-04-30 Alice
6d5e4f3a... agent-redact-pass-2@{1}   reset: moving to HEAD~2                  2026-04-30 Alice
5c4d3e2b... agent-redact-pass-2@{2}   commit: redact_secrets v2                2026-04-29 Alice
4b3c2d1a... agent-redact-pass-2@{3}   commit: redact_secrets v1                2026-04-29 Alice
3a2b1c0d... agent-redact-pass-2@{4}   commit: hot_path_marker                  2026-04-29 Alice
2918273... agent-redact-pass-2@{5}   branch: Created from main                 2026-04-29 Alice
```

Forensic reading:

1. The branch was created on 2026-04-29 from main (line 5).
2. The agent committed v1, v2 of redact_secrets, plus a hot_path_marker (lines 4, 3, 2; the v1 was at @{4}, then a hot_path_marker at @{3}, then v2 at @{2}).

Wait — the order is wrong if I read top-to-bottom. Reflog order is **newest first** (`@{0}` is most recent). So the chronological order from the reflog is:

1. `@{5}` (oldest): branch created from main (2026-04-29)
2. `@{4}`: commit v1
3. `@{3}`: commit hot_path_marker
4. `@{2}`: commit v2
5. `@{1}`: reset --soft HEAD~2 (this discards the last two commits' diffs but keeps their staged content)
6. `@{0}` (newest): commit v3 (combines v2 + hot_path_marker into one)

The `reset: moving to HEAD~2` at `@{1}` is the key: the agent decided to combine the prior commits and started over with one consolidated commit. The branch tip at `@{0}` represents v3 = v1's defensive base + hot_path_marker's perf annotation + v2's expanded redaction set, all in one commit.

### 9.3 What this means for triage

The 5 patch-id matches on canonical (`cherry_minus=5`) probably correspond to the v1 + v2 + hot_path_marker commits — but the **current branch tip** is the consolidated v3. Patch-id matches against canonical are probably **partial** — canonical has the components but not the consolidation.

Inspect the tip's diff vs. merge-base:

```bash
$ git diff --stat $(git merge-base canonical agent-redact-pass-2)..agent-redact-pass-2
src/util/logger.rs        | +47 -3
tests/redact_test.rs      | +24 -0
```

47 lines added. Are those 47 lines on canonical?

```bash
$ git diff $(git merge-base canonical agent-redact-pass-2)..agent-redact-pass-2 -- src/util/logger.rs > branch_diff.patch
$ git apply --check --reverse branch_diff.patch     # would the diff revert cleanly?
error: patch failed: src/util/logger.rs:217
```

The diff doesn't apply cleanly in reverse to canonical. **The branch has content canonical doesn't have.** The 5 patch-id matches were the *prior* commits' fragments; the consolidated v3 has additional structure.

### 9.4 Verdict flip

```
Original: superseded (cherry_minus=5)
After reflog forensics:
  → partially-novel
  → strategy: ⇄ SPLIT-COMMITS-HUNKS — the v3 commit's net diff has novel hunks beyond what's on canonical
  → confidence: 0.84
```

Phase 8 cherry-picks the novel hunks (via the diff's hunk-by-hunk apply). Without the reflog inspection, the branch would have been deleted as superseded and 47 lines of real defensive code would have been lost.

### 9.5 Forensic note in the harmonization plan

```markdown
## Reflog forensic: agent-redact-pass-2

The branch was triaged as `superseded` initially (5 patch-id matches on canonical).
Reflog inspection revealed the branch's tip is a `git reset --soft HEAD~2` consolidation
commit that combines three prior commits (v1, hot_path_marker, v2) into one (v3). The
prior commits were squash-merged onto canonical via PR #4178 (2026-04-29) but the v3
consolidation includes additional structure not on canonical.

Verdict: partially-novel (split-apply on the novel hunks of v3).
```

This forensic note lands in the handoff report; the user understands *why* this branch was treated specially.

---

## 10. Reflog Limits

The reflog is powerful but not omniscient.

| Limit | Implication |
|---|---|
| 30/90-day default gc window | Long-abandoned branches' reflogs may be expired; the skill can't reconstruct intent from the reflog alone |
| Reflog only records local operations | A force-push by another developer to a shared branch is in *their* reflog, not yours |
| Some hooks suppress reflog entries (`GIT_REFLOG_ACTION` empty) | Edge case; rare but real |
| `git update-ref --no-deref` skips the reflog | Used by some tooling; bundles created during such operations may be invisible |
| Reflog can't tell you **why** the agent did something | Only what they did; intent comes from cass / beads / commit messages |
| Squash-merges on canonical lose source attribution | The squash-merge commit's reflog says "commit: squash-merge of <PR-1234>" but doesn't expose the source branch's full history |

The skill triangulates the reflog with cass + beads + `gh` PR data per [TIMELINE-RECONSTRUCTION.md](TIMELINE-RECONSTRUCTION.md). The reflog is the strongest single source but never the only one.

---

## 11. Reflog-Aware Recovery Recipes

The recovery recipes in [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md) cover the bundle-based path. Reflog-based recovery is the fallback when the bundle is absent or corrupt.

### 11.1 "I deleted a branch and the bundle is gone but it was last week"

```bash
# Find the branch in HEAD's reflog:
git reflog show HEAD | grep -F "checkout: moving from <branch>" | head -1
# 7e8a9b0c... HEAD@{47}: checkout: moving from <branch> to main

# That commit is the branch's last tip:
git branch <branch> 7e8a9b0c
```

Works if the branch was deleted within the gc window (default 30 days for unreachable, 90 for reachable).

### 11.2 "The reflog is gone too"

Last resort: `git fsck --lost-found` and grep for the commit message.

```bash
git fsck --lost-found 2>&1 | grep '^dangling commit' | awk '{print $3}' | \
  while read sha; do
    git log -1 --format='%H %s' "$sha"
  done | grep -i 'defensive null'
```

The skill never relies on this; it's a user-facing recipe in the handoff report's "Worst-case recovery" section.

---

## 12. Cross-References

- Standard timeline reconstruction: [TIMELINE-RECONSTRUCTION.md](TIMELINE-RECONSTRUCTION.md)
- Cass mining for prior agent context: [CASS-MINING.md](CASS-MINING.md)
- Recovery recipes (bundle-based): [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md)
- Catastrophic recovery (gc-pruned, lost bundles): [ADVANCED-RECOVERY.md](ADVANCED-RECOVERY.md)
- Concurrent-agent failures (CA-2 — out-of-band branch deletion): [CONCURRENT-AGENT-FAILURE-MODES.md](CONCURRENT-AGENT-FAILURE-MODES.md#ca-2--concurrent-agent-deletes-a-branch-mid-run-that-was-in-branchestsv)
- The `git cherry -v` patch-id detector and Axiom 16: [SKILL.md](../SKILL.md#the-rationalization-kernel-universal-axioms)
- Pro Git §10.4 (data recovery via reflog): https://git-scm.com/book/en/v2/Git-Internals-Maintenance-and-Data-Recovery
