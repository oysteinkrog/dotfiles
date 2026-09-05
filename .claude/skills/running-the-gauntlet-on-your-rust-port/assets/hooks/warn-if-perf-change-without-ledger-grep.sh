#!/usr/bin/env bash
# warn-if-perf-change-without-ledger-grep.sh — UserPromptSubmit hook.
#
# When the user's prompt mentions perf-related keywords, prepend a system
# reminder asking the agent to run cass-miner first. This is informational
# (the hook never blocks), but the reminder lands in the agent's context
# at prompt-submission time so the agent sees it before composing a plan.
#
# Hook contract:
#   stdin:  JSON {prompt: "..."}
#   exit 0: always (informational only)
#   stdout: reminder text that becomes part of the agent's context

set -euo pipefail

# --- Read stdin --------------------------------------------------------------
USER_INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  # No jq: silently pass through (no reminder).
  exit 0
fi

USER_PROMPT="$(printf '%s' "$USER_INPUT" | jq -r '.prompt // ""')"

if [[ -z "$USER_PROMPT" ]]; then
  exit 0
fi

# --- Match perf-related keywords --------------------------------------------
# Case-insensitive; word-boundary anchored where possible.
# Keywords: perf, optimization, hot path, hot-path, bench, throughput,
# latency, micro-lever, MT8, profile.
PERF_REGEX='\b(perf(ormance)?|optimiz(e|ation)|hot.path|bench(mark)?|throughput|latency|micro.lever|MT8|profile|profiling|flamegraph|samply|hyperfine)\b'

if ! printf '%s' "$USER_PROMPT" | grep -qiE "$PERF_REGEX"; then
  exit 0
fi

# --- Emit the reminder to stdout (becomes agent context) --------------------
# Locate workspace so we can recommend the right script paths.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PARENT_DIR="$(dirname "$PROJECT_DIR")"
WORKSPACE="$(ls -d "$PARENT_DIR"/*__gauntlet_workspace 2>/dev/null | head -1 || true)"

cat <<EOF
[gauntlet reminder — perf-related prompt detected]

Before touching any perf-affecting code, the AGENTS.md mandate requires:

  1. Grep docs/progress/perf-negative-results.md for prior closures on this hotspot.
  2. Mine 60 days of cass session history across local/css/csd/ts1/ts2:
$(if [[ -n "$WORKSPACE" ]]; then
    echo "       ${WORKSPACE}/scripts/mine-cass-cross-machine.sh \"${WORKSPACE}\""
  else
    echo "       <workspace>/scripts/mine-cass-cross-machine.sh <workspace>"
  fi)
  3. Check recent commits:
       git log --since='60 days ago' --grep -iE 'perf|optimiz|hot.path|bench|ratchet'

If cass is unavailable or the ledger is reserved, RECORD A BLOCKER ENTRY rather
than silently skipping the mine.

If you intend to bench: also confirm bench history is current vs the candidate
change, and that the change is run under the release-perf profile (never --release).

See: references/methodology/CASS-MINING.md
See: references/cookbook/perf-regression-triage.md
See: references/methodology/KEEP-GATE-RULES.md
EOF

exit 0
