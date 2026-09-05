#!/usr/bin/env bash
# auto-stage-bench-history.sh — PostToolUse hook for Write/Edit.
#
# When .bench-history/*.latest.json is written or edited, automatically
# `git add` it. The "pass-over-pass gate is a file" rule depends on the
# bench-history file being committed atomically with the source change;
# this hook prevents the common forget-to-stage bug.
#
# Hook contract:
#   stdin:  JSON {tool_name, tool_input: {file_path: "..."}}
#   exit 0: always (telemetry-only; failures are logged but not blocking)

set -euo pipefail

# --- Read stdin --------------------------------------------------------------
TOOL_INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "[gauntlet/auto-stage-bench-history] jq not installed; skipping." >&2
  exit 0
fi

TOOL_NAME="$(printf '%s' "$TOOL_INPUT" | jq -r '.tool_name // empty')"
case "$TOOL_NAME" in
  Write|Edit|MultiEdit) ;;
  *) exit 0 ;;
esac

FILE_PATH="$(printf '%s' "$TOOL_INPUT" | jq -r '.tool_input.file_path // ""')"
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# --- Match .bench-history/*.latest.json -------------------------------------
# Normalize to absolute path if relative.
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")"
fi

case "$FILE_PATH" in
  */.bench-history/*.latest.json) ;;
  *) exit 0 ;;
esac

# --- Locate the enclosing git repo ------------------------------------------
REPO_ROOT="$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "[gauntlet/auto-stage-bench-history] $FILE_PATH is not inside a git repo; skipping stage." >&2
  exit 0
fi

if [[ ! -f "$FILE_PATH" ]]; then
  echo "[gauntlet/auto-stage-bench-history] $FILE_PATH was deleted, not staging." >&2
  exit 0
fi

# --- Stage it ----------------------------------------------------------------
# We use --intent-to-add semantics implicitly by running plain `git add`;
# this is safe because the file is JSON (no executables, no large blobs that
# would surprise the user).
if git -C "$REPO_ROOT" add -- "$FILE_PATH" 2>/dev/null; then
  echo "[gauntlet/auto-stage-bench-history] staged $FILE_PATH" >&2
else
  echo "[gauntlet/auto-stage-bench-history] failed to stage $FILE_PATH (continuing)" >&2
fi

# Optional telemetry: append to workspace's events log if discoverable.
PARENT_DIR="$(dirname "$REPO_ROOT")"
WORKSPACE="$(ls -d "$PARENT_DIR"/*__gauntlet_workspace 2>/dev/null | head -1 || true)"
if [[ -n "$WORKSPACE" && -d "$WORKSPACE" ]]; then
  mkdir -p "$WORKSPACE/telemetry"
  printf '{"event":"bench_history_staged","file":"%s","timestamp":"%s"}\n' \
    "$FILE_PATH" "$(date -Iseconds)" >> "$WORKSPACE/telemetry/events.jsonl" || true
fi

exit 0
