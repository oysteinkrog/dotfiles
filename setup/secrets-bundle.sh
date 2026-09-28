#!/usr/bin/env bash
# Move the secret files in setup/secret-paths.txt between desktops, encrypted.
#
#   setup/secrets-bundle.sh pack [FILE]    write FILE (default ~/secrets-<host>-<date>.tar.gpg)
#   setup/secrets-bundle.sh unpack FILE    restore into $HOME and fix permissions
#
# gpg asks for a passphrase. Carry the file on a USB stick or send it with
# `tailscale file cp FILE <other-host>:`. Delete it after unpacking.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$here/lib.sh"

paths=()
while read -r p _; do paths+=("${p%/}"); done < <(read_list "$here/secret-paths.txt")

case "${1:-}" in
  pack)
    out="${2:-$HOME/secrets-$HOST_NAME-$(date +%F).tar.gpg}"
    present=()
    for p in "${paths[@]}"; do [ -e "$HOME/$p" ] && present+=("$p"); done
    # Sockets and lock files in .gnupg are runtime state.
    tar -C "$HOME" -czf - --exclude='S.gpg-agent*' --exclude='*.lock' "${present[@]}" |
      gpg --symmetric --cipher-algo AES256 -o "$out"
    chmod 600 "$out"
    echo "wrote $out (${#present[@]} of ${#paths[@]} paths)"
    ;;
  unpack)
    in="${2:?usage: unpack FILE}"
    gpg --decrypt "$in" | tar -C "$HOME" -xzf -
    chmod 700 "$HOME/.config/secrets" "$HOME/.ssh" "$HOME/.gnupg" 2>/dev/null || true
    find "$HOME/.config/secrets" "$HOME/.ssh" "$HOME/.gnupg" -type f -exec chmod 600 {} + 2>/dev/null || true
    find "$HOME/.ssh" -name '*.pub' -exec chmod 644 {} + 2>/dev/null || true
    echo "restored into $HOME; now delete $in"
    ;;
  *)
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
