#!/usr/bin/env bash
# claude-persist: keep a list of open interactive Claude Code sessions and
# resume them in the terminal mux server (wezterm or Frankenterm) after a reboot.
#
#   claude-persist.sh hook-start      SessionStart hook (JSON on stdin)
#   claude-persist.sh hook-end        SessionEnd hook (JSON on stdin)
#   claude-persist.sh capture [UNIT]  record the sessions running right now,
#                                     optionally only those inside a systemd
#                                     user unit (e.g. wezterm-mux.service)
#   claude-persist.sh snapshot        save the mux server's tab order (systemd
#                                     timer and ExecStop run this)
#   claude-persist.sh plan            print sessions to resume (cwd, title, command)
#   claude-persist.sh restore         resume every recorded session with `wezterm cli`
#   claude-persist.sh list            show recorded sessions
#   claude-persist.sh forget KEY      drop one entry (file name without .json)
#
# State: ~/.local/state/claude-persist/sessions/<session_id>@<folder>.json,
# and tab-order (the last saved tab order of the mux server).
# The key includes the folder because one session id can be open in two
# folders (sessions copied between projects keep their id).
# Set CLAUDE_PERSIST=0 in a session's environment to keep it off the list.
# Only sessions a person started in a terminal are kept: Agent SDK sessions
# (entrypoint sdk-cli, e.g. the smart-translation tool) are skipped. On
# 2026-10-07 about 1000 of those were on the list and a reboot resumed 209.
# plan resumes at most CLAUDE_PERSIST_MAX sessions (default 40).

set -u

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-persist"
SESS_DIR="$STATE_DIR/sessions"
CLAUDE_SESSIONS="$HOME/.claude/sessions"   # Claude writes <pid>.json here per process
WEZTERM="$HOME/.local/bin/wezterm"
FT_CLI="$HOME/.local/bin/frankenterm-gui"
MUX_UNIT=frankenterm-mux.service
TAB_ORDER="$STATE_DIR/tab-order"
AIOLOS_RC="$HOME/.config/aiolos-rc/aiolos-rc"
# full path: at boot the mux server may not have ~/.local/bin on PATH
CLAUDE_BIN="${CLAUDE_PERSIST_BIN:-$(command -v claude || echo "$HOME/.local/bin/claude")}"

# Claude's project folder name for a cwd: every non-alphanumeric char becomes '-'.
project_slug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

entry_file() { printf '%s/%s@%s.json' "$SESS_DIR" "$1" "$(project_slug "$2")"; }

parent_of() { awk '{print $4}' "/proc/$1/stat" 2>/dev/null; }

# Walk up from the hook process to the Claude process that ran it. The process
# name is not reliable (it is the version number, or ld-linux), so look for
# the per-process file Claude keeps in ~/.claude/sessions.
find_claude_pid() {
  local p=$PPID
  while [ -n "$p" ] && [ "$p" -gt 1 ]; do
    [ -f "$CLAUDE_SESSIONS/$p.json" ] && { echo "$p"; return 0; }
    p=$(parent_of "$p")
  done
  return 1
}

# Was this Claude process started by a person in a terminal? Agent SDK runs
# (entrypoint sdk-cli or sdk-*) also report kind=interactive, but they belong
# to the program that drove them and must never get their own tab back.
started_in_terminal() {
  local e; e=$(jq -r '.entrypoint // empty' "$CLAUDE_SESSIONS/$1.json" 2>/dev/null)
  [ -z "$e" ] || [ "$e" = cli ]
}

# The entrypoint of the first message in a transcript (cli, sdk-cli, ...).
transcript_entrypoint() {
  grep -a -m1 -o '"entrypoint":"[^"]*"' "$1" 2>/dev/null | cut -d'"' -f4
}

# Is this pid a live Claude process for the given session id?
claude_alive() {
  local pid=$1 sid=$2
  [ "$pid" -gt 0 ] && [ -d "/proc/$pid" ] && [ -f "$CLAUDE_SESSIONS/$pid.json" ] \
    && [ "$(jq -r '.sessionId // empty' "$CLAUDE_SESSIONS/$pid.json" 2>/dev/null)" = "$sid" ]
}

