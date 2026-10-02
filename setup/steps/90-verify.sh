# Read-only health check. Safe to run any time: setup/bootstrap.sh verify

step "verify: links"
broken=0
for l in "$HOME"/.[!.]* "$HOME"/.config/* "$HOME"/.config/systemd/user/* "$HOME"/.local/bin/* \
         "$HOME"/.local/share/applications/* "$HOME"/.config/pipewire/filter-chain.conf.d/*; do
  [ -L "$l" ] || continue
  case "$(readlink "$l")" in "$DOTFILES"/*|"$HOSTS_ROOT"/*) ;; *) continue ;; esac
  [ -e "$l" ] || { fail "broken link ${l#$HOME/} -> $(readlink "$l")"; broken=1; }
done
[ "$broken" = 0 ] && ok "no broken dotfiles links"
[ "$(realpath "$HOME/.claude")" = "$(realpath "$DOTFILES/.claude")" ] && ok "~/.claude -> dotfiles" || fail "~/.claude is not the dotfiles .claude"

step "verify: commands"
for c in git gh fish nvim rg fd jq paru rustup cargo uv node npm codex pm2 claude cass am br docker tailscale frankenterm-gui localbuild; do
  if have "$c"; then ok "$c"; else fail "$c not on PATH"; fi
done
case "$(command -v frankenterm-gui)" in
  /usr/bin/frankenterm-gui) ok "frankenterm-gui is the frankenterm-local package" ;;
  *) warn "frankenterm-gui resolves to $(command -v frankenterm-gui), not the package in /usr/bin" ;;
esac
"$HOME/.local/bin/localbuild" check

step "verify: services"
for u in agent-mail filter-chain frankenterm-mux app-dev.lizardbyte.app.Sunshine app-org.kde.krdpserver; do
  if systemctl --user is-active -q "$u.service" 2>/dev/null; then ok "$u (user)"
  else warn "$u (user) not active"; fi
done
for u in docker tailscaled; do
  systemctl is-active -q "$u.service" && ok "$u" || warn "$u not active"
done
if curl -fsS -m 3 http://127.0.0.1:4809/health >/dev/null 2>&1; then ok "agent-mail answers on :4809"
else warn "agent-mail /health on :4809 does not answer"; fi
tailscale status >/dev/null 2>&1 && ok "tailscale logged in" || warn "tailscale not logged in: tailscale up"

step "verify: session state"
[[ " $(id -nG) " == *" docker "* ]] && ok "docker group active" || warn "docker group not active in this login; log out and in"
if pgrep -af 'ld-linux-x86-64.so.2 .*claude' >/dev/null; then
  warn "some Claude sessions run through ld-linux (started before the aiolos-rc fix); restart them"
else
  ok "no Claude session runs through ld-linux"
fi
for l in /c/users/"$(id -un)" /c/work; do
  [ -e "$l" ] && ok "$l" || warn "$l missing (system step)"
done
