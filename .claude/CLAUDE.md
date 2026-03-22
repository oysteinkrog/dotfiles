# User-Level Claude Code Instructions

## Dotfiles

User dotfiles repo is at `~/.dotfiles`. `~/.claude` is a symlink to `~/.dotfiles/.claude`.
Skills, settings, and other Claude config live in the dotfiles repo and are version-controlled there.

## Repo Index — Initial Force

| Repo | Local path | GitHub | Access | Contents |
|------|-----------|--------|--------|----------|
| **ifkb** | `/c/work/ifkb` | `InitialForce/ifkb` | All employees | Company KB — org structure, products, systems, strategy, financials (board-approved/public) |
| **ifboard** | `/c/work/ifboard` | `InitialForce/ifboard` | CEO + CTO only | Board-level confidential — investor dossiers, fundraising strategy, cap table, convertible terms, M&A, P&L actuals |

### Cross-repo rules

- **ifboard → ifkb: READ freely.** Agents in ifboard often need company context (products, people, strategy). Read from ifkb or use `qmd` to search it. See ifkb's AGENTS.md for qmd usage.
- **ifkb → ifboard: NEVER.** ifkb agents must not read, reference, or link to ifboard. ifkb is employee-visible; any ifboard reference leaks the existence of confidential material.
- **Write destination:** Use each project's CLAUDE.md decision guide to determine where new content belongs. The test: "Would it be a problem if a developer read this?" If yes → ifboard. If no → ifkb.

### Financial data split

General financials (budget scenarios, P&L from board deck, balance sheet, revenue breakdown) live in **ifkb** at `knowledge-base/company/financials.md` — these are board-approved figures shared with employees. Confidential specifics (convertible loan terms, cap table, cash position, fundraising intel, investor feedback) live in **ifboard** under `investor-research/`.

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
        "Authorization": "Bearer ${MCP_AGENT_MAIL_TOKEN}"
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

## Google Workspace CLI — gogcli (gog)

Go binary by Peter Steinberger (steipete). Single CLI for Gmail, Calendar, Drive, Contacts,
Tasks, Sheets, Docs, Slides, People, Forms, Apps Script, Chat, Classroom.
**Not an MCP server** — Claude Code calls `gog` via Bash. Zero context overhead.

- **Binary:** `~/bin/gog` (built from source)
- **Repo:** https://github.com/steipete/gogcli
- **Config:** `~/.config/gogcli/config.json`
- **Credentials:** `~/.config/gogcli/credentials.json` (OAuth client secret)
- **Tokens:** system keyring (or file-based encryption for headless)

### Auth
```bash
gog auth credentials ~/Downloads/client_secret_....json   # import OAuth client secret
gog auth add oystein@initialforce.com                      # authorize account (opens browser)
gog auth list                                              # show stored tokens
```

### Usage
Always pass `-a oystein@initialforce.com` (or set `GOG_ACCOUNT`):
```bash
gog -a oystein@initialforce.com gmail labels list
gog -a oystein@initialforce.com calendar events list --days 7
gog -a oystein@initialforce.com drive files list --limit 10
gog -a oystein@initialforce.com contacts list --limit 5
gog -a oystein@initialforce.com tasks list
gog -a oystein@initialforce.com sheets get <spreadsheet-id>
```

### Output control
- `-j` / `--json` — JSON output (best for scripting/parsing)
- `-p` / `--plain` — TSV output, no colors
- `--results-only` — drop envelope fields (nextPageToken, etc.)
- `--select=field1,field2` — select specific JSON fields

### Agent sandboxing
Restrict available commands for agent runs:
```bash
GOG_ENABLE_COMMANDS="gmail,calendar,drive,tasks" gog ...
```

### Key info
- `user_google_email` is `oystein@initialforce.com`
- Gmail and Google Calendar are also available via Claude.ai remote MCPs
  (use those for quick reads; use `gog` for Drive, Docs, Sheets, Contacts, etc.)
- `gog` replaced the `gws` MCP server which was eating context by loading all
  Google Workspace API schemas into every conversation

### Updating
```bash
cd /tmp && git clone --depth 1 https://github.com/steipete/gogcli.git && cd gogcli \
  && go build -o ~/bin/gog ./cmd/gog && rm -rf /tmp/gogcli
```

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

## CASS Memory System (`cm`)

Cross-agent memory system that learns from session history. Three-layer architecture:
episodic memory (raw session logs), working memory (diary entries), procedural memory
(confidence-tracked rules with maturity progression).

- **Binary:** `~/.local/bin/cm` (v0.2.3, native ELF, installed via install.sh)
- **Data:** `~/.cass-memory/` (config, playbook, diary, embeddings, reflections)
- **Repo:** https://github.com/Dicklesworthstone/cass_memory_system
- **Author:** Same as mcp-agent-mail and bv (Dicklesworthstone)

### Updating
```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/cass_memory_system/main/install.sh?$(date +%s)" | bash -s -- --easy-mode --verify
```

### Core agent workflow
```bash
cm context "<task>" --json              # Get relevant rules/history before starting work
cm outcome success                      # Record session outcome (success/failure)
cm doctor --json                        # Health check
cm quickstart --json                    # Self-documentation
```

