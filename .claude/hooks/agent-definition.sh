#!/bin/bash
# SessionStart hook: print this long-running agent's standing instructions. The name comes
# from AGENT_RUN (set by agent-run for a scheduled run), else the hc terminal name, else the
# space name when the terminal name has no file. "Manager Agentic" and "manager-agentic-1a2b"
# both read manager-agentic.md. agent-paths finds the file: the monorepo's tools/agents/ for
# company managers, the life repo's agents/ for personal ones.
# For a scheduled agent (its file has a **Runs:** line) it also prints the agent's memory:
# the working state file, the inbox and the ee brief in ~/.local/share/agents/<name>/.
set -u
AP=$HOME/bin/agent-paths
[ -x "$AP" ] || exit 0
norm() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]]+/-/g; s/-[0-9a-f]{4}$//'; }
names=${AGENT_RUN:-}
if [ -z "$names" ]; then
  [ -n "${HC_TERMINAL_ID:-}" ] || exit 0
  json=$(timeout 3 hc get "$HC_TERMINAL_ID" --json 2>/dev/null) || exit 0
  term=$(norm "$(printf '%s' "$json" | jq -r '.name // empty' 2>/dev/null)")
  space=$(norm "$(printf '%s' "$json" | jq -r '.labels.where // empty' 2>/dev/null | sed 's| / .*||')")
  names="$term $space"
fi
for name in $names; do
  case "$name" in */*|.*|"") continue ;; esac
  paths=$("$AP" "$name") || continue
  eval "$paths"
  printf 'You are the long-running agent "%s". Your standing instructions are in %s. They follow below as of this start. To change them, edit that file (in the monorepo through a PR, in the life repo with a pathspec commit).\n\n' "$name" "$FILE"
  cat "$FILE"
  if grep -q '^\*\*Runs:\*\*' "$FILE"; then
    printf '\n\n---\n# Your memory (scheduled agent)\n\nYour ee store is `%s` (use `--workspace %s` on every ee call). Save lessons, facts and decisions there with `ee remember` and `ee decide record`; search it with `ee search` or `ee ask`.\n' "$DIR" "$DIR"
    printf '\n## Working state: %s\n\n' "$STATE"
    cat "$STATE" 2>/dev/null || echo "(no state file yet)"
    printf '\n## Inbox: %s/inbox.md\n\n' "$DIR"
    if [ -s "$DIR/inbox.md" ]; then cat "$DIR/inbox.md"; else echo "(empty)"; fi
    if [ -s "$DIR/brief.md" ]; then
      printf '\n## ee brief (%s)\n\n' "$(date -r "$DIR/brief.md" '+%F %H:%M')"
      head -c 16000 "$DIR/brief.md"
    fi
  fi
  exit 0
done
exit 0
