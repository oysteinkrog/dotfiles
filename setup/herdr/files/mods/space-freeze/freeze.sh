#!/usr/bin/env bash
# freeze.sh: Freeze and Thaw for one herdr-app space, on the machine that owns the space.
# The space-freeze mod runs it there (exec with `on`); it also works by hand.
#
#   freeze.sh plan SPACE           JSON: what runs in each terminal of SPACE and how it would resume
#   freeze.sh freeze SPACE [NAME]  stop those programs (shells and tabs stay) and save how to resume them
#   freeze.sh thaw SPACE           start them again in the same terminals, then drop the saved state
#   freeze.sh list                 JSON: the frozen spaces on this machine
#
# SPACE is the space id as this machine's core knows it (no "home/" prefix).
#
# "Freeze" here means the programs EXIT and are resumed later (Claude with --resume). It is not
# the cgroup freeze of freeze-job.sh, where a process stays in memory, stopped.
#
# State: ~/.local/state/space-freeze/<SPACE>.json, one file per frozen space. It survives reboots
# and core restarts; only `thaw` removes it. Nothing here freezes or thaws on its own.
# freeze refuses while an agent in the space is working or blocked.
set -uo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/space-freeze"
PERSIST_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-persist/sessions"
PERSIST_SH="$HOME/.claude/hooks/claude-persist.sh"
CLAUDE_SESSIONS="$HOME/.claude/sessions"
# Typed from a terminal, hc tags a send as a message from that terminal; these are typed by the person.
unset HC_TERMINAL_ID HC_TERMINAL_SOCKET
HC=$(command -v hc || echo "$HOME/.local/bin/hc")

die() { jq -cn --arg e "$*" '{error:$e}'; exit 1; }
SHELLS=" fish bash zsh sh dash nu login "

# Every descendant of a pid, oldest first.
descendants() {
  local p
  for p in $(pgrep -P "$1"); do echo "$p"; descendants "$p"; done
}

# The Claude process under a terminal's foreground program, if any.
claude_pid() {
  local p
  for p in "$1" $(descendants "$1"); do
    [ -f "$CLAUDE_SESSIONS/$p.json" ] && { echo "$p"; return 0; }
    [ "$(cat "/proc/$p/comm" 2>/dev/null)" = claude ] && { echo "$p"; return 0; }
  done
  return 1
}

