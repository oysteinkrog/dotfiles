#!/usr/bin/env bash
# PreToolUse hook for Bash. Blocks four commands that ~/.claude/CLAUDE.md
# lists as hard "never" rules for agents:
#
#   bv (no --robot-* flag)   opens the TUI and hangs the agent.
#   am doctor fix            rewrites every MCP config back to port 8765 with
#                            a bearer token, which breaks the agent-mail setup.
#   cass index --semantic    mixes vector provenance in the index.
#   cass-gpu index           hits a memory regression in the custom GPU build.
#
# Allowed near-misses: `bv --robot-*`, `bv --help`, `am doctor` without fix,
# plain `cass index`, other cass-gpu subcommands, and --help on any of them.
#
# Detection lives in harness-rules-detect.py, which reuses the shell
# segmentation in grove-worktree-detect.py, so a quoted mention inside another
# command's argument is never blocked. Test matrix in
# harness-rules-guard.test.py. Run the tests after any change to either file.
#
# Every failure of this hook's own parsing fails OPEN (allows the command).

set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

payload=$(cat)
command=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)

# Cheap pre-filter so most Bash calls never spawn python.
if ! printf '%s' "$command" | grep -qE '(^|[^[:alnum:]_.-])(bv|am|cass|cass-gpu)([^[:alnum:]_.-]|$)'; then
  exit 0
fi

hit=$(HARNESS_GUARD_COMMAND="$command" python3 "$here/harness-rules-detect.py" 2>/dev/null || true)

if [[ -z ${hit:-} ]]; then
  exit 0
fi

kind=${hit%%$'\t'*}
detail=${hit#*$'\t'}

case $kind in
  bv_tui)
    cat >&2 <<EOF
BLOCKED: \`bv\` without a --robot-* flag.

Command: $detail

Without --robot-* it opens the TUI, and the agent hangs waiting for input.

Use instead:
  bv --robot-next           the single best next bead
  bv --robot-triage         ranked triage as JSON
  bv --help                 the full list of --robot-* flags
  br ready / br show <id>   the plain CLI
EOF
    ;;
  am_doctor_fix)
    cat >&2 <<EOF
BLOCKED: \`am doctor fix\`.

Command: $detail

It rewrites every MCP config back to port 8765 with a bearer token, which
breaks the local agent-mail setup on port 4809.

Use instead: load the \`agent-mail-ops\` skill, which owns repair of the
service and its SQLite store. Health check:
  curl -s http://127.0.0.1:4809/health
EOF
    ;;
  cass_semantic)
    cat >&2 <<EOF
BLOCKED: \`cass index --semantic\`.

Command: $detail

It mixes vector provenance in the index.

Use instead: plain \`cass index\`. For setup and recovery, see
~/.dotfiles/docs/cass-setup.md or load the \`cass\` skill.
EOF
    ;;
  cass_gpu_index)
    cat >&2 <<EOF
BLOCKED: \`cass-gpu index\`.

Command: $detail

The custom GPU build hits a memory regression when indexing.

Use instead: plain \`cass index\` (the stock build). For setup and recovery,
see ~/.dotfiles/docs/cass-setup.md or load the \`cass\` skill.
EOF
    ;;
  *)
    exit 0
    ;;
esac

exit 2
