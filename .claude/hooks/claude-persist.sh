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
#   claude-persist.sh plan            print sessions and tabs to resume (cwd, title,
#                                     command)
#   claude-persist.sh panes           print what snapshot records for each mux
#                                     pane (window, pane, kind, cwd, arg); read-only
#   claude-persist.sh restore         resume every recorded session into the running
#                                     mux server with `frankenterm-gui cli`
#   claude-persist.sh list            show recorded sessions
#   claude-persist.sh forget KEY      drop one entry (file name without .json)
#   claude-persist.sh resume-cmd FILE print the bash command that resumes the
#                                     session of entry FILE (no claude-tab-run)
#   claude-persist.sh respawn FILE [WINDOW]
#                                     resume entry FILE in a new tab, print its pane
#
# Resumed tabs run under claude-tab-run (~/bin), so claude-version-restart can
# restart a session in the same pane after a Claude Code update.
#
# State: ~/.local/state/claude-persist/sessions/<session_id>@<folder>.json,
# tab-order (the last saved tab order of the mux server), panes (what ran in
# each pane: Claude, opencode, a shell or another program, and its folder) and
# live (the session ids whose Claude was running at the last snapshot).
# Plain shell and opencode tabs come back too: a shell reopens in its folder,
# opencode resumes its session with `opencode -s <id>` (or starts fresh in the
# folder when no session id is found).
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
FT_CLI="$HOME/.local/bin/frankenterm-gui"
MUX_UNIT=frankenterm-mux.service
TAB_ORDER="$STATE_DIR/tab-order"
PANES="$STATE_DIR/panes"
LIVE="$STATE_DIR/live"
OPENCODE_DB="${OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}"
AIOLOS_RC="$HOME/.config/aiolos-rc/aiolos-rc"
# Runs a tab's resume command, and runs it again in the same pane when
# claude-version-restart restarts the session (see that script).
TAB_RUN="${CLAUDE_TAB_RUN_BIN:-$HOME/bin/claude-tab-run}"
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

