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

## Oracle Consultation Policy

**Fable (claude-fable-5) is the primary oracle.** For second opinions, design validation,
debugging help, and architecture reviews, consult Fable first and by default.

- **The GPT escalation tier is reserved for extremely important or complex tasks only**
  (e.g. high-stakes architecture decisions, problems Fable could not crack, board-level
  deliverables). Do not reach for it for routine second opinions. Preferred GPT route:
  **GPT-5.6 Sol via Codex CLI** (`codex exec --sandbox read-only -m gpt-5.6-sol
  -c model_reasoning_effort=xhigh` — explicit tier ID required, the bare `gpt-5.6`
  alias hangs); alternate: GPT-5.5-Pro via PAL (PAL does not have GPT-5.6).
- **Never use the GPT tier alone.** Whenever GPT is consulted, ALWAYS also consult Fable
  on the same question and compare the two answers. Present both views, clearly labelled,
  and call out disagreements explicitly.
- This supersedes any skill or doc that frames GPT Pro as the default/smartest oracle
  (e.g. `/consult-oracles`, `/swarm-oracle`): run those patterns with Fable as the
  primary, adding GPT Pro only under the criteria above.

## Multi-Agent Orchestration

Canonical guidance lives in the global CLAUDE.md (`~/.claude/CLAUDE.md`): see
"Claude Code Teams & Agents" and "Agent Swarm Rules". Nothing repo-specific
overrides it here.

## Skill Sources (skills-sync)

External skill repos are managed by `bin/skills-sync`: sources are declared in
`~/.claude/skills-sources.json`, pinned commits and per-skill content hashes in
`~/.claude/skills-sources.lock.json`, and skills are copied flat into
`~/.claude/skills/<name>/` with a `.skill-source.json` provenance stamp.
Local edits to an installed skill are detected by hash and never overwritten
without `--force`.

```bash
skills-sync list                 # sources + installed skills
skills-sync status               # update check + local-edit detection
skills-sync sync [SOURCE]        # install/update (--force overwrites local edits)
skills-sync add <owner/repo>     # register a new source (--dir, --ref, --name)
skills-sync remove <SOURCE>      # unregister (--purge deletes installed skills)
```
