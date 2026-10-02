#!/bin/bash
# Show Claude's state in the terminal tab bar.
# Usage: term-state.sh <working|complete|input|error> [bell]
#
# Sets the claude_state user var (OSC 1337 SetUserVar), which the
# format-tab-title handler in ~/.config/wezterm/wezterm.lua draws as a colored
# dot. With "bell" it also rings BEL, which turns an inactive tab orange.
#
# Hooks cannot just print the sequence: Claude Code captures hook stdout, and
# hooks run without a controlling terminal, so /dev/tty fails too. Walk up the
# process tree to the claude process and write to its terminal device instead.
state="${1:?state}"
bell="${2:-}"

cat >/dev/null 2>&1 # drain the hook JSON on stdin

tty=
pid=$PPID
while [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
  t=$(readlink "/proc/$pid/fd/0" 2>/dev/null)
  case "$t" in
    /dev/pts/*) tty=$t; break ;;
  esac
  pid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null)
done
[ -n "$tty" ] && [ -w "$tty" ] || exit 0

{
  printf '\033]1337;SetUserVar=claude_state=%s\007' "$(printf %s "$state" | base64)"
  [ "$bell" = bell ] && printf '\007'
} >>"$tty"
exit 0
