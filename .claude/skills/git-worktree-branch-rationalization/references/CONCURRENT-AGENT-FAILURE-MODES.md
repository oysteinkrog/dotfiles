# Concurrent-Agent Failure Modes — How Swarms Break a Rationalization Run

[FAILURE-MODES.md](FAILURE-MODES.md) catalogs git-mechanic failures (locked worktrees, format-patch caveats, refusal-on-unmerged, etc.). [INCIDENT-PLAYBOOK.md](INCIDENT-PLAYBOOK.md) walks per-incident triage. This file fills a different gap: every way **a concurrent agent's actions** can break a rationalization mid-run, with the detection signal, immediate triage, recovery path, and prevention. Cass-mined sessions repeatedly surface "autostash resulted in merge conflicts requiring manual resolution", "active agents kept modifying files while I was working", and "two competing ad-hoc approaches"; the failure modes below are the operational form of those scars.

> **Why a separate reference?** [MULTI-AGENT-COORDINATION.md](MULTI-AGENT-COORDINATION.md) is the runtime *protocol* — what reservations to acquire, how to heartbeat, when to pause. This file is the *failure catalog* — what breaks when the protocol's contract is partially or fully violated by a concurrent agent (or by chaos-monkey reality). Read MULTI-AGENT-COORDINATION first; this file second when something has already gone sideways.

The CA-prefix is for "Concurrent-Agent" failure modes. They compose with the F-prefix (git-mechanic) failures and the I-prefix (incident) playbook entries.

---

## CA-1 — Concurrent agent creates a NEW branch mid-run

**Scenario.** Phase 5 triage workers have already built `branches.tsv` with N rows. Halfway through Phase 8, a concurrent agent (say, an NTM pane writing a hotfix) creates a new branch `agent-cc-21-emergency-fix`. `git branch | wc -l` is now N+1. The rationalization run never saw this branch and has no triage row, no backup ref, no bundle entry for it.

**Detection signal.**

```bash
# scripts/apply-keeper.sh and scripts/drop-retire-confirmed.sh both run a count drift check
# at the top of every iteration:
current=$(git -C "$PROJECT" branch | wc -l)
phase2=$(awk 'NR>1' "$WS/branches.tsv" | wc -l)
[ "$current" -eq "$((phase2+1))" ] && echo "BRANCH ADDED: drift +1"   # mid-run new branch
```

Phase 0.5's count baseline + Phase 2's `branches.tsv` make the drift unambiguous.

**Immediate triage.**

1. Halt Phase 8 / Phase 10 immediately (do **not** continue applying or deleting on stale inventory).
2. `git branch -vv | grep -F -v -f <(awk -F'\t' 'NR>1{print $1}' "$WS/branches.tsv")` to identify the new branch(es).
3. Check whether the new branch is in `agent-mail.list_active_agents()`'s reservation list — that tells you whether it's a coordinated peer or a runaway.

**Recovery.**

- The new branch is **not in scope** for this rationalization run. Two options:
  - (a) Defer to next run: leave the new branch alone; Phase 11 handoff explicitly notes "branch `<name>` was created mid-run and was not triaged".
  - (b) Re-run Phase 2 inventory + Phase 3 bundle (incremental — only the new branch needs a backup ref + bundle entry); add the row to `branches.tsv`, triage it, then continue Phase 8 / 10 with the augmented plan.
- The bundle on disk is still valid for every entry it covers; re-bundling only the delta is fine.

**Prevention.**

