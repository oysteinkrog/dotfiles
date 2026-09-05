# Multi-Agent Coordination — Running Alongside Active Swarms

**The hard-won insight:** agent swarms create exactly the worktree-and-branch pile this skill rationalizes, AND the skill may need to run while a swarm is still active. This is not a hypothetical — it is the *normal* state of a project that has accumulated 200 branches and 40 worktrees in a few days. The user wants to clean up while their agents keep working.

This file documents the coordination protocol that lets the skill operate safely alongside active agents without (a) deleting branches an agent is currently using, (b) removing worktrees an agent is editing in, (c) holding locks long enough to wedge the swarm, or (d) being surprised by drift it didn't cause.

> **Why this is its own reference, not a section of [INTEGRATION.md](INTEGRATION.md):** Integration is about *plumbing* (beads, agent-mail, bv, dcg, slb). Coordination is about *protocol* — the runtime contract the skill makes with concurrent agents. Different concern, different reference.

---

## 1. The Strategic Context

The user's hard-won insight (mined from session history): **branches and worktrees don't scale to dozens of concurrent agents.**

| Failure mode | Why |
|---|---|
| One branch per agent | Agents collide on the same files when they work on overlapping problems; merging 200 branches is the harmonization problem this skill addresses; worktrees per branch eat disk |
| One worktree per branch | 50× the inode cost of the working repo; per-worktree submodule init is non-trivial; the user runs out of disk |
| Per-agent branch with rebase-on-merge | The rebase queue serializes the swarm — the slowest agent blocks all others |
| `git stash` per agent | Stash log becomes the bottleneck; stashes don't survive long-running agents (stash-janitor is the cleanup) |

**The pattern that DOES scale:** a single-canonical line with **file reservations** for the destructive write surface. Agents read freely, edit freely in their working trees, and reserve the file paths they're about to write to via Agent Mail's `file_reservation_paths`. Conflicts surface via `FILE_RESERVATION_CONFLICT` errors *before* any commit lands.

The rationalization branch is itself an integration point that supports this pattern — agents who read this skill's output should NOT spawn new branches or worktrees during normal operation. They commit to canonical (or to the rationalization branch as a temporary integration line) with file reservations.

> **Why state this in the skill?** The skill's *output* (the cleaned-up repo) is consumed by future agents. If those agents read the handoff report and assume "branches per agent is fine, the skill cleaned up the last batch", the skill has just enabled the next 200-branch pile. The handoff report explicitly recommends the file-reservation pattern; this file documents *why*.

---

## 2. Pre-Run Handshake (Phase 0)

