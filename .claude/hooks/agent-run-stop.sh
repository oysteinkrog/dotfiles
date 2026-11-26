#!/bin/bash
# Stop hook for scheduled agent runs (agent-run sets AGENT_RUN and AGENT_RUN_START).
# Keeps the run from ending until the agent has rewritten its state file in this run.
# Blocks at most once in a row (stop_hook_active), so it can never trap a session.
set -u
[ -n "${AGENT_RUN:-}" ] && [ -n "${AGENT_RUN_START:-}" ] || exit 0
in=$(cat)
[ "$(printf '%s' "$in" | jq -r '.stop_hook_active // false' 2>/dev/null)" = true ] && exit 0
paths=$("$HOME/bin/agent-paths" "$AGENT_RUN" 2>/dev/null) || exit 0
eval "$paths"
[ "$(stat -c %Y "$STATE" 2>/dev/null || echo 0)" -ge "$AGENT_RUN_START" ] && exit 0
jq -nc --arg s "$STATE" --arg d "$DIR" '{decision: "block", reason: ("Scheduled run: before you finish, rewrite " + $s + " (open items, what you watch, Questions for Oystein, this run result), save lasting lessons with ee remember --workspace " + $d + ", and clear the inbox items you handled.")}'
