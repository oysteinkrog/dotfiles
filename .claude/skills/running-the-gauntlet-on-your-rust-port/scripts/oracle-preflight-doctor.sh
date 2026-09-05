#!/usr/bin/env bash
# oracle-preflight-doctor.sh — Run the oracle preflight checks per the project
# class detected by detect-project-class.sh.
#
# USAGE:
#   oracle-preflight-doctor.sh <target-project-path> [--workspace <dir>]
#                              [--class <class>]
#
# OUTPUT (stdout): JSON envelope:
#   {certifying: bool, aggregate_outcome: "green"|"yellow"|"red", failures: [...],
#    remediation: [...]}
#
# EXIT CODES:
#   0 — green (certifying: true)
#   1 — yellow (some checks soft-failed)
#   2 — red (at least one hard precondition failed)
#   3 — usage error
#
# IDEMPOTENT: read-only against target; writes only the report file.

set -euo pipefail

usage() {
  sed -n '2,18p' "$0"
  exit "${1:-3}"
}

TARGET=""
WORKSPACE=""
CLASS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2;;
    --class)     CLASS="$2"; shift 2;;
    -h|--help)   usage 0;;
    *)
      if [ -z "$TARGET" ]; then TARGET="$1"
      else echo "Unexpected arg: $1" >&2; usage
      fi
      shift;;
  esac
done

[ -n "$TARGET" ] || usage
[ -d "$TARGET" ] || { echo "ERROR: $TARGET not a directory" >&2; exit 3; }

# Try to load class from phase0 file if not provided.
if [ -z "$CLASS" ] && [ -n "$WORKSPACE" ] && [ -f "$WORKSPACE/phase0_project_class.json" ]; then
  CLASS="$(grep -oE '"detected_class": *"[^"]+"' "$WORKSPACE/phase0_project_class.json" | head -1 | sed 's/.*"detected_class": *"//; s/".*//')"
fi
CLASS="${CLASS:-UNKNOWN}"

# Failures accumulator: each "$severity|$message|$remediation"
FAILURES=()
add_fail() { FAILURES+=("$1|$2|$3"); }

# Try to find version contract.
VERSION_CONTRACT=""
if [ -n "$WORKSPACE" ]; then
  VERSION_CONTRACT="$(find "$WORKSPACE" -maxdepth 2 -name '*_version_contract.toml' | head -1 || true)"
fi
if [ -z "$VERSION_CONTRACT" ]; then
  add_fail "red" "version contract missing" "run init-workspace.sh"
fi

case "$CLASS" in
  SQL-class)
    if ! command -v sqlite3 >/dev/null 2>&1; then
      add_fail "red" "sqlite3 oracle binary not on PATH" "install sqlite3 (apt install sqlite3 / brew install sqlite)"
    else
      v="$(sqlite3 --version 2>&1 | awk '{print $1}')"
      echo "sqlite3 oracle: $v" >&2
      if [ -n "$VERSION_CONTRACT" ] && grep -q 'version' "$VERSION_CONTRACT"; then
        want="$(grep -E '^version' "$VERSION_CONTRACT" | head -1 | sed 's/.*= *"//; s/".*//')"
        if [ -n "$want" ] && [ "$want" != "UNPINNED" ] && [ "$v" != "$want" ]; then
          add_fail "yellow" "sqlite3 version $v != pinned $want" "rebuild oracle binary at pinned version or update contract"
        fi
      fi
    fi
    ;;
  RESP-class)
    if ! command -v redis-server >/dev/null 2>&1; then
      add_fail "red" "redis-server oracle binary not on PATH" "install redis-server matching contract version"
    fi
    ;;
  Numerical-Python-class|ML-System-class)
    if ! command -v python3 >/dev/null 2>&1; then
      add_fail "red" "python3 not on PATH" "install python3 + uv"
    fi
    if command -v python3 >/dev/null 2>&1; then
      python3 -c 'import numpy' 2>/dev/null || add_fail "yellow" "python numpy not importable" "pip install numpy"
      [ "$CLASS" = "ML-System-class" ] && {
        python3 -c 'import torch' 2>/dev/null || add_fail "yellow" "python torch not importable" "pip install torch"
      }
    fi
    ;;
  HTTP-Protocol-class)
    if ! command -v python3 >/dev/null 2>&1; then
      add_fail "red" "python3 not on PATH" "install python3 (oracle replay needs it)"
    fi
    ;;
  *)
    add_fail "yellow" "unknown project class ($CLASS)" "run detect-project-class.sh first"
    ;;
