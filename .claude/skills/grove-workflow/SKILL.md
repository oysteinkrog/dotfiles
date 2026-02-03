---
name: grove-workflow
version: 1.0.0
description: |
  Understand and work with the grove worktree manager. Use when the user
  references projects, worktrees, switching between projects, or managing
  their mono-repo workflow. Grove manages named git worktrees with tags,
  issue tracking, and terminal tab orchestration.
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# Grove Workflow

## What is Grove?

Grove is a git worktree manager for mono-repo development. It wraps `git worktree`
with a registry of named projects, each identified by a short **tag** (e.g. `dlmodels`,
`ci-fix`). The user works on multiple branches simultaneously, each in its own
directory under `/c/work/`.

## Architecture

- **Binary**: `~/.dotfiles/bin/grove` (Python 3)
- **Config**: `~/.config/grove/config.json` (repo paths, remotes, branch conventions)
- **Registry**: `~/.config/grove/registry.json` (tag -> path/branch/issue mappings)
- **Shell wrapper**: `~/.dotfiles/.config/fish/functions/grove.fish` (handles `cd` via `__POSTCD__`)
- **Shorthand**: `gr <tag>` is an alias for `grove cd <tag>`

## Worktree Layout

```
/c/work/
  desktop_master/     # main repo (bare-ish checkout)
  dt-dlmodels/        # worktree for "dlmodels" project
  dt-ci-fix/          # worktree for "ci-fix" project
  dt-rawcodecs/       # etc.
```

Directories are prefixed with `dt-` (configurable via `dir_prefix`).

## Common Commands

| Command | What it does |
|---------|-------------|
| `grove new <tag> --issue N` | Create worktree with DESKTOP-N-tag branch |
| `grove cd <tag>` | cd to a project's worktree |
| `grove list` | Show all projects with git status |
| `grove done <tag>` | Remove worktree with safety checks |
| `grove fork <src> <new>` | Branch from existing project |
| `grove rename <old> <new>` | Rename and move worktree |
| `grove freeze <tag>` | Exclude from `grove launch` |
| `grove launch` | Open wezterm tabs for all active projects |

## When Working in a Project

- The current project is auto-detected from cwd for most commands
- `grove done` without args removes the current project
- `grove freeze` without args freezes the current project
- The fish wrapper sets `GROVE_TAB_TITLE` for terminal tab names

## Key Conventions

- Branch naming: `DESKTOP-{issue}-{tag}` when an issue number is provided
- Two git remotes: `if` (upstream/company) and `my` (personal fork)
- `grove done` checks for uncommitted changes and unpushed commits before removing
- On WSL/Windows, grove handles directory locking (wezterm pane detection, robocopy fallback)

## For Claude Code Agents

When you are working in a worktree managed by grove:

1. You are likely in `/c/work/dt-<tag>/` - this is a git worktree, not a full clone
2. The main repo is at `/c/work/desktop_master/`
3. Use `grove list --json` to programmatically discover all projects
4. Use `grove path <tag>` to get the path for a specific project
5. Don't modify files in other worktrees without being asked