# The systemd user unit a process runs in, e.g. frankenterm-mux.service, or
# nothing for a process in a scope (claude.slice/claude-<pid>.scope). Look only
# below user@<uid>.service: that segment is the user manager itself, and
# `systemctl --user is-active user@1000.service` says inactive, which made
# hook_end keep every entry from 2026-10-03 on.
unit_of() {
  local cg; cg=$(sed -n 's#^0::##p' "/proc/$1/cgroup" 2>/dev/null)
  cg=${cg#*/user@*.service/}
  [[ "/$cg" =~ /([^/]+\.service)(/|$) ]] && printf '%s\n' "${BASH_REMATCH[1]}"
}

# Print the Claude flags worth keeping on resume, one per line. Dropped:
# session picking (--resume, --continue, --session-id), headless flags, the
# initial prompt, and what the aiolos-rc wrapper adds by itself on every start
# (its temporary --settings file and --dangerously-skip-permissions).
keep_flags() {
  local pid=$1 via_wrapper=$2
  local -a argv
  mapfile -d '' -t argv < "/proc/$pid/cmdline"
  local i=1 a v
  while [ $i -lt ${#argv[@]} ]; do
    a=${argv[$i]}
    case "$a" in
      --dangerously-skip-permissions)
        [ "$via_wrapper" = 1 ] || printf '%s\n' "$a" ;;
      --allow-dangerously-skip-permissions|--verbose|--ide|--chrome|--no-chrome)
        printf '%s\n' "$a" ;;
      --settings)
        i=$((i + 1)); v=${argv[$i]:-}
        case "$v" in */aiolos-rc-settings.*) ;; *) printf '%s\n%s\n' "$a" "$v" ;; esac ;;
      --model|--permission-mode|--add-dir|--agent|--mcp-config|--effort|--fallback-model|--append-system-prompt|--allowedTools|--allowed-tools|--disallowedTools|--disallowed-tools|--plugin-dir)
        printf '%s\n' "$a"
        i=$((i + 1)); [ $i -lt ${#argv[@]} ] && printf '%s\n' "${argv[$i]}" ;;
      --model=*|--permission-mode=*|--add-dir=*|--agent=*|--mcp-config=*|--effort=*|--fallback-model=*)
        printf '%s\n' "$a" ;;
      -r|--resume|--session-id)
        # optional value: skip it unless it is another flag
        if [ $((i + 1)) -lt ${#argv[@]} ] && [ "${argv[$((i + 1))]#-}" = "${argv[$((i + 1))]}" ]; then i=$((i + 1)); fi ;;
    esac
    i=$((i + 1))
  done
}

# If Claude was started by the aiolos-rc wrapper, print the wrapper's routing
# options (--no-pin, or --account X), one per line, and return 0.
wrapper_mode() {
  local pp; pp=$(parent_of "$1")
  local -a argv
  mapfile -d '' -t argv < "/proc/$pp/cmdline" 2>/dev/null || return 1
  local i found=0
  for ((i = 0; i < ${#argv[@]}; i++)); do
    [ "$found" = 0 ] && { [[ "${argv[$i]}" == */aiolos-rc ]] && found=1; continue; }
    case "${argv[$i]}" in
      --no-pin) printf '%s\n' --no-pin ;;
      --account) printf '%s\n%s\n' --account "${argv[$((i + 1))]:-}"; i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [ "$found" = 1 ]
}

# Write the entry for one live Claude process.
record() {
  local pid=$1 sid=$2 cwd=$3 name=${4:-}
  local via=0 launcher='[]' flags transcript pane
  if wrapper_mode "$pid" >/dev/null; then
    via=1
    launcher=$( { printf '%s\n' "$AIOLOS_RC"; wrapper_mode "$pid"; } | jq -R . | jq -s .)
  fi
  flags=$(keep_flags "$pid" "$via" | jq -R . | jq -s .)
  transcript="$HOME/.claude/projects/$(project_slug "$cwd")/$sid.jsonl"
  # the mux pane the session runs in, to put its tab back in the same place
  pane=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^WEZTERM_PANE=//p' | head -1)
  mkdir -p "$SESS_DIR"
  local f; f=$(entry_file "$sid" "$cwd")
  jq -n --arg sid "$sid" --arg cwd "$cwd" --arg transcript "$transcript" --arg name "$name" \
        --argjson pid "$pid" --argjson flags "$flags" --argjson launcher "$launcher" \
        --arg started "$(date -Is)" --arg pane "$pane" \
        '{session_id:$sid, cwd:$cwd, name:$name, transcript:$transcript, pid:$pid,
          pane:(if $pane == "" then null else ($pane | tonumber) end),
          launcher:$launcher, flags:$flags, started:$started}' \
    > "$f.tmp" && mv "$f.tmp" "$f"
}

hook_start() {
  local input sid cwd pid kind name
  input=$(cat)
  [ "${CLAUDE_PERSIST:-1}" = "0" ] && return 0
  sid=$(jq -r '.session_id // empty' <<<"$input")
  cwd=$(jq -r '.cwd // empty' <<<"$input")
  [ -n "$sid" ] && [ -n "$cwd" ] || return 0
  pid=$(find_claude_pid) || return 0
  kind=$(jq -r '.kind // empty' "$CLAUDE_SESSIONS/$pid.json" 2>/dev/null)
  [ "$kind" = "interactive" ] || return 0
  started_in_terminal "$pid" || return 0
  name=$(jq -r '.name // empty' "$CLAUDE_SESSIONS/$pid.json" 2>/dev/null)
  record "$pid" "$sid" "$cwd" "$name"
}

hook_end() {
  local input sid cwd reason f unit
  input=$(cat)
  sid=$(jq -r '.session_id // empty' <<<"$input")
  cwd=$(jq -r '.cwd // empty' <<<"$input")
  reason=$(jq -r '.reason // empty' <<<"$input")
  [ -n "$sid" ] && [ -n "$cwd" ] || return 0
  f=$(entry_file "$sid" "$cwd")
  [ -f "$f" ] || return 0
  # Keep the entry when the session dies because the machine or its mux
  # server is going down; drop it on a normal exit.
  [ "$(systemctl is-system-running 2>/dev/null)" = "stopping" ] && return 0
  # The session also dies when the mux server stops, crashes or is OOM-killed,
  # because its terminal goes away. Sessions started by aiolos-rc run in their
  # own scope (claude-<pid>.scope), so check the mux unit itself; activating
  # covers the wait before systemd restarts it.
  case "$(systemctl --user is-active "$MUX_UNIT" 2>/dev/null)" in
    deactivating|inactive|failed|activating) return 0 ;;
  esac
  # Older sessions run inside the mux unit itself. The hook runs in the same
  # cgroup as its Claude process; use our own pid, because Claude may already
  # have removed ~/.claude/sessions/<pid>.json.
  unit=$(unit_of $$)
  if [ -n "${unit:-}" ]; then
    case "$(systemctl --user is-active "$unit" 2>/dev/null)" in
      deactivating|inactive|failed) return 0 ;;
    esac
  fi
  rm -f "$f"
  echo "$(date -Is) ended $sid ($cwd) reason=$reason" >> "$STATE_DIR/events.log"
}

