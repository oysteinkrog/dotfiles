# Rust toolchains, Node via nvm, global npm packages, fish plugins.

step "toolchains: rust"
if have rustup; then
  while read -r tc; do
    [[ "$(rustup toolchain list)" == *"$tc"* ]] || rustup toolchain install --profile minimal "$tc"
  done < <(read_list "$SETUP/packages/rustup-toolchains.txt")
  # The wezterm and cass builds fail with "no default toolchain" without this.
  rustup default >/dev/null 2>&1 || rustup default stable
  ok "rustup: $(rustup toolchain list | tr '\n' ' ')"
else
  warn "rustup missing (packages step)"
fi

step "toolchains: node"
node_version="$(read_list "$SETUP/packages/node-version")"
export NVM_DIR="$HOME/.nvm"
if [ -f /usr/share/nvm/init-nvm.sh ]; then
  # shellcheck source=/dev/null
  set +u; . /usr/share/nvm/init-nvm.sh
  if [ ! -x "$NVM_DIR/versions/node/v$node_version/bin/node" ]; then
    nvm install "$node_version"
  fi
  nvm alias default "$node_version" >/dev/null
  nvm use "$node_version" >/dev/null; set -u
  ok "node $(node --version) via nvm"
  # config.fish puts this version's bin dir on PATH; keep them in step.
  grep -q "v$node_version" "$DOTFILES/.config/fish/config.fish" ||
    warn "config.fish does not mention v$node_version; update its node PATH line"

  step "toolchains: npm globals"
  installed="$(npm ls -g --depth=0 --parseable 2>/dev/null | sed 's|.*/node_modules/||')"
  missing=()
  while read -r p; do
    grep -qxF -- "$p" <<<"$installed" || missing+=("$p")
  done < <(read_list "$SETUP/packages/npm-global.txt")
  if [ ${#missing[@]} -eq 0 ]; then
    ok "all npm globals installed"
  else
    info "installing: ${missing[*]}"
    npm install -g "${missing[@]}" || warn "some npm installs failed, see above"
  fi
else
  warn "nvm missing (packages step)"
fi

