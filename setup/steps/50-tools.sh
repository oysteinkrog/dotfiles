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

step "tools: Shader Wallpaper (localbuilds recipe shader-wallpaper)"
# The Plasma wallpaper plugin online.knowmad.shaderwallpaper v4, from the pacman package
# plasma-wallpaper-shader-local. The KDE Store copy (3.0.3) cannot save its settings.
if pacman -Q plasma-wallpaper-shader-local >/dev/null 2>&1 && [ -z "${REBUILD:-}" ]; then
  ok "$(pacman -Q plasma-wallpaper-shader-local)"
else
  "$HOME/.local/bin/localbuild" build shader-wallpaper
  "$HOME/.local/bin/localbuild" install shader-wallpaper
fi
"$HOME/bin/shader-wallpaper-theme-sync" && ok "themed Star Nest shader in ~/.local/share/shader-wallpaper"

step "tools: Plasma Login Manager (localbuilds recipe plasma-login-manager)"
# The pacman package plasma-login-manager-local: adds [Greeter] BlurWallpaper, which the
# desktop step sets to false so the login screen shows the shader sharp. It replaces the
# distro package, and pacman -U --noconfirm will not remove that by itself.
if ! systemctl is-enabled -q plasmalogin.service 2>/dev/null; then
  ok "Plasma Login Manager not in use; skipped"
elif pacman -Q plasma-login-manager-local >/dev/null 2>&1 && [ -z "${REBUILD:-}" ]; then
  ok "$(pacman -Q plasma-login-manager-local)"
else
  "$HOME/.local/bin/localbuild" build plasma-login-manager
  pacman -Q plasma-login-manager >/dev/null 2>&1 && sudo pacman -Rdd --noconfirm plasma-login-manager >/dev/null
  "$HOME/.local/bin/localbuild" install plasma-login-manager || sudo pacman -S --noconfirm plasma-login-manager
fi

step "tools: agent mail (localbuilds recipe mcp-agent-mail)"
# The pacman package mcp-agent-mail-local. agent-mail.service and older scripts use the
# ~/.local/bin paths, so those are symlinks. See the recipe README before moving the pin.
if pacman -Q mcp-agent-mail-local >/dev/null 2>&1 && [ -z "${REBUILD:-}" ]; then
  ok "$(pacman -Q mcp-agent-mail-local)"
else
  "$HOME/.local/bin/localbuild" build mcp-agent-mail
  "$HOME/.local/bin/localbuild" install mcp-agent-mail
fi
ln -sfn /usr/bin/am "$HOME/.local/bin/am"
ln -sfn /usr/bin/mcp-agent-mail "$HOME/.local/bin/mcp-agent-mail"
for alias in agent-mail agentmail mcp_agent_mail mcpagentmail; do
  ln -sfn mcp-agent-mail "$HOME/.local/bin/$alias"
done

step "tools: krdp-local (localbuilds recipes freerdp, kpipewire, krdp)"
# RDP sound, microphone and a streamed monitor that takes the client's size. Only on
# machines that stream a monitor (HOST_KRDP_MONITOR). freerdp and kpipewire are private
# copies in /opt/krdp-local, so they go first. krdp-local conflicts with the repo krdp,
# which `localbuild install` cannot replace, so its package goes in with pacman --ask=4.
if [ -n "$HOST_KRDP_MONITOR" ]; then
  for r in freerdp kpipewire; do
    if pacman -Q "$r-krdp-local" >/dev/null 2>&1 && [ -z "${REBUILD:-}" ]; then
      ok "$(pacman -Q "$r-krdp-local")"
    else
      heavy-build "$HOME/.local/bin/localbuild" build "$r" && "$HOME/.local/bin/localbuild" install "$r"
    fi
  done
  if pacman -Q krdp-local >/dev/null 2>&1 && [ -z "${REBUILD:-}" ]; then
    ok "$(pacman -Q krdp-local)"
  else
    heavy-build "$HOME/.local/bin/localbuild" build krdp
    pkg=$(find "$HOME/.cache/build/krdp" -path '*/out/*' -name 'krdp-local-*.pkg.tar.*' ! -name '*-debug-*' ! -name '*.sig' \
      -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2)
    sudo pacman -U --noconfirm --ask=4 "$pkg" && ok "krdp-local installed; restart app-org.kde.krdpserver.service"
  fi
fi

step "tools: qmd"
# Markdown search for the Life vault and the knowledge bases. Installed under ~/.local
# (not the nvm prefix), because qmd-ifkb.service runs ~/.local/lib/node_modules/@tobilu/qmd.
# Its native modules must be built by the nvm Node in packages/node-version.
qmd_ver=2.8.3
qmd_pkg="$HOME/.local/lib/node_modules/@tobilu/qmd"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && nvm use -s "$(cat "$SETUP/packages/node-version")" >/dev/null
if [ "$(jq -r .version "$qmd_pkg/package.json" 2>/dev/null)" = "$qmd_ver" ]; then
  ok "qmd $qmd_ver"
else
  npm install -g --prefix "$HOME/.local" "@tobilu/qmd@$qmd_ver" && ok "qmd $qmd_ver installed"
fi
# Collections. The monorepo knowledge bases are added by kb-index-refresh.timer once
# ~/work/desktop exists. ifkb keeps its own index in the clone (.qmd/index.yml).
if [ -d "$HOME/projects/life/vault" ]; then
  qmd collection show life >/dev/null 2>&1 || qmd collection add "$HOME/projects/life/vault" --name life >/dev/null
  qmd update >/dev/null && qmd embed >/dev/null && ok "qmd: life collection indexed"
fi
if [ -f "$HOME/work/ifkb/.qmd/index.yml" ]; then
  (cd "$HOME/work/ifkb" && qmd update >/dev/null && qmd embed >/dev/null) && ok "qmd: ifkb index built"
fi

step "tools: aiolos-rc"
if [ -f "$DOTFILES/.config/aiolos-rc/preload.so" ]; then
  ok "preload.so built"
else
  bash "$DOTFILES/.config/aiolos-rc/setup.sh"
fi

step "tools: tasklens"
# The task manager, the pacman package tasklens built from ~/projects/tasklens (setup/work-repos.sh
# in Life clones it). It cannot be copied from the other desktop: CachyOS makepkg builds Rust
# with -C target-cpu=native (/etc/makepkg.conf.d/rust.conf), and the office build (AMD Zen 3)
# dies with SIGILL on the home Intel CPU.
if pacman -Q tasklens >/dev/null 2>&1; then
  ok "$(pacman -Q tasklens)"
else
  warn "tasklens not installed: check out the newest release tag in ~/projects/tasklens, then"
  info "cd ~/projects/tasklens/packaging && heavy-build makepkg -f --nocheck && sudo pacman -U tasklens-*.pkg.tar.zst"
fi

step "tools: prebuilt binaries"
# name|where it lives|where it comes from
prebuilt=(
  "br|.local/bin|beads_rust"
  "cm|.local/bin|cass-memory"
  "jsm|.local/bin|jeffreys-skills CLI (needs a login)"
  "fsfs|.local/bin|frankensearch"
  "herdr|.local/bin|herdr"
  "mt|.local/bin|MidTerm (with mt-linux mthost-linux mtagenthost-linux)"
  "fff-mcp|.local/bin|curl -fsSL https://dmtrkovalenko.dev/install-fff-mcp.sh | bash"
  "dcg|bin|destructive command guard; install.sh links it into ~/.local/bin"
  "gog|bin|Google Workspace CLI"
  "aiolos-hook-forwarder|bin|built from ~/projects/aiolos"
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