Before any inventory or bundling, the skill checks for active agents on the project. If any agent is *actively reserving files* in the destructive surface (`.git/refs/heads/**` or any worktree's content), the skill defers and waits.

### 2.1 Check for active reservations

```python
# Pseudo-code; the actual call is via MCP Agent Mail.
inbox = fetch_inbox(project_key="<abs-path>", agent_name="<this-skill-instance>")
active_agents = list_active_agents(project_key="<abs-path>")

conflicting_reservations = []
for agent in active_agents:
    for reservation in agent.file_reservations:
        if any_path_overlaps(reservation.paths, [
            ".git/refs/heads/**",
            ".git/worktrees/**",
            ".worktree_branch_rationalization_workspace/**",
        ]):
            conflicting_reservations.append((agent, reservation))
```

If `conflicting_reservations` is non-empty, surface to the user:

```
Other agents are currently reserving files in the rationalization surface:

  - agent-cc-12 (program=claude-code, model=opus-4-7)
    paths: .git/refs/heads/agent-cc-12-feat-parser, src/parse/**
    reason: beads-1742
    expires_at: 2026-05-07T15:42:00Z (in 23 minutes)

  - agent-cod-3 (program=codex, model=gpt-5.5)
    paths: .git/refs/heads/agent-cod-3-mysql-fix
    reason: beads-1743
    expires_at: 2026-05-07T15:55:00Z (in 36 minutes)

Options:
  (a) Defer the rationalization run; resume after their reservations expire (~36 min)
  (b) Coordinate manually: ask them to release their reservations
  (c) Proceed anyway with non-exclusive reservations (advisory only; risk of mid-run drift)
  (d) Abort

Which?
```

> **Why surface and not auto-defer?** Per AGENTS.md "Mandatory explicit plan": the user is the gate. The skill knows *that* there's a conflict; it doesn't know *whether* the user wants to wait, override, or coordinate. Auto-deferring assumes the user has time to wait; auto-proceeding assumes the conflict is benign. Neither is safe to assume.

### 2.2 If no conflicts, register and proceed

```
ensure_project(project_key="<abs-path>")
register_agent(project_key="<abs-path>", program="claude-code", model="opus-4-7")
# Macro form (preferred): macro_start_session
```

Agent Mail's `macro_start_session` does the project + agent registration in one call. Use it.

### 2.3 If user chose (b) — coordinate manually

The skill sends a message on the run-id thread requesting reservation release:

```
send_message(
  project_key="<abs-path>",
  to_agent="agent-cc-12",
  thread_id="branch-rationalization-<run-id>",
  subject="[branch-rationalization-<run-id>] Coordination request: rationalization run starting",
  body="I'm about to start a branch+worktree rationalization run on this project. Your reservations on .git/refs/heads/agent-cc-12-feat-parser are blocking me. Could you release them when convenient (or by 15:42:00Z when they expire)? I'll wait.",
  ack_required=true
)
```

The skill waits for the ack OR for the reservations to expire OR for the user to override. No timer; the user is in control.

---

## 3. During-Run Reservations (Phase 0.5)

Once the pre-run handshake clears, the skill registers its own reservations covering the entire destructive surface for the duration of the run.

### 3.1 The four globs (full coverage)

```
file_reservation_paths(
  project_key="<abs-path>",
  agent_name="<this-skill-instance>",
  paths=[
    ".git/worktrees/**",                                            # worktree admin metadata
    ".git/refs/heads/**",                                           # branch refs
    ".worktree_branch_rationalization_workspace/**",                # workspace (transient artifacts)
    ".worktree_branch_rationalization_workspace/triage/**",         # triage worker outputs (parallel writes)
    ".worktree_branch_rationalization_workspace/conflicts/**"       # conflict context
  ],
  ttl_seconds=<estimated-total-wall-time>,
  exclusive=true,
  reason="branch-rationalization-<run-id>"
)
```

The TTL is the estimated total wall time from [MEASUREMENT.md § 2 "Per-Phase SLOs"](MEASUREMENT.md#2-per-phase-slos-wall-time):

| Mode | TTL |
|---|---|
| Quick | 3600s (1h) |
| Standard | 14400s (4h) |
| Comprehensive | 28800s (8h) |
| Council | 50400s (14h) |

### 3.2 What `exclusive=true` means in practice

When the skill holds an exclusive reservation:

- Other agents attempting to reserve overlapping paths get `FILE_RESERVATION_CONFLICT`. They surface to their own user.
- Other agents may *read* freely (Agent Mail reservations don't block reads — they're advisory locks on writes).
- Other agents may operate on paths *outside* the four globs without conflict (e.g., editing `src/foo.rs` is fine; the skill doesn't reserve `src/**`).

> **Why not reserve `src/**`?** Per [Axiom 12](../SKILL.md#the-rationalization-kernel-universal-axioms): "Concurrent agents' working-tree changes in any worktree are normal." Concurrent edits to the source tree are expected; the skill must coexist with them. The skill reserves only the *destructive* surface — the refs and worktree-admin namespace.

### 3.3 Heartbeat / TTL refresh on long runs

For Comprehensive and Council runs, the initial TTL may not cover the full wall time (agent scheduling delays, gate-suite latency, multi-model triangulation). The skill heartbeats every `ttl_seconds / 4`:

```python
# Pseudo-code; actual implementation uses macro_file_reservation_cycle.
import time
heartbeat_interval = ttl_seconds // 4
while run_active:
    file_reservation_paths(
        project_key=PROJECT_KEY,
        agent_name=AGENT_NAME,
        paths=THE_FOUR_GLOBS,
        ttl_seconds=ttl_seconds,
        exclusive=True,
        reason=f"branch-rationalization-{RUN_ID}"
    )
    time.sleep(heartbeat_interval)
```

Agent Mail's `macro_file_reservation_cycle` handles this loop including heartbeat, expiry detection, and graceful release on completion. Use the macro.

---

## 4. Concurrent Agent in a Triaged Worktree

Per AGENTS.md "Note for Codex/GPT-5.5":

> If you encounter changes in the working tree that you didn't make yourself, treat them as if you made them. Don't surprise the user with prompts about drift you didn't cause. Don't `git stash`, `git reset`, or `git checkout --` to make them go away.

The skill follows this rule for *every* worktree on the project, not just the active one.

### 4.1 Re-snapshot before each Phase 8 apply

The keeper-applier subagent re-snapshots `git status --porcelain=v2` in every worktree before each cherry-pick / squash-merge / rebase / harmonized-synthesis:

```bash
# scripts/apply-keeper.sh fragment:
for wt in $(git worktree list --porcelain | awk '/^worktree / {print $2}'); do
  git -C "$wt" status --porcelain=v2 > "$WS/wt_status_phase8_pre_$(slugify "$wt").txt"
done

# Compare against Phase 0 / Phase 3 baseline:
for wt in <list>; do
  if ! diff -q "$WS/wt_status_phase0_$(slugify "$wt").txt" "$WS/wt_status_phase8_pre_$(slugify "$wt").txt"; then
    echo "WORKING-TREE DRIFT detected in $wt — concurrent agent has been working"
    # Re-snapshot is the new baseline; never destructive cleanup of the drift.
  fi
done
```

If drift is detected, the skill **continues** with the new baseline. It does NOT halt, prompt, or revert. Per [Operator ↺ WORKING-TREE-DRIFT](OPERATOR-LIBRARY.md): "Re-snapshot the worktree's status; if changes appear from other agents, treat as if you made them; never stash/revert/overwrite."

### 4.2 Re-snapshot before each Phase 10 worktree removal

The cleanup-conductor subagent re-snapshots immediately before each `git worktree remove`:

```bash
# scripts/drop-retire-confirmed.sh fragment for each worktree-removal:
git -C "$WT_PATH" status --porcelain=v2 > "$WS/wt_status_phase10_pre_$(slugify "$WT_PATH").txt"

if ! diff -q "$BUNDLE/worktrees/$(slugify "$WT_PATH")/status.txt" "$WS/wt_status_phase10_pre_$(slugify "$WT_PATH").txt"; then
  # Drift since Phase 3 capture. The bundle's snapshot is stale.
  # Per Operator 🌳 WORKTREE-CHECK: refuse the removal until user OKs.
  echo "INCIDENT: working-tree drift detected at $WT_PATH between bundle capture and Phase 10"
  spawn_incident_responder I3
  exit 1
fi

git worktree remove "$WT_PATH"
```

> **Why halt at Phase 10 when Phase 8 continues?** Phase 8 is non-destructive to the source branches/worktrees; the skill is *reading* their content to land keepers on the rationalization branch. If a concurrent agent edited a worktree mid-Phase-8, no harm — the new baseline is captured. Phase 10 is *destructive*; if a concurrent agent edited a worktree between Phase 3 capture and Phase 10 removal, the bundle's dirty-state archive is stale and removal would silently lose the new content. Halt and surface.

### 4.3 If a concurrent agent created a NEW branch mid-run

Per [FAILURE-MODES.md](FAILURE-MODES.md) (referenced from SKILL.md): "`git branch | wc -l` count differs between two runs — Concurrent agent created or deleted a branch — Re-run Phase 2; never act on a stale inventory."

The cleanup-conductor's pre-Phase-10 check:

```bash
current_branch_count=$(git -C "$PROJECT" branch | wc -l)
phase2_branch_count=$(awk 'NR>1' "$WS/branches.tsv" | wc -l)
[ "$current_branch_count" = "$phase2_branch_count" ] || {
  echo "INCIDENT: branch count drift between Phase 2 and Phase 10 ($phase2_branch_count -> $current_branch_count)"
  spawn_incident_responder I6
  exit 1
}
```

Halts the run; the user decides whether to re-run Phase 2 + Phase 3 (refresh inventory + bundle) or to abort.

### 4.4 If a concurrent agent deleted a branch mid-run

Same as Section 4.3 with the inverse direction. The deleted branch may have been one the rationalization run was about to delete anyway (no real harm) OR it may have been one the run identified as `novel-and-accretive` and was about to recover (bad — the work is now outside the bundle's safety net). The cleanup-conductor halts and surfaces.

Per [ADVANCED-RECOVERY.md AR6](ADVANCED-RECOVERY.md#ar6-a-branch-was-deleted-before-phase-3-started): the reflog is the only safety net for branches deleted out-of-band before Phase 3. For deletions *during* the run, Phase 0's `wt_phase0.txt` baseline plus the reflog is the recovery surface.

---

## 5. Pause-and-Resume Protocol

If a higher-priority agent needs to land work mid-rationalization, the skill can pause cleanly. Every phase has a resume point per [PHASES.md § "Idempotence & Resumability"](PHASES.md).

### 5.1 The user (or their orchestrator) requests pause

The user (or another agent) sends a message on the run-id thread:

```
send_message(
  thread_id="branch-rationalization-<run-id>",
  to_agent="<this-skill-instance>",
  subject="[branch-rationalization-<run-id>] Pause requested",
  body="Higher-priority work needs the branch surface; please pause cleanly at the next phase boundary.",
  ack_required=true
)
```

The skill's main agent polls its inbox between phases (every phase boundary is a check-in point):

```python
# Pseudo-code; main agent at every phase boundary:
inbox = fetch_inbox(project_key=PROJECT_KEY, agent_name=AGENT_NAME)
for message in inbox:
    if message.subject.startswith(f"[branch-rationalization-{RUN_ID}] Pause"):
        # Pause request; ack and pause cleanly.
        acknowledge_message(project_key=PROJECT_KEY, agent_name=AGENT_NAME, message_id=message.id)
        pause_cleanly()
```

### 5.2 What "pause cleanly" means

| Phase boundary | What gets persisted |
|---|---|
| After Phase 0 | `wt_phase0.txt`, `bundle_path.txt` (placeholder), `run_id.txt` |
| After Phase 1 | + `project_profile.json` |
| After Phase 2 | + `worktrees.tsv`, `branches.tsv`, `inventory_grouped.md` |
| After Phase 3 | + bundle dir (complete) + `bundle_verification.log` |
| After Phase 4 | + `protected.tsv` |
| After Phase 5 | + `triage/batch_*.tsv` (each batch is independently complete) |
| After Phase 6 | + `triage.tsv`, `triage_decision.md`, `phase6_user_authorization.txt` |
| After Phase 7 | + `harmonization_plan.md` |
| Mid-Phase 8 | `apply_log.tsv` is appended-to per-keeper; resumption skips already-applied keepers |
| After Phase 8 | + `apply_log.tsv` complete; `partial_split_log.tsv` complete |
| After Phase 9 | + `fresh_eyes_log.md` |
| **DO NOT pause mid-Phase 10.** | Phase 10 is destructive; it must complete-or-not-start |
| After Phase 11 | + `handoff_report.md` |

The skill **never** holds Agent Mail reservations beyond a single phase boundary that hasn't completed. At every boundary, it heartbeats the reservations OR releases them (if the pause is user-requested).

### 5.3 Releasing reservations on pause

```
release_file_reservations(
  project_key="<abs-path>",
  agent_name="<this-skill-instance>",
  paths=[
    ".git/worktrees/**",
    ".git/refs/heads/**",
    ".worktree_branch_rationalization_workspace/**"
  ]
)

send_message(
  thread_id="branch-rationalization-<run-id>",
  subject="[branch-rationalization-<run-id>] Paused at Phase {N} boundary",
  body="Reservations released. Workspace persisted. Resume by re-invoking the skill with --resume."
)
```

### 5.4 Resume

The skill's intake (`assets/intake-prompt.md`) detects the persisted workspace:

```
A previous rationalization run was paused at Phase {N} on {timestamp}.

Options:
  (a) Resume from Phase {N+1} (preferred — picks up where it left off)
  (b) Discard the workspace and start fresh
  (c) Abort

Which?
```

If the user picks (a), the skill re-acquires reservations (Section 3.1) and continues from the persisted state.

> **Why no mid-Phase pausing for Phase 10?** Phase 10 is the destructive cleanup. Pausing mid-cleanup leaves the project in a partially-cleaned state — some worktrees removed, others not; some branches deleted, others not. The cleanup-conductor either runs the full plan (with the user's verbatim authorization) or doesn't start. There is no resume-mid-cleanup state.

---

## 6. The Single-Canonical-with-Reservations Strategy

This section captures the user's hard-won insight (Section 1) as actionable guidance for *future* agents reading the handoff report.

### 6.1 What to recommend in the handoff

The handoff report's "Recommendations for ongoing work" section says:

> **The rationalization is one-time cleanup. To avoid re-accumulating 200 branches:**
>
> 1. **Default: agents commit to canonical (or to a long-running integration branch like `branch-rationalization-2026-05-07` while it's open).** The single line is the source of truth.
> 2. **File reservations are the coordination primitive, not branches.** Before editing, agents call `file_reservation_paths(paths=["src/parse/**"], exclusive=true, reason="<beads-id>")`. Conflicts surface as `FILE_RESERVATION_CONFLICT` *before* commits race.
> 3. **Worktrees only for parallel-review-of-the-same-line, not parallel-development-of-different-lines.** If two agents need to compile the same code with different feature flags, two worktrees on canonical are fine. If two agents are developing two different features, they should both work on canonical with file reservations.
> 4. **Branches only for genuinely parallel features that will merge as branches.** And then: one branch per developer, not per agent invocation. Use ephemeral branches (created and deleted within the same agent task) sparingly.
> 5. **Stashes never.** See `git-stash-janitor` skill for the rationale.

### 6.2 Why this is in the rationalization skill's output, not in a separate "team conventions" doc

The rationalization skill's output is the *single moment* where the user has the most context about the cost of the agent-swarm-aftermath pattern. They've just paid for triaging 213 branches; the recommendation is most actionable here, not in a project-policy doc that may not be read.

### 6.3 The "branch debt accrued" metric

The handoff report includes:

```
## Branch debt accrued during this period

  Period: 2026-04-15 → 2026-05-07 (22 days)
  Branches created: 213
  Branches recovered as keepers: 23
  Branches deleted with no recovery: 187 (88%)
  Branches still active (protected): 3

  Branch yield: 23 / 213 = 10.8%

  If the file-reservation pattern had been used instead, branch creation
  would have been ~10–20 (one per genuine feature), and 0 would need
  rationalization.
```

This is the cost-of-inaction message; future agents reading it have a concrete benchmark.

---

## 7. Post-Run Cleanup Notification (Phase 11)

At Phase 11 handoff, the skill notifies the Agent Mail thread that the rationalization is complete, releases all reservations, and updates the beads issue to `closed`.

```
send_message(
  project_key="<abs-path>",
  thread_id="branch-rationalization-<run-id>",
  subject="[branch-rationalization-<run-id>] Completed",
  body=f"""Branch rationalization complete on {basename}.

Counts:
  Branches: {b_initial} -> {b_final}
  Worktrees: {w_initial} -> {w_final}
  Recovered keepers: {k_recovered} (of which {k_harmonized} are harmonized syntheses)

Rationalization branch: {rationalization_branch}
  Tip: {tip_sha}
  Push instruction: git push origin {rationalization_branch}
  (The skill does NOT push; the user controls that.)

Bundle: {bundle_path}
  Size: {bundle_size_human}
  Keep for 1–4 weeks; the user manages the lifecycle.
  See README.md for recovery recipes.

Reservations released. Beads issue {beads_id} closed.

For future agents: see Section 6 of MULTI-AGENT-COORDINATION.md for the
file-reservation pattern that scales beyond 200 branches.""",
  ack_required=False
)

release_file_reservations(
  project_key="<abs-path>",
  agent_name="<this-skill-instance>",
  paths=[
    ".git/worktrees/**",
    ".git/refs/heads/**",
    ".worktree_branch_rationalization_workspace/**"
  ]
)

br close $RUN_ID --reason "..."
```

---

## 8. Concurrent NTM Swarms (Optional)

If the user is *already* running an NTM swarm on this project, the skill's coordination model needs to integrate.

### 8.1 NTM-aware pre-run handshake

```bash
# At Phase 0:
if command -v ntm >/dev/null 2>&1 && [ -d "$HOME/.ntm/sessions/$BASENAME" ]; then
  echo "NTM swarm detected on $BASENAME; checking active panes..."
  ntm status "$BASENAME" --json > "$WS/ntm_status.json"

  # Each pane is an active agent; each pane's CWD may be a worktree.
  active_pane_count=$(jq '.panes | length' "$WS/ntm_status.json")
  echo "$active_pane_count active panes; their worktrees are auto-protected."
fi
```

The skill auto-protects every worktree currently CWD'd-to by an NTM pane. The protected.tsv includes a `reason=ntm-active-pane:<pane-id>` annotation.

### 8.2 NTM message-bus integration

NTM uses its own message bus (per the `ntm` skill). The branch-rationalization skill bridges via Agent Mail's run-id thread:

```bash
# At Phase 0.5:
ntm send "$BASENAME" \
  --pane-tag swarm \
  --message "[branch-rationalization-$RUN_ID] Starting rationalization. Will not touch any worktree currently in use by an NTM pane. Reservations on .git/refs/heads/** and .git/worktrees/** are exclusive for the duration of the run; if you need to land a branch, coordinate via the run-id thread on Agent Mail."
```

### 8.3 NTM is optional

The skill doesn't *require* NTM to be present. The default execution is single-Claude-Code-session with Task-tool subagents (per [SKILL.md "Parallelism Model"](../SKILL.md#parallelism-model)). NTM is one of several orchestration topologies; the coordination protocol in Sections 2–5 works regardless.

---

## 9. Anti-Patterns in Multi-Agent Coordination

| Why |
|---|
| Skipping the pre-run handshake (Section 2) | Surprise other agents with `FILE_RESERVATION_CONFLICT` errors mid-task. They lose work; you make enemies |
| Holding reservations across phase boundaries that completed | Wedges the swarm needlessly. Heartbeat to extend; release at handoff |
| Using `exclusive=false` for the destructive surface | Agent Mail will allow another agent to also reserve `.git/refs/heads/**`; if they delete a branch you were about to recover, the work is lost |
| Auto-fixing concurrent-agent drift (stashing it, reverting it, overwriting it) | Per AGENTS.md "Note for Codex/GPT-5.5": treat as if you made it. Re-snapshot, never destructive |
| Halting Phase 8 on every drift detection | Phase 8 is non-destructive to source branches; drift is expected. Re-snapshot and continue |
| NOT halting Phase 10 on drift detection | Phase 10 is destructive; drift means the bundle's snapshot is stale; removal would silently lose work |
| Pausing mid-Phase 10 | Destructive cleanup must run-or-not-start; mid-cleanup pause leaves the repo half-cleaned with no resume path |
| Telling future agents "branches per agent is fine because the skill cleans them up" | The skill is one-time cleanup; the file-reservation pattern (Section 6) is the steady-state solution. Promote it in the handoff |
| Using NTM-only coordination without Agent Mail | NTM messages don't survive sessions; Agent Mail thread + beads issue are the durable record. Use Agent Mail as the system of record, NTM as the orchestration layer |

---

## 10. Cross-links

- Why integrate at all: [INTEGRATION.md § Why integrate](INTEGRATION.md)
- Working-tree-drift discipline: [Operator ↺ WORKING-TREE-DRIFT in OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md), [WORKTREE-STATE.md](WORKTREE-STATE.md), AGENTS.md "Note for Codex/GPT-5.5"
- Per-phase resumption: [PHASES.md § Idempotence & Resumability](PHASES.md)
- Bundle integrity verification at Phase 10: [FRESH-EYES-PROMPTS.md § Phase 9 cleanup-specific prompt](FRESH-EYES-PROMPTS.md)
- Force-push detection mid-run: [ADVANCED-RECOVERY.md AR2](ADVANCED-RECOVERY.md), incident I12 in `subagents/incident-responder.md`
- Branch deletion mid-run: [ADVANCED-RECOVERY.md AR6](ADVANCED-RECOVERY.md), incident I6 in `subagents/incident-responder.md`