### Playbook management
```bash
cm playbook list                        # Show all rules
cm playbook get <id>                    # Rule details
cm playbook add "<content>"             # Add new rule
cm playbook add --category "debugging" "<content>"  # Add with category
cm playbook add --file rules.json       # Batch add rules
cm playbook remove <id>                 # Deprecate rule
cm playbook export                      # Backup playbook
cm top N                                # Show top N rules by score
cm similar "<query>"                    # Find similar rules (dedup check)
cm init --starter general               # Seed with starter template
```

### Learning & feedback
```bash
cm reflect --days N                     # Process sessions into rules (needs LLM key)
cm mark <id> --helpful                  # Mark rule as helpful
cm mark <id> --harmful                  # Mark rule as harmful
cm validate "<rule>"                    # Check evidence in cass
cm forget <id>                          # Permanently remove rule
cm audit --days N                       # Check rule violations in recent sessions
```

### Onboarding (build playbook from session history)
```bash
cm onboard status --json                # Check onboarding progress
cm onboard guided                       # Interactive onboarding wizard
cm onboard sample --fill-gaps --json    # Sample sessions to process
cm onboard read /path/to/session.jsonl --template --json  # Process a session
cm onboard mark-done /path/to/session.jsonl               # Mark session processed
```

### Trauma guard (safety system)
```bash
cm trauma list                          # Show dangerous patterns
cm trauma add "<pattern>" ...           # Register dangerous pattern
cm trauma heal t-id --reason "x"        # Temporarily bypass
cm trauma scan --days 30                # Scan for risks
cm guard --install                      # Install safety hooks for Claude Code
cm guard --git                          # Install git pre-commit hook
```

### MCP server mode
```bash
cm serve                                # Start MCP HTTP server (port 8765)
cm serve --port 9000                    # Custom port
MCP_HTTP_TOKEN="x" cm serve --host 0.0.0.0  # Remote access with auth
```

### Agent protocol
1. **Start:** `cm context "<task>" --json` before significant work
2. **Work:** Reference rule IDs when following guidance
3. **Feedback:** Inline comments `// [cass: helpful b-xyz]` or `// [cass: harmful b-xyz]`
4. **Finish:** `cm outcome success` or `cm outcome failure`
5. Learning happens automatically from session logs

### Output control
All commands support `--json`. Use `--limit N`, `--min-score N`, `--no-history` to control output size.

### Configuration (`~/.cass-memory/config.json`)
- Provider: `anthropic` (needs `ANTHROPIC_API_KEY` for LLM reflection; works without it)
- Scoring: helpful feedback decays with 90-day half-life; harmful weighted 4x
- Maturity: candidate -> established -> proven -> (deprecated)
- Semantic search: disabled by default (`semanticSearchEnabled: true` to enable)
- Budget: $0.10/day, $2/month default LLM budget
- Session logs at `~/.claude/projects/*/` are automatically ingested

### Starter templates
Available: `general`, `node`, `python`, `react`, `rust`. Seed with `cm init --starter=<name>`.

## Agent Swarm Rules

### NO WORKTREES — agents commit to the same branch
**NEVER use `--worktrees` with `ntm spawn`.** Worktree isolation causes silent merge
regressions — later merges overwrite earlier security fixes (16% reversion rate observed
2026-03-07). Instead:
- All agents work on the same branch (typically `main`)
- Each bead is small enough for a single atomic commit
- Agents commit directly after completing each bead
- If a bead would touch 5+ files, split it into smaller beads first

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

### Commit before building (for large-file beads)
For beads that produce large files (>500 LOC), agents often hit context limits between
writing the file and the commit step — leaving orphaned untracked files. Use this order:

```
1. Write the implementation file
2. COMMIT IMMEDIATELY (before running build or tests):
   git add <file> && git commit -m "feat(bead-id): description"
3. cargo build --release  (or equivalent)
4. cargo test
5. If checks fail: fix, then git add <file> && git commit --amend --no-edit
6. Close bead and exit
```

**Why:** The file is the hard part. If the agent runs out of context after step 2,
the work is preserved and the swarm operator can rescue it with a single build fix.
If the commit comes last, all work is lost on context exhaustion.

### Bead sizing for swarms
- Each bead should touch 1-3 files max
- Security fixes MUST include a regression test
- Refactoring beads must NOT overlap with security fix beads (separate files)
- If file overlap is unavoidable, serialize those beads (use `blockedBy` dependencies)

### Post-swarm verification
After all agents finish, verify each bead's expected changes exist on `main`:
- Grep for known-bad patterns that should have been removed
- Diff each bead's expected file changes against current HEAD
- Run the full test suite

### Other swarm prompt essentials
- Tell agents to read CLAUDE.md first
- Specify file paths agents will touch so file reservations can prevent conflicts
- Use `ntm assign --strategy=dependency` for ordered assignment

## Obsidian CLI

The official Obsidian CLI is built into Obsidian v1.12+ (not an npm package). Obsidian must be running for CLI commands to work.

On WSL1/Windows, the CLI binary is located at:

```
/mnt/c/Users/Oystein/AppData/Local/Programs/Obsidian/Obsidian.com
```

It is not in PATH by default. Use the full path when invoking from WSL.
