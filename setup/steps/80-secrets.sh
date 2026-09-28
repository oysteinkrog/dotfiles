# Check that the secret and login files exist with safe permissions. Never prints values.

step "secrets"
while read -r p flag; do
  flag="${flag%%#*}"; flag="${flag// /}"
  f="$HOME/${p%/}"
  if [ ! -e "$f" ]; then
    if [ "$flag" = optional ]; then info "missing ~/$p (optional, log in instead)"
    else warn "missing ~/$p (setup/secrets-bundle.sh unpack, see docs/secrets.md)"; fi
    continue
  fi
  if [ -d "$f" ]; then
    loose="$(find "$f" \( -type f -o -type d \) -perm /go+rwx ! -name '*.pub' ! -name known_hosts -print -quit 2>/dev/null)"
    if [ -n "$loose" ] && [ "${p%/}" != .gemini ]; then
      warn "~/$p has group/world access (e.g. ${loose#$HOME/}); run: chmod -R go-rwx ~/$p"
    else
      ok "~/$p"
    fi
  else
    ok "~/$p"
  fi
done < <(read_list "$SETUP/secret-paths.txt")

if [ -f "$HOME/.config/secrets/.env" ] && [ -x "$DOTFILES/bin/secret" ]; then
  n="$("$DOTFILES/bin/secret" --list 2>/dev/null | wc -l)"
  ok "secret --list: $n keys"
fi
