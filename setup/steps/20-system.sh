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

mkdir -p "$HOME/work"

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

# SSH between the desktops: key login only, port 22 from the tailnet only.
# Allowed keys are per machine; see ssh-access/README.md in the Life repo.
sshd_conf='# Key-only login. Reachable through Tailscale only (ufw allows 22 on tailscale0).
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers '"$(id -un)"
if [ "$(sudo cat /etc/ssh/sshd_config.d/10-hardening.conf 2>/dev/null)" != "$sshd_conf" ]; then
  printf '%s\n' "$sshd_conf" | sudo install -m 0644 /dev/stdin /etc/ssh/sshd_config.d/10-hardening.conf
fi
sudo sshd -t && sudo systemctl enable -q sshd.service && sudo systemctl reload-or-restart sshd.service
have ufw && sudo ufw allow in on tailscale0 to any port 22 proto tcp >/dev/null
ok "sshd: key login only, port 22 on tailscale0"

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

  # A key press or click at this machine ends an RDP session left open (bin/local-input-watch).
  sudo install -m 0755 -o root -g root "$DOTFILES/bin/local-input-watch" /usr/local/sbin/local-input-watch
  unit=/etc/systemd/system/local-input-watch.service
  want='[Unit]
Description=Record key presses and clicks on local USB input for krdp-remote-mode

[Service]
ExecStart=/usr/local/sbin/local-input-watch
Restart=on-failure

[Install]
WantedBy=multi-user.target'
  if [ "$(sudo cat "$unit" 2>/dev/null)" != "$want" ]; then
    printf '%s\n' "$want" | sudo tee "$unit" >/dev/null
    sudo systemctl daemon-reload
  fi
  sudo systemctl enable --now local-input-watch.service >/dev/null 2>&1
  ok "local-input-watch"
fi

# The Plasma Login greeter keeps its own monitor layout. Copy the user's layout to it on
# every change, and once at boot before the greeter starts (bin/greeter-output-sync).
if getent passwd plasmalogin >/dev/null; then
  sudo install -m 0755 -o root -g root "$DOTFILES/bin/greeter-output-sync" /usr/local/sbin/greeter-output-sync
  changed=
  unit=/etc/systemd/system/greeter-output-sync@.service
  want='[Unit]
Description=Copy the KWin monitor layout of %i to the login screen
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/greeter-output-sync %i

[Install]
WantedBy=graphical.target'
  if [ "$(sudo cat "$unit" 2>/dev/null)" != "$want" ]; then
    printf '%s\n' "$want" | sudo tee "$unit" >/dev/null; changed=1
  fi
  unit=/etc/systemd/system/greeter-output-sync@.path
  want='[Unit]
Description=Watch the KWin monitor layout of %i and of the login screen

[Path]
PathChanged=/home/%i/.config/kwinoutputconfig.json
PathChanged=/var/lib/plasmalogin/.config/kwinoutputconfig.json
Unit=greeter-output-sync@%i.service

[Install]
WantedBy=multi-user.target'
  if [ "$(sudo cat "$unit" 2>/dev/null)" != "$want" ]; then
    printf '%s\n' "$want" | sudo tee "$unit" >/dev/null; changed=1
  fi
  [ -n "$changed" ] && sudo systemctl daemon-reload
  sudo systemctl enable "greeter-output-sync@$me.service" >/dev/null 2>&1
  sudo systemctl enable --now "greeter-output-sync@$me.path" >/dev/null 2>&1
  ok "greeter-output-sync for $me"
fi

# Logitech StreamCam mic recovery (docs/streamcam.md). Installed on every machine: the
# rule only matches the StreamCam's USB ID. The udev rule starts streamcam-mic.service
# when the camera connects. The sudoers rule lets streamcam-mic-enable rebind
# snd-usb-audio when WirePlumber missed the camera's sound card during a reconnect.
rule=/etc/udev/rules.d/99-streamcam-mic.rules
if sudo cmp -s "$SETUP/system/99-streamcam-mic.rules" "$rule"; then
  ok "udev: StreamCam mic rule"
else
  sudo install -m 0644 "$SETUP/system/99-streamcam-mic.rules" "$rule"
  sudo udevadm control --reload
  ok "udev: wrote $rule"
fi
drv=/sys/bus/usb/drivers/snd-usb-audio
rule="$me ALL=(root) NOPASSWD: /usr/bin/tee $drv/unbind, /usr/bin/tee $drv/bind"
dropin=/etc/sudoers.d/92-streamcam-audio
if sudo test -f "$dropin" && sudo grep -qxF "$rule" "$dropin"; then
  ok "sudoers: StreamCam audio rebind"
else
  tmp="$(mktemp)"; echo "$rule" > "$tmp"
  if sudo visudo -cf "$tmp" >/dev/null; then
    sudo install -m 0440 -o root -g root "$tmp" "$dropin"; ok "sudoers: wrote $dropin"
  else
    fail "StreamCam sudoers rule did not validate, skipped"
  fi
  rm -f "$tmp"
fi

host_system
