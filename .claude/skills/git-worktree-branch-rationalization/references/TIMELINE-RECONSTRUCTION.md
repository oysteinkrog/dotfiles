# Timeline Reconstruction — Forensic Intent Reconstruction From Reflog and History

Some branches are puzzles: their name doesn't say what they do, their commit messages are vague, their author isn't around to ask. The reflog plus surrounding git history is the chronological diary that lets you reconstruct what the branch's author was trying to do, which often determines what to do with the branch.

Adapted from [git-stash-janitor's TIMELINE-RECONSTRUCTION.md](../../git-stash-janitor/references/TIMELINE-RECONSTRUCTION.md). Branches give you *more* forensic surface than stashes (multiple commits, possibly multiple authors, possibly an upstream-tracking history of force-pushes), so the reconstruction is correspondingly richer. This file is most useful for `novel-but-stale` and `divergent-refactor` verdicts where understanding intent is the precondition for choosing what to do.

> **Why:** Per [SKILL.md "Operator Library"](../SKILL.md#operator-library--the-cognitive-moves) — `✦ FINGERPRINT` and `◐ VERIFY-ON-CANONICAL` give you the *what*; reconstruction gives you the *why*. The why determines whether a `novel-but-stale` branch is salvageable (port the intent through canonical's refactor) or genuinely dead (the intent is no longer applicable). [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md) §"`novel-but-stale`" lists "manual decision (default skip with note)" as the default action precisely because *intent is required* to decide.

---

## The reflog basics for branches

```bash
# Per-branch ref movement history
git reflog show <branch>

# Per-branch with timestamps
git reflog show <branch> --format='%h %gd %ct %gs' | head

# Per-branch upstream history (force-push detection)
git reflog show <branch>@{upstream} 2>&1

# All-branches with reachability
git log --all --source --remotes --reflog --oneline --decorate=short | head -50

# Time-bounded
git reflog --date=iso --all --since='2026-04-01' --until='2026-04-30'
```

The reflog has a default expiry (90 days for reachable, 30 days for unreachable). Past those windows, entries fall out and the corresponding commits become candidates for `git gc`. This is why backup refs (`refs/branch-rationalization-backup/<slug>`) are created at Phase 3 — they pin commits permanently.

`%gd` is the reflog selector (`<branch>@{N}`); `%gs` is the reflog message; `%ct` is the committer Unix timestamp (use this for comparisons, not `%ci` which is human-readable local time).

---

## Reconstructing intent for an unknown branch

Scenario: a branch named `agent-cleanup-pass-3` exists with a few commits. The fingerprint shows it adds a defensive null-check at `src/util/logger.rs:42` whose intent isn't obvious from the diff alone. You need to decide between `superseded` (a polished version landed) and `novel-but-stale` (the intent is real but the surface form is obsolete) before deciding what to do.

```bash
BRANCH=agent-cleanup-pass-3
MERGE_BASE=$(git merge-base "$CANONICAL" "$BRANCH")

# 1. When was the branch created?
git reflog show "$BRANCH" --format='%h %gd %ct %gs' | tail -1
# (last entry chronologically is the creation; %ct gives Unix timestamp)

# 2. What activity surrounded the branch's creation?
CREATION_TS=$(git reflog show "$BRANCH" --format='%ct' | tail -1)
git log --all --since="@$((CREATION_TS - 3600))" --until="@$((CREATION_TS + 86400))" \
        --pretty=format:'%h %ci %an %s' \
        --no-merges \
        | head -30
# Gives you: who else was committing in this window, on which branches

# 3. Has the branch's tip moved since creation? (Force-push? Rebases?)
git reflog show "$BRANCH" --format='%h %gd %ct %gs'
# Multiple entries with different SHAs at the tip = the branch was force-pushed
# or rebased; the older SHAs may have content the newer tip doesn't

# 4. What's the upstream-tracking story?
git config --get branch."$BRANCH".remote
git config --get branch."$BRANCH".merge
git reflog show "$BRANCH"@{upstream} 2>&1 | head
# If the upstream was force-pushed, this shows when

# 5. What commits are on this branch but not on canonical?
git log --oneline "$MERGE_BASE..$BRANCH"

# 6. For each unique commit, what does the message say?
git log "$MERGE_BASE..$BRANCH" --format='%h%n%ci%n%an%n%s%n%b%n---'

# 7. What did the author think they were doing? (subject + body)
# Subjects + bodies often reveal the developer's working hypothesis at the time

# 8. What's the file's history on canonical around the same time?
git log --all --since="@$((CREATION_TS - 7*86400))" --until="@$((CREATION_TS + 30*86400))" \
        --oneline -- src/util/logger.rs
# Did canonical's version drift while this branch was working?
```

Combine the outputs into a forensic narrative. The narrative often shows: "the developer made a branch, did some work, switched to a higher-priority task, the branch sat; meanwhile canonical landed PR #234 which addresses *most but not all* of the same concern."

---

## Cross-referencing with the project's other systems

Beyond pure git data, three external sources help reconstruct intent:

### Beads (`br`)

```bash
# What ticket(s) did the developer reference?
git log --format='%s%n%b' "$MERGE_BASE..$BRANCH" | grep -oE '(BACK|JIRA|ENG)-[0-9]+|br-[a-z0-9]+' | sort -u

# For each, what's the ticket's history?
br show BACK-1742
br history BACK-1742
```

The beads issue often has the original task description; the ticket's status (open / in-progress / closed-by-PR-#234) tells you whether the work was completed elsewhere.

### CASS (`cass`)

```bash
# Mine prior agent sessions for this branch
cass search "$BRANCH"
cass search "$(git log -1 --format=%s "$BRANCH")"
cass search BACK-1742
```

CASS sessions often capture the agent's reasoning at the moment they made the branch — what hypothesis they were testing, what they tried, why they switched away. The session log is the closest thing to "ask the developer" when the developer is no longer available.

### GitHub (`gh`)

```bash
# Was there a PR that intended to land this branch?
gh pr list --state all --search "$BRANCH"

# Was there a closed PR with similar content?
gh pr list --state closed --search "BACK-1742"
```

A closed PR linked to a different branch name often is the polished version that landed instead of this one.

---

## Worked example: `agent-cleanup-pass-3`

Setup: an `agent-cleanup-pass-3` branch exists with 4 commits. The diff shows a defensive null-check at `src/util/logger.rs:42` plus a redact_secrets() call. Triage's first pass classified it as `unknown` because the fingerprint (`fn redact_secrets`) IS on canonical, but at a different file path (`src/security/redact.rs:88`) and with a slightly different signature.

The agent runs the reconstruction:

### Step 1: When was the branch created?

```bash
$ git reflog show agent-cleanup-pass-3 --format='%h %gd %ct %gs' | tail -1
b3c4d5e agent-cleanup-pass-3@{4} 1745683200 branch: Created from master
```

Unix timestamp 1745683200 = 2026-04-26 14:40:00 UTC.

### Step 2: What activity surrounded the creation?

```bash
$ git log --all --since='2026-04-26 13:00' --until='2026-04-27 14:00' \
        --pretty=format:'%h %ci %an %s' --no-merges | head -20

a1b2c3d 2026-04-26 14:35:12 agent-cc-12 [security-audit] open BACK-1742: hardening logger
b3c4d5e 2026-04-26 14:40:00 agent-cc-12 [agent-cleanup-pass-3] WIP: add null-check
6c2d4e3 2026-04-26 14:48:33 agent-cc-12 [agent-cleanup-pass-3] WIP: add redact_secrets
9f3a2d1 2026-04-26 15:02:15 agent-cc-12 [agent-cleanup-pass-3] WIP: tests for null + redact
2f8e1a4 2026-04-26 15:04:07 agent-cc-12 [agent-cleanup-pass-3] WIP: passes locally
[GAP — agent-cc-12 silent for 4 days]
e7d6c5b 2026-04-30 09:12:33 user-jeff [main] PR #234: security-audit logger hardening
```

Reading: agent-cc-12 made `agent-cleanup-pass-3` at 14:40 UTC on 2026-04-26 as part of an active security-audit task; committed for ~25 minutes; then went silent for 4 days. On 2026-04-30, user-jeff merged PR #234 which is the *polished* security-audit work, but from a different branch.

### Step 3: What's in the branch?

```bash
$ git log master..agent-cleanup-pass-3 --format='%h %ci %s%n%b'
b3c4d5e 2026-04-26 14:40:00 WIP: add null-check
        Logger::log() can be called with msg=None from FFI; this null-check
        prevents the deref panic.
6c2d4e3 2026-04-26 14:48:33 WIP: add redact_secrets
9f3a2d1 2026-04-26 15:02:15 WIP: tests for null + redact
2f8e1a4 2026-04-26 15:04:07 WIP: passes locally
```

The first commit's body explains the hypothesis: defensive null-check for FFI callers.

### Step 4: What did PR #234 (the polished version) do?

```bash
$ git log -1 --format='%h%n%ci%n%an%n%s%n%b' e7d6c5b
e7d6c5b
2026-04-30 09:12:33
user-jeff
PR #234: security-audit logger hardening

Closes BACK-1742. Adds:
- redact_secrets() filter (now in src/security/redact.rs to keep
  src/util/ focused on plumbing)
- length cap at 4 KiB
- (no null-arg guard; FFI surface uses NonNullPtr now)

Reviewed-by: agent-cod-04
```

So PR #234 added `redact_secrets` (at a different path) and the length-cap, but explicitly *did not* add the null-arg guard because the FFI surface was changed to use `NonNullPtr` instead.

### Step 5: Is the FFI surface change real?

```bash
$ git grep -nE 'NonNullPtr.*msg' master -- '**/*.rs'
src/ffi/log_bridge.rs:42:    pub fn log_ffi(msg: NonNullPtr<u8>, ...) { ... }
```

Yes — canonical's FFI now uses `NonNullPtr`, so the null-arg guard at the Rust-internal `Logger::log()` is unreachable from FFI by construction.

### Step 6: But is it unreachable from *all* paths?

```bash
$ git grep -n 'Logger::log' master -- 'src/**/*.rs' | head
src/ffi/log_bridge.rs:48:    Logger::log(...)
src/api/handler.rs:120:    Logger::log(...)        ← from web handlers
src/cron/scheduler.rs:88:  Logger::log(...)        ← from scheduled tasks
```

Two non-FFI callers (`api/handler.rs`, `cron/scheduler.rs`). Could either pass null? Reading further:

```bash
$ git show master:src/api/handler.rs | sed -n '115,125p'
let msg = req.body().to_string();
Logger::log(LogLevel::Info, &msg);  // msg is owned String, can't be null
```

```bash
$ git show master:src/cron/scheduler.rs | sed -n '85,92p'
if let Some(msg) = task.scheduled_msg() {
    Logger::log(LogLevel::Debug, &msg);  // already null-guarded by `if let Some`
}
```

Both non-FFI callers have null-impossibility by Rust's type system. So PR #234's choice to *not* add a null-arg guard is correct.

### Step 7: Reconstruction

agent-cc-12 was working on BACK-1742 security-audit. They started `agent-cleanup-pass-3` 22 minutes after opening the ticket, made 4 WIP commits adding a defensive null-check + redact_secrets + tests, then went silent (likely paged onto something else or hit a context limit). 4 days later, user-jeff manually completed BACK-1742 via PR #234 with a *better* design choice: change the FFI surface to `NonNullPtr<u8>` so the null-check is unnecessary, and put `redact_secrets` in `src/security/` for cleaner module structure.

The branch's intent (defensive hardening) IS in canonical. The branch's surface form (null-check on `Logger::log()`) IS NOT in canonical and *should not* be — adding it now would be redundant with `NonNullPtr<u8>`.

### Step 8: Verdict

The branch is `superseded` — not by a same-named branch, but by PR #234 which made a different design choice that obsoletes the branch's specific approach. The reconstruction's value is *confidence*: without the timeline, the verdict was `unknown`; with it, the verdict is `superseded` with confidence 0.95.

The triage row:

```
agent-cleanup-pass-3  superseded  0.95  reconstruction: PR #234 (sha e7d6c5b) closes BACK-1742 with NonNullPtr<u8> FFI design that obsoletes branch's null-check; redact_secrets relocated to src/security/redact.rs:88; verified non-FFI callers cannot pass null  skip
```

Recorded forensic file: `<workspace>/forensic/agent-cleanup-pass-3.md` containing the full reconstruction. The user's review at Phase 6 has the file:line citations and the reasoning chain; the verdict is auditable.

---

## Cross-referencing the bundle for force-push detection

A common failure mode: a branch's upstream was force-pushed, so the local branch has commits no one else can see, but the metadata makes it look like the branch is up-to-date with origin.

```bash
# Local upstream-tracking
git config --get branch."$BRANCH".remote      # e.g., origin
git config --get branch."$BRANCH".merge       # e.g., refs/heads/feature/foo

# Compare local tip to remote tip
LOCAL_TIP=$(git rev-parse "$BRANCH")
REMOTE_TIP=$(git rev-parse "origin/$(git config --get branch."$BRANCH".merge | sed 's|refs/heads/||')")

if [[ "$LOCAL_TIP" != "$REMOTE_TIP" ]]; then
    # Are local commits ancestors of remote? (Normal: remote is ahead)
    if git merge-base --is-ancestor "$LOCAL_TIP" "$REMOTE_TIP"; then
        echo "Local is behind remote (normal; pull would fast-forward)"
    elif git merge-base --is-ancestor "$REMOTE_TIP" "$LOCAL_TIP"; then
        echo "Local is ahead of remote (normal; user has unpushed work)"
    else
        echo "DIVERGENT — likely force-push on remote; local has unique commits"
    fi
fi
```

When divergent, the local-only commits are `novel-but-stale` candidates: their content existed at one point on the upstream but the upstream rewrote history away from them. The local tip is the only surviving witness.

### Reflog confirms force-push timing

```bash
git reflog show "$BRANCH"@{upstream} 2>&1 | head -10
# fea_branch@{0}: fetch origin: forced-update
# fea_branch@{1}: fetch origin: fast-forward
# ...
```

The "forced-update" entry in the upstream-tracking reflog timestamps when the force-push happened. Use this in the citation (Form H per [EVIDENCE-CITATIONS.md](EVIDENCE-CITATIONS.md#form-h-reflog-force-push-detection)).

---

## Detecting agent-swarm patterns from the timeline

When 5+ branches share a name prefix and creation timestamps within a short window, the timeline reveals an agent burst:

```bash
# Cluster branches by name-prefix and 1-hour creation windows
for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/agent-*); do
    ts=$(git reflog show "$branch" --format='%ct' 2>/dev/null | tail -1)
    bucket=$((ts / 3600))
    prefix=$(echo "$branch" | sed 's/-attempt-[0-9]*$//; s/-pass-[0-9]*$//; s/-try-[0-9]*$//')
    echo "$bucket $prefix $branch"
done | sort | awk '{counts[$1 "_" $2]++; entries[$1 "_" $2] = entries[$1 "_" $2] " " $3} END { for (k in counts) if (counts[k] >= 3) print counts[k] " " k ":" entries[k] }'
```

A cluster of 5 `agent-mysql-fix-2026-04-29-attempt-{1..5}` all created in a 1-hour window is an agent burst — the swarm spawned 5 parallel attempts at the same task. Most are likely `superseded-by-newer-branch`; only one (or none) of them landed.

Per [BRANCH-WORKTREE-SMELLS.md §B1](BRANCH-WORKTREE-SMELLS.md#smell-b1-agent-task-date-attempt-n--almost-always-garbage), agent burst patterns are strong-prior `garbage` candidates; the timeline reconstruction adds confidence by *proving* the burst structure.

---

## Identifying when work landed elsewhere

For each fingerprint symbol introduced by a branch, find the commit that introduced it on canonical (if any):

```bash
SYMBOL=cap_payload_length
git log --all -S "$SYMBOL" --oneline -- "$EXPECTED_PATH" | head -5
```

`-S '<string>'` is the "pickaxe" — finds commits that change the count of a string. Powerful for tracking when a symbol was introduced on canonical.

If the symbol appears on canonical with a creation date *after* the branch's creation, the polished version landed elsewhere → `superseded`.

If the symbol appears with a creation date *before* the branch's creation, the branch may be a re-implementation attempt — surface to user (could be a regression of an earlier design that was already replaced, OR a more robust version that should harmonize).

If the symbol doesn't appear on canonical at all → confirms the branch's content is genuinely novel.

---

## The forensic-mode subagent (Phase 5 escalation)

Comprehensive and Council modes spawn a `subagents/forensic-investigator.md` subagent for any row that triage's first pass classifies as `unknown` or where the reconstruction is needed for a confident verdict on `novel-but-stale` or `divergent-refactor`. The subagent:

1. Reads the branch's diff (from the bundle), the branch's commit messages (`git log master..<branch>`), the branch's reflog (`git reflog show <branch>`).
2. Runs the surrounding-activity query (`git log --all --since/--until` around the branch's creation time).
3. Runs the symbol-pickaxe query for each fingerprint symbol.
4. Cross-references with `br show <ticket-id>` if the branch references a ticket.
5. Cross-references with `cass search <query>` if available, for prior agent context.
6. Cross-references with `gh pr list --state all --search <branch>` if `gh` is authenticated.
7. Synthesizes a reconstruction: "here's what I think the developer was doing, here's why I think it, here's the verdict it implies."

Output: `<workspace>/forensic/<branch-slug>.md` containing the full reconstruction. The user's Phase 6 review has access to this file; the verdict in `triage.tsv` is auditable end-to-end.

---

## Anti-patterns in timeline reconstruction

| Anti-pattern | Why bad |
|--------------|---------|
| Trusting timestamps without verifying timezone | Reflog `%ci` is committer's local time; `%ct` is UNIX timestamp; use `%ct` for comparisons across machines |
| Assuming reflog is complete | Default 90-day expiry for reachable, 30-day for unreachable; older entries may be gone — the bundle is permanent, the reflog isn't |
| Reconstruction without surfacing | The agent's reconstruction is a *hypothesis*; let the user confirm at Phase 6, especially for `novel-but-stale` |
| Reflog scraping that's slow on huge repos | Time-bound the search (`--since=<timestamp>`); don't scrape all-time on a kernel-sized repo |
| Reading too much into solo timestamps | A single branch with no surrounding context is hard to reconstruct; surface to user with the partial reconstruction and ask for context |
| Conflating branch creation with branch tip date | The `creation_ts` is from the *first* reflog entry; the tip date is from the *last* commit; reconstruction needs both |
| Citing `git log --all` results without filtering by author | When the project has many committers, "surrounding activity" is noisy; filter by the branch's author or by file-paths the branch touches |
| Assuming the branch's author is still around | They often aren't; the reconstruction is for a future reader who needs to act WITHOUT the original author's input |

---

## Quick-reference: reconstruction commands

```bash
# Branch creation timestamp
git reflog show "$BRANCH" --format='%ct' | tail -1

# Surrounding activity (1-hour before, 1-day after)
TS=$(git reflog show "$BRANCH" --format='%ct' | tail -1)
git log --all --since="@$((TS-3600))" --until="@$((TS+86400))" --oneline --no-merges

# Force-push detection on upstream
git reflog show "$BRANCH"@{upstream} 2>&1 | grep -i 'forced'

# Symbol pickaxe
git log --all -S "$SYMBOL" --oneline -- "$PATH"

# Branch-only commits
git log --oneline "$(git merge-base "$CANONICAL" "$BRANCH")".."$BRANCH"

# Beads context
br show "$TICKET_ID"

# CASS context
cass search "$BRANCH"

# GitHub context
gh pr list --state all --search "$BRANCH"
```

These nine commands constitute ~80% of timeline reconstruction. The rest is reading carefully and writing the narrative.
