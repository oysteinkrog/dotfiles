#!/usr/bin/env bash
set -euo pipefail
# verify-cross-fm.sh — Phase 5.5 cross-FM interaction test.
#
# Phase 5's per-FM safety harness verifies each fixer in isolation. Real
# bugs often involve cross-FM interactions: fixing FM-A invalidates a
# precondition of FM-B's fixer, so running both in the same pass produces
# a state where neither detector returns None even though both fixers
# "succeeded." This is a known sharp edge.
#
# This script tests an ORDERED PAIR (fm-a, fm-b):
#   1. Spin up a fixture for both: corrupt with both `corrupt.sh` scripts.
#   2. Run `<tool> doctor --fix --json --only=<fm-a>,<fm-b>`.
#   3. Re-run `<tool> doctor diagnose --json --only=<fm-a>,<fm-b>`; assert
#      both findings are gone.
#   4. Run `<tool> doctor undo <run-id>`; assert state restored to
#      byte-identical to the corrupted state.
#
# Usage:
#   verify-cross-fm.sh <fm_a> <fm_b> [<tool>] [<fixture_root>]
#
# Args mirror verify-undo.sh / verify-idempotence.sh / etc.
#
# Exit codes:
#   0 — pass (both FMs fixed cleanly, no cross-interaction)
#   1 — fail (post-fix detect returned a finding, OR undo not byte-identical)
#   64 — usage error
#   66 — missing fixtures

usage() {
    echo "usage: verify-cross-fm.sh <fm_a> <fm_b> [<tool>] [<fixture_root>]" >&2
}

fm_a="${1:-}"
fm_b="${2:-}"
tool="${3:-${TOOL:-}}"
fixture_root="${4:-tests/doctor_fixtures}"

if [ -z "$fm_a" ] || [ -z "$fm_b" ]; then
    usage; exit 64
fi
if [ -z "$tool" ]; then
    echo "verify-cross-fm: provide <tool> as arg 3 or set TOOL env" >&2
    exit 64
fi
case "$tool" in
    */*)
        tool_dir=$(cd "$(dirname "$tool")" && pwd) || {
            echo "verify-cross-fm: tool directory missing for $tool" >&2
            exit 66
        }
        tool="$tool_dir/$(basename "$tool")"
        [ -x "$tool" ] || { echo "verify-cross-fm: $tool is not executable" >&2; exit 66; }
        ;;
esac

corrupt_a="$fixture_root/$fm_a/corrupt.sh"
corrupt_b="$fixture_root/$fm_b/corrupt.sh"
[ -x "$corrupt_a" ] || { echo "verify-cross-fm: $corrupt_a missing" >&2; exit 66; }
[ -x "$corrupt_b" ] || { echo "verify-cross-fm: $corrupt_b missing" >&2; exit 66; }

sandbox=$(mktemp -d)
artifacts=$(mktemp -d)
mkdir -p "$artifacts"
trap 'echo "verify-cross-fm: sandbox at $sandbox" >&2; echo "verify-cross-fm: artifacts at $artifacts" >&2' EXIT

# Step 1: corrupt both. Order matters — apply A first, then B; some FMs
# stack only in one order. Per-FM corrupt.sh scripts MUST be idempotent
# enough that running two in sequence produces a useful combined state.
"$corrupt_a" "$sandbox" >&2
"$corrupt_b" "$sandbox" >&2

# Snapshot the corrupted state for the undo byte-identity check.
corrupted_snapshot="$artifacts/corrupted-snapshot"
mkdir -p "$corrupted_snapshot"
cp -a "$sandbox/." "$corrupted_snapshot/"

# Step 2: run --fix for both FMs.
fix_out="$artifacts/fix.json"
fix_err="$artifacts/fix.stderr"
fix_rc=0
( cd "$sandbox" && "$tool" doctor --fix --json --only="$fm_a,$fm_b" > "$fix_out" 2> "$fix_err" ) || fix_rc=$?
case "$fix_rc" in
    0|2) ;;
    *)
        echo "FAIL: verify-cross-fm fm_a=$fm_a fm_b=$fm_b: --fix exit=$fix_rc (expected 0 or 2)" >&2
        cat "$fix_out" >&2
        cat "$fix_err" >&2
        exit 1
        ;;
esac

# Step 3: post-fix diagnose; both detectors should return None.
diag_out="$artifacts/diag-post.json"
diag_err="$artifacts/diag-post.stderr"
diag_rc=0
( cd "$sandbox" && "$tool" doctor diagnose --json --only="$fm_a,$fm_b" > "$diag_out" 2> "$diag_err" ) || diag_rc=$?
case "$diag_rc" in
    0) ;;
    *)
        echo "FAIL: verify-cross-fm fm_a=$fm_a fm_b=$fm_b: post-fix diagnose exit=$diag_rc (expected 0)" >&2
        cat "$diag_out" >&2
        cat "$diag_err" >&2
        # Show which findings remain; this is the diagnostic signature for
        # cross-FM interaction.
        echo "remaining findings:" >&2
        jq -r '.findings // [] | .[] | "  \(.id) (\(.severity)): \(.title // "?")"' "$diag_out" >&2 || true
        exit 1
        ;;
esac

# Step 4: undo. Extract run-id from fix output.
run_id=$(jq -r '.run_id // empty' "$fix_out" 2>/dev/null || echo "")
if [ -z "$run_id" ]; then
    echo "FAIL: verify-cross-fm: --fix output didn't include run_id" >&2
    exit 1
fi

undo_rc=0
( cd "$sandbox" && "$tool" doctor undo "$run_id" >&2 ) || undo_rc=$?
case "$undo_rc" in
    0) ;;
    *)
        echo "FAIL: verify-cross-fm: undo exit=$undo_rc (expected 0)" >&2
        exit 1
        ;;
esac

# Step 5: byte-identity check vs corrupted snapshot.
# Use diff -r --no-dereference; ignore the .doctor/ directory itself
# (which has new run-dirs from fix + undo).
if diff -r --no-dereference "$corrupted_snapshot" "$sandbox" -x .doctor >/dev/null 2>&1; then
    echo "PASS: verify-cross-fm fm_a=$fm_a fm_b=$fm_b (fix → diagnose-clean → undo → byte-identical)" >&2
    trap - EXIT
    exit 0
fi

echo "FAIL: verify-cross-fm: undo did not restore byte-identical state" >&2
echo "diff:" >&2
# `|| true` masks both diff's exit-1 (files differ — expected here) AND
# `head`'s SIGPIPE-induced 141 when the diff is long enough that head
# closes stdin early. Without it, set -euo pipefail propagates the SIGPIPE
# code, replacing the intended FAIL exit-1 with 141.
diff -r --no-dereference "$corrupted_snapshot" "$sandbox" -x .doctor 2>&1 | head -20 >&2 || true
exit 1
