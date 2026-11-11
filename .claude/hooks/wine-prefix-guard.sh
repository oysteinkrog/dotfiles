#!/usr/bin/env bash
# PreToolUse hook for Bash. Blocks a direct Wine call (wine, wineboot, winetricks and the like)
# that would run in a MotionCatalyst Wine prefix setup-prefix.sh did not make, or run MC itself
# in the bare ~/.wine. Detection and the reasons are in wine-prefix-detect.py; tests in
# wine-prefix-guard.test.py. Append `# noqa: wine-prefix` to bypass, only for work on a prefix
# itself.

set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

payload=$(cat)
command=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""')

case "$command" in *'# noqa: wine-prefix'*) exit 0 ;; esac
case "$command" in *wine*|*msiexec*|*regedit*) ;; *) exit 0 ;; esac

reason=$(WINE_GUARD_COMMAND="$command" WINE_GUARD_CWD="$cwd" python3 "$here/wine-prefix-detect.py" 2>/dev/null || true)
[ -n "$reason" ] || exit 0

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Wine prefix not set up for MotionCatalyst: " + $reason + ". MC in such a prefix runs on wined3d without DXVK or the .NET runtime, and its faults look like MC bugs. Run MC through tools/wine (run-mc.sh, headless-mc.sh, run-tests.sh), which use a copy of the shared prefix, or fix the prefix with tools/wine/setup-prefix.sh. Bypass with `# noqa: wine-prefix` only for work on the prefix itself.")
  }
}'
