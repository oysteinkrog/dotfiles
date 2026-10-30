# Voxtype dictation: the localbuilds package for this machine's variant, its models and
# the per-machine settings. The units (voxtype.service and the two sync timers) are
# enabled in the services step. Safe to re-run: a machine that is set up only gets ok lines.
# The guide is docs/computers/voice-typing.md in the private Life repo.

step "voxtype"
vx_variant=$HOST_VOXTYPE_VARIANT
if [ -z "$vx_variant" ]; then if has_nvidia; then vx_variant=cuda; else vx_variant=cpu; fi; fi
vx_pkg=voxtype-$vx_variant-local
lb=$HOME/.local/bin/localbuild

# The package links to the ONNX Runtime 1.24.4 that voxtype-bin (AUR, packages step)
# installs, so a system upgrade must not move voxtype-bin on its own. Upgrade it together
# with the recipe instead.
if grep -qE '^IgnorePkg[[:space:]]*=.*(^|[[:space:]=])voxtype-bin([[:space:]]|$)' /etc/pacman.conf; then
  ok "pacman ignores voxtype-bin upgrades"
elif grep -qE '^IgnorePkg[[:space:]]*=' /etc/pacman.conf; then
  sudo sed -i -E '0,/^IgnorePkg[[:space:]]*=/ s/^(IgnorePkg[[:space:]]*=.*)$/\1 voxtype-bin/' /etc/pacman.conf
  ok "added voxtype-bin to IgnorePkg in /etc/pacman.conf"
else
  sudo sed -i -E '0,/^#IgnorePkg/ s/^#IgnorePkg.*$/IgnorePkg = voxtype-bin/' /etc/pacman.conf
  if grep -qE '^IgnorePkg = voxtype-bin' /etc/pacman.conf; then
    ok "set IgnorePkg = voxtype-bin in /etc/pacman.conf"
  else
    warn "no IgnorePkg line in /etc/pacman.conf; add IgnorePkg = voxtype-bin under [options]"
  fi
fi

vx_pin=$(sed -n 's/^PIN=//p' "$HOME/src/localbuilds/recipes/voxtype/recipe.sh")
if pacman -Q "$vx_pkg" 2>/dev/null | grep -q "\.g${vx_pin:0:10}-"; then
  ok "$vx_pkg at ${vx_pin:0:10}"
else
  vx_got=""
  for p in "${HOST_VOXTYPE_PEERS[@]}"; do
    if "$lb" fetch "voxtype@$vx_variant" --from "$p"; then vx_got=1; break; fi
  done
  [ -n "$vx_got" ] || heavy-build "$lb" build "voxtype@$vx_variant"
  "$lb" install "voxtype@$vx_variant" && ok "$vx_pkg ${vx_pin:0:10} installed"
  if systemctl --user is-active -q voxtype.service; then
    info "voxtype runs the old build until it restarts; voxtype-update restarts it when idle"
  fi
fi

"$DOTFILES/bin/voxtype-models"

# install.sh links both files; say so here when one is missing.
vx_cfg=$HOME/.config/voxtype
if [ "$(readlink "$vx_cfg/config.toml")" = "$DOTFILES/.config/voxtype/config.toml" ]; then
  ok "voxtype config.toml from dotfiles"
else
  warn "$vx_cfg/config.toml is not the dotfiles file (run install.sh)"
fi
if [ -f "$HOST_DIR/voxtype.toml" ]; then
  if [ "$(readlink "$vx_cfg/config.d/50-host.toml")" = "$HOST_DIR/voxtype.toml" ]; then
    ok "voxtype settings for $HOST_NAME"
  else
    warn "$vx_cfg/config.d/50-host.toml is not $HOST_DIR/voxtype.toml (run install.sh)"
  fi
fi
