#!/usr/bin/env bash
# Set up a CachyOS/Arch desktop from these dotfiles. Every step is safe to re-run.
#
#   setup/bootstrap.sh              run all steps in order
#   setup/bootstrap.sh links tools  run only the named steps
#   setup/bootstrap.sh --list       list the steps
#
# The system step uses sudo and asks for a password, so run this in a real
# terminal, not through an agent's shell. The guide is docs/computers/linux-setup.md in
# the private Life repo.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export DOTFILES="${DOTFILES:-$(dirname "$here")}"
# shellcheck source=lib.sh
. "$here/lib.sh"

steps=()
for f in "$here"/steps/[0-9][0-9]-*.sh; do
  steps+=("$(basename "$f" .sh)")
done

if [ "${1:-}" = "--list" ]; then
  printf '%s\n' "${steps[@]}"
  exit 0
fi

selected=()
if [ $# -eq 0 ]; then
  selected=("${steps[@]}")
else
  for want in "$@"; do
    match=""
    for s in "${steps[@]}"; do
      [ "${s#*-}" = "$want" ] || [ "$s" = "$want" ] && match="$s"
    done
    [ -n "$match" ] || { echo "unknown step: $want (see --list)" >&2; exit 2; }
    selected+=("$match")
  done
fi

if grep -qi microsoft /proc/version 2>/dev/null; then
  echo "This is WSL. These steps are for native Linux; use install.sh alone on WSL." >&2
  exit 1
fi

echo "dotfiles: $DOTFILES"
if [ "$HOST_KNOWN" = 1 ]; then
  echo "host:     $HOST_NAME ($HOST_DIR/host.sh)"
else
  echo "host:     $HOST_NAME (no profile in $HOSTS_ROOT, shared settings only)"
fi

for s in "${selected[@]}"; do
  # shellcheck source=/dev/null
  ( . "$here/lib.sh"; . "$here/steps/$s.sh" )
done
