# User-Level Claude Code Instructions

## Safety Rules (mined from session history)

- **Never kill processes you didn't start.** Before killing any process, verify you started it in this session. Killing a running app instance is a critical error.
- **Don't implement when planning is in progress.** If the user is editing beads, a PRD, or a plan, do NOT begin implementation. Wait for explicit go-ahead.
- **Check for existing PR/branch before creating new ones.** Always run `gh pr list --head <branch>` before creating a PR — duplicates cause confusion.
- **Only commit files explicitly part of the task.** Don't stage or commit files the user didn't ask to change. If in doubt, ask.
- **No editorial markup in documents.** Never use strikethrough or correction annotations — git history handles that. Documents reflect current correct state only.
- **Verify implementation state before assuming.** Check `git log` and the file tree to confirm what is actually implemented vs only planned.
- **Dev questions go to the user, not colleagues.** All clarifying questions go to Oystein, not to other employees via Slack/email.
- **Ask the user to install missing tools.** Don't install packages yourself — ask the user to run `! sudo apt install <pkg>`.

## Dotfiles

User dotfiles repo is at `~/.dotfiles`. `~/.claude` is a symlink to `~/.dotfiles/.claude`.
Skills, settings, and other Claude config live in the dotfiles repo and are version-controlled there.

## Repo Index — Initial Force

| Repo | Local path | GitHub | Access |
|------|-----------|--------|--------|
| **ifkb** | `/c/work/ifkb` | `InitialForce/ifkb` | All employees |
| **ifboard** | `/c/work/ifboard` | `InitialForce/ifboard` | CEO + CTO only |

When working across repos, read the target repo's `CLAUDE.md` and `AGENTS.md` for content rules, search tools, and cross-repo access policy. **ifboard can read ifkb; ifkb must never reference ifboard.**

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

## Claude Code Teams & Agents (Multi-Agent Orchestration)

Multi-agent work runs **inside Claude Code** via the built-in `Agent`, `SendMessage`,
`TaskCreate`, and `TeamCreate` tools. No external tmux manager.

### Two swarm shapes

1. **Artifact swarm** (research / design / review) — a fixed roster of teammates, one
   per facet, each producing a single report. Teammates may use `isolation: "worktree"`
   because their output is returned in the agent's final message (leader writes the
   synthesis). `SendMessage` is appropriate here for follow-up questions.
2. **Execution swarm** (implement beads from `br`) — a pool of **fungible, terminal**
   teammates. Each picks one bead, implements it, commits to the shared branch, closes
   the bead, marks its task completed, and **exits**. The leader spawns replacement
   teammates as new beads become ready. `isolation: "worktree"` is FORBIDDEN here
   (see "Agent Swarm Rules" below). `SendMessage` is NOT used for implementation
   teammates — they are one-shot by design, which keeps each teammate's context
   window clean.

### NxM swarm notation

When Oystein writes **"NxM <model> agents"** it means **N agents per round × M rounds**,
NOT N×M total agents in one shot. Example phrasings and what they mean:

| User says | Shape |
|-----------|-------|
| "5x5 sonnet agents to search" | 5 parallel Sonnet agents per round, run 5 rounds sequentially (25 agent-runs total) |
| "2x6 opus research session" | 2 parallel Opus agents per round, run 6 rounds sequentially (12 agent-runs total) |
| "3x1" or just "3 agents" | 3 parallel agents, one round (one-shot artifact swarm) |

**How to run rounds:**
- Each round, spawn N agents in a SINGLE message (parallel tool calls) — they run concurrently.
- Wait for all N to return, then read/synthesize their outputs.
- Round K+1 should be **informed by** rounds 1..K — pass forward accumulated findings, de-dupe
  already-covered ground, direct the next round at gaps or deeper follow-ups.
- If the work is inherently breadth-first (e.g. "scan for news"), each round can take a new
  angle/lane. If depth-first (e.g. "dig into these findings"), each round escalates from the
  prior round's output.
- Always write findings to a shared directory (e.g. `data/<project>-<date>/findings-round-<K>-agent-<N>.md`)
  so the leader has durable artifacts across rounds — agent final messages alone are not enough
  when rounds compound.

