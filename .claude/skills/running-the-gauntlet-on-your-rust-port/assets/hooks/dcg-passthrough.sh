#!/usr/bin/env bash
# dcg-passthrough.sh — PreToolUse hook for Bash.
#
# Delegates to the /dcg (Destructive Command Guard) skill's hook if installed,
# else passes through (exit 0). This is the minimal-friction install: if a user
# already has /dcg wired, our gauntlet install doesn't double-block; if they
# don't, this hook is a no-op so we don't claim safety we don't enforce.
#
# Hook contract:
#   stdin:  JSON {tool_name, tool_input: {command: "..."}}
#   exit 0: allow
#   exit 2: block (stderr is shown to the agent)
#   other:  warning (logged but allowed)

set -euo pipefail

# --- Read stdin --------------------------------------------------------------
TOOL_INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "[gauntlet/dcg-passthrough] jq not installed; cannot inspect tool input. Passing through." >&2
  exit 0
fi

TOOL_NAME="$(printf '%s' "$TOOL_INPUT" | jq -r '.tool_name // empty')"
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

# --- Delegate to /dcg if installed ------------------------------------------
DCG_HOOK_CANDIDATES=(
  "${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/hooks/dcg.sh"
  "$HOME/.claude/skills/dcg/hooks/dcg-pretooluse.sh"
  "$HOME/.claude/hooks/dcg.sh"
)

for HOOK in "${DCG_HOOK_CANDIDATES[@]}"; do
  if [[ -x "$HOOK" ]]; then
    # Re-emit stdin to the delegated hook and forward its exit code.
    printf '%s' "$TOOL_INPUT" | "$HOOK"
    exit $?
  fi
done

# --- No /dcg installed: pass through ----------------------------------------
# We intentionally do NOT add inline dangerous-command detection here; that
# would silently diverge from /dcg semantics and confuse users who later install
# /dcg properly.
exit 0
