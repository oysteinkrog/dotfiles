# Swarm

Start and manage a swarm of coding agents that implement beads from the issue tracker.

Each agent is autonomous and fungible: it picks a bead, implements it, commits, and exits.
ntm auto-restarts the agent with fresh context. No coordinator needed.

## When to activate

Activate when the user says:
- "swarm" / "start swarm" / "launch swarm" / "run swarm"
- "assign bead X" / "run bead X"
- "start agents" / "spawn agents"

## Arguments

- `$ARGUMENTS` — optional: agent count (e.g. `4`), bead ID (e.g. `bd-xxx`), or `kill`/`stop`/`status`

## Instructions

### Determine intent from arguments

- No arguments or a number → **start/spawn** a swarm session
- A bead ID (starts with `bd-`) → **assign that single bead** to an idle agent
- `kill` or `stop` → **stop** the active swarm session
- `status` → delegate to `/swarm-status`

---

### A. Start a swarm session

#### 1. Pre-flight

```bash
# Check agent-mail
curl -sf http://127.0.0.1:8765/api/ > /dev/null 2>&1 && echo "agent-mail: OK" || echo "agent-mail: NOT RUNNING — start with 'am'"

# Show what's ready and the top pick
bv -robot-next 2>/dev/null | jq '{id, title, score, unblocks, reasons}'

# Show parallel execution tracks
bv -robot-plan 2>/dev/null | jq '{total_actionable: .plan.total_actionable, total_blocked: .plan.total_blocked, tracks: (.plan.tracks | length), highest_impact: .plan.summary}'
```

If agent-mail is not running, warn and suggest `am`.

#### 2. Choose a session name

Derive from the current directory name or let the user override:

```bash
SESSION_NAME="swarm-$(basename $(pwd))"
```

#### 3. Write the initial prompt

Write to `/tmp/swarm-prompt.md`. This is sent once to each fresh agent. The agent self-assigns, does one bead, then exits. ntm `--auto-restart` gives the next agent fresh context.

```
Read CLAUDE.md in the repo root. Follow ALL instructions there.

## Pick your bead

Use bv to find the highest-priority ready bead:
  bv -robot-next 2>/dev/null

If it returns a bead, claim it:
  br update <BEAD_ID> --status in_progress

If no beads are ready (all blocked or closed), exit immediately with /exit.

## Read the bead

  br show <BEAD_ID> --json 2>/dev/null

Read description, acceptance_criteria, notes, and labels. Then:
  bv -robot-related <BEAD_ID> 2>/dev/null | jq '.categories'

## Adapt to the bead

Check labels and description to understand what kind of work this is:

- **Spikes/research** (labels include "spike", or title starts with "Spike:"):
  Research and document findings, not production code.
  Record findings: br update <BEAD_ID> --notes "## Findings\n..."

- **Implementation**: Read existing code for reference behavior first.
  Follow the language, framework, and architectural conventions in the project.

- **Docs/CI/infra**: Follow existing repo conventions. Don't over-engineer.

The bead's description and the project's CLAUDE.md tell you everything you need.

## Before editing files

Check for conflicts:
  bv -robot-impact <files-you-plan-to-edit> 2>/dev/null

If risk_level is "high" or "critical", check agent-mail for active reservations before proceeding.

## Implement

1. Read and understand related existing code
2. Implement according to acceptance criteria
3. Run the project's standard checks (tests, linting — whatever CLAUDE.md specifies)
4. Commit ONLY files you changed:
   git add <specific files>
   git commit -m "feat(<BEAD_ID>): short description"
5. Close the bead:
   br close <BEAD_ID>
6. Exit to get fresh context for the next bead:
   /exit
```

#### 4. Spawn session with auto-restart

```bash
ntm spawn $SESSION_NAME --cc=$AGENT_COUNT --no-user --stagger-mode=smart --auto-restart --no-cass-check
```

Then send the initial prompt to all agents:

```bash
ntm send $SESSION_NAME --all --file=/tmp/swarm-prompt.md --no-cass-check
```

#### 5. Report

Tell the user:
- Session name and agent count
- Each agent picks its own bead via `bv -robot-next`, implements it, commits, exits
- `--auto-restart` respawns each agent with fresh context — no coordinator needed
- Monitor: `ntm activity $SESSION_NAME --watch`
- Progress: `/swarm-status`
- Stop: `/swarm kill`

---

### B. Assign a single bead

#### 1. Read the bead

```bash
br show $BEAD_ID --json 2>/dev/null
bv -robot-related $BEAD_ID 2>/dev/null | jq '.categories'
```

If not found or already closed, tell the user. Check dependencies — warn if any blocker is still open.

#### 2. Find target session and idle pane

```bash
ntm list 2>/dev/null
ntm activity <session> 2>/dev/null
```

Pick the first idle (WAITING) pane. If no session is running, offer to spawn one.

#### 3. Build a self-contained prompt

Write `/tmp/bead-$BEAD_ID.md` — same structure as the prompt in A.3, but skip the `bv -robot-next` step and inline the bead details directly (description, acceptance criteria, notes, labels, dependencies, related beads).

#### 4. Reset context and assign

```bash
ntm interrupt <session> 2>/dev/null
sleep 3
ntm send <session> --pane=<N> --file=/tmp/bead-$BEAD_ID.md --no-cass-check
```

#### 5. Report

Tell the user which pane got the bead and how to monitor it.

---

### C. Stop the swarm

```bash
ntm list 2>/dev/null
ntm kill <session> 2>/dev/null || true
echo "Swarm stopped."
bv -robot-next 2>/dev/null | jq '{id, title, unblocks}'
```

Report how many beads are still open/ready.
