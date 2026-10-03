# Root-level setup. Uses sudo. Each change is checked first, so re-running is safe.

step "system"
me="$(id -un)"

# Passwordless sudo for pacman only (the rule in ~/.claude/CLAUDE.md).
rule="$me ALL=(root) NOPASSWD: /usr/bin/pacman"
dropin=/etc/sudoers.d/90-claude-pacman
if sudo test -f "$dropin" && sudo grep -qxF "$rule" "$dropin"; then
  ok "sudoers: pacman without password"
else
  tmp="$(mktemp)"; echo "$rule" > "$tmp"
  if sudo visudo -cf "$tmp" >/dev/null; then
    sudo install -m 0440 -o root -g root "$tmp" "$dropin"; ok "sudoers: wrote $dropin"
  else
    fail "sudoers rule did not validate, skipped"
  fi
  rm -f "$tmp"
fi
for f in /etc/sudoers.d/*; do
  if sudo grep -qE "^$me[[:space:]].*NOPASSWD:[[:space:]]*ALL" "$f" 2>/dev/null; then
    warn "$f gives $me NOPASSWD ALL; remove it when setup is done: sudo rm $f"
  fi
done

# Login shell
if [ "$(getent passwd "$me" | cut -d: -f7)" = /usr/bin/fish ]; then
  ok "login shell is fish"
else
  sudo chsh -s /usr/bin/fish "$me"; ok "login shell set to fish (log out to apply)"
fi

# Old WSL paths. Hooks, scripts and old transcripts still use /c/users/oystein and /c/work.
mkdir -p "$HOME/work"
sudo mkdir -p /c/users
for pair in "/c/users/$me:$HOME" "/c/work:$HOME/work"; do
  link="${pair%%:*}"; target="${pair#*:}"
  if [ "$(readlink "$link" 2>/dev/null)" = "$target" ]; then
    ok "$link -> $target"
  elif [ -e "$link" ] || [ -L "$link" ]; then
    warn "$link exists and is not a link to $target, left alone"
  else
    sudo ln -s "$target" "$link"; ok "created $link -> $target"
  fi
done

# Docker and Tailscale
if [[ ",$(getent group docker | cut -d: -f4)," == *",$me,"* ]]; then
  ok "$me is in the docker group"
else
  sudo usermod -aG docker "$me"; ok "added $me to docker (log out to apply)"
fi
for unit in docker.service tailscaled.service; do
  if systemctl is-enabled -q "$unit" 2>/dev/null; then ok "$unit enabled"
  else sudo systemctl enable --now "$unit"; ok "$unit enabled"; fi
done
if have tailscale; then
  sudo tailscale set --operator="$me" 2>/dev/null && ok "tailscale operator is $me"
  if ! tailscale status >/dev/null 2>&1; then
    warn "tailscale is not logged in: run 'tailscale up' and open the link"
  fi
fi

# Keyboard: US with AltGr dead keys. Plain intl makes ' and " wait for the next key.
if [[ "$(localectl status)" == *"X11 Variant: altgr-intl"* ]]; then
  ok "X11 keymap us altgr-intl"
else
  sudo localectl set-x11-keymap us pc105 altgr-intl; ok "X11 keymap set to us altgr-intl"
fi

# Linger keeps user services (agent-mail, FrankenTerm mux) running without a login.
if [ "$(loginctl show-user "$me" -p Linger --value 2>/dev/null)" = yes ]; then
  ok "linger on"
else
  loginctl enable-linger "$me" 2>/dev/null || sudo loginctl enable-linger "$me"; ok "linger turned on"
fi

# Windows font aliases for Wine apps
alias_conf=/etc/fonts/conf.d/30-win32-aliases.conf
if [ -e "$alias_conf" ]; then ok "fontconfig win32 aliases"
elif [ -f /usr/share/fontconfig/conf.default/30-win32-aliases.conf ]; then
  sudo ln -s /usr/share/fontconfig/conf.default/30-win32-aliases.conf "$alias_conf"; ok "linked $alias_conf"
fi

# Firewall: Sunshine (47984-48010) and RDP (3389) from the tailnet, and from the LAN if set.
# ufw skips a rule that already exists, so these are safe to repeat. Write each rule
# out in full: a loop over "in on tailscale0" as one variable fails with an argument error.
if have ufw; then
  sudo ufw allow in on tailscale0 to any port 47984,47989,47990,48010 proto tcp >/dev/null
  sudo ufw allow in on tailscale0 to any port 47998:48010 proto udp >/dev/null
  sudo ufw allow in on tailscale0 to any port 3389 proto tcp >/dev/null
  if [ -n "$HOST_UFW_LAN" ]; then
    sudo ufw allow from "$HOST_UFW_LAN" to any port 47984,47989,47990,48010 proto tcp >/dev/null
    sudo ufw allow from "$HOST_UFW_LAN" to any port 47998:48010 proto udp >/dev/null
    sudo ufw allow from "$HOST_UFW_LAN" to any port 3389 proto tcp >/dev/null
  fi
  ok "ufw rules for Sunshine and RDP${HOST_UFW_LAN:+ (tailnet and $HOST_UFW_LAN)}"
fi

# EDID override: lets KRDP switch the streamed monitor to a size its own EDID lacks (see
# bin/edid-add-mode). The script runs as root, so install a root-owned copy rather than
# pointing a root unit at a file in the home directory.
if [ -n "$HOST_EDID_ADD_MODE" ]; then
  sudo install -m 0755 -o root -g root "$DOTFILES/bin/edid-add-mode" /usr/local/sbin/edid-add-mode
  unit=/etc/systemd/system/edid-add-mode@.service
  want='[Unit]
Description=Add a mode to a monitor EDID: %i (connector_WxH_WxH)
After=systemd-modules-load.service sys-kernel-debug.mount
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/edid-add-mode %i

[Install]
WantedBy=graphical.target'
  if [ "$(sudo cat "$unit" 2>/dev/null)" != "$want" ]; then
    printf '%s\n' "$want" | sudo tee "$unit" >/dev/null
    sudo systemctl daemon-reload
  fi
  sudo systemctl enable "edid-add-mode@$HOST_EDID_ADD_MODE.service" >/dev/null 2>&1
  ok "EDID override unit for $HOST_EDID_ADD_MODE"

  # KWin 6.7 + NVIDIA can leak kernel memory with an EDID override (bin/slab-guard).
  sudo install -m 0755 -o root -g root "$DOTFILES/bin/slab-guard" /usr/local/sbin/slab-guard
  unit=/etc/systemd/system/slab-guard.service
  want='[Unit]
Description=Stop a kernel kmalloc-128 leak (KWin/NVIDIA with an EDID override)
After=sys-kernel-debug.mount sys-kernel-tracing.mount

[Service]
ExecStart=/usr/local/sbin/slab-guard 2048
Restart=on-failure

[Install]
WantedBy=multi-user.target'
  if [ "$(sudo cat "$unit" 2>/dev/null)" != "$want" ]; then
    printf '%s\n' "$want" | sudo tee "$unit" >/dev/null
    sudo systemctl daemon-reload
  fi
  sudo systemctl enable --now slab-guard.service >/dev/null 2>&1
  ok "slab-guard"
fi

host_system
