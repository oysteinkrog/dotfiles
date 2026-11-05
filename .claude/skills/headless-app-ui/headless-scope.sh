#!/bin/sh
# Run a command in its own transient systemd scope and stop the whole scope when it ends.
# dbus-run-session ends its bus when the command exits, but D-Bus-activated helpers
# (ksecretd, kactivitymanagerd, xdg-desktop-portal-kde) keep running without a bus.
# They start inside this scope, so stopping the scope ends them.
# Two more things happen here. A command that starts with dbus-run-session gets
# --config-file=headless-session.conf (next to this script), a session bus config with no
# system service directories: the bus then activates nothing, so xdg-desktop-portal-kde is
# never started without a display and never dumps core (225 dumps on 2026-11-05, from nested
# KWin runs). HEADLESS_SCOPE_SYSTEM_SERVICES=1 keeps the old bus. And core dumps are off for
# everything in the scope (ulimit -c 0).
# Usage: headless-scope.sh <tag> -- <command> [args...]
set -u
tag=${1:?usage: headless-scope.sh <tag> -- <command> [args...]}
[ "${2:-}" = -- ] || { echo "usage: headless-scope.sh <tag> -- <command> [args...]" >&2; exit 2; }
shift 2
unit=headless-$tag-$$
ulimit -c 0 2>/dev/null || true
if [ "${1##*/}" = dbus-run-session ] && [ "${HEADLESS_SCOPE_SYSTEM_SERVICES:-0}" != 1 ]; then
  # Look only at dbus-run-session's own options (up to --, or the first non-option), so the
  # wrapped program's arguments never count. Both --config-file=F and --config-file F count.
  own=0
  i=0
  for a in "$@"; do
    i=$((i + 1))
    [ $i -eq 1 ] && continue
    case "$a" in
      --) break ;;
      --config-file|--config-file=*|--dbus-daemon|--dbus-daemon=*) own=1; break ;;
      -*) ;;
      *) break ;;
    esac
  done
  conf=$(cd "$(dirname "$0")" && pwd)/headless-session.conf
  if [ "$own" = 0 ] && [ -f "$conf" ]; then
    first=$1; shift
    set -- "$first" --config-file="$conf" "$@"
  fi
fi
# Own KDE cache per instance: a shared ~/.cache/ksycoca6_* makes the real KWin rebuild it
# on its main thread and freezes the desktop (2026-11-03). Keep a caller's own non-default value.
case "${XDG_CACHE_HOME:-}" in
  ""|"$HOME/.cache"|"$HOME/.cache/") XDG_CACHE_HOME=/var/tmp/claude/headless/$unit/cache ;;
esac
mkdir -p "$XDG_CACHE_HOME" || exit 1
export XDG_CACHE_HOME
stop() { systemctl --user stop "$unit.scope" 2>/dev/null; }
trap 'stop; exit 143' INT TERM HUP
systemd-run --user --scope --quiet --collect --unit="$unit" -- "$@"
rc=$?
trap - INT TERM HUP
stop
exit $rc
