# Timeline Reconstruction — Using Reflog and History to Understand Stashes

Some stashes are puzzles: orphan parents, deleted branches, mysterious dates. The reflog is the chronological diary that lets you reconstruct what happened.

---

## The reflog basics

```bash
git reflog show --all                    # all reflog entries across all refs
git reflog show <branch>                 # one branch's history
git reflog show stash                    # the stash log specifically
git reflog show HEAD --since=2.weeks     # time-bounded
git log --all --reflog --oneline | head  # all commits including unreachable-from-tips
```

The reflog has a default expiry (90 days for reachable, 30 days for unreachable). Past those windows, entries fall out and the corresponding commits become candidates for `git gc`.

---

## Stash reflog specifically

```bash
git reflog show stash
# stash@{0}: On main: other-agent-broken
# stash@{1}: On main: wip-safe-div
# ...

git reflog show stash --format='%h %gd %gs'
# 317a0db stash@{0} On main: other-agent-broken
# ...
```

This is exactly what the inventory captures. But the reflog has TIMESTAMPS that the live `stash list` doesn't show prominently:

```bash
git reflog show stash --format='%h %gd %ct %gs' | head
# 317a0db stash@{0} 1746568285 On main: other-agent-broken
# 9291992 stash@{1} 1746568284 On main: wip-safe-div
```

`%ct` is the committer Unix timestamp — useful for ordering and filtering.

---

## Reconstructing intent for an orphan-parent stash

Scenario: stash@{N}'s parent SHA isn't reachable from any branch.

```bash
PARENT=$(git rev-parse stash@{N}^)

# 1. Was the parent ever on a branch?
git branch -a --contains "$PARENT"
# If empty: the parent's branch was deleted

# 2. Is the parent in the reflog?
git reflog --all | grep "$(git rev-parse --short=7 $PARENT)"
# If found: the entry shows when the branch existed

# 3. What does the parent commit say?
git log -1 --format='%H%n%ci%n%an%n%s%n%b' "$PARENT"
# Subject + date + author often reveal what the developer was doing

# 4. What happened around the parent's time?
git log --all --since="$(git log -1 --format=%ci $PARENT) -1 day" \
                --until="$(git log -1 --format=%ci $PARENT) +7 days" \
                --oneline | head
# Surrounding activity reveals if the work continued or was abandoned
```

This often shows: "the developer made a branch, did some work, made a stash, switched away, and the branch was deleted later." The stash is then the only surviving witness to that work.

---

## Reconstructing supersession from history

Scenario: triage rubric says `superseded` but you want to verify.

```bash
# Find when the symbol first appeared on main
git log --all -S 'lock_until' --oneline -- src/mutex.rs | head
# Returns the commit that introduced (or significantly modified) `lock_until`
```

`-S '<string>'` is the "pickaxe" — finds commits that change the count of a string. Powerful for tracking when a symbol was introduced or removed.

```bash
# Find when the original stash's parent was reachable
PARENT_SHA=$(git rev-parse stash@{N}^)
git log --all --reflog -1 "$PARENT_SHA"
# If the commit is still in reflog, you get its history
```

---

## Detecting force-pushes that orphaned stashes

A force-push to origin can rewrite history; stashes made on the old history are now orphans.

```bash
# Compare local reflog to origin
git reflog show origin/<primary>  # local tracking history
git fetch && git reflog show origin/<primary>  # after fetch
```

If the reflog shows a non-fast-forward update on `origin/<primary>`, history was rewritten. Stashes made before the rewrite are orphans.

The recovery is unaffected (the stash commits still exist locally), but the bundle's `parent_sha` may be unreachable from any branch.

---

## Reconstructing the developer's session

```bash
# Reflog ordered by time
git reflog --date=iso --all | sort -k4 | head -50

# Activity in a specific time window
git reflog --all --since='2026-04-29' --until='2026-04-30' --date=iso

# Who did what when
for ref in $(git reflog show stash --format='%gd' | head); do
  date=$(git log -1 --format='%ci' "$ref")
  msg=$(git log -1 --format='%s' "$ref")
  echo "$date  $ref  $msg"
done | sort
```

This produces a session-level view: which stashes were created in succession, suggesting they're related (e.g., "agent X took on BACK-1742, made 5 attempts in 2 hours, stashed each one before trying a different approach").

---

## The Forensic mode subagent

The forensic mode (see MODES-OF-REASONING.md §FORENSIC) uses these techniques to reconstruct intent. The subagent:

