#!/usr/bin/env bash
# check-cass-mined-before-perf.sh — PreToolUse hook for Bash.
#
# Enforces the AGENTS.md mandate: before running a perf-affecting workload
# (cargo bench, samply, flamegraph, hyperfine, comprehensive-bench,
# mt-mvcc-bench), the cass-miner must have produced a recent findings file
# within the gauntlet workspace.
#
# Hook contract:
#   stdin:  JSON {tool_name, tool_input: {command: "..."}}
#   exit 0: allow (not a perf command, or mine is fresh)
#   exit 2: block (perf command without fresh mine)

set -euo pipefail

# --- Read stdin --------------------------------------------------------------
TOOL_INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "[gauntlet/check-cass-mined] jq not installed; cannot inspect tool input. Passing through." >&2
  exit 0
fi

TOOL_NAME="$(printf '%s' "$TOOL_INPUT" | jq -r '.tool_name // empty')"
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

BASH_CMD="$(printf '%s' "$TOOL_INPUT" | jq -r '.tool_input.command // ""')"
if [[ -z "$BASH_CMD" ]]; then
  exit 0
fi

# --- Match perf-affecting commands ------------------------------------------
# Regex covers the common perf invocations. Word-boundary anchored so that
# `cargo bench-pretty-print` (a hypothetical non-bench tool) doesn't trip.
PERF_REGEX='(^|[^[:alnum:]_-])(cargo[[:space:]]+bench|samply|flamegraph|hyperfine|comprehensive-bench|mt-mvcc-bench)([^[:alnum:]_-]|$)'

if ! [[ "$BASH_CMD" =~ $PERF_REGEX ]]; then
  exit 0
fi

# --- Locate the gauntlet workspace ------------------------------------------
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PARENT_DIR="$(dirname "$PROJECT_DIR")"
WORKSPACE="$(ls -d "$PARENT_DIR"/*__gauntlet_workspace 2>/dev/null | head -1 || true)"

if [[ -z "$WORKSPACE" || ! -d "$WORKSPACE" ]]; then
  # No gauntlet workspace: this hook does not apply.
  exit 0
fi

# --- Check freshness of cass_findings ---------------------------------------
# Acceptable: any cass_findings_<run_id>.jsonl modified within the last 4 hours.
FRESH_THRESHOLD_SECS=14400  # 4 hours
CUTOFF_EPOCH="$(($(date +%s) - FRESH_THRESHOLD_SECS))"

RECENT_MINE=""
if [[ -d "$WORKSPACE/cass_findings" ]]; then
  RECENT_MINE="$(find "$WORKSPACE/cass_findings" -maxdepth 2 -name 'cass_findings_*.jsonl' -type f \
    -newermt "@${CUTOFF_EPOCH}" 2>/dev/null | head -1 || true)"
fi

# Also accept the cross-machine aggregate.
if [[ -z "$RECENT_MINE" && -f "$WORKSPACE/cass_findings/aggregate.jsonl" ]]; then
  MTIME="$(stat -c %Y "$WORKSPACE/cass_findings/aggregate.jsonl" 2>/dev/null || echo 0)"
  if [[ "$MTIME" -ge "$CUTOFF_EPOCH" ]]; then
    RECENT_MINE="$WORKSPACE/cass_findings/aggregate.jsonl"
  fi
fi

if [[ -n "$RECENT_MINE" ]]; then
  exit 0
fi

# --- Block + explain --------------------------------------------------------
cat >&2 <<EOF
[gauntlet/check-cass-mined] BLOCKED: perf-affecting command issued without a fresh cass mine.

Command: ${BASH_CMD}
Workspace: ${WORKSPACE}
Expected: ${WORKSPACE}/cass_findings/cass_findings_<run_id>.jsonl modified within last 4 hours.

The AGENTS.md mandate requires mining 60 days of cass session history for
prior closures on the workload before running a perf-affecting command.

Run first:
  ${WORKSPACE}/scripts/mine-ledger.sh "${WORKSPACE}" --terms "<workload>"
  ${WORKSPACE}/scripts/mine-cass-cross-machine.sh ${WORKSPACE}

If cass is unavailable, RECORD A BLOCKER ENTRY rather than silently skipping
the mine — see references/methodology/CASS-MINING.md.

See: references/cookbook/perf-regression-triage.md § Scripts (the mine step
runs BEFORE any bench invocation).
EOF
exit 2
