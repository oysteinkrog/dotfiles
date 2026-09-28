# Tools that no package provides: the Claude Code native build, source builds
# (WezTerm fork, cass), aiolos-rc's preload, and prebuilt binaries in ~/.local/bin
# and ~/bin that are not in git.
#
# TOOLS_FROM=<ssh host> copies the prebuilt binaries from the other desktop, e.g.
#   TOOLS_FROM=oystein-office-primary setup/bootstrap.sh tools
# REBUILD=1 rebuilds WezTerm and cass even when they are installed.

mkdir -p "$HOME/.local/bin" "$HOME/src" "$HOME/work"

step "tools: Claude Code"
if [ -x "$HOME/.local/bin/claude" ]; then
  ok "claude $("$HOME/.local/bin/claude" --version 2>/dev/null)"
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

step "tools: WezTerm fork (vertical tabs)"
# .config/wezterm/wezterm.lua uses tab_bar_position, which only the fork has. The
# mux unit, autostart and launcher all run ~/.local/bin/wezterm*.
wez_src="$HOME/src/wezterm"
if [ -x "$HOME/.local/bin/wezterm-mux-server" ] && [ -z "${REBUILD:-}" ]; then
  ok "wezterm $("$HOME/.local/bin/wezterm" --version 2>/dev/null)"
else
  if [ ! -d "$wez_src/.git" ]; then
    git clone https://github.com/oysteinkrog/wezterm.git "$wez_src"
    git -C "$wez_src" remote add upstream https://github.com/wezterm/wezterm.git
  fi
  git -C "$wez_src" submodule update --init --recursive
  (cd "$wez_src" && cargo build --release -p wezterm -p wezterm-gui -p wezterm-mux-server)
  install -m755 "$wez_src"/target/release/{wezterm,wezterm-gui,wezterm-mux-server} "$HOME/.local/bin/"
  ok "installed wezterm fork into ~/.local/bin"
fi

step "tools: cass"
# One build serves both names. Pinned to the upstream commit that is live on the
# office desktop; see docs/cass-setup.md before moving it.
cass_ref=4773d03e
cass_src="$HOME/work/cass-gpu"
if [ -x "$HOME/.local/bin/cass" ] && [ -z "${REBUILD:-}" ]; then
  ok "$("$HOME/.local/bin/cass" --version 2>/dev/null)"
else
  if [ ! -d "$cass_src/.git" ]; then
    git clone https://github.com/Dicklesworthstone/coding_agent_session_search.git "$cass_src"
    git -C "$cass_src" remote rename origin upstream
    git -C "$cass_src" remote add origin git@github.com:oysteinkrog/coding_agent_session_search.git
  fi
  git -C "$cass_src" fetch upstream
  git -C "$cass_src" checkout -B main-latest "$cass_ref"
  (cd "$cass_src" && nice -n 5 cargo build --release --bin cass)
  install -m755 "$cass_src/target/release/cass" "$HOME/.local/bin/cass"
  ln -sfn cass "$HOME/.local/bin/cass-gpu"
  ok "installed cass from $cass_ref"
fi

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
  info "copy them from the other desktop with TOOLS_FROM=<host>, see docs/linux-setup.md"
fi

# Old static binaries in ~/bin shadow newer pacman ones because ~/bin is first on PATH.
for name in docker pandoc hugo gitui; do
  if [ -x "$DOTFILES/bin/$name" ] && [ -x "/usr/bin/$name" ]; then
    warn "~/bin/$name shadows /usr/bin/$name; delete ~/.dotfiles/bin/$name (it is gitignored)"
  fi
done
