#!/usr/bin/env bash
# claude-persist: keep a list of open interactive Claude Code sessions and
# resume them in the wezterm mux after a reboot.
#
#   claude-persist.sh hook-start   SessionStart hook (JSON on stdin)
#   claude-persist.sh hook-end     SessionEnd hook (JSON on stdin)
#   claude-persist.sh plan         print sessions to resume (cwd, title, command)
#   claude-persist.sh restore      resume every recorded session in wezterm
#   claude-persist.sh list         show recorded sessions
#   claude-persist.sh forget ID    drop one session from the list
#
# State: ~/.local/state/claude-persist/sessions/<session_id>.json
# Set CLAUDE_PERSIST=0 in a session's environment to keep it off the list.

set -u

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-persist"
SESS_DIR="$STATE_DIR/sessions"
MUX_UNIT="wezterm-mux.service"
WEZTERM="$HOME/.local/bin/wezterm"
# full path: at boot the mux server may not have ~/.local/bin on PATH
CLAUDE_BIN="${CLAUDE_PERSIST_BIN:-$(command -v claude || echo "$HOME/.local/bin/claude")}"

# Walk up from the hook process to the claude process that ran it.
find_claude_pid() {
  local p=$PPID
  while [ -n "$p" ] && [ "$p" -gt 1 ]; do
    [ "$(cat "/proc/$p/comm" 2>/dev/null)" = "claude" ] && { echo "$p"; return 0; }
    p=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)
  done
  return 1
}

# Print the launch flags worth keeping on resume, one per line.
# Session-picking flags (--resume, --continue, --session-id), headless
# flags and the initial prompt are dropped.
keep_flags() {
  local -a argv
  mapfile -d '' -t argv < "/proc/$1/cmdline"
  local i=1 a
  while [ $i -lt ${#argv[@]} ]; do
    a=${argv[$i]}
    case "$a" in
      --dangerously-skip-permissions|--allow-dangerously-skip-permissions|--verbose|--ide|--chrome|--no-chrome)
        printf '%s\n' "$a" ;;
      --model|--permission-mode|--add-dir|--agent|--settings|--mcp-config|--effort|--fallback-model|--append-system-prompt|--allowedTools|--allowed-tools|--disallowedTools|--disallowed-tools|--plugin-dir)
        printf '%s\n' "$a"
        i=$((i + 1)); [ $i -lt ${#argv[@]} ] && printf '%s\n' "${argv[$i]}" ;;
      --model=*|--permission-mode=*|--add-dir=*|--agent=*|--settings=*|--mcp-config=*|--effort=*|--fallback-model=*)
        printf '%s\n' "$a" ;;
      -r|--resume|--session-id)
        # optional value: skip it unless it is another flag
        if [ $((i + 1)) -lt ${#argv[@]} ] && [ "${argv[$((i + 1))]#-}" = "${argv[$((i + 1))]}" ]; then i=$((i + 1)); fi ;;
    esac
    i=$((i + 1))
  done
}

is_headless() {
  tr '\0' '\n' < "/proc/$1/cmdline" | grep -qxE -- '-p|--print|--output-format(=.*)?|--sdk-url(=.*)?'
}

hook_start() {
  local input sid cwd transcript pid flags
  input=$(cat)
  [ "${CLAUDE_PERSIST:-1}" = "0" ] && return 0
  sid=$(jq -r '.session_id // empty' <<<"$input")
  cwd=$(jq -r '.cwd // empty' <<<"$input")
  transcript=$(jq -r '.transcript_path // empty' <<<"$input")
  [ -n "$sid" ] && [ -n "$cwd" ] || return 0
  pid=$(find_claude_pid) || return 0
  is_headless "$pid" && return 0

  mkdir -p "$SESS_DIR"
  flags=$(keep_flags "$pid" | jq -R . | jq -s .)
  jq -n --arg sid "$sid" --arg cwd "$cwd" --arg transcript "$transcript" \
        --argjson pid "$pid" --argjson flags "$flags" \
        --arg started "$(date -Is)" --arg pane "${WEZTERM_PANE:-}" \
        '{session_id:$sid, cwd:$cwd, transcript:$transcript, pid:$pid,
          flags:$flags, started:$started, wezterm_pane:$pane}' \
    > "$SESS_DIR/$sid.json.tmp" && mv "$SESS_DIR/$sid.json.tmp" "$SESS_DIR/$sid.json"
}

hook_end() {
  local input sid reason
  input=$(cat)
  sid=$(jq -r '.session_id // empty' <<<"$input")
  reason=$(jq -r '.reason // empty' <<<"$input")
  [ -n "$sid" ] && [ -f "$SESS_DIR/$sid.json" ] || return 0
  # Keep the entry when the session dies because the machine or the mux is going down.
  [ "$(systemctl is-system-running 2>/dev/null)" = "stopping" ] && return 0
  if [ -n "${WEZTERM_PANE:-}" ]; then
    case "$(systemctl --user is-active "$MUX_UNIT" 2>/dev/null)" in
      deactivating|inactive|failed) return 0 ;;
    esac
  fi
  rm -f "$SESS_DIR/$sid.json"
  echo "$(date -Is) ended $sid reason=$reason" >> "$STATE_DIR/events.log"
}