**Why N agents in parallel, not one big agent:** parallel agents cover more ground faster and
each keeps a clean context budget for its lane. Why M rounds instead of one bigger round:
later rounds can react to what earlier rounds found (fill gaps, dig deeper, challenge claims)
without polluting earlier agents' context.

### Primitives

- Spawn a teammate: `Agent({ subagent_type, prompt, name?, team_name?, isolation?, run_in_background? })`.
- Assign ongoing work via shared tasks: `TaskCreate` / `TaskUpdate` / `TaskList` with
  per-task `owner` so each teammate claims its next unit of work.
- Inter-agent messaging: `SendMessage({ to: <name>, ... })` — continues a named agent
  with full prior context. Use for **artifact swarms** (follow-ups on a reviewer/
  designer). Do NOT use for execution-swarm teammates; spawn a fresh `Agent` for the
  next bead instead so the teammate starts with a clean context budget.
- Teams: `TeamCreate` groups agents + shared task list + shared inboxes. Team state lives
  under `~/.claude/teams/<team-name>/` (inboxes only; harness handles lifecycle).
- Parallel exploration: send multiple `Agent` tool calls in a single message — they run
  concurrently. Use `run_in_background: true` for long-running teammates while the leader
  keeps working.
- Isolation: pass `isolation: "worktree"` only for artifact-swarm teammates whose
  output is a single final message. NEVER for execution swarm or for any teammate
  whose output is a file the leader needs to read directly from the main checkout.

Use `/swarm`, `/swarm-agents`, `/swarm-exec`, `/swarm-review`, etc. skills for the
established orchestration patterns (research / design / review / bead implementation).

## BV (Beads Viewer) + br (beads_rust)

`bv` (`~/go/bin/bv`): TUI + robot API for beads issue tracker.
`br`: CLI for bead management (`br ready`, `br show`, `br close`, `br update`).
Key robot commands: `bv -robot-triage`, `bv -robot-next`, `bv -robot-plan`.
Agent workflow: triage → leader spawns teammates via `Agent` → coordinate via TaskCreate
+ SendMessage + agent-mail file reservations → teammates run `br close` and commit.

## Google Workspace CLI (gog)

Binary at `~/bin/gog`. Always pass `-a oystein@initialforce.com`.
Covers: `gmail`, `calendar`, `drive`, `contacts`, `tasks`, `sheets`, `docs`.
Add `-j` for JSON, `-p` for TSV. Gmail/Calendar also available via Claude.ai remote MCPs
(use those for quick reads; use `gog` for Drive, Docs, Sheets, Contacts, etc.).

## Static Sites (GitHub Pages)

Two destinations — pick by **content ownership**, not by who's typing.

| Destination | Use for | Visibility | Local checkout |
|---|---|---|---|
| **`oysteinkrog/sites`** | Personal stuff + work output that is *mine* (personal tools, dashboards, research notes I author, experiments under my own identity). The account is GitHub Pro, so private repos can serve public Pages if needed. | Public Pages (free GH Pages) | `/c/work/sites-repo-personal` (clone on demand) |
| **`InitialForce/sites`** | **Company** content — anything that represents Initial Force AS as an entity (OKRs, board-facing reports, shared dashboards, official docs, anything an employee would treat as authoritative). | Private Pages, org members only | `/c/work/sites-repo` |

**Decision rule:** if the content speaks *for the company* or would be referenced by anyone other than me, it goes in `InitialForce/sites`. If it's mine — personal site, my own dotfiles renders, my own benchmarks — it goes in `oysteinkrog/sites`.

The full policy for IFKB agents (and any agent operating inside `/c/work/ifkb`) is in
`ifkb/knowledge-base/technical/website-publishing.md`. That policy is binding for company content; nothing in it restricts what goes on personal accounts.

