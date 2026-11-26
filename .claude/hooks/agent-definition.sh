#!/bin/bash
# SessionStart hook: print this long-running agent's standing instructions from the
# life repo (agents/<name>.md). The name comes from AGENT_RUN (set by agent-run for a
# scheduled run), else the hc terminal name, else the space name when the terminal name has
# no file. "Manager Agentic" and "manager-agentic-1a2b" both read manager-agentic.md.
# For a scheduled agent (its file has a **Runs:** line) it also prints the agent's memory:
# agents/state/<name>.md, the inbox and the ee brief in ~/.local/share/agents/<name>/.
set -u
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
  for life in "$HOME/work/life" "$HOME/projects/life"; do
    f="$life/agents/$name.md"
    [ -f "$f" ] || continue
    printf 'You are the long-running agent "%s". Your standing instructions are in %s (git, private life repo). They follow below as of this start. To change them, edit that file and commit it with a pathspec; see agents/README.md.\n\n' "$name" "$f"
    cat "$f"
    if grep -q '^\*\*Runs:\*\*' "$f"; then
      d="$HOME/.local/share/agents/$name"
      printf '\n\n---\n# Your memory (scheduled agent)\n\nYour ee store is `%s` (use `--workspace %s` on every ee call). Save lessons, facts and decisions there with `ee remember` and `ee decide record`; search it with `ee search` or `ee ask`.\n' "$d" "$d"
      printf '\n## Working state: %s\n\n' "$life/agents/state/$name.md"
      cat "$life/agents/state/$name.md" 2>/dev/null || echo "(no state file yet)"
      printf '\n## Inbox: %s/inbox.md\n\n' "$d"
      if [ -s "$d/inbox.md" ]; then cat "$d/inbox.md"; else echo "(empty)"; fi
      if [ -s "$d/brief.md" ]; then
        printf '\n## ee brief (%s)\n\n' "$(date -r "$d/brief.md" '+%F %H:%M')"
        head -c 16000 "$d/brief.md"
      fi
    fi
    exit 0
  done
done
exit 0
