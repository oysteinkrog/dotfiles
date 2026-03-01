# User-Level Claude Code Instructions

## MCP Agent Mail (mcp-agent-mail)

Agent-mail is installed at `~/mcp_agent_mail`. Start the server with `am` (shell alias).
Server runs on `http://127.0.0.1:8765/api/`. Web UI at `http://127.0.0.1:8765/mail`.

### Setup for new projects

Add to `.mcp.json` in the project root:
```json
{
  "mcpServers": {
    "mcp-agent-mail": {
      "type": "http",
      "url": "http://127.0.0.1:8765/api/",
      "headers": {
        "Authorization": "Bearer 459f9002c2f4ca0b206a9579e0d40e8d6124f3ab162c52f73251d4e42a015dfc"
      }
    }
  }
}
```

### Key tools
- `ensure_project` — Register project before any messaging
- `register_agent` — Create agent identity (name + role)
- `send_message` — Post messages with thread support
- `fetch_inbox` — Retrieve messages for an agent
- `acknowledge_message` — Mark messages read
- `search_messages` — Full-text search
- `file_reservation_paths` — Reserve files to avoid conflicts between agents
- `release_file_reservations` — Unlock reserved paths
- `macro_start_session` — Initialize agent workflow (convenience)

## NTM (Named Tmux Manager)

Installed at `~/.bun/bin/ntm`. Manages tmux sessions with multiple AI coding agents.

### Key commands
```bash
ntm spawn <session> --cc=N --cod=N --gmi=N   # Create session with N agents of each type
ntm attach <session>                           # Attach to session
ntm send <session> "prompt" --all              # Broadcast prompt to all agents
ntm send <session> "prompt" --cc               # Send to Claude Code agents only
ntm send <session> "prompt" --pane=2           # Send to specific pane
ntm palette                                    # Open TUI command palette
ntm activity <session>                         # Show agent activity states
ntm list                                       # List all sessions
ntm kill <session>                             # Kill session
```

### Agent types
- `--cc=N` or `--cc=N:model` — Claude Code agents (e.g., `--cc=2:opus`)
- `--cod=N` — Codex CLI agents
- `--gmi=N` — Gemini CLI agents

### Recipes
```bash
ntm spawn <session> -r quick-claude            # 1 CC agent
ntm spawn <session> -r full-stack              # Mixed agents
ntm spawn <session> -r balanced                # Balanced mix
ntm recipes list                               # Show all recipes
```

### With agent-mail + bv coordination
Use ntm to spawn agents, bv for triage/work assignment, and agent-mail for message routing.
Agents register with `macro_start_session`, coordinate via `send_message`/`fetch_inbox`,
and reserve files with `file_reservation_paths` to avoid conflicts.

## BV (Beads Viewer)

Installed at `~/go/bin/bv`. TUI viewer + robot API for the beads issue tracker (br).
Same author as mcp-agent-mail (Dicklesworthstone).

### Key commands
```bash
bv                                    # Launch TUI viewer
bv -robot-triage                      # Unified triage as JSON (for AI agents)
bv -robot-triage-by-label             # Triage grouped by label
bv -robot-triage-by-track             # Triage grouped by execution track
bv -agent-brief <dir>                 # Export agent brief bundle (triage.json, brief.md, etc.)
bv -robot-suggest                     # Smart suggestions (duplicates, deps, labels, cycles)
bv -search "query"                    # Semantic search across beads
bv -robot-sprint-suggest              # Suggest sprint composition
bv -robot-alerts                      # Show alerts (stale issues, etc.)
bv -check-drift                       # Check drift from baseline
bv -save-baseline "description"       # Save current metrics as baseline
```

### Agent workflow
1. `bv -robot-triage` to get prioritized work items
2. `ntm spawn` to create agent session
3. `ntm assign` or `ntm send` to distribute work from triage
4. Agents use agent-mail for coordination, br for bead updates

## Agent Swarm Rules

### Atomic commits per work unit
When writing prompts for swarm agents (ntm, teammates, or any autonomous agent), **always
include explicit git commit instructions**. Each bead/task/work-unit MUST be committed
atomically before moving to the next. Example instruction to include in agent prompts:

```
After closing each bead, IMMEDIATELY commit your changes:
  git add <specific files you changed>
  git commit -m "feat(bead-id): short description"
Do NOT batch multiple beads into one commit. Each bead = one atomic commit.
```

**Why:** Without this, agents implement code and mark tasks closed but never commit.
You end up with thousands of lines across dozens of files as one uncommitted blob,
with no way to separate changes per task after the fact.

### Other swarm prompt essentials
- Always use `--no-cass-check` with `ntm send` to avoid CASS parse errors
- Include the cmd.exe test command for WSL GPU projects
- Tell agents to read CLAUDE.md first
- Specify file paths agents will touch so file reservations can prevent conflicts
