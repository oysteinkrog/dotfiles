#!/usr/bin/env bash
# PreToolUse hook for Bash. Blocks raw `git worktree add`, `git clone`, and
# `gh repo clone` invocations whose TARGET resolves under a grove-managed
# work_dir (from ~/.config/grove/repos.json, falling back to /c/work/desktop),
# because worktrees/clones created by hand bypass grove's registry and pile
# up as sprawl that `grove list`/`grove status`/`grove gc` never learn about.
#
# Command-position-anchored matching (see grove-worktree-detect.py, which
# splits on real shell separators found in a quote/heredoc-blanked copy of
# the command before tokenizing) means a quoted MENTION of these phrases
# inside some other command's argument -- e.g. a `br update --description`
# documenting this very hook -- is never blocked; only genuine invocations
# are. Target resolution (git -C, URL-derived clone dirs, last-non-flag-arg
# heuristic) also lives there; test matrix in grove-worktree-guard.test.py.
# Run the tests after any change to either file.
#
# Targets under WORK_DIR/.scratch/ are allowed -- grove new/fork --ephemeral
# and raw scratch clones both land there, and grove gc TTL-sweeps it.
#
# If the target can't be determined AND cwd is already inside a guarded
# work_dir, this fails CLOSED (blocks) rather than silently letting an
# unregistered worktree/clone through. Every other parse failure of this
# hook's own inputs fails OPEN (allows), same as the rest of this repo's
# hooks -- a bug here should never be able to block an unrelated command.
#
# Residual risk (accepted, not solved by this hook): this only runs inside
# the Claude Code harness. Other harnesses configured at the desktop repo
# root (cursor.mcp.json, gemini.mcp.json, opencode.json) have no PreToolUse
# hook and can create raw worktrees/clones under a guarded work_dir
# unchecked; grove gc is the backstop for those. Session scratchpads live
# under /tmp/claude-*/, outside any guarded work_dir by construction, so no
# extra carve-out is needed for them here.
#
# To bypass intentionally, append ` # noqa: grove-worktree` to the command.

set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

payload=$(cat)
command=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""')

# Cheap pre-filter: skip invoking python for the vast majority of Bash calls
# that mention neither keyword anywhere. Correctness (anchoring, quoting)
# is entirely the python detector's job; this is purely a perf shortcut so
# every unrelated Bash call doesn't pay for a subprocess spawn.
if ! printf '%s' "$command" | grep -qE 'worktree|clone'; then
  exit 0
fi

if [[ "$command" == *"noqa: grove-worktree"* ]]; then
  exit 0
fi

# Guarded work_dirs from grove's own registry, falling back to the one
# directory known to be guarded if the registry is missing/unparseable.
workdirs=$(jq -r '.repos[]?.work_dir // empty' ~/.config/grove/repos.json 2>/dev/null || true)
if [[ -z ${workdirs:-} ]]; then
  workdirs="/c/work/desktop"
fi

target=$(GROVE_GUARD_COMMAND="$command" GROVE_GUARD_CWD="$cwd" GROVE_GUARD_WORKDIRS="$workdirs" python3 "$here/grove-worktree-detect.py" 2>/dev/null || true)

if [[ -z ${target:-} ]]; then
  exit 0
fi

cat >&2 <<EOF
BLOCKED: raw worktree/clone creation under a grove-managed directory.

Target: $target

This bypasses grove's registry, so \`grove list\`, \`grove status\`, and
\`grove gc\` never learn about the new directory and it becomes untracked
sprawl.

Use instead:
  grove new TAG --issue N     durable work, tracked in the registry
  grove fork SRC NEW          fork an existing project's branch
  grove new --ephemeral       scratch lane under .scratch/, TTL-swept

If you genuinely need a raw worktree/clone (you ARE grove, or this is
outside any grove-managed repo), append \` # noqa: grove-worktree\` to the
command.
EOF

exit 2
