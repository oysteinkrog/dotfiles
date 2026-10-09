#!/bin/bash
# Send each live Claude session's tab state (the claude_state user var) to its
# terminal again. wezterm.lua runs this from gui-attached.
#
# Why: the mux server keeps every pane's user vars, but a GUI client starts
# with none and only learns a var from a later SetUserVar alert. After a GUI
# restart every Claude tab lost its colored dot until that session's next hook
# ran, which for an idle tab can take hours. Writing the escape sequence to the
# pane's tty again makes the mux send the alert to the new client.
#
# The state comes from what term-state.sh saved for that terminal, when it was
# saved by the Claude running there now. Otherwise it is mapped from the
# session's status: busy or shell -> working, waiting -> input, idle -> complete.

dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/claude-tab-state"
sessions="$HOME/.claude/sessions"
clk=$(getconf CLK_TCK)
boot=$(awk '/^btime/{print $2}' /proc/stat)

# give the GUI time to subscribe to its panes
sleep "${1:-2}"

for f in "$sessions"/*.json; do
  [ -e "$f" ] || continue
  pid=$(basename "$f" .json)
  [ -d "/proc/$pid" ] || continue
  [ "$(jq -r '.kind // empty' "$f" 2>/dev/null)" = interactive ] || continue
  tty=$(readlink "/proc/$pid/fd/0" 2>/dev/null)
  case "$tty" in /dev/pts/*) ;; *) continue ;; esac
  [ -w "$tty" ] || continue

  # when this Claude started, in seconds since the epoch
  started=$(( boot + $(awk '{print $22}' "/proc/$pid/stat") / clk ))
  state=""
  saved="$dir/${tty#/dev/pts/}"
  if [ -f "$saved" ] && [ "$(stat -c %Y "$saved")" -ge "$started" ]; then
    state=$(cat "$saved")
  else
    case "$(jq -r '.status // empty' "$f" 2>/dev/null)" in
      busy|shell) state=working ;;
      waiting) state=input ;;
      idle) state=complete ;;
    esac
  fi
  [ -n "$state" ] || continue
  # TERM_STATE_DRY=1 prints what it would send instead
  if [ -n "${TERM_STATE_DRY:-}" ]; then echo "$tty pid $pid: $state"; continue; fi
  printf '\033]1337;SetUserVar=claude_state=%s\007' "$(printf %s "$state" | base64)" >>"$tty"
done
exit 0
