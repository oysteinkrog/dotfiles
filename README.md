# Dotfiles

Personal dotfiles for WSL (Ubuntu 24.04) dev environment. Symlinked via `install.sh`.

## Setup

### Prerequisites

#### System packages (apt)

```bash
sudo apt install fzf
```

#### Node.js tools (npm -g)

```bash
npm install -g @anthropic-ai/claude-code    # AI coding assistant
npm install -g @google/gemini-cli            # Gemini AI CLI
npm install -g @openai/codex                 # OpenAI Codex CLI
npm install -g pm2                           # Process manager for shared MCP services
npm install -g mcp-remote                    # MCP SSE-to-stdio bridge
npm install -g supergateway                  # MCP stdio-to-SSE gateway
```

#### Shell prompt

```bash
# starship - cross-shell prompt
curl -sS https://starship.rs/install.sh | sh
```

Config: `~/.config/starship.toml` (symlinked from `.config/`)

#### fff MCP server (file search for AI agents)

[`fff`](https://github.com/dmtrKovalenko/fff) is a Rust MCP server that exposes
`ffgrep`/`fffind`/`fff-multi-grep` — frecency-ranked, git-aware file search.
Benchmarked faster than `rg`/`fzf` for repeated searches in long-running agent processes.

```bash
# Installs ~/.local/bin/fff-mcp and prints wiring instructions
curl -fsSL https://dmtrkovalenko.dev/install-fff-mcp.sh | bash

# Register as user-scope MCP for Claude Code (use ld-linux on WSL1, see fish/functions/claude.fish)
claude mcp add -s user fff -- ~/.local/bin/fff-mcp
```

The PreToolUse hook at `.claude/hooks/rewrite-search.py` blocks raw `grep`/`find`/`egrep`/`fgrep`
in bash and steers Claude toward `mcp__fff__ffgrep` / `mcp__fff__fffind` (or `rg`/`fd` if fff
isn't registered). Append `# noqa: search-rewrite` to a command to opt out.

### Install dotfiles

```bash
git clone <repo> ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

This symlinks all config files (`.gitconfig`, `.vimrc`, `.config/`, etc.) into `$HOME`.

## What's included

| File/Dir | Purpose |
|----------|---------|
| `.gitconfig` | Git aliases, diff-so-fancy, merge config |
| `.vimrc` + `.vim/` | Vim config with bundles |
| `.ideavimrc` / `.vsvimrc` | IDE vim emulation |
| `.config/` | starship, fish, pm2, and other XDG configs |
| `.zprezto/` | Zsh framework |
| `.tmux.conf` | tmux config |
| `.ripgreprc` | ripgrep defaults |
| `bin/` | Personal scripts and tools (includes `git-hunks` for non-interactive selective hunk staging) |
| `bin/codedb` | Patched codedb binary with WSL1 compat (see below) |
| `SERVICES.md` | Shared MCP services managed by PM2 |

## Patched binaries

### codedb (WSL1 compatibility)

The upstream [codedb](https://github.com/justrach/codedb) binary doesn't work on WSL1
because Zig 0.15's stdlib uses the `statx` syscall (requires kernel 4.11+) with no
fallback. WSL1 runs kernel 4.4, so every stat call returns `ENOSYS` / `error.Unexpected`,
causing 0 files indexed.

The patched binary in `bin/codedb` adds a runtime statx probe — if the kernel doesn't
support statx, all stat calls fall back to `fstat`/`fstatat64`. Zero overhead on normal
Linux kernels that support statx.

**Patch source**: `/c/work/codedb/src/compat.zig` (fork of `justrach/codedb`)

**To rebuild** after upstream updates:

```bash
cd /c/work/codedb
git pull                          # get upstream changes
# verify src/compat.zig is present and imported in store/watcher/snapshot/index/telemetry/main
bin/codedb-build.sh --install     # cross-compile via Windows Zig, install to dotfiles
```

Cross-compilation from Windows Zig is required because Zig 0.15 itself uses statx
internally, so it can't run on WSL1 either.
