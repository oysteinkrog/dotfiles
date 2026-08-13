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
with a registry of named projects, each identified by a short **tag** (e.g. `phonecam`,
`ci-flakes`). Each project is its own worktree directory, letting the user (and agents)
work on multiple branches of the same repo simultaneously.

This is the **rust rewrite** (source: `/c/work/grove`, binary `grove 0.1.x`). It
replaced an older Python script that lived at `~/.dotfiles/bin/grove` — that binary,
its `~/.config/grove/config.json`, and the `dt-`-prefixed directory layout are all
retired. Do not follow docs or memories that reference them.

## Architecture (verified against the installed binary)

- **Binary**: `~/.cargo/bin/grove` (on PATH). Check version: `grove --version`.
- **Global config**: `~/.config/grove/repos.json` — one entry per registered repo:
  `main_repo`, `work_dir`, `dir_prefix`, `upstream_remote`, `fork_remote`,
  `default_base`, `issue_prefix`, optional `launch` block (terminal, shell command).
  A `default_repo` key picks which repo `--repo` defaults to.
- **Per-repo registry**: `<work_dir>/.grove/registry.json` — e.g.
  `/c/work/desktop/.grove/registry.json`. Contains `schema_version` and a `projects`
  map keyed by tag: `path`, `branch`, `base`, `created`, `issue`, `frozen`.
  There is no separate per-repo `config.json`; repo-level settings live in
  `repos.json` alongside the path. (The project README describes a
  `~/.config/grove/<repo>/{registry,config}.json` layout — that does not match
  what the installed 0.1.0 binary actually reads/writes; trust this document and
  `grove repo show <id>` over the README.)
- **No shell wrapper is installed for this setup** — `grove cd <tag>` prints the
  path; the fish function wrapping it (`gr`) is optional shell integration, not
  part of grove itself.

## Worktree Layout

```
/c/work/desktop/
  master/              # main repo checkout (registry's main_repo)
  phonecam/             # worktree for "phonecam" project
  ci-flakes/             # worktree for "ci-flakes" project
  ...
```

For the `desktop` repo, `dir_prefix` is empty — tags map directly to
`<work_dir>/<tag>`, no `dt-` prefix. Do not assume a prefix exists; check
`grove repo show <id>` for the repo you're in.

## Command Surface (from `grove --help` and per-command `--help`)

| Command | Purpose |
|---|---|
| `grove new <tag> [--issue N] [--branch B] [--base REF] [--no-fetch]` | Create a worktree + branch, register it |
| `grove fork [<src>] <new_tag> [--issue N] [--branch B] [--no-fetch]` | Fork an existing project's branch into a new worktree |
| `grove list [--short] [--json] [--no-status]` | List all projects (optionally with git status) |
| `grove status [<tag>...]` | Detailed git status for one or more tags |
| `grove path <tag>` | Print the worktree path for a tag |
| `grove cd <tag>` | Print the path (for shell `cd` integration) |
| `grove adopt <tag> <path> [--issue N] [--base REF] [--move-dir]` | Import an existing worktree into the registry |
| `grove rename <old> <new> [--no-move]` | Rename a project (moves the directory unless `--no-move`) |
| `grove freeze <tag>` / `grove thaw <tag>` | Exclude/re-include a project in `grove launch` |
| `grove repo {add,list,show,remove,default,path}` | Manage `repos.json` |
| `grove launch [--only TAG] [--dry-run] [--no-claude]` | Open terminal tabs for active projects |
| `grove done [<tag>] [--force] [--keep-local] [--keep-remote]` | Remove a worktree (safety-checked) |

Global flags on every subcommand: `--repo <id>` (override cwd-based repo
detection), `-v`/`-vv`/`-vvv` (verbosity).

`new`/`fork`/`done` all infer their target from the current working directory
when no tag/positional is given, by finding the deepest registered project path
that contains `cwd` (checked via `$GROVE_ORIG_CWD` first, falling back to the
real cwd).

### `grove new` vs `grove fork`

- `grove new TAG` bases the new branch on `<upstream_remote>/<default_base>`
  unless `--base` is given. `--base` rules: a value containing `/` is used
  verbatim; a bare value that looks like a version (`25.3`, `1.0`) becomes
  `<upstream>/stable/<value>`; anything else becomes `<upstream>/<value>`.
- `grove fork [SRC] NEW` takes 1 or 2 positionals. With 2, `SRC` is an existing
  tag and `NEW` branches off `SRC`'s current branch. With 1 positional, `SRC` is
  inferred from cwd the same way `done` infers its target — run `fork` from
  inside the source worktree.
- Both fetch the upstream remote by default before creating the worktree;
  `--no-fetch` skips that.
- `--issue N` sets the branch name to `<issue_prefix>-N-<tag>` (e.g.
  `DESKTOP-1234-phonecam`); `--branch` overrides that entirely and takes
  precedence if both are given. With neither, the branch is just `<tag>`.
