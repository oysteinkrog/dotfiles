# Swarm (Execution)

Start and manage an **execution swarm** — Claude Code teammates implementing beads from
`br` (beads_rust). See `~/.claude/CLAUDE.md` "Two swarm shapes" for why execution
teammates are terminal/fungible (NOT continued with `SendMessage`).

Each teammate: claims one task → implements one bead → commits to the shared branch →
closes the bead → marks the task completed → exits. The leader spawns replacements as
new tasks become unblocked. The one-bead-then-exit pattern keeps each teammate's
context window clean.

All orchestration uses Claude Code built-ins: `Agent`, `TaskCreate`, `TaskUpdate`,
`TaskList`, `TaskGet`, `TeamCreate`. `SendMessage` is NOT used for execution teammates.

## When to activate

Activate when the user says:
- "swarm" / "start swarm" / "launch swarm" / "run swarm"
- "assign bead X" / "run bead X"
- "start agents" / "spawn agents"

## Arguments

- `$ARGUMENTS` — optional: agent count (e.g. `4`), bead ID (e.g. `bd-xxx`), or `kill`/`stop`/`status`

## Instructions

### Determine intent from arguments

- No arguments or a number → **start/spawn** a swarm (section A)
- A bead ID (starts with `bd-`) → **assign that single bead** (section B)
- `kill` or `stop` → **stop** the swarm (section C)
- `status` → delegate to `/swarm-status`

---

### A. Start a swarm

#### 1. Pre-flight

```bash
# Start agent-mail if not running (required for file reservations)
curl -sf http://127.0.0.1:8765/api/health > /dev/null 2>&1 && echo "Agent-mail: running" || { echo "Starting agent-mail..."; cd ~/mcp_agent_mail && nohup python3 -m uvicorn main:app --host 127.0.0.1 --port 8765 > /dev/null 2>&1 & sleep 2; }

# Ensure project .mcp.json has agent-mail configured
python3 -c "
import json, os
p = '.mcp.json'
cfg = json.load(open(p)) if os.path.exists(p) else {'mcpServers': {}}
if 'mcp-agent-mail' not in cfg.get('mcpServers', {}):
    cfg.setdefault('mcpServers', {})['mcp-agent-mail'] = {
        'type': 'http', 'url': 'http://127.0.0.1:8765/api/',
        'headers': {'Authorization': 'Bearer \${MCP_AGENT_MAIL_TOKEN}'}
    }
    json.dump(cfg, open(p, 'w'), indent=2)
    print('Added agent-mail to .mcp.json')
else:
    print('Agent-mail already in .mcp.json')
"

# Show what's ready
bv -robot-next 2>/dev/null | jq '{id, title, score, unblocks, reasons}'

# Show parallel execution tracks
bv -robot-plan 2>/dev/null | jq '{total_actionable: .plan.total_actionable, total_blocked: .plan.total_blocked, tracks: (.plan.tracks | length), highest_impact: .plan.summary}'
```

#### 2. Choose a team name

Use a fresh, collision-resistant name so stale state from prior runs can't leak in.
Recommended: `<dir>-<branch>-<epoch>`:

```bash
TEAM_NAME="$(basename $(pwd))-$(git branch --show-current | tr / -)-$(date +%s)"
```

Create the team:

```
TeamCreate({ name: TEAM_NAME })
```

If the user wants to **resume** an existing run, first clean stale state (see section D).

#### 3. Seed the bead backlog as tasks

Seed **all open beads in the intended scope** (not just `br ready`) — otherwise the
`blockedBy` graph you wire in step 3c has no downstream tasks to unblock.

```bash
# a) Dump all open beads in scope (adjust --epic / --status as needed)
br list --status open --json 2>/dev/null > /tmp/swarm-beads.json

# b) Dump the dependency graph (bead → bead)
br dep tree --json 2>/dev/null > /tmp/swarm-deps.json
```

Then, for each bead, the leader calls `TaskCreate` and keeps the `bead_id → taskId`
mapping so blockedBy can be translated from bead-space to task-space:

