# User CLAUDE.md

## Dotfiles

Repo at `~/.dotfiles` (regular git repo, not bare), remote `origin` = `https://github.com/oysteinkrog/dotfiles`.
Tracked files live throughout `~` (CLAUDE.md, .claude/, .config/fish/, bin/, etc.).

## Grove - Git Worktree Manager

The `grove` command manages git worktrees for a mono-repo workflow. Each worktree is a "project" identified by a short tag. Config is at `~/.config/grove/config.json`, registry at `~/.config/grove/registry.json`.

### Commands

```bash
# Create new worktree (branch: DESKTOP-NNNN-<tag> or just <tag>)
grove new <tag> [--issue N] [--branch name] [--base ref]

# Fork an existing project's branch into a new worktree
grove fork [source] <new_tag> [--issue N] [--branch name]

# Change directory to a project worktree
grove cd <tag>

# List all projects with status (dirty/clean/ahead/behind)
grove list              # full table
grove list --short      # compact
grove list --all        # include untracked worktrees
grove list --json       # JSON output

# Remove worktree (checks for uncommitted/unpushed work)
grove done <tag> [--force] [--keep-local] [--keep-remote]

# Import existing worktree into registry
grove adopt <tag> <path> [--move] [--issue N] [--base ref]

# Launch terminal tabs with Claude Code for projects
grove launch [--only tag1,tag2] [--dry-run] [--no-claude]

# Get worktree path for a tag
grove path <tag>

# Rename project (moves directory by default)
grove rename <old> <new> [--no-move]

# Freeze/thaw (exclude from launch)
grove freeze <tag>
grove thaw <tag>
```

### Examples

```bash
grove new dlmodels --issue 9947      # creates DESKTOP-9947-dlmodels branch
grove new ci-fix --base 25.3         # branch from stable/25.3
grove fork dlmodels dlmodels2        # fork from existing project
grove cd dlmodels                    # cd to worktree
grove adopt foo /c/WORK/old --move   # import and relocate
grove done dlmodels                  # remove with safety checks
```

### Shortcuts

- `gr <tag>` - shorthand for `grove cd <tag>`
- `gr` (no args) - shorthand for `grove list --short`
- Most subcommands auto-detect the current project from cwd when tag is omitted

## git-hunks - Non-interactive Hunk Staging

Selective hunk staging without interactive prompts (replacement for `git add -p`).

```bash
git hunks list              # list all hunks with unique IDs
git hunks list --staged     # list staged hunks
git hunks add <hunk-id>     # stage specific hunk(s)

# Hunk IDs use format: file:@-old,len+new,len
git hunks add 'src/main.c:@-10,6+10,7'
git hunks add 'file1:@-10,6+10,7' 'file2:@-5,3+5,4'
```

## git-addmatch - Regex-based Hunk Staging

Stage only hunks matching a regex pattern. Uses `grepdiff` from `patchutils`.

```bash
git addmatch "pattern"      # stage hunks matching pattern
```

## cfclip - Copy Files to Clipboard

Concatenate file contents and copy to Windows clipboard.

```bash
cfclip file1.cs file2.cs          # copy file contents to clipboard
fd "*.cs" src/ | cfclip           # pipe file list from stdin
```

## rgg - Filename Search

Find files by name pattern (glob wrapper around `rg --files`).

```bash
rgg VideoDevice                   # find files with VideoDevice in name
```

## Python Toolchain (Astral)

All Python projects use **uv** (packages), **ruff** (lint/format), **ty** (type check).
After editing .py files: `ruff check --fix && ruff format && ty check`.
See `/py-uv`, `/py-ruff`, `/py-ty` skills for details.

## X/Twitter Bookmarks — fieldtheory-cli (ft)

Local archive of X/Twitter bookmarks, searchable via `ft` CLI (`npm i -g fieldtheory`).
Skill `/fieldtheory` is installed for Claude Code.

- **Data:** `~/.ft-bookmarks/` (SQLite + FTS index)
- **Cookies:** `/c/work/life/data/x-cookies.env` (contains `FT_CT0` and `FT_AUTH_TOKEN`)

### Search & browse
```bash
ft search "<query>"                # full-text BM25 search
ft list --category tool --domain ai --limit 10
ft list --author @handle
ft stats                           # collection overview
ft show <id>                       # full detail for one bookmark
```

### Sync new bookmarks
```bash
# Read cookies from the env file, then sync:
source /c/work/life/data/x-cookies.env 2>/dev/null
ft sync --cookies $FT_CT0 $FT_AUTH_TOKEN --yes
```
If sync fails with auth errors, cookies have expired — ask the user to re-extract
`ct0` and `auth_token` from Chrome DevTools (Application > Cookies > x.com).

## Google Workspace CLI — gogcli (gog)

