#!/usr/bin/env bash
# detect-project-class.sh — Heuristic detection of project class from Cargo
# manifests + crate structure.
#
# USAGE:
#   detect-project-class.sh <target-project-path> [--workspace <dir>]
#
# OUTPUTS (stdout): human-readable verdict (e.g., "Detected: SQL-class ...").
# OUTPUT FILE: <workspace>/phase0_project_class.json
#
# EXIT CODES:
#   0 — class detected with confidence >= 0.8
#   1 — ambiguous / low-confidence / no class detected (confidence < 0.8)
#   2 — usage error
#
# IDEMPOTENT: re-runs overwrite phase0_project_class.json.

set -euo pipefail

usage() {
  sed -n '2,16p' "$0"
  exit "${1:-2}"
}

TARGET=""
WORKSPACE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2;;
    -h|--help)   usage 0;;
    *)
      if [ -z "$TARGET" ]; then TARGET="$1"
      else echo "Unexpected arg: $1" >&2; usage
      fi
      shift;;
  esac
done

[ -n "$TARGET" ] || usage
[ -d "$TARGET" ] || { echo "ERROR: $TARGET not a directory" >&2; exit 2; }

# Gather all Cargo.toml content (workspace root + crates).
manifest_blob=""
if [ -f "$TARGET/Cargo.toml" ]; then
  manifest_blob+="$(cat "$TARGET/Cargo.toml")"$'\n'
fi
while IFS= read -r -d '' f; do
  manifest_blob+="$(cat "$f")"$'\n'
done < <(find "$TARGET" -maxdepth 4 -name Cargo.toml -not -path "*/target/*" -print0 2>/dev/null || true)

has_dep() {
  local dep="$1" escaped
  escaped="$(printf '%s' "$dep" | sed 's/[][\\.^$*+?{}()|]/\\&/g')"
  grep -qE "(^|[\"[:space:]])${escaped}([\"[:space:]=]|$)" <<<"$manifest_blob"
}

# ---- Score each class ----------------------------------------------------
declare -A SCORE
SCORE[SQL-class]=0
SCORE[RESP-class]=0
SCORE[Numerical-Python-class]=0
SCORE[ML-System-class]=0
SCORE[HTTP-Protocol-class]=0

# SQL class
has_dep libsqlite3-sys && SCORE[SQL-class]=$((SCORE[SQL-class]+3))
has_dep rusqlite       && SCORE[SQL-class]=$((SCORE[SQL-class]+2))
has_dep sqlite3        && SCORE[SQL-class]=$((SCORE[SQL-class]+1))

# RESP class
has_dep redis              && SCORE[RESP-class]=$((SCORE[RESP-class]+2))
has_dep fr-conformance     && SCORE[RESP-class]=$((SCORE[RESP-class]+3))
has_dep redis-protocol     && SCORE[RESP-class]=$((SCORE[RESP-class]+2))
grep -q 'frankenredis\|resp_value\|RespValue' <<<"$manifest_blob" 2>/dev/null \
  && SCORE[RESP-class]=$((SCORE[RESP-class]+1))

# PyO3 — could be numerical OR ml-system; decide via secondary deps.
has_pyo3=0
has_dep pyo3 && has_pyo3=1
has_dep numpy && [ "$has_pyo3" -eq 1 ] && SCORE[Numerical-Python-class]=$((SCORE[Numerical-Python-class]+3))
has_dep numpy-rs && SCORE[Numerical-Python-class]=$((SCORE[Numerical-Python-class]+2))
grep -q 'numpy\|ndarray' <<<"$manifest_blob" 2>/dev/null && [ "$has_pyo3" -eq 1 ] \
  && SCORE[Numerical-Python-class]=$((SCORE[Numerical-Python-class]+1))

# ML-system class
for ml_dep in tch torch-sys burn candle tract; do
  has_dep "$ml_dep" && [ "$has_pyo3" -eq 1 ] && SCORE[ML-System-class]=$((SCORE[ML-System-class]+3))
  has_dep "$ml_dep" && SCORE[ML-System-class]=$((SCORE[ML-System-class]+2))
done

# HTTP-Protocol class
for http_dep in axum actix-web hyper warp poem rocket; do
  has_dep "$http_dep" && SCORE[HTTP-Protocol-class]=$((SCORE[HTTP-Protocol-class]+2))
done
has_dep tower-http && SCORE[HTTP-Protocol-class]=$((SCORE[HTTP-Protocol-class]+1))

# ---- Find winner --------------------------------------------------------
WINNER=""
MAX=0
for class in "${!SCORE[@]}"; do
  if [ "${SCORE[$class]}" -gt "$MAX" ]; then
    MAX="${SCORE[$class]}"
    WINNER="$class"
  fi
done

TOTAL=0
for v in "${SCORE[@]}"; do TOTAL=$((TOTAL+v)); done
CONFIDENCE="0.0"
if [ "$TOTAL" -gt 0 ]; then
  # Two-decimal confidence: winner / total.
  CONFIDENCE="$(awk -v w="$MAX" -v t="$TOTAL" 'BEGIN { printf "%.2f", w/t }')"
fi

if [ -z "$WINNER" ] || [ "$MAX" -eq 0 ]; then
  WINNER="UNKNOWN"
  CONFIDENCE="0.0"
fi

# ---- Reference + sibling map -------------------------------------------
case "$WINNER" in
  SQL-class)               REFERENCE="sqlite";  SIBLING="frankensqlite";;
  RESP-class)              REFERENCE="redis";   SIBLING="frankenredis";;
  Numerical-Python-class)  REFERENCE="numpy";   SIBLING="franken_numpy";;
  ML-System-class)         REFERENCE="pytorch"; SIBLING="frankentorch";;
  HTTP-Protocol-class)     REFERENCE="fastapi"; SIBLING="fastapi_rust";;
  *)                       REFERENCE="UNKNOWN"; SIBLING="UNKNOWN";;
esac

echo "Detected: $WINNER (confidence=$CONFIDENCE) reference=$REFERENCE sibling=$SIBLING"

# ---- Emit JSON ---------------------------------------------------------
if [ -n "$WORKSPACE" ]; then
  mkdir -p "$WORKSPACE"
  OUT="$WORKSPACE/phase0_project_class.json"
  {
    printf '{\n'
    printf '  "schema_version": "gauntlet.phase0_project_class.v1",\n'
    printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "target": "%s",\n' "$TARGET"
    printf '  "detected_class": "%s",\n' "$WINNER"
    printf '  "confidence": %s,\n' "$CONFIDENCE"
    printf '  "matching_reference": "%s",\n' "$REFERENCE"
    printf '  "sibling_project_example": "%s",\n' "$SIBLING"
    printf '  "scores": {\n'
    keys=("${!SCORE[@]}")
    for i in "${!keys[@]}"; do
      k="${keys[$i]}"
      sep=","; [ "$i" -eq $((${#keys[@]}-1)) ] && sep=""
      printf '    "%s": %d%s\n' "$k" "${SCORE[$k]}" "$sep"
    done
    printf '  }\n'
    printf '}\n'
  } > "$OUT"
  echo "Wrote $OUT"
fi

awk -v c="$CONFIDENCE" 'BEGIN { exit (c+0 >= 0.8 ? 0 : 1) }'