```
# Pseudocode the leader executes:
bead_to_task = {}
for bead in beads:
    t = TaskCreate({
      subject: f"bd-{bead.id}: {bead.title}",
      description: "<teammate prompt from section 4, with {BEAD_ID} bound to this bead>",
      activeForm: f"Implementing bd-{bead.id}",
    })
    bead_to_task[bead.id] = t.id

# c) Wire dependencies — TaskUpdate.addBlockedBy takes TASK IDs, not bead IDs
for bead in beads:
    blockers = [bead_to_task[dep] for dep in bead.blocked_by if dep in bead_to_task]
    if blockers:
        TaskUpdate({ taskId: bead_to_task[bead.id], addBlockedBy: blockers })
```

Now `TaskList` returns the correct ready-set (tasks with no unresolved blockers),
and downstream tasks become claimable automatically as their predecessors complete.

#### 4. Teammate prompt template

Every teammate gets this prompt shape. Keep compact to preserve teammate context budget.

```
Read CLAUDE.md in the repo root. Follow ALL instructions there.

You are a swarm teammate in team "{TEAM_NAME}". You will implement ONE bead, commit,
close it, mark your task completed, and exit. Do not pick up additional beads — the
leader spawns a fresh replacement teammate for the next one. This keeps your context
window clean (fresh-context property).

## Claim work (atomic)

1. TaskList — find the lowest-ID task with: status=pending, owner=null, blockedBy=[].
2. Claim: TaskUpdate({ taskId, owner: "<your-name>", status: "in_progress" }).
3. Verify you won the claim (race guard):
   t = TaskGet({ taskId })
   if t.owner != "<your-name>":
     # Another teammate claimed it first. Start over at step 1.
4. Extract {BEAD_ID} from the task subject ("bd-XXX: <title>").

## Implement the bead

Claim in beads:   br update {BEAD_ID} --status in_progress
Get details:      br show {BEAD_ID} --json 2>/dev/null
Check related:    bv -robot-related {BEAD_ID} 2>/dev/null | jq '.categories'

## File Coordination (MANDATORY)

Before editing ANY file, reserve it via the mcp-agent-mail MCP:
1. Call `file_reservation_paths` with the list of files you plan to edit.
2. If any file is already reserved by another teammate, STOP — release any
   reservations you did obtain, set your task back to pending + owner=null via
   TaskUpdate, then exit. The leader will reassign it later when the other
   teammate finishes and releases its files.
3. After committing, call `release_file_reservations` for your files.

## Rules

1. Read production code first. Understand actual behavior before writing anything.
2. Match existing project conventions (see CLAUDE.md).
3. Test/file folders must mirror source structure.
4. Follow .editorconfig and analyzer rules.
5. Reserve files before editing. Never edit unreserved files.

## Steps

1. Read and understand related existing code thoroughly.
2. Reserve all files you plan to edit via agent-mail file_reservation_paths.
3. Implement according to acceptance criteria.
4. Commit IMMEDIATELY after writing files (before full test suite):
     git add <specific files>
     git commit -m "<area>({BEAD_ID}): short description"
5. Run project checks (tests, linting — see CLAUDE.md).
   - For .NET/MSBuild projects: pass `--no-dependencies` (or equivalent) when
     multiple teammates may be building simultaneously, to avoid MSB3021 lock
     conflicts.
6. If checks fail, fix and amend: git add <files> && git commit --amend --no-edit
7. Release file reservations via agent-mail release_file_reservations.
8. Close: br close {BEAD_ID}
9. Mark your task completed: TaskUpdate({ taskId, status: "completed" })
10. Exit.

## On abort / shutdown (leader sent a stop signal)

Do NOT mark your task completed unless step 8 (br close) succeeded. Instead:
1. If mid-edit: decide whether the partial work is worth keeping.
   - Keep: finish the write, commit, then follow the completion path above.
   - Discard: `git restore` the files; proceed to release step.
2. Release all file reservations via release_file_reservations.
3. TaskUpdate({ taskId, owner: null, status: "pending" }) — the leader will
   reclaim or reassign.
4. Exit.
```

Note: `<area>` follows project git conventions (e.g., `test/`, `model/`, `vm/`).

#### 5. Spawn teammates

Send one `Agent` tool call per teammate in a SINGLE leader message so they run
concurrently. **Never** pass `isolation: "worktree"` for execution-swarm teammates
(see global CLAUDE.md "Agent Swarm Rules").

