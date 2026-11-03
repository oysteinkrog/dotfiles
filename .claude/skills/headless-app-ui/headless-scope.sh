#!/bin/sh
# Run a command in its own transient systemd scope and stop the whole scope when it ends.
# dbus-run-session ends its bus when the command exits, but D-Bus-activated helpers
# (ksecretd, kactivitymanagerd, xdg-desktop-portal-kde) keep running without a bus.
# They start inside this scope, so stopping the scope ends them.
# Usage: headless-scope.sh <tag> -- <command> [args...]
set -u
tag=${1:?usage: headless-scope.sh <tag> -- <command> [args...]}
[ "${2:-}" = -- ] || { echo "usage: headless-scope.sh <tag> -- <command> [args...]" >&2; exit 2; }
shift 2
unit=headless-$tag-$$
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