# Is this pid a live Claude process for the given session id? A sessions file
# older than this boot is left over from a killed Claude, and its pid may now
# belong to another process, so it does not count.
BOOT_TIME=$(awk '/^btime/{print $2}' /proc/stat)
claude_alive() {
  local pid=$1 sid=$2
  [ "$pid" -gt 0 ] && [ -d "/proc/$pid" ] && [ -f "$CLAUDE_SESSIONS/$pid.json" ] \
    && [ "$(stat -c %Y "$CLAUDE_SESSIONS/$pid.json")" -ge "$BOOT_TIME" ] \
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
        case "$v" in */aiolos-rc-settings.*|*/aiolos-rc/override.settings.json) ;; *) printf '%s\n%s\n' "$a" "$v" ;; esac ;;
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
  # The entry for this cwd, plus any other entry of this session and Claude
  # process: a session that changed folder has one per folder, and the one
  # left behind would come back at boot.
  local cpid g; cpid=$(find_claude_pid) || cpid=""
  local -a files=()
  f=$(entry_file "$sid" "$cwd"); [ -f "$f" ] && files+=("$f")
  if [ -n "$cpid" ]; then
    for g in "$SESS_DIR/$sid"@*.json; do
      [ -e "$g" ] && [ "$g" != "$f" ] || continue
      [ "$(jq -r '.pid // 0' "$g")" = "$cpid" ] && files+=("$g")
    done
  fi
  [ ${#files[@]} -gt 0 ] || return 0
  # Keep the entries when the mux server the session ran under is gone. A
  # Claude in its own scope can outlive its mux by a few seconds, and when the
  # restarted mux is already active the checks below see a normal exit. On
  # 2026-10-12 that dropped kpp one second after the mux came back.
  local cur stamp; cur=$(mux_pid)
  for g in "${files[@]}"; do
    stamp=$(jq -r '.mux // empty' "$g")
    [ -n "$stamp" ] && [ "$stamp" != "$cur" ] && return 0
  done
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
  # Hold the lock so a running snapshot cannot write an entry back between
  # its jq and its mv.
  lock_state
  for g in "${files[@]}"; do
    rm -f "$g"
    # Claude is still running while this hook runs. Leave a marker with its
    # pid, so a snapshot in that gap does not record the session again.
    [ -n "$cpid" ] && mkdir -p "$STATE_DIR/ended" && echo "$cpid" > "$STATE_DIR/ended/$(basename "$g" .json)"
    echo "$(date -Is) ended $(basename "$g" .json) reason=$reason" >> "$STATE_DIR/events.log"
  done
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

# Serialize snapshot and hook_end on the entries. The lock lasts until the
# process exits. After 6 s go on anyway: the hook has 10 s in all, and a late
# write is better than none.
lock_state() {
  mkdir -p "$STATE_DIR"
  exec 9> "$STATE_DIR/.lock"
  flock -w 6 9 || true
}

# Which mux server is running: <boot id>:<pid>, or nothing. The pid alone is
# not enough: the server starts early at boot with a low pid (1213 on
# 2026-10-07) that the next boot can hand out again. Then plan would take the
# new server for the old one and skip both the saved order and the stamp check.
mux_pid() {
  # tests set CLAUDE_PERSIST_MUX_ID (empty means no server is running)
  if [ -n "${CLAUDE_PERSIST_MUX_ID+x}" ]; then
    [ -n "$CLAUDE_PERSIST_MUX_ID" ] && printf '%s\n' "$CLAUDE_PERSIST_MUX_ID"
    return 0
  fi
  local p; p=$(systemctl --user show -p MainPID --value "$MUX_UNIT" 2>/dev/null)
  [ -n "$p" ] && [ "$p" != 0 ] || return 0
  printf '%s:%s\n' "$(cat /proc/sys/kernel/random/boot_id)" "$p"
}

# The FrankenTerm CLI, talking to the mux server's own socket, not a GUI's (a GUI
# numbers panes its own way). The CLI falls back to WEZTERM_UNIX_SOCKET, so clear
# that one too.
ft() { env -u FRANKENTERM_UNIX_SOCKET -u WEZTERM_UNIX_SOCKET -u WEZTERM_PANE "$FT_CLI" cli "$@"; }

# Is this session id running in any live Claude process? A session that Claude
# handed to its background daemon lives on under another pid (kind "bg").
session_running() {
  local sf
  for sf in $(grep -l -F -- "\"$1\"" "$CLAUDE_SESSIONS"/*.json 2>/dev/null); do
    claude_alive "$(basename "$sf" .json)" "$1" && return 0
  done
  return 1
}

# Open a tab in the mux server that runs CMD in CWD, then keeps a fish shell open,
# and print the new pane id. `cli spawn` hands the caller's environment to the new
# tab. Clear what belongs to the caller's own Claude session: with aiolos-rc's
# preload and shim port, the resumed session's shim would send its own requests
# into the caller's shim and fail; with ANTHROPIC_BASE_URL=api.anthropic.com,
# aiolos-rc would send inference straight to Anthropic. The timer runs with
# systemd's short PATH, so give the tab the PATH of a login shell.
spawn_tab() {
  local window_id=$1 cwd=$2 cmd=$3 lp listing
  local -a where=(--new-window)
  # Without a window id, ask the server again. Open a new window only when the
  # server really has none; if it cannot be asked, fail rather than split tabs
  # into a window the user did not ask for.
  if [ -z "$window_id" ]; then
    listing=$(ft list --json 2>/dev/null) || { echo "spawn_tab: cannot list mux windows, not spawning" >&2; return 1; }
    window_id=$(jq -r '.[0].window_id // empty' <<<"$listing") \
      || { echo "spawn_tab: unreadable mux listing, not spawning" >&2; return 1; }
  fi
  [ -n "$window_id" ] && where=(--window-id "$window_id")
  lp=$(fish -lc 'string join : $PATH' 2>/dev/null)
  [ -n "$lp" ] && cmd="export PATH=$(printf '%q' "$lp"); $cmd"
  env -u LD_PRELOAD -u AIOLOS_RC_PORT -u AIOLOS_RC_SCOPED -u CLAUDECODE \
      -u CLAUDE_CODE_ENTRYPOINT -u ANTHROPIC_BASE_URL \
      -u FRANKENTERM_UNIX_SOCKET -u WEZTERM_UNIX_SOCKET -u WEZTERM_PANE \
    "$FT_CLI" cli spawn "${where[@]}" --cwd "$cwd" -- bash -c "$cmd; exec fish -l"
}

# The opencode session a running opencode process (pid $1, folder $2) is in:
# its -s/--session argument, else the newest top-level session in that folder
# updated since the process started. The database is opened read-only. Prints
# nothing when no session is found (a fresh opencode that has no message yet).
opencode_session() {
  local pid=$1 cwd=$2 i a start_ms id dir want
  local -a argv
  mapfile -d '' -t argv < "/proc/$pid/cmdline" 2>/dev/null
  for ((i = 1; i < ${#argv[@]}; i++)); do
    a=${argv[$i]}
    case "$a" in
      -s|--session) printf '%s\n' "${argv[$((i + 1))]:-}"; return 0 ;;
      --session=*) printf '%s\n' "${a#--session=}"; return 0 ;;
    esac
  done
  [ -f "$OPENCODE_DB" ] && command -v sqlite3 >/dev/null || return 0
  # process start time in ms since the epoch: field 22 of stat, in clock ticks
  start_ms=$(awk -v bt="$BOOT_TIME" -v hz="$(getconf CLK_TCK)" \
    '{ sub(/^.*\) /, ""); printf "%d", (bt + $20 / hz) * 1000 }' "/proc/$pid/stat" 2>/dev/null)
  [ -n "$start_ms" ] || start_ms=0
  want=$(realpath -m -- "$cwd")
  while IFS=$'\t' read -r id dir; do
    # the folder may be stored through a symlink (~/work/x for ~/projects/x)
    [ "$(realpath -m -- "$dir")" = "$want" ] && { printf '%s\n' "$id"; return 0; }
  done < <(sqlite3 -readonly -separator $'\t' "$OPENCODE_DB" \
    "select id, directory from session where parent_id is null and time_archived is null
       and time_updated >= $start_ms order by time_updated desc limit 50" 2>/dev/null)
}

# Print one row per pane of the mux listing $1 (`cli list --json`), in its order:
# <window> TAB <pane> TAB <kind> TAB <cwd> TAB <arg>. kind is claude (arg: the
# session id), opencode (arg: its session id, or empty), shell, or other (arg:
# the program's name; it is not restarted, the tab comes back as a shell).
# Classify by the processes in the pane's foreground process group.
pane_rows() {
  local listing=$1 pid pgid tpgid tt w p tty lcwd q kind arg cwd lead comm sid
  local -A fg_of=() all_of=()
  while read -r pid pgid tpgid tt; do
    [ "$tt" = "?" ] && continue
    all_of[$tt]+="$pid "
    [ "$pgid" = "$tpgid" ] && fg_of[$tt]+="$pid "
  done < <(ps -e -o pid=,pgid=,tpgid=,tty= 2>/dev/null)
  while IFS=$'\t' read -r w p tty lcwd; do
    tty=${tty#/dev/}
    # the listing's cwd is a file:// URL; prefer the process's own cwd below
    if [ -n "$lcwd" ]; then
      lcwd=${lcwd#file://}; [ "${lcwd:0:1}" = / ] || lcwd=/${lcwd#*/}
      [ "$lcwd" = / ] || lcwd=${lcwd%/}
    fi
    kind="" arg="" cwd="" lead=""
    local procs=${fg_of[$tty]:-${all_of[$tty]:-}}
    for q in $procs; do
      [ -n "$lead" ] || lead=$q
      [ "$(awk '{print $5}' "/proc/$q/stat" 2>/dev/null)" = "$q" ] && lead=$q
      if [ -f "$CLAUDE_SESSIONS/$q.json" ]; then
        sid=$(jq -r '.sessionId // empty' "$CLAUDE_SESSIONS/$q.json" 2>/dev/null)
        if [ -n "$sid" ] && claude_alive "$q" "$sid"; then
          kind=claude arg=$sid cwd=$(readlink "/proc/$q/cwd" 2>/dev/null); break
        fi
      fi
      local -a av=()
      mapfile -d '' -t av < "/proc/$q/cmdline" 2>/dev/null
      # the opencode binary itself, or node running its script
      if [ "${av[0]:-}" != "" ] && [ "${av[0]##*/}" = opencode ] \
         || { [ "${av[1]:-}" != "" ] && [ "${av[1]##*/}" = opencode ]; }; then
        cwd=$(readlink "/proc/$q/cwd" 2>/dev/null)
        kind=opencode arg=$(opencode_session "$q" "${cwd:-$lcwd}"); break
      fi
    done
    if [ -z "$kind" ]; then
      comm=$(cat "/proc/${lead:-0}/comm" 2>/dev/null)
      case "$comm" in
        ""|fish|bash|zsh|sh|dash) kind=shell ;;
        *) kind=other arg=$comm ;;
      esac
      [ -n "$lead" ] && cwd=$(readlink "/proc/$lead/cwd" 2>/dev/null)
    fi
    # never an empty cwd: plan splits on tabs, and empty fields would collapse
    printf '%s\t%s\t%s\t%s\t%s\n' "$w" "$p" "$kind" "${cwd:-${lcwd:-?}}" "$arg"
  done < <(jq -r '.[] | [.window_id, .pane_id, (.tty_name // ""), (.cwd // "")] | @tsv' <<<"$listing" 2>/dev/null)
}