- Tag validation: 1–40 chars, no `/` or whitespace.

### `grove done` — read this before ever calling it

Verified against `/c/work/grove/src/cli/done.rs`:

- Without `--force`, `done` refuses if the worktree is dirty for **any** reason,
  including **untracked files** — not just modified tracked files. A single
  stray scratch file blocks it.
- Without `--force`, `done` also refuses if the branch has unpushed commits,
  unless the HEAD commit is reachable from some remote branch (e.g. a merged
  PR left in a detached-HEAD state is still considered safe to remove).
- On success, `done` removes the git worktree **and deletes both the local
  branch and the fork-remote branch by default**. Use `--keep-local` to keep
  the local branch, `--keep-remote` to keep the remote branch. There is no
  flag to keep the worktree directory itself — `done` always removes it.
- `--force` bypasses the dirty check and the unpushed-commit check entirely
  and force-removes the worktree regardless of state. **`--force` is
  human-only. Automation and agents must never pass `--force`** — it silently
  discards uncommitted work with no recovery path.
- Deregisters the project from `registry.json` on success.

### `grove list` — works, but can be very slow

`grove list`, `grove list --short`, and `grove list --json` all compute per-project
git status (dirty/ahead/behind/untracked) by default. Verified: with ~40 registered
projects this can take many minutes and pin a CPU core — it is not hung, just slow
(likely doing a remote-containment/ahead-behind check per project). `--json` output
is well-formed and useful when it returns:

```json
{"tag": "...", "path": "...", "branch": "...", "base": "...", "frozen": false,
 "created": "...", "status": {"dirty": false, "ahead": 0, "behind": 0, "untracked": 0}}
```

For a quick single-project check, prefer `grove status <tag>` or `grove path <tag>`
(both verified fast) over a full `grove list`. If you need `list` output, run it
with a generous timeout and expect it to take a while on a repo with many projects;
`--no-status` did not observably skip the slow path in testing, so don't rely on it
for speed.

`grove path <tag>` and `grove cd <tag>` are both fast, single-lookup commands
confirmed to work exactly as documented — they print the worktree path with no
status computation.

## Key Conventions

- Branch naming: `<ISSUE_PREFIX>-<issue>-<tag>` when `--issue` is given (e.g.
  `DESKTOP-1234-phonecam`); otherwise just `<tag>`, or an explicit `--branch`.
- Two remotes per repo: `upstream_remote` (company remote, `if` for desktop) and
  `fork_remote` (personal fork, `my` for desktop). `done` deletes the branch on
  `fork_remote`, not `upstream_remote`.
- `grove repo show <id>` and `grove repo list` are fast, read-only ways to check
  a repo's configuration without touching the registry.

## For Agents — mandatory worktree contract

1. **Create worktrees only through grove.** Use `grove new <tag> --issue N`
   (issue-tracked work) or `grove fork [<src>] <tag>` (branching off an existing
   worktree). Both register the worktree in `registry.json` so `grove done` can
   clean it up later. Never run raw `git worktree add` or `git clone` to create a
   new working copy under a grove-managed `work_dir` (e.g. `/c/work/desktop`) —
   an unregistered directory is invisible to `grove list`/`done` and becomes
   exactly the kind of untracked sprawl grove exists to prevent.
2. **Finish with `grove done <tag>`**, not manual `git worktree remove`. Commit
   or stash everything first — `done` refuses on any dirty state (including
   untracked files) unless you pass `--force`, and **agents must never pass
   `--force`**. If `done` refuses, that is a signal to actually finish or clean
   up the work, not to force past it.
3. **No permanent home for ephemeral/scratch work yet.** Grove does not have an
   ephemeral-worktree mode today — `--ephemeral` / a `.scratch` namespace does
   **not exist** in this version. Until it ships
   (`bd-grove-lifecycle-p0ur.6`, which will make `grove new --ephemeral` the
   mandated path and update this section), throwaway work goes in the current
   **session's scratchpad** (`/tmp/claude-*`, the directory named in your own
   session's system prompt), never under `/c/work/desktop`.
   <!-- TODO(bd-grove-lifecycle-p0ur.6): once grove new --ephemeral / .scratch
   namespace ships, replace this bullet with the mandated ephemeral-worktree
   flow and drop the scratchpad fallback. -->
4. **Scratchpad clones** (the swarm-rule pattern of `git clone . <scratchpad>/scratch-...`
   for a throwaway branch/commit graph) also go in the session scratchpad —
   never in `/c/work/desktop` or any other grove `work_dir`, registered or not.
5. Use `grove list --json` / `grove path <tag>` to discover or resolve tags
   programmatically, not by guessing directory names. Remember `list` can be slow
   (see above) — don't block a time-sensitive script on it without a long timeout.
6. Don't modify files in another tag's worktree without being asked, and don't
   run `grove done`, `rename`, `freeze`/`thaw`, or `repo remove` against a tag you
   don't own without confirming with the user first — these mutate shared state
   other sessions may depend on.
