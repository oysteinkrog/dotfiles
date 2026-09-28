# Repo and AUR packages from setup/packages/, plus this host's extras.

step "packages: pacman"
pkgs=()
mapfile -t pkgs < <(read_list "$SETUP/packages/pacman.txt")
if has_nvidia; then
  mapfile -t -O "${#pkgs[@]}" pkgs < <(read_list "$SETUP/packages/nvidia.txt")
  info "NVIDIA GPU found, adding packages/nvidia.txt"
fi
pkgs+=("${HOST_PACKAGES[@]}")
missing=()
for p in "${pkgs[@]}"; do
  pacman -Qq "$p" >/dev/null 2>&1 || pacman -Qqg "$p" >/dev/null 2>&1 || missing+=("$p")
done
if [ ${#missing[@]} -eq 0 ]; then
  ok "all ${#pkgs[@]} packages installed"
else
  info "installing: ${missing[*]}"
  sudo pacman -S --needed --noconfirm "${missing[@]}"
fi

step "packages: AUR"
aur=()
mapfile -t aur < <(read_list "$SETUP/packages/aur.txt")
aur+=("${HOST_AUR_PACKAGES[@]}")
missing=()
for p in "${aur[@]}"; do
  pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p")
done
if [ ${#missing[@]} -eq 0 ]; then
  ok "all ${#aur[@]} AUR packages installed"
elif have paru; then
  paru -S --needed --noconfirm --skipreview "${missing[@]}"
else
  warn "paru missing, cannot install: ${missing[*]}"
fi
