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
