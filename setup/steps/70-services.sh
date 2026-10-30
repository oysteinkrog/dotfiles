# systemd user services. The dotfiles units are linked by install.sh
# (.config/systemd/user/*.service and *.timer); the rest come from packages.

step "services"
systemctl --user daemon-reload

units=(
  agent-mail.service                       # dotfiles: am serve-http on 127.0.0.1:4809
  filter-chain.service                     # pipewire: the EQ sink and mic filter
  app-dev.lizardbyte.app.Sunshine.service  # sunshine package
  app-org.kde.krdpserver.service           # krdp package
  cass-maintenance.timer                   # dotfiles: cass index + cm reflect every 30 min
  claude-tab-watch.service                 # dotfiles: Claude session status in FrankenTerm tabs
  presence-detect.service                  # dotfiles: here, remote or away (reads local-input-watch, system step)
  shader-wallpaper-theme-sync.path         # dotfiles: Plasma colours into the Star Nest wallpaper
  streamcam-mic-resume.service             # dotfiles: StreamCam mic check at login and wake
  voxtype.service                          # dotfiles: dictation (package and models: voxtype step)
  voxtype-update.timer                     # dotfiles: pinned voxtype build and restart at idle
  voxtype-words-sync.timer                 # dotfiles: corrections and learned words via the life repo
  # Machine health and memory
  pressure-coordinator.service             # dotfiles: memory pressure level for heavy-build
  machine-monitor.service                  # dotfiles: reports machine health problems
  fs-walk-reaper.service                  # dotfiles: stops whole-disk search walks (find, ug, du) over 20 s old
  ui-slice.service                         # dotfiles: short EEVDF slice for desktop UI threads
  disk-guard.timer                         # dotfiles: free disk and btrfs metadata check
  build-sweep.timer                        # dotfiles: stale build output report
  cargo-target-prune.timer                 # dotfiles: superseded cargo units in ~/work/*/target
  wine-test-prefix-prune.timer             # dotfiles: unused Wine test prefixes
  desktop-git-repack.timer                 # dotfiles: monorepo object store repack
  chrome-idle-close.timer                  # dotfiles: close an idle Chrome profile under pressure
  # Claude Code sessions
  claude-persist-snapshot.timer            # dotfiles: mux tab order for session restore
  claude-throttle-log.timer                # dotfiles: logs MemoryHigh throttling
  claude-version-restart.timer             # dotfiles: restarts idle sessions on old versions
  claude-desktop-update.timer              # dotfiles: Claude Desktop from Anthropic's apt repo
  session-rest.timer                       # dotfiles: long-idle sessions to swap
  aiolos-rc-shim.service                   # dotfiles: shared TLS shim for --no-pin sessions
  aiolos-reauth-check.timer                # dotfiles: tells when an aiolos account needs a sign-in
  jsm-auto-update.timer                    # dotfiles: jeffreys-skills update at night
  # Worktrees, search and archives
  grove-autoreap.timer                     # dotfiles: removes scratch lanes past their TTL
  grove-gc.timer                           # dotfiles: weekly grove gc report
  kb-index-refresh.timer                   # dotfiles: knowledge-base qmd collections
  qmd-ifkb.service                         # dotfiles: qmd server for ifkb on localhost:8181
  ft-sync.timer                            # dotfiles: X bookmarks into the Field Theory archive
  # Desktop
  fooyin-theme-sync.path                   # dotfiles: Plasma accent colour into fooyin
  wine-fix-launchers.path                  # dotfiles: MC Wine launchers use our Wine
)
# Units only this machine runs, from HOST_USER_UNITS in its host.sh.
units+=("${HOST_USER_UNITS[@]}")
# The FrankenTerm mux needs the frankenterm-local package from the tools step.
if [ -x /usr/bin/frankenterm-mux-server ]; then
  units+=(frankenterm-mux.service)
else
  warn "/usr/bin/frankenterm-mux-server missing; frankenterm-mux not enabled (tools step)"
fi

# Multi-monitor hosts: KRDP streams one monitor, and krdp-remote-mode turns the others
# off while a client is connected. The override is generated, not tracked, because the
# index depends on the host.
if [ -n "$HOST_KRDP_MONITOR" ]; then
  dropin="$HOME/.config/systemd/user/app-org.kde.krdpserver.service.d/one-monitor.conf"
  want="# Written by setup/steps/70-services.sh from HOST_KRDP_MONITOR in host.sh.
[Service]
ExecStart=
ExecStart=/usr/bin/krdpserver --monitor $HOST_KRDP_MONITOR
# krdp-local only: fit the streamed monitor to the client's size on connect.
Environment=KRDP_OUTPUT_RESIZE_HOOK=$HOME/bin/krdp-remote-mode"
  if [ "$(cat "$dropin" 2>/dev/null)" != "$want" ]; then
    mkdir -p "${dropin%/*}"
    printf '%s\n' "$want" >"$dropin"
    systemctl --user daemon-reload
    info "KRDP streams monitor $HOST_KRDP_MONITOR; restart app-org.kde.krdpserver.service to apply"
  fi
  units+=(krdp-remote-mode.service)
fi

# presence-detect switches (fooyin_quit, build_boost, chrome_away_min). Built-in defaults
# apply without a file; a machine profile can ship its own presence.conf.
if [ -f "$HOST_DIR/presence.conf" ]; then
  link="$HOME/.config/presence.conf"
  if [ "$(readlink "$link" 2>/dev/null)" = "$HOST_DIR/presence.conf" ]; then
    ok "presence.conf from the machine profile"
  elif [ -e "$link" ] && [ ! -L "$link" ]; then
    warn "$link is a local file; the profile's presence.conf is not linked"
  else
    ln -sfn "$HOST_DIR/presence.conf" "$link"; ok "linked $link to the machine profile"
  fi
fi

# KRDP exits at start without a TLS certificate; this makes a 10-year one for this host.
have openssl && "$DOTFILES/bin/krdp-certificate" >/dev/null && ok "KRDP certificate for $(hostnamectl hostname)"

for u in "${units[@]}"; do
  if ! systemctl --user cat "$u" >/dev/null 2>&1; then
    warn "$u: unit not found"
  elif systemctl --user is-enabled -q "$u" 2>/dev/null; then
    ok "$u enabled"
  else
    systemctl --user enable --now "$u" && ok "$u enabled and started"
  fi
done

# Agent mail is registered with Claude once, at user scope (never in a repo's .mcp.json).
am_url=http://127.0.0.1:4809/mcp/
if jq -e --arg u "$am_url" '.mcpServers["mcp-agent-mail"].url == $u' "$HOME/.claude.json" >/dev/null 2>&1; then
  ok "agent mail registered with Claude"
elif have claude; then
  claude mcp remove --scope user mcp-agent-mail >/dev/null 2>&1 || true
  claude mcp add --scope user --transport http mcp-agent-mail "$am_url" >/dev/null &&
    ok "agent mail registered with Claude at user scope"
else
  warn "claude not installed; register agent mail later: claude mcp add --scope user --transport http mcp-agent-mail $am_url"
fi

# A stray alias link from an earlier manual setup duplicates the Sunshine unit.
if [ -L "$HOME/.config/systemd/user/sunshine.service" ]; then
  info "~/.config/systemd/user/sunshine.service is a leftover alias; safe to delete"
fi
