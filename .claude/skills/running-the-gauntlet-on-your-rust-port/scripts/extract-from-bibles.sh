#!/usr/bin/env bash
# extract-from-bibles.sh — re-extracts key sections from the two FrankenSQLite
# bibles (CC.md + CODEX.md) into the project workspace, for offline reference
# when working on a host without the bibles available.
#
# USAGE:
#   extract-from-bibles.sh <workspace> [--bibles-path <dir>]
#
# Extracts:
#   - PART VII vocabulary glossary → <workspace>/bible_excerpts/vocab.md
#   - PART XIII 10 optimizations    → <workspace>/bible_excerpts/optimizations.md
#   - PART XVI math toolkit         → <workspace>/bible_excerpts/math_toolkit.md
#   - PART XXIII proprietary skills → <workspace>/bible_excerpts/skills_map.md
#   - PART XXIV sibling adoption    → <workspace>/bible_excerpts/sibling_status.md
#   - CODEX negative-ledger / cross-project synthesis excerpts

set -euo pipefail

usage() { sed -n '2,15p' "$0"; exit "${1:-2}"; }

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage 0
fi

[ $# -gt 0 ] || usage
WORKSPACE="$1"
shift

BIBLES_PATH="/data/projects/frankensqlite"
while [ $# -gt 0 ]; do
  case "$1" in
    --bibles-path) BIBLES_PATH="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

CC_BIBLE="$BIBLES_PATH/COMPREHENSIVE_BREAKDOWN_OF_FRANKENSQLITE_PERFORMANCE_AND_CONFORMANCE_ASSURANCE_PROCESS__CC.md"
CODEX_BIBLE="$BIBLES_PATH/COMPREHENSIVE_BREAKDOWN_OF_FRANKENSQLITE_PERFORMANCE_AND_CONFORMANCE_ASSURANCE_PROCESS__CODEX.md"

if [ ! -f "$CC_BIBLE" ]; then
  echo "ERROR: CC bible not found at $CC_BIBLE" >&2
  echo "Pass --bibles-path to point at the directory containing the bibles."
  exit 2
fi

EXC="$WORKSPACE/bible_excerpts"
mkdir -p "$EXC"

# Helper: extract lines between two markdown headers from a file. The bibles are
# living docs; missing headers must fail loudly rather than producing empty
# "successful" excerpts.
extract_section() {
  local file="$1" start="$2" end="$3" out="$4" label="$5"
  set +e
  awk -v start="$start" -v end="$end" '
    BEGIN { found = 0; capture = 0 }
    $0 ~ start { found = 1; capture = 1; print; next }
    capture {
      if ($0 ~ end) { exit }
      print
    }
    END { if (!found) { exit 42 } }
  ' "$file" > "$out"
  local status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    if [ "$status" -eq 42 ]; then
      echo "ERROR: start header not found for $label in $file" >&2
      echo "       start regex: $start" >&2
    else
      echo "ERROR: failed extracting $label from $file" >&2
    fi
    exit 1
  fi
  local lines
  lines=$(wc -l < "$out")
  if [ "$lines" -eq 0 ]; then
    echo "ERROR: $label extracted 0 lines from $file" >&2
    echo "       start regex: $start" >&2
    echo "       end regex:   $end" >&2
    exit 1
  fi
  echo "  - $(basename "$out"): $lines lines extracted"
}

echo "[extract] from CC.md"
extract_section "$CC_BIBLE" '^# PART VII([[:space:]]|$)'   '^# PART VIII([[:space:]]|$)'  "$EXC/vocab.md" "CC PART VII vocabulary"
extract_section "$CC_BIBLE" '^# PART XIII([[:space:]]|$)'  '^# PART XIV([[:space:]]|$)'   "$EXC/optimizations.md" "CC PART XIII optimization patterns"
extract_section "$CC_BIBLE" '^# PART XVI([[:space:]]|$)'   '^# PART XVII([[:space:]]|$)'  "$EXC/math_toolkit.md" "CC PART XVI mathematical toolkit"
extract_section "$CC_BIBLE" '^# PART XXIII([[:space:]]|$)' '^# PART XXIV([[:space:]]|$)' "$EXC/skills_map.md" "CC PART XXIII skill map"
extract_section "$CC_BIBLE" '^# PART XXIV([[:space:]]|$)'  '^# PART XXV([[:space:]]|$)'  "$EXC/sibling_status.md" "CC PART XXIV sibling adoption"

if [ -f "$CODEX_BIBLE" ]; then
  echo "[extract] from CODEX.md"
  extract_section "$CODEX_BIBLE" '^## 10[.] ' '^## 11[.] ' "$EXC/codex_ledger_mandate.md" "CODEX section 10 negative evidence ledger"
  extract_section "$CODEX_BIBLE" '^### 16[.]20 ' '^### 16[.]25 ' "$EXC/codex_vocab.md" "CODEX sections 16.20-16.24 evidence vocabulary"
  extract_section "$CODEX_BIBLE" '^## 14[.] ' '^## 17[.] ' "$EXC/codex_per_class.md" "CODEX sections 14-16 per-class synthesis"
fi

# Render index.
cat > "$EXC/INDEX.md" <<MD
# Bible Excerpts — Offline Reference

These excerpts were extracted from the two FrankenSQLite bibles at:
- CC:    $CC_BIBLE
- CODEX: $CODEX_BIBLE

Re-extracted at $(date -u +%Y-%m-%dT%H:%M:%SZ).

## Files

- [vocab.md](vocab.md) — PART VII vocabulary glossary
- [optimizations.md](optimizations.md) — PART XIII the 10 winning optimization patterns
- [math_toolkit.md](math_toolkit.md) — PART XVI mathematical toolkit (32 rows)
- [skills_map.md](skills_map.md) — PART XXIII proprietary skill enumeration
- [sibling_status.md](sibling_status.md) — PART XXIV per-sibling adoption status
$( [ -f "$EXC/codex_ledger_mandate.md" ] && echo "- [codex_ledger_mandate.md](codex_ledger_mandate.md) — CODEX §10 negative-evidence ledger and cass-mining mandate" )
$( [ -f "$EXC/codex_vocab.md" ] && echo "- [codex_vocab.md](codex_vocab.md) — CODEX §§16.20–16.24 evidence-routed primitive / anti-repeat vocabulary" )
$( [ -f "$EXC/codex_per_class.md" ] && echo "- [codex_per_class.md](codex_per_class.md) — CODEX §§14–16 per-class and cross-project synthesis" )

## How to use
These are reference excerpts only; the pattern library
(references/patterns/00-INDEX.md) is the canonical operational source.
Use these excerpts to verify a quote, confirm a number, or check the original
context when the pattern library's summary feels insufficient.

MD

echo
echo "Excerpts at: $EXC/"
echo "Index:       $EXC/INDEX.md"
