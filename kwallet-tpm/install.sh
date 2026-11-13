#!/bin/sh
# Make D-Bus start ksecretd through ksecretd-tpm, or undo that.
# Usage: install.sh          write the two service files
#        install.sh --undo   remove them again
# It writes only to $XDG_DATA_HOME/dbus-1/services (default ~/.local/share/dbus-1/services).
# A service file there wins over the one with the same name in /usr/share/dbus-1/services.
# Nothing changes for a ksecretd that is already running; the files are used on the next
# activation, normally at the next login.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
dir=${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services
marker='/ksecretd-tpm'   # our files are the ones whose Exec ends in this
# The two names in /usr/share/dbus-1/services whose Exec is /usr/bin/ksecretd.
names='org.kde.secretservicecompat org.freedesktop.impl.portal.desktop.kwallet'

if [ "${1:-}" = --undo ]; then
  for n in $names; do
    f=$dir/$n.service
    if [ -f "$f" ] && grep -qF "$marker" "$f"; then
      rm -f "$f" && echo "removed $f"
    fi
  done
  exit 0
fi

mkdir -p "$dir"
for n in $names; do
  f=$dir/$n.service
  if [ -f "$f" ] && ! grep -qF "$marker" "$f"; then
    echo "install.sh: $f exists and is not ours, leaving it" >&2
    exit 1
  fi
  printf '[D-BUS Service]\nName=%s\nExec=%s/ksecretd-tpm\n' "$n" "$here" > "$f"
  echo "wrote $f"
done
