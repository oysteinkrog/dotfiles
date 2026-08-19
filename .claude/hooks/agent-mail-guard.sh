#!/usr/bin/env bash
# Agent-mail identity + availability guard. Registered on two events:
#
#   SessionStart       registers this session in agent-mail and tells the
#                      agent, in context, what its own name is.
#   UserPromptSubmit   refuses to let the session take a turn while
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
# The prompt-level block is the enforcement half. A SessionStart hook cannot
# halt a session, and a server that was up at startup can die at any point in
# a long session, so availability is re-checked on every turn rather than
# once.
#
# Identity is stored per session id, so resume and compact reuse the name
# already registered instead of minting a second one for the same session.
#
# Names are chosen by the server. It requires adjective+noun and rejects
# descriptive names outright, so the worktree and branch travel in
# task_description, which is what `list_agents` shows peers.
#
# Failure policy is deliberately split. If agent-mail is genuinely down this
# fails CLOSED -- that is the entire point of the hook. If the hook's OWN
# inputs or dependencies are broken (no jq, unparseable payload) it fails
# OPEN, matching the other hooks here: a bug in a guard must never be able to
# wedge a session for a reason unrelated to what it guards.
#
# Escape hatch for deliberate offline work: export AGENT_MAIL_OPTIONAL=1.

set -uo pipefail

ENDPOINT=${AGENT_MAIL_ENDPOINT:-http://127.0.0.1:8765}
STATE_DIR="$HOME/.claude/agent-mail"
HEAL_BACKOFF_SECS=120

command -v jq  >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0

payload=$(cat) || exit 0
event=$(printf '%s' "$payload" | jq -r '.hook_event_name // ""' 2>/dev/null) || exit 0
cwd=$(printf '%s'   "$payload" | jq -r '.cwd // ""'             2>/dev/null)
session=$(printf '%s' "$payload" | jq -r '.session_id // ""'    2>/dev/null)
model=$(printf '%s' "$payload" | jq -r '.model // "unknown"'    2>/dev/null)
[[ -n $cwd ]] || exit 0

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

healthy() {
  curl -sf -m 3 "$ENDPOINT/health" 2>/dev/null | grep -q '"status":"ready"'
}

# Restart attempts are rate-limited: a server that is down for a real reason
# should not have pm2 kicked at it once per prompt.
heal() {
  local stamp="$STATE_DIR/last-heal" now last
  now=$(date +%s)
  last=$(cat "$stamp" 2>/dev/null || echo 0)
  (( now - last < HEAL_BACKOFF_SECS )) && return 1
  printf '%s' "$now" > "$stamp"

  pm2 restart mcp-agent-mail >/dev/null 2>&1
  for _ in 1 2 3 4 5; do
    healthy && return 0
    sleep 1
  done

  "$HOME/.local/bin/am" doctor fix >/dev/null 2>&1
  for _ in 1 2 3 4 5; do
    healthy && return 0
    sleep 1
  done
  return 1
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

if ! healthy && ! heal; then
  [[ ${AGENT_MAIL_OPTIONAL:-} == 1 ]] && exit 0
  [[ $event == UserPromptSubmit ]] || exit 0
  cat >&2 <<EOF
BLOCKED: agent-mail is unreachable, so this session is not addressable.

Endpoint: $ENDPOINT/health
Restart was attempted and did not bring it back.

Every session is required to be registered in agent-mail. While the server is
down this one has no identity, peers cannot send to it, and any file
reservation it thinks it holds is not real, so parallel sessions will edit the
same files believing they are coordinated.

Fix it, then resend:
  pm2 restart mcp-agent-mail && pm2 save
  am doctor check
  am doctor fix          # if check is unhappy

To work deliberately without agent-mail, start the session with
AGENT_MAIL_OPTIONAL=1 in the environment.
EOF
  exit 2
fi

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
