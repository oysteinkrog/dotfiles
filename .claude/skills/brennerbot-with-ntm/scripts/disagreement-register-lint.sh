#!/usr/bin/env bash
# disagreement-register-lint.sh — Verify disagreement_register.md has the required entry count.
#
# Usage: disagreement-register-lint.sh [--workspace=<path>] [--min-entries=N]
#
# Default min_entries: (N choose 2) where N = count of distillations/by_*.md files.
# For 3 model families, default = 3.

set -uo pipefail

WORKSPACE="."
MIN_ENTRIES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace=*) WORKSPACE="${1#*=}" ;;
    # Accept both hyphen and underscore — pipeline yaml callers use snake_case keys
    # (e.g., `min_entries:`) while shell callers use the documented hyphen form.
    --min-entries=*|--min_entries=*) MIN_ENTRIES="${1#*=}" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

REGISTER="$WORKSPACE/distillations/disagreement_register.md"

if [ ! -f "$REGISTER" ]; then
  echo "VIOLATION: disagreement_register.md missing at $REGISTER" >&2
  echo "Phase 6 cannot exit (per F-603)." >&2
  exit 1
fi

# Default min_entries from per-family distillation count
if [ -z "$MIN_ENTRIES" ]; then
  N=$(find "$WORKSPACE/distillations" -maxdepth 1 -name 'by_*.md' 2>/dev/null | wc -l)
  if [ "$N" -lt 2 ]; then
    echo "Only $N per-family distillation(s); disagreement register needs ≥0 entries (Solo tier — degraded)"
    exit 0
  fi
  # (N choose 2) = N*(N-1)/2
  MIN_ENTRIES=$((N * (N - 1) / 2))
fi

# Count D-NNN entries.
# NB: don't use `grep -c ... || echo 0` here — when the file exists with 0 matches,
# grep -c outputs "0" + exit 1, then the fallback adds another "0", giving "0\n0"
# which corrupts the arithmetic comparison below. File existence is already
# guarded above, so grep -c always emits a single integer line on its own.
ENTRY_COUNT=$(grep -cE '^## D-[0-9]+' "$REGISTER" 2>/dev/null) || true
ENTRY_COUNT=${ENTRY_COUNT:-0}

echo "Disagreement register lint:"
echo "  File: $REGISTER"
echo "  Entries (D-NNN): $ENTRY_COUNT"
echo "  Required: $MIN_ENTRIES"

if [ "$ENTRY_COUNT" -lt "$MIN_ENTRIES" ]; then
  echo "VIOLATION: $ENTRY_COUNT < $MIN_ENTRIES required entries (per F-601 / F-603)" >&2
  echo "Re-dispatch MO-06b-meta-synthesize.md with explicit 'find at least one disagreement per pair' directive." >&2
  exit 1
fi

# Verify each entry cites ≥2 distillation files. Track cite_count between headings.
ORPHAN_ENTRIES=$(awk '
  /^## D-[0-9]+/ {
    if (NR > 1 && cite_count < 2) print prev_d
    prev_d = $0
    cite_count = 0
    next
  }
  /by_[a-z]+\.md/ { cite_count++ }
  END {
    if (prev_d != "" && cite_count < 2) print prev_d
  }
' "$REGISTER" | head -5)

if [ -n "$ORPHAN_ENTRIES" ]; then
  echo "VIOLATION: entries lack citations to ≥2 distillation files:" >&2
  echo "$ORPHAN_ENTRIES" >&2
  exit 1
fi

echo "  → lint clean"
exit 0