Go binary by Peter Steinberger (steipete). Single CLI for Gmail, Calendar, Drive, Contacts,
Tasks, Sheets, Docs, Slides, People, Forms, Apps Script, Chat, Classroom.
Called via Bash (not an MCP server — avoids context bloat).

- **Binary:** `~/bin/gog`
- **Repo:** https://github.com/steipete/gogcli
- **Config:** `~/.config/gogcli/`
- **Account:** `oystein@initialforce.com`

### Usage
```bash
gog -a oystein@initialforce.com gmail labels list
gog -a oystein@initialforce.com calendar events list --days 7
gog -a oystein@initialforce.com drive files list --limit 10
```
Flags: `-j` for JSON, `-p` for plain TSV, `--results-only` to drop pagination envelope.
Agent sandboxing: `GOG_ENABLE_COMMANDS="gmail,calendar,drive,tasks" gog ...`

## Multi-Agent Orchestration (Claude Code Teams & Agents)

Multi-agent work runs inside Claude Code via the built-in `Agent`, `SendMessage`,
`TaskCreate`, and `TeamCreate` tools — no external tmux manager.

### Spawning teammates
Send multiple `Agent` tool calls in a single message to run them concurrently:

```
Agent({ subagent_type: "general-purpose", name: "researcher-1",
        team_name: "feature-x", run_in_background: true,
        prompt: "<self-contained task> ..." })
```

- `name` makes the teammate addressable via `SendMessage({ to: "<name>" })`.
- `team_name` groups teammates, shared tasks, and inboxes under
  `~/.claude/teams/<team-name>/`.
- `run_in_background: true` keeps the leader responsive while the teammate works.
- `isolation: "worktree"` spawns the teammate on a temporary worktree (use for
  research/design only — never for parallel bead implementation; see swarm rules).

### Work distribution (bead integration)
Use the beads CLI to compute what to do, then hand work out via `TaskCreate`:

```bash
bv -robot-triage                   # recommendations, bottlenecks
bv -robot-next                     # single best next action
bv -robot-plan                     # parallel execution tracks
bv -robot-alerts --severity=critical
```

Leader workflow:
1. `br list --status open --json` — seed **all open beads in scope**, not just
   `br ready`. If only ready beads are seeded, there are no downstream tasks
   for `addBlockedBy` to unblock later.
2. For each bead, `TaskCreate({ subject: "bd-XXX: ...", ... })`. Keep the
   `bead_id → taskId` mapping in memory — you need it for the next step.
3. Translate bead-space dependencies (from `br dep tree --json`) into task-space
   with the mapping, then `TaskUpdate({ taskId, addBlockedBy: [<upstream-task-ids>] })`.
   `addBlockedBy` takes task IDs, not bead IDs.
4. Spawn teammates (`Agent({ name, team_name, ... })`) telling them to
   `TaskList`, claim an unowned unblocked task (set `owner`), verify the claim
   with `TaskGet` (race guard), implement, commit, `br close`, then
   `TaskUpdate({ status: "completed" })`, then exit. Execution teammates are
   **terminal** — the leader spawns a fresh one for the next bead. See the
   `/swarm` skill for the full template.

### Inter-agent messaging
```
SendMessage({ to: "<teammate-name>", content: "..." })   # direct
```
`SendMessage` continues the named teammate with full prior context. Use it for
**artifact-swarm** teammates (researchers, designers, reviewers) whose work is
multi-turn. Do NOT use it on **execution-swarm** teammates — those are
one-bead-then-exit by design, which keeps each teammate's context window clean.
Spawn a new `Agent` for the next bead instead.

### File reservations (conflict prevention)
Every teammate editing files MUST reserve them first via the `mcp-agent-mail` MCP
(`file_reservation_paths`) and release after committing (`release_file_reservations`).
See the global CLAUDE.md "Agent Swarm Rules" for details and the `/swarm` skill for
pre-flight that starts agent-mail and wires it into `.mcp.json` automatically.

### Monitoring
```
TaskList                           # overall progress + owners + blocked-by
TaskGet({ taskId })                # full detail + comments
```

Claude Code's sidebar shows live status for every named teammate.
`br ready` / `bv -robot-triage` stays the source of truth for bead backlog health.

### Tips
- Each teammate prompt MUST require an explicit `git commit` after each work unit —
  teammates do not auto-commit (see "Agent Swarm Rules" in the global CLAUDE.md).
- Prefer `SendMessage` to continue a named teammate; spawning a new `Agent` starts
  fresh and loses the prior context.
- For dependency-ordered assignment, encode the DAG via `TaskUpdate` `addBlockedBy`
  rather than trying to orchestrate it from the leader step-by-step.
- Heavy parallel work: spawn several `Agent` calls in a single leader message so
  they actually run concurrently instead of serially.
