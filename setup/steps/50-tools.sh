# Tools that no package provides: the Claude Code native build, localbuilds and the
# FrankenTerm and cass packages it builds, aiolos-rc's preload, and prebuilt binaries in
# ~/.local/bin and ~/bin that are not in git.
#
# TOOLS_FROM=<ssh host> copies the prebuilt binaries from the other desktop, e.g.
#   TOOLS_FROM=<other-desktop> setup/bootstrap.sh tools
# REBUILD=1 rebuilds FrankenTerm and cass even when they are installed.

mkdir -p "$HOME/.local/bin" "$HOME/src" "$HOME/work"

step "tools: Claude Code"
if [ -x "$HOME/.local/bin/claude" ]; then
  ok "claude $("$HOME/.local/bin/claude" --version 2>/dev/null)"
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

step "tools: localbuilds"
# Patched and source-built upstream projects: recipes and the localbuild command.
# See ~/src/localbuilds/README.md.
lb_src="$HOME/src/localbuilds"
if [ ! -d "$lb_src/.git" ]; then
  git clone https://github.com/oysteinkrog/localbuilds.git "$lb_src"
  git -C "$lb_src" config core.hooksPath hooks
fi
ln -sfn ../../src/localbuilds/bin/localbuild "$HOME/.local/bin/localbuild"
ok "localbuild $(git -C "$lb_src" log -1 --format=%h)"

step "tools: FrankenTerm (localbuilds recipe frankenterm)"
# The terminal, its mux unit and the launcher run /usr/bin/frankenterm-*, from the
# pacman package frankenterm-local.
if pacman -Q frankenterm-local >/dev/null 2>&1 && [ -z "${REBUILD:-}" ]; then
  ok "$(pacman -Q frankenterm-local)"
else
  "$HOME/.local/bin/localbuild" build frankenterm
  "$HOME/.local/bin/localbuild" install frankenterm
fi
# Symlinks for scripts that still use the old ~/.local/bin paths.
ln -sfn /usr/bin/frankenterm-gui "$HOME/.local/bin/frankenterm-gui"
ln -sfn /usr/bin/frankenterm-mux-server "$HOME/.local/bin/frankenterm-mux-server"

step "tools: cass (localbuilds recipe cass)"
# The pacman package cass-local, pinned in ~/src/localbuilds/recipes/cass; see
# docs/cass-setup.md before moving the pin. ~/.local/bin/cass and cass-gpu are symlinks
# for scripts that use the old path, and they stop `cass upgrade` replacing the build.
if pacman -Q cass-local >/dev/null 2>&1 && [ -z "${REBUILD:-}" ]; then
  ok "$(pacman -Q cass-local)"
else
  "$HOME/.local/bin/localbuild" build cass
  "$HOME/.local/bin/localbuild" install cass
fi
ln -sfn /usr/bin/cass "$HOME/.local/bin/cass"
ln -sfn /usr/bin/cass "$HOME/.local/bin/cass-gpu"

step "tools: aiolos-rc"
if [ -f "$DOTFILES/.config/aiolos-rc/preload.so" ]; then
  ok "preload.so built"
else
  bash "$DOTFILES/.config/aiolos-rc/setup.sh"
fi

step "tools: prebuilt binaries"
# name|where it lives|where it comes from
prebuilt=(
  "am|.local/bin|mcp-agent-mail (rust); also links agent-mail agentmail mcp_agent_mail mcpagentmail -> mcp-agent-mail"
  "mcp-agent-mail|.local/bin|mcp-agent-mail (rust)"
  "br|.local/bin|beads_rust"
  "cm|.local/bin|cass-memory"
  "jsm|.local/bin|jeffreys-skills CLI (needs a login)"
  "fsfs|.local/bin|frankensearch"
  "herdr|.local/bin|herdr"
  "mt|.local/bin|MidTerm (with mt-linux mthost-linux mtagenthost-linux)"
  "fff-mcp|.local/bin|curl -fsSL https://dmtrkovalenko.dev/install-fff-mcp.sh | bash"
  "dcg|bin|destructive command guard; install.sh links it into ~/.local/bin"
  "gog|bin|Google Workspace CLI"
  "aiolos-hook-forwarder|bin|built from ~/work/aiolos"
  "claw|bin|claw"
  "claurst|bin|claurst"
  "claude-rs|bin|claude-rs"
)
missing=()
for row in "${prebuilt[@]}"; do
  IFS='|' read -r name where _ <<<"$row"
  target="$HOME/$where/$name"
  [ "$where" = bin ] && target="$DOTFILES/bin/$name"
  [ -x "$target" ] || missing+=("$row")
done
if [ ${#missing[@]} -gt 0 ] && [ -n "${TOOLS_FROM:-}" ]; then
  info "copying from $TOOLS_FROM"
  rsync -a "$TOOLS_FROM:.local/bin/" "$HOME/.local/bin/" \
    --exclude claude --exclude 'wezterm*' --exclude cass --exclude cass-gpu
  rsync -a "$TOOLS_FROM:.dotfiles/bin/" "$DOTFILES/bin/" --ignore-existing
  missing=()
  for row in "${prebuilt[@]}"; do
    IFS='|' read -r name where _ <<<"$row"
    target="$HOME/$where/$name"; [ "$where" = bin ] && target="$DOTFILES/bin/$name"
    [ -x "$target" ] || missing+=("$row")
  done
fi
if [ ${#missing[@]} -eq 0 ]; then
  ok "all ${#prebuilt[@]} prebuilt binaries present"
else
  for row in "${missing[@]}"; do
    IFS='|' read -r name where from <<<"$row"
    warn "missing ~/$where/$name: $from"
  done
  info "copy them from the other desktop with TOOLS_FROM=<host>, see docs/computers/linux-setup.md in Life"
fi

# Old static binaries in ~/bin shadow newer pacman ones because ~/bin is first on PATH.
for name in docker pandoc hugo gitui; do
  if [ -x "$DOTFILES/bin/$name" ] && [ -x "/usr/bin/$name" ]; then
    warn "~/bin/$name shadows /usr/bin/$name; delete ~/.dotfiles/bin/$name (it is gitignored)"
  fi
done