# One terminal (hc get JSON on stdin is not used: pass the address) as a plan entry.
describe() {
  local addr=$1 g fgpid tpid fgname kind="program" sid="" resume="" entry="" cpid cwd status app argv
  g=$("$HC" get "$addr" --json 2>/dev/null) || return 0
  [ "$(jq -r .state <<<"$g")" = live ] || return 0
  fgpid=$(jq -r '.foreground.pid // empty' <<<"$g"); tpid=$(jq -r '.pid // empty' <<<"$g")
  fgname=$(jq -r '.foreground.name // empty' <<<"$g")
  status=$(jq -r '.status.state // empty' <<<"$g"); app=$(jq -r '.status.app // empty' <<<"$g")
  cwd=$(jq -r '.foreground.cwd // .cwd // empty' <<<"$g")
  argv=$(jq -c '.foreground.argv // []' <<<"$g")
  # herdr-app starts programs as `fish -ic 'command X; exec fish -i'`: then the foreground is that
  # shell and the program is its child. A shell with no child runs nothing: it stays as it is.
  if [ -n "$fgpid" ] && [ "$fgpid" = "$tpid" ] && [[ "$SHELLS" == *" ${fgname#-} "* ]]; then
    fgpid=$(pgrep -P "$tpid" | head -1)
    [ -n "$fgpid" ] && { argv=$(tr '\0' '\n' < "/proc/$fgpid/cmdline" | jq -R . | jq -sc 'map(select(. != ""))'); cwd=$(readlink "/proc/$fgpid/cwd"); }
  fi
  if [ -z "$fgpid" ]; then
    jq -cn --argjson g "$g" '{address:$g.address, name:$g.name, kind:"shell", status:($g.status.state // null),
      tab:($g.labels["herdr.tab"] // null), cwd:($g.cwd // null)}'
    return 0
  fi
  if cpid=$(claude_pid "$fgpid"); then
    kind=claude
    sid=$(jq -r '.sessionId // empty' "$CLAUDE_SESSIONS/$cpid.json" 2>/dev/null)
    cwd=$(jq -r '.cwd // empty' "$CLAUDE_SESSIONS/$cpid.json" 2>/dev/null || true); [ -n "$cwd" ] || cwd=$(readlink "/proc/$cpid/cwd")
    # claude-persist's entry knows the launcher (aiolos-rc and its routing) and the flags to keep.
    for f in "$PERSIST_DIR/$sid"@*.json; do
      [ -e "$f" ] && [ -n "$sid" ] || continue
      entry=$f
      [ "$(jq -r '.pid // 0' "$f")" = "$cpid" ] && break
    done
    if [ -n "$entry" ] && [ -f "$PERSIST_SH" ]; then
      # Without the resume prompt: a frozen session was idle, it waits for the person.
      resume=$(jq '.status = "idle"' "$entry" > "$STATE/.entry.$$" && bash "$PERSIST_SH" resume-cmd "$STATE/.entry.$$" 2>/dev/null)
      rm -f "$STATE/.entry.$$"
    fi
    [ -n "$resume" ] || { [ -n "$sid" ] && resume="cd $(printf %q "$cwd") && claude --resume $(printf %q "$sid")"; }
  elif [ "$app" = codex ] || [ "$(basename "$(jq -r '.[0] // ""' <<<"$argv")")" = codex ]; then
    kind=codex
    resume="cd $(printf %q "$cwd") && codex resume --last"
  fi
  if [ -z "$resume" ]; then
    resume="cd $(printf %q "$cwd") &&"
    while IFS= read -r a; do resume+=" $(printf %q "$a")"; done < <(jq -r '.[]' <<<"$argv")
  fi
  jq -cn --argjson g "$g" --arg kind "$kind" --arg sid "$sid" --arg resume "$resume" --arg cwd "$cwd" \
    --argjson argv "$argv" --arg cpid "${cpid:-}" --arg pid "$fgpid" '{address:$g.address, name:$g.name, kind:$kind,
      status:($g.status.state // null), tab:($g.labels["herdr.tab"] // null), cwd:$cwd, argv:$argv,
      session:(if $sid == "" then null else $sid end), resume:$resume, pid:($pid|tonumber),
      claude_pid:(if $cpid == "" then null else ($cpid|tonumber) end)}'
}

plan() {
  local space=$1 addrs a
  mkdir -p "$STATE"
  addrs=$("$HC" ls --json --label "herdr.space=$space" 2>/dev/null | jq -r '.terminals[].address') || die "hc ls failed"
  for a in $addrs; do describe "$a"; done | jq -s --arg s "$space" '{space:$s, terminals:.}'
}

# The foreground is back to the terminal's own shell, and that shell runs nothing.
idle_shell() {
  local g tpid; g=$("$HC" get "$1" --json 2>/dev/null) || return 0
  [ "$(jq -r .state <<<"$g")" = live ] || return 0
  tpid=$(jq -r '.pid // 1' <<<"$g")
  [ "$(jq -r '.foreground.pid // 0' <<<"$g")" = "$tpid" ] && [ -z "$(pgrep -P "$tpid")" ]
}

# Signal a process and everything under it, children first (never its process group: in a
# herdr-app terminal that group holds the terminal's own shell too).
signal_tree() {
  local sig=$1 p; shift
  for p in $(descendants "$1" | tac) "$1"; do kill "-$sig" "$p" 2>/dev/null; done
}

wait_idle() {
  local i
  for ((i = 0; i < $2 * 5; i++)); do idle_shell "$1" && return 0; sleep 0.2; done
  return 1
}

# Stop one program and leave its shell. Claude gets SIGTERM, which it handles like /exit
# (SessionEnd hooks run); typing /exit could land on a draft the person left in its input.
stop_one() {
  local e=$1 addr pid cpid sid
  addr=$(jq -r .address <<<"$e"); pid=$(jq -r '.pid // empty' <<<"$e"); cpid=$(jq -r '.claude_pid // empty' <<<"$e")
  sid=$(jq -r '.session // empty' <<<"$e")
  [ -n "$pid" ] || return 0
  if [ -n "$cpid" ]; then kill -TERM "$cpid" 2>/dev/null; else kill -TERM "$pid" 2>/dev/null; fi
  wait_idle "$addr" 15 || { signal_tree TERM "$pid"; wait_idle "$addr" 5; } \
    || { signal_tree KILL "$pid"; wait_idle "$addr" 3; } || return 1
  # claude-persist must not bring a frozen session back after a reboot.
  if [ -n "$sid" ]; then
    for f in "$PERSIST_DIR/$sid"@*.json; do [ -e "$f" ] && rm -f "$f"; done
  fi
  return 0
}

freeze() {
  local space=$1 name=${2:-} p busy e out=() failed=()
  [ -f "$STATE/$space.json" ] && die "this space is already frozen"
  p=$(plan "$space") || exit 1
  busy=$(jq -r '[.terminals[] | select(.kind != "shell" and (.status == "working" or .status == "blocked")) | "\(.name // .address) (\(.status))"] | join(", ")' <<<"$p")
  [ -z "$busy" ] || die "not frozen: still busy: $busy"
  [ "$(jq '[.terminals[] | select(.kind != "shell")] | length' <<<"$p")" -gt 0 ] || die "nothing runs in this space"
  while IFS= read -r e; do
    if stop_one "$e"; then
      "$HC" label "$(jq -r .address <<<"$e")" "herdr.frozen=$(jq -r .kind <<<"$e")" >/dev/null 2>&1
      out+=("$e")
    else
      failed+=("$(jq -r '.name // .address' <<<"$e")")
    fi
  done < <(jq -c '.terminals[] | select(.kind != "shell")' <<<"$p")
  if [ ${#out[@]} -gt 0 ]; then
    printf '%s\n' "${out[@]}" | jq -s --arg s "$space" --arg n "$name" --arg at "$(date -Is)" \
      '{space:$s, name:$n, frozen_at:$at, terminals:[.[] | del(.pid, .claude_pid, .status)]}' > "$STATE/$space.json.tmp" \
      && mv "$STATE/$space.json.tmp" "$STATE/$space.json"
  fi
  jq -cn --argjson n "${#out[@]}" --arg f "${failed[*]:-}" '{frozen:$n, failed:($f | split(" ") | map(select(. != "")))}'
}

# Start one saved program again: in its terminal when that is still an idle shell of this space,
# else in a new shell in the same tab.
# THAW_ADDR is the terminal it used, so a program that stays frozen is saved with its new address.
thaw_one() {
  local space=$1 e=$2 name tab cwd resume g target="" kind
  THAW_ADDR=""
  kind=$(jq -r '.kind // "program"' <<<"$e")
  name=$(jq -r .name <<<"$e"); tab=$(jq -r '.tab // empty' <<<"$e"); cwd=$(jq -r '.cwd // empty' <<<"$e")
  resume=$(jq -r .resume <<<"$e")
  # By name (herdr-app terminals have none), else by address: hc keeps both across a core restart.
  local key=$name; [ "$key" = null ] || [ -z "$key" ] && key=$(jq -r .address <<<"$e")
  if g=$("$HC" get "$key" --json 2>/dev/null) && [ "$(jq -r .state <<<"$g")" = live ] \
    && [ "$(jq -r '.labels["herdr.space"] // empty' <<<"$g")" = "$space" ]; then
    idle_shell "$key" || return 1   # someone runs something there now: leave it
    target=$(jq -r .address <<<"$g")
  else
    local -a lbl=(--label "herdr.space=$space"); [ -n "$tab" ] && lbl+=(--label "herdr.tab=$tab")
    [ "$name" = null ] && name=""
    [ -n "$name" ] && target=$("$HC" run --json --bg --keep --no-parent --name "$name" --cwd "${cwd:-$HOME}" "${lbl[@]}" 2>/dev/null | jq -r '.address // empty')
    [ -n "${target:-}" ] || target=$("$HC" run --json --bg --keep --no-parent --cwd "${cwd:-$HOME}" "${lbl[@]}" 2>/dev/null | jq -r '.address // empty')
    [ -n "$target" ] || return 1
    # The new shell belongs to the frozen space until the program runs in it.
    "$HC" label "$target" "herdr.frozen=$kind" >/dev/null 2>&1
    THAW_ADDR=$target
    sleep 1
  fi
  # The label goes before this returns, so every window shows the space thawed at once.
  "$HC" label "$target" "herdr.frozen=" >/dev/null 2>&1
  if ! "$HC" send "$target" "$resume" >/dev/null 2>&1; then
    "$HC" label "$target" "herdr.frozen=$kind" >/dev/null 2>&1
    THAW_ADDR=$target
    return 1
  fi
}

thaw() {
  local space=$1 f="$STATE/$1.json" e left=() n=0
  [ -f "$f" ] || die "this space is not frozen"
  while IFS= read -r e; do
    if thaw_one "$space" "$e"; then n=$((n + 1))
    elif [ -n "$THAW_ADDR" ]; then left+=("$(jq -c --arg a "$THAW_ADDR" '.address = $a' <<<"$e")")
    else left+=("$e"); fi
  done < <(jq -c '.terminals[]' "$f")
  if [ ${#left[@]} -eq 0 ]; then
    # Nothing here is frozen now: no terminal of the space may keep the label.
    local t
    for t in $("$HC" ls --json --label "herdr.space=$space" 2>/dev/null | jq -r '.terminals[].address'); do
      [ -n "$("$HC" get "$t" --json 2>/dev/null | jq -r '.labels["herdr.frozen"] // empty')" ] && "$HC" label "$t" "herdr.frozen=" >/dev/null 2>&1
    done
    mv "$f" "$STATE/.thawed-$1-$(date +%Y%m%d-%H%M%S).json"
  else
    printf '%s\n' "${left[@]}" | jq -s --slurpfile old "$f" '$old[0] + {terminals:.}' > "$f.tmp" && mv "$f.tmp" "$f"
  fi
  jq -cn --argjson n "$n" --argjson l "${#left[@]}" '{thawed:$n, left:$l}'
}

list() {
  mkdir -p "$STATE"
  local f
  for f in "$STATE"/*.json; do
    [ -e "$f" ] || continue
    jq -c '{space, name, frozen_at, count:(.terminals | length), addresses:[.terminals[].address]}' "$f"
  done | jq -s .
}

case "${1:-}" in
  plan) plan "${2:?space id}" ;;
  freeze) mkdir -p "$STATE"; freeze "${2:?space id}" "${3:-}" ;;
  thaw) thaw "${2:?space id}" ;;
  list) list ;;
  *) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