esac

# ---- Identity strings + fixture cardinality ------------------------------
if [ -n "$VERSION_CONTRACT" ]; then
  grep -q 'subject_identity_label' "$VERSION_CONTRACT" || \
    add_fail "yellow" "subject_identity_label missing in version contract" "fill in [engine_identity]"
  grep -q 'reference_identity_label' "$VERSION_CONTRACT" || \
    add_fail "yellow" "reference_identity_label missing in version contract" "fill in [engine_identity]"
  grep -q 'manifest_sha256' "$VERSION_CONTRACT" || \
    add_fail "yellow" "fixture_corpus.manifest_sha256 missing" "compute SHA-256 of fixture manifest"
fi

# ---- Aggregate verdict --------------------------------------------------
RED=0; YELLOW=0
# Guard with length check; `"${FAILURES[@]:-}"` expands to a single empty
# string when the array is empty, producing a bogus iteration.
if [ "${#FAILURES[@]}" -gt 0 ]; then
  for f in "${FAILURES[@]}"; do
    sev="${f%%|*}"
    [ "$sev" = "red" ] && RED=$((RED+1))
    [ "$sev" = "yellow" ] && YELLOW=$((YELLOW+1))
  done
fi

OUTCOME="green"
CERTIFYING=true
EXIT=0
if [ "$RED" -gt 0 ]; then OUTCOME="red"; CERTIFYING=false; EXIT=2
elif [ "$YELLOW" -gt 0 ]; then OUTCOME="yellow"; CERTIFYING=false; EXIT=1
fi

REPORT_FILE=""
if [ -n "$WORKSPACE" ]; then
  mkdir -p "$WORKSPACE"
  REPORT_FILE="$WORKSPACE/phase0_oracle_preflight.json"
fi

emit_json() {
  printf '{\n'
  printf '  "schema_version": "gauntlet.oracle_preflight_report.v1",\n'
  printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "target": "%s",\n' "$TARGET"
  printf '  "project_class": "%s",\n' "$CLASS"
  printf '  "certifying": %s,\n' "$CERTIFYING"
  printf '  "aggregate_outcome": "%s",\n' "$OUTCOME"
  # Note: `"${FAILURES[@]:-}"` would expand to a single empty string when the
  # array is empty, producing a bogus entry. Guard with the length check first.
  n="${#FAILURES[@]}"
  printf '  "failures": ['
  if [ "$n" -gt 0 ]; then
    printf '\n'
    i=0
    for f in "${FAILURES[@]}"; do
      sev="${f%%|*}"; rest="${f#*|}"
      msg="${rest%%|*}"
      sep=","; [ $((i+1)) -eq "$n" ] && sep=""
      msg_esc="$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      printf '    {"severity":"%s","message":"%s"}%s\n' "$sev" "$msg_esc" "$sep"
      i=$((i+1))
    done
    printf '  '
  fi
  printf '],\n'

  printf '  "remediation": ['
  if [ "$n" -gt 0 ]; then
    printf '\n'
    i=0
    for f in "${FAILURES[@]}"; do
      rest="${f#*|}"; rem="${rest#*|}"
      sep=","; [ $((i+1)) -eq "$n" ] && sep=""
      rem_esc="$(printf '%s' "$rem" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      printf '    "%s"%s\n' "$rem_esc" "$sep"
      i=$((i+1))
    done
    printf '  '
  fi
  printf ']\n'
  printf '}\n'
}

emit_json | tee "${REPORT_FILE:-/dev/null}" >/dev/stdout
exit "$EXIT"
