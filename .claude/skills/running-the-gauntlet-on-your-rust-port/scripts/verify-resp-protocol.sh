#!/usr/bin/env bash
# verify-resp-protocol.sh — (RESP-class only) drives a known-good RESP transcript
# against the port and the reference redis-server in parallel, asserts byte-identical
# wire output.
#
# USAGE:
#   verify-resp-protocol.sh <target-port> <workspace> [--transcript <path>] [--command <name>]

set -euo pipefail

usage() { sed -n '2,8p' "$0"; exit "${1:-2}"; }

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage 0
fi

[ $# -ge 2 ] || usage
TARGET="$1"
WORKSPACE="$2"
shift 2

TRANSCRIPT=""
COMMAND_NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --transcript) TRANSCRIPT="$2"; shift 2;;
    --command) COMMAND_NAME="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

CLASS=$(jq -r .detected_class "$WORKSPACE/phase0_project_class.json" 2>/dev/null || echo "Unknown")
case "$CLASS" in
  RESP-class|RESP) ;;
  *) echo "verify-resp-protocol.sh skipped: not RESP-class (class=$CLASS)"; exit 0 ;;
esac

REDIS_VERSION=$(grep '^version' "$WORKSPACE/docs/contracts/redis_version_contract.toml" 2>/dev/null | cut -d'"' -f2 || echo "")
[ -z "$REDIS_VERSION" ] && { echo "ERROR: no redis_version_contract.toml" >&2; exit 2; }

# Verify reference redis-server is the pinned version.
REF_VERSION=$(redis-server --version 2>/dev/null | grep -oE 'v=[0-9.]+' | head -1 | cut -d= -f2)
if [ -z "$REF_VERSION" ]; then
  echo "ERROR: redis-server not on PATH" >&2; exit 2
fi
if [ "$REF_VERSION" != "$REDIS_VERSION" ]; then
  echo "ERROR: contract pins $REDIS_VERSION but PATH has $REF_VERSION" >&2; exit 2
fi

# Default transcript = the standard test corpus.
if [ -z "$TRANSCRIPT" ] && [ -n "$COMMAND_NAME" ] && [ -f "$WORKSPACE/tests/fixtures/resp_transcripts/${COMMAND_NAME}.resp" ]; then
  TRANSCRIPT="$WORKSPACE/tests/fixtures/resp_transcripts/${COMMAND_NAME}.resp"
fi
[ -z "$TRANSCRIPT" ] && TRANSCRIPT="$WORKSPACE/tests/fixtures/resp_transcripts/standard.resp"
[ ! -f "$TRANSCRIPT" ] && { echo "ERROR: transcript not found: $TRANSCRIPT" >&2; exit 2; }

# Locate the port's redis-compatible binary.
PORT_BIN=""
for candidate in "$TARGET/target/release-perf/franken-redis-server" \
                 "$TARGET/target/release/franken-redis-server"; do
  [ -x "$candidate" ] && { PORT_BIN="$candidate"; break; }
done
[ -z "$PORT_BIN" ] && { echo "ERROR: port binary not found; build with 'cargo build --profile release-perf'" >&2; exit 2; }

# Start reference + port on distinct ports, capture wire output.
REF_PORT=16379
PORT_PORT=16380
REF_OUT=$(mktemp)
PORT_OUT=$(mktemp)
REF_PID=""
PORT_PID=""

cleanup() {
  if [ -n "$REF_PID" ]; then
    kill "$REF_PID" 2>/dev/null || true
  fi
  if [ -n "$PORT_PID" ]; then
    kill "$PORT_PID" 2>/dev/null || true
  fi
  echo "[cleanup] retained response captures: $REF_OUT $PORT_OUT" >&2
}
trap cleanup EXIT

echo "[start] reference redis-server on :$REF_PORT"
redis-server --port $REF_PORT --daemonize no --bind 127.0.0.1 --save "" --logfile "" --appendonly no &
REF_PID=$!

echo "[start] port redis-server on :$PORT_PORT"
"$PORT_BIN" --port $PORT_PORT --bind 127.0.0.1 &
PORT_PID=$!

# Wait for both to be ready.
sleep 1
redis-cli -p $REF_PORT ping >/dev/null
redis-cli -p $PORT_PORT ping >/dev/null

# Drive the transcript through both, capture raw RESP3 wire output.
echo "[drive] driving transcript: $TRANSCRIPT"
nc -w 3 127.0.0.1 $REF_PORT  < "$TRANSCRIPT" > "$REF_OUT" || true
nc -w 3 127.0.0.1 $PORT_PORT < "$TRANSCRIPT" > "$PORT_OUT" || true

# Diff.
DIFF_OUT="$WORKSPACE/resp_protocol_diff.txt"
if diff -u "$REF_OUT" "$PORT_OUT" > "$DIFF_OUT"; then
  echo "[verify] byte-identical RESP output ✓"
  STATUS="pass"
else
  echo "[verify] DIVERGENT RESP output ✗"
  echo "        see: $DIFF_OUT"
  STATUS="fail"
fi

# Summary.
cat > "$WORKSPACE/resp_protocol_summary.md" <<MD
# RESP Protocol Verification

- Reference redis: $REF_VERSION
- Port:            $PORT_BIN
- Transcript:      $TRANSCRIPT
- Command filter:  ${COMMAND_NAME:-<none>}
- Status:          $STATUS
- Diff:            $DIFF_OUT

MD

[ "$STATUS" = "pass" ] || exit 1