1. Reads the stash's diff, message, parent SHA
2. Runs `git log --since/--until` to see surrounding activity
3. Runs `git log -S '<key-symbol>'` to find when the symbol existed elsewhere
4. Runs `git reflog --all --since=...` to see session activity
5. Runs `br show <ticket-id>` if the message references a ticket
6. Runs `cass search <query>` if available, for prior agent context
7. Synthesizes a reconstruction: "here's what I think the developer was doing, here's why I think it"

The output is `<workspace>/forensic_<NNN>.md`:

```markdown
# Forensic reconstruction: stash@{34}

## Diff fingerprint
- Functions: defensive_ok_packet_length_cap, parse_ok_packet_safe
- Tests: test_ok_packet_length_overflow_returns_err
- Files: src/mysql/protocol.rs, tests/protocol_test.rs

## Stash metadata
- sha: 8a3d2c9
- parent: 7f3a1b8
- date: 2026-04-29 14:22:11
- author: agent-cc-12

## Parent's reachability
The parent 7f3a1b8 IS reachable from origin/main today. So the stash was made
on top of the then-tip-of-main, and the work was synchronous with master.

## Surrounding activity
git log --since='2026-04-29 12:00' --until='2026-04-29 18:00' shows:
- 14:18: commit 8a3d2c9 "WIP: experiment with packet validation" (this stash's parent)
- 14:22: stash@{34} created (this stash)
- 14:35: agent-cc-12 made commit 6c2d4e3 "feat: add OK-packet validation"
  on branch back-1742-validation
- 17:10: branch back-1742-validation deleted (presumably merged or abandoned)

## Beads context
br show BACK-1742 returns:
- Title: "MySQL OK-packet validation"
- Status: closed; closed by PR #234 on 2026-04-30
- PR #234 description: "Adds parse_ok_packet validation; drops legacy 'safe' suffix"

## Reconstruction

The developer (agent-cc-12) was working on BACK-1742. They wrote two
attempts (the stashed one and the eventual landing commit 6c2d4e3). The
landing happened 13 minutes after the stash, so the stash was discarded
in favor of a slightly different approach.

Looking at the diff: the stash adds a SEPARATE function
defensive_ok_packet_length_cap, which the landing version doesn't have.
The landing's parse_ok_packet does basic validation but does NOT cap
payload length defensively. This is a real gap.

## Recommendation

Recover the defensive cap. It's genuinely additive over what landed.
Confidence: 0.92.
```

---

## Practical applications

### Identifying garbage families with high confidence

```bash
# Find all stashes whose parents are unreachable
for n in $(awk -F'\t' 'NR > 1 {print $1}' inventory.tsv); do
  parent=$(git rev-parse "stash@{$n}^")
  if ! git branch -a --contains "$parent" >/dev/null 2>&1; then
    echo "$n: orphan parent $parent"
  fi
done
```

Orphan-parent stashes are more likely to be from deleted experimental branches and may skew toward `garbage` or `novel-but-stale`.

### Detecting agent-swarm patterns

```bash
# Cluster stashes by author + 1-hour windows
awk -F'\t' 'NR > 1 {
  ts = mktime(gensub(/[-T:Z+]/, " ", "g", $5));
  bucket = int(ts / 3600);
  print bucket "\t" $6 "\t" $1
}' inventory.tsv | sort | awk '{counts[$1 "\t" $2]++} END {for (k in counts) if (counts[k] > 3) print k, counts[k]}'
```

A bucket with >3 stashes from the same author in 1 hour suggests an agent burst — probably exploring alternative implementations of the same task. Most are likely `superseded-by-newer-stash`.

### Identifying landed-elsewhere

```bash
# For each fingerprint symbol, find the commit that introduced it on main
git log --all -S "$SYMBOL" --oneline -- "$EXPECTED_PATH" | head -5
```

If a symbol was introduced on main 2 days AFTER the stash was made, the stash is `superseded` and the developer's polished version is the landing commit.

If a symbol was introduced 3 weeks BEFORE the stash, the stash might be a re-implementation attempt — surface to user (could be a regression or a more robust version).

---

## Anti-Patterns in Timeline Reconstruction

| ✗ | Why |
|---|-----|
| Trusting timestamps without verifying timezone | Reflog %ci is committer's local time; %ct is UNIX timestamp; use %ct for comparisons |
| Assuming reflog is complete | Default 90-day expiry; older entries may be gone |
| Reconstruction without surfacing | The agent's reconstruction is a *hypothesis*; let the user confirm |
| Reflog scraping that's slow on large repos | Time-bound the search (`--since=...`) |
| Reading too much into solo timestamps | A single stash with no surrounding context is hard to reconstruct; surface to user |