- Pre-run handshake (Phase 0.5) registers an exclusive reservation on `.git/refs/heads/**`. A concurrent agent attempting to `git branch <new>` against that reservation gets `FILE_RESERVATION_CONFLICT` and surfaces to its own user instead of silently creating the branch.
- Per [MULTI-AGENT-COORDINATION.md § 2.2](MULTI-AGENT-COORDINATION.md#22-if-no-conflicts-register-and-proceed), the reservation is the structural prevention; this failure mode triggers only when the concurrent agent ignored the reservation OR when reservations were unavailable.

**Cross-link.** [FAILURE-MODES.md F18](FAILURE-MODES.md#f18-branch-count-differs-between-two-runs); [INCIDENT-PLAYBOOK.md I6](INCIDENT-PLAYBOOK.md#i6--canonicals-tip-moved-force-push-detected-mid-run) (related — concurrent canonical force-push).

---

## CA-2 — Concurrent agent deletes a branch mid-run that WAS in `branches.tsv`

**Scenario.** A concurrent agent decides one of the branches in our triage is theirs and runs `git branch -D agent-cc-7-fcp-handler-redact`. The branch ref is gone; our backup ref `refs/branch-rationalization-backup/<slug>` survives untouched (Phase 3 already captured it).

**Detection signal.**

```bash
# At the top of Phase 8 / 10 iterations:
for slug in $(awk -F'\t' 'NR>1 {print $1}' "$WS/branches.tsv"); do
  if ! git -C "$PROJECT" rev-parse --verify "refs/heads/$slug" >/dev/null 2>&1; then
    echo "BRANCH DELETED OUT-OF-BAND: $slug"
  fi
done
```

The Phase 8 keeper-applier and the Phase 10 cleanup-conductor both run this check. The backup ref still resolves; the live ref does not.

**Immediate triage.**

1. **Do not error.** This is not a fatal incident; the branch was scheduled for deletion anyway in Phase 10 (or the run had already classified it as garbage).
2. Surface to user: "Branch `<name>` was deleted by a concurrent agent at `<time>`; backup ref intact in `refs/branch-rationalization-backup/<slug>`. The bundle entry is unchanged. Treating as already-deleted; no further action needed."
3. Update `cleanup_log.tsv` with `pre_drop_status=externally-deleted`.

**Recovery.**

- If the branch was a `novel-and-accretive` keeper that hadn't been applied yet, the bundle's diff + format-patch series is still applyable. Apply it as if the branch still existed (the apply needs the merge-base SHA which is recorded in the bundle's `branches/<slug>/meta.txt`).
- If the branch was already applied to the rationalization branch, no recovery needed — the content is already on the rat-branch.

**Prevention.**

- Same as CA-1: exclusive reservation on `.git/refs/heads/**` prevents this entirely.
- Without reservations, this is recoverable but noisy.

**Cross-link.** [MULTI-AGENT-COORDINATION.md § 4.4](MULTI-AGENT-COORDINATION.md#44-if-a-concurrent-agent-deleted-a-branch-mid-run); [ADVANCED-RECOVERY.md AR6](ADVANCED-RECOVERY.md).

---

## CA-3 — Concurrent agent rebases canonical mid-run

**Scenario.** Mid-Phase-8, an autonomous agent runs `git rebase origin/main` on canonical (or fast-forwards canonical to a new remote tip). The rationalization branch's parent (canonical's tip at Phase 0) is now stale by N commits. The rat-branch was cut from the *old* canonical tip; new canonical is ahead by some commits.

**Detection signal.**

```bash
# Before each Phase 8 apply, the keeper-applier compares canonical's current tip
# against Phase 0's snapshot:
phase0_canonical_tip=$(cat "$WS/canonical_tip_phase0.txt")
current_canonical_tip=$(git -C "$PROJECT" rev-parse "$CANONICAL")
[ "$phase0_canonical_tip" = "$current_canonical_tip" ] || echo "CANONICAL DRIFT"
```

The Phase 0 snapshot of canonical's tip is the baseline.

**Immediate triage.**

1. Halt Phase 8.
2. Determine whether canonical moved by *fast-forward* (new commits added on top — most common) or *rewrite* (force-push / rebase changed history).
   - `git merge-base --is-ancestor "$phase0_canonical_tip" "$current_canonical_tip"` returns 0 → fast-forward; safe to rebase the rat-branch onto the new tip.
   - Returns 1 → rewrite; this is incident I6 (force-push), more serious.

**Recovery.**

- Fast-forward case (safe):
  ```bash
  git checkout branch-rationalization-2026-05-07
  git rebase --onto "$current_canonical_tip" "$phase0_canonical_tip"
  # Re-run any failed Phase 8 applies (per apply_log.tsv)
  ```
- Rewrite case (severe): treat as I6. The bundle's snapshot of canonical's tip is the recovery anchor; per [ADVANCED-RECOVERY.md AR2](ADVANCED-RECOVERY.md), `refs/branch-rationalization-backup/<canonical-slug>` exists ONLY if the run captured it; otherwise the reflog at `git reflog show <canonical>` may still have the old tip within 30 days.

**Prevention.**

- The skill's reservation set does NOT include canonical (`.git/refs/heads/<canonical>` is intentionally outside the four globs in [MULTI-AGENT-COORDINATION.md § 3.1](MULTI-AGENT-COORDINATION.md#31-the-four-globs-full-coverage)). This is deliberate — concurrent agents need to land emergency hotfixes on canonical even during a rationalization. The rationalization just needs to detect the drift and rebase.
- Soft-prevention: announce on the run-id thread: "starting rationalization run; if you must land on canonical mid-run, ack on this thread so I can rebase the rat-branch promptly."

**Cross-link.** [INCIDENT-PLAYBOOK.md I6](INCIDENT-PLAYBOOK.md#i6--canonicals-tip-moved-force-push-detected-mid-run); [FAILURE-MODES.md F27](FAILURE-MODES.md#f27-the-rationalization-branchs-tip-diverges-from-canonical-mid-run).

---

## CA-4 — Concurrent agent force-pushes canonical to remote

**Scenario.** A concurrent agent (or human) runs `git push --force origin main`. Local canonical is unaffected; `origin/main` (the remote tracking ref) now points at a different SHA than local. The rationalization branch was cut from local canonical; it is unaffected on the local side.

**Detection signal.**

```bash
# Phase 8 / Phase 11 fetches origin tracking refs (read-only) and compares:
git -C "$PROJECT" fetch origin --no-tags
local_canonical=$(git rev-parse "$CANONICAL")
remote_canonical=$(git rev-parse "origin/$CANONICAL")
[ "$local_canonical" = "$remote_canonical" ] || echo "REMOTE DIVERGED FROM LOCAL"

# Reflog shows the force-push on origin/<canonical>:
git reflog show "origin/$CANONICAL" | head -3
```

If `git rev-parse origin/main` ≠ Phase 0's snapshot of `origin/main`, AND the remote new tip is not a descendant of the old one → force-push detected.

**Immediate triage.**

1. The skill **never pushes**, so the rationalization branch on local is unaffected.
2. The handoff report flags this as a "remote diverged" warning; the user will need to reconcile their next push themselves.
3. Phase 8 continues as planned (the rat-branch is built off local canonical).

**Recovery.**

- Local rat-branch + canonical are intact. No rollback needed.
- The user, after Phase 11, decides whether to:
  - (a) push the rat-branch to origin as a new branch (no conflict); open a PR.
  - (b) reconcile local with the new remote first via `git pull --rebase origin main`; then re-base the rat-branch onto the merged result.
- The handoff report includes both options.

**Prevention.**

- Out of scope. The skill cannot prevent operations on a remote it doesn't own.
- The handoff explicitly notes: "if your team is force-pushing canonical regularly, schedule rationalization runs in coordinated maintenance windows."

**Cross-link.** [Axiom 15 — Remote cleanup is out of scope](../SKILL.md#the-rationalization-kernel-universal-axioms); [INCIDENT-PLAYBOOK.md I6](INCIDENT-PLAYBOOK.md#i6--canonicals-tip-moved-force-push-detected-mid-run).

---

## CA-5 — Concurrent agent autostashes during a rebase, creating new stashes

**Scenario.** A peer agent runs `git rebase` somewhere; the rebase autostashes the working tree changes. New stashes appear in `git stash list` that this skill didn't create. Per [Axiom 12](../SKILL.md#the-rationalization-kernel-universal-axioms), we treat these as if we made them, but they are *orthogonal* to this skill's scope.

**Detection signal.**

```bash
# Phase 0 snapshots `git stash list | wc -l`; subsequent phases re-snapshot and detect drift:
phase0_stash_count=$(cat "$WS/stash_count_phase0.txt")
current_stash_count=$(git -C "$PROJECT" stash list | wc -l)
(( current_stash_count > phase0_stash_count )) && echo "STASH GROWTH"
```

**Immediate triage.**

1. Do nothing. Stashes are explicitly out of scope for this skill ([SKILL.md "Scope"](../SKILL.md#scope-and-axiom-set)).
2. Phase 11 handoff notes the stash drift: "during the run, your stash count grew from M to N; consider running /git-stash-janitor afterward."

**Recovery.**

- N/A. The rationalization run is unaffected.

**Prevention.**

- Out of scope. We don't reserve stash refs; that's the stash-janitor skill's surface.

**Cross-link.** [git-stash-janitor SKILL.md](../../git-stash-janitor/SKILL.md); [Axiom 12](../SKILL.md#the-rationalization-kernel-universal-axioms).

---

## CA-6 — Concurrent agent modifies a worktree's working tree mid-Phase-8

**Scenario.** While the rationalization run is mid-Phase-8 (cherry-picking keepers onto the rat-branch), a peer agent edits files in worktree `/data/projects/foo-wt-3/`. Files appear modified in `git status` of that worktree.

**Detection signal.**

```bash
# scripts/apply-keeper.sh fragment, run before each apply:
for wt in $(git worktree list --porcelain | awk '/^worktree / {print $2}'); do
  current_status=$(git -C "$wt" status --porcelain=v2 | sha256sum | awk '{print $1}')
  baseline_status=$(cat "$WS/wt_status_phase0_$(slugify "$wt").txt.sha256")
  [ "$current_status" != "$baseline_status" ] && echo "WORKING-TREE DRIFT in $wt"
done
```

**Immediate triage.**

Per [Axiom 12](../SKILL.md#the-rationalization-kernel-universal-axioms): "Concurrent agents' working-tree changes in any worktree are normal." Treat as if you made it. Do **NOT** stash, revert, or overwrite.

1. Re-snapshot the worktree's status; the new baseline replaces the old.
2. Continue Phase 8 — the apply on the rat-branch is independent of the source worktrees' working state (the apply reads from the branch ref + bundle, not from the worktree's working files).
3. `↺ WORKING-TREE-DRIFT` operator handles this transparently.

**Recovery.**

- N/A — Phase 8 doesn't depend on worktree working state.
- Phase 10 is a different story; see CA-7 for what happens if drift coincides with worktree removal.

**Prevention.**

- Per [MULTI-AGENT-COORDINATION.md § 4.1](MULTI-AGENT-COORDINATION.md#41-re-snapshot-before-each-phase-8-apply): re-snapshot before each Phase 8 apply, never act surprised, never overwrite.

**Cross-link.** [Operator ↺ WORKING-TREE-DRIFT](OPERATOR-LIBRARY.md); [WORKTREE-STATE.md](WORKTREE-STATE.md); AGENTS.md "Note for Codex/GPT-5.5".

---

## CA-7 — Concurrent agent removes a worktree mid-Phase-3

**Scenario.** Phase 3 is in progress capturing worktree dirty states. A peer agent runs `git worktree remove /data/projects/foo-wt-2/` while Phase 3 is iterating. The worktree path is gone before its capture completes.

**Detection signal.**

```bash
# scripts/build-bundle.sh per-worktree iteration:
for wt_path in $(awk -F'\t' 'NR>1 {print $2}' "$WS/worktrees.tsv"); do
  [ -d "$wt_path" ] || { echo "WORKTREE GONE MID-CAPTURE: $wt_path"; continue; }
  ...
done
```

**Immediate triage.**

1. The worktree's dirty state is **lost** — there is no way to recover it without the working tree directory.
2. Mark the row in `worktrees.tsv:status=externally-removed-during-bundle`; mark `index.tsv:bundle_paths=NONE`.
3. Surface to user: "worktree `<path>` was removed by a concurrent agent during bundle capture; its dirty state, if any, is unrecoverable. The branch the worktree was pinned to (if any) is unaffected."

**Recovery.**

- For the *branch* the worktree was pinned to: the branch ref still exists; the bundle's per-branch backup is unaffected.
- For the *dirty state* (staged + unstaged + untracked): unrecoverable. The user accepts the loss or surfaces it to the agent that did the removal.

**Prevention.**

- Phase 0.5 reservations on `.git/worktrees/**` prevent peer agents from running `git worktree remove` against the protected paths. A peer agent attempting it gets `FILE_RESERVATION_CONFLICT` and aborts.
- This failure mode happens primarily when reservations are unavailable (Agent Mail down) OR a peer agent ignored them.

**Cross-link.** [FAILURE-MODES.md F4](FAILURE-MODES.md#f4-git-worktree-remove-path-refuses-on-dirty-worktrees); [WORKTREE-STATE.md](WORKTREE-STATE.md).

---

## CA-8 — Two rationalization runs in the same repo

**Scenario.** Two human users (or two agents) both invoke `/git-worktree-branch-rationalization` on the same project at roughly the same time. The first run created `.worktree_branch_rationalization_workspace/`; the second run is starting up.

**Detection signal.**

```bash
# scripts/git-doctor.sh + Phase 0.5 intake:
if [ -d "$PROJECT/.worktree_branch_rationalization_workspace" ]; then
  workspace_age=$(stat -c '%Y' "$PROJECT/.worktree_branch_rationalization_workspace")
  workspace_now=$(date +%s)
  age_seconds=$((workspace_now - workspace_age))
  if (( age_seconds < 600 )); then
    echo "FRESH WORKSPACE DETECTED — another run may be in progress (age=${age_seconds}s)"
  fi
fi

# Also: Agent Mail check
agent_mail_active=$(list_active_agents project_key="$PROJECT" | grep "branch-rationalization-")
[ -n "$agent_mail_active" ] && echo "ACTIVE RATIONALIZATION RUN: $agent_mail_active"
```

**Immediate triage.**

1. Refuse to start. Per [MULTI-AGENT-COORDINATION.md § 2](MULTI-AGENT-COORDINATION.md#2-pre-run-handshake-phase-0): "If `conflicting_reservations` is non-empty, surface to the user."
2. The intake prompt offers: (a) wait for the active run to finish; (b) abort; (c) coordinate with the other run via Agent Mail.

**Recovery.**

- The first run, if interrupted, leaves a recoverable workspace per [WORKED-EXAMPLES-EXTENDED.md scenario G](WORKED-EXAMPLES-EXTENDED.md#g-recovery-from-a-half-finished-prior-run--resumability).
- Two concurrent runs is a coordination failure, not a state corruption — neither has destroyed anything.

**Prevention.**

- File reservations on `.worktree_branch_rationalization_workspace/**` make this structurally impossible when Agent Mail is up.
- When Agent Mail is down, the workspace-directory check is the fallback: a fresh workspace older than ~10 minutes (which would be exceptional for an active run) is considered abandoned.

**Cross-link.** [MULTI-AGENT-COORDINATION.md § 2](MULTI-AGENT-COORDINATION.md#2-pre-run-handshake-phase-0).

---

## CA-9 — Beads database lock contention

**Scenario.** Phase 0.5 runs `br create --title "branch+worktree rationalization on ..."` to file a beads issue and get a run-id. The `.beads/beads.db` SQLite file is locked by another `br` process (a peer agent updating its own beads issues).

**Detection signal.**

```bash
# Phase 0.5 beads-issue creation has retry-with-backoff:
attempts=0
while ! br create --title "..." --type=task --priority=4 2>/dev/null; do
  attempts=$((attempts+1))
  (( attempts > 10 )) && { echo "BEADS LOCKED — proceeding without issue"; break; }
  sleep $(( attempts * 3 ))
done
```

Total backoff: 3+6+9+...+30 ≈ 165s if all 10 retries fail.

**Immediate triage.**

1. After 10 retries with exponential backoff (capped at 30s per attempt), proceed without filing the beads issue.
2. Set `beads_skipped=true` in handoff_report.md; the run-id falls back to `branch-rationalization-<UTC-timestamp>` instead of `<beads-id>`.
3. Phase 11 handoff prompts the user to manually file a beads issue if they want one.

**Recovery.**

- N/A — the run completes successfully without beads tracking. Beads is enrichment, not load-bearing.

**Prevention.**

- Beads is a single-writer SQLite DB; lock contention is rare but real. The retry-with-backoff is enough for typical contention.
- For heavy beads usage (a swarm filing issues every few seconds), pre-coordinate on the swarm via Agent Mail.

**Cross-link.** [FAILURE-MODES.md F20](FAILURE-MODES.md#f20-beads-database-lock-during-the-run); [INCIDENT-PLAYBOOK.md I7](INCIDENT-PLAYBOOK.md#i7--beads-database-lock-or-agent-mail-server-unreachable).

---

## CA-10 — Agent Mail server unreachable mid-run

**Scenario.** The rationalization run started with Agent Mail healthy; mid-Phase-5 (or any later phase), the Agent Mail server stops responding (network glitch, server restart, MCP transport failure). Heartbeats fail; reservations may expire.

**Detection signal.**

```python
# Heartbeat loop catches connection errors:
try:
    file_reservation_paths(project_key=..., paths=THE_FOUR_GLOBS, ttl_seconds=...)
except (ConnectionError, TimeoutError) as e:
    log("AGENT MAIL UNREACHABLE: %s", e)
    # Continue without coordination — best-effort mode.
```

**Immediate triage.**

1. Switch to "best-effort" mode: cache reservation intent locally in `.worktree_branch_rationalization_workspace/cached_reservations.json`; replay on reconnect.
2. Continue the run — the bundle + verbatim authorization gates are independent of Agent Mail.
3. Log "coordination degraded" in handoff_report.md.

**Recovery.**

- On reconnect (heartbeat retry succeeds), replay cached reservations.
- If the entire run completes with Agent Mail unreachable, the run still succeeds; the only loss is the coordination thread (no message announcing the run's start/end to the run-id thread).

**Prevention.**

- Out of scope. Agent Mail availability is infrastructure, not skill responsibility.
- The skill is *designed* to degrade gracefully when coordination layer is absent.

**Cross-link.** [INCIDENT-PLAYBOOK.md I7](INCIDENT-PLAYBOOK.md#i7--beads-database-lock-or-agent-mail-server-unreachable).

---

## CA-11 — NTM pane dies mid-Phase-5

**Scenario.** Comprehensive mode is using NTM panes for parallel triage workers. One pane dies (rate-limited; OOM; user accidentally closed the tmux window). Its assigned batch (e.g., `batch_004.tsv` covering branches 91–120) is half-written.

**Detection signal.**

```bash
# Orchestrator (main agent) heartbeats each NTM pane:
for pane_id in $PANE_IDS; do
  ntm send "$BASENAME" --pane "$pane_id" --message "heartbeat-$(date +%s)"
  if ! ntm pane-status "$BASENAME" "$pane_id" --json | jq -r .alive >/dev/null; then
    echo "PANE DEAD: $pane_id"
  fi
done
```

**Immediate triage.**

1. Identify the dead pane's assigned batch (`batch_004.tsv`).
2. Read the partial output; rows already written are valid.
3. Reassign the unfinished rows to a surviving pane (or spawn a replacement pane).
4. The replacement triages only the unfinished rows; merges into `batch_004.tsv` on completion.

**Recovery.**

- Per-row idempotency in the triage worker (each row's verdict is independent) makes pane reassignment trivial.
- No rerun of completed rows.

**Prevention.**

- Per [ORCHESTRATION.md "Failure modes"](ORCHESTRATION.md): heartbeat panes; auto-respawn; reassign on death.
- Use `caam` for pane-account rotation if rate-limit deaths are frequent.

**Cross-link.** [ORCHESTRATION.md](ORCHESTRATION.md); [vibing-with-ntm SKILL.md](../../vibing-with-ntm/SKILL.md).

---

## CA-12 — User runs `git fetch origin --prune` mid-run

**Scenario.** Mid-Phase-8, the user runs `git fetch origin --prune` to refresh remote tracking. Local branches whose upstreams were deleted on origin are now flagged `[gone]`. The triage was built before the prune; some `[gone]` flags may have changed.

**Detection signal.**

```bash
# Phase 8's pre-apply re-fingerprinting (⊞ RE-FINGERPRINT) compares branches.tsv:upstream_status
# to live `git branch -vv` output:
git -C "$PROJECT" branch -vv > "$WS/branches_current.txt"
diff <(awk -F'\t' 'NR>1 {print $1, $14}' "$WS/branches.tsv") \
     <(awk '{print $1, ($3 ~ /\[/) ? $3 : "ok"}' "$WS/branches_current.txt") || \
  echo "UPSTREAM-STATUS DRIFT (likely from a fetch --prune)"
```

**Immediate triage.**

1. Drift in `[gone]` flags is informational, not destructive.
2. Update `branches.tsv:upstream_status` for affected rows in place.
3. Per [SKILL.md "Failure Modes"](../SKILL.md#failure-modes-table--branch--worktree-footguns): "A branch with `[gone]` upstream tracking has unique commits — Don't auto-delete just because tracking is gone."
4. Continue Phase 8 with the updated status; verdict on the affected rows likely doesn't change (the `[gone]` flag is a hint, not a verdict).

**Recovery.**

- N/A — the run continues; the only effect is updated metadata.

**Prevention.**

- Out of scope. The user can run `git fetch` whenever they want; the skill never blocks read-only operations.
- Phase 11 handoff notes any `[gone]` status changes that occurred during the run.

**Cross-link.** [FAILURE-MODES.md F7](FAILURE-MODES.md#f7-a-branch-with-gone-upstream-tracking-has-unique-commits).

---

## CA-13 — Agent Mail file reservation expired (TTL exceeded)

**Scenario.** A long-running Comprehensive run took longer than the initial TTL estimate. The heartbeat loop is supposed to refresh every TTL/4, but a temporary network blip caused a heartbeat to fail. Another agent saw the expired reservation and grabbed it. The skill's exclusive lock is now stolen.

**Detection signal.**

```python
# Heartbeat refresh attempts to extend the TTL; if Agent Mail rejects with "reservation_held_by_other":
try:
    file_reservation_paths(project_key=..., paths=..., exclusive=True, reason=...)
except FileReservationConflictError as e:
    log("RESERVATION STOLEN: %s", e)
    halt_run()
```

**Immediate triage.**

1. Halt the run immediately. The exclusive lock is gone; we cannot guarantee no concurrent agent is touching `.git/refs/heads/**`.
2. Surface the incident to the user: "another agent took our file reservation after a heartbeat failure; halting to prevent corruption."
3. The bundle is intact; the rat-branch is intact; nothing destructive has happened.
4. The user resolves manually (asks the other agent to release; or the user authorizes resuming with non-exclusive reservations).

**Recovery.**

- The skill resumes per [WORKED-EXAMPLES-EXTENDED.md scenario G](WORKED-EXAMPLES-EXTENDED.md#g-recovery-from-a-half-finished-prior-run--resumability).
- All persisted artifacts (bundle, branches.tsv, harmonization_plan.md, apply_log.tsv) are valid.

**Prevention.**

- TTL should be a generous over-estimate. Default for Comprehensive: 28800s (8h); for Council: 50400s (14h).
- Heartbeat at TTL/4 (faster than necessary) so a single failed heartbeat doesn't expire the reservation — the next heartbeat is still well within TTL.
- Use [Agent Mail's `macro_file_reservation_cycle`](MULTI-AGENT-COORDINATION.md#33-heartbeat--ttl-refresh-on-long-runs) which handles this loop with built-in resilience.

**Cross-link.** [MULTI-AGENT-COORDINATION.md § 3.3](MULTI-AGENT-COORDINATION.md#33-heartbeat--ttl-refresh-on-long-runs).

---

## CA-14 — Concurrent agent commits to the rationalization branch itself

**Scenario.** A peer agent, not knowing the rationalization branch is the integration branch, sees `branch-rationalization-2026-05-07` and lands a commit on it (e.g., a quick fix). The rat-branch's tip is now beyond `apply_log.tsv`'s last row.

**Detection signal.**

```bash
# Before each Phase 8 apply, the keeper-applier verifies the rat-branch tip matches expectations:
expected_tip=$(awk -F'\t' 'END {print $3}' "$WS/apply_log.tsv" | tr -d '\r\n')
actual_tip=$(git rev-parse "$RAT_BRANCH")
[ "$expected_tip" = "$actual_tip" ] || echo "RAT-BRANCH UNEXPECTED COMMITS"
```

**Immediate triage.**

1. Halt Phase 8.
2. Inspect: `git log --format='%H %an %s' "$expected_tip..$actual_tip"`.
3. Surface to user: "an unexpected commit `<sha>` by `<author>` landed on the rationalization branch. Options: (a) keep it (treat as if it had been an applied keeper); (b) revert it; (c) abort the rationalization run."

**Recovery.**

- (a) is usually the right answer; update `apply_log.tsv` with a row marking the unexpected commit as `external-commit` and continue Phase 8.
- (b) is reasonable if the commit was destructive or wrong; surface the revert to the user.
- (c) is the nuclear option; the bundle is intact.

**Prevention.**

- Add the rationalization branch to the reservation set: `.git/refs/heads/branch-rationalization-*`.
- Announce the rat-branch in the Phase 0.5 run-id thread message: "DO NOT commit to `branch-rationalization-<DATE>` while this run is active."

**Cross-link.** [FAILURE-MODES.md F27](FAILURE-MODES.md#f27-the-rationalization-branchs-tip-diverges-from-canonical-mid-run); [INCIDENT-PLAYBOOK.md I5](INCIDENT-PLAYBOOK.md#i5--rationalization-branch-deleted-out-of-band-mid-run).

---

## CA-15 — A peer agent's working tree changes propagate via shared pre-commit hooks

**Scenario.** Phase 8 runs `cargo fmt --check` as a pre-commit hook gate. A peer agent in another worktree just ran `cargo fmt` (which writes files), and the formatter wrote into a shared `target/` cache. The rationalization run's apply now sees an unexpected target-cache state, OR the formatter modified a file in the rat-branch's worktree that wasn't part of the keeper.

**Detection signal.**

```bash
# git status --porcelain after the apply but before commit shows unexpected files:
unexpected=$(git status --porcelain | grep -v "^M  $expected_keeper_path")
[ -n "$unexpected" ] && echo "UNEXPECTED CHANGES: $unexpected"
```

**Immediate triage.**

1. Per Axiom 12, treat the unexpected changes as if you made them — but DO NOT include them in the keeper commit.
2. Use `git add` on only the keeper's expected files (NOT `git add -A`); commit; re-snapshot.
3. The unexpected changes remain in the rat-branch's working tree as un-committed; they roll forward into the next iteration.

**Recovery.**

- No rollback needed; the keeper commit is clean.
- The unexpected changes either get included in a later iteration's commit (if they belong) or stay as drift to surface in the handoff.

**Prevention.**

- Use `git diff --cached` to verify what's being committed; never `git add -A` unconditionally.
- Per AGENTS.md "No Script-Based Changes": don't run formatters as part of the apply step; let the project's pre-commit hooks run them, but commit only what was intentionally staged.

**Cross-link.** [Operator ↺ WORKING-TREE-DRIFT](OPERATOR-LIBRARY.md); [WORKTREE-STATE.md](WORKTREE-STATE.md).

---

## Composite scenarios — Multiple CAs at once

Real swarm aftermath rarely produces failures one at a time. Common combinations:

| Combo | Why it happens | Compounded triage |
|---|---|---|
| CA-1 + CA-3 | A new agent created a branch AND rebased canonical (it's a feature branch landing) | Halt both; re-run Phase 2 + verify CA-3 fast-forward; rebase rat-branch; add new branch to inventory; re-bundle delta; continue |
| CA-6 + CA-7 | A peer is editing a worktree and another removes it | The CA-7 wins — once the dir is gone, CA-6's drift is moot. Mark dirty state lost; surface to user |
| CA-2 + CA-14 | Concurrent agent deleted a branch AND committed to rat-branch | Independent; handle CA-14 first (rat-branch state matters more); then ack CA-2 in handoff |
| CA-9 + CA-10 | Beads down + Mail down | Run in fully degraded mode; both are best-effort; the bundle + verbatim auth gates carry the safety story |
| CA-13 + concurrent reservation re-acquisition | TTL expired, peer grabbed lock, then released it | If the peer's reservation has been released by the time we detect, re-acquire; otherwise halt |

---

## Detection scaffolding (where to put the checks)

Concentrating drift-detection in a few hot points is easier to maintain than spraying checks everywhere. The skill places concurrent-agent detection at:

| Phase | Check | Action on positive |
|---|---|---|
| Phase 0 | Snapshot canonical tip + worktree statuses + branch count + stash count | Sets baselines for later phases |
| Phase 0.5 | Active reservations check via Agent Mail | Pre-run handshake; defer or coordinate |
| Phase 3 | Per-worktree existence check before each capture | Skip + log if gone (CA-7) |
| Phase 5 | Per-batch row independence (no cross-row state) | Pane death (CA-11) only loses the unfinished batch |
| Phase 8 (every iteration) | Branch count drift + canonical tip drift + rat-branch tip + worktree drift | CA-1, CA-2, CA-3, CA-4, CA-6, CA-12, CA-14 |
| Phase 10 (every iteration) | Branch existence + worktree existence + bundle byte-equality | CA-2, CA-7 detected fail-safe |
| Heartbeat (every TTL/4) | Reservation refresh | CA-13 |

Per [PHASES.md "Idempotence & Resumability"](PHASES.md), every phase is resumable from a clean checkpoint, which means CAs detected mid-phase can halt, surface, and resume after the user authorizes — without losing any prior work.

---

## Cross-References

- Coordination protocol: [MULTI-AGENT-COORDINATION.md](MULTI-AGENT-COORDINATION.md)
- Per-incident triage runbook: [INCIDENT-PLAYBOOK.md](INCIDENT-PLAYBOOK.md)
- Git-mechanic failures (the F-prefix): [FAILURE-MODES.md](FAILURE-MODES.md)
- Working-tree-drift discipline: [WORKTREE-STATE.md](WORKTREE-STATE.md), AGENTS.md "Note for Codex/GPT-5.5", [Operator ↺ WORKING-TREE-DRIFT](OPERATOR-LIBRARY.md)
- Resume from incident: [WORKED-EXAMPLES-EXTENDED.md scenario G](WORKED-EXAMPLES-EXTENDED.md#g-recovery-from-a-half-finished-prior-run--resumability)
- NTM pane management: [ORCHESTRATION.md](ORCHESTRATION.md), [vibing-with-ntm SKILL.md](../../vibing-with-ntm/SKILL.md)
