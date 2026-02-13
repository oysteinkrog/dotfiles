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
| `SERVICES.md` | Shared MCP services managed by PM2 |
