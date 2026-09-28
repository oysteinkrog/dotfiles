# Dotfiles

Personal dotfiles for WSL (Ubuntu 24.04) and native Linux (CachyOS/Arch). Symlinked via `install.sh`.

`install.sh` checks `/proc/version` for WSL. On native Linux it skips Windows-only
configs, links `~/.gitconfig.local` to `.gitconfig.linux`, links the systemd user units in
`.config/systemd/user/` and links `bin/dcg` into `~/.local/bin`.

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

Claude Code hooks actually wired in `.claude/settings.json`: `dcg` (destructive
command guard) and `.claude/hooks/trauma_guard.py` (blocks commands matching
learned trauma patterns) on PreToolUse for Bash, plus the gated aiolos telemetry
forwarder on all lifecycle events (`bin/aiolos-hook-forwarder`; enable/disable
via `aiolos-hooks`). A former `rewrite-search.py` hook that steered raw
`grep`/`find` toward fff/rg/fd was never wired into settings.json and has been
removed (it lives in git history if wanted again).

### Native Linux (CachyOS/Arch)

```bash
sudo pacman -S --needed git git-lfs github-cli fish tmux ripgrep fd jq rsync base-devel \
  neovim starship rustup uv bun dotnet-sdk nvm tailscale docker docker-compose docker-buildx
sudo pacman -S --needed 7zip qemu-img ntfs-3g   # only to read the old Windows disk

# Node via nvm
source /usr/share/nvm/nvm.sh
nvm install 22.14.0 && nvm alias default 22.14.0
npm install -g @ast-grep/cli @browserbasehq/browse-cli @getpaseo/cli @google/gemini-cli \
  @googleworkspace/cli @isaacphi/mcp-gdrive @jetbrains/mcp-proxy @modelcontextprotocol/inspector \
  @modelcontextprotocol/server-github @openai/codex @poai/mcpm-aider better-ccflare ccexp \
  codeburn esbuild fieldtheory mcp-remote onnxruntime-node opencode-ai pm2 supergateway

chsh -s /usr/bin/fish
git lfs install --skip-repo
gh auth login

# Old WSL paths (/c/users/oystein, /c/work) keep working through these links
sudo mkdir -p /c/users
sudo ln -s /home/oystein /c/users/oystein
sudo ln -s /home/oystein/work /c/work
```

Then run `./install.sh` (below). It links `~/.claude` to `.dotfiles/.claude` as a whole
when `~/.claude` does not exist yet (set `CLAUDE_LINK_ITEMS=1` to link single items instead).
On Linux, agent-mail runs as a systemd user service instead of under PM2:

```bash
systemctl --user daemon-reload
systemctl --user enable --now agent-mail.service   # am serve-http on port 4809
```

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
