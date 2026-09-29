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
# The WezTerm mux and the Claude restore unit need the fork binaries from the tools step.
if [ -x "$HOME/.local/bin/wezterm-mux-server" ]; then
  units+=(wezterm-mux.service)
  [ -f "$HOME/.config/systemd/user/claude-restore.service" ] && units+=(claude-restore.service)
else
  warn "~/.local/bin/wezterm-mux-server missing; wezterm-mux not enabled (tools step)"
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