wait_for_mux() {
  local n=0
  until "$WEZTERM" cli --prefer-mux list >/dev/null 2>&1; do
    n=$((n + 1)); [ $n -ge 60 ] && return 1
    sleep 1
  done
}

# Print one line per session to resume: <cwd> TAB <tab title> TAB <bash command>.
# The command cds into <cwd> itself, because some spawn APIs ignore the cwd
# they are given when a command is set (Frankenterm's Lua spawn_tab does).
# Entries are moved to restored/ as they are handed out; the resumed session's
# SessionStart hook writes a fresh entry. Log lines go to restore.log.
plan() {
  mkdir -p "$SESS_DIR" "$STATE_DIR/restored"
  local log="$STATE_DIR/restore.log" f sid cwd transcript pid cmd
  echo "=== plan $(date -Is)" >> "$log"
  # oldest first, so tab order matches start order
  while IFS= read -r f; do
    sid=$(jq -r .session_id "$f"); cwd=$(jq -r .cwd "$f")
    transcript=$(jq -r '.transcript // empty' "$f"); pid=$(jq -r '.pid // 0' "$f")
    if [ "$pid" -gt 0 ] && [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = "claude" ]; then
      echo "skip $sid: still running as pid $pid" >> "$log"; continue
    fi
    if [ -n "$transcript" ] && [ ! -s "$transcript" ]; then
      echo "drop $sid: no transcript (session never had a message)" >> "$log"
      mv "$f" "$STATE_DIR/restored/"; continue
    fi
    if [ ! -d "$cwd" ]; then
      echo "drop $sid: folder $cwd is gone" >> "$log"; mv "$f" "$STATE_DIR/restored/"; continue
    fi

    cmd="cd $(printf '%q' "$cwd") && $(printf '%q' "$CLAUDE_BIN") --resume $(printf '%q' "$sid")"
    while IFS= read -r a; do cmd+=" $(printf '%q' "$a")"; done < <(jq -r '.flags[]' "$f")
    mv "$f" "$STATE_DIR/restored/"
    echo "resume $sid ($cwd): $cmd" >> "$log"
    printf '%s\t%s\t%s\n' "$cwd" "$(basename "$cwd")" "$cmd"
  done < <(ls -1tr "$SESS_DIR"/*.json 2>/dev/null)
}

# Resume sessions into an already running wezterm mux with `wezterm cli`.
# (The mux-startup handler in wezterm.lua uses `plan` directly instead.)
restore() {
  exec >> "$STATE_DIR/restore.log" 2>&1
  wait_for_mux || { echo "mux not reachable, giving up"; return 1; }
  local cwd title cmd pane window_id
  window_id=$("$WEZTERM" cli --prefer-mux list --format json | jq -r '.[0].window_id // empty')
  while IFS=$'\t' read -r cwd title cmd; do
    # run claude, then keep a shell open in the tab when it exits
    if [ -n "$window_id" ]; then
      pane=$("$WEZTERM" cli --prefer-mux spawn --window-id "$window_id" --cwd "$cwd" -- bash -c "$cmd; exec fish -l")
    else
      pane=$("$WEZTERM" cli --prefer-mux spawn --new-window --cwd "$cwd" -- bash -c "$cmd; exec fish -l")
      window_id=$("$WEZTERM" cli --prefer-mux list --format json | jq -r --argjson p "$pane" '.[] | select(.pane_id==$p) | .window_id')
    fi
    "$WEZTERM" cli --prefer-mux set-tab-title --pane-id "$pane" "$title" >/dev/null 2>&1
    echo "spawned pane $pane for $cwd"
  done < <(plan)
}

list() {
  local f found=""
  for f in "$SESS_DIR"/*.json; do
    [ -e "$f" ] || continue
    found=1
    jq -r '"\(.session_id)  \(.started)  pid=\(.pid)  \(.cwd)  \(.flags|join(" "))"' "$f"
  done
  [ -n "$found" ] || echo "no recorded sessions"
}

case "${1:-}" in
  hook-start) [ -d /run/systemd/system ] && hook_start ;;
  hook-end)   [ -d /run/systemd/system ] && hook_end ;;
  plan)       plan ;;
  restore)    restore ;;
  list)       list ;;
  forget)     rm -v "$SESS_DIR/${2:?session id}.json" ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
exit 0
