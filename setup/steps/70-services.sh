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
)
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

for u in "${units[@]}"; do
  if ! systemctl --user cat "$u" >/dev/null 2>&1; then
    warn "$u: unit not found"
  elif systemctl --user is-enabled -q "$u" 2>/dev/null; then
    ok "$u enabled"
  else
    systemctl --user enable --now "$u" && ok "$u enabled and started"
  fi
done

# A stray alias link from an earlier manual setup duplicates the Sunshine unit.
if [ -L "$HOME/.config/systemd/user/sunshine.service" ]; then
  info "~/.config/systemd/user/sunshine.service is a leftover alias; safe to delete"
fi
