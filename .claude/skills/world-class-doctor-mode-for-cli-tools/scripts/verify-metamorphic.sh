#!/usr/bin/env bash
set -euo pipefail
# verify-metamorphic.sh — Phase 5 metamorphic-relation test.
#
# A detector is metamorphically sound if running it on a state, then on the
# state the detector itself REPORTS, yields the same finding set. Concretely:
# detect(state) == detect(detect(state)) — idempotence under repeated detection.
# A detector that violates this is non-deterministic or stateful; either is a
# bug per Axiom 1 (detect-then-fix; detector is pure).
#
# We don't need the per-FM specifics — we just run `<tool> doctor diagnose
# --json --only=<fm_id>` twice in a row against the corrupted fixture, and
# diff the .findings arrays. Identical → metamorphic-sound. Different →
# detector has hidden state.
#
# Usage:
#   verify-metamorphic.sh <fm_id> [<tool>] [<fixture_root>]
#
# Args mirror verify-undo.sh / verify-idempotence.sh / etc.
#
# Exit codes:
#   0 — pass (detector is metamorphically sound)
#   1 — fail (two diagnoses produced different finding sets)
#   64 — usage error

usage() {
    echo "usage: verify-metamorphic.sh <fm_id> [<tool>] [<fixture_root>]" >&2
}

fm_id="${1:-}"
tool="${2:-${TOOL:-}}"
fixture_root="${3:-tests/doctor_fixtures}"

if [ -z "$fm_id" ]; then
    usage; exit 64
fi
if [ -z "$tool" ]; then
    echo "verify-metamorphic: provide <tool> as arg 2 or set TOOL env" >&2
    exit 64
fi

corrupt_sh="$fixture_root/$fm_id/corrupt.sh"
[ -x "$corrupt_sh" ] || { echo "verify-metamorphic: $corrupt_sh missing" >&2; exit 1; }

sandbox=$(mktemp -d)
trap 'echo "verify-metamorphic: sandbox at $sandbox" >&2' EXIT

"$corrupt_sh" "$sandbox" >&2

artifacts="$sandbox/.verify-metamorphic"
mkdir -p "$artifacts"

# Run diagnose twice. Capture only the .findings array (deterministic field).
out1="$artifacts/diag1.json"
out2="$artifacts/diag2.json"

rc1=0
( cd "$sandbox" && "$tool" doctor diagnose --json --only="$fm_id" > "$out1" 2>/dev/null ) || rc1=$?
case "$rc1" in
    0|1) ;;
    *)
        echo "verify-metamorphic: first diagnose unexpected exit=$rc1" >&2
        cat "$out1" >&2
        exit 1
        ;;
esac

# Detector should be pure: second invocation against the SAME state should
# return the same findings. No --fix between runs.
rc2=0
( cd "$sandbox" && "$tool" doctor diagnose --json --only="$fm_id" > "$out2" 2>/dev/null ) || rc2=$?
case "$rc2" in
    0|1) ;;
    *)
        echo "verify-metamorphic: second diagnose unexpected exit=$rc2" >&2
        cat "$out2" >&2
        exit 1
        ;;
esac

# Compare .findings arrays. We canonicalize: sort by .id, drop fields known
# to legitimately differ between runs (run_id, started_at, finished_at,
# duration_ms, evidence-time fields).
canon() {
    jq -S '
        (.findings // [])
        | sort_by(.id // "")
        | map(del(.run_id, .started_at, .finished_at, .duration_ms, .evidence.timestamp))
    ' "$1"
}

canon1=$(canon "$out1")
canon2=$(canon "$out2")

if [ "$canon1" = "$canon2" ]; then
    echo "PASS: verify-metamorphic.sh fm=$fm_id (detect twice → same findings)" >&2
    trap - EXIT
    exit 0
fi

echo "FAIL: verify-metamorphic.sh fm=$fm_id (detect twice produced different findings)" >&2
echo "first diagnose:" >&2
echo "$canon1" >&2
echo "second diagnose:" >&2
echo "$canon2" >&2
echo "diff:" >&2
diff <(printf '%s' "$canon1") <(printf '%s' "$canon2") >&2 || true
exit 1