# Save the mux server's tab order: a header line with the server's id, then
# <window id> TAB <pane id> per pane, in tab order. Ask the server's own socket,
# not a GUI's (a GUI numbers panes its own way). Keep the old file when the
# server answers with nothing, so a dying server cannot wipe it.
snapshot() {
  local pid listing rows
  pid=$(mux_pid); [ -n "$pid" ] || return 0
  listing=$(ft list --json 2>/dev/null)
  rows=$(jq -r '.[] | "\(.window_id)\t\(.pane_id)"' <<<"$listing" 2>/dev/null)
  [ -n "$rows" ] || return 0
  lock_state
  { echo "mux $pid"; printf '%s\n' "$rows"; } > "$TAB_ORDER.tmp" && mv "$TAB_ORDER.tmp" "$TAB_ORDER"
  # What runs in each pane, so plan can bring back shell and opencode tabs too.
  local prow
  prow=$(pane_rows "$listing")
  [ -n "$prow" ] && { echo "mux $pid"; printf '%s\n' "$prow"; } > "$PANES.tmp" && mv "$PANES.tmp" "$PANES"

  local f epid pane sf ssid scwd em
  local -A row_pane=() row_tty=()
  local w_ p_ t_
  while IFS=$'\t' read -r w_ p_; do row_pane[$p_]=1; done <<<"$rows"
  # The terminal of each pane. Pane ids start over in every mux server, so a
  # Claude that outlived the last server can have the pane id of a new pane.
  # A tty cannot be shared: the old Claude still holds its pts open, so the new
  # server gets other numbers. "Is this Claude in this server" asks by tty.
  while IFS= read -r t_; do [ -n "$t_" ] && row_tty[$t_]=1; done \
    < <(jq -r '.[].tty_name // empty' <<<"$listing" 2>/dev/null)
  in_this_mux() { local t; t=$(readlink "/proc/$1/fd/0" 2>/dev/null); [ -n "$t" ] && [ -n "${row_tty[$t]:-}" ]; }

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
    [ -n "$pane" ] && in_this_mux "$epid" || continue
    tr '\0' '\n' < "/proc/$epid/environ" 2>/dev/null | grep -qx 'CLAUDE_PERSIST=0' && continue
    ssid=$(jq -r '.sessionId // empty' "$sf"); scwd=$(jq -r '.cwd // empty' "$sf")
    [ -n "$ssid" ] && [ -n "$scwd" ] || continue
    [ -f "$(entry_file "$ssid" "$scwd")" ] && continue
    em="$STATE_DIR/ended/$(basename "$(entry_file "$ssid" "$scwd")" .json)"
    [ "$(cat "$em" 2>/dev/null)" = "$epid" ] && continue
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

  # Stamp each live session with this server's id. plan resumes only the
  # sessions stamped by the server that just went away, which are the ones
  # still open at its last snapshot (at most 30 s before it stopped). An entry
  # whose tab was closed without a SessionEnd hook keeps an old stamp and is
  # dropped instead of coming back. Only a session whose terminal is in this
  # server gets the stamp: a Claude that outlived the last server keeps that
  # server's stamp, so its exit hook keeps the entry and the late resume below
  # brings it back.
  for f in "$SESS_DIR"/*.json; do
    [ -e "$f" ] || continue
    epid=$(jq -r '.pid // 0' "$f")
    claude_alive "$epid" "$(jq -r .session_id "$f")" || continue
    [ "$(jq -r '.mux // empty' "$f")" = "$pid" ] && continue
    in_this_mux "$epid" || continue
    jq --arg m "$pid" '.mux = $m' "$f" > "$f.tmp" && touch -r "$f" "$f.tmp" && mv "$f.tmp" "$f"
  done

  # Is the machine or this server going down? Then sessions and panes are
  # going away: nothing is retired below, and the live list only grows.
  local stopping=""
  [ "$(systemctl is-system-running 2>/dev/null)" = stopping ] && stopping=1
  [ "$(systemctl --user is-active "$MUX_UNIT" 2>/dev/null)" = active ] || stopping=1

  # Save the session ids whose Claude is running now, whatever their stamp.
  # plan resumes these even when the stamp is old: a session that was running
  # at the last snapshot must come back. The stamp alone missed sessions whose
  # terminal was not matched to this server.
  local lsid_ lrows=""
  for f in "$SESS_DIR"/*.json; do
    [ -e "$f" ] || continue
    lsid_=$(jq -r '.session_id // empty' "$f" 2>/dev/null)
    [ -n "$lsid_" ] && claude_alive "$(jq -r '.pid // 0' "$f")" "$lsid_" && lrows+="$lsid_"$'\n'
  done
  # While the machine or the server is stopping, Claude processes are dying one
  # by one: keep the ids the earlier snapshot of this server saw as well.
  if [ -n "$stopping" ] && [ "$(head -1 "$LIVE" 2>/dev/null)" = "mux $pid" ]; then
    lrows+=$(tail -n +2 "$LIVE")$'\n'
  fi
  { echo "mux $pid"; printf '%s' "$lrows" | sed '/^$/d' | sort -u; } > "$LIVE.tmp" && mv "$LIVE.tmp" "$LIVE"

  # Retire the entries of closed tabs: stamped by this server, Claude no longer
  # running, and the pane gone from this server's list. Closing a tab can kill
  # Claude before its SessionEnd hook runs, and those entries used to come back
  # at the next boot. Pane ids are never reused within one server, and a tab
  # whose Claude exited still has its pane (the fish shell after it).
  # Never during shutdown: sessions and panes are going away then, and their
  # entries must stay for the next boot.
  mkdir -p "$STATE_DIR/restored"
  for f in "$SESS_DIR"/*.json; do
    [ -z "$stopping" ] || break
    [ -e "$f" ] || continue
    [ "$(jq -r '.mux // empty' "$f")" = "$pid" ] || continue
    pane=$(jq -r '.pane // empty' "$f"); [ -n "$pane" ] || continue
    [ -n "${row_pane[$pane]:-}" ] && continue
    claude_alive "$(jq -r '.pid // 0' "$f")" "$(jq -r .session_id "$f")" && continue
    mv "$f" "$STATE_DIR/restored/"
    echo "$(date -Is) closed $(basename "$f" .json): pane $pane is gone from mux $pid" >> "$STATE_DIR/events.log"
  done
  # Resume sessions whose Claude outlived its mux server. At mux startup plan
  # skips a session that is still running and marks it late. Its Claude dies
  # soon after (its terminal is gone), its exit hook keeps the entry because the
  # stamp is the old server's, and nothing else would bring it back. On
  # 2026-10-12 kpp had to be resumed by hand. A session that Claude moved to its
  # background daemon is still running under another pid: drop that entry.
  local late lsid window_id="" lcmd lpane
  for f in "$SESS_DIR"/*.json; do
    [ -z "$stopping" ] || break
    [ -e "$f" ] || continue
    late=$(jq -r '.late // empty' "$f"); [ -n "$late" ] || continue
    lsid=$(jq -r .session_id "$f")
    claude_alive "$(jq -r '.pid // 0' "$f")" "$lsid" && continue
    if [ "$(jq -r '.mux // empty' "$f")" != "$late" ] || session_running "$lsid"; then
      mv "$f" "$STATE_DIR/restored/"
      echo "$(date -Is) late $(basename "$f" .json): not resumed, restamped or still running elsewhere" >> "$STATE_DIR/events.log"
      continue
    fi
    lcmd=$(resume_cmd "$f") || { mv "$f" "$STATE_DIR/restored/"; continue; }
    [ -n "$window_id" ] || window_id=$(jq -r '.[0].window_id // empty' <<<"$listing")
    mv "$f" "$STATE_DIR/restored/"
    if lpane=$(spawn_tab "$window_id" "$(jq -r .cwd "$STATE_DIR/restored/$(basename "$f")")" "$lcmd"); then
      echo "$(date -Is) late $(basename "$f" .json): resumed in pane $lpane, its Claude outlived mux $late" >> "$STATE_DIR/events.log"
    else
      echo "$(date -Is) late $(basename "$f" .json): spawn failed" >> "$STATE_DIR/events.log"
    fi
  done

  # Drop ended markers once their Claude process is gone.
  for em in "$STATE_DIR"/ended/*; do
    [ -e "$em" ] || continue
    [ -d "/proc/$(cat "$em" 2>/dev/null)" ] || rm -f "$em"
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

# Print what plan works through, in the order to resume it: by the pane's
# place in the saved tab order, then the rest of the entries oldest first.
# One line per item: "entry TAB <file>", or, when a panes file $1 is given,
# "pane TAB <kind> TAB <pane> TAB <cwd> TAB <arg>" for each pane in it. At the
# same place an entry comes before its pane. The saved order is used only when
# it came from an earlier mux server: pane ids start over in a new server, so a
# snapshot of the current one says nothing about the recorded panes.
ordered_entries() {
  local panes_file=${1:-}
  local -A pos=()
  local tag spid w p i=0 n=0 f pane k pc pa
  if [ -f "$TAB_ORDER" ]; then
    read -r tag spid < "$TAB_ORDER"
    if [ "$tag" = mux ] && [ "$spid" != "$(mux_pid)" ]; then
      while IFS=$'\t' read -r w p; do
        [ -n "${pos[$p]:-}" ] || pos[$p]=$i; i=$((i + 1))
      done < <(tail -n +2 "$TAB_ORDER")
    fi
  fi
  {
    while IFS= read -r f; do
      pane=$(jq -r '.pane // empty' "$f" 2>/dev/null)
      printf '%d\t0\tentry\t%s\n' "${pos[${pane:-x}]:-$((1000000 + n))}" "$f"
      n=$((n + 1))
    done < <(ls -1tr "$SESS_DIR"/*.json 2>/dev/null)
    if [ -n "$panes_file" ] && [ -f "$panes_file" ]; then
      i=0
      while IFS=$'\t' read -r w p k pc pa; do
        [ -n "$p" ] || continue
        printf '%d\t1\tpane\t%s\t%s\t%s\t%s\n' "${pos[$p]:-$((2000000 + i))}" "$k" "$p" "$pc" "$pa"
        i=$((i + 1))
      done < <(tail -n +2 "$panes_file")
    fi
  } | sort -s -t$'\t' -k1,1n -k2,2n | cut -f3-
}

# The folder $1 after the 2026-10 move between ~/work and ~/projects, when $1
# is gone and the other one exists.
relocated_dir() {
  local d=$1 alt=""
  case "$d/" in
    "$HOME/work/"*) alt="$HOME/projects${d#"$HOME/work"}" ;;
    "$HOME/projects/"*) alt="$HOME/work${d#"$HOME/projects"}" ;;
  esac
  [ -n "$alt" ] && [ -d "$alt" ] && printf '%s\n' "$alt"
}

# The tab title for a session: the last name given with /rename, which Claude
# stores in the transcript, else the last title Claude generated, else the
# folder name. The name recorded at
# SessionStart is no good: it is often Claude's generated name with a short
# hex suffix (manager-ci-bd), from before the session was renamed.
tab_title() {
  local transcript=$1 cwd=$2 t=""
  if [ -f "$transcript" ]; then
    t=$(grep -a -F '"type":"custom-title"' "$transcript" | tail -1 | jq -r '.customTitle // empty' 2>/dev/null)
    # else the title Claude generated, which the live tab shows
    [ -n "$t" ] || t=$(grep -a -F '"type":"ai-title"' "$transcript" | tail -1 | jq -r '.aiTitle // empty' 2>/dev/null)
  fi
  printf '%s' "${t:-$(basename "$cwd")}"
}

# Print the bash command that resumes the session of entry file $1, run through
# claude-tab-run when it is installed.
resume_cmd() {
  local inner
  inner=$(resume_cmd_inner "$1") || return 1
  if [ -x "$TAB_RUN" ]; then
    printf '%q %q\n' "$TAB_RUN" "$inner"
  else
    printf '%s\n' "$inner"
  fi
}

# Print the bash command that resumes the session of entry file $1.
resume_cmd_inner() {
  local f=$1 a prompt cmd
  cmd="cd $(printf '%q' "$(jq -r .cwd "$f")") &&"
  if [ "$(jq '.launcher | length' "$f")" -gt 0 ]; then
    while IFS= read -r a; do cmd+=" $(printf '%q' "$a")"; done < <(jq -r '.launcher[]' "$f")
  else
    cmd+=" $(printf '%q' "$CLAUDE_BIN")"
  fi
  cmd+=" --resume $(printf '%q' "$(jq -r .session_id "$f")")"
  while IFS= read -r a; do cmd+=" $(printf '%q' "$a")"; done < <(jq -r '.flags[]' "$f")
  # `--` ends the options, so a variadic flag such as --add-dir cannot take the prompt
  prompt=$(resume_prompt "$(jq -r '.transcript // empty' "$f")" "$(jq -r '.status // empty' "$f")")
  [ -n "$prompt" ] && cmd+=" -- $(printf '%q' "$prompt")"
  printf '%s\n' "$cmd"
}

# Print one line per tab to reopen: <cwd> TAB <tab title> TAB <bash command>.
# The command cds into <cwd> itself, because some spawn APIs ignore the cwd
# they are given (Frankenterm's Lua spawn_tab when a command is set, and
# `cli spawn --cwd`). Claude entries are moved to restored/ as they are handed
# out; the resumed session's SessionStart hook writes a fresh entry. After a
# restart of the mux server (not when run by hand against a live one), the
# shell and opencode tabs of the last snapshot come back too.
#
# Every entry and pane gets a line in restore.log saying what was done with it
# and why: resume, reopen, drop, skip or hold. Nothing is left out silently.
plan() {
  mkdir -p "$SESS_DIR" "$STATE_DIR/restored"
  local log="$STATE_DIR/restore.log" f tag spid
  local max=${CLAUDE_PERSIST_MAX:-40} max_panes=${CLAUDE_PERSIST_MAX_PANES:-40}
  local n=0 np=0 last_mux="" panes_file="" k a b c d
  local -A newest=() mt=() live=() seen=() claimed=() resumed_sid=()
  local -a out=()
  # Hold the lock while deciding, so nothing renames or rewrites entries under
  # us. On 2026-10-30 retire-work-symlinks.service moved an entry from
  # ~/work/life to ~/projects/life while plan ran; plan had listed the old name,
  # found it gone, logged "drop : folder  is gone" and never saw the new one.
  lock_state
  # The id of the server that wrote the last snapshot, when that server is
  # gone (the normal case at boot). Run by hand against a live server, the
  # stamp check is skipped and no shell tabs are reopened.
  if [ -f "$TAB_ORDER" ]; then
    read -r tag spid < "$TAB_ORDER"
    [ "$tag" = mux ] && [ "$spid" != "$(mux_pid)" ] && last_mux=$spid
  fi
  echo "=== plan $(date -Is)${last_mux:+ (last mux $last_mux)}" >> "$log"
  # Sessions whose Claude was running at the last snapshot of that server.
  if [ -n "$last_mux" ] && [ "$(head -1 "$LIVE" 2>/dev/null)" = "mux $last_mux" ]; then
    while IFS= read -r a; do [ -n "$a" ] && live[$a]=1; done < <(tail -n +2 "$LIVE")
  fi
  # The panes of that server. Used once: a second plan for the same server
  # (a crash before the first snapshot) must not open the tabs twice.
  if [ -n "$last_mux" ] && [ "$(head -1 "$PANES" 2>/dev/null)" = "mux $last_mux" ]; then
    panes_file="$PANES.used"
    mv "$PANES" "$panes_file"
  fi
  # A pane holds one session at a time. When several entries from the last
  # server claim the same pane, resume only the newest of them.
  local p_ m_ t_
  if [ -n "$last_mux" ]; then
    for f in "$SESS_DIR"/*.json; do
      [ -e "$f" ] || continue
      [ "$(jq -r '.mux // empty' "$f" 2>/dev/null)" = "$last_mux" ] || continue
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

  # One Claude entry.
  plan_entry() {
    local f=$1 key sid cwd transcript pid stamp ep cmd mine=""
    key=$(basename "$f" .json); seen[$key]=1
    if [ ! -f "$f" ]; then
      echo "skip $key: the entry vanished during plan (renamed or removed by another program)" >> "$log"
      # It no longer holds its pane: an entry found under its new name may.
      for p_ in "${!newest[@]}"; do [ "${newest[$p_]}" = "$f" ] && unset "newest[$p_]"; done
      return 0
    fi
    sid=$(jq -r '.session_id // empty' "$f" 2>/dev/null); cwd=$(jq -r '.cwd // empty' "$f" 2>/dev/null)
    if [ -z "$sid" ] || [ -z "$cwd" ]; then
      echo "drop $key: unreadable entry (no session id or folder)" >> "$log"
      mv "$f" "$STATE_DIR/restored/"; return 0
    fi
    transcript=$(jq -r '.transcript // empty' "$f"); pid=$(jq -r '.pid // 0' "$f")
    stamp=$(jq -r '.mux // empty' "$f")
    [ -n "$last_mux" ] && [ "$stamp" = "$last_mux" ] && mine=1
    p_=$(jq -r '.pane // empty' "$f")
    if claude_alive "$pid" "$sid"; then
      resumed_sid[$sid]=1
      [ -n "$mine" ] && [ -n "$p_" ] && claimed[$p_]="Claude session $sid, still running"
      # It outlived the last server; snapshot resumes it once it exits.
      if [ -n "$mine" ] || { [ -n "${live[$sid]:-}" ] && [ -n "$stamp" ]; }; then
        jq --arg m "$stamp" '.late = $m' "$f" > "$f.tmp" && touch -r "$f" "$f.tmp" && mv "$f.tmp" "$f"
        echo "skip $sid: still running as pid $pid, resumed when it exits" >> "$log"
      else
        echo "skip $sid: still running as pid $pid" >> "$log"
      fi
      return 0
    fi
    if [ -n "$transcript" ] && [ ! -s "$transcript" ]; then
      echo "drop $sid ($cwd): no transcript (session never had a message)" >> "$log"
      mv "$f" "$STATE_DIR/restored/"; return 0
    fi
    if [ ! -d "$cwd" ]; then
      echo "drop $sid: folder $cwd is gone" >> "$log"; mv "$f" "$STATE_DIR/restored/"; return 0
    fi
    if [ -n "$last_mux" ] && [ -z "$mine" ]; then
      if [ -n "${live[$sid]:-}" ]; then
        # A running Claude at the last snapshot wins over an old stamp.
        echo "keep $sid ($cwd): stamped by mux ${stamp:-none}, but its Claude was running at the last snapshot" >> "$log"
      else
        echo "drop $sid ($cwd): not open at the last snapshot of mux $last_mux (stamp ${stamp:-none})" >> "$log"
        mv "$f" "$STATE_DIR/restored/"; return 0
      fi
    fi
    ep=$(transcript_entrypoint "$transcript")
    if [ -n "$ep" ] && [ "$ep" != cli ]; then
      echo "drop $sid ($cwd): started by the Agent SDK ($ep), not in a terminal" >> "$log"
      mv "$f" "$STATE_DIR/restored/"; return 0
    fi
    # Pane ids belong to one server; compare them only among its own entries.
    if [ -n "$mine" ] && [ -n "$p_" ] && [ -n "${newest[$p_]:-}" ] && [ "${newest[$p_]}" != "$f" ]; then
      echo "drop $sid ($cwd): a newer session was in the same pane $p_" >> "$log"
      mv "$f" "$STATE_DIR/restored/"; return 0
    fi
    # Leave the rest on the list, so a runaway list cannot fill memory at boot.
    # Resume them by hand with `claude-persist.sh restore` once you have looked.
    if [ "$n" -ge "$max" ]; then
      [ -n "$mine" ] && [ -n "$p_" ] && claimed[$p_]="Claude session $sid, held over the limit"
      resumed_sid[$sid]=1
      echo "hold $sid ($cwd): over the limit of $max sessions" >> "$log"; return 0
    fi
    n=$((n + 1))
    cmd=$(resume_cmd "$f")
    mv "$f" "$STATE_DIR/restored/"
    [ -n "$mine" ] && [ -n "$p_" ] && claimed[$p_]="Claude session $sid"
    resumed_sid[$sid]=1
    echo "resume $sid ($cwd): $cmd" >> "$log"
    out+=("$cwd"$'\t'"$(tab_title "$transcript" "$cwd")"$'\t'"$cmd")
  }

  # One pane of the last server that is not a resumed Claude session.
  plan_pane() {
    local kind=$1 pane=$2 cwd=$3 arg=$4 dir alt cmd what
    if [ -n "${claimed[$pane]:-}" ]; then
      echo "skip pane $pane ($kind): ${claimed[$pane]} is in it" >> "$log"; return 0
    fi
    if [ "$kind" = claude ] && [ -n "${resumed_sid[$arg]:-}" ]; then
      echo "skip pane $pane (claude): its session $arg is handled from its entry" >> "$log"; return 0
    fi
    if [ "$np" -ge "$max_panes" ]; then
      echo "skip pane $pane ($kind, $cwd): over the limit of $max_panes tabs" >> "$log"; return 0
    fi
    dir=$cwd
    if [ ! -d "$dir" ]; then
      if alt=$(relocated_dir "$dir"); then
        echo "pane $pane: folder $cwd is gone, using $alt (moved)" >> "$log"; dir=$alt
      else
        echo "pane $pane: folder $cwd is gone, opening in $HOME instead" >> "$log"; dir=$HOME
      fi
    fi
    case "$kind" in
      opencode)
        if [ -n "$arg" ]; then
          cmd="cd $(printf '%q' "$dir") && opencode -s $(printf '%q' "$arg")"
          what="opencode session $arg"
        else
          cmd="cd $(printf '%q' "$dir") && opencode"
          what="opencode, started fresh: no session id was found"
        fi ;;
      claude) cmd="cd $(printf '%q' "$dir")"; what="a shell: Claude session $arg ran here, but has no entry to resume" ;;
      other)  cmd="cd $(printf '%q' "$dir")"; what="a shell: it ran $arg, which is not restarted" ;;
      *)      cmd="cd $(printf '%q' "$dir")"; what="a shell" ;;
    esac
    np=$((np + 1))
    echo "reopen pane $pane in $dir as $what: $cmd" >> "$log"
    out+=("$dir"$'\t'"$(basename "$dir")"$'\t'"$cmd")
  }

  while IFS=$'\t' read -r k a b c d; do
    case "$k" in
      entry) plan_entry "$a" ;;
      pane) plan_pane "$a" "$b" "$c" "${d:-}" ;;
    esac
  done < <(ordered_entries "$panes_file")
  # Entries that appeared while plan ran (written under a new name by another
  # program) would otherwise be missed. Look again until nothing new shows up.
  for _ in 1 2 3; do
    local -a extra=()
    for f in "$SESS_DIR"/*.json; do
      [ -e "$f" ] || continue
      [ -n "${seen[$(basename "$f" .json)]:-}" ] || extra+=("$f")
    done
    [ ${#extra[@]} -gt 0 ] || break
    for f in "${extra[@]}"; do
      echo "found $(basename "$f" .json) after the first pass" >> "$log"
      plan_entry "$f"
    done
  done
  # Release the lock before printing: the caller spawns tabs as it reads, and
  # their hooks and snapshots must not wait for us.
  exec 9>&-
  [ ${#out[@]} -gt 0 ] && printf '%s\n' "${out[@]}"
  return 0
}

wait_for_mux() {
  local n=0
  until ft list >/dev/null 2>&1; do
    n=$((n + 1)); [ $n -ge 60 ] && return 1
    sleep 1
  done
}

# Resume sessions into an already running mux server, for example the ones plan
# held back over the limit. (The mux-startup handler in wezterm.lua uses `plan`
# directly instead.) The CLI cannot set a tab title; Claude sets it once it runs.
restore() {
  exec >> "$STATE_DIR/restore.log" 2>&1
  wait_for_mux || { echo "mux not reachable, giving up"; return 1; }
  local cwd title cmd pane window_id
  window_id=$(ft list --json | jq -r '.[0].window_id // empty')
  while IFS=$'\t' read -r cwd title cmd; do
    if pane=$(spawn_tab "$window_id" "$cwd" "$cmd"); then
      echo "spawned pane $pane for $cwd ($title)"
      [ -n "$window_id" ] || window_id=$(ft list --json | jq -r --argjson p "$pane" '.[] | select(.pane_id==$p) | .window_id')
    else
      echo "could not spawn a tab for $cwd ($title)"
    fi
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

# Sourced (by claude-persist.test.sh): define the functions only.
[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

case "${1:-}" in
  hook-start) [ -d /run/systemd/system ] && hook_start ;;
  hook-end)   [ -d /run/systemd/system ] && hook_end ;;
  capture)    capture "${2:-}" ;;
  snapshot)   snapshot ;;
  plan)       plan ;;
  panes)      ft list --json 2>/dev/null | { l=$(cat); pane_rows "$l"; } ;;
  restore)    restore ;;
  list)       list ;;
  forget)     rm -v "$SESS_DIR/${2:?entry key}.json" ;;
  resume-cmd) resume_cmd_inner "${2:?entry file}" ;;
  respawn)    f=${2:?entry file}; [ -f "$f" ] || { echo "no entry file $f" >&2; exit 1; }
              spawn_tab "${3:-}" "$(jq -r .cwd "$f")" "$(resume_cmd "$f")" || exit 1 ;;
  *) sed -n '2,/^$/p' "$0"; exit 1 ;;
esac
exit 0
