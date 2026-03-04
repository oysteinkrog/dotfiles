# Swarm

Start and manage a swarm of coding agents that implement beads from the issue tracker.

Each agent is autonomous and fungible: it picks a bead, implements it, commits, and exits.
`ntm --auto-restart` respawns bare Claude Code, then `ntm assign --watch` detects the
idle agent and sends the next bead assignment with the prompt template. Fresh context per bead.

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

```bash
SESSION_NAME="swarm-$(basename $(pwd))"
```

#### 3. Write the prompt template

Write to `/tmp/swarm-template.md`. This is sent by `ntm assign --watch` each time
an agent goes idle. The agent implements one bead, commits, and exits.

```
Read CLAUDE.md in the repo root. Follow ALL instructions there.

## Your bead: {BEAD_ID} — {TITLE}

Get full details:
  br show {BEAD_ID} --json 2>/dev/null

Read description, acceptance_criteria, notes, and labels.

Check related work:
  bv -robot-related {BEAD_ID} 2>/dev/null | jq '.categories'

## Adapt to the bead

Check labels and description to determine approach:

- **Spikes/research** (labels include "spike"): Research and document findings.
  Record: br update {BEAD_ID} --notes "## Findings\n..."

- **Implementation**: Read existing code for reference behavior first.
  Follow the language, framework, and conventions in the project.

- **Docs/CI/infra**: Follow existing repo conventions.

## Before editing files

Check for conflicts:
  bv -robot-impact <files-you-plan-to-edit> 2>/dev/null

## Implement

1. Read and understand related existing code
2. Implement according to acceptance criteria
3. Run the project's standard checks (tests, linting — see CLAUDE.md)
4. Commit ONLY files you changed:
   git add <specific files>
   git commit -m "feat({BEAD_ID}): short description"
5. Close the bead: br close {BEAD_ID}
6. Exit for fresh context: /exit
```

#### 4. Bump max_restarts

Default is 3 — not enough for a full swarm. Set in ntm config:

```bash
mkdir -p ~/.config/ntm
# Add or update [resilience] section
grep -q '^\[resilience\]' ~/.config/ntm/config.toml 2>/dev/null || echo -e '\n[resilience]\nmax_restarts = 100' >> ~/.config/ntm/config.toml
```

Or tell the user to set `max_restarts = 100` in `~/.config/ntm/config.toml`.

#### 5. Spawn and start watch mode

Two commands, run in separate terminals (or the second in background):

**Terminal 1: Spawn agents**
```bash
ntm spawn $SESSION_NAME --cc=$AGENT_COUNT --no-user --auto-restart --stagger-mode=smart --no-cass-check
```

**Terminal 2: Watch mode (assigns beads to idle agents)**
```bash
ntm assign $SESSION_NAME --watch --strategy=dependency --stop-when-done \
  --template-file=/tmp/swarm-template.md --no-cass-check
```

The flow per agent:
1. `--auto-restart` spawns bare Claude Code (fresh context)
2. `--watch` detects idle agent, sends template with next bead
3. Agent implements bead, commits, closes, exits via `/exit`
4. Go to step 1

#### 6. Report

Tell the user:
- Session name and agent count
- Two processes needed: `ntm spawn` (manages agents) + `ntm assign --watch` (assigns work)
- Each agent gets fresh context per bead (exit + auto-restart)
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

If not found or already closed, tell the user. Warn if blockers are still open.

#### 2. Find target session and idle pane

```bash
ntm list 2>/dev/null
ntm activity <session> 2>/dev/null
```

Pick first idle (WAITING) pane. If no session running, offer to spawn one.

#### 3. Build a self-contained prompt

Write `/tmp/bead-$BEAD_ID.md` — same structure as template in A.3, but with bead details
inlined (description, acceptance criteria, notes, labels, related beads).

#### 4. Assign

```bash
ntm assign <session> --pane=<N> --beads=$BEAD_ID --template-file=/tmp/bead-$BEAD_ID.md --no-cass-check
```

---

### C. Stop the swarm

```bash
ntm list 2>/dev/null
ntm kill <session> 2>/dev/null || true
bv -robot-next 2>/dev/null | jq '{id, title, unblocks}'
```

Report how many beads are still open/ready.
