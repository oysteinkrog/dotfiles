#!/bin/bash
# Keep each Claude Code tab's state in step with Claude Code's own session
# status. wezterm.lua draws the claude_state user var as the tab's dot.
#
# Claude Code keeps ~/.claude/sessions/<pid>.json with a status:
#   busy, shell  working                                   -> working (blue dot)
#   waiting      blocked on you: AskUserQuestion or a
#                permission prompt                          -> input ("?", tinted tab)
#   idle         finished, at the prompt                   -> complete (green dot)
# Hooks used to guess this and got it wrong: the "waiting for your input"
# notice 60 s after every turn looked like a question, and a cancelled question
# never cleared. A session that starts waiting also rings the bell, which is
# what Alt+M jumps to.
#
# Runs as claude-tab-watch.service. Polls once a second with one grep over the
# small session files; a status change reaches the tab within a second.

sessions="$HOME/.claude/sessions"
dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/claude-tab-state"
mkdir -p "$dir"
declare -A last

while :; do
  declare -A kind=() status=()
  while IFS=: read -r f kv; do
    case "$kv" in
      '"kind":'*) kind[$f]=${kv#'"kind":"'} kind[$f]=${kind[$f]%'"'} ;;
      '"status":'*) status[$f]=${kv#'"status":"'} status[$f]=${status[$f]%'"'} ;;
    esac
  done < <(grep -o -E '"(kind|status)":"[a-z]*"' "$sessions"/*.json 2>/dev/null)

  for f in "${!status[@]}"; do
    [ "${kind[$f]}" = interactive ] || continue
    s=${status[$f]}
    [ "${last[$f]}" = "$s" ] && continue
    pid=$(basename "$f" .json)
    tty=$(readlink "/proc/$pid/fd/0" 2>/dev/null)
    case "$tty" in /dev/pts/*) ;; *) continue ;; esac
    [ -w "$tty" ] || continue
    case "$s" in
      waiting) state=input ;;
      idle) state=complete ;;
      *) state=working ;;
    esac
    {
      printf '\033]1337;SetUserVar=claude_state=%s\007' "$(printf %s "$state" | base64)"
      [ "$state" = input ] && printf '\007'
    } >>"$tty"
    # term-state-replay.sh sends this again when a GUI attaches later
    printf '%s\n' "$state" >"$dir/${tty#/dev/pts/}"
    last[$f]=$s
  done
  sleep 1
done
