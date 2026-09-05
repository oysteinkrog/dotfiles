#!/usr/bin/env bash
# verify-undo.sh — Phase 5 reversibility test.
#
# Usage: verify-undo.sh <fm_id> [<tool>] [<fixture_dir>]
#
# Asserts: corrupt → <tool> doctor --fix → assert healthy → <tool> doctor
# undo <run-id> → byte-identical to corrupted state.
#
# Exit 0 if pass, 1 if fail.

set -euo pipefail
fm_id="${1:-}"
if [ -z "$fm_id" ]; then
    echo "usage: verify-undo.sh <fm_id> [<tool>] [<fixture_root>]" >&2
    exit 64
fi
tool="${2:-${TOOL:-}}"
if [ -z "$tool" ]; then
    echo "error: provide <tool> as arg 2 or set TOOL env var" >&2
    exit 64
fi
fixture_root="${3:-tests/doctor_fixtures}"

corrupt_sh="$fixture_root/$fm_id/corrupt.sh"
assert_sh="$fixture_root/$fm_id/assert.sh"
[ -x "$corrupt_sh" ] || { echo "FAIL: $corrupt_sh missing" >&2; exit 1; }
[ -x "$assert_sh" ]  || { echo "FAIL: $assert_sh missing" >&2; exit 1; }

sandbox=$(mktemp -d)
trap 'echo "verify-undo: sandbox preserved at $sandbox" >&2' EXIT

"$corrupt_sh" "$sandbox" >&2
[ -d "$sandbox/.fixture_baseline" ] \
    || { echo "FAIL: $corrupt_sh did not write .fixture_baseline" >&2; exit 1; }

# Snapshot the corrupted state for byte comparison after undo.
corrupted_snap=$(mktemp -d)
cp -a "$sandbox/.fixture_baseline/." "$corrupted_snap/"

# Diagnose: must report findings. Capture the diagnose process's exit code
# explicitly. The prior version did `cmd || true` then parsed the JSON for
# `exit_code`, but if the tool CRASHED (no JSON output), the python json.load
# raises and the script aborts under set -e WITHOUT the intended FAIL line —
# the operator sees a JSONDecodeError traceback, not "FAIL: diagnose ...".
diag_rc=0
diag_json=$(cd "$sandbox" && "$tool" doctor --json) || diag_rc=$?
case "$diag_rc" in
    0|1) ;;  # 0=clean, 1=findings — both acceptable on the diagnose path
    *)
        echo "FAIL: <tool> doctor --json exited unexpectedly with $diag_rc (no JSON to parse)" >&2
        echo "$diag_json" >&2
        exit 1
        ;;
esac
# Use python with strict missing-key handling. Prior version used
# `.get("exit_code", "?")` which silently returned "?" on missing field;
# downstream `[ "?" = "1" ]` then failed with the wrong error message.
# `--exit-on-missing` here makes the failure mode obvious.
diag_exit=$(echo "$diag_json" | python3 -c '
import sys, json
try:
    obj = json.loads(sys.stdin.read())
except json.JSONDecodeError as e:
    print(f"PARSE_ERROR:{e}", file=sys.stderr); sys.exit(2)
ec = obj.get("exit_code")
if ec is None:
    print("MISSING_FIELD:exit_code", file=sys.stderr); sys.exit(2)
print(ec)
' 2>&1) || { echo "FAIL: diagnose JSON malformed or missing exit_code: $diag_json" >&2; exit 1; }
[ "$diag_exit" = "1" ] || { echo "FAIL: diagnose exit_code=$diag_exit (expected 1)" >&2; exit 1; }

# Fix.
fix_rc=0
fix_json=$(cd "$sandbox" && "$tool" doctor --fix --json) || fix_rc=$?
case "$fix_rc" in
    0|2) ;;  # 0=all fixed, 2=partial — both legitimate per canonical exit-code table
    *)
        echo "FAIL: --fix exited unexpectedly with $fix_rc (expected 0 or 2)" >&2
        echo "$fix_json" >&2
        exit 1
        ;;
esac
run_id=$(echo "$fix_json" | python3 -c '
import sys, json
try:
    obj = json.loads(sys.stdin.read())
except json.JSONDecodeError as e:
    print(f"PARSE_ERROR:{e}", file=sys.stderr); sys.exit(2)
rid = obj.get("run_id")
if rid is None or rid == "" or rid == "null":
    print("MISSING_FIELD:run_id", file=sys.stderr); sys.exit(2)
print(rid)
' 2>&1) || { echo "FAIL: --fix output missing run_id: $fix_json" >&2; exit 1; }
[ -n "$run_id" ] || { echo "FAIL: no run_id in fix output" >&2; exit 1; }

# Assert healthy.
"$assert_sh" "$sandbox" >&2 || { echo "FAIL: assert.sh failed after --fix" >&2; exit 1; }

# Undo.
( cd "$sandbox" && "$tool" doctor undo "$run_id" --strict ) >&2 \
    || { echo "FAIL: undo exited non-zero" >&2; exit 1; }

# Compare bytes against the corrupted snapshot.
# Doctor's own .doctor/ artifacts are excluded from the comparison.
mkdir -p "$sandbox/.compare_against"
cp -a "$corrupted_snap/." "$sandbox/.compare_against/"

# Capture diff output explicitly. We only excuse "Only in" lines that mention
# the doctor's own bookkeeping paths (.doctor/, .compare_against/,
# .fixture_baseline/) — anything else is a real undo bug that left an
# unexpected file behind, and MUST surface as a failure.
diff_out=$(diff -r --brief \
    --exclude='.doctor' \
    --exclude='.compare_against' \
    --exclude='.fixture_baseline' \
    "$sandbox/.compare_against/" "$sandbox/" 2>&1 \
    | grep -vE '^Only in [^:]+: \.(doctor|compare_against|fixture_baseline)$' \
    || true)

if [ -n "$diff_out" ]; then
    echo "FAIL: undo not byte-identical (see diff below)" >&2
    echo "$diff_out" >&2
    exit 1
fi

echo "PASS: verify-undo.sh fm=$fm_id" >&2
trap - EXIT
