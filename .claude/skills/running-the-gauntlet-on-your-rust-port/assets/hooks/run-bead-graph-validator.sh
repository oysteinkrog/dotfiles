#!/usr/bin/env bash
# run-bead-graph-validator.sh — PreToolUse hook for Bash.
#
# Before `git commit`, run scripts/bead-graph-validator.sh. The validator
# checks:
#   - br dep cycles is empty
#   - bv --robot-insights | jq '(.Cycles // []) | length == 0' passes
#   - every remediation bead has test + bench + doc dependencies
#
# If any check fails, exit 2 to block the commit.
#
# Hook contract:
#   stdin:  JSON {tool_name, tool_input: {command: "..."}}
#   exit 0: allow (not a commit, no workspace, or validator clean)
#   exit 2: block (validator failed)

set -euo pipefail

# --- Read stdin --------------------------------------------------------------
TOOL_INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "[gauntlet/run-bead-graph-validator] jq not installed; passing through." >&2
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

# --- Match `git commit` (but not `git commit-tree` or other variants) -------
# Allow common forms: `git commit`, `git commit -m ...`, `git -C path commit`, etc.
if ! [[ "$BASH_CMD" =~ (^|[^[:alnum:]_-])git([[:space:]]+-[CcS][[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$) ]]; then
  exit 0
fi
# Exclude `git commit-tree` (plumbing) — the above check accepts trailing
# space or end-of-string after "commit", so "commit-tree" wouldn't match.

# --- Locate the gauntlet workspace ------------------------------------------
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PARENT_DIR="$(dirname "$PROJECT_DIR")"
WORKSPACE="$(ls -d "$PARENT_DIR"/*__gauntlet_workspace 2>/dev/null | head -1 || true)"

if [[ -z "$WORKSPACE" || ! -d "$WORKSPACE" ]]; then
  # No gauntlet workspace: nothing to validate.
  exit 0
fi

VALIDATOR="$WORKSPACE/scripts/bead-graph-validator.sh"
if [[ ! -x "$VALIDATOR" ]]; then
  echo "[gauntlet/run-bead-graph-validator] validator $VALIDATOR not found or not executable; skipping." >&2
  exit 0
fi

# --- Run the validator ------------------------------------------------------
set +e
VALIDATOR_OUTPUT="$("$VALIDATOR" "$PROJECT_DIR" --output-root "$WORKSPACE" 2>&1)"
VALIDATOR_EXIT="$?"
set -e

if [[ "$VALIDATOR_EXIT" -eq 0 ]]; then
  exit 0
fi

# --- Block + surface validator output ---------------------------------------
cat >&2 <<EOF
[gauntlet/run-bead-graph-validator] BLOCKED: bead-graph validator failed.

Validator: ${VALIDATOR}
Exit code: ${VALIDATOR_EXIT}

Validator output:
$(printf '%s\n' "$VALIDATOR_OUTPUT" | sed 's/^/  /')

Likely causes:
  - br dep cycles non-empty
  - bv --robot-insights | jq '(.Cycles // []) | length == 0' failed
  - A remediation bead is missing test/bench/doc dependency

Fix in Phase 13 polish round (bead-polisher subagent) before re-committing.

See: references/cookbook/perf-regression-triage.md § Beads (dep requirements)
See: references/orchestration/BEADS-HANDOFF.md
EOF
exit 2
