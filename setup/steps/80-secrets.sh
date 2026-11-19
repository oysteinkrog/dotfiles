# Check that the secret and login files exist with safe permissions. Never prints values.

step "secrets"
while read -r p flag; do
  flag="${flag%%#*}"; flag="${flag// /}"
  f="$HOME/${p%/}"
  if [ ! -e "$f" ]; then
    if [ "$flag" = optional ]; then info "missing ~/$p (optional, log in instead)"
    else warn "missing ~/$p (setup/secrets-bundle.sh unpack, see docs/computers/secrets.md in Life)"; fi
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

sd="$HOME/.config/secrets"
if [ -f "$sd/work.env" ] && [ -f "$sd/personal.env" ]; then
  # .env is generated from the two owned files; rebuild it if it is missing or stale.
  if "$DOTFILES/bin/secrets-build" --check >/dev/null 2>&1; then
    ok "secrets: work.env $(grep -c '^[A-Za-z_]' "$sd/work.env") keys, personal.env $(grep -c '^[A-Za-z_]' "$sd/personal.env") keys, .env current"
  elif "$DOTFILES/bin/secrets-build" >/dev/null; then
    ok "secrets: rebuilt .env from work.env and personal.env"
  else
    warn "secrets-build failed; run it by hand to see why"
  fi
elif [ -f "$sd/.env" ]; then
  warn "~/.config/secrets has only a hand-kept .env; split it into work.env and personal.env (docs/computers/secrets.md in Life)"
fi
if [ -f "$sd/.env" ] && [ -x "$DOTFILES/bin/secret" ]; then
  n="$("$DOTFILES/bin/secret" --list 2>/dev/null | wc -l)"
  ok "secret --list: $n keys"
fi
