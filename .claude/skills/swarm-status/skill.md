# Swarm Status

Show current swarm progress: teammate activity, task + bead state, and stuck work.

## When to activate

Activate when the user says:
- "swarm status" / "check swarm" / "swarm progress"
- "how's the swarm" / "agent status"

## Instructions

### 1. Teammates and tasks

```
TaskList
```

Report:
- How many tasks are `pending` (ready, awaiting a teammate) vs `in_progress` (claimed)
  vs `completed` vs `deleted`.
- For each `in_progress` task: its `owner`.
- For each `pending` task: whether `blockedBy` is non-empty (blocked) or empty
  (claimable by the next idle teammate).

For any `in_progress` task that looks stuck, `TaskGet({ taskId })` for full
context + teammate comments; `TaskOutput({ taskId })` to see live output if helpful.

### 2. Bead progress (via bv)

```bash
# Quick health overview
bv -robot-triage 2>/dev/null | jq '{
  actionable: .triage.quick_ref.actionable_count,
  blocked: .triage.quick_ref.blocked_count,
  top_picks: [.triage.quick_ref.top_picks[]? | {id, title, unblocks}],
  health: .triage.project_health.status
}'

# Any alerts?
bv -robot-alerts --severity=critical 2>/dev/null | jq '.alerts[:5]'
```

### 3. Recent commits

```bash
git log --oneline -15
```

Verify each commit references a bead ID. Flag any commits that don't.

### 4. Drift check (if baseline exists)

```bash
bv -check-drift 2>/dev/null
```

### 5. Orphaned files check

```bash
git status --short | grep '^??' | head -20
```

Flag any untracked test files — teammates often write files but crash before committing.
These need manual build/test/commit rescue.

### 6. Stuck-task rescue (releases reservations too)

A task is stuck when its `owner` points to a teammate that is no longer running.
Rescue sequence:

1. Identify stuck tasks: `in_progress` with owner = `<name>` where `<name>` is not
   in the set of running backgrounded Agents.
2. **Release file reservations first**, then reset the task. A crashed teammate
   leaves its `file_reservation_paths` entries locked, which blocks every other
   teammate that needs those paths. Via the agent-mail MCP:

   ```
   # List reservations held by the crashed owner, then release:
   mcp-agent-mail.release_file_reservations({
     agent: "<crashed-owner>",
     paths: [<their held paths>]
   })
   ```

3. Reset the task so a fresh teammate can claim it:

   ```
   TaskUpdate({ taskId, owner: null, status: "pending" })
   ```

4. If the bead was marked `in_progress` in `br`, reset it:
   `br update <bead-id> --status open`.
5. If the crashed teammate had committed but not closed the bead (check `git log`
   for the bead ID), close it manually: `br close <bead-id>`.

### 7. Summary

Present:
- Teammate count: running / crashed / idle
- Tasks: pending (claimable / blocked) / in_progress / completed
- Stuck tasks rescued (if any)
- Bead backlog: actionable / blocked / project health
- Critical alerts
- Recent commits with bead ID verification
- Orphaned untracked files
- Next highest-impact bead
