#!/usr/bin/env bash
# run-ubs-on-deliverables.sh — Run /ubs on any code in deliverables/scripts/ or deliverables/code/.
#
# Phase 7 hard-block: F-703 fires if this exits non-zero. Phase 8 cannot proceed until clean.
#
# Usage: run-ubs-on-deliverables.sh [--workspace=<path>]

set -uo pipefail

WORKSPACE="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace=*) WORKSPACE="${1#*=}" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

WORKSPACE_INPUT="$WORKSPACE"
if ! WORKSPACE="$(cd "$WORKSPACE_INPUT" 2>/dev/null && pwd)"; then
  echo "workspace not accessible: $WORKSPACE_INPUT" >&2
  exit 1
fi

DELIVERABLES_CODE_DIR="$WORKSPACE/deliverables/scripts"
DELIVERABLES_CODE_DIR2="$WORKSPACE/deliverables/code"

if ! command -v ubs >/dev/null 2>&1; then
  echo "Warning: ubs not installed. Falling back to language-specific linters." >&2
  # Fall back to whatever is available
  for d in "$DELIVERABLES_CODE_DIR" "$DELIVERABLES_CODE_DIR2"; do
    [ -d "$d" ] || continue
    # Bash
    for f in "$d"/*.sh; do
      [ -f "$f" ] || continue
      bash -n "$f" || { echo "FAIL: bash syntax: $f" >&2; exit 1; }
    done
    # Python
    if command -v ruff >/dev/null 2>&1; then
      py_files=()
      for f in "$d"/*.py; do
        [ -f "$f" ] || continue
        py_files+=("$f")
      done
      if [ ${#py_files[@]} -gt 0 ]; then
        ruff check "${py_files[@]}" || { echo "FAIL: ruff check: $d" >&2; exit 1; }
      fi
    fi
  done
  echo "Linter fallback: no critical errors detected (best-effort)." >&2
  exit 0
fi

# ubs available — use it
FILES=()
for d in "$DELIVERABLES_CODE_DIR" "$DELIVERABLES_CODE_DIR2"; do
  [ -d "$d" ] || continue
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(find "$d" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.rs' -o -name '*.go' \) 2>/dev/null)
done

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No code in deliverables/scripts/ or deliverables/code/. ubs check skipped (vacuously clean)." >&2
  exit 0
fi

echo "Running ubs on ${#FILES[@]} file(s)..." >&2
ubs "${FILES[@]}"
RC=$?

if [ $RC -ne 0 ]; then
  echo "F-703: ubs reported issues. Phase 8 blocked until clean." >&2
  exit 1
fi

echo "ubs clean." >&2
exit 0