```
Agent({
  subagent_type: "general-purpose",
  name: "swarm-1",
  team_name: TEAM_NAME,
  run_in_background: true,
  prompt: "<the template from section 4>"
})
Agent({ ..., name: "swarm-2", ... })
# ... up to $AGENT_COUNT
```

Each teammate self-claims the next available task. The leader does not need to
pre-assign specific beads to specific teammates.

**Targeted assignment** (if you want a specific bead to go to a specific teammate):
pre-set `owner` on the task before spawning:
`TaskUpdate({ taskId, owner: "swarm-1" })`. Execution teammates are still
fungible — do not use `SendMessage` to redirect them mid-task.

#### 6. Monitor loop

```
TaskList                       # progress + owners + blocked-by
TaskGet({ taskId })            # full detail + teammate comments
```

When a teammate completes and exits, the harness notifies the leader. On each
notification the leader should:
1. Look for newly-unblocked tasks (predecessor just completed → successors now
   claimable).
2. If unclaimed claimable tasks exist AND running teammates < target, spawn
   replacement teammates using the same template.
3. Check for orphaned files: `git status --short | grep '^??'`. Rescue manually.
4. Look for stuck in-progress tasks whose owner is no longer running (see
   `/swarm-status` stuck-task rescue).

If the leader hasn't received notifications for a while and the pool isn't at
capacity, `ScheduleWakeup` with a sensible delay to re-check `TaskList`. Don't
busy-poll; the notifications are the primary signal.

#### Known issues

- **Orphaned files**: Teammates may hit context limits before committing. Monitor
  `git status --short` after each batch.
- **Concurrent build locks (MSBuild)**: Tell teammates to build with
  `--no-dependencies` in the prompt template (already embedded in section 4, step 5).
- **Beads committed but not closed**: Check `git log` for bead IDs and close manually.
- **Task claimed but teammate crashed**: see stuck-task rescue in `/swarm-status`.

#### 7. Report

Tell the user:
- Team name and teammate count
- How many tasks seeded / unblocked / blocked
- Monitor progress: `/swarm-status`
- Stop: `/swarm kill`

---

### B. Assign a single bead

#### 1. Read the bead

```bash
br show $BEAD_ID --json 2>/dev/null
bv -robot-related $BEAD_ID 2>/dev/null | jq '.categories'
```

If not found or already closed, tell the user. Warn if blockers are still open.

#### 2. Ensure team + task exist

```
# Ensure the team exists (idempotent; create if missing)
TeamCreate({ name: TEAM_NAME })

# Look for an existing task for this bead
TaskList
```

If no matching `bd-$BEAD_ID:` task exists, `TaskCreate({ subject: "bd-$BEAD_ID: <title>", description: "<full teammate prompt from A.4 with {BEAD_ID} inlined>" })`.

#### 3. Spawn one teammate

```
Agent({
  subagent_type: "general-purpose",
  name: "swarm-$BEAD_ID",
  team_name: TEAM_NAME,
  run_in_background: true,
  prompt: "<teammate template from A.4 with {BEAD_ID} already bound>"
})
```

---

### C. Stop the swarm

1. For each running backgrounded teammate, signal a stop via a fresh `Agent`
   instruction OR `TaskStop` if the harness supports interrupting by ID. Give
   them the "On abort / shutdown" script from A.4 so they release reservations
   and return their task to `pending` (NOT completed — completed implies the
   bead was actually closed in `br`).
2. Wait for notifications. If a teammate is truly stuck, `TaskStop({ taskId })`.
3. Run the stuck-task rescue from `/swarm-status` to release orphaned file
   reservations and reset any in-progress tasks whose owner is gone.
4. Report open beads:

```bash
bv -robot-next 2>/dev/null | jq '{id, title, unblocks}'
```

---

### D. Resume / clean stale state

If the user wants to reuse an existing team name:

1. `TaskList` — find tasks whose `owner` points to a teammate that is no longer
   running. For each, run the stuck-task rescue from `/swarm-status` (release
   file reservations held by that owner + reset task to `pending`, `owner=null`).
2. Drop completed tasks (`TaskUpdate({ status: "deleted" })`) if they'd pollute
   the next run's `TaskList` output.
3. Optionally re-seed new beads that became ready since the last run.
