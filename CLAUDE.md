# User CLAUDE.md

Machine-level notes for work under `~`. The global rules are in `~/.claude/CLAUDE.md`,
including multi-agent orchestration, secrets and the writing contract.

## Grove worktree manager

`grove` manages git worktrees for a mono-repo workflow, each worktree a "project" with a
short tag. This is the rust build: binary `~/.cargo/bin/grove`, source `/c/work/grove`.
Never read worktree lists from the stale files in `~/.config/grove/`; `grove-workflow`
names the live config and registry paths.

- **Load `grove-workflow` before any worktree work.** It holds every command, the flags and
  the traps.
- **Never run `grove list` in agent context.** It works out git status per project and takes
  17+ minutes on WSL1. Use `git -C <repo>/master worktree list --porcelain` instead.
- Shortcuts: `gr <tag>` is `grove cd <tag>`; bare `gr` is `grove list --short`.

## Consulting oracles

**GPT-6 Astra is the primary oracle**, reached through the Codex CLI. Consult it first for
second opinions, design validation, hard debugging and architecture review. One Astra call is
a complete consultation.

- **Fable is the secondary oracle.** Add a Fable consultation on the same question when the
  decision is high-stakes or hard to reverse, when Astra's answer looks thin, or when Oystein
  asks for a second opinion. Present both views clearly labelled and call out disagreements.
- **Fallback order when the Codex call fails**, whatever the reason: Fable subagent, then
  Opus subagent. Say which one answered. Never downgrade silently.
- **Codex calls leave the machine.** The confidentiality rule in the global file applies.
- **Load `consult-oracles`** for the exact invocation and its known failure modes.

## Python

All Python work uses uv for packages, ruff for lint and format, ty for type checking. After
editing `.py` files run `ruff check --fix && ruff format && ty check`. Load `/py-uv`,
`/py-ruff` and `/py-ty` for details.

## X/Twitter bookmarks

Bookmarks are archived locally in `~/.ft-bookmarks/` and searched with the `ft` CLI. **Load
`/fieldtheory`** before searching, browsing or syncing. Cookies expire; when a sync fails
with an auth error, ask Oystein to re-extract them.

## CASS

The full setup and recovery runbook for a new machine is
[docs/cass-setup.md](docs/cass-setup.md). The standing rules are in the global file.
