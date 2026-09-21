---
name: local-tools
description: Small local command-line tools on this WSL1 machine that are not obvious from the shell. Covers selective git hunk staging (git-hunks, git-addmatch), the Windows clipboard bridge (cfclip), filename search (rgg), the Obsidian CLI, the Google Workspace CLI (gog), and skill source management (skills-sync). Use when staging part of a file, making a partial commit, copying file contents to the Windows clipboard, finding a file by name, driving Obsidian from the command line, reading or writing Google Drive, Docs, Sheets, Gmail or Calendar from the shell, or installing and updating external skill repos.
---

# Local tools

Each of these is installed and on PATH. This skill exists so the details do not have to sit
in CLAUDE.md on every session.

## git-hunks: stage hunks without a prompt

Replacement for `git add -p`, which cannot run in agent context.

```bash
git hunks list              # all hunks, each with a unique id
git hunks list --staged     # what is already staged
git hunks add <hunk-id>     # stage one or more

# Hunk ids look like  file:@-old,len+new,len
git hunks add 'src/main.c:@-10,6+10,7'
git hunks add 'file1:@-10,6+10,7' 'file2:@-5,3+5,4'
```

## git-addmatch: stage hunks matching a pattern

Stages only the hunks that match a regex. Needs `grepdiff` from `patchutils`.

```bash
git addmatch "pattern"
```

## cfclip: copy file contents to the Windows clipboard

```bash
cfclip file1.cs file2.cs      # concatenate and copy
fd "*.cs" src/ | cfclip       # take the file list from stdin
```

## rgg: find files by name

A glob wrapper around `rg --files`.

```bash
rgg VideoDevice               # files with VideoDevice in the name
```

## Obsidian CLI

Built into Obsidian 1.12 and later, not an npm package. **Obsidian must be running** or the
commands do nothing. On WSL1 the binary is not on PATH, so call it by full path:

```
/mnt/c/Users/Oystein/AppData/Local/Programs/Obsidian/Obsidian.com
```

## gog: Google Workspace from the shell

Go binary at `~/bin/gog` (steipete/gogcli), config in `~/.config/gogcli/`. Called through
Bash rather than run as an MCP server, to keep it out of the context budget.

- **Always pass `-a` with the user's work email.** It is in the session context.
- `gog --help` lists the command surface and the output flags.
- Sandbox an agent to part of it with
  `GOG_ENABLE_COMMANDS="gmail,calendar,drive,tasks" gog ...`
- Gmail and Calendar are also on Claude.ai remote MCP servers. Use those for quick reads and
  `gog` for Drive, Docs, Sheets and Contacts.
- Name clash: the fish function `gws` is `git status --short`, not the retired workspace CLI.

## skills-sync: external skill repos

Sources are declared in `~/.claude/skills-sources.json`. Pinned commits and per-skill content
hashes live in `~/.claude/skills-sources.lock.json`. Skills are copied flat into
`~/.claude/skills/<name>/` with a `.skill-source.json` provenance stamp.

```bash
skills-sync list                 # sources and installed skills
skills-sync status               # update check, and which skills you edited locally
skills-sync sync [SOURCE]        # install or update
skills-sync add <owner/repo>     # register a source (--dir, --ref, --name)
skills-sync remove <SOURCE>      # unregister (--purge also deletes the installed skills)
```

Local edits to an installed skill are found by hash and are never overwritten unless you pass
`--force`. That flag throws your edits away, so check `skills-sync status` first.
