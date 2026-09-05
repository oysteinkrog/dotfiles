#!/usr/bin/env bash
# verify-concurrent-mode-guard.sh — PostToolUse hook for Write/Edit.
#
# When a tests/artifacts/perf/**/concurrent_mode_default_guard.txt file is
# written or edited, assert the file contains CONCURRENT_MODE_DEFAULT=true.
#
# Rationale: silent reversion of concurrent mode means "MVCC perf win"
# was actually running serial, invalidating the kept-perf claim. The
# guard file exists exactly to catch this. If the guard is wrong, the
# kept perf is a lie; we block the write.
#
# Hook contract:
#   stdin:  JSON {tool_name, tool_input: {file_path: "..."}}
#   exit 0: allow (not a guard file, or guard correct)
#   exit 2: block (guard incorrect)

set -euo pipefail

# --- Read stdin --------------------------------------------------------------
TOOL_INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "[gauntlet/verify-concurrent-mode-guard] jq not installed; passing through." >&2
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

# Normalize to absolute path.
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")"
fi

# --- Match tests/artifacts/perf/**/concurrent_mode_default_guard.txt --------
case "$FILE_PATH" in
  */tests/artifacts/perf/*/concurrent_mode_default_guard.txt) ;;
  *) exit 0 ;;
esac

# --- Verify guard contents --------------------------------------------------
if [[ ! -f "$FILE_PATH" ]]; then
  # PostToolUse on a non-existent file is unusual; treat as warning.
  echo "[gauntlet/verify-concurrent-mode-guard] WARNING: $FILE_PATH does not exist after Write/Edit." >&2
  exit 0
fi

EXPECTED='CONCURRENT_MODE_DEFAULT=true'

if grep -qF "$EXPECTED" "$FILE_PATH"; then
  echo "[gauntlet/verify-concurrent-mode-guard] OK: $FILE_PATH contains $EXPECTED" >&2
  exit 0
fi

# --- Block + explain --------------------------------------------------------
cat >&2 <<EOF
[gauntlet/verify-concurrent-mode-guard] BLOCKED: guard file does not assert concurrent mode.

File: ${FILE_PATH}
Expected line: ${EXPECTED}
Actual contents:
$(sed 's/^/  /' "$FILE_PATH" | head -20)

The concurrent_mode_default_guard.txt file is the standing assertion that
every perf artifact in this lane was produced with concurrent mode enabled.
If this file is wrong, every kept-perf claim relying on this artifact lane
becomes a lie ("we measured concurrent perf" — but actually serial).

Either:
1. Restore '${EXPECTED}' to the file (the change here is wrong), OR
2. Open a bead 'concurrent-mode-default-flipped' with a proof-pack showing
   the gauntlet is now intentionally running serial for this lane, AND
   re-baseline every perf number in this lane (revisit each retry-condition
   predicate).

See: references/patterns/175-CONCURRENT-MODE-GUARD.md
See: SKILL.md § Keep-Gate Rules § concurrent_mode_default_guard.txt
EOF
exit 2
