#!/bin/bash
# SessionStart hook: print this long-running agent's standing instructions from the
# life repo (agents/<name>.md). The name comes from the hc terminal name, or from the
# space name when the terminal name has no file. "Manager Agentic" and
# "manager-agentic-1a2b" both read manager-agentic.md.
set -u
[ -n "${HC_TERMINAL_ID:-}" ] || exit 0
json=$(timeout 3 hc get "$HC_TERMINAL_ID" --json 2>/dev/null) || exit 0
norm() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]]+/-/g; s/-[0-9a-f]{4}$//'; }
term=$(norm "$(printf '%s' "$json" | jq -r '.name // empty' 2>/dev/null)")
space=$(norm "$(printf '%s' "$json" | jq -r '.labels.where // empty' 2>/dev/null | sed 's| / .*||')")
for name in "$term" "$space"; do
  case "$name" in */*|.*|"") continue ;; esac
  for life in "$HOME/work/life" "$HOME/projects/life"; do
    f="$life/agents/$name.md"
    if [ -f "$f" ]; then
      printf 'You are the long-running agent "%s". Your standing instructions are in %s (git, private life repo). They follow below as of this start. To change them, edit that file and commit it with a pathspec; see agents/README.md.\n\n' "$name" "$f"
      cat "$f"; exit 0
    fi
  done
done
exit 0
