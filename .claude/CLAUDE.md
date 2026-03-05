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

### Swarm orchestration

**Spawning with isolation:**
```bash
ntm spawn <session> --cc=4 --no-user --worktrees --stagger-mode=smart --no-cass-check
```
- `--worktrees` gives each agent its own git branch (prevents file conflicts)
- `--stagger-mode=smart` avoids API rate limit thundering herd
- `--no-user` makes all panes agent panes (no user pane)
- `--no-cass-check` always required to avoid CASS parse errors

**Dependency-aware continuous assignment (watch mode):**
```bash
ntm assign <session> --watch --strategy=dependency --stop-when-done \
  --template-file=prompts/implement.md --no-cass-check
```
- Queries `bv -robot-triage` for prioritized ready beads
- Assigns to idle agents, waits for completion, assigns next
- `--strategy=dependency` prioritizes beads that unblock the most downstream work
- `--stop-when-done` exits when no beads remain

**Direct bead assignment:**
```bash
ntm assign <session> --pane=3 --beads=bd-123 --no-cass-check
```

**Fresh context between beads:**
```bash
ntm interrupt <session>           # Ctrl+C to all agent panes (resets Claude Code context)
ntm interrupt <session> --pane=3  # Reset specific pane only (not yet supported — interrupt is session-wide)
```

**Monitoring:**
```bash
ntm activity <session> --watch    # Real-time agent states
ntm changes <session>             # File changes per agent
ntm conflicts <session>           # File reservation conflicts
ntm worktrees merge <agent>       # Merge agent's worktree branch to main
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
bv -robot-plan                        # Execution plan with parallel tracks
bv -robot-next                        # Single top recommendation with claim command
bv -robot-related <bead-id>           # Related beads (file overlap, deps, commit overlap)
bv -robot-blocker-chain <bead-id>     # Full blocker chain to root blockers
bv -agent-brief <dir>                 # Export agent brief bundle (triage.json, brief.md, etc.)
bv -robot-suggest                     # Smart suggestions (duplicates, deps, labels, cycles)
bv -search "query"                    # Semantic search across beads
bv -robot-sprint-suggest              # Suggest sprint composition
bv -robot-alerts                      # Show alerts (stale issues, etc.)
bv -check-drift                       # Check drift from baseline
bv -save-baseline "description"       # Save current metrics as baseline
```

### br (beads_rust) key commands
```bash
br ready                              # List unblocked beads
br ready --json                       # Same, machine-readable (filter stderr: 2>/dev/null)
br blocked                            # List blocked beads with their blockers
br show <bead-id>                     # Full bead detail (text)
br show <bead-id> --json              # Full bead detail (JSON: description, acceptance_criteria, notes, deps)
br dep list <bead-id>                 # List dependencies for a bead
br update <bead-id> --status in_progress  # Claim a bead
br close <bead-id>                    # Close a bead when done
br update <bead-id> --notes "..."     # Add notes to a bead
```

### Agent workflow
1. `bv -robot-triage` to get prioritized work items
2. `ntm spawn` to create agent session
3. `ntm assign` or `ntm send` to distribute work from triage
4. Agents use agent-mail for coordination, br for bead updates

## Google Workspace CLI (gws)

Installed globally via `npm install -g @googleworkspace/cli`. One CLI for all Google Workspace APIs.
**Note:** `gws` conflicts with the fish alias `gws` (`git status --short`). Use full path in MCP config. On the CLI, the fish function takes priority.

### Auth
```bash
gws auth setup    # one-time: provide OAuth client_secret.json from Google Cloud Console
gws auth login    # subsequent logins
gws auth status   # check current auth state
```
Credentials stored at `~/.config/gws/`. Client secret goes at `~/.config/gws/client_secret.json`.

### MCP server (for AI agents)
Configured in `~/.claude/mcp-servers.json` as stdio (uses full path to avoid fish alias conflict):
```json
"google-workspace": {
  "type": "stdio",
  "command": "/c/users/oystein/.nvm/versions/node/v22.14.0/bin/gws",
  "args": ["mcp", "-s", "all", "-w", "-e"]
}
```
Flags: `-s all` exposes all services, `-w` enables workflows, `-e` enables helpers.
To limit services: `-s drive,gmail,calendar`.

### Key info
- `user_google_email` is `oystein@initialforce.com` (not `@swingcatalyst.com`)
- CLI: `gws drive files list --params '{"pageSize": 5}'`, `gws schema drive.files.list`
- Outputs structured JSON, supports `--format table|yaml|csv`
- Auto-pagination with `--page-all` (NDJSON output)

## Static Sites (GitHub Pages)

Repo: `oysteinkrog/sites` — `gh-pages` branch. Live at `https://oysteinkrog.github.io/sites/`.

### Publishing static content
Fixed local checkout at `/c/work/sites-repo`. Use `/publish-site` skill or manually:
```bash
# First time: git clone --branch gh-pages --single-branch https://github.com/oysteinkrog/sites.git /c/work/sites-repo
cd /c/work/sites-repo && git pull origin gh-pages
mkdir -p <category>/<slug> && cp -r /path/to/content/* <category>/<slug>/
git add -A && git commit -m "add <category>/<slug>" && git push origin gh-pages
```
Result: `https://oysteinkrog.github.io/sites/<category>/<slug>/`

### Conventions
- Organize by category: `bv/` (beads viewer), `docs/`, `reports/`, etc.
- Each site is a self-contained directory with its own `index.html`

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
