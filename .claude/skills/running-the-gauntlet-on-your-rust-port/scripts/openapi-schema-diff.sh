#!/usr/bin/env bash
# openapi-schema-diff.sh — (HTTP-Protocol-class only) diffs the port's emitted
# OpenAPI schema against the reference framework's schema. Asserts byte-identical
# (after canonical re-serialization for key-order independence).
#
# USAGE:
#   openapi-schema-diff.sh <target-port> <workspace> [--reference-schema <path>] [--endpoint <path>]

set -euo pipefail

usage() { sed -n '2,8p' "$0"; exit "${1:-2}"; }

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage 0
fi

[ $# -ge 2 ] || usage
TARGET="$1"
WORKSPACE="$2"
shift 2

REF_SCHEMA=""
ENDPOINT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --reference-schema) REF_SCHEMA="$2"; shift 2;;
    --endpoint) ENDPOINT="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

CLASS=$(jq -r .detected_class "$WORKSPACE/phase0_project_class.json" 2>/dev/null || echo "Unknown")
case "$CLASS" in
  HTTP-Protocol-class|HTTP-Protocol|HTTP) ;;
  *) echo "openapi-schema-diff.sh skipped: not HTTP-Protocol-class (class=$CLASS)"; exit 0 ;;
esac

# Emit the port's OpenAPI schema.
PORT_BIN=""
for candidate in "$TARGET/target/release-perf/openapi-emit" \
                 "$TARGET/target/release/openapi-emit"; do
  [ -x "$candidate" ] && { PORT_BIN="$candidate"; break; }
done
[ -z "$PORT_BIN" ] && { echo "ERROR: openapi-emit binary not found; build with 'cargo build --profile release-perf --bin openapi-emit'" >&2; exit 2; }

PORT_SCHEMA_RAW="$WORKSPACE/openapi_port.raw.json"
PORT_SCHEMA="$WORKSPACE/openapi_port.canonical.json"
REF_SCHEMA_RAW="${REF_SCHEMA:-$WORKSPACE/openapi_reference.raw.json}"
REF_SCHEMA_CANON="$WORKSPACE/openapi_reference.canonical.json"

echo "[emit] port schema → $PORT_SCHEMA_RAW"
"$PORT_BIN" --pretty > "$PORT_SCHEMA_RAW"

if [ -z "$REF_SCHEMA" ]; then
  echo "[emit] reference schema → $REF_SCHEMA_RAW (via reference framework)"
  # Per python-reference-bridger; the bridger emits a Python helper that calls
  # `fastapi.FastAPI.openapi()` and writes the result.
  python3 -c "
from importlib import import_module
import json, sys
# The port's harness registers a get_reference_openapi() callable.
ref = import_module('reference_openapi_shim').get_reference_openapi()
json.dump(ref, sys.stdout, indent=2)
" > "$REF_SCHEMA_RAW"
fi

# Canonicalize both sides: sort keys, normalize whitespace, strip generated
# fields (info.title, info.version) that aren't behaviorally meaningful.
canonicalize() {
  python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
# Strip non-behavioral fields.
if 'info' in data:
    for k in ('title', 'version', 'description', 'termsOfService', 'contact', 'license'):
        data['info'].pop(k, None)
json.dump(data, open(sys.argv[2], 'w'), indent=2, sort_keys=True)
" "$1" "$2"
}

canonicalize "$PORT_SCHEMA_RAW" "$PORT_SCHEMA"
canonicalize "$REF_SCHEMA_RAW" "$REF_SCHEMA_CANON"

DIFF_OUT="$WORKSPACE/openapi_schema_diff.txt"
if diff -u "$REF_SCHEMA_CANON" "$PORT_SCHEMA" > "$DIFF_OUT"; then
  echo "[verify] OpenAPI schema byte-identical (canonical) ✓"
  STATUS="pass"
else
  DIFF_LINES=$(wc -l < "$DIFF_OUT")
  echo "[verify] OpenAPI schema DIVERGENT ($DIFF_LINES diff lines)"
  STATUS="fail"
fi

cat > "$WORKSPACE/openapi_schema_summary.md" <<MD
# OpenAPI Schema Diff

- port schema:        $PORT_SCHEMA
- reference schema:   $REF_SCHEMA_CANON
- diff:               $DIFF_OUT
- endpoint filter:    ${ENDPOINT:-<none>}
- status:             $STATUS

MD

[ "$STATUS" = "pass" ] || exit 1
