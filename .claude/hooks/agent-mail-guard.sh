#!/usr/bin/env bash
# Agent-mail identity + availability guard. Registered on two events:
#
#   SessionStart       registers this session in agent-mail and tells the
#                      agent, in context, what its own name is.
#   UserPromptSubmit   checks availability without blocking the agent when
#                      agent-mail is unreachable.
#
# Why both. Agent-mail is only useful if EVERY session is addressable in it,
# and addressability is not something an agent can fix for a peer: a session
# that never registered has no name, so no one can send to it and its work is
# invisible to `list_agents`. Leaving registration to a prose instruction
# means it happens when an agent happens to need to send mail, which is far
# too late -- by then the peer it wants to reach has already been running
# unregistered for an hour. So registration is mechanical and happens before
# the agent's first turn.
#
# Availability is re-checked on every turn. A transient 503 or a slow health
# probe is not an outage: the server can briefly degrade while SQLite performs
# validation, checkpointing, or archive maintenance. PM2 is the only crash
# supervisor. Prompt hooks never restart or repair the SQLite-backed service.
#
# Identity is stored per session id, so resume and compact reuse the name
# already registered instead of minting a second one for the same session.
#
# Names are chosen by the server. It requires adjective+noun and rejects
# descriptive names outright, so the worktree and branch travel in
# task_description, which is what `list_agents` shows peers.
#
# Failure policy is fail-open. An unavailable coordination service must be
# visible, but it must never block agents from doing unrelated work or create a
# restart storm from many concurrent prompt hooks.

set -uo pipefail

ENDPOINT=${AGENT_MAIL_ENDPOINT:-http://127.0.0.1:8765}
STATE_DIR="$HOME/.claude/agent-mail"
OUTAGE_NOTICE_BACKOFF_SECS=900

command -v jq  >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0

payload=$(cat) || exit 0
event=$(printf '%s' "$payload" | jq -r '.hook_event_name // ""' 2>/dev/null) || exit 0
cwd=$(printf '%s'   "$payload" | jq -r '.cwd // ""'             2>/dev/null)
session=$(printf '%s' "$payload" | jq -r '.session_id // ""'    2>/dev/null)
model=$(printf '%s' "$payload" | jq -r '.model // "unknown"'    2>/dev/null)
[[ -n $cwd ]] || exit 0

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# Returns 0 when ready, 2 when the HTTP server responds but is degraded, and 1
# when no HTTP response is received. In particular, HTTP 503 proves the server
# is alive and must not trigger a restart.
probe() {
  local response code body
  response=$(curl -sS -m 3 -w $'\n%{http_code}' "$ENDPOINT/health" 2>/dev/null) || return 1
  code=${response##*$'\n'}
  body=${response%$'\n'*}
  [[ $code =~ ^[1-5][0-9][0-9]$ ]] || return 1
  [[ $body == *'"status":"ready"'* ]] && return 0
  return 2
}

# Report an outage at most once per interval. This is deliberately diagnostic
# only: PM2 owns crash recovery, while database repair requires a drained owner
# and validated backups and therefore must remain an operator action.
notice_unreachable() {
  local stamp="$STATE_DIR/last-outage-notice" now last
  now=$(date +%s)
  last=$(cat "$stamp" 2>/dev/null || echo 0)
  [[ $last =~ ^[0-9]+$ ]] || last=0
  (( now - last >= OUTAGE_NOTICE_BACKOFF_SECS )) || return 0
  printf '%s' "$now" > "$stamp"
  printf 'agent-mail unavailable at %s; coordination skipped for this turn (non-blocking)\n' \
    "$ENDPOINT/health" >&2
}

rpc() {
  curl -sf -m 10 -X POST "$ENDPOINT/mcp/" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg n "$1" --argjson a "$2" \
          '{jsonrpc:"2.0",id:1,method:"tools/call",params:{name:$n,arguments:$a}}')" 2>/dev/null
}

# Registers this session once and echoes its agent name. A cached name is
# reused so resume/compact do not mint duplicate identities.
register() {
  local cache="$STATE_DIR/identity-${session:-nosession}.json" name branch desc
  if [[ -s $cache ]]; then
    name=$(jq -r '.name // ""' "$cache" 2>/dev/null)
    [[ -n $name ]] && { printf '%s' "$name"; return 0; }
  fi

  # Do not make a new session wait on RPC while the HTTP server is degraded.
  # The hook fails open for this turn and retries registration on the next one.
  (( server_degraded )) && return 1

  rpc ensure_project "$(jq -n --arg k "$cwd" '{human_key:$k}')" >/dev/null || return 1

  branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)
  desc="worktree=$(basename "$cwd") branch=$branch"

  name=$(rpc register_agent "$(jq -n --arg k "$cwd" --arg m "$model" --arg d "$desc" \
           '{project_key:$k,program:"claude-code",model:$m,task_description:$d}')" \
         | jq -r '.result.content[0].text // ""' 2>/dev/null \
         | jq -r '.name // ""' 2>/dev/null)
  [[ -n $name ]] || return 1

  jq -n --arg n "$name" --arg k "$cwd" '{name:$n,project_key:$k}' > "$cache" 2>/dev/null
  printf '%s' "$name"
}

context_blob() {
  local name=$1
  cat <<EOF
Agent-mail identity for this session (registered automatically, no action needed):

  your name:   $name
  project key: $cwd

Use this identity for all agent-mail calls. Two standing rules:

- Coordinate through agent-mail, not only through your own report. Before
  editing shared files reserve them with file_reservation_paths, and release
  them after committing.
- Peers are addressable by name. Run list_agents on a project key to see who
  is working there and what their task_description says; that is how you find
  the right recipient instead of guessing or inventing one.
EOF
}

server_degraded=0
probe
probe_rc=$?
case $probe_rc in
  0)
    ;;
  2)
    # Temporarily degraded: alive, but avoid blocking on registration RPC.
    server_degraded=1
    ;;
  *)
    notice_unreachable
    exit 0
    ;;
esac

name=$(register) || exit 0
[[ -n $name ]] || exit 0

# The identity is announced once per session. Re-announcing on every prompt
# would spend context on something that has not changed.
announced="$STATE_DIR/announced-${session:-nosession}"
if [[ ! -e $announced ]]; then
  : > "$announced"
  jq -n --arg e "$event" --arg c "$(context_blob "$name")" \
    '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}'
fi

exit 0