# Record every live interactive Claude session, or only those inside UNIT.
capture() {
  local want=${1:-} f pid sid cwd kind name n=0
  for f in "$CLAUDE_SESSIONS"/*.json; do
    pid=$(basename "$f" .json)
    [ -d "/proc/$pid" ] || continue
    kind=$(jq -r '.kind // empty' "$f"); [ "$kind" = "interactive" ] || continue
    started_in_terminal "$pid" || continue
    [ -z "$want" ] || [ "$(unit_of "$pid")" = "$want" ] || continue
    sid=$(jq -r '.sessionId // empty' "$f"); cwd=$(jq -r '.cwd // empty' "$f")
    name=$(jq -r '.name // empty' "$f")
    [ -n "$sid" ] && [ -n "$cwd" ] || continue
    record "$pid" "$sid" "$cwd" "$name"
    # plan restores oldest first; date the entry by when the session started
    local started_ms; started_ms=$(jq -r '.startedAt // empty' "$f")
    [ -n "$started_ms" ] && touch -d "@$((started_ms / 1000))" "$(entry_file "$sid" "$cwd")"
    n=$((n + 1)); echo "recorded $sid ${name:+($name) }$cwd"
  done
  echo "$n session(s) recorded"
}

mux_pid() { systemctl --user show -p MainPID --value "$MUX_UNIT" 2>/dev/null; }

# Save the mux server's tab order: a header line with the server's pid, then
# <window id> TAB <pane id> per pane, in tab order. Ask the server's own socket,
# not a GUI's (a GUI numbers panes its own way). Keep the old file when the
# server answers with nothing, so a dying server cannot wipe it.
snapshot() {
  local pid rows
  pid=$(mux_pid); [ -n "$pid" ] && [ "$pid" != 0 ] || return 0
  rows=$(env -u FRANKENTERM_UNIX_SOCKET "$FT_CLI" cli list --json 2>/dev/null \
    | jq -r '.[] | "\(.window_id)\t\(.pane_id)"' 2>/dev/null)
  [ -n "$rows" ] || return 0
  mkdir -p "$STATE_DIR"
  { echo "mux $pid"; printf '%s\n' "$rows"; } > "$TAB_ORDER.tmp" && mv "$TAB_ORDER.tmp" "$TAB_ORDER"

  local f epid pane sf ssid scwd
  local -A row_pane=()
  local w_ p_
  while IFS=$'\t' read -r w_ p_; do row_pane[$p_]=1; done <<<"$rows"

  # Record live terminal sessions in this server that have no entry. Their
  # SessionStart hook can miss: at boot about 40 sessions start at once, and
  # the hook has 10 s. A session missing here would not come back.
  for sf in "$CLAUDE_SESSIONS"/*.json; do
    [ -e "$sf" ] || continue
    epid=$(basename "$sf" .json)
    [ -d "/proc/$epid" ] || continue
    [ "$(jq -r '.kind // empty' "$sf" 2>/dev/null)" = interactive ] || continue
    started_in_terminal "$epid" || continue
    pane=$(tr '\0' '\n' < "/proc/$epid/environ" 2>/dev/null | sed -n 's/^WEZTERM_PANE=//p' | head -1)
    [ -n "$pane" ] && [ -n "${row_pane[$pane]:-}" ] || continue
    tr '\0' '\n' < "/proc/$epid/environ" 2>/dev/null | grep -qx 'CLAUDE_PERSIST=0' && continue
    ssid=$(jq -r '.sessionId // empty' "$sf"); scwd=$(jq -r '.cwd // empty' "$sf")
    [ -n "$ssid" ] && [ -n "$scwd" ] || continue
    [ -f "$(entry_file "$ssid" "$scwd")" ] && continue
    record "$epid" "$ssid" "$scwd" "$(jq -r '.name // empty' "$sf")"
    echo "$(date -Is) recorded $ssid ($scwd) from snapshot: pane $pane had no entry" >> "$STATE_DIR/events.log"
  done

  # Fill in the pane of entries recorded without one (older entries, and
  # sessions Claude keeps no ~/.claude/sessions file for, which capture misses).
  for f in "$SESS_DIR"/*.json; do
    [ -e "$f" ] || continue
    [ "$(jq -r '.pane // empty' "$f")" = "" ] || continue
    epid=$(jq -r '.pid // 0' "$f")
    [ "$epid" -gt 0 ] && [ -r "/proc/$epid/environ" ] || continue
    grep -qaF -- "$(jq -r .session_id "$f")" "/proc/$epid/cmdline" 2>/dev/null \
      || [ -f "$CLAUDE_SESSIONS/$epid.json" ] || continue
    pane=$(tr '\0' '\n' < "/proc/$epid/environ" | sed -n 's/^WEZTERM_PANE=//p' | head -1)
    [ -n "$pane" ] || continue
    jq --argjson pane "$pane" '.pane = $pane' "$f" > "$f.tmp" && touch -r "$f" "$f.tmp" && mv "$f.tmp" "$f"
  done

  # Stamp each live session with this server's pid. plan resumes only the
  # sessions stamped by the server that just went away, which are the ones
  # still open at its last snapshot (at most 30 s before it stopped). An entry
  # whose tab was closed without a SessionEnd hook keeps an old stamp and is
  # dropped instead of coming back.
  for f in "$SESS_DIR"/*.json; do
    [ -e "$f" ] || continue
    epid=$(jq -r '.pid // 0' "$f")
    claude_alive "$epid" "$(jq -r .session_id "$f")" || continue
    [ "$(jq -r '.mux // empty' "$f")" = "$pid" ] && continue
    jq --argjson m "$pid" '.mux = $m' "$f" > "$f.tmp" && touch -r "$f" "$f.tmp" && mv "$f.tmp" "$f"
  done

  # Retire the entries of closed tabs: stamped by this server, Claude no longer
  # running, and the pane gone from this server's list. Closing a tab can kill
  # Claude before its SessionEnd hook runs, and those entries used to come back
  # at the next boot. Pane ids are never reused within one server, and a tab
  # whose Claude exited still has its pane (the fish shell after it).
  mkdir -p "$STATE_DIR/restored"
  for f in "$SESS_DIR"/*.json; do
    [ -e "$f" ] || continue
    [ "$(jq -r '.mux // empty' "$f")" = "$pid" ] || continue
    pane=$(jq -r '.pane // empty' "$f"); [ -n "$pane" ] || continue
    [ -n "${row_pane[$pane]:-}" ] && continue
    claude_alive "$(jq -r '.pid // 0' "$f")" "$(jq -r .session_id "$f")" && continue
    mv "$f" "$STATE_DIR/restored/"
    echo "$(date -Is) closed $(basename "$f" .json): pane $pane is gone from mux $pid" >> "$STATE_DIR/events.log"
  done

  # Save each live session's status (busy, waiting or idle) so the restore
  # knows which sessions were cut off mid-turn. Claude deletes its
  # ~/.claude/sessions/<pid>.json file on exit, so it has to be copied now.
  local status
  for f in "$SESS_DIR"/*.json; do
    [ -e "$f" ] || continue
    epid=$(jq -r '.pid // 0' "$f")
    [ -f "$CLAUDE_SESSIONS/$epid.json" ] || continue
    status=$(jq -r '.status // empty' "$CLAUDE_SESSIONS/$epid.json" 2>/dev/null)
    [ -n "$status" ] || continue
    [ "$(jq -r '.status // empty' "$f")" = "$status" ] && continue
    jq --arg s "$status" '.status = $s' "$f" > "$f.tmp" && touch -r "$f" "$f.tmp" && mv "$f.tmp" "$f"
  done
}

# Print the prompt to start a resumed session with, or nothing. A restart
# loses what lives only in the Claude process: a /goal (a session-scoped Stop
# hook), a /loop's pending ScheduleWakeup, an open question, and the turn that
# was running. Idle sessions get no prompt, so they stay quiet.
resume_prompt() {
  local transcript=$1 status=$2
  python3 "$(dirname "${BASH_SOURCE[0]}")/claude-persist-resume.py" "$transcript" "$status" 2>/dev/null
}

# Print the entry files in the order to resume them: by their pane's place in
# the saved tab order, then the rest oldest first. The saved order is used only
# when it came from an earlier mux server: pane ids start over in a new server,
# so a snapshot of the current one says nothing about the recorded panes.
ordered_entries() {
  local -A pos=()
  local tag spid w p i=0 n=0 f pane
  if [ -f "$TAB_ORDER" ]; then
    read -r tag spid < "$TAB_ORDER"
    if [ "$tag" = mux ] && [ "$spid" != "$(mux_pid)" ]; then
      while IFS=$'\t' read -r w p; do
        [ -n "${pos[$p]:-}" ] || pos[$p]=$i; i=$((i + 1))
      done < <(tail -n +2 "$TAB_ORDER")
    fi
  fi
  while IFS= read -r f; do
    pane=$(jq -r '.pane // empty' "$f")
    printf '%d\t%s\n' "${pos[${pane:-x}]:-$((1000000 + n))}" "$f"
    n=$((n + 1))
  done < <(ls -1tr "$SESS_DIR"/*.json 2>/dev/null) | sort -s -n -k1,1 | cut -f2-
}

# The tab title for a session: the last name given with /rename, which Claude
# stores in the transcript, else the folder name. The name recorded at
# SessionStart is no good: it is often Claude's generated name with a short
# hex suffix (manager-ci-bd), from before the session was renamed.
tab_title() {
  local transcript=$1 cwd=$2 t=""
  [ -f "$transcript" ] && t=$(grep -a -F '"type":"custom-title"' "$transcript" | tail -1 | jq -r '.customTitle // empty' 2>/dev/null)
  printf '%s' "${t:-$(basename "$cwd")}"
}

# Print one line per session to resume: <cwd> TAB <tab title> TAB <bash command>.
# The command cds into <cwd> itself, because some spawn APIs ignore the cwd
# they are given when a command is set (Frankenterm's Lua spawn_tab does).
# Entries are moved to restored/ as they are handed out; the resumed session's
# SessionStart hook writes a fresh entry. Log lines go to restore.log.
plan() {
  mkdir -p "$SESS_DIR" "$STATE_DIR/restored"
  local log="$STATE_DIR/restore.log" f sid cwd transcript pid cmd a prompt ep
  local max=${CLAUDE_PERSIST_MAX:-40} n=0 last_mux="" tag spid
  local -A newest=() mt=()
  # The pid of the server that wrote the last snapshot, when that server is
  # gone (the normal case at boot). Run by hand against a live server, the
  # stamp check is skipped.
  if [ -f "$TAB_ORDER" ]; then
    read -r tag spid < "$TAB_ORDER"
    [ "$tag" = mux ] && [ "$spid" != "$(mux_pid)" ] && last_mux=$spid
  fi
  # A pane holds one session at a time. When several entries from the last
  # server claim the same pane, resume only the newest of them.
  local p_ m_ t_
  if [ -n "$last_mux" ]; then
    for f in "$SESS_DIR"/*.json; do
      [ -e "$f" ] || continue
      [ "$(jq -r '.mux // empty' "$f")" = "$last_mux" ] || continue
      p_=$(jq -r '.pane // empty' "$f"); [ -n "$p_" ] || continue
      # Only an entry that can be resumed may claim the pane. A session that
      # starts again in another folder (same pid and pane) writes a second
      # entry whose transcript does not exist; it must not push out the real one.
      t_=$(jq -r '.transcript // empty' "$f")
      { [ -z "$t_" ] || [ -s "$t_" ]; } && [ -d "$(jq -r .cwd "$f")" ] || continue
      m_=$(stat -c %Y "$f")
      if [ -z "${newest[$p_]:-}" ] || [ "$m_" -gt "${mt[$p_]}" ]; then newest[$p_]=$f; mt[$p_]=$m_; fi
    done
  fi
  echo "=== plan $(date -Is)" >> "$log"
  while IFS= read -r f; do
    sid=$(jq -r .session_id "$f"); cwd=$(jq -r .cwd "$f")
    transcript=$(jq -r '.transcript // empty' "$f"); pid=$(jq -r '.pid // 0' "$f")
    if claude_alive "$pid" "$sid"; then
      echo "skip $sid: still running as pid $pid" >> "$log"; continue
    fi
    if [ -n "$transcript" ] && [ ! -s "$transcript" ]; then
      echo "drop $sid ($cwd): no transcript (session never had a message)" >> "$log"
      mv "$f" "$STATE_DIR/restored/"; continue
    fi
    if [ ! -d "$cwd" ]; then
      echo "drop $sid: folder $cwd is gone" >> "$log"; mv "$f" "$STATE_DIR/restored/"; continue
    fi
    if [ -n "$last_mux" ] && [ "$(jq -r '.mux // empty' "$f")" != "$last_mux" ]; then
      echo "drop $sid ($cwd): not open at the last snapshot of mux $last_mux" >> "$log"
      mv "$f" "$STATE_DIR/restored/"; continue
    fi
    ep=$(transcript_entrypoint "$transcript")
    if [ -n "$ep" ] && [ "$ep" != cli ]; then
      echo "drop $sid ($cwd): started by the Agent SDK ($ep), not in a terminal" >> "$log"
      mv "$f" "$STATE_DIR/restored/"; continue
    fi
    p_=$(jq -r '.pane // empty' "$f")
    if [ -n "$p_" ] && [ -n "${newest[$p_]:-}" ] && [ "${newest[$p_]}" != "$f" ]; then
      echo "drop $sid ($cwd): a newer session was in the same pane $p_" >> "$log"
      mv "$f" "$STATE_DIR/restored/"; continue
    fi
    # Leave the rest on the list, so a runaway list cannot fill memory at boot.
    # Resume them by hand with `claude-persist.sh restore` once you have looked.
    if [ "$n" -ge "$max" ]; then
      echo "hold $sid ($cwd): over the limit of $max sessions" >> "$log"; continue
    fi
    n=$((n + 1))

    cmd="cd $(printf '%q' "$cwd") &&"
    if [ "$(jq '.launcher | length' "$f")" -gt 0 ]; then
      while IFS= read -r a; do cmd+=" $(printf '%q' "$a")"; done < <(jq -r '.launcher[]' "$f")
    else
      cmd+=" $(printf '%q' "$CLAUDE_BIN")"
    fi
    cmd+=" --resume $(printf '%q' "$sid")"
    while IFS= read -r a; do cmd+=" $(printf '%q' "$a")"; done < <(jq -r '.flags[]' "$f")
    # `--` ends the options, so a variadic flag such as --add-dir cannot take the prompt
    prompt=$(resume_prompt "$transcript" "$(jq -r '.status // empty' "$f")")
    [ -n "$prompt" ] && cmd+=" -- $(printf '%q' "$prompt")"
    mv "$f" "$STATE_DIR/restored/"
    echo "resume $sid ($cwd): $cmd" >> "$log"
    printf '%s\t%s\t%s\n' "$cwd" "$(tab_title "$transcript" "$cwd")" "$cmd"
  done < <(ordered_entries)
}

wait_for_mux() {
  local n=0
  until "$WEZTERM" cli --prefer-mux list >/dev/null 2>&1; do
    n=$((n + 1)); [ $n -ge 60 ] && return 1
    sleep 1
  done
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
    jq -r '"\(.session_id)  \(.name // "-")  pid=\(.pid)  \(.cwd)  \((.launcher // []) + .flags | join(" "))"' "$f"
  done
  [ -n "$found" ] || echo "no recorded sessions"
}

case "${1:-}" in
  hook-start) [ -d /run/systemd/system ] && hook_start ;;
  hook-end)   [ -d /run/systemd/system ] && hook_end ;;
  capture)    capture "${2:-}" ;;
  snapshot)   snapshot ;;
  plan)       plan ;;
  restore)    restore ;;
  list)       list ;;
  forget)     rm -v "$SESS_DIR/${2:?entry key}.json" ;;
  *) sed -n '2,21p' "$0"; exit 1 ;;
esac
exit 0
