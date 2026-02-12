---
name: partial-stage
description: |
  Non-interactive partial staging of git hunks (git add -p alternative).
  Use when the user wants to stage specific hunks, make partial commits,
  split changes across commits, or says "partial stage", "stage hunks",
  "split commit", "selective stage", or "commit part of a file".
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - AskUserQuestion
---

# Partial Stage — non-interactive `git add -p`

Stage individual change groups (sub-hunk granularity) without interactive prompts.

## Tool

The helper script lives at `~/.claude/skills/partial-stage/partial-stage.py`.
It parses diffs into individually selectable "change groups" — contiguous
blocks of added/removed lines within a hunk — so you can stage at finer
granularity than whole hunks.

**No external dependencies** beyond Python 3.10+ and git.

## Commands

### Show change groups in a file

```bash
python3 ~/.claude/skills/partial-stage/partial-stage.py show <file>
python3 ~/.claude/skills/partial-stage/partial-stage.py show <file> --verbose    # include context
python3 ~/.claude/skills/partial-stage/partial-stage.py show <file> --grep "pattern"  # filter by regex
python3 ~/.claude/skills/partial-stage/partial-stage.py show <file> --group 5    # show one group
python3 ~/.claude/skills/partial-stage/partial-stage.py show <file> --cached     # show staged changes
```

### Stage specific groups

```bash
# By group number (comma-separated, ranges supported)
python3 ~/.claude/skills/partial-stage/partial-stage.py stage <file> --groups 2,5,7-9

# By pattern match (searches in diff lines and surrounding context)
python3 ~/.claude/skills/partial-stage/partial-stage.py stage <file> --grep "lightbox"
```

### Unstage specific groups

```bash
python3 ~/.claude/skills/partial-stage/partial-stage.py unstage <file> --groups 3
python3 ~/.claude/skills/partial-stage/partial-stage.py unstage <file> --grep "pattern"
```

## Workflow

### Step 1: Identify changed files

```bash
git diff --stat HEAD
```

### Step 2: Show and select change groups

```bash
# See all groups in the file
python3 ~/.claude/skills/partial-stage/partial-stage.py show <file>

# If the user describes what they want to stage, use --grep to find it
python3 ~/.claude/skills/partial-stage/partial-stage.py show <file> --grep "keyword"
```

Present the groups to the user and ask which ones to stage.

### Step 3: Stage the selected groups

```bash
python3 ~/.claude/skills/partial-stage/partial-stage.py stage <file> --groups <selection>
# or
python3 ~/.claude/skills/partial-stage/partial-stage.py stage <file> --grep "keyword"
```

The script automatically:
- Builds a minimal patch containing only the selected changes
- Applies it to the git index via `git apply --cached`
- Shows a summary of what was staged

### Step 4: Verify and repeat or commit

```bash
git diff --cached --stat   # what is staged
git diff --stat            # what remains unstaged
```

Ask the user if they want to:
- Stage more groups from the same or another file
- Commit the staged changes now
- Review the full staged diff before committing

## Key details

- **Group numbers are 1-indexed** and global across all hunks in the file
- **Sub-hunk precision**: each contiguous block of +/- lines is its own group, even if git considers them part of one hunk
- **Working tree is untouched** — only the git index is modified
- **Safe**: `git apply --cached` fails cleanly if the patch doesn't apply
- **`--grep` searches** the change lines AND surrounding context, case-insensitive
