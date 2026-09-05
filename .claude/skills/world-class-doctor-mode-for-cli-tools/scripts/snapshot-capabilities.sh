#!/usr/bin/env bash
set -euo pipefail
# snapshot-capabilities.sh — golden-artifact regression for `<tool> doctor capabilities --json`.
#
# The capabilities document IS the contract. Any change to it is contract
# drift. This script captures the current contract to a snapshot file on
# first run; on subsequent runs, diffs current output against the snapshot.
# Any drift fails CI — agents reading older capabilities now mismatch.
#
# Usage:
#   snapshot-capabilities.sh <tool> <snapshot-path> [--update]
#
# Args:
#   <tool>             binary name
#   <snapshot-path>    path to snap file (e.g., baseline/capabilities.snap.json)
#   --update           write current output as the new snapshot (use after
#                      an intentional contract bump)
#
# Comparison is canonicalized: jq -S sorts object keys; volatile fields
# (tool_version, doctor_version) are stripped from the diff so a routine
# version bump doesn't look like contract drift.
#
# Exit codes:
#   0 — snapshot exists and matches; OR --update wrote the new snapshot.
#   1 — snapshot exists and DIFFERS (drift detected).
#   2 — first-run; no prior snapshot. Wrote a new one. (Caller may treat as info.)
#   64 — usage error.
#   66 — capabilities query failed.

usage() {
    echo "usage: snapshot-capabilities.sh <tool> <snapshot-path> [--update]" >&2
}

tool="${1:-}"
snapshot="${2:-}"
mode="check"
if [ "${3:-}" = "--update" ]; then
    mode="update"
fi

if [ -z "$tool" ] || [ -z "$snapshot" ]; then
    usage; exit 64
fi

# Resolve the binary like discover-cli.sh does.
bin_invocation=""
if command -v "$tool" >/dev/null 2>&1; then
    bin_invocation="$tool"
elif [ -x "./$tool" ]; then
    bin_invocation="./$tool"
elif [ -x "./target/release/$tool" ]; then
    bin_invocation="./target/release/$tool"
elif [ -x "./target/debug/$tool" ]; then
    bin_invocation="./target/debug/$tool"
else
    echo "snapshot-capabilities: $tool not found (PATH or target/)" >&2
    exit 66
fi

current=$("$bin_invocation" doctor capabilities --json 2>/dev/null) \
    || { echo "snapshot-capabilities: '$bin_invocation doctor capabilities --json' failed" >&2; exit 66; }

# Canonicalize: drop volatile fields, sort keys. Volatile fields are those
# expected to change between releases or hosts and that don't constitute
# contract drift. Schemas (run_artifact_schema, report_schema) are URLs
# that SHOULD be checked — if they change, that IS a contract event.
canon() {
    jq -S 'del(.tool_version, .doctor_version, .platform)'
}
if ! current_canon=$(echo "$current" | canon 2>&1); then
    echo "snapshot-capabilities: failed to canonicalize current capabilities (jq error):" >&2
    echo "$current_canon" >&2
    exit 66
fi

mkdir -p "$(dirname "$snapshot")"

if [ "$mode" = "update" ]; then
    echo "$current_canon" > "$snapshot"
    echo "snapshot-capabilities: wrote $snapshot (--update)" >&2
    exit 0
fi

if [ ! -f "$snapshot" ]; then
    echo "$current_canon" > "$snapshot"
    echo "snapshot-capabilities: first run; wrote new snapshot at $snapshot (rc=2)" >&2
    exit 2
fi

# Read prior snapshot through canon so old snapshots written before the
# canonicalization rules changed still compare apples-to-apples. If the
# snapshot is corrupted, error explicitly — don't silently fall back to
# raw bytes (the prior code did `|| cat "$snapshot"` which would compare
# raw vs canonical, producing spurious diffs).
if ! prior_canon=$(canon < "$snapshot" 2>&1); then
    echo "snapshot-capabilities: prior snapshot at $snapshot is malformed JSON" >&2
    echo "  (re-run with --update to overwrite, or restore the snapshot manually)" >&2
    echo "$prior_canon" >&2
    exit 1
fi

if [ "$current_canon" = "$prior_canon" ]; then
    echo "snapshot-capabilities: OK (capabilities match snapshot at $snapshot)" >&2
    exit 0
fi

echo "FAIL: snapshot-capabilities: capabilities drift detected vs $snapshot" >&2
echo "(re-run with --update if the drift was intentional and the contract version was bumped)" >&2
echo "" >&2
diff <(echo "$prior_canon") <(echo "$current_canon") >&2 || true
exit 1
