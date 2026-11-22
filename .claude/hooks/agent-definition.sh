#!/bin/bash
# SessionStart hook: give a long-running agent its standing instructions.
#
# The definitions live in the private life repo, agents/<name>.md (see its README).
# The name is this terminal's hc name without the 4-character suffix hc adds
# (manager-security-f330 -> manager-security), lowercased. Sessions without a
# matching file get nothing. Runs on start and on resume, so a restart picks up edits.
set -u
[ -n "${HC_TERMINAL_ID:-}" ] || exit 0
name=$(timeout 3 hc get "$HC_TERMINAL_ID" --json 2>/dev/null | jq -r '.name // empty' 2>/dev/null)
[ -n "$name" ] || exit 0
name=$(printf '%s' "$name" | sed -E 's/-[0-9a-f]{4}$//' | tr '[:upper:]' '[:lower:]')
case "$name" in */*|.*|"") exit 0 ;; esac
for life in "$HOME/work/life" "$HOME/projects/life"; do
  f="$life/agents/$name.md"
  if [ -f "$f" ]; then
    printf 'You are the long-running agent "%s". Your standing instructions are in %s (git, private life repo). They follow below as of this start. To change them, edit that file and commit it with a pathspec; see agents/README.md.\n\n' "$name" "$f"
    cat "$f"
    exit 0
  fi
done
exit 0