### Publishing — company content (`InitialForce/sites`)
Fixed checkout at `/c/work/sites-repo`. Use `/publish-site` skill or manually:
```bash
# First time: git clone --branch gh-pages --single-branch https://github.com/InitialForce/sites.git /c/work/sites-repo
cd /c/work/sites-repo && git pull origin gh-pages
mkdir -p <category>/<slug> && cp -r /path/to/content/* <category>/<slug>/
git add -A && git commit -m "add <category>/<slug>" && git push origin gh-pages
```
Result: `https://initialforce.github.io/sites/<category>/<slug>/` (org-member login required).

### Publishing — personal content (`oysteinkrog/sites`)
```bash
# git clone --branch gh-pages --single-branch https://github.com/oysteinkrog/sites.git /c/work/sites-repo-personal
cd /c/work/sites-repo-personal && git pull origin gh-pages
mkdir -p <category>/<slug> && cp -r /path/to/content/* <category>/<slug>/
git add -A && git commit -m "add <category>/<slug>" && git push origin gh-pages
```
Result: `https://oysteinkrog.github.io/sites/<category>/<slug>/` (public).

### Conventions (both repos)
- Organize by category: `okrs/`, `bv/`, `docs/`, `reports/`, etc.
- Each site is a self-contained directory with its own `index.html`

## CASS Memory System (`cm` + `cass`)

Cross-agent procedural memory. `cass` indexes session logs (14K+ sessions);
`cm` extracts rules and provides them in context.

- **cm:** `~/.local/bin/cm` (v0.2.3, rebuilt from source). Config: `~/.cass-memory/config.json`
- **cass:** Windows binary via WSL wrapper at `~/.local/bin/cass` (v0.1.64). Data: `C:\Users\oystein\AppData\Roaming\cass-old\`

### Agent protocol
1. **Start:** `cm context "<task>" --json --limit 5 --no-history` before significant work
2. **Work:** Follow relevant rules. Leave feedback: `// [cass: helpful b-xyz]` or `// [cass: harmful b-xyz]`
3. **Finish:** `cm outcome success` or `cm outcome failure`

### Key commands
```bash
cm context "<task>" --json       # Get relevant rules for a task
cm playbook list                 # Show all rules
cm reflect --session <path>      # Extract rules from a session (uses LLM)
cm mark <id> --helpful           # Promote a rule
cass search "<query>" --json     # Search session history
cass index --full                # Re-index after new sessions
```

## Agent Swarm Rules

### NO WORKTREES for bead implementation — teammates commit to the same branch
**NEVER pass `isolation: "worktree"` to `Agent` for bead-implementation teammates.**
Worktree isolation causes silent merge regressions — later merges overwrite earlier
security fixes (16% reversion rate observed 2026-03-07). Instead:
- All teammates work on the same branch (typically `main`)
- Each bead is small enough for a single atomic commit
- Teammates commit directly after completing each bead
- If a bead would touch 5+ files, split it into smaller beads first

(Worktree isolation is still fine for read-only research/design teammates that produce
a single report file and no code changes.)

### Atomic commits per work unit
When writing prompts for any autonomous teammate, **always include explicit git commit
instructions**. Each bead/task/work-unit MUST be committed atomically before moving to
the next. Example instruction to include in agent prompts:

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

### Agent-mail file reservations (MANDATORY)
Before launching any swarm, ensure agent-mail MCP is running and configured in `.mcp.json`.
Every agent MUST reserve files via `file_reservation_paths` before editing, and release after
committing. Without this, parallel agents editing the same file create merge conflicts.
See `/swarm` skill pre-flight for setup automation.

### Other swarm prompt essentials
- Tell teammates to read CLAUDE.md first
- Specify file paths teammates will touch so file reservations can prevent conflicts
- For ordered assignment, have the leader release tasks in dependency order (use
  `br dep tree` / `bv -robot-plan` to compute the order) and use `TaskUpdate` with
  `addBlockedBy` to encode the dependency graph so teammates only claim unblocked tasks

## Obsidian CLI

The official Obsidian CLI is built into Obsidian v1.12+ (not an npm package). Obsidian must be running for CLI commands to work.

On WSL1/Windows, the CLI binary is located at:

```
/mnt/c/Users/Oystein/AppData/Local/Programs/Obsidian/Obsidian.com
```

It is not in PATH by default. Use the full path when invoking from WSL.
