# User CLAUDE.md

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
